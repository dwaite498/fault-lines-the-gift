# Population Tuning: Scarce Food (approved direction Nov 9, 2026)

This file overrides the numbers in POPULATION.md, FACTION_TRAITS.md, and CITY_TIERS.md wherever they differ. The goal is slow growth, so that every lost division is a real cost. All values go in `data/cities_config.json` unless marked otherwise.

## 1. Growth formula (changed)
`growth = (base_growth + growth_labor_max_bonus * growth_labor / total_labor) * terrain_growth_mult * trait mods`, clamped at the housing cap. The final rate is never below `min_growth`, except during a siege, when it is 0.
- The bonus now scales with the *share* of labor assigned to Growth, not the raw labor points. This stops big cities from compounding.

| Key | Old | New |
|---|---|---|
| `base_growth` | 0.01 | **0.005** |
| `growth_per_labor_point` | 0.005 | removed |
| `growth_labor_max_bonus` | n/a | **0.010** (full Growth = 1.5% total) |
| `min_growth` | n/a | 0.001 |

Turns to reach each threshold, at the base rate with no traits or terrain modifiers:
| Allocation | Colony 3k to 5k | Colony 3k to 15k | Capital 10k to 15k | Capital 10k to 30k |
|---|---|---|---|---|
| No Growth labor (0.5%) | 103 | 323 | 82 | 221 |
| Half on Growth (1.0%) | 52 | 162 | 41 | 111 |
| Full Growth (1.5%) | 35 | 109 | 28 | 74 |
| Assembly, full Growth (1.8% while below 15k) | 29 | 91 | 23 | 62 |

What this means: a capital becomes a City in about 30-40 turns and a Metropolis in about 75-110. Colonies stay Outposts or Bases for most of a small-map game. That matches food being scarce.

## 2. Manpower (changed, so losses hurt without making recruiting impossible)
| Key | Old | New |
|---|---|---|
| `division_people_cost` | 2,000 | **1,000** |
| `people_per_strength` | 100 | **10** (= 1,000 / 100 max strength). This fixes a mismatch in rev 2: survivors returned and reinforcement now both use 10 per strength point. |
| `pool_fill_rate` | 1% of pop per turn | **0.5%** |
| `pool_cap` | 10% (20% above 10k) | **15% flat** |
| `capital_start_pool` | n/a | **1,000**, enough for exactly 1 extra division at landfall |
| `colony_start_pool` | n/a | 0 |
| `train_min_city_pop` | 5,000 | 5,000 (unchanged) |

Feel check: a 10k capital refills 50 people per turn, so replacing a lost division takes about 20 turns of pool. That pool also costs about 7 turns of full-Growth population gain. A 3k colony's cap is 450, so it can't raise a division until it has about 6,700 people. Colonies are not recruiting centers early on.

## 3. City tiers (re-checked)
The 5k / 15k / 30k thresholds are kept. Metropolis can be reached by a capital in about 74 turns on full Growth, or about 111 on half. The housing cap from starting infrastructure (10 infra = 30,000) only just allows it, so it effectively needs 1 extra infrastructure. That's intended: Metropolis is a late-game investment. No change to CITY_TIERS.md.

## 4. Trait growth mods (FACTION_TRAITS.md, in data/factions.json)
| Key | Old | New |
|---|---|---|
| Assembly `growth_bonus_small_city` | +0.005 | **+0.003** |
| Directorate, Collective, Free Tide `growth_mod` | -0.005 | **-0.003** |
| Collective `pool_fill_mult` | 1.25 | 1.25 (this is now 0.625% per turn) |
| Covenant `recruit_cap_flat_per_city` | +500 | **+300** |
| Assembly `recruit_cap_mult` | 0.75 | 0.75 (unchanged) |
| Verdant `housing_flat_per_city` | 3,000 | **2,000** (housing rarely binds now) |
With the old -0.5%, a penalized faction's base growth would have dropped to 0%, which made the penalty far too harsh.

## 5. Food levers (config only, `terrain_growth_mult` keyed by the city's own tile)
`{plains: 1.0, coast: 1.1, forest: 0.9, hills: 0.9, mountains: 0.7, shallow_ocean: 1.0}`. Then multiply by `fungus_adjacent_growth_mult` = **0.95 per adjacent fungus tile**, with a minimum of 0.7. Fungus pressure means less food.
- `siege_growth` = 0, and siege still causes a -2% per turn population loss (unchanged).

## Acceptance criteria
1. A capital at 10k on full Growth on plains, with no traits, reaches 15k on turn 28 ± 1 and 30k on turn 74 ± 1 (needs infrastructure of 11 or more, or a cap of exactly 30k allowed).
2. A city with 0 Growth labor grows exactly 0.5% per turn on plains.
3. A Directorate city with 0 Growth labor grows 0.2% per turn. No faction's growth falls below 0.1% outside a siege.
4. A city with 3 adjacent fungus tiles has a terrain multiplier of 0.857 (0.95^3).
5. Recruiting a division removes 1,000 people. Reinforcing 10 strength costs 100 people, and disbanding a division at 60 strength returns 600 people to its home city.
6. A capital starts with a pool of 1,000, and a 3k colony's pool never exceeds 450.

## Separate proposal (not part of this spec): a real Food resource
- What it is: each claimed tile yields food by terrain (plains 2, coast 2, forest 1, hills 1, fungus 0, shallow ocean 1). Each city eats 1 food per 1,000 people. A surplus feeds growth through the Growth multiplier. A deficit causes starvation: -1% population per turn and no recruiting. Cities could later trade food over supply lines.
- Why later: it makes territory and terrain matter more, and it ties into fungus spread and natives. It needs a new resource, UI, AI handling, and balance work.
- Size: M, 3 PRs (tile yields and city consumption; UI and starvation; AI and food transport). I'd recommend it after ALIENS.md lands, once fungus spread exists.
