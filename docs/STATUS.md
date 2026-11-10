# Fault Lines: Planetfall — Status

Last updated: Nov 9 2026 (Task 40)

## Current direction
An Alpha Centauri (SMAC) homage with landfall and 10 ideological factions.
See [docs/PIVOT.md](PIVOT.md) for the pivot brief.

## Built
- Combat
- Simultaneous turns and orders
- Cities and reinforcement
- Terrain
- Art pass: terrain, counters, UI theme
- Action bar and multi-turn moves
- Color-named nations
- Iso view: elevation, skirts, back-to-front draw, picking (Task 33; docs/art/ART_SPEC_v2.md)
- Elevation rules: climb cost, cliffs, uphill attack penalty; maps smoothed to 1-level steps with mountain foothills (hills) and a few tagged ridge cliffs, all land reachable; headless tests in tests/run_tests.gd
- Camera: arrow-key pan, middle/right-drag, wheel zoom 0.5x-2x at the cursor, clamped to the map (data/map_config.json "camera"); iso view_scale is 1.0
- Population model (Task 35): cities hold real people (capital 10,000), housing cap = infra x 3,000, growth 1% + 0.5% per Growth labor point, labor points = people / 2,000, cash = 1 per unassigned labor; specs in docs/specs/ (labor assignment, sinks and the recruit pool are Tasks 36-38)
- Labor assignment (Task 36): each city assigns labor points to Training, Infrastructure and Growth (city panel -/+ buttons; nation panel totals); default 50% Growth, rest unassigned for cash (resources_config.json "labor"); Growth feeds growth, the other two are stored until Task 37
- Labor sinks (Task 37): Training labor feeds the recruit queue (15 labor-turns, min 3 turns, existing recruit costs); Infrastructure labor builds +1 infra per 10 labor-turns (raises housing, repairs capture damage); city panel shows queue and infra progress
- Recruit pool and tuning (Task 38; docs/specs/POPULATION_TUNING.md overrides POPULATION.md): growth = (0.5% + 1.0% x Growth labor share) x terrain mult (x 0.95 per adjacent fungus tile), never under 0.1%, 0 in a siege; each city has a recruit pool (fills 0.5%/turn, capped at 15%; capital starts with 1,000, colonies 0) that replaces the nation manpower stock; a recruit draws 1,000 people and needs 5,000 left; reinforcement costs 10 people per strength, drawn from the home city's pool then the nearest owned cities'; divisions carry home_city_id and survivors return to its population; siege (all land neighbors enemy-held) stops growth, costs 2% people a turn and halves labor; capture empties the pool and resets labor. Settings are in data/cities_config.json (growth, pool, siege), people_per_strength is global until Task 38b moves it to the division type.
- Stalled recruits: a queued recruit with 0 Training labor shows "Recruit stalled: assign Training labor" on the city panel, in the military panel queue list and in the end-turn message.
- Not yet: trait growth mods (hook: HexMap.growth_mods), fungus tiles (hook: HexMap.fungus_tiles), starvation (Task 38b hook), the global plunder cooldown and faction_traits (Task 41), attitude (Task 42).
- Pillars recruiting rules (Task 38b): people_per_strength and upkeep live on each division type in data/divisions_config.json (infantry 10 people/strength, 3 cash; mechanized and robotic are future entries with no units); new divisions are always full strength (no splitting); no training progress while a city is besieged, starving (hook: city.starving) or enslaved (hook: city.enslaved, Task 39); enslaved cities have no Training labor and a 0 pool; reinforcement skips empty pools; the AI uses the same checks and queues no recruit if its projected cash upkeep (fielded plus queued plus the new division) would exceed its per-turn cash income. Unpaid upkeep: divisions are paid in id order, cash never goes below 0, and each unpaid division loses 5 org that turn (unpaid_upkeep_org_loss), logged and shown in the military panel.
- Capture choices (Task 39; docs/specs/CAPTURE.md): taking a city opens a popup for the player (the AI uses ai_default_option, Annex, until Task 40) with Annex (-25% people, -30% infra, 26-turn rebuild, pool 0, 10-turn recruit lockout), Occupy (-10% people, labor x0.5, pool 0, no training, annexable free after 5 turns via a city panel button), Plunder (+5 cash per 1,000 people, -15% people, -50% infra, then annexed), Reduce (-50% people who flee to the old owner as refugees, -50% infra, then annexed), Raze (city removed, its land freed, 50% of its people flee to the old owner's nearest city, the rest die; allowed on a last city, which eliminates the nation, its armies surrendering as POWs) and Enslave (-10% people, city.enslaved: growth, pool and training 0, labor x1.5). Every choice logs a reputation_event (stub: HexMap.reputation, nothing reads it); Raze is always an atrocity, severity 3. All numbers are in data/cities_config.json "capture". Turn end waits on the popup (DivisionRoster.pending_captures).
- Capture gating and AI personality (Task 40; docs/specs/CAPTURE.md): each faction may only use the capture options in the cities_config.json capture.faction_options table (all may Annex; a gated option is disabled in the popup with a reason and falls back to Annex if forced). The AI takes its faction's harshest allowed option (capture.harshness_order) with probability aggressive_harsh_chance (0.5) if the faction is in capture.aggressive_factions (Directorate, Collective, Free Tide, Drift), else Annex; ai_default_option is only the fallback for a nation with no faction. Atrocity is judged per observer: each faction in factions.json has views_as_atrocity (Raze always on it); HexMap.is_atrocity_to(faction, event) and reputation_weight_to(faction, event) (capture.atrocity_weight x the faction's optional atrocity_sensitivity, default 1.0, else base severity) are for Task 42's attitude to consume, nothing does yet. The event's own atrocity flag and severity are unchanged. The city panel shows Recruitable 0 for occupied and enslaved cities.

## Next
- Task 31: remove doom systems
- Task 32: factions.json, 4 factions with 1 sea
- Then the naval slice

## On hold
- Rail Tasks 27 and 28

## Maintenance
Read this file at the start of every session and update it with each PR.
