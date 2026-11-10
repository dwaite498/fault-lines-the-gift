class_name NativeSpawner
extends RefCounted
## Native life spawner (docs/specs/ALIENS.md, Part A). Runs at the end of each turn. Every
## number is in data/natives.json. Draws from the roster's random stream, so a seeded game
## spawns the same natives and a save keeps the stream.

const CONFIG_PATH := "res://data/natives.json"


static func load_config(path := CONFIG_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Number of native divisions on the map.
static func count(roster: DivisionRoster) -> int:
	var n := 0
	for d in roster.divisions:
		if roster.is_native(d):
			n += 1
	return n


## One end-of-turn spawn step for turn `turn`. Returns the divisions spawned.
## No spawns before spawner.no_spawn_before_turn (landfall); none within city_safe_radius of a
## city before city_safe_until_turn; never past max_natives. The map is kept at
## least spawner.min_natives groups (a strider is placed if it falls short).
static func run(hex_map: HexMap, roster: DivisionRoster, turn: int) -> Array[Division]:
	var out: Array[Division] = []
	var cfg: Dictionary = hex_map.natives_config
	if cfg.is_empty() or turn < int(cfg.spawner.no_spawn_before_turn):
		return out
	var sp: Dictionary = cfg.spawner
	var cap := int(sp.max_natives)
	# Worms: each fungus tile of enough density with no unit nearby.
	var worm: Dictionary = sp.worm
	var cells: Array = hex_map.fungus_tiles.keys()
	cells.sort()
	for cell in cells:
		if count(roster) >= cap:
			break
		if int(hex_map.fungus_tiles[cell]) < int(worm.min_density) or not _free(cell, hex_map, roster, turn):
			continue
		if _unit_within(cell, int(worm.no_unit_radius), roster):
			continue
		if roster.rng.randf() < float(worm.chance):
			out.append(_spawn("tendril_worm", cell, roster))
	# Striders: one random plains tile far from every city, with a chance per turn.
	if count(roster) < cap:
		var cell := _strider_tile(hex_map, roster, turn, int(sp.strider.min_city_distance))
		if cell != Vector2i(-1, -1) and roster.rng.randf() < float(sp.strider.chance):
			out.append(_spawn("rust_strider", cell, roster))
	# Minimum: always at least min_natives groups.
	while count(roster) < mini(int(sp.min_natives), cap):
		var cell := _strider_tile(hex_map, roster, turn, int(sp.strider.min_city_distance))
		if cell == Vector2i(-1, -1):
			cell = _strider_tile(hex_map, roster, turn, int(sp.city_safe_radius))
		if cell == Vector2i(-1, -1):
			break
		out.append(_spawn("rust_strider", cell, roster))
	return out


static func _spawn(key: String, cell: Vector2i, roster: DivisionRoster) -> Division:
	var d := roster.spawn_division(DivisionRoster.NATIVE_NATION, cell, key)
	print("native_spawn: %s at %s" % [key, cell])
	return d


## A random free plains tile at least `min_distance` from every city (and out of the early safe
## zone), or (-1, -1). Candidates are sorted so the pick depends only on the random stream.
static func _strider_tile(hex_map: HexMap, roster: DivisionRoster, turn: int, min_distance: int) -> Vector2i:
	var options: Array[Vector2i] = []
	for cell in hex_map.cells:
		if hex_map.terrain_name(cell) != "plains" or hex_map.cells[cell] == HexMap.WATER:
			continue
		if not _free(cell, hex_map, roster, turn) or _city_within(cell, min_distance - 1, hex_map):
			continue
		options.append(cell)
	if options.is_empty():
		return Vector2i(-1, -1)
	options.sort()
	return options[roster.rng.randi_range(0, options.size() - 1)]


static func _free(cell: Vector2i, hex_map: HexMap, roster: DivisionRoster, turn: int) -> bool:
	if roster.division_at(cell) != null or not hex_map.city_at(cell).is_empty():
		return false
	var sp: Dictionary = hex_map.natives_config.spawner
	if turn < int(sp.city_safe_until_turn) and _city_within(cell, int(sp.city_safe_radius), hex_map):
		return false
	return true


static func _city_within(cell: Vector2i, radius: int, hex_map: HexMap) -> bool:
	for c in hex_map.cities:
		if HexMap.hex_distance(cell, c.cell) <= radius:
			return true
	return false


static func _unit_within(cell: Vector2i, radius: int, roster: DivisionRoster) -> bool:
	for d in roster.divisions:
		if HexMap.hex_distance(cell, d.hex) <= radius:
			return true
	return false
