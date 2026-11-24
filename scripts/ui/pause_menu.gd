class_name PauseMenu
extends CanvasLayer
## The in-game Esc menu: Resume, Save Game, Main Menu, Quit, and the Reduce motion and Hide empty turn report toggles. Modal while open.

signal resume_pressed
signal save_pressed
signal main_menu_pressed
signal quit_pressed
signal reduce_motion_toggled(on: bool)
signal report_auto_hide_toggled(on: bool)

var root := Control.new()
var status := Label.new()
var resume_button := Button.new()
var save_button := Button.new()
var menu_button := Button.new()
var quit_button := Button.new()
## Combat FX off switch (saved by main through GameSettings).
var reduce_motion_check := CheckButton.new()
## Turn report: hide the panel when a turn has nothing to report (saved by main through GameSettings).
var report_auto_hide_check := CheckButton.new()


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
	reduce_motion_check.text = "Reduce motion"
	reduce_motion_check.focus_mode = Control.FOCUS_NONE
	box.add_child(reduce_motion_check)
	report_auto_hide_check.text = "Hide empty turn report"
	report_auto_hide_check.focus_mode = Control.FOCUS_NONE
	box.add_child(report_auto_hide_check)
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
	reduce_motion_check.toggled.connect(func(on: bool) -> void: reduce_motion_toggled.emit(on))
	report_auto_hide_check.toggled.connect(func(on: bool) -> void: report_auto_hide_toggled.emit(on))


func is_open() -> bool:
	return root.visible


func open() -> void:
	status.text = ""
	root.visible = true


func close() -> void:
	root.visible = false
