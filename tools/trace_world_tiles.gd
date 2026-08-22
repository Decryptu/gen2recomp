extends SceneTree

## Every hardware frame of a map's tileset animation: which of the tileset's
## tiles `_AnimateTileset` rewrote, where the command list stands, and what the
## two palette commands are holding.
##
##   Godot --headless --path . -s res://tools/trace_world_tiles.gd -- \
##       <game> <group> <map> <frames> <out.txt> [time_of_day]
##
## The port half of `.claude/oracle/overworld/trace_tiles.py`, which prints the
## same artefact off a real cartridge by reading vTiles2 once a frame. The line
## is `frame anim_frame timer water cave tiles`, and `anim_frame` is read after
## the frame is spent, which is where `hTileAnimFrame` stands on that side.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("usage: <game> <group> <map> <frames> <out.txt> [time_of_day]")
		quit(2)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("no imported cache for %s" % args[0])
		quit(2)
		return
	var frames: int = maxi(1, int(args[3]))

	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	var screen: Gen2WorldScreen = packed.instantiate() as Gen2WorldScreen
	screen.set_data(data)
	screen.map_group = int(args[1])
	screen.map_number = int(args[2])
	if args.size() > 5:
		screen.time_of_day = int(args[5])
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(screen)
	await process_frame
	if screen._world == null:
		push_error("the world did not open")
		quit(2)
		return
	screen.set_process(false)

	var animation: Gen2WorldAnimation = screen._animation
	var lines: PackedStringArray = PackedStringArray([
		"# frame anim_frame timer water cave tiles"
	])
	for frame: int in frames:
		screen.advance_frame()
		var changed: PackedInt32Array = animation.changed_tiles()
		var names: PackedStringArray = PackedStringArray()
		for tile: int in changed:
			names.append("%02X" % tile)
		lines.append("%d %d %d %d %d %s" % [
			frame, animation.command_index(), animation.timer(),
			animation.water_palette_color(), animation.cave_palette_color(),
			",".join(names) if names.size() > 0 else "-",
		])
	FileAccess.open(args[4], FileAccess.WRITE).store_string("\n".join(lines) + "\n")
	print("wrote %d frames to %s" % [frames, args[4]])
	root.remove_child(screen)
	screen.free()
	quit(0)
