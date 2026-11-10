class_name FactionTraits
extends RefCounted
## Faction trait modifiers (docs/specs/FACTION_TRAITS.md). Every number lives in
## data/factions.json (`global` and each faction's `faction_traits`); this is the single
## lookup the combat, economy, population, capture and movement code use.

## Nation index -> faction id. May be shared with HexMap.nation_factions.
var nation_factions := {}
## Faction id -> its faction_traits dictionary.
var by_faction := {}
## factions.json "global" block.
var globals := {}


## Fills the tables from the factions.json entries (`factions`), its `global` block and the
## nation -> faction id map. Replaces the dictionary contents in place, so shared references
## stay valid.
func load_factions(factions: Array, global_block: Dictionary, nation_ids: Dictionary) -> void:
	by_faction.clear()
	for f in factions:
		by_faction[str(f.id)] = f.get("faction_traits", {})
	globals = global_block
	nation_factions.clear()
	nation_factions.merge(nation_ids)


## The trait value for the nation's faction, or `default` if the nation has no faction or
## the faction does not have the trait.
func mod(nation: int, key: String, default: Variant = 0.0) -> Variant:
	var traits: Dictionary = by_faction.get(nation_factions.get(nation, ""), {})
	return traits.get(key, default)


func has_trait(nation: int, key: String) -> bool:
	return by_faction.get(nation_factions.get(nation, ""), {}).has(key)


## A factions.json `global` value.
func global_value(key: String, default: Variant = 0) -> Variant:
	return globals.get(key, default)


## How many cities of a flat `*_per_city` bonus count: at most flat_bonus_city_cap.
func counted_cities(city_count: int) -> int:
	return mini(city_count, int(global_value("flat_bonus_city_cap", city_count)))
