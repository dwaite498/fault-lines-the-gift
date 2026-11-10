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
## Each city is {"id", "nation", "cell": Vector2i, "population", "infrastructure",
## "radius"}, kept in ascending id order. radius is that city's claim radius.
## A recently captured city also has "rebuild_target" and "rebuild_turns_left".
var cities: Array[Dictionary] = []
## Nations that still have at least one city.
var nations: Array[int] = []
## Growth rules from cities_config.json. Set before generate() so new cities use them.
var city_rules := {
	"claim_radius": 1, "grown_claim_radius": 2, "grown_radius_population": 20,
	"start_population": 10, "start_infrastructure": 10,
	"growth_per_turn": 1, "max_population": 30,
	"capture_pop_loss": 0.25, "capture_infra_loss": 0.3, "rebuild_turns": 26,
}
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
## View-only for now (Task 33); no rules read it.
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
		coastal: Array[int] = []) -> HexMap:
	var map_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
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
func step_cost(from: Vector2i, to: Vector2i) -> int:
	var cost := int(terrain_of(to).move_cost)
	if elevation_of(to) > elevation_of(from):
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
	var cliff := int(elevation_rules.get("cliff_diff", 1 << 20))
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
						var lo := mini(elevation[a], elevation[b])
						var hi_cell: Vector2i = a if elevation[a] > elevation[b] else b
						elevation[hi_cell] = maxi(lo + cliff - 1, int(elevation_rules.get("min", -3)))
						passes += 1
						fixed = true
						break
				if fixed:
					break
			if not fixed:
				break
	return passes


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


static func _to_cube(cell: Vector2i) -> Vector3i:
	var x := cell.x - int((cell.y - (cell.y & 1)) / 2.0)
	return Vector3i(x, -x - cell.y, cell.y)


## Each land tile goes to the nation of the closest city whose own radius
## reaches it. Ties go to the lowest city id. Unclaimed land is neutral.
func update_ownership() -> void:
	for cell in territory:
		if territory[cell] == WATER:
			cells[cell] = WATER
			continue
		var owner := UNCLAIMED
		var best_dist := 1 << 30
		for city in cities:
			var dist := hex_distance(cell, city.cell)
			if dist <= int(city.radius) and dist < best_dist:
				best_dist = dist
				owner = city.nation
		cells[cell] = owner


## Adds growth_per_turn population to every city (up to max_population) and
## sets each radius from its population. Reruns ownership if a radius changed.
## Returns true if ownership was rerun. Called once per end turn.
func grow_cities() -> bool:
	var changed := false
	for city in cities:
		city.population = mini(int(city.population) + int(city_rules.growth_per_turn),
				int(city_rules.max_population))
		_rebuild_step(city)
		var radius := _radius_for(int(city.population))
		if radius != int(city.radius):
			city.radius = radius
			changed = true
	if changed:
		update_ownership()
	return changed


## Regains (target - current) / turns_left infra. Lands exactly on the target
## on the last turn, then clears the rebuild keys.
func _rebuild_step(city: Dictionary) -> void:
	if not city.has("rebuild_turns_left"):
		return
	var left := int(city.rebuild_turns_left)
	var target := float(city.rebuild_target)
	if left <= 1:
		city.infrastructure = target
		city.erase("rebuild_turns_left")
		city.erase("rebuild_target")
		return
	city.infrastructure = float(city.infrastructure) + (target - float(city.infrastructure)) / left
	city.rebuild_turns_left = left - 1


func _radius_for(population: int) -> int:
	if population >= int(city_rules.grown_radius_population):
		return int(city_rules.grown_claim_radius)
	return int(city_rules.claim_radius)


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


## Hands the city on cell to new_nation, reruns ownership, and removes any
## nation left with no cities. Returns the eliminated nation indexes.
## The city loses capture_pop_loss of its pop (rounded down) and
## capture_infra_loss of its infra, then rebuilds over rebuild_turns turns.
## Re-capture during a rebuild keeps the original target and restarts the timer.
func capture_city(cell: Vector2i, new_nation: int) -> Array[int]:
	for city in cities:
		if city.cell == cell:
			city.nation = new_nation
			if not city.has("rebuild_target"):
				city.rebuild_target = float(city.infrastructure)
			city.rebuild_turns_left = int(city_rules.rebuild_turns)
			var pop := int(city.population)
			city.population = pop - int(floor(pop * float(city_rules.capture_pop_loss)))
			city.infrastructure = float(city.infrastructure) * (1.0 - float(city_rules.capture_infra_loss))
			city.radius = _radius_for(int(city.population))
	var eliminated := eliminate_nations_without_cities()
	update_ownership()
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
			var pop := int(city_rules.start_population)
			cities.append({"id": cities.size(), "nation": nation, "cell": spot,
					"population": pop, "radius": _radius_for(pop),
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