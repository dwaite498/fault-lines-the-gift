class_name TopBar
extends CanvasLayer
## 32px top bar: faction on the left, WEEK N in the center, turn on the right.

const HEIGHT := 32.0
var panel := Panel.new()
var faction := Label.new()
var week := Label.new()
var turn_label := Label.new()


func _init() -> void:
	panel.theme_type_variation = &"TopBar"
	panel.position = Vector2.ZERO
	panel.size = Vector2(1280, HEIGHT)
	add_child(panel)
	for l in [faction, week, turn_label]:
		l.size = Vector2(1280 - 16, HEIGHT)
		l.position = Vector2(8, 0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(l)
	week.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	week.add_theme_font_size_override("font_size", 14)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func refresh(faction_name: String, turn: int) -> void:
	faction.text = faction_name
	week.text = ("Week %d" % turn).to_upper()
	turn_label.text = "Turn %d" % turn
