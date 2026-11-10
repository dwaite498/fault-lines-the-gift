class_name MilitaryPanel
extends CanvasLayer

## Player's divisions and pending recruits. Toggled with M. Placed below the nation panel.

var panel := Panel.new()
var label := Label.new()
var swatch := MapView.make_swatch()
var factions: FactionRoster
var max_fortify := 3
const SIDE_WIDTH := 240.0

func _init() -> void:
	label.position = Vector2(22, 6)
	swatch.position = Vector2(8, 10)
	panel.add_child(swatch)
	panel.add_child(label)
	add_child(panel)
	panel.visible = false

func toggle() -> void:
	panel.visible = not panel.visible

func refresh(nation: int, roster: DivisionRoster, economy: NationEconomy, top: float) -> void:
	var lines: Array[String] = ["%s - Military (M to close)" % factions.name_of(nation), "Leader: %s" % factions.leader_of(nation)]
	for d in roster.divisions:
		if d.nation != nation:
			continue
		lines.append("#%d (%d,%d) str %.1f org %.1f mor %.2f %s fort %d/%d" % [
				d.id, d.hex.x, d.hex.y, d.strength, d.org, d.morale,
				"supplied" if d.supplied else "unsupplied", d.fortify_level, max_fortify])
	if lines.size() == 2:
		lines.append("No divisions")
	lines.append("People spent on reinforcement last turn: %d" % int(economy.reinforce_spent.get(nation, 0.0)))
	var cost: Dictionary = economy.config.recruit_cost
	lines.append("Recruit cost: cash %d, capacity %d, %d people from the city pool; %d turns training" % [
			int(cost.get("cash", 0)), int(cost.get("capacity", 0)),
			int(economy.city_rules.division_people_cost), int(economy.config.training_turns)])
	var ids := economy.pending.keys()
	ids.sort()
	for id in ids:
		if economy.pending[id].nation == nation:
			lines.append("city %d: %s" % [id, NationEconomy.queue_text(economy.pending[id])])
	label.text = "\n".join(lines)
	swatch.color = factions.color_of(nation)
	panel.size = label.get_minimum_size() + Vector2(30, 12)
	var viewport_width := get_viewport().get_visible_rect().size.x
	panel.position = Vector2(viewport_width - SIDE_WIDTH - panel.size.x - 8, top)
