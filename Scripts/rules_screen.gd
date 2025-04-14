extends Control

# Store the scene we should return to after closing the rules
var return_scene: String = ""

func _ready():
	# If no return scene is set, default to main menu
	if return_scene == "":
		return_scene = "res://scene/main_menu.tscn"

# Called when the back button is pressed
func _on_back_button_pressed():
	get_tree().change_scene_to_file(return_scene)

# Call this to set where we should return after closing the rules
func set_return_scene(scene_path: String):
	return_scene = scene_path
