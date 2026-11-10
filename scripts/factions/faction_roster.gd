class_name FactionRoster
extends RefCounted
## The factions in this game, one per nation index. Name, color and leader all come
## from data/factions.json; nothing else in the code defines a faction color.

const FACTIONS_PATH := "res://data/factions.json"
const NO_FACTION_COLOR := Color(0.5, 0.5, 0.5)

## All factions from factions.json, in file order.
var all: Array[Dictionary] = []
## Nation index -> faction dictionary. Nation 0 is the player's.
var assigned: Array[Dictionary] = []
## Set by pick() when player_faction was given but matched nothing ("" otherwise).
## The match is exact and case-sensitive on id or name; the player then gets a random faction.
var player_warning := ""


static func load_all(path := FACTIONS_PATH) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in JSON.parse_string(FileAccess.get_file_as_string(path)).factions:
		out.append(f)
	return out


## Picks `count` factions with at least one sea faction, deterministic for a seed.
## player_id (optional) forces the player's faction; it becomes nation 0.
## faction_seed < 0 uses the map seed.
static func from_config(cfg: Dictionary, path := FACTIONS_PATH) -> FactionRoster:
	var r := FactionRoster.new()
	r.all = load_all(path)
	var seed_value := int(cfg.get("faction_seed", -1))
	if seed_value < 0:
		seed_value = int(cfg.seed)
	r.pick(int(cfg.get("faction_count", 4)), seed_value, str(cfg.get("player_faction", "")))
	return r


func pick(count: int, seed_value: int, player_id := "") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 104729 + 7
	count = clampi(count, 1, all.size())
	var chosen: Array[Dictionary] = []
	var pool: Array[Dictionary] = all.duplicate()
	if player_id != "":
		for f in pool:
			if f.id == player_id or f.name == player_id:
				chosen.append(f)
	var forced := not chosen.is_empty()
	player_warning = ""
	if player_id != "" and not forced:
		var hint := ""
		for f in pool:
			if str(f.id).to_lower() == player_id.to_lower() or str(f.name).to_lower() == player_id.to_lower():
				hint = " (did you mean \"%s\"? ids and names are case-sensitive)" % f.id
		player_warning = "map_config player_faction \"%s\" matches no faction%s; picking a random player faction" % [player_id, hint]
		push_warning(player_warning)
	for f in chosen:
		pool.erase(f)
	# Guarantee a sea faction: take one at random unless already chosen.
	if count > 1 and not chosen.any(func(f: Dictionary) -> bool: return f.type == "sea"):
		var seas := pool.filter(func(f: Dictionary) -> bool: return f.type == "sea")
		var s: Dictionary = seas[rng.randi_range(0, seas.size() - 1)]
		chosen.append(s)
		pool.erase(s)
	_shuffle(pool, rng)
	while chosen.size() < count:
		chosen.append(pool.pop_back())
	# A forced player faction stays nation 0; otherwise nation 0 is a random draw.
	var rest: Array[Dictionary] = []
	rest.append_array(chosen.slice(1) if forced else chosen)
	_shuffle(rest, rng)
	assigned.clear()
	if forced:
		assigned.append(chosen[0])
	assigned.append_array(rest)


func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


## Nation indexes whose faction is a sea faction.
func sea_nations() -> Array[int]:
	var out: Array[int] = []
	for i in assigned.size():
		if assigned[i].type == "sea":
			out.append(i)
	return out


func has_nation(nation: int) -> bool:
	return nation >= 0 and nation < assigned.size()


## The faction id of a nation ("" if none).
func id_of(nation: int) -> String:
	return str(assigned[nation].id) if has_nation(nation) else ""


## Nation index -> faction id for every assigned nation.
func nation_ids() -> Dictionary:
	var out := {}
	for i in assigned.size():
		out[i] = str(assigned[i].id)
	return out


func name_of(nation: int) -> String:
	return str(assigned[nation].name) if has_nation(nation) else "Neutral"


func leader_of(nation: int) -> String:
	return str(assigned[nation].leader) if has_nation(nation) else ""


func color_of(nation: int) -> Color:
	return Color.html(assigned[nation].color) if has_nation(nation) else NO_FACTION_COLOR
