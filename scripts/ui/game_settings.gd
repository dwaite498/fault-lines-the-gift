class_name GameSettings
extends RefCounted
## Player settings kept between sessions in user://settings.cfg (ConfigFile). There was no settings
## file before Combat FX. Keys: display/reduce_motion, display/turn_report_auto_hide.

const PATH := "user://settings.cfg"


static func reduce_motion(path := PATH) -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return false
	return bool(cf.get_value("display", "reduce_motion", false))


static func set_reduce_motion(on: bool, path := PATH) -> void:
	var cf := ConfigFile.new()
	cf.load(path)  # keep any other keys
	cf.set_value("display", "reduce_motion", on)
	cf.save(path)


## Turn report: skip the panel on a turn with nothing to report (default on).
static func turn_report_auto_hide(path := PATH) -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return true
	return bool(cf.get_value("display", "turn_report_auto_hide", true))


static func set_turn_report_auto_hide(on: bool, path := PATH) -> void:
	var cf := ConfigFile.new()
	cf.load(path)  # keep any other keys
	cf.set_value("display", "turn_report_auto_hide", on)
	cf.save(path)
