class_name CombatFx
extends Node2D
## Combat feedback juice (Art Director spec via PM, Nov 23): the shared tween/FX helper. Visual only:
## it reads DivisionRoster.fx_events after the orders ran and plays fire-and-forget tweens; combat
## results, turn flow and input never wait on it. reduce_motion (the Esc menu's "Reduce motion",
## saved in user://settings.cfg by GameSettings) turns every effect off: no tweens, no nodes.

const LUNGE_PX := 6.0  # attacker moves toward the target...
const LUNGE_TIME := 0.15  # ...and snaps back, out and back in this time
const SHAKE_PX := 3.0  # defender shake amplitude
const SHAKE_TIME := 0.15
const SHAKE_WAVES := 3.0
const FLASH_FRAMES := 1  # defender drawn white for this many frames on impact
const FLOAT_TIME := 0.8  # floating number rises and fades over this time
const FLOAT_RISE_PX := 24.0
const FLOAT_FONT_SIZE := 14
const DAMAGE_COLOR := Color("#E0583A")
const OUTCOME_COLOR := Color("#E6B85C")  # routed or captured
const DEATH_TIME := 0.4  # a destroyed unit fades and shrinks over this time
const DEATH_SCALE := 0.2
const SCREEN_SHAKE_PX := 3.0  # city capture only
const SCREEN_SHAKE_TIME := 0.25

var view: MapView
var camera: Camera2D
var reduce_motion := false
## Tweens started since the game began (tests check none are made with reduce_motion on).
var tweens_created := 0


func _tween() -> Tween:
	tweens_created += 1
	return create_tween()


func _visible(hex: Vector2i) -> bool:
	return view.fog_state(hex) == Fog.VISIBLE


## Plays one turn's effects: every hit and outcome in `events`, and a screen shake if a visible
## city was captured (`captures`, DivisionRoster.pending_captures). Does nothing with reduce_motion.
func play(events: Array, captures: Array = []) -> void:
	if reduce_motion or view == null:
		return
	for e in events:
		if e.kind == "hit":
			if _visible(e.from) or _visible(e.to):
				_hit(e)
		elif _visible(e.hex):
			_outcome(e)
	for c in captures:
		var city := view.hex_map.city_by_id(int(c.get("city_id", -1)))
		if not city.is_empty() and _visible(city.cell):
			float_text(city.cell, "Captured", OUTCOME_COLOR)
			screen_shake()
			break


func _hit(e: Dictionary) -> void:
	var dir: Vector2 = (view.hex_to_pixel(e.to) - view.hex_to_pixel(e.from)).normalized()
	lunge(int(e.attacker), dir)
	var t := _tween()
	t.tween_interval(LUNGE_TIME / 2.0)
	t.tween_callback(func() -> void:
			view.flash_until[int(e.defender)] = Engine.get_process_frames() + FLASH_FRAMES
			shake(int(e.defender)))
	if float(e.to_defender) > 0.0:
		float_text(e.to, "-%d" % maxi(roundi(float(e.to_defender)), 1), DAMAGE_COLOR, LUNGE_TIME / 2.0)
	if float(e.to_attacker) > 0.0:
		float_text(e.from, "-%d" % maxi(roundi(float(e.to_attacker)), 1), DAMAGE_COLOR, LUNGE_TIME / 2.0)


func _outcome(e: Dictionary) -> void:
	match str(e.outcome):
		"retreated":
			float_text(e.hex, "Routed", OUTCOME_COLOR, LUNGE_TIME)
		"surrendered":
			float_text(e.hex, "Captured", OUTCOME_COLOR, LUNGE_TIME)
			death(e)
		"destroyed":
			death(e)


func _set_offset(id: int, offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		view.unit_offset.erase(id)
	else:
		view.unit_offset[id] = offset
	view.queue_redraw()


## The attacker moves LUNGE_PX toward the target and snaps back over LUNGE_TIME.
func lunge(id: int, dir: Vector2) -> Tween:
	var t := _tween()
	t.tween_method(func(f: float) -> void: _set_offset(id, dir * LUNGE_PX * f), 0.0, 1.0, LUNGE_TIME / 2.0)
	t.tween_method(func(f: float) -> void: _set_offset(id, dir * LUNGE_PX * f), 1.0, 0.0, LUNGE_TIME / 2.0)
	return t


## Side-to-side shake of SHAKE_PX, dying out over SHAKE_TIME.
func shake(id: int) -> Tween:
	var t := _tween()
	t.tween_method(func(f: float) -> void:
			_set_offset(id, Vector2(sin(f * TAU * SHAKE_WAVES) * SHAKE_PX * (1.0 - f), 0.0)), 0.0, 1.0, SHAKE_TIME)
	return t


## A number or word that rises FLOAT_RISE_PX and fades out over FLOAT_TIME.
func float_text(hex: Vector2i, text: String, color: Color, delay := 0.0) -> Node2D:
	var label := FloatText.new()
	label.text = text
	label.color = color
	label.position = view.hex_to_pixel(hex) + Vector2(0, -26)
	label.modulate.a = 0.0 if delay > 0.0 else 1.0
	add_child(label)
	var t := _tween()
	if delay > 0.0:
		t.tween_interval(delay)
		t.tween_property(label, "modulate:a", 1.0, 0.0)
	t.tween_property(label, "position:y", label.position.y - FLOAT_RISE_PX, FLOAT_TIME)
	t.parallel().tween_property(label, "modulate:a", 0.0, FLOAT_TIME).set_ease(Tween.EASE_IN)
	t.tween_callback(label.queue_free)
	return label


## A destroyed (or captured) unit: a ghost counter that fades and shrinks instead of popping.
func death(e: Dictionary) -> Node2D:
	var ghost := Ghost.new()
	ghost.native = int(e.nation) == DivisionRoster.NATIVE_NATION
	ghost.k = view._k()
	var c: Dictionary = view.palette.counter
	ghost.fill = Color.html(c.badge)
	ghost.frame = Color.html(c.badge_frame)
	ghost.stripe = view._color_for(int(e.nation)) if int(e.nation) >= 0 and not view.hidden_nations.has(int(e.nation)) else Color.html(c.neutral_fill)
	ghost.position = view.hex_to_pixel(e.hex) + Vector2(0, -6 * ghost.k)
	add_child(ghost)
	var t := _tween()
	t.tween_property(ghost, "scale", Vector2.ONE * DEATH_SCALE, DEATH_TIME)
	t.parallel().tween_property(ghost, "modulate:a", 0.0, DEATH_TIME)
	t.tween_callback(ghost.queue_free)
	return ghost


## A tiny camera shake (city capture only).
func screen_shake() -> Tween:
	if camera == null:
		return null
	var t := _tween()
	t.tween_method(func(f: float) -> void:
			camera.offset = Vector2(sin(f * TAU * SHAKE_WAVES), cos(f * TAU * SHAKE_WAVES * 0.5)) * SCREEN_SHAKE_PX * (1.0 - f),
			0.0, 1.0, SCREEN_SHAKE_TIME)
	t.tween_callback(func() -> void: camera.offset = Vector2.ZERO)
	return t


## Stops everything at once (reduce motion switched on mid-animation).
func clear() -> void:
	for child in get_children():
		child.queue_free()
	if view:
		view.unit_offset.clear()
		view.flash_until.clear()
		view.queue_redraw()
	if camera:
		camera.offset = Vector2.ZERO
	for t in get_tree().get_processed_tweens() if is_inside_tree() else []:
		if t.is_valid():
			t.kill()


class FloatText extends Node2D:
	var text := ""
	var color := Color.WHITE

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FLOAT_FONT_SIZE).x
		var at := Vector2(-w / 2.0, 0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FLOAT_FONT_SIZE, 4, Color(0, 0, 0, 0.8))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FLOAT_FONT_SIZE, color)


class Ghost extends Node2D:
	var native := false
	var k := 1.0
	var fill := Color.BLACK
	var frame := Color.WHITE
	var stripe := Color.GRAY

	func _draw() -> void:
		if native:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, 13 * k, frame)
			draw_circle(Vector2.ZERO, 11 * k, fill)
			return
		var size := Vector2(40, 34) * k
		var r := Rect2(-size / 2, size)
		var shoulder := r.position.y + size.y * 0.72
		var shield := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, shoulder),
				Vector2(0, r.end.y), Vector2(r.position.x, shoulder)])
		draw_colored_polygon(shield, fill)
		draw_rect(Rect2(r.position, Vector2(size.x, 5 * k)), stripe)
		var loop := shield.duplicate()
		loop.append(shield[0])
		draw_polyline(loop, frame, 2.0)
