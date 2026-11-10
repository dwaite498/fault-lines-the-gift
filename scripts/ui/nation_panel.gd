class_name NationPanel
extends CanvasLayer

const SIDE_WIDTH := 240.0

var panel := Panel.new()
var label := Label.new()
var swatch := MapView.make_swatch()
var factions: FactionRoster

func _init() -> void:
	label.position = Vector2(22, 6)
	swatch.position = Vector2(8, 10)
	panel.add_child(swatch)
	panel.add_child(label)
	add_child(panel)

static func projected_income(nation: int, hex_map: HexMap, economy: NationEconomy) -> Dictionary:
	var income := {"cash": 0.0, "influence": 0.0, "operations": 0.0, "capacity": 0.0}
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
	var tile_count := hex_map.cells.values().count(nation)
	var lines: Array[String] = [
		"%s - Turn %d" % [factions.name_of(nation), turn],
		"Leader: %s" % factions.leader_of(nation),
		"Cities: %d   Tiles: %d" % [city_count, tile_count],
	]
	var income := projected_income(nation, hex_map, economy)
	var stock: Dictionary = economy.stocks.get(nation, {})
	for r in NationEconomy.RESOURCES:
		lines.append("%s: %.1f (+%.1f/turn)" % [r.capitalize(), float(stock.get(r, 0.0)), income[r]])
	var labor := economy.labor_totals(nation, hex_map)
	lines.append("Recruitable: %s people" % CityPanel.people_text(economy.recruitable_total(nation, hex_map)))
	lines.append("Labor: %d (%d free)" % [labor.total, labor.free])
	lines.append("  Training %d, Infrastructure %d, Growth %d" % [labor.training, labor.infrastructure, labor.growth])
	lines.append("POWs held: %d" % roundi(economy.pows_held(nation)))
	lines.append("POWs lost: %d" % roundi(economy.pows_lost(nation)))
	if city_count == 0:
		lines.append("Closest to falling: eliminated")
	else:
		lines.append("Closest to falling: %d %s left" % [city_count, "city" if city_count == 1 else "cities"])
	label.text = "\n".join(lines)
	swatch.color = factions.color_of(nation)
	panel.size = label.get_minimum_size() + Vector2(30, 12)
	panel.position = Vector2(get_viewport().get_visible_rect().size.x - SIDE_WIDTH - panel.size.x - 8, 40)
