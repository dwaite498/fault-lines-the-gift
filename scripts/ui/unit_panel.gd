class_name UnitPanel
extends CanvasLayer
## Simple on-screen info panel for the selected division. Hidden when nothing is selected.

var panel := Panel.new()
var label := Label.new()
var max_fortify := 3
var flank_per_hex := 0.15
var flank_min_mult := 0.4


func _init() -> void:
	panel.position = Vector2(8, 8)
	panel.size = Vector2(230, 200)
	label.position = Vector2(8, 6)
	panel.add_child(label)
	add_child(panel)
	panel.visible = false


## Shows d's current stats, or hides the panel when d is null.
func refresh(d: Division, hex_map: HexMap) -> void:
	panel.visible = d != null
	if d == null:
		label.text = ""
		return
	var terrain_name: String = hex_map.terrain[d.hex]
	var acted := d.moves_left < d.move
	label.text = "\n".join([
		"Nation: %d" % d.nation,
		"Strength: %.1f" % d.strength,
		"Org: %.1f / %.1f" % [d.org, d.max_org],
		"Morale: %.2f" % d.morale,
		"Attack: %.1f" % d.attack,
		"Defense: %.1f" % d.defense,
		"Fortify: %d/%d" % [d.fortify_level, max_fortify],
		"Moves left: %d / %d" % [d.moves_left, d.move],
		"Acted this turn: %s" % ("yes" if acted else "no"),
		"Terrain: %s (def x%.2f)" % [terrain_name, float(hex_map.terrain_of(d.hex).defense_mult)],
	])
	## Current flank penalty from the distinct hexes that attacked d this turn.
	var penalty := 1.0 - DivisionRoster.flank_mult_for(d.attacked_from.size(), flank_per_hex, flank_min_mult)
	if not d.supplied:
		label.text += "\nOut of supply"
	if penalty > 0.0:
		label.text += "\nFlanked: -%d%% def" % roundi(penalty * 100.0)
	panel.size = label.get_minimum_size() + Vector2(16, 12)
