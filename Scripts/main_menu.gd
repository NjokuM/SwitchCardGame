extends Control

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/play_menu.tscn")
	
func _on_rules_pressed() -> void:
	# Load the rules scene
	get_tree().change_scene_to_file("res://scene/rules_screen.tscn")
	
func _on_exit_pressed() -> void:
	get_tree().quit()
