# Native Life and Alien Escalation (approved Nov 9, 2026)

## Part A: the minimum native layer
### Files
- `data/natives.json`: unit types, spawner, AI, and pressure config.
- `scripts/natives/native_spawner.gd`, `scripts/natives/native_ai.gd`, and `scripts/natives/pressure.gd`.
- Natives are a special nation (`NATIVE_NATION = -2`). They're hostile to everyone, own no cities, have no economy, and never surrender.

### Unit types (from art_concepts/alien_fauna_sheet.jpg)
| key | Lifeform | Habitat | Stats (str / org / atk / def) | Move | Notes |
|---|---|---|---|---|---|
| `tendril_worm` | Tendril Worm | fungus only | 60 / 40 / 12 / 8 | 1 | Ambusher: +25% attack on the first combat round when it attacks out of fungus. It can't leave fungus tiles. |
| `rust_strider` | Rust Strider herd | land: plains and hills | 30 / 30 / 5 / 5 | 2 | Weak wanderer. It flees when org drops below 50%. |
Natives use the normal combat resolution. They don't fortify and can't capture cities. If a native reaches 0 org, it's removed, and it never retreats to a home or surrenders. Draw natives with creature sprites and the magenta outline per CONCEPT_NOTES, never on a standee plate.

### Spawner
- Runs at the end of each turn.
- For each fungus tile with `fungus_density` of 3 or more and no unit within 2 hexes, there's a `worm_spawn_chance` (default 0.02) of spawning a Tendril Worm.
- For a random plains tile at least 4 hexes from any city, there's a `strider_spawn_chance` (default 0.05) per turn of spawning a Rust Strider herd.
- Caps: at most `max_natives` (default 6 on small maps), and no spawns within 3 hexes of a city before turn 5.
- Spawns can't block landfall: no spawns before turn 3.

### Native AI
- Each turn, if an enemy unit is adjacent and the native can attack it legally, it attacks. Otherwise it moves 1 random step within its habitat.
- Strider herds also flee away from adjacent enemies when org is below 50%.
- Worms attack adjacent city hexes too. They do org damage only and can't take the city.
- Natives issue orders through the normal simultaneous-orders system, collected blind like the AI's.

## Part B: Pressure and escalation
### Pressure score (planet-wide, 0-100, stored with per-faction contributions)
| Event | Base pressure |
|---|---|
| +1 infrastructure built | +0.5 |
| New city founded | +2 |
| Each city above 30,000 people | +1 per turn |
| Battle on a fungus tile, or any battle involving natives | +1 |
| Raze | +5 |
| Enslave | +3 |
- Each faction's contribution is multiplied by `pressure_mult`: Verdant Accord 0.5, Syndicate 1.25, Deepwater Guild 1.25, and everyone else 1.0. This goes in `data/natives.json` under `faction_pressure_mult`, keyed by faction key.
- Keep a `recent_contrib[faction]` per faction, with exponential decay of 0.9 per turn, for offender bias.

### Levels (they compound)
| Level | Name | Threshold | Effect (multipliers stack on the base config) |
|---|---|---|---|
| 1 | Wary | 0 | Base spawn chances and stats. |
| 2 | Hostile | 30 | Spawn chances x2, native str/atk x1.25, `max_natives` +4. |
| 3 | Swarm | 60 | Spawn chances x3 (stacked on Hostile, so x6 total), native str/atk x1.5 (x1.875 total), `max_natives` +8. Worms may spawn on density-2 fungus. |
- Decay: if pressure is below the current level's threshold, it drops by 0.5 per turn. Swarm never decays. Once pressure reaches 60, the level stays at 3 for the rest of the game.
- Levels go up immediately when a threshold is crossed. They go down only through decay, and only from Hostile to Wary.
- Every level change logs a world event, such as "The planet stirs", with no faction-specific hint text (hints are OUT OF SCOPE for now).

### Offender-biased spawns
- When spawning, pick a target faction weighted by `recent_contrib`.
- 70% of spawns are placed in or within 3 hexes of that faction's claimed territory, in a valid habitat. The other 30% are placed at random.
- If there's no valid habitat near the offender, spawn at random.

## Out of scope
Spore Drifter, Mycel Hive, Trench Leviathan, and Reef Skimmer; fungus growth and spread; taming or capturing natives; the Planet-axis diplomacy reactions; hint text; and naval natives.

## Acceptance criteria
1. With `seed=1` on a small map, no natives spawn before turn 3, and the native count never exceeds `max_natives` for the current level.
2. A Tendril Worm never leaves fungus tiles, and its first attack out of fungus gets +25%.
3. A native with an enemy adjacent attacks it. Otherwise it moves within its habitat.
4. Natives never capture or claim a city.
5. Building one infrastructure as Verdant adds 0.25 pressure, and as Syndicate adds 0.625.
6. Pressure 30 gives Hostile with doubled spawn chance, and pressure 60 gives Swarm, which stays even if pressure is later forced to 0.
7. In a test where only faction X razes cities, at least 60% of 100 seeded spawns land near X's territory.
8. Every number is in data/natives.json.

Size: M, 3 PRs. PR 1 covers the native nation, the 2 unit types, rendering, and the spawner. PR 2 covers the native AI and combat hookup. PR 3 covers pressure, levels, decay, multipliers, and offender bias.
