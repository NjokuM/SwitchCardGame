# Tests/card_slot_integration_test.gd
extends GutTest

# This test verifies the integration between the Card and CardSlot components
# It tests placing cards in the slot and checking card placement rules

func test_placing_card_in_empty_slot():
	# Create card slot
	var card_slot_script = load("res://Scripts/CardSlot.gd")
	var card_slot = card_slot_script.new()
	add_child(card_slot)
	
	# Create test card
	var card_scene = load("res://scene/card.tscn")
	var card = card_scene.instantiate()
	add_child(card)
	card.set_card_data("7", "Hearts")
	
	# Place card in the slot
	card_slot.place_card(card)
	
	# Verify card is in the slot
	assert_eq(card_slot.get_last_played_card(), card, "Card should be placed in the slot")
	assert_true(card.is_card_in_card_slot, "Card should be marked as in the slot")
	assert_eq(card.position, Vector2.ZERO, "Card should be centered in the slot")
	
	# Cleanup
	card_slot.queue_free()

func test_can_place_card_rules():
	# Create card slot
	var card_slot_script = load("res://Scripts/CardSlot.gd")
	var card_slot = card_slot_script.new()
	add_child(card_slot)
	
	# Create first card (to place in slot)
	var card_scene = load("res://scene/card.tscn")
	var first_card = card_scene.instantiate()
	add_child(first_card)
	first_card.set_card_data("7", "Hearts")
	
	# Place first card in the slot
	card_slot.place_card(first_card)
	
	# Test cards that should be placeable (same suit)
	var same_suit_card = card_scene.instantiate()
	add_child(same_suit_card)
	same_suit_card.set_card_data("2", "Hearts")
	assert_true(card_slot.can_place_card(same_suit_card), "Should be able to place card with same suit")
	
	# Test cards that should be placeable (same value)
	var same_value_card = card_scene.instantiate()
	add_child(same_value_card)
	same_value_card.set_card_data("7", "Clubs")
	assert_true(card_slot.can_place_card(same_value_card), "Should be able to place card with same value")
	
	# Test cards that should not be placeable (different suit and value)
	var different_card = card_scene.instantiate()
	add_child(different_card)
	different_card.set_card_data("10", "Spades")
	assert_false(card_slot.can_place_card(different_card), "Should not be able to place card with different suit and value")
	
	# Test Ace placement rule (can always be played)
	var ace_card = card_scene.instantiate()
	add_child(ace_card)
	ace_card.set_card_data("Ace", "Diamonds")
	assert_true(card_slot.can_place_card(ace_card), "Should be able to place an Ace on any card")
	
	# Cleanup
	card_slot.queue_free()
	first_card.queue_free()
	same_suit_card.queue_free()
	same_value_card.queue_free()
	different_card.queue_free()
	ace_card.queue_free()

func test_ace_suit_selection():
	# Create card slot
	var card_slot_script = load("res://Scripts/CardSlot.gd")
	var card_slot = card_slot_script.new()
	add_child(card_slot)
	
	# Create ace card
	var card_scene = load("res://scene/card.tscn")
	var ace_card = card_scene.instantiate()
	add_child(ace_card)
	ace_card.set_card_data("Ace", "Diamonds")
	
	# Place ace in the slot
	card_slot.place_card(ace_card)
	
	# Set chosen suit for the ace
	ace_card.set_chosen_suit("Clubs")
	
	# Create a card that matches the chosen suit
	var matching_suit_card = card_scene.instantiate()
	add_child(matching_suit_card)
	matching_suit_card.set_card_data("5", "Clubs")
	
	# Create a card that doesn't match the chosen suit
	var non_matching_card = card_scene.instantiate()
	add_child(non_matching_card)
	non_matching_card.set_card_data("5", "Hearts")
	
	# Verify that only cards matching the chosen suit can be played
	assert_true(card_slot.can_place_card(matching_suit_card), "Should be able to place card matching Ace's chosen suit")
	assert_false(card_slot.can_place_card(non_matching_card), "Should not be able to place card that doesn't match Ace's chosen suit")
	
	# Cleanup
	card_slot.queue_free()
	ace_card.queue_free()
	matching_suit_card.queue_free()
	non_matching_card.queue_free()
