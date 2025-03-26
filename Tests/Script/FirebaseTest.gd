extends Control

# Firebase integration test script
# Verifies FirebaseDB, SessionSync, and Deck functionality

# UI Components
@onready var test_results = $ScrollContainer/VBoxContainer/TestResults
@onready var status_label = $StatusLabel
@onready var run_tests_button = $RunTestsButton
@onready var clear_button = $ClearButton

# Test Variables
var firebase_db
var session_sync
var deck
var test_session_id = "test_session_" + str(randi() % 100000)
var tests_completed = 0
var tests_passed = 0
var tests_failed = 0

func _ready():
	# Connect UI signals
	run_tests_button.pressed.connect(_on_run_tests_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	
	# Initialize status
	status_label.text = "Ready to run tests"
	
	# Look for required nodes
	firebase_db = get_node_or_null("/root/FirebaseDB")
	if firebase_db:
		log_message("✅ Found FirebaseDB singleton")
	else:
		log_message("❌ FirebaseDB singleton not found!")
	
	session_sync = get_node_or_null("/root/SessionSync")
	if session_sync:
		log_message("✅ Found SessionSync singleton")
	else:
		log_message("❌ SessionSync singleton not found!")
	
	deck = get_node_or_null("/root/Main/Deck")
	if deck:
		log_message("✅ Found Deck node")
	else:
		log_message("❌ Deck node not found!")

func _on_run_tests_pressed():
	clear_test_results()
	log_message("Starting Firebase integration tests...")
	status_label.text = "Running tests..."
	
	tests_completed = 0
	tests_passed = 0
	tests_failed = 0
	
	# First authenticate with Firebase
	if firebase_db and !firebase_db.is_authenticated:
		log_message("Authenticating with Firebase...")
		firebase_db.auth_succeeded.connect(_on_auth_succeeded_run_tests)
		firebase_db.auth_failed.connect(_on_auth_failed)
		firebase_db.anonymous_sign_in()
	else:
		# Already authenticated or no Firebase DB
		await run_test_sequence()
		
		# Show final results
		status_label.text = "Tests completed: " + str(tests_completed) + ", Passed: " + str(tests_passed) + ", Failed: " + str(tests_failed)

func _on_auth_succeeded_run_tests():
	log_message("✅ Authentication successful")
	firebase_db.auth_succeeded.disconnect(_on_auth_succeeded_run_tests)
	firebase_db.auth_failed.disconnect(_on_auth_failed)
	
	# Now run the tests
	await run_test_sequence()
	
	# Show final results
	status_label.text = "Tests completed: " + str(tests_completed) + ", Passed: " + str(tests_passed) + ", Failed: " + str(tests_failed)

func _on_auth_failed(error_code, error_message):
	log_message("❌ Authentication failed: " + str(error_code) + " - " + error_message)
	firebase_db.auth_succeeded.disconnect(_on_auth_succeeded_run_tests)
	firebase_db.auth_failed.disconnect(_on_auth_failed)
	
	# Cannot run tests without authentication
	status_label.text = "Tests aborted: Authentication failed"

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
	# Test 1: FirebaseDB basic functionality
	await test_firebase_db()
	
	# Test 2: SessionSync core functionality
	await test_session_sync()
	
	# Test 3: Deck integration
	await test_deck_integration()
	
	# Test 4: Full game action sequence
	await test_game_action_sequence()
	
	log_message("\nAll tests completed!")

func test_firebase_db():
	log_message("\n--- Testing FirebaseDB ---")
	
	if not firebase_db:
		log_message("❌ Cannot test FirebaseDB: singleton not found")
		return
	
	# Test write operation
	var test_data = {
		"test_key": "test_value",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	var write_successful = false
	var test_path = "test/firebase_db_test"
	
	# Connect to data_updated signal temporarily
	var callable = func(path, data):
		if path == test_path and data and "test_key" in data:
			write_successful = data.test_key == "test_value"
	
	firebase_db.data_updated.connect(callable)
	
	# Write test data
	firebase_db.write_data(test_path, test_data)
	
	# Wait for response (with timeout)
	var start_time = Time.get_unix_time_from_system()
	while not write_successful and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	firebase_db.data_updated.disconnect(callable)
	
	# Assert test result
	assert_test(write_successful, "FirebaseDB write operation")
	
	# Test read operation
	var read_successful = false
	callable = func(path, data):
		if path == test_path and data and "test_key" in data:
			read_successful = data.test_key == "test_value"
	
	firebase_db.data_updated.connect(callable)
	
	# Read test data
	firebase_db.read_data(test_path)
	
	# Wait for response (with timeout)
	start_time = Time.get_unix_time_from_system()
	while not read_successful and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	firebase_db.data_updated.disconnect(callable)
	
	# Assert test result
	assert_test(read_successful, "FirebaseDB read operation")
	
	# Test delete operation
	var delete_successful = false
	callable = func(path, data):
		if path == test_path:
			delete_successful = data == null
	
	firebase_db.data_updated.connect(callable)
	
	# Delete test data
	firebase_db.delete_data(test_path)
	
	# Wait for response (with timeout)
	start_time = Time.get_unix_time_from_system()
	while not delete_successful and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	firebase_db.data_updated.disconnect(callable)
	
	# Assert test result
	assert_test(delete_successful, "FirebaseDB delete operation")

func test_session_sync():
	log_message("\n--- Testing SessionSync ---")
	
	if not session_sync:
		log_message("❌ Cannot test SessionSync: singleton not found")
		return
		
	if not firebase_db:
		log_message("❌ Cannot test SessionSync: FirebaseDB singleton not found")
		return
	
	# Test session initialization
	var session_initialized = false
	
	# Set up test session
	session_sync.session_id = test_session_id
	session_sync.is_host = true
	session_sync.local_player_index = 0
	session_sync.initialize_game_state(2)  # Initialize for 2 players
	
	# Check if initialization worked
	session_initialized = session_sync.is_game_initialized && session_sync.num_players == 2
	
	# Assert test result
	assert_test(session_initialized, "SessionSync initialization")
	
	# Test game state update
	var game_state_updated = false
	
	# Connect to signal temporarily
	var callable = func():
		game_state_updated = true
	
	session_sync.game_state_synchronized.connect(callable)
	
	# Force game state update
	session_sync._update_game_state()
	
	# Wait for response (with timeout)
	var start_time = Time.get_unix_time_from_system()
	while not game_state_updated and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	session_sync.game_state_synchronized.disconnect(callable)
	
	# Assert test result
	assert_test(game_state_updated, "SessionSync game state update")
	
	# Test initial card dealing
	var cards_dealt = false
	
	# Connect to signal temporarily
	callable = func():
		# Check if hands have cards
		cards_dealt = session_sync.player_hands[0].size() > 0 && session_sync.player_hands[1].size() > 0
	
	session_sync.game_state_synchronized.connect(callable)
	
	# Deal initial cards
	session_sync.deal_initial_cards(5)  # Deal 5 cards per player
	
	# Wait for response (with timeout)
	start_time = Time.get_unix_time_from_system()
	while not cards_dealt and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	session_sync.game_state_synchronized.disconnect(callable)
	
	# Assert test result
	assert_test(cards_dealt, "SessionSync initial card dealing")

func test_deck_integration():
	log_message("\n--- Testing Deck Integration ---")
	
	if not deck:
		log_message("❌ Cannot test Deck: node not found")
		return
		
	if not session_sync:
		log_message("❌ Cannot test Deck integration: SessionSync singleton not found")
		return
	
	# Test deck connection to SessionSync
	var deck_connected = deck.is_using_session_sync()
	
	# Assert test result
	assert_test(deck_connected, "Deck connected to SessionSync")
	
	# Test card creation from data
	var card_created = false
	
	# Create a test card
	var test_card = deck.create_card_from_data("Ace", "Spades")
	
	card_created = test_card != null && test_card.value == "Ace" && test_card.suit == "Spades"
	
	# Clean up the test card
	if test_card:
		test_card.queue_free()
	
	# Assert test result
	assert_test(card_created, "Deck card creation from data")

func test_game_action_sequence():
	log_message("\n--- Testing Game Action Sequence ---")
	
	if not session_sync:
		log_message("❌ Cannot test game actions: SessionSync singleton not found")
		return
		
	if not firebase_db:
		log_message("❌ Cannot test game actions: FirebaseDB singleton not found")
		return
	
	# Test card play
	var card_played = false
	
	# Connect to signal temporarily
	var callable = func(player_index, cards, special_effects):
		card_played = player_index == 0 && cards.size() > 0
	
	session_sync.cards_played.connect(callable)
	
	# Make sure player has at least one card
	if session_sync.player_hands[0].size() == 0:
		session_sync.player_hands[0].append({"value": "7", "suit": "Hearts"})
		session_sync._update_game_state()
	
	# Play a card
	var test_card = session_sync.player_hands[0][0].duplicate()
	session_sync.submit_card_play(0, [test_card])
	
	# Wait for response (with timeout)
	var start_time = Time.get_unix_time_from_system()
	while not card_played and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	session_sync.cards_played.disconnect(callable)
	
	# Assert test result
	assert_test(card_played, "Game action: Play card")
	
	# Test card draw
	var card_drawn = false
	
	# Connect to signal temporarily
	callable = func(player_index, card_count):
		card_drawn = player_index == 0 && card_count > 0
	
	session_sync.cards_drawn.connect(callable)
	
	# Draw a card
	session_sync.submit_card_draw(0)
	
	# Wait for response (with timeout)
	start_time = Time.get_unix_time_from_system()
	while not card_drawn and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	session_sync.cards_drawn.disconnect(callable)
	
	# Assert test result
	assert_test(card_drawn, "Game action: Draw card")
	
	# Test turn change
	var turn_changed = false
	
	# Connect to signal temporarily
	callable = func(player_index):
		turn_changed = player_index == 1
	
	session_sync.turn_changed.connect(callable)
	
	# Change turn
	session_sync.submit_turn_change(1, 1)
	
	# Wait for response (with timeout)
	start_time = Time.get_unix_time_from_system()
	while not turn_changed and (Time.get_unix_time_from_system() - start_time < 5.0):
		await get_tree().create_timer(0.1).timeout
	
	# Disconnect signal
	session_sync.turn_changed.disconnect(callable)
	
	# Assert test result
	assert_test(turn_changed, "Game action: Change turn")
	
	# Clean up test session
	firebase_db.delete_data("sessions/" + test_session_id)
