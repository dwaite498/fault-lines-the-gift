class_name NativeAI
extends RefCounted
## Native AI (docs/specs/ALIENS.md, Part A). Natives are hostile to everyone, issue their
## orders through the normal simultaneous-orders system (blind, like the AI), never
## fortify and cannot capture a city.


## Plans one native's order: an adjacent enemy it can attack is attacked; otherwise it takes
## one random step inside its habitat. A strider below flee_org_share of its org steps away from
## adjacent enemies instead.
static func plan(d: Division, roster: DivisionRoster, hex_map: HexMap) -> void:
	if d.moves_left <= 0:
		return
	var enemies: Array[Division] = []
	var free: Array[Vector2i] = []
	for n in hex_map.neighbors(d.hex):
		var other := roster.division_at(n)
		if other != null and other.nation != d.nation:
			enemies.append(other)
		elif roster.can_move(d, n, hex_map):
			free.append(n)
	var tpl: Dictionary = roster.templates.get(d.unit_type, {})
	if not enemies.is_empty():
		if tpl.has("flee_org_share") and d.org < d.max_org * float(tpl.flee_org_share) and not free.is_empty():
			roster.set_order(d, _farthest(free, enemies), hex_map)
			return
		for e in enemies:
			if roster.can_attack(d, e, hex_map):
				roster.set_order(d, e.hex, hex_map)
				return
	if not free.is_empty():
		roster.set_order(d, free[roster.rng.randi_range(0, free.size() - 1)], hex_map)


## The free hex farthest from the nearest of `enemies` (ties: first in order).
static func _farthest(free: Array[Vector2i], enemies: Array[Division]) -> Vector2i:
	var best := free[0]
	var best_dist := -1
	for cell in free:
		var nearest := 1 << 30
		for e in enemies:
			nearest = mini(nearest, HexMap.hex_distance(cell, e.hex))
		if nearest > best_dist:
			best_dist = nearest
			best = cell
	return best


## End-of-turn raid step: a strider next to an UNDEFENDED enemy Outpost or Base (raid.city_tiers)
## strips raid.pop_loss of its people (never below raid.min_population). It cannot take the
## city, and a city is raided at most once per raid.city_cooldown_turns. Returns the raided cities.
static func raid_step(hex_map: HexMap, roster: DivisionRoster, turn: int) -> Array[Dictionary]:
	var raided: Array[Dictionary] = []
	var rules: Dictionary = hex_map.natives_config.get("raid", {})
	if rules.is_empty():
		return raided
	for d in roster.divisions:
		if not roster.is_native(d) or not roster.templates.get(d.unit_type, {}).get("raids", false):
			continue
		for n in hex_map.neighbors(d.hex):
			var city := hex_map.city_at(n)
			if city.is_empty() or roster.division_at(n) != null or not rules.city_tiers.has(hex_map.tier(city)):
				continue
			if turn - int(city.get("last_raid_turn", -1000)) < int(rules.city_cooldown_turns):
				continue
			var loss := mini(int(floor(int(city.population) * float(rules.pop_loss))),
					maxi(int(city.population) - int(rules.min_population), 0))
			if loss <= 0:
				continue
			city.population = int(city.population) - loss
			city.last_raid_turn = turn
			print("native_raid: city %d loses %d people" % [int(city.id), loss])
			raided.append(city)
			break
	return raided
