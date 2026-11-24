class_name ColonyCharter
extends RefCounted
## C1 colony charter (COLONY_CHARTER.md): player-only early goals from data/charter.json.
## Checks run at end of turn; rewards are cash and capacity only. The top-bar tracker is C2.

const CONFIG_PATH := "res://data/charter.json"

var cfg: Dictionary = {}
var player := 0
## Milestone ids completed, in the order they completed.
var completed: Array = []
## Running total of destroyed_natives entries with by == player.
var natives_killed := 0
## True until the first planet event has resolved (instant events the turn they fire;
## a Blizzard when blizzard_left hits 0).
var awaiting_event := true
## Set for one end_turn when the first event has just resolved (not persisted).
var _just_resolved := false
## Player city ids already seen, so a cities-milestone line can point at the new city.
var known_city_ids := {}


static func load_config(path := CONFIG_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func setup(config: Dictionary, player_nation: int) -> void:
	cfg = config
	player = player_nation
	completed.clear()
	natives_killed = 0
	awaiting_event = true
	_just_resolved = false
	known_city_ids.clear()
	if bool(cfg.get("debug_complete_all", false)):
		for milestone in cfg.milestones:
			completed.append(str(milestone.id))
		awaiting_event = false


## Count player kills in roster.destroyed_natives. Call this in _finish_turn before
## PlanetEvents.end_turn clears the array.
func tally_kills(roster: DivisionRoster) -> void:
	for rec in roster.destroyed_natives:
		if int(rec.by) == player:
			natives_killed += 1


## After grow_cities, economy.end_turn and PlanetEvents.end_turn. Completes every unmet
## milestone whose condition is now true, pays its reward once, and returns report lines
## {"text", "cell"} (cell is NO_CELL unless the hook has an obvious tile).
func end_turn(hex_map: HexMap, roster: DivisionRoster, economy: NationEconomy, events: PlanetEvents) -> Array:
	var lines: Array = []
	_just_resolved = false
	if bool(cfg.get("debug_complete_all", false)):
		_remember_cities(hex_map)
		return lines
	_resolve_first_event(events)
	for milestone in cfg.milestones:
		var id := str(milestone.id)
		if completed.has(id):
			continue
		if not _met(milestone, hex_map, roster, events):
			continue
		var cell: Vector2i = _line_cell(milestone, hex_map)
		completed.append(id)
		_pay(economy, milestone.get("reward", {}))
		lines.append({"text": _line_text(milestone), "cell": cell})
	_remember_cities(hex_map)
	return lines


func capture() -> Dictionary:
	return {"completed": completed.duplicate(), "natives_killed": natives_killed, "awaiting_event": awaiting_event}


func restore(state: Dictionary, hex_map: HexMap = null) -> void:
	if state.is_empty():
		if hex_map != null:
			_remember_cities(hex_map)
		return
	completed = state.get("completed", []).duplicate()
	natives_killed = int(state.get("natives_killed", 0))
	awaiting_event = bool(state.get("awaiting_event", true))
	if hex_map != null:
		_remember_cities(hex_map)


func _owned_cities(hex_map: HexMap) -> Array:
	return hex_map.cities.filter(func(c: Dictionary) -> bool: return int(c.nation) == player)


func _remember_cities(hex_map: HexMap) -> void:
	known_city_ids.clear()
	for city in _owned_cities(hex_map):
		known_city_ids[int(city.id)] = true


func _fielded(roster: DivisionRoster) -> int:
	var count := 0
	for d in roster.divisions:
		if d.nation == player and not roster.is_colonizer(d):
			count += 1
	return count


func _tier_at_least(hex_map: HexMap, city: Dictionary, want: String) -> bool:
	var have := hex_map.tier(city)
	if have == want:
		return true
	var reached := false
	for entry in hex_map.city_rules.get("tiers", []):
		if str(entry.key) == want:
			reached = true
		if reached and str(entry.key) == have:
			return true
	return false


func _first_event_resolved(events: PlanetEvents) -> bool:
	if events.planet_event_log.is_empty():
		return false
	var first: Dictionary = events.planet_event_log[0]
	if str(first.get("event", "")) == "blizzard" and int(events.blizzard_left) > 0:
		return false
	return true


func _resolve_first_event(events: PlanetEvents) -> void:
	if awaiting_event and _first_event_resolved(events):
		awaiting_event = false
		_just_resolved = true


func _met(milestone: Dictionary, hex_map: HexMap, roster: DivisionRoster, events: PlanetEvents) -> bool:
	match str(milestone.type):
		"divisions":
			return _fielded(roster) >= int(milestone.count)
		"cities":
			return _owned_cities(hex_map).size() >= int(milestone.count)
		"natives_killed":
			return natives_killed >= int(milestone.count)
		"survive_planet_event":
			# Only the turn the first event resolves (QA: the fire turn, or blizzard-passed).
			return _just_resolved and not _owned_cities(hex_map).is_empty()
		"tier":
			var want := str(milestone.get("tier", "city"))
			for city in _owned_cities(hex_map):
				if _tier_at_least(hex_map, city, want):
					return true
			return false
		_:
			return false


func _line_cell(milestone: Dictionary, hex_map: HexMap) -> Vector2i:
	if str(milestone.type) == "cities":
		for city in _owned_cities(hex_map):
			if not known_city_ids.has(int(city.id)):
				known_city_ids[int(city.id)] = true
				return city.get("cell", TurnReport.NO_CELL)
		var owned: Array = _owned_cities(hex_map)
		return owned.back().get("cell", TurnReport.NO_CELL) if not owned.is_empty() else TurnReport.NO_CELL
	if str(milestone.type) == "tier":
		var want := str(milestone.get("tier", "city"))
		for change in hex_map.tier_changes:
			if int(change.nation) != player:
				continue
			if str(change.to) == want or _tier_at_least(hex_map, hex_map.city_by_id(int(change.city_id)), want):
				var changed: Dictionary = hex_map.city_by_id(int(change.city_id))
				if int(changed.get("nation", -1)) == player:
					return changed.get("cell", TurnReport.NO_CELL)
		for city in _owned_cities(hex_map):
			if _tier_at_least(hex_map, city, want):
				return city.get("cell", TurnReport.NO_CELL)
	return TurnReport.NO_CELL


func _pay(economy: NationEconomy, reward: Dictionary) -> void:
	if not economy.stocks.has(player):
		return
	var stock: Dictionary = economy.stocks[player]
	if reward.has("cash"):
		stock.cash = float(stock.cash) + float(reward.cash)
	if reward.has("capacity"):
		stock.capacity = float(stock.capacity) + float(reward.capacity)


func _reward_text(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if reward.has("cash"):
		parts.append("+%d cash" % int(reward.cash))
	if reward.has("capacity"):
		parts.append("+%d capacity" % int(reward.capacity))
	return ", ".join(parts)


func _line_text(milestone: Dictionary) -> String:
	return "Charter: %s (%s)" % [str(milestone.label), _reward_text(milestone.get("reward", {}))]
