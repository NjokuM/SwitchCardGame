extends Node

# Firebase database communication handler
signal data_updated(path, data)

# Firebase database URL
const DATABASE_URL = "https://switchcardgame-b3b34-default-rtdb.europe-west1.firebasedatabase.app/"

# HTTP request objects
var db_request
var listener_request

func _ready():
	# Create HTTP request nodes
	db_request = HTTPRequest.new()
	listener_request = HTTPRequest.new()
	add_child(db_request)
	add_child(listener_request)
	
	# Connect signals
	db_request.request_completed.connect(_on_request_completed)
	listener_request.request_completed.connect(_on_listener_request_completed)
	
	print("Firebase DB initialized")

# Write data to a specific path
func write_data(path, data):
	var auth = get_node_or_null("/root/AuthManager")
	if not auth or not auth.is_logged_in():
		push_error("Cannot write to database: Not logged in")
		return
	
	var json_data = JSON.stringify(data)
	var url = DATABASE_URL + path + ".json?auth=" + auth.id_token
	var headers = ["Content-Type: application/json"]
	
	print("Writing to Firebase path: " + path)
	var error = db_request.request(url, headers, HTTPClient.METHOD_PUT, json_data)
	if error != OK:
		push_error("Failed to send database write request: " + str(error))

# Update specific fields without overwriting the entire object
func update_data(path, data):
	var auth = get_node_or_null("/root/AuthManager")
	if not auth or not auth.is_logged_in():
		push_error("Cannot update database: Not logged in")
		return
	
	var json_data = JSON.stringify(data)
	var url = DATABASE_URL + path + ".json?auth=" + auth.id_token
	var headers = ["Content-Type: application/json"]
	
	var error = db_request.request(url, headers, HTTPClient.METHOD_PATCH, json_data)
	if error != OK:
		push_error("Failed to send database update request: " + str(error))

# Read data from a specific path
func read_data(path):
	var auth = get_node_or_null("/root/AuthManager")
	if not auth or not auth.is_logged_in():
		push_error("Cannot read from database: Not logged in")
		return
	
	var url = DATABASE_URL + path + ".json?auth=" + auth.id_token
	var headers = ["Content-Type: application/json"]
	
	var error = db_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_error("Failed to send database read request: " + str(error))

# Listen for changes at a specific path
func listen_for_changes(path):
	var auth = get_node_or_null("/root/AuthManager")
	if not auth or not auth.is_logged_in():
		push_error("Cannot listen to database: Not logged in")
		return
	
	var url = DATABASE_URL + path + ".json?auth=" + auth.id_token
	var headers = ["Content-Type: application/json"]
	
	print("Starting listener for path: " + path)
	var error = listener_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_error("Failed to start database listener: " + str(error))

# Handle completion of write/read requests
func _on_request_completed(result, response_code, headers, body):
	var body_text = body.get_string_from_utf8()
	
	if response_code == 200:
		var data = JSON.parse_string(body_text)
		emit_signal("data_updated", "", data)
	else:
		push_error("Database request failed with code: " + str(response_code))
		push_error("Response: " + body_text)

# Handle listener request completion
func _on_listener_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		emit_signal("data_updated", "", json)
		
		# Continue listening - wait briefly to avoid overwhelming the server
		await get_tree().create_timer(1.0).timeout
		listen_for_changes("")
	else:
		push_error("Database listener failed with code: " + str(response_code))
		
		# Try again after a short delay
		await get_tree().create_timer(3.0).timeout
		listen_for_changes("")