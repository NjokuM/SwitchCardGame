# Tests/simple_hand_card_test.gd
extends GutTest

# This test verifies basic hand-card integration without depending on GameManager
# It patches the hand.add_card method to avoid connecting signals to GameManager

func _create_mocked_hand():
	var hand_scene = load("res://scene/hand.tscn")
	var hand = hand_scene.instantiate()
	
	# Create a patched version of add_card that doesn't connect signals
	var add_card_func = hand.add_card
	hand.add_card = func(card, speed):
		if card not in hand.hand:
			hand.hand.append(card)
			hand.add_child(card)
			# Skip the signal connection to GameManager
			hand.update_positions(speed)
			
			# Update card visibility as soon as it's added
			if !hand.is_player:
				# Hide card face for opponents' cards
				card.get_node("CardFaceImage").texture = hand.BACK_OF_CARD_TEXTURE
		else:
			print("❌ Error: Duplicate card detected!")
			
	return hand

func test_add_and_remove_cards():
	# Create mocked hand
	var hand = _create_mocked_hand()
	add_child(hand)
	
	# Create some test cards
	var card_scene = load("res://scene/card.tscn")
	var cards = []
	
	for i in range(3):
		var card = card_scene.instantiate()
		card.set_card_data(str(i+2), "Hearts") 
		cards.append(card)
	
	# Test adding cards
	for card in cards:
		hand.add_card(card, 0.1)
	
	# Assert cards are in hand
	assert_eq(hand.hand.size(), 3, "Hand should have 3 cards")
	
	# Test removing a card
	hand.remove_card(cards[1])
	await get_tree().create_timer(0.2).timeout
	
	# Assert one card was removed
	assert_eq(hand.hand.size(), 2, "Hand should have 2 cards after removal")
	assert_true(hand.hand.has(cards[0]), "First card should still be in hand")
	assert_true(hand.hand.has(cards[2]), "Third card should still be in hand")
	assert_false(hand.hand.has(cards[1]), "Second card should be removed from hand")
	
	# Cleanup
	for card in cards:
		card.queue_free()
	hand.queue_free()

func test_card_visibility():
	# Create mocked hand
	var hand = _create_mocked_hand()
	add_child(hand)
	
	# Create test card
	var card_scene = load("res://scene/card.tscn")
	var card = card_scene.instantiate()
	card.set_card_data("King", "Diamonds")
	
	# Add card to hand
	hand.add_card(card, 0.1)
	
	# Test visibility for player's hand
	hand.is_player = true
	hand.update_visibility(true)
	assert_eq(card.get_node("CardFaceImage").texture, card.face_texture, "Player's card should show face")
	
	# Test visibility for opponent's hand
	hand.is_player = false
	hand.update_visibility(false)
	assert_ne(card.get_node("CardFaceImage").texture, card.face_texture, "Opponent's card should not show face")
	
	# Cleanup
	card.queue_free()
	hand.queue_free()

func test_hand_repositioning():
	# Create mocked hand
	var hand = _create_mocked_hand()
	add_child(hand)
	
	# Create some test cards
	var card_scene = load("res://scene/card.tscn")
	var cards = []
	
	for i in range(5):
		var card = card_scene.instantiate()
		card.set_card_data(str(i+2), "Clubs") 
		cards.append(card)
		hand.add_card(card, 0.1)
	
	await get_tree().create_timer(0.2).timeout
	
	# Store original positions
	var original_positions = []
	for card in cards:
		original_positions.append(card.position)
	
	# Remove middle card
	hand.remove_card(cards[2])
	
	await get_tree().create_timer(0.2).timeout
	
	# Verify positions have changed
	for i in range(cards.size()):
		if i != 2:  # Skip the removed card
			assert_ne(cards[i].position, original_positions[i], 
				"Card positions should be updated after removal")
	
	# Cleanup
	for card in cards:
		card.queue_free()
	hand.queue_free()
