extends Control

# Reference to the game screen that opened this popup
var opener_scene = null

func _ready():
	# Center the popup on screen
	var screen_size = get_viewport_rect().size
	position = Vector2(screen_size.x / 2 - size.x / 2, screen_size.y / 2 - size.y / 2)
	
	# Connect to window resize to maintain centering
	get_tree().root.size_changed.connect(center_popup)
	
	# Make the popup visible at the start
	visible = true
	
	# Ensure the popup appears on top of other elements
	z_index = 1000

func center_popup():
	var screen_size = get_viewport_rect().size
	position = Vector2(screen_size.x / 2 - size.x / 2, screen_size.y / 2 - size.y / 2)

func _on_close_button_pressed():
	# Hide the popup
	queue_free()
