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
	var is_networked = network and network.multiplayer and network.player_info.size() > 0
	
	if !is_networked or network.multiplayer.is_server():
		# Server controls initial dealing
		for i in range(CARDS_PER_PLAYER):
			for j in range(game_manager.num_players):
				SoundManager.play_card_draw_sound()
				await get_tree().create_timer(CARD_DRAW_SPEED).timeout
				var card = deal_card_to_player(j)
				
				# Broadcast the deal in networked mode
				if is_networked and card:
					sync_deal_card.rpc(j, card.value, card.suit)
	
	print("Initial cards have been dealt")

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
	SoundManager.play_card_draw_sound()
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
	var network = get_node_or_null("/root/NetworkManager")
	var is_networked = network and network.multiplayer and network.player_info.size() > 0
	
	if !is_networked or network.multiplayer.is_server():
		var card = draw_card_for_slot()
		while card and game_manager.is_power_card(card):
			# Put power card back and draw another
			return_card_to_deck(card)
			card = draw_card_for_slot()
			
		# Broadcast initial card in networked mode
		if is_networked and card:
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
