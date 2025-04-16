extends Control

@onready var player_name_input = $CenterPanel/VBoxContainer/PlayerNameInput
@onready var ip_input = $CenterPanel/VBoxContainer/IPInput
@onready var port_input = $CenterPanel/VBoxContainer/PortInput
@onready var host_button = $CenterPanel/VBoxContainer/ButtonContainer/HostButton
@onready var join_button = $CenterPanel/VBoxContainer/ButtonContainer/JoinButton
@onready var status_label = $CenterPanel/VBoxContainer/StatusLabel
@onready var player_list = $CenterPanel/VBoxContainer/PlayerList
@onready var start_game_button = $CenterPanel/VBoxContainer/StartGameButton
@onready var ready_button = $CenterPanel/VBoxContainer/ReadyButton
@onready var back_button = $CenterPanel/VBoxContainer/BackButton

var default_ip = "127.0.0.1"
var default_port = "10567"
var local_player_name = ""
var refresh_timer = null

func _ready():
	# Get the network manager singleton
	var network = get_node("/root/NetworkManager")
	
	# Connect signals
	network.connect("player_connected", _on_player_connected)
	network.connect("player_disconnected", _on_player_disconnected)
	network.connect("server_created", _on_server_created)
	network.connect("connection_succeeded", _on_connection_success)
	network.connect("connection_failed", _on_connection_failed)
	network.connect("game_error", _on_game_error)
	
	# Initialize player name from OS
	if OS.has_environment("USERNAME"):
		player_name_input.text = OS.get_environment("USERNAME")
	else:
		player_name_input.text = "Player " + str(randi() % 1000)
		
	# Set default IP and port
	ip_input.text = default_ip
	port_input.text = default_port
	
	# Hide game control buttons initially
	start_game_button.visible = false
	ready_button.visible = false
	
	# Clear the player list
	player_list.clear()
	
	# Set up a timer to periodically refresh the player list
	refresh_timer = Timer.new()
	refresh_timer.wait_time = 2.0
	refresh_timer.timeout.connect(update_player_list)
	add_child(refresh_timer)
	refresh_timer.start()

func _on_host_button_pressed():
	SoundManager.play_card_select_sound()
	if player_name_input.text == "":
		_on_game_error("Please enter a player name")
		return
		
	local_player_name = player_name_input.text
	disable_lobby_controls()
	
	var port = int(port_input.text) if port_input.text.is_valid_int() else default_port
	status_label.text = "Creating server on port " + str(port) + "..."
	
	var network = get_node("/root/NetworkManager")
	network.create_server(local_player_name)
	
	var local_ip = network.get_local_ip()
	if local_ip != "":
		status_label.text = "Server created! Local players can connect to: " + local_ip
	else:
		status_label.text = "Server created! Waiting for players..."

func _on_join_button_pressed():
	SoundManager.play_card_select_sound()
	if player_name_input.text == "":
		_on_game_error("Please enter a player name")
		return
		
	if ip_input.text == "":
		_on_game_error("Please enter a server IP address")
		return
		
	local_player_name = player_name_input.text
	disable_lobby_controls()
	
	status_label.text = "Connecting to server at " + ip_input.text + "..."
	var network = get_node("/root/NetworkManager")
	network.join_server(ip_input.text, local_player_name)

func _on_back_button_pressed():
	SoundManager.play_card_select_sound()
	
	if refresh_timer:
		refresh_timer.stop()
	
	var network = get_node("/root/NetworkManager")
	network.close_connection()
	get_tree().change_scene_to_file("res://scene/play_menu.tscn")

func _on_ready_button_pressed():
	SoundManager.play_card_select_sound()
	# Tell everybody we're ready to start
	var network = get_node("/root/NetworkManager")
	network.set_player_ready(true)
	ready_button.disabled = true
	status_label.text = "Ready! Waiting for other players..."
	
	print("Set ready status to true")
	
	# Update the player list to show ready status
	update_player_list()
	
	# Check if we need to show the start button (if we're the host)
	update_start_button_visibility()
	
	# Force update after a delay (in case of network lag)
	await get_tree().create_timer(1.0).timeout
	update_start_button_visibility()

func _on_start_game_button_pressed():
	SoundManager.play_card_select_sound()
	# Start the game
	var network = get_node("/root/NetworkManager")
	start_game_button.disabled = true
	status_label.text = "Starting game..."
	
	# Debug print player info before starting
	network.debug_print_players()
	
	print("Start game button pressed, calling network.start_game()")
	network.start_game()
	
	# In case the RPC doesn't trigger for some reason, force scene change locally after a delay
	await get_tree().create_timer(3.0).timeout
	if get_tree().current_scene.name == "MultiplayerMenu":  # If we're still in the menu
		print("Forcing scene change after timeout")
		get_tree().change_scene_to_file("res://scene/main.tscn")

# Signal handlers for network events

func _on_player_connected(id, player):
	var network = get_node("/root/NetworkManager")
	
	# Add to player list
	update_player_list()
	
	# Update status
	if player.has("name"):
		status_label.text = "Player connected: " + player.name
	else:
		status_label.text = "Player connected with ID: " + str(id)
	
	# Show ready button for all players
	ready_button.visible = true
	
	# Force update start button visibility
	update_start_button_visibility()
	print("Player connected, checking start button visibility")

func _on_player_disconnected(id):
	var network = get_node("/root/NetworkManager")
	
	# Update player list - rebuild from player_info
	update_player_list()
	
	# Update status
	status_label.text = "Player disconnected: ID " + str(id)
	
	# Update start button visibility
	update_start_button_visibility()

func _on_server_created():
	status_label.text = "Server created successfully! Waiting for players..."
	
	# Show ready button for the host
	ready_button.visible = true
	
	# Add ourselves to the player list
	update_player_list()

func _on_connection_success():
	status_label.text = "Connected to server!"
	
	# Show ready button for the client
	ready_button.visible = true
	
	# Add ourselves to the player list (though server will update this)
	update_player_list()

func _on_connection_failed():
	status_label.text = "Failed to connect to server."
	enable_lobby_controls()
	ready_button.visible = false
	start_game_button.visible = false

func _on_game_error(message):
	status_label.text = "Error: " + message
	enable_lobby_controls()
	ready_button.visible = false
	start_game_button.visible = false

# Helper functions

func disable_lobby_controls():
	player_name_input.editable = false
	ip_input.editable = false
	port_input.editable = false
	host_button.disabled = true
	join_button.disabled = true

func enable_lobby_controls():
	player_name_input.editable = true
	ip_input.editable = true
	port_input.editable = true
	host_button.disabled = false
	join_button.disabled = false

# Update the player list to show ready status
func update_player_list():
	var network = get_node("/root/NetworkManager")
	
	# Clear the player list
	player_list.clear()
	
	# Add all players with their ready status
	var sorted_players = []
	
	# First collect all players
	for p_id in network.player_info:
		var player = network.player_info[p_id]
		sorted_players.append({"id": p_id, "info": player})
	
	# Sort by position
	sorted_players.sort_custom(func(a, b): 
		var pos_a = a.info.position if a.info.has("position") else 999
		var pos_b = b.info.position if b.info.has("position") else 999
		return pos_a < pos_b
	)
	
	# Add to the list
	for player_data in sorted_players:
		var p_id = player_data.id
		var player = player_data.info
		
		var ready_status = ""
		if player.has("ready"):
			ready_status = " ✓" if player.ready else " ..."
		
		var name_display = ""
		if player.has("name"):
			name_display = player.name
		else:
			name_display = "Unknown"
			
		var position_display = ""
		if player.has("position"):
			position_display = str(player.position)
		else:
			position_display = "?"
		
		player_list.add_item(name_display + " (Position: " + position_display + ")" + ready_status)
	
	# Print total players for debug
	print("Player list updated - Total players: " + str(sorted_players.size()))

# Show start button only for host when all players are ready
func update_start_button_visibility():
	var network = get_node("/root/NetworkManager")
	
	if network.multiplayer.is_server():
		# Count ready players
		var all_ready = true
		var ready_count = 0
		
		for p_id in network.player_info:
			if network.player_info[p_id].has("ready") and network.player_info[p_id].ready:
				ready_count += 1
			else:
				all_ready = false
		
		print("Checking start button visibility: " + str(ready_count) + " ready of " + str(network.player_info.size()) + ", all ready: " + str(all_ready))
		
		# Show start button if we're the server and all players are ready
		start_game_button.visible = all_ready
		
		# Force to visible if we're in debug mode with 2+ players
		if OS.is_debug_build() and network.player_info.size() >= 2:
			start_game_button.visible = true
			
		print("Start button visibility set to: " + str(start_game_button.visible))
	else:
		# Clients never see the start button
		start_game_button.visible = false
