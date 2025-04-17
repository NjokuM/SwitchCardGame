extends Control

# References to UI elements
@onready var sound_slider = $CenterPanel/VBoxContainer/SoundEffectsContainer/SoundEffectsSlider
@onready var music_slider = $CenterPanel/VBoxContainer/MusicContainer/MusicSlider
@onready var back_button = $CenterPanel/VBoxContainer/BackButton

# Store the scene we should return to after closing the settings
var return_scene: String = ""

func _ready():
	# If no return scene is set, default to main menu
	if return_scene == "":
		return_scene = "res://scene/main_menu.tscn"
		
	# Connect signals
	sound_slider.value_changed.connect(_on_sound_effects_value_changed)
	music_slider.value_changed.connect(_on_music_value_changed)
	back_button.pressed.connect(_on_back_button_pressed)
	
	# Set initial slider values based on current volume settings
	sound_slider.value = SoundManager.sound_effects_volume
	music_slider.value = MusicManager.music_volume

# Called when the Sound Effects slider value changes
func _on_sound_effects_value_changed(value):
	SoundManager.set_sound_effects_volume(value)
	# Play a sound to demonstrate new volume
	SoundManager.play_card_select_sound()

# Called when the Music slider value changes
func _on_music_value_changed(value):
	MusicManager.set_music_volume(value)

# Called when the back button is pressed
func _on_back_button_pressed():
	SoundManager.play_card_select_sound()
	get_tree().change_scene_to_file(return_scene)

# Call this to set where we should return after closing the settings
func set_return_scene(scene_path: String):
	return_scene = scene_path
