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
## nation index -> ids of divisions whose upkeep could not be paid on the last end_turn.
var unpaid_divisions: Dictionary = {}
## POWs: captor nation -> {owner nation -> count (float)}. Kept after elimination.
var pows: Dictionary = {}
## nation index -> people drawn from pools for reinforcement on the last end_turn.
var reinforce_spent: Dictionary = {}
## nation -> labor points rushed with cash this turn (Syndicate rush-buy; reset each end turn).
var rush_spent: Dictionary = {}
## The map this economy was set up on (faction traits and city ranks read it).
var _map: HexMap = null


func _init(path := CONFIG_PATH) -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(path))
	city_rules = JSON.parse_string(FileAccess.get_file_as_string(CITIES_CONFIG_PATH))


func setup(hex_map: HexMap) -> void:
	_map = hex_map
	rush_spent.clear()
	city_rules = hex_map.city_rules
	stocks.clear()
	pending.clear()
	upkeep_paid.clear()
	unpaid_divisions.clear()
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
	if _map != null:
		return _map.labor_points(city)  # includes the faction trait labor bonuses
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
	if city.get("enslaved", false):
		city.labor.training = 0
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
	if sink == "training" and city.get("enslaved", false):
		room = 0  # an enslaved city's labor cannot go to Training
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
## A faction's infra_cost_labor trait replaces it for that nation.
func infra_labor_per_level(nation := -1) -> int:
	var base := int(config.get("labor", {}).get("infra_labor_per_level", 1 << 30))
	if _map != null and nation >= 0:
		return int(_map.traits.mod(nation, "infra_cost_labor", base))
	return base


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
	if city.get("enslaved", false):
		return
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
	for city in hex_map.cities:
		var per_level := infra_labor_per_level(int(city.nation))
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
		s.cash += cash_income(nation, hex_map)
	for city in hex_map.cities:
		if not hex_map.nations.has(city.nation):
			continue
		var income := city_income(city)
		for r in income:
			if r != "cash":  # cash goes through cash_income (faction cash traits)
				stocks[city.nation][r] += income[r]


## Total upkeep a nation owes this turn, summed over its divisions' types, e.g. {"cash": 6}.
func upkeep_due(nation: int, roster: DivisionRoster) -> Dictionary:
	var due := {}
	for d in roster.divisions:
		if d.nation == nation:
			var each := roster.upkeep_of(d)
			for r in each:
				due[r] = float(due.get(r, 0.0)) + float(each[r])
	return due


## Pays upkeep division by division (id order) from the nation's stocks. A division whose
## upkeep the stock cannot cover is UNPAID: nothing is deducted for it (so cash is
## clamped at 0 and never goes negative) and it loses unpaid_upkeep_org_loss org this turn
## (clamped at 0, no retreat). Unpaid division ids are listed in unpaid_divisions and
## logged; upkeep_paid is false for a nation with any unpaid division.
func pay_upkeep(hex_map: HexMap, roster: DivisionRoster) -> void:
	unpaid_divisions.clear()
	var loss := float(config.unpaid_upkeep_org_loss)
	var order := roster.divisions.duplicate()
	order.sort_custom(func(a, b): return a.id < b.id)
	for nation in hex_map.nations:
		var s: Dictionary = stocks[nation]
		var unpaid: Array[int] = []
		for d in order:
			if d.nation != nation:
				continue
			var cost := roster.upkeep_of(d)
			var can_pay := true
			for r in cost:
				if float(s.get(r, 0.0)) < float(cost[r]):
					can_pay = false
			if can_pay:
				for r in cost:
					s[r] = float(s[r]) - float(cost[r])
			else:
				unpaid.append(d.id)
				d.org = maxf(d.org - loss, 0.0)
		upkeep_paid[nation] = unpaid.is_empty()
		if not unpaid.is_empty():
			unpaid_divisions[nation] = unpaid
			print("Nation %d could not pay upkeep for divisions %s: they lose %d org" % [nation, unpaid, int(loss)])


## Why training is blocked in the city ("besieged", "starving", "enslaved", "occupied",
## "locked out after annexation"), or "".
## "starving" reads city.starving, a hook for the Food resource (nothing sets it yet);
## "enslaved" reads city.enslaved and "occupied" city.occupied (set by the Enslave and
## Occupy capture choices); the lockout reads city.recruit_lockout, the turns left after
## an Annex (CAPTURE.md).
func training_blocked(city: Dictionary) -> String:
	if city.get("besieged", false):
		return "besieged"
	if city.get("starving", false):
		return "starving"
	if city.get("enslaved", false):
		return "enslaved"
	if city.get("occupied", false):
		return "occupied"
	if int(city.get("recruit_lockout", 0)) > 0:
		return "locked out after annexation"
	return ""


## Why the city cannot recruit for nation, or "" if it can.
func recruit_block_reason(city: Dictionary, nation: int, roster: DivisionRoster) -> String:
	if city.is_empty() or city.nation != nation:
		return "not your city"
	if pending.has(city.id):
		return "already recruiting"
	if roster.division_at(city.cell) != null:
		return "city hex occupied"
	var blocked := training_blocked(city)
	if blocked != "":
		return "cannot train: city is %s" % blocked
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


# --- Rush-buy (Syndicate trait; Task 41) ---

## Why the city's queue cannot be rushed with cash, or "" if it can: the nation's faction
## needs rush_cost_per_labor, the city a queued recruit that still needs labor, the nation
## rush_cap_per_turn labor points left this turn (nation-wide) and enough cash.
func rush_block_reason(city: Dictionary, nation: int) -> String:
	if _map == null or not _map.traits.has_trait(nation, "rush_cost_per_labor"):
		return "no rush-buy"
	if city.is_empty() or city.nation != nation:
		return "not your city"
	if not pending.has(city.id) or int(pending[city.id].labor) >= int(pending[city.id].cost):
		return "nothing to rush"
	if int(rush_spent.get(nation, 0)) >= int(_map.traits.mod(nation, "rush_cap_per_turn", 0)):
		return "rush cap reached"
	if float(stocks[nation].cash) < float(_map.traits.mod(nation, "rush_cost_per_labor")):
		return "not enough cash"
	return ""


## Rushes 1 labor point into the city's queue for rush_cost_per_labor cash. False if blocked.
func rush_training(city: Dictionary, nation: int) -> bool:
	if rush_block_reason(city, nation) != "":
		return false
	stocks[nation].cash = float(stocks[nation].cash) - float(_map.traits.mod(nation, "rush_cost_per_labor"))
	pending[city.id].labor = int(pending[city.id].labor) + 1
	rush_spent[nation] = int(rush_spent.get(nation, 0)) + 1
	return true


# --- Scouts (Task 40g) ---

const SCOUT_KIND := "scout"


## divisions_config.json scout "recruit": {"people", "labor_turns", "ai_count"}.
func scout_rules(roster: DivisionRoster) -> Dictionary:
	return roster.templates.scout.recruit


## Why the city cannot queue a scout for nation, or "" if it can. Like a division: one queue
## per city, no training while besieged and so on, people from the recruit pool, and the city
## keeps train_min_city_pop. Unlike a division it costs no capacity.
func scout_block_reason(city: Dictionary, nation: int, roster: DivisionRoster) -> String:
	if city.is_empty() or city.nation != nation:
		return "not your city"
	if pending.has(city.id):
		return "already recruiting"
	if roster.division_at(city.cell) != null:
		return "city hex occupied"
	var blocked := training_blocked(city)
	if blocked != "":
		return "cannot train: city is %s" % blocked
	var people := int(scout_rules(roster).people)
	if int(city.get("pool", 0)) < people:
		return "recruit pool too small"
	if int(city.population) - people < int(city_rules.train_min_city_pop):
		return "city too small to train"
	return ""


## Queues a scout: draws its people from the city's pool and population now (not refunded),
## then it needs labor_turns of Training labor. Returns false if blocked.
func queue_scout(city: Dictionary, nation: int, roster: DivisionRoster) -> bool:
	if scout_block_reason(city, nation, roster) != "":
		return false
	var rules := scout_rules(roster)
	city.pool = int(city.pool) - int(rules.people)
	city.population = int(city.population) - int(rules.people)
	pending[city.id] = {"nation": nation, "kind": SCOUT_KIND, "turns_left": 0, "labor": 0, "cost": int(rules.labor_turns)}
	auto_training(city)
	return true


## Scouts nation has fielded or queued.
func scout_count(nation: int, roster: DivisionRoster) -> int:
	var count := 0
	for d in roster.divisions:
		if d.nation == nation and d.unit_type == SCOUT_KIND:
			count += 1
	for id in pending:
		if pending[id].nation == nation and pending[id].get("kind", "") == SCOUT_KIND:
			count += 1
	return count


# --- Colony pods (Task 40e) ---

const POD_KIND := "colony_pod"


## colonization rules from cities_config.json.
func colony_rules() -> Dictionary:
	return city_rules.colonization


## Why the city cannot queue a colony pod for nation, or "" if it can. A pod shares the
## city's one training queue, needs no cash or capacity, and may be queued while a division
## stands on the city hex (it waits to appear). The city must keep colonization.min_remaining_population people.
func colony_block_reason(city: Dictionary, nation: int) -> String:
	if city.is_empty() or city.nation != nation:
		return "not your city"
	if pending.has(city.id):
		return "already recruiting"
	var blocked := training_blocked(city)
	if blocked != "":
		return "cannot train: city is %s" % blocked
	var rules := colony_rules()
	if int(city.population) - int(rules.population_cost) < int(rules.min_remaining_population):
		return "city needs %d people left" % int(rules.min_remaining_population)
	return ""


## Queues a colony pod: draws colonization.population_cost people from the city's population
## now (not refunded), then it needs colonization.labor_turns labor-turns of Training before it
## appears on the city hex. Returns false if blocked.
func queue_colony_pod(city: Dictionary, nation: int) -> bool:
	if colony_block_reason(city, nation) != "":
		return false
	var rules := colony_rules()
	city.population = int(city.population) - int(rules.population_cost)
	city.pool = mini(int(city.get("pool", 0)), int(floor(float(city.population) * float(city_rules.pool_cap))))
	pending[city.id] = {"nation": nation, "kind": POD_KIND, "turns_left": 0, "labor": 0, "cost": int(rules.labor_turns)}
	auto_training(city)
	return true


## Colony pods nation has fielded or queued.
func pod_count(nation: int, roster: DivisionRoster) -> int:
	var count := 0
	for d in roster.divisions:
		if d.nation == nation and roster.is_colonizer(d):
			count += 1
	for id in pending:
		if pending[id].nation == nation and pending[id].get("kind", "") == POD_KIND:
			count += 1
	return count


## True if the AI should queue a pod in this city: pods are on for the AI, the nation has
## fewer than ai_max_pods, a valid site exists, and the city can spare the people.
func ai_wants_pod(city: Dictionary, hex_map: HexMap, roster: DivisionRoster) -> bool:
	var rules := colony_rules()
	if not bool(rules.ai_build_pods) or colony_block_reason(city, city.nation) != "":
		return false
	if pod_count(city.nation, roster) >= int(rules.ai_max_pods):
		return false
	return not hex_map.colony_sites(city.nation).is_empty()


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
		# No training progress while besieged, starving, enslaved, occupied or locked out: the queue waits.
		if training_blocked(city) != "":
			continue
		entry.turns_left = maxi(entry.turns_left - 1, 0)
		var cost := int(entry.get("cost", training_labor_cost()))
		entry.labor = mini(int(entry.get("labor", 0)) + training_points(city), cost)
		if entry.turns_left == 0 and entry.labor >= cost and roster.division_at(city.cell) == null:
			var kind: String = entry.get("kind", "")
			var template: String = kind if kind == POD_KIND or kind == SCOUT_KIND else str(config.recruit_template)
			roster.spawn_division(entry.nation, city.cell, template, int(city.id))
			pending.erase(id)
			end_auto_training(city)


## True if the city has a recruit queued, no Training labor to feed it, and the recruit
## still needs labor (the queue cannot progress until the player assigns Training).
func recruit_stalled(city: Dictionary) -> bool:
	if not pending.has(city.id):
		return false
	var entry: Dictionary = pending[city.id]
	if training_blocked(city) != "":
		return false  # paused, not stalled
	return training_points(city) <= 0 and int(entry.get("labor", 0)) < int(entry.get("cost", 0))


## Ids of the cities of `nation` whose recruit is stalled (see recruit_stalled).
func stalled_cities(nation: int, hex_map: HexMap) -> Array[int]:
	var ids: Array[int] = []
	for c in hex_map.cities:
		if c.nation == nation and recruit_stalled(c):
			ids.append(int(c.id))
	return ids


## Queue text for one pending recruit, e.g. "Division 9/15 labor, 2 turns left".
## The labor cost comes from the entry, so no config is needed here.
static func queue_text(entry: Dictionary) -> String:
	var what: String = {POD_KIND: "Colony pod", SCOUT_KIND: "Scout"}.get(entry.get("kind", ""), "Division")
	var labor := "%s %d/%d labor, " % [what, int(entry.get("labor", 0)), int(entry.get("cost", 0))] if entry.has("cost") else ""
	if entry.turns_left <= 0 and int(entry.get("labor", 0)) >= int(entry.get("cost", 0)):
		return labor + "ready, waiting for hex to clear"
	if entry.turns_left <= 0:
		return labor + "needs more Training labor"
	return labor + "%d turn%s left" % [entry.turns_left, "" if entry.turns_left == 1 else "s"]


func division_count(nation: int, roster: DivisionRoster) -> int:
	var count := 0
	for d in roster.divisions:
		if d.nation == nation and not roster.is_colonizer(d):
			count += 1
	for id in pending:
		if pending[id].nation == nation and pending[id].get("kind", "") != POD_KIND:
			count += 1
	return count


## Cash per turn a nation's cities make (the same city_income the economy collects).
## Faction traits: cash_per_city adds per city (at most flat_bonus_city_cap cities), then
## cash_mult scales the nation's total.
func cash_income(nation: int, hex_map: HexMap) -> float:
	var total := 0.0
	var count := 0
	for city in hex_map.cities:
		if city.nation == nation:
			total += float(city_income(city).cash)
			count += 1
	total += float(hex_map.traits.mod(nation, "cash_per_city", 0.0)) * hex_map.traits.counted_cities(count)
	return total * float(hex_map.traits.mod(nation, "cash_mult", 1.0))


## Cash upkeep per turn of the nation's fielded divisions plus its queued recruits (each at
## the recruit template's upkeep), plus `extra_recruits` more of them.
func projected_cash_upkeep(nation: int, roster: DivisionRoster, extra_recruits := 0) -> float:
	var total: float = float(upkeep_due(nation, roster).get("cash", 0.0))
	var each := float(roster.templates.get(config.recruit_template, {}).get("upkeep", {}).get("cash", 0.0))
	var queued := 0.0
	for id in pending:
		if pending[id].nation != nation:
			continue
		var kind: String = pending[id].get("kind", "")
		if kind == SCOUT_KIND:
			queued += float(roster.templates.scout.get("upkeep", {}).get("cash", 0.0)) / each if each > 0.0 else 0.0
		elif kind != POD_KIND:
			queued += 1.0
	return total + each * (queued + extra_recruits)


## Each AI city that can recruit does so with ai_recruit_chance, using roster.rng,
## while the nation has fewer than ai_max_divisions (fielded plus in training) and the
## upkeep after the new division (fielded, queued and the new one) would not exceed
## its per-turn cash income.
func run_ai(player_nation: int, hex_map: HexMap, roster: DivisionRoster) -> void:
	for city in hex_map.cities.duplicate():
		if city.nation == player_nation:
			continue
		if scout_count(city.nation, roster) < int(scout_rules(roster).ai_count) \
				and scout_block_reason(city, city.nation, roster) == "":
			queue_scout(city, city.nation, roster)  # the AI builds its scout first, to explore
			continue
		if ai_wants_pod(city, hex_map, roster):
			queue_colony_pod(city, city.nation)
			continue
		if recruit_block_reason(city, city.nation, roster) != "":
			continue
		if division_count(city.nation, roster) >= int(config.ai_max_divisions):
			continue
		if projected_cash_upkeep(city.nation, roster, 1) > cash_income(city.nation, hex_map):
			continue
		if roster.rng.randf() < float(config.ai_recruit_chance):
			recruit(city, city.nation, roster)


## End-of-turn economy step: income, upkeep, reinforcement, then training ticks
## and recruits appear.
func end_turn(hex_map: HexMap, roster: DivisionRoster) -> void:
	rush_spent.clear()
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


## Plans one reinforcement pass without changing anything. `pools` maps city id to the
## people available (a copy is used). Returns {"gains": {division id: strength},
## "draws": {city id: people}, "spent": {nation: people}}. reinforce() applies it and
## the unit panel previews with next turn's pools. Divisions of one nation only when
## `only_nation` >= 0.
func reinforce_plan(roster: DivisionRoster, hex_map: HexMap, pools: Dictionary,
		only_nation := -1) -> Dictionary:
	var cap := float(config.reinforce_cap_per_turn)
	var left := pools.duplicate()
	var plan := {"gains": {}, "draws": {}, "spent": {}}
	var order := roster.divisions.duplicate()
	order.sort_custom(func(a, b): return a.id < b.id)
	for d in order:
		if (only_nation >= 0 and d.nation != only_nation) or not d.supplied or d.strength >= d.max_strength \
				or roster.is_colonizer(d):
			continue
		var rate := roster.people_per_strength(d)
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
		pools[c.id] = 0 if c.get("enslaved", false) else hex_map.pool_of(c)
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
## (count x the recruit template's people_per_strength) go to the owner's capital: POWs do
## not record a home city or a division type.
## Not called yet; peace and alliance switching will call it. Works for eliminated nations
## too (their people are lost). Returns the strength returned.
func return_pows(captor: int, owner: int, hex_map: HexMap, roster: DivisionRoster) -> float:
	if not pows.has(captor) or not pows[captor].has(owner):
		return 0.0
	var count: float = pows[captor][owner]
	pows[captor].erase(owner)
	if pows[captor].is_empty():
		pows.erase(captor)
	var capital := hex_map.capital_of(owner)
	if not capital.is_empty():
		hex_map.return_people(owner, int(capital.id), capital.cell, int(floor(count * float(roster.templates.get(config.recruit_template, {}).get("people_per_strength", 10.0)))))
	return count
