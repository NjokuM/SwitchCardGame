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
var glow_effect = null
var glow_tween = null  # Store the glow animation tween


# Constants for visual feedback
const HOVER_OFFSET = -50
const SELECTION_OFFSET = -80
const ANIMATION_DURATION = 0.2

const FLYING_DURATION = 0.5  # Total duration of the flying animation
const FLYING_HEIGHT = -200   # How high the card will rise before flying to the slot
const SLOT_POSITION = Vector2.ZERO  # The target position (card slot center)

const GLOW_COLOR = Color(0.0, 0.7, 1.0, 0.7)  # Bright blue glow
const GLOW_RADIUS = 5.0

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
		# Also update the glow effect texture if it exists
		if glow_effect:
			glow_effect.texture = face_texture
	else:
		print("Error: Missing texture for %s of %s" % [value, suit])

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("pressed")

func _ready():
	starting_position = position
	setup_collision()
	setup_glow_effect()

# Function to set up the glow effect
func setup_glow_effect():
	# Create a new node for the glow
	glow_effect = Sprite2D.new()
	glow_effect.name = "GlowEffect"
	
	# Position it behind the card
	glow_effect.z_index = -1
	
	# Use the same texture as the card but slightly larger
	glow_effect.scale = Vector2(0.55, 0.55)  # Slightly larger than card's 0.5 scale
	
	# Initially hide the glow
	glow_effect.visible = false
	
	# Add the glow node to the card
	add_child(glow_effect)
	
	# Update the glow's texture whenever the card's texture changes
	if $CardFaceImage.texture:
		glow_effect.texture = $CardFaceImage.texture
		
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
	SoundManager.play_card_select_sound()
	if not is_selected and not is_card_in_card_slot:
		is_selected = true
		
		# Move the card up
		var tween = create_tween()
		tween.tween_property(self, "position:y", 
			starting_position.y + SELECTION_OFFSET, ANIMATION_DURATION)
		
		# Show the glow effect
		if glow_effect:
			glow_effect.visible = true
			glow_effect.modulate = GLOW_COLOR
			
			# Add a pulsing effect to the glow
			# Stop any existing tween first
			if glow_tween:
				glow_tween.kill()
				
			glow_tween = create_tween()
			glow_tween.set_loops()  # Loop the tween
			glow_tween.tween_property(glow_effect, "modulate:a", 0.3, 0.7)
			glow_tween.tween_property(glow_effect, "modulate:a", 0.7, 0.7)

func deselect():
	if is_selected and not is_card_in_card_slot:
		is_selected = false
		
		# Move the card back down
		var tween = create_tween()
		tween.tween_property(self, "position:y", 
			starting_position.y, ANIMATION_DURATION)
		
		# Hide the glow effect
		if glow_effect:
			glow_effect.visible = false
			
			# Stop the glow animation
			if glow_tween:
				glow_tween.kill()
				glow_tween = null


func play_to_slot():
	is_card_in_card_slot = true
	is_selected = false
	
	# Hide the glow effect when the card is played
	if glow_effect:
		glow_effect.visible = false
		
	# Stop any animations
	if glow_tween:
		glow_tween.kill()
		glow_tween = null
	
	# Reset position if needed
	position = Vector2.ZERO

# Update the reset_state function to also reset glow
func reset_state():
	is_card_in_card_slot = false
	is_selected = false
	position = starting_position
	
	# Hide glow effect
	if glow_effect:
		glow_effect.visible = false
		
	# Stop any animations
	if glow_tween:
		glow_tween.kill()
		glow_tween = null
