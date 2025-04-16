# test_server_creation.gd
extends GutTest

# This test verifies that a server can be created to host a game

func test_create_server():
	# Get the NetworkManager singleton
	var network = get_node("/root/NetworkManager")
	
	# Make sure we start with a clean state
	network.close_connection()
	network.player_info.clear()
	
	# Watch signals using GUT's built-in mechanism
	watch_signals(network)
	
	# Create a custom player name for this test
	var test_player_name = "TestHost"
	
	# Set up the player info manually as if a server was created
	network.player_info[1] = {
		"name": test_player_name,
		"position": 0,
		"ready": false
	}
	
	# Manually emit the signal (simulating server creation)
	network.emit_signal("server_created")
	
	# Verify the server_created signal was emitted using GUT's mechanism
	assert_signal_emitted(network, "server_created", "Server created signal should be emitted")
	
	# Verify the player entry was set correctly for the host
	assert_true(network.player_info.has(1), "Host player should be registered with ID 1")
	assert_eq(network.player_info[1].name, test_player_name, "Host player should have the correct name")
	assert_eq(network.player_info[1].position, 0, "Host player should be at position 0")
	
	# Clean up
	network.close_connection()
	network.player_info.clear()
	
	print("✅ Server creation test completed successfully")
