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
	await get_tree().create_timer(1.0).timeout

# Additional unit tests for card functionality
func test_card_selection():
	var card_scene = load("res://scene/card.tscn")
	var card = card_scene.instantiate()
	add_child(card)
	card.set_card_data("Ace", "Hearts")
	card.select()
	assert_eq(card.is_selected, true, "Card should be selected after calling select()")
	card.deselect()
	assert_eq(card.is_selected, false, "Card should be deselected after calling deselect()")
	card.queue_free()
	await get_tree().create_timer(1.0).timeout

func test_card_suit_change():
	var card_scene = load("res://scene/card.tscn")
	var card = card_scene.instantiate()
	add_child(card)
	
	card.set_card_data("Ace", "Hearts")
	card.set_chosen_suit("Spades")
	assert_eq(card.chosen_suit, "Spades", "Ace should reflect the new chosen suit")
	
	card.queue_free()
	await get_tree().create_timer(1.0).timeout
