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
## Each city is {"id": int, "nation": int, "cell": Vector2i}, kept in ascending id order.
var cities: Array[Dictionary] = []
## Nations that still have at least one city.
var nations: Array[int] = []
var claim_radius := 2


## Builds a map from the map config (width, height, seed, land_ratio, nation_count)
## and the cities config (cities_per_nation, claim_radius, min_spacing).
static func from_config_file(map_path: String,
		cities_path := "res://data/cities_config.json") -> HexMap:
	var map_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var city_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cities_path))
	var hex_map := HexMap.new()
	hex_map.generate(int(map_cfg.width), int(map_cfg.height), int(map_cfg.seed),
			float(map_cfg.land_ratio), int(map_cfg.nation_count),
			int(city_cfg.cities_per_nation), int(city_cfg.claim_radius),
			int(city_cfg.min_spacing))
	return hex_map


func generate(map_width: int, map_height: int, map_seed: int,
		land_ratio: float, nation_count: int, cities_per_nation := 2,
		city_claim_radius := 2, min_spacing := 3) -> void:
	width = map_width
	height = map_height
	claim_radius = city_claim_radius
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


## Each land tile goes to the nation of the closest city within claim_radius.
## Ties go to the lowest city id. Unclaimed land is neutral.
func update_ownership() -> void:
	for cell in territory:
		if territory[cell] == WATER:
			cells[cell] = WATER
			continue
		var owner := UNCLAIMED
		var best_dist := claim_radius + 1
		for city in cities:
			var dist := hex_distance(cell, city.cell)
			if dist < best_dist:
				best_dist = dist
				owner = city.nation
		cells[cell] = owner


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
			cities.append({"id": cities.size(), "nation": nation, "cell": spot})
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