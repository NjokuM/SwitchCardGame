extends Node2D

signal hovered
signal hovered_off
signal pressed

var starting_position: Vector2 = Vector2.ZERO
var value: String
var suit: String
var is_card_in_card_slot: bool = false
var is_selected: bool = false
var face_texture: Texture2D  # Store the face texture for reference
var chosen_suit: String = ""  # For Aces


# Constants for visual feedback
const HOVER_OFFSET = -50
const SELECTION_OFFSET = -80
const ANIMATION_DURATION = 0.2

func set_card_data(card_value: String, card_suit: String):
	value = card_value
	suit = card_suit
	
	# Loads the card image
	var texture_path = "res://assets/cards/{value}_of_{suit}.png".format({
		"value": value.to_lower(),
		"suit": suit.to_lower()
	})
	face_texture = load(texture_path)
	
	# Assign the texture to Sprite2D
	if face_texture:
		$CardFaceImage.texture = face_texture
	else:
		print("Error: Missing texture for %s of %s" % [value, suit])

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("pressed")

func _ready():
	starting_position = position
	setup_collision()

func setup_collision():
	# Make sure we have an Area2D for collision
	var area = $Area2D if has_node("Area2D") else null
	if not area:
		area = Area2D.new()
		area.name = "Area2D"
		add_child(area)
		
		# Add collision shape if it doesn't exist
		var collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(140, 190)  # Adjust size to match your card sprite
		collision.shape = shape
		area.add_child(collision)
	
	# Connect signals if they're not already connected
	if not area.is_connected("mouse_entered", _on_area_2d_mouse_entered):
		area.mouse_entered.connect(_on_area_2d_mouse_entered)
	if not area.is_connected("mouse_exited", _on_area_2d_mouse_exited):
		area.mouse_exited.connect(_on_area_2d_mouse_exited)

var hover_direction = 1  # 1 for upward (bottom player), -1 for downward

func _on_area_2d_mouse_entered():
	# Only apply hover effect if the card is in a player's hand
	if not is_selected and not is_card_in_card_slot:
		var tween = create_tween()
		tween.tween_property(self, "position:y", 
			starting_position.y + (HOVER_OFFSET * hover_direction), ANIMATION_DURATION)
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited():
	# Only remove hover effect if the card is in a player's hand
	if not is_selected and not is_card_in_card_slot:
		var tween = create_tween()
		tween.tween_property(self, "position:y", 
			starting_position.y, ANIMATION_DURATION)
	emit_signal("hovered_off", self)

func select():
	if not is_selected and not is_card_in_card_slot:
		is_selected = true
		var tween = create_tween()
		tween.tween_property(self, "position:y", 
			starting_position.y + (SELECTION_OFFSET * hover_direction), ANIMATION_DURATION)

func deselect():
	if is_selected and not is_card_in_card_slot:
		is_selected = false
		var tween = create_tween()
		tween.tween_property(self, "position:y", 
			starting_position.y, ANIMATION_DURATION)
			
# Set hover direction based on player position
func set_hover_direction(direction: int):
	hover_direction = direction

# Call this when the card is played to the slot
func play_to_slot():
	is_card_in_card_slot = true
	is_selected = false
	# Reset position if needed
	position = Vector2.ZERO
	
func set_chosen_suit(suit: String):
	chosen_suit = suit

	print("Card suit changed to:", suit)

# Call this when removing card from play
func reset_state():
	is_card_in_card_slot = false
	is_selected = false
	position = starting_position
	
# Add or update these functions in Card.gd

# Function to show the card face
func show_face():
	if has_node("CardFaceImage"):
		$CardFaceImage.visible = true
		$CardFaceImage.texture = face_texture
	
	if has_node("CardBackImage"):
		$CardBackImage.visible = false
		
	print("Showing face for: ", value, " of ", suit)

# Function to show the card back
func show_back():
	if has_node("CardFaceImage"):
		$CardFaceImage.visible = true
		$CardFaceImage.texture = preload("res://assets/BACK.png")
	
	if has_node("CardBackImage"):
		$CardBackImage.visible = false
		
	print("Showing back for card")

# Call this function when the card is added to a hand
# to set its initial visibility
func set_in_hand(is_player_hand: bool):
	print("Setting card visibility - is player hand: " + str(is_player_hand))
	if is_player_hand:
		show_face()
	else:
		show_back()
