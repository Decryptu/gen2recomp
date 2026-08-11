extends SceneTree

## Captures Oak's speech against a real imported cache: the real trainer-class
## pic, the real Wooper front pic, the real font and the real text-box frame.
##
##   Godot --path . -s res://tools/preview_oak_speech.gd -- crystal /tmp/oak.png [advance|choices|player]
##
## [advance] is how many A presses to make before the capture, so 0 is the first
## page of `_OakText1` and enough of them reaches the naming screen.

const WINDOW_SIZE := Vector2i(1152, 648)
const SETTLE_FRAMES: int = 8

var _screen: Gen2OakSpeechScreen = null
var _output_path: String = ""
var _frames: int = 0
var _target: String = "0"
var _prepared: bool = false


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

	_target = args[2] if args.size() > 2 else "0"


func _prepare_target() -> void:
	if _target in ["choices", "player"]:
		for _step: int in 200:
			if _screen.choosing_name():
				break
			_screen.handle_button(Gen2Button.A)
		if _target == "player" and _screen.choosing_name():
			_screen.handle_button(Gen2Button.DOWN)
			_screen.handle_button(Gen2Button.A)
	else:
		for _step: int in int(_target):
			_screen.handle_button(Gen2Button.A)


func _process(_delta: float) -> bool:
	if not _prepared:
		_prepared = true
		_prepare_target()
		_frames = 0
		return false
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var texture: ViewportTexture = root.get_texture()
	if texture == null:
		push_error("The active renderer cannot capture the Oak speech viewport.")
		quit(1)
		return true
	var image: Image = texture.get_image()
	if image == null:
		push_error("The Oak speech viewport returned no image.")
		quit(1)
		return true
	if image.save_png(_output_path) != OK:
		push_error("Could not write %s" % _output_path)
		quit(1)
		return true
	print("Wrote %s, beat %d of %d, naming %s, choices %s" % [
		_output_path, _screen.beat_index() + 1, _screen.beat_count(), _screen.naming(),
		_screen.choosing_name(),
	])
	quit(0)
	return true
