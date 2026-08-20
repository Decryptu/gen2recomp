extends SceneTree

## Photographs the launcher in one appearance, at one window size, with a
## chosen set of cartridges present.
##
##   Godot --path . -s res://tools/preview_launcher.gd -- \
##       <out.png> [light|dark] [width] [height] [page] [empty|mixed|full] [view] [mod id] \
##       [scroll] [focus index] [fade step]
##
## `view` opens a sheet (`manage`, `touch`, `binding`, `bugs`, `delete_mod`) or
## picks the mods page's own: `list`, `sources`, or `mod` with an id.
## `fade` is which step of the screen transition to photograph, 0 for none and 1
## to 4 for one of `FadeOutToWhite`'s own rows: the launcher's leave-the-screen
## sheet is stepped rather than tweened, so a still is the only way to see that
## it is discrete. See [method Gen2LauncherShell.flash].
##
## `scroll` is how far down the page's own scroll to photograph, in pixels, for a
## card that does not fit the window. `focus` puts the keyboard on the nth
## focusable control in tree order, which is the only way to photograph a focus
## ring: nothing takes focus until the player presses something.
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
var _scroll: int = 0
var _focus: int = -1
var _fade: int = 0


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
	_scroll = int(args[8]) if args.size() > 8 else 0
	_focus = int(args[9]) if args.size() > 9 else -1
	_fade = int(args[10]) if args.size() > 10 else 0

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
		if _view in ["manage", "touch", "binding", "delete_mod", "bugs"]:
			_launcher.preview_sheet(StringName(_view))
		elif not _view.is_empty():
			_launcher.preview_mods_view(StringName(_view), StringName(_mod))
	# After the seams, so the page being photographed is the one that scrolls, and
	# every frame, since a rebuilt page starts at the top again.
	if _scroll > 0:
		var scroll: ScrollContainer = _first_scroll(_launcher)
		if scroll != null:
			scroll.scroll_vertical = _scroll
	# Late enough that the page it lands on is the one being photographed, and the
	# guard has finished moving focus about after the page change.
	if _frames == 20 and _focus >= 0:
		var reachable: Array[Control] = []
		_focusable(_launcher, reachable)
		if _focus < reachable.size():
			reachable[_focus].grab_focus()
		else:
			push_error("Only %d focusable controls" % reachable.size())
	# After the page and the focus, so the sheet lies over the screen the fade is
	# actually leaving.
	if _frames == 24 and _fade > 0:
		_launcher.preview_fade_step(_fade)
	if _frames < 26:
		return false
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	if image.save_png(_output) != OK:
		push_error("Could not write %s" % _output)
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output, image.get_width(), image.get_height()])
	quit()
	return true


func _focusable(node: Node, into: Array[Control]) -> void:
	var control := node as Control
	if control != null and control.is_visible_in_tree() \
			and control.focus_mode == Control.FOCUS_ALL:
		into.append(control)
	for child: Node in node.get_children():
		_focusable(child, into)


func _first_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer and node.is_visible_in_tree():
		return node
	for child: Node in node.get_children():
		var found: ScrollContainer = _first_scroll(child)
		if found != null:
			return found
	return null
