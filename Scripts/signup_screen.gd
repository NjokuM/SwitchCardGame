extends Control

@onready var email_input = $SignupContainer/EmailInput
@onready var username_input = $SignupContainer/UsernameInput
@onready var password_input = $SignupContainer/PasswordInput
@onready var confirm_password_input = $SignupContainer/ConfirmPasswordInput
@onready var signup_button = $SignupContainer/SignupButton
@onready var back_button = $SignupContainer/BackButton
@onready var error_label = $SignupContainer/ErrorLabel

func _ready():
	signup_button.pressed.connect(_on_signup_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	
	# Connect signals from AuthManager
	var auth = get_node("/root/AuthManager")
	
	if auth != null:
		auth.signup_succeeded.connect(_on_signup_succeeded)
		auth.signup_failed.connect(_on_signup_failed)
	else:
		print("AuthManager not found!")
	
	# Hide error message initially
	error_label.text = ""
	error_label.visible = false

func _on_signup_button_pressed():
	var email = email_input.text.strip_edges()
	var username = username_input.text.strip_edges()
	var password = password_input.text
	var confirm_password = confirm_password_input.text
	
	# Basic validation
	if email.is_empty() or username.is_empty() or password.is_empty():
		error_label.text = "Please fill out all fields"
		error_label.visible = true
		return
	
	if password != confirm_password:
		error_label.text = "Passwords do not match"
		error_label.visible = true
		return
	
	if password.length() < 6:
		error_label.text = "Password must be at least 6 characters"
		error_label.visible = true
		return
	
	# Show loading indicator or disable buttons
	signup_button.disabled = true
	back_button.disabled = true
	error_label.text = "Creating account..."
	error_label.visible = true
	
	# Attempt signup
	var auth = get_node("/root/AuthManager")
	if auth != null:
		auth.signup_with_email(email, password, username)
	else:
		error_label.text = "Authentication system not available"
		error_label.visible = true
		signup_button.disabled = false
		back_button.disabled = false

func _on_back_button_pressed():
	# Navigate back to login screen
	get_tree().change_scene_to_file("res://scene/login_screen.tscn")

func _on_signup_succeeded(user_data):
	print("Signup successful: ", user_data.email)
	
	# Re-enable buttons
	signup_button.disabled = false
	back_button.disabled = false
	
	# Navigate to the main menu
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")

func _on_signup_failed(error_code, error_message):
	# Re-enable buttons
	signup_button.disabled = false
	back_button.disabled = false
	
	# Show error message
	error_label.text = "Signup failed: " + error_message
	error_label.visible = true
