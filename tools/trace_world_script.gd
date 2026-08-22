extends SceneTree

## Every script command a walked conversation runs on the real world screen, in
## the order it ran and with the `bank:address` the cartridge would hold in
## wScriptBank:wScriptPos for it.
##
##   Godot --headless --path . -s res://tools/trace_world_script.gd -- \
##       <game> <group> <map> <x> <y> <dir:count,...> <frames> <out.txt>
##
## The port half of `.claude/oracle/overworld/trace_script.py`, which prints the
## same artefact off a real cartridge. The line is `frame bank:addr opcode name`,
## so the two command orders diff directly and a branch taken on the wrong side
## of a flag shows up as the first differing address rather than as a wrong box
## on a screenshot.
##
## The walk list is the steps taken before A is pressed, so a run reaches the
## object it is about to talk to. A count of zero is a turn on the spot, which
## is what a press into the object being talked to does. A is then pressed every
## fourteenth frame, the cadence the cartridge trace mashes at, until the one
## conversation it started has ended.

## The cartridge trace's own pace: slow enough that a box waiting for a press is
## not pressed twice.
const PRESS_EVERY: int = 14
## A scratch root, so a run cannot reach the owner's own saves: the world is
## given a save because half the script commands read one, VAR_BOXSPACE and
## VAR_PARTYCOUNT among them, and a world with none fails the command rather
## than inventing an empty party.
const SAVE_ROOT: String = "user://trace_world_script_slots"
## Frames with no script running before a run is called finished.
const IDLE_FRAMES: int = 90


## The runner being drained, held across the frame it finishes on.
var _runner: Gen2WorldScriptRunner = null
var _seen: int = 0
## Set once a conversation has run and ended. One talk is the artefact, and a
## press into the object it was with starts the same one over.
var _finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 8:
		push_error("usage: <game> <group> <map> <x> <y> <dir:count,...> <frames> <out.txt>")
		quit(2)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("no imported cache for %s" % args[0])
		quit(2)
		return

	DirAccess.make_dir_recursive_absolute(SAVE_ROOT)
	Gen2SaveStore.use_root(SAVE_ROOT)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save == null:
		push_error("no development save")
		quit(2)
		return
	save.world = null
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	var screen: Gen2WorldScreen = packed.instantiate() as Gen2WorldScreen
	screen.set_data(data)
	screen.set_save(save)
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

	Gen2WorldScriptRunner.trace_commands = true
	var lines: PackedStringArray = PackedStringArray(["# frame bank:addr opcode name"])
	var frame: int = 0

	for step: String in args[5].split(",", false):
		var parts: PackedStringArray = step.split(":")
		var button: int = _button_for(parts[0])
		if button == Gen2Button.NONE:
			push_error("a walk step is <up|down|left|right>:<count>")
			quit(2)
			return
		var cells: int = int(parts[1]) if parts.size() > 1 else 1
		if cells == 0:
			var turns: int = 0
			while turns < 16 and screen._world.player_facing != _facing_for(button):
				screen.press_button(button)
				screen.advance_frame()
				_collect(screen, lines, frame)
				frame += 1
				turns += 1
			continue
		for cell: int in cells:
			var before: Vector2i = screen._world.player_cell
			var spent: int = 0
			while spent < 48 and screen._world.player_cell == before:
				screen.press_button(button)
				screen.advance_frame()
				_collect(screen, lines, frame)
				frame += 1
				spent += 1
			## The step is still being drawn when the cell commits, and a button
			## that arrives inside one is refused, so the next step or the turn
			## after it would be dropped.
			while screen._world.player_step_in_progress():
				screen.advance_frame()
				_collect(screen, lines, frame)
				frame += 1

	print("talking from %s facing %d" % [screen._world.player_cell, screen._world.player_facing])
	var idle: int = 0
	var limit: int = maxi(1, int(args[6]))
	while frame < limit:
		if frame % PRESS_EVERY == 0:
			screen.press_button(Gen2Button.A)
		screen.advance_frame()
		_collect(screen, lines, frame)
		frame += 1
		if _finished:
			break
		if screen._world._active_script == null:
			idle += 1
			if idle > IDLE_FRAMES:
				break
		else:
			idle = 0

	Gen2WorldScriptRunner.trace_commands = false
	FileAccess.open(args[7], FileAccess.WRITE).store_string("\n".join(lines) + "\n")
	print("wrote %d commands to %s" % [lines.size() - 1, args[7]])
	root.remove_child(screen)
	screen.free()
	quit(0)


## Drains whatever the runner has executed since the last frame, and drains a
## runner that finished inside the frame before letting go of it: the commands
## after the last wait all run on one frame, and a sample that only ever looks
## at the live runner loses every one of them.
func _collect(screen: Gen2WorldScreen, lines: PackedStringArray, frame: int) -> void:
	var runner: Gen2WorldScriptRunner = screen._world._active_script
	if runner != _runner:
		_drain(lines, frame)
		if _runner != null:
			_finished = true
			return
		_runner = runner
		_seen = 0
	_drain(lines, frame)


func _drain(lines: PackedStringArray, frame: int) -> void:
	if _runner == null:
		return
	var trace: Array[Dictionary] = _runner.command_trace
	for index: int in range(_seen, trace.size()):
		var command: Dictionary = trace[index]
		lines.append("%d %02x:%04x %02x %s" % [
			frame, int(command["bank"]), int(command["address"]),
			int(command["opcode"]), String(command["name"]),
		])
	_seen = trace.size()


## The facing a held direction settles on, which is what says a turn on the spot
## has been taken.
func _facing_for(button: int) -> int:
	match button:
		Gen2Button.UP: return Gen2WorldSprite.FACING_UP
		Gen2Button.DOWN: return Gen2WorldSprite.FACING_DOWN
		Gen2Button.LEFT: return Gen2WorldSprite.FACING_LEFT
		Gen2Button.RIGHT: return Gen2WorldSprite.FACING_RIGHT
	return Gen2WorldSprite.FACING_DOWN


func _button_for(name: String) -> int:
	match name.to_lower():
		"up": return Gen2Button.UP
		"down": return Gen2Button.DOWN
		"left": return Gen2Button.LEFT
		"right": return Gen2Button.RIGHT
	return Gen2Button.NONE
