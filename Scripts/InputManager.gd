extends Node2D

signal left_mouse_button_clicked
signal left_mouse_button_released

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_DECK = 4
const COLLISION_MASK_SLOT = 8  # Add new collision mask for slot

@onready var card_manager_reference = $"../CardManager"
@onready var game_manager_reference = $"../GameManager"
@onready var deck_reference = $"../Deck"
@onready var card_slot = $"../CardSlot"

func _ready():
	card_slot.slot_clicked.connect(_on_slot_clicked)

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			emit_signal("left_mouse_button_clicked")
			raycast_at_cursor()
		else:
			emit_signal("left_mouse_button_released")

func raycast_at_cursor():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	var result = space_state.intersect_point(parameters)
	
	if result.size() > 0:
		var result_collision_mask = result[0].collider.collision_mask
		if result_collision_mask == COLLISION_MASK_CARD:
			var card_found = result[0].collider.get_parent()
			if card_found:
				game_manager_reference.select_card(card_found)
		elif result_collision_mask == COLLISION_MASK_DECK:
			deck_reference.draw_card(0)  # Draw for current player

func _on_slot_clicked():
	game_manager_reference.play_selected_cards()
