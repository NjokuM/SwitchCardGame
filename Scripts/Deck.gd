extends Node2D

const CARD_IMAGE = "res://scene/card.tscn"
const CARD_SCENE = preload(CARD_IMAGE)
const CARD_DRAW_SPEED = 0.33
const SUITS = ["Hearts", "Spades", "Clubs", "Diamonds"]
const VALUES = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"]
const CARDS_PER_PLAYER = 3

var deck = []
var discard_pile = []

@onready var game_manager = $"../GameManager"

func _ready() -> void:
	# Wait until the first frame has been processed to ensure UI is displayed
	await get_tree().process_frame  # ✅ This ensures the scene is fully displayed
	initialize_deck()
	shuffle_deck()

func initialize_deck():
	deck.clear()
	for suit in SUITS:
		for value in VALUES:
			deck.append({"value": value, "suit": suit})


func shuffle_deck():
	deck.shuffle()
	print("Shuffled deck = " ,deck)

func deal_cards() -> void:  # Corrected syntax
	print("Cards are being dealt")
	
	for i in range(CARDS_PER_PLAYER):
		for j in range(game_manager.num_players):  # Loop through players
			await get_tree().create_timer(CARD_DRAW_SPEED).timeout
			draw_card(j)  # ✅ Pass the player index to draw_card()
	print("Cards have been dealt")


func draw_card(player_index: int):
	if deck.size() == 0:  # Corrected is_empty() usage
		reshuffle_discard_pile()
		if deck.size() == 0:
			return  # No more cards

	var card_data = deck.pop_front()
	var new_card = CARD_SCENE.instantiate()
	
	if new_card.has_method("set_card_data"):
		new_card.set_card_data(card_data["value"], card_data["suit"])
	else:
		push_error("Card scene is missing 'set_card_data' method.")

	# ✅ Give the card to the correct player
	game_manager.hands[player_index].add_card(new_card, CARD_DRAW_SPEED)

	if deck.size() == 0:
		if has_node("Area2D/CollisionShape2D"):
			$Area2D/CollisionShape2D.disabled = true
		if has_node("Sprite2D"):
			$Sprite2D.visible = false

func reshuffle_discard_pile():
	if discard_pile.size() == 0:
		return
	deck = discard_pile.duplicate()
	discard_pile.clear()
	shuffle_deck()

	if has_node("Area2D/CollisionShape2D"):
		$Area2D/CollisionShape2D.disabled = false
	if has_node("Sprite2D"):
		$Sprite2D.visible = true
