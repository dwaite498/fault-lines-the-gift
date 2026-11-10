class_name CityPanel
extends CanvasLayer
## Simple on-screen info panel for a clicked city. Same style as UnitPanel.

var panel := Panel.new()
var label := Label.new()
## Set by main.gd: the map supplies housing cap, growth and people rounding.
var hex_map: HexMap
var economy: NationEconomy
## Set by main.gd. The Recruit button shows for this nation's cities.
var roster: DivisionRoster
var player_nation := 0
var button := Button.new()
var swatch := MapView.make_swatch()
var factions: FactionRoster
## Emitted when the Recruit button is clicked (same action as the R key).
signal recruit_pressed
## Emitted when the Colony pod button is clicked (same action as the P key).
signal pod_pressed
## Emitted when the Scout button is clicked (same action as the S key).
signal scout_pressed
## Emitted when the Rush button is clicked (Syndicate rush-buy).
signal rush_pressed
## Emitted when the Annex button (an occupied city whose timer ran out) is clicked.
signal annex_pressed
var annex_button := Button.new()
var pod_button := Button.new()
var scout_button := Button.new()
var rush_button := Button.new()
## Emitted by a labor row's -/+ button: the sink name and +1 or -1.
signal labor_pressed(sink: String, delta: int)
## sink -> {"label": Label, "minus": Button, "plus": Button}
var labor_rows := {}
const ROW_HEIGHT := 26.0


func _init() -> void:
	panel.position = Vector2(8, 40)
	label.position = Vector2(22, 6)
	swatch.position = Vector2(8, 10)
	panel.add_child(swatch)
	panel.add_child(label)
	panel.add_child(button)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): recruit_pressed.emit())
	panel.add_child(rush_button)
	rush_button.focus_mode = Control.FOCUS_NONE
	rush_button.pressed.connect(func(): rush_pressed.emit())
	panel.add_child(scout_button)
	scout_button.focus_mode = Control.FOCUS_NONE
	scout_button.pressed.connect(func(): scout_pressed.emit())
	panel.add_child(pod_button)
	pod_button.focus_mode = Control.FOCUS_NONE
	pod_button.pressed.connect(func(): pod_pressed.emit())
	panel.add_child(annex_button)
	annex_button.focus_mode = Control.FOCUS_NONE
	annex_button.text = "Annex (occupation over)"
	annex_button.pressed.connect(func(): annex_pressed.emit())
	for sink in NationEconomy.SINKS:
		var row := {"label": Label.new(), "minus": Button.new(), "plus": Button.new()}
		row.minus.text = "-"
		row.plus.text = "+"
		for b in [row.minus, row.plus]:
			b.focus_mode = Control.FOCUS_NONE
			panel.add_child(b)
		panel.add_child(row.label)
		row.minus.pressed.connect(func() -> void: labor_pressed.emit(sink, -1))
		row.plus.pressed.connect(func() -> void: labor_pressed.emit(sink, 1))
		labor_rows[sink] = row
	add_child(panel)
	panel.visible = false


## 12400 -> "12,400".
static func people_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Shows the city's current values, or hides the panel when city is empty.
func refresh(city: Dictionary) -> void:
	panel.visible = not city.is_empty()
	if city.is_empty():
		label.text = ""
		return
	swatch.color = factions.color_of(int(city.nation))
	var growth := hex_map.growth_amount(city)
	label.text = "\n".join([
		"%s - City %d" % [factions.name_of(int(city.nation)), city.id],
		"Pop %s / %s housing" % [people_text(hex_map.display_people(int(city.population))),
				people_text(hex_map.housing_cap(city))],
		"Growth/turn: +%s" % people_text(hex_map.display_people(growth)),
		"Claim radius: %d" % city.radius,
		"Tier: %s%s" % [hex_map.tier(city).capitalize(), "" if hex_map.next_tier_population(city) < 0
				else " (next tier: %s)" % people_text(hex_map.display_people(hex_map.next_tier_population(city)))],
		"Infrastructure: %.1f" % float(city.infrastructure),
	])
	if city.has("rebuild_turns_left"):
		label.text += "\nRebuilding: %d turns left (infra %.1f/%.1f)" % [
				city.rebuild_turns_left, float(city.infrastructure), float(city.rebuild_target)]
	if economy:
		var free := economy.unassigned_labor(city)
		label.text += "\nLabor %d (%d free)" % [economy.labor_points(city), free]
		var income := economy.city_income(city)
		if city.get("occupied", false) or city.get("enslaved", false):
			label.text += "\nRecruitable 0 (held at 0)"  # the pool is kept empty, so no fill or cap
		else:
			label.text += "\nRecruitable %s (+%s/turn, cap %s)" % [people_text(hex_map.pool_of(city)),
					people_text(hex_map.pool_fill(city)), people_text(hex_map.pool_cap(city))]
		if city.get("besieged", false):
			label.text += "\nBESIEGED: no growth, -%d%% pop/turn, labor halved" % roundi(float(hex_map.city_rules.siege_pop_loss) * 100.0)
		if city.get("occupied", false):
			label.text += "\nOCCUPIED: labor x%s, no pool or training; %s" % [
					String.num(float(hex_map.city_rules.capture.options.occupy.labor_mult)),
					"can be annexed now" if hex_map.can_annex_occupied(city)
					else "annexable in %d turns" % int(city.get("occupy_turns_left", 0))]
		if city.get("enslaved", false):
			label.text += "\nENSLAVED: no growth, pool or training, labor x%s" % String.num(
					float(hex_map.city_rules.capture.options.enslave.labor_mult))
		if int(city.get("recruit_lockout", 0)) > 0:
			label.text += "\nRecruit lockout: %d turns" % int(city.recruit_lockout)
		label.text += "\nOutput/turn: cash +%.1f, capacity +%.1f" % [income.cash, income.capacity]
		var per_level := economy.infra_labor_per_level(int(city.nation))
		label.text += "\nInfra build %d/%d (+%d/turn)" % [int(city.get("infra_progress", 0)), per_level, economy.infra_points(city)]
		if economy.pending.has(city.id):
			label.text += "\nRecruiting: " + NationEconomy.queue_text(economy.pending[city.id])
			label.text += " (+%d/turn)" % economy.training_points(city)
			if economy.training_blocked(city) != "":
				label.text += "\nTraining paused: city is %s" % economy.training_blocked(city)
			elif economy.recruit_stalled(city):
				label.text += "\nRecruit stalled: assign Training labor"
	button.visible = economy != null and roster != null and city.nation == player_nation
	var psize := label.get_minimum_size() + Vector2(30, 12)
	var editable: bool = economy != null and city.nation == player_nation
	for sink in NationEconomy.SINKS:
		var row: Dictionary = labor_rows[sink]
		var show: bool = economy != null
		row.label.visible = show
		row.minus.visible = show and editable
		row.plus.visible = show and editable
		if not show:
			continue
		var pts := int(city.get("labor", {}).get(sink, 0))
		row.label.text = "%s %d" % [String(sink).capitalize(), pts]
		row.label.position = Vector2(8, psize.y + 2)
		row.minus.size = row.minus.get_minimum_size()
		row.plus.size = row.plus.get_minimum_size()
		row.minus.position = Vector2(150, psize.y)
		row.plus.position = Vector2(186, psize.y)
		row.minus.disabled = pts <= 0
		row.plus.disabled = economy.unassigned_labor(city) <= 0 or (sink == "training" and city.get("enslaved", false))
		psize = Vector2(maxf(psize.x, 226.0), psize.y + ROW_HEIGHT)
	pod_button.visible = button.visible
	scout_button.visible = button.visible
	rush_button.visible = button.visible
	annex_button.visible = button.visible and hex_map.can_annex_occupied(city)
	if annex_button.visible:
		annex_button.position = Vector2(8, psize.y)
		annex_button.size = annex_button.get_minimum_size()
		psize = Vector2(maxf(psize.x, annex_button.size.x + 16), psize.y + annex_button.size.y + 8)
	if button.visible:
		var reason := economy.recruit_block_reason(city, player_nation, roster)
		button.disabled = reason != ""
		button.text = "Recruit (R)" if reason == "" else "Recruit: " + reason
		button.position = Vector2(8, psize.y)
		button.size = button.get_minimum_size()
		psize = Vector2(maxf(psize.x, button.size.x + 16), psize.y + button.size.y + 8)
		var rush_reason := economy.rush_block_reason(city, player_nation)
		rush_button.visible = rush_reason != "no rush-buy"
		rush_button.disabled = rush_reason != ""
		rush_button.text = "Rush +1 labor" if rush_reason == "" else "Rush: " + rush_reason
		if rush_button.visible:
			rush_button.position = Vector2(8, psize.y)
			rush_button.size = rush_button.get_minimum_size()
			psize = Vector2(maxf(psize.x, rush_button.size.x + 16), psize.y + rush_button.size.y + 8)
		var scout_reason := economy.scout_block_reason(city, player_nation, roster)
		scout_button.disabled = scout_reason != ""
		scout_button.text = "Scout (S)" if scout_reason == "" else "Scout: " + scout_reason
		scout_button.position = Vector2(8, psize.y)
		scout_button.size = scout_button.get_minimum_size()
		psize = Vector2(maxf(psize.x, scout_button.size.x + 16), psize.y + scout_button.size.y + 8)
		var pod_reason := economy.colony_block_reason(city, player_nation)
		pod_button.disabled = pod_reason != ""
		pod_button.text = "Colony pod (P)" if pod_reason == "" else "Colony pod: " + pod_reason
		pod_button.position = Vector2(8, psize.y)
		pod_button.size = pod_button.get_minimum_size()
		psize = Vector2(maxf(psize.x, pod_button.size.x + 16), psize.y + pod_button.size.y + 8)
	panel.size = psize