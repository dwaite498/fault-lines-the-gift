class_name Attitude
extends RefCounted
## Faction affinity and attitude (docs/specs/FACTION_TRAITS.md, "Affinity and attitude").
## Each faction has integer axes (order, faith, planet) from -2 to +2. A faction's base
## attitude to another is -(sum of the axis gaps), plus global.rival_attitude if the other is
## in its rivals list (so it is not symmetric). The captor's atrocity record then lowers it:
## every reputation_event it caused counts HexMap.reputation_weight_to(observer, event)
## (atrocity_weight x the observer's atrocity_sensitivity for an event the observer calls an
## atrocity, else the base severity) x global.reputation_attitude_scale.

const AXES := ["order", "faith", "planet"]

## Faction id -> {"order", "faith", "planet"}.
var axes := {}
## Faction id -> Array of faction ids it counts as rivals.
var rivals := {}
var rival_attitude := 0.0
var reputation_scale := 1.0
## factions.json "ai" block (attitude_weight, distance_weight, ...).
var rules := {}
## Nation index -> faction id.
var nation_factions := {}


func load_factions(factions: Array, global_block: Dictionary, ai_block: Dictionary, nation_ids: Dictionary) -> void:
	axes.clear()
	rivals.clear()
	var names := {}
	for f in factions:
		names[str(f.id)] = str(f.get("name", f.id))
		if f.has("axes"):
			axes[str(f.id)] = f.axes
	for f in factions:
		var ids: Array = []
		for r in f.get("rivals", []):
			for id in names:
				if str(r) == id or str(r) == names[id]:
					ids.append(id)
		rivals[str(f.id)] = ids
	rival_attitude = float(global_block.get("rival_attitude", 0.0))
	reputation_scale = float(global_block.get("reputation_attitude_scale", 1.0))
	rules = ai_block
	nation_factions.clear()
	nation_factions.merge(nation_ids)


## True once axes are loaded (the AI target weighting needs them).
func enabled() -> bool:
	return not axes.is_empty()


## Axis-and-rival attitude of faction a toward faction b (0 for an unknown faction).
func base(a: String, b: String) -> float:
	if not axes.has(a) or not axes.has(b):
		return 0.0
	var gap := 0
	for axis in AXES:
		gap += absi(int(axes[a].get(axis, 0)) - int(axes[b].get(axis, 0)))
	var value := -float(gap)
	if rivals.get(a, []).has(b):
		value += rival_attitude
	return value


## Attitude of nation a toward nation b: the base attitude minus b's atrocity record as
## a's faction sees it. Events b caused against anyone count (a is the observer).
func between(hex_map: HexMap, a: int, b: int) -> float:
	var fa: String = nation_factions.get(a, "")
	var value := base(fa, str(nation_factions.get(b, "")))
	for e in hex_map.reputation.events:
		if int(e.actor) == b:
			value -= hex_map.reputation_weight_to(fa, e) * reputation_scale
	return value
