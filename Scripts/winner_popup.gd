extends Control

signal play_again_pressed
signal main_menu_pressed

@onready var winner_label = $Panel/VBoxContainer/WinnerLabel

# Called when the node enters the scene tree for the first time
func _ready():
	# Hide by default
	visible = true

# Show the winner popup with player info
func show_winner(player_number):
	# Update winner text
	winner_label.text = "PLAYER " + str(player_number) + " WINS!"
	
	# Show the popup
	visible = true
	# Connect to window resize to maintain centered position
	get_tree().root.size_changed.connect(_center_popup)
	
	# Initial centering
	_center_popup()

func _on_play_again_button_pressed():
	visible = false
	emit_signal("play_again_pressed")

func _on_main_menu_button_pressed():
	visible = false
	emit_signal("main_menu_pressed")

func _center_popup():
	# Force the panel to center regardless of game state
	var panel = $Panel
	var screen_size = get_viewport_rect().size
	position = Vector2(screen_size.x / 2, screen_size.y / 2)
	
	# Also ensure the overlay covers the entire screen
	$Overlay.size = screen_size
