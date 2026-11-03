class_name UnitPanel
extends CanvasLayer
## Simple on-screen info panel for the selected division. Hidden when nothing is selected.

signal action_pressed(action: String)

const ACTION_LABELS := {"move": "Move (M)", "attack": "Attack (A)", "dig_in": "Dig in (D)",
		"follow": "Follow/Swap (F)", "cancel": "Cancel order (Esc)"}

var panel := Panel.new()
## Action buttons for the player's selected unit; only valid ones are shown.
var buttons := {}
var _box := VBoxContainer.new()
var label := Label.new()
var max_fortify := 3
var flank_per_hex := 0.15
var flank_min_mult := 0.4
## Set by main.gd; used only to preview this turn's recovery.
var roster: DivisionRoster
var economy: NationEconomy
## Map from the last refresh(); projected_recovery() uses it for income.
var _map: HexMap


func _init() -> void:
	panel.position = Vector2(8, 8)
	panel.size = Vector2(230, 200)
	label.position = Vector2(8, 6)
	panel.add_child(label)
	add_child(panel)
	panel.visible = false
	_box.position = Vector2(8, 212)
	add_child(_box)
	for a in ACTION_LABELS:
		var b := Button.new()
		b.text = ACTION_LABELS[a]
		b.pressed.connect(func() -> void: action_pressed.emit(a))
		b.visible = false
		_box.add_child(b)
		buttons[a] = b


## Shows d's current stats, or hides the panel when d is null.
func refresh(d: Division, hex_map: HexMap, actions: Array[String] = [], mode := "") -> void:
	panel.visible = d != null
	_map = hex_map
	for a in buttons:
		buttons[a].visible = d != null and actions.has(a)
	if d == null:
		label.text = ""
		return
	var terrain_name := hex_map.terrain_name(d.hex)
	var acted := d.moves_left < d.move
	label.text = "\n".join([
		"Nation: %d" % d.nation,
		"Strength: %.1f" % d.strength,
		"Org: %.1f / %.1f" % [d.org, d.max_org],
		"Morale: %.2f" % d.morale,
		"Attack: %.1f" % d.attack,
		"Defense: %.1f" % d.defense,
		"Fortify: %d/%d" % [d.fortify_level, max_fortify],
		"Moves left: %d / %d" % [d.moves_left, d.move],
		"Acted this turn: %s" % ("yes" if acted else "no"),
		"Terrain: %s (def x%.2f)" % [terrain_name, float(hex_map.terrain_of(d.hex).defense_mult)],
	])
	## Current flank penalty from the distinct hexes that attacked d this turn.
	var penalty := 1.0 - DivisionRoster.flank_mult_for(d.attacked_from.size(), flank_per_hex, flank_min_mult)
	if roster and economy:
		var rec := projected_recovery(d)
		label.text += "\nWill recover %+.1f org / +%.1f str this turn" % [rec.org, rec.strength]
	if d.last_reinforce > 0.0:
		label.text += "\nReinforcing +%.1f" % d.last_reinforce
	label.text += "\nTab: next unit without orders"
	if mode != "":
		label.text += "\nPick a highlighted hex (Esc: back)"
	if not d.order_path.is_empty():
		var dest: Vector2i = d.order_path.back()
		label.text += "\nOrder: %s (%d,%d)%s" % ["attack" if d.order_attack else "move to",
				dest.x, dest.y, "" if d.order_attack else ", %d steps" % d.order_path.size()]
	else:
		label.text += "\nOrder: none"
	if not d.supplied:
		label.text += "\nOut of supply"
	if penalty > 0.0:
		label.text += "\nFlanked: -%d%% def" % roundi(penalty * 100.0)
	panel.size = label.get_minimum_size() + Vector2(16, 12)
	_box.position = panel.position + Vector2(0, panel.size.y + 4)


## Preview of d's org and strength change at the next end turn, using the same
## rules as DivisionRoster.end_turn (supply drain or morale recovery) and
## NationEconomy.reinforce (cap, cost, pool shared in division id order).
## The pool includes this turn's manpower income (collected before reinforcement;
## upkeep costs no manpower). with_growth adds the city growth main.gd applies
## before income. Uses d's current supply status and ignores unpaid-upkeep drain. Read-only.
func projected_recovery(d: Division, with_growth := true) -> Dictionary:
	var c := roster.combat
	var org := 0.0
	if not d.supplied:
		org = -minf(float(c.out_of_supply_org_drain), d.org)
	elif not d.in_combat:
		org = minf(d.morale * float(c.org_recovery_per_morale), d.max_org - d.org)
	var cap := float(economy.config.reinforce_cap_per_turn)
	var rate := float(economy.config.reinforce_manpower_per_strength)
	var pool := float(economy.stocks.get(d.nation, {}).get("manpower", 0.0))
	if _map and _map.nations.has(d.nation):
		for city in _map.cities:
			if city.nation != d.nation:
				continue
			var c2: Dictionary = city.duplicate()
			if with_growth:
				c2.population = mini(int(city.population) + int(_map.city_rules.growth_per_turn),
						int(_map.city_rules.max_population))
			pool += float(economy.city_income(c2).manpower)
	var order := roster.divisions.filter(func(x): return x.nation == d.nation)
	order.sort_custom(func(a, b): return a.id < b.id)
	var strength := 0.0
	for x in order:
		if not x.supplied or x.strength >= x.max_strength:
			continue
		var gain := minf(cap * economy.reinforce_mult(x, _map, x.in_combat), x.max_strength - x.strength)
		if rate > 0.0:
			gain = minf(gain, pool / rate)
		gain = maxf(gain, 0.0)
		pool -= gain * rate
		if x == d:
			strength = gain
			break
	return {"org": org, "strength": strength}
