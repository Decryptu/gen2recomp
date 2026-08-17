extends RefCounted

## Long source-script movements whose leader and player-follower paths cross
## several turns. Each row is driven from the imported map event, one hardware
## frame at a time, on every cartridge profile.
##
##   Godot --headless --path . -s res://tools/validate.gd -- scripted_scenes

const CHERRYGROVE_CITY := Vector2i(26, 3)
const ROUTE_29 := Vector2i(24, 3)
const GUIDE_START := Vector2i(33, 6)
const GUIDE_OBJECT: int = 0
const DUDE_OBJECT: int = 0
const ROUTE_TRIGGERS: Array[Vector2i] = [Vector2i(53, 8), Vector2i(53, 9)]

const GUIDE_WAYPOINTS: Array[Vector2i] = [
	Vector2i(29, 5), Vector2i(23, 5), Vector2i(16, 5),
	Vector2i(10, 7), Vector2i(25, 11), Vector2i(25, 9),
]
const GUIDE_FOLLOWER_WAYPOINTS: Array[Vector2i] = [
	Vector2i(30, 5), Vector2i(24, 5), Vector2i(17, 5),
	Vector2i(10, 6), Vector2i(24, 11), Vector2i(24, 11),
]
const GUIDE_MOVEMENT_FRAMES: Array[int] = [32, 48, 56, 64, 152, 16]
const DUDE_MOVEMENT_FRAMES: Array[Array] = [[48, 48], [40, 40]]

var _r: RefCounted = null


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_check_guide(game_id, data)
		for trigger_index: int in ROUTE_TRIGGERS.size():
			_check_tutorial(game_id, data, trigger_index)


func _check_guide(game_id: StringName, data: GameData) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, CHERRYGROVE_CITY.x, CHERRYGROVE_CITY.y, GUIDE_START
	)
	if not _r.check(world != null, "%s: Cherrygrove City did not open." % game_id):
		return
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	var run_result: Dictionary = _drain(world, world.interact(), GUIDE_OBJECT)
	if not _r.check(bool(run_result.get("ok", false)), "%s: Guide Gent: %s" % [
		game_id, String(run_result.get("reason", "did not finish")),
	]):
		return
	var movements: Array = run_result.get("movements", [])
	_r.check(movements.size() == GUIDE_WAYPOINTS.size(),
		"%s: Guide Gent ran %d movement streams, expected %d." % [
			game_id, movements.size(), GUIDE_WAYPOINTS.size(),
		])
	for index: int in mini(movements.size(), GUIDE_WAYPOINTS.size()):
		var row: Dictionary = movements[index]
		_r.check(int(row.get("frames", -1)) == GUIDE_MOVEMENT_FRAMES[index],
			"%s: Guide Gent movement %d spent %d frames, expected %d." % [
				game_id, index + 1, int(row.get("frames", -1)), GUIDE_MOVEMENT_FRAMES[index],
			])
		_r.check(row.get("leader", Vector2i(-1, -1)) == GUIDE_WAYPOINTS[index],
			"%s: Guide Gent movement %d ended at %s, expected %s." % [
				game_id, index + 1, row.get("leader"), GUIDE_WAYPOINTS[index],
			])
		_r.check(row.get("player", Vector2i(-1, -1)) == GUIDE_FOLLOWER_WAYPOINTS[index],
			"%s: Guide Gent movement %d left the player at %s, expected %s." % [
				game_id, index + 1, row.get("player"), GUIDE_FOLLOWER_WAYPOINTS[index],
			])
	_r.check(not (world.objects[GUIDE_OBJECT] as Gen2WorldObject).active,
		"%s: Guide Gent did not disappear at his door." % game_id)
	print("%s: Guide Gent %d movement frames" % [game_id, int(run_result.get("movement_frames", 0))])


func _check_tutorial(game_id: StringName, data: GameData, trigger_index: int) -> void:
	var trigger: Vector2i = ROUTE_TRIGGERS[trigger_index]
	var state := Gen2WorldState.new({}, {
		Gen2WorldState.map_scene_key(ROUTE_29.x, ROUTE_29.y): 1,
	})
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ROUTE_29.x, ROUTE_29.y, trigger, state
	)
	if not _r.check(world != null, "%s: Route 29 did not open." % game_id):
		return
	var run_result: Dictionary = _drain(
		world, world.dispatch_script_events(trigger), DUDE_OBJECT
	)
	var label := "Route 29 row %d" % trigger.y
	if not _r.check(bool(run_result.get("ok", false)), "%s: %s: %s" % [
		game_id, label, String(run_result.get("reason", "did not finish")),
	]):
		return
	var movements: Array = run_result.get("movements", [])
	_r.check(movements.size() == 2, "%s: %s ran %d movement streams, expected 2." % [
		game_id, label, movements.size(),
	])
	for index: int in mini(movements.size(), 2):
		_r.check(int((movements[index] as Dictionary).get("frames", -1))
			== int(DUDE_MOVEMENT_FRAMES[trigger_index][index]),
			"%s: %s movement %d spent %d frames, expected %d." % [
				game_id, label, index + 1,
				int((movements[index] as Dictionary).get("frames", -1)),
				int(DUDE_MOVEMENT_FRAMES[trigger_index][index]),
			])
	if movements.size() == 2:
		_r.check((movements[0] as Dictionary).get("leader") == Vector2i(52, trigger.y),
			"%s: %s did not reach the player before the question." % [game_id, label])
		_r.check((movements[1] as Dictionary).get("leader") == Vector2i(50, 12),
			"%s: %s did not return the DUDE to his standing cell." % [game_id, label])
		_r.check((movements[1] as Dictionary).get("player") == Vector2i(50, 11),
			"%s: %s did not leave the player one cell behind the DUDE." % [game_id, label])
	_r.check(int(run_result.get("tutorials", 0)) == 1,
		"%s: %s requested %d catching tutorials, expected 1." % [
			game_id, label, int(run_result.get("tutorials", 0)),
		])
	print("%s: %s %d movement frames" % [
		game_id, label, int(run_result.get("movement_frames", 0)),
	])


func _drain(world: Gen2WorldAPI, initial: Array, tracked_object: int) -> Dictionary:
	if initial.is_empty():
		return {"ok": false, "reason": "no script event was dispatched"}
	var movements: Array = []
	var movement_frames: int = 0
	var tutorials: int = 0
	var results: Array = initial
	for _step: int in 512:
		var wait: Dictionary = world.pending_script_wait()
		if not wait.is_empty():
			var movement: bool = StringName(wait.get("wait", &"")) \
				== Gen2WorldScriptRunner.WAIT_MOVEMENT
			var wait_kind: StringName = StringName(wait.get("wait", &""))
			var frames: int = 0
			while not world.pending_script_wait().is_empty() and frames < 2048:
				results = world.advance_script_presentation_frame()
				frames += 1
				if StringName(world.pending_script_wait().get("wait", &"")) != wait_kind:
					break
			if frames >= 2048 \
				and StringName(world.pending_script_wait().get("wait", &"")) == wait_kind:
				return {"ok": false, "reason": "a script wait exceeded 2048 frames"}
			if movement:
				movement_frames += frames
				movements.append({
					"frames": frames,
					"leader": (world.objects[tracked_object] as Gen2WorldObject).cell,
					"player": world.player_cell,
				})
			continue

		var input: Dictionary = world.pending_script_input()
		var input_type: StringName = StringName(input.get("type", &""))
		if input_type in [&"text", &"button"]:
			results = world.run_event_queue(true)
			continue
		if input_type in [&"choice", &"menu"]:
			results = world.choose_script_input(0)
			continue

		var request: Dictionary = world.pending_runtime_request()
		if not request.is_empty():
			var kind: StringName = StringName(request.get("kind", &""))
			if kind == &"catch_tutorial_requested":
				tutorials += 1
				results = world.complete_runtime_request({
					"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_CAUGHT,
				})
			elif kind == &"audio_requested":
				results = world.complete_runtime_request({"ok": true})
			else:
				return {"ok": false, "reason": "unsupported request %s" % kind}
			continue

		if not world.script_busy():
			return {
				"ok": true,
				"movements": movements,
				"movement_frames": movement_frames,
				"tutorials": tutorials,
			}
		if results.is_empty():
			results = world.run_event_queue(false)
	return {"ok": false, "reason": "script did not terminate in 512 transitions"}
