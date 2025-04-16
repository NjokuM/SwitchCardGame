extends Node

# Sound effect paths
const SOUNDS = {
	"card_select": "res://assets/sounds/soundEffects/button-4-214382.mp3",
	"card_draw": "res://assets/sounds/soundEffects/flipcard-91468.mp3",
	"card_place": "res://assets/sounds/soundEffects/cardPlace3.ogg",
	"card_deal": "res://assets/sounds/soundEffects/playing-cards-being-delt-29099.mp3",
	"win": "res://assets/sounds/soundEffects/winning-218995.mp3"
}

# Preloaded sound streams
var sound_streams = {}

# Volume settings (can be adjusted globally)
var master_volume: float = 0.5
var sound_effects_volume: float = 1.0

func _ready():
	# Preload all sounds
	for key in SOUNDS:
		var stream = load(SOUNDS[key])
		if stream:
			sound_streams[key] = stream
		else:
			print("WARNING: Could not load sound: ", SOUNDS[key])

# Central method to play a sound
func play_sound(sound_key: String, volume_adjust: float = 0):
	# Check if sound exists
	if not sound_streams.has(sound_key):
		print("Sound not found: ", sound_key)
		return
	
	# Create temporary audio player
	var audio_player = AudioStreamPlayer.new()
	audio_player.stream = sound_streams[sound_key]
	
	# Calculate final volume
	var final_volume = linear_to_db(
		master_volume * 
		sound_effects_volume * 
		(1 + volume_adjust)
	)
	audio_player.volume_db = final_volume
	
	# Add to scene and play
	add_child(audio_player)
	audio_player.play()
	
	# Cleanup after playing
	await audio_player.finished
	audio_player.queue_free()

# Convenience methods for specific sounds
func play_card_select_sound():
	play_sound("card_select", -0.2)

func play_card_draw_sound():
	play_sound("card_draw", -0.2)

func play_card_place_sound():
	play_sound("card_place", -0.3)

func play_card_deal_sound():
	play_sound("card_deal", -0.2)

func play_win_sound():
	play_sound("win")

# Optional: Methods to adjust volume
func set_master_volume(value: float):
	master_volume = clamp(value, 0.0, 1.0)

func set_sound_effects_volume(value: float):
	sound_effects_volume = clamp(value, 0.0, 1.0)
