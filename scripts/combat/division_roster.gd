class_name DivisionRoster
extends RefCounted
## Holds all divisions and the movement rules.

const CONFIG_PATH := "res://data/divisions_config.json"

var divisions: Array[Division] = []
var templates: Dictionary = {}


static func load_templates(path := CONFIG_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Puts one division of template_name on every city hex, owned by that city's nation.
func spawn_at_cities(hex_map: HexMap, template_name := "infantry") -> void:
	if templates.is_empty():
		templates = load_templates()
	divisions.clear()
	for city in hex_map.cities:
		divisions.append(Division.from_template(divisions.size(), city.nation,
				city.cell, templates[template_name]))


func division_at(hex: Vector2i) -> Division:
	for d in divisions:
		if d.hex == hex:
			return d
	return null


## True if d has a move left and hex is an adjacent, unoccupied land hex.
func can_move(d: Division, hex: Vector2i, hex_map: HexMap) -> bool:
	return (d.moves_left > 0
			and hex in hex_map.neighbors(d.hex)
			and hex_map.cells[hex] != HexMap.WATER
			and division_at(hex) == null)


func try_move(d: Division, hex: Vector2i, hex_map: HexMap) -> bool:
	if not can_move(d, hex, hex_map):
		return false
	d.hex = hex
	d.moves_left -= 1
	return true


func end_turn() -> void:
	for d in divisions:
		d.moves_left = d.move