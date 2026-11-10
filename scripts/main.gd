extends Node2D
## Entry scene. Builds the map and divisions from data/ configs and shows them.
## Controls: click your division to select it, then click a reachable hex to order
## a move or an adjacent enemy to order an attack (right-click without dragging, or Esc, clears the
## order). Camera: arrow keys pan, middle/right-drag pans, wheel zooms at the cursor. F fortifies. Space ends the turn and executes all orders (AI orders are
## issued at the start of each turn, before yours). With your city panel open, R recruits infantry. N toggles the military panel. Capturing a city opens a popup to choose Annex, Occupy, Plunder, Reduce, Raze or Enslave; an occupied city shows an Annex button once its timer is up. Debug: K removes the newest city.

const GAME_TITLE := "Fault Lines: Planetfall"
const MAP_CONFIG_PATH := "res://data/map_config.json"
## The human player's nation for now.
const PLAYER_NATION := 0

var _view: MapView
var _camera := MapCamera.new()
var _panel: UnitPanel
var _city_panel: CityPanel
var _economy: NationEconomy
## The city shown in the city panel, or {} when closed.
var _city: Dictionary = {}
var _nation_panel: NationPanel
var _military_panel: MilitaryPanel
var _capture_popup := CapturePopup.new()
var _top_bar := TopBar.new()
## Brief on-screen message (e.g. why R was blocked). Cleared on the next action.
var message := Label.new()
var turn := 1
## Active target mode: "", "move", "attack" or "follow".
var _mode := ""


func _ready() -> void:
	get_window().title = GAME_TITLE
	_view = MapView.new()
	var map_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_CONFIG_PATH))
	var factions := FactionRoster.from_config(map_cfg)
	_view.factions = factions
	_view.hex_map = HexMap.from_config_file(MAP_CONFIG_PATH, "res://data/cities_config.json",
			"res://data/terrain_config.json", factions.sea_nations())
	_view.hex_map.nation_factions = factions.nation_ids()
	_view.hex_map.load_faction_views(factions.all)
	_view.roster = DivisionRoster.new()
	_view.roster.spawn_at_cities(_view.hex_map)
	_view.hidden_nations = _view.roster.neutral_nations
	add_child(_view)
	_camera.configure(map_cfg.get("camera", {}))
	add_child(_camera)
	_camera.fit_to(_view.world_bounds())
	_camera.secondary_click.connect(do_action.bind("cancel"))
	_economy = NationEconomy.new()
	_economy.setup(_view.hex_map)
	_view.roster.economy = _economy
	_panel = UnitPanel.new()
	_panel.max_fortify = int(_view.roster.combat.max_fortify)
	_panel.flank_per_hex = float(_view.roster.combat.flank_penalty_per_hex)
	_panel.flank_min_mult = float(_view.roster.combat.flank_min_mult)
	add_child(_panel)
	_city_panel = CityPanel.new()
	_city_panel.hex_map = _view.hex_map
	_city_panel.economy = _economy
	_city_panel.roster = _view.roster
	_city_panel.player_nation = PLAYER_NATION
	_city_panel.recruit_pressed.connect(_on_recruit_pressed)
	_city_panel.labor_pressed.connect(_on_labor_pressed)
	_city_panel.annex_pressed.connect(_on_annex_pressed)
	_capture_popup.chosen.connect(_on_capture_chosen)
	add_child(_capture_popup)
	_panel.roster = _view.roster
	_panel.player_nation = PLAYER_NATION
	_panel.factions = factions
	_city_panel.factions = factions
	_panel.economy = _economy
	_panel.action_pressed.connect(do_action)
	add_child(_city_panel)
	_nation_panel = NationPanel.new()
	_nation_panel.factions = factions
	add_child(_nation_panel)
	_military_panel = MilitaryPanel.new()
	_military_panel.factions = factions
	_military_panel.max_fortify = _panel.max_fortify
	add_child(_military_panel)
	add_child(_top_bar)
	var layer := CanvasLayer.new()
	message.position = Vector2(8, 690)
	message.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	layer.add_child(message)
	add_child(layer)
	_view.roster.run_ai(PLAYER_NATION, _view.hex_map)
	_refresh_panels()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_on_hex_clicked(_view.pixel_to_hex(_camera.screen_to_world(click.position)))
		return
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	if _capture_popup.is_open():
		return  # the capture choice comes first
	message.text = ""
	var roster := _view.roster
	if key.keycode == KEY_SPACE:
		_set_mode("")
		_economy.run_ai(PLAYER_NATION, _view.hex_map, roster)
		roster.execute_orders(_view.hex_map)
		_resolve_captures()
	elif ACTION_KEYS.has(key.keycode):
		do_action(ACTION_KEYS[key.keycode])
		return
	elif key.keycode == KEY_TAB:
		select_unit(next_idle_unit(_view.selected))
	elif key.keycode == KEY_R and not _city.is_empty() and _city.nation == PLAYER_NATION:
		_try_recruit()
	elif key.keycode == KEY_N:
		_military_panel.toggle()
	elif key.keycode == KEY_K and OS.is_debug_build():
		var hex_map := _view.hex_map
		if hex_map.cities.is_empty():
			return
		var city: Dictionary = hex_map.cities.back()
		var eliminated := hex_map.remove_city(city.id)
		roster.disband(eliminated)
		print("Removed city %d; eliminated nations: %s" % [city.id, eliminated])
	if _view.selected and not roster.divisions.has(_view.selected):
		select_unit(null)
	if not _view.hex_map.cities.has(_city):
		_city = {}
	_refresh_panels()


## After the orders ran: the AI's captures take its default choice, then each of the
## player's captures asks for a choice in the popup. The turn finishes once none is left.
func _resolve_captures() -> void:
	var roster := _view.roster
	roster.resolve_ai_captures(_view.hex_map, PLAYER_NATION)
	if roster.pending_captures.is_empty():
		_finish_turn()
		return
	var info: Dictionary = roster.pending_captures[0]
	var victim := _view.hex_map.city_by_id(int(info.city_id))
	var blocked := {}
	for id in _view.hex_map.city_rules.capture.order:
		if _view.hex_map.capture_block_reason(PLAYER_NATION, id) != "":
			blocked[id] = "Not available to the %s." % _view.factions.name_of(PLAYER_NATION)
	_capture_popup.open(victim, _view.factions.name_of(int(info.victim)), _view.hex_map.city_rules, blocked)
	_refresh_panels()


func _on_capture_chosen(option: String) -> void:
	var roster := _view.roster
	var info: Dictionary = roster.pending_captures[0]
	var result := roster.apply_capture(int(info.city_id), option, _view.hex_map)
	message.text = "City %d: %s" % [int(info.city_id), option]
	print("Capture choice: %s" % [result])
	_resolve_captures()
	if _view.selected and not roster.divisions.has(_view.selected):
		select_unit(null)
	if not _view.hex_map.cities.has(_city):
		_city = {}
	_refresh_panels()


## The rest of the turn, after every capture is resolved.
func _finish_turn() -> void:
	var roster := _view.roster
	roster.end_turn(_view.hex_map)
	_view.hex_map.grow_cities(roster.unit_cells())
	_economy.end_turn(_view.hex_map, roster)
	turn += 1
	var stalled := _economy.stalled_cities(PLAYER_NATION, _view.hex_map)
	if not stalled.is_empty():
		message.text = "Recruit stalled in city %s: assign Training labor" % ", ".join(stalled.map(func(i: int) -> String: return str(i)))
	roster.run_ai(PLAYER_NATION, _view.hex_map)
	print("Turn ended")


func _on_annex_pressed() -> void:
	message.text = ""
	if not _city.is_empty() and _city.nation == PLAYER_NATION and _view.hex_map.annex_occupied(int(_city.id)):
		message.text = "City %d annexed" % int(_city.id)
	_refresh_panels()


## Hotkeys for the unit panel's action buttons (Task 26). N toggles the military
## panel (was M); K is the debug remove-city key (was D).
const ACTION_KEYS := {KEY_M: "move", KEY_A: "attack", KEY_D: "dig_in", KEY_F: "follow", KEY_ESCAPE: "cancel"}


## Selects d (or nothing) and leaves any target mode.
func select_unit(d: Division) -> void:
	_view.selected = d
	_set_mode("")


func _set_mode(mode: String) -> void:
	_mode = mode
	_view.highlights.clear()
	if mode != "" and _view.selected:
		_view.highlights = _view.roster.action_targets(_view.selected, mode, _view.hex_map)


## Button or hotkey for one of the selected unit's actions. Move/Attack/Follow
## enter a target mode; Dig in replaces the order with fortify; Cancel leaves a
## target mode if one is active, otherwise clears the order. Invalid actions do nothing.
func do_action(action: String) -> void:
	var d := _view.selected
	message.text = ""
	if action == "cancel" and _mode != "":
		_set_mode("")
	elif d and d.nation == PLAYER_NATION and _view.roster.valid_actions(d, _view.hex_map).has(action):
		if action == "cancel":
			_view.roster.clear_order(d)
		elif action == "dig_in":
			_view.roster.clear_order(d)
			_view.roster.fortify(d)
		else:
			_set_mode(action)
	_refresh_panels()


## Next player division with no order after `after` in id order, wrapping; null if none.
func next_idle_unit(after: Division) -> Division:
	var idle: Array[Division] = []
	for d in _view.roster.divisions:
		if d.nation == PLAYER_NATION and d.order_path.is_empty():
			idle.append(d)
	if idle.is_empty():
		return null
	idle.sort_custom(func(x: Division, y: Division) -> bool: return x.id < y.id)
	for d in idle:
		if after == null or d.id > after.id:
			return d
	return idle[0]


func _refresh_panels() -> void:
	_economy.refresh_labor(_view.hex_map)
	var acts: Array[String] = []
	if _view.selected and _view.selected.nation == PLAYER_NATION:
		acts = _view.roster.valid_actions(_view.selected, _view.hex_map)
	_panel.refresh(_view.selected, _view.hex_map, acts, _mode)
	_city_panel.refresh(_city)
	_top_bar.refresh(_view.factions.name_of(PLAYER_NATION), turn)
	_nation_panel.refresh(PLAYER_NATION, turn, _view.hex_map, _economy)
	var np := _nation_panel.panel
	_military_panel.refresh(PLAYER_NATION, _view.roster, _economy, np.position.y + np.size.y + 8, _view.hex_map)
	_view.queue_redraw()


## Left-click. In a target mode, a highlighted hex sets the order (selection
## stays) and any other hex just leaves the mode. With no mode, a click only
## selects: a unit (any nation; a second click on it shows the city under it),
## else the city there, else nothing. It never creates an order.
func _on_hex_clicked(hex: Vector2i) -> void:
	if hex == Vector2i(-1, -1) or _capture_popup.is_open():
		return
	var roster := _view.roster
	message.text = ""
	var selected := _view.selected
	if _mode != "":
		if selected and _view.highlights.has(hex):
			var target := roster.division_at(hex)
			if _mode == "follow" and target and not roster.is_leaving(target):
				roster.set_swap(selected, target, _view.hex_map)
			else:
				roster.set_order(selected, hex, _view.hex_map)
		_set_mode("")
		_refresh_panels()
		return
	var unit := roster.division_at(hex)
	_city = {}
	if unit and unit != selected:
		select_unit(unit)
	else:
		select_unit(null)
		_city = _view.hex_map.city_at(hex)
	_refresh_panels()


## R key and the city panel's Recruit button.
func _try_recruit() -> void:
	var reason := _economy.recruit_block_reason(_city, PLAYER_NATION, _view.roster)
	if reason == "":
		_economy.recruit(_city, PLAYER_NATION, _view.roster)
		print("Recruiting at city %d; arrives in %d turns" % [_city.id, int(_economy.config.training_turns)])
	else:
		message.text = "Cannot recruit: " + reason
		print(message.text)


## A city panel labor button: +1 or -1 point on a sink of the open player city.
func _on_labor_pressed(sink: String, delta: int) -> void:
	if not _city.is_empty() and _city.nation == PLAYER_NATION:
		_economy.adjust_labor(_city, sink, delta)
	_refresh_panels()


func _on_recruit_pressed() -> void:
	message.text = ""
	if not _city.is_empty() and _city.nation == PLAYER_NATION:
		_try_recruit()
	_refresh_panels()
