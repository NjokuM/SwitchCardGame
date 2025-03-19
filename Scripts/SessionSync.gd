extends Node

# This script provides reliable game state synchronization for multiplayer
# It works with both Firebase-based sessions and traditional multiplayer

signal game_state_synchronized

# Connection status
var is_connected = false
var is_host = false
var session_id = ""
var local_player_id = ""
var last_sync_time = 0

# Game state tracking
var initial_sync_complete = false
var player_hands = []  # Array of arrays, each containing card data for a player
var deck = []  # Current deck
var discard_pile = []  # Discard pile
var current_card = null  # Current card in play
var current_turn = 0  # Whose turn is it
var game_direction = 1  # 1 for clockwise, -1 for counterclockwise

func _ready():
	# Set up session manager connections if available
	var session_mgr = get_node_or_null("/root/SessionManager")
	if session_mgr:
		session_mgr.session_data_updated.connect(_on_session_data_updated)
		# Check if we're already in a session
		if !session_mgr.current_session_id.is_empty():
			is_connected = true
			session_id = session_mgr.current_session_id
			local_player_id = session_mgr.local_player_id
			is_host = session_mgr.is_local_player_host()
			
			# Start periodic syncing for the host
			if is_host:
				_start_sync_timer()
	
	# Set up connection to firebase if available
	var firebase_db = get_node_or_null("/root/FirebaseDB")
	if firebase_db:
		firebase_db.data_updated.connect(_on_firebase_data_updated)
	
	print("SessionSync initialized. Host: ", is_host)

# Start a timer to periodically sync game state (host only)
func _start_sync_timer():
	var timer = Timer.new()
	timer.wait_time = 2.0  # Sync every 2 seconds
	timer.autostart = true
	timer.timeout.connect(_sync_game_state)
	add_child(timer)
	print("Started sync timer for host")

# Initial synchronization of game state at game start
func initialize_game_state(num_players: int):
	if !is_connected:
		print("Not connected to any multiplayer session")
		return
	
	print("Initializing game state for ", num_players, " players")
	
	# If we're the host in a Firebase session, we need to generate and share the initial state
	if is_host:
		# Initialize player hands array
		player_hands = []
		for i in range(num_players):
			player_hands.append([])
		
		# Initialize the deck
		_initialize_and_shuffle_deck()
		
		# Send initial empty state to establish the structure
		_sync_game_state()
		print("Host initialized game state")
	else:
		# Clients wait for the host to send the initial state
		print("Client waiting for host to initialize game state")

# Deal cards to players (host only)
func deal_initial_cards(num_cards_per_player: int):
	if !is_host or !is_connected:
		print("Only host can deal initial cards")
		return
	
	print("Host dealing initial cards: ", num_cards_per_player, " per player")
	
	# Deal cards to each player
	for i in range(num_cards_per_player):
		for j in range(player_hands.size()):
			if deck.size() > 0:
				var card = deck.pop_front()
				player_hands[j].append(card)
	
	# Draw a valid initial card for the discard pile
	while deck.size() > 0:
		var card = deck.pop_front()
		
		# Check if it's a power card
		var is_power = false
		if card.value in ["2", "7", "8", "Ace", "Jack"]:
			is_power = true
		if card.value == "King" and card.suit == "Hearts":
			is_power = true
		if card.value == "5" and card.suit == "Hearts":
			is_power = true
		if card.value == "2" and card.suit == "Hearts":
			is_power = true
		
		if !is_power:
			current_card = card
			discard_pile.append(card)
			break
		else:
			# Put power card back at the end
			deck.push_back(card)
	
	# Sync the game state after dealing
	_sync_game_state()
	print("Host completed dealing cards")

# Get hand data for a specific player
func get_player_hand(player_index: int) -> Array:
	if player_index < 0 or player_index >= player_hands.size():
		return []
	return player_hands[player_index]

# Get the local player's position
func get_local_player_position() -> int:
	var session_mgr = get_node_or_null("/root/SessionManager")
	if session_mgr:
		return session_mgr.get_local_player_position()
	return 0  # Default to first player in local play

# Submit a card play action
func submit_card_play(player_index: int, cards: Array):
	if !is_connected:
		return
	
	# Check if it's this player's turn
	if player_index != current_turn:
		print("Not your turn!")
		return
	
	# If we're the host, process the play directly
	if is_host:
		_process_card_play(player_index, cards)
		_sync_game_state()
	else:
		# Client: Send play to Firebase
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr:
			var move_data = {
				"action": "play_cards",
				"player_index": player_index,
				"cards": cards
			}
			session_mgr.submit_move(move_data)

# Submit a card draw action
func submit_card_draw(player_index: int):
	if !is_connected:
		return
	
	# Check if it's this player's turn
	if player_index != current_turn:
		print("Not your turn!")
		return
	
	# If we're the host, process the draw directly
	if is_host:
		_process_card_draw(player_index)
		_sync_game_state()
	else:
		# Client: Send draw to Firebase
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr:
			var move_data = {
				"action": "draw_card",
				"player_index": player_index
			}
			session_mgr.submit_move(move_data)

# Initialize and shuffle the deck
func _initialize_and_shuffle_deck():
	deck = []
	# Standard 52-card deck
	var suits = ["Hearts", "Spades", "Clubs", "Diamonds"]
	var values = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"]
	
	# Create deck
	for suit in suits:
		for value in values:
			deck.append({"value": value, "suit": suit})
	
	# Shuffle deck
	var seed_value = 0
	if session_id:
		seed_value = session_id.hash()
	else:
		seed_value = Time.get_unix_time_from_system()
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Fisher-Yates shuffle
	var n = deck.size()
	for i in range(n - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp
	
	print("Deck initialized and shuffled with seed: ", seed_value)

# Process a card play
func _process_card_play(player_index: int, cards: Array):
	# Remove the cards from the player's hand
	for card in cards:
		player_hands[player_index].erase(card)
	
	# Handle last card and add to discard pile
	if cards.size() > 0:
		current_card = cards[cards.size() - 1]
		for card in cards:
			discard_pile.append(card)
	
	# Handle turn switching, etc.
	# This is a simplified version - you'll need more logic for special cards
	current_turn = (current_turn + game_direction) % player_hands.size()
	if current_turn < 0:
		current_turn = player_hands.size() - 1

# Process a card draw
func _process_card_draw(player_index: int):
	# Check if deck is empty
	if deck.size() == 0:
		_reshuffle_discard_pile()
	
	# Draw a card if there are any left
	if deck.size() > 0:
		var card = deck.pop_front()
		player_hands[player_index].append(card)
	
	# Switch turns
	current_turn = (current_turn + game_direction) % player_hands.size()
	if current_turn < 0:
		current_turn = player_hands.size() - 1

# Reshuffle the discard pile back into the deck
func _reshuffle_discard_pile():
	if discard_pile.size() <= 1:
		return  # Nothing to reshuffle
	
	# Keep the top card
	var top_card = discard_pile.pop_back()
	
	# Move all other cards to the deck
	deck = discard_pile
	discard_pile = [top_card]
	
	# Shuffle the deck
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Fisher-Yates shuffle
	var n = deck.size()
	for i in range(n - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp
	
	print("Discard pile reshuffled back into deck")

# Sync the current game state (host only)
func _sync_game_state():
	if !is_host or !is_connected:
		return
	
	last_sync_time = Time.get_unix_time_from_system()
	
	# Prepare the game state data
	var game_state = {
		"player_hands": player_hands,
		"deck": deck,
		"discard_pile": discard_pile,
		"current_card": current_card,
		"current_turn": current_turn,
		"game_direction": game_direction,
		"timestamp": last_sync_time
	}
	
	# Use Firebase to sync the state
	var session_mgr = get_node_or_null("/root/SessionManager")
	if session_mgr:
		session_mgr.update_game_state(game_state)
		print("Game state synced to Firebase at timestamp: ", last_sync_time)

# Handle Firebase data updates
func _on_firebase_data_updated(path, data):
	if !is_connected or data == null:
		return
	
	# We only care about game_state updates from within our session
	if !path.begins_with("sessions/" + session_id + "/game_state"):
		return
		
	print("Received Firebase update for path: ", path)
	
	# Process game state updates
	_process_game_state_update(data)

# Handle session data updates
func _on_session_data_updated(session_data):
	if session_data == null or !is_connected:
		return
	
	# Check if there's game state data
	if "game_state" in session_data:
		_process_game_state_update(session_data.game_state)
		
	# Process any pending moves
	if "game_state" in session_data and "last_move" in session_data.game_state:
		var move = session_data.game_state.last_move
		_process_move(move)

# Process incoming game state updates
func _process_game_state_update(game_state):
	if !game_state or game_state.is_empty():
		return
	
	# Check if this is a newer state than what we have
	if "timestamp" in game_state and game_state.timestamp <= last_sync_time and initial_sync_complete:
		return  # Skip older or same-age updates
	
	print("Processing game state update")
	
	# Update our local state
	if "player_hands" in game_state:
		player_hands = game_state.player_hands
	
	if "deck" in game_state:
		deck = game_state.deck
	
	if "discard_pile" in game_state:
		discard_pile = game_state.discard_pile
	
	if "current_card" in game_state:
		current_card = game_state.current_card
	
	if "current_turn" in game_state:
		current_turn = game_state.current_turn
	
	if "game_direction" in game_state:
		game_direction = game_state.game_direction
	
	if "timestamp" in game_state:
		last_sync_time = game_state.timestamp
	
	# Mark initial sync complete
	if !initial_sync_complete:
		initial_sync_complete = true
		emit_signal("game_state_synchronized")
	
	print("Game state updated from Firebase. Turn: ", current_turn)

# Process a move from another player
func _process_move(move):
	if !move or !is_host:
		return  # Only host processes moves
	
	# Check if this is a valid action
	if "action" in move:
		if move.action == "play_cards" and "player_index" in move and "cards" in move:
			_process_card_play(move.player_index, move.cards)
			_sync_game_state()
			
		elif move.action == "draw_card" and "player_index" in move:
			_process_card_draw(move.player_index)
			_sync_game_state()
