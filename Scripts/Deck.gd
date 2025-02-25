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
func _ready() -> void:
	await get_tree().process_frame
	initialize_deck()
	shuffle_deck()
func initialize_deck():
	deck.clear()
	for suit in SUITS:
		for value in VALUES:
			deck.append({"value": value, "suit": suit})
func shuffle_deck():
	deck.shuffle()
	print("✅ Deck shuffled")
func deal_initial_cards() -> void:
	for i in range(CARDS_PER_PLAYER):
		for j in range(game_manager.num_players):
			await get_tree().create_timer(CARD_DRAW_SPEED).timeout
			deal_card_to_player(j)
	print("Initial cards have been dealt")
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
func draw_card(player_index: int):
	print("DEBUG: Draw request for Player " + str(player_index + 1))
	print("DEBUG: Current turn is Player " + str(game_manager.current_turn + 1))
	
	# Critical fix: Don't check turn here, trust the player_index passed in
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
	
	# Important: Don't switch turns here, let GameManager handle it
	return new_card
	
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
	if discard_pile.is_empty():
		print("❌ No cards in discard pile to reshuffle!")
		return

	print("Reshuffling discard pile into deck...")

	# Move all cards except the top card from card_slot to the deck
	var top_card = discard_pile.pop_back()
	deck = discard_pile.duplicate()
	discard_pile.clear()
	if top_card:
		discard_pile.append(top_card)

	shuffle_deck()
	print("✅ Discard pile reshuffled into deck")
func add_to_discard_pile(card_data: Dictionary):
	discard_pile.append(card_data)
# Helper function to get current deck size
func get_deck_size() -> int:
	return deck.size()
# Helper function to get discard pile size
func get_discard_pile_size() -> int:
	return discard_pile.size()
