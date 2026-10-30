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
## The seed passed to generate(); other systems derive their RNG from it.
var seed_value := 0
## Vector2i cell -> terrain name ("plains", "forest", ...). See generate_terrain().
var terrain: Dictionary = {}
## Terrain name -> {color, move_cost, defense_mult, passable} from terrain_config.json.
var terrain_types: Dictionary = {}


## Builds a map from the map config (width, height, seed, land_ratio, nation_count)
## and the cities config (cities_per_nation, claim_radius, min_spacing).
static func from_config_file(map_path: String,
		cities_path := "res://data/cities_config.json",
		terrain_path := "res://data/terrain_config.json") -> HexMap:
	var map_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var city_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cities_path))
	var hex_map := HexMap.new()
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


func terrain_of(cell: Vector2i) -> Dictionary:
	return terrain_types[terrain[cell]]


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