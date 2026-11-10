class_name PauseMenu
extends CanvasLayer
## The in-game Esc menu: Resume, Save Game, Main Menu and Quit. Modal while open.

signal resume_pressed
signal save_pressed
signal main_menu_pressed
signal quit_pressed

var root := Control.new()
var status := Label.new()
var resume_button := Button.new()
var save_button := Button.new()
var menu_button := Button.new()
var quit_button := Button.new()


func _init() -> void:
	layer = 25
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for pair in [[resume_button, "Resume"], [save_button, "Save Game"], [menu_button, "Main Menu"], [quit_button, "Quit"]]:
		pair[0].text = pair[1]
		pair[0].custom_minimum_size = Vector2(200, 36)
		pair[0].focus_mode = Control.FOCUS_NONE
		box.add_child(pair[0])
	box.add_child(status)
	panel.add_child(box)
	center.add_child(panel)
	root.add_child(center)
	add_child(root)
	root.visible = false
	resume_button.pressed.connect(func() -> void: resume_pressed.emit())
	save_button.pressed.connect(func() -> void: save_pressed.emit())
	menu_button.pressed.connect(func() -> void: main_menu_pressed.emit())
	quit_button.pressed.connect(func() -> void: quit_pressed.emit())


func is_open() -> bool:
	return root.visible


func open() -> void:
	status.text = ""
	root.visible = true


func close() -> void:
	root.visible = false
