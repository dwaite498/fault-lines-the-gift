class_name CapturePopup
extends CanvasLayer
## Modal popup shown when the player captures a city (CAPTURE.md): one button per capture
## choice with its effects. All numbers in the text come from city_rules.capture.

## The player picked a choice: the option id ("annex", "occupy", ...).
signal chosen(option: String)

var root := Control.new()
var title := Label.new()
var buttons := {}  # option id -> Button
var _list := VBoxContainer.new()


func _init() -> void:
	layer = 20
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks clicks on the map behind
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.add_child(title)
	panel.add_child(_list)
	center.add_child(panel)
	root.add_child(center)
	add_child(root)
	root.visible = false


func is_open() -> bool:
	return root.visible


## Shows the choices for `city` (captured from `victim_name`). rules is city_rules.
func open(city: Dictionary, victim_name: String, rules: Dictionary) -> void:
	for b in buttons.values():
		b.get_parent().queue_free()
	buttons.clear()
	title.text = "City %d captured from %s: choose its fate" % [int(city.id), victim_name]
	for id in rules.capture.order:
		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = String(id).capitalize()
		b.custom_minimum_size = Vector2(110, 0)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_pressed.bind(String(id)))
		var desc := Label.new()
		desc.text = effect_text(String(id), rules)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(460, 0)
		row.add_child(b)
		row.add_child(desc)
		_list.add_child(row)
		buttons[id] = b
	root.visible = true


func _on_pressed(option: String) -> void:
	root.visible = false
	chosen.emit(option)


static func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


## One line describing an option's effects, from the config numbers.
static func effect_text(id: String, rules: Dictionary) -> String:
	var cap: Dictionary = rules.capture
	var o: Dictionary = cap.options[id]
	var lockout := int(cap.annexed_recruit_lockout_turns)
	var text := ""
	match id:
		"annex":
			text = "Lose %s of its people and %s of its infrastructure (rebuilds over %d turns). Recruit pool 0 and no recruiting for %d turns." % [
					_pct(o.pop_loss), _pct(o.infra_loss), int(rules.rebuild_turns), lockout]
		"occupy":
			text = "Lose %s of its people. Held at %s labor with recruit pool 0 and no training. It can be annexed with no further loss after %d turns." % [
					_pct(o.pop_loss), _pct(o.labor_mult), int(o.turns)]
		"plunder":
			text = "+%s cash per 1,000 people. Lose %s of its people and %s of its infrastructure, then it is annexed (no recruiting for %d turns)." % [
					String.num(float(o.cash_per_1000_people)), _pct(o.pop_loss), _pct(o.infra_loss), lockout]
		"reduce":
			text = "Lose %s of its people (they flee to the old owner) and %s of its infrastructure, then it is annexed (no recruiting for %d turns)." % [
					_pct(o.pop_loss), _pct(o.infra_loss), lockout]
		"raze":
			text = "Destroys the city and frees its land. %s of its people flee to the old owner's nearest city, the rest die. Razing a last city eliminates the nation." % _pct(o.refugee_share)
		"enslave":
			text = "Lose %s of its people. Its growth, recruit pool and training stay 0, but it makes %sx labor." % [
					_pct(o.pop_loss), String.num(float(o.labor_mult))]
		_:
			text = id
	if bool(o.atrocity):
		text += " ATROCITY (reputation severity %d)." % int(o.severity)
	elif int(o.severity) > 0:
		text += " Reputation severity %d." % int(o.severity)
	return text
