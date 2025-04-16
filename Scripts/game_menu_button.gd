extends Control

@onready var popup_menu = $MenuPopup

func _ready():
	popup_menu.hide()

# Handle your existing button press function
func _on_button_pressed():
	# Toggle the popup menu
	if popup_menu.visible:
		popup_menu.hide()
	else:
		popup_menu.show()

# New functions to handle the menu options
func _on_rules_button_pressed():
	# Hide the menu popup
	popup_menu.hide()
	SoundManager.play_card_select_sound()
	
	# Create the rules popup as a child of the current scene
	var rules_popup = load("res://scene/rules_popup.tscn").instantiate()
	
	# Get the main scene (usually the root node)
	var main_scene = get_tree().current_scene
	main_scene.add_child(rules_popup)
	
	
	# Rules popup will center itself in its _ready function

func _on_resume_button_pressed():
	# Hide the popup menu
	SoundManager.play_card_select_sound()
	popup_menu.hide()
	

func _on_main_menu_button_pressed():
	# Return to main menu
	SoundManager.play_card_select_sound()
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")
