class_name NationEconomy
extends RefCounted
## Per-nation resource stocks, per-turn city income, and pending recruits.
## All numbers come from data/resources_config.json.

const CONFIG_PATH := "res://data/resources_config.json"
const RESOURCES: Array[String] = ["cash", "influence", "operations", "manpower", "capacity"]

var config: Dictionary = {}
## nation index -> {"cash": float, "influence": ..., ...}
var stocks: Dictionary = {}
## city id -> nation that paid for the recruit. One pending recruit per city.
var pending: Dictionary = {}


func _init(path := CONFIG_PATH) -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(path))


func setup(hex_map: HexMap) -> void:
	stocks.clear()
	pending.clear()
	for nation in hex_map.nations:
		stocks[nation] = {}
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


## Pays the cost and queues a division for next turn. Returns false if blocked.
func recruit(city: Dictionary, nation: int, roster: DivisionRoster) -> bool:
	if recruit_block_reason(city, nation, roster) != "":
		return false
	_pay(nation, -1.0)
	pending[city.id] = nation
	return true


func _pay(nation: int, direction: float) -> void:
	if not stocks.has(nation):
		return
	for r in config.recruit_cost:
		stocks[nation][r] += direction * float(config.recruit_cost[r])


## Spawns pending recruits. If the city changed owner or its hex is occupied,
## the recruit is cancelled and the cost refunded.
func spawn_pending(hex_map: HexMap, roster: DivisionRoster) -> void:
	var ids := pending.keys()
	ids.sort()
	for id in ids:
		var nation: int = pending[id]
		var city := {}
		for c in hex_map.cities:
			if c.id == id:
				city = c
		if city.is_empty() or city.nation != nation or roster.division_at(city.cell) != null:
			_pay(nation, 1.0)
		else:
			roster.spawn_division(nation, city.cell, config.recruit_template)
	pending.clear()


## Each AI city that can recruit does so with ai_recruit_chance, using roster.rng.
func run_ai(player_nation: int, hex_map: HexMap, roster: DivisionRoster) -> void:
	for city in hex_map.cities:
		if city.nation == player_nation or recruit_block_reason(city, city.nation, roster) != "":
			continue
		if roster.rng.randf() < float(config.ai_recruit_chance):
			recruit(city, city.nation, roster)


## End-of-turn economy step: income, then last turn's recruits appear.
func end_turn(hex_map: HexMap, roster: DivisionRoster) -> void:
	collect_income(hex_map)
	spawn_pending(hex_map, roster)