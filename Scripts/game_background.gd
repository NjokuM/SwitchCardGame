extends Control

@onready var table_panel = $TablePanel
@onready var table_outer_panel = $TableOuterPanel

# Minimum table size constants (to prevent the table from getting too small)
const MIN_TABLE_SIZE = 500  # Minimum diameter for the table in pixels
const MIN_SCREEN_SIZE = 800  # Reference screen size for minimum scaling

# Called when the node enters the scene tree for the first time
func _ready():
	# Connect to window resize signals to maintain position
	get_tree().root.size_changed.connect(resize_table)
	
	# Initial positioning
	resize_table()

# Resize the table when window size changes with better adaptability
func resize_table():
	var screen_size = get_viewport_rect().size
	
	# Calculate the available space, accounting for both dimensions
	var min_dimension = min(screen_size.x, screen_size.y)
	
	# Calculate the ideal table size as a percentage of the screen
	var table_size_percent = 0.7  # 80% of the available space
	
	# Adapt percentage based on screen size to handle small screens better
	if min_dimension < MIN_SCREEN_SIZE:
		# Gradually reduce the percentage as the screen gets smaller
		var scale_factor = min_dimension / float(MIN_SCREEN_SIZE)
		# Apply a minimum of 60% and maximum of 80%
		table_size_percent = max(0.6, min(0.8, table_size_percent * scale_factor))
	
	# Calculate final table size with a minimum bound
	var table_size = max(MIN_TABLE_SIZE, min_dimension * table_size_percent)
	
	# Update table size to maintain circular shape
	table_panel.size = Vector2(table_size, table_size)
	table_panel.position = Vector2(
		screen_size.x / 2 - table_size / 2,
		screen_size.y / 2 - table_size / 2
	)
	
	# Update outer table size
	var outer_size = table_size * 1.1  # Make it slightly larger
	table_outer_panel.size = Vector2(outer_size, outer_size)
	table_outer_panel.position = Vector2(
		screen_size.x / 2 - outer_size / 2,
		screen_size.y / 2 - outer_size / 2
	)
	
	# Print debug info
	print("Screen size: ", screen_size, " Table size: ", table_size)
