# Fault Lines: The Gift — Design

Open questions are marked **TBD**.

## Overview

- 2D turn-based, civ-style strategy game built in Godot.
- Planet layer only for now. Space comes later.

## Premise

- On turn 1, an alien object called **the Gift** hits the planet and destroys one region.
- **The doom** is a slow, overwhelming alien force. It escalates through a hidden **attention counter** that every faction can raise or lower.
- Attention stages:
  1. **Ignored**
  2. **Curious**: scouts
  3. **Interested**: signals
  4. **Engaged**: envoys. The doom objectives are revealed here.
  5. **Threatened**: army and invasion
- Players see only flavor events and hints until they research the tech to talk to the doom.
- TBD: the attention thresholds and which actions raise or lower attention.

## Core pillar

Every fix costs part of the faction's soul, and those costs are permanent. Bad choices pile up.

## Factions

### Playable public factions

| Faction | Stance | Meter |
| --- | --- | --- |
| **Concord** | Unites humanity the old way. | Unity |
| **Accord** | Welcomes the doom, and pays a heavy price for the doom's help. | Devotion |
| **Ascendants** | Take doom tech without serving the doom, and oppose doom troops on the planet. | Humanity |

- When Ascendant Humanity drops, it brings social, diplomatic, doom-whisper, and identity-drift effects.
- TBD: the specific Accord costs and Humanity effects.

### Hidden AI minor factions

These factions secretly take over nations that still look neutral.

- Humanity First, plus Terran Guard
- Insurgents
- Syndicate, plus Exodus

## Collapse

- When a faction's meter drops low enough, the faction splinters by dice roll.
- The pieces range from extreme to moderate. A piece's trait strength depends on how extreme it is. Some neutral nations also split off.
- The player keeps one piece.
- Pieces can reunite slowly: through diplomacy for the Concord, and through doctrine for the Accord. TBD: how Ascendant pieces reunite.
- **Concord:**
  - Collapse risk starts below 25% Unity and grows as Unity falls.
  - Nation requests raise or lower Unity.
  - Desperate measures unlock as Unity drops.
- TBD: the collapse thresholds for Devotion and Humanity.

## Victory

- Each faction has a weighted mix of win conditions.
- Each faction also picks one **doom objective** at the reveal, and that choice is locked in. Factions can share an objective.
- Example doom objectives:
  - A defense station, which means permanent self-exile
  - Pushing the doom back past a line
  - A black hole bomb
- TBD: the full list of win conditions and their weights.

## Map

- The map is a generated hex map.
- Nations are made of regions. Each region has population, infrastructure, tech level, resources, and bonuses or drawbacks.
- Nations have a minimum size, and hexes can be traded.
- The target is 30 nations on about 80 by 50 hexes. Test builds use small maps and scaled-down numbers.
- Players start in large nations.

## Turns

- One turn is one week.
- All factions plan, then resolve simultaneously.
- Resolution order:
  1. Espionage
  2. Diplomacy
  3. Management and research
  4. Movement and combat
  5. Events and doom
- Clashes go to contested rolls. Bigger forces get better dice, but a large enough tech gap overrides numbers.
- Battles can last several turns and are driven by cohesion and morale.
- TBD: the dice formulas and the size of tech gap that overrides numbers.

## First playable version

- The Concord only, against simple AI
- Units: infantry, armor, and artillery
- Influence-based diplomacy
- Unity with a few requests and events
- The Gift's impact plus the first doom stages

## MVP Systems Spec (Oct 29)

Status tags: **[Built]** is in the game now. **[Partial]** is partly built. **[Planned]** is not built yet.

### 1. Cities and territory
- **[Partial]** Each city claims the hexes around it, and unclaimed land is neutral. The target claim radius is 1 (the city plus its 6 neighbors), growing to 2 as the city grows. Today every city uses a fixed radius of 2 (`data/cities_config.json`), and growth is **[Planned]**.
- **[Built]** A nation is eliminated when it loses its last city, and its divisions are disbanded.
- **[Partial]** A city is captured when an enemy division moves onto it with no defender there. All of the city's claimed tiles flip with it. Capture works today.
- **[Planned]** Cities are captured intact. Population drops by about 25%, some infrastructure is lost, and rebuilding takes about 26 turns (1 turn is 1 week).
- **Later:** gradual and contested tile flipping.

### 2. Popularity and unrest [Planned]
- Each city tracks a 0-100 popularity for every faction.
- Unrest is the best rival faction's popularity minus the owner's popularity.
- A small gap gives an output penalty. A large gap causes riots and a bloodless defection of the city to the most popular faction.

### 3. Resources [Planned]
- **Cash.**
- **Influence.**
- **Operations.**
- **Manpower** comes from population and caps recruiting and reinforcement.
- **Capacity** builds divisions and infrastructure, and later launch and orbital work.
- **Faction meters.**
- **Research** is funded with cash. Parked.

### 4. Espionage [Planned, PROVISIONAL, parked]
- To be built as a modular piece.
- Control points work like Terra Invicta's.
- 3 starting agents (whether per player or per faction is TBD). Agents have Persuasion, Investigation, and Security stats.
- Ops are Investigate, Propaganda, Coup, Purge, Sabotage (a candidate soul-cost op), and Protect.
- Each op is a contested roll, and a failed op exposes the agent.

### 5. Player info screens
- **[Partial]** A unit panel (selected-unit info) is built. Ownership shows as a nation-color tint and borders on the map.
- **[Planned]** Turn summary, city panel, nation panel, military panel, and map overlays by owner and by unrest.
- **Later:** faction, espionage, doom log, and diplomacy screens.

### 6. Hidden-information rule [Planned]
- A nation secretly run by a minor faction shows as neutral everywhere.
- Its actions are logged with no actor.
- A successful Investigate reveals the controller and relabels the earlier log entries.
- The UI must never leak hidden control.

### 7. Parked
- A space race pivot around the Engaged stage.
- Strategic materials.