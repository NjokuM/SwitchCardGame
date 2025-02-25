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
	print("DEBUG: Checking if can place card")
	print("DEBUG: Card type:", typeof(card))
	
	# More thorough property checks
	if card == null:
		print("DEBUG: Card is null")
		return false
		
	# Do NOT access properties yet - check if they exist first
	if not card.get("value"):
		print("DEBUG: Card missing 'value' property")
		if card.has_method("get_value"):
			print("DEBUG: Card has get_value() method")
			# Could try using a method instead
		return false
		
	if not card.get("suit"):
		print("DEBUG: Card missing 'suit' property")
		return false
	
	# Now it's safe to access the properties
	var card_value = card.value
	var card_suit = card.suit
	
	# Aces can be played anytime
	if card_value == "Ace":
		return true
		
	if last_played_card == null:
		print("No card in slot yet, can play any card")
		return true  # First card can be anything
	
	# Check last_played_card properties safely
	if not last_played_card.get("value") or not last_played_card.get("suit"):
		print("DEBUG: Last played card missing properties")
		return false
	
	# Debug prints
	print("Last played card: ", last_played_card.value, " of ", last_played_card.suit)
	print("Attempting to play: ", card_value, " of ", card_suit)
	
	# Check if the new card matches either the suit or value of the last played card
	var suit_matches = card_suit == last_played_card.suit
	var value_matches = card_value == last_played_card.value
	
	print("Suit matches: ", suit_matches)
	print("Value matches: ", value_matches)
	
	return suit_matches or value_matches

func place_card(card: Node2D):
	print("DEBUG: Attempting to place card")
	
	# First do a safety check without accessing potentially missing properties
	if card == null:
		print("DEBUG: Card is null in place_card")
		return
	
	# Try can_place_card in a safe way
	var can_place = false
	# We can't use try/except in GDScript 4, so we'll check differently
	if card.get("value") != null and card.get("suit") != null:
		can_place = can_place_card(card)
	else:
		print("DEBUG: Card missing properties in place_card")
		# Still allow first card to be placed
		can_place = last_played_card == null
	
	if not can_place:
		print("❌ Cannot place this card!")
		return
		
	# Add the card as a child of the CardSlot if it isn't already
	if card.get_parent() != self:
		if card.get_parent():
			card.get_parent().remove_child(card)
		add_child(card)
	
	# Position the card at the slot location
	card.position = Vector2.ZERO
	card.z_index = 10
	card.visible = true
	
	# Safely set card state
	if card.get("is_card_in_card_slot") != null:
		card.is_card_in_card_slot = true
	
	# Hide previous card if it exists
	if last_played_card and last_played_card != card:
		last_played_card.visible = false
	
	# Update the last played card
	last_played_card = card
	
	# Safely print card details
	var card_value = card.get("value")
	var card_suit = card.get("suit")
	if card_value and card_suit:
		print("✅ Card placed in slot:", card_value, "of", card_suit)
	else:
		print("✅ Card placed in slot (details unavailable)")

func _on_area_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("slot_clicked")

func get_last_played_card() -> Node2D:
	return last_played_card
