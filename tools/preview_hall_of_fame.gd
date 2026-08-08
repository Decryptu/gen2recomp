extends SceneTree

## Captures the production Hall of Fame overlay against a real imported cache,
## which is what makes it worth looking at: the panel draws a real front pic,
## the real font and the real text-box frame.
##
##   Godot --path . -s res://tools/preview_hall_of_fame.gd -- crystal /tmp/hof.png [page]
##
## [page] is how many times to advance before the capture, so 0 is the first
## party member and the last page is the player's own.

const WINDOW_SIZE := Vector2i(1152, 648)
## Enough frames for the scene to lay out and the overlay to draw once.
const SETTLE_FRAMES: int = 18

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _advance: int = 0
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: preview_hall_of_fame.gd -- <game> <output.png> [page]")
		quit(1)
		return
	_output_path = args[1]
	_advance = int(args[2]) if args.size() > 2 else 0

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var spawn: Gen2WorldSnapshot = Gen2WorldSpawn.new_game_snapshot(data)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if spawn == null or save == null:
		push_error("Missing new-game spawn or development save")
		quit(1)
		return

	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = spawn.map_id.x
	_screen.map_number = spawn.map_id.y
	_screen.start_cell = spawn.player_cell
	save.world = spawn
	_screen.set_data(data)
	_screen.set_save(save)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_screen.open_hall_of_fame()
		for _step: int in _advance:
			if _screen._hall_of_fame_host != null:
				_screen._hall_of_fame_host.advance()
	if _frames < SETTLE_FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true
