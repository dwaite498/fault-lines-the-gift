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
## Optional. When set, surrenders are recorded as POWs (main.gd sets it).
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


## Flank multiplier for a defender hit from hex_count distinct hexes this turn:
## max(floor, 1 - per_hex * (hex_count - 1)).
static func flank_mult_for(hex_count: int, per_hex: float, floor_mult: float) -> float:
	return maxf(floor_mult, 1.0 - per_hex * maxi(hex_count - 1, 0))


func flank_mult(d: Division) -> float:
	return flank_mult_for(d.attacked_from.size(), float(combat.flank_penalty_per_hex), float(combat.flank_min_mult))


## The defender's effective defense: defense * terrain_mult * fortify * city bonus * flank.
func defense_of(defender: Division, hex_map: HexMap) -> float:
	var fort_mult: float = 1.0 + float(combat.fortify_bonus_per_level) * defender.fortify_level
	var terrain_mult: float = hex_map.terrain_of(defender.hex).defense_mult
	var city_mult: float = float(combat.city_defense_mult) if not hex_map.city_at(defender.hex).is_empty() else 1.0
	return defender.defense * terrain_mult * fort_mult * city_mult * flank_mult(defender)


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
	if not defender.attacked_from.has(attacker.hex):
		defender.attacked_from.append(attacker.hex)
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
		"defender_defense": def_defense, "flank_mult": flank_mult(defender), "attacker_defense": atk_defense,
		"damage_to_defender": dmg_to_defender, "damage_to_attacker": dmg_to_attacker,
		"defender_org_loss": taken_by_defender.org, "defender_strength_loss": taken_by_defender.strength,
		"attacker_org_loss": taken_by_attacker.org, "attacker_strength_loss": taken_by_attacker.strength,
		"attacker_outcome": _after_combat(attacker, hex_map, defender.nation),
		"defender_outcome": _after_combat(defender, hex_map, attacker.nation),
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
## land hex. If boxed in, it surrenders and is removed.
## Returns "destroyed", "retreated", "surrendered", or "held".
func _after_combat(d: Division, hex_map: HexMap, captor: int) -> String:
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
	if economy:
		economy.add_pows(captor, d.nation, d.strength)
	return "surrendered"

# --- Orders ---

## Stores an order for d toward dest instead of acting now. An adjacent enemy is
## an attack order; otherwise a move along the shortest free path d can afford
## this turn. Returns false (order unchanged) if dest is unreachable.
func set_order(d: Division, dest: Vector2i, hex_map: HexMap) -> bool:
	var target := division_at(dest)
	if target and can_attack(d, target, hex_map):
		d.order_path.assign([dest])
		d.order_attack = true
		return true
	var path := plan_path(d, dest, hex_map)
	if path.is_empty():
		return false
	d.order_path.assign(path)
	d.order_attack = false
	return true


func clear_order(d: Division) -> void:
	d.order_path.clear()
	d.order_attack = false


## Shortest path (by steps, BFS) from d.hex to dest through passable hexes with no
## division, excluding d.hex. Empty if none or if d can't pay for it this turn.
func plan_path(d: Division, dest: Vector2i, hex_map: HexMap) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if dest == d.hex or not hex_map.cells.has(dest):
		return none
	var came := {d.hex: d.hex}
	var queue: Array[Vector2i] = [d.hex]
	while not queue.is_empty() and not came.has(dest):
		var cell: Vector2i = queue.pop_front()
		for n in hex_map.neighbors(cell):
			if came.has(n) or not hex_map.terrain_of(n).passable or division_at(n) != null:
				continue
			came[n] = cell
			queue.append(n)
	if not came.has(dest):
		return none
	var path: Array[Vector2i] = []
	var cur := dest
	while cur != d.hex:
		path.push_front(cur)
		cur = came[cur]
	# Same cost rule as can_move: the first step is always allowed.
	var moves := d.moves_left
	var moved := d.has_moved
	for cell in path:
		var cost := int(hex_map.terrain_of(cell).move_cost)
		if moves <= 0 or (moves < cost and moved):
			return none
		moves = maxi(moves - cost, 0)
		moved = true
	return path


## Executes every pending order, by nation then division id. Each step uses the
## normal move/attack rules; an order stops at the first step that fails (e.g. the
## hex became occupied). All orders are cleared afterwards.
func execute_orders(hex_map: HexMap) -> void:
	var order := divisions.duplicate()
	order.sort_custom(func(a, b): return a.nation < b.nation or (a.nation == b.nation and a.id < b.id))
	for d in order:
		if not divisions.has(d) or d.order_path.is_empty():
			continue
		if d.order_attack:
			var target := division_at(d.order_path[0])
			if target and can_attack(d, target, hex_map):
				attack(d, target, hex_map)
		else:
			for cell in d.order_path:
				if not divisions.has(d) or not try_move(d, cell, hex_map):
					break
	for d in divisions:
		clear_order(d)


## Order endpoints of nation's divisions shared by two or more orders (possible clash).
func clash_hexes(nation: int) -> Array[Vector2i]:
	var counts := {}
	for d in divisions:
		if d.nation == nation and not d.order_path.is_empty():
			counts[d.order_path.back()] = int(counts.get(d.order_path.back(), 0)) + 1
	var out: Array[Vector2i] = []
	for cell in counts:
		if counts[cell] > 1:
			out.append(cell)
	return out


## Placeholder AI for every nation except player_nation: order an attack on a random
## adjacent enemy if possible, otherwise order a random 1-hex move (70%) or
## fortify on the spot (fortify is immediate, not an order).
## Reads only the board, never other divisions' orders, so call it before the
## player gives orders.
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
			set_order(d, enemies[rng.randi_range(0, enemies.size() - 1)].hex, hex_map)
		elif not free.is_empty() and rng.randf() < 0.7:
			set_order(d, free[rng.randi_range(0, free.size() - 1)], hex_map)
		else:
			fortify(d)


# --- Supply ---

## True if a BFS over passable hexes not holding an enemy division reaches a city
## d's nation owns within supply_max_path steps (d's own hex is step 0).
func is_in_supply(d: Division, hex_map: HexMap) -> bool:
	var max_steps := int(combat.supply_max_path)
	var seen := {d.hex: 0}
	var queue: Array[Vector2i] = [d.hex]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var city := hex_map.city_at(cell)
		if not city.is_empty() and city.nation == d.nation:
			return true
		var steps: int = seen[cell]
		if steps >= max_steps:
			continue
		for n in hex_map.neighbors(cell):
			if seen.has(n) or not hex_map.terrain_of(n).passable:
				continue
			var other := division_at(n)
			if other and other.nation != d.nation:
				continue
			seen[n] = steps + 1
			queue.append(n)
	return false


## Sets supplied on every division. Out of supply and encircled are the same state for now.
func update_supply(hex_map: HexMap) -> void:
	for d in divisions:
		d.supplied = is_in_supply(d, hex_map)


# --- Turn ---

## Checks supply first (if hex_map is given). Out-of-supply divisions lose
## out_of_supply_org_drain org (clamped at 0, no retreat) and recover nothing.
## Supplied divisions not in combat recover org (morale * rate). Then resets actions.
## Strength never regenerates here.
func end_turn(hex_map: HexMap = null) -> void:
	if hex_map:
		update_supply(hex_map)
	var rate: float = combat.org_recovery_per_morale
	for d in divisions:
		if not d.supplied:
			d.org = maxf(d.org - float(combat.out_of_supply_org_drain), 0.0)
		elif not d.in_combat:
			d.org = minf(d.org + d.morale * rate, d.max_org)
		d.fought_this_turn = d.in_combat
		d.in_combat = false
		d.attacked_from.clear()
		d.moves_left = d.move
		d.has_moved = false