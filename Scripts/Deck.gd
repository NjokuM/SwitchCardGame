extends Node2D
const CARD_IMAGE = "res://scene/card.tscn"
const BACK_OF_CARD = "res://assets/BACK.png"
const CARD_SCENE = preload(CARD_IMAGE)
const CARD_DRAW_SPEED = 0.33
const SUITS = ["Hearts", "Spades", "Clubs", "Diamonds"]
const VALUES = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"]
const CARDS_PER_PLAYER = 7
var deck = []
var discard_pile = []
@onready var game_manager = $"../GameManager"
@onready var card_slot = $"../CardSlot"

func _ready() -> void:
	await get_tree().process_frame
	initialize_deck()
	shuffle_deck()
	
	# Position the deck
	position_deck()
	
	# Connect to window resize signals
	get_tree().root.size_changed.connect(position_deck)
	
func using_firebase_sync() -> bool:
	var session_mgr = get_node_or_null("/root/SessionManager")
	var is_firebase_session = session_mgr and !session_mgr.current_session_id.is_empty()
	return is_firebase_session
	
func position_deck():
	var screen_size = get_viewport_rect().size
	# Position the deck at the left side of the center
	position = Vector2(screen_size.x / 2 - 400, screen_size.y / 2)
	
func initialize_deck():
	deck.clear()
	for suit in SUITS:
		for value in VALUES:
			deck.append({"value": value, "suit": suit})

func shuffle_deck():
	# Only shuffle if we're the server or in local play
	var network = get_node_or_null("/root/NetworkManager")
	var is_networked = network and network.multiplayer and network.player_info.size() > 0
	
	if !is_networked or network.multiplayer.is_server():
		# Do the actual shuffling
		deck.shuffle()
		print("✅ Deck shuffled")
		
		# If in network mode, send the shuffled deck to all clients
		if is_networked:
			sync_deck.rpc(deck)
	# Non-server clients don't shuffle in networked mode

# Add a new RPC to sync the deck state
@rpc("authority", "call_local")
func sync_deck(shuffled_deck):
	deck = shuffled_deck
	print("✅ Received shuffled deck from server")

func deal_initial_cards() -> void:
	var network = get_node_or_null("/root/NetworkManager")
	var session_mgr = get_node_or_null("/root/SessionManager")
	
	# Check if we're in a Firebase session
	var is_firebase_session = session_mgr and !session_mgr.current_session_id.is_empty()
	var is_traditional_network = network and network.multiplayer and network.player_info.size() > 0
	
	# Firebase session handling
	if is_firebase_session:
		# Only host deals cards in Firebase mode
		if session_mgr.is_local_player_host():
			print("Firebase: Host dealing initial cards")
			
			# Generate a consistent deck with a seed based on session ID
			# This ensures all clients can generate the same deck
			var seed_value = session_mgr.current_session_id.hash()
			var rng = RandomNumberGenerator.new()
			rng.seed = seed_value
			
			# Initialize and shuffle the deck with our seeded RNG
			initialize_deck()
			
			# Use a custom shuffle that uses the seed
			_shuffle_deck_with_seed(rng)
			
			# Create hands data for all players
			var hands_data = []
			for player in range(game_manager.num_players):
				hands_data.append([])
			
			# Deal cards to each player
			for i in range(CARDS_PER_PLAYER):
				for j in range(game_manager.num_players):
					# Add delay between dealing
					await get_tree().create_timer(CARD_DRAW_SPEED).timeout
					
					if deck.is_empty():
						continue
						
					# Pop a card and add it to the appropriate hand
					var card_data = deck.pop_front()
					hands_data[j].append(card_data)
					
					# Also create a local visual card
					var new_card = CARD_SCENE.instantiate()
					new_card.set_card_data(card_data.value, card_data.suit)
					game_manager.hands[j].add_card(new_card, CARD_DRAW_SPEED)
			
			# Draw valid starting card using the same algorithm
			var first_card = null
			var discard_pile = []
			
			while deck.size() > 0:
				first_card = deck.pop_front()
				# Skip power cards for first card
				if not game_manager.is_power_card(first_card):
					discard_pile.push_back(first_card)
					break
				else:
					# Put power card back at the end
					deck.push_back(first_card)
			
			# If we found a valid first card
			if first_card:
				# Create visual representation
				var visual_card = CARD_SCENE.instantiate()
				visual_card.set_card_data(first_card.value, first_card.suit)
				card_slot.place_card(visual_card)
				
				# Save the complete initial game state to Firebase
				var game_state = {
					"seed": seed_value,  # Store the seed so clients can recreate the same deck
					"hands": hands_data,
					"deck": deck,
					"discard_pile": discard_pile,
					"first_card": first_card,  # Store the first card explicitly
					"current_turn": 0,
					"game_direction": 1,
					"last_updated": Time.get_unix_time_from_system()
				}
				
				var firebase_db = get_node_or_null("/root/FirebaseDB")
				if firebase_db:
					# Use write_data to ensure the entire state is replaced, not just updated
					firebase_db.write_data("sessions/" + session_mgr.current_session_id + "/game_state", game_state)
					
				print("Firebase: Initial cards dealt and synchronized with seed", seed_value)
		else:
			# Non-host clients need to clear their local state and wait for Firebase
			print("Firebase: Client waiting for host to deal cards")
			
			# Clear any local deck/cards to prevent state conflicts
			deck.clear()
			
			# Set up listeners for game state changes
			_setup_firebase_listeners()
	
	# Traditional network handling
	elif is_traditional_network:
		if network.multiplayer.is_server():
			# Server controls initial dealing
			for i in range(CARDS_PER_PLAYER):
				for j in range(game_manager.num_players):
					await get_tree().create_timer(CARD_DRAW_SPEED).timeout
					var card = deal_card_to_player(j)
					
					# Broadcast the deal in networked mode
					if card:
						sync_deal_card.rpc(j, card.value, card.suit)
	
	# Local game handling
	else:
		# Local mode - deal directly
		for i in range(CARDS_PER_PLAYER):
			for j in range(game_manager.num_players):
				# Add delay between dealing cards
				await get_tree().create_timer(CARD_DRAW_SPEED).timeout
				deal_card_to_player(j)
				
		# Draw first card
		var card = draw_valid_starting_card()
		if card:
			card_slot.place_card(card)
	
	print("Initial cards have been dealt")

# Set up Firebase listeners for game state changes
func _setup_firebase_listeners():
	var session_mgr = get_node_or_null("/root/SessionManager")
	if not session_mgr or session_mgr.current_session_id.is_empty():
		return
		
	var firebase_db = get_node_or_null("/root/FirebaseDB")
	if not firebase_db:
		return
		
	# Path to listen for game state changes
	var path = "sessions/" + session_mgr.current_session_id + "/game_state"
	
	# Listen for updates
	firebase_db.data_updated.connect(_on_firebase_game_state_updated)
	firebase_db.listen_for_changes(path)
	
	print("Firebase: Listening for game state changes")

# Handle Firebase game state updates
func _on_firebase_game_state_updated(path, data):
	if not data:
		return
		
	print("Firebase: Received game state update")
	
	# If we received a seed, use it to recreate the same deck as the host
	if "seed" in data:
		var seed_value = data.seed
		print("Firebase: Received game seed: " + str(seed_value))
		
		# Initialize a new deck with the same seed
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		
		# Only recreate the deck if we don't have one already
		if deck.is_empty():
			initialize_deck()
			_shuffle_deck_with_seed(rng)
			print("Firebase: Recreated deck with host's seed")
	
	# Process deck updates
	if "deck" in data:
		# Only update the deck if it's different
		if deck != data.deck:
			deck = data.deck.duplicate(true)  # Deep copy
			print("Firebase: Deck updated with " + str(deck.size()) + " cards")
		
	# Process hands updates
	if "hands" in data:
		var local_player_position = 0
		
		# Get local player position from session manager
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr:
			local_player_position = session_mgr.get_local_player_position()
			
		# Update visual hands
		for i in range(min(data.hands.size(), game_manager.hands.size())):
			if data.hands[i]:
				_sync_hand_with_data(i, data.hands[i], i == local_player_position)
				
	# Process first card (explicit)
	if "first_card" in data and data.first_card:
		_update_current_card(data.first_card)
	# Process discard pile / current card (fallback)
	elif "discard_pile" in data and data.discard_pile.size() > 0:
		var current_card = data.discard_pile[data.discard_pile.size() - 1]
		_update_current_card(current_card)
		
	# Process current turn
	if "current_turn" in data:
		game_manager.current_turn = data.current_turn
		
	# Process game direction
	if "game_direction" in data:
		game_manager.game_direction = data.game_direction
		
	print("Firebase: Game state fully synchronized")

# Sync a hand with the data from Firebase
func _sync_hand_with_data(hand_index, hand_data, is_local_player):
	if hand_index < 0 or hand_index >= game_manager.hands.size():
		print("Firebase: Invalid hand index:", hand_index)
		return
		
	var hand = game_manager.hands[hand_index]
	
	# Create a list of existing cards
	var existing_cards = []
	for card in hand.hand:
		if "value" in card and "suit" in card:
			existing_cards.append({"value": card.value, "suit": card.suit})
		else:
			print("Firebase: Card missing value or suit properties")
	
	# Add new cards
	for card_data in hand_data:
		# Ensure card_data has required properties
		if not ("value" in card_data and "suit" in card_data):
			print("Firebase: Skipping invalid card data:", card_data)
			continue
		
		# Check if card already exists
		var found = false
		for existing in existing_cards:
			if existing.value == card_data.value and existing.suit == card_data.suit:
				found = true
				break
				
		# If it's a new card, add it
		if not found:
			var new_card = CARD_SCENE.instantiate()
			if new_card.has_method("set_card_data"):
				new_card.set_card_data(card_data.value, card_data.suit)
				hand.add_card(new_card, CARD_DRAW_SPEED)
				print("Firebase: Added new card to player", hand_index, ":", card_data.value, "of", card_data.suit)
			else:
				print("Firebase: Card scene missing set_card_data method")
	
	# Update visibility based on local player
	if hand.has_method("update_visibility"):
		hand.update_visibility(is_local_player)
		print("Firebase: Updated hand visibility for player", hand_index, "is_local =", is_local_player)
	else:
		print("Firebase: Hand missing update_visibility method")
	
# Update the current card in the slot
func _update_current_card(card_data):
	# Ensure card_data has required properties
	if not ("value" in card_data and "suit" in card_data):
		print("Firebase: Cannot update current card - invalid card data")
		return
		
	# Check if a card with these values is already in the slot
	var current_card = card_slot.get_last_played_card()
	if current_card and "value" in current_card and "suit" in current_card:
		if current_card.value == card_data.value and current_card.suit == card_data.suit:
			return  # Card already matches, no update needed
	
	# Create a new card
	var new_card = CARD_SCENE.instantiate()
	if new_card.has_method("set_card_data"):
		new_card.set_card_data(card_data.value, card_data.suit)
		if card_slot.has_method("place_card"):
			card_slot.place_card(new_card)
			print("Firebase: Updated current card to " + card_data.value + " of " + card_data.suit)
		else:
			print("Firebase: CardSlot missing place_card method")
	else:
		print("Firebase: Card scene missing set_card_data method")

# Custom deck shuffling function with a seed for consistency
func _shuffle_deck_with_seed(rng: RandomNumberGenerator):
	# Fisher-Yates shuffle algorithm with a seeded RNG
	var n = deck.size()
	for i in range(n - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp
	
	print("Deck shuffled with seed: " + str(rng.seed))

# Add RPC to synchronize dealing
@rpc("authority", "call_local")
func sync_deal_card(player_index, card_value, card_suit):
	# Find and remove this specific card from the deck
	var found_index = -1
	for i in range(deck.size()):
		if deck[i].value == card_value and deck[i].suit == card_suit:
			found_index = i
			break
	
	if found_index >= 0:
		deck.remove_at(found_index)
		
		# Create the card and add it to the player's hand
		var new_card = CARD_SCENE.instantiate()
		new_card.set_card_data(card_value, card_suit)
		game_manager.hands[player_index].add_card(new_card, CARD_DRAW_SPEED)

func deal_card_to_player(player_index: int):
	if deck.is_empty():
		reshuffle_discard_pile()
		if deck.is_empty():
			print("❌ No cards left to deal!")
			return null

	var card_data = deck.pop_front()
	var new_card = CARD_SCENE.instantiate()

	if new_card.has_method("set_card_data"):
		new_card.set_card_data(card_data["value"], card_data["suit"])
		print("✅ Dealing card:", card_data["value"], "of", card_data["suit"], "for Player", player_index + 1)
	else:
		push_error("❌ Error: Card scene is missing 'set_card_data' method!")
		return null

	game_manager.hands[player_index].add_card(new_card, CARD_DRAW_SPEED)
	return new_card

@rpc("any_peer", "call_local")
func network_draw_card(player_index: int):
	var network = get_node_or_null("/root/NetworkManager")
	var is_networked = network and network.multiplayer and network.player_info.size() > 0
	
	# Only the server decides which card is drawn
	if !is_networked or network.multiplayer.is_server():
		if deck.is_empty():
			reshuffle_discard_pile()
			if deck.is_empty():
				print("❌ No cards left to draw!")
				return
				
		var card_data = deck.pop_front()
		print("✅ Server selected card to draw:", card_data["value"], "of", card_data["suit"])
		
		# Broadcast the drawn card to all clients
		if is_networked:
			sync_draw_card.rpc(player_index, card_data.value, card_data.suit)
		else:
			# In local mode, create and add the card directly
			var new_card = CARD_SCENE.instantiate()
			new_card.set_card_data(card_data["value"], card_data["suit"])
			game_manager.hands[player_index].add_card(new_card, CARD_DRAW_SPEED)

@rpc("authority", "call_local")
func sync_draw_card(player_index, card_value, card_suit):
	# Create and add the card on all clients
	var new_card = CARD_SCENE.instantiate()
	new_card.set_card_data(card_value, card_suit)
	print("✅ Drawing card:", card_value, "of", card_suit, "for Player", player_index + 1)
	game_manager.hands[player_index].add_card(new_card, CARD_DRAW_SPEED)

func draw_card(player_index: int):
	print("DEBUG: Draw request for Player " + str(player_index + 1))
	
	var network = get_node_or_null("/root/NetworkManager")
	var is_networked = network and network.multiplayer and network.player_info.size() > 0
	
	if is_networked:
		# Use RPC to synchronize card drawing
		network_draw_card.rpc(player_index)
		return null  # The actual card will be created by the RPC
	else:
		# Local mode - draw directly
		if deck.is_empty():
			reshuffle_discard_pile()
			if deck.is_empty():
				print("❌ No cards left to draw!")
				return null
				
		var card_data = deck.pop_front()
		var new_card = CARD_SCENE.instantiate()
		
		if new_card.has_method("set_card_data"):
			new_card.set_card_data(card_data["value"], card_data["suit"])
			print("✅ Drawing card:", card_data["value"], "of", card_data["suit"], "for Player", player_index + 1)
		else:
			push_error("❌ Error: Card scene is missing 'set_card_data' method!")
			return null
			
		game_manager.hands[player_index].add_card(new_card, CARD_DRAW_SPEED)
		return new_card

func draw_valid_starting_card():
	# Check if we're using Firebase sync
	if using_firebase_sync():
		# In Firebase sessions, the card will be synced by SessionSync
		# so we don't need to draw it here
		print("Using SessionSync for initial card")
		return null
		
	# Continue with the original logic for non-Firebase games
	var network = get_node_or_null("/root/NetworkManager")
	var is_traditional_network = network and network.multiplayer and network.player_info.size() > 0
	
	if !is_traditional_network or network.multiplayer.is_server():
		var card = draw_card_for_slot()
		while card and game_manager.is_power_card(card):
			# Put power card back and draw another
			return_card_to_deck(card)
			card = draw_card_for_slot()
			
		# Broadcast initial card in networked mode
		if is_traditional_network and card:
			sync_initial_card.rpc(card.value, card.suit)
			
		return card
	else:
		# Non-server clients wait for the RPC
		return null
@rpc("authority", "call_local")
func sync_initial_card(card_value, card_suit):
	# Find and remove this specific card from the deck
	var found_index = -1
	for i in range(deck.size()):
		if deck[i].value == card_value and deck[i].suit == card_suit:
			found_index = i
			break
			
	if found_index >= 0:
		deck.remove_at(found_index)
		
	# Create the card 
	var new_card = CARD_SCENE.instantiate()
	new_card.set_card_data(card_value, card_suit)
	
	# Update game state
	card_slot.place_card(new_card)
	
func draw_card_for_slot():
	if deck.is_empty():
		reshuffle_discard_pile()
		if deck.is_empty():
			print("❌ No cards left for slot!")
			return null

	var card_data = deck.pop_front()
	var new_card = CARD_SCENE.instantiate()
	new_card.set_card_data(card_data["value"], card_data["suit"])

	return new_card

func create_card_from_data(value: String, suit: String) -> Node2D:
	var new_card = CARD_SCENE.instantiate()
	new_card.set_card_data(value, suit)
	return new_card
	
func return_card_to_deck(card: Node2D):
	# Create card data from the card node
	var card_data = {
		"value": card.value,
		"suit": card.suit
	}

	# Add the card data back to the deck
	deck.append(card_data)

	# Remove the card node
	if card.get_parent():
		card.get_parent().remove_child(card)
	card.queue_free()

	# Shuffle the deck to ensure randomness
	shuffle_deck()
	print("✅ Card returned to deck:", card_data["value"], "of", card_data["suit"])
	
func reshuffle_discard_pile():
	print("Attempting to reshuffle discard pile...")
	
	# Check if we have any cards in the discard pile
	if discard_pile.is_empty():
		print("❌ No cards in discard pile to reshuffle!")
		return false
	
	# Get the top card from the CardSlot
	var top_card = card_slot.get_last_played_card()
	
	# Create a new array for the reshuffled deck
	var reshuffled_deck = []
	
	# Add all cards from the discard pile to the reshuffled deck except the top card
	for card_data in discard_pile:
		# Skip the top card
		if top_card and top_card.value == card_data.value and top_card.suit == card_data.suit:
			continue
		
		reshuffled_deck.append(card_data)
	
	# Replace the deck with the reshuffled cards
	deck = reshuffled_deck
	
	# Clear the discard pile (except for the top card)
	discard_pile = []
	
	# If we have a top card, add it back to the discard pile
	if top_card:
		discard_pile.append({"value": top_card.value, "suit": top_card.suit})
	
	print("Reshuffled " + str(deck.size()) + " cards back into the deck")
	shuffle_deck()
	return true
	
func add_to_discard_pile(card_data: Dictionary):
	discard_pile.append(card_data)
	
# Helper function to get current deck size
func get_deck_size() -> int:
	return deck.size()
	
# Helper function to get discard pile size
func get_discard_pile_size() -> int:
	return discard_pile.size()
