extends Node

# Game state synchronization module for Firebase
# Handles converting game actions to Firebase updates and vice versa

# --- Signals for event-driven architecture ---
signal game_state_synchronized # Emitted when game state is fully synchronized
signal cards_played(player_index, cards, special_effects) # Emitted when cards are played
signal cards_drawn(player_index, card_count) # Emitted when cards are drawn
signal turn_changed(player_index) # Emitted when turn changes
signal direction_changed(direction) # Emitted when direction changes
signal card_effect_resolved # Emitted when a special card effect resolves
signal pending_card_effect(effect_type, target_player) # Emitted when a special effect needs player input
signal last_card_declared(player_index) # Emitted when a player declares last card

# --- Game state variables ---
var is_host = false
var local_player_index = -1
var current_turn = 0
var game_direction = 1 # 1 for clockwise, -1 for counter-clockwise
var current_card = null
var player_hands = [] # Array of arrays, each containing card data dictionaries
var deck = [] # Array of card data dictionaries
var discard_pile = [] # Array of card data dictionaries
var session_id = ""
var is_game_initialized = false
var num_players = 0
var play_count = 0 # Used to track how many times a player has played in a turn (for Jack)
var cards_to_draw = 0 # For accumulating draw cards (e.g., multiple 2s)
var waiting_for_defense = false # Flag for when waiting for player to defend against card effects
var waiting_for_suit_selection = false # Flag for when waiting for Ace suit selection

# --- Card constants ---
const SUITS = ["Hearts", "Spades", "Clubs", "Diamonds"]
const VALUES = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"]

func _ready():
	# Connect to FirebaseDB signals
	var firebase_db = get_node_or_null("/root/FirebaseDB")
	if firebase_db:
		firebase_db.data_updated.connect(_on_firebase_data_updated)
	else:
		push_error("FirebaseDB singleton not found!")
	
	# Connect to SessionManager signals
	var session_manager = get_node_or_null("/root/SessionManager")
	if session_manager:
		session_id = session_manager.current_session_id
		is_host = session_manager.is_local_player_host()
		local_player_index = session_manager.get_local_player_position()
		print("SessionSync initialized - Session ID: " + session_id)
		print("Local player index: " + str(local_player_index))
		print("Is host: " + str(is_host))
	else:
		push_error("SessionManager singleton not found!")

# --- Initialization ---

# Initialize game state for a new game with specified number of players
func initialize_game_state(players_count: int):
	num_players = players_count
	
	# Initialize local state
	player_hands = []
	for i in range(num_players):
		player_hands.append([])
	
	deck = []
	discard_pile = []
	current_turn = 0
	game_direction = 1
	
	is_game_initialized = true
	print("Game state initialized for " + str(num_players) + " players")
	
	# If we're the host, start listening for player moves
	if is_host:
		_start_listening_for_moves()
	
	# All clients listen for game state changes
	_start_listening_for_game_state()

# Deal initial cards to all players
func deal_initial_cards(cards_per_player: int):
	if !is_host:
		push_error("Only host can deal initial cards!")
		return
	
	print("Dealing " + str(cards_per_player) + " cards to " + str(num_players) + " players")
	
	# Create a new deck
	_create_and_shuffle_deck()
	
	# Deal cards to each player
	for i in range(cards_per_player):
		for j in range(num_players):
			if deck.size() > 0:
				var card = deck.pop_front()
				player_hands[j].append(card)
	
	# Draw valid starting card (non-power card)
	var first_card = null
	while deck.size() > 0:
		first_card = deck.pop_front()
		# Skip power cards for first card
		if not _is_power_card(first_card):
			discard_pile.push_back(first_card)
			current_card = first_card
			break
		else:
			# Put power card back at the end
			deck.push_back(first_card)
	
	# Update the game state in Firebase
	_update_game_state()

# --- Player Actions ---

# Submit a card play to Firebase
func submit_card_play(player_index: int, cards: Array):
	if player_index != local_player_index:
		push_error("Can only submit moves for local player!")
		return
		
	if player_index != current_turn:
		push_error("Not this player's turn!")
		return
	
	print("Submitting card play: Player " + str(player_index) + " playing " + str(cards.size()) + " cards")
	
	# If we're the host, process the move directly
	if is_host:
		_process_card_play(player_index, cards)
	else:
		# Otherwise, send the move to Firebase for the host to process
		var firebase_db = get_node_or_null("/root/FirebaseDB")
		if firebase_db and session_id != "":
			var move_data = {
				"type": "play_cards",
				"player_index": player_index,
				"cards": cards,
				"timestamp": Time.get_unix_time_from_system()
			}
			
			# Write to the moves collection
			firebase_db.write_data("sessions/" + session_id + "/moves/" + str(player_index), move_data)
		else:
			push_error("Cannot submit move - Firebase DB not available or no active session")

# Submit a card draw to Firebase
func submit_card_draw(player_index: int):
	if player_index != local_player_index:
		push_error("Can only submit moves for local player!")
		return
		
	if player_index != current_turn:
		push_error("Not this player's turn!")
		return
	
	print("Submitting card draw: Player " + str(player_index))
	
	# If we're the host, process the move directly
	if is_host:
		_process_card_draw(player_index)
	else:
		# Otherwise, send the move to Firebase for the host to process
		var firebase_db = get_node_or_null("/root/FirebaseDB")
		if firebase_db and session_id != "":
			var move_data = {
				"type": "draw_card",
				"player_index": player_index,
				"timestamp": Time.get_unix_time_from_system()
			}
			
			# Write to the moves collection
			firebase_db.write_data("sessions/" + session_id + "/moves/" + str(player_index), move_data)
		else:
			push_error("Cannot submit move - Firebase DB not available or no active session")

# Submit suit selection after playing an Ace
func submit_suit_selection(suit: String):
	if !waiting_for_suit_selection:
		push_error("Not waiting for suit selection!")
		return
		
	if local_player_index != current_turn:
		push_error("Not your turn to select suit!")
		return
	
	print("Submitting suit selection: " + suit)
	
	# If we're the host, process directly
	if is_host:
		_process_suit_selection(suit)
	else:
		# Otherwise, send to Firebase
		var firebase_db = get_node_or_null("/root/FirebaseDB")
		if firebase_db and session_id != "":
			var move_data = {
				"type": "select_suit",
				"player_index": local_player_index,
				"suit": suit,
				"timestamp": Time.get_unix_time_from_system()
			}
			
			# Write to the moves collection
			firebase_db.write_data("sessions/" + session_id + "/moves/" + str(local_player_index), move_data)
		else:
			push_error("Cannot submit move - Firebase DB not available or no active session")

# Submit defense against card effects (2, King of Hearts)
func submit_defense(defense_card):
	if !waiting_for_defense:
		push_error("Not waiting for defense!")
		return
		
	if local_player_index != current_turn:
		push_error("Not your turn to defend!")
		return
	
	print("Submitting defense with card: " + defense_card.value + " of " + defense_card.suit)
	
	# If we're the host, process directly
	if is_host:
		_process_defense(local_player_index, defense_card)
	else:
		# Otherwise, send to Firebase
		var firebase_db = get_node_or_null("/root/FirebaseDB")
		if firebase_db and session_id != "":
			var move_data = {
				"type": "defense",
				"player_index": local_player_index,
				"card": defense_card,
				"timestamp": Time.get_unix_time_from_system()
			}
			
			# Write to the moves collection
			firebase_db.write_data("sessions/" + session_id + "/moves/" + str(local_player_index), move_data)
		else:
			push_error("Cannot submit move - Firebase DB not available or no active session")

# Submit skip defense (accept penalty)
func submit_skip_defense():
	if !waiting_for_defense:
		push_error("Not waiting for defense!")
		return
		
	if local_player_index != current_turn:
		push_error("Not your turn to defend!")
		return
	
	print("Submitting skip defense")
	
	# If we're the host, process directly
	if is_host:
		_process_skip_defense(local_player_index)
	else:
		# Otherwise, send to Firebase
		var firebase_db = get_node_or_null("/root/FirebaseDB")
		if firebase_db and session_id != "":
			var move_data = {
				"type": "skip_defense",
				"player_index": local_player_index,
				"timestamp": Time.get_unix_time_from_system()
			}
			
			# Write to the moves collection
			firebase_db.write_data("sessions/" + session_id + "/moves/" + str(local_player_index), move_data)
		else:
			push_error("Cannot submit move - Firebase DB not available or no active session")

# Submit last card declaration
func submit_last_card_declaration():
	if local_player_index != current_turn:
		push_error("Not your turn to declare last card!")
		return
		
	if player_hands[local_player_index].size() != 1:
		push_error("Can only declare last card when you have 1 card left!")
		return
	
	print("Submitting last card declaration for player " + str(local_player_index))
	
	# If we're the host, process directly
	if is_host:
		_process_last_card_declaration(local_player_index)
	else:
		# Otherwise, send to Firebase
		var firebase_db = get_node_or_null("/root/FirebaseDB")
		if firebase_db and session_id != "":
			var move_data = {
				"type": "last_card",
				"player_index": local_player_index,
				"timestamp": Time.get_unix_time_from_system()
			}
			
			# Write to the moves collection
			firebase_db.write_data("sessions/" + session_id + "/moves/" + str(local_player_index), move_data)
		else:
			push_error("Cannot submit move - Firebase DB not available or no active session")

# Submit turn change
func submit_turn_change(new_turn: int, new_direction: int):
	if !is_host:
		push_error("Only host can change turn!")
		return
	
	print("Submitting turn change to player " + str(new_turn))
	
	current_turn = new_turn
	game_direction = new_direction
	
	# Reset play count for the new player's turn
	play_count = 0
	
	# Update game state in Firebase
	_update_game_state()
	
	# Emit signals
	emit_signal("turn_changed", current_turn)
	emit_signal("direction_changed", game_direction)

# --- Firebase Event Handlers ---

# Handle FirebaseDB data update events
func _on_firebase_data_updated(path, data):
	if data == null:
		return
		
	# Check if this is game state data
	if path.begins_with("sessions/" + session_id + "/game_state"):
		_process_game_state_update(data)
	
	# Check if this is a move (host only)
	elif is_host and path.begins_with("sessions/" + session_id + "/moves/"):
		_process_move_update(path, data)

# Process game state updates from Firebase
func _process_game_state_update(data):
	print("Processing game state update")
	
	# Update local state variables
	if "current_turn" in data:
		current_turn = data.current_turn
	
	if "game_direction" in data:
		game_direction = data.game_direction
	
	if "player_hands" in data and data.player_hands is Array:
		player_hands = data.player_hands.duplicate(true)
	
	if "deck" in data and data.deck is Array:
		deck = data.deck.duplicate(true)
	
	if "discard_pile" in data and data.discard_pile is Array:
		discard_pile = data.discard_pile.duplicate(true)
		if discard_pile.size() > 0:
			current_card = discard_pile.back()
	
	if "current_card" in data and data.current_card != null:
		current_card = data.current_card.duplicate(true)
	
	if "cards_to_draw" in data:
		cards_to_draw = data.cards_to_draw
	
	if "waiting_for_defense" in data:
		waiting_for_defense = data.waiting_for_defense
	
	if "waiting_for_suit_selection" in data:
		waiting_for_suit_selection = data.waiting_for_suit_selection
		
	if "play_count" in data:
		play_count = data.play_count
	
	# Emit signals
	emit_signal("game_state_synchronized")
	emit_signal("turn_changed", current_turn)
	emit_signal("direction_changed", game_direction)
	
# --- Private Game Logic Methods ---

# Process playing cards
func _process_card_play(player_index: int, cards: Array):
	if player_index != current_turn:
		push_error("Not this player's turn!")
		return
		
	if cards.size() == 0:
		push_error("No cards to play!")
		return
	
	print("Processing card play from player " + str(player_index) + ": " + str(cards.size()) + " cards")
	
	# Check if the first card can be played
	if current_card != null and !_can_play_card(cards[0], current_card):
		push_error("Cannot play this card!")
		return
	
	# Check if all cards have the same value (for multiple cards)
	if cards.size() > 1:
		var first_value = cards[0].value
		for i in range(1, cards.size()):
			if cards[i].value != first_value:
				push_error("All cards must have the same value!")
				return
	
	# Check if player has these cards
	for card in cards:
		var has_card = false
		for player_card in player_hands[player_index]:
			if player_card.value == card.value and player_card.suit == card.suit:
				has_card = true
				break
				
		if !has_card:
			push_error("Player " + str(player_index) + " doesn't have this card: " + card.value + " of " + card.suit)
			return
	
	# Remove cards from player's hand
	for card in cards:
		for i in range(player_hands[player_index].size()):
			var player_card = player_hands[player_index][i]
			if player_card.value == card.value and player_card.suit == card.suit:
				player_hands[player_index].remove_at(i)
				break
	
	# Add cards to discard pile
	for card in cards:
		discard_pile.append(card)
	
	# Set current card to the last played card
	current_card = cards.back()
	
	# Track special card effects
	var special_effects = {"has_special": false}
	var switch_turn = true # Whether to switch turn after play
	
	# Count power cards
	var jacks_count = 0
	var sevens_count = 0
	var eights_count = 0
	
	# Count special cards
	for card in cards:
		if card.value == "Jack":
			jacks_count += 1
			special_effects.has_special = true
		elif card.value == "7":
			sevens_count += 1
			special_effects.has_special = true
		elif card.value == "8":
			eights_count += 1
			special_effects.has_special = true
		elif card.value == "Ace":
			special_effects.has_special = true
			waiting_for_suit_selection = true
			switch_turn = false # Don't switch turns until suit is selected
		elif card.value == "2":
			special_effects.has_special = true
			if cards_to_draw == 0:
				cards_to_draw = 2
			else:
				cards_to_draw += 2
			
			# Check if next player has a 2 to defend
			var next_player = _get_next_player(current_turn)
			if _has_card_in_hand(next_player, "2"):
				waiting_for_defense = true
				switch_turn = false # Don't switch turns until defense is resolved
		elif card.value == "King" and card.suit == "Hearts":
			special_effects.has_special = true
			cards_to_draw = 5
			
			# Check if next player has a defense card
			var next_player = _get_next_player(current_turn)
			if _has_card_in_hand(next_player, "5", "Hearts") or _has_card_in_hand(next_player, "2", "Hearts"):
				waiting_for_defense = true
				switch_turn = false # Don't switch turns until defense is resolved
	
	# Add special effects to the data
	if jacks_count > 0:
		special_effects.jacks_count = jacks_count
		switch_turn = false # Jack allows player to go again
		play_count += 1
	
	if sevens_count > 0:
		special_effects.sevens_count = sevens_count
		
		# Skip the next player(s)
		for i in range(sevens_count):
			current_turn = _get_next_player(current_turn)
	
	if eights_count > 0:
		special_effects.eights_count = eights_count
		
		if num_players == 2:
			switch_turn = false # In 2-player, 8 works like Jack
		else:
			# Reverse direction
			game_direction *= -1
	
	# Check win condition
	if player_hands[player_index].size() == 0:
		special_effects.has_won = true
	
	# Update game state
	_update_game_state()
	
	# Emit signals
	emit_signal("cards_played", player_index, cards, special_effects)
	
	# Switch turn if needed
	if switch_turn and !waiting_for_defense and !waiting_for_suit_selection:
		current_turn = _get_next_player(current_turn)
		play_count = 0
		_update_game_state()
		emit_signal("turn_changed", current_turn)

# Process drawing a card
func _process_card_draw(player_index: int):
	if player_index != current_turn:
		push_error("Not this player's turn!")
		return
	
	print("Processing card draw for player " + str(player_index))
	
	# Check if deck needs reshuffling
	if deck.size() == 0:
		_reshuffle_discard_pile()
		
		if deck.size() == 0:
			push_error("No cards left to draw!")
			return
	
	# Draw a card from the deck
	var card = deck.pop_front()
	player_hands[player_index].append(card)
	
	# Update game state
	_update_game_state()
	
	# Emit signal
	emit_signal("cards_drawn", player_index, 1)
	
	# Advance to next player
	current_turn = _get_next_player(current_turn)
	play_count = 0
	_update_game_state()
	emit_signal("turn_changed", current_turn)

# Process suit selection after Ace
func _process_suit_selection(suit: String):
	if !waiting_for_suit_selection:
		push_error("Not waiting for suit selection!")
		return
	
	print("Processing suit selection: " + suit)
	
	# Validate the suit
	if !SUITS.has(suit):
		push_error("Invalid suit: " + suit)
		return
	
	# Set the chosen suit on the current card
	current_card.chosen_suit = suit
	
	# Reset waiting state
	waiting_for_suit_selection = false
	
	# Update game state
	_update_game_state()
	
	# Advance to next player
	current_turn = _get_next_player(current_turn)
	play_count = 0
	_update_game_state()
	emit_signal("turn_changed", current_turn)

# Process defense against card effects
func _process_defense(player_index: int, defense_card):
	if !waiting_for_defense:
		push_error("Not waiting for defense!")
		return
		
	if player_index != current_turn:
		push_error("Not your turn to defend!")
		return
		
	print("Processing defense for player " + str(player_index) + " with " + defense_card.value + " of " + defense_card.suit)
	
	# Check if player has this card
	var has_card = false
	var card_index = -1
	
	for i in range(player_hands[player_index].size()):
		var card = player_hands[player_index][i]
		if card.value == defense_card.value and card.suit == defense_card.suit:
			has_card = true
			card_index = i
			break
			
	if !has_card:
		push_error("Player " + str(player_index) + " doesn't have this defense card")
		return
	
	# Handle different defense types
	if defense_card.value == "2":
		# Add 2 more cards to draw
		cards_to_draw += 2
		
		# Remove the card from player's hand
		player_hands[player_index].remove_at(card_index)
		
		# Add to discard pile
		discard_pile.append(defense_card)
		current_card = defense_card
		
		# Calculate next player
		var next_player = _get_next_player(player_index)
		
		# Check if next player has a 2 to defend
		if _has_card_in_hand(next_player, "2"):
			current_turn = next_player
			# Still waiting for defense
		else:
			# Apply card drawing
			for i in range(cards_to_draw):
				if deck.size() == 0:
					_reshuffle_discard_pile()
					if deck.size() == 0:
						break
				
				var card = deck.pop_front()
				player_hands[next_player].append(card)
			
			# Reset state
			waiting_for_defense = false
			cards_to_draw = 0
			
			# Move to next player
			current_turn = _get_next_player(next_player)
			play_count = 0
	
	elif defense_card.value == "5" and defense_card.suit == "Hearts" and cards_to_draw == 5:
		# Cancel King of Hearts effect
		cards_to_draw = 0
		
		# Remove the card from player's hand
		player_hands[player_index].remove_at(card_index)
		
		# Add to discard pile
		discard_pile.append(defense_card)
		current_card = defense_card
		
		# Reset state
		waiting_for_defense = false
		
		# Move to next player
		current_turn = _get_next_player(player_index)
		play_count = 0
	
	elif defense_card.value == "2" and defense_card.suit == "Hearts" and cards_to_draw == 5:
		# Convert 5 to 7 cards
		cards_to_draw = 7
		
		# Remove the card from player's hand
		player_hands[player_index].remove_at(card_index)
		
		# Add to discard pile
		discard_pile.append(defense_card)
		current_card = defense_card
		
		# Apply card drawing to current player
		for i in range(cards_to_draw):
			if deck.size() == 0:
				_reshuffle_discard_pile()
				if deck.size() == 0:
					break
			
			var card = deck.pop_front()
			player_hands[player_index].append(card)
		
		# Reset state
		waiting_for_defense = false
		cards_to_draw = 0
		
		# Move to next player
		current_turn = _get_next_player(player_index)
		play_count = 0
	
	# Update game state
	_update_game_state()
	
	# Emit signal for card effect resolution
	emit_signal("card_effect_resolved")
	
	# Emit signal for turn change
	emit_signal("turn_changed", current_turn)

# Process skipping defense (accept penalty)
func _process_skip_defense(player_index: int):
	if !waiting_for_defense:
		push_error("Not waiting for defense!")
		return
		
	if player_index != current_turn:
		push_error("Not your turn to defend!")
		return
	
	print("Processing skip defense for player " + str(player_index))
	
	# Apply the card drawing penalty
	for i in range(cards_to_draw):
		if deck.size() == 0:
			_reshuffle_discard_pile()
			if deck.size() == 0:
				break
		
		var card = deck.pop_front()
		player_hands[player_index].append(card)
	
	# Reset state
	waiting_for_defense = false
	cards_to_draw = 0
	
	# Move to next player
	current_turn = _get_next_player(player_index)
	play_count = 0
	
	# Update game state
	_update_game_state()
	
	# Emit signals
	emit_signal("card_effect_resolved")
	emit_signal("turn_changed", current_turn)

# Process last card declaration
func _process_last_card_declaration(player_index: int):
	if player_index != current_turn:
		push_error("Not your turn to declare last card!")
		return
		
	if player_hands[player_index].size() != 1:
		push_error("Can only declare last card when you have 1 card left!")
		return
	
	print("Processing last card declaration for player " + str(player_index))
	
	# Update game state with last card declaration
	_update_game_state({"last_card_declared": player_index})
	
	# Emit signal
	emit_signal("last_card_declared", player_index)

# Start listening for moves in Firebase
func _start_listening_for_moves():
	if !is_host or session_id == "":
		return
		
	print("Starting to listen for player moves")
	
	var firebase_db = get_node_or_null("/root/FirebaseDB")
	if firebase_db:
		firebase_db.listen_for_changes("sessions/" + session_id + "/moves")

# Start listening for game state changes
func _start_listening_for_game_state():
	if session_id == "":
		return
		
	print("Starting to listen for game state changes")
	
	var firebase_db = get_node_or_null("/root/FirebaseDB")
	if firebase_db:
		firebase_db.listen_for_changes("sessions/" + session_id + "/game_state")

# Update the game state in Firebase
func _update_game_state(additional_data = {}):
	if !is_host or session_id == "":
		return
		
	var firebase_db = get_node_or_null("/root/FirebaseDB")
	if firebase_db:
		var game_state = {
			"current_turn": current_turn,
			"game_direction": game_direction,
			"player_hands": player_hands,
			"deck": deck,
			"discard_pile": discard_pile,
			"current_card": current_card,
			"cards_to_draw": cards_to_draw,
			"waiting_for_defense": waiting_for_defense,
			"waiting_for_suit_selection": waiting_for_suit_selection,
			"play_count": play_count,
			"last_updated": Time.get_unix_time_from_system()
		}
		
		# Add any additional data
		for key in additional_data:
			game_state[key] = additional_data[key]
		
		firebase_db.write_data("sessions/" + session_id + "/game_state", game_state)

# --- Helper Functions ---

# Create and shuffle a new deck
func _create_and_shuffle_deck():
	print("Creating new deck")
	
	# Create a new deck
	deck = []
	for suit in SUITS:
		for value in VALUES:
			deck.append({"value": value, "suit": suit})
	
	# Shuffle the deck using a consistent method
	_shuffle_deck()

# Shuffle the deck
func _shuffle_deck():
	# Fisher-Yates shuffle
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(session_id + str(Time.get_unix_time_from_system()))
	
	var n = deck.size()
	for i in range(n - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp
		
	print("Deck shuffled with seed: " + str(rng.seed))

# Reshuffle discard pile into deck
func _reshuffle_discard_pile():
	print("Reshuffling discard pile into deck")
	
	if discard_pile.size() <= 1:
		print("Not enough cards in discard pile to reshuffle")
		return
	
	# Keep the top card
	var top_card = discard_pile.back()
	
	# Add all other cards to the deck
	for i in range(discard_pile.size() - 1):
		deck.append(discard_pile[i])
	
	# Clear discard pile and put top card back
	discard_pile = [top_card]
	
	# Shuffle the deck
	_shuffle_deck()

# Check if a card can be played on the current card
func _can_play_card(card, current):
	# Aces can be played anytime
	if card.value == "Ace":
		return true
		
	if current == null:
		return true # First card can be anything
	
	# Check if the last card was an Ace with a chosen suit
	if current.value == "Ace" and current.get("chosen_suit"):
		return card.suit == current.chosen_suit
	
	# Normal card matching
	return card.suit == current.suit or card.value == current.value

# Check if a card is a power card
func _is_power_card(card):
	if card.value in ["2", "7", "8", "Ace", "Jack"]:
		return true
	if card.value == "King" and card.suit == "Hearts":
		return true
	if card.value == "5" and card.suit == "Hearts":
		return true
	if card.value == "2" and card.suit == "Hearts":
		return true
	return false

# Get the next player based on game direction
func _get_next_player(player_index):
	var next = (player_index + game_direction) % num_players
	if next < 0:
		next += num_players
	return next

# Check if a player has a specific card
func _has_card_in_hand(player_index, value, suit = null):
	if player_index < 0 or player_index >= player_hands.size():
		return false
		
	for card in player_hands[player_index]:
		if card.value == value:
			if suit == null or card.suit == suit:
				return true
	return false

# Get a player's hand
func get_player_hand(player_index):
	if player_index < 0 or player_index >= player_hands.size():
		return []
	return player_hands[player_index]

# Get the local player position
func get_local_player_position():
	return local_player_index

# Process move updates from Firebase (host only)
func _process_move_update(path, data):
	if !is_host:
		return
		
	if data == null or !("type" in data) or !("player_index" in data):
		push_error("Invalid move data received")
		return
	
	var player_index = data.player_index
	var move_type = data.type
	
	print("Processing move: " + move_type + " from player " + str(player_index))
	
	match move_type:
		"play_cards":
			if "cards" in data and data.cards is Array:
				_process_card_play(player_index, data.cards)
				
		"draw_card":
			_process_card_draw(player_index)
			
		"select_suit":
			if "suit" in data:
				_process_suit_selection(data.suit)
			
		"defense":
			if "card" in data:
				_process_defense(player_index, data.card)
			
		"skip_defense":
			_process_skip_defense(player_index)
			
		"last_card":
			_process_last_card_declaration(player_index)
	
	# Clean up move after processing
	var firebase_db = get_node_or_null("/root/FirebaseDB")
	if firebase_db:
		firebase_db.delete_data("sessions/" + session_id + "/moves/" + str(player_index))
