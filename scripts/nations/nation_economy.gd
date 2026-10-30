class_name NationEconomy
extends RefCounted
## Per-nation resource stocks, per-turn city income, division upkeep, and the
## recruit training queue. All numbers come from data/resources_config.json.

const CONFIG_PATH := "res://data/resources_config.json"
const RESOURCES: Array[String] = ["cash", "influence", "operations", "manpower", "capacity"]

var config: Dictionary = {}
## nation index -> {"cash": float, "influence": ..., ...}
var stocks: Dictionary = {}
## city id -> {"nation": int, "turns_left": int}. One pending recruit per city.
## turns_left 0 means trained and waiting for the city hex to be free.
var pending: Dictionary = {}
## nation index -> true if that nation paid its upkeep on the last end_turn.
var upkeep_paid: Dictionary = {}


func _init(path := CONFIG_PATH) -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(path))


func setup(hex_map: HexMap) -> void:
	stocks.clear()
	pending.clear()
	upkeep_paid.clear()
	for nation in hex_map.nations:
		stocks[nation] = {}
		upkeep_paid[nation] = true
		for r in RESOURCES:
			stocks[nation][r] = float(config.start_stock.get(r, 0))


## Per-turn output of one city: {"cash", "manpower", "capacity"}.
func city_income(city: Dictionary) -> Dictionary:
	return {
		"cash": float(city.population) * float(config.cash_per_pop),
		"manpower": float(city.population) * float(config.manpower_per_pop),
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
	var s: Dictionary = stocks[nation]
	for r in config.recruit_cost:
		if s[r] < float(config.recruit_cost[r]):
			return "not enough " + r
	return ""


## Pays the cost and queues a division that appears after training_turns. Returns false if blocked.
func recruit(city: Dictionary, nation: int, roster: DivisionRoster) -> bool:
	if recruit_block_reason(city, nation, roster) != "":
		return false
	for r in config.recruit_cost:
		stocks[nation][r] -= float(config.recruit_cost[r])
	pending[city.id] = {"nation": nation, "turns_left": int(config.training_turns)}
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
			continue
		entry.turns_left = maxi(entry.turns_left - 1, 0)
		if entry.turns_left == 0 and roster.division_at(city.cell) == null:
			roster.spawn_division(entry.nation, city.cell, config.recruit_template)
			pending.erase(id)


## Queue text for one pending recruit, e.g. "2 turns left".
static func queue_text(entry: Dictionary) -> String:
	if entry.turns_left <= 0:
		return "ready, waiting for hex to clear"
	return "%d turn%s left" % [entry.turns_left, "" if entry.turns_left == 1 else "s"]


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


## End-of-turn economy step: income, upkeep, then training ticks and recruits appear.
func end_turn(hex_map: HexMap, roster: DivisionRoster) -> void:
	collect_income(hex_map)
	pay_upkeep(hex_map, roster)
	spawn_pending(hex_map, roster)