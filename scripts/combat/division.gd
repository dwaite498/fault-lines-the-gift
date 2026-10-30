class_name Division
extends RefCounted
## One military division. Plain data; rules live in DivisionRoster.

var id: int
var nation: int
var hex: Vector2i
var strength: float
var org: float
var max_org: float
## Multiplier for how fast organization recovers.
var morale: float
var attack: float
var defense: float
## Move points per turn. Each step costs the entered hex's move_cost.
var move: int
var moves_left: int
## True once it has moved this turn; it can keep moving but not attack or fortify.
var has_moved := false
var supplied := true
var fortify_level := 0
## True if it attacked or was attacked this turn (blocks org recovery).
var in_combat := false
## Equipment tier. Unused for now.
var equipment_level := 1


static func from_template(new_id: int, owner_nation: int, start_hex: Vector2i,
		template: Dictionary) -> Division:
	var d := Division.new()
	d.id = new_id
	d.nation = owner_nation
	d.hex = start_hex
	d.strength = float(template.strength)
	d.org = float(template.organization)
	d.max_org = d.org
	d.morale = float(template.morale)
	d.attack = float(template.attack)
	d.defense = float(template.defense)
	d.move = int(template.move)
	d.moves_left = d.move
	d.equipment_level = int(template.get("equipment_level", 1))
	return d