extends Node2D

@export var player_position: int = 0
@export var is_player: bool = false  # Whether this is the local player's hand
const CARD_WIDTH = 200
const CARD_SPACING = 30
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
		update_positions(speed)
		print("✅ Card added:", card.value, "of", card.suit, "to Player", player_position + 1)
		
		# Update card visibility as soon as it's added
		if !is_player:
			# Hide card face for opponents' cards
			card.get_node("CardFaceImage").texture = BACK_OF_CARD_TEXTURE
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
		hand.erase(card)
		update_positions(DEFAULT_CARD_MOVE_SPEED)

# Improved function to handle card visibility
func update_visibility(show_card_faces: bool):
	print("🔍 Updating visibility for Player", player_position + 1, "Show faces:", show_card_faces)
	
	for card in hand:
		# Cards are always visible, but we change their texture
		card.visible = true
		
		if show_card_faces:
			# Show the actual card face
			card.get_node("CardFaceImage").visible = true
			card.get_node("CardFaceImage").texture = card.face_texture
			if card.has_node("CardBackImage"):
				card.get_node("CardBackImage").visible = false
		else:
			# Show the card back
			card.get_node("CardFaceImage").visible = true
			card.get_node("CardFaceImage").texture = BACK_OF_CARD_TEXTURE
			if card.has_node("CardBackImage"):
				card.get_node("CardBackImage").visible = false
