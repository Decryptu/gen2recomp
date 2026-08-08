extends SceneTree

## Verifies the corridor from the Indigo Plateau Pokemon Center to the Hall of
## Fame, against freshly imported real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `maps/IndigoPlateauPokecenter1F.asm`, `maps/WillsRoom.asm`,
## `maps/KogasRoom.asm`, `maps/BrunosRoom.asm`, `maps/KarensRoom.asm`,
## `maps/LancesRoom.asm` and `maps/HallOfFame.asm`. The Pokemon Center and the
## Hall of Fame are byte identical between the pins and the four rooms differ
## only in their `reanchormap` operand ($86 Crystal, $85 Gold/Silver). Lance's
## room is the profile split: Gold and Silver put Lance one row further up, its
## exit warps on y=0 rather than y=1, and end the champion scene with `warp`
## rather than `warpfacing`.
##
## What is worth pinning is the two block changes each room turns on. Nothing
## else stops the leg: the door behind the player is walled by the entrance
## scene, and the door ahead is opened only by the boss.
##
##   Godot --headless --path . -s res://tools/validate_elite_four.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm's INDIGO group, the 16th `newgroup`.
const INDIGO_GROUP: int = 16
const POKECENTER_NUMBER: int = 2
const LANCES_ROOM_NUMBER: int = 7
const HALL_OF_FAME_NUMBER: int = 8

## `IndigoPlateauPokecenter1F_MapEvents` warp 4, the only way in.
const ELITE_FOUR_DOOR: Vector2i = Vector2i(14, 3)
## The cell the route stands on when it takes that door.
const POKECENTER_APPROACH: Vector2i = Vector2i(16, 4)

## The four rooms, in door order. Each is 5x9 blocks, arrives on (5,17), walls
## (4,14) behind the player and opens (4,2) ahead of them.
const ROOMS: Array = [3, 4, 5, 6]
const ROOM_SIZE_BLOCKS: Vector2i = Vector2i(5, 9)
const ROOM_ARRIVAL: Vector2i = Vector2i(5, 17)
const ROOM_BOSS: Vector2i = Vector2i(5, 7)
const ROOM_EXIT: Vector2i = Vector2i(4, 2)
const ROOM_SEAL: Vector2i = Vector2i(4, 14)
## `<Room>_EnterMovement` is four `step UP`.
const ENTER_STEPS: int = 4

## Lance's room is 5x12 blocks and everything in it sits four rows lower.
const LANCES_ROOM_SIZE_BLOCKS: Vector2i = Vector2i(5, 12)
const LANCES_ROOM_ARRIVAL: Vector2i = Vector2i(5, 23)
const LANCES_ROOM_SEAL: Vector2i = Vector2i(4, 22)
const LANCES_ROOM_DOOR: Vector2i = Vector2i(4, 0)
## `coord_event 4, 5` and `coord_event 5, 5`, both on
## SCENE_LANCESROOM_APPROACH_LANCE, which is scene 1: scene constants count from
## zero in `scene_script` declaration order (`macros/scripts/maps.asm`).
const LANCE_COORD_EVENTS: Array = [Vector2i(4, 5), Vector2i(5, 5)]
const LANCE_APPROACH_SCENE: int = 1

## The Hall of Fame is 5x7 blocks; the champion scene lands the player on (4,13)
## and Lance is already standing on (4,12).
const HALL_OF_FAME_SIZE_BLOCKS: Vector2i = Vector2i(5, 7)
const HALL_OF_FAME_ARRIVAL: Vector2i = Vector2i(4, 13)
const HALL_OF_FAME_LANCE: Vector2i = Vector2i(4, 12)

## The block ids the rooms change (`<Room>DoorsCallback` and the boss scripts).
const BLOCK_ROOM_WALL: int = 0x2a
const BLOCK_ROOM_DOOR: int = 0x16
const BLOCK_LANCE_WALL: int = 0x34
const BLOCK_LANCE_DOOR: int = 0x0b

## constants/event_flags.asm, the same numbers in both pins. The twelve
## `IndigoPlateauPokecenter1FPrepareElite4Callback` clears, then the five it
## leaves the boss scripts to set.
const PREPARED_FLAGS: Array[int] = [
	777, 778, 779, 780, 781, 782, 783, 784, 785, 786,
	1464, 1465, 1466, 1467, 1468,
]
## The same callback's one `setevent`, which is what puts Oak and Mary out of
## Lance's room until the champion scene calls them in.
const EVENT_LANCES_ROOM_OAK_AND_MARY: int = 1887

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_pokecenter(data, game_id)
		for number: int in ROOMS:
			_verify_room(data, game_id, number)
		_verify_lances_room(data, game_id)
		_verify_hall_of_fame(data, game_id)
	_finish()


## The one door in, and the prepare callback that resets the leg.
##
## This is the one map here worth entering: `MAPCALLBACK_NEWMAP` is what
## `IndigoPlateauPokecenter1FPrepareElite4Callback` hangs off, and it is a
## reset, so it is checked by setting every flag it clears beforehand.
func _verify_pokecenter(data: GameData, game_id: StringName) -> void:
	var state := Gen2WorldState.new()
	for flag: int in PREPARED_FLAGS:
		state.set_event_flag(flag)
	state.set_event_flag(EVENT_LANCES_ROOM_OAK_AND_MARY, false)
	var world: Gen2WorldAPI = _open(data, POKECENTER_NUMBER, POKECENTER_APPROACH, state)
	if world == null:
		_fail("%s: Indigo Plateau Pokemon Center is missing." % game_id)
		return
	var warp: Dictionary = world.warp_at(ELITE_FOUR_DOOR)
	_check(
		int(warp.get("map_group", -1)) == INDIGO_GROUP
			and int(warp.get("map_number", -1)) == ROOMS[0],
		"%s: %s is not the door into Will's room." % [game_id, ELITE_FOUR_DOOR]
	)
	_check(
		_reaches(world, POKECENTER_APPROACH, ELITE_FOUR_DOOR),
		"%s: the Elite Four door is not reachable from %s." % [game_id, POKECENTER_APPROACH]
	)

	var _entry: Array = world.dispatch_map_entry()
	for _step: int in 8:
		if world.pending_script_input().is_empty():
			break
		world.run_event_queue(true)
	for flag: int in PREPARED_FLAGS:
		_check(
			not world.event_flag_active(flag),
			"%s: the prepare callback left event flag %d set." % [game_id, flag]
		)
	_check(
		world.event_flag_active(EVENT_LANCES_ROOM_OAK_AND_MARY),
		"%s: the prepare callback did not hide Oak and Mary." % game_id
	)


## One of the four identical rooms: the boss on its own cell, the entrance the
## scene walls behind the player, and the exit only the boss opens.
func _verify_room(data: GameData, game_id: StringName, number: int) -> void:
	var world: Gen2WorldAPI = _open(data, number, ROOM_ARRIVAL)
	if world == null:
		_fail("%s: map %d/%d is missing." % [game_id, INDIGO_GROUP, number])
		return
	_check(
		Vector2i(world.current_map.width_blocks, world.current_map.height_blocks)
			== ROOM_SIZE_BLOCKS,
		"%s: %d/%d is %dx%d blocks, not the pinned %s." % [
			game_id, INDIGO_GROUP, number, world.current_map.width_blocks,
			world.current_map.height_blocks, ROOM_SIZE_BLOCKS,
		]
	)
	_check(
		_object_at(world, ROOM_BOSS),
		"%s: %d/%d has no boss object on %s." % [game_id, INDIGO_GROUP, number, ROOM_BOSS]
	)
	var exit_warp: Dictionary = world.warp_at(ROOM_EXIT)
	_check(
		int(exit_warp.get("map_group", -1)) == INDIGO_GROUP
			and int(exit_warp.get("map_number", -1)) == number + 1,
		"%s: %d/%d's exit on %s does not lead to the next room." % [
			game_id, INDIGO_GROUP, number, ROOM_EXIT,
		]
	)
	_verify_doors(
		world, game_id, "%d/%d" % [INDIGO_GROUP, number], ROOM_ARRIVAL,
		ROOM_SEAL, BLOCK_ROOM_WALL, ROOM_EXIT, ROOM_EXIT, BLOCK_ROOM_DOOR
	)


## Lance's room. Its geometry is the profile split, and it is the only room
## whose boss is reached by a coord event rather than by facing an object.
func _verify_lances_room(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, LANCES_ROOM_NUMBER, LANCES_ROOM_ARRIVAL)
	if world == null:
		_fail("%s: Lance's room is missing." % game_id)
		return
	_check(
		Vector2i(world.current_map.width_blocks, world.current_map.height_blocks)
			== LANCES_ROOM_SIZE_BLOCKS,
		"%s: Lance's room is %dx%d blocks, not the pinned %s." % [
			game_id, world.current_map.width_blocks, world.current_map.height_blocks,
			LANCES_ROOM_SIZE_BLOCKS,
		]
	)
	# Gold and Silver stand Lance one row higher and put the Hall of Fame warps
	# on y=0 rather than y=1.
	var crystal: bool = game_id == &"crystal"
	var lance_cell := Vector2i(5, 3 if crystal else 2)
	var exit_cell := Vector2i(4, 1 if crystal else 0)
	_check(
		_object_at(world, lance_cell),
		"%s: Lance is not standing on %s." % [game_id, lance_cell]
	)
	var coords: Array = []
	for event: Dictionary in world.current_map.events.get("coord_events", []):
		coords.append(Vector2i(int(event.get("x", -1)), int(event.get("y", -1))))
		_check(
			int(event.get("scene", -1)) == LANCE_APPROACH_SCENE,
			"%s: Lance's coord event on %s is not on scene %d." % [
				game_id, coords[-1], LANCE_APPROACH_SCENE,
			]
		)
	_check(
		coords == LANCE_COORD_EVENTS,
		"%s: Lance's coord events are on %s, not the pinned %s." % [
			game_id, coords, LANCE_COORD_EVENTS,
		]
	)
	var exit_warp: Dictionary = world.warp_at(exit_cell)
	_check(
		int(exit_warp.get("map_group", -1)) == INDIGO_GROUP
			and int(exit_warp.get("map_number", -1)) == HALL_OF_FAME_NUMBER,
		"%s: Lance's exit on %s does not lead to the Hall of Fame." % [game_id, exit_cell]
	)
	_verify_doors(
		world, game_id, "Lance's room", LANCES_ROOM_ARRIVAL,
		LANCES_ROOM_SEAL, BLOCK_LANCE_WALL, LANCES_ROOM_DOOR, exit_cell, BLOCK_LANCE_DOOR
	)


## The Hall of Fame, which the champion scene warps into rather than walks into.
func _verify_hall_of_fame(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, HALL_OF_FAME_NUMBER, HALL_OF_FAME_ARRIVAL)
	if world == null:
		_fail("%s: the Hall of Fame is missing." % game_id)
		return
	_check(
		Vector2i(world.current_map.width_blocks, world.current_map.height_blocks)
			== HALL_OF_FAME_SIZE_BLOCKS,
		"%s: the Hall of Fame is %dx%d blocks, not the pinned %s." % [
			game_id, world.current_map.width_blocks, world.current_map.height_blocks,
			HALL_OF_FAME_SIZE_BLOCKS,
		]
	)
	_check(
		_object_at(world, HALL_OF_FAME_LANCE),
		"%s: Lance is not standing on %s." % [game_id, HALL_OF_FAME_LANCE]
	)
	# HallOfFame_WalkUpWithLance is eight `step UP` then one `step RIGHT`, with
	# the player following, so the column north of the arrival has to be open.
	_check(
		_reaches(world, HALL_OF_FAME_ARRIVAL, HALL_OF_FAME_ARRIVAL + Vector2i(0, -9)),
		"%s: the Hall of Fame machine is not reachable from %s." % [
			game_id, HALL_OF_FAME_ARRIVAL,
		]
	)


## The two block changes a room turns on, checked as reachability rather than as
## collision bytes: the entrance scene has to cut the arrival warp off, and the
## boss has to open a door that was solid before them.
##
## [param seal] and [param door] are source walk cells, which a `changeblock`
## takes; a block spans 2x2 of them, so the block index is the cell halved.
func _verify_doors(
	world: Gen2WorldAPI,
	game_id: StringName,
	label: String,
	arrival: Vector2i,
	seal: Vector2i,
	seal_block: int,
	door: Vector2i,
	exit_cell: Vector2i,
	door_block: int,
) -> void:
	var settled: Vector2i = arrival + Vector2i(0, -ENTER_STEPS)
	_check(
		world.can_walk_to(settled) and _reaches(world, settled, arrival),
		"%s: %s does not walk %d cells north of %s." % [game_id, label, ENTER_STEPS, arrival]
	)
	_check(
		_reaches(world, settled, exit_cell + Vector2i(0, 1)),
		"%s: %s does not reach its own exit door from %s." % [game_id, label, settled]
	)
	_check(
		not world.can_walk_to(exit_cell) and not _reaches(world, settled, exit_cell),
		"%s: %s's exit on %s is open before its boss." % [game_id, label, exit_cell]
	)
	_check(
		bool(world.change_block(seal.x / 2, seal.y / 2, seal_block).get("ok", false))
			and not _reaches(world, settled, arrival),
		"%s: %s's entrance scene does not seal %s." % [game_id, label, arrival]
	)
	_check(
		bool(world.change_block(door.x / 2, door.y / 2, door_block).get("ok", false))
			and world.can_walk_to(exit_cell) and _reaches(world, settled, exit_cell),
		"%s: %s's boss does not open the exit on %s." % [game_id, label, exit_cell]
	)


## Map entry is deliberately not dispatched for the rooms. Every one of them
## has an entry scene that walls the door behind the player, and the Hall of
## Fame's walks Lance off his own cell, so a dispatched world describes the
## scripts rather than the map they run on. Proving the scripts is the walked
## route's job (`tools/preview_world_story.gd`); this pins what they act on.
func _open(
	data: GameData, number: int, cell: Vector2i, state: Gen2WorldState = null
) -> Gen2WorldAPI:
	return Gen2WorldAPI.open(
		data, INDIGO_GROUP, number, cell,
		state if state != null else Gen2WorldState.new()
	)


func _object_at(world: Gen2WorldAPI, cell: Vector2i) -> bool:
	for object: Gen2WorldObject in world.objects:
		if object.cell == cell:
			return true
	return false


## Plain walking reachability. Warp tiles are walls unless they are the target,
## the way a walked route has it: stepping onto one takes it.
func _reaches(world: Gen2WorldAPI, from: Vector2i, target: Vector2i) -> bool:
	var seen: Dictionary = {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		if cell == target:
			return true
		for step: Vector2i in STEPS:
			var next: Vector2i = cell + step
			if seen.has(next) or not world.can_walk_to(next, step):
				continue
			if next != target and not world.warp_at(next).is_empty() \
				and Gen2WorldCollision.is_warp_tile(world.collision_code_at(next)):
				continue
			# can_walk_to() reads the leave/enter mask at the API's own player
			# cell; from a frontier it has to be anchored on the frontier cell.
			var face: int = Gen2WorldCollision.face_mask_for_direction(step)
			if face != 0 and (world.tile_permissions_at(cell) & face) != 0:
				continue
			seen[next] = true
			frontier.append(next)
	return seen.has(target)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS elite four: the five rooms' doors, coord events and flags verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL elite four: %d problems." % _failures.size())
	quit(1)
