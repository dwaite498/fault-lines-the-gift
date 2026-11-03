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
const WIDTH := 240.0
## ORG / STR bars (6px, counter colors) with % values.
var bars := Control.new()
## HEX and SUPPLY sections.
var details := RichTextLabel.new()
## Order, recovery and reinforcing lines under the action buttons.
var orders := RichTextLabel.new()
var _shown: Division
var _pal: Dictionary = MapView.load_palette()
var max_fortify := 3
var flank_per_hex := 0.15
var flank_min_mult := 0.4
## Set by main.gd; used only to preview this turn's recovery.
var roster: DivisionRoster
var economy: NationEconomy
## Map from the last refresh(); projected_recovery() uses it for income.
var _map: HexMap


func _init() -> void:
	# Right side panel, 240 wide, full height under the 32px top bar.
	panel.position = Vector2(1280 - WIDTH, 32)
	panel.size = Vector2(WIDTH, 720 - 32)
	add_child(panel)
	var col := VBoxContainer.new()
	col.position = Vector2(8, 8)
	col.size = Vector2(WIDTH - 16, 0)
	panel.add_child(col)
	col.add_child(_header("SELECTED UNIT"))
	col.add_child(label)
	bars.custom_minimum_size = Vector2(WIDTH - 16, 34)
	bars.draw.connect(_draw_bars)
	col.add_child(bars)
	col.add_child(HSeparator.new())
	details.fit_content = true
	details.bbcode_enabled = true
	details.custom_minimum_size = Vector2(WIDTH - 16, 0)
	col.add_child(details)
	col.add_child(_header("ORDERS"))
	col.add_child(_box)
	col.add_child(orders)
	orders.fit_content = true
	orders.custom_minimum_size = Vector2(WIDTH - 16, 0)
	for a in ACTION_LABELS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = ACTION_LABELS[a]
		b.pressed.connect(func() -> void: action_pressed.emit(a))
		b.visible = false
		_box.add_child(b)
		buttons[a] = b


## Shows d's current stats, or hides the panel when d is null.
func refresh(d: Division, hex_map: HexMap, actions: Array[String] = [], mode := "") -> void:
	_map = hex_map
	_shown = d
	for a in buttons:
		buttons[a].visible = d != null and actions.has(a)
	if d == null:
		label.text = "None"
		details.text = ""
		orders.text = ""
		bars.queue_redraw()
		return
	_shown = d
	bars.queue_redraw()
	label.text = "Div %d - %s, nation %d" % [d.id, d.unit_type.capitalize(), d.nation]
	var penalty := 1.0 - DivisionRoster.flank_mult_for(d.attacked_from.size(), flank_per_hex, flank_min_mult)
	var dim: String = _pal.ui.dim
	var lines: Array[String] = [
		"[b]HEX[/b]  (%d,%d) %s, def x%.2f" % [d.hex.x, d.hex.y, hex_map.terrain_name(d.hex), float(hex_map.terrain_of(d.hex).defense_mult)],
		"[color=%s]Moves %d/%d  Fortify %d/%d  Atk %.0f  Def %.0f%s[/color]" % [dim, d.moves_left, d.move,
				d.fortify_level, max_fortify, d.attack, d.defense, ("  Flanked -%d%%" % roundi(penalty * 100.0)) if penalty > 0.0 else ""],
		"[b]SUPPLY[/b]  " + ("OK" if d.supplied else "[color=%s]OUT[/color]" % _pal.ui.supply_out),
	]
	details.text = "\n".join(lines)
	var o: Array[String] = []
	if not d.order_path.is_empty():
		var dest: Vector2i = d.order_path.back()
		o.append("Order: %s (%d,%d)%s" % ["attack" if d.order_attack else "move to",
				dest.x, dest.y, "" if d.order_attack or _map == null else _turns_text(roster.turns_to_arrive(d, _map))])
	else:
		o.append("Order: none")
	if roster and economy:
		var rec := projected_recovery(d)
		o.append("Will recover %+.1f org / +%.1f str this turn" % [rec.org, rec.strength])
	if d.last_reinforce > 0.0:
		o.append("Reinforcing +%.1f" % d.last_reinforce)
	if mode != "":
		o.append("Pick a highlighted hex (Esc: back)")
	o.append("Tab: next unit without orders")
	orders.text = "\n".join(o)


func _header(text: String) -> Label:
	var h := Label.new()
	h.text = text.to_upper()
	h.add_theme_font_size_override("font_size", 13)
	h.add_theme_color_override("font_color", Color.html(_pal.ui.accent))
	return h


func _draw_bars() -> void:
	if _shown == null:
		return
	var fr := MapView.bar_fractions(_shown)
	var c: Dictionary = _pal.counter
	var font := ThemeDB.fallback_font
	for i in 2:
		var y := 4.0 + i * 15.0
		bars.draw_string(font, Vector2(0, y + 7), "ORG" if i == 0 else "STR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.html(_pal.ui.dim))
		var track := Rect2(Vector2(32, y), Vector2(WIDTH - 16 - 32 - 40, 6))
		bars.draw_rect(track, Color.html(c.track))
		bars.draw_rect(Rect2(track.position, Vector2(track.size.x * fr[i], 6)), Color.html(c.org if i == 0 else c.str))
		bars.draw_string(font, Vector2(track.end.x + 4, y + 7), "%d%%" % roundi(fr[i] * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.html(_pal.ui.text))

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


func _turns_text(n: int) -> String:
	return ", %d turn%s" % [n, "" if n == 1 else "s"]
