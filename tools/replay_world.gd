extends SceneTree

## Records `(frame, button)` from a run of the real world screen and replays it
## into a fresh world, then diffs the two worlds.
##
##   Godot --headless --path . -s res://tools/replay_world.gd -- [game ...] [frames]
##
## A seed, an input log and a frame number should reproduce a world exactly.
## That is what `Gen2WorldScreen.advance_frame()` is for, and this is the
## artefact it is proved by: the compared value is `Gen2WorldSnapshot` JSON plus
## the play timer, which either matches byte for byte or does not.
##
## Four runs per route, all from the same seed and the same log:
##
## | Run | Driven by | Proves |
## |---|---|---|
## | record | `advance_frames`, a generated input program | the log the world consumed |
## | replay | `advance_frames`, the recorded log | a log alone reproduces the run |
## | 30 fps | `_process(1/30)`, the recorded log | the pump, not the host, spends frames |
## | 144 fps | `_process(1/144)` , the recorded log | the same, from the other side |
##
## The two `_process` runs top up the last frame or two with `advance_frame()`,
## because a host slower than the hardware cannot land on every frame; the run is
## otherwise entirely theirs. They also feed `Gen2WorldClock` real seconds, which
## is deliberate (`Gen2WorldScreen._advance_day_cycle`), so a route stays under a
## cartridge minute and the day cycle cannot move under one run and not another.

const GAMES: Array[StringName] = [&"gold", &"silver", &"crystal"]
## Twenty seconds of hardware frames: long enough for several walks, a script
## and a wild roll, short enough that no run crosses a clock minute.
const DEFAULT_FRAMES: int = 1200
const DIRECTIONS: Array[int] = [
	Gen2Button.UP, Gen2Button.DOWN, Gen2Button.LEFT, Gen2Button.RIGHT
]
## `Gen2WorldSpawn`'s own group, whose map numbering is the same on all three
## cartridges, so one route list sweeps every profile.
const ROUTE_GROUP: int = Gen2WorldSpawn.NEW_BARK_GROUP
const ROUTE_MAPS: int = 8

var _failures: int = 0
var _routes: int = 0


func _initialize() -> void:
	_sweep.call_deferred()


## The screen's own nodes do not resolve until the tree has run a frame, so every
## run waits for one before touching the world it opened.
func _sweep() -> void:
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var games: Array[StringName] = []
	var frames: int = DEFAULT_FRAMES
	for argument: String in args:
		if argument.is_valid_int():
			frames = maxi(1, int(argument))
		else:
			games.append(StringName(argument))
	if games.is_empty():
		games = GAMES

	for game: StringName in games:
		var data: GameData = GameData.open(game)
		if data == null:
			print("%-8s no imported cache, skipped" % game)
			continue
		for route: Dictionary in _routes_for(data):
			_failures += await _check_route(data, route, frames)

	print("%d routes, %d failures" % [_routes, _failures])
	quit(1 if _failures > 0 else 0)


## Every map in the spawn group the cache ships, entered on a cell the cartridge
## itself warps onto, plus the new game's own spawn. A route list rather than one
## map, because a walk that never leaves an empty bedroom proves the pump on
## nothing.
func _routes_for(data: GameData) -> Array:
	var out: Array = [{"name": "new_game_spawn", "spawn": true}]
	for number: int in range(1, ROUTE_MAPS + 1):
		var map: Gen2WorldMap = data.world_map(ROUTE_GROUP, number)
		if map == null:
			continue
		var warps: Array = map.events.get("warps", [])
		if warps.is_empty():
			continue
		var first: Dictionary = warps[0]
		out.append({
			"name": "map_%d_%d" % [ROUTE_GROUP, number],
			"group": ROUTE_GROUP,
			"number": number,
			"cell": Vector2i(int(first.get("x", 0)), int(first.get("y", 0))),
		})
	return out


func _check_route(data: GameData, route: Dictionary, frames: int) -> int:
	_routes += 1
	var failures: int = 0
	var seed_value: int = _route_seed(data, route)
	var program: Array = _program(seed_value, frames)

	var recorded: Dictionary = await _run(data, route, seed_value, frames, program, true)
	if not bool(recorded.get("ok", false)):
		_report(data, route, "open", String(recorded.get("reason", "unavailable")))
		return 1
	var log: Array = recorded["log"]
	var expected: String = recorded["state"]
	## A route the input never moved would pass every comparison below on a world
	## that did nothing, which is the same trap `_drain_story`'s require_events
	## closes in the story walker.
	if String(recorded["world"]) == String(recorded["initial"]):
		_report(data, route, "record", "the run moved no world state, so it proves nothing")
		return 1

	for label: String in ["replay", "30fps", "144fps"]:
		var host_fps: float = 0.0
		if label == "30fps":
			host_fps = 30.0
		elif label == "144fps":
			host_fps = 144.0
		var run: Dictionary = await _run(data, route, seed_value, frames, log, false, host_fps)
		if not bool(run.get("ok", false)):
			_report(data, route, label, String(run.get("reason", "unavailable")))
			failures += 1
			continue
		if String(run["state"]) != expected:
			_report(data, route, label, _first_difference(expected, String(run["state"])))
			failures += 1
			continue
		if label == "replay" and JSON.stringify(run["log"]) != JSON.stringify(log):
			_report(data, route, label, "the replay consumed a different log")
			failures += 1
			continue
		print("%-8s %-16s %-7s %d frames, %d input entries" % [
			data.id, route["name"], label, frames, log.size()
		])
	return failures


## One run of the real screen. [param host_fps] of zero spends the frames
## directly; anything else pumps them through `_process` at that rate, which is
## the whole point of the comparison.
func _run(
	data: GameData,
	route: Dictionary,
	seed_value: int,
	frames: int,
	log: Array,
	recording: bool,
	host_fps: float = 0.0,
) -> Dictionary:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	var screen: Gen2WorldScreen = packed.instantiate() as Gen2WorldScreen
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save == null:
		screen.free()
		return {"ok": false, "reason": "no development save"}
	save.run_seed = seed_value
	if bool(route.get("spawn", false)):
		save.world = Gen2WorldSpawn.new_game_snapshot(data)
	else:
		screen.map_group = int(route["group"])
		screen.map_number = int(route["number"])
		screen.start_cell = route["cell"]
		save.world = null
	screen.set_data(data)
	screen.set_save(save)
	## The host's frames belong to the host: every frame below is spent by this
	## tool, so the screen never runs one of its own.
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(screen)
	await process_frame
	if screen._world == null:
		var why: String = "%s / %s" % [screen._caption.text, screen._hint.text]
		root.remove_child(screen)
		screen.free()
		return {"ok": false, "reason": why}
	screen.set_process(false)

	var initial: String = JSON.stringify(screen._world.snapshot().to_dict(), "\t")
	screen.replay_input(log)
	if recording:
		screen.record_input()
	if host_fps <= 0.0:
		screen.advance_frames(frames)
	else:
		var delta: float = 1.0 / host_fps
		var guard: int = frames * 8
		while screen._world.frame_number < frames - 1 and guard > 0:
			screen._process(delta)
			guard -= 1
		screen.advance_frames(frames - screen._world.frame_number)

	var state: String = _state(screen, save)
	var world: String = JSON.stringify(screen._world.snapshot().to_dict(), "\t")
	var consumed: Array = screen.input_recording()
	root.remove_child(screen)
	screen.free()
	return {
		"ok": true,
		"state": state,
		"initial": initial,
		"world": world,
		"log": log if not recording else consumed,
	}


## The compared artefact: the world snapshot the save would carry, the play timer
## beside it and the frame both are read at.
func _state(screen: Gen2WorldScreen, save: Gen2SaveData) -> String:
	return JSON.stringify({
		"frame": screen._world.frame_number,
		"game_time": save.game_time.to_dict(),
		"world": screen._world.snapshot().to_dict(),
	}, "\t")


## The input a run is driven by: a direction held for a while, an occasional A,
## and nothing else the cartridge's own controller does not have. Deterministic
## in the route's seed, so the generated program is itself reproducible.
func _program(seed_value: int, frames: int) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var log: Array = []
	var frame: int = 1
	while frame <= frames:
		if random.randi_range(0, 9) == 0:
			log.append({"frame": frame, "kind": "press", "button": Gen2Button.A})
			frame += random.randi_range(2, 8)
			continue
		var direction: int = DIRECTIONS[random.randi_range(0, DIRECTIONS.size() - 1)]
		for _held: int in random.randi_range(4, 40):
			if frame > frames:
				break
			log.append({"frame": frame, "kind": "hold", "button": direction})
			frame += 1
	return log


## `String.hash()` moves by one between two names that differ in their last
## character, so it is mixed before the low bit is set: without that, every
## second route on a cartridge draws the seed of the one before it.
func _route_seed(data: GameData, route: Dictionary) -> int:
	var mixed: int = ("%s/%s" % [data.id, route["name"]]).hash() * 2654435761
	return (mixed & 0x7FFFFFFF) | 1


func _first_difference(expected: String, actual: String) -> String:
	var left: PackedStringArray = expected.split("\n")
	var right: PackedStringArray = actual.split("\n")
	for line: int in maxi(left.size(), right.size()):
		var a: String = left[line] if line < left.size() else "<end>"
		var b: String = right[line] if line < right.size() else "<end>"
		if a != b:
			return "line %d: %s != %s" % [line + 1, a.strip_edges(), b.strip_edges()]
	return "the two states differ in length only"


func _report(data: GameData, route: Dictionary, label: String, reason: String) -> void:
	printerr("%-8s %-16s %-7s FAILED %s" % [data.id, route["name"], label, reason])
