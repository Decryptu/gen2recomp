extends RefCounted

var _r: RefCounted = null

## Verifies the S.S. Aqua's interior against freshly imported real caches, for
## both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## maps/FastShip1F.asm, maps/FastShipB1F.asm, maps/FastShipCabins_NNW_NNE_NE.asm,
## maps/FastShipCabins_SE_SSE_CaptainsCabin.asm and constants/event_flags.asm.
## All five maps' event tables are byte identical between the pins and every
## event flag below has the same number in both, so nothing here is profile
## split; only the text and Crystal's own gender branch differ.
##
## The crossing is one puzzle. B1F's two sailors stand on (30,6) and (31,6) and
## the coord events below them each move the visible one onto the player's own
## column, so the corridor west is sealed for as long as the map scene is
## SCENE_FASTSHIPB1F_SAILOR_BLOCKS. Nothing on B1F opens it: the on-duty sailor
## reveals the lazy one in the NE cabin, and that sailor's own script sets
## SCENE_FASTSHIPB1F_NOOP, which retires both coord events.
##
##   Godot --headless --path . -s res://tools/validate.gd -- ss_aqua


## `constants/map_constants.asm`'s 15th `newgroup`.
const GROUP: int = 15
const VERMILION_PORT: int = 2
const FAST_SHIP_1F: int = 3
const NE_CABIN: int = 4
const CAPTAIN_CABIN: int = 6
const FAST_SHIP_B1F: int = 7

## Scene ids are ordinal in `scene_script` declaration order
## (`macros/scripts/maps.asm`), so B1F's first scene is the blocking one.
const SCENE_SAILOR_BLOCKS: int = 0
const SCENE_NOOP: int = 1

## constants/event_flags.asm, identical in both pins.
const EVENT_B1F_SAILOR_LEFT: int = 1838
const EVENT_B1F_SAILOR_RIGHT: int = 1839
const EVENT_NE_CABIN_SAILOR: int = 1837
const EVENT_TWIN_2: int = 1842

## `maps/FastShipB1F.asm`'s own event table.
const B1F_SAILORS: Array[Vector2i] = [Vector2i(30, 6), Vector2i(31, 6)]
const B1F_COORD_EVENTS: Array[Vector2i] = [Vector2i(30, 7), Vector2i(31, 7)]
const B1F_EAST_DOOR: Vector2i = Vector2i(31, 13)
const B1F_WEST_STAIRS: Vector2i = Vector2i(5, 11)

## The 1F doors this crossing uses, in `def_warp_events` order.
const ONE_F_TO_NE_CABIN: Vector2i = Vector2i(19, 8)
const ONE_F_TO_CAPTAIN_CABIN: Vector2i = Vector2i(3, 13)
const ONE_F_TO_B1F_WEST: Vector2i = Vector2i(6, 12)
const ONE_F_TO_B1F_EAST: Vector2i = Vector2i(30, 14)

const LAZY_SAILOR: Vector2i = Vector2i(4, 26)
const NE_CABIN_DOOR: Vector2i = Vector2i(2, 24)
const GRANDDAUGHTER: Vector2i = Vector2i(2, 25)
const GRANDDAUGHTER_FACE: Vector2i = Vector2i(1, 25)
const GRANDPA_CABIN_DOOR: Vector2i = Vector2i(2, 19)


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_b1f_records(data, game_id)
		_verify_one_f_regions(data, game_id)
		_verify_cabins(data, game_id)
		_drive_sealed_corridor(data, game_id)
		_drive_open_corridor(data, game_id)


## B1F's two sailors, their flags and the coord events that move them.
func _verify_b1f_records(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, FAST_SHIP_B1F, B1F_EAST_DOOR)
	if world == null:
		_r.fail("%s: FAST_SHIP_B1F is missing." % game_id)
		return
	var flags: Array[int] = [EVENT_B1F_SAILOR_LEFT, EVENT_B1F_SAILOR_RIGHT]
	for index: int in B1F_SAILORS.size():
		var object: Gen2WorldObject = world.object_at(B1F_SAILORS[index])
		if not _r.check(
			object != null,
			"%s: no sailor on %s of B1F." % [game_id, B1F_SAILORS[index]]
		):
			continue
		_r.check(
			object.event_flag == flags[index],
			"%s: the sailor on %s carries flag %d, not the pinned %d." % [
				game_id, B1F_SAILORS[index], object.event_flag, flags[index],
			]
		)
	var coord_events: Array = world.current_map.events.get("coord_events", [])
	var seen: Array[Vector2i] = []
	for event: Dictionary in coord_events:
		var cell := Vector2i(int(event.get("x", -1)), int(event.get("y", -1)))
		seen.append(cell)
		_r.check(
			int(event.get("scene", -1)) == SCENE_SAILOR_BLOCKS,
			"%s: B1F's coord event on %s is scene %d, not the blocking one." % [
				game_id, cell, int(event.get("scene", -1)),
			]
		)
	_r.check(
		seen == B1F_COORD_EVENTS,
		"%s: B1F's coord events are on %s, not the pinned %s." % [
			game_id, seen, B1F_COORD_EVENTS,
		]
	)
	_r.check(
		world.warp_index_at(B1F_EAST_DOOR) == 2 and world.warp_index_at(B1F_WEST_STAIRS) == 1,
		"%s: B1F's two warps are not on %s and %s." % [
			game_id, B1F_WEST_STAIRS, B1F_EAST_DOOR,
		]
	)
	print("%s b1f: both sailors, both coord events and both warps match the pins." % game_id)


## 1F is three walkable regions, and the deck cannot reach the west wing: the
## sailor on (14,7) has event flag -1, so nothing ever moves him.
func _verify_one_f_regions(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, FAST_SHIP_1F, ONE_F_TO_B1F_EAST)
	if world == null:
		_r.fail("%s: FAST_SHIP_1F is missing." % game_id)
		return
	var deck: Dictionary = _region(world, ONE_F_TO_B1F_EAST)
	_r.check(
		deck.has(ONE_F_TO_NE_CABIN),
		"%s: 1F's deck does not reach the NE cabin door." % game_id
	)
	_r.check(
		not deck.has(ONE_F_TO_CAPTAIN_CABIN) and not deck.has(ONE_F_TO_B1F_WEST),
		"%s: 1F's deck reaches the west wing without going below." % game_id
	)
	var wing: Dictionary = _region(world, ONE_F_TO_B1F_WEST)
	_r.check(
		wing.has(ONE_F_TO_CAPTAIN_CABIN),
		"%s: 1F's west wing does not reach the captain's cabin door." % game_id
	)
	print("%s 1f: the deck is %d cells and the west wing %d, with no path between." % [
		game_id, deck.size(), wing.size(),
	])


## The lazy sailor and the granddaughter, and the five rows of wall the
## granddaughter's scene walks the player through.
func _verify_cabins(data: GameData, game_id: StringName) -> void:
	var cabin: Gen2WorldAPI = _open(data, NE_CABIN, NE_CABIN_DOOR)
	if cabin == null:
		_r.fail("%s: the NE cabin is missing." % game_id)
	else:
		var sailor: Gen2WorldObject = cabin.object_at(LAZY_SAILOR)
		if _r.check(sailor != null, "%s: no lazy sailor on %s." % [game_id, LAZY_SAILOR]):
			_r.check(
				sailor.event_flag == EVENT_NE_CABIN_SAILOR,
				"%s: the lazy sailor carries flag %d, not the pinned %d." % [
					game_id, sailor.event_flag, EVENT_NE_CABIN_SAILOR,
				]
			)
		_r.check(
			_region(cabin, NE_CABIN_DOOR).has(Vector2i(4, 27)),
			"%s: the lazy sailor cannot be faced from the NE cabin's own door." % game_id
		)

	var captain: Gen2WorldAPI = _open(data, CAPTAIN_CABIN, Vector2i(2, 33))
	if captain == null:
		_r.fail("%s: the captain's cabin is missing." % game_id)
		return
	var twin: Gen2WorldObject = captain.object_at(GRANDDAUGHTER)
	if _r.check(twin != null, "%s: no granddaughter on %s." % [game_id, GRANDDAUGHTER]):
		_r.check(
			twin.event_flag == EVENT_TWIN_2,
			"%s: the granddaughter carries flag %d, not the pinned %d." % [
				game_id, twin.event_flag, EVENT_TWIN_2,
			]
		)
	var section: Dictionary = _region(captain, Vector2i(2, 33))
	_r.check(
		section.has(GRANDDAUGHTER_FACE),
		"%s: the granddaughter cannot be faced from the captain's cabin door." % game_id
	)
	_r.check(
		not section.has(GRANDPA_CABIN_DOOR),
		"%s: the captain's cabin already walks to the grandpa cabin's door." % game_id
	)
	# SSAquaCaptainsCabinWarpsToGrandpasCabinMovement is one big_step RIGHT and
	# six UP, from (1,25) to (2,19). Every cell between is wall, which is the
	# whole reason the scene is the only way back east.
	for y: int in range(20, 25):
		_r.check(
			not captain.can_walk_to(Vector2i(2, y)),
			"%s: (2,%d) of the captain's cabin is walkable, so the scene crosses no wall." % [
				game_id, y,
			]
		)
	_r.check(
		captain.warp_index_at(GRANDPA_CABIN_DOOR) == 3,
		"%s: %s is not the grandpa cabin's own door." % [game_id, GRANDPA_CABIN_DOOR]
	)
	print("%s cabins: the lazy sailor, the granddaughter and her scene's five wall rows check out." % game_id)


## The puzzle itself, on the map the cartridge ships: whichever coord event the
## player steps onto, the cell north of them is the one the sailor takes.
func _drive_sealed_corridor(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(
		data, FAST_SHIP_B1F, Vector2i(31, 8), {EVENT_B1F_SAILOR_RIGHT: true}
	)
	if world == null:
		return
	for step: Array in [[Vector2i.UP, Vector2i(31, 7)], [Vector2i.LEFT, Vector2i(30, 7)]]:
		var moved: Dictionary = world.move_result(step[0])
		if not _r.check(
			bool(moved.get("ok", false)) and world.player_cell == step[1],
			"%s: the step onto %s refused: %s" % [game_id, step[1], moved.get("reason", "")]
		):
			return
		var results: Array = world.dispatch_script_events()
		if not _r.check(
			not results.is_empty(),
			"%s: %s dispatched no coord event while the scene blocks." % [game_id, step[1]]
		):
			return
		for _attempt: int in 16:
			if not world.pending_script_wait().is_empty():
				results = world.finish_script_waits()
				continue
			if world.pending_script_input().is_empty():
				break
			results = world.run_event_queue(true)
		var north: Vector2i = world.player_cell + Vector2i.UP
		_r.check(
			world.object_at(north) != null,
			"%s: %s is open after the coord event on %s ran." % [game_id, north, step[1]]
		)
	# Which is the whole seal: the two sailor cells are the east region's only
	# way onto row 6, and each is entered only from the coord event below it, so
	# a walk that steps north is always stepping into the sailor that step just
	# summoned. A plain region test cannot say that, because after the second
	# toggle the column the player is not standing in really is open.
	for cell: Vector2i in B1F_SAILORS:
		_r.check(
			cell + Vector2i.DOWN in B1F_COORD_EVENTS,
			"%s: %s is not entered from a coord event cell." % [game_id, cell]
		)
	_r.check(
		not _region(world, world.player_cell, B1F_COORD_EVENTS).has(B1F_WEST_STAIRS),
		"%s: B1F's west stairs are reachable while the sailors still block." % game_id
	)
	print("%s b1f sealed: both coord events put a sailor back in the player's own column." % game_id)


## And once the lazy sailor's `setmapscene FAST_SHIP_B1F, SCENE_FASTSHIPB1F_NOOP`
## has run, the coord events are inert and the free column is a corridor.
func _drive_open_corridor(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(
		data, FAST_SHIP_B1F, Vector2i(31, 8), {EVENT_B1F_SAILOR_RIGHT: true},
		{Gen2WorldState.map_scene_key(GROUP, FAST_SHIP_B1F): SCENE_NOOP}
	)
	if world == null:
		return
	var moved: Dictionary = world.move_result(Vector2i.UP)
	if not _r.check(
		bool(moved.get("ok", false)),
		"%s: the step onto (31,7) refused with the scene retired." % game_id
	):
		return
	_r.check(
		world.dispatch_script_events().is_empty(),
		"%s: (31,7) still dispatches a coord event with the scene retired." % game_id
	)
	var region: Dictionary = _region(world, world.player_cell)
	_r.check(
		region.has(B1F_WEST_STAIRS),
		"%s: B1F's west stairs are still unreachable with the scene retired." % game_id
	)
	print("%s b1f open: the retired scene leaves a %d-cell region reaching the west stairs." % [
		game_id, region.size(),
	])


func _open(
	data: GameData, number: int, cell: Vector2i,
	flags: Dictionary = {}, scenes: Dictionary = {},
) -> Gen2WorldAPI:
	var state := Gen2WorldState.new(flags, scenes)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, GROUP, number, cell, state)
	if world == null:
		_r.fail("map %d/%d is missing." % [GROUP, number])
	return world


## [param sealed_north] names cells a walk may enter but never step north from,
## which is how a coord event that summons a sailor onto the cell above behaves.
func _region(
	world: Gen2WorldAPI, start: Vector2i, sealed_north: Array[Vector2i] = []
) -> Dictionary:
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if direction == Vector2i.UP and cell in sealed_north:
				continue
			var next: Vector2i = cell + direction
			if seen.has(next) or not world.can_walk_to(next, direction):
				continue
			seen[next] = true
			frontier.append(next)
	return seen
