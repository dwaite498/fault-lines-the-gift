extends SceneTree
## Headless test runner. Run from the project root:
##   godot --headless --path . -s tests/run_tests.gd
## Prints PASS/FAIL per check and exits non-zero if any fail.

var fails := 0
var checks := 0
var terrain_cfg: Dictionary
var combat_cfg: Dictionary


func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
	print(("PASS " if cond else "FAIL ") + msg)


func _initialize() -> void:
	terrain_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain_config.json"))
	combat_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_config.json"))
	test_climb_cost()
	test_cliff_blocking()
	test_multi_turn_paths()
	test_uphill_penalty()
	test_uphill_damage()
	test_reachability()
	test_camera()
	test_population()
	test_player_faction_warning()
	test_labor()
	test_labor_sinks()
	test_growth_tuning()
	test_recruit_pool()
	test_siege_capture_ai()
	print("%d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)


## A w x h all-plains map with the given elevations (Vector2i -> int; default 1).
func make_map(w: int, h: int, elev := {}) -> HexMap:
	var m := HexMap.new()
	m.width = w
	m.height = h
	m.terrain_types = terrain_cfg.types
	m.elevation_rules = terrain_cfg.elevation
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			m.cells[c] = HexMap.UNCLAIMED
			m.terrain[c] = "plains"
			m.elevation[c] = int(elev.get(c, 1))
	return m


func make_roster() -> DivisionRoster:
	var r := DivisionRoster.new()
	r.templates = DivisionRoster.load_templates()
	r.combat = DivisionRoster.load_templates(DivisionRoster.COMBAT_CONFIG_PATH)
	return r


func test_climb_cost() -> void:
	var m := make_map(3, 1, {Vector2i(0, 0): 1, Vector2i(1, 0): 2, Vector2i(2, 0): 1})
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var base := int(terrain_cfg.types.plains.move_cost)
	var climb := int(terrain_cfg.elevation.climb_cost)
	ok(m.step_cost(a, b) == base + climb, "uphill 1 level costs +%d (%d)" % [climb, m.step_cost(a, b)])
	ok(m.step_cost(b, c) == base, "downhill costs the normal amount")
	ok(m.step_cost(a, a + Vector2i(0, 0)) == base, "level costs the normal amount")
	var r := make_roster()
	var d := r.spawn_division(0, a, "infantry")
	var before := d.moves_left
	ok(r.try_move(d, b, m) and d.moves_left == before - (base + climb), "moving uphill spends the climb cost")
	d.moves_left = d.move
	var before2 := d.moves_left
	d.has_moved = true
	ok(r.try_move(d, c, m) and d.moves_left == maxi(before2 - base, 0), "moving downhill spends the normal cost")


func test_cliff_blocking() -> void:
	# 2 levels or more between neighbors is a cliff, in both directions.
	var m := make_map(3, 1, {Vector2i(0, 0): 1, Vector2i(1, 0): 3, Vector2i(2, 0): 4})
	ok(not m.can_step(Vector2i(0, 0), Vector2i(1, 0)), "cliff up (2 levels) is blocked")
	ok(not m.can_step(Vector2i(1, 0), Vector2i(0, 0)), "cliff down (2 levels) is blocked")
	ok(m.can_step(Vector2i(1, 0), Vector2i(2, 0)), "1 level is passable")
	var r := make_roster()
	var d := r.spawn_division(0, Vector2i(0, 0), "infantry")
	ok(not r.can_move(d, Vector2i(1, 0), m), "can_move refuses a cliff")
	ok(not r.try_move(d, Vector2i(1, 0), m) and d.hex == Vector2i(0, 0), "try_move refuses a cliff")
	ok(r.plan_path(d, Vector2i(2, 0), m).is_empty(), "no path across a cliff wall")
	# A pass: lowering one hex to 2 makes the path exist.
	m.elevation[Vector2i(1, 0)] = 2
	m.elevation[Vector2i(2, 0)] = 3
	ok(r.plan_path(d, Vector2i(2, 0), m).size() == 2, "path exists once the cliff is lowered to 1 level")
	# Paths go around a cliff when there is a way.
	var m2 := make_map(3, 3)
	m2.elevation[Vector2i(1, 1)] = 4
	var d2 := r.spawn_division(1, Vector2i(0, 1), "infantry")
	var path := r.plan_path(d2, Vector2i(2, 1), m2)
	ok(not path.is_empty() and not path.has(Vector2i(1, 1)), "path routes around a cliff hex")


func test_multi_turn_paths() -> void:
	# 1 -> 2 -> 3 -> 4 climbing: every step costs base + climb, so move points run out.
	var m := make_map(5, 1, {Vector2i(0, 0): 1, Vector2i(1, 0): 2, Vector2i(2, 0): 3, Vector2i(3, 0): 4, Vector2i(4, 0): 4})
	var r := make_roster()
	var d := r.spawn_division(0, Vector2i(0, 0), "infantry")
	var path := r.plan_path(d, Vector2i(4, 0), m)
	ok(path.size() == 4, "multi-turn path over climbs is found")
	var split := r.turn_split(d, path, m)
	var step := int(terrain_cfg.types.plains.move_cost) + int(terrain_cfg.elevation.climb_cost)
	var per_turn := maxi(d.move / step, 1)
	ok(split[0] == per_turn, "turn_split counts climb cost: %s" % str(split))
	d.order_path.assign(path)
	ok(r.steps_this_turn(d, m) == per_turn, "preview steps this turn match")
	# Executing the order moves exactly that far and keeps the rest.
	r.execute_orders(m)
	ok(d.hex == path[per_turn - 1] and d.order_path.size() == path.size() - per_turn, "execute stops where the points run out")


func test_uphill_penalty() -> void:
	var r := make_roster()
	var m := make_map(4, 1, {Vector2i(0, 0): 1, Vector2i(1, 0): 2, Vector2i(2, 0): 3, Vector2i(3, 0): 4})
	var per := float(combat_cfg.uphill_attack_per_level)
	var cap := float(combat_cfg.uphill_attack_cap)
	var lvl1 := r.elevation_attack_mult(Vector2i(0, 0), Vector2i(1, 0), m)
	var lvl2 := r.elevation_attack_mult(Vector2i(0, 0), Vector2i(2, 0), m)
	var lvl3 := r.elevation_attack_mult(Vector2i(0, 0), Vector2i(3, 0), m)
	ok(is_equal_approx(lvl1, 1.0 - per), "uphill 1 level = %.2f" % lvl1)
	ok(is_equal_approx(lvl2, 1.0 - minf(2.0 * per, cap)), "uphill 2 levels = %.2f" % lvl2)
	ok(is_equal_approx(lvl3, 1.0 - cap), "uphill 3 levels is capped at -%.0f%% (%.2f)" % [cap * 100.0, lvl3])
	ok(is_equal_approx(r.elevation_attack_mult(Vector2i(1, 0), Vector2i(0, 0), m), 1.0), "downhill gets no penalty")
	ok(is_equal_approx(r.elevation_attack_mult(Vector2i(0, 0), Vector2i(0, 0), m), 1.0), "level gets no penalty")
	ok(is_equal_approx(r.elevation_attack_mult(Vector2i(0, 0), Vector2i(3, 0), m, true), 1.0), "ranged/naval ignores elevation")


func test_uphill_damage() -> void:
	# Same rolls, same defender defense: damage to the defender scales by the uphill multiplier.
	var m := make_map(2, 1, {Vector2i(0, 0): 1, Vector2i(1, 0): 2})
	var r := make_roster()
	var a := r.spawn_division(0, Vector2i(0, 0), "infantry")
	var t := r.spawn_division(1, Vector2i(1, 0), "infantry")
	r.rng.seed = 77
	var up := r.attack(a, t, m)
	# Now swap: attack downhill with fresh divisions and the same seed.
	var r2 := make_roster()
	var m2 := make_map(2, 1, {Vector2i(0, 0): 1, Vector2i(1, 0): 1})
	var a2 := r2.spawn_division(0, Vector2i(0, 0), "infantry")
	var t2 := r2.spawn_division(1, Vector2i(1, 0), "infantry")
	r2.rng.seed = 77
	var level := r2.attack(a2, t2, m2)
	ok(not up.is_empty() and not level.is_empty(), "both attacks resolve")
	ok(is_equal_approx(float(up.damage_to_defender), float(level.damage_to_defender) * (1.0 - float(combat_cfg.uphill_attack_per_level))),
			"uphill attack deals 85%% damage (%.3f vs %.3f)" % [up.damage_to_defender, level.damage_to_defender])
	ok(is_equal_approx(float(up.defender_defense), float(level.defender_defense)), "defender gets no height bonus")
	ok(is_equal_approx(float(up.damage_to_attacker), float(level.damage_to_attacker)), "defender's counter-damage is unaffected")


func test_reachability() -> void:
	# A walled-off region gets exactly the passes it needs.
	var w := make_map(5, 1, {Vector2i(2, 0): 3, Vector2i(3, 0): 3, Vector2i(4, 0): 3})
	w.cities.append({"id": 0, "nation": 0, "cell": Vector2i(0, 0)})
	ok(w.reachable_from(Vector2i(0, 0)).size() == 2, "walled-off land starts unreachable")
	ok(w.ensure_reachable() == 1 and w.reachable_from(Vector2i(0, 0)).size() == 5, "one lowered cliff edge opens a pass")
	var all_ok := true
	var deterministic := true
	var worst := ""
	for seed_value in range(1, 21):
		var m := build(seed_value)
		var m2 := build(seed_value)
		deterministic = deterministic and m.elevation == m2.elevation
		var seen_comp := {}
		for city in m.cities:
			if seen_comp.has(city.cell):
				continue
			var comp := m.land_component(city.cell)
			for c in comp:
				seen_comp[c] = true
			var reach := m.reachable_from(city.cell)
			for c in comp:
				if not reach.has(c):
					all_ok = false
					worst = "seed %d cell %s" % [seed_value, str(c)]
		# Neighbors differ by at most 1 everywhere except on tagged ridge edges.
		for cell in m.elevation:
			for n in m.neighbors(cell):
				if absi(m.elevation[cell] - m.elevation[n]) > 1 and m.terrain_of(cell).passable and m.terrain_of(n).passable \
						and not m.is_ridge_edge(cell, n):
					all_ok = false
					worst = "smooth seed %d %s" % [seed_value, str(cell)]
	ok(all_ok, "all land reachable from its start on 20 seeds %s" % worst)
	test_mountains()
	ok(m_idempotent(), "ensure_reachable finds nothing more to fix")
	ok(deterministic, "same seed gives the same elevations")


# Mountains stay at 3 but get foothills: any mountain-to-land edge that is a cliff
# (2+ levels) must be a tagged ridge, and most mountain edges can be walked.
func test_mountains() -> void:
	var untagged := 0
	var edges := 0
	var open_edges := 0
	var cliff_edges := 0
	var mountains := 0
	var lowered := 0
	var foothills := 0
	var ridges := 0
	var false_ridges := 0
	for seed_value in range(1, 21):
		var m := build(seed_value)
		ridges += m.ridge_edges.size()
		for key in m.ridge_edges:
			var ra := Vector2i(key.x, key.y)
			var rb := Vector2i(key.z, key.w)
			if absi(m.elevation[ra] - m.elevation[rb]) < int(terrain_cfg.elevation.cliff_diff):
				false_ridges += 1
		for cell in m.terrain:
			if m.terrain[cell] != "mountains":
				continue
			mountains += 1
			if m.elevation[cell] != int(terrain_cfg.elevation.by_terrain.mountains):
				lowered += 1
			for n in m.neighbors(cell):
				if not m.terrain_of(n).passable or m.terrain[n] == "mountains":
					continue
				edges += 1
				if m.can_step(cell, n) and m.can_step(n, cell):
					open_edges += 1
				else:
					cliff_edges += 1
				if absi(m.elevation[cell] - m.elevation[n]) > 1 and not m.is_ridge_edge(cell, n):
					untagged += 1
				if m.terrain[n] == "hills" and m.elevation[n] == 2:
					foothills += 1
	ok(mountains > 0 and edges > 0, "20 seeds have mountains (%d) with lowland edges (%d)" % [mountains, edges])
	ok(lowered == 0, "every mountain stays at elevation 3 on 20 seeds (%d of %d lowered)" % [lowered, mountains])
	ok(false_ridges == 0, "every tagged ridge edge is a real cliff (%d tagged, %d false)" % [ridges, false_ridges])
	ok(untagged == 0, "no mountain borders a level-1 tile across a cliff unless the edge is a tagged ridge (%d untagged)" % untagged)
	ok(float(open_edges) / float(maxi(edges, 1)) > 0.5, "most mountain edges are walkable (%d of %d); kept cliffs %d (%.1f%%)" % [open_edges, edges, cliff_edges, 100.0 * cliff_edges / maxi(edges, 1)])
	ok(foothills > 0, "mountains get hills foothills (%d)" % foothills)
	var m1 := build(7)
	var m2 := build(7)
	ok(m1.ridge_edges == m2.ridge_edges and m1.terrain == m2.terrain, "ridge tags and foothills are deterministic")
	# QA repro: seed 3 used to lower the mountain at (3,9) to 2.
	var q := HexMap.new()
	q.generate(20, 12, 3, 0.6, 4, 2, 3)
	q.generate_terrain(terrain_cfg)
	ok(q.terrain[Vector2i(3, 9)] != "mountains" or q.elevation[Vector2i(3, 9)] == 3, "seed 3 (3,9) is no longer a lowered mountain")
	# A pass into a mountain raises the low side to a foothill instead of lowering the mountain.
	var w := make_map(3, 1, {Vector2i(0, 0): 1, Vector2i(1, 0): 3, Vector2i(2, 0): 3})
	w.terrain[Vector2i(1, 0)] = "mountains"
	w.terrain[Vector2i(2, 0)] = "mountains"
	w.cities.append({"id": 0, "nation": 0, "cell": Vector2i(0, 0)})
	w.ridge_edges[HexMap.edge_key(Vector2i(0, 0), Vector2i(1, 0))] = true
	ok(w.ensure_reachable() == 1 and w.elevation[Vector2i(1, 0)] == 3 and w.elevation[Vector2i(0, 0)] == 2, "a pass into a mountain raises the low side to 2 and leaves the mountain at 3")
	ok(w.terrain[Vector2i(0, 0)] == "plains", "a city hex raised for a pass keeps its terrain")
	ok(w.ridge_edges.is_empty(), "cutting a pass drops that edge from ridge_edges")


func build(seed_value: int) -> HexMap:
	var m := HexMap.new()
	m.generate(20, 12, seed_value, 0.6, 4, 2, 3)
	m.generate_terrain(terrain_cfg)
	return m


func m_idempotent() -> bool:
	return build(5).ensure_reachable() == 0


func make_camera() -> MapCamera:
	var cam := MapCamera.new()
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_config.json"))
	cam.configure(cfg.camera)
	cam.view_size = Vector2(1280, 720)
	return cam


func mouse_button(index: int, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	return e


func mouse_motion(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	return e


func test_camera() -> void:
	var m := build(3)
	var view := MapView.new()
	view.hex_map = m
	view.roster = make_roster()
	root.add_child(view)
	var cam := make_camera()
	var wb := view.world_bounds()
	ok(view.scale == Vector2.ONE, "iso.view_scale is 1.0 (the camera fits the map)")
	cam.fit_to(wb)
	ok(cam.zoom.x >= cam.zoom_min and cam.zoom.x <= cam.zoom_max, "starting zoom %.2f is in range" % cam.zoom.x)
	ok(wb.size.x * cam.zoom.x <= cam.view_size.x + 0.5 and wb.size.y * cam.zoom.x <= cam.view_size.y + 0.5, "starting zoom fits the whole map")
	# Screen -> hex at zoom 0.5, 1 and 2 with a pan offset: every hex whose face center is
	# visible must be picked from the screen point of its own center.
	var cells := m.cells.keys()
	cells.sort()
	for z in [0.5, 1.0, 2.0]:
		cam.zoom = Vector2.ONE * z
		cam.position = wb.get_center() + Vector2(-210, 95)
		cam.clamp_position()
		var checked := 0
		var bad := 0
		var view_rect := Rect2(Vector2.ZERO, cam.view_size)
		for cell in cells:
			var screen := cam.world_to_screen(view.hex_to_pixel(cell))
			if not view_rect.has_point(screen):
				continue
			var expect := view.pixel_to_hex(view.hex_to_pixel(cell))
			checked += 1
			if view.pixel_to_hex(cam.screen_to_world(screen)) != expect:
				bad += 1
		ok(checked > 0 and bad == 0, "screen -> hex at zoom %.1f with a pan offset: %d visible hexes, %d wrong" % [z, checked, bad])
		var probe := Vector2(333, 271)
		ok(cam.world_to_screen(cam.screen_to_world(probe)).is_equal_approx(probe), "screen/world round trip at zoom %.1f" % z)
	# Most hexes pick themselves at zoom 1 (a tall front tile can cover a center).
	cam.zoom = Vector2.ONE
	cam.position = wb.get_center()
	cam.clamp_position()
	var self_picks := 0
	for cell in cells:
		if view.pixel_to_hex(cam.screen_to_world(cam.world_to_screen(view.hex_to_pixel(cell)))) == cell:
			self_picks += 1
	ok(self_picks >= cells.size() - 4, "hexes pick themselves through the camera (%d of %d)" % [self_picks, cells.size()])
	# Zoom centered on the cursor keeps the world point under it (bounds widened so the
	# clamp doesn't move the camera), and steps clamp.
	cam.bounds = wb.grow(3000)
	cam.zoom = Vector2.ONE
	cam.position = wb.get_center()
	var cursor := Vector2(900, 300)
	var before := cam.screen_to_world(cursor)
	cam.zoom_notch(1, cursor)
	ok(is_equal_approx(cam.zoom.x, 1.25) and cam.screen_to_world(cursor).distance_to(before) < 0.01, "wheel zoom steps by 0.25 and stays centered on the cursor")
	for i in 20:
		cam.zoom_notch(1, cursor)
	ok(is_equal_approx(cam.zoom.x, 2.0), "zoom clamps at the max (2x)")
	for i in 20:
		cam.zoom_notch(-1, cursor)
	ok(is_equal_approx(cam.zoom.x, 0.5), "zoom clamps at the min (0.5x)")
	cam.bounds = wb
	# Clamping to the map bounds.
	cam.zoom = Vector2.ONE * 2.0
	cam.position = wb.position - Vector2(5000, 5000)
	cam.clamp_position()
	var half := cam.view_size * 0.5 / 2.0
	ok(is_equal_approx(cam.position.x, wb.position.x + half.x) and is_equal_approx(cam.position.y, wb.position.y + half.y), "top-left clamps to the map bounds")
	cam.position = wb.end + Vector2(5000, 5000)
	cam.clamp_position()
	ok(is_equal_approx(cam.position.x, wb.end.x - half.x) and is_equal_approx(cam.position.y, wb.end.y - half.y), "bottom-right clamps to the map bounds")
	cam.zoom = Vector2.ONE * 0.5
	cam.position = wb.position
	cam.clamp_position()
	var vis := Rect2(cam.position - cam.view_size * 0.5 / 0.5, cam.view_size / 0.5)
	ok(cam.position.x == wb.get_center().x or wb.encloses(Rect2(vis.position.x, wb.position.y, vis.size.x, wb.size.y)), "an axis where the view is larger than the map is centered")
	# Drag: middle-drag pans, a right-click without dragging is a click, a right-drag pans.
	cam.bounds = wb.grow(3000)
	cam.zoom = Vector2.ONE
	cam.position = wb.get_center()
	var start := cam.position
	cam.handle_event(mouse_button(MOUSE_BUTTON_MIDDLE, true, Vector2(500, 400)))
	cam.handle_event(mouse_motion(Vector2(470, 380), Vector2(-30, -20)))
	cam.handle_event(mouse_button(MOUSE_BUTTON_MIDDLE, false, Vector2(470, 380)))
	ok(cam.position.is_equal_approx(start + Vector2(30, 20)), "middle-drag pans the map with the pointer")
	var clicks := []
	cam.secondary_click.connect(func() -> void: clicks.append(1))
	cam.handle_event(mouse_button(MOUSE_BUTTON_RIGHT, true, Vector2(500, 400)))
	cam.handle_event(mouse_motion(Vector2(502, 401), Vector2(2, 1)))
	cam.handle_event(mouse_button(MOUSE_BUTTON_RIGHT, false, Vector2(502, 401)))
	ok(clicks.size() == 1, "right-click with a small wobble still counts as a click")
	var p0 := cam.position
	cam.handle_event(mouse_button(MOUSE_BUTTON_RIGHT, true, Vector2(500, 400)))
	cam.handle_event(mouse_motion(Vector2(450, 400), Vector2(-50, 0)))
	cam.handle_event(mouse_button(MOUSE_BUTTON_RIGHT, false, Vector2(450, 400)))
	ok(clicks.size() == 1 and cam.position.is_equal_approx(p0 + Vector2(50, 0)), "right-drag past the threshold pans and is not a click")
	ok(not cam.handle_event(mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(10, 10))), "left click is left to the game")
	cam.edge_scroll_enabled = false
	ok(not cam.edge_scroll_enabled and cam._edge_direction(Vector2(2, 300)) == Vector2(-1, 0), "edge zone maps to a pan direction (applied only when enabled, off by default)")
	cam.free()
	view.free()


func city_rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/cities_config.json"))


func pop_map() -> HexMap:
	var m := HexMap.new()
	for key in city_rules():
		m.city_rules[key] = city_rules()[key]
	return m


func test_population() -> void:
	var m := pop_map()
	var eco := NationEconomy.new()
	var capital := {"id": 0, "nation": 0, "population": 10000, "infrastructure": 10}
	ok(m.city_rules.start_population == 10000, "a capital starts at 10,000 people (config start_population)")
	# Housing cap = infrastructure x 3,000.
	ok(m.housing_cap(capital) == 30000, "starting infra 10 gives a 30,000 housing cap")
	ok(m.housing_cap({"infrastructure": 11.5}) == 34500 and m.housing_cap({"infrastructure": 0}) == 0, "housing cap scales with infra (11.5 -> 34,500, 0 -> 0)")
	# Growth = (0.5% base + 1.0% x the share of labor on Growth) x terrain, capped at housing.
	ok(is_equal_approx(m.growth_rate(capital), 0.005), "base growth is 0.5% a turn (no Growth labor)")
	var with_labor := capital.duplicate()
	with_labor.labor = {"growth": 3}
	ok(is_equal_approx(m.growth_rate(with_labor), 0.011), "3 of 5 labor points on Growth: 0.5% + 1.0% x 0.6 = 1.1%")
	ok(m.growth_amount(capital) == 50 and m.grown_population(capital) == 10050, "0.5% of 10,000 is +50 people")
	ok(m.growth_amount(with_labor) == 110, "1.1% of 10,000 is +110 people")
	var near := {"id": 1, "nation": 0, "population": 29950, "infrastructure": 10}
	ok(m.growth_amount(near) == 50 and m.grown_population(near) == 30000, "growth is capped at housing (29,950 -> 30,000)")
	var full := {"id": 2, "nation": 0, "population": 30000, "infrastructure": 10}
	ok(m.growth_amount(full) == 0, "a city at its cap stops growing")
	var over := {"id": 3, "nation": 0, "population": 30000, "infrastructure": 7}
	ok(m.growth_amount(over) == 0 and m.grown_population(over) == 30000, "a city over its cap (infra lost) does not shrink or grow")
	# grow_cities applies it to every city.
	var gm := pop_map()
	gm.cities.append({"id": 0, "nation": 0, "cell": Vector2i(0, 0), "population": 10000, "infrastructure": 10, "radius": 1})
	gm.grow_cities()
	ok(gm.cities[0].population == 10050, "grow_cities adds 0.5% a turn")
	# People rounded to the nearest 100 for display.
	ok(m.display_people(12449) == 12400 and m.display_people(12450) == 12500 and m.display_people(10000) == 10000, "people display rounds to the nearest 100")
	ok(CityPanel.people_text(12400) == "12,400" and CityPanel.people_text(30000) == "30,000" and CityPanel.people_text(950) == "950", "people are shown with thousands separators")
	# Labor points = population / 2,000, rounded down.
	ok(eco.labor_points(capital) == 5, "10,000 people give 5 labor points")
	ok(eco.labor_points({"population": 3999}) == 1 and eco.labor_points({"population": 1999}) == 0 and eco.labor_points({"population": 12400}) == 6, "labor rounds down (3,999 -> 1, 1,999 -> 0, 12,400 -> 6)")
	# Cash formula: +1 cash for every unassigned labor point.
	ok(eco.unassigned_labor(capital) == 5 and is_equal_approx(eco.city_income(capital).cash, 5.0), "a capital with nothing assigned makes 5 cash (5 free labor)")
	var assigned := capital.duplicate()
	assigned.labor = {"growth": 2, "training": 1}
	ok(eco.unassigned_labor(assigned) == 2 and is_equal_approx(eco.city_income(assigned).cash, 2.0), "assigned labor earns no cash (5 - 3 = 2 free -> 2 cash)")
	assigned.labor = {"growth": 9}
	ok(eco.unassigned_labor(assigned) == 0, "unassigned labor never goes below 0")
	# No nation-wide manpower: it is neither a stock nor an income.
	ok(not NationEconomy.RESOURCES.has("manpower") and not eco.city_income(capital).has("manpower") and not eco.config.has("manpower_per_person"), "manpower is gone as a nation resource (per-city pools replace it)")
	# Old keys are gone from config.
	ok(not m.city_rules.has("max_population") and not m.city_rules.has("growth_per_turn") and not eco.config.has("cash_per_pop"), "pre-rescale config keys are removed")
	# Territory radius still grows at 20,000 people.
	ok(m._radius_for(19999) == m.city_rules.claim_radius and m._radius_for(20000) == m.city_rules.grown_claim_radius, "claim radius grows at 20,000 people (was 20 pop)")
	# A generated map starts every city at the config population.
	var gen := build(5)
	var starts := gen.cities.all(func(c: Dictionary) -> bool: return int(c.population) == 10000)
	ok(starts, "generated cities start at 10,000 people")


func test_player_faction_warning() -> void:
	var cfg := {"seed": 5, "faction_count": 4, "faction_seed": -1}
	cfg.player_faction = "ASSEMBLY"
	var r := FactionRoster.from_config(cfg)
	ok(r.player_warning.contains("ASSEMBLY") and r.player_warning.contains("did you mean"), "wrong-case player_faction warns and suggests the id")
	ok(r.assigned.size() == 4, "a wrong player_faction still falls back to a random roster")
	cfg.player_faction = "no-such-faction"
	ok(FactionRoster.from_config(cfg).player_warning != "", "an unknown player_faction warns")
	var good_id: String = FactionRoster.load_all()[0].id
	cfg.player_faction = good_id
	var g := FactionRoster.from_config(cfg)
	ok(g.player_warning == "" and g.assigned[0].id == good_id, "a valid player_faction does not warn and is nation 0")
	cfg.player_faction = ""
	ok(FactionRoster.from_config(cfg).player_warning == "", "blank player_faction does not warn")


func test_labor() -> void:
	var eco := NationEconomy.new()
	var m := pop_map()
	var cap := {"id": 0, "nation": 0, "population": 10000, "infrastructure": 10}
	ok(is_equal_approx(float(eco.config.labor.default_growth_share), 0.5), "config labor.default_growth_share is 0.5 (resources_config.json)")
	# Default: 50% of labor on Growth, rounded down; the rest unassigned and making cash.
	eco.ensure_labor(cap)
	ok(cap.labor == {"training": 0, "infrastructure": 0, "growth": 2}, "a 10,000 capital defaults to 2 on Growth, 0 Training, 0 Infrastructure")
	ok(eco.labor_points(cap) == 5 and eco.unassigned_labor(cap) == 3, "5 labor points leave 3 unassigned")
	ok(is_equal_approx(eco.city_income(cap).cash, 3.0), "3 unassigned labor make 3 cash")
	for pair in [[2000, 0], [3999, 0], [4000, 1], [12000, 3], [14000, 3], [16000, 4]]:
		ok(eco.default_labor({"population": pair[0]}).growth == pair[1], "default Growth rounds down: %d people -> %d" % [pair[0], pair[1]])
	# Growth labor feeds the growth formula: 2 of 5 points = 0.5% + 1.0% x 0.4 = 0.9%.
	ok(is_equal_approx(m.growth_rate(cap), 0.009) and m.growth_amount(cap) == 90, "Growth labor feeds growth: default capital grows 0.9% (+90)")
	# The default share comes from config.
	var all_growth := NationEconomy.new()
	all_growth.config.labor.default_growth_share = 1.0
	var c2 := {"population": 10000, "infrastructure": 10}
	all_growth.ensure_labor(c2)
	ok(c2.labor.growth == 5 and all_growth.unassigned_labor(c2) == 0 and is_equal_approx(all_growth.city_income(c2).cash, 0.0), "changing default_growth_share to 1.0 gives all-Growth and no cash")
	# Assign freely: +/- buttons, limited by free labor and by zero.
	ok(eco.adjust_labor(cap, "training", 1) and eco.adjust_labor(cap, "infrastructure", 1) and eco.adjust_labor(cap, "training", 1), "can assign free labor to Training and Infrastructure")
	ok(cap.labor == {"training": 2, "infrastructure": 1, "growth": 2} and eco.unassigned_labor(cap) == 0, "assignment stored 2/1/2 with nothing free")
	ok(not eco.adjust_labor(cap, "growth", 1), "+ does nothing when no labor is free")
	ok(eco.adjust_labor(cap, "infrastructure", -1) and eco.unassigned_labor(cap) == 1, "- frees a point")
	ok(not eco.adjust_labor(cap, "infrastructure", -1), "- does nothing at 0")
	ok(is_equal_approx(eco.city_income(cap).cash, 1.0), "1 free point makes 1 cash")
	ok(eco.set_labor(cap, "growth", 99) == 3 and eco.set_labor(cap, "training", -4) == 0, "set_labor clamps to the free labor and to 0")
	# Clamp when population drops: Growth is trimmed first, then Infrastructure, then Training.
	var c3 := {"id": 3, "population": 10000, "infrastructure": 10, "labor": {"training": 2, "infrastructure": 1, "growth": 2}}
	c3.population = 6000
	eco.ensure_labor(c3)
	ok(c3.labor == {"training": 2, "infrastructure": 1, "growth": 0} and eco.assigned_labor(c3) <= eco.labor_points(c3), "population drop to 6,000 (3 labor) trims Growth first")
	c3.population = 2000
	eco.ensure_labor(c3)
	ok(c3.labor == {"training": 1, "infrastructure": 0, "growth": 0}, "population drop to 2,000 (1 labor) keeps only what fits (Training last)")
	c3.population = 500
	eco.ensure_labor(c3)
	ok(eco.assigned_labor(c3) == 0 and eco.unassigned_labor(c3) == 0, "population under 2,000 leaves no labor and nothing assigned")
	# Assignment lives through a turn: the economy end_turn clamps and defaults new cities.
	var gm := build(5)
	var geco := NationEconomy.new()
	geco.setup(gm)
	ok(gm.cities.all(func(c: Dictionary) -> bool: return c.labor.growth == 2 and c.labor.training == 0), "every generated city (AI included) starts at the default split after setup")
	var fresh := gm.cities[0]
	fresh.erase("labor")
	fresh.population = 4000
	geco.refresh_labor(gm)
	ok(fresh.labor.growth == 1, "a city without an assignment (new or captured) gets the default for its size")
	# Nation totals.
	var nat: int = gm.cities[1].nation
	var t := geco.labor_totals(nat, gm)
	var expect_total := 0
	for c in gm.cities:
		if c.nation == nat:
			expect_total += geco.labor_points(c)
	ok(t.total == expect_total and t.total == t.free + t.training + t.infrastructure + t.growth and t.growth > 0, "nation totals add up (total %d, growth %d, free %d)" % [t.total, t.growth, t.free])


## A generated map, an economy set up on it, an empty roster and the first nation-0 city.
func sink_setup(training: int, infra: int) -> Dictionary:
	var m := build(5)
	var eco := NationEconomy.new()
	eco.setup(m)
	var roster := make_roster()
	var city: Dictionary = m.cities.filter(func(c: Dictionary) -> bool: return c.nation == 0)[0]
	city.labor = {"training": training, "infrastructure": infra, "growth": 0}
	eco.stocks[0].capacity = 100.0
	return {"map": m, "eco": eco, "roster": roster, "city": city}


func turns_to_division(training: int) -> int:
	var s := sink_setup(training, 0)
	var eco: NationEconomy = s.eco
	eco.recruit(s.city, 0, s.roster)
	for turn in range(1, 41):
		s.city.labor = {"training": training, "infrastructure": 0, "growth": 0}
		eco.spawn_pending(s.map, s.roster)
		if not s.roster.divisions.is_empty():
			return turn
	return -1


func test_labor_sinks() -> void:
	var eco0 := NationEconomy.new()
	ok(eco0.training_labor_cost() == 15 and eco0.infra_labor_per_level() == 10, "config: a division costs 15 labor-turns, +1 infra costs 10 (resources_config.json labor)")
	# Training queue: progress adds Training points each turn; a division needs 15 labor
	# and at least training_turns (3) turns.
	ok(turns_to_division(15) == 3, "15 Training points: labor is full after 1 turn but the division still takes the minimum 3 turns")
	ok(turns_to_division(5) == 3, "5 Training points: 15 labor-turns in 3 turns -> division on turn 3")
	ok(turns_to_division(4) == 4, "4 Training points: 16 labor-turns -> division on turn 4")
	ok(turns_to_division(1) == 15, "1 Training point: 15 turns")
	ok(turns_to_division(0) == -1, "0 Training points: the queue never finishes")
	var s := sink_setup(4, 0)
	var eco: NationEconomy = s.eco
	ok(eco.recruit(s.city, 0, s.roster) and eco.stocks[0].capacity == 85.0 and s.city.pool == 0 and s.city.population == 9000, "recruiting pays 15 capacity and draws 1,000 people from the city pool (and its population)")
	eco.spawn_pending(s.map, s.roster)
	ok(eco.pending[s.city.id].labor == 4 and eco.pending[s.city.id].turns_left == 2, "one turn adds 4 labor and ticks the timer")
	ok(NationEconomy.queue_text(eco.pending[s.city.id]) == "Division 4/15 labor, 2 turns left", "queue text shows labor progress and turns")
	for i in 3:
		eco.spawn_pending(s.map, s.roster)
	ok(s.roster.divisions.size() == 1 and not eco.pending.has(s.city.id), "the division appears once labor and time are both done")
	ok(NationEconomy.queue_text({"turns_left": 0, "labor": 3, "cost": 15}) == "Division 3/15 labor, needs more Training labor", "queue text when only the timer is done")
	# Occupied hex: labor is capped at the cost and the recruit waits.
	var s2 := sink_setup(15, 0)
	var e2: NationEconomy = s2.eco
	e2.recruit(s2.city, 0, s2.roster)
	s2.roster.spawn_division(0, s2.city.cell, "infantry")
	for i in 5:
		e2.spawn_pending(s2.map, s2.roster)
	ok(e2.pending[s2.city.id].labor == 15 and s2.roster.divisions.size() == 1, "labor progress is capped at the cost and an occupied hex holds the recruit")
	# Auto-training: queueing a recruit in a city with no Training moves its labor there;
	# the default split returns when the queue clears.
	var s3 := sink_setup(0, 1)
	var e3: NationEconomy = s3.eco
	s3.city.labor = {"training": 0, "infrastructure": 1, "growth": 2}
	e3.recruit(s3.city, 0, s3.roster)
	ok(s3.city.labor == {"training": 2, "infrastructure": 1, "growth": 1}, "queueing a recruit moves half the labor to Training (the 1,000-person draw leaves 4 points: 2 Training, Infrastructure 1 kept, Growth trimmed to fit)")
	for i in 9:
		e3.spawn_pending(s3.map, s3.roster)
	ok(s3.roster.divisions.size() == 1 and s3.city.labor.training == 0 and s3.city.labor.growth == 2 and s3.city.labor.infrastructure == 1, "when the queue clears the default Growth returns and Training goes back to 0")
	var s4 := sink_setup(0, 0)
	s4.city.labor = {"training": 0, "infrastructure": 0, "growth": 2}
	s4.eco.recruit(s4.city, 0, s4.roster)
	s4.eco.adjust_labor(s4.city, "training", -1)
	for i in 5:
		s4.eco.spawn_pending(s4.map, s4.roster)
	ok(s4.city.labor.training == 1, "a manual change keeps the player's assignment after the queue clears (no auto reset)")
	# The AI path: run_ai queues, auto-training feeds it, and a division arrives with no player input.
	var s5 := sink_setup(0, 0)
	var e5: NationEconomy = s5.eco
	var ai_city: Dictionary = s5.map.cities.filter(func(c: Dictionary) -> bool: return c.nation != 0)[0]
	e5.stocks[ai_city.nation].capacity = 100.0
	e5.recruit(ai_city, ai_city.nation, s5.roster)
	for i in 9:
		e5.spawn_pending(s5.map, s5.roster)
	ok(s5.roster.divisions.any(func(d: Division) -> bool: return d.nation == ai_city.nation), "an AI city's recruit completes through its default Training labor")
	# Infrastructure: 10 labor-turns = +1 infra = +3,000 housing; leftover carries over.
	var s6 := sink_setup(0, 3)
	var e6: NationEconomy = s6.eco
	var infra0: float = float(s6.city.infrastructure)
	var cap0: int = s6.map.housing_cap(s6.city)
	for i in 3:
		e6.apply_infrastructure(s6.map)
	ok(s6.city.infra_progress == 9 and float(s6.city.infrastructure) == infra0, "3 Infrastructure points x 3 turns = 9 labor-turns, no level yet")
	e6.apply_infrastructure(s6.map)
	ok(float(s6.city.infrastructure) == infra0 + 1.0 and s6.city.infra_progress == 2, "the 4th turn reaches 12: +1 infra and 2 carried over")
	ok(s6.map.housing_cap(s6.city) == cap0 + 3000, "+1 infra raises the housing cap by 3,000")
	var s7 := sink_setup(0, 0)
	s7.eco.apply_infrastructure(s7.map)
	ok(s7.city.infra_progress == 0, "no Infrastructure points means no progress")
	# Infrastructure labor rebuilds capture damage: levels count toward the repair and the
	# rebuild finishes early (never below the target).
	var s8 := sink_setup(0, 10)
	s8.city.infrastructure = 7.0
	s8.city.rebuild_target = 10.0
	s8.city.rebuild_turns_left = 20
	for i in 3:
		s8.eco.apply_infrastructure(s8.map)
	ok(float(s8.city.infrastructure) == 10.0, "10 Infrastructure points a turn add +1 infra a turn: 3 turns repair 7 -> 10")
	s8.map._rebuild_step(s8.city)
	ok(not s8.city.has("rebuild_turns_left") and float(s8.city.infrastructure) == 10.0, "the rebuild ends once labor has repaired it to the target")
	var s9 := sink_setup(0, 0)
	s9.city.infrastructure = 7.0
	s9.city.rebuild_target = 10.0
	s9.city.rebuild_turns_left = 2
	s9.map._rebuild_step(s9.city)
	ok(float(s9.city.infrastructure) == 8.5 and s9.city.rebuild_turns_left == 1, "the timed rebuild still works with no labor (7 -> 8.5, one turn left)")
	# The turn step runs both sinks: economy end_turn applies training and infrastructure.
	var s10 := sink_setup(2, 3)
	s10.eco.recruit(s10.city, 0, s10.roster)
	s10.city.labor = {"training": 2, "infrastructure": 2, "growth": 0}
	s10.eco.end_turn(s10.map, s10.roster)
	ok(s10.eco.pending[s10.city.id].labor == 2 and s10.city.infra_progress == 2, "end_turn feeds the training queue and infrastructure progress")
	# Auto-training with the 0.5 share on a 10,000 capital keeps cash and growth (5 points:
	# 2 Training, 2 Growth, 1 free). Recruiting also draws 1,000 people, which costs one
	# labor point (9,000 people = 4 points), so a recruiting capital has 0 free after the draw.
	var s11 := sink_setup(0, 0)
	s11.city.erase("labor")
	s11.eco.ensure_labor(s11.city)
	s11.eco.auto_training(s11.city)
	ok(s11.city.labor == {"training": 2, "infrastructure": 0, "growth": 2} and s11.eco.unassigned_labor(s11.city) == 1 and s11.eco.city_income(s11.city).cash > 0.0, "auto-training a 10,000 capital: 2 Training, 2 Growth, 1 free point of cash")
	ok(s11.map.growth_amount(s11.city) > 0, "a training capital still grows")
	var s12 := sink_setup(0, 0)
	s12.city.erase("labor")
	s12.eco.ensure_labor(s12.city)
	s12.eco.recruit(s12.city, 0, s12.roster)
	ok(s12.eco.labor_points(s12.city) == 4 and s12.city.labor == {"training": 2, "infrastructure": 0, "growth": 2}, "recruiting from a 10,000 capital: the draw leaves 4 labor points, split 2 Training / 2 Growth")


# --- Task 38: growth tuning, recruit pool, home city, siege ---

## Turns for a city to reach target at a fixed Growth share (0..1), from the config rules.
func turns_to_grow(m: HexMap, from: int, target: int, share: float, infra := 11.0) -> int:
	var city := {"id": 0, "nation": 0, "population": from, "infrastructure": infra}
	for turn in range(1, 1000):
		city.population = int(city.population) + m.growth_amount(city, share)
		if int(city.population) >= target:
			return turn
	return -1


func near(actual: int, expected: int, slack := 2) -> bool:
	return absi(actual - expected) <= slack


func test_growth_tuning() -> void:
	var m := pop_map()
	var r := m.city_rules
	ok(is_equal_approx(r.base_growth, 0.005) and is_equal_approx(r.growth_labor_max_bonus, 0.01) and is_equal_approx(r.min_growth, 0.001), "config: base_growth 0.005, growth_labor_max_bonus 0.010, min_growth 0.001")
	ok(r.division_people_cost == 1000 and r.people_per_strength == 10 and is_equal_approx(r.pool_fill_rate, 0.005) and is_equal_approx(r.pool_cap, 0.15), "config: division 1,000 people, 10 per strength, fill 0.5%, cap 15%")
	ok(r.capital_start_pool == 1000 and r.colony_start_pool == 0 and r.train_min_city_pop == 5000, "config: capital pool 1,000, colony pool 0, training floor 5,000")
	ok(not r.has("growth_rate_per_labor_point") and not r.has("growth_base_rate"), "growth_per_labor_point is removed")
	# Turn counts from POPULATION_TUNING.md (floor rounding makes them a turn or two slower).
	var table := [
		["capital 10k -> 15k, no Growth", 10000, 15000, 0.0, 82],
		["capital 10k -> 15k, half Growth", 10000, 15000, 0.5, 41],
		["capital 10k -> 15k, full Growth", 10000, 15000, 1.0, 28],
		["capital 10k -> 30k, no Growth", 10000, 30000, 0.0, 221],
		["capital 10k -> 30k, half Growth", 10000, 30000, 0.5, 111],
		["capital 10k -> 30k, full Growth", 10000, 30000, 1.0, 74],
		["colony 3k -> 5k, no Growth", 3000, 5000, 0.0, 103],
		["colony 3k -> 5k, half Growth", 3000, 5000, 0.5, 52],
		["colony 3k -> 5k, full Growth", 3000, 5000, 1.0, 35],
		["colony 3k -> 15k, no Growth", 3000, 15000, 0.0, 323],
		["colony 3k -> 15k, half Growth", 3000, 15000, 0.5, 162],
		["colony 3k -> 15k, full Growth", 3000, 15000, 1.0, 109],
	]
	for row in table:
		var got := turns_to_grow(m, row[1], row[2], row[3])
		ok(near(got, row[4], maxi(3, int(row[4] * 0.02))), "%s takes %d turns (doc %d; whole people round down, so a turn or two slower)" % [row[0], got, row[4]])
	var a := turns_to_grow(m, 10000, 15000, 1.0)
	var b := turns_to_grow(m, 10000, 30000, 1.0)
	ok(near(a, 28, 1) and near(b, 74, 2), "acceptance 1: full-Growth capital reaches 15k on turn %d (28 +/- 1) and 30k on turn %d (74, +/- 2 for rounding down)" % [a, b])
	# Rate checks.
	var plain := {"id": 0, "nation": 0, "population": 10000, "infrastructure": 10}
	ok(is_equal_approx(m.growth_rate(plain, 0.0), 0.005), "acceptance 2: 0 Growth labor grows exactly 0.5% a turn on plains")
	ok(is_equal_approx(m.growth_rate(plain, 1.0), 0.015) and is_equal_approx(m.growth_rate(plain, 0.5), 0.010), "full Growth is 1.5%, half is 1.0%")
	m.growth_mods[0] = -0.003
	ok(is_equal_approx(m.growth_rate(plain, 0.0), 0.002), "acceptance 3: a -0.3% trait mod (Directorate) with 0 Growth grows 0.2%")
	m.growth_mods[0] = -0.02
	ok(is_equal_approx(m.growth_rate(plain, 0.0), 0.001), "growth never falls below min_growth (0.1%) outside a siege")
	m.growth_mods.clear()
	# Terrain and fungus multipliers on the city's own tile.
	var fm := make_map(7, 7)
	for key in r:
		fm.city_rules[key] = r[key]
	var city := {"id": 0, "nation": 0, "cell": Vector2i(3, 3), "population": 10000, "infrastructure": 10}
	ok(is_equal_approx(fm.terrain_growth_mult(city), 1.0), "plains: terrain multiplier 1.0")
	fm.terrain[city.cell] = "forest"
	ok(is_equal_approx(fm.terrain_growth_mult(city), 0.9), "forest: 0.9")
	fm.terrain[city.cell] = "hills"
	ok(is_equal_approx(fm.terrain_growth_mult(city), 0.9), "hills: 0.9")
	fm.terrain[city.cell] = "mountains"
	ok(is_equal_approx(fm.terrain_growth_mult(city), 0.7) and is_equal_approx(fm.growth_rate(city, 0.0), 0.0035), "mountains: 0.7 (rate 0.35%)")
	fm.terrain[city.cell] = "plains"
	var nbrs := fm.neighbors(city.cell)
	fm.cells[nbrs[0]] = HexMap.WATER
	ok(fm.growth_terrain_key(city) == "coast" and is_equal_approx(fm.terrain_growth_mult(city), 1.1), "plains touching water count as coast: 1.1")
	fm.cells[nbrs[0]] = HexMap.UNCLAIMED
	fm.terrain[city.cell] = "water"
	ok(fm.growth_terrain_key(city) == "shallow_ocean" and is_equal_approx(fm.terrain_growth_mult(city), 1.0), "a city on water uses shallow_ocean: 1.0")
	fm.terrain[city.cell] = "plains"
	for i in 3:
		fm.fungus_tiles[nbrs[i]] = true
	ok(fm.fungus_adjacent(city) == 3 and is_equal_approx(fm.terrain_growth_mult(city), 0.857375), "acceptance 4: 3 adjacent fungus tiles give 0.95^3 = 0.857")
	fm.city_rules.fungus_adjacent_growth_mult = 0.8
	ok(is_equal_approx(fm.terrain_growth_mult(city), 0.7), "the fungus multiplier never goes below 0.7 (0.8^3 = 0.512 -> 0.7)")
	ok(fm.city_rules.terrain_growth_mult.size() == 6 and is_equal_approx(fm.city_rules.fungus_growth_min_mult, 0.7), "terrain table and fungus minimum are in config")


## A generated map with a roster whose divisions sit on the city hexes and an economy.
func pool_setup() -> Dictionary:
	var m := build(5)
	var eco := NationEconomy.new()
	eco.setup(m)
	var roster := make_roster()
	roster.spawn_at_cities(m)
	for d in roster.divisions:
		d.supplied = true
	return {"map": m, "eco": eco, "roster": roster}


func nation_cities(m: HexMap, nation: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in m.cities:
		if c.nation == nation:
			out.append(c)
	return out


func test_recruit_pool() -> void:
	var s := pool_setup()
	var m: HexMap = s.map
	var eco: NationEconomy = s.eco
	var roster: DivisionRoster = s.roster
	# Starting pools: the capital (a nation's first city) has 1,000, a colony 0.
	var cap := m.capital_of(0)
	var colony := nation_cities(m, 0)[1]
	ok(cap.pool == 1000 and colony.pool == 0, "acceptance 6: a capital starts with a pool of 1,000, a colony with 0")
	ok(m.cities.all(func(c: Dictionary) -> bool: return m.pool_of(c) == (1000 if c == m.capital_of(c.nation) else 0)), "every nation's first city is its capital with the starting pool")
	# Fill and cap.
	var c10 := {"id": 0, "nation": 0, "population": 10000, "infrastructure": 10, "pool": 1000}
	ok(m.pool_fill(c10) == 50 and m.pool_cap(c10) == 1500, "a 10k city fills 50 a turn and caps at 1,500 (0.5% / 15%)")
	ok(m.advance_preview(c10).pool > 1000, "the pool grows each end turn")
	var c3 := {"id": 1, "nation": 0, "population": 3000, "infrastructure": 10, "pool": 0}
	var top := 0
	for i in 80:
		m._advance_people(c3)
		top = maxi(top, int(c3.pool))
	ok(top == int(floor(float(c3.population) * 0.15)) and top <= int(floor(float(c3.population) * 0.15)), "the pool never exceeds 15% of the city's population")
	var c3b := {"id": 1, "nation": 0, "population": 3000, "infrastructure": 0, "pool": 0}
	for i in 80:
		m._advance_people(c3b)
	ok(c3b.pool == 450 and c3b.population == 3000, "acceptance 6: a 3k colony's pool tops out at 450 (infra 0, no growth)")
	var shrunk := {"id": 2, "nation": 0, "population": 4000, "infrastructure": 0, "pool": 900}
	m._advance_people(shrunk)
	ok(shrunk.pool == 600, "a pool above the cap after population drops is trimmed to the cap (900 -> 600 at 4,000 people)")
	# Recruiting: removes 1,000 people, needs a full pool, and respects the 5,000 floor.
	ok(eco.recruit_block_reason(cap, 0, roster) == "city hex occupied", "(a division stands on the city hex)")
	roster.divisions.assign(roster.divisions.filter(func(d: Division) -> bool: return d.hex != cap.cell))
	eco.stocks[0].capacity = 100.0
	ok(eco.recruit_block_reason(cap, 0, roster) == "", "the capital's starting pool allows exactly one recruit")
	ok(eco.recruit(cap, 0, roster) and cap.pool == 0 and cap.population == 9000, "acceptance 5: recruiting removes 1,000 people (pool 1,000 -> 0, population 10,000 -> 9,000)")
	eco.pending.clear()
	cap.pool = 999
	ok(eco.recruit_block_reason(cap, 0, roster) == "recruit pool too small", "a pool under 1,000 cannot recruit")
	cap.pool = 1000
	cap.population = 5999
	ok(eco.recruit_block_reason(cap, 0, roster) == "city too small to train", "a recruit that would leave the city under 5,000 is blocked")
	cap.population = 6000
	ok(eco.recruit_block_reason(cap, 0, roster) == "", "6,000 people may train (5,000 left)")
	colony.pool = 0
	ok(eco.recruit_block_reason(colony, 0, roster).begins_with("recruit pool") or eco.recruit_block_reason(colony, 0, roster) == "city hex occupied", "a colony with an empty pool cannot recruit")
	# Home city: starting divisions use the capital; a trained recruit uses its city.
	var s2 := pool_setup()
	var home_ok: bool = s2.roster.divisions.all(func(d: Division) -> bool: return d.home_city_id == s2.map.capital_of(d.nation).id)
	ok(home_ok, "starting divisions have the nation's capital as home_city_id")
	var rc := nation_cities(s2.map, 0)[0]
	s2.roster.divisions.assign(s2.roster.divisions.filter(func(d: Division) -> bool: return d.hex != rc.cell))
	s2.eco.stocks[0].capacity = 100.0
	s2.eco.recruit(rc, 0, s2.roster)
	rc.labor = {"training": 5, "infrastructure": 0, "growth": 0}
	for i in 4:
		s2.eco.spawn_pending(s2.map, s2.roster)
	ok(s2.roster.division_at(rc.cell) != null and s2.roster.division_at(rc.cell).home_city_id == rc.id, "a recruit's home_city_id is the city that trained it")
	# Disband / demobilize: survivors (strength x 10) return to the home city's population.
	var s3 := pool_setup()
	var d3: Division = s3.roster.divisions.filter(func(d: Division) -> bool: return d.nation == 0)[0]
	var home3: Dictionary = s3.map.city_by_id(d3.home_city_id)
	d3.strength = 60.0
	var pop3 := int(home3.population)
	var pool3 := int(home3.pool)
	ok(s3.roster.demobilize(d3, s3.map) == 600 and home3.population == pop3 + 600 and home3.pool == pool3 and not s3.roster.divisions.has(d3), "acceptance 5: disbanding a division at 60 strength returns 600 people to its home city's population (not its pool)")
	# Home city lost: nearest owned city, capital on ties; the flag stays if it is retaken.
	var hm := make_map(10, 10)
	for key in r_rules():
		hm.city_rules[key] = r_rules()[key]
	hm.cities.append({"id": 0, "nation": 0, "cell": Vector2i(0, 0), "population": 10000, "pool": 0, "infrastructure": 10, "radius": 1})
	hm.cities.append({"id": 1, "nation": 0, "cell": Vector2i(4, 0), "population": 10000, "pool": 0, "infrastructure": 10, "radius": 1})
	hm.cities.append({"id": 2, "nation": 0, "cell": Vector2i(2, 0), "population": 10000, "pool": 0, "infrastructure": 10, "radius": 1})
	hm.cities.append({"id": 3, "nation": 1, "cell": Vector2i(8, 8), "population": 10000, "pool": 0, "infrastructure": 10, "radius": 1})
	var droster := make_roster()
	var dd := droster.spawn_division(0, Vector2i(2, 0), "infantry", 2)
	dd.strength = 40.0
	hm.cities.remove_at(2)
	ok(droster.demobilize(dd, hm) == 400 and hm.cities[0].population == 10400 and hm.cities[1].population == 10000, "home city lost: survivors go to the nearest owned city, capital on a tie (400 to city 0)")
	var dd2 := droster.spawn_division(0, Vector2i(5, 0), "infantry", 3)
	dd2.strength = 10.0
	droster.demobilize(dd2, hm)
	ok(hm.city_by_id(3).population == 10000 and hm.cities[1].population == 10100, "home city held by another nation: survivors go to an owned city instead")
	var dd3 := droster.spawn_division(0, Vector2i(5, 1), "infantry", 1)
	hm.capture_city(Vector2i(4, 0), 1)
	ok(dd3.home_city_id == 1, "the home_city_id flag stays when the home city is captured")
	droster.demobilize(dd3, hm)
	ok(hm.city_by_id(1).population < 10000 and hm.cities[0].population == 10400 + 1000, "survivors of a division whose home was captured go to the owner's remaining city (population +1,000)")
	# Reinforcement: 10 strength costs 100 people from the home pool first.
	var s4 := pool_setup()
	var d4: Division = s4.roster.divisions.filter(func(d: Division) -> bool: return d.nation == 0)[0]
	var home4: Dictionary = s4.map.city_by_id(d4.home_city_id)
	d4.strength = 50.0
	var pop4 := int(home4.population)
	s4.eco.reinforce(s4.roster, s4.map)
	ok(d4.strength == 60.0 and home4.pool == 900 and home4.population == pop4 - 100 and s4.eco.reinforce_spent[0] == 100.0, "acceptance 5: reinforcing 10 strength costs 100 people (home pool 1,000 -> 900, population -100)")
	ok(not s4.eco.stocks[0].has("manpower"), "reinforcement no longer touches a nation manpower stock")
	# Preview matches the real thing.
	var s5 := pool_setup()
	var d5: Division = s5.roster.divisions.filter(func(d: Division) -> bool: return d.nation == 0)[0]
	d5.strength = 50.0
	var plan: Dictionary = s5.eco.reinforce_plan(s5.roster, s5.map, s5.eco.current_pools(s5.map), 0)
	ok(plan.gains[d5.id] == 10.0 and s5.map.pool_of(s5.map.city_by_id(d5.home_city_id)) == 1000, "reinforce_plan previews without changing anything")
	# Empty home pool: fall back to the nearest owned city's pool, and partial pools are combined.
	var s6 := pool_setup()
	var d6: Division = s6.roster.divisions.filter(func(d: Division) -> bool: return d.nation == 0)[0]
	var home6: Dictionary = s6.map.city_by_id(d6.home_city_id)
	var other6: Dictionary = nation_cities(s6.map, 0).filter(func(c: Dictionary) -> bool: return c.id != home6.id)[0]
	d6.strength = 50.0
	home6.pool = 0
	other6.pool = 500
	s6.eco.reinforce(s6.roster, s6.map)
	ok(d6.strength == 60.0 and other6.pool == 400 and home6.pool == 0, "an empty home pool falls back to the nearest owned city (500 -> 400)")
	d6.strength = 50.0
	home6.pool = 30
	s6.eco.reinforce(s6.roster, s6.map)
	ok(d6.strength == 60.0 and home6.pool == 0 and other6.pool == 330, "a short home pool is topped up from the next city (30 + 70)")
	d6.strength = 50.0
	home6.pool = 0
	other6.pool = 0
	s6.eco.reinforce(s6.roster, s6.map)
	ok(d6.strength == 50.0 and d6.last_reinforce == 0.0, "no pool anywhere means no reinforcement")
	# Pools are shared in division id order.
	var s7 := pool_setup()
	var mine: Array = s7.roster.divisions.filter(func(d: Division) -> bool: return d.nation == 0)
	for d in mine:
		d.strength = 50.0
	for c in nation_cities(s7.map, 0):
		c.pool = 0
	s7.map.capital_of(0).pool = 150
	s7.eco.reinforce(s7.roster, s7.map)
	ok(mine[0].strength == 60.0 and mine[1].strength == 55.0, "a 150-person pool pays 100 for division %d and 50 for the next (+10, +5)" % mine[0].id)
	# POWs return to the owner's capital population.
	var s8 := pool_setup()
	var pop8 := int(s8.map.capital_of(0).population)
	s8.eco.add_pows(1, 0, 30.0)
	ok(s8.eco.return_pows(1, 0, s8.map) == 30.0 and s8.map.capital_of(0).population == pop8 + 300, "returned POWs (30 strength) add 300 people to the owner's capital")


func r_rules() -> Dictionary:
	return city_rules()


func test_siege_capture_ai() -> void:
	var r := city_rules()
	var fm := make_map(7, 7)
	for key in r:
		fm.city_rules[key] = r[key]
	var city := {"id": 0, "nation": 0, "cell": Vector2i(3, 3), "population": 10000, "pool": 1000, "infrastructure": 10, "radius": 1}
	fm.cities.append(city)
	var nbrs := fm.neighbors(city.cell)
	var enemy_units := {}
	for n in nbrs:
		enemy_units[n] = 1
	ok(fm.is_besieged(city, enemy_units), "a city with an enemy division on every land neighbor is besieged")
	var mixed := enemy_units.duplicate()
	mixed[nbrs[0]] = 0
	ok(not fm.is_besieged(city, mixed), "one friendly division on a neighbor breaks the siege")
	ok(not fm.is_besieged(city, {}), "unclaimed land and no units is not a siege")
	for n in nbrs:
		fm.cells[n] = 1
	ok(fm.is_besieged(city, {}), "all neighbors owned by an enemy nation is a siege")
	fm.cells[nbrs[1]] = HexMap.UNCLAIMED
	ok(not fm.is_besieged(city, {}), "a neutral neighbor is not enemy-held")
	fm.cells[nbrs[1]] = 1
	fm.cells[nbrs[2]] = HexMap.WATER
	ok(fm.is_besieged(city, {}), "water neighbors are ignored")
	for n in nbrs:
		fm.cells[n] = HexMap.WATER
	ok(not fm.is_besieged(city, enemy_units), "a city with no land neighbors is never besieged")
	for n in nbrs:
		fm.cells[n] = HexMap.UNCLAIMED
	# Effects: growth 0, -2% population a turn, labor halved.
	var eco := NationEconomy.new()
	var before := city.duplicate()
	fm.grow_cities(enemy_units)
	ok(city.besieged and city.population == 9800 and fm.growth_rate(city) == 0.0, "siege: population -2% (10,000 -> 9,800), growth 0")
	ok(city.pool == mini(1000 + fm.pool_fill({"population": 9800}), fm.pool_cap({"population": 9800})), "the pool still fills during a siege (and is capped by the lower population)")
	ok(eco.labor_points(city) == 2 and eco.labor_points(before) == 5, "siege halves labor (9,800 people: 4.9 / 2 -> 2 points, was 5)")
	fm.grow_cities({})
	ok(not city.besieged and city.population > 9800, "the siege ends and growth resumes when the ring is broken")
	# Capture: the new owner gets an empty pool, a reset labor plan and no siege flag.
	var m := build(5)
	var ceco := NationEconomy.new()
	ceco.setup(m)
	var target := nation_cities(m, 1)[0]
	target.pool = 1000
	target.besieged = true
	target.infra_progress = 7
	m.capture_city(target.cell, 0)
	ok(target.nation == 0 and target.pool == 0 and not target.besieged and not target.has("labor") and target.infra_progress == 0, "capture empties the pool and resets labor, infra progress and the siege flag")
	ok(target.population == 7500, "capture still costs 25% of the people (10,000 -> 7,500)")
	ceco.refresh_labor(m)
	ok(target.labor.growth == 1, "the new owner's city gets the default labor split (3 points: 1 Growth)")
	# AI: same pool and floor rules, default labor assignment.
	var s := pool_setup()
	var m2: HexMap = s.map
	var eco2: NationEconomy = s.eco
	var roster: DivisionRoster = s.roster
	roster.divisions.clear()
	eco2.config.ai_recruit_chance = 1.0
	for c in m2.cities:
		c.pool = 0
	for nation in m2.nations:
		eco2.stocks[nation].capacity = 100.0
	eco2.run_ai(0, m2, roster)
	ok(eco2.pending.is_empty(), "the AI does not recruit from cities with empty pools")
	var ai_cap: Dictionary = m2.capital_of(m2.nations.filter(func(n: int) -> bool: return n != 0)[0])
	ai_cap.pool = 1000
	ai_cap.population = 5500
	eco2.run_ai(0, m2, roster)
	ok(eco2.pending.is_empty(), "the AI respects the 5,000-person floor (5,500 people, 1,000 pool)")
	ai_cap.population = 10000
	eco2.run_ai(0, m2, roster)
	ok(eco2.pending.has(ai_cap.id) and ai_cap.pool == 0 and ai_cap.population == 9000, "an AI capital with a full pool recruits and pays 1,000 people")
	ok(m2.cities.all(func(c: Dictionary) -> bool: return c.has("labor") and c.labor.training >= 0), "AI cities get the default labor assignment (and auto-training for the recruit)")
