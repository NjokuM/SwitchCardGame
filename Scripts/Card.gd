extends Node2D

signal hovered
signal hovered_off

var starting_position: Vector2 = Vector2.ZERO  # ✅ Define the variable
var value: String
var suit: String
var is_card_in_card_slot: bool = false

func set_card_data(card_value: String, card_suit: String):
	value = card_value
	suit = card_suit
	
	# Loads the card image
	var texture_path = "res://assets/cards/{value}_of_{suit}.png".format({
	"value": value.to_lower(),
	"suit": suit.to_lower() })
	var texture = load(texture_path)
	
	# Assign the texture to Sprite2D
	if texture:
		$CardFaceImage.texture = texture
	else:
		print("Error: Missing texture for %s of %s" % [value, suit])
		

func _ready() -> void:
	get_parent().connect_card_signals(self)

func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)
