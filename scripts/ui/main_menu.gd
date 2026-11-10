class_name MainMenu
extends Control
## The main menu (the project's main scene): New Game, Load Game and Quit. New Game opens
## the setup screen: faction picker (playable factions), map seed (Random button plus a text
## field), number of AI nations (within map_config.json "setup") and Start. Nothing else.

const GAME_SCENE := "res://scenes/main.tscn"

## The player pressed Start: {"player_faction", "seed", "ai_count"}.
signal new_game(settings: Dictionary)
signal load_game
signal quit_game

var menu_box := VBoxContainer.new()
var setup_box := VBoxContainer.new()
var new_button := Button.new()
var load_button := Button.new()
var quit_button := Button.new()
var faction_picker := OptionButton.new()
var seed_field := LineEdit.new()
var random_button := Button.new()
var ai_spin := SpinBox.new()
var start_button := Button.new()
var back_button := Button.new()
var _factions: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 16)
	center.add_child(holder)
	var title := Label.new()
	title.text = "Fault Lines: Planetfall"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	holder.add_child(title)
	holder.add_child(menu_box)
	holder.add_child(setup_box)
	menu_box.add_theme_constant_override("separation", 8)
	setup_box.add_theme_constant_override("separation", 8)
	for pair in [[new_button, "New Game"], [load_button, "Load Game"], [quit_button, "Quit"]]:
		pair[0].text = pair[1]
		pair[0].custom_minimum_size = Vector2(220, 40)
		menu_box.add_child(pair[0])
	_build_setup()
	new_button.pressed.connect(show_setup)
	back_button.pressed.connect(show_menu)
	start_button.pressed.connect(func() -> void: new_game.emit(build_settings()))
	load_button.pressed.connect(func() -> void: load_game.emit())
	quit_button.pressed.connect(func() -> void: quit_game.emit())
	random_button.pressed.connect(randomize_seed)
	show_menu()


func _ready() -> void:
	new_game.connect(_go_new_game)
	load_game.connect(_go_load_game)
	quit_game.connect(func() -> void: get_tree().quit())


func _build_setup() -> void:
	var limits := GameSession.setup_limits()
	_factions.assign(FactionRoster.load_all().filter(func(f: Dictionary) -> bool: return f.get("playable", true)))
	for f in _factions:
		faction_picker.add_item(str(f.name))
	var seed_row := HBoxContainer.new()
	seed_field.custom_minimum_size = Vector2(140, 0)
	seed_field.placeholder_text = "Map seed"
	random_button.text = "Random"
	seed_row.add_child(seed_field)
	seed_row.add_child(random_button)
	ai_spin.min_value = int(limits.min_ai)
	ai_spin.max_value = int(limits.max_ai)
	ai_spin.step = 1
	ai_spin.value = int(limits.default_ai)
	start_button.text = "Start"
	back_button.text = "Back"
	setup_box.add_child(_row("Faction", faction_picker))
	setup_box.add_child(_row("Map seed", seed_row))
	setup_box.add_child(_row("AI nations", ai_spin))
	setup_box.add_child(start_button)
	setup_box.add_child(back_button)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameSession.SETUP_CONFIG_PATH))
	seed_field.text = str(int(cfg.seed))


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(100, 0)
	row.add_child(l)
	row.add_child(control)
	return row


func show_menu() -> void:
	menu_box.visible = true
	setup_box.visible = false


func show_setup() -> void:
	menu_box.visible = false
	setup_box.visible = true


## Puts a random seed in the text field.
func randomize_seed() -> void:
	_rng.randomize()
	seed_field.text = str(_rng.randi_range(1, 999999))


## The setup screen's choices. An empty or non-numeric seed gets a random one.
func build_settings() -> Dictionary:
	if not seed_field.text.strip_edges().is_valid_int():
		randomize_seed()
	return {
		"player_faction": str(_factions[faction_picker.selected].id),
		"seed": seed_field.text.strip_edges().to_int(),
		"ai_count": int(ai_spin.value),
	}


func _go_new_game(settings: Dictionary) -> void:
	GameSession.settings = settings
	GameSession.load_requested = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _go_load_game() -> void:
	GameSession.load_requested = true
	get_tree().change_scene_to_file(GAME_SCENE)
