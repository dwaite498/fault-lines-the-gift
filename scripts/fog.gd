class_name Fog
extends RefCounted
## Fog of war with line of sight (Task 40f). Three states per tile per nation:
## UNEXPLORED (black), EXPLORED (terrain and cities as last seen, with the owner and city tier
## at that time; no units; the world keeps changing unseen) and VISIBLE (live).
## Rules come from map_config.json "fog". The AI stays omniscient (ai.respects_fog = false):
## fog only filters what the observer (the player) can see and target, plus any nation if
## respects_fog is turned on; there is no AI fog logic.

const CONFIG_PATH := "res://data/map_config.json"
const UNEXPLORED := 0
const EXPLORED := 1
const VISIBLE := 2

var rules := {}
var respects_fog := false
## The nation whose screen the fog hides things from (the player).
var observer := 0
## nation -> {cell: {"owner": int, "city": {} or {"id", "nation", "tier", "population"}}}
var explored := {}
## nation -> {cell: true}, recomputed by update (not saved).
var visible := {}


static func from_config(map_cfg: Dictionary, observer_nation := 0) -> Fog:
	var f := Fog.new()
	f.rules = map_cfg.get("fog", {"enabled": false}).duplicate(true)
	f.respects_fog = bool(map_cfg.get("ai", {}).get("respects_fog", false))
	f.observer = observer_nation
	return f


static func load_config(path := CONFIG_PATH, observer_nation := 0) -> Fog:
	return from_config(JSON.parse_string(FileAccess.get_file_as_string(path)), observer_nation)


func enabled() -> bool:
	return bool(rules.get("enabled", false))


## True if fog hides things from this nation: the observer, or everyone if the AI respects fog.
func filters(nation: int) -> bool:
	return enabled() and (nation == observer or respects_fog)


## City tier name for a population ("outpost", "base", "city", "metropolis").
func tier_of(population: int) -> String:
	var best := ""
	var best_min := -1
	for name in rules.tier_thresholds:
		var need := int(rules.tier_thresholds[name])
		if population >= need and need > best_min:
			best = name
			best_min = need
	return best


## Sight in hexes of a city: sight.city, +city_sight_bonus at city_bonus_tier or higher.
func sight_of_city(city: Dictionary) -> int:
	var sight := int(rules.sight.city)
	var need := int(rules.tier_thresholds[rules.city_bonus_tier])
	if int(city.population) >= need:
		sight += int(rules.city_sight_bonus)
	return sight


## Sight of a unit: by unit type, +elevated_sight_bonus on hills or mountains.
func sight_of_unit(d: Division, hex_map: HexMap) -> int:
	var sight := int(rules.sight.get(d.unit_type, rules.sight.default))
	if rules.elevated_terrain.has(hex_map.terrain_name(d.hex)):
		sight += int(rules.elevated_sight_bonus)
	return sight


## True if a viewer on `from` sees `to` within `sight` hexes: every hex strictly between them
## must not be blocking terrain (mountains). A blocking hex itself can be seen.
func sees(hex_map: HexMap, from: Vector2i, to: Vector2i, sight: int) -> bool:
	var dist := HexMap.hex_distance(from, to)
	if dist > sight:
		return false
	if dist <= 1:
		return true
	var line := HexMap.hex_line(from, to)
	for i in range(1, line.size() - 1):
		if rules.blocking_terrain.has(hex_map.terrain_name(line[i])):
			return false
	return true


## Hexes within `radius` of `center` that exist on the map (center included).
func _within(hex_map: HexMap, center: Vector2i, radius: int) -> Array[Vector2i]:
	var seen := {center: true}
	var frontier: Array[Vector2i] = [center]
	for step in radius:
		var next: Array[Vector2i] = []
		for cell in frontier:
			for n in hex_map.neighbors(cell):
				if not seen.has(n):
					seen[n] = true
					next.append(n)
		frontier = next
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	return out


func _mark(hex_map: HexMap, into: Dictionary, from: Vector2i, sight: int) -> void:
	for cell in _within(hex_map, from, sight):
		if not into.has(cell) and sees(hex_map, from, cell, sight):
			into[cell] = true


## The landing: the tiles within fog.landfall_radius of each of the nation's cities are
## explored (no line of sight at landfall). Call once at the start of a new game.
func explore_landing(hex_map: HexMap) -> void:
	for nation in hex_map.nations:
		for city in hex_map.cities:
			if city.nation == nation:
				for cell in _within(hex_map, city.cell, int(rules.landfall_radius)):
					_see(hex_map, nation, cell)


func _snapshot(hex_map: HexMap, cell: Vector2i) -> Dictionary:
	var city := hex_map.city_at(cell)
	var snap := {"owner": int(hex_map.cells.get(cell, HexMap.UNCLAIMED)), "city": {}}
	if not city.is_empty():
		snap.city = {"id": int(city.id), "nation": int(city.nation), "tier": tier_of(int(city.population)),
				"population": int(city.population)}
	return snap


func _see(hex_map: HexMap, nation: int, cell: Vector2i) -> void:
	if not explored.has(nation):
		explored[nation] = {}
	explored[nation][cell] = _snapshot(hex_map, cell)


## Recomputes what every nation sees now (cities, units) and refreshes the "last seen"
## snapshot of every visible tile. Cheap enough to call after every change.
func update(hex_map: HexMap, roster: DivisionRoster) -> void:
	if not enabled():
		return
	visible.clear()
	for nation in hex_map.nations:
		var vis := {}
		for city in hex_map.cities:
			if city.nation == nation:
				_mark(hex_map, vis, city.cell, sight_of_city(city))
		for d in roster.divisions:
			if d.nation == nation:
				_mark(hex_map, vis, d.hex, sight_of_unit(d, hex_map))
		visible[nation] = vis
		for cell in vis:
			_see(hex_map, nation, cell)


## UNEXPLORED, EXPLORED or VISIBLE for `nation` at `cell`. With fog off everything is VISIBLE.
func state(nation: int, cell: Vector2i) -> int:
	if not enabled():
		return VISIBLE
	if visible.get(nation, {}).has(cell):
		return VISIBLE
	if explored.get(nation, {}).has(cell):
		return EXPLORED
	return UNEXPLORED


## True if `nation` can see (and so target) what is on `cell` right now.
func can_target(nation: int, cell: Vector2i) -> bool:
	return state(nation, cell) == VISIBLE


## What `nation` last saw on an explored tile ({} if unexplored): {"owner", "city"}.
func last_seen(nation: int, cell: Vector2i) -> Dictionary:
	return explored.get(nation, {}).get(cell, {})


## The explored memory for saving (the visible set is recomputed by update).
func capture() -> Dictionary:
	return explored.duplicate(true)


func restore(saved: Dictionary) -> void:
	explored = saved.duplicate(true)
	visible.clear()
