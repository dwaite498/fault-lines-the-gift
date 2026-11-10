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
