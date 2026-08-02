extends SceneTree

## Renders a scene and writes it to a PNG, so UI work can be checked without a
## human having to press Play and describe what they see.
##
##   Godot --path . -s res://tools/screenshot.gd -- <scene> <output.png> [frames] [method] [times]
##
## The optional method/times pair calls a no-argument method on the scene root
## before capturing, which is how you photograph a screen mid-interaction
## rather than only on its first frame.
##
## Note this opens a real window for a moment: rendering needs a display, so it
## cannot run under --headless.

const DEFAULT_FRAMES: int = 12
const WINDOW_SIZE := Vector2i(1152, 648)

var _output_path: String = ""
var _frames_to_wait: int = DEFAULT_FRAMES
var _elapsed_frames: int = 0
var _failed: bool = false
var _call_method: String = ""
var _call_times: int = 0
var _call_arg: int = -1
var _called: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -s tools/screenshot.gd -- <scene> <output.png> [frames]")
		_failed = true
		quit(1)
		return

	var scene_path: String = args[0]
	_output_path = args[1]
	if args.size() >= 3:
		_frames_to_wait = maxi(1, int(args[2]))

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Could not load scene: %s" % scene_path)
		_failed = true
		quit(1)
		return

	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	current_scene = instance

	if args.size() >= 5:
		_call_method = args[3]
		_call_times = int(args[4])
		# Handlers usually take an index (which ability, which slot), so allow
		# one optional integer argument.
		_call_arg = int(args[5]) if args.size() >= 6 else -1


## Waits a few frames before capturing so containers have laid out and any
## first-frame tween has settled.
func _process(_delta: float) -> bool:
	if _failed:
		return true
	_elapsed_frames += 1

	# Driven on a live frame, not during setup: the scene's _ready() has to
	# have run before its handlers will do anything.
	if not _called and _elapsed_frames >= 2 and not _call_method.is_empty():
		_called = true
		var target: Node = _find_handler(current_scene, _call_method)
		if target == null:
			push_error("No node under the scene has method %s" % _call_method)
			quit(1)
			return true
		for i: int in range(_call_times):
			if _call_arg >= 0:
				target.call(_call_method, _call_arg)
			else:
				target.call(_call_method)

	if _elapsed_frames < _frames_to_wait:
		return false

	var image: Image = root.get_texture().get_image()
	var error: int = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true


## Breadth-first search for whichever node actually implements the handler, so
## a screen that embeds another screen can still be driven by method name.
func _find_handler(from: Node, method: String) -> Node:
	var queue: Array[Node] = [from]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node.has_method(method):
			return node
		for child: Node in node.get_children():
			queue.append(child)
	return null
