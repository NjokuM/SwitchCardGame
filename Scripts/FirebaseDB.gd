extends Node

# Firebase configuration - you'll need to replace these with your actual Firebase project details
const FIREBASE_DATABASE_URL = "https://switchcardgame-b3b34-default-rtdb.europe-west1.firebasedatabase.app/"
const FIREBASE_API_KEY = "AIzaSyDzvEBUhTdyEdQlwWqq_E-uV8IuK8inPdQ" # Add your Firebase API key here

# Authentication
var auth_token = ""
var is_authenticated = false
var is_authenticating = false

# Signals for event-driven approach
signal data_updated(path, data)
signal listener_registered(path)
signal listener_error(path, error)
signal auth_succeeded
signal auth_failed(error_code, error_message)

# Track active listeners to avoid duplicates
var active_listeners = {}
# Track pending HTTP requests
var pending_requests = {}
# Request ID counter for tracking
var request_counter = 0

func _ready():
	print("FirebaseDB initialized")

# ---- Authentication ----

# Anonymous sign-in (for testing)
func anonymous_sign_in():
	if is_authenticating:
		return
		
	is_authenticating = true
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_anonymous_sign_in_completed)
	
	var url = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + FIREBASE_API_KEY
	var body = JSON.stringify({
		"returnSecureToken": true
	})
	
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		print("Error making anonymous sign-in request: " + str(error))
		is_authenticating = false
		emit_signal("auth_failed", error, "Failed to connect to authentication server")

func _on_anonymous_sign_in_completed(result, response_code, headers, body):
	is_authenticating = false
	
	# Clean up the request
	var requester = get_node_or_null("%s" % [result])
	if requester:
		requester.queue_free()
	
	if response_code != 200:
		print("Authentication error: " + str(response_code))
		print("Response: " + body.get_string_from_utf8())
		emit_signal("auth_failed", response_code, "Authentication failed")
		return
		
	var response = JSON.parse_string(body.get_string_from_utf8())
	
	if response and "idToken" in response:
		auth_token = response.idToken
		is_authenticated = true
		print("Anonymous authentication successful")
		emit_signal("auth_succeeded")
	else:
		print("Authentication response missing token")
		emit_signal("auth_failed", 0, "Authentication response missing token")

# Sign-in with email/password
func sign_in_with_email(email: String, password: String):
	if is_authenticating:
		return
		
	is_authenticating = true
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_email_sign_in_completed)
	
	var url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + FIREBASE_API_KEY
	var body = JSON.stringify({
		"email": email,
		"password": password,
		"returnSecureToken": true
	})
	
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		print("Error making email sign-in request: " + str(error))
		is_authenticating = false
		emit_signal("auth_failed", error, "Failed to connect to authentication server")

func _on_email_sign_in_completed(result, response_code, headers, body):
	is_authenticating = false
	
	# Clean up the request
	var requester = get_node_or_null("%s" % [result])
	if requester:
		requester.queue_free()
	
	if response_code != 200:
		print("Authentication error: " + str(response_code))
		print("Response: " + body.get_string_from_utf8())
		emit_signal("auth_failed", response_code, "Authentication failed")
		return
		
	var response = JSON.parse_string(body.get_string_from_utf8())
	
	if response and "idToken" in response:
		auth_token = response.idToken
		is_authenticated = true
		print("Email authentication successful")
		emit_signal("auth_succeeded")
	else:
		print("Authentication response missing token")
		emit_signal("auth_failed", 0, "Authentication response missing token")

# ---- Database Operations ----

# Read data once from specified path
func read_data(path: String):
	if !is_authenticated and !path.begins_with("public/"):
		print("Warning: Attempting to read without authentication: " + path)
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Generate a unique ID for this request
	var request_id = str(request_counter)
	request_counter += 1
	
	# Store the request to track it
	pending_requests[request_id] = {
		"path": path,
		"type": "read",
		"request": http_request
	}
	
	# Connect to the completion signal
	http_request.request_completed.connect(_on_request_completed.bind(request_id))
	
	# Construct URL
	var url = FIREBASE_DATABASE_URL + path + ".json"
	print(url)
	if is_authenticated and auth_token != "":
		url += "?auth=" + auth_token
	
	# Make the request
	var error = http_request.request(url)
	if error != OK:
		print("Error making HTTP request: " + str(error))
		_cleanup_request(request_id)

# Write data to specified path (replaces any existing data)
func write_data(path: String, data):
	if !is_authenticated and !path.begins_with("public/"):
		print("Warning: Attempting to write without authentication: " + path)
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Generate a unique ID for this request
	var request_id = str(request_counter)
	request_counter += 1
	
	# Store the request to track it
	pending_requests[request_id] = {
		"path": path,
		"type": "write",
		"request": http_request,
		"data": data
	}
	
	# Connect to the completion signal
	http_request.request_completed.connect(_on_request_completed.bind(request_id))
	
	# Construct URL
	var url = FIREBASE_DATABASE_URL + path + ".json"
	if is_authenticated and auth_token != "":
		url += "?auth=" + auth_token
	
	# Convert data to JSON
	var json_data = JSON.stringify(data)
	
	# Set headers
	var headers = ["Content-Type: application/json"]
	
	# Make the request (PUT replaces all data)
	var error = http_request.request(url, headers, HTTPClient.METHOD_PUT, json_data)
	if error != OK:
		print("Error making HTTP request: " + str(error))
		_cleanup_request(request_id)

# Update only specific fields at the path without overwriting everything
func update_data(path: String, data):
	if !is_authenticated and !path.begins_with("public/"):
		print("Warning: Attempting to update without authentication: " + path)
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Generate a unique ID for this request
	var request_id = str(request_counter)
	request_counter += 1
	
	# Store the request to track it
	pending_requests[request_id] = {
		"path": path,
		"type": "update",
		"request": http_request,
		"data": data
	}
	
	# Connect to the completion signal
	http_request.request_completed.connect(_on_request_completed.bind(request_id))
	
	# Construct URL
	var url = FIREBASE_DATABASE_URL + path + ".json"
	if is_authenticated and auth_token != "":
		url += "?auth=" + auth_token
	
	# Convert data to JSON
	var json_data = JSON.stringify(data)
	
	# Set headers
	var headers = ["Content-Type: application/json"]
	
	# Make the request (PATCH updates specific fields)
	var error = http_request.request(url, headers, HTTPClient.METHOD_PATCH, json_data)
	if error != OK:
		print("Error making HTTP request: " + str(error))
		_cleanup_request(request_id)

# Delete data at specified path
func delete_data(path: String):
	if !is_authenticated and !path.begins_with("public/"):
		print("Warning: Attempting to delete without authentication: " + path)
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Generate a unique ID for this request
	var request_id = str(request_counter)
	request_counter += 1
	
	# Store the request to track it
	pending_requests[request_id] = {
		"path": path,
		"type": "delete",
		"request": http_request
	}
	
	# Connect to the completion signal
	http_request.request_completed.connect(_on_request_completed.bind(request_id))
	
	# Construct URL
	var url = FIREBASE_DATABASE_URL + path + ".json"
	print(url)
	if is_authenticated and auth_token != "":
		url += "?auth=" + auth_token
	
	# Make the request
	var error = http_request.request(url, [], HTTPClient.METHOD_DELETE)
	if error != OK:
		print("Error making HTTP request: " + str(error))
		_cleanup_request(request_id)

# ---- Event-Driven Listeners ----

# Start listening for changes at a specific path
func listen_for_changes(path: String):
	# Check if we're already listening to this path
	if path in active_listeners:
		print("Already listening to path: " + path)
		return
	
	print("Starting listener for path: " + path)
	
	# Create a persistent HTTP request
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Store in active listeners
	active_listeners[path] = {
		"request": http_request,
		"last_event_id": null
	}
	
	# Connect to the completion signal
	http_request.request_completed.connect(_on_listener_update.bind(path))
	
	# Start the initial request
	_start_listener_request(path)

# Stop listening for changes at a specific path
func stop_listening(path: String):
	if path in active_listeners:
		var listener = active_listeners[path]
		if listener.request:
			listener.request.cancel_request()
			listener.request.queue_free()
		active_listeners.erase(path)
		print("Stopped listening to path: " + path)

# ---- Internal Helper Methods ----

# Handle completed HTTP requests
func _on_request_completed(result, response_code, headers, body, request_id):
	if not request_id in pending_requests:
		print("Got response for unknown request ID: " + request_id)
		return
	
	var request_info = pending_requests[request_id]
	var path = request_info.path
	
	if response_code == 200:
		if body.size() > 0:
			var json_result = JSON.parse_string(body.get_string_from_utf8())
			
			# Emit signal with the updated data
			if request_info.type != "delete":
				emit_signal("data_updated", path, json_result)
	else:
		print("HTTP Error: " + str(response_code) + " for path: " + path)
		print("Response: " + body.get_string_from_utf8())
	
	# Clean up the request
	_cleanup_request(request_id)

# Handle updates from listeners
func _on_listener_update(result, response_code, headers, body, path):
	if not path in active_listeners:
		print("Got update for inactive listener: " + path)
		return
	
	if response_code == 200:
		if body.size() > 0:
			var json_result = JSON.parse_string(body.get_string_from_utf8())
			
			# Emit signal with the updated data
			emit_signal("data_updated", path, json_result)
			
			# Look for the last event ID in headers
			for header in headers:
				if header.begins_with("ETag:"):
					active_listeners[path].last_event_id = header.substr(6).strip_edges()
	else:
		print("Listener HTTP Error: " + str(response_code) + " for path: " + path)
		print("Response: " + body.get_string_from_utf8())
		emit_signal("listener_error", path, response_code)
	
	# Firebase REST API doesn't support true streaming, so we need to re-request
	# with a small delay to prevent constant polling
	await get_tree().create_timer(2.0).timeout
	
	# Check if listener is still active
	if path in active_listeners:
		_start_listener_request(path)

# Start or restart a listener request
func _start_listener_request(path: String):
	if not path in active_listeners:
		return
		
	var listener = active_listeners[path]
	var url = FIREBASE_DATABASE_URL + path + ".json"
	
	# Add auth token if authenticated
	if is_authenticated and auth_token != "":
		url += "?auth=" + auth_token
		
		# Add ETag if we have a last event ID to only get changes
		if listener.last_event_id != null:
			url += "&orderBy=\"$key\"&startAt=\"" + listener.last_event_id + "\""
	else:
		# Add ETag if we have a last event ID to only get changes
		if listener.last_event_id != null:
			url += "?orderBy=\"$key\"&startAt=\"" + listener.last_event_id + "\""
	
	var headers = []
	var error = listener.request.request(url, headers)
	
	if error != OK:
		print("Error starting listener for path " + path + ": " + str(error))
		emit_signal("listener_error", path, error)

# Clean up a request
func _cleanup_request(request_id: String):
	if request_id in pending_requests:
		var request = pending_requests[request_id].request
		if request:
			request.queue_free()
		pending_requests.erase(request_id)

# Clean up all resources when node is destroyed
func _exit_tree():
	# Stop all active listeners
	for path in active_listeners:
		stop_listening(path)
	
	# Clean up any pending requests
	for request_id in pending_requests:
		_cleanup_request(request_id)
