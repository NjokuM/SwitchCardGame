extends Node2D

var num_players: int  
@onready var deck = $"../Deck"
@onready var card_slot = $"../CardSlot"
@onready var play_label = $PlayLabel
@onready var game_status_panel = $"../GameStatusPanel"
@onready var game_ui_labels = $"../GameUILabels"
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
var defense_button_container = null
var last_card_button = null
var last_card_declared = false  # Track if player has declared last card
var jack_count = 0  # Track how many Jacks were played
var winner_popup = null

# Networking variables
var is_networked_game = false
var player_positions = {} # Maps peer_ids to player positions
var my_peer_id = 0

func _ready() -> void:
	await get_tree().process_frame  
	MusicManager.stop_for_game()
	
	# Check if we're coming from the network setup
	var network = get_node_or_null("/root/NetworkManager")
	if network and network.player_info.size() > 0:
		# Only setup network if we're coming from multiplayer menu
		_ready_network_setup()
		# Use number of players from network
		num_players = player_positions.size()
		print("The number of players in this game is " + str(num_players))
		
		# Ensure we have at least 2 players in network mode
		if num_players < 2:
			num_players = 2  # Fallback to minimum
			
		print("Networked game with " + str(num_players) + " players")
	else:
		# We're in local mode - don't even attempt network setup
		is_networked_game = false
		num_players = GameSettings.num_players
		print("Local game with " + str(num_players) + " players from GameSettings")
		
	var popup_scene = load("res://scene/winner_popup.tscn")
	if popup_scene:
		winner_popup = popup_scene.instantiate()
		add_child(winner_popup)
		
		# Connect signals
		winner_popup.play_again_pressed.connect(_on_play_again)
		winner_popup.main_menu_pressed.connect(_on_main_menu)
	
	print("Game started with", num_players, "players!")
	setup_play_label()
	
	# Initialize the game status panel
	update_game_status()
	
	start_game()

func _on_play_again():
	# Reset the game for another round
	reset_game()
	
func _on_main_menu():
	# Return to main menu
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")
	
func reset_game():
	# Clear existing hands
	for hand in hands:
		if hand:
			hand.queue_free()
	hands.clear()
	
	# Clear selected cards
	selected_cards.clear()
	
	# Reset game variables
	current_turn = 0
	game_direction = 1
	cards_to_draw = 0
	skip_turn_switch = false
	waiting_for_defense = false
	waiting_for_suit_selection = false
	last_card_declared = false
	
	# Reset the deck
	if deck and deck.has_method("initialize_deck"):
		deck.initialize_deck()
		deck.shuffle_deck()
	
	# Clear the card slot
	if card_slot:
		var last_card = card_slot.get_last_played_card()
		if last_card:
			last_card.queue_free()
	
	# Restart the game
	start_game()

# Network setup
func _ready_network_setup():
	# Check if we're in a networked game
	var network = get_node_or_null("/root/NetworkManager")
	if network:
		is_networked_game = true
		my_peer_id = network.multiplayer.get_unique_id()
		
		# Map player positions from network info
		if network.player_info.size() > 0:
			# Clear existing mappings
			player_positions.clear()
			
			# Create mappings from network data and count players
			var actual_player_count = 0
			for peer_id in network.player_info:
				if network.player_info[peer_id].has("position"):
					var pos = network.player_info[peer_id].position
					player_positions[peer_id] = pos
					actual_player_count += 1
				else:
					print("⚠️ Warning: Player", peer_id, "has no position assigned!")
			
			# Set the number of players based on actual player count
			num_players = max(2, actual_player_count)  # Ensure at least 2 players
			
			print("Networked game started. My peer ID:", my_peer_id)
			print("Player positions mapping:", player_positions)
			print("Setting num_players to:", num_players)
			
			# Set up RPCs
			if multiplayer:
				multiplayer.peer_disconnected.connect(_on_player_disconnected)
			
			# Call for initial setup specific to networked games
			setup_networked_game()
		else:
			print("⚠️ Warning: No player info found in NetworkManager")
			is_networked_game = false
	else:
		print("Starting single player or local multiplayer game")
		is_networked_game = false
		
# Add this new function to handle networked game-specific setup
func setup_networked_game():
	# This gets called after player positions are determined
	print("Setting up networked game for player", my_peer_id)
	
	# Connect to window resize signals for proper layout
	get_tree().root.size_changed.connect(reposition_player_hands)
	get_tree().root.size_changed.connect(func(): update_hand_visibility())
	
	# Make sure to call reposition on first load
	await get_tree().process_frame
	reposition_player_hands()

# Add this function to handle player disconnections
func _on_player_disconnected(id):
	if is_networked_game:
		# Only process if we have valid player info
		if player_positions.has(id):
			# Handle player disconnection - can pause, end game, or replace with AI
			show_play_notification("Player " + str(player_positions[id] + 1) + " disconnected!")
			
			# Example: If it's their turn, skip it
			if current_turn == player_positions[id]:
				switch_turn()
	
# Add this to handle screen resizing
func reposition_all_game_elements():
	# Update card slot position
	card_slot.center_position()
	
	# Update deck position
	deck.position_deck()
	
	# Update all hands positions
	reposition_player_hands()
	
	# Update any UI elements
	if last_card_button != null:
		var screen_size = get_viewport_rect().size
		last_card_button.position = Vector2(screen_size.x / 2 - 100, screen_size.y - 100)

func reposition_player_hands():
	var screen_size = get_viewport_rect().size
	var margin = 100
	
	# Different positioning logic based on whether we're in a networked game
	if is_networked_game:
		# Find which position is the local player
		var local_position = -1
		if player_positions.has(my_peer_id):
			local_position = player_positions[my_peer_id]
		
		if local_position >= 0 and local_position < hands.size():
			# Always position local player's hand at the bottom
			hands[local_position].position = Vector2(screen_size.x / 2, screen_size.y - margin)
			hands[local_position].rotation = 0  # No rotation for local player
			
			# For 2 players, opponent is always at top
			if num_players == 2:
				var opponent_idx = (local_position + 1) % 2
				hands[opponent_idx].position = Vector2(screen_size.x / 2, margin)
				hands[opponent_idx].rotation = PI
			
			# For 3 players, opponents are left and right
			elif num_players == 3:
				var opponent1_idx = (local_position + 1) % 3
				var opponent2_idx = (local_position + 2) % 3
				
				hands[opponent1_idx].position = Vector2(margin, screen_size.y / 2)
				hands[opponent1_idx].rotation = PI/2
				
				hands[opponent2_idx].position = Vector2(screen_size.x - margin, screen_size.y / 2)
				hands[opponent2_idx].rotation = -PI/2
			
			# For 4 players, opponents are top, left, and right
			elif num_players == 4:
				var opponent1_idx = (local_position + 1) % 4
				var opponent2_idx = (local_position + 2) % 4
				var opponent3_idx = (local_position + 3) % 4
				
				hands[opponent1_idx].position = Vector2(margin, screen_size.y / 2)
				hands[opponent1_idx].rotation = PI/2
				
				hands[opponent2_idx].position = Vector2(screen_size.x / 2, margin)
				hands[opponent2_idx].rotation = PI
				
				hands[opponent3_idx].position = Vector2(screen_size.x - margin, screen_size.y / 2)
				hands[opponent3_idx].rotation = -PI/2
			
			# Update all hand positions with a small animation
			for hand in hands:
				hand.update_positions(0.2)
		else:
			print("⚠️ Warning: Local player position not found for hand repositioning")
	else:
		# Original local positioning
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
		
		# Update hand positions
		for i in range(hands.size()):
			if i < positions.size():
				hands[i].position = positions[i]
				hands[i].update_positions(0.2)  # Small animation duration

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
	if play_label:
		play_label.text = message
		play_label.show()
		
		# Check if we can create a timer
		if Engine.is_in_physics_frame() and get_tree():
			var timer = get_tree().create_timer(label_display_time)
			if timer:
				timer.timeout.connect(func(): if play_label: play_label.hide())
		else:
			# Manual timeout as fallback
			var start_time = Time.get_ticks_msec()
			var timer_process = func():
				if Time.get_ticks_msec() - start_time > label_display_time * 1000:
					if play_label:
						play_label.hide()
					set_process(false)
			set_process(true)
	else:
		print("Play notification (no label): " + message)

func start_game():
	if is_networked_game:
		print("Starting networked game with", num_players, "players")
	else:
		print("Starting local game with", num_players, "players")
	
	if hands.is_empty():
		create_player_hands()
	
	print("Created hands. Now dealing cards...")
	await deck.deal_initial_cards()
	
	var network = get_node_or_null("/root/NetworkManager")
	var is_networked = network and network.multiplayer and network.player_info.size() > 0
	
	if !is_networked or network.multiplayer.is_server():
		var first_card = draw_valid_starting_card()
		if first_card:
			if !is_networked:
				# Local mode - place card directly
				card_slot.place_card(first_card)
			else:
				# Networked mode - server places locally and uses RPC for clients
				card_slot.place_card(first_card)
				place_card_networked.rpc(first_card.value, first_card.suit)
				
			# Update game status panel with initial state
			update_game_status()
			
			# Initialize the UI labels
			if game_ui_labels:
				game_ui_labels.show_effect_message("Game starts with " + first_card.value + " of " + first_card.suit)
				update_turn_label()
	
	print("Finished dealing cards. Starting turn for Player", current_turn + 1)
	
@rpc("authority", "call_local", "reliable")
func place_card_networked(value: String, suit: String):
	print("DEBUG: Received card sync: " + value + " of " + suit)
	var new_card = deck.create_card_from_data(value, suit)
	if new_card:
		card_slot.place_card(new_card)
	else:
		print("ERROR: Failed to create card from data: " + value + " of " + suit)
	
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
		
		# In networked mode, only the local player's hand should be fully visible
		if is_networked_game:
			var local_position = -1
			
			# Find which position the local player has
			if player_positions.has(my_peer_id):
				local_position = player_positions[my_peer_id]
				
			# Set whether this is the local player's hand
			hand.is_player = (i == local_position)
		else:
			hand.is_player = true  # In local mode, all hands are visible
			
		hand.position = positions[i]
		hand.player_position = i
		
		# Handle rotation based on player positions
		if is_networked_game:
			# In networked game, each player sees their hand at the bottom
			# This means we shouldn't rotate the hand if it's the local player's
			var local_position = -1
			if player_positions.has(my_peer_id):
				local_position = player_positions[my_peer_id]
				
			if i == local_position:
				# Local player's hand should always be upright (no rotation)
				hand.rotation = 0
			else:
				# For opponents, calculate relative position
				var relative_pos = (i - local_position) % num_players
				if relative_pos < 0:
					relative_pos += num_players
					
				# Apply rotation based on relative position
				match num_players:
					2:  # In 2-player game, opponent is always at top (180 degrees)
						hand.rotation = PI
					3:  # In 3-player game, other positions are left/right
						if relative_pos == 1:  # Player to the left
							hand.rotation = PI/2
						elif relative_pos == 2:  # Player to the right
							hand.rotation = -PI/2
					4:  # In 4-player game, opponents are at top, left, right
						if relative_pos == 1:  # Player to the left
							hand.rotation = PI/2
						elif relative_pos == 2:  # Player opposite (top)
							hand.rotation = PI
						elif relative_pos == 3:  # Player to the right
							hand.rotation = -PI/2
		else:
			# For local games, use the original rotation logic
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
						if num_players == 3:
							hand.rotation = -PI/2  # Right player
						else:
							hand.rotation = PI/2  # Left player in 4-player game
					3: 
						hand.rotation = -PI/2  # Right player in 4-player game
		
		add_child(hand)
		hands.append(hand)
		
		# Set hand visibility based on whether this is local player or not
		update_hand_visibility()
		
		print("✅ Hand added for Player", i + 1, "at", positions[i])

# Improved hand visibility function
func update_hand_visibility():
	if is_networked_game:
		# In networked mode, all hands are visible but only show faces for local player
		var local_position = -1
		if player_positions.has(my_peer_id):
			local_position = player_positions[my_peer_id]
		
		for i in range(hands.size()):
			if i == local_position:
				# For local player's hand, show card faces
				hands[i].update_visibility(true)
			else:
				# For opponent hands, show card backs
				hands[i].update_visibility(false)
	else:
		# In local mode, show all hands' faces
		for hand in hands:
			hand.update_visibility(true)

# Network version for drawing cards
@rpc("any_peer", "call_local")
func network_draw_card(peer_id):
	# Find which player this peer is
	if not player_positions.has(peer_id):
		print("Error: Unknown peer tried to draw a card: ", peer_id)
		return
	
	var player_position = player_positions[peer_id]
	
	# Verify it's their turn
	if player_position != current_turn:
		print("Error: Player tried to draw a card out of turn")
		return
	
	# Only the server should do the actual card drawing
	if multiplayer.is_server() or not is_networked_game:
		print("Server drawing card for Player " + str(player_position + 1))
		draw_card_for_player(player_position)
	else:
		# Clients just wait for the server to handle it
		print("Client waiting for server to process draw request")

# Modified draw card function that supports both network and local play
func draw_card_for_current_player():
	print("DEBUG: Attempting to draw for Player " + str(current_turn + 1))
	
	if is_networked_game:
		network_draw_card.rpc(my_peer_id)
	else:
		# Local gameplay
		draw_card_for_player(current_turn)

# Internal draw card function used by both local and networked versions
func draw_card_for_player(player_position):
	print("DEBUG: Drawing card for Player " + str(player_position + 1))
	
	var drawn_card = deck.draw_card(player_position)
	
	if drawn_card:
		show_play_notification("Player " + str(player_position + 1) + " drew a card")
		
		# Update game status panel since deck count has changed
		update_game_status()
	
	# Handle turn switching for both local and networked games
	if is_networked_game:
		# In networked games, the server should initiate the turn switch
		if multiplayer.is_server():
			# Calculate new turn based on game direction
			var new_turn = (current_turn + game_direction) % num_players
			if new_turn < 0:
				new_turn = num_players - 1
			
			# Use the existing network_switch_turn RPC to update all clients
			network_switch_turn.rpc(new_turn, game_direction)
	else:
		# For local games, switch turn directly as before
		switch_turn()
	
	return drawn_card

# Network version of card selection
@rpc("any_peer", "call_local")
func network_select_card(peer_id, card_value, card_suit):
	# Find which player position this peer is using
	if not player_positions.has(peer_id):
		print("Error: Unknown peer tried to select card: ", peer_id)
		return
	
	var player_position = player_positions[peer_id]
	
	# Verify it's their turn
	if player_position != current_turn:
		print("Error: Player tried to select card out of turn")
		return
	
	# Find the card in the player's hand by value and suit
	var card_to_select = null
	for card in hands[player_position].hand:
		if card.value == card_value and card.suit == card_suit:
			card_to_select = card
			break
	
	if card_to_select:
		# Call internal selection logic
		select_card_internal(card_to_select)
	else:
		print("Error: Card not found in player's hand:", card_value, "of", card_suit)

# Modified select_card that supports both network and local play
func select_card(card):
	if not card:
		print("Invalid card")
		return
		
	# Check if card has required properties
	if not ("value" in card) or not ("suit" in card):
		print("❌ Card missing required properties in select_card")
		return
	
	if is_networked_game:
		# In networked game, send selection via RPC
		network_select_card.rpc(my_peer_id, card.value, card.suit)
	else:
		# Local gameplay, use internal function directly
		select_card_internal(card)

# Internal select_card implementation used by both local and network versions
func select_card_internal(card):
	if not is_current_player_turn() or not card:
		print("Not current player's turn or invalid card")
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
		# If we just played an 8 in 2-player mode or a Jack,
		# we need to check against the current top card
		var can_place = card_slot.can_place_card(card)
		print("Checking if can place card:", can_place)
		return can_place
	
	# For normal multiple card selection, we just need the same value
	# Even if we're in a special turn after 8 or Jack
	if not card or not ("value" in card):
		print("❌ Card being checked is missing required properties")
		return false
	
	if not selected_cards[0] or not ("value" in selected_cards[0]):
		print("❌ First selected card is missing required properties")
		return false
	
	# Check if value matches first selected card,
	# regardless of whether it's after a special card
	var value_matches = card.value == selected_cards[0].value
	print("Checking if value matches first selected card:", value_matches)
	return value_matches
	
func can_win_next_turn() -> bool:
	# Check if all remaining cards have the same value
	if hands[current_turn].hand.size() <= 1:
		return false
	
	# Get the top card in the slot
	var top_card = card_slot.get_last_played_card()
	if not top_card:
		return false
	
	# Group cards by value
	var cards_by_value = {}
	for card in hands[current_turn].hand:
		if not cards_by_value.has(card.value):
			cards_by_value[card.value] = []
		cards_by_value[card.value].append(card)
	
	# Check if any group contains cards that can be played and would empty the hand
	for value in cards_by_value:
		var cards_group = cards_by_value[value]
		
		# Only check groups with multiple cards
		if cards_group.size() < 2:
			continue
			
		# Check if these cards can be played
		var can_play = false
		for card in cards_group:
			if card_slot.can_place_card(card):
				can_play = true
				break
				
		# If we can play these cards and they're all the cards in our hand
		if can_play and cards_group.size() == hands[current_turn].hand.size():
			return true
	
	return false

func is_current_player_turn() -> bool:
	if is_networked_game:
		# Check if it's the local player's turn
		if player_positions.has(my_peer_id):
			var local_position = player_positions[my_peer_id]
			return current_turn == local_position
		return false
	else:
		return true  # For local testing, allow all actions

# Network version of playing cards
@rpc("any_peer", "call_local")
func network_play_cards(peer_id, card_data_array):
	# This function is called on all clients when a player plays cards
	
	# Find which player position this peer is using
	if not player_positions.has(peer_id):
		print("Error: Unknown peer ID tried to play cards: ", peer_id)
		return
	
	var player_position = player_positions[peer_id]
	
	# Verify it's their turn
	if player_position != current_turn:
		print("Error: Player tried to play cards out of turn")
		return
	
	# Recreate selected cards from the data
	selected_cards = []
	
	for card_dict in card_data_array:
		# Find the card in the player's hand by value and suit
		for card in hands[player_position].hand:
			if card.value == card_dict.value and card.suit == card_dict.suit:
				selected_cards.append(card)
				break
	
	# Now call the original play_selected_cards logic
	play_selected_cards_internal()

# Modified play_selected_cards to support both network and local play
func play_selected_cards():
	if selected_cards.is_empty():
		return
		
	if not card_slot.can_place_card(selected_cards[0]):
		print("Cannot play these cards!")
		return
	
	if is_networked_game:
		# Convert selected cards to data dictionary for network transmission
		var card_data = []
		for card in selected_cards:
			card_data.append({
				"value": card.value,
				"suit": card.suit
			})
		
		# Send to all clients
		network_play_cards.rpc(my_peer_id, card_data)
	else:
		# Local game, just play the cards
		play_selected_cards_internal()

# Internal play_selected_cards implementation used by both local and network versions
func play_selected_cards_internal():
	if selected_cards.is_empty():
		return
		
	if not card_slot.can_place_card(selected_cards[0]):
		print("Cannot play these cards!")
		return
	
	# Check if this is their second-last card and show Last Card button
	if hands[current_turn].hand.size() == selected_cards.size() + 1:
		show_last_card_button()
	# New code: Also check if player could win on next turn with multiple same cards
	elif can_win_next_turn():
		show_last_card_button()
	
	# Play all selected cards in order
	var played_cards_descriptions = []
	skip_turn_switch = false  # Reset the Jack effect
	
	# Count power cards
	var sevens_count = 0
	var jack_count = 0
	var eights_count = 0
	var twos_count = 0  # Add counter for "2" cards
	
	# Check for Ace selection - only the LAST one matters
	var has_ace = false
	var last_ace_index = -1
	
	# Count special cards first
	for i in range(selected_cards.size()):
		if selected_cards[i].value == "Ace":
			has_ace = true
			last_ace_index = i
		elif selected_cards[i].value == "Jack":
			jack_count += 1
		elif selected_cards[i].value == "7":
			sevens_count += 1
		elif selected_cards[i].value == "8" and num_players == 2:
			eights_count += 1
		elif selected_cards[i].value == "2":
			twos_count += 1  # Count how many "2" cards are played
	
	# Track card effects for the UI label
	var effect_description = ""
	
	# Handle cards in a networked-aware way
	for i in range(selected_cards.size()):
		var card = selected_cards[i]
		var card_value = card.value
		var card_suit = card.suit
		
		# Remove from hand
		hands[current_turn].remove_card(card)
		
		# In networked mode, only the server actually updates the card slot
		# and broadcasts the update to all clients
		if is_networked_game:
			if multiplayer.is_server():
				# Server places card and broadcasts to clients
				card_slot.place_card(card)
				place_card_networked.rpc(card_value, card_suit)
				print("DEBUG: Server placed and broadcast: " + card_value + " of " + card_suit)
			# Clients don't update their card slots directly - they wait for the server's RPC
			else:
				# We need to free the card since it will be recreated by the RPC
				card.queue_free()
				print("DEBUG: Client sent card to server: " + card_value + " of " + card_suit)
		else:
			# Local game - just place the card directly
			card_slot.place_card(card)
		
		played_cards_descriptions.append(str(card_value) + " of " + str(card_suit))
		
		# Special handling - don't process effects for "2" cards until we've played all of them
		if card_value == "2" and i < selected_cards.size() - 1 and selected_cards[i+1].value == "2":
			continue  # Skip processing this "2" since there are more to come
	
	# Now process the combined effects of all cards played
	
	# Get player name
	var player_name = "Player " + str(current_turn + 1)
	
	# If this is a networked game, use actual player names if available
	if is_networked_game and player_positions.has(my_peer_id):
		var network = get_node_or_null("/root/NetworkManager")
		if network and network.player_info.size() > 0:
			# Find the player ID for the current player position
			var current_player_id = -1
			for id in player_positions:
				if player_positions[id] == current_turn:
					current_player_id = id
					break
			
			# If we found the player ID, get their name
			if current_player_id > 0 and network.player_info.has(current_player_id) and network.player_info[current_player_id].has("name"):
				player_name = network.player_info[current_player_id].name
	
	# Handle the cumulative effect of multiple "2" cards
	if twos_count > 0:
		# Calculate next player considering game direction
		next_player_to_draw = (current_turn + game_direction) % num_players
		if next_player_to_draw < 0:
			next_player_to_draw = num_players - 1
			
		# Calculate the total cards to draw - 2 per "2" card
		cards_to_draw = twos_count * 2
		
		# Check if next player has a 2 to defend
		if has_card_in_hand(next_player_to_draw, "2"):
			waiting_for_defense = true
			current_attacker = current_turn
			show_play_notification("Player " + str(next_player_to_draw + 1) + " can play a 2 to defend against " + str(cards_to_draw) + " cards!")
			show_defense_ui("2")
			# Don't switch turns yet - wait for defense or skip
		else:
			print("Player ", next_player_to_draw + 1, " will draw ", cards_to_draw, " cards")
			switch_turn()
		
		effect_description = "Next player draws " + str(cards_to_draw) + " cards"
	# Only trigger special effects for other cards if no "2"s were played
	elif twos_count == 0:
		# Special handling for multiple Jacks or 8s
		if jack_count > 0 or (eights_count > 0 and num_players == 2):
			skip_turn_switch = true
			
			var extra_message = ""
			if jack_count > 0 and eights_count > 0:
				extra_message = "Player " + str(current_turn + 1) + " can play " + str(jack_count + eights_count) + " more card(s)!"
			elif jack_count > 0:
				extra_message = "Player " + str(current_turn + 1) + " can play " + str(jack_count) + " more card(s)!"
			else:
				extra_message = "Player " + str(current_turn + 1) + " plays again!"
				
			show_play_notification(extra_message)
			
		# Process other power card effects
		if has_ace and last_ace_index >= 0:
			# Handle Ace effect
			waiting_for_suit_selection = true
			skip_turn_switch = true
			show_suit_selection_ui()
			effect_description = "Changing suit"
		elif sevens_count > 0:
			# Handle accumulated 7s
			if sevens_count > 0:
				effect_description = "Skipping " + str(sevens_count) + " player(s)"
				
				# Store original turn before skipping
				var original_turn = current_turn
				
				# Apply skips one by one to ensure proper wrapping
				for i in range(sevens_count):
					current_turn = (current_turn + game_direction) % num_players
					if current_turn < 0:
						current_turn = num_players - 1
				
				show_play_notification("Player " + str(original_turn + 1) + " played " + 
									  str(sevens_count) + " 7s. Skipping " + str(sevens_count) + 
									  " players to Player " + str(current_turn + 1) + "!")
		elif eights_count > 0 and num_players > 2:
			# In 3+ player mode, reverse direction for each 8 (odd number of 8s changes direction)
			if eights_count % 2 == 1:
				game_direction *= -1
				show_play_notification("Game direction reversed!")
				effect_description = "Game direction reversed"
				
				# Update game status panel to show new direction
				update_game_status()
	
	# Update the play label with the card played information
	if selected_cards.size() == 1:
		game_ui_labels.update_play_label(player_name, selected_cards[0].value, selected_cards[0].suit, effect_description)
	else:
		# For multiple cards
		var effect_text = ""
		if effect_description != "":
			effect_text = " - " + effect_description
			
		game_ui_labels.show_effect_message(player_name + " played " + str(selected_cards.size()) + " cards: " + ", ".join(played_cards_descriptions) + effect_text)
	
	# Join the card descriptions with commas
	var played_cards_text = ", ".join(played_cards_descriptions)
	
	# Show notification of what was played
	var player_number = current_turn + 1
	var message = "Player " + str(player_number) + " played: " + played_cards_text
	show_play_notification(message)
	
	# Check for win condition
	if hands[current_turn].hand.is_empty():
		# Check if the last card played was a power card
		var last_card = selected_cards[selected_cards.size() - 1]
		if is_power_card(last_card):
			show_play_notification("Cannot win with a power card! Drawing a card.")
			var drawn_card = deck.draw_card(current_turn)
		# Otherwise check for Last Card declaration
		elif last_card_declared:
			handle_game_over(current_turn)
		else:
			# Player didn't declare Last Card - penalty
			show_play_notification("Player " + str(current_turn + 1) + " didn't declare Last Card! +2 cards penalty!")
			
			# Add 2 penalty cards
			for i in range(2):
				var drawn_card = deck.draw_card(current_turn)
				if drawn_card:
					print("Player " + str(current_turn + 1) + " drew a penalty card")
		
	# Reset last card declared if they still have cards
	if hands[current_turn].hand.size() > 1:
		last_card_declared = false
	
	# Clear selection
	selected_cards.clear()
	update_game_status()
	
	# Update the turn label
	update_turn_label()
	
	# Switch turns unless special condition
	if not skip_turn_switch and not waiting_for_defense and not waiting_for_suit_selection:
		switch_turn()

func update_turn_label():
	if game_ui_labels:
		var player_name = "Player " + str(current_turn + 1)
		var is_local_player = false
		
		# If this is a networked game, check if it's the local player's turn
		if is_networked_game and player_positions.has(my_peer_id):
			var local_position = player_positions[my_peer_id]
			is_local_player = (current_turn == local_position)
			
			# If we have player names available, use them
			var network = get_node_or_null("/root/NetworkManager")
			if network and network.player_info.size() > 0:
				# Find the player ID for the current player position
				var current_player_id = -1
				for id in player_positions:
					if player_positions[id] == current_turn:
						current_player_id = id
						break
				
				# If we found the player ID, get their name
				if current_player_id > 0 and network.player_info.has(current_player_id) and network.player_info[current_player_id].has("name"):
					player_name = network.player_info[current_player_id].name
		
		# In local mode, all players are considered "local" for UI purposes
		if not is_networked_game:
			is_local_player = true
		
		# Update the turn label
		game_ui_labels.update_turn_label(player_name, is_local_player)

func get_card_effect_description(card, sevens_count = 0) -> String:
	match card.value:
		"2":
			return "Next player draws 2 cards"
		"7":
			if sevens_count > 0:
				return "Skipping " + str(sevens_count) + " player(s)"
			else:
				return "Skipping next player"
		"8":
			if num_players == 2:
				return "Player gets another turn"
			else:
				return "Game direction reversed"
		"Ace":
			return "Changing suit"
		"Jack":
			return "Player gets another turn"
		"King":
			if card.suit == "Hearts":
				return "Next player draws 5 cards"
	
	# No special effect
	return ""
		
func handle_power_card_effects(card, sevens_count = 0):
	match card.value:
		"2":
			# Skip individual processing if cards_to_draw is already set by multiple 2s
			# Only process if this is a single "2" card play
			if cards_to_draw == 0:
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
					show_defense_ui("2")
					# Don't switch turns yet - wait for defense or skip
				else:
					cards_to_draw = 2
					print("Player ", next_player_to_draw + 1, " will draw ", cards_to_draw, " cards")
					switch_turn()
			
		# Rest of function remains the same...
		"7":
			# Handle multiple 7s correctly across all player counts
			if sevens_count > 0:
				# Calculate how many players to skip based on 7s count
				var players_to_skip = sevens_count
				
				# Store original turn before skipping
				var original_turn = current_turn
				
				# Apply skips one by one to ensure proper wrapping
				for i in range(players_to_skip):
					current_turn = (current_turn + game_direction) % num_players
					if current_turn < 0:
						current_turn = num_players - 1
				
				show_play_notification("Player " + str(original_turn + 1) + " played " + 
									  str(sevens_count) + " 7s. Skipping " + str(players_to_skip) + 
									  " players to Player " + str(current_turn + 1) + "!")
			else:
				# Single 7 - skip one player
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
				
				# Update game status panel to show new direction
				update_game_status()
				
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
					show_defense_ui("KingOfHearts")
					# Don't switch turns yet - wait for defense or skip
				else:
					cards_to_draw = 5
					print("Player ", next_player_to_draw + 1, " will draw ", cards_to_draw, " cards")
					switch_turn()
				
		"5":
			if card.suit == "Hearts" and cards_to_draw == 5:
				cards_to_draw = 0  # Cancel King of Hearts effect
				show_play_notification("King of Hearts effect cancelled!")
				
		"2":
			if card.suit == "Hearts" and cards_to_draw == 5:
				cards_to_draw = 7  # Convert 5 to 7 cards
				show_play_notification("Pick up increased to 7 cards!")
				switch_turn()
				
# Add this function to check if a player has a specific card
func has_card_in_hand(player_index, value, suit = null):
	if player_index < 0 or player_index >= hands.size():
		return false
		
	for card in hands[player_index].hand:
		if card.value == value:
			if suit == null or card.suit == suit:
				return true
	return false

# Show UI for defending against attacks
func show_defense_ui(attack_type):
	# Switch to the defending player's turn
	current_turn = next_player_to_draw
	
	# Only show UI to current player in networked games
	if is_networked_game:
		# Get local player position
		var local_position = -1
		if player_positions.has(my_peer_id):
			local_position = player_positions[my_peer_id]
		
		if current_turn != local_position:
			show_play_notification("Waiting for Player " + str(current_turn + 1) + " to defend...")
			return
	
	# Create buttons for defense options
	var screen_size = get_viewport_rect().size
	defense_button_container = VBoxContainer.new()
	defense_button_container.name = "DefenseButtons"
	defense_button_container.position = Vector2(screen_size.x / 2 + 200, screen_size.y / 2 + 50)
	
	if attack_type == "KingOfHearts":
		# Check for both defense options
		var has_5_of_hearts = false
		var has_2_of_hearts = false
		
		for card in hands[current_turn].hand:
			if card.value == "5" and card.suit == "Hearts":
				has_5_of_hearts = true
			elif card.value == "2" and card.suit == "Hearts":
				has_2_of_hearts = true
		
		# Add specific defense buttons
		if has_5_of_hearts:
			var five_button = Button.new()
			five_button.text = "Use 5 of Hearts (Cancel)"
			five_button.custom_minimum_size = Vector2(200, 50)
			five_button.pressed.connect(func(): _on_specific_defend_pressed("5ofHearts"))
			defense_button_container.add_child(five_button)
		
		if has_2_of_hearts:
			var two_button = Button.new()
			two_button.text = "Use 2 of Hearts (Add +2)"
			two_button.custom_minimum_size = Vector2(200, 50)
			two_button.pressed.connect(func(): _on_specific_defend_pressed("2ofHearts"))
			defense_button_container.add_child(two_button)
	else:
		var defend_button = Button.new()
		defend_button.text = "Defend"
		defend_button.custom_minimum_size = Vector2(200, 50)
		defend_button.pressed.connect(func(): _on_defend_pressed(attack_type))
		defense_button_container.add_child(defend_button)
	
	var skip_button = Button.new()
	skip_button.text = "Draw Cards"
	skip_button.custom_minimum_size = Vector2(200, 50)
	skip_button.pressed.connect(func(): _on_skip_defense_pressed())
	defense_button_container.add_child(skip_button)
	
	add_child(defense_button_container)

# Update these functions in your GameManager.gd

func _on_specific_defend_pressed(defense_type):
	# Clean up UI
	if defense_button_container:
		defense_button_container.queue_free()
		defense_button_container = null
	
	var defense_card = null
	
	if defense_type == "5ofHearts":
		# Find 5 of Hearts
		for card in hands[current_turn].hand:
			if card.value == "5" and card.suit == "Hearts":
				defense_card = card
				break
	elif defense_type == "2ofHearts":
		# Find 2 of Hearts
		for card in hands[current_turn].hand:
			if card.value == "2" and card.suit == "Hearts":
				defense_card = card
				break
	
	if defense_card:
		if is_networked_game:
			network_defend_with_card.rpc(my_peer_id, defense_card.value, defense_card.suit)
		else:
			defend_against_attack(defense_card)
	else:
		if is_networked_game:
			network_skip_defense.rpc(my_peer_id)
		else:
			_on_skip_defense_pressed()

func _on_defend_pressed(attack_type):
	# Clean up UI
	if defense_button_container:
		defense_button_container.queue_free()
		defense_button_container = null
	
	# Find the appropriate defense card
	var defense_card = null
	
	if attack_type == "2":
		# Find a 2 in the player's hand
		for card in hands[current_turn].hand:
			if card.value == "2":
				defense_card = card
				break
	elif attack_type == "KingOfHearts":
		# Check for appropriate defense cards
		for card in hands[current_turn].hand:
			if (card.value == "5" and card.suit == "Hearts") or (card.value == "2" and card.suit == "Hearts"):
				defense_card = card
				break
	
	if defense_card:
		if is_networked_game:
			network_defend_with_card.rpc(my_peer_id, defense_card.value, defense_card.suit)
		else:
			defend_against_attack(defense_card)
	else:
		if is_networked_game:
			network_skip_defense.rpc(my_peer_id)
		else:
			_on_skip_defense_pressed()

func _on_skip_defense_pressed():
	# Clean up UI
	if defense_button_container:
		defense_button_container.queue_free()
		defense_button_container = null
	
	if is_networked_game:
		network_skip_defense.rpc(my_peer_id)
	else:
		defend_against_attack(null)
# Add these new RPC functions in your GameManager.gd file

func defend_against_attack(card = null):
	if not waiting_for_defense:
		return
 
	if card:
		# Player is defending with a card
		if card.value == "2":
			# Add 2 more cards to draw
			cards_to_draw += 2
 
			# Calculate next player to check if they can defend
			next_player_to_draw = (current_turn + game_direction) % num_players
			if next_player_to_draw < 0:
				next_player_to_draw = num_players - 1
 
			# Remove the card from hand
			hands[current_turn].remove_card(card)
 
			# Add a small delay to ensure hand repositioning completes
			await get_tree().create_timer(0.5).timeout
 
			# Place card in slot
			if is_networked_game and multiplayer.is_server():
				# First place the card locally on the server
				card_slot.place_card(card)
				# Then sync to all clients
				place_card_networked.rpc(card.value, card.suit)
			else:
				# Only for local games
				card_slot.place_card(card)
 
			# Check if next player has a 2 to defend
			if has_card_in_hand(next_player_to_draw, "2"):
				show_play_notification("Player " + str(next_player_to_draw + 1) + " can defend! Total cards: " + str(cards_to_draw))
				current_turn = next_player_to_draw
				waiting_for_defense = true
				show_defense_ui("2")
			else:
				# No more defenses possible
				show_play_notification("Player " + str(next_player_to_draw + 1) + " must draw " + str(cards_to_draw) + " cards!")
				waiting_for_defense = false
				current_turn = next_player_to_draw
 
				# Apply card drawing - ONLY on server for networked games
				if not is_networked_game or multiplayer.is_server():
					for i in range(cards_to_draw):
						var drawn_card = deck.draw_card(current_turn)
				
				cards_to_draw = 0
				switch_turn()
 
		elif card.value == "5" and card.suit == "Hearts" and cards_to_draw == 5:
			# Cancel King of Hearts effect
			cards_to_draw = 0
			show_play_notification("King of Hearts effect cancelled!")
 
			# Remove the card from hand
			hands[current_turn].remove_card(card)
 
			# Add a small delay to ensure hand repositioning completes
			await get_tree().create_timer(0.5).timeout
 
			# Place card in slot
			if is_networked_game and multiplayer.is_server():
				# First place the card locally on the server
				card_slot.place_card(card)
				# Then sync to all clients
				place_card_networked.rpc(card.value, card.suit)
			else:
				# Only for local games
				card_slot.place_card(card)
 
			# Move to next player
			waiting_for_defense = false
			switch_turn()
 
		elif card.value == "2" and card.suit == "Hearts" and cards_to_draw == 5:
			# Convert 5 to 7 cards
			cards_to_draw = 7
			show_play_notification("Pick up increased to 7 cards!")
 
			# Remove the card from hand
			hands[current_turn].remove_card(card)
 
			# Add a small delay to ensure hand repositioning completes
			await get_tree().create_timer(0.5).timeout
 
			# Place card in slot
			if is_networked_game and multiplayer.is_server():
				# First place the card locally on the server
				card_slot.place_card(card)
				# Then sync to all clients
				place_card_networked.rpc(card.value, card.suit)
			else:
				# Only for local games
				card_slot.place_card(card)
 
			# Player who defended still must draw cards
			waiting_for_defense = false
 
			# Apply card drawing to current player - ONLY on server for networked games
			if not is_networked_game or multiplayer.is_server():
				for i in range(cards_to_draw):
					var drawn_card = deck.draw_card(current_turn)
					if drawn_card:
						print("Player " + str(current_turn + 1) + " drew a card")
 
			# Reset state and move to next player
			cards_to_draw = 0
			switch_turn()
	else:
		# Player is not defending (skipped)
		show_play_notification("Player " + str(current_turn + 1) + " draws " + str(cards_to_draw) + " cards")
 
		# Apply the card drawing - ONLY on server for networked games
		if not is_networked_game or multiplayer.is_server():
			for i in range(cards_to_draw):
				var drawn_card = deck.draw_card(current_turn)
				if drawn_card:
					print("Player " + str(current_turn + 1) + " drew a card")
 
		# Reset state
		cards_to_draw = 0
		waiting_for_defense = false
 
		# Skip directly to the next player
		switch_turn()

@rpc("any_peer", "call_local", "reliable")
func network_defend_with_card(peer_id, card_value, card_suit):
	# Find which player position this peer is using
	if not player_positions.has(peer_id):
		print("Error: Unknown peer tried to defend: ", peer_id)
		return
	
	var player_position = player_positions[peer_id]
	
	# Verify it's their turn
	if player_position != current_turn:
		print("Error: Player tried to defend out of turn")
		return
	
	# Find the card in the player's hand by value and suit
	var defense_card = null
	for card in hands[player_position].hand:
		if card.value == card_value and card.suit == card_suit:
			defense_card = card
			break
	
	if defense_card:
		# Call internal defend logic
		defend_against_attack(defense_card)
	else:
		print("Error: Defense card not found in player's hand:", card_value, "of", card_suit)

@rpc("any_peer", "call_local", "reliable")
func network_skip_defense(peer_id):
	# Find which player position this peer is using
	if not player_positions.has(peer_id):
		print("Error: Unknown peer tried to skip defense: ", peer_id)
		return
	
	var player_position = player_positions[peer_id]
	
	# Verify it's their turn
	if player_position != current_turn:
		print("Error: Player tried to skip defense out of turn")
		return
		
	# Call internal skip defense logic
	defend_against_attack(null)
		
# Networked version of suit selection
@rpc("any_peer", "call_local", "reliable")
func network_select_suit(peer_id, suit):
	# Find which player position this peer is using
	if not player_positions.has(peer_id):
		print("Error: Unknown peer tried to select suit: ", peer_id)
		return
	
	var player_position = player_positions[peer_id]
	
	# Verify it's their turn
	if player_position != current_turn:
		print("Error: Player tried to select suit out of turn")
		return
	
	# Call internal suit selection logic with authority flag
	select_suit_internal(suit, true)

# Function to show suit selection UI for Ace
func show_suit_selection_ui():
	show_play_notification("Select a suit: Hearts, Diamonds, Clubs, or Spades")
	
	# Only show UI to the current player in networked games
	if is_networked_game:
		var local_position = -1
		if player_positions.has(my_peer_id):
			local_position = player_positions[my_peer_id]
			
		if current_turn != local_position:
			show_play_notification("Waiting for Player " + str(current_turn + 1) + " to select a suit...")
			return
	
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
	button_container.position = Vector2(screen_size.x / 2 + 200, screen_size.y / 2 + 50)
	
	add_child(button_container)

# Function to handle suit selection button press
func select_suit(suit):
	if is_networked_game:
		# In networked game, send selection via RPC
		network_select_suit.rpc(my_peer_id, suit)
	else:
		# Local gameplay, use internal function directly
		select_suit_internal(suit)

func select_suit_internal(suit, is_authority = false):
	chosen_suit = suit
	show_play_notification("Suit changed to " + suit)
	
	# Update the Ace card to show chosen suit
	var ace_card = card_slot.get_last_played_card()
	if ace_card:
		if ace_card.has_method("set_chosen_suit"):
			ace_card.set_chosen_suit(suit)
		else:
			# Fallback if method doesn't exist - set property directly
			ace_card.chosen_suit = suit
			print("Card suit changed to:", suit)
	
	# If this is the server or we're explicitly told this is authoritative
	if (is_networked_game && multiplayer.is_server()) || is_authority:
		# Sync suit change to all clients
		sync_chosen_suit.rpc(suit)
	
	# Remove the suit selection UI
	if has_node("SuitButtons"):
		get_node("SuitButtons").queue_free()
	
	# Update the game status panel
	update_game_status()
	
	# Update the UI labels
	if game_ui_labels:
		var player_name = "Player " + str(current_turn + 1)
		
		# If we're in a networked game, try to get the actual player name
		if is_networked_game:
			var network = get_node_or_null("/root/NetworkManager")
			if network && network.player_info.size() > 0:
				# Find the player ID for this position
				var player_id = -1
				for id in player_positions:
					if player_positions[id] == current_turn:
						player_id = id
						break
				
				if player_id > 0 && network.player_info.has(player_id) && network.player_info[player_id].has("name"):
					player_name = network.player_info[player_id].name
		
		game_ui_labels.show_effect_message(player_name + " changed suit to " + suit)
	
	# Reset state and continue game
	waiting_for_suit_selection = false
	skip_turn_switch = false
	switch_turn()
	
@rpc("authority", "call_local", "reliable")
func sync_chosen_suit(suit):
	# Directly update the chosen suit without recalculating anything
	chosen_suit = suit
	
	# Also update the Ace card property
	var ace_card = card_slot.get_last_played_card()
	if ace_card && ace_card.value == "Ace":
		if ace_card.has_method("set_chosen_suit"):
			ace_card.set_chosen_suit(suit)
		else:
			ace_card.chosen_suit = suit
	
	# Update game status panel
	update_game_status()
	
	print("Suit synchronized to:", suit)

func update_game_status():
	if game_status_panel:
		# Update current suit
		var current_suit = "None"
		var last_card = card_slot.get_last_played_card()
		if last_card:
			if last_card.value == "Ace" and "chosen_suit" in last_card and last_card.chosen_suit != "":
				current_suit = last_card.chosen_suit
			else:
				current_suit = last_card.suit
		
		# Update direction (1 is clockwise, -1 is counter-clockwise)
		var is_clockwise = game_direction == 1
		
		# Update deck count
		var cards_in_deck = deck.get_deck_size()
		
		# Send updates to the panel
		game_status_panel.update_suit(current_suit)
		game_status_panel.update_direction(is_clockwise)
		game_status_panel.update_deck_count(cards_in_deck)

# Network version of last card declaration
@rpc("any_peer", "call_local")
func network_declare_last_card(peer_id):
	# Find which player position this peer is using
	if not player_positions.has(peer_id):
		print("Error: Unknown peer tried to declare last card: ", peer_id)
		return
	
	var player_position = player_positions[peer_id]
	
	# Verify it's their turn
	if player_position != current_turn:
		print("Error: Player tried to declare last card out of turn")
		return
	
	# Call internal last card declaration
	last_card_declared = true
	show_play_notification("Player " + str(player_position + 1) + " declares Last Card!")
	hide_last_card_button()
	
# Add this function to show the Last Card button
func show_last_card_button():
	# Only show to the current player in networked games
	if is_networked_game:
		var local_position = -1
		if player_positions.has(my_peer_id):
			local_position = player_positions[my_peer_id]
			
		if current_turn != local_position:
			return
	
	# Create button if it doesn't exist
	if last_card_button == null:
		last_card_button = Button.new()
		last_card_button.text = "Last Card!"
		last_card_button.custom_minimum_size = Vector2(200, 50)
		
		# Style the button to make it stand out
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.9, 0.1, 0.1, 0.8)  # Bright red
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(1, 1, 1)
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		last_card_button.add_theme_stylebox_override("normal", style)
		
		# Position at the bottom center of the screen
		var screen_size = get_viewport_rect().size
		last_card_button.position = Vector2(screen_size.x / 2 - 300, screen_size.y - 300)
		
		# Connect the button to its handler
		last_card_button.pressed.connect(_on_last_card_pressed)
		
		add_child(last_card_button)
	
	# Show the button
	last_card_button.visible = true

# Add this function to hide the Last Card button
func hide_last_card_button():
	if last_card_button != null:
		last_card_button.visible = false

# Add this function to handle the Last Card button press
func _on_last_card_pressed():
	if is_networked_game:
		network_declare_last_card.rpc(my_peer_id)
	else:
		last_card_declared = true
		show_play_notification("Player " + str(current_turn + 1) + " declares Last Card!")
		hide_last_card_button()

# Network version of turn switching
@rpc("any_peer", "call_local")
func network_switch_turn(new_turn, new_direction):
	# Update game direction
	game_direction = new_direction
	
	# Update current turn
	current_turn = new_turn
	
	print("It's now Player", current_turn + 1, "'s turn!")
	
	# Update hand visibility
	update_hand_visibility()
	
	# Update game status panel
	update_game_status()
	
	# Update the turn label
	update_turn_label()

func switch_turn():
	# Skip turn switching if still waiting for player input
	if waiting_for_defense or waiting_for_suit_selection:
		return
		
	# Apply any accumulated card draws to the next player
	if cards_to_draw > 0:
		# Draw cards for the next player
		var next_player = (current_turn + game_direction) % num_players
		if next_player < 0:
			next_player = num_players - 1
		
		# ONLY the server should draw cards
		if not is_networked_game or multiplayer.is_server():    
			for i in range(cards_to_draw):
				var drawn_card = deck.draw_card(next_player)
				if drawn_card:
					print("Player " + str(next_player + 1) + " drew a card")
		
		show_play_notification("Player " + str(next_player + 1) + " drew " + str(cards_to_draw) + " cards!")
		
		# Update the UI with the draw information
		if game_ui_labels:
			var player_name = "Player " + str(next_player + 1)
			game_ui_labels.show_effect_message(player_name + " drew " + str(cards_to_draw) + " cards")
		
		cards_to_draw = 0
		
		# Update game status since deck count has changed
		update_game_status()
	
	# Update current turn based on game direction
	var new_turn = (current_turn + game_direction) % num_players
	if new_turn < 0:
		new_turn = num_players - 1
	
	if is_networked_game:
		# In networked mode, whoever initiated the turn change sends the update
		network_switch_turn.rpc(new_turn, game_direction)
	else:
		# In local mode, just update directly
		current_turn = new_turn
		print("It's now Player", current_turn + 1, "'s turn!")
		update_hand_visibility()
		
		# Update game status panel
		update_game_status()
		
		# Update the turn label
		update_turn_label()

func _on_card_clicked(card):
	# In networked games, only process clicks for cards in the local player's hand
	if is_networked_game:
		# Find which position is the local player
		var local_player_position = -1
		if player_positions.has(my_peer_id):
			local_player_position = player_positions[my_peer_id]
		
		# Check if this card belongs to the local player
		var is_local_player_card = false
		if local_player_position >= 0 and local_player_position < hands.size():
			for c in hands[local_player_position].hand:
				if c == card:
					is_local_player_card = true
					break
		
		if is_local_player_card and current_turn == local_player_position:
			select_card(card)
		elif is_local_player_card:
			show_play_notification("It's not your turn!")
	else:
		# Local gameplay - handle all clicks
		select_card(card)
		
func handle_game_over(player_index):
	
	SoundManager.play_win_sound()
	
	# Wait a moment before showing winner popup
	await get_tree().create_timer(.5).timeout
	
	# Show the winner popup
	if winner_popup:
		# Explicitly center the popup before showing it
		if winner_popup.has_method("_center_popup"):
			winner_popup.call("_center_popup")
		
		# Show the winner popup
		winner_popup.show_winner(player_index + 1)
