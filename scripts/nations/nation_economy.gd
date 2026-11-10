class_name NationEconomy
extends RefCounted
## Per-nation resource stocks, per-turn city income, division upkeep, and the
## recruit training queue. Numbers come from data/resources_config.json; the people
## numbers (division cost, pool, labor, people per strength) from data/cities_config.json.
## There is no nation-wide manpower stock: recruits and reinforcements draw people from
## each city's recruitable pool (HexMap).

const CONFIG_PATH := "res://data/resources_config.json"
const CITIES_CONFIG_PATH := "res://data/cities_config.json"
const RESOURCES: Array[String] = ["cash", "influence", "operations", "capacity"]
## The three labor sinks a city's labor points are assigned to. Training and
## Infrastructure are only stored for now (their sinks are Task 37); Growth feeds
## HexMap.growth_rate.
const SINKS: Array[String] = ["training", "infrastructure", "growth"]

var config: Dictionary = {}
## The cities_config.json rules (same values as HexMap.city_rules; setup() adopts the map's).
var city_rules: Dictionary = {}
## nation index -> {"cash": float, "influence": ..., ...}
var stocks: Dictionary = {}
## city id -> {"nation": int, "turns_left": int}. One pending recruit per city.
## turns_left 0 means trained and waiting for the city hex to be free.
var pending: Dictionary = {}
## nation index -> true if that nation paid its upkeep on the last end_turn.
var upkeep_paid: Dictionary = {}
## POWs: captor nation -> {owner nation -> count (float)}. Kept after elimination.
var pows: Dictionary = {}
## nation index -> people drawn from pools for reinforcement on the last end_turn.
var reinforce_spent: Dictionary = {}


func _init(path := CONFIG_PATH) -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(path))
	city_rules = JSON.parse_string(FileAccess.get_file_as_string(CITIES_CONFIG_PATH))


func setup(hex_map: HexMap) -> void:
	city_rules = hex_map.city_rules
	stocks.clear()
	pending.clear()
	upkeep_paid.clear()
	pows.clear()
	reinforce_spent.clear()
	refresh_labor(hex_map)
	for nation in hex_map.nations:
		stocks[nation] = {}
		upkeep_paid[nation] = true
		for r in RESOURCES:
			stocks[nation][r] = float(config.start_stock.get(r, 0))


## Labor points of a city: population / people_per_labor_point, rounded down, times
## siege_labor_mult while besieged (HexMap.labor_points_for).
func labor_points(city: Dictionary) -> int:
	return HexMap.labor_points_for(city, city_rules)


## Labor not assigned to a sink: labor_points minus everything in city.labor (the
## assignment dictionary, absent until labor assignment exists), never below 0.
func unassigned_labor(city: Dictionary) -> int:
	var assigned := 0
	for sink in city.get("labor", {}):
		assigned += int(city.labor[sink])
	return maxi(labor_points(city) - assigned, 0)


## Default assignment for a city: labor.default_growth_share of its labor points on
## Growth (rounded down), nothing on Training or Infrastructure; the rest is left
## unassigned and makes cash. Used for new and AI cities.
func default_labor(city: Dictionary) -> Dictionary:
	var share := float(config.get("labor", {}).get("default_growth_share", 0.0))
	return {"training": 0, "infrastructure": 0, "growth": int(floor(labor_points(city) * share))}


## Sum of the points assigned to the three sinks.
func assigned_labor(city: Dictionary) -> int:
	var total := 0
	for sink in SINKS:
		total += int(city.get("labor", {}).get(sink, 0))
	return total


## Gives the city its default assignment if it has none, otherwise clamps the
## existing one to the current labor points. Safe to call any time.
func ensure_labor(city: Dictionary) -> void:
	if not city.has("labor"):
		city.labor = default_labor(city)
		return
	clamp_labor(city)


## Trims the assignment so it never exceeds labor_points (population dropped, e.g.
## after capture or siege). Takes points from the sinks in labor.clamp_order
## (Growth first, then Infrastructure, then Training).
func clamp_labor(city: Dictionary) -> void:
	var excess := assigned_labor(city) - labor_points(city)
	if excess <= 0:
		return
	var order: Array = config.get("labor", {}).get("clamp_order", SINKS)
	for sink in order:
		var take := mini(excess, int(city.labor.get(sink, 0)))
		city.labor[sink] = int(city.labor.get(sink, 0)) - take
		excess -= take
		if excess <= 0:
			break


## Sets one sink to `points`, limited to 0..(its current points + free labor).
## Returns the value actually set.
func set_labor(city: Dictionary, sink: String, points: int) -> int:
	ensure_labor(city)
	var room := int(city.labor[sink]) + unassigned_labor(city)
	city.labor[sink] = clampi(points, 0, room)
	city.erase("labor_auto")
	return int(city.labor[sink])


## Moves one sink by delta points (the panel's -/+ buttons). Returns true if it changed.
func adjust_labor(city: Dictionary, sink: String, delta: int) -> bool:
	ensure_labor(city)
	var before := int(city.labor[sink])
	return set_labor(city, sink, before + delta) != before


## Gives every city a default assignment if it has none and clamps the rest.
func refresh_labor(hex_map: HexMap) -> void:
	for city in hex_map.cities:
		ensure_labor(city)


## Labor-turns one division costs (labor.training_labor_cost).
func training_labor_cost() -> int:
	return int(config.get("labor", {}).get("training_labor_cost", 0))


## Labor-turns of infrastructure per +1 infra level (labor.infra_labor_per_level).
func infra_labor_per_level() -> int:
	return int(config.get("labor", {}).get("infra_labor_per_level", 1 << 30))


## Points the city has on Training / Infrastructure.
func training_points(city: Dictionary) -> int:
	return int(city.get("labor", {}).get("training", 0))


func infra_points(city: Dictionary) -> int:
	return int(city.get("labor", {}).get("infrastructure", 0))


## When a recruit is queued in a city with nothing on Training, moves
## labor.recruit_auto_training_share of its labor points to Training (from Growth,
## keeping Infrastructure). The city is flagged labor_auto so end_auto_training can
## put the default split back when the queue clears. Any manual change drops the flag.
func auto_training(city: Dictionary) -> void:
	ensure_labor(city)
	if training_points(city) > 0:
		return
	var share := float(config.get("labor", {}).get("recruit_auto_training_share", 0.0))
	var room := labor_points(city) - infra_points(city)
	var train := clampi(int(floor(labor_points(city) * share)), 0, maxi(room, 0))
	city.labor.training = train
	city.labor.growth = mini(int(city.labor.growth), maxi(room - train, 0))
	city.labor_auto = true


## Undoes auto_training: Training back to 0 and Growth to its default, Infrastructure kept.
func end_auto_training(city: Dictionary) -> void:
	if not city.get("labor_auto", false):
		return
	city.erase("labor_auto")
	if not city.has("labor"):
		return
	city.labor.training = 0
	city.labor.growth = mini(int(default_labor(city).growth), maxi(labor_points(city) - infra_points(city), 0))


## Infrastructure sink: each city adds its Infrastructure points to city.infra_progress;
## every infra_labor_per_level labor-turns raises infrastructure by 1 (leftover carries
## over), which raises the housing cap. During a capture rebuild the levels repair the
## damage first (see HexMap._rebuild_step).
func apply_infrastructure(hex_map: HexMap) -> void:
	var per_level := infra_labor_per_level()
	for city in hex_map.cities:
		var progress := int(city.get("infra_progress", 0)) + infra_points(city)
		while progress >= per_level:
			progress -= per_level
			city.infrastructure = float(city.infrastructure) + 1.0
		city.infra_progress = progress


## Labor totals for a nation: {"total", "training", "infrastructure", "growth", "free"}.
func labor_totals(nation: int, hex_map: HexMap) -> Dictionary:
	var t := {"total": 0, "training": 0, "infrastructure": 0, "growth": 0, "free": 0}
	for city in hex_map.cities:
		if city.nation != nation:
			continue
		t.total += labor_points(city)
		for sink in SINKS:
			t[sink] += int(city.get("labor", {}).get(sink, 0))
		t.free += unassigned_labor(city)
	return t


## Per-turn output of one city: {"cash", "capacity"}. Cash is
## cash_per_unassigned_labor for each unassigned labor point.
func city_income(city: Dictionary) -> Dictionary:
	return {
		"cash": float(unassigned_labor(city)) * float(config.cash_per_unassigned_labor),
		"capacity": float(city.infrastructure) * float(config.capacity_per_infra),
	}


## Adds city income plus the flat influence and operations to every living nation.
func collect_income(hex_map: HexMap) -> void:
	for nation in hex_map.nations:
		var s: Dictionary = stocks[nation]
		s.influence += float(config.influence_per_turn)
		s.operations += float(config.operations_per_turn)
	for city in hex_map.cities:
		if not hex_map.nations.has(city.nation):
			continue
		var income := city_income(city)
		for r in income:
			stocks[city.nation][r] += income[r]


## Total upkeep a nation owes this turn: {"cash", "capacity"}.
func upkeep_due(nation: int, roster: DivisionRoster) -> Dictionary:
	var count := 0
	for d in roster.divisions:
		if d.nation == nation:
			count += 1
	var due := {}
	for r in config.upkeep_per_division:
		due[r] = count * float(config.upkeep_per_division[r])
	return due


## Each nation pays upkeep in full, or pays nothing and all its divisions lose
## unpaid_upkeep_org_loss org (clamped at 0, no retreat).
func pay_upkeep(hex_map: HexMap, roster: DivisionRoster) -> void:
	for nation in hex_map.nations:
		var due := upkeep_due(nation, roster)
		var s: Dictionary = stocks[nation]
		var can_pay := true
		for r in due:
			if s[r] < due[r]:
				can_pay = false
		upkeep_paid[nation] = can_pay
		if can_pay:
			for r in due:
				s[r] -= due[r]
		else:
			var loss := float(config.unpaid_upkeep_org_loss)
			for d in roster.divisions:
				if d.nation == nation:
					d.org = maxf(d.org - loss, 0.0)


## Why the city cannot recruit for nation, or "" if it can.
func recruit_block_reason(city: Dictionary, nation: int, roster: DivisionRoster) -> String:
	if city.is_empty() or city.nation != nation:
		return "not your city"
	if pending.has(city.id):
		return "already recruiting"
	if roster.division_at(city.cell) != null:
		return "city hex occupied"
	var people_cost := int(city_rules.division_people_cost)
	if int(city.get("pool", 0)) < people_cost:
		return "recruit pool too small"
	if int(city.population) - people_cost < int(city_rules.train_min_city_pop):
		return "city too small to train"
	var s: Dictionary = stocks[nation]
	for r in config.recruit_cost:
		if s[r] < float(config.recruit_cost[r]):
			return "not enough " + r
	return ""


## Pays the cost, draws division_people_cost people from the city's pool (they leave its
## population and labor too, and are not refunded if the recruit is lost), and queues a
## division that appears after training_turns. Returns false if blocked.
func recruit(city: Dictionary, nation: int, roster: DivisionRoster) -> bool:
	if recruit_block_reason(city, nation, roster) != "":
		return false
	for r in config.recruit_cost:
		stocks[nation][r] -= float(config.recruit_cost[r])
	city.pool = int(city.pool) - int(city_rules.division_people_cost)
	city.population = int(city.population) - int(city_rules.division_people_cost)
	pending[city.id] = {"nation": nation, "turns_left": int(config.training_turns), "labor": 0, "cost": training_labor_cost()}
	auto_training(city)
	return true


## Ticks training. A trained recruit spawns on its city hex, or waits there if
## the hex is occupied. If the city changed owner, the recruit is lost.
func spawn_pending(hex_map: HexMap, roster: DivisionRoster) -> void:
	var ids := pending.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = pending[id]
		var city := {}
		for c in hex_map.cities:
			if c.id == id:
				city = c
		if city.is_empty() or city.nation != entry.nation:
			pending.erase(id)
			if not city.is_empty():
				end_auto_training(city)
			continue
		entry.turns_left = maxi(entry.turns_left - 1, 0)
		entry.labor = mini(int(entry.get("labor", 0)) + training_points(city), training_labor_cost())
		if entry.turns_left == 0 and entry.labor >= training_labor_cost() and roster.division_at(city.cell) == null:
			roster.spawn_division(entry.nation, city.cell, config.recruit_template, int(city.id))
			pending.erase(id)
			end_auto_training(city)


## Queue text for one pending recruit, e.g. "Division 9/15 labor, 2 turns left".
## The labor cost comes from the entry, so no config is needed here.
static func queue_text(entry: Dictionary) -> String:
	var labor := "Division %d/%d labor, " % [int(entry.get("labor", 0)), int(entry.get("cost", 0))] if entry.has("cost") else ""
	if entry.turns_left <= 0 and int(entry.get("labor", 0)) >= int(entry.get("cost", 0)):
		return labor + "ready, waiting for hex to clear"
	if entry.turns_left <= 0:
		return labor + "needs more Training labor"
	return labor + "%d turn%s left" % [entry.turns_left, "" if entry.turns_left == 1 else "s"]


func division_count(nation: int, roster: DivisionRoster) -> int:
	var count := 0
	for d in roster.divisions:
		if d.nation == nation:
			count += 1
	for id in pending:
		if pending[id].nation == nation:
			count += 1
	return count


## Each AI city that can recruit does so with ai_recruit_chance, using roster.rng,
## while the nation has fewer than ai_max_divisions (fielded plus in training).
func run_ai(player_nation: int, hex_map: HexMap, roster: DivisionRoster) -> void:
	for city in hex_map.cities:
		if city.nation == player_nation or recruit_block_reason(city, city.nation, roster) != "":
			continue
		if division_count(city.nation, roster) >= int(config.ai_max_divisions):
			continue
		if roster.rng.randf() < float(config.ai_recruit_chance):
			recruit(city, city.nation, roster)


## End-of-turn economy step: income, upkeep, reinforcement, then training ticks
## and recruits appear.
func end_turn(hex_map: HexMap, roster: DivisionRoster) -> void:
	refresh_labor(hex_map)
	collect_income(hex_map)
	pay_upkeep(hex_map, roster)
	reinforce(roster, hex_map)
	apply_infrastructure(hex_map)
	spawn_pending(hex_map, roster)


## Refills supplied divisions below max_strength from city recruit pools, by division id
## ascending. Each gains at most reinforce_cap_per_turn (times reinforce_mult) and only
## what the pools can pay at people_per_strength people per point. The draw comes from
## the division's home city pool first, then the nearest owned cities' pools (distance
## from the home city, ties by id); empty pools are skipped. A draw removes people from
## the pool and the city's population. Out-of-supply divisions get nothing. Sets
## d.last_reinforce and reinforce_spent (people).
## Cap multiplier for d: lowest of territory (own/neutral/enemy) and in_combat;
## 0 out of supply. fought = d was in combat this turn. hex_map null = own territory.
## Shared by reinforce() and the unit panel preview.
func reinforce_mult(d: Division, hex_map: HexMap, fought: bool) -> float:
	if not d.supplied:
		return 0.0
	var m: Dictionary = config.get("reinforce_mult", {})
	var key := "own"
	if hex_map and hex_map.cells.has(d.hex):
		var owner: int = hex_map.cells[d.hex]
		if owner == HexMap.UNCLAIMED:
			key = "neutral"
		elif owner != d.nation:
			key = "enemy"
	var mult := float(m.get(key, 1.0))
	if fought:
		mult = minf(mult, float(m.get("in_combat", 1.0)))
	return mult


## People per strength point (cities_config people_per_strength).
func people_per_strength() -> float:
	return float(city_rules.people_per_strength)


## Plans one reinforcement pass without changing anything. `pools` maps city id to the
## people available (a copy is used). Returns {"gains": {division id: strength},
## "draws": {city id: people}, "spent": {nation: people}}. reinforce() applies it and
## the unit panel previews with next turn's pools. Divisions of one nation only when
## `only_nation` >= 0.
func reinforce_plan(roster: DivisionRoster, hex_map: HexMap, pools: Dictionary,
		only_nation := -1) -> Dictionary:
	var cap := float(config.reinforce_cap_per_turn)
	var rate := people_per_strength()
	var left := pools.duplicate()
	var plan := {"gains": {}, "draws": {}, "spent": {}}
	var order := roster.divisions.duplicate()
	order.sort_custom(func(a, b): return a.id < b.id)
	for d in order:
		if (only_nation >= 0 and d.nation != only_nation) or not d.supplied or d.strength >= d.max_strength:
			continue
		var gain := minf(cap * reinforce_mult(d, hex_map, d.fought_this_turn), d.max_strength - d.strength)
		if gain <= 0.0 or rate <= 0.0:
			continue
		var need := int(ceil(gain * rate - 0.000001))
		var home := hex_map.city_by_id(d.home_city_id)
		var anchor: Vector2i = home.cell if not home.is_empty() and home.nation == d.nation else d.hex
		var sources: Array[Dictionary] = []
		if not home.is_empty() and home.nation == d.nation:
			sources.append(home)
		for c in hex_map.owned_cities_by_distance(d.nation, anchor):
			if c.id != d.home_city_id:
				sources.append(c)
		var taken := {}
		var got := 0
		for c in sources:
			var avail := int(left.get(c.id, 0))
			if avail <= 0:
				continue
			var take := mini(avail, need - got)
			taken[c.id] = take
			got += take
			if got >= need:
				break
		if got <= 0:
			continue
		for id in taken:
			left[id] = int(left[id]) - int(taken[id])
			plan.draws[id] = int(plan.draws.get(id, 0)) + int(taken[id])
		plan.gains[d.id] = minf(gain, float(got) / rate)
		plan.spent[d.nation] = int(plan.spent.get(d.nation, 0)) + got
	return plan


## City id -> pool people for every city (the input of reinforce_plan).
func current_pools(hex_map: HexMap) -> Dictionary:
	var pools := {}
	for c in hex_map.cities:
		pools[c.id] = hex_map.pool_of(c)
	return pools


func reinforce(roster: DivisionRoster, hex_map: HexMap) -> void:
	reinforce_spent.clear()
	var plan := reinforce_plan(roster, hex_map, current_pools(hex_map))
	for d in roster.divisions:
		d.last_reinforce = 0.0
		if plan.gains.has(d.id):
			d.strength += plan.gains[d.id]
			d.last_reinforce = plan.gains[d.id]
	for id in plan.draws:
		hex_map.draw_people(hex_map.city_by_id(id), int(plan.draws[id]))
	for nation in plan.spent:
		reinforce_spent[nation] = float(plan.spent[nation])


## Total recruitable people in a nation's cities.
func recruitable_total(nation: int, hex_map: HexMap) -> int:
	var total := 0
	for c in hex_map.cities:
		if c.nation == nation:
			total += hex_map.pool_of(c)
	return total

# --- POWs ---

## Records surrendered strength as POWs held by captor from owner.
func add_pows(captor: int, owner: int, count: float) -> void:
	if count <= 0.0:
		return
	if not pows.has(captor):
		pows[captor] = {}
	pows[captor][owner] = float(pows[captor].get(owner, 0.0)) + count


## POWs captor holds from all nations.
func pows_held(captor: int) -> float:
	var total := 0.0
	for owner in pows.get(captor, {}):
		total += float(pows[captor][owner])
	return total


## POWs taken from owner by all captors.
func pows_lost(owner: int) -> float:
	var total := 0.0
	for captor in pows:
		total += float(pows[captor].get(owner, 0.0))
	return total


## Returns captor's POWs from owner to owner's population and clears them. The people
## (count x people_per_strength) go to the owner's capital: POWs do not record a home city.
## Not called yet; peace and alliance switching will call it. Works for eliminated nations
## too (their people are lost). Returns the strength returned.
func return_pows(captor: int, owner: int, hex_map: HexMap) -> float:
	if not pows.has(captor) or not pows[captor].has(owner):
		return 0.0
	var count: float = pows[captor][owner]
	pows[captor].erase(owner)
	if pows[captor].is_empty():
		pows.erase(captor)
	var capital := hex_map.capital_of(owner)
	if not capital.is_empty():
		hex_map.return_people(owner, int(capital.id), capital.cell, int(floor(count * people_per_strength())))
	return count
