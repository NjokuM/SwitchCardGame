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
var waiting_for_defense = false  # Flag for when waiting for 2 or 5 defense
var waiting_for_suit_selection = false  # Flag for when waiting for Ace suit selection
var chosen_suit = ""  # For storing the chosen suit after an Ace is played
var current_attacker = -1  # Track who played the attacking card

func _ready():
	if not InputMap.has_action("draw_card"):
		InputMap.add_action("draw_card")
		
		# Associate it with the 'D' key
		var event = InputEventKey.new()
		event.keycode = KEY_D
		InputMap.action_add_event("draw_card", event)
	
	
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
		
		# Position in the center of the screen instead of the top
		var screen_size = get_viewport_rect().size
		label.position = Vector2(screen_size.x / 2 + 200, screen_size.y / 2 - 50)
		label.custom_minimum_size = Vector2(400, 100)  # Make it larger
		
		# Style the label to be more visible
		var style = LabelSettings.new()
		style.font_size = 32  # Larger font
		style.font_color = Color(1, 1, 1)  # White text
		style.outline_size = 2  # Add outline
		style.outline_color = Color(0, 0, 0)  # Black outline
		style.shadow_size = 5  # Add shadow
		style.shadow_color = Color(0, 0, 0, 0.5)  # Semi-transparent black shadow
		label.label_settings = style
		
		# Add a background panel
		var panel = ColorRect.new()
		panel.color = Color(0.1, 0.1, 0.1, 0.7)  # Semi-transparent dark background
		panel.size = Vector2(400, 100)
		panel.position = Vector2(0, 0)
		label.add_child(panel)
		panel.z_index = -1  # Make sure it's behind the text
		
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
	print("DEBUG: Attempting to draw for Player " + str(current_turn + 1))
	
	# Pass the current_turn to draw_card
	var drawn_card = deck.draw_card(current_turn)
	
	if drawn_card:
		show_play_notification("Player " + str(current_turn + 1) + " drew a card")
		# Switch turn AFTER drawing is complete
		switch_turn()
	
	return drawn_card

func select_card(card):
	if not is_current_player_turn() or not card:
		print("Not current player's turn or invalid card")
		return
		
	# Check if card has required properties
	if not ("value" in card) or not ("suit" in card):
		print("❌ Card missing required properties in select_card")
		return
	
	# Make sure the card is actually in the current player's hand
	if not hands[current_turn].hand.has(card):
		print("❌ Attempted to select a card not in current player's hand")
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
			
			# Safely access last played card properties
			var last_card = card_slot.get_last_played_card()
			if last_card and "value" in last_card:
				print("Card in slot:", last_card.value)
			
			# Now we can safely print the card properties
			print("Trying to play:", card.value, "of", card.suit)

func can_select_card(card) -> bool:
	# First card must match the card in slot
	if selected_cards.is_empty():
		var can_place = card_slot.can_place_card(card)
		print("Checking if can place card:", can_place)
		return can_place
	
	# Only do value matching when we have multiple cards
	# Make sure all cards have the required properties
	if not card or not ("value" in card):
		print("❌ Card being checked is missing required properties")
		return false
	
	if not selected_cards[0] or not ("value" in selected_cards[0]):
		print("❌ First selected card is missing required properties")
		return false
	
	# Now it's safe to compare the values
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
				
			# Check if next player has a 2 to defend
			if has_card_in_hand(next_player_to_draw, "2"):
				waiting_for_defense = true
				current_attacker = current_turn
				cards_to_draw = 2
				show_play_notification("Player " + str(next_player_to_draw + 1) + " can play a 2 to defend!")
				# Don't switch turns yet - wait for defense or skip
			else:
				cards_to_draw = 2
				print("Player ", next_player_to_draw + 1, " will draw ", cards_to_draw, " cards")
			
		"7":
			# Skip next player's turn
			current_turn = (current_turn + game_direction) % num_players
			if current_turn < 0:
				current_turn = num_players - 1
			show_play_notification("Skipping Player " + str(current_turn + 1) + "'s turn!")
			
		"8":
			if num_players == 2:
				# In 2-player mode, 8 works like 7 (skip/play again)
				show_play_notification("Player " + str(current_turn + 1) + " plays again!")
				skip_turn_switch = true  # Don't switch turns
			else:
				# In 3+ player mode, reverse direction
				game_direction *= -1
				show_play_notification("Game direction reversed!")
				
		"Ace":
			# Prompt for suit selection
			waiting_for_suit_selection = true
			skip_turn_switch = true  # Don't switch turns until suit is selected
			show_suit_selection_ui()
			
		"King":
			if card.suit == "Hearts":
				next_player_to_draw = (current_turn + game_direction) % num_players
				if next_player_to_draw < 0:
					next_player_to_draw = num_players - 1
					
				# Check if next player has a 5 of Hearts or 2 of Hearts to defend
				if has_card_in_hand(next_player_to_draw, "5", "Hearts") or has_card_in_hand(next_player_to_draw, "2", "Hearts"):
					waiting_for_defense = true
					current_attacker = current_turn
					cards_to_draw = 5
					show_play_notification("Player " + str(next_player_to_draw + 1) + " can defend against King of Hearts!")
					# Don't switch turns yet - wait for defense or skip
				else:
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

# Add this function to check if a player has a specific card
func has_card_in_hand(player_index, value, suit = null):
	for card in hands[player_index].hand:
		if card.value == value:
			if suit == null or card.suit == suit:
				return true
	return false

# Function to handle defending against a 2 or King of Hearts
func defend_against_attack(card = null):
	if not waiting_for_defense:
		return
		
	if card:
		# Player is defending with a card
		if card.value == "2":
			# Add 2 more cards to draw
			cards_to_draw += 2
			show_play_notification("Player " + str(current_turn + 1) + " defended! Next player draws " + str(cards_to_draw))
			
			# Remove the card from hand
			hands[current_turn].remove_card(card)
			card_slot.place_card(card)
			
		elif card.value == "5" and card.suit == "Hearts" and cards_to_draw == 5:
			# Cancel King of Hearts effect
			cards_to_draw = 0
			show_play_notification("King of Hearts effect cancelled!")
			
			# Remove the card from hand
			hands[current_turn].remove_card(card)
			card_slot.place_card(card)
			
		elif card.value == "2" and card.suit == "Hearts" and cards_to_draw == 5:
			# Convert 5 to 7 cards
			cards_to_draw = 7
			show_play_notification("Pick up increased to 7 cards!")
			
			# Remove the card from hand
			hands[current_turn].remove_card(card)
			card_slot.place_card(card)
	else:
		# Player is not defending (skipped)
		show_play_notification("Player " + str(current_turn + 1) + " draws " + str(cards_to_draw) + " cards")
	
	# Reset defense state
	waiting_for_defense = false
	current_attacker = -1
	
	# Continue the game
	switch_turn()

# Function to show suit selection UI for Ace
func show_suit_selection_ui():
	show_play_notification("Select a suit: Hearts, Diamonds, Clubs, or Spades")
	
	# Create buttons for suit selection
	var suits = ["Hearts", "Diamonds", "Clubs", "Spades"]
	var button_container = HBoxContainer.new()
	button_container.name = "SuitButtons"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	for suit in suits:
		var button = Button.new()
		button.text = suit
		button.custom_minimum_size = Vector2(100, 50)
		button.pressed.connect(func(): select_suit(suit))
		button_container.add_child(button)
	
	# Position the buttons at center screen
	var screen_size = get_viewport_rect().size
	button_container.position = Vector2(screen_size.x / 2 - 200, screen_size.y / 2 + 50)
	
	add_child(button_container)

# Function to handle suit selection
func select_suit(suit):
	chosen_suit = suit
	show_play_notification("Suit changed to " + suit)
	
	# Update the Ace card to show chosen suit
	var ace_card = card_slot.get_last_played_card()
	if ace_card:
		ace_card.set_chosen_suit(suit)
	
	# Remove the suit selection UI
	if has_node("SuitButtons"):
		get_node("SuitButtons").queue_free()
	
	# Reset state and continue game
	waiting_for_suit_selection = false
	skip_turn_switch = false
	switch_turn()

func switch_turn():
	# Apply any accumulated card draws to the next player
	
	if waiting_for_defense or waiting_for_suit_selection:
		return
		
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
