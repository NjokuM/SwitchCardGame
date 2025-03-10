# Updated main_menu.gd
extends Control

@onready var play_button = $VBoxContainer/Button
@onready var options_button = $VBoxContainer/Button2
@onready var exit_button = $VBoxContainer/Button3
@onready var login_button = $VBoxContainer/LoginButton
@onready var logout_button = $VBoxContainer/LogoutButton
@onready var user_label = $UserLabel

func _ready():
	# Connect buttons
	play_button.pressed.connect(_on_play_pressed)
	options_button.pressed.connect(_on_options_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	login_button.pressed.connect(_on_login_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	
	# Connect signals from AuthManager
	AuthManager.logout_succeeded.connect(_on_logout_succeeded)
	
	# Update UI based on login status
	update_login_status()

func update_login_status():
	var is_logged_in = AuthManager.is_logged_in()
	
	# Show/hide appropriate buttons
	login_button.visible = !is_logged_in
	logout_button.visible = is_logged_in
	
	# Update user label
	if is_logged_in:
		var user_data = AuthManager.get_user_data()
		var display_name = user_data.display_name if !user_data.display_name.is_empty() else user_data.email
		user_label.text = "Logged in as: " + display_name
		user_label.visible = true
	else:
		user_label.visible = false

func _on_play_pressed():
	get_tree().change_scene_to_file("res://scene/play_menu.tscn")
	
func _on_options_pressed():
	print("Settings pressed")
	
func _on_exit_pressed():
	get_tree().quit()

func _on_login_pressed():
	get_tree().change_scene_to_file("res://scene/login_screen.tscn")

func _on_logout_pressed():
	AuthManager.logout()

func _on_logout_succeeded():
	# Update UI after logout
	update_login_status()
