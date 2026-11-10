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
		"Infrastructure: %.1f" % float(city.infrastructure),
	])
	if city.has("rebuild_turns_left"):
		label.text += "\nRebuilding: %d turns left (infra %.1f/%.1f)" % [
				city.rebuild_turns_left, float(city.infrastructure), float(city.rebuild_target)]
	if economy:
		var free := economy.unassigned_labor(city)
		label.text += "\nLabor %d (%d free)" % [economy.labor_points(city), free]
		var income := economy.city_income(city)
		label.text += "\nOutput/turn: cash +%.1f, manpower +%.1f, capacity +%.1f" % [
				income.cash, income.manpower, income.capacity]
		var per_level := economy.infra_labor_per_level()
		label.text += "\nInfra build %d/%d (+%d/turn)" % [int(city.get("infra_progress", 0)), per_level, economy.infra_points(city)]
		if economy.pending.has(city.id):
			label.text += "\nRecruiting: " + NationEconomy.queue_text(economy.pending[city.id])
			label.text += " (+%d/turn)" % economy.training_points(city)
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
		row.plus.disabled = economy.unassigned_labor(city) <= 0
		psize = Vector2(maxf(psize.x, 226.0), psize.y + ROW_HEIGHT)
	if button.visible:
		var reason := economy.recruit_block_reason(city, player_nation, roster)
		button.disabled = reason != ""
		button.text = "Recruit (R)" if reason == "" else "Recruit: " + reason
		button.position = Vector2(8, psize.y)
		button.size = button.get_minimum_size()
		psize = Vector2(maxf(psize.x, button.size.x + 16), psize.y + button.size.y + 8)
	panel.size = psize