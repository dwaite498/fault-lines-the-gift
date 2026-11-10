# Fault Lines: Pivot Brief (Landfall)

## Direction
This is a homage to Sid Meier's Alpha Centauri: rival ideological factions settle an alien world after landfall. Keep combat (simultaneous orders, strength x organization, fortify, attrition, encirclement, POWs), cities and influence, territory, and terrain. Native life and aliens come later. Doom/Gift systems are removed from the build, and their design lives in docs/archive/.

## Landfall start (turn 1, every faction)
- 1 colony pod. It founds the capital on its turn-1 tile or within 2 hexes [DEFAULT].
- 2 full-strength divisions. Land factions get 2 infantry; sea factions get 1 Naval and 1 Marine division [DEFAULT].
- 1 extra colony pod, ready after 3 turns of training [DEFAULT].
- A small cash and manpower stockpile, enough for 1 more division [DEFAULT].
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

## Out of scope
Native life and aliens, faction bonuses, tech tree changes, new diplomacy, maps bigger than small, 10-faction games, extra naval types, terraforming, councils and votes. Intelligence Capacity stays queued as-is.
