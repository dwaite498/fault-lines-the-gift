# City Tiers (approved Nov 9, 2026)

Tiers are a visual label plus claim radius. They have no other stat effects. All numbers go in `data/cities_config.json`.

## Config changes (data/cities_config.json)
- Add `"tiers": [{"key": "outpost", "min_pop": 0}, {"key": "base", "min_pop": 5000}, {"key": "city", "min_pop": 15000, "claim_radius": 2}, {"key": "metropolis", "min_pop": 30000, "claim_radius": 2}]`.
- Add `"colony_start_population": 3000` and `"capital_start_population": 10000`. These replace `start_population`, now in people per POPULATION.md.
- Remove `grown_radius_population`. Claim radius comes from the tier, with a default of `claim_radius` (1).

## Rules
- `tier(city)` is the highest tier whose `min_pop` is less than or equal to the population. It's recalculated at the end of each turn, after growth and losses.
- Claim radius 2 starts at City tier (15,000 people). If a city drops below 15,000, it keeps the tiles it already claimed but stops claiming new ring-2 tiles [DEFAULT]. Tiles still flip on capture as they do now.
- A tier change logs to the turn log, for example "Port Haven grew to a City".

## Sprites
- The key format is `base_<base_style>_<tier>`, for example `base_assembly_city`. `base_style` comes from factions.json, and sea factions use their own styles.
- Look it up in this order: the exact key, then `base_generic_<tier>` (the generic dome, scaled per tier), then `base_generic_base`. Missing art never crashes the game and never shows an empty tile.
- Placeholder scaling until the art lands: Outpost 0.6x, Base 0.8x, City 1.0x, Metropolis 1.2x of the generic dome. Sea factions get the dome-on-platform variant.
- The city label shows the tier, for example "Port Haven (City)". The city panel shows the population needed for the next tier, for example "Next tier: 15,000".

## Out of scope
Tier-based stat bonuses, per-faction sprite art (a separate art task), and city decay or abandonment.

## Acceptance criteria
1. A new colony starts at 3,000 people as an Outpost, and a capital starts at 10,000 as a Base.
2. A city reaching 15,000 becomes a City and starts claiming radius-2 tiles the next turn. At 4,999 it's an Outpost, and at 5,000 it's a Base.
3. A City that drops to 14,000 shows as a Base and keeps its ring-2 tiles.
4. With no faction sprites present, every tier renders with the generic dome at the right scale, with no errors in the log.
5. `grown_radius_population` has no remaining references in the code.

Size: S, 1 PR.
