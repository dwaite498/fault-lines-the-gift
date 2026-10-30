class_name NationPanel
extends CanvasLayer
## Always-visible panel for the player's own nation, in the top-right corner.
## Shows only the player's data (hidden-info rule).

var panel := Panel.new()
var label := Label.new()


func _init() -> void:
	label.position = Vector2(8, 6)
	panel.add_child(label)
	add_child(panel)


## Projected next-turn income for nation, using NationEconomy's formula.
static func projected_income(nation: int, hex_map: HexMap, economy: NationEconomy) -> Dictionary:
	var income := {"cash": 0.0, "influence": 0.0, "operations": 0.0, "manpower": 0.0, "capacity": 0.0}
	if not hex_map.nations.has(nation):
		return income
	income.influence = float(economy.config.influence_per_turn)
	income.operations = float(economy.config.operations_per_turn)
	for city in hex_map.cities:
		if city.nation == nation:
			var c := economy.city_income(city)
			for r in c:
				income[r] += c[r]
	return income


func refresh(nation: int, turn: int, hex_map: HexMap, economy: NationEconomy) -> void:
	var city_count := hex_map.cities.filter(func(c): return c.nation == nation).size()
	var tile_count := hex_map.territory.values().count(nation)
	var lines: Array[String] = [
		"Nation %d - Turn %d" % [nation, turn],
		"Cities: %d   Tiles: %d" % [city_count, tile_count],
	]
	var income := projected_income(nation, hex_map, economy)
	var stock: Dictionary = economy.stocks.get(nation, {})
	for r in NationEconomy.RESOURCES:
		lines.append("%s: %.1f (+%.1f/turn)" % [r.capitalize(), float(stock.get(r, 0.0)), income[r]])
	if city_count == 0:
		lines.append("Closest to falling: eliminated")
	else:
		lines.append("Closest to falling: %d %s left" % [city_count, "city" if city_count == 1 else "cities"])
	label.text = "\n".join(lines)
	panel.size = label.get_minimum_size() + Vector2(16, 12)
	panel.position = Vector2(1280 - panel.size.x - 8, 8)