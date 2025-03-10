extends Node

# Firebase database URL
const DATABASE_URL = "https://switchcardgame-b3b34-default-rtdb.europe-west1.firebasedatabase.app/"
const AUTH_HEADER = "auth="

# Signals for session management
signal session_created(session_id)
signal session_creation_failed(error)
signal session_joined(session_id, player_data)
signal session_join_failed(error)
signal player_joined(player_id, player_data)
signal player_left(player_id)
signal session_data_updated(data)
signal session_ended()

# Session variables
var current_session_id = ""
var is_host = false
var session_data = {}
var local_player_id = ""
var game_in_progress = false

# Timer for polling session updates
var update_timer = null
var polling_interval = 1.0  # seconds

func _ready():
	# Initialize update timer
	update_timer = Timer.new()
	update_timer.wait_time = polling_interval
	update_timer.autostart = false
	update_timer.one_shot = false
	update_timer.timeout.connect(_poll_session_updates)
	add_child(update_timer)
	
	print("SessionManager initialized")

# Create a new game session
func create_session(game_settings: Dictionary):
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		emit_signal("session_creation_failed", "User not logged in")
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_session_creation_completed)
	
	# Generate a unique session ID
	var session_id = _generate_session_id()
	
	# Sanitize user ID for Firebase
	var sanitized_user_id = _sanitize_firebase_key(auth.user_info.user_id)
	local_player_id = auth.user_info.user_id
	
	# Setup initial session data
	var player_data = {
		"id": auth.user_info.user_id,
		"name": auth.user_info.display_name if !auth.user_info.display_name.is_empty() else auth.user_info.email,
		"is_host": true,
		"is_ready": false,
		"joined_at": Time.get_unix_time_from_system()
	}
	
	session_data = {
		"session_id": session_id,
		"created_at": Time.get_unix_time_from_system(),
		"settings": game_settings,
		"status": "waiting",  # waiting, playing, ended
		"players": {},
		"game_state": {},
		"turn_data": {},
		"last_updated": Time.get_unix_time_from_system()
	}
	
	# Add player to players dictionary using sanitized key
	session_data.players[sanitized_user_id] = player_data
	
	var url = DATABASE_URL + "sessions/" + session_id + ".json?" + AUTH_HEADER + auth.id_token
	var body = JSON.stringify(session_data)
	var headers = ["Content-Type: application/json"]
	
	print("Sending session data: ", body)  # Debug print
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_error("An error occurred in the HTTP request for session creation")
		emit_signal("session_creation_failed", "Network error")

# Join an existing session
func join_session(session_id: String):
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		emit_signal("session_join_failed", "User not logged in")
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_session_data_received.bind(session_id, true))
	
	var url = DATABASE_URL + "sessions/" + session_id + ".json?" + AUTH_HEADER + auth.id_token
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_error("An error occurred in the HTTP request for session join")
		emit_signal("session_join_failed", "Network error")

# Add player to session after confirming it exists
func _add_player_to_session(session_id: String, session_data: Dictionary):
	var auth = get_node("/root/AuthManager")
	
	# Check if session is joinable
	if session_data.status != "waiting":
		emit_signal("session_join_failed", "Game already in progress or ended")
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_player_join_completed)
	
	# Sanitize user ID for Firebase
	var sanitized_user_id = _sanitize_firebase_key(auth.user_info.user_id)
	local_player_id = auth.user_info.user_id
	
	# Setup player data
	var player_data = {
		"id": auth.user_info.user_id,
		"name": auth.user_info.display_name if !auth.user_info.display_name.is_empty() else auth.user_info.email,
		"is_host": false,
		"is_ready": false,
		"joined_at": Time.get_unix_time_from_system()
	}
	
	var url = DATABASE_URL + "sessions/" + session_id + "/players/" + sanitized_user_id + ".json?" + AUTH_HEADER + auth.id_token
	var body = JSON.stringify(player_data)
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_error("An error occurred in the HTTP request for player join")
		emit_signal("session_join_failed", "Network error")

# Start polling for updates after joining a session
func _start_session_updates(session_id: String):
	current_session_id = session_id
	update_timer.start()

# Stop polling when leaving a session
func _stop_session_updates():
	update_timer.stop()
	current_session_id = ""
	session_data = {}
	game_in_progress = false

# Poll for session updates
func _poll_session_updates():
	if current_session_id.is_empty():
		return
	
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_session_data_received.bind(current_session_id, false))
	
	var url = DATABASE_URL + "sessions/" + current_session_id + ".json?" + AUTH_HEADER + auth.id_token
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_error("An error occurred in the HTTP request for session update")

# Update player ready status
# In SessionManager.gd - improve the set_player_ready function
func set_player_ready(ready: bool):
	if current_session_id.is_empty() or local_player_id.is_empty():
		print("Can't set ready status - no active session or player ID")
		return
	
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		print("Can't set ready status - not logged in")
		return
	
	print("Setting ready status to: ", ready)
	
	# Sanitize user ID for Firebase
	var sanitized_user_id = _sanitize_firebase_key(local_player_id)
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_player_update_completed)
	
	var url = DATABASE_URL + "sessions/" + current_session_id + "/players/" + sanitized_user_id + "/is_ready.json?" + AUTH_HEADER + auth.id_token
	var body = JSON.stringify(ready)
	var headers = ["Content-Type: application/json"]
	
	print("Sending ready status update request to: ", url)
	print("Body: ", body)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_error("An error occurred in the HTTP request for player update")
		
# Start the game (host only)
func start_game():
	if not is_host or current_session_id.is_empty():
		return
	
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_game_start_completed)
	
	var url = DATABASE_URL + "sessions/" + current_session_id + "/status.json?" + AUTH_HEADER + auth.id_token
	var body = JSON.stringify("playing")
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_error("An error occurred in the HTTP request for game start")

# Leave the current session
func leave_session():
	if current_session_id.is_empty() or local_player_id.is_empty():
		return
	
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		return
	
	# Sanitize user ID for Firebase
	var sanitized_user_id = _sanitize_firebase_key(local_player_id)
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_leave_session_completed)
	
	var url = DATABASE_URL + "sessions/" + current_session_id + "/players/" + sanitized_user_id + ".json?" + AUTH_HEADER + auth.id_token
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_DELETE)
	if error != OK:
		push_error("An error occurred in the HTTP request for leaving session")
	
	# If host, check if we should transfer host status to another player
	if is_host and session_data.players.size() > 1:
		_transfer_host()
	
	# Stop session updates
	_stop_session_updates()
	
	emit_signal("session_ended")

# Transfer host status to another player
func _transfer_host():
	# Find another player
	var new_host_id = ""
	for player_id in session_data.players:
		if _sanitize_firebase_key(local_player_id) != player_id:
			new_host_id = player_id
			break
	
	if new_host_id.is_empty():
		return
	
	var auth = get_node("/root/AuthManager")
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var url = DATABASE_URL + "sessions/" + current_session_id + "/players/" + new_host_id + "/is_host.json?" + AUTH_HEADER + auth.id_token
	var body = JSON.stringify(true)
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_error("An error occurred in the HTTP request for host transfer")

# Submit a game move
func submit_move(move_data: Dictionary):
	if current_session_id.is_empty() or local_player_id.is_empty():
		return
	
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_move_submitted)
	
	# Add timestamp and player ID to move data
	move_data["timestamp"] = Time.get_unix_time_from_system()
	move_data["player_id"] = local_player_id
	
	var url = DATABASE_URL + "sessions/" + current_session_id + "/game_state/last_move.json?" + AUTH_HEADER + auth.id_token
	var body = JSON.stringify(move_data)
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_error("An error occurred in the HTTP request for submitting move")

# Update the game state (after a move)
func update_game_state(game_state: Dictionary):
	if current_session_id.is_empty() or local_player_id.is_empty():
		return
	
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_game_state_updated)
	
	# Add timestamp to game state
	game_state["last_updated"] = Time.get_unix_time_from_system()
	
	var url = DATABASE_URL + "sessions/" + current_session_id + "/game_state.json?" + AUTH_HEADER + auth.id_token
	var body = JSON.stringify(game_state)
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_error("An error occurred in the HTTP request for updating game state")

# End the game and update the session status
func end_game(winner_id: String):
	if current_session_id.is_empty():
		return
	
	var auth = get_node("/root/AuthManager")
	if not auth.is_logged_in():
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_game_ended)
	
	var game_result = {
		"winner_id": winner_id,
		"ended_at": Time.get_unix_time_from_system()
	}
	
	var update_data = {
		"status": "ended",
		"game_state/result": game_result
	}
	
	var url = DATABASE_URL + "sessions/" + current_session_id + ".json?" + AUTH_HEADER + auth.id_token
	var body = JSON.stringify(update_data)
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PATCH)
	if error != OK:
		push_error("An error occurred in the HTTP request for ending game")

# Sanitize keys for Firebase (remove forbidden characters)
func _sanitize_firebase_key(key: String) -> String:
	# Replace forbidden characters with underscores
	var sanitized = key.replace(".", "_")
	sanitized = sanitized.replace("#", "_")
	sanitized = sanitized.replace("$", "_")
	sanitized = sanitized.replace("[", "_")
	sanitized = sanitized.replace("]", "_")
	sanitized = sanitized.replace("/", "_")
	
	# Ensure key is not empty
	if sanitized.is_empty():
		sanitized = "_empty_key_"
	
	return sanitized

# Helpers and utility functions
func _generate_session_id() -> String:
	var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var session_id = ""
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(6):
		session_id += chars[rng.randi() % chars.length()]
	
	return session_id

# HTTP Callbacks
func _on_session_creation_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Session creation error: ", body.get_string_from_utf8())
		emit_signal("session_creation_failed", "Server error: " + body.get_string_from_utf8())
		return
	
	current_session_id = session_data.session_id
	is_host = true
	
	# Start polling for updates
	_start_session_updates(current_session_id)
	
	emit_signal("session_created", current_session_id)
	print("Session created: ", current_session_id)

func _on_session_data_received(result, response_code, headers, body, session_id, is_join_attempt):
	if response_code != 200:
		print("Session data error: ", body.get_string_from_utf8())
		if is_join_attempt:
			emit_signal("session_join_failed", "Server error: " + body.get_string_from_utf8())
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if json == null:
		print("Session not found: ", session_id)
		if is_join_attempt:
			emit_signal("session_join_failed", "Session not found")
		return
	
	if is_join_attempt:
		# This is the initial join attempt
		_add_player_to_session(session_id, json)
	else:
		# Regular update polling
		_process_session_update(json)

func _on_player_join_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Player join error: ", body.get_string_from_utf8())
		emit_signal("session_join_failed", "Server error: " + body.get_string_from_utf8())
		return
	
	# Start polling for updates
	_start_session_updates(current_session_id)
	
	emit_signal("session_joined", current_session_id, JSON.parse_string(body.get_string_from_utf8()))
	print("Joined session: ", current_session_id)

func _on_player_update_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Player update error: ", body.get_string_from_utf8())
		return
	
	print("Player ready status updated")

func _on_game_start_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Game start error: ", body.get_string_from_utf8())
		return
	
	game_in_progress = true
	print("Game started in session: ", current_session_id)

func _on_leave_session_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Leave session error: ", body.get_string_from_utf8())
		return
	
	print("Left session: ", current_session_id)

func _on_move_submitted(result, response_code, headers, body):
	if response_code != 200:
		print("Move submission error: ", body.get_string_from_utf8())
		return
	
	print("Move submitted")

func _on_game_state_updated(result, response_code, headers, body):
	if response_code != 200:
		print("Game state update error: ", body.get_string_from_utf8())
		return
	
	print("Game state updated")

func _on_game_ended(result, response_code, headers, body):
	if response_code != 200:
		print("Game end error: ", body.get_string_from_utf8())
		return
	
	game_in_progress = false
	print("Game ended in session: ", current_session_id)

# Process session updates received from polling
# In the _process_session_update function, modify or add:
func _process_session_update(updated_session):
	print("Processing session update: ", JSON.stringify(updated_session))
	
	# Store previous player count to detect joins/leaves
	var previous_players = {}
	if !session_data.is_empty() and "players" in session_data:
		previous_players = session_data.players.duplicate()
	
	# Update local session data
	session_data = updated_session
	
	# Check if players key exists - sometimes Firebase might not include empty objects
	if !("players" in session_data):
		session_data.players = {}
	
	# Debug print of players
	print("Players in session: ", session_data.players.keys())
	
	# Check if we're the host
	var sanitized_local_id = _sanitize_firebase_key(local_player_id)
	if sanitized_local_id in session_data.players:
		is_host = session_data.players[sanitized_local_id].is_host
		print("Host status: ", is_host)
	
	# Check for player joins/leaves
	for player_id in session_data.players:
		if !previous_players.has(player_id):
			print("New player joined: ", player_id)
			emit_signal("player_joined", player_id, session_data.players[player_id])
	
	for player_id in previous_players:
		if !session_data.players.has(player_id):
			print("Player left: ", player_id)
			emit_signal("player_left", player_id)
	
	# Emit the updated data for other components to use
	emit_signal("session_data_updated", session_data)
