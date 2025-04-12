extends Control

@onready var table_panel = $TablePanel
@onready var table_outer_panel = $TableOuterPanel

# Called when the node enters the scene tree for the first time
func _ready():
	# Connect to window resize signals to maintain position
	get_tree().root.size_changed.connect(resize_table)
	
	# Initial positioning
	resize_table()

# Resize the table when window size changes
func resize_table():
	var screen_size = get_viewport_rect().size
	var min_dimension = min(screen_size.x, screen_size.y) * 0.8
	
	# Update table size to maintain circular shape
	table_panel.size = Vector2(min_dimension, min_dimension)
	table_panel.position = Vector2(
		screen_size.x / 2 - min_dimension / 2,
		screen_size.y / 2 - min_dimension / 2
	)
	
	# Update outer table size
	var outer_size = min_dimension * 1.1  # Make it slightly larger
	table_outer_panel.size = Vector2(outer_size, outer_size)
	table_outer_panel.position = Vector2(
		screen_size.x / 2 - outer_size / 2,
		screen_size.y / 2 - outer_size / 2
	)
