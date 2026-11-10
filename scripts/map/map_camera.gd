class_name MapCamera
extends Camera2D
## Pan and zoom for the map (Task 34b). Arrow keys pan (WASD would clash with the A and
## D hotkeys), middle-drag and right-drag pan, optional screen-edge scrolling, wheel
## zoom in steps centered on the cursor. The camera is clamped to the map bounds. The
## UI lives on CanvasLayers, so it is not affected. All numbers come from the "camera"
## block of data/map_config.json. The view math (screen_to_world, zoom_at, pan,
## clamp_position) uses only position, zoom, view_size and bounds, so it is testable
## without a running viewport.

## Emitted when the right button is released without having dragged: a plain
## right-click (main.gd cancels the current order on it).
signal secondary_click

var zoom_min := 0.5
var zoom_max := 2.0
var zoom_step := 0.25
## Screen pixels per second for arrow-key and edge-scroll panning.
var pan_speed := 700.0
var edge_scroll_enabled := false
var edge_scroll_margin := 12.0
## Screen pixels the pointer must move with a button held before it counts as a drag.
var drag_threshold := 6.0
## World rect the camera must stay inside (set from MapView.world_bounds()).
var bounds := Rect2()
## Size of the screen area in pixels; follows the viewport.
var view_size := Vector2(1280, 720)

var _drag_button := 0
var _drag_origin := Vector2.ZERO
var _dragging := false


## Loads the camera numbers from a config dictionary (map_config.json "camera" block).
func configure(cfg: Dictionary) -> void:
	zoom_min = float(cfg.get("zoom_min", zoom_min))
	zoom_max = float(cfg.get("zoom_max", zoom_max))
	zoom_step = float(cfg.get("zoom_step", zoom_step))
	pan_speed = float(cfg.get("pan_speed", pan_speed))
	edge_scroll_enabled = bool(cfg.get("edge_scroll_enabled", edge_scroll_enabled))
	edge_scroll_margin = float(cfg.get("edge_scroll_margin", edge_scroll_margin))
	drag_threshold = float(cfg.get("drag_threshold", drag_threshold))


func _ready() -> void:
	ignore_rotation = true
	position_smoothing_enabled = false
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	make_current()
	var vp := get_viewport()
	view_size = vp.get_visible_rect().size
	vp.size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	view_size = get_viewport().get_visible_rect().size
	clamp_position()


## Frames the whole map: the zoom that fits `world_bounds` in the view (kept inside the
## zoom range), centered. Call once after the view and camera exist.
func fit_to(world_bounds: Rect2) -> void:
	bounds = world_bounds
	var fit := minf(view_size.x / bounds.size.x, view_size.y / bounds.size.y)
	zoom = Vector2.ONE * clampf(fit, zoom_min, zoom_max)
	position = bounds.get_center()
	clamp_position()


## World position under a screen (viewport) position.
func screen_to_world(screen: Vector2) -> Vector2:
	return (screen - view_size * 0.5) / zoom.x + position


## Screen (viewport) position of a world position.
func world_to_screen(world: Vector2) -> Vector2:
	return (world - position) * zoom.x + view_size * 0.5


## Sets the zoom (clamped to the range) keeping the world point under `screen` fixed.
func zoom_at(new_zoom: float, screen: Vector2) -> void:
	var anchor := screen_to_world(screen)
	zoom = Vector2.ONE * clampf(new_zoom, zoom_min, zoom_max)
	position = anchor - (screen - view_size * 0.5) / zoom.x
	clamp_position()


## One wheel notch: +1 zooms in, -1 out, by zoom_step, centered on `screen`.
func zoom_notch(direction: int, screen: Vector2) -> void:
	zoom_at(snappedf(zoom.x, 0.0001) + zoom_step * direction, screen)


## Moves the camera by a world-space delta, then clamps.
func pan_world(delta: Vector2) -> void:
	position += delta
	clamp_position()


## Keeps the visible area inside the bounds; an axis where the view is larger than the
## bounds is centered on them.
func clamp_position() -> void:
	if bounds.size == Vector2.ZERO:
		return
	var half := view_size * 0.5 / zoom.x
	var p := position
	if half.x * 2.0 >= bounds.size.x:
		p.x = bounds.get_center().x
	else:
		p.x = clampf(p.x, bounds.position.x + half.x, bounds.end.x - half.x)
	if half.y * 2.0 >= bounds.size.y:
		p.y = bounds.get_center().y
	else:
		p.y = clampf(p.y, bounds.position.y + half.y, bounds.end.y - half.y)
	position = p


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if edge_scroll_enabled:
		dir += _edge_direction(get_viewport().get_mouse_position())
	if dir != Vector2.ZERO:
		pan_world(dir.normalized() * pan_speed * delta / zoom.x)


## Pan direction from the pointer sitting inside the edge margin (zero elsewhere, or
## when the pointer is outside the window).
func _edge_direction(mouse: Vector2) -> Vector2:
	if not Rect2(Vector2.ZERO, view_size).has_point(mouse):
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if mouse.x < edge_scroll_margin:
		dir.x -= 1.0
	elif mouse.x > view_size.x - edge_scroll_margin:
		dir.x += 1.0
	if mouse.y < edge_scroll_margin:
		dir.y -= 1.0
	elif mouse.y > view_size.y - edge_scroll_margin:
		dir.y += 1.0
	return dir


func _unhandled_input(event: InputEvent) -> void:
	if handle_event(event):
		get_viewport().set_input_as_handled()


## Handles wheel zoom and middle/right drag. Returns true if the event was used.
## A right button press is held back until release: no drag means secondary_click.
func handle_event(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			zoom_notch(1, button.position)
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			zoom_notch(-1, button.position)
			return true
		if button.button_index == MOUSE_BUTTON_MIDDLE or button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed:
				_drag_button = button.button_index
				_drag_origin = button.position
				_dragging = button.button_index == MOUSE_BUTTON_MIDDLE
				return true
			if button.button_index == _drag_button:
				var was_drag := _dragging
				_drag_button = 0
				_dragging = false
				if not was_drag and button.button_index == MOUSE_BUTTON_RIGHT:
					secondary_click.emit()
				return true
		return false
	var motion := event as InputEventMouseMotion
	if motion and _drag_button != 0:
		if not _dragging and motion.position.distance_to(_drag_origin) >= drag_threshold:
			_dragging = true
		if _dragging:
			pan_world(-motion.relative / zoom.x)
		return true
	return false
