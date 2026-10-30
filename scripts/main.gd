extends Node2D
## Entry scene. Builds the map from data/ configs and shows it.
## Debug: press D to remove the newest city (tests nation elimination).

const GAME_TITLE := "Fault Lines: The Gift"
const MAP_CONFIG_PATH := "res://data/map_config.json"

var _view: MapView


func _ready() -> void:
	get_window().title = GAME_TITLE
	_view = MapView.new()
	_view.hex_map = HexMap.from_config_file(MAP_CONFIG_PATH)
	add_child(_view)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_D:
		var hex_map := _view.hex_map
		if hex_map.cities.is_empty():
			return
		var city: Dictionary = hex_map.cities.back()
		var eliminated := hex_map.remove_city(city.id)
		print("Removed city %d; eliminated nations: %s" % [city.id, eliminated])
		_view.queue_redraw()