class_name MapView
extends Node2D
## Draws a HexMap with placeholder colors. Holds no game logic.

const HEX_SIZE := 30.0
const ORIGIN := Vector2(50, 50)
const WATER_COLOR := Color(0.16, 0.32, 0.55)
const NEUTRAL_COLOR := Color(0.6, 0.6, 0.55)
const NATION_COLORS: Array[Color] = [
	Color(0.85, 0.3, 0.3), Color(0.3, 0.7, 0.35), Color(0.9, 0.75, 0.25),
	Color(0.6, 0.4, 0.8), Color(0.95, 0.55, 0.2), Color(0.3, 0.75, 0.8),
]

var hex_map: HexMap


func hex_to_pixel(cell: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (cell.x + 0.5 * (cell.y % 2))
	return ORIGIN + Vector2(x, HEX_SIZE * 1.5 * cell.y)


func _draw() -> void:
	if hex_map == null:
		return
	for cell in hex_map.cells:
		var corners := _corners(hex_to_pixel(cell))
		draw_colored_polygon(corners, _color_for(hex_map.cells[cell]))
		corners.append(corners[0])
		draw_polyline(corners, Color(0, 0, 0, 0.2), 1.0)
	# Thick lines where two different owners meet.
	for cell in hex_map.cells:
		var owner: int = hex_map.cells[cell]
		if owner < 0:
			continue
		for n in hex_map.neighbors(cell):
			if hex_map.cells[n] != owner:
				_draw_shared_edge(cell, n)


func _draw_shared_edge(cell: Vector2i, other: Vector2i) -> void:
	var other_center := hex_to_pixel(other)
	var corners := Array(_corners(hex_to_pixel(cell)))
	corners.sort_custom(func(a, b): return a.distance_to(other_center) < b.distance_to(other_center))
	draw_line(corners[0], corners[1], Color(0.1, 0.1, 0.1), 3.0)


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