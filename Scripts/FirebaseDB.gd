extends Node

# Firebase configuration
const FIREBASE_DATABASE_URL = "https://switchcardgame-b3b34-default-rtdb.europe-west1.firebasedatabase.app/"

# Authentication manager reference
var auth_manager = null

# Signals for event-driven approach
signal data_updated(path, data)
signal listener_registered(path)
signal listener_error(path, error)
signal network_request_completed(success, path, data)

# Track active listeners to avoid duplicates
var active_listeners = {}
# Track pending HTTP requests
var pending_requests = {}
# Request ID counter for tracking
var request_counter = 0

func _ready():
	print("FirebaseDB initialized")
	# Get reference to AuthManager
	auth_manager = get_node_or_null("/root/AuthManager")
	
	# Connect to authentication signals if AuthManager exists
	if auth_manager:
		auth_manager.login_succeeded.connect(_on_login_succeeded)
		auth_manager.logout_succeeded.connect(_on_logout_succeeded)

func _on_login_succeeded(_user_data):
	print("FirebaseDB: Authentication updated from AuthManager")

func _on_logout_succeeded():
	print("FirebaseDB: Authentication reset")
	# Clear any active listeners or pending requests if needed
	for path in active_listeners:
		stop_listening(path)
	pending_requests.clear()

# Create a centralized method for making HTTP requests
func _make_authenticated_request(method: String, path: String, data = null):
	# Ensure we have an AuthManager and are logged in
	if !auth_manager or !auth_manager.is_logged_in():
		print("WARNING: Cannot make request - not authenticated")
		emit_signal("network_request_completed", false, path, null)
		return null
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Generate a unique ID for this request
	var request_id = str(request_counter)
	request_counter += 1
	
	# Construct URL with authentication token
	var url = FIREBASE_DATABASE_URL + path + ".json?auth=" + auth_manager.id_token
	
	# Prepare headers and body
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify(data) if data else ""
	
	# Store the request details
	pending_requests[request_id] = {
		"path": path,
		"type": method,
		"request": http_request,
		"data": data
	}
	
	# Connect to request completion signal
	http_request.request_completed.connect(_on_request_completed.bind(request_id))
	
	# Make the request based on method
	var error
	match method:
		"GET":
			error = http_request.request(url, headers, HTTPClient.METHOD_GET)
		"PUT":
			error = http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
		"POST":
			error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
		"PATCH":
			error = http_request.request(url, headers, HTTPClient.METHOD_PATCH, body)
		"DELETE":
			error = http_request.request(url, headers, HTTPClient.METHOD_DELETE)
		_:
			print("ERROR: Invalid HTTP method")
			_cleanup_request(request_id)
			return null
	
	if error != OK:
		print("Error making HTTP request: " + str(error))
		_cleanup_request(request_id)
	
	return http_request

# Read data from a specific path
func read_data(path: String):
	print("Reading data from: " + path)
	return _make_authenticated_request("GET", path)

# Write data to a specific path (replaces existing data)
func write_data(path: String, data):
	print("Writing data to: " + path)
	return _make_authenticated_request("PUT", path, data)

# Update specific fields without overwriting entire path
func update_data(path: String, data):
	print("Updating data at: " + path)
	return _make_authenticated_request("PATCH", path, data)

# Delete data at a specific path
func delete_data(path: String):
	print("Deleting data at: " + path)
	return _make_authenticated_request("DELETE", path)

# Handle completed HTTP requests
func _on_request_completed(result, response_code, headers, body, request_id):
	if not request_id in pending_requests:
		print("Got response for unknown request ID: " + request_id)
		return
	
	var request_info = pending_requests[request_id]
	var path = request_info.path
	
	# Parse response body
	var json_result = null
	if body.size() > 0:
		json_result = JSON.parse_string(body.get_string_from_utf8())
	
	# Check response code
	if response_code == 200:
		# Emit signal with updated data (except for DELETE requests)
		if request_info.type != "DELETE":
			emit_signal("data_updated", path, json_result)
		
		# Signal successful network request
		emit_signal("network_request_completed", true, path, json_result)
	else:
		# Log error details
		print("HTTP Error: " + str(response_code) + " for path: " + path)
		print("Response: " + body.get_string_from_utf8())
		
		# Emit error signals
		emit_signal("listener_error", path, response_code)
		emit_signal("network_request_completed", false, path, json_result)
	
	# Clean up the request
	_cleanup_request(request_id)

# Start listening for changes at a specific path
func listen_for_changes(path: String):
	# Check if we're already listening to this path
	if path in active_listeners:
		print("Already listening to path: " + path)
		return
	
	print("Starting listener for path: " + path)
	
	# Ensure authentication
	if !auth_manager or !auth_manager.is_logged_in():
		print("Cannot start listener - not authenticated")
		return
	
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

# Start or restart a listener request
func _start_listener_request(path: String):
	if not path in active_listeners or !auth_manager or !auth_manager.is_logged_in():
		return
		
	var listener = active_listeners[path]
	var url = FIREBASE_DATABASE_URL + path + ".json?auth=" + auth_manager.id_token
	
	# Add ETag if we have a last event ID to only get changes
	if listener.last_event_id != null:
		url += "&orderBy=\"$key\"&startAt=\"" + listener.last_event_id + "\""
	
	var headers = []
	var error = listener.request.request(url, headers)
	
	if error != OK:
		print("Error starting listener for path " + path + ": " + str(error))
		emit_signal("listener_error", path, error)

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
