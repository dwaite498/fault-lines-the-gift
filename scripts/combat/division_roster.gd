class_name DivisionRoster
extends RefCounted
## Holds all divisions and the rules for moving, attacking, fortifying,
## capturing cities, and the placeholder AI. Every random roll uses rng,
## seeded from the map seed, so the same seed and actions give the same results.

const CONFIG_PATH := "res://data/divisions_config.json"
const COMBAT_CONFIG_PATH := "res://data/combat_config.json"

var divisions: Array[Division] = []
var templates: Dictionary = {}
var combat: Dictionary = {}
var rng := RandomNumberGenerator.new()
## Set by main so surrenders can charge manpower. Optional.
var economy: NationEconomy = null


static func load_templates(path := CONFIG_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Puts one division of template_name on every city hex, owned by that city's nation.
func spawn_at_cities(hex_map: HexMap, template_name := "infantry") -> void:
	if templates.is_empty():
		templates = load_templates()
	if combat.is_empty():
		combat = load_templates(COMBAT_CONFIG_PATH)
	rng.seed = hex_map.seed_value
	divisions.clear()
	for city in hex_map.cities:
		divisions.append(Division.from_template(divisions.size(), city.nation,
				city.cell, templates[template_name]))


## Adds one new division of template_name on hex with a fresh id.
func spawn_division(nation: int, hex: Vector2i, template_name := "infantry") -> Division:
	var next_id := 0
	for d in divisions:
		next_id = maxi(next_id, d.id + 1)
	var d := Division.from_template(next_id, nation, hex, templates[template_name])
	divisions.append(d)
	return d


func division_at(hex: Vector2i) -> Division:
	for d in divisions:
		if d.hex == hex:
			return d
	return null


# --- Move ---

## True if hex is an adjacent, unoccupied, passable hex and d can pay its
## move_cost. The first step of a turn is always allowed (1-hex minimum).
func can_move(d: Division, hex: Vector2i, hex_map: HexMap) -> bool:
	if d.moves_left <= 0 or not hex in hex_map.neighbors(d.hex) or division_at(hex) != null:
		return false
	var terrain := hex_map.terrain_of(hex)
	if not terrain.passable:
		return false
	return d.moves_left >= int(terrain.move_cost) or not d.has_moved


## Moves d one hex; moving onto an enemy city captures it.
func try_move(d: Division, hex: Vector2i, hex_map: HexMap) -> bool:
	if not can_move(d, hex, hex_map):
		return false
	d.hex = hex
	d.moves_left = maxi(d.moves_left - int(hex_map.terrain_of(hex).move_cost), 0)
	d.has_moved = true
	d.fortify_level = 0
	var city := hex_map.city_at(hex)
	if not city.is_empty() and city.nation != d.nation:
		var eliminated := hex_map.capture_city(hex, d.nation)
		disband(eliminated)
		print("Nation %d captured a city at %s; eliminated: %s" % [d.nation, hex, eliminated])
	return true


## Removes every division of the given nations.
func disband(nations: Array[int]) -> void:
	divisions.assign(divisions.filter(func(d): return not nations.has(d.nation)))


# --- Fortify ---

func fortify(d: Division) -> bool:
	if d.moves_left <= 0 or d.has_moved:
		return false
	d.fortify_level = mini(d.fortify_level + 1, int(combat.max_fortify))
	d.moves_left = 0
	return true


# --- Attack ---

func can_attack(attacker: Division, defender: Division, hex_map: HexMap) -> bool:
	return (attacker.moves_left > 0 and not attacker.has_moved and defender != null
			and defender.nation != attacker.nation
			and defender.hex in hex_map.neighbors(attacker.hex))


## The defender's effective defense: defense * terrain_mult * fortify * city bonus.
func defense_of(defender: Division, hex_map: HexMap) -> float:
	var fort_mult: float = 1.0 + float(combat.fortify_bonus_per_level) * defender.fortify_level
	var terrain_mult: float = hex_map.terrain_of(defender.hex).defense_mult
	var city_mult: float = float(combat.city_defense_mult) if not hex_map.city_at(defender.hex).is_empty() else 1.0
	return defender.defense * terrain_mult * fort_mult * city_mult


## Damage one side deals: base_dmg * (attack / other_defense) * rand(roll_min..roll_max).
func roll_damage(attack_value: float, other_defense: float) -> float:
	return (float(combat.base_dmg) * (attack_value / other_defense)
			* rng.randf_range(float(combat.roll_min), float(combat.roll_max)))


## Grind resolution: both sides deal damage each attack (attacker's roll first).
## The attacker's own defense is its plain defense stat (no terrain, fortify or
## city bonus). The attacker never moves in. Returns both damages and outcomes,
## or {} if not allowed.
func attack(attacker: Division, defender: Division, hex_map: HexMap) -> Dictionary:
	if not can_attack(attacker, defender, hex_map):
		return {}
	var def_defense := defense_of(defender, hex_map)
	var atk_defense := attacker.defense
	var dmg_to_defender := roll_damage(attacker.attack, def_defense)
	var dmg_to_attacker := roll_damage(defender.attack, atk_defense)
	var taken_by_defender := _damage(defender, dmg_to_defender)
	var taken_by_attacker := _damage(attacker, dmg_to_attacker)
	attacker.moves_left = 0
	attacker.fortify_level = 0
	attacker.in_combat = true
	defender.in_combat = true
	return {
		"defender_defense": def_defense, "attacker_defense": atk_defense,
		"damage_to_defender": dmg_to_defender, "damage_to_attacker": dmg_to_attacker,
		"defender_org_loss": taken_by_defender.org, "defender_strength_loss": taken_by_defender.strength,
		"attacker_org_loss": taken_by_attacker.org, "attacker_strength_loss": taken_by_attacker.strength,
		"attacker_outcome": _after_combat(attacker, hex_map),
		"defender_outcome": _after_combat(defender, hex_map),
	}


## Applies raw damage scaled by morale (* (morale_offset - morale)), split between
## org and strength. Returns the {"org", "strength"} amounts applied before clamping.
func _damage(d: Division, raw: float) -> Dictionary:
	var scaled: float = raw * maxf(float(combat.morale_offset) - d.morale, 0.0)
	var org_dmg: float = scaled * float(combat.org_damage_share)
	var str_dmg: float = scaled * (1.0 - float(combat.org_damage_share))
	d.org = maxf(d.org - org_dmg, 0.0)
	d.strength = maxf(d.strength - str_dmg, 0.0)
	return {"org": org_dmg, "strength": str_dmg}


## Strength 0: destroyed. Org 0: retreat 1 hex to a free friendly or neutral
## land hex. If boxed in, it surrenders: removed, and its nation loses
## manpower = strength * surrender_manpower_factor (never below 0).
## Returns "destroyed", "retreated", "surrendered", or "held".
func _after_combat(d: Division, hex_map: HexMap) -> String:
	if d.strength <= 0.0:
		divisions.erase(d)
		return "destroyed"
	if d.org > 0.0:
		return "held"
	for n in hex_map.neighbors(d.hex):
		var owner: int = hex_map.cells[n]
		if ((owner == d.nation or owner == HexMap.UNCLAIMED) and division_at(n) == null
				and hex_map.terrain_of(n).passable):
			d.hex = n
			d.fortify_level = 0
			return "retreated"
	divisions.erase(d)
	if economy and economy.stocks.has(d.nation):
		var stock: Dictionary = economy.stocks[d.nation]
		stock.manpower = maxf(float(stock.manpower) - d.strength * float(combat.surrender_manpower_factor), 0.0)
	return "surrendered"

# --- Turn ---

## Placeholder AI for every nation except player_nation: attack a random adjacent
## enemy if possible, otherwise move randomly or fortify.
func run_ai(player_nation: int, hex_map: HexMap) -> void:
	for d in divisions.duplicate():
		if d.nation == player_nation or not divisions.has(d) or d.moves_left <= 0:
			continue
		var enemies: Array[Division] = []
		var free: Array[Vector2i] = []
		for n in hex_map.neighbors(d.hex):
			var other := division_at(n)
			if other and other.nation != d.nation:
				enemies.append(other)
			elif can_move(d, n, hex_map):
				free.append(n)
		if not enemies.is_empty():
			attack(d, enemies[rng.randi_range(0, enemies.size() - 1)], hex_map)
		elif not free.is_empty() and rng.randf() < 0.7:
			try_move(d, free[rng.randi_range(0, free.size() - 1)], hex_map)
		else:
			fortify(d)


## Recovers org (morale * rate) for divisions not in combat, then resets actions.
func end_turn() -> void:
	var rate: float = combat.org_recovery_per_morale
	for d in divisions:
		if not d.in_combat:
			d.org = minf(d.org + d.morale * rate, d.max_org)
		d.in_combat = false
		d.moves_left = d.move
		d.has_moved = false