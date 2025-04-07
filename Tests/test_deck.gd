# In test_deck.gd
extends GutTest

func test_deck_initialization():
	var deck_scene = load("res://Scripts/Deck.gd")
	var deck = deck_scene.new()
	
	# Test initial deck size
	deck.initialize_deck()
	assert_eq(deck.deck.size(), 52, "Deck should be initialized with 52 cards")
	
	# Test deck shuffling
	var original_deck = deck.deck.duplicate()
	deck.shuffle_deck()
	assert_eq(deck.deck.size(), 52, "Shuffling should not change deck size")
	assert_false(deck.deck == original_deck, "Deck should be randomized after shuffling")
	
	wait_seconds(5.0)  # Wait for 2 seconds before closing
