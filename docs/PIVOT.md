# Fault Lines: Pivot Brief (Landfall)

## Direction
This is a homage to Sid Meier's Alpha Centauri: rival ideological factions settle an alien world after landfall. Keep combat (simultaneous orders, strength x organization, fortify, attrition, encirclement, POWs), cities and influence, territory, and terrain. Native life and aliens come later. Doom/Gift systems are removed from the build, and their design lives in docs/archive/.

## Landfall start (turn 1, every faction)
- 1 colony pod. It founds the capital on its turn-1 tile or within 2 hexes [DEFAULT].
- 2 full-strength divisions. Land factions get 2 infantry; sea factions get 1 Naval and 1 Marine division [DEFAULT].
- 1 extra colony pod, ready after 3 turns of training [DEFAULT].
- A small stockpile, enough for 1 more division [DEFAULT]. In the build this is the capital's starting recruit pool of 1,000 people (docs/specs/POPULATION_TUNING.md).
- Land starts are at least 6 hexes apart on land. Sea starts are on shallow ocean near the coast [DEFAULT].

## Factions per game
- Small test maps: 4 factions, at least 1 sea (APPROVED). Medium: 6. All 10 only on large maps, post-MVP.
- The player picks a faction on setup, and the rest are random.

## Factions (identity only, no mechanical bonuses yet)
Working-draft names, original and not SMAC copies. Colors are the Art Director v2 slots.

| # | Faction | Type | Color | Leader | Ideology | Rivals |
|---|---|---|---|---|---|---|
| 0 | Assembly | Land | #3FA7D6 | Speaker Mara Ellison | Democracy, consent, rights | Directorate, Collective |
| 1 | Directorate | Land | #D64545 | Marshal Yuri Kessane | Order, discipline, security | Assembly, Free Tide |
| 2 | Syndicate | Land | #E3C14B | Chairman Teodor Halvard | Markets and profit set people free | Collective, Verdant Accord |
| 3 | Verdant Accord | Land | #5DBB63 | Steward Ilse Varga | The planet is not ours to strip | Deepwater Guild, Syndicate |
| 4 | Covenant | Land | #9B6FD1 | Shepherd Abigail Crane | Faith and a divine mission | Lyceum, Assembly |
| 5 | Collective | Land | #E07B39 | Comrade-Chair Lin Wei | All for the commune | Syndicate, Assembly |
| 6 | Lyceum | Land | #3CC4B0 | Provost Anand Rao | Knowledge above all | Covenant |
| 7 | Free Tide | Sea | #D65FA0 | Captain Rook Salazar | Freedom through plunder | Directorate, Deepwater Guild |
| 8 | Deepwater Guild | Sea | #C9C9C9 | Foreman Odile Brandt | Industry under the sea | Verdant Accord, Free Tide |
| 9 | Drift | Sea | #7A8FE0 | Navigator Kai Aleho | Keep moving, need no one | Distrusts all landed powers |

## Minimum naval slice
- Ocean tiles come in two kinds. Shallow ocean can hold sea cities. Deep ocean is movement only. Land units can't enter ocean.
- Sea cities are platform cities founded on shallow ocean. They claim ocean and coastal tiles like land cities do, and they're captured by marines or adjacent naval units [DEFAULT].
- Unit types (APPROVED, an exception to the one-division-type rule): a Naval Division moves on ocean only and uses the same strength/organization stats. A Marine Division can move on ocean at reduced defense and lands on the coast with an amphibious penalty.
- Coastal combat: naval units bombard an adjacent land hex for organization damage only and never take the hex. Amphibious landings get a large attack penalty, the same as the large-river rule. Fortify works on land and in sea cities, but not for units at sea.
- Naval supply: units must stay within X hexes of a friendly sea or coastal city or suffer attrition [DEFAULT X=4].
- Out of scope: submarines, carriers, transport capacity, and any other naval types.

## Archived (docs/archive/, design kept, code removed)
The Gift lore and impact; the doom enemy, hidden attention counter, drift, and hints; the arrival countdown and readiness score; the Concord/Accord/Ascendants factions and faction meters, plus the splinter-below-25 rule; soul-cost fixes; the space-race pivot.

## Pillars
Approved Nov 9, 2026 (summary of the design pillars; items marked FIX are cheap config or rule changes, the rest are notes for later).

1. **Forces shift from people to machines.** As tech advances, divisions move from Infantry to Mechanized to Robotic. Each step needs fewer people per strength point and costs more upkeep.
   - FIX: `people_per_strength` and upkeep live on each division type in `data/divisions_config.json` (Infantry: 10 people per strength, 3 cash). Later types are just new entries.
   - Future values [DEFAULT]: Mechanized 5 people per strength, 6 cash, 1 Alloy support. Robotic 2 people per strength, 10 cash, 1 Alloy, 1 Fuel. Alloy caps how many mechanized and robotic divisions you can support, and Fuel supplies Robotic and Naval, so resource option C waits for tech and option B stays the MVP.
   - A tech system (about 12 techs across 3 eras that unlock division types, fungus yields and buildings) is future and out of scope.
2. **Wave tactics are never viable.** A division costs 1,000 people, the recruit pool fills 0.5% of population a turn and caps at 15%, casualties are permanent, only survivors go home, and upkeep is 3 cash per division. Loopholes closed:
   - A new division always starts at full strength and pays the full 1,000 people. There are no splits [DEFAULT].
   - Attacks on one hex are capped at `max_attackers_per_hex` = 3 (frontage) [DEFAULT]. Task 46.
   - An annexed city's pool starts at 0 and it cannot recruit for `captured_recruit_lockout_turns` = 10; an occupied city's pool stays 0. Task 39.
   - An enslaved city's pool is 0 permanently, its labor cannot go to Training, and reinforcement skips pools at 0.
   - Covenant's cap bonus becomes `recruit_cap_pct_bonus` +3% (a cap of 18%). Task 41.
   - Collective's pool fill x1.25 stays (its identity).
   - No Training during a siege or while food_ratio is below 1 (starving).
   - Disbanding to farm the pool does not work, since survivors go to population, not the pool.
   - The AI uses the same pool and floor rules.
3. **The planet is dangerous.** The early game must not feel empty, and fungus must be a risk.
   - FIX: `min_natives_wary` = 2 (the spawner tops the native count up to 2 even at zero pressure).
   - FIX: ending a turn on fungus costs a non-native unit -5 org and -2 strength (`fungus_attrition`); Verdant takes half [DEFAULT]. Fungus also costs +1 move.
   - FIX: Rust Striders raid an adjacent city with no defender (Outpost or Base): the city loses 5% of its population and 1 infra, then the strider flees.
   - FIX: the Hostile threshold drops from 30 to 25; Swarm stays at 60.
   - Keep the early safety rules: no spawns before turn 3, none within 3 hexes of a city before turn 5.
   - Later, with tech: a way to make fungus tiles worth something.

Where each lands in the build: pool, home city, reinforcement and the training floor are Task 38; the Pillars recruiting rules and per-type upkeep are Task 38b; annex lockout and enslave are Tasks 39-40; Covenant is Task 41; natives and fungus are Task 44; the Hostile threshold is Task 45; frontage is Task 46.

## Out of scope
Native life and aliens, faction bonuses, tech tree changes, new diplomacy, maps bigger than small, 10-faction games, extra naval types, terraforming, councils and votes. Intelligence Capacity stays queued as-is.
