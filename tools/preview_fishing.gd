extends SceneTree

## Captures the production fishing cast screen with the integration cache.
## This keeps the visual smoke check deterministic when no user cartridge is
## imported in the local Godot profile.
##
##   Godot --path . -s res://tools/preview_fishing.gd -- /tmp/fishing.png

const WINDOW_SIZE := Vector2i(1152, 648)
const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: preview_fishing.gd -- <output.png>")
		quit(1)
		return
	_output_path = args[0]
	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var data: GameData = Fixture.build()
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = Fixture.MAP_GROUP
	_screen.map_number = Fixture.MAP_NUMBER
	_screen.start_cell = Vector2i(4, 5)
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_screen.preview_fishing()
	if _frames < 18:
		return false
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	RomCache.clear(Fixture.directory())
	quit(0)
	return true
