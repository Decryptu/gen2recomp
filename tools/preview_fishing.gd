extends SceneTree

## Captures the production fishing cast screen.
##
## With only an output path it uses the deterministic integration fixture:
##
##   Godot --path . -s res://tools/preview_fishing.gd -- /tmp/fishing.png
##
## Pass a real imported cache and map to capture authentic map art instead:
##
##   Godot --path . -s res://tools/preview_fishing.gd -- /tmp/fishing.png silver 2 5
##

const WINDOW_SIZE := Vector2i(1152, 648)
const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _screen: Gen2WorldScreen = null
var _data: GameData = null
var _output_path: String = ""
var _fixture_directory: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: preview_fishing.gd -- <output.png> [game group map]")
		quit(1)
		return
	_output_path = args[0]
	if args.size() >= 4:
		_data = GameData.open(StringName(args[1]))
		if _data == null:
			push_error("No imported cache for %s." % args[1])
			quit(1)
			return
	else:
		_fixture_directory = Fixture.directory()
		_data = Fixture.build()
	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	if args.size() >= 4:
		_screen.map_group = int(args[2])
		_screen.map_number = int(args[3])
	else:
		_screen.map_group = Fixture.MAP_GROUP
		_screen.map_number = Fixture.MAP_NUMBER
	_screen.start_cell = Vector2i.ZERO
	_screen.set_data(_data)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_screen.preview_fishing()
	if _frames < 18:
		return false
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	if not _fixture_directory.is_empty():
		RomCache.clear(_fixture_directory)
	quit(0)
	return true
