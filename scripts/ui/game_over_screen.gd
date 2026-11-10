class_name GameOverScreen
extends CanvasLayer
## The victory / defeat screen: New Game (the setup screen) or Main Menu. Modal while open.

signal new_game_pressed
signal main_menu_pressed

var root := Control.new()
var title := Label.new()
var message := Label.new()
var new_button := Button.new()
var menu_button := Button.new()


func _init() -> void:
	layer = 30
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(message)
	for pair in [[new_button, "New Game"], [menu_button, "Main Menu"]]:
		pair[0].text = pair[1]
		pair[0].custom_minimum_size = Vector2(220, 36)
		pair[0].focus_mode = Control.FOCUS_NONE
		box.add_child(pair[0])
	panel.add_child(box)
	center.add_child(panel)
	root.add_child(center)
	add_child(root)
	root.visible = false
	new_button.pressed.connect(func() -> void: new_game_pressed.emit())
	menu_button.pressed.connect(func() -> void: main_menu_pressed.emit())


func is_open() -> bool:
	return root.visible


## Shows the screen for a Victory.check result; winner_name names the winning nation.
func open(result: Dictionary, winner_name := "") -> void:
	title.text = "Victory" if result.result == "victory" else "Defeat"
	if result.result == "victory":
		message.text = "Your nation holds the world: domination victory."
	elif result.reason == "elimination":
		message.text = "Your last city has fallen. Your nation is eliminated."
	else:
		message.text = "%s dominates the world." % (winner_name if winner_name != "" else "Another nation")
	root.visible = true


func close() -> void:
	root.visible = false
