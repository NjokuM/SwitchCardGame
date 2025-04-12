extends Control

@onready var play_label = $PlayLabelPanel/PlayLabel
@onready var turn_label = $TurnLabelPanel/TurnLabel

# Called when the node enters the scene tree for the first time
func _ready():
	# Connect to window resize signals for proper positioning
	get_tree().root.size_changed.connect(reposition_labels)
	
	# Initial positioning
	reposition_labels()

# Positions the labels relative to the card slot and deck
func reposition_labels():
	var screen_size = get_viewport_rect().size
	var center_x = screen_size.x / 2
	var center_y = screen_size.y / 2
	
	# Position above card slot and deck
	$PlayLabelPanel.position.x = center_x - $PlayLabelPanel.size.x / 2
	$PlayLabelPanel.position.y = center_y - 250
	
	# Position below card slot and deck
	$TurnLabelPanel.position.x = center_x - $TurnLabelPanel.size.x / 2
	$TurnLabelPanel.position.y = center_y + 250

# Update the play label with information about the played card
func update_play_label(player_name: String, card_value: String, card_suit: String, effect: String = ""):
	var message = player_name + " played " + card_value + " of " + card_suit
	
	# Add effect information if available
	if effect != "":
		message += " - " + effect
	
	play_label.text = message

# Update the turn label to show whose turn it is
func update_turn_label(player_name: String, is_local_player: bool = false):
	if is_local_player:
		turn_label.text = "YOUR TURN"
	else:
		turn_label.text = player_name + "'S TURN"

# Show a specific effect message without card information
# Useful for actions like drawing cards or skipping
func show_effect_message(message: String):
	play_label.text = message
