# game_state_ui.gd
extends Control

@onready var player_label = $PlayerLabel
@onready var direction_indicator = $DirectionIndicator
@onready var cards_to_draw_label = $CardsToDrawLabel
@onready var player_highlights = []

# Keep track of player names
var player_names = []

func _ready():
	# Initialize player highlights array
	for i in range(4):
		var highlight = get_node_or_null("PlayerHighlight" + str(i+1))
		if highlight:
			player_highlights.append(highlight)
			highlight.visible = false

	# Set initial visibility
	hide_cards_to_draw()
	
	# Connect to window resize signals
	get_tree().root.size_changed.connect(func(): update_positions())

# Update all UI elements from game manager at once
func update_from_game_manager(current_turn, game_direction, cards_to_draw):
	# Update turn indicator
	set_current_player(current_turn + 1)  # +1 for player numbers starting at 1
	
	# Update direction indicator
	set_direction(game_direction)
	
	# Update cards to draw label
	if cards_to_draw > 0:
		show_cards_to_draw(cards_to_draw)
	else:
		hide_cards_to_draw()

# Update player names from session data
func set_player_names(names_array):
	player_names = names_array

func set_current_player(player_num: int):
	# Update the player label with name if available
	if player_num <= player_names.size() and player_names[player_num - 1] != "":
		player_label.text = player_names[player_num - 1] + "'s Turn"
	else:
		player_label.text = "Player " + str(player_num) + "'s Turn"
	
	# Highlight current player's area
	for i in range(player_highlights.size()):
		if player_highlights[i]:
			player_highlights[i].visible = (i + 1) == player_num

func set_direction(direction: int):
	# Rotate arrow based on direction
	var rotation_target = 0 if direction == 1 else PI
	var tween = create_tween()
	tween.tween_property(direction_indicator, "rotation", 
		rotation_target, 0.3).set_trans(Tween.TRANS_BOUNCE)

func show_cards_to_draw(amount: int):
	cards_to_draw_label.text = "Draw " + str(amount) + " cards"
	cards_to_draw_label.show()

func hide_cards_to_draw():
	cards_to_draw_label.hide()

# Make UI elements responsive to window size changes
func update_positions():
	var screen_size = get_viewport_rect().size
	
	# Center the player label
	if player_label:
		player_label.position = Vector2(screen_size.x / 2 - player_label.size.x / 2, 
			screen_size.y * 0.1)
	
	# Center the direction indicator
	if direction_indicator:
		direction_indicator.position = Vector2(screen_size.x / 2, 
			screen_size.y * 0.15)
			
	# Position the cards to draw label
	if cards_to_draw_label:
		cards_to_draw_label.position = Vector2(screen_size.x / 2 - cards_to_draw_label.size.x / 2, 
			screen_size.y * 0.2)
