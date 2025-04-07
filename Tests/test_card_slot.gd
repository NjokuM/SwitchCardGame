# In test_card_slot.gd
extends GutTest

func test_card_placement_rules():
	var card_slot_scene = load("res://Scripts/CardSlot.gd")
	var card_slot = card_slot_scene.new()
	
	# Create some test cards
	var card1 = load("res://scene/card.tscn").instantiate()
	card1.set_card_data("Ace", "Hearts")
	
	var card2 = load("res://scene/card.tscn").instantiate()
	card2.set_card_data("2", "Hearts")
	
	var card3 = load("res://scene/card.tscn").instantiate()
	card3.set_card_data("King", "Diamonds")
	
	# First card can always be placed
	assert_true(card_slot.can_place_card(card1), "First card should always be placeable")
	
	# Place the first card
	card_slot.place_card(card1)
	
	# Test matching suit
	assert_true(card_slot.can_place_card(card2), "Card with matching suit should be placeable")
	
	# Test matching value
	var card_same_value = load("res://scene/card.tscn").instantiate()
	card_same_value.set_card_data("Ace", "Diamonds")
	assert_true(card_slot.can_place_card(card_same_value), "Card with matching value should be placeable")
	
	# Test non-matching card
	assert_false(card_slot.can_place_card(card3), "Card with different suit and value should not be placeable")
