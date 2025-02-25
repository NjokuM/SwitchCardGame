# game_state_ui.gd

extends Control

@onready var player_label = $PlayerLabel
@onready var direction_indicator = $DirectionIndicator
@onready var cards_to_draw_label = $CardsToDrawLabel

func set_current_player(player_num: int):
	player_label.text = "Player " + str(player_num) + "'s Turn"
	
	# Highlight current player's area
	for i in range(4):
		var player_highlight = get_node_or_null("PlayerHighlight" + str(i+1))
		if player_highlight:
			player_highlight.visible = (i + 1) == player_num

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
