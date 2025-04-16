# Tests/card_deck_integration_test.gd
extends GutTest

# This test verifies the integration between the Card and Deck components
# It tests deck initialization, shuffling, and card drawing

func test_deck_initialization_and_card_creation():
	# Load the deck script directly
	var deck_script = load("res://Scripts/Deck.gd")
	var deck = deck_script.new()
	add_child(deck)
	
	# Initialize deck
	deck.initialize_deck()
	
	# Check initial deck state
	assert_eq(deck.deck.size(), 52, "Deck should contain 52 cards")
	
	# Check that each card in the deck is unique
	var unique_cards = {}
	for card_data in deck.deck:
		var card_id = card_data.value + "_of_" + card_data.suit
		assert_false(unique_cards.has(card_id), "Deck shouldn't have duplicate cards")
		unique_cards[card_id] = true
	
	# Check that we have the right distribution of cards
	var suit_count = {"Hearts": 0, "Diamonds": 0, "Clubs": 0, "Spades": 0}
	var value_count = {}
	for value in deck.VALUES:
		value_count[value] = 0
	
	for card_data in deck.deck:
		suit_count[card_data.suit] += 1
		value_count[card_data.value] += 1
	
	# Check that we have 13 cards of each suit
	for suit in suit_count.keys():
		assert_eq(suit_count[suit], 13, "Should have 13 cards of suit " + suit)
	
	# Check that we have 4 cards of each value
	for value in value_count.keys():
		assert_eq(value_count[value], 4, "Should have 4 cards of value " + value)
	
	# Cleanup
	deck.queue_free()

func test_deck_shuffle():
	# Load the deck script directly
	var deck_script = load("res://Scripts/Deck.gd")
	var deck = deck_script.new()
	add_child(deck)
	
	# Initialize deck
	deck.initialize_deck()
	
	# Store original order
	var original_order = deck.deck.duplicate(true)
	
	# Shuffle deck
	deck.shuffle_deck()
	
	# Check that deck is still the same size
	assert_eq(deck.deck.size(), 52, "Shuffled deck should still have 52 cards")
	
	# Check that the order has changed (this could theoretically fail by chance, but very unlikely)
	var same_positions = 0
	for i in range(deck.deck.size()):
		if i < original_order.size() and deck.deck[i].value == original_order[i].value and deck.deck[i].suit == original_order[i].suit:
			same_positions += 1
	
	# We'll say shuffle is successful if less than 90% of cards stay in the same position
	assert_lt(same_positions, 47, "Shuffling should change the order of most cards")
	
	# Cleanup
	deck.queue_free()

func test_creating_card_from_data():
	# Load the deck script directly
	var deck_script = load("res://Scripts/Deck.gd")
	var deck = deck_script.new()
	add_child(deck)
	
	# Create a card using deck's method
	var test_card = deck.create_card_from_data("Ace", "Spades")
	
	# Verify the card is created with correct data
	assert_not_null(test_card, "Card should be created")
	assert_eq(test_card.value, "Ace", "Card should have value Ace")
	assert_eq(test_card.suit, "Spades", "Card should have suit Spades")
	
	# Cleanup
	test_card.queue_free()
	deck.queue_free()
