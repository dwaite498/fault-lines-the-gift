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
	var mountains := 0
	var foothills := 0
	var ridges := 0
	var all3 := true
	for seed_value in range(1, 21):
		var m := build(seed_value)
		ridges += m.ridge_edges.size()
		for cell in m.terrain:
			if m.terrain[cell] != "mountains":
				continue
			mountains += 1
			for n in m.neighbors(cell):
				if not m.terrain_of(n).passable or m.terrain[n] == "mountains":
					continue
				edges += 1
				if m.can_step(cell, n) and m.can_step(n, cell):
					open_edges += 1
				if absi(m.elevation[cell] - m.elevation[n]) > 1 and not m.is_ridge_edge(cell, n):
					untagged += 1
				if m.terrain[n] == "hills" and m.elevation[n] == 2:
					foothills += 1
	ok(mountains > 0 and edges > 0, "20 seeds have mountains (%d) with lowland edges (%d)" % [mountains, edges])
	ok(untagged == 0, "no mountain borders a level-1 tile across a cliff unless the edge is a tagged ridge (%d untagged)" % untagged)
	ok(float(open_edges) / float(maxi(edges, 1)) > 0.5, "most mountain edges are walkable (%d of %d), %d ridge edges tagged" % [open_edges, edges, ridges])
	ok(foothills > 0, "mountains get hills foothills (%d)" % foothills)
	var m1 := build(7)
	var m2 := build(7)
	ok(m1.ridge_edges == m2.ridge_edges and m1.terrain == m2.terrain, "ridge tags and foothills are deterministic")


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
	# Growth = 1% base + 0.5% per labor point assigned to Growth, capped at housing.
	ok(is_equal_approx(m.growth_rate(capital), 0.01), "base growth is 1% a turn")
	var with_labor := capital.duplicate()
	with_labor.labor = {"growth": 3}
	ok(is_equal_approx(m.growth_rate(with_labor), 0.025), "3 labor points on Growth give 2.5% (1% + 3 x 0.5%)")
	ok(m.growth_amount(capital) == 100 and m.grown_population(capital) == 10100, "1% of 10,000 is +100 people")
	ok(m.growth_amount(with_labor) == 250, "2.5% of 10,000 is +250 people")
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
	ok(gm.cities[0].population == 10100, "grow_cities adds 1% a turn")
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
	# Manpower per person: the old 0.08 per 1,000 people.
	ok(is_equal_approx(eco.city_income(capital).manpower, 0.8), "manpower income stays 0.8 for 10,000 people (rescaled to per person)")
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
	# Growth labor feeds the Task 35 growth formula: 2 points = 1% + 2 x 0.5% = 2%.
	ok(is_equal_approx(m.growth_rate(cap), 0.02) and m.growth_amount(cap) == 200, "Growth labor feeds growth: default capital grows 2% (+200)")
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
