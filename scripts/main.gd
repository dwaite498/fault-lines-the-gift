extends Node2D
## Entry scene. Builds the map and divisions from data/ configs and shows them.
## Controls: click your division to select it, then click an adjacent land hex to
## move or an adjacent enemy to attack. F fortifies. Space ends the turn (the AI
## nations act first). Debug: D removes the newest city.

const GAME_TITLE := "Fault Lines: The Gift"
const MAP_CONFIG_PATH := "res://data/map_config.json"
## The human player's nation for now.
const PLAYER_NATION := 0

var _view: MapView
var _panel: UnitPanel
var _city_panel: CityPanel
## The city shown in the city panel, or {} when closed.
var _city: Dictionary = {}


func _ready() -> void:
	get_window().title = GAME_TITLE
	_view = MapView.new()
	_view.hex_map = HexMap.from_config_file(MAP_CONFIG_PATH)
	_view.roster = DivisionRoster.new()
	_view.roster.spawn_at_cities(_view.hex_map)
	add_child(_view)
	_panel = UnitPanel.new()
	_panel.max_fortify = int(_view.roster.combat.max_fortify)
	add_child(_panel)
	_city_panel = CityPanel.new()
	_city_panel.growth_per_turn = int(_view.hex_map.city_rules.growth_per_turn)
	_city_panel.max_population = int(_view.hex_map.city_rules.max_population)
	add_child(_city_panel)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_on_hex_clicked(_view.pixel_to_hex(click.position))
		return
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	var roster := _view.roster
	if key.keycode == KEY_SPACE:
		roster.run_ai(PLAYER_NATION, _view.hex_map)
		roster.end_turn()
		_view.hex_map.grow_cities()
		print("Turn ended")
	elif key.keycode == KEY_F and _view.selected:
		roster.fortify(_view.selected)
	elif key.keycode == KEY_D and OS.is_debug_build():
		var hex_map := _view.hex_map
		if hex_map.cities.is_empty():
			return
		var city: Dictionary = hex_map.cities.back()
		var eliminated := hex_map.remove_city(city.id)
		roster.disband(eliminated)
		print("Removed city %d; eliminated nations: %s" % [city.id, eliminated])
	if _view.selected and not roster.divisions.has(_view.selected):
		_view.selected = null
	if not _view.hex_map.cities.has(_city):
		_city = {}
	_refresh_panels()


func _refresh_panels() -> void:
	_panel.refresh(_view.selected, _view.hex_map)
	_city_panel.refresh(_city)
	_view.queue_redraw()


func _on_hex_clicked(hex: Vector2i) -> void:
	if hex == Vector2i(-1, -1):
		return
	var roster := _view.roster
	var target := roster.division_at(hex)
	var selected := _view.selected
	_city = {}
	if selected and roster.can_attack(selected, target, _view.hex_map):
		print("Attack: ", roster.attack(selected, target, _view.hex_map))
	elif selected and roster.try_move(selected, hex, _view.hex_map):
		pass
	else:
		_view.selected = target if target and target.nation == PLAYER_NATION else null
		if selected == null and _view.selected == null:
			_city = _view.hex_map.city_at(hex)
	if _view.selected and not roster.divisions.has(_view.selected):
		_view.selected = null
	_refresh_panels()
