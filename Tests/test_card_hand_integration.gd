# Tests/card_hand_integration_test.gd
extends GutTest

# This test verifies the integration between the Card and Hand components
# It tests adding cards to hands, card selection, positioning, and removal

var hand_scene = load("res://scene/hand.tscn")
var card_scene = load("res://scene/card.tscn")

# Setup function runs before each test
func before_each():
	# Clear the test area
	
	# Initialize the game settings for consistent testing
	GameSettings.num_players = 2
	
	# Create a mock Main node with GameManager
	var mock_main = Node.new()
	mock_main.name = "Main"
	
	var mock_game_manager = Node.new()
	mock_game_manager.name = "GameManager"
	# Add a method to handle card clicks
	mock_game_manager.set_script(GDScript.new())
	mock_game_manager.get_script().source_code = """
	extends Node
	func _on_card_clicked(card):
		# Mock implementation
		pass
	"""
	mock_game_manager.get_script().reload()
	
	add_child(mock_main)
	mock_main.add_child(mock_game_manager)
	
# Function to create a test card with given value and suit
func create_test_card(value: String, suit: String) -> Node2D:
	var card = card_scene.instantiate()
	add_child(card)
	card.set_card_data(value, suit)
	return card

# Test adding a card to a hand and verifying it exists in the hand
func test_add_card_to_hand():
	# Create a hand
	var hand = hand_scene.instantiate()
	add_child(hand)
	hand.player_position = 0
	hand.is_player = true
	
	# Create a test card
	var card = create_test_card("Ace", "Hearts")
	
	# Add the card to the hand
	hand.add_card(card, 0.1)
	
	# Wait for any animations to complete
	await get_tree().create_timer(0.2).timeout
	
	# Assertions
	assert_eq(hand.hand.size(), 1, "Hand should contain 1 card")
	assert_true(hand.hand.has(card), "Hand should contain the added card")
	assert_eq(card.get_parent(), hand, "Card's parent should be the hand")

# Test removing a card from a hand
func test_remove_card_from_hand():
	# Create a hand and add a card
	var hand = hand_scene.instantiate()
	add_child(hand)
	hand.player_position = 0
	
	var card = create_test_card("King", "Spades")
	hand.add_card(card, 0.1)
	
	# Wait for adding animation
	await get_tree().create_timer(0.2).timeout
	
	# Initial assertion
	assert_eq(hand.hand.size(), 1, "Hand should start with 1 card")
	
	# Remove the card
	var result = hand.remove_card(card)
	
	# Wait for removal animation
	await get_tree().create_timer(0.2).timeout
	
	# Assertions
	assert_true(result, "remove_card should return true for successful removal")
	assert_eq(hand.hand.size(), 0, "Hand should be empty after removal")
	assert_ne(card.get_parent(), hand, "Card should no longer be a child of hand")

# Test that cards in hand are properly positioned
func test_card_positioning_in_hand():
	# Create a hand
	var hand = hand_scene.instantiate()
	add_child(hand)
	hand.player_position = 0
	
	# Add multiple cards
	var card1 = create_test_card("2", "Hearts")
	var card2 = create_test_card("3", "Clubs")
	var card3 = create_test_card("4", "Diamonds")
	
	hand.add_card(card1, 0.1)
	hand.add_card(card2, 0.1)
	hand.add_card(card3, 0.1)
	
	# Wait for positioning animations
	await get_tree().create_timer(0.3).timeout
	
	# Assertions - cards should have different x positions
	assert_ne(card1.position.x, card2.position.x, "Cards should have different x positions")
	assert_ne(card2.position.x, card3.position.x, "Cards should have different x positions")
	assert_ne(card1.position.x, card3.position.x, "Cards should have different x positions")
	
	# The y positions should be the same for all cards in a horizontal layout
	assert_eq(card1.position.y, card2.position.y, "Cards should have the same y position")
	assert_eq(card2.position.y, card3.position.y, "Cards should have the same y position")

# Test updating card visibility based on player status
func test_hand_visibility_updates():
	# Create a hand
	var hand = hand_scene.instantiate()
	add_child(hand)
	hand.player_position = 0
	
	# Add a card
	var card = create_test_card("Queen", "Diamonds")
	hand.add_card(card, 0.1)
	
	# Wait for animation
	await get_tree().create_timer(0.2).timeout
	
	# Test visibility when is_player = true (show card faces)
	hand.is_player = true
	hand.update_visibility(true)
	
	# Check if card face is visible with the correct texture
	assert_true(card.visible, "Card should be visible")
	assert_true(card.get_node("CardFaceImage").visible, "Card face should be visible")
	assert_eq(card.get_node("CardFaceImage").texture, card.face_texture, "Card should show face texture")
	
	# Test visibility when is_player = false (show card backs)
	hand.is_player = false
	hand.update_visibility(false)
	
	# Card should still be visible but showing back texture
	assert_true(card.visible, "Card should still be visible")
	assert_true(card.get_node("CardFaceImage").visible, "Card face image should be visible")
	assert_ne(card.get_node("CardFaceImage").texture, card.face_texture, "Card should not show face texture")

# Test that removing multiple cards works correctly
func test_remove_multiple_cards():
	# Create a hand
	var hand = hand_scene.instantiate()
	add_child(hand)
	hand.player_position = 0
	
	# Create cards
	var cards = []
	for i in range(5):
		var card = create_test_card(str(i+2), "Hearts")
		cards.append(card)
		hand.add_card(card, 0.1)
	
	# Wait for animations
	await get_tree().create_timer(0.3).timeout
	
	# Verify initial state
	assert_eq(hand.hand.size(), 5, "Hand should contain 5 cards")
	
	# Remove cards 0, 2, and 4
	hand.remove_card(cards[0])
	hand.remove_card(cards[2])
	hand.remove_card(cards[4])
	
	# Wait for repositioning
	await get_tree().create_timer(0.3).timeout
	
	# Verify final state
	assert_eq(hand.hand.size(), 2, "Hand should have 2 cards remaining")
	assert_true(hand.hand.has(cards[1]), "Hand should still have card 1")
	assert_true(hand.hand.has(cards[3]), "Hand should still have card 3")
	
	# The remaining cards should be repositioned
	assert_ne(cards[1].position, cards[3].position, "Remaining cards should be repositioned")
