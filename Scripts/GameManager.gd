extends Node2D

var num_players: int  
@onready var deck = $"../Deck"
@onready var card_slot = $"../CardSlot"
@onready var play_label = $PlayLabel
var hands = []
var current_turn = 0
var selected_cards = []
var label_display_time = 2.0
var game_direction = 1  # 1 for clockwise, -1 for counter-clockwise
var cards_to_draw = 0   # For accumulating draw cards (e.g., multiple 2s)
var skip_turn_switch = false  # For Jack effect
var next_player_to_draw = 0  # Track who needs to draw cards

func _ready():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await get_tree().process_frame  
	num_players = GameSettings.num_players  
	print("Game started with", num_players, "players!")
	setup_play_label()
	start_game()

func setup_play_label():
	# Create label if it doesn't exist
	if not has_node("PlayLabel"):
		var label = Label.new()
		label.name = "PlayLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Position in the upper middle of the screen
		label.position = Vector2(get_viewport_rect().size.x / 2 - 150, 50)
		label.custom_minimum_size = Vector2(300, 50)  # Give it some minimum size
		
		# Style the label
		var style = LabelSettings.new()
		style.font_size = 24
		style.font_color = Color(1, 1, 1)  # White text
		label.label_settings = style
		
		add_child(label)
		play_label = label
	
	# Initially hide the label
	play_label.hide()

func show_play_notification(message: String):
	play_label.text = message
	play_label.show()
	
	# Create timer to hide the label
	var timer = get_tree().create_timer(label_display_time)
	timer.timeout.connect(func(): play_label.hide())

func start_game():
	if hands.is_empty():
		create_player_hands()
	print("Created hands. Now dealing cards...")
	await deck.deal_initial_cards()
	
	var first_card = draw_valid_starting_card()
	if first_card:
		card_slot.place_card(first_card)
	print("Finished dealing cards. Starting turn for Player", current_turn + 1)

func draw_valid_starting_card():
	var card = deck.draw_card_for_slot()
	while card and is_power_card(card):
		# Put power card back and draw another
		deck.return_card_to_deck(card)
		card = deck.draw_card_for_slot()
	return card

func is_power_card(card) -> bool:
	# Check if card is a power card
	if card.value in ["2", "7", "8", "Ace", "Jack"]:
		return true
	if card.value == "King" and card.suit == "Hearts":
		return true
	if card.value == "5" and card.suit == "Hearts":
		return true
	if card.value == "2" and card.suit == "Hearts":
		return true
	return false

func create_player_hands():
	var screen_size = get_viewport_rect().size
	var margin = 100  # Margin from screen edges
	
	# Calculate positions based on number of players
	var positions = []
	match num_players:
		2:
			positions = [
				Vector2(screen_size.x / 2, screen_size.y - margin),  # Bottom
				Vector2(screen_size.x / 2, margin)  # Top
			]
		3:
			positions = [
				Vector2(screen_size.x / 2, screen_size.y - margin),  # Bottom
				Vector2(margin, screen_size.y / 2),  # Left
				Vector2(screen_size.x - margin, screen_size.y / 2)  # Right
			]
		4:
			positions = [
				Vector2(screen_size.x / 2, screen_size.y - margin),  # Bottom
				Vector2(screen_size.x / 2, margin),  # Top
				Vector2(margin, screen_size.y / 2),  # Left
				Vector2(screen_size.x - margin, screen_size.y / 2)  # Right
			]
		_:
			print("❌ Error: Unsupported number of players:", num_players)
			return
	
	# Create hands at calculated positions
	for i in range(num_players):
		var hand_scene = preload("res://scene/hand.tscn")
		if not hand_scene:
			print("❌ Error: Could not load hand scene!")
			return
			
		var hand = hand_scene.instantiate()
		hand.is_player = true  # Make all hands playable for testing
		hand.position = positions[i]
		hand.player_position = i
		
		# Set rotation based on position and number of players
		if num_players == 2:
			hand.rotation = PI if i == 1 else 0
		else:
			match i:
				0: hand.rotation = 0  # Bottom player
				1: 
					if num_players == 3:
						hand.rotation = PI/2  # Left player
					else:
						hand.rotation = PI  # Top player in 4-player game
				2: 
					hand.rotation = -PI/2  # Right player
				3: 
					hand.rotation = -PI/2  # Right player in 4-player game
		
		add_child(hand)
		hands.append(hand)
		hand.update_visibility(false)  # Always show all hands for testing
		print("✅ Hand added for Player", i + 1, "at", positions[i])

func draw_card_for_current_player():
	# Only allow drawing if it's the player's actual turn
	if not is_current_player_turn():
		show_play_notification("Not your turn to draw!")
		return null
		
	var drawn_card = deck.draw_card(current_turn)
	if drawn_card:
		show_play_notification("Player " + str(current_turn + 1) + " drew a card")
		switch_turn()  # End turn after drawing
	return drawn_card

func select_card(card):
	if not is_current_player_turn() or not card:
		print("Not current player's turn or invalid card")
		return

	if card in selected_cards:
		# Deselect card
		selected_cards.erase(card)
		card.deselect()
		print("Card deselected:", card.value, "of", card.suit)
	else:
		# Check if card can be selected
		if can_select_card(card):
			selected_cards.append(card)
			card.select()
			print("Card selected:", card.value, "of", card.suit)
		else:
			print("Cannot select this card! Doesn't match current card in slot.")
			if card_slot.get_last_played_card():
				print("Card in slot:", card_slot.get_last_played_card().value)
			print("Trying to play:", card.value, "of", card.suit)

func can_select_card(card) -> bool:
	# First card must match the card in slot
	if selected_cards.is_empty():
		var can_place = card_slot.can_place_card(card)
		print("Checking if can place card:", can_place)
		return can_place
	
	# Additional cards must match the value of first selected card
	var value_matches = card.value == selected_cards[0].value
	print("Checking if value matches first selected card:", value_matches)
	return value_matches

func is_current_player_turn() -> bool:
	# For testing card playing, we still allow playing any hand
	# But for drawing, we need to respect the actual turn order
	if Input.is_action_just_pressed("draw_card"):  # If this is a draw action
		return true # Allow drawing only on current turn
	return true # Still allow playing from any hand for testing

func play_selected_cards():
	if selected_cards.is_empty():
		return
		
	if not card_slot.can_place_card(selected_cards[0]):
		print("Cannot play these cards!")
		return
	
	# Play all selected cards in order
	var played_cards_descriptions = []
	skip_turn_switch = false  # Reset the Jack effect
	
	for card in selected_cards:
		hands[current_turn].remove_card(card)
		card_slot.place_card(card)
		played_cards_descriptions.append(str(card.value) + " of " + str(card.suit))
		
		# Handle power card effects
		handle_power_card_effects(card)
	
	# Join the card descriptions with commas
	var played_cards_text = ", ".join(played_cards_descriptions)
	
	# Show notification of what was played
	var player_number = current_turn + 1
	var message = "Player " + str(player_number) + " played: " + played_cards_text
	show_play_notification(message)
	
	# Check for win condition
	if hands[current_turn].hand.is_empty():
		show_play_notification("Player " + str(current_turn + 1) + " wins!")
		# You might want to add game over handling here
	
	# Clear selection and only switch turns if we didn't play a Jack
	selected_cards.clear()
	if not skip_turn_switch:
		switch_turn()

func handle_power_card_effects(card):
	match card.value:
		"2":
			# Calculate next player considering game direction
			next_player_to_draw = (current_turn + game_direction) % num_players
			if next_player_to_draw < 0:
				next_player_to_draw = num_players - 1
			cards_to_draw += 2
			print("Player ", next_player_to_draw + 1, " will draw ", cards_to_draw, " cards")
		"7":
			# Skip next player's turn
			current_turn = (current_turn + game_direction) % num_players
			if current_turn < 0:
				current_turn = num_players - 1
			show_play_notification("Skipping Player " + str(current_turn + 1) + "'s turn!")
		"8":
			game_direction *= -1  # Reverse direction
			show_play_notification("Game direction reversed!")
		"King":
			if card.suit == "Hearts":
				next_player_to_draw = (current_turn + game_direction) % num_players
				if next_player_to_draw < 0:
					next_player_to_draw = num_players - 1
				cards_to_draw = 5
				print("Player ", next_player_to_draw + 1, " will draw ", cards_to_draw, " cards")
		"5":
			if card.suit == "Hearts" and cards_to_draw == 5:
				cards_to_draw = 0  # Cancel King of Hearts effect
				show_play_notification("King of Hearts effect cancelled!")
		"2":
			if card.suit == "Hearts" and cards_to_draw == 5:
				cards_to_draw = 7  # Convert 5 to 7 cards
				show_play_notification("Pick up increased to 7 cards!")
		"Jack":
			skip_turn_switch = true  # Don't end turn after playing a Jack
			show_play_notification("Player " + str(current_turn + 1) + " can play another card!")

func switch_turn():
	# Apply any accumulated card draws to the next player
	if cards_to_draw > 0:
		# Draw cards for the next player
		for i in range(cards_to_draw):
			var drawn_card = deck.draw_card(next_player_to_draw)
			if drawn_card:
				show_play_notification("Player " + str(next_player_to_draw + 1) + " drew a card")
		
		show_play_notification("Player " + str(next_player_to_draw + 1) + " drew " + str(cards_to_draw) + " cards!")
		cards_to_draw = 0
	
	# Update current turn based on game direction
	current_turn = (current_turn + game_direction) % num_players
	if current_turn < 0:
		current_turn = num_players - 1
		
	print("It's now Player", current_turn + 1, "'s turn!")
	
	# Keep all hands visible for testing
	for i in range(num_players):
		hands[i].update_visibility(true)

func _on_card_clicked(card):
	select_card(card)

func _on_card_slot_clicked():
	play_selected_cards()
