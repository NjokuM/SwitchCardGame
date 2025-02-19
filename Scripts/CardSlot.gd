extends Node2D

signal slot_clicked
var last_played_card: Node2D  # Store the actual card node

func _ready():
	# Add click detection for the slot
	var area = Area2D.new()
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(140, 190)
	collision.shape = shape
	area.add_child(collision)
	add_child(area)
	
	area.input_event.connect(_on_area_input_event)

func can_place_card(card: Node2D) -> bool:
	# Aces can be played anytime
	if "value" in card and card.value == "Ace":
		return true
		
	if last_played_card == null:
		print("No card in slot yet, can play any card")
		return true  # First card can be anything
		
	# Make sure the cards have the required properties
	if not ("value" in card and "suit" in card and "value" in last_played_card and "suit" in last_played_card):
		print("❌ Cards are missing required properties!")
		return false
		
	# Debug prints
	print("Last played card: ", last_played_card.value, " of ", last_played_card.suit)
	print("Attempting to play: ", card.value, " of ", card.suit)
	
	# Check if the new card matches either the suit or value of the last played card
	var suit_matches = card.suit == last_played_card.suit
	var value_matches = card.value == last_played_card.value
	
	print("Suit matches: ", suit_matches)
	print("Value matches: ", value_matches)
	
	return suit_matches or value_matches

func place_card(card: Node2D):
	if not can_place_card(card):
		print("❌ Cannot place this card!")
		return
		
	# Add the card as a child of the CardSlot if it isn't already
	if card.get_parent() != self:
		if card.get_parent():
			card.get_parent().remove_child(card)
		add_child(card)
	
	# Reset the card's position relative to the CardSlot
	card.position = Vector2.ZERO
	card.z_index = 10
	card.visible = true
	if "is_card_in_card_slot" in card:
		card.is_card_in_card_slot = true  # Set the card's slot status
	
	# Update the last played card
	last_played_card = card
	print("✅ Card placed in slot:", card.value, "of", card.suit)

func _on_area_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("slot_clicked")

func get_last_played_card() -> Node2D:
	return last_played_card
