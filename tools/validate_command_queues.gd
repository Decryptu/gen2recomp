extends SceneTree

## Verifies the imported `cmdqueue` payloads against freshly imported real
## caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## macros/scripts/maps.asm's `cmdqueue` and `stonetable`, engine/overworld/
## cmd_queue.asm's CmdQueue_StoneTable, home/stone_queue.asm's HandleStoneQueue,
## and the two maps that write one, maps/BlackthornGym2F.asm and
## maps/IcePathB1F.asm. Both files are byte identical between the pins.
##
## The importer skips a queue pointer it cannot resolve, because scripts are
## collected as fixed slices and a slice running past its own end can decode
## stray bytes as a `writecmdqueue`. This is what makes that tolerance safe: it
## asserts the two real tables are present, complete and correct rather than
## trusting the scan not to have missed one.
##
##   Godot --headless --path . -s res://tools/validate_command_queues.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## Blackthorn Gym 2F and Ice Path B1F, the only two maps in either game with a
## MAPCALLBACK_CMDQUEUE (`data/maps/maps.asm` group/number pairs). The gym sits
## at the same pair in both games; Crystal's own extra maps push Ice Path B1F
## eight places down its group.
const BLACKTHORN_GYM_2F: Array = [5, 2]
const ICE_PATH_B1F: Dictionary = {
	&"gold": [3, 54],
	&"silver": [3, 54],
	&"crystal": [3, 62],
}

## The `stonetable` rows verbatim, warp id then object id. Object ids are
## `object_const_def` constants, which start at 2: Blackthorn Gym 2F lists two
## trainers before its boulders, so its first boulder is 4, while Ice Path B1F
## lists boulders first, so its first is 2.
const EXPECTED_ROWS: Dictionary = {
	"blackthorn": [[5, 4], [3, 5], [4, 6]],
	"ice_path": [[3, 2], [4, 3], [5, 4], [6, 5]],
}

## The pit warps each row names, as the cell the boulder has to reach. Read off
## the two maps' own `def_warp_events`, one-based like the source counts them.
const EXPECTED_WARP_CELLS: Dictionary = {
	"blackthorn": {3: Vector2i(2, 5), 4: Vector2i(8, 7), 5: Vector2i(8, 3)},
	"ice_path": {
		3: Vector2i(11, 2), 4: Vector2i(4, 7), 5: Vector2i(5, 12), 6: Vector2i(12, 13),
	},
}

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_map(data, game_id, "blackthorn", BLACKTHORN_GYM_2F)
		_verify_map(data, game_id, "ice_path", ICE_PATH_B1F[game_id])
		_drive_blackthorn(data, game_id)
	_finish()


func _verify_map(data: GameData, game_id: StringName, name: String, id: Array) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, id[0], id[1], Vector2i.ZERO)
	if world == null:
		_fail("%s: map %d/%d is missing." % [game_id, id[0], id[1]])
		return

	# The queue is written by a MAPCALLBACK_CMDQUEUE, so running the map's own
	# callbacks is what puts it on the world. Nothing else writes one.
	var _entry: Array = world.dispatch_map_entry()
	for _step: int in 8:
		if not world.pending_script_wait().is_empty():
			world.finish_script_waits()
			continue
		if world.pending_script_input().is_empty():
			break
		world.run_event_queue(true)

	var queues: Array = world.command_queues()
	var tables: Array = []
	for queue: Dictionary in queues:
		if int(queue.get("type", 0)) == Gen2WorldScript.CMDQUEUE_STONETABLE:
			tables.append(queue)
	if not _check(
		tables.size() == 1,
		"%s %s: %d stone tables written, not 1." % [game_id, name, tables.size()]
	):
		return

	var rows: Array = (tables[0] as Dictionary).get("rows", [])
	var expected: Array = EXPECTED_ROWS[name]
	if not _check(
		rows.size() == expected.size(),
		"%s %s: %d stonetable rows, not the pinned %d." % [
			game_id, name, rows.size(), expected.size(),
		]
	):
		return
	for index: int in expected.size():
		var row: Dictionary = rows[index]
		var want: Array = expected[index]
		_check(
			int(row["warp"]) == int(want[0]) and int(row["object"]) == int(want[1]),
			"%s %s row %d is warp %d object %d, not the pinned warp %d object %d." % [
				game_id, name, index,
				int(row["warp"]), int(row["object"]), int(want[0]), int(want[1]),
			]
		)
		_check(
			int(row["script"]) >= RomFile.BANK_SIZE,
			"%s %s row %d has script $%04X, which is not a banked address." % [
				game_id, name, index, int(row["script"]),
			]
		)

	# Every named warp has to be a real warp event on a pit tile, or the boulder
	# could never satisfy HandleStoneQueue.
	var cells: Dictionary = EXPECTED_WARP_CELLS[name]
	for warp: int in cells:
		var cell: Vector2i = cells[warp]
		_check(
			world.warp_index_at(cell) == warp,
			"%s %s: warp %d is not at %s." % [game_id, name, warp, cell]
		)
		_check(
			Gen2WorldCollision.is_pit_tile(world.collision_code_at(cell)),
			"%s %s: warp %d at %s is collision $%02X, not a pit." % [
				game_id, name, warp, cell, world.collision_code_at(cell),
			]
		)

	# And every row has to name a boulder object the map actually carries.
	for row: Dictionary in rows:
		var index: int = int(row["object"]) - 2
		if not _check(
			index >= 0 and index < world.objects.size(),
			"%s %s: object id %d is outside the map's object list." % [
				game_id, name, int(row["object"]),
			]
		):
			continue
		var object: Gen2WorldObject = world.objects[index]
		_check(
			object.is_strength_boulder(),
			"%s %s: object id %d is not a Strength boulder." % [game_id, name, int(row["object"])]
		)
	print("%s %s: %d stonetable rows over %d pit warps verified." % [
		game_id, name, rows.size(), cells.size(),
	])


## Blackthorn Gym 2F's first row, driven against the real cache: BOULDER1 stands
## at (8,2) and warp 5 is the pit directly below it, so one push south is the
## whole puzzle step. The flag it sets is what BlackthornGym1FBouldersCallback
## reads to changeblock the floor below.
func _drive_blackthorn(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, BLACKTHORN_GYM_2F[0], BLACKTHORN_GYM_2F[1], Vector2i(8, 1)
	)
	if world == null:
		_fail("%s: Blackthorn Gym 2F is missing." % game_id)
		return
	world.state.set_engine_flag(Gen2WorldState.strength_active_flag(
		Gen2WorldState.is_crystal_profile(data)
	))
	var _entry: Array = world.dispatch_map_entry()

	var boulder: Gen2WorldObject = world.object_at(Vector2i(8, 2))
	if not _check(
		boulder != null and boulder.is_strength_boulder(),
		"%s: no boulder at (8,2) on Blackthorn Gym 2F." % game_id
	):
		return
	var flag: int = boulder.event_flag
	_check(
		not world.state.is_event_flag_active(flag),
		"%s: boulder flag %d is already set before the push." % [game_id, flag]
	)

	var pushed: Dictionary = world.move_result(Vector2i.DOWN)
	if not _check(
		pushed.has("boulder_pushed"),
		"%s: the boulder at (8,2) did not move: %s" % [game_id, pushed.get("reason", "")]
	):
		return
	if not _check(
		pushed["boulder_pushed"].has("fall_script"),
		"%s: the boulder reached the pit warp without firing its stone table." % game_id
	):
		return

	var results: Array = world.run_event_queue(false)
	for _step: int in 16:
		if not world.pending_script_wait().is_empty():
			results = world.finish_script_waits()
			continue
		if world.pending_script_input().is_empty():
			break
		results = world.run_event_queue(true)
	var status: StringName = StringName(
		(results[results.size() - 1] as Dictionary).get("status", &"")
	) if not results.is_empty() else &""
	_check(
		status == &"complete",
		"%s: the fall script ended as %s, not complete." % [game_id, status]
	)
	_check(
		world.state.is_event_flag_active(flag),
		"%s: the fall script did not set boulder flag %d." % [game_id, flag]
	)
	print("%s blackthorn: the real push fired its stone table and set flag %d." % [
		game_id, flag,
	])


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS command queues: both stone tables and their pit warps verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL command queues: %d problems." % _failures.size())
	quit(1)
