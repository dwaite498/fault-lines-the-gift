class_name MilitaryPanel
extends CanvasLayer
## Player's divisions and pending recruits. Toggled with M. Placed below the nation panel.

var panel := Panel.new()
var label := Label.new()
var max_fortify := 3


func _init() -> void:
	label.position = Vector2(8, 6)
	panel.add_child(label)
	add_child(panel)
	panel.visible = false


func toggle() -> void:
	panel.visible = not panel.visible


func refresh(nation: int, roster: DivisionRoster, economy: NationEconomy, top: float) -> void:
	var lines: Array[String] = ["Military (M to close)"]
	for d in roster.divisions:
		if d.nation != nation:
			continue
		lines.append("#%d (%d,%d) str %.1f org %.1f mor %.2f %s fort %d/%d" % [
				d.id, d.hex.x, d.hex.y, d.strength, d.org, d.morale,
				"supplied" if d.supplied else "unsupplied", d.fortify_level, max_fortify])
	if lines.size() == 1:
		lines.append("No divisions")
	lines.append("Manpower spent on reinforcement last turn: %.1f" % float(economy.reinforce_spent.get(nation, 0.0)))
	var ids := economy.pending.keys()
	ids.sort()
	for id in ids:
		if economy.pending[id].nation == nation:
			lines.append("city %d: %s" % [id, NationEconomy.queue_text(economy.pending[id])])
	label.text = "\n".join(lines)
	panel.size = label.get_minimum_size() + Vector2(16, 12)
	panel.position = Vector2(1280 - panel.size.x - 8, top)