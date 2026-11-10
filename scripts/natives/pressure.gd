class_name Pressure
extends RefCounted
## Planet-wide alien Pressure and escalation levels (docs/specs/ALIENS.md, Part B). The score
## is 0 to pressure.max, kept with per-faction contributions. Every number is in
## data/natives.json "pressure". The state is saved through SaveGame extras ("pressure").

var cfg := {}
var score := 0.0
## 1 Wary, 2 Hostile, 3 Swarm (levels are 1-based).
var level := 1
## Faction id -> total pressure it caused (after its pressure_mult).
var contrib := {}
## Faction id -> recent contribution, decayed each turn (offender bias).
var recent := {}
## World events: {"turn", "text"}. Oldest first.
var events: Array[Dictionary] = []


func configure(pressure_cfg: Dictionary) -> void:
	cfg = pressure_cfg


func enabled() -> bool:
	return not cfg.is_empty()


## The faction's pressure multiplier (Verdant 0.5, Syndicate 1.25, Deepwater 1.25, else the default).
func mult(faction: String) -> float:
	return float(cfg.get("faction_pressure_mult", {}).get(faction, cfg.get("default_pressure_mult", 1.0)))


## Adds `count` x events[key] x the faction's multiplier. Returns the amount added.
func add(faction: String, key: String, count := 1.0) -> float:
	if not enabled() or not cfg.events.has(key):
		return 0.0
	var amount := float(cfg.events[key]) * count * mult(faction)
	score = clampf(score + amount, 0.0, float(cfg.max))
	contrib[faction] = float(contrib.get(faction, 0.0)) + amount
	recent[faction] = float(recent.get(faction, 0.0)) + amount
	return amount


func _level_data() -> Dictionary:
	return cfg.levels[level - 1]


## End-of-turn step: +big_city_per_turn per city above big_city_population, recent contributions
## decay, then level changes. A level goes up the moment its threshold is crossed. Below the
## current level's threshold the score decays level_decay_per_turn; Hostile drops back to Wary once
## it is level_drop_margin under its threshold. Swarm never decays or drops. Returns the new world event lines.
func end_turn(hex_map: HexMap, turn: int) -> Array[String]:
	var lines: Array[String] = []
	if not enabled():
		return lines
	for city in hex_map.cities:
		if int(city.nation) >= 0 and int(city.population) > int(cfg.big_city_population):
			add(str(hex_map.nation_factions.get(city.nation, "")), "big_city_per_turn")
	for f in recent:
		recent[f] = float(recent[f]) * float(cfg.recent_decay)
	if level < 3 and score < float(_level_data().threshold):
		score = maxf(score - float(cfg.level_decay_per_turn), 0.0)
	for i in range(cfg.levels.size(), level, -1):
		if score >= float(cfg.levels[i - 1].threshold):
			level = i
			lines.append(_log(turn, str(cfg.levels[i - 1].event)))
			break
	if level == 2 and score < float(cfg.levels[1].threshold) - float(cfg.level_drop_margin):
		level = 1
		lines.append(_log(turn, "The planet settles"))
	return lines


## Sets the score (clamped) and applies level rises at once. For tests and debugging.
func set_score(value: float, turn := 0) -> void:
	score = clampf(value, 0.0, float(cfg.max))
	for i in range(cfg.levels.size(), level, -1):
		if score >= float(cfg.levels[i - 1].threshold):
			level = i
			_log(turn, str(cfg.levels[i - 1].event))
			break


func _log(turn: int, text: String) -> String:
	events.append({"turn": turn, "text": text})
	print("world_event: %s" % text)
	return text


## Spawn chance multiplier: the product of every reached level's spawn_mult (Hostile x2, Swarm x3 = x6).
func spawn_mult() -> float:
	return _product("spawn_mult")


## Native strength and attack multiplier (Hostile x1.25, Swarm x1.5 = x1.875).
func stat_mult() -> float:
	return _product("stat_mult")


func _product(key: String) -> float:
	var m := 1.0
	if not enabled():
		return m
	for i in level:
		m *= float(cfg.levels[i].get(key, 1.0))
	return m


## Extra max_natives of the current level (Hostile +4, Swarm +8: the current level's bonus).
func max_natives_bonus() -> int:
	return int(_level_data().get("max_natives_bonus", 0)) if enabled() else 0


## Minimum fungus density worms spawn on: `base`, or the level's worm_min_density (Swarm 2).
func worm_min_density(base: int) -> int:
	return int(_level_data().get("worm_min_density", base)) if enabled() else base


## A faction picked at random weighted by recent contribution, or "" if nobody has any.
func target_faction(rng: RandomNumberGenerator) -> String:
	var names: Array = recent.keys()
	names.sort()
	var total := 0.0
	for f in names:
		total += float(recent[f])
	if total <= 0.0001:
		return ""
	var roll := rng.randf() * total
	for f in names:
		roll -= float(recent[f])
		if roll <= 0.0:
			return str(f)
	return str(names.back())


func capture() -> Dictionary:
	return {"score": score, "level": level, "contrib": contrib.duplicate(), "recent": recent.duplicate(),
			"events": events.duplicate(true)}


func restore(state: Dictionary) -> void:
	score = float(state.get("score", 0.0))
	level = int(state.get("level", 1))
	contrib = state.get("contrib", {}).duplicate()
	recent = state.get("recent", {}).duplicate()
	events.assign(state.get("events", []))
