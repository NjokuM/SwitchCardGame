extends Node2D

@export var player_position: int = 0  # 0 = Bottom, 1 = Top, 2 = Left, 3 = Right
@export var is_player: bool = false  # True for player, false for AI
const CARD_WIDTH = 150
const HAND_Y_POSITION = { true: 1450, false: 150 }  # Player & Opponent positions
const DEFAULT_CARD_MOVE_SPEED = 0.33


var hand = []
var center_screen_x

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

func add_card(card: Node2D, speed: float):
	if card not in hand:
		hand.insert(0, card)
		add_child(card)  # ✅ Add the card to Hand node so it's visible
		connect_card_signals(card)  # ✅ Fix the error by adding this function
		update_positions(speed)
	else:
		move_card(card, card.starting_position, speed)

# ✅ New function to connect card signals
func connect_card_signals(card):
	if card.has_signal("hovered"):
		card.connect("hovered", Callable(self, "_on_card_hovered"))
	if card.has_signal("hovered_off"):
		card.connect("hovered_off", Callable(self, "_on_card_hovered_off"))

func _on_card_hovered(card):
	pass

func _on_card_hovered_off(card):
	pass

func update_positions(speed):
	for i in range(hand.size()):
		var new_position = Vector2(calculate_position(i), HAND_Y_POSITION[is_player])
		var card = hand[i]
		card.starting_position = new_position
		move_card(card, new_position, speed)

func calculate_position(index: int) -> float:
	var total_width = (hand.size() - 1) * CARD_WIDTH
	return center_screen_x + index * CARD_WIDTH - total_width / 2

func move_card(card: Node2D, new_position: Vector2, speed: float):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed)

func remove_card(card: Node2D):
	if card in hand:
		hand.erase(card)
		update_positions(DEFAULT_CARD_MOVE_SPEED)
