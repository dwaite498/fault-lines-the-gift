class_name CityPanel
extends CanvasLayer
## Simple on-screen info panel for a clicked city. Same style as UnitPanel.

var panel := Panel.new()
var label := Label.new()
var growth_per_turn := 1
var max_population := 30
var economy: NationEconomy
## Set by main.gd. The Recruit button shows for this nation's cities.
var roster: DivisionRoster
var player_nation := 0
var button := Button.new()
var swatch := MapView.make_swatch()
var factions: FactionRoster
## Emitted when the Recruit button is clicked (same action as the R key).
signal recruit_pressed


func _init() -> void:
	panel.position = Vector2(8, 40)
	label.position = Vector2(22, 6)
	swatch.position = Vector2(8, 10)
	panel.add_child(swatch)
	panel.add_child(label)
	panel.add_child(button)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): recruit_pressed.emit())
	add_child(panel)
	panel.visible = false


## Shows the city's current values, or hides the panel when city is empty.
func refresh(city: Dictionary) -> void:
	panel.visible = not city.is_empty()
	if city.is_empty():
		label.text = ""
		return
	swatch.color = factions.color_of(int(city.nation))
	var growth := growth_per_turn if int(city.population) < max_population else 0
	label.text = "\n".join([
		"%s - City %d" % [factions.name_of(int(city.nation)), city.id],
		"Population: %d / %d" % [city.population, max_population],
		"Growth/turn: +%d" % growth,
		"Claim radius: %d" % city.radius,
		"Infrastructure: %.1f" % float(city.infrastructure),
	])
	if city.has("rebuild_turns_left"):
		label.text += "\nRebuilding: %d turns left (infra %.1f/%.1f)" % [
				city.rebuild_turns_left, float(city.infrastructure), float(city.rebuild_target)]
	if economy:
		var income := economy.city_income(city)
		label.text += "\nOutput/turn: cash +%.1f, manpower +%.1f, capacity +%.1f" % [
				income.cash, income.manpower, income.capacity]
		if economy.pending.has(city.id):
			label.text += "\nRecruiting: " + NationEconomy.queue_text(economy.pending[city.id])
	button.visible = economy != null and roster != null and city.nation == player_nation
	var psize := label.get_minimum_size() + Vector2(30, 12)
	if button.visible:
		var reason := economy.recruit_block_reason(city, player_nation, roster)
		button.disabled = reason != ""
		button.text = "Recruit (R)" if reason == "" else "Recruit: " + reason
		button.position = Vector2(8, psize.y)
		button.size = button.get_minimum_size()
		psize = Vector2(maxf(psize.x, button.size.x + 16), psize.y + button.size.y + 8)
	panel.size = psize