extends Control

signal menu_button_pressed

func _ready():
	# Make sure the button stays in the top left corner
	_update_position()
	
	# Connect to window resize signals for proper positioning
	get_tree().root.size_changed.connect(_update_position)

func _update_position():
	# Position in the top left corner with some margin
	var screen_size = get_viewport_rect().size
	position = Vector2(20, 20)

func _on_button_pressed():
	# Emit signal that the menu button was pressed
	emit_signal("menu_button_pressed")
	
	# You can also directly handle the menu navigation here if preferred
	_show_confirmation_dialog()

func _show_confirmation_dialog():
	# Create a confirmation dialog
	var dialog = ConfirmationDialog.new()
	dialog.title = "Return to Menu"
	dialog.dialog_text = "Are you sure you want to return to the main menu?\nAny ongoing game progress will be lost."
	dialog.size = Vector2(400, 150)

	# Position the dialog in the center of the screen
	var screen_size = get_viewport_rect().size
	dialog.position = Vector2(
		screen_size.x / 2 - dialog.size.x / 2,
		screen_size.y / 2 - dialog.size.y / 2
	)

	# Connect dialog signals
	dialog.confirmed.connect(_return_to_main_menu)
	dialog.canceled.connect(func(): dialog.queue_free())

	# Add dialog to the scene
	add_child(dialog)
	dialog.popup()

func _return_to_main_menu():
	# Clean up any network connections if needed
	var network = get_node_or_null("/root/NetworkManager")
	if network and network.multiplayer and network.multiplayer.has_multiplayer_peer():
		network.close_connection()

	# Return to main menu
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")
