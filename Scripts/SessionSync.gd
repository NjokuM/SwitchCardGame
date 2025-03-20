extends Node

# This script provides reliable game state synchronization for multiplayer
# It works with both Firebase-based sessions and traditional multiplayer

signal game_state_synchronized
signal cards_played(player_index, cards, special_effects)

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
	if player_index < 0 or player_index >= player_hands.size() or not player_hands is Array:
		print("DEBUG: Invalid player hand access: ", player_index)
		return []
	
	if not player_hands[player_index] is Array:
		print("DEBUG: Player hand is not an array: ", player_index)
		return []
		
	return player_hands[player_index]

# Get the local player's position
func get_local_player_position() -> int:
	var session_mgr = get_node_or_null("/root/SessionManager")
	if session_mgr:
		return session_mgr.get_local_player_position()
	return 0  # Default to first player in local play

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

# Replace the card play handling functions in SessionSync.gd

# Submit a card play action with improved logging and error handling
func submit_card_play(player_index: int, cards: Array):
	if !is_connected:
		print("DEBUG: Not connected to multiplayer session")
		return
	
	# Check if it's this player's turn
	if player_index != current_turn:
		print("DEBUG: Not your turn! Your position:", player_index, "Current turn:", current_turn)
		return
	
	print("DEBUG: Submitting card play: Player ", player_index, " playing ", cards.size(), " cards")
	
	# Check for invalid cards
	for card in cards:
		if not card is Dictionary or not "value" in card or not "suit" in card:
			print("DEBUG: Invalid card data in submission")
			return
	
	# If we're the host, process the play directly
	if is_host:
		print("DEBUG: Host processing card play directly")
		_process_card_play(player_index, cards)
		
		# Always sync game state after processing
		_sync_game_state()
	else:
		# Client: Send play to Firebase
		print("DEBUG: Client sending card play to Firebase")
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr:
			# Count special cards for host validation
			var has_jacks = false
			var has_sevens = false
			var has_eights = false
			var has_ace = false
			var has_draw_cards = false
			
			for card in cards:
				if card.value == "Jack":
					has_jacks = true
				elif card.value == "7":
					has_sevens = true
				elif card.value == "8":
					has_eights = true
				elif card.value == "Ace":
					has_ace = true
				elif card.value == "2" or (card.value == "King" and card.suit == "Hearts"):
					has_draw_cards = true
			
			# Send detailed data to help the host validate
			var move_data = {
				"action": "play_cards",
				"player_index": player_index,
				"cards": cards,
				"has_jacks": has_jacks,
				"has_sevens": has_sevens,
				"has_eights": has_eights,
				"has_ace": has_ace,
				"has_draw_cards": has_draw_cards,
				"timestamp": Time.get_unix_time_from_system()
			}
			session_mgr.submit_move(move_data)
			print("DEBUG: Move submitted to session manager")
		else:
			print("DEBUG: Failed to find SessionManager")

# Improved _process_card_play with better error handling and special card handling
func _process_card_play(player_index: int, cards: Array):
	print("DEBUG: Processing card play from player ", player_index)
	
	# Safety check for valid player index and player_hands
	if player_index < 0 or player_index >= player_hands.size() or not player_hands is Array:
		print("DEBUG: Invalid player index: ", player_index)
		return
		
	if not player_hands[player_index] is Array:
		print("DEBUG: Player hand is not an array: ", player_index)
		return
		
	# Check for valid cards
	if cards.size() == 0 or not cards is Array:
		print("DEBUG: No cards to process or invalid cards data")
		return
	
	# Process special cards with proper game logic for turn switching
	var special_effects = {}
	var last_card = cards[cards.size() - 1]
	
	# Safety check for last card
	if not last_card is Dictionary or not "value" in last_card or not "suit" in last_card:
		print("DEBUG: Invalid last card data")
		return
	
	# Count special cards for effects
	var jacks_count = 0
	var sevens_count = 0
	var eights_count = 0
	var has_ace = false
	
	for card in cards:
		if card.value == "Jack":
			jacks_count += 1
		elif card.value == "7":
			sevens_count += 1
		elif card.value == "8":
			eights_count += 1
		elif card.value == "Ace":
			has_ace = true
	
	# Detect special card effects
	if jacks_count > 0 or sevens_count > 0 or eights_count > 0 or has_ace or (last_card.value == "2") or (last_card.value == "King" and last_card.suit == "Hearts"):
		special_effects["has_special"] = true
		special_effects["card"] = last_card
		
		# Add detailed special effect info
		if jacks_count > 0:
			special_effects["jacks_count"] = jacks_count
			print("DEBUG: Jack(s) detected - player goes again")
		
		if sevens_count > 0:
			special_effects["sevens_count"] = sevens_count
			print("DEBUG: Seven(s) detected - skip next player")
		
		if eights_count > 0:
			special_effects["eights_count"] = eights_count
			print("DEBUG: Eight(s) detected - reverse direction")
		
		if has_ace:
			special_effects["has_ace"] = true
			print("DEBUG: Ace detected - suit selection needed")
			
		if last_card.value == "2" or (last_card.value == "King" and last_card.suit == "Hearts"):
			special_effects["draw_cards"] = true
			print("DEBUG: Draw card effect detected")
			
		print("DEBUG: Special card detected: ", last_card.value, " of ", last_card.suit)
	
	# Remove the cards from the player's hand with better error handling
	for card in cards:
		# Safety check for card
		if not card is Dictionary or not "value" in card or not "suit" in card:
			print("DEBUG: Invalid card data in cards array")
			continue
			
		var found = false
		var card_index = -1
		
		# Find the card in the player's hand
		for i in range(player_hands[player_index].size()):
			var hand_card = player_hands[player_index][i]
			if not hand_card is Dictionary or not "value" in hand_card or not "suit" in hand_card:
				print("DEBUG: Invalid hand card data at index ", i)
				continue
				
			if hand_card.value == card.value and hand_card.suit == card.suit:
				card_index = i
				found = true
				break
		
		if found:
			player_hands[player_index].remove_at(card_index)
			print("DEBUG: Removed card from player's hand: ", card.value, " of ", card.suit)
		else:
			print("DEBUG: Card not found in player's hand: ", card.value, " of ", card.suit)
	
	# Handle last card and add to discard pile
	current_card = last_card
	for card in cards:
		discard_pile.append(card)
	
	print("DEBUG: Updated current card to: ", current_card.value, " of ", current_card.suit)
	print("DEBUG: Added ", cards.size(), " cards to discard pile")
	
	# Emit signal to notify about the play
	emit_signal("cards_played", player_index, cards, special_effects)
	
	# Process turn switching with special card rules
	var old_turn = current_turn
	var num_players = int(player_hands.size())
	var skip_turn_switch = false
	
	# Handle special card effects for turn switching
	if "has_special" in special_effects:
		# Jack allows player to go again
		if jacks_count > 0:
			skip_turn_switch = true
			print("DEBUG: Jack played - player ", player_index, " goes again")
			
		# Process direction change from 8
		if eights_count > 0:
			if num_players == 2:
				# In 2-player game, 8 works like Jack (play again)
				skip_turn_switch = true
				print("DEBUG: 8 played in 2-player game - player ", player_index, " goes again")
			else:
				# Reverse direction in 3+ player games
				game_direction *= -1
				print("DEBUG: 8 played - game direction reversed to ", game_direction)
				
		# Process skipping from 7 (always process AFTER direction change from 8)
		if sevens_count > 0:
			if !skip_turn_switch:  # Only if not already skipping turn switch
				# Calculate how many players to skip (1 per 7)
				var players_to_skip = sevens_count
				var new_turn = current_turn
				
				# Apply skips one by one
				for i in range(players_to_skip):
					new_turn = (new_turn + game_direction) % num_players
					if new_turn < 0:
						new_turn += num_players
						
				current_turn = new_turn
				skip_turn_switch = true  # We've already handled the turn change
				print("DEBUG: 7 played - skipped ", players_to_skip, " players to ", current_turn)
			
		# For Ace, King, 2, we let normal turn switching happen
		
	# Normal turn switching if not skipped by special cards
	if !skip_turn_switch:
		# Convert values to integers explicitly to avoid float/int errors
		var next_turn = int(current_turn) + int(game_direction)
		
		# Handle negative values manually instead of using modulo
		if next_turn >= num_players:
			next_turn = next_turn - num_players
		elif next_turn < 0:
			next_turn = num_players + next_turn
		
		current_turn = next_turn
		print("DEBUG: Turn switched from ", old_turn, " to ", current_turn)
# Process a card draw
# Replace the _process_card_draw function in SessionSync.gd

func _process_card_draw(player_index: int):
	print("DEBUG: Processing card draw for player", player_index)
	
	# Safety check for valid player index and player_hands
	if player_index < 0 or player_index >= player_hands.size() or not player_hands is Array:
		print("DEBUG: Invalid player index for card draw: ", player_index)
		return
		
	if not player_hands[player_index] is Array:
		print("DEBUG: Player hand is not an array for card draw: ", player_index)
		return
	
	# Check if deck is empty
	if deck.size() == 0 or not deck is Array:
		_reshuffle_discard_pile()
	
	# Draw a card if there are any left
	if deck.size() > 0 and deck is Array:
		var card = deck.pop_front()
		# Safety check for card
		if not card is Dictionary or not "value" in card or not "suit" in card:
			print("DEBUG: Invalid card drawn from deck")
			return
			
		player_hands[player_index].append(card)
		print("DEBUG: Drew card:", card.value, "of", card.suit, "for player", player_index)
	else:
		print("DEBUG: No cards left to draw")
	
	# Switch turns - using manual handling instead of modulo
	var old_turn = current_turn
	
	# Convert values to integers explicitly to avoid float/int errors
	var next_turn = int(current_turn) + int(game_direction)
	var num_players = int(player_hands.size())
	
	# Handle negative values manually instead of using modulo
	if next_turn >= num_players:
		next_turn = next_turn - num_players
	elif next_turn < 0:
		next_turn = num_players + next_turn
	
	current_turn = next_turn
	print("DEBUG: Turn switched from", old_turn, "to", current_turn, "after card draw")

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
# Replace this code in SessionSync.gd _process_game_state_update function

# Process incoming game state updates
func _process_game_state_update(game_state):
	if !game_state or game_state.is_empty():
		return
	
	# Check if this is a newer state than what we have
	if "timestamp" in game_state and game_state.timestamp <= last_sync_time and initial_sync_complete:
		return  # Skip older or same-age updates
	
	print("Processing game state update")
	
	# Keep track of the old current card to detect changes
	var old_card = current_card
	
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
		# Ensure integers when reading from Firebase
		current_turn = int(game_state.current_turn)
	
	if "game_direction" in game_state:
		# Ensure integers when reading from Firebase
		game_direction = int(game_state.game_direction)
	
	if "timestamp" in game_state:
		last_sync_time = game_state.timestamp
	
	# Mark initial sync complete
	if !initial_sync_complete:
		initial_sync_complete = true
		emit_signal("game_state_synchronized")
		return  # Initial sync is already handled by _on_game_state_synchronized
	
	# If the current card has changed, we need to visualize it
	if old_card != current_card and current_card != null:
		print("Card change detected in game state update")
		# For simplicity, we'll assume the previous player played the card
		
		# Calculate player index with explicit integer casting
		var prev_turn = int(current_turn) - int(game_direction)
		var num_players = int(player_hands.size())
		
		# Handle wraparound manually instead of using modulo
		if prev_turn >= num_players:
			prev_turn = prev_turn - num_players
		elif prev_turn < 0:
			prev_turn = num_players + prev_turn
			
		# Create a visual card only if we're not the one who played it
		if prev_turn != get_local_player_position():
			emit_signal("cards_played", prev_turn, [current_card], {})
	
	print("Game state updated from Firebase. Turn: ", current_turn)

# Process a move from another player with better logging and validation
func _process_move(move):
	if !move or !is_host:
		return  # Only host processes moves
	
	print("DEBUG: Host processing move action: ", move.get("action", "unknown"))
	
	# Check if this is a valid action
	if "action" in move:
		if move.action == "play_cards" and "player_index" in move and "cards" in move:
			# Validate that it's this player's turn
			if move.player_index != current_turn:
				print("DEBUG: Ignored play_cards - not player's turn")
				return
				
			# Process the play with detailed logging
			print("DEBUG: Processing valid play_cards move from player ", move.player_index)
			_process_card_play(move.player_index, move.cards)
			_sync_game_state()
			
		elif move.action == "draw_card" and "player_index" in move:
			# Validate that it's this player's turn
			if move.player_index != current_turn:
				print("DEBUG: Ignored draw_card - not player's turn")
				return
				
			print("DEBUG: Processing valid draw_card move from player ", move.player_index)
			_process_card_draw(move.player_index)
			_sync_game_state()
			
		elif move.action == "select_suit" and "player_index" in move and "suit" in move:
			# Validate player and current card
			if move.player_index != current_turn or current_card.value != "Ace":
				print("DEBUG: Ignored select_suit - invalid state")
				return
				
			print("DEBUG: Processing valid select_suit move from player ", move.player_index)
			_process_suit_selection(move.player_index, move.suit)
			_sync_game_state()
			
		elif move.action == "declare_last_card" and "player_index" in move:
			# Validate player and card count
			if move.player_index != current_turn or player_hands[move.player_index].size() != 1:
				print("DEBUG: Ignored declare_last_card - invalid state")
				return
				
			print("DEBUG: Processing valid declare_last_card move from player ", move.player_index)
			_process_last_card_declaration(move.player_index)
			_sync_game_state()
			
		elif move.action == "turn_change" and "new_turn" in move and "new_direction" in move:
			print("DEBUG: Processing valid turn_change move")
			_process_turn_change(move.new_turn, move.new_direction)
			_sync_game_state()
			
		else:
			print("DEBUG: Received unknown or incomplete move action: ", move)

# Submit a suit selection (for Ace)
func submit_suit_selection(suit: String):
	if !is_connected:
		print("DEBUG: Not connected to multiplayer session")
		return
		
	# Get local player position
	var player_index = get_local_player_position()
	
	# Check if it's this player's turn
	if player_index != current_turn:
		print("DEBUG: Not your turn to select suit!")
		return
		
	print("DEBUG: Submitting suit selection: ", suit)
	
	# If we're the host, process directly
	if is_host:
		_process_suit_selection(player_index, suit)
		_sync_game_state()
	else:
		# Client: Send to Firebase
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr:
			var move_data = {
				"action": "select_suit",
				"player_index": player_index,
				"suit": suit,
				"timestamp": Time.get_unix_time_from_system()
			}
			session_mgr.submit_move(move_data)
		
# Process suit selection
func _process_suit_selection(player_index: int, suit: String):
	print("DEBUG: Processing suit selection: ", suit, " from player ", player_index)
	
	# Check if current card is an Ace
	if current_card == null or current_card.value != "Ace":
		print("DEBUG: Cannot select suit - current card is not an Ace")
		return
		
	# Add chosen suit to the current card
	current_card["chosen_suit"] = suit
	print("DEBUG: Updated Ace with chosen suit: ", suit)
	
	# Switch turns
	var old_turn = current_turn
	var next_turn = int(current_turn) + int(game_direction)
	var num_players = int(player_hands.size())
	
	# Handle negative values manually instead of using modulo
	if next_turn >= num_players:
		next_turn = next_turn - num_players
	elif next_turn < 0:
		next_turn = num_players + next_turn
	
	current_turn = next_turn
	print("DEBUG: Turn switched from ", old_turn, " to ", current_turn, " after suit selection")

# Submit last card declaration
func submit_last_card_declaration():
	if !is_connected:
		print("DEBUG: Not connected to multiplayer session")
		return
		
	# Get local player position
	var player_index = get_local_player_position()
	
	# Check if it's this player's turn
	if player_index != current_turn:
		print("DEBUG: Not your turn to declare last card!")
		return
		
	print("DEBUG: Submitting last card declaration")
	
	# If we're the host, process directly
	if is_host:
		_process_last_card_declaration(player_index)
		_sync_game_state()
	else:
		# Client: Send to Firebase
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr:
			var move_data = {
				"action": "declare_last_card",
				"player_index": player_index,
				"timestamp": Time.get_unix_time_from_system()
			}
			session_mgr.submit_move(move_data)

# Process last card declaration
func _process_last_card_declaration(player_index: int):
	print("DEBUG: Processing last card declaration from player ", player_index)
	
	# Safety check for valid index and player_hands
	if player_index < 0 or player_index >= player_hands.size():
		print("DEBUG: Invalid player index for last card declaration: ", player_index)
		return
	
	# Check if player really has only one card left
	if player_hands[player_index].size() != 1:
		print("DEBUG: Player does not have exactly one card left")
		return
	
	# Safety check for current card
	if current_card == null:
		print("DEBUG: Cannot process last card declaration - no current card")
		return
		
	# Update game state to track this (could be stored in a custom field)
	if !current_card.has("last_card_declared"):
		current_card["last_card_declared"] = []
	
	# Add player to the list of those who declared last card
	if !current_card.last_card_declared.has(player_index):
		current_card.last_card_declared.append(player_index)
		print("DEBUG: Player ", player_index, " has declared last card")

# Submit turn change
func submit_turn_change(new_turn: int, new_direction: int):
	if !is_connected:
		print("DEBUG: Not connected to multiplayer session")
		return
		
	print("DEBUG: Submitting turn change from ", current_turn, " to ", new_turn)
	
	# If we're the host, process directly
	if is_host:
		_process_turn_change(new_turn, new_direction)
		_sync_game_state()
	else:
		# Client: Send to Firebase
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr:
			var move_data = {
				"action": "turn_change",
				"new_turn": new_turn,
				"new_direction": new_direction,
				"timestamp": Time.get_unix_time_from_system()
			}
			session_mgr.submit_move(move_data)

# Process turn change
func _process_turn_change(new_turn: int, new_direction: int):
	print("DEBUG: Processing turn change from ", current_turn, " to ", new_turn)
	
	current_turn = new_turn
	game_direction = new_direction
