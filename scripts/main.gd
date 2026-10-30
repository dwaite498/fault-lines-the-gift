extends Node2D
## Entry scene. Builds the map and divisions from data/ configs and shows them.
## Controls: click your division to select it, click an adjacent land hex to move.
## Space ends the turn. Debug: D removes the newest city.

const GAME_TITLE := "Fault Lines: The Gift"
const MAP_CONFIG_PATH := "res://data/map_config.json"
## The human player's nation for now.
const PLAYER_NATION := 0

var _view: MapView


func _ready() -> void:
	get_window().title = GAME_TITLE
	_view = MapView.new()
	_view.hex_map = HexMap.from_config_file(MAP_CONFIG_PATH)
	_view.roster = DivisionRoster.new()
	_view.roster.spawn_at_cities(_view.hex_map)
	add_child(_view)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_on_hex_clicked(_view.pixel_to_hex(click.position))
		return
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		_view.roster.end_turn()
		print("Turn ended")
		_view.queue_redraw()
	elif key.keycode == KEY_D and OS.is_debug_build():
		var hex_map := _view.hex_map
		if hex_map.cities.is_empty():
			return
		var city: Dictionary = hex_map.cities.back()
		var eliminated := hex_map.remove_city(city.id)
		print("Removed city %d; eliminated nations: %s" % [city.id, eliminated])
		_view.queue_redraw()


func _on_hex_clicked(hex: Vector2i) -> void:
	if hex == Vector2i(-1, -1):
		return
	var roster := _view.roster
	if _view.selected and roster.try_move(_view.selected, hex, _view.hex_map):
		pass
	else:
		var d := roster.division_at(hex)
		_view.selected = d if d and d.nation == PLAYER_NATION else null
	_view.queue_redraw()