extends Node2D

@export var player_position: int = 0
@export var is_player: bool = false  # Whether this is the local player's hand

# Card positioning constants
const BASE_CARD_WIDTH = 115  # Increased from 110
const MIN_CARD_SPACING = 20  # Increased from 20
const MAX_CARD_SPACING = 50  # Increased from 50
const DEFAULT_CARD_MOVE_SPEED = 0.33
const BACK_OF_CARD_TEXTURE = preload("res://assets/BACK.png")

# Screen constants
const SCREEN_MARGIN_PERCENT = 0.15  # 15% of screen width as margin on each side

var hand = []
var center_screen_x

# References to UI elements
@onready var cards_container = $Cards
@onready var player_name_panel = $PlayerNamePanel
@onready var player_name_label = $PlayerNamePanel/PlayerNameLabel

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2
	
	# Connect to window resize signals
	get_tree().root.size_changed.connect(func(): 
		center_screen_x = get_viewport().size.x / 2
		update_positions(0.2)
		update_name_label_position()
	)
	
	# Initial name label positioning
	update_name_label_position()

func set_player_name(new_name: String) -> void:
	player_name_label.text = new_name
	
	# Resize the panel to fit the text if needed
	var label_width = player_name_label.get_minimum_size().x
	if label_width > player_name_panel.size.x - 20:  # If text is wider than panel with padding
		player_name_panel.size.x = label_width + 30  # Add padding
		player_name_panel.position.x = -player_name_panel.size.x / 2  # Re-center

func update_name_label_position() -> void:
	# Position based on hand rotation to ensure the name is always above/beside the hand
	var base_offset = Vector2(0, -60)  # Default offset for bottom player
	
	# Adjust the offset based on rotation
	if rotation_degrees >= 45 and rotation_degrees < 135:
		# Left side player - name on left side
		base_offset = Vector2(-90, 0)
		player_name_panel.rotation = -rotation  # Counter-rotate the panel
	elif rotation_degrees >= 135 and rotation_degrees < 225 or rotation_degrees <= -135 and rotation_degrees > -225:
		# Top player
		base_offset = Vector2(0, 70)
		player_name_panel.rotation = -rotation
	elif rotation_degrees >= 225 and rotation_degrees < 315 or rotation_degrees <= -45 and rotation_degrees > -135:
		# Right side player
		base_offset = Vector2(90, 0)
		player_name_panel.rotation = -rotation
	else:
		# Bottom player (default)
		player_name_panel.rotation = 0
	
	player_name_panel.position = base_offset

func add_card(card: Node2D, speed: float):
	if card not in hand:
		hand.append(card)
		cards_container.add_child(card)  # Add card to the cards container
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
	# Get screen dimensions
	var screen_size = get_viewport_rect().size
	
	# Adaptive card spacing for different hand sizes
	var max_width = screen_size.x * (1 - 2 * SCREEN_MARGIN_PERCENT)  # Available width
	var card_spacing = calculate_card_spacing(hand.size(), max_width)
	var card_scale = calculate_card_scale(hand.size(), max_width)
	
	# Calculate total width needed for all cards with spacing
	var effective_card_width = BASE_CARD_WIDTH * card_scale
	var total_width = (hand.size() * (effective_card_width + card_spacing)) - card_spacing
	var start_x = -total_width / 2  # Center the hand
	
	# Update scales and positions of all cards
	for i in range(hand.size()):
		var card = hand[i]
		
		# Update card scale if needed
		if card.scale.x != card_scale:
			var scale_tween = get_tree().create_tween()
			scale_tween.tween_property(card, "scale", Vector2(card_scale, card_scale), speed)
		
		# Update card position
		var new_position = Vector2(
			start_x + (i * (effective_card_width + card_spacing)),
			0  # Keep Y at 0 relative to hand position
		)
		move_card(card, new_position, speed)

func calculate_card_spacing(card_count: int, max_width: float) -> float:
	# Dynamic spacing based on card count and available width
	if card_count <= 1:
		return MAX_CARD_SPACING
	
	# Calculate ideal spacing
	var ideal_spacing = max_width / (card_count + 1) - BASE_CARD_WIDTH
	
	# Clamp to min/max values
	return clamp(ideal_spacing, MIN_CARD_SPACING, MAX_CARD_SPACING)

func calculate_card_scale(card_count: int, max_width: float) -> float:
	# Start with increased default scale
	var scale = 0.6  # Increased from 0.5
	
	# If we have many cards, reduce scale to fit
	if card_count > 7:
		# Calculate how much we need to scale down
		var total_width_full_scale = card_count * BASE_CARD_WIDTH + (card_count - 1) * MIN_CARD_SPACING
		if total_width_full_scale > max_width:
			scale = max_width / total_width_full_scale * 0.6
			# Don't go too small
			scale = max(scale, 0.4)  # Increased minimum scale
	
	return scale


func move_card(card: Node2D, new_position: Vector2, speed: float):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed)

func remove_card(card: Node2D):
	if card in hand:
		# Remove the card from our array and parent
		hand.erase(card)
		if card.get_parent() == cards_container:
			cards_container.remove_child(card)
			
		# Allow card to settle in the slot first, then update hand positions
		get_tree().create_timer(0.1).timeout.connect(func(): update_positions(DEFAULT_CARD_MOVE_SPEED))
		
		return true
	
	return false
		
func remove_card_without_repositioning(card: Node2D):
	if card in hand:
		# Remove the card from our array and parent
		hand.erase(card)
		if card.get_parent() == cards_container:
			cards_container.remove_child(card)
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
		else:
			# Show the card back
			card.get_node("CardFaceImage").visible = true
			card.get_node("CardFaceImage").texture = BACK_OF_CARD_TEXTURE
			if card.has_node("CardBackImage"):
				card.get_node("CardBackImage").visible = false

# Update hand style based on whether it's the current player's turn
func highlight_active_turn(is_active: bool):
	# If this is the active player's turn, add a subtle glow effect
	if is_active:
		modulate = Color(1.2, 1.2, 1.0)  # Slightly yellowish glow
		
		# Also highlight the name label panel
		var style_box = player_name_panel.get_theme_stylebox("panel").duplicate()
		style_box.bg_color = Color(0.7, 0.5, 0.1, 0.7)  # Gold highlight
		player_name_panel.add_theme_stylebox_override("panel", style_box)
	else:
		modulate = Color(1.0, 1.0, 1.0)  # Normal color
		
		# Reset name label highlight
		var style_box = player_name_panel.get_theme_stylebox("panel").duplicate()
		style_box.bg_color = Color(0.1, 0.3, 0.5, 0.7)  # Default blue
		player_name_panel.add_theme_stylebox_override("panel", style_box)
