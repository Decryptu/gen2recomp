extends SceneTree

## Captures Oak's speech against a real imported cache: the real trainer-class
## pic, the real Wooper front pic, the real font and the real text-box frame.
##
##   Godot --path . -s res://tools/preview_oak_speech.gd -- crystal /tmp/oak.png [advance]
##
## [advance] is how many A presses to make before the capture, so 0 is the first
## page of `_OakText1` and enough of them reaches the naming screen.

const WINDOW_SIZE := Vector2i(1152, 648)
const SETTLE_FRAMES: int = 8

var _screen: Gen2OakSpeechScreen = null
var _output_path: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: preview_oak_speech.gd -- <game> <output.png> [advance]")
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
	_screen = Gen2OakSpeechScreen.new()
	if not _screen.open(data, Gen2SaveData.GENDER_MALE):
		push_error("The %s cache carries no intro text." % args[0])
		quit(1)
		return
	_screen.scale = Vector2(4, 4)
	root.add_child(_screen)
	current_scene = _screen

	for _step: int in (int(args[2]) if args.size() > 2 else 0):
		_screen.handle_button(Gen2Button.A)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	if image.save_png(_output_path) != OK:
		push_error("Could not write %s" % _output_path)
		quit(1)
		return true
	print("Wrote %s, beat %d of %d, naming %s" % [
		_output_path, _screen.beat_index() + 1, _screen.beat_count(), _screen.naming(),
	])
	quit(0)
	return true
