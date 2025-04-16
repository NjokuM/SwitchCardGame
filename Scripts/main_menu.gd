extends Control

func _ready():
	# Start menu background music if not already playing
	MusicManager.play_menu_music()

func _on_play_pressed() -> void:
	SoundManager.play_card_select_sound()
	get_tree().change_scene_to_file("res://scene/play_menu.tscn")
	
func _on_rules_pressed() -> void:
	SoundManager.play_card_select_sound()
	# Load the rules scene
	get_tree().change_scene_to_file("res://scene/rules_screen.tscn")
	
func _on_exit_pressed() -> void:
	get_tree().quit()
