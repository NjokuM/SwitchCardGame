extends Control

func _on_two_button_pressed() -> void:
	GameSettings.num_players = 2
	print("Number of players set to:", GameSettings.num_players)
	_load_main_scene()

func _on_three_button_pressed() -> void:
	GameSettings.num_players = 3
	print("Number of players set to:", GameSettings.num_players)
	_load_main_scene()

func _on_four_button_pressed() -> void:
	GameSettings.num_players = 4
	print("Number of players set to:", GameSettings.num_players)
	_load_main_scene()

func _load_main_scene():
	get_tree().change_scene_to_file("res://scene/main.tscn")
