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
	
	# Initial positioning
	center_position()
	
	# Connect to window resize signals
	get_tree().root.size_changed.connect(center_position)

# Function to center the card slot on screen
func center_position():
	var screen_size = get_viewport_rect().size
	position = Vector2(screen_size.x / 2, screen_size.y / 2)
	print("Card slot positioned at center:", position)

func can_place_card(card: Node2D) -> bool:
	# Safety checks
	if not card or not ("value" in card) or not ("suit" in card):
		print("DEBUG: Card missing required properties")
		return false
	
	# Aces can be played anytime
	if card.value == "Ace":
		return true
		
	if last_played_card == null:
		print("No card in slot yet, can play any card")
		return true  # First card can be anything
	
	# Safety checks for last_played_card
	if not last_played_card or not ("value" in last_played_card) or not ("suit" in last_played_card):
		print("DEBUG: Last played card missing properties")
		return false
	
	# Check if the last card was an Ace with a chosen suit
	if last_played_card.value == "Ace" and last_played_card.get("chosen_suit") and last_played_card.chosen_suit != "":
		var suit_matches = card.suit == last_played_card.chosen_suit
		print("Ace with chosen suit:", last_played_card.chosen_suit)
		print("Card suit matches chosen suit:", suit_matches)
		return suit_matches
	
	# Normal card matching
	var suit_matches = card.suit == last_played_card.suit
	var value_matches = card.value == last_played_card.value
	
	print("Last played card: ", last_played_card.value, " of ", last_played_card.suit)
	print("Attempting to play: ", card.value, " of ", card.suit)
	print("Suit matches:", suit_matches)
	print("Value matches:", value_matches)
	
	return suit_matches or value_matches

func place_card(card: Node2D):
		
	# First do a safety check without accessing potentially missing properties
	if card == null:
		print("DEBUG: Card is null in place_card")
		return
	
	# Try can_place_card in a safe way
	var can_place = false
	if card.get("value") != null and card.get("suit") != null:
		can_place = can_place_card(card)
	else:
		print("DEBUG: Card missing properties in place_card")
		# Still allow first card to be placed
		can_place = last_played_card == null
	
	if not can_place:
		print("❌ Cannot place this card!")
		return
		
	# Add the previous card to the discard pile before replacing it
	if last_played_card and last_played_card != card:
		add_to_discard_pile(last_played_card)
		
	# Add the card as a child of the CardSlot if it isn't already
	if card.get_parent() != self:
		if card.get_parent():
			card.get_parent().remove_child(card)
		add_child(card)
	
	# Position the card at the center of the CardSlot (0,0 local position)
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

# Add this function to add cards to the discard pile
func add_to_discard_pile(card: Node2D):
	if card and card.get("value") != null and card.get("suit") != null:
		var card_data = {
			"value": card.value,
			"suit": card.suit
		}
		$"../Deck".add_to_discard_pile(card_data)
