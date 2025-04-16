extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_created
signal connection_failed
signal connection_succeeded
signal game_error(what)

# Default game server port
const DEFAULT_PORT = 10567
# Max number of players
const MAX_PLAYERS = 4

# Player info, associate ID to data
var player_info = {}
# Info we send to other players
var my_info = {
	name = "Player",  # Updated from device name or user input
	color = Color.from_hsv(randf(), 0.8, 0.8),  # Random player color
	ready = false,
	position = -1  # Player position at the game table (will be assigned by server)
}

func _ready():
	multiplayer.peer_connected.connect(_player_connected)
	multiplayer.peer_disconnected.connect(_player_disconnected)
	multiplayer.connected_to_server.connect(_connected_ok)
	multiplayer.connection_failed.connect(_connected_fail)
	multiplayer.server_disconnected.connect(_server_disconnected)
	
	# Set the player name from device
	if OS.has_environment("USERNAME"):
		my_info.name = OS.get_environment("USERNAME")
	else:
		my_info.name = "Player " + str(randi() % 1000)

# Create a server, maximum of 4 players
func create_server(player_name=""):
	if player_name != "":
		my_info.name = player_name
	
	my_info.position = 0  # Host is always position 0
	print("Server created. Players can connect using:")
	print("- Local network: " + get_local_ip())
	print("- Internet: Requires port forwarding of port " + str(DEFAULT_PORT))
	
	print("Creating server...")
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, MAX_PLAYERS - 1)  # -1 because server counts as one
	
	if error != OK:
		print("Cannot create server: " + str(error))
		emit_signal("game_error", "Cannot create server: " + str(error))
		return
	
	multiplayer.multiplayer_peer = peer
	player_info[1] = my_info.duplicate()  # Server is always ID 1
	emit_signal("server_created")
	print("Server created successfully on port: " + str(DEFAULT_PORT))

func get_local_ip() -> String:
	var ip = ""
	for address in IP.get_local_addresses():
		print(address)
		# Filter out loopback, IPv6, and other non-standard IPs
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			ip = address
			break
	return ip
	

# Connect to a server
func join_server(ip, player_name=""):
	if ip == "127.0.0.1" and not is_local_server_running():
		emit_signal("game_error", "No local server running. Start a server first or use the host's IP address.")
		return
		
	if player_name != "":
		my_info.name = player_name
	
	print("Joining server at: " + ip)
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	
	if error != OK:
		print("Cannot connect to server: " + str(error))
		emit_signal("game_error", "Cannot connect to server: " + str(error))
		return
		
	multiplayer.multiplayer_peer = peer
	
func is_local_server_running() -> bool:
	# Simple check if we already have a server
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

# Close current connection
func close_connection():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	player_info.clear()

# Callback from SceneTree, called when a new client connects
func _player_connected(id):
	print("Player connected with ID: " + str(id))
	
	if multiplayer.is_server():
		# Server sends its player info to the new client
		_send_player_info.rpc_id(id, 1, player_info[1])
	
	# On clients, we don't do anything yet - wait for server to tell us about this new player

# Callback from SceneTree, called when a client disconnects
func _player_disconnected(id):
	print("Player disconnected: " + str(id))
	
	if player_info.has(id):
		# If player had a position assigned, tell everyone
		if player_info[id].has("position"):
			print("Player at position " + str(player_info[id].position) + " has disconnected")
	
	# Remove from our list
	player_info.erase(id)
	
	# If we're the server, tell everyone about this disconnection
	if multiplayer.is_server():
		_player_disconnected_notify.rpc(id)
	
	emit_signal("player_disconnected", id)

# Broadcasted when a player disconnects
@rpc("authority", "call_local")
func _player_disconnected_notify(id):
	# Make sure client also removes the player from their list
	if player_info.has(id):
		print("Removing player ID " + str(id) + " due to disconnection")
		player_info.erase(id)
	
	emit_signal("player_disconnected", id)

# Callback from SceneTree, only called on clients, not server
func _connected_ok():
	print("Connection OK")
	var my_id = multiplayer.get_unique_id()
	# Send my info to server without position - server will assign it
	_register_player.rpc_id(1, my_id, my_info)
	emit_signal("connection_succeeded")

# Callback from SceneTree, only called on clients, not server
func _connected_fail():
	print("Connection failed")
	multiplayer.multiplayer_peer = null
	emit_signal("connection_failed")

# Callback from SceneTree, only called on clients, not server
func _server_disconnected():
	print("Server disconnected")
	close_connection()
	emit_signal("game_error", "Server disconnected")

# Remote function called by clients to register themselves with the server
@rpc("any_peer", "call_local")
func _register_player(id, info):
	print("Registering player ID: " + str(id) + " with info: " + str(info))
	
	if multiplayer.is_server():
		# Server is responsible for assigning positions
		if id != 1: # Skip server as it's already assigned position 0
			# Make a copy of the player info in case we need to modify it
			var player_data = info.duplicate()
			
			# Ensure no position is assigned (client shouldn't have set this)
			if "position" in player_data:
				player_data.position = -1
			
			# Find first available position by checking what's already used
			var positions_used = []
			for player_id in player_info:
				if player_info[player_id].has("position") and player_info[player_id].position >= 0:
					positions_used.append(player_info[player_id].position)
			
			# Assign next available position
			for pos in range(MAX_PLAYERS):
				if not pos in positions_used:
					player_data.position = pos
					break
					
			print("Server assigned position " + str(player_data.position) + " to player " + str(id))
			
			# Store the modified player info
			player_info[id] = player_data
			
			# Broadcast this player to all clients (including self for confirmation)
			_send_player_info.rpc(id, player_data)
			
			# Also send all existing players to the new player
			for peer_id in player_info:
				if peer_id != id: # Don't send their own info back
					_send_player_info.rpc_id(id, peer_id, player_info[peer_id])
					
			# Emit signal for UI updates
			emit_signal("player_connected", id, player_data)
			
			# After all player info is sent, broadcast a full player count update
			# This ensures all clients have the same view of who's in the game
			_sync_all_players.rpc()
	else:
		# Clients don't process this directly - all player management is done by server
		pass

# Separate RPC function to prevent recursion
@rpc("authority", "call_local")
func _send_player_info(id, info):
	print("Received player info for ID " + str(id) + " with position " + str(info.position))
	
	# Store player info
	player_info[id] = info
	
	# Emit signal for UI updates
	emit_signal("player_connected", id, info)

# For synchronizing all players to ensure consistent view
@rpc("authority", "call_local")
func _sync_all_players():
	print("Synchronizing all players - currently have " + str(player_info.size()) + " players")
	
	# Just a verification call that counts players after all info has been sent
	var player_count = player_info.size()
	
	# Print debug info for verification
	debug_print_players()

# Tell the server we're ready to start
func set_player_ready(is_ready):
	my_info.ready = is_ready
	print("Setting my ready status to: " + str(is_ready))
	
	if multiplayer.is_server():
		# If we're the server, update locally
		player_info[1].ready = is_ready
		print("Server ready status updated")
		
		# Broadcast to all clients
		_player_ready_broadcast.rpc(1, is_ready)
		
		# Check if everyone is ready
		check_all_ready()
	else:
		# If we're a client, send to server
		_player_ready.rpc_id(1, multiplayer.get_unique_id(), is_ready)

@rpc("any_peer")
func _player_ready(id, is_ready):
	# This should only be called on the server
	if multiplayer.is_server():
		print("Server received ready status from player " + str(id) + ": " + str(is_ready))
		
		# Update player ready status
		if player_info.has(id):
			player_info[id].ready = is_ready
		
		# Broadcast to all clients (including the sender for confirmation)
		_player_ready_broadcast.rpc(id, is_ready)
		
		# Check if all players are ready
		check_all_ready()

@rpc("authority", "call_local")
func _player_ready_broadcast(id, is_ready):
	# Update player ready status on all clients
	if player_info.has(id):
		player_info[id].ready = is_ready
		print("Updated: Player " + str(id) + " ready status: " + str(is_ready))
		
		# Emit signal to update UI
		emit_signal("player_connected", id, player_info[id])

# Check if all players are ready to start
func check_all_ready():
	if multiplayer.is_server():
		var all_ready = true
		var ready_count = 0
		
		for player_id in player_info:
			if player_info[player_id].has("ready") and player_info[player_id].ready:
				ready_count += 1
			else:
				all_ready = false
		
		print("Ready players: " + str(ready_count) + " of " + str(player_info.size()))
		
		if all_ready and player_info.size() > 1:
			print("All players ready! Server can now start the game.")
			
			# If auto-start is enabled, start immediately
			# Uncomment the line below to auto-start when all players are ready
			# _start_game.rpc()

# Start the game - called by the host
func start_game():
	if multiplayer.is_server():
		print("Host is starting the game...")
		
		# Final sync before starting
		_sync_all_players.rpc()
		
		# Start the game after a short delay to ensure sync completes
		await get_tree().create_timer(0.5).timeout
		_start_game.rpc()
	else:
		print("Only the host can start the game!")

@rpc("authority", "call_local")
func _start_game():
	print("Start game function called!")
	
	# Final check - recount players 
	var actual_player_count = player_info.size()
	print("Starting game with " + str(actual_player_count) + " players")
	
	# Print players for debugging
	print("Players in game:")
	debug_print_players()
	
	print("Changing scene to main.tscn...")
	# Transition to the main game scene using call_deferred for safety
	call_deferred("_do_scene_change")

# Safely change scene
func _do_scene_change():
	var error = get_tree().change_scene_to_file("res://scene/main.tscn")
	if error != OK:
		print("Error changing scene: " + str(error))
	else:
		print("Scene change successful!")

# Debug function to print player positions
func debug_print_players():
	print("\n===== PLAYER POSITIONS =====")
	print("Total players: " + str(player_info.size()))
	for id in player_info:
		var pos = player_info[id].position if player_info[id].has("position") else "unassigned"
		var name = player_info[id].name if player_info[id].has("name") else "Unknown"
		var ready = player_info[id].ready if player_info[id].has("ready") else false
		print("Player ID: " + str(id) + ", Name: " + name + ", Position: " + str(pos) + ", Ready: " + str(ready))
	print("============================\n")
