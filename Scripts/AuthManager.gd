extends Node

# Firebase configuration
const API_KEY = "AIzaSyDzvEBUhTdyEdQlwWqq_E-uV8IuK8inPdQ"
const PROJECT_ID = "https://switchcardgame-b3b34-default-rtdb.europe-west1.firebasedatabase.app/"
const EMAIL_SIGNIN_URL = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="
const EMAIL_SIGNUP_URL = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key="
const REFRESH_TOKEN_URL = "https://securetoken.googleapis.com/v1/token?key="

# User data
var user_info = {
	"is_logged_in": false,
	"email": "",
	"display_name": "",
	"user_id": "",
	"photo_url": ""
}

# Authentication tokens
var id_token = ""
var refresh_token = ""
var is_authenticating = false
var is_guest = false

# Signals
signal login_succeeded(user_data)
signal login_failed(error_code, error_message)
signal signup_succeeded(user_data)
signal signup_failed(error_code, error_message)
signal logout_succeeded()
signal auth_succeeded(user_data)
signal auth_failed(error_code, error_message)

func _ready():
	# Check if user is already logged in
	var saved_token = load_user_data()
	if saved_token:
		# Auto login with stored refresh token
		refresh_login_token(saved_token)
	else:
		# Optional: Auto-authenticate as guest
		# Remove comment if you want automatic guest login
			#auto_guest_sign_in()
		pass
		
		
func anonymous_sign_in():
	if is_authenticating:
		return
		
	is_authenticating = true
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_anonymous_signin_completed)
	
	var body = JSON.stringify({
		"returnSecureToken": true
	})
	
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(EMAIL_SIGNUP_URL + API_KEY, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		is_authenticating = false
		push_error("An error occurred in the HTTP request for anonymous signin")
		emit_signal("auth_failed", "HTTP_ERROR", "Failed to send request")

# Callback for anonymous sign in
func _on_anonymous_signin_completed(result, response_code, headers, body):
	is_authenticating = false
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if response_code != 200:
		print("Anonymous Signin Error: ", json.error.message if "error" in json else "Unknown error")
		emit_signal("auth_failed", json.error.code if "error" in json else "UNKNOWN", 
				   json.error.message if "error" in json else "Unknown error")
		return
	
	# Save user info
	id_token = json.idToken
	refresh_token = json.refreshToken
	user_info.is_logged_in = true
	user_info.user_id = json.localId
	user_info.email = ""  # Anonymous users don't have emails
	
	# Generate a guest name
	var guest_name = generate_guest_name()
	user_info.display_name = guest_name
	is_guest = true
	
	print("Anonymous sign-in successful with guest name: " + guest_name)
	
	# Save user data to Firebase database if needed
	# Note: You might want to save guest info differently than regular users
	_save_guest_to_database()
	
	# Emit signals
	emit_signal("auth_succeeded", user_info)
	emit_signal("login_succeeded", user_info)  # For backward compatibility

# Generate a random guest name
func generate_guest_name() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return "Guest" + str(rng.randi_range(1000, 9999))

# Save guest user to database
func _save_guest_to_database():
	if !user_info.is_logged_in or user_info.user_id.is_empty():
		push_error("Cannot save guest data: Not logged in or missing user ID")
		return
	
	var guest_data = {
		"display_name": user_info.display_name,
		"is_guest": true,
		"created_at": Time.get_unix_time_from_system(),
		"last_login": Time.get_unix_time_from_system()
	}
	
	# Add guest user to the database
	_make_database_request("PUT", "/users/" + user_info.user_id, guest_data, "_on_user_data_saved")

# Check if current user is a guest
func is_guest_user() -> bool:
	return is_logged_in() && is_guest

# Helper function to make Firebase Realtime Database requests
func _make_database_request(method: String, path: String, data = null, callback = ""):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	if callback:
		http_request.request_completed.connect(Callable(self, callback))
	
	# Format the URL for Firebase Realtime Database
	var url = PROJECT_ID + path + ".json?auth=" + id_token
	
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify(data) if data else ""
	
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
	
	if error != OK:
		push_error("An error occurred in the database request: " + str(error))
	
	return http_request

# Add this function to save user data to the database after signup
func _save_user_to_database():
	if !user_info.is_logged_in or user_info.user_id.is_empty():
		push_error("Cannot save user data: Not logged in or missing user ID")
		return
	
	var user_data = {
		"email": user_info.email,
		"display_name": user_info.display_name,
		"created_at": Time.get_unix_time_from_system(),
		"last_login": Time.get_unix_time_from_system()
	}
	
	# Add user to the database at /users/{user_id}
	_make_database_request("PUT", "/users/" + user_info.user_id, user_data, "_on_user_data_saved")

# Callback for database save
func _on_user_data_saved(result, response_code, headers, body):
	if response_code == 200:
		print("User data saved to database successfully")
	else:
		var response = JSON.parse_string(body.get_string_from_utf8())
		push_error("Failed to save user data: " + str(response))

# Function to update last login time
func _update_user_last_login():
	if !user_info.is_logged_in or user_info.user_id.is_empty():
		return
		
	var update_data = {
		"last_login": Time.get_unix_time_from_system()
	}
	
	# Update just the last_login field
	_make_database_request("PATCH", "/users/" + user_info.user_id, update_data)

# Sign up with email and password
func signup_with_email(email: String, password: String, username: String = ""):
	# Set the display name right away
	user_info.display_name = email
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_signup_request_completed)
	
	var body = JSON.stringify({
		"email": email,
		"password": password,
		"returnSecureToken": true
	})
	
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(EMAIL_SIGNUP_URL + API_KEY, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("An error occurred in the HTTP request for signup")
		emit_signal("signup_failed", "HTTP_ERROR", "Failed to send request")
# On signup request completed
func _on_signup_request_completed(result, response_code, headers, body):
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if response_code != 200:
		print("Signup Error: ", json.error.message if "error" in json else "Unknown error")
		emit_signal("signup_failed", json.error.code if "error" in json else "UNKNOWN", 
				   json.error.message if "error" in json else "Unknown error")
		return
	
	# Save user info
	id_token = json.idToken
	refresh_token = json.refreshToken
	user_info.is_logged_in = true
	user_info.email = json.email
	user_info.user_id = json.localId
	
	# Save user data locally
	save_user_data()
	
	# Save user data to Firebase database
	_save_user_to_database()
	
	# Emit signal
	emit_signal("signup_succeeded", user_info)

# Login with email and password
func login_with_email(email: String, password: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_login_request_completed)
	
	var body = JSON.stringify({
		"email": email,
		"password": password,
		"returnSecureToken": true
	})
	
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(EMAIL_SIGNIN_URL + API_KEY, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("An error occurred in the HTTP request for login")
		emit_signal("login_failed", "HTTP_ERROR", "Failed to send request")

# On login request completed
func _on_login_request_completed(result, response_code, headers, body):
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if response_code != 200:
		print("Login Error: ", json.error.message if "error" in json else "Unknown error")
		emit_signal("login_failed", json.error.code if "error" in json else "UNKNOWN", 
				   json.error.message if "error" in json else "Unknown error")
		return
	
	# Save user info
	id_token = json.idToken
	refresh_token = json.refreshToken
	user_info.is_logged_in = true
	user_info.email = json.email
	user_info.user_id = json.localId
	
	# Save user data locally
	save_user_data()
	
	# Update last login time in Firebase database
	_update_user_last_login()
	
	# Emit signal
	emit_signal("login_succeeded", user_info)

# Refresh the login token
func refresh_login_token(token: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_refresh_token_completed)
	
	var body = JSON.stringify({
		"grant_type": "refresh_token",
		"refresh_token": token
	})
	
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(REFRESH_TOKEN_URL + API_KEY, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("An error occurred in the HTTP request for token refresh")

# On token refresh completed
func _on_refresh_token_completed(result, response_code, headers, body):
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if response_code != 200:
		print("Token Refresh Error")
		return
	
	# Update tokens
	id_token = json.id_token
	refresh_token = json.refresh_token
	user_info.is_logged_in = true
	
	# Save updated tokens
	save_user_data()
	
	# Update last login in database
	_update_user_last_login()
	
	print("Token refreshed successfully")

# Logout user
func logout():
	user_info.is_logged_in = false
	user_info.email = ""
	user_info.display_name = ""
	user_info.user_id = ""
	user_info.photo_url = ""
	id_token = ""
	refresh_token = ""
	
	# Remove saved data
	var dir = DirAccess.open("user://")
	if dir:
		dir.remove("user_data.dat")
	
	emit_signal("logout_succeeded")

# Save user data to disk
func save_user_data():
	var file = FileAccess.open("user://user_data.dat", FileAccess.WRITE)
	if file:
		file.store_line(refresh_token)
		return true
	return false

# Load user data from disk
func load_user_data():
	if FileAccess.file_exists("user://user_data.dat"):
		var file = FileAccess.open("user://user_data.dat", FileAccess.READ)
		if file:
			var token = file.get_line()
			return token
	return ""

# Check if user is logged in
func is_logged_in() -> bool:
	return user_info.is_logged_in

# Get current user data
func get_user_data() -> Dictionary:
	return user_info
