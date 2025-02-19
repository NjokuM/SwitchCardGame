extends Node2D

@export var player_position: int = 0
@export var is_player: bool = true
const CARD_WIDTH = 200  # Increased from 150
const CARD_SPACING = 30  # Additional spacing between cards
const DEFAULT_CARD_MOVE_SPEED = 0.33
const BACK_OF_CARD_TEXTURE = preload("res://assets/BACK.png")

var hand = []
var center_screen_x

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

func add_card(card: Node2D, speed: float):
	if card not in hand:
		hand.append(card)
		add_child(card)
		card.pressed.connect(get_node("/root/Main/GameManager")._on_card_clicked.bind(card))
		update_positions(speed)
		print("✅ Card added:", card.value, "of", card.suit, "to Player", player_position + 1)
	else:
		print("❌ Error: Duplicate card detected!")

func update_positions(speed):
	# Calculate total width needed for all cards with spacing
	var total_width = (hand.size() * (CARD_WIDTH + CARD_SPACING)) - CARD_SPACING
	var start_x = -total_width / 2  # Center the hand
	
	for i in range(hand.size()):
		var new_position
		if player_position == 0 or player_position == 1:  # Horizontal hands (bottom/top)
			new_position = Vector2(
				start_x + (i * (CARD_WIDTH + CARD_SPACING)),
				0  # Keep Y at 0 relative to hand position
			)
		else:  # Vertical hands (left/right)
			new_position = Vector2(
				0,  # Keep X at 0 relative to hand position
				start_x + (i * (CARD_WIDTH + CARD_SPACING))
			)
		
		move_card(hand[i], new_position, speed)

func move_card(card: Node2D, new_position: Vector2, speed: float):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed)

func remove_card(card: Node2D):
	if card in hand:
		hand.erase(card)
		update_positions(DEFAULT_CARD_MOVE_SPEED)

func update_visibility(is_active_player):
	print("🔍 Updating visibility for Player", player_position + 1, "Active:", is_active_player)
	
	for card in hand:
		if is_active_player or is_player:
			card.visible = true
			card.get_node("CardFaceImage").texture = card.face_texture
		else:
			card.visible = true
			card.get_node("CardFaceImage").texture = BACK_OF_CARD_TEXTURE
