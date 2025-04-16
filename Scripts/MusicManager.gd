extends Node

# Menu background music
var menu_music: AudioStreamMP3
var music_player: AudioStreamPlayer

# Music volume settings
var music_volume: float = 0.2  # Quiet volume
var is_playing: bool = false

func _ready():
	# Ensure the music player persists across scene changes
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Load menu background music
	menu_music = load("res://assets/sounds/backgroundMusic/menu_background_music.mp3")
	
	# Create audio stream player
	music_player = AudioStreamPlayer.new()
	music_player.stream = menu_music
	music_player.volume_db = linear_to_db(music_volume)
	music_player.autoplay = false
	music_player.stream.loop = true
	music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music_player)

func play_menu_music():
	if music_player and menu_music and not is_playing:
		music_player.play()
		is_playing = true

func stop_menu_music():
	if music_player and is_playing:
		music_player.stop()
		is_playing = false

# Stop music when entering game scene
func stop_for_game():
	if music_player and is_playing:
		music_player.stop()
		is_playing = false

# Adjust music volume
func set_music_volume(value: float):
	music_volume = clamp(value, 0.0, 1.0)
	if music_player:
		music_player.volume_db = linear_to_db(music_volume)
