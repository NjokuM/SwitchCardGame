
extends Control
@onready var suit_label = $VBoxContainer/SuitContainer/SuitLabel
@onready var direction_label = $VBoxContainer/DirectionContainer/DirectionLabel
@onready var deck_count_label = $VBoxContainer/DeckContainer/DeckCountLabel

# Called when the node enters the scene tree for the first time
func _ready():
	# Initial positioning
	position_panel()
	
	# Connect to window resize signals to maintain position
	get_tree().root.size_changed.connect(position_panel)

func position_panel():
	# Position in the top-right corner
	var screen_size = get_viewport_rect().size
	position = Vector2(screen_size.x - 250, 50)

func update_suit(new_suit: String):
	if suit_label:
		suit_label.text = new_suit

func update_direction(is_clockwise: bool):
	if direction_label:
		direction_label.text = "Clockwise" if is_clockwise else "Counter-clockwise"

func update_deck_count(count: int):
	if deck_count_label:
		deck_count_label.text = str(count)
