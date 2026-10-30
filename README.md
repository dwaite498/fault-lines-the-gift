# Fault Lines: The Gift

A turn-based, civ-style strategy game where nations and factions rise, clash, and negotiate as the world fractures around them.

## Running the game

1. Install [Godot 4.7.2 (stable)](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **Play** (F5). A blank window titled "Fault Lines: The Gift" opens.

From a terminal: `godot --path .`

## Folder map

| Folder | Purpose |
| --- | --- |
| `scenes/` | Godot scenes. `main.tscn` is the entry scene. |
| `scripts/` | GDScript code. `main.gd` drives the entry scene. |
| `scripts/map/` | Map generation, tiles, and terrain. |
| `scripts/nations/` | Nation state: cities, resources, territory. |
| `scripts/factions/` | Factions within or across nations. |
| `scripts/combat/` | Units fighting and battle resolution. |
| `scripts/diplomacy/` | Relations, treaties, and war declarations. |
| `scripts/events/` | Random and scripted world events. |
| `scripts/doom/` | The world-ending threat and its progress. |
| `scripts/ai/` | Computer-controlled players. |
| `scripts/turn/` | Turn order and the game loop. |
| `data/` | JSON definitions loaded at runtime (added later). |
| `data/factions/` | Faction definitions. |
| `data/units/` | Unit definitions. |
| `data/events/` | Event definitions. |
| `data/nations/` | Nation definitions. |
| `assets/` | Art, audio, and fonts. |
| `tests/` | Automated tests. |