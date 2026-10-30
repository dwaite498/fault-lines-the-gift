class_name CityPanel
extends CanvasLayer
## Simple on-screen info panel for a clicked city. Same style as UnitPanel.

var panel := Panel.new()
var label := Label.new()
var growth_per_turn := 1
var max_population := 30
var economy: NationEconomy


func _init() -> void:
	panel.position = Vector2(8, 8)
	label.position = Vector2(8, 6)
	panel.add_child(label)
	add_child(panel)
	panel.visible = false


## Shows the city's current values, or hides the panel when city is empty.
func refresh(city: Dictionary) -> void:
	panel.visible = not city.is_empty()
	if city.is_empty():
		label.text = ""
		return
	var growth := growth_per_turn if int(city.population) < max_population else 0
	label.text = "\n".join([
		"City: %d" % city.id,
		"Owner: Nation %d" % city.nation,
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
			label.text += "\nRecruiting: infantry arrives next turn"
	panel.size = label.get_minimum_size() + Vector2(16, 12)