extends RefCounted

var _r: RefCounted = null

## Verifies the walk from Viridian Gym to Red on Silver Cave Room 3, against
## freshly imported real caches for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## data/maps/attributes.asm, constants/map_constants.asm, maps/PalletTown.asm,
## maps/OaksLab.asm, maps/Route22.asm, maps/VictoryRoadGate.asm,
## maps/Route28.asm, maps/SilverCaveOutside.asm and maps/SilverCaveRoom1.asm
## through maps/SilverCaveRoom3.asm.
##
## Three findings carry the leg. The Victory Road Gate is three regions joined
## by two single cells, and a black belt stands in each, so each belt's hide
## flag is the gate on its own arm: EVENT_FOUGHT_SNORLAX opens the Route 22 arm
## and EVENT_OPENED_MT_SILVER the Route 28 one, which makes Oak a hard gate on
## Mt. Silver rather than a courtesy. Each Silver Cave room is one region, so no
## room needs a hand-named intermediate cell the way Cinnabar did. And Red
## carries EVENT_RED_IN_MT_SILVER as his hide flag, which InitializeEventsScript
## sets at a new game and only HallOfFameEnterScript clears, so the room is
## empty until the Hall of Fame.
##
##   Godot --headless --path . -s res://tools/validate.gd -- mt_silver


## constants/map_constants.asm. The DUNGEONS group is the one split on this leg:
## Crystal inserts maps ahead of Silver Cave, so its three rooms are 74, 75 and
## 76 where Gold and Silver number them 66, 67 and 68.
const DUNGEONS_GROUP: int = 3
const SILVER_CAVE_ROOM_1: int = 74
const SILVER_CAVE_ROOM_1_GOLD_SILVER: int = 66
const PALLET_GROUP: int = 13
const ROUTE_1: int = 1
const PALLET_TOWN: int = 2
const OAKS_LAB: int = 6
const SILVER_GROUP: int = 19
const ROUTE_28: int = 1
const SILVER_CAVE_OUTSIDE: int = 2
const SILVER_CAVE_POKECENTER_1F: int = 3
const VIRIDIAN_GROUP: int = 23
const ROUTE_22: int = 2
const VIRIDIAN_CITY: int = 3
const VIRIDIAN_GYM: int = 4
const VICTORY_ROAD_GATE: int = 13

## The warp chain, as [label, group, number, the cell the warp stands on, the
## target group and number, and the one-based destination warp index that
## decides the landing cell]. [param room_1] is the profile's first Silver Cave
## room, which the other two follow.
func _warp_chain(room_1: int) -> Array:
	return [
		["Viridian Gym's door", VIRIDIAN_GROUP, VIRIDIAN_GYM, Vector2i(4, 17),
			VIRIDIAN_GROUP, VIRIDIAN_CITY, 1],
		["Pallet Town's lab door", PALLET_GROUP, PALLET_TOWN, Vector2i(12, 11),
			PALLET_GROUP, OAKS_LAB, 1],
		["Oak's lab exit", PALLET_GROUP, OAKS_LAB, Vector2i(4, 11),
			PALLET_GROUP, PALLET_TOWN, 3],
		["Route 22's gate door", VIRIDIAN_GROUP, ROUTE_22, Vector2i(13, 5),
			VIRIDIAN_GROUP, VICTORY_ROAD_GATE, 1],
		["the gate's west door", VIRIDIAN_GROUP, VICTORY_ROAD_GATE, Vector2i(1, 7),
			SILVER_GROUP, ROUTE_28, 2],
		["the Mt. Silver Pokecenter door", SILVER_GROUP, SILVER_CAVE_OUTSIDE, Vector2i(23, 19),
			SILVER_GROUP, SILVER_CAVE_POKECENTER_1F, 1],
		["Silver Cave's mouth", SILVER_GROUP, SILVER_CAVE_OUTSIDE, Vector2i(18, 11),
			DUNGEONS_GROUP, room_1, 1],
		["Room 1's north ladder", DUNGEONS_GROUP, room_1, Vector2i(15, 1),
			DUNGEONS_GROUP, room_1 + 1, 1],
		["Room 2's north ladder", DUNGEONS_GROUP, room_1 + 1, Vector2i(11, 5),
			DUNGEONS_GROUP, room_1 + 2, 1],
	]

## The two plain connections the leg walks, as [label, group, number, the cell
## the walk starts on, the axis, and the map that axis crosses onto].
const CONNECTIONS: Array = [
	["Viridian City", VIRIDIAN_GROUP, VIRIDIAN_CITY, Vector2i(18, 0), "west",
		VIRIDIAN_GROUP, ROUTE_22],
	["Route 28", SILVER_GROUP, ROUTE_28, Vector2i(33, 5), "west",
		SILVER_GROUP, SILVER_CAVE_OUTSIDE],
]

## Pallet Town, where Oak stands. The lab door is the third warp, so the walk
## south off Route 1 has to reach it on foot.
const PALLET_LANDING: Vector2i = Vector2i(8, 0)
const OAKS_LAB_DOOR: Vector2i = Vector2i(12, 11)
const OAKS_LAB_LANDING: Vector2i = Vector2i(4, 11)
const OAK_CELL: Vector2i = Vector2i(4, 2)
const OAK_FACE: Vector2i = Vector2i(4, 3)
const EVENT_OPENED_MT_SILVER: int = 1871

## Victory Road Gate, which is three regions joined by two single cells, and a
## black belt stands in each. The left belt on (7,5) joins the central corridor
## to the west arm and the Route 28 door; the right belt on (12,5) joins it to
## the east arm and the Route 22 door. Each belt's hide flag is therefore the
## gate on its own arm, which is why Oak has to be talked to before the walk
## west is open at all.
const GATE_LANDING: Vector2i = Vector2i(17, 7)
const GATE_WEST_DOOR: Vector2i = Vector2i(1, 7)
const GATE_ROUTE_26_DOOR: Vector2i = Vector2i(9, 17)
const GATE_VICTORY_ROAD_DOOR: Vector2i = Vector2i(9, 0)
const GATE_LEFT_BLACK_BELT: Vector2i = Vector2i(7, 5)
const GATE_RIGHT_BLACK_BELT: Vector2i = Vector2i(12, 5)
const GATE_BADGE_CHECK: Vector2i = Vector2i(10, 11)
const EVENT_FOUGHT_SNORLAX: int = 1872

## Route 28 and Silver Cave Outside.
const ROUTE_28_LANDING: Vector2i = Vector2i(33, 5)
const SILVER_CAVE_OUTSIDE_POKECENTER_DOOR: Vector2i = Vector2i(23, 19)
const SILVER_CAVE_MOUTH: Vector2i = Vector2i(18, 11)
const ENGINE_FLYPOINT_SILVER_CAVE: int = 76

## The Mt. Silver Pokecenter, the last heal before Red.
const POKECENTER_LANDING: Vector2i = Vector2i(3, 7)
const NURSE_CELL: Vector2i = Vector2i(3, 1)
const NURSE_FACE: Vector2i = Vector2i(3, 2)

## The three rooms, as [label, the offset off the profile's first room, the cell
## the room is entered on, the cell the walk has to reach in it].
const SILVER_CAVE_ROOMS: Array = [
	["Room 1", 0, Vector2i(9, 33), Vector2i(15, 1)],
	["Room 2", 1, Vector2i(17, 31), Vector2i(11, 5)],
	["Room 3", 2, Vector2i(9, 33), Vector2i(9, 11)],
]
const RED_CELL: Vector2i = Vector2i(9, 10)
const RED_FACE: Vector2i = Vector2i(9, 11)
const EVENT_RED_IN_MT_SILVER: int = 1890


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_warp_chain(
			data, game_id, SILVER_CAVE_ROOM_1 if crystal else SILVER_CAVE_ROOM_1_GOLD_SILVER
		)
		_verify_connections(data, game_id)
		_verify_oaks_lab(data, game_id)
		_verify_gate(data, game_id)
		_verify_silver_cave_outside(data, game_id, crystal)
		_verify_pokecenter(data, game_id)
		_verify_rooms(
			data, game_id, SILVER_CAVE_ROOM_1 if crystal else SILVER_CAVE_ROOM_1_GOLD_SILVER
		)


## Every door on the leg, by the warp it stands on and the cell it lands on.
func _verify_warp_chain(data: GameData, game_id: StringName, room_1: int) -> void:
	for leg: Array in _warp_chain(room_1):
		var label: String = leg[0]
		var world: Gen2WorldAPI = _open(data, int(leg[1]), int(leg[2]), leg[3])
		if world == null:
			continue
		var warp: Dictionary = world.warp_at(leg[3])
		if not _r.check(
			int(warp.get("map_group", -1)) == int(leg[4])
				and int(warp.get("map_number", -1)) == int(leg[5]),
			"%s: %s reaches %d/%d, not the pinned %d/%d." % [
				game_id, label,
				int(warp.get("map_group", -1)), int(warp.get("map_number", -1)),
				int(leg[4]), int(leg[5]),
			]
		):
			continue
		_r.check(
			int(warp.get("destination", -1)) == int(leg[6]),
			"%s: %s targets warp %d, not the pinned %d." % [
				game_id, label, int(warp.get("destination", -1)), int(leg[6]),
			]
		)
	print("%s warps: %d doors from Viridian Gym to Silver Cave Room 3." % [
		game_id, _warp_chain(room_1).size(),
	])


## The two plain connections, each proved by the map its region crosses onto.
func _verify_connections(data: GameData, game_id: StringName) -> void:
	for leg: Array in CONNECTIONS:
		var label: String = leg[0]
		var start: Vector2i = leg[3]
		var world: Gen2WorldAPI = _open(data, int(leg[1]), int(leg[2]), start)
		if world == null:
			continue
		var crossing: Dictionary = _crossing(world, _region(world, start), String(leg[4]))
		_r.check(
			int(crossing.get("map_group", -1)) == int(leg[5])
				and int(crossing.get("map_number", -1)) == int(leg[6]),
			"%s: %s's %s edge reaches %d/%d, not the pinned %d/%d." % [
				game_id, label, String(leg[4]),
				int(crossing.get("map_group", -1)), int(crossing.get("map_number", -1)),
				int(leg[5]), int(leg[6]),
			]
		)
	print("%s connections: Viridian west onto Route 22, Route 28 west onto Silver Cave Outside." % game_id)


## Pallet Town's lab door reached on foot from Route 1, and Oak inside it.
func _verify_oaks_lab(data: GameData, game_id: StringName) -> void:
	var town: Gen2WorldAPI = _open(data, PALLET_GROUP, PALLET_TOWN, PALLET_LANDING)
	if town != null:
		_r.check(
			_region(town, PALLET_LANDING).has(OAKS_LAB_DOOR),
			"%s: Pallet's lab door at %s is not reachable from the north edge." % [
				game_id, OAKS_LAB_DOOR,
			]
		)
	var world: Gen2WorldAPI = _open(data, PALLET_GROUP, OAKS_LAB, OAKS_LAB_LANDING)
	if world == null:
		return
	var region: Dictionary = _region(world, OAKS_LAB_LANDING)
	_r.check(
		region.has(OAK_FACE) and world.object_at(OAK_CELL) != null,
		"%s: Oak on %s is not faced from %s." % [game_id, OAK_CELL, OAK_FACE]
	)
	# Oak's own object carries no hide flag, so the lab is the same before and
	# after the sixteenth badge: only his script branches.
	var sealed := Gen2WorldState.new()
	sealed.set_event_flag(EVENT_OPENED_MT_SILVER)
	var opened: Gen2WorldAPI = _open(data, PALLET_GROUP, OAKS_LAB, OAKS_LAB_LANDING, sealed)
	if opened != null:
		_r.check(
			opened.visible_objects().size() == world.visible_objects().size(),
			"%s: EVENT_OPENED_MT_SILVER changes Oak's lab objects." % game_id
		)
	print("%s oak's lab: a %d-cell room, Oak faced from below, nothing behind a flag." % [
		game_id, region.size(),
	])


## The gate, whose two arms are each shut by a black belt standing in the one
## cell that joins them to the corridor. Both flags are needed to walk Route 22
## to Route 28, and the walked route sets EVENT_FOUGHT_SNORLAX in Vermilion long
## before it reaches Oak.
func _verify_gate(data: GameData, game_id: StringName) -> void:
	# [label, the flags set, the crossings that must work, the ones that must not].
	for case: Array in [
		["a new gate", [], [[GATE_ROUTE_26_DOOR, GATE_VICTORY_ROAD_DOOR]],
			[[GATE_LANDING, GATE_WEST_DOOR], [GATE_LANDING, GATE_VICTORY_ROAD_DOOR],
				[GATE_ROUTE_26_DOOR, GATE_WEST_DOOR]]],
		["the Snorlax fought", [EVENT_FOUGHT_SNORLAX],
			[[GATE_LANDING, GATE_VICTORY_ROAD_DOOR]],
			[[GATE_LANDING, GATE_WEST_DOOR], [GATE_ROUTE_26_DOOR, GATE_WEST_DOOR]]],
		["Mt. Silver opened", [EVENT_OPENED_MT_SILVER],
			[[GATE_ROUTE_26_DOOR, GATE_WEST_DOOR]], [[GATE_LANDING, GATE_WEST_DOOR]]],
		["both", [EVENT_FOUGHT_SNORLAX, EVENT_OPENED_MT_SILVER],
			[[GATE_LANDING, GATE_WEST_DOOR]], []],
	]:
		var state := Gen2WorldState.new()
		for flag: int in case[1] as Array:
			state.set_event_flag(flag)
		var world: Gen2WorldAPI = _open(
			data, VIRIDIAN_GROUP, VICTORY_ROAD_GATE, GATE_LANDING, state
		)
		if world == null:
			continue
		_r.check(
			world.visible_objects().size() == 3 - (case[1] as Array).size(),
			"%s: with %s the gate shows %d objects, not %d." % [
				game_id, String(case[0]), world.visible_objects().size(),
				3 - (case[1] as Array).size(),
			]
		)
		for pair: Array in case[2] as Array:
			_r.check(
				_region(world, pair[0]).has(pair[1]),
				"%s: with %s the gate does not join %s to %s." % [
					game_id, String(case[0]), pair[0], pair[1],
				]
			)
		for pair: Array in case[3] as Array:
			_r.check(
				not _region(world, pair[0]).has(pair[1]),
				"%s: with %s the gate already joins %s to %s." % [
					game_id, String(case[0]), pair[0], pair[1],
				]
			)

	var open := Gen2WorldState.new()
	open.set_event_flag(EVENT_FOUGHT_SNORLAX)
	open.set_event_flag(EVENT_OPENED_MT_SILVER)
	var crossed: Gen2WorldAPI = _open(
		data, VIRIDIAN_GROUP, VICTORY_ROAD_GATE, GATE_LANDING, open
	)
	if crossed == null:
		return
	# The badge-check coord event is spent by the time the leg arrives, but the
	# walk must not need its cell either, so it is never re-dispatched.
	_r.check(
		not _path_cells(crossed, GATE_LANDING, GATE_WEST_DOOR).has(GATE_BADGE_CHECK),
		"%s: the gate cannot be crossed without stepping on %s." % [game_id, GATE_BADGE_CHECK]
	)
	var shut: Gen2WorldAPI = _open(data, VIRIDIAN_GROUP, VICTORY_ROAD_GATE, GATE_LANDING)
	if shut != null:
		for cell: Vector2i in [GATE_LEFT_BLACK_BELT, GATE_RIGHT_BLACK_BELT]:
			_r.check(
				shut.object_at(cell) != null and crossed.object_at(cell) == null,
				"%s: %s is not a black belt cell that both flags clear." % [game_id, cell]
			)
	print("%s gate: two arms, each shut by one black belt standing in the one cell that joins it." % game_id)


## Silver Cave Outside: the flypoint its map callback sets, and the two doors.
func _verify_silver_cave_outside(data: GameData, game_id: StringName, crystal: bool) -> void:
	var route: Gen2WorldAPI = _open(data, SILVER_GROUP, ROUTE_28, ROUTE_28_LANDING)
	if route != null:
		_r.check(
			_region(route, ROUTE_28_LANDING).size() > 0,
			"%s: Route 28's gate landing at %s is not walkable." % [game_id, ROUTE_28_LANDING]
		)
	var world: Gen2WorldAPI = _open(data, SILVER_GROUP, SILVER_CAVE_OUTSIDE, SILVER_CAVE_MOUTH)
	if world == null:
		return
	var flag: int = ENGINE_FLYPOINT_SILVER_CAVE if crystal else ENGINE_FLYPOINT_SILVER_CAVE - 1
	_r.check(
		world.state.is_engine_flag_active(flag),
		"%s: SilverCaveOutsideFlypointCallback did not set engine flag %d." % [game_id, flag]
	)
	var region: Dictionary = _region(world, SILVER_CAVE_MOUTH)
	for cell: Vector2i in [SILVER_CAVE_OUTSIDE_POKECENTER_DOOR, SILVER_CAVE_MOUTH]:
		_r.check(
			region.has(cell),
			"%s: Silver Cave Outside does not reach %s." % [game_id, cell]
		)
	print("%s silver cave outside: a %d-cell region holding both doors, flypoint %d." % [
		game_id, region.size(), flag,
	])


func _verify_pokecenter(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(
		data, SILVER_GROUP, SILVER_CAVE_POKECENTER_1F, POKECENTER_LANDING
	)
	if world == null:
		return
	var region: Dictionary = _region(world, POKECENTER_LANDING)
	_r.check(
		world.object_at(NURSE_CELL) != null,
		"%s: %s is not the nurse's cell." % [game_id, NURSE_CELL]
	)
	# The counter tile below her is not walkable, so the nurse is talked to from
	# a cell placed directly rather than walked to, the way every other
	# Pokemon Center on the route is.
	_r.check(
		not region.has(NURSE_FACE),
		"%s: %s is walkable, so the counter is not a counter." % [game_id, NURSE_FACE]
	)
	print("%s mt. silver pokecenter: a %d-cell room, the nurse behind her counter on %s." % [
		game_id, region.size(), NURSE_CELL,
	])


## The three rooms. Each is one region, which is what lets the leg warp straight
## through without a hand-named intermediate cell.
func _verify_rooms(data: GameData, game_id: StringName, room_1: int) -> void:
	for room: Array in SILVER_CAVE_ROOMS:
		var label: String = room[0]
		var entry: Vector2i = room[2]
		var target: Vector2i = room[3]
		var world: Gen2WorldAPI = _open(data, DUNGEONS_GROUP, room_1 + int(room[1]), entry)
		if world == null:
			continue
		var region: Dictionary = _region(world, entry)
		_r.check(
			region.has(target),
			"%s: Silver Cave %s does not reach %s from %s." % [
				game_id, label, target, entry,
			]
		)
		print("%s silver cave %s: %d cells from %s, reaching %s." % [
			game_id, label, region.size(), entry, target,
		])

	# Red is hidden by his own flag, which a new game sets and only the Hall of
	# Fame clears (engine/events/std_scripts.asm, maps/HallOfFame.asm).
	var room_3: Gen2WorldAPI = _open(
		data, DUNGEONS_GROUP, room_1 + 2, Vector2i(9, 33)
	)
	if room_3 == null:
		return
	_r.check(
		room_3.object_at(RED_CELL) != null,
		"%s: %s is not Red's cell." % [game_id, RED_CELL]
	)
	_r.check(
		room_3.visible_objects().size() == 1,
		"%s: Silver Cave Room 3 shows %d objects with the flag clear, not one." % [
			game_id, room_3.visible_objects().size(),
		]
	)
	var before := Gen2WorldState.new()
	before.set_event_flag(EVENT_RED_IN_MT_SILVER)
	var empty: Gen2WorldAPI = _open(
		data, DUNGEONS_GROUP, room_1 + 2, Vector2i(9, 33), before
	)
	if empty != null:
		_r.check(
			empty.visible_objects().is_empty(),
			"%s: Room 3 is not empty while EVENT_RED_IN_MT_SILVER is set." % game_id
		)
	print("%s silver cave red: one object on %s, gone behind EVENT_RED_IN_MT_SILVER." % [
		game_id, RED_CELL,
	])


## The map [param region] crosses onto over [param axis], as the first edge cell
## in it that really connects. Empty when the region reaches no such edge.
func _crossing(world: Gen2WorldAPI, region: Dictionary, axis: String) -> Dictionary:
	var size: Vector2i = world.map_size_cells()
	var direction: Vector2i = {
		"north": Vector2i.UP, "south": Vector2i.DOWN,
		"west": Vector2i.LEFT, "east": Vector2i.RIGHT,
	}[axis]
	for index: int in (size.y if axis in ["west", "east"] else size.x):
		var edge: Vector2i = Vector2i(index, 0) if axis == "north" \
			else Vector2i(index, size.y - 1) if axis == "south" \
			else Vector2i(0, index) if axis == "west" \
			else Vector2i(size.x - 1, index)
		if not region.has(edge):
			continue
		world.player_cell = edge
		var target: Dictionary = world.connection_target(edge, direction)
		if bool(target.get("ok", false)):
			target["edge"] = edge
			return target
	return {}


## One shortest walk from [param start] to [param goal], as the cells it steps
## on. Empty when the goal is in another region.
func _path_cells(world: Gen2WorldAPI, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var came_from: Dictionary = {start: start}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		if cell == goal:
			var path: Array[Vector2i] = []
			var step: Vector2i = goal
			while step != start:
				path.append(step)
				step = came_from[step]
			return path
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			var face: int = Gen2WorldCollision.face_mask_for_direction(direction)
			if face != 0 and (world.tile_permissions_at(cell) & face) != 0:
				continue
			if not world.can_walk_to(next) or came_from.has(next):
				continue
			came_from[next] = cell
			frontier.append(next)
	return []


func _open(
	data: GameData, group: int, number: int, cell: Vector2i, state: Gen2WorldState = null
) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, group, number, cell, state if state != null else Gen2WorldState.new()
	)
	if world == null:
		_r.fail("map %d/%d is missing." % [group, number])
		return null
	var _entry: Array = world.dispatch_map_entry()
	return world


## Ledge hops included, the way tools/checks/cinnabar.gd walks.
func _region(world: Gen2WorldAPI, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	var size: Vector2i = world.map_size_cells()
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			var face: int = Gen2WorldCollision.face_mask_for_direction(direction)
			var walled: bool = face != 0 and (world.tile_permissions_at(cell) & face) != 0
			if walled or not world.can_walk_to(next):
				if not Gen2WorldCollision.allows_hop(world.collision_code_at(cell), direction):
					continue
				next = cell + direction * 2
				if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
					continue
			if seen.has(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen
