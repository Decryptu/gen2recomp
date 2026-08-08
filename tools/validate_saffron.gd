extends SceneTree

## Verifies the way into Saffron City and its gym's warp maze against freshly
## imported real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## maps/SaffronCity.asm, maps/SaffronGym.asm, maps/Route6.asm,
## maps/Route6SaffronGate.asm and data/maps/attributes.asm. The city, the gym and
## the gate are byte identical between the pins; Route 6 differs only in the two
## extra Pokefans Crystal puts on (9,12) and (10,12), both sight range 0, so
## nothing here is profile split.
##
## Two things are worth pinning. Saffron has a real south connection to Route 6,
## but the city's own south row is wall everywhere Route 6's north edge aligns
## to, so `ROUTE_6_SAFFRON_GATE` is the only way in, the way Route 31's gate is
## into Violet. And Saffron Gym is nine rooms with no walkable path between them,
## joined only by fifteen pairs of self-warps: Sabrina's room holds exactly one
## pad and exactly one pad reaches it, so the way in is a fixed chain.
##
##   Godot --headless --path . -s res://tools/validate_saffron.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm.
const VERMILION_GROUP: int = 12
const ROUTE_6: int = 1
const ROUTE_6_SAFFRON_GATE: int = 12
const SAFFRON_GROUP: int = 25
const SAFFRON_CITY: int = 2
const SAFFRON_GYM: int = 4

const GYM_SIZE: Vector2i = Vector2i(20, 18)
const GYM_ROOMS: int = 9

## `maps/Route6SaffronGate.asm`: the Route 6 door and the pair onto the city.
const ROUTE_6_GATE_DOOR: Vector2i = Vector2i(6, 1)
const GATE_TO_CITY: Array[Vector2i] = [Vector2i(4, 0), Vector2i(5, 0)]
const CITY_FROM_GATE: Array[Vector2i] = [Vector2i(16, 33), Vector2i(17, 33)]

## `maps/SaffronGym.asm`'s own event table, warp 1 first. Warps 1 and 2 leave for
## the city; every other warp is a self-warp naming another warp's id.
const GYM_EXITS: Array[Vector2i] = [Vector2i(8, 17), Vector2i(9, 17)]
const GYM_PAD_COUNT: int = 30

## The entrance room's only pad, and the chain it starts. Each entry is the pad
## stepped on and the cell it lands the player on.
const MAZE_CHAIN: Array[Dictionary] = [
	{"pad": Vector2i(11, 15), "landed": Vector2i(19, 17)},
	{"pad": Vector2i(15, 17), "landed": Vector2i(5, 15)},
	{"pad": Vector2i(5, 17), "landed": Vector2i(5, 11)},
	{"pad": Vector2i(1, 11), "landed": Vector2i(5, 5)},
	{"pad": Vector2i(1, 5), "landed": Vector2i(11, 9)},
]
const SABRINA: Vector2i = Vector2i(9, 8)
const SABRINA_ROOM_PAD: Vector2i = Vector2i(11, 9)

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_gate_is_the_only_way(data, game_id)
		_verify_maze_records(data, game_id)
		_drive_maze(data, game_id)
	_finish()


## Route 6's north edge is a real connection and a dead end: every walkable cell
## on it refuses the step north, so the gate carries the whole crossing.
func _verify_gate_is_the_only_way(data: GameData, game_id: StringName) -> void:
	var route: Gen2WorldAPI = _open(data, VERMILION_GROUP, ROUTE_6, ROUTE_6_GATE_DOOR)
	if route == null:
		return
	# Crossing the connection is not the question; reaching the city is. A step
	# north off Route 6's northwest corner does land on Saffron, in the sealed
	# two-by-two pocket its own southwest corner ends in, and no walk out of that
	# pocket exists. Each cell gets its own world, since a crossing moves the one
	# it was taken on.
	var reached: Array[Vector2i] = []
	for x: int in route.map_size_cells().x:
		var edge := Vector2i(x, 0)
		if not route.can_walk_to(edge):
			continue
		var attempt: Gen2WorldAPI = _open(data, VERMILION_GROUP, ROUTE_6, edge)
		if attempt == null:
			continue
		if not bool(attempt.move_result(Vector2i.UP).get("ok", false)):
			continue
		if attempt.map_id() != Vector2i(SAFFRON_GROUP, SAFFRON_CITY):
			continue
		if _region(attempt, attempt.player_cell).has(CITY_FROM_GATE[0]):
			reached.append(edge)
	_check(
		reached.is_empty(),
		"%s: Route 6's north edge walks into Saffron proper at %s." % [game_id, reached]
	)
	_check(
		route.warp_index_at(ROUTE_6_GATE_DOOR) == 2,
		"%s: %s is not Route 6's gate door." % [game_id, ROUTE_6_GATE_DOOR]
	)

	var gate: Gen2WorldAPI = _open(
		data, VERMILION_GROUP, ROUTE_6_SAFFRON_GATE, GATE_TO_CITY[0]
	)
	if gate == null:
		return
	for index: int in GATE_TO_CITY.size():
		var warp: Dictionary = gate.warp_at(GATE_TO_CITY[index])
		_check(
			int(warp.get("map_group", -1)) == SAFFRON_GROUP
				and int(warp.get("map_number", -1)) == SAFFRON_CITY,
			"%s: the gate's %s does not open onto Saffron City." % [game_id, GATE_TO_CITY[index]]
		)
	var city: Gen2WorldAPI = _open(data, SAFFRON_GROUP, SAFFRON_CITY, CITY_FROM_GATE[0])
	if city == null:
		return
	for cell: Vector2i in CITY_FROM_GATE:
		_check(
			city.warp_index_at(cell) > 0,
			"%s: %s of Saffron City is not the gate's landing." % [game_id, cell]
		)
	print("%s gate: Route 6's north edge is sealed, so the gate is the only way into Saffron." % game_id)


## The gym's nine rooms and the fifteen self-warp pairs that join them.
func _verify_maze_records(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, SAFFRON_GROUP, SAFFRON_GYM, GYM_EXITS[0])
	if world == null:
		return
	_check(
		world.map_size_cells() == GYM_SIZE,
		"%s: Saffron Gym is %s, not the pinned %s." % [game_id, world.map_size_cells(), GYM_SIZE]
	)
	var warps: Array = world.current_map.events.get("warps", [])
	_check(
		warps.size() == GYM_EXITS.size() + GYM_PAD_COUNT,
		"%s: Saffron Gym has %d warps, not the pinned %d." % [
			game_id, warps.size(), GYM_EXITS.size() + GYM_PAD_COUNT,
		]
	)

	# Every pad is one half of a bidirectional pair: warp N names M and M names N.
	var pads: Dictionary = {}
	for index: int in warps.size():
		var warp: Dictionary = warps[index]
		var cell := Vector2i(int(warp.get("x", -1)), int(warp.get("y", -1)))
		if index < GYM_EXITS.size():
			_check(
				cell == GYM_EXITS[index],
				"%s: gym warp %d is on %s, not %s." % [game_id, index + 1, cell, GYM_EXITS[index]]
			)
			continue
		if not _check(
			int(warp.get("map_group", -1)) == SAFFRON_GROUP
				and int(warp.get("map_number", -1)) == SAFFRON_GYM,
			"%s: gym warp %d leaves the map; every pad should be a self-warp." % [
				game_id, index + 1,
			]
		):
			continue
		pads[index + 1] = int(warp.get("destination", -1))
	for source: int in pads:
		var target: int = pads[source]
		_check(
			pads.has(target) and int(pads[target]) == source,
			"%s: gym pad %d names %d, which does not name it back." % [game_id, source, target]
		)

	# Nine rooms, no walkable path between any two of them.
	var rooms: Array = _rooms(world)
	_check(
		rooms.size() == GYM_ROOMS,
		"%s: Saffron Gym is %d walkable regions, not the pinned %d." % [
			game_id, rooms.size(), GYM_ROOMS,
		]
	)
	var entrance: Dictionary = _region(world, GYM_EXITS[0])
	_check(
		not entrance.has(SABRINA + Vector2i.DOWN),
		"%s: Sabrina is reachable from the gym door on foot." % game_id
	)

	# Sabrina's room holds one pad, and one pad reaches it.
	var sabrina_room: Dictionary = _region(world, SABRINA_ROOM_PAD)
	var inside: Array[int] = []
	for index: int in warps.size():
		var warp: Dictionary = warps[index]
		var cell := Vector2i(int(warp.get("x", -1)), int(warp.get("y", -1)))
		if sabrina_room.has(cell):
			inside.append(index + 1)
	_check(
		inside.size() == 1 and Vector2i(
			int((warps[inside[0] - 1] as Dictionary).get("x", -1)),
			int((warps[inside[0] - 1] as Dictionary).get("y", -1))
		) == SABRINA_ROOM_PAD,
		"%s: Sabrina's room holds pads %s, not one on %s." % [
			game_id, inside, SABRINA_ROOM_PAD,
		]
	)
	var reaching: Array[int] = []
	for source: int in pads:
		if int(pads[source]) == inside[0]:
			reaching.append(source)
	_check(
		reaching.size() == 1,
		"%s: %d pads reach Sabrina's room, not one." % [game_id, reaching.size()]
	)
	print("%s gym: %d rooms, %d self-warp pairs, and one pad into Sabrina's room." % [
		game_id, rooms.size(), pads.size() / 2,
	])


## The chain itself, driven against the real cache from the gym door.
func _drive_maze(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, SAFFRON_GROUP, SAFFRON_GYM, GYM_EXITS[0])
	if world == null:
		return
	for hop: Dictionary in MAZE_CHAIN:
		var pad: Vector2i = hop["pad"]
		if not _check(
			_region(world, world.player_cell).has(pad),
			"%s: the maze pad on %s is not in the room the player is standing in." % [game_id, pad]
		):
			return
		world.player_cell = pad
		var taken: Dictionary = world.try_warp()
		if not _check(
			bool(taken.get("ok", false)),
			"%s: the pad on %s did not fire: %s" % [game_id, pad, taken.get("reason", "")]
		):
			return
		_check(
			world.player_cell == hop["landed"],
			"%s: the pad on %s landed the player on %s, not %s." % [
				game_id, pad, world.player_cell, hop["landed"],
			]
		)
	_check(
		_region(world, world.player_cell).has(SABRINA + Vector2i.DOWN),
		"%s: the chain did not end in reach of Sabrina." % game_id
	)
	print("%s maze: the five-pad chain reaches Sabrina from the gym door." % game_id)


func _rooms(world: Gen2WorldAPI) -> Array:
	var size: Vector2i = world.map_size_cells()
	var assigned: Dictionary = {}
	var found: Array = []
	for y: int in size.y:
		for x: int in size.x:
			var start := Vector2i(x, y)
			if assigned.has(start) or not world.can_walk_to(start):
				continue
			var cells: Dictionary = _region(world, start)
			for cell: Vector2i in cells:
				assigned[cell] = true
			found.append(cells)
	return found


func _open(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell)
	if world == null:
		_fail("map %d/%d is missing." % [group, number])
		return null
	var _entry: Array = world.dispatch_map_entry()
	return world


func _region(world: Gen2WorldAPI, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if seen.has(next) or not world.can_walk_to(next, direction):
				continue
			seen[next] = true
			frontier.append(next)
	return seen


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS saffron: the gate, the gym's nine rooms and the chain to Sabrina verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL saffron: %d problems." % _failures.size())
	quit(1)
