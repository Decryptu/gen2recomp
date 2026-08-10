extends SceneTree

## Captures the naming screen against a real imported cache, which is what makes
## it worth looking at: the keyboard, the border, the two entry markers and the
## cursor bracket are all cartridge graphics rather than stand-ins.
##
##   Godot --path . -s res://tools/preview_naming_screen.gd -- crystal /tmp/name.png [presses]
##
## [presses] is a button script driving the screen before the capture: `r`, `l`,
## `u`, `d` for the d-pad, `a`, `b`, `s` for START and `c` for SELECT. So
## `aaardc` types three letters, steps right and down and flips the case.

const WINDOW_SIZE := Vector2i(1152, 648)
const SETTLE_FRAMES: int = 8

const BUTTONS: Dictionary = {
	"u": Gen2Button.UP,
	"d": Gen2Button.DOWN,
	"l": Gen2Button.LEFT,
	"r": Gen2Button.RIGHT,
	"a": Gen2Button.A,
	"b": Gen2Button.B,
	"s": Gen2Button.START,
	"c": Gen2Button.SELECT,
}

var _screen: Gen2NamingScreenScreen = null
var _output_path: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: preview_naming_screen.gd -- <game> <output.png> [presses]")
		quit(1)
		return
	_output_path = args[1]

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	_screen = Gen2NamingScreenScreen.new()
	if not _screen.open(data, "YOUR NAME?"):
		push_error("The %s cache carries no naming screen data." % args[0])
		quit(1)
		return
	_screen.scale = Vector2(4, 4)
	root.add_child(_screen)
	current_scene = _screen

	var presses: String = args[2] if args.size() > 2 else ""
	for key: String in presses:
		if BUTTONS.has(key):
			_screen.handle_button(int(BUTTONS[key]))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	if image.save_png(_output_path) != OK:
		push_error("Could not write %s" % _output_path)
		quit(1)
		return true
	print("Wrote %s (%dx%d), entry \"%s\"" % [
		_output_path, image.get_width(), image.get_height(), _screen.model().stored_name(),
	])
	quit(0)
	return true
