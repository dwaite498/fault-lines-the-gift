class_name GameSession
extends RefCounted
## Hands the main menu's choices to the game scene (scenes/main.tscn). The menu fills
## `settings`; main.gd applies them over data/map_config.json when the game starts.
## With no settings (the game scene run directly, or tests) the config is used as is.

const SETUP_CONFIG_PATH := "res://data/map_config.json"

## {"player_faction": faction id, "seed": int, "ai_count": int}, or {} for the config defaults.
static var settings := {}
## True when the game scene should load the save slot instead of starting a new game.
static var load_requested := false


static func clear() -> void:
	settings = {}
	load_requested = false


## The setup screen limits from map_config.json "setup": {"min_ai", "max_ai", "default_ai"}.
static func setup_limits(path := SETUP_CONFIG_PATH) -> Dictionary:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	return cfg.get("setup", {"min_ai": 1, "max_ai": 3, "default_ai": 3})


## map_cfg with the menu's settings applied: seed, nation_count and faction_count (the
## player plus ai_count AI nations), player_faction. Returns a copy.
static func apply(map_cfg: Dictionary, s := settings) -> Dictionary:
	var cfg := map_cfg.duplicate(true)
	if s.is_empty():
		return cfg
	cfg["seed"] = int(s.seed)
	cfg["nation_count"] = int(s.ai_count) + 1
	cfg["faction_count"] = int(s.ai_count) + 1
	cfg["player_faction"] = str(s.player_faction)
	return cfg
