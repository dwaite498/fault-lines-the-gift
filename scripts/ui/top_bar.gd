class_name TopBar
extends CanvasLayer

## 32px top bar (Mockup M14): the player's faction emblem on the left, one centered amber
## "WEEK N" title, and framed M13 icon buttons (save, pause menu) on the right.
## C2: a compact "Charter n/6" (or "Charter complete") label just right of the emblem;
## hover shows a built-in tooltip of each milestone (window, reward, done). Player only.

## An icon button on the right was clicked (id is a key of ICON_BUTTONS; main.gd runs it
## through the same handler as the panel's M13 buttons).
signal icon_pressed(id: String)

const HEIGHT := 32.0
## Right-side buttons, reusing the M13 icons (assets/ui/icons/icon_<id>[_active].png).
const ICON_BUTTONS := {"save": "Save game", "menu": "Pause menu (Esc)"}
const BUTTON_SIZE := 28.0
var panel := Panel.new()
## Procedural faction emblem: a framed slanted plate with a chevron mark in the faction color.
var emblem := Emblem.new()
var week := Label.new()
## C2 charter tracker, just right of the emblem (hidden when there is no player charter).
var tracker := Label.new()
var icon_row := HBoxContainer.new()
var icon_buttons := {}


class Emblem extends Control:
	var color := Color.WHITE
	const FRAME := Color(0.3098039, 0.4196078, 0.3843137, 1)
	const PLATE := Color(0.05098039, 0.08627451, 0.07843137, 1)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Plate with a slanted right edge, like the mockup's emblem tab.
		var plate := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - h * 0.35, h), Vector2(0, h)])
		draw_colored_polygon(plate, PLATE)
		plate.append(plate[0])
		draw_polyline(plate, FRAME, 1.0)
		# Mark: a rising chevron over a diamond, in the faction color.
		var c := Vector2((w - h * 0.35) * 0.5 + 2.0, h * 0.5)
		var s := h * 0.3
		draw_polyline(PackedVector2Array([c + Vector2(-s, -s * 0.1), c + Vector2(0, -s), c + Vector2(s, -s * 0.1)]), color, 2.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.35), c + Vector2(s * 0.45, s * 0.3),
				c + Vector2(0, s * 0.95), c + Vector2(-s * 0.45, s * 0.3)]), color)


func _init() -> void:
	panel.theme_type_variation = &"TopBar"
	panel.position = Vector2.ZERO
	add_child(panel)
	emblem.position = Vector2.ZERO
	emblem.size = Vector2(52, HEIGHT)
	emblem.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(emblem)
	tracker.theme_type_variation = &"TopBarTitle"
	tracker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tracker.mouse_filter = Control.MOUSE_FILTER_STOP
	tracker.visible = false
	tracker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.add_child(tracker)
	week.theme_type_variation = &"TopBarTitle"
	week.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	week.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	week.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(week)
	icon_row.add_theme_constant_override("separation", 4)
	panel.add_child(icon_row)
	for id: String in ICON_BUTTONS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.tooltip_text = ICON_BUTTONS[id]
		var normal: Texture2D = load("res://assets/ui/icons/icon_%s.png" % id)
		var active: Texture2D = load("res://assets/ui/icons/icon_%s_active.png" % id)
		b.icon = normal
		b.mouse_entered.connect(func() -> void: b.icon = active)
		b.mouse_exited.connect(func() -> void: b.icon = normal)
		b.button_down.connect(func() -> void: b.icon = active)
		b.pressed.connect(func() -> void: icon_pressed.emit(id))
		icon_row.add_child(b)
		icon_buttons[id] = b

func _ready() -> void:
	# Same as the M13 panel buttons: drop the theme's side padding so the 24px icon sits
	# centered in a 28px frame (2px padding).
	for b: Button in icon_buttons.values():
		for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := b.get_theme_stylebox(st).duplicate() as StyleBox
			for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				sb.set_content_margin(side, (BUTTON_SIZE - 24.0) / 2.0)
			b.add_theme_stylebox_override(st, sb)
	_layout()
	get_viewport().size_changed.connect(_layout)

func _place_tracker() -> void:
	tracker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var track_w := maxf(tracker.get_minimum_size().x, 1.0)
	tracker.position = Vector2(52.0 + 8.0, 0)
	tracker.size = Vector2(track_w, HEIGHT)


func _layout() -> void:
	var viewport_width := 1280.0
	if is_inside_tree() and get_viewport() != null:
		var w := get_viewport().get_visible_rect().size.x
		if w > 0.0:
			viewport_width = w
	panel.size = Vector2(viewport_width, HEIGHT)
	emblem.set_anchors_preset(Control.PRESET_TOP_LEFT)
	emblem.position = Vector2.ZERO
	emblem.size = Vector2(52, HEIGHT)
	week.position = Vector2.ZERO
	week.size = Vector2(viewport_width, HEIGHT)
	_place_tracker()
	var row_w := ICON_BUTTONS.size() * BUTTON_SIZE + (ICON_BUTTONS.size() - 1) * 4.0
	icon_row.position = Vector2(viewport_width - row_w - 4.0, (HEIGHT - BUTTON_SIZE) / 2.0)

func refresh(faction_name: String, turn: int, faction_color := Color.WHITE, charter: ColonyCharter = null, show_charter := true) -> void:
	emblem.tooltip_text = faction_name
	if emblem.color != faction_color:
		emblem.color = faction_color
		emblem.queue_redraw()
	week.text = "WEEK %d" % turn
	_refresh_tracker(charter, show_charter)


## Updates the C2 tracker from the player's ColonyCharter. Hidden when `show_charter` is
## false (AI-only views) or when there is no charter.
func _refresh_tracker(charter: ColonyCharter, show_charter: bool) -> void:
	var show := show_charter and charter != null
	tracker.visible = show
	if not show:
		tracker.text = ""
		tracker.tooltip_text = ""
		return
	var total: int = charter.cfg.milestones.size() if charter.cfg.get("milestones") else 0
	var n: int = charter.completed.size()
	tracker.text = "Charter complete" if total > 0 and n >= total else "Charter %d/%d" % [n, total]
	tracker.tooltip_text = _charter_tooltip(charter)
	# Place it even when the bar is not yet in a viewport (tests construct it off-tree).
	_place_tracker()
	if is_inside_tree() and get_viewport() != null:
		_layout()


func _charter_tooltip(charter: ColonyCharter) -> String:
	var lines: Array[String] = []
	for milestone in charter.cfg.get("milestones", []):
		var mark := "✓ " if charter.completed.has(str(milestone.id)) else "  "
		lines.append("%s%s (weeks %d-%d, %s)" % [mark, str(milestone.label),
				int(milestone.window_min), int(milestone.window_max), _reward_text(milestone.get("reward", {}))])
	return "\n".join(lines)


func _reward_text(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if reward.has("cash"):
		parts.append("+%d cash" % int(reward.cash))
	if reward.has("capacity"):
		parts.append("+%d capacity" % int(reward.capacity))
	return ", ".join(parts)
