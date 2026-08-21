extends SceneTree

## Every hardware frame of a walk on the real world screen: where the map is
## scrolled to, where the player is drawn, and which of `Facings` is up.
##
##   Godot --headless --path . -s res://tools/trace_world_walk.gd -- \
##       <game> <group> <map> <x> <y> <direction> <frames> <out.txt>
##
## The port half of `.claude/oracle/overworld/trace_walk.py`, which prints the
## same artefact off a real cartridge. The line is
## `frame cam_x cam_y x y screen_x screen_y facing walk_frame`, where `cam_x`
## and `cam_y` are hSCX/hSCY in map pixels rather than modulo the BG map and
## `screen_x`/`screen_y` are `sprite_x - scx` on that side: the camera lags the
## player by one pass (`ScrollScreen` runs after `NextOverworldFrame`), so a
## walking player is drawn two pixels ahead of its resting cell and the pair is
## what says so.
##
## Ten standing frames come first, the way the cartridge trace opens, so a diff
## aligns on the frame the direction starts being held rather than on the file.

const STANDING_FRAMES: int = 10


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 8:
		push_error("usage: <game> <group> <map> <x> <y> <direction> <frames> <out.txt>")
		quit(2)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("no imported cache for %s" % args[0])
		quit(2)
		return
	var direction: int = _button_for(args[5])
	if direction == Gen2Button.NONE:
		push_error("direction is one of up, down, left, right")
		quit(2)
		return
	var frames: int = maxi(1, int(args[6]))

	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	var screen: Gen2WorldScreen = packed.instantiate() as Gen2WorldScreen
	screen.set_data(data)
	screen.map_group = int(args[1])
	screen.map_number = int(args[2])
	screen.start_cell = Vector2i(int(args[3]), int(args[4]))
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(screen)
	await process_frame
	if screen._world == null:
		push_error("the world did not open: %s" % screen._caption.text)
		quit(2)
		return
	screen.set_process(false)

	## Held from the eleventh frame on, which is where the cartridge trace
	## presses, and released once the run has spent its frames.
	var log: Array = []
	for frame: int in range(STANDING_FRAMES, frames):
		log.append({"frame": frame, "kind": "hold", "button": direction})
	screen.replay_input(log)

	var lines: PackedStringArray = PackedStringArray([
		"# frame cam_x cam_y x y screen_x screen_y facing walk_frame"
	])
	for frame: int in frames:
		screen.advance_frame()
		lines.append(_sample(screen._world, frame))
	var out: String = args[7]
	FileAccess.open(out, FileAccess.WRITE).store_string("\n".join(lines) + "\n")
	print("wrote %d frames to %s" % [frames, out])
	root.remove_child(screen)
	screen.free()
	quit(0)


## Read after the frame is spent, which is where the emulator samples: a line is
## the state the frame it names left behind.
func _sample(world: Gen2WorldAPI, frame: int) -> String:
	var camera: Vector2 = world.visible_origin_cells() * float(Gen2WorldAPI.CELL_PIXELS)
	var screen_pixel: Vector2i = world.player_pixel_position()
	return "%d %d %d %d %d %d %d %d %d" % [
		frame, roundi(camera.x), roundi(camera.y),
		world.player_cell.x, world.player_cell.y,
		screen_pixel.x, screen_pixel.y,
		world.player_facing, world.player_walk_frame(),
	]


func _button_for(name: String) -> int:
	match name.to_lower():
		"up": return Gen2Button.UP
		"down": return Gen2Button.DOWN
		"left": return Gen2Button.LEFT
		"right": return Gen2Button.RIGHT
	return Gen2Button.NONE
