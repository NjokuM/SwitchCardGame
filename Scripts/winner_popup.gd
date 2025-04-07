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

func _on_play_again_button_pressed():
	visible = false
	emit_signal("play_again_pressed")

func _on_main_menu_button_pressed():
	visible = false
	emit_signal("main_menu_pressed")
