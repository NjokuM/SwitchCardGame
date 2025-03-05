extends Control

func _on_multiplayer_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/multiplayer_menu.tscn")

func _on_local_button_pressed() -> void:
	pass # Replace with function body.


func _on_play_cpu_button_pressed() -> void:
		get_tree().change_scene_to_file("res://scene/select_player_num_menu.tscn")
