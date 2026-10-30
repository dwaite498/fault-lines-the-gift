extends Node2D
## Entry scene. Sets the window title; gameplay comes later.

const GAME_TITLE := "Fault Lines: The Gift"


func _ready() -> void:
	get_window().title = GAME_TITLE