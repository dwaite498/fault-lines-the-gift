extends Node2D
## Entry scene. Builds the map from data/map_config.json and shows it.

const GAME_TITLE := "Fault Lines: The Gift"
const MAP_CONFIG_PATH := "res://data/map_config.json"


func _ready() -> void:
	get_window().title = GAME_TITLE
	var view := MapView.new()
	view.hex_map = HexMap.from_config_file(MAP_CONFIG_PATH)
	add_child(view)