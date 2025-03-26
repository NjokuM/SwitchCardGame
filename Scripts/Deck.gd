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
var session_sync = null

@onready var game_manager = $"../GameManager"
@onready var card_slot = $"../CardSlot"

func _ready() -> void:
	await get_tree().process_frame
	
	# Get SessionSync reference
	session_sync = get_node_or_null("/root/Main/GameManager/SessionSync")
	if not session_sync:
		session_sync = get_node_or_null("/root/SessionSync")
	
	if session_sync:
		# Connect to SessionSync signals
		session_sync.game_state_synchronized.connect(_on_game_state_synchronized)
		session_sync.cards_drawn.connect(_on_cards_drawn)
		print("Deck connected to SessionSync")
	else:
		print("SessionSync not found, running in local mode")
		initialize_deck()
		shuffle_deck()
	
	# Position the deck
	position_deck()
	
	# Connect to window resize signals
	get_tree().root.size_changed.connect(position_deck)

func _on_game_state_synchronized():
	# This is called when the SessionSync has updated the game state from Firebase
	print("Deck updating from synchronized game state")
	
	# In networked mode, deck is managed by SessionSync and we just visualize it
	if is_using_session_sync():
		# No local deck manipulation needed - SessionSync handles this
		print("Using SessionSync for deck management")
	else:
		# Local mode initialization if needed
		if deck.size() == 0:
			initialize_deck()
			shuffle_deck()

func _on_cards_drawn(player_index, card_count):
	# This is called when SessionSync signals that cards have been drawn
	print("Cards drawn: " + str(card_count) + " for player " + str(player_index))
	
	# Don't need to modify the deck locally - SessionSync handles this
	# We just need to create visual cards for the local player
	
	if is_using_session_sync() and session_sync.get_local_player_position() == player_index:
		# Get the updated hand from SessionSync
		var hand = session_sync.get_player_hand(player_index)
		var current_hand_size = game_manager.hands[player_index].hand.size()
		
		# If the hand size has increased, create visual cards for the new cards
		if hand.size() > current_hand_size:
			var cards_to_add = hand.size() - current_hand_size
			for i in range(cards_to_add):
				var card_data = hand[current_hand_size + i]
				var new_card = CARD_SCENE.instantiate()
				new_card.set_card_data(card_data.value, card_data.suit)
				game_manager.hands[player_index].add_card(new_card, CARD_DRAW_SPEED)
	
func is_using_session_sync() -> bool:
	return session_sync != null

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
	# Only shuffle if we're in local mode or we're the host
	if is_using_session_sync():
		# In networked mode, don't shuffle locally - SessionSync handles this
		print("Using SessionSync for deck shuffling")
		return

	# Local mode shuffling
	deck.shuffle()
	print("✅ Deck shuffled locally")

# Deal initial cards (used in local mode only)
func deal_initial_cards() -> void:
	# In networked mode, SessionSync handles card dealing
	if is_using_session_sync():
		print("Using SessionSync for initial card dealing")
		return
	
	# Local game logic
	print("Dealing initial cards locally")
	for i in range(CARDS_PER_PLAYER):
		for j in range(game_manager.num_players):
			# Add delay between dealing
			await get_tree().create_timer(CARD_DRAW_SPEED).timeout
			deal_card_to_player(j)
	
	# Draw valid starting card
	var card = draw_valid_starting_card()
	if card:
		card_slot.place_card(card)
	
	print("Initial cards have been dealt")

# Used in local mode to deal a card to a player
func deal_card_to_player(player_index: int):
	if is_using_session_sync():
		# In networked mode, SessionSync handles card dealing
		return null

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

# Used by GameManager to draw a card
func draw_card(player_index: int):
	# If using SessionSync, submit card draw action through it
	if is_using_session_sync():
		if session_sync.get_local_player_position() == player_index:
			session_sync.submit_card_draw(player_index)
		return null
	
	# Local mode logic
	print("DEBUG: Draw request for Player " + str(player_index + 1))
	
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

# Used in local mode for the initial valid card
func draw_valid_starting_card():
	if is_using_session_sync():
		# In networked mode, SessionSync handles initial card
		print("Using SessionSync for initial card")
		return null
	
	# Local mode logic
	var card = draw_card_for_slot()
	while card and game_manager.is_power_card(card):
		# Put power card back and draw another
		return_card_to_deck(card)
		card = draw_card_for_slot()
		
	return card
	
func draw_card_for_slot():
	if is_using_session_sync():
		# In networked mode, SessionSync handles this
		return null

	if deck.is_empty():
		reshuffle_discard_pile()
		if deck.is_empty():
			print("❌ No cards left for slot!")
			return null

	var card_data = deck.pop_front()
	var new_card = CARD_SCENE.instantiate()
	new_card.set_card_data(card_data["value"], card_data["suit"])

	return new_card

# Helper to create a card from data - useful for visualizing SessionSync game state
func create_card_from_data(value: String, suit: String) -> Node2D:
	var new_card = CARD_SCENE.instantiate()
	new_card.set_card_data(value, suit)
	return new_card
	
func return_card_to_deck(card: Node2D):
	if is_using_session_sync():
		# In networked mode, SessionSync handles deck management
		return

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
	if is_using_session_sync():
		# In networked mode, SessionSync handles reshuffling
		return false
		
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
	if is_using_session_sync():
		# In networked mode, SessionSync handles the discard pile
		return
		
	discard_pile.append(card_data)
	
# Helper functions
func get_deck_size() -> int:
	return deck.size()
	
func get_discard_pile_size() -> int:
	return discard_pile.size()
