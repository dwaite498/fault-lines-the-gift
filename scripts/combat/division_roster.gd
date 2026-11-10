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
## Clash/combat lines from the last execute_orders().
var turn_log: Array[String] = []
## Nations treated as neutral: their hexes can be neither ordered into nor attacked.
var neutral_nations: Array[int] = []
var _defer_after_combat := false
var _pending_captor := {}


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
	if not hex_map.can_step(d.hex, hex):
		return false
	return d.moves_left >= hex_map.step_cost(d.hex, hex) or not d.has_moved


## Moves d one hex; moving onto an enemy city captures it.
func try_move(d: Division, hex: Vector2i, hex_map: HexMap) -> bool:
	if not can_move(d, hex, hex_map):
		return false
	var cost := hex_map.step_cost(d.hex, hex)
	d.hex = hex
	d.moves_left = maxi(d.moves_left - cost, 0)
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
			and defender.nation != attacker.nation and not neutral_nations.has(defender.nation)
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


## Attack multiplier for hitting defender_hex from attacker_hex: -uphill_attack_per_level
## for each level the target is higher, capped at uphill_attack_cap. Downhill and level
## attacks are 1.0, and the defender gets no height bonus. Naval and bombard attacks
## ignore elevation: pass ranged = true (hook for the naval slice; none exist yet).
func elevation_attack_mult(attacker_hex: Vector2i, defender_hex: Vector2i, hex_map: HexMap, ranged := false) -> float:
	if ranged:
		return 1.0
	var levels := maxi(hex_map.elevation_of(defender_hex) - hex_map.elevation_of(attacker_hex), 0)
	var penalty := minf(float(combat.uphill_attack_per_level) * levels, float(combat.uphill_attack_cap))
	return 1.0 - penalty


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
	var uphill := elevation_attack_mult(attacker.hex, defender.hex, hex_map)
	var dmg_to_defender := roll_damage(attacker.attack * uphill, def_defense)
	var dmg_to_attacker := roll_damage(defender.attack, atk_defense)
	var taken_by_defender := _damage(defender, dmg_to_defender)
	var taken_by_attacker := _damage(attacker, dmg_to_attacker)
	attacker.moves_left = 0
	attacker.fortify_level = 0
	attacker.in_combat = true
	defender.in_combat = true
	return {
		"defender_defense": def_defense, "flank_mult": flank_mult(defender), "uphill_mult": uphill, "attacker_defense": atk_defense,
		"damage_to_defender": dmg_to_defender, "damage_to_attacker": dmg_to_attacker,
		"defender_org_loss": taken_by_defender.org, "defender_strength_loss": taken_by_defender.strength,
		"attacker_org_loss": taken_by_attacker.org, "attacker_strength_loss": taken_by_attacker.strength,
		"attacker_outcome": _after_combat_or_defer(attacker, hex_map, defender.nation),
		"defender_outcome": _after_combat_or_defer(defender, hex_map, attacker.nation),
	}


## While execute_orders runs, retreat/surrender waits until everything resolved.
func _after_combat_or_defer(d: Division, hex_map: HexMap, captor: int) -> String:
	if _defer_after_combat:
		_pending_captor[d] = captor
		return "pending"
	return _after_combat(d, hex_map, captor)


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
				and hex_map.can_step(d.hex, n)):
			d.hex = n
			d.fortify_level = 0
			return "retreated"
	divisions.erase(d)
	if economy:
		economy.add_pows(captor, d.nation, d.strength)
	return "surrendered"

# --- Orders ---

## Stores an order for d toward dest instead of acting now. An adjacent enemy is
## an attack order; otherwise a move along the shortest free path, which may take
## several turns (Task 25). Returns false (order unchanged) if dest is unreachable.
func set_order(d: Division, dest: Vector2i, hex_map: HexMap) -> bool:
	var target := division_at(dest)
	if target and neutral_nations.has(target.nation):
		return false
	if target and can_attack(d, target, hex_map):
		if is_leaving(d):
			clear_order(d)
		d.order_path.assign([dest])
		d.order_attack = true
		return true
	var path := plan_path(d, dest, hex_map)
	if path.is_empty():
		return false
	d.order_path.assign(path)
	d.order_attack = false
	return true


## Paired swap: a and b (same nation, adjacent, both without orders) each get a
## one-hex move into the other's hex; execute_orders resolves it as a friendly swap.
## Cancelling either clears both (clear_order's follower cascade). False if not allowed.
func set_swap(a: Division, b: Division, hex_map: HexMap) -> bool:
	if not can_swap(a, b, hex_map):
		return false
	a.order_path.assign([b.hex])
	a.order_attack = false
	b.order_path.assign([a.hex])
	b.order_attack = false
	return true


func can_swap(a: Division, b: Division, hex_map: HexMap) -> bool:
	if a == b or a.nation != b.nation or not a.order_path.is_empty() or not b.order_path.is_empty():
		return false
	if not hex_map.neighbors(a.hex).has(b.hex):
		return false
	if not hex_map.can_step(a.hex, b.hex) or not hex_map.can_step(b.hex, a.hex):
		return false
	return a.moves_left > 0 and b.moves_left > 0


## Valid target hexes for d's actions (Task 26), sorted for determinism.
## "move": empty hexes with a path; "attack": attackable enemies; "follow": a
## friendly moving out that d can reach, or an adjacent idle friendly to swap with.
func action_targets(d: Division, action: String, hex_map: HexMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if action == "move":
		for cell in hex_map.cells:
			if division_at(cell) == null and not plan_path(d, cell, hex_map).is_empty():
				out.append(cell)
	else:
		for o in divisions:
			if o == d:
				continue
			if action == "attack" and o.nation != d.nation and not neutral_nations.has(o.nation) \
					and can_attack(d, o, hex_map):
				out.append(o.hex)
			elif action == "follow" and o.nation == d.nation:
				if (is_leaving(o) and not plan_path(d, o.hex, hex_map).is_empty()) \
						or (o.order_path.is_empty() and can_swap(d, o, hex_map)):
					out.append(o.hex)
	out.sort()
	return out


## Actions valid for d right now, in button order.
func valid_actions(d: Division, hex_map: HexMap) -> Array[String]:
	var out: Array[String] = []
	for a in ["move", "attack", "follow"]:
		if not action_targets(d, a, hex_map).is_empty():
			out.append(a)
	if d.moves_left > 0 and not d.has_moved:
		out.append("dig_in")
	if not d.order_path.is_empty():
		out.append("cancel")
	return out


## True if d has a move (not attack) order, so it is leaving its hex.
func is_leaving(d: Division) -> bool:
	return d != null and not d.order_path.is_empty() and not d.order_attack


## Cancels d's order. Friendly orders routed through d's hex were only valid while
## d was leaving, so they are cleared too, with a note in turn_log.
func clear_order(d: Division) -> void:
	var was_leaving := is_leaving(d)
	d.order_path.clear()
	d.order_attack = false
	if not was_leaving:
		return
	for f in divisions:
		if f != d and f.nation == d.nation and is_leaving(f) and f.order_path.has(d.hex):
			var note := "Div %d order cleared: div %d's move out of %s was cancelled" % [f.id, d.id, d.hex]
			turn_log.append(note)
			print(note)
			clear_order(f)


## Shortest path (by steps, BFS) from d.hex to dest through passable hexes that are
## empty or held by a friendly with a move order out, excluding d.hex. Empty if none or if d can't pay for it this turn.
func plan_path(d: Division, dest: Vector2i, hex_map: HexMap) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if dest == d.hex or not hex_map.cells.has(dest):
		return none
	var came := {d.hex: d.hex}
	var queue: Array[Vector2i] = [d.hex]
	while not queue.is_empty() and not came.has(dest):
		var cell: Vector2i = queue.pop_front()
		for n in hex_map.neighbors(cell):
			if came.has(n) or not hex_map.can_step(cell, n):
				continue
			var occ := division_at(n)
			# Only a friendly that is moving out may be followed into its hex.
			if occ != null and not (occ.nation == d.nation and is_leaving(occ)):
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
	return path


## How many steps of path d can take per turn, starting this turn: one int per
## turn until the path is covered (Task 25). Same cost rule as can_move: the first
## step of a turn is always allowed. This turn uses d.moves_left/has_moved,
## later turns d.move. Deterministic, read-only.
func turn_split(d: Division, path: Array[Vector2i], hex_map: HexMap) -> Array[int]:
	var out: Array[int] = []
	var moves := d.moves_left
	var moved := d.has_moved
	var steps := 0
	var i := 0
	while i < path.size():
		var cost := hex_map.step_cost(path[i - 1] if i > 0 else d.hex, path[i])
		if moves <= 0 or (moves < cost and moved):
			out.append(steps)
			steps = 0
			moves = d.move
			moved = false
			continue
		moves = maxi(moves - cost, 0)
		moved = true
		steps += 1
		i += 1
	out.append(steps)
	return out


## Steps of d's order it will take this turn (0 if none or an attack order counts as 1).
func steps_this_turn(d: Division, hex_map: HexMap) -> int:
	if d.order_path.is_empty():
		return 0
	if d.order_attack:
		return 1
	return turn_split(d, d.order_path, hex_map)[0]


## Turns until d's move order arrives (0 if no move order).
func turns_to_arrive(d: Division, hex_map: HexMap) -> int:
	if not is_leaving(d):
		return 0
	var split := turn_split(d, d.order_path, hex_map)
	return split.size() - (1 if split[0] == 0 else 0)


## Simultaneous resolution (Task 21). All move orders advance together one hex
## step at a time; each step resolves, in order: head-on swaps (meeting
## engagement at the border; nobody passes), friendlies entering one hex (lowest
## id gets in), enemies entering one hex (meeting engagement), then leavers move
## before the units following them in. A mover blocked by an enemy that failed to
## leave attacks it in the combat phase. Then attack orders resolve (an attack on
## a target that moved away becomes a move into the vacated hex). Retreat and
## surrender are checked after everything. Any move order resets fortify, even a
## bounce. Clashes go to turn_log. All orders are cleared afterwards.
func execute_orders(hex_map: HexMap) -> void:
	turn_log.clear()
	_defer_after_combat = true
	_pending_captor.clear()
	var by_id := func(a, b): return a.nation < b.nation or (a.nation == b.nation and a.id < b.id)
	var order := divisions.duplicate()
	order.sort_custom(by_id)
	var movers: Array = []
	var attacks: Array = []  # [attacker, target]
	for d in order:
		if d.order_path.is_empty():
			continue
		if d.order_attack:
			attacks.append([d, division_at(d.order_path[0])])
		else:
			d.fortify_level = 0
			movers.append(d)
	var step := {}
	var limit := {}
	for d in movers:
		step[d] = 0
		limit[d] = steps_this_turn(d, hex_map)
	var ended := {}  # movers whose order ended early (clash, bounce, blocked)
	var blocked_attacks: Array = []
	while not movers.is_empty():
		var active: Array = []
		for d in movers:
			if divisions.has(d) and step[d] < limit[d]:
				active.append(d)
		var stopped := {}
		var swapped := {}
		var target_of := {}
		for d in active:
			target_of[d] = d.order_path[step[d]]
		# Head-on swaps.
		for i in active.size():
			for j in range(i + 1, active.size()):
				var a: Division = active[i]
				var b: Division = active[j]
				if target_of[a] == b.hex and target_of[b] == a.hex:
					stopped[a] = true
					stopped[b] = true
					if a.nation != b.nation:
						_meeting(a, b, a.hex, b.hex, hex_map, "head-on at %s|%s" % [a.hex, b.hex])
					else:
						_friendly_swap(a, b, hex_map)
						stopped.erase(a)
						stopped.erase(b)
						step[a] += 1
						step[b] += 1
						swapped[a] = true
						swapped[b] = true
		# Group the rest by target hex.
		var groups := {}
		for d in active:
			if not stopped.has(d) and not swapped.has(d):
				if not groups.has(target_of[d]):
					groups[target_of[d]] = []
				groups[target_of[d]].append(d)
		var candidates: Array = []
		for hex in groups:
			var champs: Array = []  # lowest id per nation
			for d in groups[hex]:
				if champs.is_empty() or champs.back().nation != d.nation:
					champs.append(d)
				else:
					stopped[d] = true
					turn_log.append("Div %d (n%d) stops short of %s: div %d enters first" % [d.id, d.nation, hex, champs.back().id])
			var champ: Division = null
			for d in champs:
				if champ == null:
					champ = d
					continue
				var res := _meeting(champ, d, hex, hex, hex_map, "meeting at %s" % [hex])
				if res == 1:
					stopped[d] = true
				elif res == -1:
					stopped[champ] = true
					champ = d
				else:
					stopped[champ] = true
					stopped[d] = true
					champ = null
			if champ and not stopped.get(champ, false):
				candidates.append(champ)
		# Leavers first: keep moving whoever has a free target until no progress.
		var progress := true
		while progress:
			progress = false
			for d in candidates.duplicate():
				if divisions.has(d) and try_move(d, target_of[d], hex_map):
					step[d] += 1
					candidates.erase(d)
					progress = true
		for d in candidates:
			stopped[d] = true
			var occ := division_at(target_of[d])
			if occ and occ.nation != d.nation:
				blocked_attacks.append([d, occ])
				turn_log.append("Div %d (n%d) blocked at %s by div %d (n%d); attacks" % [d.id, d.nation, target_of[d], occ.id, occ.nation])
			elif occ:
				turn_log.append("Div %d (n%d) stalls short of %s: friendly div %d did not leave" % [d.id, d.nation, target_of[d], occ.id])
			else:
				turn_log.append("Div %d (n%d) stalls short of %s: cannot enter" % [d.id, d.nation, target_of[d]])
		var still: Array = []
		for d in movers:
			if divisions.has(d) and not stopped.has(d) and active.has(d):
				still.append(d)
		for d in stopped:
			if not ended.has(d) and step.has(d) and step[d] < d.order_path.size():
				ended[d] = true
				turn_log.append("Div %d (n%d) order to %s ends at %s" % [d.id, d.nation, d.order_path.back(), d.hex])
		movers = still
	# Combat phase.
	for pair in blocked_attacks:
		var a: Division = pair[0]
		var t: Division = pair[1]
		if divisions.has(a) and divisions.has(t) and t.hex in hex_map.neighbors(a.hex):
			_log_attack(a, t, attack_unchecked(a, t, hex_map))
	for pair in attacks:
		var a: Division = pair[0]
		var t = pair[1]
		var vacated: Vector2i = a.order_path[0]
		if not divisions.has(a):
			continue
		if t != null and divisions.has(t) and t.hex in hex_map.neighbors(a.hex):
			_log_attack(a, t, attack_unchecked(a, t, hex_map))
		elif division_at(vacated) == null:
			a.fortify_level = 0
			if try_move(a, vacated, hex_map):
				turn_log.append("Div %d (n%d): target moved away; moves into %s" % [a.id, a.nation, vacated])
	# Retreat / surrender after everything.
	_defer_after_combat = false
	var hit := _pending_captor.keys()
	hit.sort_custom(by_id)
	for d in hit:
		if divisions.has(d):
			var outcome := _after_combat(d, hex_map, _pending_captor[d])
			if outcome != "held":
				turn_log.append("Div %d (n%d) %s" % [d.id, d.nation, outcome])
	_pending_captor.clear()
	# Unfinished multi-turn moves keep the rest of their path; everything else clears.
	var keep := {}
	for d in step:
		if divisions.has(d) and not ended.has(d) and step[d] < d.order_path.size() \
				and d.hex == (d.order_path[step[d] - 1] if step[d] > 0 else d.hex):
			keep[d] = d.order_path.slice(step[d])
	for d in divisions:
		d.order_path.clear()
		d.order_attack = false
		if keep.has(d):
			d.order_path.assign(keep[d])
	for line in turn_log:
		print(line)


## Two friendlies trading hexes both complete the swap, no combat.
func _friendly_swap(a: Division, b: Division, hex_map: HexMap) -> void:
	var ha := a.hex
	var hb := b.hex
	var costs := {a: hex_map.step_cost(ha, hb), b: hex_map.step_cost(hb, ha)}
	a.hex = hb
	b.hex = ha
	for d in [a, b]:
		d.moves_left = maxi(d.moves_left - int(costs[d]), 0)
		d.has_moved = true
		d.fortify_level = 0
	turn_log.append("Div %d and div %d (n%d) swap %s <-> %s" % [a.id, b.id, a.nation, b.hex, a.hex])


## Attack without the can_attack gate (resolution already checked adjacency).
func attack_unchecked(a: Division, t: Division, hex_map: HexMap) -> Dictionary:
	var ml := a.moves_left
	var hm := a.has_moved
	a.moves_left = 1
	a.has_moved = false
	var r := attack(a, t, hex_map)
	if r.is_empty():
		a.moves_left = ml
		a.has_moved = hm
	return r


func _log_attack(a: Division, t: Division, r: Dictionary) -> void:
	turn_log.append("Div %d (n%d) attacks div %d (n%d) at %s: -%.1f/-%.1f str" % [a.id, a.nation, t.id,
			t.nation, t.hex, float(r.get("defender_strength_loss", 0.0)), float(r.get("attacker_strength_loss", 0.0))])


## One meeting-engagement round: no fortify/city/flank bonus, each side's
## defense uses the terrain of hex_for_terrain (its own hex for a head-on).
## Returns 1 if a wins (higher strength*org afterwards), -1 if b wins, 0 on tie.
func _meeting(a: Division, b: Division, terrain_a: Vector2i, terrain_b: Vector2i,
		hex_map: HexMap, where: String) -> int:
	var ta: float = hex_map.terrain_of(terrain_a).defense_mult
	var tb: float = hex_map.terrain_of(terrain_b).defense_mult
	var to_b := roll_damage(a.attack, b.defense * tb)
	var to_a := roll_damage(b.attack, a.defense * ta)
	_damage(b, to_b)
	_damage(a, to_a)
	a.in_combat = true
	b.in_combat = true
	a.fortify_level = 0
	b.fortify_level = 0
	_pending_captor[a] = b.nation
	_pending_captor[b] = a.nation
	var sa := a.strength * a.org
	var sb := b.strength * b.org
	var res := 0 if is_equal_approx(sa, sb) else (1 if sa > sb else -1)
	var head_on := where.begins_with("head-on")
	var result := ("tie, both hold" if head_on else "tie, both bounce") if res == 0 else (
			"div %d wins the clash, both hold" if head_on else "div %d wins") % (a.id if res == 1 else b.id)
	turn_log.append("Clash %s: div %d (n%d) vs div %d (n%d): %s" % [where, a.id, a.nation, b.id, b.nation, result])
	return res


## Endpoints shared by two or more of nation's MOVE orders (possible clash). Attacks on
## the same enemy are a combined (flanking) attack, not a clash.
func clash_hexes(nation: int, hex_map: HexMap = null) -> Array[Vector2i]:
	var counts := {}
	for d in divisions:
		if d.nation == nation and not d.order_path.is_empty() and not d.order_attack:
			# This turn's endpoint (Task 25); full path end if no map given.
			var n := steps_this_turn(d, hex_map) if hex_map else d.order_path.size()
			if n == 0:
				continue
			var end: Vector2i = d.order_path[n - 1]
			counts[end] = int(counts.get(end, 0)) + 1
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