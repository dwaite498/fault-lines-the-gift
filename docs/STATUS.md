# Fault Lines: Planetfall — Status

Last updated: Nov 9 2026 (Task 36)

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

## Next
- Task 31: remove doom systems
- Task 32: factions.json, 4 factions with 1 sea
- Then the naval slice

## On hold
- Rail Tasks 27 and 28

## Maintenance
Read this file at the start of every session and update it with each PR.
