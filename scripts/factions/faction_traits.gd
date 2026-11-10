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


## 0-based position of the city among its nation's cities by id (the first
## flat_bonus_city_cap cities get the flat per-city bonuses).
func city_rank(hex_map: HexMap, city: Dictionary) -> int:
	var rank := 0
	for c in hex_map.cities:
		if c.nation == city.nation and int(c.id) < int(city.id):
			rank += 1
	return rank


## True if the city is one of the first flat_bonus_city_cap cities of its nation.
func within_city_cap(hex_map: HexMap, city: Dictionary) -> bool:
	return city_rank(hex_map, city) < int(global_value("flat_bonus_city_cap", 1 << 20))


## A sea city: on coast or shallow ocean (global sea_city_terrains).
func is_sea_city(hex_map: HexMap, city: Dictionary) -> bool:
	return global_value("sea_city_terrains", []).has(hex_map.growth_terrain_key(city))


## True if the city is one of the first flat_bonus_city_cap SEA cities of its nation.
func within_sea_city_cap(hex_map: HexMap, city: Dictionary) -> bool:
	if not is_sea_city(hex_map, city):
		return false
	var rank := 0
	for c in hex_map.cities:
		if c.nation == city.nation and int(c.id) < int(city.id) and is_sea_city(hex_map, c):
			rank += 1
	return rank < int(global_value("flat_bonus_city_cap", 1 << 20))
