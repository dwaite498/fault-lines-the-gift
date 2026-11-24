class_name PlanetEvents
extends RefCounted
## T2 rare planet events (PACING_TUNING_577a022.md section 3; PM rulings Nov 23). One global
## schedule seeded from the map seed: the first event on first_turn, then one every
## interval_min-interval_max turns, each aimed at the human player (Blizzard is global). Every
## number is in data/events/planet_events.json. Text only: each event returns a line for the
## message line and the turn log, and is kept in planet_event_log. State is saved in the save extras.

const CONFIG_PATH := "res://data/events/planet_events.json"

var cfg: Dictionary = {}
var player := 0
var rng := RandomNumberGenerator.new()
var next_turn := 0
var last_event := ""
var survivor_count := 0
var blizzard_left := 0
## Division id -> true for the Native Migration natives that pay a bounty when the player kills them.
var bounty_ids := {}
## {"turn", "event", "text"} per event fired.
var planet_event_log: Array = []


static func load_config(path := CONFIG_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func setup(config: Dictionary, map_seed: int, player_nation: int) -> void:
	cfg = config
	player = player_nation
	rng.seed = hash([map_seed, int(cfg.get("salt", 0))])
	next_turn = int(cfg.first_turn)


## End-of-turn step for the turn that is starting (`turn`): pays bounties for tagged natives the
## player destroyed, counts down Blizzard, then fires the scheduled event. Returns the text lines.
func end_turn(hex_map: HexMap, roster: DivisionRoster, economy: NationEconomy, turn: int) -> Array[String]:
	var lines: Array[String] = []
	var mig: Dictionary = cfg.events.native_migration
	for rec in roster.destroyed_natives:
		if bounty_ids.has(int(rec.id)):
			bounty_ids.erase(int(rec.id))
			if int(rec.by) == player:
				economy.stocks[player].cash = float(economy.stocks[player].cash) + float(mig.bounty_cash)
				lines.append("Migration native destroyed: +%d cash" % int(mig.bounty_cash))
	roster.destroyed_natives.clear()
	if blizzard_left > 0:
		blizzard_left -= 1
		_apply_blizzard(hex_map)
		if blizzard_left == 0:
			lines.append("The blizzard has passed")
	if turn >= next_turn:
		var key := pick_event()
		var text := fire(key, hex_map, roster, economy)
		last_event = key
		planet_event_log.append({"turn": turn, "event": key, "text": text})
		lines.append(text)
		next_turn = turn + rng.randi_range(int(cfg.interval_min), int(cfg.interval_max))
	for line in lines:
		print("turn_log: planet event: ", line)
	return lines


## Weighted pick: never the last event again, Survivor Landing at most max_per_game times.
func pick_event() -> String:
	var keys: Array = cfg.events.keys()
	keys.sort()
	var options: Array = keys.filter(func(k: String) -> bool:
			return k != last_event and not (k == "survivor_landing" and survivor_count >= int(cfg.events[k].max_per_game)))
	var total := 0.0
	for k in options:
		total += float(cfg.events[k].weight)
	var roll := rng.randf() * total
	for k in options:
		roll -= float(cfg.events[k].weight)
		if roll < 0.0:
			return k
	return options.back()


func fire(key: String, hex_map: HexMap, roster: DivisionRoster, economy: NationEconomy) -> String:
	var e: Dictionary = cfg.events[key]
	match key:
		"survivor_landing":
			return _survivor_landing(e, hex_map, roster)
		"native_migration":
			return _native_migration(e, hex_map, roster)
		"blizzard":
			blizzard_left = int(e.turns)
			_apply_blizzard(hex_map)
			return "Blizzard: %d turns of doubled cold attrition, snow costs +%d move" % [int(e.turns), int(e.snow_move_cost_extra)]
		"spore_bloom":
			return _spore_bloom(e, hex_map)
		"supply_cache":
			if rng.randf() < float(e.cash_chance):
				economy.stocks[player].cash = float(economy.stocks[player].cash) + float(e.cash)
				return "Supply Cache: +%d cash" % int(e.cash)
			economy.stocks[player].capacity = float(economy.stocks[player].capacity) + float(e.capacity)
			return "Supply Cache: +%d capacity" % int(e.capacity)
	return ""


func _apply_blizzard(hex_map: HexMap) -> void:
	var e: Dictionary = cfg.events.blizzard
	hex_map.cold_event_mult = float(e.cold_attrition_mult) if blizzard_left > 0 else 1.0
	hex_map.snow_extra_move = int(e.snow_move_cost_extra) if blizzard_left > 0 else 0


func _player_cities(hex_map: HexMap) -> Array:
	var out: Array = hex_map.cities.filter(func(c: Dictionary) -> bool: return int(c.nation) == player)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return out


func _survivor_landing(e: Dictionary, hex_map: HexMap, roster: DivisionRoster) -> String:
	var mine := _player_cities(hex_map)
	if mine.is_empty():
		return "Survivor Landing: no city to land beside"
	var big: Dictionary = mine[0]
	for c in mine:
		if int(c.population) > int(big.population):
			big = c
	var spots: Array[Vector2i] = []
	for n in hex_map.neighbors(big.cell):
		if hex_map.cells.get(n, HexMap.WATER) != HexMap.WATER and hex_map.terrain_of(n).passable \
				and hex_map.city_at(n).is_empty() and roster.division_at(n) == null:
			spots.append(n)
	spots.sort()
	survivor_count += 1
	if spots.is_empty():
		return "Survivor Landing: no free hex beside city %d" % int(big.id)
	var cell := spots[rng.randi_range(0, spots.size() - 1)]
	roster.spawn_division(player, cell, str(e.template), int(big.id))
	return "Survivor Landing: a free colony pod lands beside city %d" % int(big.id)


func _native_migration(e: Dictionary, hex_map: HexMap, roster: DivisionRoster) -> String:
	var mine := _player_cities(hex_map)
	if mine.is_empty():
		return "Native Migration: no border city"
	var border: Array = mine.filter(func(c: Dictionary) -> bool:
			for cell in hex_map.cells:
				if HexMap.hex_distance(cell, c.cell) <= int(c.get("radius", 1)) + 1 and int(hex_map.cells[cell]) != player:
					return true
			return false)
	if border.is_empty():
		border = mine
	var city: Dictionary = border[rng.randi_range(0, border.size() - 1)]
	var by_terrain: Dictionary = e.native_by_terrain
	var spots: Array[Vector2i] = []
	for cell in hex_map.cells:
		var d := HexMap.hex_distance(cell, city.cell)
		if d >= int(e.min_distance) and d <= int(e.max_distance) and native_type_for(cell, hex_map, by_terrain) != "" \
				and roster.division_at(cell) == null and hex_map.city_at(cell).is_empty():
			spots.append(cell)
	spots.sort()
	var placed := 0
	for i in int(e.count):
		if spots.is_empty():
			break
		var cell: Vector2i = spots.pop_at(rng.randi_range(0, spots.size() - 1))
		var kind := native_type_for(cell, hex_map, by_terrain)
		var nd := NativeSpawner._spawn(kind, cell, roster, hex_map.pressure)
		if kind == "crag_harrier":
			nd.nest = cell
		bounty_ids[nd.id] = true
		placed += 1
	return "Native Migration: %d natives near city %d (+%d cash each killed)" % [placed, int(city.id), int(e.bounty_cash)]


## The normal native for a hex: fungus first, else by terrain; "" if none lives there.
static func native_type_for(cell: Vector2i, hex_map: HexMap, by_terrain: Dictionary) -> String:
	if hex_map.cells.get(cell, HexMap.WATER) == HexMap.WATER:
		return ""
	if hex_map.is_fungus(cell) and by_terrain.has("fungus"):
		return str(by_terrain.fungus)
	return str(by_terrain.get(hex_map.terrain_name(cell), ""))


func _spore_bloom(e: Dictionary, hex_map: HexMap) -> String:
	if hex_map.fungus_tiles.is_empty():
		return "Spore Bloom: no fungus on the planet"
	var claim: Array[Vector2i] = []
	for cell in hex_map.cells:
		if int(hex_map.cells[cell]) == player:
			claim.append(cell)
	# Fungus tiles nearest the claim first; the patch grown is the nearest one with room to grow.
	var dist_of := {}
	for t in hex_map.fungus_tiles:
		var best := 1 << 20
		for c in claim:
			best = mini(best, HexMap.hex_distance(t, c))
		dist_of[t] = best
	var tiles: Array = dist_of.keys()
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return dist_of[a] < dist_of[b] or (dist_of[a] == dist_of[b] and a < b))
	var patch := {}
	for start in tiles:
		patch = {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			for n in hex_map.neighbors(queue.pop_front()):
				if hex_map.fungus_tiles.has(n) and not patch.has(n):
					patch[n] = true
					queue.append(n)
		if not _bloom_edge(patch, hex_map).is_empty():
			break
	var grown: Array[Vector2i] = []
	for i in int(e.grow_tiles):
		var options := _bloom_edge(patch, hex_map)
		if options.is_empty():
			break
		var cell: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		hex_map.fungus_tiles[cell] = int(e.new_density)
		patch[cell] = true
		grown.append(cell)
	var touches := grown.any(func(g: Vector2i) -> bool:
			if int(hex_map.cells.get(g, -1)) == player:
				return true
			return hex_map.neighbors(g).any(func(n: Vector2i) -> bool: return int(hex_map.cells.get(n, -1)) == player))
	if touches:
		hex_map.pressure_event(player, str(e.pressure_key))
	return "Spore Bloom: a fungus patch grows by %d tiles%s" % [grown.size(), " and touches your claim (+Pressure)" if touches else ""]


## Sorted free tiles next to a patch that can take fungus (land, no city, can_host_fungus).
func _bloom_edge(patch: Dictionary, hex_map: HexMap) -> Array:
	var edge := {}
	for p in patch:
		for n in hex_map.neighbors(p):
			if not patch.has(n) and hex_map.cells.get(n, HexMap.WATER) != HexMap.WATER and hex_map.city_at(n).is_empty() \
					and hex_map.can_host_fungus(n):
				edge[n] = true
	var options: Array = edge.keys()
	options.sort()
	return options


func capture() -> Dictionary:
	return {"next_turn": next_turn, "last_event": last_event, "survivor_count": survivor_count, "blizzard_left": blizzard_left,
			"bounty_ids": bounty_ids.keys(), "log": planet_event_log.duplicate(true), "rng_state": str(rng.state)}


func restore(state: Dictionary, hex_map: HexMap) -> void:
	if state.is_empty():
		return
	next_turn = int(state.next_turn)
	last_event = str(state.last_event)
	survivor_count = int(state.survivor_count)
	blizzard_left = int(state.blizzard_left)
	bounty_ids.clear()
	for id in state.bounty_ids:
		bounty_ids[int(id)] = true
	planet_event_log = state.log.duplicate(true)
	rng.state = str(state.rng_state).to_int()  # a string: JSON would round a 64-bit int
	_apply_blizzard(hex_map)
