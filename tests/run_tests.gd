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
