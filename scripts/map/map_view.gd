class_name MapView
extends Node2D
## Draws a HexMap: terrain colors with a tinted nation overlay and borders. No game logic.

const HEX_SIZE := 30.0
const ORIGIN := Vector2(50, 50)
const PALETTE_PATH := "res://data/art_palette.json"
## Colors and line styles from data/art_palette.json (Art PR A).
var palette: Dictionary = load_palette()
## Faction per nation (name, color, leader); set by main.gd. All nation colors come from it.
var factions := FactionRoster.new()
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
		_draw_city(city)
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


## Spec sizes are for a 64px-wide hex; scale to ours.
func _k() -> float:
	return HEX_SIZE * sqrt(3.0) / 64.0


## Counter fill: the nation's faction color darkened; neutral/unknown grey.
func counter_fill(nation: int) -> Color:
	var c: Dictionary = palette.counter
	if nation < 0 or hidden_nations.has(nation):
		return Color.html(c.neutral_fill)
	return _color_for(nation).darkened(float(c.darken))


## "x" (infantry, default), "ellipse" (armor) or "dot" (artillery).
static func symbol_for(unit_type: String) -> String:
	return {"armor": "ellipse", "artillery": "dot"}.get(unit_type, "x")


## [org, strength] bar fill fractions, clamped to 0..1.
static func bar_fractions(d: Division) -> Array[float]:
	return [clampf(d.org / maxf(d.max_org, 0.001), 0.0, 1.0),
			clampf(d.strength / maxf(d.max_strength, 0.001), 0.0, 1.0)]


func spent_alpha() -> float:
	return float(palette.counter.get("spent_alpha", 1.0))


func _draw_counter(d: Division) -> void:
	var k := _k()
	var c: Dictionary = palette.counter
	var light := Color.html(c.frame)
	var size := Vector2(40, 28) * k
	var center := hex_to_pixel(d.hex) + Vector2(0, -4 * k)
	var rect := Rect2(center - size / 2, size)
	var fill := counter_fill(d.nation)
	if d.moves_left <= 0:
		fill.a = spent_alpha()
	draw_rect(rect, fill)
	draw_rect(rect, light, false, 2.0)
	var inner := rect.grow(-4 * k)
	match symbol_for(d.unit_type):
		"x":
			draw_line(inner.position, inner.end, light, 2.0)
			draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), light, 2.0)
		"ellipse":
			var pts := PackedVector2Array()
			for i in 33:
				var a := TAU * i / 32.0
				pts.append(center + Vector2(cos(a) * size.x * 0.35, sin(a) * size.y * 0.25))
			draw_polyline(pts, light, 2.0)
		"dot":
			draw_circle(center, 5 * k, light)
	var font := ThemeDB.fallback_font
	var fs := int(round(10 * k))
	var tw := font.get_string_size("XX", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(center.x - tw / 2, rect.position.y - 2 * k)
	draw_string_outline(font, tp, "XX", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color.html(c.size_outline))
	draw_string(font, tp, "XX", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.html(c.size_text))
	var fr := bar_fractions(d)
	var bar := Vector2(40 * k, 3 * k)
	var y := rect.end.y + 1 * k
	for i in 2:
		var track := Rect2(Vector2(rect.position.x, y), bar)
		draw_rect(track, Color.html(c.track))
		draw_rect(Rect2(track.position, Vector2(bar.x * fr[i], bar.y)), Color.html(c.org if i == 0 else c.str))
		y += bar.y + 1 * k
	if d == selected:
		draw_rect(rect.grow(3.0), Color.html(c.selected), false, 2.0)


## Capital: the lowest-id city of each nation (no capital flag exists yet).
func is_capital(city: Dictionary) -> bool:
	if city.has("capital"):
		return bool(city.capital)
	for other in hex_map.cities:
		if other.nation == city.nation:
			return other.id == city.id
	return false


func _draw_city(city: Dictionary) -> void:
	var k := _k()
	var c: Dictionary = palette.city
	var center := hex_to_pixel(city.cell)
	var half := 8 * k
	var rect := Rect2(center - Vector2(half, half), Vector2(half, half) * 2)
	draw_rect(rect, Color.html(c.fill))
	draw_rect(rect.grow(-2 * k), Color.html(c.ring), false, 2.0)
	if city.nation >= 0 and is_capital(city):
		var star := PackedVector2Array()
		for i in 10:
			var r := (5.0 if i % 2 == 0 else 2.2) * k
			var a := -PI / 2 + PI * i / 5.0
			star.append(center + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(star, Color.html(c.star))
	var label := str(city.get("name", "City %d" % city.id)).to_upper()
	var font := ThemeDB.fallback_font
	var fs := int(round(11 * k))
	var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	# Below the unit bars when a division stands here, so the label stays visible.
	var top := rect.end.y + 4 * k
	if roster and roster.division_at(city.cell):
		top = center.y + (-4 + 14 + 8) * k + 4 * k
	var plate := Rect2(Vector2(center.x - sz.x / 2 - 3 * k, top), Vector2(sz.x + 6 * k, sz.y))
	draw_rect(plate, Color.html(c.plate))
	draw_string(font, Vector2(plate.position.x + 3 * k, top + font.get_ascent(fs)), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.html(c.label))


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
	return factions.color_of(owner)


## 10px swatch in the nation's map color.
static func make_swatch() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(10, 10)
	r.size = Vector2(10, 10)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r
