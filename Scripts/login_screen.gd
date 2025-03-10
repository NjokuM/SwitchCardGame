extends Control

@onready var email_input = $LoginContainer/EmailInput
@onready var password_input = $LoginContainer/PasswordInput
@onready var login_button = $LoginContainer/LoginButton
@onready var signup_button = $LoginContainer/SignupButton
@onready var back_button = $LoginContainer/BackButton
@onready var error_label = $LoginContainer/ErrorLabel

func _ready():
	login_button.pressed.connect(_on_login_button_pressed)
	signup_button.pressed.connect(_on_signup_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	
	# Connect signals from AuthManager
	var auth = get_node("/root/AuthManager")
	
	if auth != null:
		auth.login_succeeded.connect(_on_login_succeeded)
		auth.login_failed.connect(_on_login_failed)
	else:
		print("AuthManager not found!")
	
	# Hide error message initially
	error_label.text = ""
	error_label.visible = false

func _on_login_button_pressed():
	var email = email_input.text.strip_edges()
	var password = password_input.text
	
	if email.is_empty() or password.is_empty():
		error_label.text = "Please enter both email and password"
		error_label.visible = true
		return
	
	# Show loading indicator or disable buttons
	login_button.disabled = true
	signup_button.disabled = true
	error_label.text = "Logging in..."
	error_label.visible = true
	
	# Attempt login
	var auth = get_node("/root/AuthManager")
	if auth != null:
		auth.login_with_email(email, password)
	else:
		error_label.text = "Authentication system not available"
		error_label.visible = true
		login_button.disabled = false
		signup_button.disabled = false

func _on_signup_button_pressed():
	# Navigate to the signup screen
	get_tree().change_scene_to_file("res://scene/signup_screen.tscn")

func _on_back_button_pressed():
	# Navigate back to main menu
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")

func _on_login_succeeded(user_data):
	print("Login successful: ", user_data.email)
	
	# Re-enable buttons
	login_button.disabled = false
	signup_button.disabled = false
	
	# Navigate to the main menu
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")

func _on_login_failed(error_code, error_message):
	# Re-enable buttons
	login_button.disabled = false
	signup_button.disabled = false
	
	# Show error message
	error_label.text = "Login failed: " + error_message
	error_label.visible = true
