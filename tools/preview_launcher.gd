extends SceneTree

## Photographs the launcher in one appearance, at one window size, with a
## chosen set of cartridges present.
##
##   Godot --path . -s res://tools/preview_launcher.gd -- \
##       <out.png> [light|dark] [width] [height] [page] [empty|mixed|full] [view] [mod id]
##
## `view` is the mods page's own: `list`, `sources`, or `mod` with an id.
##
## The state argument uses the preview seams on the launcher, so an empty shelf
## can be photographed on a machine that has every cache imported. Like
## `tools/screenshot.gd` this opens a real window and cannot run headless.

const STATES: Dictionary = {
	"empty": {"gold": false, "silver": false, "crystal": false},
	"mixed": {"gold": true, "silver": false, "crystal": false},
	"full": {"gold": true, "silver": true, "crystal": true},
}

var _output: String = ""
var _frames: int = 0
var _launcher: Control = null
var _mode: String = "light"
var _page: String = "shelf"
var _state: String = "full"
var _view: String = ""
var _mod: String = ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: -s tools/preview_launcher.gd -- <out.png> [theme] [w] [h] [page] [state]")
		quit(1)
		return
	_output = args[0]
	var mode: String = args[1] if args.size() > 1 else "light"
	var width: int = int(args[2]) if args.size() > 2 else 1280
	var height: int = int(args[3]) if args.size() > 3 else 800
	var page: String = args[4] if args.size() > 4 else "shelf"
	var state: String = args[5] if args.size() > 5 else "full"
	_view = args[6] if args.size() > 6 else ""
	_mod = args[7] if args.size() > 7 else ""

	# Both, because the window already exists by the time a tool script runs and
	# only the display server moves it.
	DisplayServer.window_set_size(Vector2i(width, height))
	root.set_content_scale_size(Vector2i(width, height))
	root.size = Vector2i(width, height)

	_mode = mode
	_page = page
	_state = state
	var packed: PackedScene = load("res://game/main/main.tscn")
	_launcher = packed.instantiate()
	root.add_child(_launcher)


func _process(_delta: float) -> bool:
	_frames += 1
	# A node added during _initialize is not ready until the first frame, so the
	# seams are driven here rather than beside the instantiation.
	if _frames == 1:
		_launcher.preview_theme(StringName(_mode))
		if STATES.has(_state):
			_launcher.preview_slot_states(STATES[_state])
		_launcher.select_page(StringName(_page))
		if not _view.is_empty():
			_launcher.preview_mods_view(StringName(_view), StringName(_mod))
	if _frames < 26:
		return false
	var image: Image = root.get_texture().get_image()
	if image.save_png(_output) != OK:
		push_error("Could not write %s" % _output)
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output, image.get_width(), image.get_height()])
	quit()
	return true
