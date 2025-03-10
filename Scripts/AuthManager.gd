
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

# Signals
signal login_succeeded(user_data)
signal login_failed(error_code, error_message)
signal signup_succeeded(user_data)
signal signup_failed(error_code, error_message)
signal logout_succeeded()

func _ready():
	# Check if user is already logged in
	var saved_token = load_user_data()
	if saved_token:
		# Auto login with stored refresh token
		refresh_login_token(saved_token)

# Sign up with email and password
func signup_with_email(email: String, password: String, username: String = ""):
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
