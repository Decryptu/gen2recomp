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
## The corpus is twenty-seven generated walks over the spawn group, one scripted
## errand and one wild battle. The battle route is the seam this tool exists to
## close: a fight is spent from the world's own pump and its buttons arrive
## through the world's own funnel, so the encounter, the enemy's own choices and
## the party that comes out are all functions of the run's seed and its log.
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
## What the battle route asks for instead. A fight costs its intro, an animation
## per hit and the boxes on either side of each, and it has to be walked into
## first; forty seconds is still inside the same clock minute.
const BATTLE_FRAMES: int = 2400
const DIRECTIONS: Array[int] = [
	Gen2Button.UP, Gen2Button.DOWN, Gen2Button.LEFT, Gen2Button.RIGHT
]
## `Gen2WorldSpawn`'s own group, whose map numbering is the same on all three
## cartridges, so one route list sweeps every profile.
const ROUTE_GROUP: int = Gen2WorldSpawn.NEW_BARK_GROUP
const ROUTE_MAPS: int = 8

## Cherrygrove's mart, which is map 1/8 with the clerk on (1,3) and its two door
## cells on (2,7) and (3,7) in all three caches, so one errand route sweeps
## every profile the way the walk routes do.
const MART_MAP: Vector2i = Vector2i(1, 8)
const MART_DOOR: Vector2i = Vector2i(3, 7)
## The counter cell the clerk is talked to across, which is `preview_world_story`'s
## own MART_CLERK_FACE: `CheckFacingObject` reaches two cells over a `$90`.
const MART_COUNTER: Vector2i = Vector2i(3, 3)
## How often the driver presses A inside a battle: the errand's own cadence, which
## is slow enough that a box waiting for a press is not pressed twice.
const BATTLE_PRESS_FRAMES: int = 8

## A won battle writes the slot it was played from, so every run below is pointed
## at a scratch root and the owner's own saves cannot be reached.
const SAVE_ROOT: String = "user://replay_world_slots"

var _failures: int = 0
var _routes: int = 0


func _initialize() -> void:
	_sweep.call_deferred()


func _clear_save_root() -> void:
	if DirAccess.dir_exists_absolute(SAVE_ROOT):
		var directory: DirAccess = DirAccess.open(SAVE_ROOT)
		if directory != null:
			for name: String in directory.get_directories():
				var inner: DirAccess = DirAccess.open("%s/%s" % [SAVE_ROOT, name])
				if inner != null:
					for file: String in inner.get_files():
						DirAccess.remove_absolute("%s/%s/%s" % [SAVE_ROOT, name, file])
				DirAccess.remove_absolute("%s/%s" % [SAVE_ROOT, name])
	DirAccess.make_dir_recursive_absolute(SAVE_ROOT)


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

	Gen2SaveStore.use_root(SAVE_ROOT)
	_clear_save_root()

	for game: StringName in games:
		var data: GameData = GameData.open(game)
		if data == null:
			print("%-8s no imported cache, skipped" % game)
			continue
		for route: Dictionary in _routes_for(data):
			_failures += await _check_route(data, route, frames)

	_clear_save_root()
	Gen2SaveStore.use_root("")
	print("%d routes, %d failures" % [_routes, _failures])
	quit(1 if _failures > 0 else 0)


## Every map in the spawn group the cache ships, entered on a cell the cartridge
## itself warps onto, plus the new game's own spawn and one scripted errand. A
## route list rather than one map, because a walk that never leaves an empty
## bedroom proves the pump on nothing.
func _routes_for(data: GameData) -> Array:
	var out: Array = []
	var battle: Dictionary = _battle_route(data)
	if not battle.is_empty():
		out.append(battle)
	out.append_array([
		{"name": "new_game_spawn", "spawn": true},
		{
			"name": "mart_errand",
			"spawn": true,
			"errand": true,
			"group": MART_MAP.x,
			"number": MART_MAP.y,
			"cell": MART_DOOR,
		},
	])
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


## The first map this cache holds with two adjacent cells a wild roll can fire
## on, walked between. Found rather than named, because a map id is not the same
## number on the three profiles and a grass cell is a `.blk` fact: the story
## walker paid for both lessons already. Iterated in id order, so one cache always
## answers with the same map.
func _battle_route(data: GameData) -> Dictionary:
	for map: Gen2WorldMap in data.world_maps():
		if (data.world_encounter(
			Gen2WorldEncounter.METHOD_GRASS, map.group, map.number
		) as Dictionary).is_empty():
			continue
		var world: Gen2WorldAPI = Gen2WorldAPI.open(data, map.group, map.number, Vector2i.ZERO)
		if world == null:
			continue
		var cells: PackedVector2Array = world.visible_encounter_cells().get(
			Gen2WorldEncounter.METHOD_GRASS, PackedVector2Array()
		)
		var grass: Dictionary = {}
		for raw: Vector2 in cells:
			grass[Vector2i(raw)] = true
		for raw: Vector2 in cells:
			var cell := Vector2i(raw)
			# Up and down rather than any neighbour: the two directions a walk
			# alternates below, so both of its steps land on grass.
			if grass.has(cell + Vector2i(0, 1)):
				return {
					"name": "wild_battle",
					"battle": true,
					"frames": BATTLE_FRAMES,
					"group": map.group,
					"number": map.number,
					"cell": cell,
				}
	return {}


func _check_route(data: GameData, route: Dictionary, requested_frames: int) -> int:
	_routes += 1
	var failures: int = 0
	## A route may ask for more than the sweep's own count, and the battle one
	## does: a fight does not fit in a walk's twenty seconds.
	var frames: int = maxi(requested_frames, int(route.get("frames", 0)))
	var seed_value: int = _route_seed(data, route)
	var errand: bool = bool(route.get("errand", false))
	var battle: bool = bool(route.get("battle", false))
	## A battle route records what a driver decides frame by frame rather than
	## replaying a precomputed program: how long the walk takes to roll an
	## encounter is the seed's business, and a fixed program would either press A
	## at the map or hold a direction inside the move menu.
	var program: Array = [] if battle else _program(seed_value, frames, errand)

	var recorded: Dictionary = await _run(data, route, seed_value, frames, program, true, 0.0, battle)
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
	## And an errand that never reached the till is a walk around a shop: the
	## money is what says the clerk's script ran, the overlay opened and a
	## purchase was committed, which is the whole reason this route is here.
	if errand and int(recorded["money"]) >= int(recorded["initial_money"]):
		_report(data, route, "record", "the mart took no money, so no purchase was replayed")
		return 1
	## And a battle route that never met anything is a walk in the grass: the
	## fought counter is what says the encounter fired, the fight was spent from
	## the world's own pump and the party came back out of it.
	if battle and int(recorded["battles"]) == 0:
		_report(data, route, "record", "no wild battle started, so none was replayed")
		return 1
	## A fight that started and resolved nothing is an encounter box on screen, so
	## it has to have reached an outcome. The party is deliberately not the test:
	## a lost battle blacks out and heals it on the way, which can land back on the
	## numbers it started with. Same reason the errand checks the till.
	if battle and String(recorded["outcome"]).is_empty():
		_report(data, route, "record", "the battle reached no outcome, so it proves nothing")
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
		print("%-8s %-16s %-7s %d frames, %d input entries%s" % [
			data.id, route["name"], label, frames, log.size(),
			", %d battles" % int(run["battles"]) if int(run["battles"]) > 0 else "",
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
	adaptive: bool = false,
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
		## An errand starts from the new game's own snapshot rather than a bare
		## map, because the start money is what a mart spends and only the spawn
		## carries it, and then stands on the errand's map.
		if bool(route.get("errand", false)) and save.world != null:
			save.world.map_id = Vector2i(int(route["group"]), int(route["number"]))
			save.world.player_cell = route["cell"]
			save.world.last_spawn_map = save.world.map_id
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
	var initial_money: int = screen._world.state.money()

	screen.replay_input(log)
	if recording:
		screen.record_input()
	var battles: int = 0
	if adaptive:
		battles = _drive(screen, frames)
	elif host_fps <= 0.0:
		screen.advance_frames(frames)
	elif host_fps <= 0.0:
		screen.advance_frames(frames)
	else:
		var delta: float = 1.0 / host_fps
		var guard: int = frames * 8
		while screen._world.frame_number < frames - 1 and guard > 0:
			screen._process(delta)
			guard -= 1
		screen.advance_frames(frames - screen._world.frame_number)
	if not adaptive:
		battles = screen.battles_fought()

	var state: String = _state(screen, save)
	var world: String = JSON.stringify(screen._world.snapshot().to_dict(), "\t")
	var money: int = screen._world.state.money()
	var outcome: String = String(screen.last_battle_outcome())
	var consumed: Array = screen.input_recording()
	root.remove_child(screen)
	screen.free()
	return {
		"ok": true,
		"battles": battles,
		"state": state,
		"initial": initial,
		"initial_money": initial_money,
		"outcome": outcome,
		"money": money,
		"world": world,
		"log": log if not recording else consumed,
	}


## The compared artefact: the world snapshot the save would carry, the play timer
## beside it, the frame both are read at, and the party.
##
## The party is what a battle changes, the snapshot carrying none of it: HP, level,
## experience, moves and PP are the whole outcome of a fight, so a route that
## fights is only proved replayable by comparing them.
func _state(screen: Gen2WorldScreen, save: Gen2SaveData) -> String:
	return JSON.stringify({
		"frame": screen._world.frame_number,
		"battles": screen.battles_fought(),
		"outcome": String(screen.last_battle_outcome()),
		"game_time": save.game_time.to_dict(),
		"party": _party(screen.active_save()),
		"world": screen._world.snapshot().to_dict(),
	}, "\t")


## Every field of the party a fight can move, and nothing that would differ
## between two runs for another reason.
func _party(save: Gen2SaveData) -> Array:
	var out: Array = []
	if save == null:
		return out
	for raw: Variant in save.party:
		if not raw is Gen2SaveMon:
			continue
		var mon: Gen2SaveMon = raw
		out.append({
			"species": mon.species, "level": mon.level, "hp": mon.hp, "exp": mon.exp,
			"status": mon.status, "item": mon.item,
			"moves": mon.moves.duplicate(), "pp": mon.pp.duplicate(),
			"stat_exp": mon.stat_exp.duplicate(),
		})
	return out


## Drives the run itself instead of replaying a program: hold a direction in the
## grass until something appears, then press A on the mart errand's own cadence,
## which is every button a wild battle asks for (FIGHT, the first move, and the
## boxes on either side of it). Every press goes through the world's own
## `press_button`, so the recording is what a replay is then fed.
func _drive(screen: Gen2WorldScreen, frames: int) -> int:
	var battles: int = 0
	var in_battle: bool = false
	var since_press: int = 0
	var cursor_moved: int = 0
	while screen._world.frame_number < frames:
		if screen.battle_active():
			if not in_battle:
				in_battle = true
				battles += 1
				since_press = 0
			since_press += 1
			if since_press >= BATTLE_PRESS_FRAMES:
				since_press = 0
				## A is every button a wild battle asks for, except the one place
				## it is refused: the list that asks which Pokemon replaces a
				## fainted one opens on the fainted one itself, so the cursor has
				## to move before the choice is taken.
				var picking: bool = screen._battle_host._switch_stage == &"pick"
				screen.press_button(
					Gen2Button.DOWN if picking and cursor_moved % 2 == 0 else Gen2Button.A
				)
				if picking:
					cursor_moved += 1
		else:
			in_battle = false
			## Two cells, alternating, so every step lands on grass and the roll
			## keeps being offered. A step is STEP_FRAMES_WALK long, and a
			## direction held across it is one step.
			@warning_ignore("integer_division")
			var step: int = screen._world.frame_number / Gen2WorldAPI.STEP_FRAMES_WALK
			screen.press_button(
				Gen2Button.DOWN if step % 2 == 0 else Gen2Button.UP
			)
		screen.advance_frame()
	return battles


## The input a run is driven by: a direction held for a while, an occasional A,
## and nothing else the cartridge's own controller does not have. Deterministic
## in the route's seed, so the generated program is itself reproducible.
func _program(seed_value: int, frames: int, errand: bool = false) -> Array:
	if errand:
		return _errand_program(frames)
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


## The scripted errand: walk the door column up to the counter, turn into the
## clerk, and then press A on a cadence for the rest of the run. That one button
## carries the whole leg, because every step of it answers a press: the clerk's
## `pokemart` dialog, the mart overlay's own A, and the boxes on either side.
##
## Held rather than counted out step by step: `move_player` refuses while a step
## is in flight, so a direction held to the counter arrives on the cell whatever
## the walk rate is, and the turn into the counter is a press the wall refuses to
## move on.
func _errand_program(frames: int) -> Array:
	var log: Array = []
	var walk: int = mini(frames, (MART_DOOR.y - MART_COUNTER.y) * Gen2WorldAPI.STEP_FRAMES_WALK)
	for frame: int in range(1, walk + 1):
		log.append({"frame": frame, "kind": "hold", "button": Gen2Button.UP})
	## Clear of the walk rather than up against it: `move_player` refuses a press
	## while the last step is still in flight, and a turn that is refused leaves
	## the player facing the wall behind the counter instead of the clerk.
	if walk + Gen2WorldAPI.STEP_FRAMES_WALK * 3 <= frames:
		log.append({
			"frame": walk + Gen2WorldAPI.STEP_FRAMES_WALK * 3,
			"kind": "press",
			"button": Gen2Button.LEFT,
		})
	var frame: int = walk + Gen2WorldAPI.STEP_FRAMES_WALK * 5
	while frame <= frames:
		log.append({"frame": frame, "kind": "press", "button": Gen2Button.A})
		frame += 8
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
