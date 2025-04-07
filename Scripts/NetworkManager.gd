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
	position = 0  # Player position at the game table
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
	 # Add this after server creation succeeds:
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
	player_info[1] = my_info  # Server is always ID 1
	emit_signal("server_created")
	print("Server created successfully on port: " + str(DEFAULT_PORT))

func get_local_ip() -> String:
	var ip = ""
	for address in IP.get_local_addresses():
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
	print("Player connected: " + str(id))
	
	# Send my info to the new player
	register_player(id, multiplayer.get_unique_id(), my_info)

# Callback from SceneTree, called when a client disconnects
func _player_disconnected(id):
	print("Player disconnected: " + str(id))
	player_info.erase(id)
	emit_signal("player_disconnected", id)

# Callback from SceneTree, only called on clients, not server
func _connected_ok():
	print("Connection OK")
	var my_id = multiplayer.get_unique_id()
	# Send my info to server
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
	# Store the player info locally
	register_player(multiplayer.get_unique_id(), id, info)

# Local function to register a player and send updates to others
func register_player(receiver_id, sender_id, info):
	# Store the player info
	player_info[sender_id] = info
	
	# Assign the position for the new player
	if sender_id != 1:  # Skip for server as already assigned
		var positions_used = []
		for player_id in player_info:
			if player_info[player_id].has("position"):
				positions_used.append(player_info[player_id].position)
		
		# Find first available position
		for pos in range(MAX_PLAYERS):
			if not pos in positions_used:
				player_info[sender_id].position = pos
				break
	
	# If I'm the server, let everybody know about this new player
	if multiplayer.is_server():
		# Broadcast all existing players to the new player
		for peer_id in player_info:
			if peer_id != sender_id:  # Don't send own info back to the new player
				print("Server telling player " + str(sender_id) + " about player " + str(peer_id))
				_register_player.rpc_id(sender_id, peer_id, player_info[peer_id])
		
		# Also broadcast the new player to all existing players
		for peer_id in player_info:
			if peer_id != sender_id and peer_id != 1:  # Don't send to self or to server
				print("Server telling player " + str(peer_id) + " about new player " + str(sender_id))
				_register_player.rpc_id(peer_id, sender_id, player_info[sender_id])
	
	print("Player registered: " + str(sender_id) + " with position " + str(player_info[sender_id].position))
	emit_signal("player_connected", sender_id, player_info[sender_id])

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

@rpc("authority")
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
		_start_game.rpc()
	else:
		print("Only the host can start the game!")

@rpc("authority", "call_local")
func _start_game():
	print("Start game function called!")
	
	# Print players for debugging
	print("Players in game:")
	for id in player_info:
		var player = player_info[id]
		if player.has("name") and player.has("position") and player.has("ready"):
			print("Player ", player.name, " (", id, ") at position ", player.position, ", ready: ", player.ready)
		else:
			print("Player with ID ", id, " has incomplete info")
	
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
