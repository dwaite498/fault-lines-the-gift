# Capture Choices

When a city is captured, the captor picks one option in a popup. The AI picks by personality. All numbers are [DEFAULT]. This depends on POPULATION.md.

## Options
- **Annex** (the default): -25% population, -30% infra. The city joins normally.
- **Occupy**: -10% population. The city is held at 50% labor with its recruitable pool at 0. It can be annexed after 5 turns with no extra loss.
- **Plunder**: +5 cash per 1,000 people, -15% population, -50% infra, then annex.
- **Reduce**: -50% population, -50% infra, then annex. The displaced people move to the former owner's nearest city, or are lost if it has none.
- **Raze**: the city is destroyed and its tiles become unclaimed. 50% of the population flees to the former owner's nearest city and the rest are lost.
  - Every Raze is an atrocity: log a reputation_event with type 'raze', severity 3, and `atrocity: true`.
  - Razing a nation's LAST city is allowed. It eliminates the nation (the existing nation-death rules apply, and its armies surrender as POWs).
- **Enslave**: -10% population. The city produces 1.5x labor, but its growth and recruitable pool stay at 0 permanently.

## Reputation hook
Every choice logs `reputation_event{type, captor, victim, city, severity 0-3, atrocity}`. Severity defaults: Annex 0, Occupy 0, Plunder 1, Reduce 2, Enslave 3, Raze 3 (always atrocity: true). It has no effect yet; it's for later diplomacy.

## Faction gating [DEFAULT]
| Faction | Allowed |
|---|---|
| Assembly | Annex, Occupy |
| Directorate | Annex, Occupy, Reduce, Raze |
| Syndicate | Annex, Occupy, Plunder |
| Verdant Accord | Annex, Occupy, Reduce |
| Covenant | Annex, Occupy, Reduce |
| Collective | Annex, Occupy, Enslave, Raze |
| Lyceum | Annex, Occupy |
| Free Tide | Annex, Occupy, Plunder, Enslave |
| Deepwater Guild | Annex, Occupy, Plunder, Enslave |
| Drift | Annex, Plunder, Raze |

## AI
Aggressive factions (Directorate, Collective, Free Tide, Drift) pick their harshest allowed option 50% of the time and Annex otherwise. Other factions always pick Annex.

## Size: S-M, 2 PRs
1. Capture popup and effects, including the Occupy timer, refugee transfer, last-city raze elimination, and the reputation_event log stub.
2. Faction gating table in data, and AI choice by personality.

## Atrocity views per faction (David's ruling, Nov 9, 2026)
The `reputation_event` keeps its base severity. Raze is always `atrocity: true`. Each observing faction then judges the event using its own `views_as_atrocity` list in `data/factions.json`. If the event's type is on the observer's list, that observer treats it as an atrocity: its attitude toward the captor gets the atrocity penalty, scaled by its atrocity sensitivity. Otherwise the observer treats it as a normal event of that severity. Raze is on every list.
| Faction | `views_as_atrocity` | Reason |
|---|---|---|
| Assembly | raze, enslave, plunder | Its civic rights cover everyone, including people in conquered cities. |
| Directorate | raze | It sees forced labor as discipline and spoils as the price of war. |
| Syndicate | raze | It treats labor and loot as assets. Destroying a city only wastes them. |
| Verdant Accord | raze, enslave, plunder | It regards stripping people or land as a violation of the planet's balance. |
| Covenant | raze, enslave | It holds that every soul is sacred, while tribute is acceptable. |
| Collective | raze | It sees enslavement as labor re-education for the common good. |
| Lyceum | raze, enslave | It considers enslavement a waste of minds, while plunder is ordinary war economics. |
| Free Tide | raze | For pirates, loot and captives are part of the trade. |
| Deepwater Guild | raze | It views indentured labor and salvage as standard Guild practice. |
| Drift | raze, enslave | Its nomads value freedom of movement above everything else. |
Consistency: other than Raze, no faction's list includes a capture choice that faction is allowed to make. Raze is condemned by everyone, including the factions that can raze (Directorate, Collective, Drift). Those factions just have low or mid atrocity sensitivity.
