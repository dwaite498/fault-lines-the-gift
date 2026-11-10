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
	test_stalled_recruit()
	test_pillars_rules()
	test_ai_upkeep_cap()
	test_capture_choices()
	test_capture_flow()
	test_capture_gating()
	test_atrocity_views()
	test_main_menu()
	test_save_load()
	test_victory()
	test_colonizers()
	test_fog()
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
	ok(r.division_people_cost == 1000 and not r.has("people_per_strength") and is_equal_approx(r.pool_fill_rate, 0.005) and is_equal_approx(r.pool_cap, 0.15), "config: division 1,000 people, fill 0.5%, cap 15% (people_per_strength moved to the division type)")
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
	ok(s8.eco.return_pows(1, 0, s8.map, s8.roster) == 30.0 and s8.map.capital_of(0).population == pop8 + 300, "returned POWs (30 strength) add 300 people to the owner's capital")


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
	eco2.city_rules.colonization.ai_build_pods = false  # these checks are about division recruiting
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


func test_stalled_recruit() -> void:
	var s := sink_setup(0, 0)
	var eco: NationEconomy = s.eco
	var city: Dictionary = s.city
	ok(not eco.recruit_stalled(city), "no recruit queued: not stalled")
	eco.recruit(city, 0, s.roster)
	city.labor = {"training": 0, "infrastructure": 0, "growth": 2}
	ok(eco.recruit_stalled(city) and eco.stalled_cities(0, s.map) == [city.id], "a queued recruit with 0 Training labor is stalled and listed")
	var panel := CityPanel.new()
	panel.hex_map = s.map
	panel.economy = eco
	panel.roster = s.roster
	panel.player_nation = 0
	panel.factions = FactionRoster.from_config({"seed": 5, "faction_count": 4, "faction_seed": -1})
	panel.refresh(city)
	ok(panel.label.text.contains("Recruit stalled: assign Training labor"), "the city panel says 'Recruit stalled: assign Training labor'")
	city.labor.training = 2
	panel.refresh(city)
	ok(not eco.recruit_stalled(city) and not panel.label.text.contains("Recruit stalled") and eco.stalled_cities(0, s.map).is_empty(), "assigning Training clears the warning")
	panel.free()


# --- Task 38b: Pillars recruiting rules ---

func test_pillars_rules() -> void:
	var t := DivisionRoster.load_templates()
	var inf: Dictionary = t.infantry
	ok(inf.people_per_strength == 10 and inf.upkeep.size() == 1 and inf.upkeep.cash == 3, "config: infantry has 10 people per strength and 3 cash upkeep (divisions_config.json)")
	ok(t.mechanized.future and t.mechanized.people_per_strength == 5 and t.mechanized.upkeep.cash == 6 and t.mechanized.upkeep.alloy == 1, "config: mechanized is a future entry (5 people/strength, 6 cash, 1 alloy)")
	ok(t.robotic.future and t.robotic.people_per_strength == 2 and t.robotic.upkeep.cash == 10 and t.robotic.upkeep.alloy == 1 and t.robotic.upkeep.fuel == 1, "config: robotic is a future entry (2 people/strength, 10 cash, 1 alloy, 1 fuel)")
	var r := make_roster()
	ok(r.spawn_division(0, Vector2i(0, 0), "mechanized") == null and r.divisions.is_empty(), "future division types cannot be spawned (no units yet)")
	# Full strength, no splitting.
	var s := pool_setup()
	var rc := nation_cities(s.map, 0)[0]
	s.roster.divisions.assign(s.roster.divisions.filter(func(d: Division) -> bool: return d.hex != rc.cell))
	s.eco.stocks[0].capacity = 100.0
	s.eco.recruit(rc, 0, s.roster)
	rc.labor = {"training": 5, "infrastructure": 0, "growth": 0}
	for i in 4:
		s.eco.spawn_pending(s.map, s.roster)
	var fresh: Division = s.roster.division_at(rc.cell)
	ok(fresh != null and fresh.strength == 100.0 and fresh.strength == fresh.max_strength, "a recruited division starts at full strength (100)")
	ok(s.roster.spawn_division(0, Vector2i(0, 0), "infantry").strength == 100.0, "spawn_division always makes a full-strength division")
	ok(not s.roster.has_method("split_division") and not s.eco.has_method("recruit_partial"), "there is no split and no partial recruit")
	ok(s.eco.recruit_block_reason(nation_cities(s.map, 0)[1], 0, s.roster) != "", "a recruit always costs the full 1,000 people (a colony with an empty pool cannot recruit a small one)")
	# No training while besieged or starving; the queue waits.
	for flag in ["besieged", "starving"]:
		var b := sink_setup(5, 0)
		b.eco.recruit(b.city, 0, b.roster)
		b.city.labor = {"training": 5, "infrastructure": 0, "growth": 0}
		b.eco.spawn_pending(b.map, b.roster)
		var progress: int = b.eco.pending[b.city.id].labor
		var turns: int = b.eco.pending[b.city.id].turns_left
		b.city[flag] = true
		for i in 6:
			b.eco.spawn_pending(b.map, b.roster)
		ok(b.eco.pending[b.city.id].labor == progress and b.eco.pending[b.city.id].turns_left == turns and b.roster.divisions.is_empty(), "a %s city makes no training progress (labor %d, %d turns left, no division)" % [flag, progress, turns])
		ok(not b.eco.recruit_stalled(b.city), "a %s queue is paused, not 'stalled'" % flag)
		b.city.erase(flag)
		for i in 4:
			b.eco.spawn_pending(b.map, b.roster)
		ok(b.roster.divisions.size() == 1, "training resumes and finishes once the %s state ends" % flag)
		var b2 := sink_setup(5, 0)
		b2.city[flag] = true
		ok(b2.eco.recruit_block_reason(b2.city, 0, b2.roster).contains(flag) and not b2.eco.recruit(b2.city, 0, b2.roster), "a %s city cannot start a recruit" % flag)
	# Reinforcement skips empty pools (and enslaved cities' pools).
	var rs := pool_setup()
	var d: Division = rs.roster.divisions.filter(func(x: Division) -> bool: return x.nation == 0)[0]
	var home: Dictionary = rs.map.city_by_id(d.home_city_id)
	var other: Dictionary = nation_cities(rs.map, 0).filter(func(c: Dictionary) -> bool: return c.id != home.id)[0]
	d.strength = 50.0
	home.pool = 1000
	home.enslaved = true
	other.pool = 500
	rs.eco.reinforce(rs.roster, rs.map)
	ok(d.strength == 60.0 and home.pool == 1000 and other.pool == 400, "reinforcement skips an enslaved city's pool and draws from the next city (500 -> 400)")
	home.erase("enslaved")
	home.pool = 0
	other.pool = 0
	d.strength = 50.0
	rs.eco.reinforce(rs.roster, rs.map)
	ok(d.strength == 50.0, "reinforcement skips empty pools (nothing to draw)")
	# Enslaved cities cannot train.
	var e := sink_setup(0, 0)
	e.city.enslaved = true
	ok(e.eco.recruit_block_reason(e.city, 0, e.roster).contains("enslaved"), "an enslaved city cannot recruit")
	e.eco.ensure_labor(e.city)
	ok(e.eco.set_labor(e.city, "training", 3) == 0 and e.city.labor.training == 0, "an enslaved city's labor cannot go to Training")
	e.city.labor.training = 2
	e.eco.ensure_labor(e.city)
	ok(e.city.labor.training == 0, "existing Training labor is dropped when a city is enslaved")
	var before: Dictionary = e.city.labor.duplicate()
	e.eco.auto_training(e.city)
	ok(e.city.labor.training == 0 and e.city.labor == before, "auto-training does nothing for an enslaved city")
	e.city.pool = 700
	e.map._advance_people(e.city)
	ok(e.city.pool == 0, "an enslaved city's pool is 0 permanently")
	var panel := CityPanel.new()
	panel.hex_map = e.map
	panel.economy = e.eco
	panel.roster = e.roster
	panel.player_nation = 0
	panel.factions = FactionRoster.from_config({"seed": 5, "faction_count": 4, "faction_seed": -1})
	panel.refresh(e.city)
	ok(panel.labor_rows.training.plus.disabled, "an enslaved city's Training + button is disabled")
	panel.free()
	e.map.capture_city(e.city.cell, 1)
	ok(not e.city.has("enslaved"), "capture clears the enslaved flag for the new owner (Task 39 sets it by choice)")
	# The AI follows the same rules.
	for flag in ["besieged", "starving", "enslaved"]:
		var a := pool_setup()
		a.roster.divisions.clear()
		a.eco.city_rules.colonization.ai_build_pods = false
		a.eco.config.ai_recruit_chance = 1.0
		for nation in a.map.nations:
			a.eco.stocks[nation].capacity = 100.0
		var acap: Dictionary = a.map.capital_of(a.map.nations.filter(func(n: int) -> bool: return n != 0)[0])
		acap[flag] = true
		a.eco.run_ai(0, a.map, a.roster)
		ok(not a.eco.pending.has(acap.id), "the AI does not recruit in a %s city" % flag)
		acap.erase(flag)
		a.eco.run_ai(0, a.map, a.roster)
		ok(a.eco.pending.has(acap.id), "the AI recruits there once it is not %s" % flag)
	# Upkeep per division type, and the unpaid consequence.
	var u := pool_setup()
	var mine: Array = u.roster.divisions.filter(func(x: Division) -> bool: return x.nation == 0)
	ok(u.eco.upkeep_due(0, u.roster) == {"cash": 3.0 * mine.size()}, "upkeep is 3 cash per infantry division (%d divisions)" % mine.size())
	ok(not u.eco.config.has("upkeep_per_division"), "the global upkeep_per_division is gone (per-type upkeep)")
	u.eco.stocks[0].cash = 3.0 * mine.size()
	u.eco.stocks[0].capacity = 40.0
	u.eco.pay_upkeep(u.map, u.roster)
	ok(u.eco.stocks[0].cash == 0.0 and u.eco.stocks[0].capacity == 40.0 and u.eco.upkeep_paid[0] and not u.eco.unpaid_divisions.has(0), "upkeep paid in full takes only cash and leaves nothing unpaid")
	u.eco.stocks[0].cash = 4.0
	for x in mine:
		x.org = 30.0
	u.eco.pay_upkeep(u.map, u.roster)
	ok(u.eco.stocks[0].cash == 1.0 and u.eco.unpaid_divisions[0] == [mine[1].id] and mine[0].org == 30.0 and mine[1].org == 25.0 and not u.eco.upkeep_paid[0], "cash 4 pays one division (id order); the other is unpaid, loses 5 org (config unpaid_upkeep_org_loss) and cash stays >= 0")
	u.eco.stocks[0].cash = 0.0
	for x in mine:
		x.org = 3.0
	u.eco.pay_upkeep(u.map, u.roster)
	ok(u.eco.stocks[0].cash == 0.0 and u.eco.unpaid_divisions[0].size() == mine.size() and mine.all(func(x: Division) -> bool: return x.org == 0.0), "with no cash every division is unpaid, org clamps at 0 and cash never goes negative")
	ok(u.map.nations.all(func(n: int) -> bool: return u.eco.stocks[n].cash >= 0.0), "no nation (AI included) has negative cash")
	u.eco.stocks[0].cash = 100.0
	u.eco.pay_upkeep(u.map, u.roster)
	ok(not u.eco.unpaid_divisions.has(0), "the unpaid list resets each turn")
	# Survivors use the division type's people_per_strength.
	var dm := pool_setup()
	var dv: Division = dm.roster.divisions.filter(func(x: Division) -> bool: return x.nation == 0)[0]
	dm.roster.templates = dm.roster.templates.duplicate(true)
	dm.roster.templates.infantry.people_per_strength = 5
	dv.strength = 60.0
	ok(dm.roster.demobilize(dv, dm.map) == 300, "survivors return at the division type's people_per_strength (60 x 5 = 300)")
	# QA nit: the main.gd header names the real keys.
	var header := FileAccess.get_file_as_string("res://scripts/main.gd").substr(0, 900)
	ok(header.contains("N toggles the military panel") and header.contains("K removes the newest city") and not header.contains("D removes"), "main.gd header comment names N and K (not M and D)")


func test_ai_upkeep_cap() -> void:
	var a := pool_setup()
	var m: HexMap = a.map
	var eco: NationEconomy = a.eco
	var roster: DivisionRoster = a.roster
	eco.config.ai_recruit_chance = 1.0
	eco.city_rules.colonization.ai_build_pods = false  # these checks are about division recruiting
	var nation: int = m.nations.filter(func(n: int) -> bool: return n != 0)[0]
	for n in m.nations:
		eco.stocks[n].capacity = 100.0
	var cap := m.capital_of(nation)
	var income := eco.cash_income(nation, m)
	var fielded: int = roster.divisions.filter(func(d: Division) -> bool: return d.nation == nation).size()
	ok(income == 6.0 and fielded == 2 and eco.projected_cash_upkeep(nation, roster) == 6.0, "setup: the AI nation makes 6 cash and its 2 divisions cost 6")
	# Free the capital hex so only upkeep can stop the recruit.
	roster.divisions.assign(roster.divisions.filter(func(d: Division) -> bool: return d.hex != cap.cell))
	ok(eco.projected_cash_upkeep(nation, roster, 1) == 6.0 and eco.projected_cash_upkeep(nation, roster, 1) <= income, "with 1 division left, a new one brings upkeep to exactly the income: allowed")
	eco.run_ai(0, m, roster)
	ok(eco.pending.has(cap.id), "the AI recruits when projected upkeep equals its income")
	cap.pool = 1000
	eco.pending.erase(cap.id)
	var other: Dictionary = m.cities.filter(func(c: Dictionary) -> bool: return c.nation == nation and c.id != cap.id)[0]
	eco.pending[other.id] = {"nation": nation, "turns_left": 3, "labor": 0, "cost": 15}
	other.pool = 0
	ok(eco.projected_cash_upkeep(nation, roster) == 6.0 and eco.projected_cash_upkeep(nation, roster, 1) == 9.0, "queued recruits count toward projected upkeep (1 fielded + 1 queued = 6, +1 new = 9)")
	cap.pool = 1000
	cap.population = 10000
	eco.run_ai(0, m, roster)
	ok(not eco.pending.has(cap.id), "the AI queues no recruit when upkeep after it (9) would exceed its income (6)")


## A map where nation 0 captures nation 1's first city: {"map", "eco", "roster", "city", "other"}.
func cap_setup() -> Dictionary:
	var s := pool_setup()
	s.roster.economy = s.eco
	var cities := nation_cities(s.map, 1)
	var guard: Division = s.roster.division_at(cities[0].cell)
	if guard:
		s.roster.divisions.erase(guard)  # an empty enemy city, so it can be captured
	s["city"] = cities[0]
	s["other"] = cities[1]
	return s


## take_city + apply_capture through the roster (credits plunder), returns the result.
func capture_with(s: Dictionary, city: Dictionary, captor: int, option: String) -> Dictionary:
	s.roster.pending_captures.append(s.map.take_city(city.cell, captor))
	return s.roster.apply_capture(int(city.id), option, s.map)


func test_capture_choices() -> void:
	# Taking a city only hands it over; the choice applies the effects.
	var s := cap_setup()
	var c: Dictionary = s.city
	var m: HexMap = s.map
	var taken: Dictionary = m.take_city(c.cell, 0)
	ok(c.nation == 0 and c.capture_pending and c.population == 10000 and taken.victim == 1 and taken.eliminated.is_empty(), "take_city hands the city over and flags it pending, with no losses yet")
	ok(m.apply_capture(int(c.id), "annex").option == "annex" and m.apply_capture(int(c.id), "annex").is_empty(), "a choice applies once")
	# Annex.
	var s1 := cap_setup()
	var c1: Dictionary = s1.city
	var r1 := capture_with(s1, c1, 0, "annex")
	ok(c1.population == 7500 and is_equal_approx(float(c1.infrastructure), 7.0) and c1.rebuild_target == 10.0 and c1.rebuild_turns_left == 26, "Annex: -25% people, -30% infra (10 -> 7), rebuilds over 26 turns")
	ok(c1.pool == 0 and c1.recruit_lockout == 10 and not c1.has("capture_pending"), "Annex: pool 0 and a 10-turn recruit lockout")
	var reason: String = s1.eco.recruit_block_reason(c1, 0, s1.roster)
	ok(reason.contains("locked out"), "Annex: the lockout blocks recruiting (%s)" % reason)
	for i in 9:
		s1.map.grow_cities({})
	ok(c1.recruit_lockout == 1 and s1.eco.training_blocked(c1) != "", "Annex: still locked after 9 end turns")
	s1.map.grow_cities({})
	ok(c1.recruit_lockout == 0 and s1.eco.training_blocked(c1) == "", "Annex: the lockout ends after 10 end turns")
	ok(r1.severity == 0 and not r1.atrocity and s1.map.reputation.count("annex") == 1, "Annex logs a severity-0 reputation_event")
	# Occupy.
	var s2 := cap_setup()
	var c2: Dictionary = s2.city
	c2.pool = 800
	var r2 := capture_with(s2, c2, 0, "occupy")
	ok(c2.population == 9000 and float(c2.infrastructure) == 10.0 and not c2.has("rebuild_turns_left") and c2.occupied and c2.occupy_turns_left == 5, "Occupy: -10% people, no infra loss, a 5-turn timer")
	ok(s2.eco.labor_points(c2) == 2 and s2.eco.training_blocked(c2) == "occupied", "Occupy: labor at 50% (9,000 people: 4.5 x 0.5 -> 2 points), no training")
	s2.map.grow_cities({})
	ok(c2.pool == 0 and c2.occupy_turns_left == 4 and not s2.map.annex_occupied(int(c2.id)), "Occupy: the pool stays 0, the timer counts down and an early annex is refused")
	for i in 4:
		s2.map.grow_cities({})
	ok(s2.map.can_annex_occupied(c2), "Occupy: annexable after 5 end turns")
	var pop2 := int(c2.population)
	ok(s2.map.annex_occupied(int(c2.id)) and int(c2.population) == pop2 and not c2.has("occupied") and c2.recruit_lockout == 10 and c2.pool == 0, "annexing an occupied city costs no more people, starts the 10-turn lockout and keeps pool 0")
	ok(s2.map.reputation.count("occupy") == 1 and s2.map.reputation.count("annex") == 1 and r2.severity == 0, "Occupy and the later Annex each log an event")
	# Plunder.
	var s3 := cap_setup()
	var c3: Dictionary = s3.city
	var cash3: float = s3.eco.stocks[0].cash
	var r3 := capture_with(s3, c3, 0, "plunder")
	ok(is_equal_approx(float(r3.cash), 50.0) and is_equal_approx(s3.eco.stocks[0].cash, cash3 + 50.0), "Plunder: +5 cash per 1,000 people (10,000 people -> +50 cash, credited to the captor)")
	ok(c3.population == 8500 and is_equal_approx(float(c3.infrastructure), 5.0) and c3.recruit_lockout == 10 and c3.pool == 0, "Plunder: -15% people, -50% infra, annexed with the lockout")
	ok(r3.severity == 1 and not r3.atrocity, "Plunder logs severity 1")
	# Reduce.
	var s4 := cap_setup()
	var c4: Dictionary = s4.city
	var other4: Dictionary = s4.other
	var r4 := capture_with(s4, c4, 0, "reduce")
	ok(c4.population == 5000 and is_equal_approx(float(c4.infrastructure), 5.0) and c4.recruit_lockout == 10, "Reduce: -50% people, -50% infra, annexed with the lockout")
	ok(other4.population == 15000 and r4.refugees == 5000 and r4.lost_people == 0, "Reduce: the displaced 5,000 flee to the old owner's nearest city (+5,000 refugees)")
	ok(r4.severity == 2 and not r4.atrocity, "Reduce logs severity 2")
	# Raze.
	var s5 := cap_setup()
	var c5: Dictionary = s5.city
	var other5: Dictionary = s5.other
	var cell5: Vector2i = c5.cell
	var r5 := capture_with(s5, c5, 0, "raze")
	ok(s5.map.city_by_id(int(c5.id)).is_empty() and s5.map.city_at(cell5).is_empty() and s5.map.cells[cell5] != 1, "Raze: the city is removed and its hex no longer belongs to the old owner")
	ok(other5.population == 15000 and r5.refugees == 5000 and r5.lost_people == 5000, "Raze: 50% of the people flee to the old owner's nearest city (+5,000), the rest die")
	ok(r5.severity == 3 and r5.atrocity and s5.map.reputation.atrocities(0).size() == 1 and s5.map.reputation.events[0].type == "raze", "Raze logs an atrocity with severity 3")
	# Raze on a last city eliminates the nation, with its armies surrendering as POWs.
	var s6 := cap_setup()
	var c6: Dictionary = s6.city
	var m6: HexMap = s6.map
	m6.remove_city(int(s6.other.id))
	var cell6: Vector2i = c6.cell
	var taken6: Dictionary = m6.take_city(cell6, 0)
	s6.roster.surrender(taken6.eliminated, 0)
	s6.roster.pending_captures.append(taken6)
	var r6: Dictionary = s6.roster.apply_capture(int(c6.id), "raze", m6)
	ok(taken6.eliminated == [1] and not m6.nations.has(1) and m6.city_by_id(int(c6.id)).is_empty(), "Raze on a last city is allowed and eliminates the nation")
	ok(r6.atrocity and r6.severity == 3 and r6.refugees == 0 and r6.lost_people == 10000, "a last-city Raze is still an atrocity; with no city left the refugees are lost")
	ok(s6.roster.divisions.all(func(d: Division) -> bool: return d.nation != 1) and s6.eco.pows_held(0) > 0.0, "the eliminated nation's divisions surrender as POWs held by the captor")
	# Enslave.
	var s7 := cap_setup()
	var c7: Dictionary = s7.city
	c7.pool = 700
	var r7 := capture_with(s7, c7, 0, "enslave")
	ok(c7.population == 9000 and float(c7.infrastructure) == 10.0 and c7.enslaved and not c7.has("rebuild_turns_left"), "Enslave: -10% people, no infra loss, city.enslaved set")
	ok(s7.map.growth_rate(c7) == 0.0 and s7.eco.labor_points(c7) == 6 and s7.eco.training_blocked(c7) == "enslaved", "Enslave: no growth, labor x1.5 (9,000 people: 4.5 x 1.5 -> 6 points), no training")
	var pop7 := int(c7.population)
	s7.map.grow_cities({})
	ok(c7.pool == 0 and c7.population == pop7, "Enslave: the pool stays 0 and the population stays put")
	ok(r7.severity == 3 and not r7.atrocity, "Enslave logs severity 3 (not flagged an atrocity: only Raze always is)")
	# Re-capture clears the previous capture's states.
	var s8 := cap_setup()
	var c8: Dictionary = s8.city
	capture_with(s8, c8, 0, "enslave")
	capture_with(s8, c8, 1, "annex")
	ok(c8.nation == 1 and not c8.has("enslaved") and c8.recruit_lockout == 10, "re-capturing an enslaved city clears enslaved and applies the new choice")
	ok(s8.map.reputation.count() == 2, "every choice logged exactly one reputation_event")
	# Config: all numbers come from city_rules.capture.
	var s9 := cap_setup()
	s9.map.city_rules.capture.options.occupy.pop_loss = 0.2
	s9.map.city_rules.capture.annexed_recruit_lockout_turns = 3
	capture_with(s9, s9.city, 0, "occupy")
	ok(s9.city.population == 8000, "the capture numbers are config (occupy pop_loss 0.2 -> 8,000)")


func test_capture_flow() -> void:
	# Capturing an empty enemy city with a move leaves the choice pending.
	var s := cap_setup()
	var m: HexMap = s.map
	var roster: DivisionRoster = s.roster
	var city: Dictionary = s.city
	var guard := roster.division_at(city.cell)
	if guard:
		roster.divisions.erase(guard)
	var from := Vector2i(-1, -1)
	for n in m.neighbors(city.cell):
		if m.can_step(n, city.cell) and roster.division_at(n) == null:
			from = n
			break
	ok(from != Vector2i(-1, -1), "setup: a land hex next to the enemy city")
	var mover := roster.spawn_division(0, from, "infantry", 0)
	mover.moves_left = 5
	ok(roster.try_move(mover, city.cell, m) and city.nation == 0 and roster.pending_captures.size() == 1 and city.capture_pending and city.population == 10000, "moving into an empty enemy city takes it and queues the choice (no effects yet)")
	# The AI's captures take the default choice (Annex); the player's stay pending for the popup.
	roster.resolve_ai_captures(m, 0)
	ok(roster.pending_captures.size() == 1, "the player's capture stays pending after the AI resolves")
	roster.resolve_ai_captures(m, 5)
	ok(roster.pending_captures.is_empty() and city.population == 7500 and city.recruit_lockout == 10, "a non-player capture takes the AI default (Annex)")
	# The AI default is a config key; an AI Occupy is auto-annexed when its timer is up.
	var s2 := cap_setup()
	s2.map.city_rules.capture.ai_default_option = "occupy"
	s2.roster.pending_captures.append(s2.map.take_city(s2.city.cell, 1 if s2.city.nation == 0 else 0))
	s2.roster.resolve_ai_captures(s2.map, 99)
	ok(s2.city.occupied and s2.city.occupy_turns_left == 5, "ai_default_option occupy: the AI occupies")
	for i in 5:
		s2.map.grow_cities({})
	s2.roster.resolve_ai_captures(s2.map, 99)
	ok(not s2.city.get("occupied", false) and s2.city.recruit_lockout == 10, "the AI annexes an occupied city once its timer is up")
	# The popup lists the six choices and reports the pick.
	var popup := CapturePopup.new()
	popup.open(city, "Nation 1", m.city_rules)
	ok(popup.is_open() and popup.buttons.keys() == ["annex", "occupy", "plunder", "reduce", "raze", "enslave"], "the capture popup offers Annex, Occupy, Plunder, Reduce, Raze and Enslave in order")
	var picked := []
	popup.chosen.connect(func(o: String) -> void: picked.append(o))
	popup.buttons.raze.pressed.emit()
	ok(picked == ["raze"] and not popup.is_open(), "pressing a choice reports it and closes the popup")
	var annex_text := CapturePopup.effect_text("annex", m.city_rules)
	ok(annex_text.contains("25%") and annex_text.contains("30%") and annex_text.contains("10 turns"), "the popup text comes from the config numbers")
	ok(CapturePopup.effect_text("raze", m.city_rules).contains("ATROCITY"), "Raze is marked an atrocity in the popup")
	popup.free()


# --- Task 40: capture gating and AI choice by personality ---

## The CAPTURE.md gating table, written out independently of the config.
const GATING := {
	"assembly": ["annex", "occupy"],
	"directorate": ["annex", "occupy", "reduce", "raze"],
	"syndicate": ["annex", "occupy", "plunder"],
	"verdant_accord": ["annex", "occupy", "reduce"],
	"covenant": ["annex", "occupy", "reduce"],
	"collective": ["annex", "occupy", "enslave", "raze"],
	"lyceum": ["annex", "occupy"],
	"free_tide": ["annex", "occupy", "plunder", "enslave"],
	"deepwater_guild": ["annex", "occupy", "plunder", "enslave"],
	"drift": ["annex", "plunder", "raze"],
}


## A map whose nation `n` plays faction `faction_id` (nation 0 captures nation 1's city).
func gated_setup(faction_id: String, victim_faction := "assembly") -> Dictionary:
	var s := cap_setup()
	s.map.nation_factions = {0: faction_id, 1: victim_faction}
	return s


func test_capture_gating() -> void:
	var rules: Dictionary = city_rules().capture
	var ids: Array = FactionRoster.load_all().map(func(f: Dictionary) -> String: return f.id)
	ok(rules.faction_options.keys().size() == 10 and ids.all(func(id: String) -> bool: return rules.faction_options.has(id)), "config: the gating table has a row for every faction id in factions.json")
	for id in GATING:
		ok(rules.faction_options[id] == GATING[id] and rules.faction_options[id].has("annex"), "config: %s may use %s (and always Annex)" % [id, GATING[id]])
	var m := pop_map()
	for id in GATING:
		m.nation_factions = {0: id}
		var allowed := m.allowed_capture_options(0)
		var expect: Array = rules.order.filter(func(o: String) -> bool: return GATING[id].has(o))
		ok(allowed == expect and allowed.size() == GATING[id].size(), "%s: allowed options come from the table, in menu order" % id)
		for opt in rules.order:
			ok((m.capture_block_reason(0, opt) == "") == GATING[id].has(opt), "%s: %s %s" % [id, opt, "allowed" if GATING[id].has(opt) else "gated with a reason"])
	ok(m.capture_block_reason(0, "bogus") != "", "an unknown option is blocked")
	m.nation_factions = {}
	ok(m.allowed_capture_options(0).size() == 6 and m.capture_block_reason(0, "raze") == "", "a nation with no faction is ungated")
	# A gated option falls back to Annex when applied.
	var s := gated_setup("assembly")
	var r := capture_with(s, s.city, 0, "raze")
	ok(r.option == "annex" and not s.map.city_by_id(int(s.city.id)).is_empty() and s.city.population == 7500, "a gated Raze (Assembly) is applied as Annex")
	var s2 := gated_setup("directorate")
	ok(capture_with(s2, s2.city, 0, "raze").option == "raze", "an allowed Raze (Directorate) is applied")
	# Harshest allowed option, by harshness_order.
	var harsh := {"assembly": "occupy", "directorate": "raze", "syndicate": "plunder", "verdant_accord": "reduce",
			"covenant": "reduce", "collective": "raze", "lyceum": "occupy", "free_tide": "enslave",
			"deepwater_guild": "enslave", "drift": "raze"}
	for id in harsh:
		m.nation_factions = {0: id}
		ok(m.harshest_capture_option(0) == harsh[id], "%s: harshest allowed option is %s" % [id, harsh[id]])
	# AI choice: aggressive factions pick their harshest 50% of the time, others always Annex.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id in GATING:
		m.nation_factions = {0: id}
		var picks := {}
		for i in 400:
			var pick := m.ai_capture_option(0, rng)
			picks[pick] = int(picks.get(pick, 0)) + 1
			if m.capture_block_reason(0, pick) != "":
				picks["illegal"] = 1
		if ["directorate", "collective", "free_tide", "drift"].has(id):
			var share := float(picks.get(harsh[id], 0)) / 400.0
			ok(picks.size() == 2 and picks.has("annex") and share > 0.4 and share < 0.6, "%s (aggressive): Annex or %s, about half each (%.2f)" % [id, harsh[id], share])
		else:
			ok(picks == {"annex": 400}, "%s: always Annex" % id)
	m.nation_factions = {0: "drift"}
	m.city_rules.capture.aggressive_harsh_chance = 1.0
	ok(m.ai_capture_option(0, rng) == "raze", "aggressive_harsh_chance is config (1.0: always the harshest)")
	m.city_rules.capture.aggressive_harsh_chance = 0.0
	ok(m.ai_capture_option(0, rng) == "annex", "aggressive_harsh_chance 0.0: always Annex")
	m.city_rules.capture.aggressive_harsh_chance = 1.0
	ok(m.ai_capture_option(0, null) == "annex", "no rng: Annex")
	# ai_default_option is only the fallback for a nation with no faction.
	m.city_rules.capture.ai_default_option = "reduce"
	m.nation_factions = {}
	ok(m.ai_capture_option(0, rng) == "reduce", "no faction: ai_default_option is the fallback")
	m.nation_factions = {0: "assembly"}
	ok(m.ai_capture_option(0, rng) == "annex", "a faction ignores ai_default_option")
	m.nation_factions = {}
	m.city_rules.capture.ai_default_option = "raze"
	m.nation_factions = {0: "lyceum"}
	m.city_rules.capture.faction_options.lyceum = ["annex"]
	ok(m.ai_capture_option(0, rng) == "annex", "the AI never picks a gated option")
	# End to end: an aggressive AI captor resolves through the roster with its personality.
	var s3 := gated_setup("directorate")
	s3.map.city_rules.capture.aggressive_harsh_chance = 1.0
	s3.roster.pending_captures.append(s3.map.take_city(s3.city.cell, 0))
	var cid := int(s3.city.id)
	s3.roster.resolve_ai_captures(s3.map, 99)
	ok(s3.map.city_by_id(cid).is_empty() and s3.map.reputation.events.back().type == "raze", "a Directorate AI razes a captured city")
	var s4 := gated_setup("assembly")
	s4.roster.pending_captures.append(s4.map.take_city(s4.city.cell, 0))
	s4.roster.resolve_ai_captures(s4.map, 99)
	ok(s4.city.recruit_lockout == 10 and s4.map.reputation.events.back().type == "annex", "an Assembly AI annexes")
	# Faction roster mapping.
	var fr := FactionRoster.from_config({"seed": 5, "faction_count": 4, "faction_seed": -1})
	ok(fr.nation_ids().size() == 4 and fr.id_of(0) == fr.assigned[0].id and fr.id_of(9) == "", "FactionRoster maps nations to faction ids")
	# Popup: gated options are disabled with a reason.
	var popup := CapturePopup.new()
	var blocked := {"raze": "Not available to the Assembly.", "enslave": "Not available to the Assembly."}
	popup.open(s.city, "Nation 1", city_rules(), blocked)
	var open_ids := popup.buttons.keys().filter(func(id: String) -> bool: return not popup.buttons[id].disabled)
	ok(open_ids == ["annex", "occupy", "plunder", "reduce"], "the popup disables gated options")
	ok(popup.buttons.raze.get_parent().get_child(1).text == "Not available to the Assembly.", "a gated option shows its reason instead of its effects")
	ok(popup.buttons.annex.get_parent().get_child(1).text.contains("25%"), "an allowed option still shows its effects")
	popup.free()
	# City panel: occupied and enslaved cities show a pool held at 0, no fill rate.
	var sp := pool_setup()
	var pc := nation_cities(sp.map, 0)[0]
	var panel := CityPanel.new()
	panel.hex_map = sp.map
	panel.economy = sp.eco
	panel.roster = sp.roster
	panel.player_nation = 0
	panel.factions = fr
	panel.refresh(pc)
	ok(panel.label.text.contains("/turn, cap"), "a normal city shows its pool fill and cap")
	pc.occupied = true
	pc.occupy_turns_left = 3
	panel.refresh(pc)
	ok(panel.label.text.contains("Recruitable 0 (held at 0)") and not panel.label.text.contains("/turn, cap"), "an occupied city shows Recruitable 0 and no fill rate")
	pc.erase("occupied")
	pc.enslaved = true
	panel.refresh(pc)
	ok(panel.label.text.contains("Recruitable 0 (held at 0)") and not panel.label.text.contains("/turn, cap"), "an enslaved city shows Recruitable 0 and no fill rate")
	panel.free()


# --- Task 40: atrocity is judged per observing faction ---

func test_atrocity_views() -> void:
	var factions := FactionRoster.load_all()
	var views := {"assembly": ["raze", "enslave", "plunder"], "verdant_accord": ["raze", "enslave", "plunder"],
			"covenant": ["raze", "enslave"], "lyceum": ["raze", "enslave"], "drift": ["raze", "enslave"],
			"directorate": ["raze"], "syndicate": ["raze"], "collective": ["raze"],
			"free_tide": ["raze"], "deepwater_guild": ["raze"]}
	for f in factions:
		ok(f.views_as_atrocity == views[f.id], "factions.json: %s views %s as atrocities" % [f.id, views[f.id]])
	var m := pop_map()
	m.load_faction_views(factions)
	var raze := {"type": "raze", "severity": 3, "atrocity": true}
	var enslave := {"type": "enslave", "severity": 3, "atrocity": false}
	var plunder := {"type": "plunder", "severity": 1, "atrocity": false}
	var annex := {"type": "annex", "severity": 0, "atrocity": false}
	ok(factions.all(func(f: Dictionary) -> bool: return m.is_atrocity_to(f.id, raze)), "Raze is an atrocity to every faction")
	ok(m.is_atrocity_to("assembly", plunder) and m.is_atrocity_to("verdant_accord", plunder), "Assembly (and Verdant Accord) see Plunder as an atrocity")
	ok(not m.is_atrocity_to("directorate", enslave) and not m.is_atrocity_to("collective", enslave), "Directorate (and Collective) do not see Enslave as an atrocity")
	ok(m.is_atrocity_to("assembly", enslave) and m.is_atrocity_to("drift", enslave), "a faction whose list includes Enslave sees it as one")
	ok(not m.is_atrocity_to("assembly", annex) and not m.is_atrocity_to("syndicate", plunder), "Annex is never one, and Syndicate does not see Plunder as one")
	ok(m.is_atrocity_to("nobody", raze) and not m.is_atrocity_to("nobody", enslave), "an unknown faction uses the default list (Raze only)")
	# The event keeps its own flag and severity: Enslave stays severity 3, atrocity false.
	var s := cap_setup()
	var r := capture_with(s, s.city, 0, "enslave")
	var ev: Dictionary = s.map.reputation.events.back()
	ok(ev.type == "enslave" and ev.severity == 3 and ev.atrocity == false and r.severity == 3, "the Enslave event keeps severity 3 and atrocity false")
	# Observer-relative weight: atrocity_weight x sensitivity for an atrocity, else base severity.
	var w: float = float(m.city_rules.capture.atrocity_weight)
	ok(is_equal_approx(m.reputation_weight_to("assembly", plunder), w) and is_equal_approx(m.reputation_weight_to("syndicate", plunder), 1.0), "weight: Plunder is an atrocity weight to Assembly and its base severity (1) to Syndicate")
	ok(is_equal_approx(m.reputation_weight_to("directorate", enslave), 3.0) and is_equal_approx(m.reputation_weight_to("directorate", annex), 0.0), "weight: a normal event counts its base severity")
	m.faction_sensitivity["drift"] = 0.5
	ok(is_equal_approx(m.reputation_weight_to("drift", raze), w * 0.5) and is_equal_approx(m.reputation_weight_to("assembly", raze), w), "weight: scaled by the faction's atrocity sensitivity (default 1.0)")
	var custom := [{"id": "x", "views_as_atrocity": ["raze"], "atrocity_sensitivity": 2.0}, {"id": "y"}]
	m.load_faction_views(custom)
	ok(is_equal_approx(m.reputation_weight_to("x", raze), w * 2.0) and is_equal_approx(m.reputation_weight_to("y", raze), w), "atrocity_sensitivity is read from the faction entry when present")


# --- Task 40b: main menu and game setup ---

func test_main_menu() -> void:
	ok(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/menu.tscn", "the main menu is the project's main scene")
	var limits := GameSession.setup_limits()
	ok(limits.min_ai == 1 and limits.max_ai == 3 and limits.default_ai == 3, "config: setup screen allows 1 to 3 AI nations (default 3)")
	var menu := MainMenu.new()
	ok(menu.menu_box.visible and not menu.setup_box.visible, "the menu opens on New Game, Load Game and Quit")
	ok(menu.new_button.text == "New Game" and menu.load_button.text == "Load Game" and menu.quit_button.text == "Quit", "the menu has New Game, Load Game and Quit")
	menu.new_button.pressed.emit()
	ok(menu.setup_box.visible and not menu.menu_box.visible, "New Game opens the setup screen")
	var playable := FactionRoster.load_all().filter(func(f: Dictionary) -> bool: return f.get("playable", true))
	ok(menu.faction_picker.item_count == playable.size() and menu.faction_picker.get_item_text(0) == playable[0].name, "the faction picker lists the playable factions")
	ok(menu.ai_spin.min_value == 1 and menu.ai_spin.max_value == 3 and menu.ai_spin.value == 3, "the AI nation spinner uses the config range")
	var before := menu.seed_field.text
	ok(before == "12345", "the seed field starts at the config seed")
	menu.random_button.pressed.emit()
	ok(menu.seed_field.text.is_valid_int() and menu.seed_field.text != "", "the Random button puts a seed in the field")
	menu.seed_field.text = "777"
	menu.faction_picker.select(2)
	menu.ai_spin.value = 2
	var got := []
	menu.new_game.connect(func(st: Dictionary) -> void: got.append(st))
	menu.start_button.pressed.emit()
	ok(got.size() == 1 and got[0] == {"player_faction": playable[2].id, "seed": 777, "ai_count": 2}, "Start emits the chosen faction, seed and AI count")
	menu.seed_field.text = "abc"
	ok(menu.build_settings().seed > 0 and menu.seed_field.text.is_valid_int(), "a bad seed gets replaced by a random one")
	var loads := [0]
	menu.load_game.connect(func() -> void: loads[0] += 1)
	menu.load_button.pressed.emit()
	ok(loads[0] == 1, "Load Game emits load_game")
	menu.back_button.pressed.emit()
	ok(menu.menu_box.visible and not menu.setup_box.visible, "Back returns to the menu")
	menu.free()
	# The settings drive the game: seed, nation count and player faction.
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_config.json"))
	ok(GameSession.apply(base, {}) == base, "no settings leaves the config unchanged")
	for ai in [1, 2, 3]:
		for sd in [3, 11, 25]:
			var cfg := GameSession.apply(base, {"player_faction": "covenant", "seed": sd, "ai_count": ai})
			var roster := FactionRoster.from_config(cfg)
			var m := HexMap.from_config_file("res://data/map_config.json", "res://data/cities_config.json",
					"res://data/terrain_config.json", roster.sea_nations(), cfg)
			ok(m.seed_value == sd and m.nations.size() == ai + 1 and roster.assigned.size() == ai + 1 and roster.assigned[0].id == "covenant", "seed %d with %d AI: %d nations, the player is the Covenant" % [sd, ai, ai + 1])


# --- Task 40c: save and load ---

## A fresh all-AI game from map_config.json with the given seed: {"map", "eco", "roster", "cfg"}.
func save_game_setup(seed_value: int) -> Dictionary:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_config.json"))
	cfg["seed"] = seed_value
	var m := HexMap.from_config_file("res://data/map_config.json", "res://data/cities_config.json",
			"res://data/terrain_config.json", [], cfg)
	var eco := NationEconomy.new()
	eco.setup(m)
	var roster := make_roster()
	roster.spawn_at_cities(m)
	roster.economy = eco
	var fog := Fog.from_config(cfg)
	roster.fog = fog
	fog.explore_landing(m)
	fog.update(m, roster)
	return {"map": m, "eco": eco, "roster": roster, "cfg": cfg, "fog": fog}


## One end turn with every nation run by the AI (the order main.gd uses).
func save_play_turn(g: Dictionary) -> void:
	var m: HexMap = g.map
	var roster: DivisionRoster = g.roster
	g.eco.run_ai(-1, m, roster)
	roster.execute_orders(m)
	roster.resolve_ai_captures(m, -1)
	roster.end_turn(m)
	m.grow_cities(roster.unit_cells())
	g.eco.end_turn(m, roster)
	roster.run_ai(-1, m)
	g.fog.update(m, roster)


func save_state(g: Dictionary, turn: int) -> Dictionary:
	var ids: Array = []
	for i in g.map.nations.size():
		ids.append("f%d" % i)
	g.fog.update(g.map, g.roster)
	return SaveGame.capture(g.map, g.roster, g.eco, turn, g.cfg, ids, {"fog": g.fog.capture()})


func test_save_load() -> void:
	var g := save_game_setup(5)
	g.eco.config.ai_recruit_chance = 1.0
	for t in 4:
		save_play_turn(g)
	# Put the interesting state in: a capture with a reputation event and an occupied city,
	# a plunder (cash), a queued recruit and a division with an order.
	var m: HexMap = g.map
	var roster: DivisionRoster = g.roster
	var victims := nation_cities(m, 1)
	var raider_cities := nation_cities(m, 0)
	if not victims.is_empty():
		var guard := roster.division_at(victims[0].cell)
		if guard:
			roster.divisions.erase(guard)
		roster.pending_captures.append(m.take_city(victims[0].cell, 0))
		roster.apply_capture(int(victims[0].id), "occupy", m)
	var marked: Division = roster.divisions[0]
	marked.order_path.append(m.neighbors(marked.hex)[0])
	marked.attacked_from.append(m.neighbors(marked.hex)[1])
	for t in 6:
		save_play_turn(g)
	var turn_n := 11
	var state := save_state(g, turn_n)
	var h1 := SaveGame.state_hash(state)
	ok(state.map.reputation.size() >= 1 and state.economy.stocks.size() == m.nations.size() and state.roster.divisions.size() > 0, "the state holds reputation events, stocks and divisions")
	ok(state.roster.divisions.any(func(d: Dictionary) -> bool: return not d.order_path.is_empty()), "division orders are part of the state")
	ok(m.cities.any(func(c: Dictionary) -> bool: return c.get("occupied", false) or c.has("recruit_lockout")), "capture states (occupied or lockout) are in the saved cities")
	# File round trip.
	var path := "user://test_save_40c.sav"
	ok(SaveGame.write(path, state), "the state is written to user://")
	var read := SaveGame.read(path)
	ok(SaveGame.state_hash(read) == h1, "the state read back from disk has the same hash")
	# Load into fresh objects.
	var g2 := save_game_setup(5)
	var turn2 := SaveGame.restore(read, g2.map, g2.roster, g2.eco)
	g2.fog.restore(read.extras.fog)
	var h2 := SaveGame.state_hash(save_state(g2, turn2))
	ok(turn2 == turn_n and h2 == h1, "saving on turn %d, loading and saving again gives the same state hash" % turn_n)
	# The loaded game plays on exactly like the original (including the AI's random stream).
	g2.eco.config.ai_recruit_chance = 1.0
	for t in 6:
		save_play_turn(g)
		save_play_turn(g2)
	ok(SaveGame.state_hash(save_state(g, turn_n + 6)) == SaveGame.state_hash(save_state(g2, turn_n + 6)), "6 more turns after loading end in the same state as the original game")
	# A different state hashes differently, and unreadable saves load as empty.
	ok(SaveGame.state_hash(save_state(g, turn_n + 6)) != h1, "the hash changes when the game moves on")
	var bad := read.duplicate()
	bad["version"] = 999
	SaveGame.write(path, bad)
	ok(SaveGame.read(path).is_empty() and SaveGame.read("user://no_such_save.sav").is_empty(), "a save of another version or a missing file reads as empty")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Menus.
	var menu := MainMenu.new()
	ok(menu.load_button.disabled == not SaveGame.has_save(), "Load Game is enabled only when a save exists")
	menu.free()
	var pause := PauseMenu.new()
	var presses := []
	pause.save_pressed.connect(func() -> void: presses.append("save"))
	pause.main_menu_pressed.connect(func() -> void: presses.append("menu"))
	pause.open()
	pause.save_button.pressed.emit()
	pause.menu_button.pressed.emit()
	ok(pause.is_open() and presses == ["save", "menu"] and pause.save_button.text == "Save Game", "the Esc menu offers Save Game and Main Menu")
	pause.close()
	ok(not pause.is_open(), "Resume closes the Esc menu")
	pause.free()


# --- Task 40d: domination victory and defeat ---

func test_victory() -> void:
	var share := Victory.domination_share()
	ok(is_equal_approx(share, 0.85), "victory.domination_share is 0.85 in map_config.json")
	var g := save_game_setup(5)
	var m: HexMap = g.map
	var player := 0
	var total := m.cities.size()
	ok(Victory.check(m, player, share).over == false, "a fresh game is not over")
	# Give the player cities until just under 85%, then to 85%.
	var need := ceili(share * total - 0.000001)
	var others: Array[Dictionary] = []
	for c in m.cities:
		if c.nation != player:
			others.append(c)
	for i in need - 1 - nation_cities(m, player).size():
		others[i].nation = player
	var held := nation_cities(m, player).size()
	var r := Victory.check(m, player, share)
	ok(held == need - 1 and not r.over, "%d of %d cities (below the share) is not a win" % [held, total])
	# One more city reaches the share.
	for c in m.cities:
		if c.nation != player:
			c.nation = player
			break
	r = Victory.check(m, player, share)
	ok(r.over and r.result == "victory" and r.reason == "domination" and r.winner == player, "%d of %d cities (the share) is a domination win" % [nation_cities(m, player).size(), total])
	# An AI nation reaching the share is a defeat for the player.
	var ai_game := save_game_setup(5)
	var am: HexMap = ai_game.map
	var keep: Dictionary = nation_cities(am, 0)[0]
	for c in am.cities:
		if c.id != keep.id:
			c.nation = 1
	var ar := Victory.check(am, 0, share)
	ok(ar.over and ar.result == "defeat" and ar.reason == "domination" and ar.winner == 1, "an AI nation with the share defeats the player")
	# Natives and alien sites are not counted, as owners or in the total.
	var nm := pop_map()
	nm.cities.clear()
	for i in 7:
		nm.cities.append({"id": i, "nation": 0, "cell": Vector2i(i, 0)})
	nm.cities.append({"id": 7, "nation": 1, "cell": Vector2i(7, 0)})
	var native_city := {"id": 8, "nation": 2, "cell": Vector2i(8, 0)}
	var alien_city := {"id": 9, "nation": 3, "cell": Vector2i(9, 0), "alien_site": true}
	var native_flag := {"id": 10, "nation": 1, "cell": Vector2i(10, 0), "native": true}
	for i in 5:
		nm.cities.append(native_city.merged({"id": 20 + i}))
	nm.cities.append(alien_city)
	nm.cities.append(native_flag)
	ok(Victory.dominating_nation(nm, share, [2]) == 0, "7 of 8 counted cities wins when neutral natives and alien sites are left out")
	ok(Victory.dominating_nation(nm, share, []) == -1, "the same map without excluding natives is not a win (7 of 14)")
	# Elimination.
	var em := save_game_setup(5)
	var em_map: HexMap = em.map
	for c in nation_cities(em_map, 0).duplicate():
		em_map.remove_city(c.id)
	var er := Victory.check(em_map, 0, share)
	ok(er.over and er.result == "defeat" and er.reason == "elimination", "the player with no cities is eliminated: defeat")
	# The end screen.
	var screen := GameOverScreen.new()
	var pressed := []
	screen.new_game_pressed.connect(func() -> void: pressed.append("new"))
	screen.main_menu_pressed.connect(func() -> void: pressed.append("menu"))
	screen.open(r, "")
	ok(screen.is_open() and screen.title.text == "Victory", "the victory screen opens")
	screen.new_button.pressed.emit()
	screen.menu_button.pressed.emit()
	ok(pressed == ["new", "menu"], "the end screen offers New Game and Main Menu")
	screen.open(er, "")
	ok(screen.title.text == "Defeat" and screen.message.text.contains("eliminated"), "the defeat screen says the nation was eliminated")
	screen.free()


# --- Task 40e: colony pods ---

func test_colonizers() -> void:
	var s := pool_setup()
	var m: HexMap = s.map
	var eco: NationEconomy = s.eco
	var roster: DivisionRoster = s.roster
	roster.divisions.clear()
	var rules: Dictionary = m.city_rules.colonization
	ok(rules.labor_turns == 15 and rules.population_cost == 3000 and rules.min_remaining_population == 5000 and rules.outpost_population == 3000 and rules.min_city_distance == 3, "colonization config: 15 labor-turns, 3,000 people, 5,000 left, 3k Outpost, 3 hexes")
	var pod_template: Dictionary = roster.templates.colony_pod
	ok(pod_template.move == 2 and pod_template.attack == 0 and pod_template.colonizer and pod_template.upkeep.is_empty(), "the pod template: move 2, attack 0, colonizer, no upkeep")
	# Queue: people leave the population at queue time, nothing else is paid.
	var city: Dictionary = nation_cities(m, 0)[0]
	var cash_before := float(eco.stocks[0].cash)
	var cap_before := float(eco.stocks[0].capacity)
	ok(eco.colony_block_reason(city, 0) == "", "a 10,000-person city can queue a colony pod")
	ok(eco.queue_colony_pod(city, 0), "the pod is queued")
	var entry: Dictionary = eco.pending[city.id]
	ok(city.population == 7000 and entry.kind == "colony_pod" and entry.cost == 15 and entry.turns_left == 0, "3,000 people drawn at queue time; a 15 labor-turn pod entry")
	ok(float(eco.stocks[0].cash) == cash_before and float(eco.stocks[0].capacity) == cap_before, "a pod costs no cash or capacity")
	ok(city.pool <= int(floor(7000 * 0.15)), "the recruit pool is held under the smaller city's cap")
	ok(eco.colony_block_reason(city, 0) == "already recruiting" and not eco.recruit(city, 0, roster), "one queue per city: a pod blocks a second pod and a division")
	ok(NationEconomy.queue_text(entry).begins_with("Colony pod 0/15 labor"), "the queue text names the pod")
	# Labor gating: 5 Training points per turn needs 3 turns.
	city.labor.training = 5
	eco.spawn_pending(m, roster)
	eco.spawn_pending(m, roster)
	ok(roster.divisions.is_empty() and eco.pending[city.id].labor == 10, "after 2 turns of 5 labor the pod is not ready (10/15)")
	eco.spawn_pending(m, roster)
	ok(roster.divisions.size() == 1 and not eco.pending.has(city.id), "after 3 turns (15 labor-turns) the pod appears on the city hex")
	var pod: Division = roster.divisions[0]
	ok(pod.unit_type == "colony_pod" and pod.hex == city.cell and pod.move == 2 and roster.is_colonizer(pod) and roster.upkeep_of(pod).is_empty(), "the pod stands on the city hex, moves 2, no upkeep")
	# The 5,000 floor: 7,999 is blocked, 8,000 is allowed.
	var c2: Dictionary = nation_cities(m, 0)[1] if nation_cities(m, 0).size() > 1 else city
	c2.population = 7999
	ok(eco.colony_block_reason(c2, 0).begins_with("city needs 5000"), "7,999 people: the city would keep under 5,000, blocked")
	c2.population = 8000
	ok(eco.colony_block_reason(c2, 0) == "" if c2 != city else true, "8,000 people: it keeps exactly 5,000, allowed")
	ok(eco.colony_block_reason(nation_cities(m, 1)[0], 0) == "not your city", "not another nation's city")
	var enslaved: Dictionary = nation_cities(m, 1)[0]
	enslaved["enslaved"] = true
	ok(eco.colony_block_reason(enslaved, 1).contains("enslaved"), "no pods in an enslaved city")
	enslaved.erase("enslaved")
	# Unarmed: cannot attack, dig in, or capture.
	var foe_city: Dictionary = nation_cities(m, 1)[0]
	var foe := roster.spawn_division(1, m.neighbors(pod.hex)[0], "infantry", int(foe_city.id))
	ok(not roster.can_attack(pod, foe, m) and not roster.valid_actions(pod, m).has("attack") and not roster.valid_actions(pod, m).has("dig_in"), "a pod cannot attack or dig in")
	ok(not roster.fortify(pod), "a pod cannot fortify")
	ok(roster.can_attack(foe, pod, m), "the pod can be attacked")
	roster.divisions.erase(foe)
	var near_foe: Vector2i = foe_city.cell
	var step: Vector2i = m.neighbors(near_foe)[0]
	pod.hex = step
	pod.moves_left = 2
	ok(not roster.can_move(pod, near_foe, m), "a pod cannot step onto an enemy city (no capture)")
	pod.hex = city.cell
	# Founding: valid sites keep 3 hexes from every city, on land the nation can settle.
	var sites := m.colony_sites(0)
	ok(not sites.is_empty(), "the test map has valid colony sites")
	var spaced := true
	for cell in sites:
		for c in m.cities:
			if HexMap.hex_distance(c.cell, cell) < 3:
				spaced = false
	ok(spaced, "every valid site is at least 3 hexes from every city")
	var too_close: Vector2i = Vector2i(-1, -1)
	for cell in m.cells:
		if HexMap.hex_distance(city.cell, cell) == 2 and int(m.territory.get(cell, -2)) != HexMap.WATER and m.terrain_of(cell).passable:
			too_close = cell
			break
	ok(m.found_block_reason(too_close, 0) == "too close to a city", "2 hexes from a city is too close")
	var water: Vector2i = Vector2i(-1, -1)
	var foreign: Vector2i = Vector2i(-1, -1)
	for cell in m.cells:
		if int(m.territory[cell]) == HexMap.WATER and water.x < 0:
			water = cell
		if int(m.cells[cell]) == 1 and foreign.x < 0:
			foreign = cell
	if water.x >= 0:
		ok(m.found_block_reason(water, 0) == "not land", "water is not a site")
	if foreign.x >= 0:
		ok(m.found_block_reason(foreign, 0) == "foreign territory", "another nation's territory is not a site")
	pod.hex = sites[0]
	ok(roster.valid_actions(pod, m).has("found"), "a pod on a valid site is offered Found city")
	var cities_before := m.cities.size()
	var founded := roster.found_city(pod, m)
	ok(not founded.is_empty() and m.cities.size() == cities_before + 1 and founded.nation == 0 and founded.population == 3000 and founded.cell == sites[0], "founding makes a 3,000-person Outpost on the pod's hex")
	ok(not roster.divisions.has(pod) and m.city_at(sites[0]).id == founded.id and m.cells[sites[0]] == 0, "the pod is used up and the new city claims its hex")
	ok(founded.id == m.cities.map(func(c: Dictionary) -> int: return c.id).max() and eco.labor_points(founded) == 1, "the new city has a fresh id and its own labor")
	var pod2 := roster.spawn_division(0, city.cell, "colony_pod", int(city.id))
	ok(roster.found_city(pod2, m).is_empty() and roster.divisions.has(pod2), "founding on an invalid hex (next to a city) does nothing")
	# Pods are not divisions for the AI's division cap or upkeep, and do not reinforce.
	var before_count := eco.division_count(0, roster)
	pod2.strength = 50.0
	eco.pending[nation_cities(m, 0)[0].id] = {"nation": 0, "kind": "colony_pod", "turns_left": 0, "labor": 0, "cost": 15}
	ok(eco.division_count(0, roster) == before_count and eco.pod_count(0, roster) == 2, "pods do not count as divisions (1 fielded, 1 queued pod counted separately)")
	var plan := eco.reinforce_plan(roster, m, eco.current_pools(m))
	ok(not plan.gains.has(pod2.id), "a damaged pod is not reinforced from the pools")
	# The AI.
	var g := pool_setup()
	var gm: HexMap = g.map
	var geco: NationEconomy = g.eco
	var groster: DivisionRoster = g.roster
	groster.divisions.clear()
	geco.config.ai_recruit_chance = 0.0
	geco.run_ai(0, gm, groster)
	var queued := {}
	for id in geco.pending:
		if geco.pending[id].kind == "colony_pod":
			queued[geco.pending[id].nation] = int(queued.get(geco.pending[id].nation, 0)) + 1
	ok(not queued.is_empty() and queued.values().all(func(n: int) -> bool: return n == 1) and not queued.has(0), "each AI nation with a valid site queues one pod; the player's nations do not")
	var no_site := pool_setup()
	no_site.map.city_rules.colonization.min_city_distance = 99
	no_site.roster.divisions.clear()
	no_site.eco.config.ai_recruit_chance = 0.0
	no_site.eco.run_ai(0, no_site.map, no_site.roster)
	ok(no_site.eco.pending.is_empty(), "the AI queues no pod when there is no valid site")
	var small := pool_setup()
	small.roster.divisions.clear()
	small.eco.config.ai_recruit_chance = 0.0
	for c in small.map.cities:
		c.population = 7000
	small.eco.run_ai(0, small.map, small.roster)
	ok(small.eco.pending.is_empty(), "the AI queues no pod when its cities cannot spare the people")
	var off := pool_setup()
	off.map.city_rules.colonization.ai_build_pods = false
	off.roster.divisions.clear()
	off.eco.config.ai_recruit_chance = 0.0
	off.eco.run_ai(0, off.map, off.roster)
	ok(off.eco.pending.is_empty(), "ai_build_pods = false turns the AI's pods off")
	# A full AI game: pods are built, walk to a site and found new cities.
	var game := save_game_setup(5)
	var start_cities: int = game.map.cities.size()
	game.eco.config.ai_recruit_chance = 1.0
	for t in 40:
		save_play_turn(game)
	var gm_cities: int = game.map.cities.size()
	ok(gm_cities > start_cities, "40 turns of AI play: the AI founded new cities (%d -> %d)" % [start_cities, gm_cities])
	var founded_ok := true
	for c in game.map.cities:
		for o in game.map.cities:
			if c.id != o.id and HexMap.hex_distance(c.cell, o.cell) < 3:
				founded_ok = false
	ok(founded_ok, "no two cities are closer than 3 hexes after AI colonization")
	ok(MapView.symbol_for("colony_pod") == "plus", "a pod draws a plus counter")


# --- Task 40f: fog of war ---

func fog_world() -> Dictionary:
	var m := make_map(12, 7)
	m.nations.assign([0, 1])
	var roster := make_roster()
	var fog := Fog.load_config()
	roster.fog = fog
	return {"map": m, "roster": roster, "fog": fog}


func fog_visible_count(fog: Fog, m: HexMap, nation: int) -> int:
	var n := 0
	for cell in m.cells:
		if fog.state(nation, cell) == Fog.VISIBLE:
			n += 1
	return n


func test_fog() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_config.json"))
	var rules: Dictionary = cfg.fog
	ok(rules.landfall_radius == 2 and rules.sight.infantry == 2 and rules.sight.scout == 3 and rules.sight.city == 2 and rules.city_sight_bonus == 1 and rules.elevated_sight_bonus == 1 and rules.blocking_terrain == ["mountains"], "fog config: landfall 2, infantry 2, scout 3, city 2 (+1 at City tier), +1 elevated, mountains block")
	ok(cfg.ai.respects_fog == false, "ai.respects_fog is false (the AI is omniscient)")
	# Hex lines.
	var lines_ok := true
	for pair in [[Vector2i(0, 0), Vector2i(5, 3)], [Vector2i(4, 1), Vector2i(1, 5)], [Vector2i(2, 2), Vector2i(2, 2)], [Vector2i(0, 3), Vector2i(6, 3)], [Vector2i(3, 0), Vector2i(3, 6)]]:
		var line := HexMap.hex_line(pair[0], pair[1])
		lines_ok = lines_ok and line.size() == HexMap.hex_distance(pair[0], pair[1]) + 1 and line[0] == pair[0] and line[-1] == pair[1]
		for i in range(1, line.size()):
			lines_ok = lines_ok and HexMap.hex_distance(line[i - 1], line[i]) == 1
	ok(lines_ok, "hex_line runs from a to b in unit steps")
	# Sight ranges.
	var w := fog_world()
	var m: HexMap = w.map
	var roster: DivisionRoster = w.roster
	var fog: Fog = w.fog
	var inf := roster.spawn_division(0, Vector2i(5, 3), "infantry")
	fog.update(m, roster)
	var within2 := 0
	var all_in := true
	for cell in m.cells:
		var seen := fog.state(0, cell) == Fog.VISIBLE
		if HexMap.hex_distance(inf.hex, cell) <= 2:
			within2 += 1
			all_in = all_in and seen
		else:
			all_in = all_in and not seen
	ok(all_in and within2 == 19, "infantry sees exactly the 19 hexes within 2")
	ok(fog_visible_count(fog, m, 1) == 0 and fog.state(1, inf.hex) == Fog.UNEXPLORED, "another nation with no units or cities sees nothing")
	inf.unit_type = "scout"
	fog.update(m, roster)
	ok(fog_visible_count(fog, m, 0) == 37, "a scout sees 3 hexes (37 hexes)")
	inf.unit_type = "infantry"
	m.terrain[inf.hex] = "hills"
	fog.update(m, roster)
	ok(fog.sight_of_unit(inf, m) == 3 and fog_visible_count(fog, m, 0) == 37, "a unit on hills sees +1")
	m.terrain[inf.hex] = "mountains"
	ok(fog.sight_of_unit(inf, m) == 3, "a unit on mountains sees +1")
	m.terrain[inf.hex] = "plains"
	# Cities: sight 2, +1 at City tier (15,000).
	m.cities.append({"id": 0, "nation": 0, "cell": Vector2i(9, 1), "population": 14999, "radius": 1})
	ok(fog.sight_of_city(m.cities[0]) == 2 and fog.tier_of(14999) == "base", "a 14,999 city sees 2 (Base)")
	m.cities[0].population = 15000
	ok(fog.sight_of_city(m.cities[0]) == 3 and fog.tier_of(15000) == "city" and fog.tier_of(4999) == "outpost" and fog.tier_of(30000) == "metropolis", "a 15,000 city (City tier) sees 3")
	# Mountains block sight to the tiles behind them, but can be seen themselves.
	var w2 := fog_world()
	var m2: HexMap = w2.map
	var roster2: DivisionRoster = w2.roster
	var fog2: Fog = w2.fog
	var u := roster2.spawn_division(0, Vector2i(1, 3), "infantry")
	m2.terrain[Vector2i(2, 3)] = "mountains"
	fog2.update(m2, roster2)
	ok(fog2.state(0, Vector2i(2, 3)) == Fog.VISIBLE, "the mountain itself is visible")
	ok(fog2.state(0, Vector2i(3, 3)) != Fog.VISIBLE, "the tile directly behind a mountain is not")
	ok(fog2.state(0, Vector2i(2, 2)) == Fog.VISIBLE or fog2.state(0, Vector2i(1, 2)) == Fog.VISIBLE, "tiles beside the mountain are still seen")
	var mid_ok := fog2.sees(m2, Vector2i(1, 3), Vector2i(2, 3), 2) and not fog2.sees(m2, Vector2i(1, 3), Vector2i(3, 3), 2)
	ok(mid_ok, "sees(): the mountain is seen, the tile behind it is not")
	# A unit standing on a mountain is not blocked by its own tile.
	m2.terrain[Vector2i(1, 3)] = "mountains"
	m2.terrain[Vector2i(2, 3)] = "plains"
	fog2.update(m2, roster2)
	ok(fog2.state(0, Vector2i(3, 3)) == Fog.VISIBLE and fog2.state(0, Vector2i(4, 3)) == Fog.VISIBLE, "a unit on a mountain sees past its own tile (3 hexes)")
	# Explored memory: owner and tier as last seen, no live updates.
	var w3 := fog_world()
	var m3: HexMap = w3.map
	var roster3: DivisionRoster = w3.roster
	var fog3: Fog = w3.fog
	m3.cities.append({"id": 5, "nation": 1, "cell": Vector2i(6, 3), "population": 4000, "radius": 1})
	m3.cells[Vector2i(6, 3)] = 1
	m3.cells[Vector2i(5, 3)] = 1
	var scout := roster3.spawn_division(0, Vector2i(4, 3), "infantry")
	fog3.update(m3, roster3)
	ok(fog3.state(0, Vector2i(6, 3)) == Fog.VISIBLE and fog3.last_seen(0, Vector2i(6, 3)).city.tier == "outpost" and fog3.last_seen(0, Vector2i(6, 3)).owner == 1, "a seen city is remembered with its owner and tier")
	scout.hex = Vector2i(0, 3)
	fog3.update(m3, roster3)
	ok(fog3.state(0, Vector2i(6, 3)) == Fog.EXPLORED and fog3.state(0, Vector2i(11, 6)) == Fog.UNEXPLORED, "leaving it behind makes it Explored; never-seen tiles stay Unexplored")
	m3.cities[0].nation = 2  # taken by a nation this one does not see
	m3.cities[0].population = 16000
	m3.cells[Vector2i(6, 3)] = 2
	fog3.update(m3, roster3)
	var memory := fog3.last_seen(0, Vector2i(6, 3))
	ok(memory.owner == 1 and memory.city.nation == 1 and memory.city.tier == "outpost", "changes out of sight are not shown: still the old owner and tier")
	scout.hex = Vector2i(4, 3)
	fog3.update(m3, roster3)
	memory = fog3.last_seen(0, Vector2i(6, 3))
	ok(memory.owner == 2 and memory.city.nation == 2 and memory.city.tier == "city", "seeing it again refreshes the memory")
	# MapView draws owners as remembered; unexplored is unowned.
	var view := MapView.new()
	view.hex_map = m3
	view.fog = fog3
	view.player_nation = 0
	scout.hex = Vector2i(0, 3)
	fog3.update(m3, roster3)
	m3.cells[Vector2i(6, 3)] = 1
	ok(view.owner_of(Vector2i(6, 3)) == 2 and view.owner_of(Vector2i(11, 6)) == HexMap.UNCLAIMED and view.fog_state(Vector2i(6, 3)) == Fog.EXPLORED, "the map shows the remembered owner on explored tiles")
	view.free()
	# Landfall: only radius 2 around the landing site is explored.
	var w4 := fog_world()
	var m4: HexMap = w4.map
	var fog4: Fog = w4.fog
	m4.cities.append({"id": 0, "nation": 0, "cell": Vector2i(5, 3), "population": 10000, "radius": 1})
	fog4.explore_landing(m4)
	var landing_ok := true
	for cell in m4.cells:
		var near := HexMap.hex_distance(Vector2i(5, 3), cell) <= 2
		landing_ok = landing_ok and (fog4.state(0, cell) == Fog.EXPLORED) == near and fog4.state(1, cell) == Fog.UNEXPLORED
	ok(landing_ok, "at landfall exactly the 19 hexes within 2 of the landing site are explored")
	# Targeting: what the player cannot see cannot be targeted. The AI is not filtered.
	var w5 := fog_world()
	var m5: HexMap = w5.map
	var roster5: DivisionRoster = w5.roster
	var fog5: Fog = w5.fog
	var mine := roster5.spawn_division(0, Vector2i(3, 3), "infantry")
	var enemy := roster5.spawn_division(1, Vector2i(4, 3), "infantry")
	mine.supplied = true
	fog5.update(m5, roster5)
	ok(roster5.action_targets(mine, "attack", m5).has(Vector2i(4, 3)) and not roster5.hides_from(0, Vector2i(4, 3)), "a visible adjacent enemy can be targeted")
	fog5.visible[0] = {}
	ok(not roster5.action_targets(mine, "attack", m5).has(Vector2i(4, 3)) and roster5.hides_from(0, Vector2i(4, 3)), "an enemy on a tile the player cannot see is not a target")
	ok(not roster5.set_order(mine, Vector2i(4, 3), m5) and mine.order_path.is_empty(), "the player cannot order an attack on an unseen unit")
	ok(not roster5.hides_from(1, Vector2i(3, 3)) and roster5.set_order(enemy, Vector2i(3, 3), m5), "the AI nation is not filtered: it can order the same attack")
	fog5.respects_fog = true
	fog5.visible[1] = {}
	ok(roster5.hides_from(1, Vector2i(3, 3)), "with ai.respects_fog on, the AI would be filtered too")
	fog5.respects_fog = false
	# Fog off: everything is visible.
	var off := Fog.new()
	off.rules = {"enabled": false}
	ok(off.state(0, Vector2i(0, 0)) == Fog.VISIBLE and not off.filters(0), "with fog disabled every tile is visible")
	# Speed: a full update on the 20x12 test map with 4 nations.
	var g := save_game_setup(5)
	var t0 := Time.get_ticks_usec()
	for i in 10:
		g.fog.update(g.map, g.roster)
	var per := (Time.get_ticks_usec() - t0) / 10000.0
	ok(per < 50.0, "a fog update on the test map takes %.1f ms (under 50)" % per)
