extends Node2D

var num_players: int  # Adjustable for AI players
@onready var deck = $"../Deck"


var hands = []
var current_turn = 0

func _ready():
	num_players = GameSettings.num_players  # ✅ Get the selected value
	print("Game started with", num_players, "players!")
	start_game(deck)

func create_player_hands():
	# Get screen size dynamically so the layout works on all resolutions
	var screen_size = get_viewport_rect().size
	var center_x = screen_size.x / 2
	var center_y = screen_size.y / 2

	var positions = [
		Vector2(center_x, screen_size.y - 100),  # Bottom-Center (Player 1 - Main Player)
		Vector2(center_x, 100),  # Top-Center (Player 2)
		Vector2(100, center_y),  # Left-Center (Player 3 - Vertical Hand)
		Vector2(screen_size.x - 100, center_y)  # Right-Center (Player 4 - Vertical Hand)
	]

	for i in range(GameSettings.num_players):
		var hand = preload("res://scene/hand.tscn").instantiate()
		hand.is_player = (i == 0)  # Only Player 1 is human
		hand.position = positions[i]
		hand.player_position = i  # Assigns correct hand layout (0=Bottom, 1=Top, 2=Left, 3=Right)
		add_child(hand)
		hands.append(hand)

func start_game(deck):

	if hands.size() == 0:
		create_player_hands()
	print("Created hands. Now dealing cards...")
	await deck.deal_cards()  # Await ensures cards are dealt
	print("Finished dealing cards.")

func give_card_to_current_player(card):
	if hands.is_empty():
		push_error("Hands array is empty. Cannot give card.")
		return

	hands[current_turn].add_card(card, 0.3)
	switch_turn()

func switch_turn():
	current_turn = (current_turn + 1) % num_players
