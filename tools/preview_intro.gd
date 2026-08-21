extends SceneTree

## Captures the new-game opening screens against a real cache.
##
##   Godot --path . -s res://tools/preview_intro.gd -- <game> <out.png> [what] [steps]
##
## `what` is `copyright`, `presents`, `gender`, `clock`, `speech` or `shrink`; `steps` is how many source frames or
## advances to run first, so any beat of `OakSpeech` can be photographed. Several
## comma-separated steps write one file each, suffixed with the step, which is
## how a whole fade is looked at without paying for a process per frame. The
## screens are built directly rather than through `intro_screen.tscn`, which
## reads `GameRuntime` and so cannot compile under `-s`.
##
## Opens a window: rendering needs a display.

## Captured at hardware resolution, so a frame here compares to an emulator
## frame pixel for pixel rather than by eye.
const WINDOW_SIZE := Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
const FRAMES_BEFORE_CAPTURE: int = 6
## The copyright half in front of the GameFreak animation: `DelayFrames 10`, the
## screen for a hundred, and the frame `SplashScreen` clears it on.
const PRESENTS_FIRST_FRAME: int = Gen2BootCinema.COPYRIGHT_PRELUDE_FRAMES \
	+ Gen2BootCinema.COPYRIGHT_HOLD_FRAMES

var _output_path: String = ""
var _what: String = "gender"
var _steps: Array[Vector2i] = [Vector2i.ZERO]
var _at: int = 0
var _screen: Control = null
var _elapsed: int = 0
var _presses_run: int = 0
var _frames_run: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: preview_intro.gd -- <game> <out.png> "
			+ "[copyright|presents|gender|clock|speech|shrink] [step]"
		)
		quit(1)
		return
	var game: StringName = StringName(args[0])
	_output_path = args[1]
	if args.size() > 2:
		_what = args[2]
	if args.size() > 3:
		_steps = []
		for value: String in args[3].split(","):
			# `presses+frames`, so a beat can be reached by button and then
			# stepped a frame at a time through the animation it starts.
			var parts: PackedStringArray = value.split("+")
			_steps.append(Vector2i(
				maxi(int(parts[0]), 0), maxi(int(parts[1]), 0) if parts.size() > 1 else 0
			))

	var directory: String = _find_cache(game)
	if directory.is_empty():
		push_error("No cache for %s. Run tools/import_rom.gd first." % game)
		quit(1)
		return
	var data: GameData = GameData.open_directory(directory)
	if data == null:
		push_error("Could not open the cache for %s." % game)
		quit(1)
		return

	# CONTENT_SCALE_MODE_VIEWPORT makes the root viewport itself 160x144, so the
	# captured texture is the hardware frame rather than a magnified window.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.set_content_scale_size(WINDOW_SIZE)
	_screen = _build(data)
	if _screen == null:
		quit(1)
		return
	# The window is already one hardware screen across, so the sub-screens are
	# added to it directly rather than through [Gen2Screen]'s scaling viewport.
	root.add_child(_screen)
	current_scene = _screen


func _build(data: GameData) -> Control:
	if _what == "copyright" or _what == "presents":
		var splash := Gen2SplashScreen.new()
		if not splash.open(data):
			push_error("This cache carries no copyright screen.")
			splash.free()
			return null
		return splash
	if _what == "gender":
		var gender := Gen2GenderScreen.new()
		if not gender.open(data):
			push_error("This cartridge has no gender screen.")
			gender.free()
			return null
		return gender
	if _what == "clock":
		var clock := Gen2ClockSetScreen.new()
		if not clock.open(data):
			push_error("This cache carries no clock font.")
			clock.free()
			return null
		return clock
	var speech := Gen2OakSpeechScreen.new()
	if not speech.open(data, Gen2SaveData.GENDER_MALE):
		push_error("This cache carries no intro text.")
		speech.free()
		return null
	return speech


## Runs the screen forward to [param step]: `x` A presses, each with the queued
## `DelayFrames` run spent in front of it, then `y` raw source frames. On the
## gender screen `x` is cursor moves instead; in `speech` mode it is frames, so
## the opening fades can be stepped through without a press.
func _drive(step: Vector2i) -> void:
	if _what == "copyright" or _what == "presents":
		# `SplashScreen` reads no button over the copyright, so both halves of a
		# step are frames: the screen appears on the tenth and is cleared a
		# hundred later, and the GameFreak animation runs straight on from there.
		# `presents` counts from the frame that animation starts on.
		var splash: Gen2SplashScreen = _screen as Gen2SplashScreen
		var offset: int = PRESENTS_FIRST_FRAME if _what == "presents" else 0
		while _frames_run < offset + step.x + step.y:
			splash.advance_frames(1)
			_frames_run += 1
		return
	if _what == "gender":
		for _press: int in step.x - _presses_run:
			_screen.handle_button(Gen2Button.DOWN)
		_presses_run = step.x
		return
	if _what == "clock":
		# `x` is A presses and `y` raw frames after them, so a fade or a
		# `DelayFrames` run can be photographed partway as well as settled.
		var clock: Gen2ClockSetScreen = _screen as Gen2ClockSetScreen
		while _presses_run < step.x:
			_settle_frames(clock)
			clock.handle_button(Gen2Button.A)
			_presses_run += 1
			_frames_run = 0
		clock.advance_frames(maxi(step.y - _frames_run, 0))
		_frames_run = maxi(step.y, _frames_run)
		return
	var speech: Gen2OakSpeechScreen = _screen as Gen2OakSpeechScreen
	if _what == "speech":
		while _frames_run < step.x:
			speech.advance_frames(1)
			_frames_run += 1
		return
	while _presses_run < step.x:
		_settle_frames(speech)
		speech.handle_button(Gen2Button.A)
		_presses_run += 1
		_frames_run = 0
	# Both halves of a step are absolute, so steps given in order photograph a
	# run of frames rather than compounding.
	speech.advance_frames(maxi(step.y - _frames_run, 0))
	_frames_run = maxi(step.y, _frames_run)


## Spends whatever `DelayFrames` run or printing text a screen is standing in.
func _settle_frames(screen: Node) -> void:
	for _pass: int in 40:
		var owed: int = int(screen.call(&"animation_frames_left"))
		if owed == 0:
			return
		screen.call(&"advance_frames", owed)


## One capture per step, each after a fresh pair of rendered frames so the
## textures written this step have reached the window.
func _process(_delta: float) -> bool:
	_elapsed += 1
	# Frames are spent by `steps`, not by the clock, so a given frame of a fade
	# comes out the same on every run. It has to be turned off from inside the
	# tree: a node with `_process` has it enabled again when it is added.
	_screen.set_process(false)
	if _elapsed < FRAMES_BEFORE_CAPTURE:
		return false
	if _at >= _steps.size():
		quit(0)
		return true
	if _elapsed == FRAMES_BEFORE_CAPTURE:
		_drive(_steps[_at])
		return false
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var path: String = _output_path
	if _steps.size() > 1:
		path = "%s_%d_%d.%s" % [
			_output_path.get_basename(), _steps[_at].x, _steps[_at].y,
			_output_path.get_extension(),
		]
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	_at += 1
	_elapsed = FRAMES_BEFORE_CAPTURE - 1
	return false


func _find_cache(game: StringName) -> String:
	var sha1: String = RomRegistry.sha1_for(game)
	if sha1.is_empty():
		return ""
	var directory: String = RomCache.directory_for(game, sha1)
	return directory if RomCache.is_usable(directory) else ""
