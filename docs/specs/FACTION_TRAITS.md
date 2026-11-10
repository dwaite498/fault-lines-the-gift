# Faction Traits and Affinities (approved Nov 9, 2026)

Identity, colors and leaders: see PIVOT.md. This spec adds mechanics. Every number lives in `data/factions.json`, with no hard-coded values.

## Files
- `data/factions.json`: a `factions[]` array (ids 0-9, in PIVOT order), plus `global` and `ai` blocks.
- Modifier lookup: a single helper, `FactionTraits.mod(nation, key, default)`, used by combat, economy, population, capture and movement.

## data/factions.json shape
```json
{
  "global": {"plunder_cooldown_turns": 20, "flat_bonus_city_cap": 6, "growth_bonus_pop_ceiling": 15000, "rival_attitude": -2},
  "ai": {"attitude_weight": 1.0, "distance_weight": 0.5, "strength_ratio_weight": 1.0, "min_attack_score": 0},
  "factions": [
    {"id": 0, "key": "assembly", "axes": {"order": -2, "faith": 0, "planet": 0}, "atrocity_sensitivity": 1.5,
     "rivals": ["directorate", "collective"], "capture_allowed": ["annex", "occupy"],
     "faction_traits": {"growth_bonus_small_city": 0.005, "cash_per_city": 2, "recruit_cap_mult": 0.75, "upkeep_extra": 1, "occupy_annex_turns": 3}}
  ]
}
```
Atrocity sensitivity values: Low = 0.5, Mid = 1.0, High = 1.5. This value is stored now and used later by diplomacy.

## Traits (faction_traits keys)
| id | Faction | Bonuses | Deficits | Flavor |
|---|---|---|---|---|
| 0 | Assembly | `growth_bonus_small_city` 0.005; `cash_per_city` 2 | `recruit_cap_mult` 0.75; `upkeep_extra` 1 | `occupy_annex_turns` 3 |
| 1 | Directorate | `max_org_mult` 1.10; `fortify_turns_to_max` 2 | `growth_mod` -0.005 | `home_org_regen_bonus` 5 |
| 2 | Syndicate | `cash_per_city` 3; `plunder_cash_mult` 1.5 | `max_org_mult` 0.90 | `rush_cost_per_labor` 10, `rush_cap_per_turn` 5 (nation-wide) |
| 3 | Verdant Accord | `defense_mult_terrain` {forest: 1.15, hills: 1.15}; `housing_flat_per_city` 3000 | `infra_cost_labor` 13 | `no_uphill_penalty_terrain` ["forest"] |
| 4 | Covenant | `org_mult_defending_own_city` 1.15; `recruit_cap_flat_per_city` 500 | `cash_mult` 0.85 | `org_on_city_lost` 10 |
| 5 | Collective | `labor_per_city` 1; `pool_fill_mult` 1.25 | `growth_mod` -0.005; `cash_mult` 0.90 | `occupy_labor_mult` 0.75 |
| 6 | Lyceum | `infra_cost_labor` 8; `supply_range_bonus` 1 | `attack_mult` 0.90 | `intel_start_level` 2 (stored only; no effect until Intelligence Capacity exists) |
| 7 | Free Tide | `naval_attack_mult` 1.20; `plunder_cash_mult` 2.0, `plunder_cash_cap` 50 | `growth_mod` -0.005; `max_fortify_mod` -1 | `naval_capture_undefended_coastal` true |
| 8 | Deepwater Guild | `labor_per_sea_city` 1; `sea_housing_per_infra` 4000 | `naval_strength_mult` 0.90 | none (deep-ocean building is OUT OF SCOPE) |
| 9 | Drift | `naval_move_bonus` 1; `sea_supply_range_bonus` 2 | `housing_mult` 0.75 | none (the fleet-survival rule is OUT OF SCOPE) |

Rules:
- Every `*_per_city` and `*_per_sea_city` bonus counts at most `flat_bonus_city_cap` (6) cities.
- `growth_bonus_small_city` applies only while the city is below `growth_bonus_pop_ceiling` (15,000).
- `growth_mod` applies to every city, and growth can't go below 0.
- Global plunder cooldown: each city stores `last_plundered_turn`. If fewer than `plunder_cooldown_turns` (20) turns have passed since any nation plundered it, Plunder is not offered.
- The Collective's Enslave uses the standard 1.5x labor. There's no Collective override.

## Affinity and attitude
- Axes are integers from -2 to +2: order (+Order / -Liberty), faith (+Faith / -Reason), planet (+Planet / -Industry).
- `attitude(a, b) = -(|order_a - order_b| + |faith_a - faith_b| + |planet_a - planet_b|)`. Add `rival_attitude` (-2) if b is in a's rivals. The result is not symmetric when rivals lists differ.
- Axes: Assembly (-2,0,0), Directorate (+2,0,-1), Syndicate (-1,-1,-2), Verdant (0,+1,+2), Covenant (+1,+2,0), Collective (+2,-1,-1), Lyceum (0,-2,-1), Free Tide (-2,0,0), Deepwater (+1,-1,-2), Drift (-1,+1,+1).
- Atrocity sensitivity: Assembly High, Directorate Low, Syndicate Low, Verdant High, Covenant Mid, Collective Low, Lyceum Mid, Free Tide Low, Deepwater Low, Drift Mid.

## AI target weighting
For each enemy city in range, `score = -attitude * attitude_weight - hex_distance * distance_weight + (my_local_strength / their_local_strength - 1) * 10 * strength_ratio_weight`. The AI attacks the highest score above `min_attack_score` and otherwise defends or expands as it does today. Capture choice per CAPTURE.md: aggressive factions (Directorate, Collective, Free Tide, Drift) pick their harshest allowed option 50% of the time.

## Out of scope
Diplomacy reactions to atrocities, rush-buy UI beyond one button, deep-ocean building, Drift fleet survival, and intel.

## Acceptance criteria
1. Each of the 10 factions loads from data/factions.json. Changing any number in the JSON changes the behavior with no code edits.
2. A unit test per faction checks each trait. For example, a Directorate division reaches max fortify in 2 turns, and a Verdant division defends at 1.15x in forest.
3. A flat per-city bonus with 8 cities equals the 6-city value.
4. The Assembly growth bonus disappears when a city reaches 15,000 people.
5. A city plundered on turn T can't be plundered by anyone before turn T+20.
6. attitude(Assembly, Directorate) = -(4+0+1) - 2 = -7, and attitude(Assembly, Free Tide) = 0.
7. In a seeded 4-faction AI test game, each AI attacks its lowest-attitude reachable neighbor first when strengths are equal.

Size: S-M, 2 PRs. PR 1 covers the data file, the helper, and the trait hooks. PR 2 covers affinity, attitude, AI weighting, and the plunder cooldown.
