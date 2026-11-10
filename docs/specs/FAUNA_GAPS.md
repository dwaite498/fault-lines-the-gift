> **Status (Task 45b):** only the Crag Harrier (section 2) is built. The Hollowfin Pack (section 1) is deferred to the naval slice (Naval N1-N3): the game has no deep-water layer or mobile naval units yet. Harrier numbers live in data/natives.json; Hostile/Swarm scaling uses the Pressure level multipliers (x1.25 / x1.875, so 44 and 66 strength).

# Fauna Gaps Addendum to ALIENS.md: Concept Only (Nov 9, 2026)
These two small natives fill the gaps left in the deep ocean and the highlands. The other 5 small natives are unchanged, and there's still no forest creature. The two new ones use the same threat-level scaling as the others: Hostile is x1.25 strength and attack, and Swarm is x1.875 in total. Org, defense, and move don't change. Stats are listed as strength / org / attack / defense / move.

## 1. Hollowfin Pack (deep water and trench)
**Role:** pack hunters from the deep that pick off lone ships and raid coastal Outposts.
**Look:** sleek, eyeless eel-sharks with glowing lateral lines, hunting in pairs.
| Level | Stats |
|---|---|
| Wary | 40 / 30 / 10 / 6 / 3 |
| Hostile | 50 / 30 / 12 / 6 / 3 |
| Swarm | 75 / 30 / 19 / 6 / 3 |
- **Habitat:** deep ocean and trench only. It can strike into an adjacent shallow or coastal hex without entering it.
- **Pack:** it always spawns as 2 units, and both count toward `max_natives`. It gets +15% attack when both units attack the same target, and it targets lone naval units first.
- **Raid:** when it strikes an undefended coastal Outpost next to deep water, the Outpost loses 5% of its population and its training queue resets. It never razes.
- **Spawning:** `hollowfin_spawn_chance` 0.02 per turn, on a deep tile at least 3 hexes from land, using the usual caps and turn-3 floor.
- **Pillar fit:** sending ships out one at a time is punished. Escorted fleets and ships with Fuel support (a combat bonus for them comes later) are the answer, not more hulls. The frontage cap still applies.

## 2. Crag Harrier (hills and mountains)
**Role:** winged cliff-nesters that dive on units moving through the highlands and hold the mountain passes.
**Look:** leathery, four-winged raptors with stone-gray hides, nesting in cliff hollows.
| Level | Stats |
|---|---|
| Wary | 35 / 35 / 9 / 10 / 2 |
| Hostile | 44 / 35 / 11 / 10 / 2 |
| Swarm | 66 / 35 / 17 / 10 / 2 |
- **Habitat:** each Harrier has a nest on a mountain tile and stays within 2 hexes of it, on hills and mountains only. It ignores terrain movement cost, and it gets normal terrain defense (so x2 on mountains).
- **Dive:** +30% attack against units that moved this turn. Units that are fortified or stationary are safe from the bonus. That makes moving carefully through the highlands the counter.
- **Pass hold:** enemy units next to a Harrier spend +1 movement to leave that hex. This is a zone of control.
- **Spawning:** `harrier_spawn_chance` 0.015 per turn, on a mountain tile with no unit within 2 hexes, using the usual caps. The nest is that tile.
- **Pillar fit:** it slows and bleeds anyone pushing through the mountains, so crossing the highlands is risky. You deal with it by fortifying and advancing slowly, or by sending a strong force to the nest. Stacking more divisions doesn't solve it.

## Pressure and integration
- Any battle with either creature adds Pressure +1, as for all natives.
- Neither one changes the levels or the offender bias.
- Building them waits for David's sizing. My estimate is S, 1 PR after Aliens Task 45. It covers two unit types plus the pack, strike, and dive rules.
