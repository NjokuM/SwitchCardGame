extends Control

func _on_multiplayer_button_pressed() -> void:
	SoundManager.play_card_select_sound()
	get_tree().change_scene_to_file("res://scene/multiplayer_menu.tscn")

func _on_play_cpu_button_pressed() -> void:
	SoundManager.play_card_select_sound()
	get_tree().change_scene_to_file("res://scene/select_player_num_menu.tscn")

func _on_back_button_pressed() -> void:
	SoundManager.play_card_select_sound()
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")
