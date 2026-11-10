class_name CityArt
extends RefCounted
## City sprite lookup and placeholder scaling (docs/specs/CITY_TIERS.md). Missing art never
## crashes the game and never leaves an empty tile.

const ART_DIR := "res://assets/cities/"


## Sprite keys to try, best first: base_<style>_<tier>, base_generic_<tier>, base_generic_base.
static func candidate_keys(style: String, tier: String) -> Array[String]:
	return ["base_%s_%s" % [style, tier], "base_generic_%s" % tier, "base_generic_base"]


## The first candidate key whose art `exists` (a Callable(key) -> bool, default: a PNG in
## assets/cities/), or "" if none does (the caller draws the placeholder dome).
static func resolve_key(style: String, tier: String, exists := Callable()) -> String:
	for key in candidate_keys(style, tier):
		var found := bool(exists.call(key)) if exists.is_valid() else ResourceLoader.exists(ART_DIR + key + ".png")
		if found:
			return key
	return ""


## Placeholder scale of the generic dome for a tier (the tier's sprite_scale in cities_config.json).
static func tier_scale(tiers: Array, tier: String) -> float:
	for t in tiers:
		if str(t.key) == tier:
			return float(t.get("sprite_scale", 1.0))
	return 1.0
