class_name GameSettings
extends RefCounted
## Player settings kept between sessions in user://settings.cfg (ConfigFile). There was no settings
## file before Combat FX; its only key so far is display/reduce_motion.

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
