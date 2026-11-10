# City Population and Labor

## Population
- Cities track real people. Scale: the old 1 pop = 1,000 people. A capital starts at 10,000 [DEFAULT]. Display it rounded to the nearest 100.
- Housing cap = infrastructure x 3,000, so the starting infra of 10 gives a 30,000 cap.
- Growth per turn = 1% base + 0.5% per labor point assigned to Growth, capped at housing [DEFAULT]. There is no food stockpile in the MVP.

## Labor
- Labor points = population / 2,000, rounded down [DEFAULT].
- Each turn the player assigns labor to 3 sinks. Unassigned labor gives +1 cash each.
  1. Training feeds the city's recruit queue. A division costs 15 labor-turns and takes at least 3 turns [DEFAULT].
  2. Infrastructure: 10 labor-turns = +1 infra (+3,000 housing). It also rebuilds capture damage.
  3. Growth: +0.5% growth per point.
- New and AI cities default to all-Growth until a recruit is queued [DEFAULT].
- Labor replaces the capacity resource for city production. Division upkeep becomes cash only, at 3 cash per division [DEFAULT]. Keep the `capacity` name reserved for later orbital use.

## Recruitable pool (replaces the nation-wide manpower pool)
- Each city has a recruitable pool that is part of its population. It fills by 1% of city population per turn. The cap is 10% of population, or 20% for cities over 10,000 [DEFAULT].
- Recruitable people stay in the population and count toward labor until they're drawn. Drawing from the pool reduces the pool, the city population, and the city's labor, which is recalculated immediately.
- A new division draws 2,000 people from its training city's pool, and the pool must hold at least 2,000. A city can't train if that would drop it below 5,000 people [DEFAULT].
- Reinforcement costs 100 people per strength point, drawn from the home city's pool. If that pool is empty, draw from the nearest owned city's pool. The existing reinforcement multipliers still apply.

## Home city
- Every division stores `home_city_id`, set to where it trained. Starting divisions use the capital.
- When a division leaves play (disbanded, demobilized, or POWs returned), its survivors (strength x 100) return to the home city's population, not its pool.
- If the home city is lost, survivors go to the nearest owned city, with the capital as tiebreak [DEFAULT]. If the home city is retaken, the flag stays as it was.
- Combat deaths aren't subtracted again, since those people were already drawn. Destroyed or surrendered divisions return no one except through POWs.

## Capture and siege
- Capture effects depend on the captor's choice; see CAPTURE.md. Recruit queue progress is lost on capture.
- Siege (all land neighbors are enemy-held, or the city is cut off from supply): growth stops, population drops 2% per turn, and labor is halved [DEFAULT].

## UI
- City panel: 'Pop 12,400 / 30,000 housing', 'Labor 6 (1 free)', 'Recruitable 1,000', then 3 rows (Training, Infrastructure, Growth), each with -/+ buttons and progress toward its next result, such as 'Division 9/15, 2 turns left'.
- Nation panel: total labor and its split, plus total recruitable.

## Out of scope
Tech, happiness and unrest effects, trade, specialists, and food as a separate resource.

## Size: M, 4 PRs
1. Population data model: people counts, housing, growth, config rescale, and the cash formula.
2. Labor pool and assignment, the city panel UI, and nation panel totals.
3. Labor sinks: a training queue fed by labor, and infrastructure building.
4. Per-city recruitable pool, replacing the nation-wide manpower pool (economy panel and AI recruit checks); the home_city_id flag and survivor returns; reinforcement draw; the training floor; siege effects; and AI default assignment.
