extends SceneTree

## Captures the credits against a real imported cache, one source frame at a
## time.
##
##   Godot --headless --path . -s res://tools/preview_credits.gd -- crystal /tmp/c.png [frame] [live]
##
## [frame] is how many source frames to spend before the shot. A `CREDITS_WAIT`
## tick is thirteen frames, so the batches land a long way apart; several frames
## separated by `;` write one file each, numbered. A frame suffixed `b` holds B
## down for it, which is the skip a replay allows.
##
## `live` drives the production world screen's own overlay instead of the page
## directly, which is what says `open_credits` reaches it. One frame only, since
## the screen owns its own clock.
##
## Headless either way: the page draws into an [Image] rather than through a
## viewport, so no window and no settle are needed.

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _frames: int = 0
var _spent: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: preview_credits.gd -- <game> <output.png> [frame;frame;...] [live]")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var held: bool = false
	var frames: Array = []
	for step: String in (args[2] if args.size() > 2 else "0").split(";", false):
		var text: String = step.strip_edges()
		if text.ends_with("b"):
			held = true
			text = text.substr(0, text.length() - 1)
		frames.append(maxi(int(text), 0))
	frames.sort()

	_output_path = args[1]
	if args.size() > 3 and args[3] == "live":
		_spent = int(frames[frames.size() - 1])
		_open_world(data)
		return

	var page: Gen2CreditsPage = Gen2CreditsPage.from_data(data)
	var credits: Gen2Credits = Gen2Credits.create(data, true)
	if page == null or not page.ready() or credits == null:
		push_error("The %s cache holds no credits." % args[0])
		quit(1)
		return

	var buttons: Array = [Gen2Button.B] if held else []
	var spent: int = 0
	for wanted: int in frames:
		while spent < wanted:
			credits.advance_frame(buttons)
			spent += 1
		var path: String = args[1]
		if frames.size() > 1:
			path = "%s-%d.%s" % [args[1].get_basename(), wanted, args[1].get_extension()]
		if not _write(page.image(data, credits.frame_state()), path):
			return
		print("frame %d, scene %d, block %d, scroll %d, pos %d, timer %d%s" % [
			wanted, credits.scene(), credits.banner_block(), credits.scroll(),
			credits.position(), credits.timer(), ", finished" if credits.finished() else "",
		])
	quit(0)


## The live path: a real world screen at the new game's own spawn, with
## `open_credits` doing what `Script_credits` does to it.
func _open_world(data: GameData) -> void:
	var spawn: Gen2WorldSnapshot = Gen2WorldSpawn.new_game_snapshot(data)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if spawn == null or save == null:
		push_error("Missing new-game spawn or development save")
		quit(1)
		return
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = spawn.map_id.x
	_screen.map_number = spawn.map_id.y
	_screen.start_cell = spawn.player_cell
	save.world = spawn
	_screen.set_data(data)
	_screen.set_save(save)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	if _screen == null:
		return true
	_frames += 1
	if _frames < 2:
		return false
	_screen.open_credits()
	var host: Gen2CreditsScreen = _screen._credits_host
	if host == null:
		push_error("open_credits() reached no overlay")
		quit(1)
		return true
	host.advance_frames(_spent)
	if not _write(host.render(), _output_path):
		return true
	print("live frame %d, %s" % [
		_spent, "finished" if host.credits().finished() else "running",
	])
	## `quit` from inside `_process` would leave the screen standing, so its own
	## teardown never runs.
	current_scene = null
	root.remove_child(_screen)
	_screen.free()
	_screen = null
	quit(0)
	return true


func _write(image: Image, path: String) -> bool:
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [path, error])
		quit(1)
		return false
	print("Wrote %s" % path)
	return true
