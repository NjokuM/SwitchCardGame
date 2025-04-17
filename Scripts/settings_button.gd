extends Button

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	SoundManager.play_card_select_sound()
	
	# Load the settings scene
	var settings_scene = load("res://scene/settings_screen.tscn").instantiate()
	
	# Set the return scene to the current scene
	if settings_scene.has_method("set_return_scene"):
		var current_scene_path = get_tree().current_scene.scene_file_path
		settings_scene.set_return_scene(current_scene_path)
	
	# Change to settings scene
	get_tree().root.add_child(settings_scene)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = settings_scene
