extends SceneTree

## Verifies the gates the Goldenrod Radio Tower leg turns, against freshly
## imported real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `maps/BlackthornCity.asm`, `maps/RadioTower2F.asm`, `maps/RadioTower3F.asm`
## and `maps/GoldenrodUndergroundSwitchRoomEntrances.asm`. Blackthorn City's
## event rows, RadioTower3F whole, and the switch room's `ugdoor_def` table and
## `..._UpdateDoors` body are byte identical between the pins, and every event
## flag below has the same number in both.
##
## The leg is route work, so what is worth pinning is not the scripts but the
## three places a wrong flag or a missed `changeblock` would silently seal the
## route: Blackthorn Gym's door, Radio Tower 2F's stairs and 3F's card-key
## shutter, and the switch room's eleven doors.
##
##   Godot --headless --path . -s res://tools/validate_radio_tower.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## data/maps/maps.asm group/number pairs. Blackthorn City and the Radio Tower
## floors sit at the same pair in both games; Crystal's own extra maps push the
## Goldenrod Underground eight places down the Dungeons group.
const BLACKTHORN_CITY: Array = [5, 10]
const RADIO_TOWER_2F: Array = [3, 18]
const RADIO_TOWER_3F: Array = [3, 19]
const SWITCH_ROOM: Dictionary = {
	&"gold": [3, 46],
	&"silver": [3, 46],
	&"crystal": [3, 54],
}

## constants/event_flags.asm, same numbers in both pins.
const EVENT_USED_THE_CARD_KEY: int = 37
const EVENT_BLACKBELT_BLOCKS_STAIRS: int = 1745
const EVENT_SUPER_NERD_BLOCKS_GYM: int = 1763
const EVENT_SUPER_NERD_DOES_NOT_BLOCK_GYM: int = 1764
## EVENT_DOOR_1_OPEN is 727, so door n is this plus n.
const EVENT_DOOR_OPEN_BASE: int = 726

## The `ugdoor_def` table verbatim: door id, then each row's source cell with
## its closed and open block ids. Rows 1 to 6 are the single-block vertical
## links between bands; 7 to 11 are the two-block horizontal doors whose $2a
## upper half stays a wall and whose $2d lower half is what opens.
const UGDOORS: Array = [
	{"door": 1, "rows": [[Vector2i(16, 6), 0x3e, 0x2d]]},
	{"door": 2, "rows": [[Vector2i(10, 6), 0x3e, 0x2d]]},
	{"door": 3, "rows": [[Vector2i(2, 6), 0x3e, 0x2d]]},
	{"door": 4, "rows": [[Vector2i(2, 10), 0x3e, 0x2d]]},
	{"door": 5, "rows": [[Vector2i(10, 10), 0x3e, 0x2d]]},
	{"door": 6, "rows": [[Vector2i(16, 10), 0x3e, 0x2d]]},
	{"door": 7, "rows": [[Vector2i(12, 6), 0x3f, 0x2a], [Vector2i(12, 8), 0x3d, 0x2d]]},
	{"door": 8, "rows": [[Vector2i(6, 6), 0x3f, 0x2a], [Vector2i(6, 8), 0x3d, 0x2d]]},
	{"door": 9, "rows": [[Vector2i(12, 10), 0x3f, 0x2a], [Vector2i(12, 12), 0x3d, 0x2d]]},
	{"door": 10, "rows": [[Vector2i(6, 10), 0x3f, 0x2a], [Vector2i(6, 12), 0x3d, 0x2d]]},
	{"door": 11, "rows": [[Vector2i(18, 10), 0x3f, 0x2a], [Vector2i(18, 12), 0x3d, 0x2d]]},
]

## What `..._UpdateDoors` leaves open after switch 3, then 2, then 1, which
## walks positions 3, 5 and 6. Position 6 opens 6, 8, 9 and 11 and closes only
## 1, 7 and 10, so 3 and 5 survive from the two positions before it.
const OPEN_AT_POSITION_6: Array[int] = [3, 5, 6, 8, 9, 11]

## The switch room's top corridor, entered from GoldenrodUnderground's south
## half, and the two warps into the warehouse.
const SWITCH_ROOM_ENTRY: Vector2i = Vector2i(23, 3)
const WAREHOUSE_DOORS: Array = [Vector2i(22, 10), Vector2i(23, 10)]

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_blackthorn_gym_door(data, game_id)
		_verify_radio_tower_stairs(data, game_id)
		_verify_switch_room(data, game_id)
	_finish()


## The gate this whole leg exists to open. BLACKTHORNCITY_SUPER_NERD1 stands on
## (18,12), the only cell that reaches the gym door warp at (18,11), and
## RadioTower5FRocketBossScript is the only thing that hides it.
func _verify_blackthorn_gym_door(data: GameData, game_id: StringName) -> void:
	var sealed: Gen2WorldAPI = _open(
		data, BLACKTHORN_CITY, Vector2i(18, 13), [EVENT_SUPER_NERD_DOES_NOT_BLOCK_GYM]
	)
	if sealed == null:
		_fail("%s: Blackthorn City is missing." % game_id)
		return

	var warp: Dictionary = sealed.warp_at(Vector2i(18, 11))
	_check(
		not warp.is_empty() and int(warp.get("map_group", -1)) == 5
			and int(warp.get("map_number", -1)) == 1,
		"%s: (18,11) is not the Blackthorn Gym warp." % game_id
	)
	_check(
		Gen2WorldCollision.is_warp_tile(sealed.collision_code_at(Vector2i(18, 11))),
		"%s: the gym door at (18,11) is not on a warp tile." % game_id
	)
	for wall: Vector2i in [Vector2i(17, 11), Vector2i(19, 11)]:
		_check(
			not sealed.can_walk_to(wall),
			"%s: %s beside the gym door is walkable, so (18,12) is not the only way in." % [
				game_id, wall,
			]
		)
	_check(
		not _reaches(sealed, Vector2i(18, 13), Vector2i(18, 11)),
		"%s: the gym door is reachable before the Radio Tower is cleared." % game_id
	)

	var open_city: Gen2WorldAPI = _open(
		data, BLACKTHORN_CITY, Vector2i(18, 13), [EVENT_SUPER_NERD_BLOCKS_GYM]
	)
	_check(
		_reaches(open_city, Vector2i(18, 13), Vector2i(18, 11)),
		"%s: the gym door is still sealed after the Radio Tower is cleared." % game_id
	)


## 2F's stairs are behind the Black Belt on (0,1), whom RadioTowerRocketsScript
## hides; 3F's second staircase is behind the card-key shutter, which
## RadioTower3FCardKeyShutterCallback changeblocks open on every later load.
func _verify_radio_tower_stairs(data: GameData, game_id: StringName) -> void:
	var blocked: Gen2WorldAPI = _open(data, RADIO_TOWER_2F, Vector2i(15, 0), [])
	if blocked == null:
		_fail("%s: Radio Tower 2F is missing." % game_id)
		return
	_check(
		not _reaches(blocked, Vector2i(15, 0), Vector2i(0, 0)),
		"%s: Radio Tower 2F's stairs are open before the takeover." % game_id
	)
	var cleared: Gen2WorldAPI = _open(
		data, RADIO_TOWER_2F, Vector2i(15, 0), [EVENT_BLACKBELT_BLOCKS_STAIRS]
	)
	_check(
		_reaches(cleared, Vector2i(15, 0), Vector2i(0, 0)),
		"%s: Radio Tower 2F's stairs are still blocked after the takeover." % game_id
	)

	var shut: Gen2WorldAPI = _open(data, RADIO_TOWER_3F, Vector2i(0, 0), [])
	if shut == null:
		_fail("%s: Radio Tower 3F is missing." % game_id)
		return
	_check(
		_reaches(shut, Vector2i(0, 0), Vector2i(7, 0)),
		"%s: Radio Tower 3F's first staircase is unreachable." % game_id
	)
	_check(
		_reaches(shut, Vector2i(0, 0), Vector2i(14, 3)),
		"%s: the card-key slot cannot be faced from (14,3)." % game_id
	)
	_check(
		not _reaches(shut, Vector2i(0, 0), Vector2i(17, 0)),
		"%s: Radio Tower 3F's shutter staircase is open without the card key." % game_id
	)
	var opened: Gen2WorldAPI = _open(
		data, RADIO_TOWER_3F, Vector2i(0, 0), [EVENT_USED_THE_CARD_KEY]
	)
	_check(
		_reaches(opened, Vector2i(0, 0), Vector2i(17, 0)),
		"%s: the card-key shutter did not open the second staircase." % game_id
	)


## Every `ugdoor_def` row against the blocks its callback writes, then the one
## chain from the top corridor to the warehouse that the three switches open.
func _verify_switch_room(data: GameData, game_id: StringName) -> void:
	var id: Array = SWITCH_ROOM[game_id]
	var closed: Gen2WorldAPI = _open(data, id, SWITCH_ROOM_ENTRY, [])
	if closed == null:
		_fail("%s: the switch room is missing." % game_id)
		return
	for door: Dictionary in UGDOORS:
		for row: Array in door["rows"]:
			var cell: Vector2i = row[0]
			_check(
				closed.block_at(cell.x / 2, cell.y / 2) == int(row[1]),
				"%s: door %d at %s is block $%02x closed, not the pinned $%02x." % [
					game_id, int(door["door"]), cell,
					closed.block_at(cell.x / 2, cell.y / 2), int(row[1]),
				]
			)

	var all_doors: Array[int] = []
	for door: Dictionary in UGDOORS:
		all_doors.append(EVENT_DOOR_OPEN_BASE + int(door["door"]))
	var opened: Gen2WorldAPI = _open(data, id, SWITCH_ROOM_ENTRY, all_doors)
	for door: Dictionary in UGDOORS:
		for row: Array in door["rows"]:
			var cell: Vector2i = row[0]
			_check(
				opened.block_at(cell.x / 2, cell.y / 2) == int(row[2]),
				"%s: door %d at %s is block $%02x open, not the pinned $%02x." % [
					game_id, int(door["door"]), cell,
					opened.block_at(cell.x / 2, cell.y / 2), int(row[2]),
				]
			)

	for warehouse_door: Vector2i in WAREHOUSE_DOORS:
		_check(
			not _reaches(closed, SWITCH_ROOM_ENTRY, warehouse_door),
			"%s: the warehouse door %s is reachable with every door shut." % [
				game_id, warehouse_door,
			]
		)

	var position_6: Array[int] = []
	for door: int in OPEN_AT_POSITION_6:
		position_6.append(EVENT_DOOR_OPEN_BASE + door)
	var solved: Gen2WorldAPI = _open(data, id, SWITCH_ROOM_ENTRY, position_6)
	for warehouse_door: Vector2i in WAREHOUSE_DOORS:
		_check(
			_reaches(solved, SWITCH_ROOM_ENTRY, warehouse_door),
			"%s: switches 3, 2 and 1 do not open a way to the warehouse door %s." % [
				game_id, warehouse_door,
			]
		)
	# The emergency switch is inside the room the warehouse opens into, which is
	# why coming back needs it rather than the three switches.
	_check(
		_reaches(solved, WAREHOUSE_DOORS[0], Vector2i(20, 12)),
		"%s: the emergency switch cannot be faced from inside the warehouse room." % game_id
	)


func _open(data: GameData, id: Array, cell: Vector2i, flags: Array) -> Gen2WorldAPI:
	var state := Gen2WorldState.new()
	for flag: int in flags:
		state.set_event_flag(flag)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, id[0], id[1], cell, state)
	if world == null:
		return null
	# The door and shutter blocks are written by MAPCALLBACK_TILES, so the map's
	# own callbacks have to run before anything is read off the grid.
	var _entry: Array = world.dispatch_map_entry()
	for _step: int in 8:
		if not world.pending_script_wait().is_empty():
			world.finish_script_waits()
			continue
		if world.pending_script_input().is_empty():
			break
		world.run_event_queue(true)
	return world


## Plain walking reachability, which is all these gates turn on.
func _reaches(world: Gen2WorldAPI, from: Vector2i, target: Vector2i) -> bool:
	if world == null:
		return false
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
			seen[next] = true
			frontier.append(next)
	return false


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS radio tower: the Blackthorn, stairs, shutter and switch-room gates verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL radio tower: %d problems." % _failures.size())
	quit(1)
