extends Node2D


enum GameState {
	DEALING,
	PLAYING,
	GAME_OVER
}

enum PowerCardEffect {
	NONE,
	DRAW_TWO,
	SKIP_TURN,
	REVERSE,
	DRAW_FIVE,
	PLAY_AGAIN,
	CANCEL_DRAW
}

var num_players: int  
@onready var deck = $"../Deck"
@onready var card_slot = $"../CardSlot"
@onready var play_label = $PlayLabel
var hands = []
var current_turn = 0
var selected_cards = []
var label_display_time = 2.0
var game_direction = 1  # 1 for clockwise, -1 for counter-clockwise
var cards_to_draw = 0   # For accumulating draw cards
var skip_turn_switch = false  # For Jack effect
var next_player_to_draw = 0  # Track who needs to draw cards
var current_state: GameState = GameState.DEALING
var can_draw_card: bool = true  # Controls if player can draw
var has_played_card: bool = false  # Tracks if player has played a card
var game_state_ui = null # Will be set in _ready

func _ready():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await get_tree().process_frame  
	num_players = GameSettings.num_players  
	print("Game started with", num_players, "players!")
	setup_play_label()
	setup_game_state_ui()
	start_game()

func setup_game_state_ui():
	game_state_ui = preload("res://scene/game_state_ui.tscn").instantiate()
	add_child(game_state_ui)
	update_game_state_ui()

func setup_play_label():
	if not has_node("PlayLabel"):
		var label = Label.new()
		label.name = "PlayLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(get_viewport_rect().size.x / 2 - 150, 50)
		label.custom_minimum_size = Vector2(300, 50)
		
		var style = LabelSettings.new()
		style.font_size = 24
		style.font_color = Color(1, 1, 1)
		label.label_settings = style
		
		add_child(label)
		play_label = label
	
	play_label.hide()

func show_play_notification(message: String):
	play_label.text = message
	play_label.show()
	
	var timer = get_tree().create_timer(label_display_time)
	timer.timeout.connect(func(): play_label.hide())

func start_game():
	current_state = GameState.DEALING
	if hands.is_empty():
		create_player_hands()
	print("Created hands. Now dealing cards...")
	await deck.deal_initial_cards()
	
	var first_card = draw_valid_starting_card()
	if first_card:
		card_slot.place_card(first_card)
	
	current_state = GameState.PLAYING
	print("Finished dealing cards. Starting turn for Player", current_turn + 1)
	update_game_state_ui()

func draw_valid_starting_card():
	var card = deck.draw_card_for_slot()
	while card and is_power_card(card):
		deck.return_card_to_deck(card)
		card = deck.draw_card_for_slot()
	return card

func is_power_card(card) -> bool:
	return get_card_effect(card) != PowerCardEffect.NONE

func get_card_effect(card) -> PowerCardEffect:
	match card.value:
		"2":
			if card.suit == "Hearts" and cards_to_draw == 5:
				return PowerCardEffect.DRAW_FIVE # Increases draw to 7
			return PowerCardEffect.DRAW_TWO
		"7":
			return PowerCardEffect.SKIP_TURN
		"8":
			return PowerCardEffect.REVERSE
		"King":
			if card.suit == "Hearts":
				return PowerCardEffect.DRAW_FIVE
		"5":
			if card.suit == "Hearts":
				return PowerCardEffect.CANCEL_DRAW
		"Jack":
			return PowerCardEffect.PLAY_AGAIN
	return PowerCardEffect.NONE

func create_player_hands():
	var screen_size = get_viewport_rect().size
	var margin = 100
	
	var positions = []
	match num_players:
		2:
			positions = [
				Vector2(screen_size.x / 2, screen_size.y - margin),
				Vector2(screen_size.x / 2, margin)
			]
		3:
			positions = [
				Vector2(screen_size.x / 2, screen_size.y - margin),
				Vector2(margin, screen_size.y / 2),
				Vector2(screen_size.x - margin, screen_size.y / 2)
			]
		4:
			positions = [
				Vector2(screen_size.x / 2, screen_size.y - margin),
				Vector2(screen_size.x / 2, margin),
				Vector2(margin, screen_size.y / 2),
				Vector2(screen_size.x - margin, screen_size.y / 2)
			]
		_:
			print("❌ Error: Unsupported number of players:", num_players)
			return
	
	for i in range(num_players):
		var hand_scene = preload("res://scene/hand.tscn")
		if not hand_scene:
			print("❌ Error: Could not load hand scene!")
			return
			
		var hand = hand_scene.instantiate()
		hand.is_player = true
		hand.position = positions[i]
		hand.player_position = i
		
		if num_players == 2:
			hand.rotation = PI if i == 1 else 0
		else:
			match i:
				0: hand.rotation = 0
				1: 
					if num_players == 3:
						hand.rotation = PI/2
					else:
						hand.rotation = PI
				2: 
					hand.rotation = -PI/2
				3: 
					hand.rotation = -PI/2
		
		add_child(hand)
		hands.append(hand)
		hand.update_visibility(true)
		print("✅ Hand added for Player", i + 1, "at", positions[i])

func draw_card_for_current_player():
	if not is_current_player_turn():
		show_play_notification("Not your turn to draw!")
		return null
		
	if not can_draw_card:
		show_play_notification("You've already drawn a card!")
		return null
		
	if has_played_card:
		show_play_notification("You've already played a card!")
		return null
		
	var drawn_card = deck.draw_card(current_turn)
	if drawn_card:
		can_draw_card = false
		show_play_notification("Player " + str(current_turn + 1) + " drew a card")
		
		if card_slot.can_place_card(drawn_card):
			return drawn_card
		else:
			await get_tree().create_timer(1.0).timeout
			switch_turn()
			
	return drawn_card

func select_card(card):
	if not is_current_player_turn():
		show_play_notification("Not your turn!")
		return

	if card in selected_cards:
		selected_cards.erase(card)
		card.deselect()
		print("Card deselected:", card.value, "of", card.suit)
	else:
		if can_select_card(card):
			selected_cards.append(card)
			card.select()
			print("Card selected:", card.value, "of", card.suit)
		else:
			print("Cannot select this card!")
			if card_slot.get_last_played_card():
				print("Card in slot:", card_slot.get_last_played_card().value)
			print("Trying to play:", card.value, "of", card.suit)

func can_select_card(card) -> bool:
	if selected_cards.is_empty():
		if not card_slot.can_place_card(card):
			return false
		if cards_to_draw > 0 and not can_play_power_card(card):
			return false
		return true
	
	return card.value == selected_cards[0].value

func can_play_power_card(card) -> bool:
	var effect = get_card_effect(card)
	
	if effect == PowerCardEffect.CANCEL_DRAW and cards_to_draw == 5:
		return true
		
	if cards_to_draw > 0 and effect != PowerCardEffect.DRAW_TWO:
		return false
		
	return true

func is_current_player_turn() -> bool:
	if current_state != GameState.PLAYING:
		return false
		
	var card_hand = null
	if not selected_cards.is_empty():
		card_hand = selected_cards[0].get_parent()
	
	var hand_index = -1
	for i in range(hands.size()):
		if hands[i] == card_hand:
			hand_index = i
			break
	
	return hand_index == current_turn

func play_selected_cards():
	if selected_cards.is_empty():
		return
		
	if not card_slot.can_place_card(selected_cards[0]):
		show_play_notification("Cannot play these cards!")
		return
	
	var played_cards_descriptions = []
	skip_turn_switch = false
	has_played_card = true
	
	for card in selected_cards:
		hands[current_turn].remove_card(card)
		card_slot.place_card(card)
		played_cards_descriptions.append(str(card.value) + " of " + str(card.suit))
		handle_power_card_effects(card)
	
	var played_cards_text = ", ".join(played_cards_descriptions)
	show_play_notification("Player " + str(current_turn + 1) + " played: " + played_cards_text)
	
	if hands[current_turn].hand.is_empty():
		current_state = GameState.GAME_OVER
		show_play_notification("Player " + str(current_turn + 1) + " wins!")
		return
	
	selected_cards.clear()
	if not skip_turn_switch:
		switch_turn()

func handle_power_card_effects(card):
	match get_card_effect(card):
		PowerCardEffect.DRAW_TWO:
			next_player_to_draw = (current_turn + game_direction) % num_players
			if next_player_to_draw < 0:
				next_player_to_draw = num_players - 1
			if card.suit == "Hearts" and cards_to_draw == 5:
				cards_to_draw = 7
				show_play_notification("Pick up increased to 7 cards!")
			else:
				cards_to_draw += 2
			print("Player ", next_player_to_draw + 1, " will draw ", cards_to_draw, " cards")
			
		PowerCardEffect.SKIP_TURN:
			current_turn = (current_turn + game_direction) % num_players
			if current_turn < 0:
				current_turn = num_players - 1
			show_play_notification("Skipping Player " + str(current_turn + 1) + "'s turn!")
			
		PowerCardEffect.REVERSE:
			game_direction *= -1
			show_play_notification("Game direction reversed!")
			
		PowerCardEffect.DRAW_FIVE:
			next_player_to_draw = (current_turn + game_direction) % num_players
			if next_player_to_draw < 0:
				next_player_to_draw = num_players - 1
			cards_to_draw = 5
			print("Player ", next_player_to_draw + 1, " will draw ", cards_to_draw, " cards")
			
		PowerCardEffect.CANCEL_DRAW:
			if cards_to_draw == 5:
				cards_to_draw = 0
				show_play_notification("King of Hearts effect cancelled!")
				
		PowerCardEffect.PLAY_AGAIN:
			skip_turn_switch = true
			show_play_notification("Player " + str(current_turn + 1) + " can play another card!")

func switch_turn():
	if cards_to_draw > 0:
		for i in range(cards_to_draw):
			var drawn_card = deck.draw_card(next_player_to_draw)
			if drawn_card:
				show_play_notification("Player " + str(next_player_to_draw + 1) + " drew a card")
		
		show_play_notification("Player " + str(next_player_to_draw + 1) + " drew " + str(cards_to_draw) + " cards!")
		cards_to_draw = 0
	
	current_turn = (current_turn + game_direction) % num_players
	if current_turn < 0:
		current_turn = num_players - 1
		
	can_draw_card = true
	has_played_card = false
		
	print("It's now Player", current_turn + 1, "'s turn!")
	update_game_state_ui()
	
	for i in range(num_players):
		hands[i].update_visibility(true)

func update_game_state_ui():
	if game_state_ui:
		game_state_ui.set_current_player(current_turn + 1)
		game_state_ui.set_direction(game_direction)
		if cards_to_draw > 0:
			game_state_ui.show_cards_to_draw(cards_to_draw)
		else:
			game_state_ui.hide_cards_to_draw()

func _on_card_clicked(card):
	select_card(card)

func _on_card_slot_clicked():
	play_selected_cards()
