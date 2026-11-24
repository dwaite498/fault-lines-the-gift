class_name TurnReport
extends CanvasLayer
## End-of-turn report (PM rulings, Nov 23): what changed for the player this turn, built only from
## data the turn already produces (tier_changes, the new divisions after the economy step,
## NativeAI.raid_step / NativeSpawner.run returns, the Pressure and planet-event lines). Lines with a
## cell center the camera when clicked; a click outside the panel, Close or Esc dismisses it.

signal line_pressed(cell: Vector2i)

const NO_CELL := Vector2i(-1, -1)

var root := Control.new()
var panel := PanelContainer.new()
var list := VBoxContainer.new()
var title := Label.new()
var close_button := Button.new()
## The lines shown: {"text": String, "cell": Vector2i (NO_CELL = plain text)}.
var lines: Array = []


func _init() -> void:
	layer = 18
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_root_input)
	panel.position = Vector2(12, TopBar.HEIGHT + 12)
	panel.custom_minimum_size = Vector2(320, 0)
	list.add_theme_constant_override("separation", 4)
	title.text = "Turn report"
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	list.add_child(title)
	list.add_child(close_button)
	panel.add_child(list)
	root.add_child(panel)
	add_child(root)
	root.visible = false


func is_open() -> bool:
	return root.visible


## True if the report should open for these lines (auto_hide skips an empty report).
static func should_show(report_lines: Array, auto_hide: bool) -> bool:
	return not (report_lines.is_empty() and auto_hide)


## Rebuilds the panel for `report_lines` and opens it.
func open(report_lines: Array) -> void:
	lines = report_lines
	for child in list.get_children():
		if child != title and child != close_button:
			list.remove_child(child)
			child.queue_free()
	if lines.is_empty():
		var none := Label.new()
		none.text = "Nothing new this turn."
		list.add_child(none)
	for line in lines:
		if line.cell == NO_CELL:
			var label := Label.new()
			label.text = str(line.text)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(label)
		else:
			var b := Button.new()
			b.text = str(line.text)
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func() -> void: line_pressed.emit(line.cell))
			list.add_child(b)
	list.move_child(close_button, -1)
	panel.reset_size()
	panel.call_deferred("reset_size")  # once the new rows have their sizes
	root.visible = true


func close() -> void:
	root.visible = false


func _on_root_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and not panel.get_global_rect().has_point(click.global_position):
		close()  # a click outside the panel dismisses it


static func _line(text: String, cell := NO_CELL) -> Dictionary:
	return {"text": text, "cell": cell}


static func _city_name(city: Dictionary) -> String:
	return str(city.get("name", "City %d" % int(city.get("id", -1))))


## The report lines for `player`, in this order: cities, new units, raids, sightings, Pressure,
## planet events. new_divisions are the player's divisions that appeared in the economy step;
## raided and spawned are the NativeAI.raid_step and NativeSpawner.run returns; is_visible(cell)
## says whether the player sees a hex; radius is natives.json sighting_report_radius.
static func collect(hex_map: HexMap, player: int, new_divisions: Array, raided: Array, spawned: Array,
		is_visible: Callable, radius: int, pressure_lines: Array, planet_lines: Array) -> Array:
	var out: Array = []
	for change in hex_map.tier_changes:
		if int(change.nation) != player:
			continue
		var city := hex_map.city_by_id(int(change.city_id))
		out.append(_line("%s %s to %s" % [_city_name(city), "grew" if change.grew else "shrank",
				str(change.to).capitalize()], city.get("cell", NO_CELL)))
	for d in new_divisions:
		var home := _city_name(hex_map.city_by_id(d.home_city_id))
		if d.unit_type == "colony_pod":
			out.append(_line("Colony pod ready in %s" % home, d.hex))
		else:
			out.append(_line("%s trained in %s" % [str(d.unit_type).capitalize(), home], d.hex))
	for city in raided:
		if int(city.nation) == player:
			out.append(_line("Natives raided %s" % _city_name(city), city.cell))
	for d in spawned:
		if not is_visible.call(d.hex):
			continue
		for city in hex_map.cities:
			if int(city.nation) == player and HexMap.hex_distance(d.hex, city.cell) <= radius:
				out.append(_line("Natives sighted near %s" % _city_name(city), d.hex))
				break
	for text in pressure_lines:
		out.append(_line(str(text)))
	for text in planet_lines:
		out.append(_line(str(text)))
	return out
