extends Node2D

const CARD_SCENE_PATH = "res://scene/card.tscn"
const CARD_DRAW_SPEED = 0.33
const SUITS = ["Hearts", "Spades", "Clubs", "Diamonds"]
const VALUES = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"]
const NUMBER_OF_CARDS_TO_DEAL = 7

var game_deck = []
@onready var pile_discarded = $"../CardManager".discard_pile  # To store played cards
var number_of_players = 2
var is_player_turn = true
var delay_time_in_seconds = .33

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	initialize_deck()
	shuffle_deck(game_deck)
	#start_game()
	deal_cards()
	
func delay():
	await get_tree().create_timer(delay_time_in_seconds).timeout

func initialize_deck():
	"""
	Populate the player_deck with all cards (combination of suits and values).
	"""
	game_deck.clear()
	for suit in SUITS:
		for value in VALUES:
			game_deck.append({"value": value, "suit": suit})

func shuffle_deck(deck):
	"""
	Shuffle the given deck in place.
	"""
	deck.shuffle()

func deal_cards():
	"""Deals cards to each player in the game """
	for i in range(NUMBER_OF_CARDS_TO_DEAL * number_of_players):
		# Slow down the speed cards are being dealt
		await delay()
		draw_card()

func start_game():
	if game_deck.size() > 0:
		var first_card = game_deck.pop_back()
		get_node("CardSlot").place_card(first_card)

func draw_card():
	"""
	Draw the top card from the deck and instantiate its scene.
	"""
	# Get and remove the top card
	var card_drawn = game_deck.pop_front()

	# Instantiate the card scene to card load image
	var card_scene = preload(CARD_SCENE_PATH)
	var new_card = card_scene.instantiate()

	# Set card data (value and suit)
	new_card.set_card_data(card_drawn["value"], card_drawn["suit"])

	# Add the card to the player's hand
	$"../CardManager".add_child(new_card)
	
	if is_player_turn:
		$"../PlayerHand".add_card_to_hand(new_card, CARD_DRAW_SPEED)
	else:
		$"../OpponentHand".add_card_to_hand(new_card, CARD_DRAW_SPEED)
	
	# Switch turn
	is_player_turn = !is_player_turn
	
	#new_card.get_node("AnimationPlayer").play("card_flip")

	print("Draw Card: %s of %s" % [card_drawn["value"], card_drawn["suit"]])

	# Disable deck sprite if all cards have been drawn
	if game_deck.is_empty():
		$Area2D/CollisionShape2D.disabled = true
		$Sprite2D.visible = false
		reshuffle_deck()

func reshuffle_deck():
	"""
	Reshuffle the discard pile back into the deck if it is empty.
	"""
	if game_deck.is_empty() and pile_discarded.size() > 0:
		print("Reshuffling discard pile into deck.")
		game_deck = pile_discarded.duplicate()  # Copy discard pile to deck
		pile_discarded.clear()  # Clear discard pile
		shuffle_deck(game_deck)
		# Re-enable deck
		$Area2D/CollisionShape2D.disabled = false
		$Sprite2D.visible = true
	else:
		print("Deck is not empty, no need to reshuffle.")
