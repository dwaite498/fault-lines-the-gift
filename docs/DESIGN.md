# Fault Lines: Planetfall — Design

Open questions are marked **TBD**.

## Overview

- 2D turn-based, civ-style strategy game built in Godot.
- Planet layer only for now. Space comes later.

## Victory

- Each faction has a weighted mix of win conditions.
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
- Combat is a grind. Each attack, both sides deal damage (the attacker rolls first): damage = base_dmg * (own attack / other side's defense) * rand(0.8..1.2).
- The defender's defense includes its terrain's defense_mult, its fortify bonus (+10% per level), and a city bonus (x1.25) when it holds a city. The attacker uses its plain defense stat.
- Damage taken is scaled by morale, * (1.5 - morale), then split 75% to organization and 25% to strength.
- A division at 0 organization retreats 1 hex to a free friendly or neutral hex.
- A boxed-in division at 0 organization surrenders; its remaining strength becomes POWs held by the captor (see POWs).
- Manpower is spent when a division is created and drawn over time to replace losses and attrition.
- Divisions on home territory and not in combat take no attrition.
- Strength loss is permanent (reinforcement is planned). A division at 0 strength is destroyed.
- Divisions have 2 move points per turn (confirmed as intended by David).
- Selecting and orders (Task 26): a left-click only selects (a unit, else the city, else nothing); it never creates an order. The unit panel shows only the valid actions: Move (M), Attack (A), Dig in (D, fortify, replaces the order), Follow/Swap (F) and Cancel order (Esc). Move, Attack and Follow/Swap highlight their valid targets and the next click sets the order; the selection stays. Esc or a click elsewhere leaves the mode. Tab selects the next unit without an order. N toggles the military panel.
- Orders: the Move action highlights every hex reachable along a free path, including ones beyond this turn's move points; the unit moves as far as its points allow each turn and keeps the rest of the order until it arrives (Task 25). The arrow is solid for this turn's part and dimmer for later turns; the panel shows "Order: move to X, N turns". A blocked step, clash or bounce ends the order where the unit stands, with a log note. An attack order targets an adjacent enemy. Right-click or Esc clears it. AI orders are issued at the start of each turn, before and without seeing the player's. End turn executes all orders by nation then division id using the normal move and attack rules. Player arrows whose this-turn endpoints are the same hex turn yellow as a possible clash. (Simultaneous resolution comes later.)
- Supply: at end of turn, a division is in supply if a path of up to 8 passable hexes (no water, no hexes held by enemy divisions) reaches a city its nation owns. Out of supply (including encircled) divisions lose 10 org per turn (down to 0, no retreat) and recover no org or strength. Values are in `data/combat_config.json`.
- Upkeep: each division costs its type's upkeep per turn (infantry 3 cash, `data/divisions_config.json`). Divisions are paid in id order; one the stock cannot cover is unpaid, costs nothing (cash never goes negative) and loses `unpaid_upkeep_org_loss` (5) org that turn. The log and the military panel list unpaid divisions.
- Reinforcement: after income and upkeep, each in-supply division below its template strength regains up to 10 strength per turn, paying 10 people per point from its home city's recruit pool (then the nearest owned cities' pools; empty pools are skipped), in division id order until the pools run out. The people leave the city's population too. Out-of-supply divisions get nothing. Values are in `data/resources_config.json` and `data/cities_config.json`.
- The attacker never moves in. A city is captured only by moving into it when it is empty.
- Battles last several turns: an even fight takes 4 to 5 attacks to break a division's organization.
- All numbers are in `data/combat_config.json`. Each division has an equipment_level (default 1), unused for now.
- TBD: how a tech gap affects combat.

## POWs

- When a division surrenders, its remaining strength becomes POWs held by the captor (the nation that made the attack). Strength destroyed in combat does not become POWs.
- Each nation tracks the POWs it holds, by owner nation. The player's nation panel shows POWs held and POWs lost.
- POWs return to the owner's capital population (10 people per strength point) on peace, or immediately if the captor joins the owner's side.
- If a nation is eliminated, the POWs it holds and the POWs held from it stay recorded.
- Later: POW exchanges, POWs as bargaining chips, and a mistreatment option.

## First playable version

- One faction only, against simple AI
- Units: infantry, armor, and artillery
- Influence-based diplomacy

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
- **Research** is funded with cash. Parked.

### 4. Espionage [Planned, PROVISIONAL, parked]
- To be built as a modular piece.
- Control points work like Terra Invicta's.
- 3 starting agents (whether per player or per faction is TBD). Agents have Persuasion, Investigation, and Security stats.
- Ops are Investigate, Propaganda, Coup, Purge, Sabotage, and Protect.
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
- Strategic materials.