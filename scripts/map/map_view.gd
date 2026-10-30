class_name MapView
extends Node2D
## Draws a HexMap: terrain colors with a tinted nation overlay and borders. No game logic.

const HEX_SIZE := 30.0
const ORIGIN := Vector2(50, 50)
const WATER_COLOR := Color(0.16, 0.32, 0.55)
const NEUTRAL_COLOR := Color(0.6, 0.6, 0.55)
const NATION_COLORS: Array[Color] = [
	Color(0.85, 0.3, 0.3), Color(0.3, 0.7, 0.35), Color(0.9, 0.75, 0.25),
	Color(0.6, 0.4, 0.8), Color(0.95, 0.55, 0.2), Color(0.3, 0.75, 0.8),
]

var hex_map: HexMap
var roster: DivisionRoster
var selected: Division


func hex_to_pixel(cell: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (cell.x + 0.5 * (cell.y % 2))
	return ORIGIN + Vector2(x, HEX_SIZE * 1.5 * cell.y)


func _draw() -> void:
	if hex_map == null:
		return
	for cell in hex_map.cells:
		var corners := _corners(hex_to_pixel(cell))
		draw_colored_polygon(corners, Color.html(hex_map.terrain_of(cell).color))
		var owner: int = hex_map.cells[cell]
		if owner >= 0:
			draw_colored_polygon(corners, Color(_color_for(owner), 0.3))
		corners.append(corners[0])
		draw_polyline(corners, Color(0, 0, 0, 0.2), 1.0)
	# Thick lines in the nation's color where two different owners meet.
	for cell in hex_map.cells:
		var owner: int = hex_map.cells[cell]
		if owner < 0:
			continue
		for n in hex_map.neighbors(cell):
			if hex_map.cells[n] != owner:
				_draw_shared_edge(cell, n, _color_for(owner))
	for city in hex_map.cities:
		var center := hex_to_pixel(city.cell)
		draw_circle(center, HEX_SIZE * 0.35, Color.WHITE)
		draw_arc(center, HEX_SIZE * 0.35, 0.0, TAU, 24, Color.BLACK, 2.0)
	if roster:
		for d in roster.divisions:
			_draw_counter(d)


## A small rectangle in the owner's color; yellow outline when selected,
## faded once it has no moves left.
func _draw_counter(d: Division) -> void:
	var rect := Rect2(hex_to_pixel(d.hex) + Vector2(-11, -2), Vector2(22, 14))
	var color := _color_for(d.nation)
	if d.moves_left <= 0:
		color = color.darkened(0.4)
	draw_rect(rect, color)
	var outline := Color.YELLOW if d == selected else Color.BLACK
	draw_rect(rect, outline, false, 2.0)


## The cell under a pixel position, or Vector2i(-1, -1) if none.
func pixel_to_hex(pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := HEX_SIZE
	for cell in hex_map.cells:
		var dist := pos.distance_to(hex_to_pixel(cell))
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best


func _draw_shared_edge(cell: Vector2i, other: Vector2i, color: Color) -> void:
	var other_center := hex_to_pixel(other)
	var corners := Array(_corners(hex_to_pixel(cell)))
	corners.sort_custom(func(a, b): return a.distance_to(other_center) < b.distance_to(other_center))
	draw_line(corners[0], corners[1], color.darkened(0.3), 4.0)


func _corners(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + HEX_SIZE * Vector2(cos(angle), sin(angle)))
	return points


func _color_for(owner: int) -> Color:
	if owner == HexMap.WATER:
		return WATER_COLOR
	if owner == HexMap.UNCLAIMED:
		return NEUTRAL_COLOR
	return NATION_COLORS[owner % NATION_COLORS.size()]