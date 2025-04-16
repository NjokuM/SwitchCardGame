# In test_game_manager.gd
extends GutTest

func test_turn_switching():
	var game_manager_scene = load("res://Scripts/GameManager.gd")
	var game_manager = game_manager_scene.new()
	
	# Simulate 4 player game
	game_manager.num_players = 4
	game_manager.current_turn = 0
	game_manager.game_direction = 1
	
	# Test forward turn switching
	game_manager.switch_turn()
	assert_eq(game_manager.current_turn, 1, "Turn should switch to next player in clockwise direction")
	
	# Test turn switching with direction change
	game_manager.game_direction = -1
	game_manager.switch_turn()
	assert_eq(game_manager.current_turn, 0, "Turn should switch to previous player in counter-clockwise direction")
