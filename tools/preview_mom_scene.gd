extends SceneTree

## Traces `MeetMomRightScript` through the world screen, frame by frame.
##
##   Godot --headless --path . -s res://tools/preview_mom_scene.gd -- <game> [png] [frame]
##
## The story walker already proves the script's own results on [Gen2WorldAPI];
## what it cannot say is whether the presentation runs. This drives the real
## screen at the source frame rate from the cell the coord event sits on and
## reports, per frame: the script's state, the object `applymovement` is walking,
## and whether the text box is up. A `png` argument writes a frame, the last one
## traced unless a `frame` number names an earlier one, so the emote, the walk
## and the box can each be looked at.
##
## `maps/PlayersHouse1F.asm`: the two coord events at (8,4) and (9,4) are
## Crystal's trigger. Gold and Silver ship none; their scene 0 is an `sdefer` of
## the same script, so the trace there starts from the map entry instead.

const WINDOW_SIZE := Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
const FRAME: float = 1.0 / 59.7275
## Long enough for the walk, the emote's fifteen frames and the text to appear.
const TRACE_FRAMES: int = 600

## `constants/map_constants.asm`, and `Gen2WorldSpawn`'s own group.
const PLAYERS_HOUSE_1F: int = 6
## `MomWalksToPlayerMovement` starts here, and the player is met at (9,4).
const MOM_OBJECT: int = 0
const APPROACH_CELL := Vector2i(9, 3)
const TRIGGER_CELL := Vector2i(9, 4)

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _capture_frame: int = TRACE_FRAMES
var _frames: int = 0
var _started: bool = false
var _trace: Array[Dictionary] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: preview_mom_scene.gd -- <game> [out.png] [frame]")
		quit(1)
		return
	var game: StringName = StringName(args[0])
	if args.size() > 1:
		_output_path = args[1]
	if args.size() > 2:
		_capture_frame = maxi(1, int(args[2]))

	var sha1: String = RomRegistry.sha1_for(game)
	var directory: String = RomCache.directory_for(game, sha1) if not sha1.is_empty() else ""
	if directory.is_empty() or not RomCache.is_usable(directory):
		push_error("No cache for %s. Run tools/import_rom.gd first." % game)
		quit(1)
		return
	var data: GameData = GameData.open_directory(directory)

	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.set_content_scale_size(WINDOW_SIZE)

	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = Gen2WorldSpawn.NEW_BARK_GROUP
	_screen.map_number = PLAYERS_HOUSE_1F
	_screen.start_cell = APPROACH_CELL
	var world := Gen2WorldAPI.open(
		data, Gen2WorldSpawn.NEW_BARK_GROUP, PLAYERS_HOUSE_1F, APPROACH_CELL
	)
	var save := Gen2SaveStore.create_development_save(data, 0)
	save.world = world.snapshot()
	_screen.set_data(data)
	_screen.set_save(save)
	root.add_child(_screen)
	current_scene = _screen


## One row per source frame, so a gap in the presentation is a run of frames
## with nothing happening rather than a missing event.
func _sample() -> Dictionary:
	var world: Gen2WorldAPI = _screen._world
	var mom: Gen2WorldObject = null
	for object: Gen2WorldObject in world.visible_objects():
		if object.index == MOM_OBJECT:
			mom = object
	return {
		"frame": _frames,
		"script_busy": world.script_busy(),
		"waiting_input": world.script_input_waiting(),
		"player": world.player_cell,
		"mom": mom.cell if mom != null else Vector2i(-1, -1),
		"mom_offset": mom.step_offset_cells() if mom != null else Vector2.ZERO,
		"emote": mom != null and mom.emote_visible,
		"text": _screen._text_box != null and _screen._text_box.visible,
	}


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		# The development caption and hint are drawn over a 160x144 window, so a
		# capture of the game itself loses them. Done from here because the
		# screen's own nodes are not resolved until it has run a frame.
		for label: StringName in [&"Caption", &"Hint"]:
			var node: CanvasItem = _screen.get_node_or_null(NodePath(label)) as CanvasItem
			if node != null:
				node.visible = false
		return false
	# The clock is the trace's, not the renderer's, so the report is the same on
	# every run.
	_screen.set_process(false)
	if not _started:
		_started = true
		_screen.move_player(Vector2i(0, 1))
	_screen._process(FRAME)
	_trace.append(_sample())
	if _frames == _capture_frame and not _output_path.is_empty():
		root.get_texture().get_image().save_png(_output_path)
		print("Wrote %s at frame %d" % [_output_path, _frames])
	if _frames < maxi(TRACE_FRAMES, _capture_frame):
		return false
	_report()
	quit(0)
	return true


## Prints only where something changed, which is what makes a stall readable.
func _report() -> void:
	var last: Dictionary = {}
	var changes: int = 0
	for row: Dictionary in _trace:
		var without: Dictionary = row.duplicate()
		without.erase("frame")
		if without == last:
			continue
		last = without
		changes += 1
		print("f%4d  script %s  input %s  player %s  mom %s%s%s  text %s" % [
			row["frame"],
			"busy" if row["script_busy"] else "idle",
			"wait" if row["waiting_input"] else "-   ",
			row["player"], row["mom"],
			" stepping" if row["mom_offset"] != Vector2.ZERO else "",
			" emote" if row["emote"] else "",
			"up" if row["text"] else "-",
		])
	print("%d frames, %d changes" % [_trace.size(), changes])
