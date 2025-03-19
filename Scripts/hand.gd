extends Node2D

@export var player_position: int = 0
@export var is_player: bool = false  # Whether this is the local player's hand
const CARD_WIDTH = 110
const CARD_SPACING = 35
const DEFAULT_CARD_MOVE_SPEED = 0.33
const BACK_OF_CARD_TEXTURE = preload("res://assets/BACK.png")

var hand = []
var center_screen_x

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2
	
	# Connect to window resize signals
	get_tree().root.size_changed.connect(func(): 
		center_screen_x = get_viewport().size.x / 2
		update_positions(0.2)
	)

func add_card(card: Node2D, speed: float):
	if card not in hand:
		hand.append(card)
		add_child(card)
		card.pressed.connect(get_node("/root/Main/GameManager")._on_card_clicked.bind(card))
		
		# Set visibility right away based on whether this is the local player's hand
		if card.has_method("set_in_hand"):
			card.set_in_hand(is_player)
		else:
			# Fallback to direct texture manipulation
			if !is_player:
				card.get_node("CardFaceImage").texture = BACK_OF_CARD_TEXTURE
		
		update_positions(speed)
		print("✅ Card added:", card.value, "of", card.suit, "to Player", player_position + 1)
	else:
		print("❌ Error: Duplicate card detected!")
func update_positions(speed):
	# Calculate total width needed for all cards with spacing
	var total_width = (hand.size() * (CARD_WIDTH + CARD_SPACING)) - CARD_SPACING
	var start_x = -total_width / 2  # Center the hand
	
	for i in range(hand.size()):
		var new_position = Vector2(
			start_x + (i * (CARD_WIDTH + CARD_SPACING)),
			0  # Keep Y at 0 relative to hand position
		)
		move_card(hand[i], new_position, speed)

func move_card(card: Node2D, new_position: Vector2, speed: float):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed)

func remove_card(card: Node2D):
	if card in hand:
		# Remove the card from our array and parent
		hand.erase(card)
		if card.get_parent() == self:
			remove_child(card)
			
		# Allow card to settle in the slot first, then update hand positions
		get_tree().create_timer(0.1).timeout.connect(func(): update_positions(DEFAULT_CARD_MOVE_SPEED))
		
		return true
	
	return false
		

# Improved function to handle card visibility
func update_visibility(show_card_faces: bool):
	
	for card in hand:
		# Cards are always visible, but we change their texture
		card.visible = true
		
		if show_card_faces:
			# Show the actual card face
			card.get_node("CardFaceImage").visible = true
			card.get_node("CardFaceImage").texture = card.face_texture
			if card.has_node("CardBackImage"):
				card.get_node("CardBackImage").visible = false
			print("Showing face for card: ", card.value, " of ", card.suit)
		else:
			# Show the card back
			card.get_node("CardFaceImage").visible = true
			card.get_node("CardFaceImage").texture = BACK_OF_CARD_TEXTURE
			if card.has_node("CardBackImage"):
				card.get_node("CardBackImage").visible = false
			print("Showing back for card in player ", player_position, "'s hand")
