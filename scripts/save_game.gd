class_name SaveGame
extends RefCounted
## Save and load (Task 40c): one manual save slot plus an autosave written at the end of
## every turn, both under user://. The whole game state round-trips: map ownership, cities
## (population, pools, rebuild and capture states), divisions (with orders), economy stocks
## and recruit queues, POWs, reputation events, the AI's random stream and the turn.
## Later systems add their state through `extras` (fog of war in Task 40f, alien Pressure
## when it exists).

const VERSION := 1
const SLOT_PATH := "user://savegame.sav"
const AUTOSAVE_PATH := "user://autosave.sav"


## Division variables saved by name (every script variable of Division).
static func _division_props() -> Array[String]:
	var out: Array[String] = []
	for p in Division.new().get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(String(p.name))
	return out


## The game state as plain data. map_cfg is the applied map config the game started from
## (GameSession.apply), faction_ids the faction id of each nation index.
static func capture(hex_map: HexMap, roster: DivisionRoster, economy: NationEconomy, turn: int,
		map_cfg: Dictionary, faction_ids: Array, extras := {}) -> Dictionary:
	var divs: Array = []
	var props := _division_props()
	for d in roster.divisions:
		var saved := {}
		for p in props:
			var value = d.get(p)
			saved[p] = value.duplicate() if value is Array else value
		divs.append(saved)
	return {
		"version": VERSION,
		"turn": turn,
		"map_cfg": map_cfg.duplicate(true),
		"faction_ids": faction_ids.duplicate(),
		"map": {
			"cells": hex_map.cells.duplicate(), "territory": hex_map.territory.duplicate(),
			"terrain": hex_map.terrain.duplicate(), "elevation": hex_map.elevation.duplicate(),
			"ridge_edges": hex_map.ridge_edges.duplicate(), "fungus_tiles": hex_map.fungus_tiles.duplicate(),
			"cities": hex_map.cities.duplicate(true), "nations": hex_map.nations.duplicate(),
			"coastal_nations": hex_map.coastal_nations.duplicate(), "growth_mods": hex_map.growth_mods.duplicate(),
			"seed_value": hex_map.seed_value, "width": hex_map.width, "height": hex_map.height,
			"reputation": hex_map.reputation.events.duplicate(true),
		},
		"roster": {
			"divisions": divs, "neutral_nations": roster.neutral_nations.duplicate(),
			"pending_captures": roster.pending_captures.duplicate(true),
			"rng_seed": roster.rng.seed, "rng_state": roster.rng.state,
		},
		"economy": {
			"stocks": economy.stocks.duplicate(true), "pending": economy.pending.duplicate(true),
			"upkeep_paid": economy.upkeep_paid.duplicate(), "unpaid_divisions": economy.unpaid_divisions.duplicate(true),
			"pows": economy.pows.duplicate(true), "reinforce_spent": economy.reinforce_spent.duplicate(),
		},
		"extras": extras.duplicate(true),
	}


## Loads `state` into freshly built objects (a map from the same config, a roster and an
## economy set up on it). Replaces every saved value in place. Returns the turn.
static func restore(state: Dictionary, hex_map: HexMap, roster: DivisionRoster, economy: NationEconomy) -> int:
	var m: Dictionary = state.map
	hex_map.width = int(m.width)
	hex_map.height = int(m.height)
	hex_map.seed_value = int(m.seed_value)
	for key in ["cells", "territory", "terrain", "elevation", "ridge_edges", "fungus_tiles", "growth_mods"]:
		var target: Dictionary = hex_map.get(key)
		target.clear()
		target.merge(m[key].duplicate(true))
	hex_map.cities.assign(m.cities.duplicate(true))
	hex_map.nations.assign(m.nations)
	hex_map.coastal_nations.assign(m.coastal_nations)
	hex_map.reputation.events.assign(m.reputation.duplicate(true))
	var r: Dictionary = state.roster
	roster.divisions.clear()
	for saved in r.divisions:
		var d := Division.new()
		for p in saved:
			var value = saved[p]
			if value is Array:
				var current: Array = d.get(p)
				current.assign(value)
			else:
				d.set(p, value)
		roster.divisions.append(d)
	roster.neutral_nations.assign(r.neutral_nations)
	roster.pending_captures.assign(r.pending_captures.duplicate(true))
	roster.rng.seed = int(r.rng_seed)
	roster.rng.state = int(r.rng_state)
	var e: Dictionary = state.economy
	economy.stocks = e.stocks.duplicate(true)
	economy.pending = e.pending.duplicate(true)
	economy.upkeep_paid = e.upkeep_paid.duplicate()
	economy.unpaid_divisions = e.unpaid_divisions.duplicate(true)
	economy.pows = e.pows.duplicate(true)
	economy.reinforce_spent = e.reinforce_spent.duplicate()
	return int(state.turn)


## A hash of the state that does not depend on dictionary insertion order.
static func state_hash(state: Dictionary) -> String:
	return _canonical(state).sha256_text()


static func _canonical(v: Variant) -> String:
	if v is Dictionary:
		var keys: Array = v.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var parts: PackedStringArray = []
		for k in keys:
			parts.append(_canonical(k) + ":" + _canonical(v[k]))
		return "{" + ",".join(parts) + "}"
	if v is Array:
		var parts: PackedStringArray = []
		for x in v:
			parts.append(_canonical(x))
		return "[" + ",".join(parts) + "]"
	return var_to_bytes(v).hex_encode()


static func write(path: String, state: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_var(state)
	f.close()
	return true


## The saved state, or {} if the file is missing, unreadable or from another version.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var state = f.get_var()
	f.close()
	if not state is Dictionary or int(state.get("version", -1)) != VERSION:
		return {}
	return state


## The newest existing save file (the slot or the autosave), or "" if there is none.
static func latest_path() -> String:
	var best := ""
	var best_time := -1
	for path in [SLOT_PATH, AUTOSAVE_PATH]:
		if FileAccess.file_exists(path):
			var t := FileAccess.get_modified_time(path)
			if t > best_time:
				best = path
				best_time = t
	return best


static func has_save() -> bool:
	return latest_path() != ""
