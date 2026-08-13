extends SceneTree

## Captures the overworld with the on-screen controller shown, in whichever
## orientation the window is given.
##
##   Godot --path . --resolution 480x960 -s res://tools/preview_controls.gd -- <out.png> [mod]
##
## A `mod` argument registers two controls of a mod's own and switches their
## on-screen buttons on, which is what a phone player who wants a mod's camera
## has to be able to reach.
##
## The orientation is the window's, so `--resolution` chooses which arrangement
## is captured: portrait puts the screen at the top and the controller under it,
## landscape centres the screen and leaves the margins for the controller.
##
## The controller is forced on for the capture, since a desktop is not a
## touchscreen and `auto` would correctly hide the thing being photographed. The
## options file is never written, so the developer's own settings are untouched.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _fixture_directory: String = ""
var _frames: int = 0
var _with_mod_buttons: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: preview_controls.gd -- <output.png>")
		quit(1)
		return
	_output_path = args[0]
	_with_mod_buttons = args.size() > 1 and args[1] == "mod"


## Built on the first frame rather than in [method _initialize], because the
## autoloads are added to the tree after the main loop is initialised and the
## controller setting has to be applied through one of them.
func _build() -> void:
	_fixture_directory = Fixture.directory()
	Fixture.build()
	var data: GameData = GameData.open_directory(_fixture_directory)

	var options: Gen2Options = Gen2OptionsStore.current()
	options.touch_mode = Gen2Options.TOUCH_ALWAYS
	if _with_mod_buttons:
		for key: String in ["pitch_up", "pitch_down"]:
			Gen2ModHost.instance().register_action(&"voxel_preview", {
				"key": StringName(key), "label": key.capitalize().replace("_", " "),
			})
		options.touch_layout.mod_buttons_shown = true
	Gen2InputRuntime.instance().apply_options(options)
	Gen2InputRuntime.instance().install_mod_actions()

	# The window is whatever `--resolution` asked for; the interface is drawn at
	# that size rather than stretched from the project's own base resolution.
	var window_size: Vector2i = DisplayServer.window_get_size()
	root.set_content_scale_size(window_size)
	root.size = window_size

	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = Fixture.MAP_GROUP
	_screen.map_number = Fixture.MAP_NUMBER
	_screen.start_cell = Vector2i(7, 6)
	var world := Gen2WorldAPI.open(
		data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6)
	)
	var save := Gen2SaveStore.create_development_save(data, 0)
	save.world = world.snapshot()
	_screen.set_data(data)
	_screen.set_save(save)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_build()
		return false
	if _frames < 18:
		return false
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	RomCache.clear(_fixture_directory)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true
