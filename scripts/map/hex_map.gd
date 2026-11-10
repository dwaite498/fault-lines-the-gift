class_name HexMap
extends RefCounted
## Generates a seeded hex map: land, water, nations, and their cities.
## No drawing here; see map_view.gd.
## Cells use "odd-r" offset coordinates: pointy-top hexes, odd rows shifted right.

const WATER := -2
const UNCLAIMED := -1
## How many seeds to try before accepting a city that breaks spacing.
const MAX_MAP_ATTEMPTS := 20

const _EVEN_ROW_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const _ODD_ROW_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1),
]

var width := 0
var height := 0
## Vector2i cell -> WATER, UNCLAIMED (neutral land), or the owning nation index.
## Ownership comes from cities; see update_ownership().
var cells: Dictionary = {}
## Generated nation areas (same keys and values as cells). Cities are placed inside these.
var territory: Dictionary = {}
## Each city is {"id", "nation", "cell": Vector2i, "population" (people), "pool" (recruitable
## people, part of population), "infrastructure", "radius"}, kept in ascending id order.
## radius is that city's claim radius. "besieged" is set each end turn (see update_sieges).
## A recently captured city also has "rebuild_target" and "rebuild_turns_left". Capture
## flags (CAPTURE.md): "capture_pending" until the captor picks a choice, "occupied" with
## "occupy_turns_left" (annexable at 0), "enslaved", and "recruit_lockout" (turns left).
var cities: Array[Dictionary] = []
## Nations that still have at least one city.
var nations: Array[int] = []
## Growth rules from cities_config.json. Set before generate() so new cities use them.
var city_rules := {
	"claim_radius": 1,
	"tiers": [{"key": "outpost", "min_pop": 0, "sprite_scale": 0.6}, {"key": "base", "min_pop": 5000, "sprite_scale": 0.8},
			{"key": "city", "min_pop": 15000, "claim_radius": 2, "sprite_scale": 1.0},
			{"key": "metropolis", "min_pop": 30000, "claim_radius": 2, "sprite_scale": 1.2}],
	"colony_start_population": 3000, "capital_start_population": 10000, "start_infrastructure": 10,
	"housing_per_infra": 3000, "people_per_labor_point": 2000,
	"base_growth": 0.005, "growth_labor_max_bonus": 0.01, "min_growth": 0.001,
	"terrain_growth_mult": {"plains": 1.0, "coast": 1.1, "forest": 0.9, "hills": 0.9,
			"mountains": 0.7, "shallow_ocean": 1.0},
	"fungus_adjacent_growth_mult": 0.95, "fungus_growth_min_mult": 0.7,
	"division_people_cost": 1000, "pool_fill_rate": 0.005,
	"pool_cap": 0.15, "capital_start_pool": 1000, "colony_start_pool": 0,
	"train_min_city_pop": 5000,
	"siege_growth": 0.0, "siege_pop_loss": 0.02, "siege_labor_mult": 0.5,
	"display_round": 100,
	"rebuild_turns": 26,
	"colonization": {
		"labor_turns": 15, "population_cost": 3000, "min_remaining_population": 5000,
		"outpost_population": 3000, "outpost_infrastructure": 10, "min_city_distance": 3,
		"ai_build_pods": true, "ai_max_pods": 1,
	},
	"capture": {
		"order": ["annex", "occupy", "plunder", "reduce", "raze", "enslave"],
		"annexed_recruit_lockout_turns": 10, "ai_default_option": "annex",
		"aggressive_factions": ["directorate", "collective", "free_tide", "drift"], "aggressive_harsh_chance": 0.5,
		"default_views_as_atrocity": ["raze"], "atrocity_weight": 3.0,
		"harshness_order": ["annex", "occupy", "plunder", "reduce", "enslave", "raze"],
		"faction_options": {
			"assembly": ["annex", "occupy"],
			"directorate": ["annex", "occupy", "reduce", "raze"],
			"syndicate": ["annex", "occupy", "plunder"],
			"verdant_accord": ["annex", "occupy", "reduce"],
			"covenant": ["annex", "occupy", "reduce"],
			"collective": ["annex", "occupy", "enslave", "raze"],
			"lyceum": ["annex", "occupy"],
			"free_tide": ["annex", "occupy", "plunder", "enslave"],
			"deepwater_guild": ["annex", "occupy", "plunder", "enslave"],
			"drift": ["annex", "plunder", "raze"],
		},
		"options": {
			"annex": {"pop_loss": 0.25, "infra_loss": 0.3, "severity": 0, "atrocity": false},
			"occupy": {"pop_loss": 0.1, "infra_loss": 0.0, "severity": 0, "atrocity": false,
					"turns": 5, "labor_mult": 0.5},
			"plunder": {"pop_loss": 0.15, "infra_loss": 0.5, "severity": 1, "atrocity": false,
					"cash_per_1000_people": 5},
			"reduce": {"pop_loss": 0.5, "infra_loss": 0.5, "severity": 2, "atrocity": false},
			"raze": {"refugee_share": 0.5, "severity": 3, "atrocity": true},
			"enslave": {"pop_loss": 0.1, "infra_loss": 0.0, "severity": 3, "atrocity": false,
					"labor_mult": 1.5},
		},
	},
}
## Nation index -> faction id (from factions.json), set by main. Capture gating and the
## AI's choice read it; a nation with no entry is ungated and the AI uses ai_default_option.
var nation_factions := {}
## Faction id -> its views_as_atrocity list and atrocity_sensitivity (from factions.json),
## see load_faction_views. Atrocity is judged per observing faction.
var faction_views := {}
var faction_sensitivity := {}
## Every capture choice logs a reputation_event here (a stub; nothing reads it yet).
var reputation := ReputationLog.new()
## The result of the latest apply_capture, see apply_capture.
var last_capture := {}
## Additive growth-rate modifier per nation (a trait hook for Task 41; empty today).
## Added to base_growth before the terrain multiplier, e.g. -0.003 for a penalized faction.
var growth_mods: Dictionary = {}
## Faction trait modifiers (factions.json faction_traits), filled by load_faction_traits.
var traits := FactionTraits.new()
## Affinity axes, rivals and attitude (Task 42); empty until load_attitude.
var attitude := Attitude.new()
## The game's current turn (main.gd keeps it); the plunder cooldown reads it.
var current_turn := 0
## nation -> turn it last plundered a city (used when plunder_cooldown_scope is "nation").
var plunder_last_turn: Dictionary = {}
## Tier changes made by the last grow_cities: {"city_id", "nation", "from", "to", "grew"} (for the turn log).
var tier_changes: Array[Dictionary] = []
## Faction id -> {"style": base_style, "sea": bool} for city sprite keys (load_faction_views).
var faction_art := {}
## Vector2i cell -> true for fungus tiles (hook; the map has no fungus yet). A terrain
## named "fungus" also counts.
var fungus_tiles: Dictionary = {}
## data/natives.json (spawner, fungus attrition, raids); empty disables them. See load_natives_config.
var natives_config := {}
## Nations whose first cities should sit on the coast (sea factions until the naval
## slice). Set before generate(). A hex counts as coastal if it touches water; if a
## nation has no such hex, a map-edge hex is next best.
var coastal_nations: Array[int] = []
## The seed passed to generate(); other systems derive their RNG from it.
var seed_value := 0
## Vector2i cell -> terrain name ("plains", "forest", ...). See generate_terrain().
var terrain: Dictionary = {}
## Vector2i cell -> elevation int (-3..4), from terrain_config.json's "elevation" table.
## Water touching land is "shallows"; other water uses the table's water value.
## Read by the movement and combat rules (can_step, step_cost, uphill attack; Task 34).
var elevation: Dictionary = {}
## The "elevation" block of terrain_config.json: climb_cost, cliff_diff, smooth_max_step,
## ridge_terrain. Without it there are no elevation rules (no climb cost, no cliffs).
var elevation_rules: Dictionary = {}
## Tagged ridge edges (edge_key) left as cliffs between a mountain and lower land.
var ridge_edges: Dictionary = {}
## Terrain name -> {color, move_cost, defense_mult, passable} from terrain_config.json.
var terrain_types: Dictionary = {}


## Builds a map from the map config (width, height, seed, land_ratio, nation_count)
## and the cities config (cities_per_nation, claim_radius, min_spacing).
static func from_config_file(map_path: String,
		cities_path := "res://data/cities_config.json",
		terrain_path := "res://data/terrain_config.json",
		coastal: Array[int] = [], map_override := {}) -> HexMap:
	var map_cfg: Dictionary = map_override if not map_override.is_empty() \
			else JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var city_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cities_path))
	var hex_map := HexMap.new()
	hex_map.coastal_nations = coastal
	for key in hex_map.city_rules:
		if city_cfg.has(key):
			hex_map.city_rules[key] = city_cfg[key]
	hex_map.generate(int(map_cfg.width), int(map_cfg.height), int(map_cfg.seed),
			float(map_cfg.land_ratio), int(map_cfg.nation_count),
			int(city_cfg.cities_per_nation), int(city_cfg.min_spacing))
	hex_map.generate_terrain(JSON.parse_string(FileAccess.get_file_as_string(terrain_path)))
	return hex_map


## Picks a terrain for every land hex by weight; water hexes get "water" and
## city hexes are always plains. Uses its own RNG derived from seed_value, so
## land, nations, and cities don't change.
func generate_terrain(config: Dictionary) -> void:
	terrain_types = config.types
	var weights: Dictionary = config.land_weights
	var total := 0.0
	for kind in weights:
		total += float(weights[kind])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 1
	terrain.clear()
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if cells[cell] == WATER:
				terrain[cell] = "water"
				continue
			var roll := rng.randf() * total
			for kind in weights:
				roll -= float(weights[kind])
				if roll < 0.0:
					terrain[cell] = kind
					break
			if not terrain.has(cell):
				terrain[cell] = weights.keys().back()
	for city in cities:
		terrain[city.cell] = "plains"
	_assign_elevation(config.get("elevation", {}))


func _assign_elevation(cfg: Dictionary) -> void:
	elevation_rules = cfg
	elevation.clear()
	var by_terrain: Dictionary = cfg.get("by_terrain", {})
	var lo := int(cfg.get("min", -3))
	var hi := int(cfg.get("max", 4))
	for cell in terrain:
		var e := int(by_terrain.get(terrain[cell], 0))
		if terrain[cell] == "water" and neighbors(cell).any(func(n: Vector2i) -> bool: return cells[n] != WATER):
			e = int(cfg.get("shallows", e))
		elevation[cell] = clampi(e, lo, hi)
	_smooth_elevation()
	ensure_reachable()


## True if terrain is passable for a step from `from` to its neighbor `to`: the target
## terrain is passable and the elevation difference is below cliff_diff (a cliff).
func can_step(from: Vector2i, to: Vector2i) -> bool:
	if not terrain_of(to).passable:
		return false
	return absi(elevation_of(to) - elevation_of(from)) < int(elevation_rules.get("cliff_diff", 1 << 20))


## Move points to step from `from` into `to`: the target's move_cost, plus climb_cost
## when it is one or more levels higher. Downhill and level steps cost the normal amount.
func step_cost(from: Vector2i, to: Vector2i, nation := -1) -> int:
	var cost := int(terrain_of(to).move_cost) + fungus_extra_cost(to, nation)
	if elevation_of(to) > elevation_of(from):
		var free: Array = traits.mod(nation, "no_uphill_penalty_terrain", []) if nation >= 0 else []
		if not free.has(terrain_name(to)):
			cost += int(elevation_rules.get("climb_cost", 0))
	return cost


func _is_ridge(cell: Vector2i) -> bool:
	return elevation_rules.get("ridge_terrain", []).has(terrain_name(cell))


## Cell pair -> key for ridge_edges (order-independent).
static func edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	var lo := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var hi := b if lo == a else a
	return Vector4i(lo.x, lo.y, hi.x, hi.y)


## True if the edge between a and b is a tagged ridge: a deliberate cliff left between
## a mountain and lower land (see _smooth_elevation).
func is_ridge_edge(a: Vector2i, b: Vector2i) -> bool:
	return ridge_edges.has(edge_key(a, b))


## Deterministic pick (seed plus the two cells, integer hash, no RNG) of whether the
## mountain-to-lowland edge a-b is a ridge. The chance is ridge_edge_chance (0..1).
func _picks_ridge(a: Vector2i, b: Vector2i) -> bool:
	var k := edge_key(a, b)
	var h := (k.x * 73856093) ^ (k.y * 19349663) ^ (k.z * 83492791) ^ (k.w * 2654435761) ^ (seed_value * 374761393)
	h = (h ^ (h >> 13)) & 0x7fffffff
	return float(h % 1000) < float(elevation_rules.get("ridge_edge_chance", 0.0)) * 1000.0


## Makes land neighbors differ by at most smooth_max_step, everywhere except on tagged
## ridge edges. Between two non-mountain hexes the higher one is lowered. Next to a
## mountain (ridge_terrain) the lower hex is raised to a foothill, one step under the
## mountain: its terrain becomes foothill_terrain (hills) unless it is a city hex (those
## only get the elevation), except that a deterministic ~ridge_edge_chance of the
## mountain-to-lowland edges stay as cliffs and are tagged in ridge_edges. Deterministic.
func _smooth_elevation() -> void:
	ridge_edges.clear()
	var max_step := int(elevation_rules.get("smooth_max_step", 1 << 20))
	var foothill := str(elevation_rules.get("foothill_terrain", ""))
	var city_cells := {}
	for city in cities:
		city_cells[city.cell] = true
	var keys: Array = terrain.keys()
	keys.sort()
	for pass_index in keys.size():
		var changed := false
		for cell in keys:
			if not terrain_of(cell).passable:
				continue
			for n in neighbors(cell):
				if not terrain_of(n).passable or elevation[cell] <= elevation[n] + max_step:
					continue
				# cell is more than max_step above n.
				if _is_ridge(cell) or _is_ridge(n):
					if ridge_edges.has(edge_key(cell, n)):
						continue
					if _picks_ridge(cell, n):
						ridge_edges[edge_key(cell, n)] = true
						continue
					elevation[n] = elevation[cell] - max_step
					if foothill != "" and not _is_ridge(n) and not city_cells.has(n) and terrain_types.has(foothill):
						terrain[n] = foothill
				else:
					elevation[cell] = elevation[n] + max_step
				changed = true
		if not changed:
			break
	_prune_ridges()


## Hexes reachable from start by can_step (ignoring units).
func reachable_from(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		for n in neighbors(queue[i]):
			if not seen.has(n) and can_step(queue[i], n):
				seen[n] = true
				queue.append(n)
		i += 1
	return seen


## Makes every land hex connected (by land, ignoring cliffs) to a start reachable from
## that start's first city: while some are not, lowers one cliff edge to a one-step
## pass. Land with no city on it (islands) is left alone. Deterministic; returns the
## number of passes made. Called when elevation is assigned.
func ensure_reachable() -> int:
	var passes := 0
	var done := {}
	for city in cities:
		if done.has(city.cell):
			continue
		var comp := {}
		for c in land_component(city.cell):
			comp[c] = true
			done[c] = true
		var guard := 0
		while guard < comp.size() * 8:
			guard += 1
			var reach := reachable_from(city.cell)
			var keys: Array = reach.keys()
			keys.sort()
			var fixed := false
			for a in keys:
				var ns := neighbors(a)
				ns.sort()
				for b in ns:
					if comp.has(b) and not reach.has(b):
						# b is passable land that a cannot step to: a cliff between them.
						_cut_pass(a, b)
						passes += 1
						fixed = true
						break
				if fixed:
					break
			if not fixed:
				break
	return passes


## Opens the cliff between a and b into a one-step pass. A mountain (ridge terrain) is
## never lowered: when the high side is a mountain, the low side is raised to the
## mountain's elevation - smooth_max_step instead (it becomes a foothill, like the
## foothill pass in _smooth_elevation: hills terrain, except city hexes). Otherwise
## the high side is lowered to low + cliff_diff - 1. Tagged ridge edges that stop being
## cliffs are then dropped, so every ridge_edges entry stays a real cliff.
func _cut_pass(a: Vector2i, b: Vector2i) -> void:
	var cliff := int(elevation_rules.get("cliff_diff", 1 << 20))
	var hi_cell: Vector2i = a if elevation[a] > elevation[b] else b
	var lo_cell: Vector2i = b if hi_cell == a else a
	if _is_ridge(hi_cell) and not _is_ridge(lo_cell):
		elevation[lo_cell] = elevation[hi_cell] - int(elevation_rules.get("smooth_max_step", 1))
		var foothill := str(elevation_rules.get("foothill_terrain", ""))
		var is_city := cities.any(func(c: Dictionary) -> bool: return c.cell == lo_cell)
		if foothill != "" and not is_city and terrain_types.has(foothill):
			terrain[lo_cell] = foothill
	else:
		elevation[hi_cell] = maxi(elevation[lo_cell] + cliff - 1, int(elevation_rules.get("min", -3)))
	_prune_ridges()


## Drops tagged ridge edges whose two hexes no longer differ by cliff_diff or more.
func _prune_ridges() -> void:
	var cliff := int(elevation_rules.get("cliff_diff", 1 << 20))
	for key in ridge_edges.keys():
		var a := Vector2i(key.x, key.y)
		var b := Vector2i(key.z, key.w)
		if absi(elevation_of(a) - elevation_of(b)) < cliff:
			ridge_edges.erase(key)


## Elevation of cell; 0 before generate_terrain() has run.
func elevation_of(cell: Vector2i) -> int:
	return int(elevation.get(cell, 0))


## Fallback terrain when generate_terrain() hasn't run or a name is unknown.
const _DEFAULT_TERRAIN := {
	"plains": {"color": "#a8c070", "move_cost": 1, "defense_mult": 1.0, "passable": true},
	"water": {"color": "#29528c", "move_cost": 1, "defense_mult": 1.0, "passable": false},
}


## Terrain name for cell. Without generated terrain: "water" on water hexes, else "plains".
func terrain_name(cell: Vector2i) -> String:
	if terrain.has(cell):
		return terrain[cell]
	return "water" if cells.get(cell, WATER) == WATER else "plains"


## Terrain stats for cell; safe before generate_terrain() (uses built-in plains/water).
func terrain_of(cell: Vector2i) -> Dictionary:
	var kind := terrain_name(cell)
	if terrain_types.has(kind):
		return terrain_types[kind]
	if _DEFAULT_TERRAIN.has(kind):
		return _DEFAULT_TERRAIN[kind]
	return _DEFAULT_TERRAIN.plains


func generate(map_width: int, map_height: int, map_seed: int,
		land_ratio: float, nation_count: int, cities_per_nation := 2,
		min_spacing := 3) -> void:
	width = map_width
	height = map_height
	seed_value = map_seed
	# If some nation can't fit a spaced city, retry with a derived seed.
	# The last attempt accepts a city that breaks spacing.
	for attempt in MAX_MAP_ATTEMPTS:
		var attempt_seed := map_seed if attempt == 0 else map_seed * 31 + attempt
		cells.clear()
		cities.clear()
		nations.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = attempt_seed
		_make_land(attempt_seed, land_ratio)
		_make_nations(rng, nation_count)
		territory = cells.duplicate()
		var last_try := attempt == MAX_MAP_ATTEMPTS - 1
		if _place_cities(rng, maxi(cities_per_nation, 1), min_spacing, last_try):
			break
	for city in cities:
		if not nations.has(city.nation):
			nations.append(city.nation)
	update_ownership()


## Distance in hex steps between two cells.
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac := _to_cube(a)
	var bc := _to_cube(b)
	return maxi(maxi(absi(ac.x - bc.x), absi(ac.y - bc.y)), absi(ac.z - bc.z))


## The cells on the straight line from a to b, both ends included (cube lerp and round, with
## a tiny fixed nudge so ties always break the same way).
static func hex_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := hex_distance(a, b)
	var ac := _to_cube(a)
	var bc := _to_cube(b)
	for i in n + 1:
		var t := float(i) / float(maxi(n, 1))
		var fx := lerpf(ac.x, bc.x, t) + 1e-6
		var fy := lerpf(ac.y, bc.y, t) + 2e-6
		var fz := lerpf(ac.z, bc.z, t) - 3e-6
		var rx := roundi(fx)
		var ry := roundi(fy)
		var rz := roundi(fz)
		var dx := absf(rx - fx)
		var dy := absf(ry - fy)
		var dz := absf(rz - fz)
		if dx > dy and dx > dz:
			rx = -ry - rz
		elif dy > dz:
			ry = -rx - rz
		else:
			rz = -rx - ry
		out.append(Vector2i(rx + int((rz - (rz & 1)) / 2.0), rz))
	return out


static func _to_cube(cell: Vector2i) -> Vector3i:
	var x := cell.x - int((cell.y - (cell.y & 1)) / 2.0)
	return Vector3i(x, -x - cell.y, cell.y)


## Each land tile goes to the nation of the closest city whose own radius
## reaches it. Ties go to the lowest city id. Unclaimed land is neutral.
## A city that has dropped below City tier keeps the ring-2 tiles it held (`kept_ring2`,
## recorded while its claim radius is 2) but claims no new ones.
func update_ownership() -> void:
	var winners := {}
	for cell in territory:
		if territory[cell] == WATER:
			cells[cell] = WATER
			continue
		var owner := UNCLAIMED
		var best_dist := 1 << 30
		var winner := -1
		for city in cities:
			var dist := hex_distance(cell, city.cell)
			var claims: bool = dist <= int(city.radius) \
					or (dist == 2 and city.get("kept_ring2", []).has(cell))
			if claims and dist < best_dist:
				best_dist = dist
				owner = city.nation
				winner = int(city.id)
		cells[cell] = owner
		winners[cell] = winner
	for city in cities:
		if int(city.radius) >= 2:
			var held: Array[Vector2i] = []
			for cell in winners:
				if winners[cell] == int(city.id) and hex_distance(cell, city.cell) == 2:
					held.append(cell)
			held.sort()
			city.kept_ring2 = held


## Advances every city one turn (see _advance_people: siege loss, growth, pool fill),
## steps capture rebuilds, and sets each radius from its population. Sieges are
## updated first from unit_cells. Tiers are recalculated after growth and losses (a change
## is recorded in tier_changes). Reruns ownership if a radius changed. Returns true if
## ownership was rerun. Called once per end turn.
func grow_cities(unit_cells := {}) -> bool:
	update_sieges(unit_cells)
	tier_changes.clear()
	var changed := false
	for city in cities:
		_advance_people(city)
		_rebuild_step(city)
		_tick_capture_timers(city)
		_note_tier(city)
		var radius := _radius_for(int(city.population))
		if radius != int(city.radius):
			city.radius = radius
			changed = true
	if changed:
		update_ownership()
	return changed


## Housing cap in people: infrastructure x housing_per_infra, rounded down.
## Loads data/natives.json (NativeSpawner.load_config()).
func load_natives_config(cfg: Dictionary) -> void:
	natives_config = cfg


## Fungus attrition scale for a nation: 1 for most, a faction's fungus_attrition_mult trait (Verdant
## 0.5), 0 for natives (they are exempt), and 0 if fungus_attrition is not configured.
func fungus_scale(nation: int) -> float:
	var rules: Dictionary = natives_config.get("fungus_attrition", {})
	if rules.is_empty() or (nation == int(natives_config.get("native_nation", -2)) and rules.get("exempt_natives", true)):
		return 0.0
	return float(traits.mod(nation, "fungus_attrition_mult", 1.0))


## Extra move cost for entering a fungus tile (fungus_attrition.move_cost x the nation's scale, rounded down).
func fungus_extra_cost(cell: Vector2i, nation: int) -> int:
	if not fungus_tiles.has(cell):
		return 0
	return int(floor(float(natives_config.get("fungus_attrition", {}).get("move_cost", 0)) * fungus_scale(nation)))


## True for a fungus tile.
func is_fungus(cell: Vector2i) -> bool:
	return fungus_tiles.has(cell) or terrain_name(cell) == "fungus"


## Places `fungus.patches` patches of fungus (seeded by `rng`) at least `fungus.min_city_distance`
## from every city: density max_density at the centre, one less per ring, minimum 1. There is no
## fungus growth or spread yet. Returns the number of tiles placed.
func place_fungus(rng: RandomNumberGenerator) -> int:
	var rules: Dictionary = natives_config.get("fungus", {})
	if rules.is_empty():
		return 0
	var land: Array[Vector2i] = []
	for cell in cells:
		if cells[cell] != WATER and terrain_name(cell) != "water" and city_at(cell).is_empty():
			land.append(cell)
	land.sort()
	var placed := 0
	for i in int(rules.patches):
		var options := land.filter(func(c: Vector2i) -> bool: return not _city_near(c, int(rules.min_city_distance) - 1))
		if options.is_empty():
			break
		var centre: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		for cell in land:
			var ring := hex_distance(cell, centre)
			if ring <= int(rules.patch_radius) and not _city_near(cell, int(rules.min_city_distance) - 1):
				var density := maxi(int(rules.max_density) - ring, 1)
				if density > int(fungus_tiles.get(cell, 0)):
					if not fungus_tiles.has(cell):
						placed += 1
					fungus_tiles[cell] = density
	return placed


func _city_near(cell: Vector2i, radius: int) -> bool:
	for c in cities:
		if hex_distance(cell, c.cell) <= radius:
			return true
	return false


## Faction traits: a sea city of a faction with sea_housing_per_infra uses that per infra,
## housing_flat_per_city adds to each of the first flat_bonus_city_cap cities, and
## housing_mult scales the total.
func housing_cap(city: Dictionary) -> int:
	var nation := int(city.get("nation", -1))
	var per_infra := float(city_rules.housing_per_infra)
	if traits.has_trait(nation, "sea_housing_per_infra") and traits.is_sea_city(self, city):
		per_infra = float(traits.mod(nation, "sea_housing_per_infra"))
	var total := float(city.infrastructure) * per_infra
	if traits.has_trait(nation, "housing_flat_per_city") and traits.within_city_cap(self, city):
		total += float(traits.mod(nation, "housing_flat_per_city"))
	return int(floor(total * float(traits.mod(nation, "housing_mult", 1.0))))


## Labor points of a city: population / people_per_labor_point rounded down, times
## siege_labor_mult while besieged, the Occupy labor_mult while occupied and the Enslave
## labor_mult while enslaved.
static func labor_points_for(city: Dictionary, rules: Dictionary, occupy_mult := -1.0) -> int:
	var points := float(city.population) / float(rules.people_per_labor_point)
	if city.get("besieged", false):
		points *= float(rules.siege_labor_mult)
	if city.get("occupied", false):
		points *= occupy_mult if occupy_mult >= 0.0 else float(rules.capture.options.occupy.labor_mult)
	if city.get("enslaved", false):
		points *= float(rules.capture.options.enslave.labor_mult)
	return int(floor(points))


## Faction traits: occupy_labor_mult replaces the Occupy labor_mult for the occupier,
## labor_per_city adds points to each of the first flat_bonus_city_cap cities and
## labor_per_sea_city to each of the first sea cities.
func labor_points(city: Dictionary) -> int:
	var nation := int(city.get("nation", -1))
	var occupy := float(traits.mod(nation, "occupy_labor_mult", -1.0))
	var points := labor_points_for(city, city_rules, occupy)
	if traits.has_trait(nation, "labor_per_city") and traits.within_city_cap(self, city):
		points += int(traits.mod(nation, "labor_per_city"))
	if traits.has_trait(nation, "labor_per_sea_city") and traits.within_sea_city_cap(self, city):
		points += int(traits.mod(nation, "labor_per_sea_city"))
	return points


## Key into terrain_growth_mult for the city's own tile: "coast" for plains that touch
## water, "shallow_ocean" for a city on water, otherwise the terrain name.
func growth_terrain_key(city: Dictionary) -> String:
	if not city.has("cell"):
		return "plains"
	var kind := terrain_name(city.cell)
	if kind == "water":
		return "shallow_ocean"
	if kind == "plains":
		for n in neighbors(city.cell):
			if cells.get(n, WATER) == WATER:
				return "coast"
	return kind


## Fungus tiles touching the city (fungus_tiles hook or a "fungus" terrain).
func fungus_adjacent(city: Dictionary) -> int:
	var count := 0
	if not city.has("cell"):
		return 0
	for n in neighbors(city.cell):
		if fungus_tiles.has(n) or terrain_name(n) == "fungus":
			count += 1
	return count


## Food multiplier: terrain_growth_mult for the city's tile times
## fungus_adjacent_growth_mult per adjacent fungus tile (never below fungus_growth_min_mult).
func terrain_growth_mult(city: Dictionary) -> float:
	var mult := float(city_rules.terrain_growth_mult.get(growth_terrain_key(city), 1.0))
	var fungus := pow(float(city_rules.fungus_adjacent_growth_mult), fungus_adjacent(city))
	return mult * maxf(fungus, float(city_rules.fungus_growth_min_mult))


## Growth rate per turn: (base_growth + nation mod + growth_labor_max_bonus x the share of
## labor on Growth) x terrain_growth_mult, never below min_growth. A besieged city has
## siege_growth (0). share_override (0..1) replaces the city's actual Growth share.
func growth_rate(city: Dictionary, share_override := -1.0) -> float:
	if city.get("besieged", false):
		return float(city_rules.siege_growth)
	if city.get("enslaved", false):
		return 0.0  # an enslaved city never grows (CAPTURE.md)
	var share := share_override
	if share < 0.0:
		var total := labor_points(city)
		share = float(int(city.get("labor", {}).get("growth", 0))) / float(total) if total > 0 else 0.0
	var base := float(city_rules.base_growth) + float(growth_mods.get(int(city.nation), 0.0))
	if int(city.population) < int(traits.global_value("growth_bonus_pop_ceiling", 0)):
		base += float(traits.mod(int(city.nation), "growth_bonus_small_city", 0.0))
	var rate := (base + float(city_rules.growth_labor_max_bonus) * clampf(share, 0.0, 1.0)) \
			* terrain_growth_mult(city)
	return maxf(rate, float(city_rules.min_growth))


## People gained next turn (rounded down): population x growth_rate, never past housing,
## and 0 for a city already at or over housing (it does not shrink).
func growth_amount(city: Dictionary, share_override := -1.0) -> int:
	var pop := int(city.population)
	var room := maxi(housing_cap(city) - pop, 0)
	return mini(int(floor(pop * growth_rate(city, share_override))), room)


## The city's population after one turn of growth.
func grown_population(city: Dictionary) -> int:
	return int(city.population) + growth_amount(city)


## People rounded for display (nearest display_round, 100 by default).
func display_people(people: int) -> int:
	var step := maxi(int(city_rules.display_round), 1)
	return int(round(float(people) / step)) * step


# --- Recruitable pool ---

## The pool never holds more than pool_cap of the population (rounded down).
## Faction traits: recruit_cap_pop_share adds to the cap rate, then recruit_cap_mult scales it.
func pool_cap(city: Dictionary) -> int:
	var nation := int(city.get("nation", -1))
	var rate := (float(city_rules.pool_cap) + float(traits.mod(nation, "recruit_cap_pop_share", 0.0))) \
			* float(traits.mod(nation, "recruit_cap_mult", 1.0))
	return int(floor(float(city.population) * rate))


## People added to the pool each turn: pool_fill_rate of the population, rounded down.
## Faction traits: pool_fill_mult scales the fill.
func pool_fill(city: Dictionary) -> int:
	var mult := float(traits.mod(int(city.get("nation", -1)), "pool_fill_mult", 1.0))
	return int(floor(float(city.population) * float(city_rules.pool_fill_rate) * mult))


## Recruitable people now (cities built by hand may have no "pool" key).
func pool_of(city: Dictionary) -> int:
	return int(city.get("pool", 0))


## The lowest-id city of a nation (no capital flag exists yet), or {} if none.
func capital_of(nation: int) -> Dictionary:
	for city in cities:
		if city.nation == nation:
			return city
	return {}


func city_by_id(city_id: int) -> Dictionary:
	for city in cities:
		if city.id == city_id:
			return city
	return {}


## The city of `nation` closest to `from`; ties go to the capital, then the lowest id.
## {} if the nation has no city.
func nearest_owned_city(nation: int, from: Vector2i) -> Dictionary:
	var best := {}
	var best_dist := 1 << 30
	for city in cities:
		if city.nation != nation:
			continue
		var dist := hex_distance(from, city.cell)
		if dist < best_dist:
			best = city
			best_dist = dist
	return best


## Cities of `nation` ordered by distance from `from` (ties: lowest id, so the capital first).
func owned_cities_by_distance(nation: int, from: Vector2i) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for city in cities:
		if city.nation == nation:
			list.append(city)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := hex_distance(from, a.cell)
		var db := hex_distance(from, b.cell)
		return da < db or (da == db and a.id < b.id))
	return list


## Adds `people` to a nation's city population (not its pool): the home city if it is
## still the nation's, else the nearest owned city to `from` (capital on ties). Returns the
## city id that received them, or -1 if the nation has no city (the people are lost).
func return_people(nation: int, home_city_id: int, from: Vector2i, people: int) -> int:
	if people <= 0:
		return -1
	var city := city_by_id(home_city_id)
	if city.is_empty() or city.nation != nation:
		var anchor: Vector2i = city.cell if not city.is_empty() else from
		city = nearest_owned_city(nation, anchor)
	if city.is_empty():
		return -1
	city.population = int(city.population) + people
	return int(city.id)


## Removes `people` from a city's pool and population (a division drawn from it).
func draw_people(city: Dictionary, people: int) -> void:
	people = mini(people, pool_of(city))
	city.pool = pool_of(city) - people
	city.population = maxi(int(city.population) - people, 0)


# --- Siege ---

## True if the city has land neighbors and every one is enemy-held: an enemy division
## stands there, or (with no friendly division) an enemy nation owns it. unit_cells maps
## cell -> nation of the division on it (see DivisionRoster.unit_cells).
## Supply cut-off (POPULATION.md's other siege trigger) is not modelled: supply is
## per division, not per city.
func is_besieged(city: Dictionary, unit_cells := {}) -> bool:
	var land := 0
	for n in neighbors(city.cell):
		if cells.get(n, WATER) == WATER:
			continue
		land += 1
		var unit: int = unit_cells.get(n, -1)
		var enemy: bool
		if unit >= 0:
			enemy = unit != city.nation
		else:
			var owner: int = cells.get(n, UNCLAIMED)
			enemy = owner >= 0 and owner != city.nation
		if not enemy:
			return false
	return land > 0


## Sets city.besieged on every city.
func update_sieges(unit_cells := {}) -> void:
	for city in cities:
		city.besieged = is_besieged(city, unit_cells)


## One end turn of a city's people: a besieged city loses siege_pop_loss of its people,
## then growth, then the pool fills by pool_fill_rate and is trimmed to pool_cap.
## Mutates `city`; advance_preview runs it on a copy.
func _advance_people(city: Dictionary) -> void:
	if city.get("besieged", false):
		var pop := int(city.population)
		city.population = pop - int(floor(pop * float(city_rules.siege_pop_loss)))
	city.population = grown_population(city)
	# An enslaved or occupied city's pool stays 0 (POPULATION, Pillars and CAPTURE rules).
	city.pool = 0 if city.get("enslaved", false) or city.get("occupied", false) else clampi(pool_of(city) + pool_fill(city), 0, pool_cap(city))


## A copy of the city as it will stand after this end turn's growth and pool fill.
func advance_preview(city: Dictionary) -> Dictionary:
	var c := city.duplicate()
	_advance_people(c)
	return c


## Regains (target - current) / turns_left infra. Lands exactly on the target
## on the last turn, then clears the rebuild keys.
func _rebuild_step(city: Dictionary) -> void:
	if not city.has("rebuild_turns_left"):
		return
	var left := int(city.rebuild_turns_left)
	var target := float(city.rebuild_target)
	# Infrastructure labor may already have repaired it (or built past the target).
	if left <= 1 or float(city.infrastructure) >= target:
		city.infrastructure = maxf(float(city.infrastructure), target)
		city.erase("rebuild_turns_left")
		city.erase("rebuild_target")
		return
	city.infrastructure = float(city.infrastructure) + (target - float(city.infrastructure)) / left
	city.rebuild_turns_left = left - 1


## The tier entry (city_rules.tiers) for a population: the highest min_pop at or below it.
func tier_for_population(population: int) -> Dictionary:
	var best: Dictionary = city_rules.tiers[0]
	for t in city_rules.tiers:
		if population >= int(t.min_pop) and int(t.min_pop) >= int(best.min_pop):
			best = t
	return best


## Tier key of a city: "outpost", "base", "city" or "metropolis".
func tier(city: Dictionary) -> String:
	return str(tier_for_population(int(city.population)).key)


## Claim radius from the tier, default city_rules.claim_radius.
func _radius_for(population: int) -> int:
	return int(tier_for_population(population).get("claim_radius", city_rules.claim_radius))


## Population at the next tier above the city's, or -1 at the top tier.
func next_tier_population(city: Dictionary) -> int:
	var next := -1
	for t in city_rules.tiers:
		if int(t.min_pop) > int(city.population) and (next < 0 or int(t.min_pop) < next):
			next = int(t.min_pop)
	return next


## Records a tier change in tier_changes (the first call for a city only stores its tier).
func _note_tier(city: Dictionary) -> void:
	var now := tier(city)
	var before := str(city.get("last_tier", ""))
	if before != "" and before != now:
		tier_changes.append({"city_id": int(city.id), "nation": int(city.nation), "from": before, "to": now,
				"grew": int(tier_for_population(int(city.population)).min_pop) > _tier_min(before)})
	city.last_tier = now


func _tier_min(key: String) -> int:
	for t in city_rules.tiers:
		if str(t.key) == key:
			return int(t.min_pop)
	return 0


## Label for a city: "City 3 (City)" (cities have no names yet).
func city_label(city: Dictionary) -> String:
	return "%s (%s)" % [str(city.get("name", "City %d" % int(city.id))), str(tier(city)).capitalize()]


## Turn-log text for a tier change, e.g. "City 3 grew to a City".
func tier_change_text(change: Dictionary) -> String:
	var city := city_by_id(int(change.city_id))
	var name := str(city.get("name", "City %d" % int(change.city_id)))
	var to := str(change.to).capitalize()
	return "%s %s to %s %s" % [name, "grew" if change.grew else "shrank",
			"an" if to[0] in "AEIOU" else "a", to]


# --- Colonization (Task 40e) ---

## Why a colony pod of `nation` cannot found a city on `cell`, or "" if it can: the hex must
## be land the nation can settle (its own territory or unclaimed, not another nation's) and at
## least colonization.min_city_distance hexes from every city.
func found_block_reason(cell: Vector2i, nation: int) -> String:
	if not cells.has(cell) or int(territory.get(cell, WATER)) == WATER or not terrain_of(cell).passable:
		return "not land"
	var owner := int(cells.get(cell, UNCLAIMED))
	if owner != UNCLAIMED and owner != nation:
		return "foreign territory"
	var min_dist := int(city_rules.colonization.min_city_distance)
	for c in cities:
		if hex_distance(c.cell, cell) < min_dist:
			return "too close to a city"
	return ""


## Every cell where `nation` could found a city (see found_block_reason), sorted.
func colony_sites(nation: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in cells:
		if found_block_reason(cell, nation) == "":
			out.append(cell)
	out.sort()
	return out


## Founds an Outpost for `nation` on `cell` (colonization.outpost_population people),
## or returns {} if found_block_reason says no. Returns the new city.
func found_city(nation: int, cell: Vector2i) -> Dictionary:
	if found_block_reason(cell, nation) != "":
		return {}
	var rules: Dictionary = city_rules.colonization
	var next_id := 0
	for c in cities:
		next_id = maxi(next_id, int(c.id) + 1)
	var pop := int(rules.outpost_population)
	var city := {"id": next_id, "nation": nation, "cell": cell, "population": pop,
			"pool": mini(int(city_rules.colony_start_pool), pop), "radius": _radius_for(pop),
			"last_tier": str(tier_for_population(pop).key),
			"infrastructure": int(rules.outpost_infrastructure)}
	cities.append(city)
	update_ownership()
	return city


## Removes a city, then removes any nation left with no cities.
## Returns the eliminated nation indexes. Also the test hook for elimination.
func remove_city(city_id: int) -> Array[int]:
	for i in cities.size():
		if cities[i].id == city_id:
			cities.remove_at(i)
			break
	var eliminated := eliminate_nations_without_cities()
	update_ownership()
	return eliminated


## Capture timers (one per end turn): Occupy counts down to annexable, and the recruit
## lockout after an annex counts down to 0.
func _tick_capture_timers(city: Dictionary) -> void:
	if city.get("occupied", false):
		city.occupy_turns_left = maxi(int(city.get("occupy_turns_left", 0)) - 1, 0)
	if int(city.get("recruit_lockout", 0)) > 0:
		city.recruit_lockout = int(city.recruit_lockout) - 1


## The capture choices in menu order: [{"id", plus the option's config numbers}].
func capture_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in city_rules.capture.order:
		var opt: Dictionary = city_rules.capture.options[id].duplicate()
		opt["id"] = id
		out.append(opt)
	return out


## The capture options `nation` may use, in menu order: its faction's row of
## capture.faction_options. A nation with no faction (or none in the table) may use all.
func allowed_capture_options(nation: int) -> Array[String]:
	var out: Array[String] = []
	var row: Array = city_rules.capture.faction_options.get(nation_factions.get(nation, ""), [])
	for id in city_rules.capture.order:
		if row.is_empty() or row.has(id):
			out.append(String(id))
	return out


## "" if `nation` may use the capture option, else a short reason.
## Plunder also has a global cooldown (factions.json global.plunder_cooldown_turns): with
## plunder_cooldown_scope "city" (the spec: nobody may plunder a city for that many turns after
## it was plundered; needs city_id) or "nation" (the plundering nation may not plunder again).
func capture_block_reason(nation: int, option: String, city_id := -1) -> String:
	if not city_rules.capture.options.has(option):
		return "unknown option"
	if not allowed_capture_options(nation).has(option):
		return "not allowed for this faction"
	if option == "plunder":
		var left := plunder_turns_left(nation, city_id)
		if left > 0:
			return "plunder on cooldown: %d turn%s left" % [left, "" if left == 1 else "s"]
	return ""


## Turns until `nation` may plunder (the city, in "city" scope) again; 0 if it may now.
func plunder_turns_left(nation: int, city_id := -1) -> int:
	var cooldown := int(traits.global_value("plunder_cooldown_turns", 0))
	var last := -1
	if str(traits.global_value("plunder_cooldown_scope", "city")) == "nation":
		if not plunder_last_turn.has(nation):
			return 0
		last = int(plunder_last_turn[nation])
	else:
		var city := city_by_id(city_id)
		if city.is_empty() or not city.has("last_plundered_turn"):
			return 0
		last = int(city.last_plundered_turn)
	return maxi(last + cooldown - current_turn, 0)


## Loads the affinity axes, rivals and AI weights (factions.json) for this map's nations
## (nation_factions must be set).
func load_attitude(factions: Array, global_block: Dictionary, ai_block: Dictionary) -> void:
	attitude.load_factions(factions, global_block, ai_block, nation_factions)


## Attitude of nation a toward nation b (axes, rivals and b's atrocity record).
func attitude_between(a: int, b: int) -> float:
	return attitude.between(self, a, b)


## Loads faction_traits and the global block (factions.json) for this map's nations
## (nation_factions must be set), and gives each nation its static growth_mod through
## growth_mods.
func load_faction_traits(factions: Array, global_block: Dictionary) -> void:
	traits.load_factions(factions, global_block, nation_factions)
	for nation in nation_factions:
		if traits.has_trait(int(nation), "growth_mod"):
			growth_mods[int(nation)] = float(traits.mod(int(nation), "growth_mod"))


## The harshest option `nation` may use, by capture.harshness_order.
func harshest_capture_option(nation: int) -> String:
	var allowed := allowed_capture_options(nation)
	var best := "annex"
	for id in city_rules.capture.harshness_order:
		if allowed.has(id):
			best = String(id)
	return best


## Reads each faction's `views_as_atrocity` (capture event types it condemns) and optional
## `atrocity_sensitivity` (default 1.0) from the factions.json entries.
func load_faction_views(factions: Array) -> void:
	faction_views.clear()
	faction_sensitivity.clear()
	for f in factions:
		faction_views[str(f.id)] = f.get("views_as_atrocity", city_rules.capture.default_views_as_atrocity)
		faction_sensitivity[str(f.id)] = float(f.get("atrocity_sensitivity", 1.0))
		faction_art[str(f.id)] = {"style": str(f.get("base_style", f.id)), "sea": str(f.get("type", "land")) == "sea"}


## True if the observing faction treats this reputation_event as an atrocity: its type is
## on the observer's views_as_atrocity list (Raze is always on it). The event's own
## `atrocity` flag and severity are unchanged. An unknown faction uses
## capture.default_views_as_atrocity.
func is_atrocity_to(observer_faction: String, event: Dictionary) -> bool:
	if event.type == "raze":
		return true
	return faction_views.get(observer_faction, city_rules.capture.default_views_as_atrocity).has(event.type)


## How heavily the observing faction weighs a reputation_event: an atrocity to it counts
## capture.atrocity_weight x the faction's atrocity sensitivity, any other event counts its
## base severity. Attitude.between() consumes this (Task 42).
func reputation_weight_to(observer_faction: String, event: Dictionary) -> float:
	if is_atrocity_to(observer_faction, event):
		return float(city_rules.capture.atrocity_weight) * float(faction_sensitivity.get(observer_faction, 1.0))
	return float(event.severity)


## The option the AI picks (CAPTURE.md): an aggressive faction takes its harshest allowed
## option with probability aggressive_harsh_chance (drawn from rng) and Annex otherwise;
## every other faction always picks Annex. A nation with no faction uses
## capture.ai_default_option. The result is always an allowed option (else Annex).
func ai_capture_option(nation := -1, rng: RandomNumberGenerator = null, city_id := -1) -> String:
	var faction: String = nation_factions.get(nation, "")
	var pick := String(city_rules.capture.ai_default_option)
	if faction != "":
		pick = "annex"
		if city_rules.capture.aggressive_factions.has(faction) and rng != null \
				and rng.randf() < float(city_rules.capture.aggressive_harsh_chance):
			pick = harshest_capture_option(nation)
	return pick if capture_block_reason(nation, pick, city_id) == "" else "annex"


## True if the city is occupied and its occupy timer has run out (it may be annexed).
func can_annex_occupied(city: Dictionary) -> bool:
	return city.get("occupied", false) and int(city.get("occupy_turns_left", 0)) <= 0


## Step 1 of a capture: hands the city on cell to new_nation, reruns ownership and
## removes any nation left with no cities (taking its last city eliminates it, whatever
## is chosen next). The city is flagged "capture_pending" with "capture_victim" until
## apply_capture picks the choice. Returns {"city_id", "captor", "victim", "eliminated"},
## or {} if there is no city there.
func take_city(cell: Vector2i, new_nation: int) -> Dictionary:
	var city := city_at(cell)
	if city.is_empty():
		return {}
	var victim := int(city.nation)
	city.nation = new_nation
	city.capture_pending = true
	city.capture_victim = victim
	city.besieged = false
	var eliminated := eliminate_nations_without_cities()
	update_ownership()
	return {"city_id": int(city.id), "captor": new_nation, "victim": victim, "eliminated": eliminated}


## Step 2 of a capture (CAPTURE.md): applies option ("annex", "occupy", "plunder",
## "reduce", "raze" or "enslave"; anything else is "annex") to a city taken with take_city,
## and logs the reputation_event. Numbers come from city_rules.capture.options. Returns
## {"option", "city_id", "captor", "victim", "population_loss", "cash" (plunder, for the
## caller to credit), "refugees" (people who reached the victim's nearest city),
## "lost_people" (died or had nowhere to go), "severity", "atrocity", "eliminated"}, or {}
## if the city is not awaiting a choice. Raze removes the city, so its land is freed.
func apply_capture(city_id: int, option: String) -> Dictionary:
	var city := city_by_id(city_id)
	if city.is_empty() or not city.get("capture_pending", false):
		return {}
	if capture_block_reason(int(city.nation), option, city_id) != "":
		option = "annex"  # unknown, gated for the captor's faction, or plunder on cooldown
	var opt: Dictionary = city_rules.capture.options[option]
	var victim := int(city.capture_victim)
	var captor := int(city.nation)
	var cell: Vector2i = city.cell
	var pop := int(city.population)
	var result := {"option": option, "city_id": city_id, "captor": captor, "victim": victim,
			"population_loss": 0, "cash": 0.0, "refugees": 0, "lost_people": 0,
			"severity": int(opt.severity), "atrocity": bool(opt.atrocity), "eliminated": []}
	city.erase("capture_pending")
	city.erase("capture_victim")
	if option == "raze":
		var fled := int(floor(pop * float(opt.refugee_share)))
		result.population_loss = pop
		result.eliminated = remove_city(city_id)
		_settle_refugees(result, victim, cell, fled, pop)
	else:
		var loss := int(floor(pop * float(opt.get("pop_loss", 0.0))))
		var infra_loss := float(opt.get("infra_loss", 0.0))
		result.population_loss = loss
		if infra_loss > 0.0:
			if not city.has("rebuild_target"):
				city.rebuild_target = float(city.infrastructure)
			city.rebuild_turns_left = int(city_rules.rebuild_turns)
			city.infrastructure = float(city.infrastructure) * (1.0 - infra_loss)
		city.population = pop - loss
		city.radius = _radius_for(int(city.population))
		# The old owner's recruits, labor plan, infra build and capture states do not carry over.
		city.pool = 0
		city.infra_progress = 0
		city.erase("labor")
		city.erase("labor_auto")
		for key in ["enslaved", "occupied", "occupy_turns_left", "recruit_lockout"]:
			city.erase(key)
		match option:
			"occupy":
				city.occupied = true
				city.occupy_turns_left = int(traits.mod(captor, "occupy_annex_turns", int(opt.turns)))
			"enslave":
				city.enslaved = true
			"plunder":
				var cash := float(pop) / 1000.0 * float(opt.cash_per_1000_people) \
						* float(traits.mod(captor, "plunder_cash_mult", 1.0))
				if traits.has_trait(captor, "plunder_cash_cap"):
					cash = minf(cash, float(traits.mod(captor, "plunder_cash_cap")))
				result.cash = cash
				city.last_plundered_turn = current_turn
				plunder_last_turn[captor] = current_turn
			"reduce":
				_settle_refugees(result, victim, cell, loss, loss)
		if option in ["annex", "plunder", "reduce"]:
			city.recruit_lockout = int(city_rules.capture.annexed_recruit_lockout_turns)
	reputation.log_event(option, captor, victim, int(opt.severity), bool(opt.atrocity),
			{"city": city_id, "cell": cell})
	last_capture = result
	return result


## Sends `fled` people to the victim's nearest city (recorded in result.refugees); the
## rest of the `of` people, and everyone if the victim has no city left, are lost.
func _settle_refugees(result: Dictionary, victim: int, cell: Vector2i, fled: int, of: int) -> void:
	var received := 0
	if fled > 0 and return_people(victim, -1, cell, fled) >= 0:
		received = fled
	result.refugees = received
	result.lost_people = of - received


## Annexes an occupied city whose timer has run out, with no extra loss: Annex's recruit
## lockout starts, the pool stays 0. Logs an "annex" reputation_event. False if it cannot.
func annex_occupied(city_id: int) -> bool:
	var city := city_by_id(city_id)
	if city.is_empty() or not can_annex_occupied(city):
		return false
	city.erase("occupied")
	city.erase("occupy_turns_left")
	city.pool = 0
	city.recruit_lockout = int(city_rules.capture.annexed_recruit_lockout_turns)
	var annex: Dictionary = city_rules.capture.options.annex
	reputation.log_event("annex", int(city.nation), -1, int(annex.severity), bool(annex.atrocity),
			{"city": city_id, "cell": city.cell, "from_occupy": true})
	return true


## Both capture steps at once: hands the city on cell to new_nation, applies `option`
## (the default is Annex) and returns the eliminated nation indexes. The full result is
## in last_capture (including plunder cash, which the caller credits).
func capture_city(cell: Vector2i, new_nation: int, option := "annex") -> Array[int]:
	var taken := take_city(cell, new_nation)
	if taken.is_empty():
		return []
	apply_capture(int(taken.city_id), option)
	var eliminated: Array[int] = []
	eliminated.assign(taken.eliminated)
	return eliminated


func city_at(cell: Vector2i) -> Dictionary:
	for city in cities:
		if city.cell == cell:
			return city
	return {}


## Removes every nation that has 0 cities. Returns the removed nation indexes.
func eliminate_nations_without_cities() -> Array[int]:
	var removed: Array[int] = []
	for nation in nations.duplicate():
		if not cities.any(func(city): return city.nation == nation):
			nations.erase(nation)
			removed.append(nation)
	return removed


## Places cities on each nation's land, one round per city so every nation gets
## its first city before any gets a second. Cities keep min_spacing from all others.
## Returns false if a nation had no spaced hex for its first city and
## allow_fallback is off. With allow_fallback, places it anyway and warns.
func _place_cities(rng: RandomNumberGenerator, per_nation: int, min_spacing: int,
		allow_fallback: bool) -> bool:
	var land_by_nation := {}
	for cell in territory:
		var nation: int = territory[cell]
		if nation >= 0:
			if not land_by_nation.has(nation):
				land_by_nation[nation] = []
			land_by_nation[nation].append(cell)
	var nation_ids := land_by_nation.keys()
	nation_ids.sort()
	for nation in nation_ids:
		_shuffle(land_by_nation[nation], rng)
		if coastal_nations.has(nation):
			land_by_nation[nation].sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
					return _coast_rank(a) < _coast_rank(b))
	for pass_index in per_nation:
		for nation in nation_ids:
			var spot: Variant = _first_spaced_cell(land_by_nation[nation], min_spacing)
			if spot == null:
				if pass_index > 0:
					continue
				if not allow_fallback:
					return false
				# Every nation needs at least one city, even if spacing can't be met.
				push_warning("Nation %d: no hex meets city spacing" % nation)
				spot = land_by_nation[nation][0]
			# A nation's first city is its capital; later ones are colonies.
			var first := not cities.any(func(c: Dictionary) -> bool: return c.nation == nation)
			var pop := int(city_rules.capital_start_population if first else city_rules.colony_start_population)
			var pool := int(city_rules.capital_start_pool if first else city_rules.colony_start_pool)
			cities.append({"id": cities.size(), "nation": nation, "cell": spot,
					"population": pop, "pool": mini(pool, pop), "radius": _radius_for(pop), "last_tier": str(tier_for_population(pop).key),
					"infrastructure": int(city_rules.start_infrastructure)})
	return true


## 0 touches water, 1 on the map edge, 2 inland. Used to start sea factions on the coast.
func _coast_rank(cell: Vector2i) -> int:
	var ns := neighbors(cell)
	for n in ns:
		if territory[n] == WATER:
			return 0
	return 1 if ns.size() < 6 else 2


func _first_spaced_cell(candidates: Array, min_spacing: int) -> Variant:
	for cell in candidates:
		if cities.all(func(city): return hex_distance(cell, city.cell) >= min_spacing):
			return cell
	return null


func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var dirs := _ODD_ROW_DIRS if cell.y % 2 == 1 else _EVEN_ROW_DIRS
	var result: Array[Vector2i] = []
	for dir in dirs:
		var n := cell + dir
		if n.x >= 0 and n.x < width and n.y >= 0 and n.y < height:
			result.append(n)
	return result


## All land cells connected to start (any owner except WATER).
func land_component(start: Vector2i) -> Array[Vector2i]:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		for n in neighbors(queue[i]):
			if not seen.has(n) and cells[n] != WATER:
				seen[n] = true
				queue.append(n)
		i += 1
	return queue


## Land is the top land_ratio share of noise values, so the ratio is exact.
func _make_land(map_seed: int, land_ratio: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = map_seed
	noise.frequency = 0.12
	var values: Array[float] = []
	var by_cell := {}
	for y in height:
		for x in width:
			var v := noise.get_noise_2d(x, y)
			by_cell[Vector2i(x, y)] = v
			values.append(v)
	values.sort()
	var cut: float = values[int((1.0 - land_ratio) * values.size())]
	for cell in by_cell:
		cells[cell] = UNCLAIMED if by_cell[cell] >= cut else WATER


## Seeds nations far apart on the largest landmass, then grows them outward
## one hex at a time. Growth only spreads to neighbors, so each nation stays
## contiguous. Land it can't reach stays neutral.
func _make_nations(rng: RandomNumberGenerator, nation_count: int) -> void:
	var main_land := _largest_landmass()
	if main_land.is_empty():
		return
	var seeds: Array[Vector2i] = [main_land[rng.randi_range(0, main_land.size() - 1)]]
	while seeds.size() < mini(nation_count, main_land.size()):
		var best := main_land[0]
		var best_dist := -1.0
		for cell in main_land:
			var dist := INF
			for s in seeds:
				dist = minf(dist, Vector2(cell).distance_squared_to(Vector2(s)))
			if dist > best_dist:
				best_dist = dist
				best = cell
		seeds.append(best)

	var frontiers: Array = []
	for i in seeds.size():
		cells[seeds[i]] = i
		frontiers.append([seeds[i]])
	var growing := true
	while growing:
		growing = false
		for i in frontiers.size():
			var frontier: Array = frontiers[i]
			if frontier.is_empty():
				continue
			growing = true
			var cell: Vector2i = frontier.pop_at(rng.randi_range(0, frontier.size() - 1))
			for n in neighbors(cell):
				if cells[n] == UNCLAIMED:
					cells[n] = i
					frontier.append(n)


func _largest_landmass() -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var seen := {}
	for cell in cells:
		if cells[cell] == WATER or seen.has(cell):
			continue
		var part := land_component(cell)
		for c in part:
			seen[c] = true
		if part.size() > best.size():
			best = part
	return best