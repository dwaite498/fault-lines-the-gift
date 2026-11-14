class_name MapView
extends Node2D
## Draws a HexMap in isometric view: raised top faces, side skirts, back-to-front.
## No game logic: cells stay in odd-r hex coordinates, only the drawing and picking
## are iso. Sizes come from palette.iso (96x48 top face, 10px per elevation step).

const PALETTE_PATH := "res://data/art_palette.json"
## Colors and line styles from data/art_palette.json (Art PR A).
var palette: Dictionary = load_palette()
## Faction per nation (name, color, leader); set by main.gd. All nation colors come from it.
var factions := FactionRoster.new()
## Nations drawn as neutral (no tint, no border), e.g. hidden minor factions.
var hidden_nations: Array[int] = []
## Fog of war for player_nation, or null: unexplored tiles are black, explored ones show
## terrain and cities as last seen (dimmed, no units), visible ones are live.
var fog: Fog = null
const EXPLORED_DIM := Color(0, 0, 0, 0.45)

## Iso numbers from palette.iso, cached in _init().
var _w := 96.0
var _h := 48.0
var _step := 10.0
var _origin := Vector2.ZERO
var _min_elev := -3
var _max_elev := 4
var _skirt_dark: Array = [0.35, 0.2]

var hex_map: HexMap
var roster: DivisionRoster
var selected: Division
## Valid target hexes for the active action mode, outlined.
var highlights: Array[Vector2i] = []
## Attack targets blocked by the frontage cap (Task 46), drawn greyed and not clickable.
var blocked_highlights: Array[Vector2i] = []
var player_nation := 0
const ORDER_COLOR := Color(1, 1, 1, 0.9)
const ATTACK_COLOR := Color(0.9, 0.1, 0.1, 0.95)
const CLASH_COLOR := Color(1, 0.85, 0.0, 1.0)


func _init() -> void:
	var iso: Dictionary = palette.iso
	_w = float(iso.tile_w)
	_h = float(iso.tile_h)
	_step = float(iso.step)
	_origin = Vector2(float(iso.origin[0]), float(iso.origin[1]))
	_min_elev = int(iso.min_elev)
	_max_elev = int(iso.max_elev)
	_skirt_dark = iso.skirt_dark
	# 1.0: the camera (MapCamera) handles fit and zoom. Kept as a data value.
	scale = Vector2.ONE * float(iso.view_scale)


## Center of the hex's flat (elevation 0) top face.
func flat_center(cell: Vector2i) -> Vector2:
	return _origin + Vector2(_w * (cell.x + 0.5 * (cell.y % 2)), _h * 0.75 * cell.y)


func elevation_of(cell: Vector2i) -> int:
	return clampi(hex_map.elevation_of(cell), _min_elev, _max_elev)


## Center of the hex's raised top face. Everything drawn on a hex uses this, so
## counters, cities, borders, highlights and arrows all lift with elevation.
func hex_to_pixel(cell: Vector2i) -> Vector2:
	return flat_center(cell) - Vector2(0, drawn_elevation(cell) * _step)


## Elevation the cell is drawn at: water lies flat on the sea plane (0), land at its elevation.
func drawn_elevation(cell: Vector2i) -> int:
	return 0 if is_water(cell) else elevation_of(cell)


func is_water(cell: Vector2i) -> bool:
	return hex_map.terrain_name(cell) == "water"


## Mockup M1: the viewport behind the map is the trench color instead of grey.
func _enter_tree() -> void:
	RenderingServer.set_default_clear_color(Color.html(palette.water_depth.background))


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color"))


func _draw() -> void:
	if hex_map == null:
		return
	var grid: Dictionary = palette.grid
	var grid_color := Color(Color.html(grid.color), float(grid.alpha))
	var edges := {}
	for e in border_edges():
		if not edges.has(e[0]):
			edges[e[0]] = []
		edges[e[0]].append(e[1])
	var city_at := {}
	for city in hex_map.cities:
		if fog_state(city.cell) == Fog.VISIBLE:
			city_at[city.cell] = city
	for cell in hex_map.cells:
		if fog_state(cell) == Fog.EXPLORED:
			var seen: Dictionary = fog.last_seen(player_nation, cell).get("city", {})
			if not seen.is_empty():
				city_at[cell] = {"id": seen.id, "nation": seen.nation, "cell": cell,
						"name": hex_map.city_by_id(int(seen.id)).get("name", "City %d" % int(seen.id)),
						"population": int(seen.get("population", 0)), "remembered": true}
	var units_at := {}
	if roster:
		for d in roster.divisions:
			if d.nation != player_nation and fog_state(d.hex) != Fog.VISIBLE:
				continue
			if not units_at.has(d.hex):
				units_at[d.hex] = []
			units_at[d.hex].append(d)
	# Back to front, row by row. Each row's decor is drawn right after its tiles, so a
	# taller tile in a later row hides what stands behind it. City nameplates (M6) hang below
	# their hex, so each row's plates are drawn after the next row's tiles, under its units.
	var plates := []
	for y in hex_map.height:
		for x in hex_map.width:
			var cell := Vector2i(x, y)
			if not hex_map.cells.has(cell):
				continue
			var fstate := fog_state(cell)
			if fstate == Fog.UNEXPLORED:
				var black := _corners(hex_to_pixel(cell))
				draw_colored_polygon(black, Color.BLACK)
				continue
			for sk in skirt_polys(cell):
				_draw_skirt(cell, sk)
			var corners := _corners(hex_to_pixel(cell))
			draw_colored_polygon(corners, terrain_color(cell))
			var owner := owner_of(cell)
			if owner >= 0:
				draw_colored_polygon(corners, Color(_color_for(owner), float(palette.tint_alpha)))
			if is_water(cell):
				_draw_coast(cell, corners)
			var is_mat := false
			if hex_map.fungus_tiles.has(cell):
				is_mat = _draw_fungus(cell, corners)
			if fstate == Fog.EXPLORED:
				draw_colored_polygon(corners, EXPLORED_DIM)
			corners.append(corners[0])
			_draw_grid(cell, corners, is_mat, grid_color, Color(grid_color, float(grid.alpha_match)), float(grid.width))
		for x in hex_map.width:
			var cell := Vector2i(x, y)
			# Border in the nation color on edges between different owners (solid; dashed under explored fog).
			for other in edges.get(cell, []):
				_draw_border(cell, other, _color_for(owner_of(cell)))
		for city in plates:
			_draw_city_plate(city)
		plates = []
		for x in hex_map.width:
			var cell := Vector2i(x, y)
			if city_at.has(cell):
				_draw_city(city_at[cell])
				plates.append(city_at[cell])
		for x in hex_map.width:
			for d in units_at.get(Vector2i(x, y), []):
				_draw_counter(d)
	for city in plates:
		_draw_city_plate(city)
	var hl: Dictionary = palette.highlight
	var reach_color := Color(Color.html(hl.reach), float(hl.reach_alpha))
	var blocked_color := Color(Color.html(hl.blocked), float(hl.blocked_alpha))
	for cell in highlights:
		var hc := _corners(hex_to_pixel(cell))
		hc.append(hc[0])
		draw_polyline(hc, reach_color, float(hl.width))
	for cell in blocked_highlights:
		var bc := _corners(hex_to_pixel(cell))
		bc.append(bc[0])
		draw_polyline(bc, blocked_color, float(hl.width))
	if roster:
		_draw_orders()


## Skirts on the two front-facing edges of a pointy-top hex (SW and SE), down to the
## neighbor's height (or the lowest level at the map edge). Each is [polygon, color],
## darkened on the left and right by palette.iso.skirt_dark, plus the drop in px.
func skirt_polys(cell: Vector2i) -> Array:
	var out := []
	if is_water(cell):
		return out
	var e := drawn_elevation(cell)
	var base := terrain_color(cell)
	var cs := _corners(hex_to_pixel(cell))
	var odd := cell.y % 2 == 1
	var sw := Vector2i(cell.x if odd else cell.x - 1, cell.y + 1)
	var se := Vector2i(cell.x + 1 if odd else cell.x, cell.y + 1)
	# Corner indexes: 1 lower-right, 2 bottom, 3 lower-left.
	for edge in [[3, 2, sw, 0], [2, 1, se, 1]]:
		var ne := _min_elev
		if hex_map.cells.has(edge[2]):
			ne = drawn_elevation(edge[2])
		var drop := float(e - ne) * _step
		if drop <= 0.0:
			continue
		var a: Vector2 = cs[edge[0]]
		var b: Vector2 = cs[edge[1]]
		out.append([PackedVector2Array([a, b, b + Vector2(0, drop), a + Vector2(0, drop)]),
				base.darkened(float(_skirt_dark[edge[3]])), drop])
	return out


## Draws one skirt from skirt_polys as rock (M7): a top-to-bottom dark gradient, a darker
## base band, and vertical striations seeded from the cell and edge so they never move.
## Steps shorter than palette.cliff.striation_min_drop levels get no striations. No top lip.
func _draw_skirt(cell: Vector2i, sk: Array) -> void:
	var cl: Dictionary = palette.cliff
	var poly: PackedVector2Array = sk[0]
	var col: Color = sk[1]
	var drop: float = sk[2]
	var low := col.darkened(float(cl.gradient_dark))
	draw_polygon(poly, PackedColorArray([col, col, low, low]))
	var band := minf(float(cl.band_px), drop * 0.3)
	var a := poly[0]
	var b := poly[1]
	var dn := Vector2(0, drop - band)
	draw_colored_polygon(PackedVector2Array([a + dn, b + dn, poly[2], poly[3]]), col.darkened(float(cl.band_dark)))
	if drop < float(cl.striation_min_drop) * _step:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cell, a.x < b.x and a.y < b.y])
	var count := int(a.distance_to(b) / float(cl.striation_spacing))
	var dark := col.darkened(float(cl.striation_dark))
	var light := col.lightened(float(cl.striation_light))
	for i in count:
		var p := a.lerp(b, (i + rng.randf_range(0.2, 0.8)) / count)
		var top := p + Vector2(0, rng.randf_range(1.0, drop * 0.3))
		var bottom := p + Vector2(rng.randf_range(-1.0, 1.0), drop - band - rng.randf_range(0.0, drop * 0.2))
		draw_line(top, bottom, dark if rng.randf() < 0.7 else light, 1.0)


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
	return _w / 64.0


## Counter fill: the nation's faction color darkened; neutral/unknown grey.
func counter_fill(nation: int) -> Color:
	var c: Dictionary = palette.counter
	if nation < 0 or hidden_nations.has(nation):
		return Color.html(c.neutral_fill)
	return _color_for(nation).darkened(float(c.darken))


## "x" (infantry, default), "ellipse" (armor), "dot" (artillery) or "plus" (colony pod).
static func symbol_for(unit_type: String) -> String:
	return {"armor": "ellipse", "artillery": "dot", "colony_pod": "plus"}.get(unit_type, "x")


## [org, strength] bar fill fractions, clamped to 0..1.
static func bar_fractions(d: Division) -> Array[float]:
	return [clampf(d.org / maxf(d.max_org, 0.001), 0.0, 1.0),
			clampf(d.strength / maxf(d.max_strength, 0.001), 0.0, 1.0)]


func spent_alpha() -> float:
	return float(palette.counter.get("spent_alpha", 1.0))


## A native creature (no standee plate): a placeholder silhouette with the magenta outline.
## worm: a wavy body; strider: an oval body on four legs.
func _draw_native(d: Division) -> void:
	var k := _k()
	var c: Dictionary = palette.counter
	var outline := Color.html(str(hex_map.natives_config.get("render", {}).get("outline", "#FF00FF")))
	var center := hex_to_pixel(d.hex) + Vector2(0, -2 * k)
	var body := Color.html(c.neutral_fill).lightened(0.2)
	if d.unit_type == "tendril_worm":
		var pts := PackedVector2Array()
		for i in 9:
			pts.append(center + Vector2((i - 4) * 4.0 * k, sin(i * 1.2) * 4.0 * k))
		draw_polyline(pts, outline, 7.0 * k)
		draw_polyline(pts, body, 3.5 * k)
	else:
		var ring := PackedVector2Array()
		for i in 25:
			var a := TAU * i / 24.0
			ring.append(center + Vector2(cos(a) * 13 * k, sin(a) * 7 * k))
		draw_colored_polygon(ring, outline)
		for sx in [-9, -3, 3, 9]:
			draw_line(center + Vector2(sx * k, 5 * k), center + Vector2(sx * k * 1.2, 12 * k), outline, 3.0 * k)
		var inner := PackedVector2Array()
		for i in 25:
			var a := TAU * i / 24.0
			inner.append(center + Vector2(cos(a) * 11 * k, sin(a) * 5 * k))
		draw_colored_polygon(inner, body)
	var fr := bar_fractions(d)
	var bar := Vector2(30 * k, 3 * k)
	var y := center.y + 14 * k
	for i in 2:
		var track := Rect2(Vector2(center.x - bar.x / 2, y), bar)
		draw_rect(track, Color.html(c.track))
		draw_rect(Rect2(track.position, Vector2(bar.x * fr[i], bar.y)), Color.html(c.org if i == 0 else c.str))
		y += bar.y + 1 * k
	if d == selected:
		draw_circle(center, 16 * k, Color.html(c.selected), false, 2.0)


func _draw_counter(d: Division) -> void:
	if d.nation == DivisionRoster.NATIVE_NATION:
		_draw_native(d)
		return
	# Mockup M5: dark shield badge with a gold frame, a faction-color stripe across the top,
	# the NATO symbol in gold and the size number under it.
	var k := _k()
	var c: Dictionary = palette.counter
	var gold := Color.html(c.badge_symbol)
	var size := Vector2(40, 34) * k
	var center := hex_to_pixel(d.hex) + Vector2(0, -6 * k)
	var rect := Rect2(center - size / 2, size)
	var shoulder := rect.position.y + size.y * 0.72
	var shield := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x, shoulder), Vector2(center.x, rect.end.y), Vector2(rect.position.x, shoulder)])
	var fill := Color.html(c.badge)
	var stripe_color := Color.html(c.neutral_fill)
	if d.nation >= 0 and not hidden_nations.has(d.nation):
		stripe_color = _color_for(d.nation)
	if d.moves_left <= 0:
		fill.a = spent_alpha()
		stripe_color.a = spent_alpha()
	draw_colored_polygon(shield, fill)
	var sh := float(c.badge_stripe) * k
	draw_rect(Rect2(rect.position, Vector2(size.x, sh)), stripe_color)
	var loop := shield.duplicate()
	loop.append(shield[0])
	draw_polyline(loop, Color.html(c.badge_frame), float(c.badge_frame_width))
	var inner := Rect2(rect.position.x + 9 * k, rect.position.y + sh + 3 * k, size.x - 18 * k, 11 * k)
	var sc := inner.get_center()
	match symbol_for(d.unit_type):
		"x":
			draw_line(inner.position, inner.end, gold, 2.0)
			draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), gold, 2.0)
		"ellipse":
			var pts := PackedVector2Array()
			for i in 33:
				var a := TAU * i / 32.0
				pts.append(sc + Vector2(cos(a) * inner.size.x * 0.5, sin(a) * inner.size.y * 0.5))
			draw_polyline(pts, gold, 2.0)
		"dot":
			draw_circle(sc, 4 * k, gold)
		"plus":
			draw_line(Vector2(inner.position.x, sc.y), Vector2(inner.end.x, sc.y), gold, 2.0)
			draw_line(Vector2(sc.x, inner.position.y), Vector2(sc.x, inner.end.y), gold, 2.0)
	var font := ThemeDB.fallback_font
	var fs := int(round(8 * k))
	var tw := font.get_string_size("XX", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(center.x - tw / 2, inner.end.y + 2 * k + fs * 0.8)
	draw_string(font, tp, "XX", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gold)
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


## The generic placeholder city: a dome (half disc) on a base, on a platform for sea factions.
func _draw_dome(center: Vector2, half: float, sea: bool, c: Dictionary) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		pts.append(center + Vector2(cos(a) * half, sin(a) * half * 0.9 + half * 0.4))
	draw_colored_polygon(pts, Color.html(c.fill))
	draw_polyline(pts, Color.html(c.ring), 2.0)
	var base := Rect2(center + Vector2(-half, half * 0.4), Vector2(half * 2, half * 0.35))
	draw_rect(base, Color.html(c.ring))
	if sea:
		draw_rect(Rect2(center + Vector2(-half * 1.2, half * 0.75), Vector2(half * 2.4, half * 0.25)), Color.html(c.plate))


func _draw_city(city: Dictionary) -> void:
	var k := _k()
	var c: Dictionary = palette.city
	var center := hex_to_pixel(city.cell)
	var tier := hex_map.tier(city)
	var art: Dictionary = hex_map.faction_art.get(str(hex_map.nation_factions.get(city.nation, "")), {})
	var scale_k := CityArt.tier_scale(hex_map.city_rules.tiers, tier)
	var half := 8 * k * scale_k
	var rect := Rect2(center - Vector2(half, half), Vector2(half, half) * 2)
	var key := CityArt.resolve_key(str(art.get("style", "generic")), tier)
	if key != "":
		var tex: Texture2D = load(CityArt.ART_DIR + key + ".png")
		draw_texture_rect(tex, rect, false)
	else:
		_draw_dome(center, half, art.get("sea", false), c)
	if city.nation >= 0 and is_capital(city):
		var star := PackedVector2Array()
		for i in 10:
			var r := (5.0 if i % 2 == 0 else 2.2) * k
			var a := -PI / 2 + PI * i / 5.0
			star.append(center + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(star, Color.html(c.star))


## Mockup M6 nameplate: dark plate, 1px faction-color border, a faction-color glyph block on
## the left, NAME and POP N (thousands) in two amber lines, centered under the dome.
## A remembered (fogged) city shows its last-seen plate, dimmed.
func _draw_city_plate(city: Dictionary) -> void:
	var k := _k()
	var c: Dictionary = palette.city
	var center := hex_to_pixel(city.cell)
	var half := 8 * k * CityArt.tier_scale(hex_map.city_rules.tiers, hex_map.tier(city))
	var rect := Rect2(center - Vector2(half, half), Vector2(half, half) * 2)
	var dim := float(c.remembered_alpha) if city.get("remembered", false) else 1.0
	var faction := Color.html(c.ring)
	if city.nation >= 0 and not hidden_nations.has(city.nation):
		faction = _color_for(city.nation)
	faction.a = dim
	var text_color := Color(Color.html(c.plate_text), dim)
	var city_name := str(city.get("name", "City %d" % int(city.id))).to_upper()
	var pop := "POP %dk" % roundi(int(city.get("population", 0)) / 1000.0)
	var font := ThemeDB.fallback_font
	var fs := int(round(9 * k))
	var fs2 := int(round(8 * k))
	var name_w := font.get_string_size(city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pop_w := font.get_string_size(pop, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	var pad := 3 * k
	var glyph_w := 5 * k
	var text_w := maxf(name_w, pop_w)
	var line1 := font.get_height(fs)
	var line2 := font.get_height(fs2)
	var size := Vector2(pad + glyph_w + pad + text_w + pad, pad + line1 + line2 + pad * 0.5)
	# Below the unit bars when a division stands here, so the plate stays visible.
	var top := rect.end.y + 4 * k
	if roster and roster.division_at(city.cell):
		top = center.y + (-4 + 14 + 8) * k + 4 * k
	var plate := Rect2(Vector2(center.x - size.x / 2, top), size)
	draw_rect(plate, Color(Color.html(c.plate), dim))
	draw_rect(plate, faction, false, float(c.plate_border_width))
	draw_rect(Rect2(plate.position + Vector2(pad, pad), Vector2(glyph_w, size.y - pad * 2)), faction)
	var tx := plate.position.x + pad + glyph_w + pad
	draw_string(font, Vector2(tx + (text_w - name_w) / 2, top + pad + font.get_ascent(fs)), city_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	draw_string(font, Vector2(tx + (text_w - pop_w) / 2, top + pad + line1 + font.get_ascent(fs2)), pop,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, text_color)


## The world rect the camera may show: every hex including raised faces and skirts.
func world_bounds() -> Rect2:
	var left := _origin.x - _w * 0.5
	var right := _origin.x + _w * (hex_map.width + 0.5)
	var top := _origin.y - _h * 0.5 - _max_elev * _step
	var bottom := _origin.y + _h * 0.75 * (hex_map.height - 1) + _h * 0.5 - _min_elev * _step
	return Rect2(Vector2(left, top) * scale, Vector2(right - left, bottom - top) * scale)


## The cell under a position (this node's parent space: world coordinates, not screen;
## use MapCamera.screen_to_world first for a click),
## or Vector2i(-1, -1). Matches the draw order: rows from front to back, and within a
## row the raised top faces (drawn last, higher elevation first) before that row's
## skirts. A tall tile therefore covers what is behind it, and a click on a front
## tile's skirt picks that tile rather than a higher tile behind.
func pixel_to_hex(pos: Vector2) -> Vector2i:
	var p := to_local(pos)
	for y in range(hex_map.height - 1, -1, -1):
		var best := Vector2i(-1, -1)
		for x in hex_map.width:
			var cell := Vector2i(x, y)
			if hex_map.cells.has(cell) and Geometry2D.is_point_in_polygon(p, _corners(hex_to_pixel(cell))):
				if best.x < 0 or elevation_of(cell) > elevation_of(best):
					best = cell
		if best.x >= 0:
			return best
		for x in range(hex_map.width - 1, -1, -1):
			var cell := Vector2i(x, y)
			if not hex_map.cells.has(cell):
				continue
			for sk in skirt_polys(cell):
				if Geometry2D.is_point_in_polygon(p, sk[0]):
					return cell
	return Vector2i(-1, -1)


static func load_palette(path := PALETTE_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Owner as drawn: hidden nations count as neutral (UNCLAIMED).
func owner_of(cell: Vector2i) -> int:
	var owner: int = hex_map.cells[cell]
	match fog_state(cell):
		Fog.UNEXPLORED:
			return HexMap.UNCLAIMED
		Fog.EXPLORED:
			owner = int(fog.last_seen(player_nation, cell).get("owner", HexMap.UNCLAIMED))
	return HexMap.UNCLAIMED if hidden_nations.has(owner) else owner


## Fog.UNEXPLORED, EXPLORED or VISIBLE for player_nation at cell (VISIBLE with no fog).
func fog_state(cell: Vector2i) -> int:
	return Fog.VISIBLE if fog == null else fog.state(player_nation, cell)


func terrain_color(cell: Vector2i) -> Color:
	var name := hex_map.terrain_name(cell)
	if name == "water":
		return water_color(cell)
	return Color.html(palette.terrain.get(name, hex_map.terrain_of(cell).color))


## Mockup M1: water color by depth. Depth is the deeper of the hex's own depth (-elevation)
## and its distance in hexes from land (shallows next to land are 1), so the sea is lighter
## near land and darker offshore: 1 / 2 / 3 -> water_depth.levels, 4+ -> trench.
func water_color(cell: Vector2i) -> Color:
	var wd: Dictionary = palette.water_depth
	var levels: Array = wd.levels
	var depth := maxi(int(_land_distance().get(cell, levels.size() + 1)), -hex_map.elevation_of(cell))
	if depth > levels.size():
		return Color.html(wd.trench)
	return Color.html(levels[maxi(depth, 1) - 1])


var _dist_map: HexMap = null
var _dist_key := 0
var _dist := {}


## Hexes from the nearest land for each water cell (BFS), cached per HexMap and terrain; capped at 4.
func _land_distance() -> Dictionary:
	var key := hex_map.terrain.hash() ^ hex_map.cells.size()
	if _dist_map == hex_map and _dist_key == key:
		return _dist
	_dist_map = hex_map
	_dist_key = key
	_dist = {}
	var frontier: Array[Vector2i] = []
	for cell in hex_map.cells:
		if not is_water(cell):
			_dist[cell] = 0
			frontier.append(cell)
	var level := 0
	while not frontier.is_empty() and level < 4:
		level += 1
		var next: Array[Vector2i] = []
		for cell in frontier:
			for n in hex_map.neighbors(cell):
				if hex_map.cells.has(n) and not _dist.has(n):
					_dist[n] = level
					next.append(n)
		frontier = next
	return _dist


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


## Mockup M2b: border on cell's side of the edge shared with other, inset border.inset px into
## cell so two neighboring nations show two parallel lines in their own colors (and a coast
## border stays on the land side). A 1px keyline sits on the outer (edge) side of the 3px line.
## Solid for visible ownership; dashed only for remembered ownership under explored fog.
func _draw_border(cell: Vector2i, other: Vector2i, color: Color) -> void:
	var center := hex_to_pixel(cell)
	var d := flat_center(other) - flat_center(cell)
	# Direction in regular-hex terms, 0 = east, 60 = south-east ...; edge i joins corners i and i+1.
	var ang := rad_to_deg(atan2(d.y / (_h * 0.75) * 1.5, d.x / _w * sqrt(3.0)))
	var i := posmod(roundi(ang / 60.0), 6)
	var corners := _corners(center)
	var b: Dictionary = palette.border
	var width := float(b.width)
	var inset := float(b.inset)
	var kw := float(b.keyline_width)
	var key := Color(Color.html(b.keyline), float(b.keyline_alpha))
	var line := Color(color, float(b.alpha))
	var dashed := fog_state(cell) == Fog.EXPLORED
	var ks := _inset_edge(corners, center, i, inset - kw * 0.5)
	var ls := _inset_edge(corners, center, i, inset + width * 0.5)
	_border_stroke(ks[0], ks[1], key, kw, dashed)
	_border_stroke(ls[0], ls[1], line, width, dashed)


## A solid line, or border.dash / border.gap dashes along it.
func _border_stroke(from: Vector2, to: Vector2, color: Color, width: float, dashed: bool) -> void:
	if not dashed:
		draw_line(from, to, color, width)
		return
	var b: Dictionary = palette.border
	var dash := float(b.dash)
	var gap := float(b.gap)
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var t := 0.0
	while t < length:
		draw_line(from + dir * t, from + dir * minf(t + dash, length), color, width)
		t += dash + gap


## Edge i of the face (corners i to i+1) moved k px toward center, with its ends trimmed where
## it meets the neighboring edges moved by the same amount, so lines on adjacent edges join.
func _inset_edge(corners: PackedVector2Array, center: Vector2, i: int, k: float) -> Array:
	var lines := []
	for j in [i - 1, i, i + 1]:
		var a: Vector2 = corners[posmod(j, 6)]
		var c: Vector2 = corners[posmod(j + 1, 6)]
		var n := (c - a).orthogonal().normalized()
		if n.dot(center - a) < 0.0:
			n = -n
		lines.append([a + n * k, c - a])
	var from = Geometry2D.line_intersects_line(lines[0][0], lines[0][1], lines[1][0], lines[1][1])
	var to = Geometry2D.line_intersects_line(lines[1][0], lines[1][1], lines[2][0], lines[2][1])
	if from == null or to == null:
		return [lines[1][0], lines[1][0] + lines[1][1]]
	return [from, to]


## Mockup M3: on each edge of a water hex shared with land, a soft lighter band about
## halo_width px wide on the water side (three stacked strips, so it fades out) and a
## foam_width px foam line just inside the edge. Edges toward unexplored land are skipped.
func _draw_coast(cell: Vector2i, corners: PackedVector2Array) -> void:
	var c: Dictionary = palette.coast
	var center := hex_to_pixel(cell)
	var foam := Color(Color.html(c.foam), float(c.foam_alpha))
	var halo := Color(Color.html(c.halo), float(c.halo_alpha) / 3.0)
	var hw := float(c.halo_width)
	for n in hex_map.neighbors(cell):
		if not hex_map.cells.has(n) or is_water(n) or fog_state(n) == Fog.UNEXPLORED:
			continue
		var d := flat_center(n) - flat_center(cell)
		var ang := rad_to_deg(atan2(d.y / (_h * 0.75) * 1.5, d.x / _w * sqrt(3.0)))
		var i := posmod(roundi(ang / 60.0), 6)
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 6]
		var inward := (center - (a + b) * 0.5).normalized()
		for k in 3:
			var w := hw * float(3 - k) / 3.0
			draw_colored_polygon(PackedVector2Array([a, b, b + inward * w, a + inward * w]), halo)
		var off := inward * float(c.foam_width) * 0.5
		draw_line(a + off, b + off, foam, float(c.foam_width))


## Pink worm fungus on the top face (UI v2 U2): `base` at the density's alpha with density + 1
## vein strokes; a mat (density 4, or 5+ of 6 neighbors fungus) is `base` at mat_alpha with 4 strokes.
## Strokes are seeded from the cell, so they are identical on every redraw and after a load.
## Returns true for a mat.
func _draw_fungus(cell: Vector2i, corners: PackedVector2Array) -> bool:
	var fp: Dictionary = palette.fungus
	var density := clampi(int(hex_map.fungus_tiles[cell]), 1, 4)
	var mat := density >= 4 or _fungus_neighbors(cell) >= 5
	var alpha := float(fp.mat_alpha) if mat else float(fp.alpha_by_density[density - 1])
	draw_colored_polygon(corners, Color(Color.html(fp.base), alpha))
	var strokes := 4 if mat else density + 1
	var vein := Color.html(fp.vein)
	var light := Color.html(fp.highlight)
	var center := hex_to_pixel(cell)
	var rx := _w * 0.5 * 0.8
	var ry := _h * 0.5 * 0.7
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell)
	for s in strokes:
		var start := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * 0.3
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var side := Vector2(-dir.y, dir.x)
		var phase := rng.randf() * TAU
		var pts := PackedVector2Array()
		for i in 7:
			var t := float(i) / 6.0 - 0.5
			var p := start + dir * t + side * (0.15 * sin(t * TAU * 1.5 + phase))
			if p.length() > 0.95:
				p = p.normalized() * 0.95
			pts.append(center + Vector2(p.x * rx, p.y * ry))
		var up := PackedVector2Array()
		for p in pts:
			up.append(p + Vector2(0, -1))
		draw_polyline(pts, vein, 2.0, true)
		draw_polyline(up, light, 1.0, true)
	return mat


func _fungus_neighbors(cell: Vector2i) -> int:
	var n := 0
	for o in hex_map.neighbors(cell):
		if hex_map.fungus_tiles.has(o):
			n += 1
	return n


## The cell's grid outline (Mockup M4). An edge to a hex with the same terrain and elevation is
## drawn faint (grid.alpha_match) and only once, from the later-drawn hex, so a plateau reads
## as one mass; edges to differing, unexplored or missing neighbors keep the full grid line.
## An edge that carries a territory border (M2b) gets no grid line.
## An edge shared with another mat hex is drawn at half alpha (U2). `corners` is the closed loop.
func _draw_grid(cell: Vector2i, corners: PackedVector2Array, is_mat: bool, full: Color, faint: Color, width: float) -> void:
	var by_edge := {}
	for o in hex_map.neighbors(cell):
		if not hex_map.cells.has(o):
			continue
		var d := flat_center(o) - flat_center(cell)
		var ang := rad_to_deg(atan2(d.y / (_h * 0.75) * 1.5, d.x / _w * sqrt(3.0)))
		by_edge[posmod(roundi(ang / 60.0), 6)] = o
	for i in 6:
		var color := full
		if by_edge.has(i):
			var o: Vector2i = by_edge[i]
			var own := owner_of(cell)
			var other_own := owner_of(o)
			if own != other_own and (own >= 0 or other_own >= 0):
				continue
			if fog_state(o) != Fog.UNEXPLORED and hex_map.terrain_name(o) == hex_map.terrain_name(cell) \
					and drawn_elevation(o) == drawn_elevation(cell):
				if o.y > cell.y or (o.y == cell.y and o.x > cell.x):
					continue
				color = faint
			if is_mat and _is_mat(o):
				color = Color(color, color.a * 0.5)
		draw_line(corners[i], corners[i + 1], color, width)


func _is_mat(cell: Vector2i) -> bool:
	return hex_map.fungus_tiles.has(cell) and (int(hex_map.fungus_tiles[cell]) >= 4 or _fungus_neighbors(cell) >= 5)


## The 96x48 top face around center: corner i is at angle 60*i - 30 degrees.
func _corners(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle) * _w * 0.5 / (sqrt(3.0) / 2.0), sin(angle) * _h * 0.5))
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
