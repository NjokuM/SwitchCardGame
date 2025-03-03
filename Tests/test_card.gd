# test_card.gd
extends GutTest

func test_card_creation():
	var card_scene = load("res://scene/card.tscn")
	var card = card_scene.instantiate()
	add_child(card)
	
	card.set_card_data("Ace", "Hearts")
	assert_eq(card.value, "Ace", "Card value should be set properly")
	assert_eq(card.suit, "Hearts", "Card suit should be set properly")
	assert_eq(card.is_selected, false, "Card should not be selected by default")
	assert_eq(card.is_card_in_card_slot, false, "Card should not be in slot by default")
	
	card.queue_free()
