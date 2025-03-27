extends Control

# Firebase CRUD Operation Test Script

@onready var test_results = $ScrollContainer/VBoxContainer/TestResults
@onready var status_label = $StatusLabel
@onready var run_tests_button = $RunTestsButton
@onready var clear_button = $ClearButton

var auth_manager
var firebase_db

# Login Credentials
const TEST_EMAIL = "euser@euser.com"
const TEST_PASSWORD = "password"

# Test tracking
var tests_completed = 0
var tests_passed = 0
var tests_failed = 0

func _ready():
	# Connect UI signals
	run_tests_button.pressed.connect(_on_run_tests_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	
	# Find singletons
	auth_manager = get_node_or_null("/root/AuthManager")
	firebase_db = get_node_or_null("/root/FirebaseDB")
	
	status_label.text = "Ready to run tests"

func _on_run_tests_pressed():
	# Clear previous test results
	clear_test_results()
	status_label.text = "Running tests..."
	
	# Reset test counters
	tests_completed = 0
	tests_passed = 0
	tests_failed = 0
	
	# Run the test sequence
	await run_test_sequence()
	
	# Display final results
	status_label.text = "Tests completed: %d, Passed: %d, Failed: %d" % [tests_completed, tests_passed, tests_failed]

func _on_clear_pressed():
	clear_test_results()
	status_label.text = "Ready to run tests"

func clear_test_results():
	test_results.text = ""

func log_message(message: String):
	test_results.text += message + "\n"
	# Scroll to bottom
	await get_tree().process_frame
	var scroll = test_results.get_parent().get_parent() as ScrollContainer
	if scroll:
		scroll.scroll_vertical = test_results.get_line_count() * test_results.get_line_height()

func assert_test(condition: bool, test_name: String):
	tests_completed += 1
	
	if condition:
		tests_passed += 1
		log_message("✅ PASS: " + test_name)
	else:
		tests_failed += 1
		log_message("❌ FAIL: " + test_name)

func run_test_sequence():
	# Authenticate first
	var authenticated = await test_authentication()
	
	if authenticated:
		# Run CRUD tests
		await test_create_operation()
		await test_read_operation()
		await test_update_operation()
		await test_delete_operation()
	
	log_message("\nAll tests completed!")

func test_authentication() -> bool:
	log_message("\n--- Testing Authentication ---")
	
	var auth_completed = false
	var auth_success = false
	
	# Connect to login signals
	var succeeded_connection = auth_manager.login_succeeded.connect(func(_user_data):
		auth_completed = true
		auth_success = true
	)
	
	var failed_connection = auth_manager.login_failed.connect(func(error_code, error_message):
		log_message("Login Failed: " + str(error_code) + " - " + error_message)
		auth_completed = true
		auth_success = false
	)
	
	# Attempt login
	auth_manager.login_with_email(TEST_EMAIL, TEST_PASSWORD)
	
	# Wait for login result
	var start_time = Time.get_unix_time_from_system()
	while !auth_completed and (Time.get_unix_time_from_system() - start_time < 10.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signals
	if succeeded_connection:
		auth_manager.login_succeeded.disconnect(succeeded_connection)
	if failed_connection:
		auth_manager.login_failed.disconnect(failed_connection)
	
	# Log and assert authentication
	if auth_success:
		log_message("✅ Logged in as: " + TEST_EMAIL)
	else:
		log_message("❌ Authentication failed")
	
	return auth_success

func test_create_operation():
	log_message("\n--- Testing CREATE Operation ---")
	
	var test_path = "test/crud_create_" + str(randi() % 10000)
	var test_data = {
		"message": "Hello, Firebase!",
		"timestamp": Time.get_unix_time_from_system(),
		"user_email": TEST_EMAIL
	}
	
	var write_completed = false
	var write_success = false
	
	# Connect to network request signal
	var connection = firebase_db.network_request_completed.connect(func(success, path, _data):
		if path == test_path:
			write_completed = true
			write_success = success
	)
	
	# Perform write operation
	firebase_db.write_data(test_path, test_data)
	
	# Wait for operation to complete
	var start_time = Time.get_unix_time_from_system()
	while !write_completed and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	if connection:
		firebase_db.network_request_completed.disconnect(connection)
	
	# Assert test result
	assert_test(write_completed and write_success, "Create Operation")
	
	return test_path

func test_read_operation(path = null):
	log_message("\n--- Testing READ Operation ---")
	
	if path == null:
		path = "test/crud_create_" + str(randi() % 10000)
	
	var read_completed = false
	var read_success = false
	var read_data = null
	
	# Connect to data updated signal
	var connection = firebase_db.data_updated.connect(func(update_path, data):
		if update_path == path:
			read_completed = true
			read_success = data != null
			read_data = data
	)
	
	# Perform read operation
	firebase_db.read_data(path)
	
	# Wait for operation to complete
	var start_time = Time.get_unix_time_from_system()
	while !read_completed and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	if connection:
		firebase_db.data_updated.disconnect(connection)
	
	# Log read data
	if read_data:
		log_message("Read Data: " + str(read_data))
	
	# Assert test result
	assert_test(read_completed and read_success, "Read Operation")
	
	return read_data

func test_update_operation(path = null):
	log_message("\n--- Testing UPDATE Operation ---")
	
	if path == null:
		path = "test/crud_create_" + str(randi() % 10000)
	
	var update_data = {
		"message": "Updated Firebase data!",
		"timestamp": Time.get_unix_time_from_system(),
		"user_email": TEST_EMAIL
	}
	
	var update_completed = false
	var update_success = false
	
	# Connect to network request signal
	var connection = firebase_db.network_request_completed.connect(func(success, update_path, _data):
		if update_path == path:
			update_completed = true
			update_success = success
	)
	
	# Perform update operation
	firebase_db.update_data(path, update_data)
	
	# Wait for operation to complete
	var start_time = Time.get_unix_time_from_system()
	while !update_completed and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	if connection:
		firebase_db.network_request_completed.disconnect(connection)
	
	# Assert test result
	assert_test(update_completed and update_success, "Update Operation")
	
	return path

func test_delete_operation(path = null):
	log_message("\n--- Testing DELETE Operation ---")
	
	if path == null:
		path = "test/crud_create_" + str(randi() % 10000)
	
	var delete_completed = false
	var delete_success = false
	
	# Connect to network request signal
	var connection = firebase_db.network_request_completed.connect(func(success, delete_path, _data):
		if delete_path == path:
			delete_completed = true
			delete_success = success
	)
	
	# Perform delete operation
	firebase_db.delete_data(path)
	
	# Wait for operation to complete
	var start_time = Time.get_unix_time_from_system()
	while !delete_completed and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	if connection:
		firebase_db.network_request_completed.disconnect(connection)
	
	# Assert test result
	assert_test(delete_completed and delete_success, "Delete Operation")
