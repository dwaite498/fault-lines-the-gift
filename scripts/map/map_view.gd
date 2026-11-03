class_name MapView
extends Node2D
## Draws a HexMap: terrain colors with a tinted nation overlay and borders. No game logic.

const HEX_SIZE := 30.0
const ORIGIN := Vector2(50, 50)
const PALETTE_PATH := "res://data/art_palette.json"
## Colors and line styles from data/art_palette.json (Art PR A).
var palette: Dictionary = load_palette()
## Nations drawn as neutral (no tint, no border), e.g. hidden minor factions.
var hidden_nations: Array[int] = []

var hex_map: HexMap
var roster: DivisionRoster
var selected: Division
## Valid target hexes for the active action mode, outlined.
var highlights: Array[Vector2i] = []
var player_nation := 0
const ORDER_COLOR := Color(1, 1, 1, 0.9)
const ATTACK_COLOR := Color(0.9, 0.1, 0.1, 0.95)
const CLASH_COLOR := Color(1, 0.85, 0.0, 1.0)


func hex_to_pixel(cell: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (cell.x + 0.5 * (cell.y % 2))
	return ORIGIN + Vector2(x, HEX_SIZE * 1.5 * cell.y)


func _draw() -> void:
	if hex_map == null:
		return
	var grid: Dictionary = palette.grid
	var grid_color := Color(Color.html(grid.color), float(grid.alpha))
	for cell in hex_map.cells:
		var corners := _corners(hex_to_pixel(cell))
		draw_colored_polygon(corners, terrain_color(cell))
		var owner := owner_of(cell)
		if owner >= 0:
			draw_colored_polygon(corners, Color(_color_for(owner), float(palette.tint_alpha)))
		corners.append(corners[0])
		draw_polyline(corners, grid_color, float(grid.width))
	# Dashed border in the nation color on edges between different owners (or owner and neutral).
	for e in border_edges():
		_draw_border(e[0], e[1], _color_for(owner_of(e[0])))
	for city in hex_map.cities:
		var center := hex_to_pixel(city.cell)
		draw_circle(center, HEX_SIZE * 0.35, Color.WHITE)
		draw_arc(center, HEX_SIZE * 0.35, 0.0, TAU, 24, Color.BLACK, 2.0)
	for cell in highlights:
		var hc := _corners(hex_to_pixel(cell))
		hc.append(hc[0])
		draw_polyline(hc, Color(1, 1, 1, 0.9), 3.0)
	if roster:
		for d in roster.divisions:
			_draw_counter(d)
		_draw_orders()


## Arrows for the player's pending orders. Orders ending on the same hex are
## drawn in CLASH_COLOR. AI orders are not shown.
func _draw_orders() -> void:
	var clashes := roster.clash_hexes(player_nation, hex_map)
	for d in roster.divisions:
		if d.nation != player_nation or d.order_path.is_empty():
			continue
		var now := roster.steps_this_turn(d, hex_map)
		var color := CLASH_COLOR if not d.order_attack and now > 0 and clashes.has(d.order_path[now - 1]) else (
				ATTACK_COLOR if d.order_attack else ORDER_COLOR)
		var centers := PackedVector2Array([hex_to_pixel(d.hex)])
		for cell in d.order_path:
			centers.append(hex_to_pixel(cell))
		var points := ArrowCurve.through(centers)
		var width := 4.0 if d.order_attack else 3.0
		# This turn's part solid; later turns dimmer and thinner (Task 25).
		var cut := ArrowCurve.split_index(centers.size(), now, points.size())
		if cut >= 1:
			draw_polyline(points.slice(0, cut + 1), color, width, true)
		if cut < points.size() - 1:
			var later := Color(color, 0.4)
			draw_polyline(points.slice(maxi(cut, 0)), later, width - 1.0, true)
			if cut < points.size() - 1:
				color = later
		var tip := points[points.size() - 1]
		var dir := (tip - points[points.size() - 2]).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 10 + side * 6, tip - dir * 10 - side * 6]), color)


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


static func load_palette(path := PALETTE_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Owner as drawn: hidden nations count as neutral (UNCLAIMED).
func owner_of(cell: Vector2i) -> int:
	var owner: int = hex_map.cells[cell]
	return HexMap.UNCLAIMED if hidden_nations.has(owner) else owner


func terrain_color(cell: Vector2i) -> Color:
	var name := hex_map.terrain_name(cell)
	return Color.html(palette.terrain.get(name, hex_map.terrain_of(cell).color))


## [cell, neighbor] pairs where cell has a visible owner and the neighbor's drawn owner differs.
## Sorted for determinism.
func border_edges() -> Array:
	var out := []
	var keys := hex_map.cells.keys()
	keys.sort()
	for cell in keys:
		var owner := owner_of(cell)
		if owner < 0:
			continue
		for n in hex_map.neighbors(cell):
			if owner_of(n) != owner:
				out.append([cell, n])
	return out


## Dashed line on the shared edge, nudged 1px into cell so both sides show.
func _draw_border(cell: Vector2i, other: Vector2i, color: Color) -> void:
	var center := hex_to_pixel(cell)
	var other_center := hex_to_pixel(other)
	var corners := Array(_corners(center))
	corners.sort_custom(func(a, b): return a.distance_to(other_center) < b.distance_to(other_center))
	var inward := (center - other_center).normalized()
	var from: Vector2 = corners[0] + inward
	var to: Vector2 = corners[1] + inward
	var b: Dictionary = palette.border
	var dash := float(b.dash)
	var gap := float(b.gap)
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var t := 0.0
	while t < length:
		draw_line(from + dir * t, from + dir * minf(t + dash, length), Color(color, float(b.alpha)), float(b.width))
		t += dash + gap


func _corners(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + HEX_SIZE * Vector2(cos(angle), sin(angle)))
	return points


func _color_for(owner: int) -> Color:
	if owner < 0:
		return Color.html(palette.terrain.water if owner == HexMap.WATER else palette.terrain.plains)
	var nations: Array = palette.nations
	return Color.html(nations[owner % nations.size()])
