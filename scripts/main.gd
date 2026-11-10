extends Node2D
## Entry scene. Builds the map and divisions from data/ configs and shows them.
## Controls: click your division to select it, then click a reachable hex to order
## a move or an adjacent enemy to order an attack (right-click without dragging, or Esc, clears the
## order). Camera: arrow keys pan, middle/right-drag pans, wheel zooms at the cursor. F fortifies. Esc opens the menu (Save Game, Main Menu, Quit) when there is nothing to cancel. Space ends the turn and executes all orders (AI orders are
## issued at the start of each turn, before yours). With your city panel open, R recruits infantry, S queues a scout, P queues a colony pod (B on a selected pod founds an Outpost). N toggles the military panel. Capturing a city opens a popup to choose Annex, Occupy, Plunder, Reduce, Raze or Enslave; an occupied city shows an Annex button once its timer is up. Debug: K removes the newest city.

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
var _pause_menu := PauseMenu.new()
var _fog: Fog
var _game_over := GameOverScreen.new()
## Share of nation-owned cities that wins by domination (map_config.json "victory").
var _domination_share := Victory.DEFAULT_SHARE
## The applied map config the game started from (saved with the game).
var _map_cfg := {}
## Set when this run was loaded from a save: skips the start-of-game AI orders.
var _loaded := false
var _top_bar := TopBar.new()
## Brief on-screen message (e.g. why R was blocked). Cleared on the next action.
var message := Label.new()
var turn := 1
## Active target mode: "", "move", "attack" or "follow".
var _mode := ""


func _ready() -> void:
	get_window().title = GAME_TITLE
	_view = MapView.new()
	var saved := {}
	if GameSession.load_requested:
		saved = SaveGame.read(SaveGame.latest_path())
		if saved.is_empty():
			push_warning("No readable save to load; starting a new game")
	GameSession.load_requested = false
	var map_cfg: Dictionary = saved.map_cfg if not saved.is_empty() else GameSession.apply(
			JSON.parse_string(FileAccess.get_file_as_string(MAP_CONFIG_PATH)))
	_map_cfg = map_cfg
	var factions := FactionRoster.from_config(map_cfg)
	if not saved.is_empty():
		factions.assigned.assign(saved.faction_ids.map(func(id: String) -> Dictionary:
				return factions.all.filter(func(f: Dictionary) -> bool: return f.id == id)[0]))
	_view.factions = factions
	_view.hex_map = HexMap.from_config_file(MAP_CONFIG_PATH, "res://data/cities_config.json",
			"res://data/terrain_config.json", factions.sea_nations(), map_cfg)
	_view.hex_map.nation_factions = factions.nation_ids()
	_view.hex_map.load_faction_views(factions.all)
	_view.hex_map.load_faction_traits(factions.all, FactionRoster.load_global())
	_view.hex_map.load_attitude(factions.all, FactionRoster.load_global(), FactionRoster.load_ai())
	_view.hex_map.load_natives_config(NativeSpawner.load_config())
	_view.roster = DivisionRoster.new()
	_view.roster.traits = _view.hex_map.traits
	_view.roster.spawn_at_cities(_view.hex_map)
	if saved.is_empty():
		_view.hex_map.place_fungus(_view.roster.rng)  # a loaded game brings its own fungus
	_view.hidden_nations = _view.roster.neutral_nations
	_fog = Fog.from_config(map_cfg, PLAYER_NATION)
	_view.roster.fog = _fog
	_view.fog = _fog
	_view.player_nation = PLAYER_NATION
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
	_city_panel.rush_pressed.connect(func() -> void:
			if not _city.is_empty() and _city.nation == PLAYER_NATION:
				_economy.rush_training(_city, PLAYER_NATION)
			_refresh_panels())
	_city_panel.scout_pressed.connect(func() -> void:
			message.text = ""
			if not _city.is_empty() and _city.nation == PLAYER_NATION:
				_try_scout()
			_refresh_panels())
	_city_panel.pod_pressed.connect(func() -> void:
			message.text = ""
			if not _city.is_empty() and _city.nation == PLAYER_NATION:
				_try_colony_pod()
			_refresh_panels())
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
	_pause_menu.resume_pressed.connect(_pause_menu.close)
	_pause_menu.save_pressed.connect(_on_save_pressed)
	_pause_menu.main_menu_pressed.connect(_on_main_menu_pressed)
	_pause_menu.quit_pressed.connect(func() -> void: get_tree().quit())
	add_child(_pause_menu)
	_domination_share = float(map_cfg.get("victory", {}).get("domination_share", Victory.DEFAULT_SHARE))
	_game_over.new_game_pressed.connect(_on_game_over_new_game)
	_game_over.main_menu_pressed.connect(_on_main_menu_pressed)
	add_child(_game_over)
	if not saved.is_empty():
		turn = SaveGame.restore(saved, _view.hex_map, _view.roster, _economy)
		_fog.restore(saved.extras.get("fog", {}))
		_view.hex_map.pressure.restore(saved.extras.get("pressure", {}))
		_loaded = true
		print("Loaded the saved game at turn %d" % turn)
	else:
		_fog.explore_landing(_view.hex_map)
		_view.roster.run_ai(PLAYER_NATION, _view.hex_map)
	# A loaded game keeps the saved labor plans: a city just occupied (labor cleared) is not refilled.
	_refresh_panels(saved.is_empty())


## The game state for saving.
func _capture_state() -> Dictionary:
	_fog.update(_view.hex_map, _view.roster)
	var ids: Array = []
	for i in _view.factions.assigned.size():
		ids.append(_view.factions.id_of(i))
	return SaveGame.capture(_view.hex_map, _view.roster, _economy, turn, _map_cfg, ids, {"fog": _fog.capture(), "pressure": _view.hex_map.pressure.capture()})


func _on_save_pressed() -> void:
	_pause_menu.status.text = "Game saved" if SaveGame.write(SaveGame.SLOT_PATH, _capture_state()) else "Could not save"


func _on_game_over_new_game() -> void:
	GameSession.open_setup = true
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


## Victory / defeat check, end of each turn. Shows the end screen and drops the autosave
## (a finished game is not resumed). Returns true if the game is over.
func _check_game_over() -> bool:
	var result := Victory.check(_view.hex_map, PLAYER_NATION, _domination_share, _view.roster.neutral_nations)
	if not result.over:
		return false
	var winner_name := ""
	if int(result.winner) >= 0:
		winner_name = str(_view.factions.assigned[int(result.winner)].get("name", ""))
	_game_over.open(result, winner_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.AUTOSAVE_PATH))
	print("Game over: %s by %s (winner nation %d)" % [result.result, result.reason, result.winner])
	return true


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


## Esc: leave a target mode, else cancel the selected unit's order, else toggle the menu.
func _escape() -> void:
	var d := _view.selected
	if _pause_menu.is_open():
		_pause_menu.close()
	elif _mode != "" or (d and d.nation == PLAYER_NATION and not d.order_path.is_empty()):
		do_action("cancel")
	else:
		_pause_menu.open()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_on_hex_clicked(_view.pixel_to_hex(_camera.screen_to_world(click.position)))
		return
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	if _game_over.is_open():
		return  # only the end screen's buttons work
	if key.keycode == KEY_ESCAPE and not _capture_popup.is_open():
		_escape()
		return
	if _capture_popup.is_open() or _pause_menu.is_open() or _game_over.is_open():
		return  # the capture choice or the menu comes first
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
	elif key.keycode == KEY_P and not _city.is_empty() and _city.nation == PLAYER_NATION:
		_try_colony_pod()
	elif key.keycode == KEY_S and not _city.is_empty() and _city.nation == PLAYER_NATION:
		_try_scout()
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
		var reason := _view.hex_map.capture_block_reason(PLAYER_NATION, id, int(info.city_id))
		if reason == "not allowed for this faction":
			blocked[id] = "Not available to the %s." % _view.factions.name_of(PLAYER_NATION)
		elif reason != "":
			blocked[id] = reason.capitalize() + "."  # e.g. the plunder cooldown, with turns left
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
	var tier_log: Array[String] = []
	for change in _view.hex_map.tier_changes:
		var line := _view.hex_map.tier_change_text(change)
		print("turn_log: ", line)
		if int(change.nation) == PLAYER_NATION:
			tier_log.append(line)
	if not tier_log.is_empty():
		message.text = ". ".join(tier_log)
	_economy.end_turn(_view.hex_map, roster)
	turn += 1
	_view.hex_map.current_turn = turn
	var world_events := _view.hex_map.pressure.end_turn(_view.hex_map, turn)
	if not world_events.is_empty():
		message.text = ". ".join(world_events)
	NativeSpawner.run(_view.hex_map, roster, turn)
	NativeAI.raid_step(_view.hex_map, roster, turn)
	var stalled := _economy.stalled_cities(PLAYER_NATION, _view.hex_map)
	if not stalled.is_empty():
		message.text = "Recruit stalled in city %s: assign Training labor" % ", ".join(stalled.map(func(i: int) -> String: return str(i)))
	if _check_game_over():
		return
	roster.run_ai(PLAYER_NATION, _view.hex_map)
	SaveGame.write(SaveGame.AUTOSAVE_PATH, _capture_state())
	print("Turn ended")


func _on_annex_pressed() -> void:
	message.text = ""
	if not _city.is_empty() and _city.nation == PLAYER_NATION and _view.hex_map.annex_occupied(int(_city.id)):
		message.text = "City %d annexed" % int(_city.id)
	_refresh_panels()


## Hotkeys for the unit panel's action buttons (Task 26). N toggles the military
## panel (was M); K is the debug remove-city key (was D).
const ACTION_KEYS := {KEY_M: "move", KEY_A: "attack", KEY_D: "dig_in", KEY_F: "follow", KEY_B: "found", KEY_ESCAPE: "cancel"}


## Selects d (or nothing) and leaves any target mode.
func select_unit(d: Division) -> void:
	_view.selected = d
	_set_mode("")


func _set_mode(mode: String) -> void:
	_mode = mode
	_view.highlights.clear()
	_view.blocked_highlights.clear()
	if mode != "" and _view.selected:
		_view.highlights = _view.roster.action_targets(_view.selected, mode, _view.hex_map)
		if mode == "attack":
			_view.blocked_highlights = _view.roster.frontage_blocked_targets(_view.selected, _view.hex_map)


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
		elif action == "found":
			var city := _view.roster.found_city(d, _view.hex_map)
			message.text = "Founded an Outpost" if not city.is_empty() else "Cannot found a city here"
			select_unit(null)
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


func _refresh_panels(refill_labor := true) -> void:
	if refill_labor:
		_economy.refresh_labor(_view.hex_map)
	_fog.update(_view.hex_map, _view.roster)
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
	if hex == Vector2i(-1, -1) or _capture_popup.is_open() or _pause_menu.is_open() or _game_over.is_open():
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
	if unit and unit.nation != PLAYER_NATION and not _fog.can_target(PLAYER_NATION, hex):
		unit = null  # an enemy in the fog cannot be selected
	_city = {}
	if unit and unit != selected:
		select_unit(unit)
	else:
		select_unit(null)
		_city = _view.hex_map.city_at(hex)
		if not _city.is_empty() and _city.nation != PLAYER_NATION and not _fog.can_target(PLAYER_NATION, hex):
			var seen: Dictionary = _fog.last_seen(PLAYER_NATION, hex).get("city", {})
			message.text = "Last seen: %s city, %s" % [_view.factions.name_of(int(seen.nation)), seen.tier] if not seen.is_empty() else ""
			_city = {}
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


## S key and the city panel's Scout button.
func _try_scout() -> void:
	var reason := _economy.scout_block_reason(_city, PLAYER_NATION, _view.roster)
	if reason == "":
		_economy.queue_scout(_city, PLAYER_NATION, _view.roster)
		print("Scout queued at city %d" % _city.id)
	else:
		message.text = "Cannot queue a scout: " + reason
		print(message.text)


## P key and the city panel's Colony pod button.
func _try_colony_pod() -> void:
	var reason := _economy.colony_block_reason(_city, PLAYER_NATION)
	if reason == "":
		_economy.queue_colony_pod(_city, PLAYER_NATION)
		print("Colony pod queued at city %d" % _city.id)
	else:
		message.text = "Cannot queue a colony pod: " + reason
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
