extends Control

@onready var create_button = $LobbyPanel/CreateButton
@onready var join_button = $LobbyPanel/JoinButton
@onready var session_id_input = $LobbyPanel/SessionIdInput
@onready var player_list = $LobbyPanel/PlayerList
@onready var ready_button = $LobbyPanel/ReadyButton
@onready var start_button = $LobbyPanel/StartButton
@onready var back_button = $LobbyPanel/BackButton
@onready var status_label = $LobbyPanel/StatusLabel
@onready var session_id_display = $LobbyPanel/SessionIdDisplay
@onready var refresh_button = $LobbyPanel/RefreshButton

var session_id = ""
var is_host = false
var ready_players = 0
var total_players = 0

func _ready():
	
	# Connect UI elements
	create_button.pressed.connect(_on_create_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	ready_button.pressed.connect(_on_ready_button_pressed)
	start_button.pressed.connect(_on_start_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	refresh_button.pressed.connect(_on_refresh_button_pressed)
	
	# Use deferred call to connect signals after everything is initialized
	call_deferred("_connect_session_signals")
	
	# Initial UI setup
	set_initial_ui_state()

func _connect_session_signals():
	# Try to get the SessionManager node
	var session_mgr = get_node_or_null("/root/SessionManager")
	
	if session_mgr == null:
		status_label.text = "Error connecting to session manager"
		return
	
	# Connect to session manager signals
	session_mgr.session_created.connect(_on_session_created)
	session_mgr.session_creation_failed.connect(_on_session_creation_failed)
	session_mgr.session_joined.connect(_on_session_joined)
	session_mgr.session_join_failed.connect(_on_session_join_failed)
	session_mgr.player_joined.connect(_on_player_joined)
	session_mgr.player_left.connect(_on_player_left)
	session_mgr.session_data_updated.connect(_on_session_data_updated)
	

func set_initial_ui_state():
	# Show/hide appropriate elements
	create_button.visible = true
	join_button.visible = true
	session_id_input.visible = true
	player_list.visible = false
	ready_button.visible = false
	start_button.visible = false
	session_id_display.visible = false
	
	status_label.text = "Create a new game or join an existing one."

func set_lobby_ui_state():
	# Show/hide appropriate elements
	create_button.visible = false
	join_button.visible = false
	session_id_input.visible = false
	player_list.visible = true  # Always show player list in lobby
	ready_button.visible = true
	start_button.visible = is_host
	session_id_display.visible = true
	
	status_label.text = "Waiting for players to get ready..."
	if session_id:
		session_id_display.text = "Session ID: " + session_id

func _on_create_button_pressed():
	# Disable buttons to prevent multiple clicks
	create_button.disabled = true
	join_button.disabled = true
	
	status_label.text = "Creating game session..."
	
	# Create a new game session with default settings
	var game_settings = {
		"max_players": 4,
		"game_type": "switch",
		"rules": {"standard": true}
	}
	
	var session_mgr = get_node("/root/SessionManager")
	if session_mgr:
		session_mgr.create_session(game_settings)
	else:
		status_label.text = "Error: SessionManager not found!"
		create_button.disabled = false
		join_button.disabled = false

func _on_join_button_pressed():
	var input_session_id = session_id_input.text.strip_edges()
	
	if input_session_id.is_empty():
		status_label.text = "Please enter a session ID."
		return
	
	# Disable buttons to prevent multiple clicks
	create_button.disabled = true
	join_button.disabled = true
	
	status_label.text = "Joining game session..."
	
	var session_mgr = get_node("/root/SessionManager")
	if session_mgr:
		session_mgr.join_session(input_session_id)
	else:
		status_label.text = "Error: SessionManager not found!"
		create_button.disabled = false
		join_button.disabled = false


func _on_ready_button_pressed():
	var is_ready = ready_button.text == "Ready"
	
	# Toggle ready status
	ready_button.text = "Not Ready" if is_ready else "Ready"
	
	var session_mgr = get_node("/root/SessionManager")
	if session_mgr:
		session_mgr.set_player_ready(is_ready)
	else:
		status_label.text = "Error: SessionManager not found!"

func _on_start_button_pressed():
	if ready_players < total_players:
		status_label.text = "Not all players are ready!"
		return
	
	var session_mgr = get_node("/root/SessionManager")
	if session_mgr:
		session_mgr.start_game()
		
		# Transition to the game scene
		get_tree().change_scene_to_file("res://scene/main.tscn")
	else:
		status_label.text = "Error: SessionManager not found!"

func _on_back_button_pressed():
	var session_mgr = get_node("/root/SessionManager")
	
	# If we're in a session, leave it
	if session_mgr and !session_id.is_empty():
		session_mgr.leave_session()
	
	# Return to main menu
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")

# Session Manager callbacks
func _on_session_created(new_session_id):
	session_id = new_session_id
	is_host = true
	
	# Update UI for lobby
	set_lobby_ui_state()
	
	status_label.text = "Session created! Waiting for players..."

func _on_session_creation_failed(error):
	# Re-enable buttons
	create_button.disabled = false
	join_button.disabled = false
	
	status_label.text = "Failed to create session: " + error

func _on_session_joined(new_session_id, player_data):
	session_id = new_session_id
	is_host = false
	
	# Update UI for lobby immediately
	set_lobby_ui_state()
	
	# Force an update of the player list
	var session_mgr = get_node("/root/SessionManager")
	if session_mgr and !session_mgr.session_data.is_empty():
		update_player_list()
	
	status_label.text = "Joined session! Waiting for players..."
	
func _on_session_join_failed(error):
	# Re-enable buttons
	create_button.disabled = false
	join_button.disabled = false
	
	status_label.text = "Failed to join session: " + error

func _on_player_joined(player_id, player_data):
	update_player_list()
	status_label.text = "Player joined: " + player_data.name

func _on_player_left(player_id):
	update_player_list()
	status_label.text = "A player left the session."

# Add this function in game_lobby.gd
func _on_session_data_updated(session_data):
	
	# Update session ID display
	if "session_id" in session_data:
		session_id = session_data.session_id
		session_id_display.text = "Session ID: " + session_id
		session_id_display.visible = true
	
	# Update host status
	var session_mgr = get_node_or_null("/root/SessionManager")
	if session_mgr:
		is_host = false
		var sanitized_local_id = session_mgr._sanitize_firebase_key(session_mgr.local_player_id)
		
		if "players" in session_data and sanitized_local_id in session_data.players:
			is_host = session_data.players[sanitized_local_id].is_host
			
			# If we're in the lobby, make sure the UI is updated
			if !player_list.visible:
				set_lobby_ui_state()
		
		# Update UI based on host status
		start_button.visible = is_host
		
		# Update player list with latest data
		update_player_list()
		
		# Check if the game has started
		if "status" in session_data and session_data.status == "playing":
			status_label.text = "Game is starting..."
			# Transition to game scene
			get_tree().change_scene_to_file("res://scene/main.tscn")

func _on_refresh_button_pressed():
	status_label.text = "Refreshing session data..."
	
	var session_mgr = get_node("/root/SessionManager")
	if session_mgr:
		# Force a session update
		session_mgr._poll_session_updates()
	else:
		status_label.text = "Error: SessionManager not found!"

func update_player_list():
	# Clear existing items
	player_list.clear()
	
	var session_mgr = get_node("/root/SessionManager")
	if not session_mgr:
		return
		
	var session_data = session_mgr.session_data
	
	ready_players = 0
	total_players = 0
	
	if session_data.is_empty() or !("players" in session_data):
		status_label.text = "Waiting for players..."
		return
	
	# Add each player to the list
	for player_id in session_data.players:
		var player = session_data.players[player_id]
		var player_name = player.name if "name" in player else "Unknown Player"
		
		# Add host indicator
		if "is_host" in player and player.is_host:
			player_name += " (Host)"
		
		# Add ready indicator
		if "is_ready" in player and player.is_ready:
			player_name += " ✓"
			ready_players += 1
		
		player_list.add_item(player_name)
		total_players += 1
	
	# Update start button enabled state (host only can start when all ready)
	start_button.disabled = ready_players < total_players
	
	# Update status label
	if total_players <= 1:
		status_label.text = "Waiting for other players to join..."
	else:
		status_label.text = "Players in lobby: " + str(total_players) + " (Ready: " + str(ready_players) + ")"
