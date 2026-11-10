class_name Victory
extends RefCounted
## End-of-game rules (checked at the end of each turn): a nation holding at least
## victory.domination_share (map_config.json) of all nation-owned cities wins by domination.
## Natives (neutral nations) and alien sites do not count, neither as owners nor in the total.
## The player loses on elimination (no cities left), or when an AI nation dominates.

const CONFIG_PATH := "res://data/map_config.json"
const DEFAULT_SHARE := 0.85


## map_config.json "victory": {"domination_share"}; the default if the key is missing.
static func domination_share(path := CONFIG_PATH) -> float:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	return float(cfg.get("victory", {}).get("domination_share", DEFAULT_SHARE))


## Cities that count: not owned by an excluded (neutral/native) nation, not flagged
## "native" or "alien_site". Returns {nation: count}.
static func counted_cities(m: HexMap, excluded: Array = []) -> Dictionary:
	var counts := {}
	for c in m.cities:
		if excluded.has(int(c.nation)) or c.get("native", false) or c.get("alien_site", false):
			continue
		counts[int(c.nation)] = int(counts.get(int(c.nation), 0)) + 1
	return counts


## The nation holding at least `share` of the counted cities, or -1.
static func dominating_nation(m: HexMap, share: float, excluded: Array = []) -> int:
	var counts := counted_cities(m, excluded)
	var total := 0
	for n in counts:
		total += int(counts[n])
	if total == 0:
		return -1
	var keys: Array = counts.keys()
	keys.sort()
	for n in keys:
		if float(counts[n]) / float(total) >= share - 0.000001:
			return int(n)
	return -1


## {"over": bool, "result": "victory" | "defeat" | "", "reason": "domination" | "elimination" | "",
## "winner": nation or -1}. Elimination is checked first.
static func check(m: HexMap, player: int, share: float, excluded: Array = []) -> Dictionary:
	var counts := counted_cities(m, excluded)
	if int(counts.get(player, 0)) == 0:
		return {"over": true, "result": "defeat", "reason": "elimination", "winner": dominating_nation(m, share, excluded)}
	var winner := dominating_nation(m, share, excluded)
	if winner == player:
		return {"over": true, "result": "victory", "reason": "domination", "winner": winner}
	if winner >= 0:
		return {"over": true, "result": "defeat", "reason": "domination", "winner": winner}
	return {"over": false, "result": "", "reason": "", "winner": -1}
