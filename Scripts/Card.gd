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

# Constants for visual feedback
const HOVER_OFFSET = -20
const SELECTION_OFFSET = -30
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

func _on_area_2d_mouse_entered():
	# Only apply hover effect if the card is in a player's hand
	if not is_selected and not is_card_in_card_slot:
		var tween = create_tween()
		tween.tween_property(self, "position:y", 
			starting_position.y + HOVER_OFFSET, ANIMATION_DURATION)
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
			starting_position.y + SELECTION_OFFSET, ANIMATION_DURATION)

func deselect():
	if is_selected and not is_card_in_card_slot:
		is_selected = false
		var tween = create_tween()
		tween.tween_property(self, "position:y", 
			starting_position.y, ANIMATION_DURATION)

# Call this when the card is played to the slot
func play_to_slot():
	is_card_in_card_slot = true
	is_selected = false
	# Reset position if needed
	position = Vector2.ZERO

# Call this when removing card from play
func reset_state():
	is_card_in_card_slot = false
	is_selected = false
	position = starting_position
