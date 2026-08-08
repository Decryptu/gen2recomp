extends SceneTree

## Verifies the walk back from Fuchsia City to Vermilion, through Diglett's Cave
## onto Route 2, and north to Pewter Gym, against freshly imported real caches
## for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## data/maps/attributes.asm, maps/Route11.asm, maps/VermilionCity.asm,
## maps/DiglettsCave.asm, maps/Route2.asm, maps/PewterCity.asm and
## maps/PewterGym.asm.
##
## Three findings carry the leg. The way back to Vermilion is five plain
## connections with one gate at the start, not the walk through Lavender and
## Saffron the route came by, because Route 12 connects west onto Route 11 and
## Route 11 declares no warps at all. The Route 11 crossing lands inside the
## eight-cell pocket the Snorlax's own two-by-two body seals off Vermilion's
## east edge, which is why SnorlaxAwake lists five proximity coordinates rather
## than the two the port side can stand on. And Diglett's Cave is three
## disjoint regions joined by two ladders, so it is crossed by warps rather than
## walked.
##
## The Snorlax chain itself, the Route 2 cut and their counts belong to
## tools/validate_radio.gd and are not repeated here.
##
##   Godot --headless --path . -s res://tools/validate_pewter.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm. Only Diglett's Cave splits between the profiles.
const FUCHSIA_GROUP: int = 17
const FUCHSIA_CITY: int = 5
const ROUTE_13: int = 1
const ROUTE_14: int = 2
const ROUTE_15: int = 3
const ROUTE_15_FUCHSIA_GATE: int = 13
const LAVENDER_GROUP: int = 18
const ROUTE_12: int = 2
const VERMILION_GROUP: int = 12
const ROUTE_11: int = 2
const VERMILION_CITY: int = 3
const DUNGEONS_GROUP: int = 3
const DIGLETTS_CAVE: int = 84
const DIGLETTS_CAVE_GOLD_SILVER: int = 75
const VIRIDIAN_GROUP: int = 23
const ROUTE_2: int = 1
const PEWTER_GROUP: int = 14
const PEWTER_CITY: int = 2
const PEWTER_GYM: int = 4

## The way out of Fuchsia: `maps/FuchsiaCity.asm` warp 8 into the gate, and the
## gate's own east door onto Route 15.
const CITY_GATE_DOOR: Vector2i = Vector2i(37, 22)
const GATE_FROM_CITY: Vector2i = Vector2i(0, 4)
const GATE_TO_ROUTE: Vector2i = Vector2i(9, 4)

## The chain back, as [label, group, number, the cell it is entered on, the
## direction it leaves by, the target group and number of that crossing].
const NORTHBOUND: Array = [
	["Route 15", FUCHSIA_GROUP, ROUTE_15, Vector2i(2, 4), "east", FUCHSIA_GROUP, ROUTE_14],
	["Route 14", FUCHSIA_GROUP, ROUTE_14, Vector2i(0, 26), "north", FUCHSIA_GROUP, ROUTE_13],
	["Route 13", FUCHSIA_GROUP, ROUTE_13, Vector2i(12, 17), "north", LAVENDER_GROUP, ROUTE_12],
	["Route 12", LAVENDER_GROUP, ROUTE_12, Vector2i(14, 53), "west", VERMILION_GROUP, ROUTE_11],
	["Route 11", VERMILION_GROUP, ROUTE_11, Vector2i(39, 8), "west", VERMILION_GROUP, VERMILION_CITY],
]

## Vermilion's east pocket. `maps/VermilionCity.asm` object 4 is a BIG_OBJECT on
## (34,8), so it fills a two-by-two, and the cells east of it are cut off from
## the city until it moves.
const VERMILION_EAST_LANDING: Vector2i = Vector2i(39, 8)
const VERMILION_EAST_POCKET_CELLS: int = 8
const SNORLAX_CELL: Vector2i = Vector2i(34, 8)
## The two cells of that pocket SnorlaxAwake.ProximityCoords names, which are
## the only ones an eastbound player can talk to it from.
const EAST_PROXIMITY: Array[Vector2i] = [Vector2i(36, 8), Vector2i(36, 9)]
const DIGLETTS_CAVE_MOUTH: Vector2i = Vector2i(34, 7)

## Diglett's Cave, as [the cell a region is entered on, its size, the cell the
## region's own way on sits on]. The last leg's exit is the Route 2 door rather
## than a ladder (`maps/DiglettsCave.asm` warps 2, 6 and 3).
const CAVE_REGIONS: Array = [
	[Vector2i(3, 33), 14, Vector2i(5, 31)],
	[Vector2i(17, 33), 99, Vector2i(3, 3)],
	[Vector2i(17, 3), 15, Vector2i(15, 5)],
]
const CAVE_LANDING_ON_ROUTE_2: Vector2i = Vector2i(12, 7)

## Route 2's cut tree and the crossing behind it, both owned by
## tools/validate_radio.gd; what is checked here is only that the opened route
## really crosses onto Pewter.
const ROUTE_2_CUT_APPROACH: Vector2i = Vector2i(5, 9)
const ROUTE_2_CUT_TREE: Vector2i = Vector2i(5, 8)

## Pewter City. The south connection lands on the two-cell corridor at x=18 and
## 19, which is the only one of the three pockets along that edge that reaches
## the city at all.
const PEWTER_SOUTH_LANDING: Vector2i = Vector2i(18, 35)
const PEWTER_CITY_CELLS: int = 730
const PEWTER_SEALED_SOUTH_EDGE: Array[Vector2i] = [Vector2i(10, 35), Vector2i(30, 35)]
const PEWTER_GYM_DOOR: Vector2i = Vector2i(16, 17)
const ENGINE_FLYPOINT_PEWTER: int = 55
const ENGINE_FLYPOINT_PEWTER_GOLD_SILVER: int = 54

## The gym. `maps/PewterGym.asm` is byte identical between the pins: Brock on
## (5,1) faced from below, Camper Jerry watching three cells east along row 5,
## and the guide by the door.
const GYM_LANDING: Vector2i = Vector2i(4, 13)
const BROCK_CELL: Vector2i = Vector2i(5, 1)
const BROCK_FACE: Vector2i = Vector2i(5, 2)
const JERRY_INDEX: int = 1
const GYM_OBJECTS: int = 3

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_return_chain(data, game_id)
		_verify_vermilion_pocket(data, game_id, crystal)
		_verify_cave(data, game_id, crystal)
		_verify_route_2_crossing(data, game_id, crystal)
		_verify_pewter(data, game_id, crystal)
	_finish()


## Fuchsia's gate and the five connections back to Vermilion, each proved by the
## crossing it actually reaches rather than by its edge coordinate.
func _verify_return_chain(data: GameData, game_id: StringName) -> void:
	var city: Gen2WorldAPI = _open(data, FUCHSIA_GROUP, FUCHSIA_CITY, CITY_GATE_DOOR)
	if city != null:
		var door: Dictionary = city.warp_at(CITY_GATE_DOOR)
		_check(
			int(door.get("map_group", -1)) == FUCHSIA_GROUP
				and int(door.get("map_number", -1)) == ROUTE_15_FUCHSIA_GATE,
			"%s: Fuchsia's %s does not open onto the Route 15 gate." % [game_id, CITY_GATE_DOOR]
		)
	var gate: Gen2WorldAPI = _open(data, FUCHSIA_GROUP, ROUTE_15_FUCHSIA_GATE, GATE_FROM_CITY)
	if gate != null:
		_check(
			_region(gate, GATE_FROM_CITY).has(GATE_TO_ROUTE),
			"%s: the Fuchsia gate's two doors are not joined on foot." % game_id
		)

	for leg: Array in NORTHBOUND:
		var label: String = leg[0]
		var start: Vector2i = leg[3]
		var world: Gen2WorldAPI = _open(data, int(leg[1]), int(leg[2]), start)
		if world == null:
			continue
		var region: Dictionary = _region(world, start)
		var crossing: Dictionary = _crossing(world, region, String(leg[4]))
		_check(
			int(crossing.get("map_group", -1)) == int(leg[5])
				and int(crossing.get("map_number", -1)) == int(leg[6]),
			"%s: %s's %s edge reaches %d/%d, not the pinned %d/%d." % [
				game_id, label, leg[4],
				int(crossing.get("map_group", -1)), int(crossing.get("map_number", -1)),
				int(leg[5]), int(leg[6]),
			]
		)
		# Route 11 is the whole reason this way back is shorter than the one the
		# route came by: no warps means no gate building to walk through.
		if int(leg[2]) == ROUTE_11 and int(leg[1]) == VERMILION_GROUP:
			_check(
				world.current_map.events.get("warps", []).is_empty(),
				"%s: Route 11 declares warps, so it is gated after all." % game_id
			)
	print("%s return chain: Fuchsia's gate and five connections back to Vermilion." % game_id)


## The pocket the Route 11 crossing lands in, and what seals it.
func _verify_vermilion_pocket(data: GameData, game_id: StringName, _crystal: bool) -> void:
	var world: Gen2WorldAPI = _open(data, VERMILION_GROUP, VERMILION_CITY, VERMILION_EAST_LANDING)
	if world == null:
		return
	var snorlax: Gen2WorldObject = world.object_at(SNORLAX_CELL)
	if not _check(
		snorlax != null and snorlax.is_big_object(),
		"%s: %s is not the big Snorlax object." % [game_id, SNORLAX_CELL]
	):
		return
	var pocket: Dictionary = _region(world, VERMILION_EAST_LANDING)
	_check(
		pocket.size() == VERMILION_EAST_POCKET_CELLS,
		"%s: Vermilion's east landing is %d cells, not the pinned %d." % [
			game_id, pocket.size(), VERMILION_EAST_POCKET_CELLS,
		]
	)
	_check(
		not pocket.has(DIGLETTS_CAVE_MOUTH),
		"%s: the east pocket already reaches the cave mouth." % game_id
	)
	for cell: Vector2i in EAST_PROXIMITY:
		_check(
			pocket.has(cell),
			"%s: %s is not in the pocket the Route 11 crossing lands in." % [game_id, cell]
		)
		var faces: bool = false
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if world.object_at(cell + direction) == snorlax:
				faces = true
		_check(faces, "%s: %s does not face the Snorlax." % [game_id, cell])
	print("%s vermilion: the Route 11 crossing lands in a %d-cell pocket the Snorlax seals." % [
		game_id, pocket.size(),
	])


## Diglett's Cave: three regions, two ladders and the Route 2 door.
func _verify_cave(data: GameData, game_id: StringName, crystal: bool) -> void:
	var number: int = DIGLETTS_CAVE if crystal else DIGLETTS_CAVE_GOLD_SILVER
	for leg: Array in CAVE_REGIONS:
		var start: Vector2i = leg[0]
		var exit_cell: Vector2i = leg[2]
		var world: Gen2WorldAPI = _open(data, DUNGEONS_GROUP, number, start)
		if world == null:
			continue
		var region: Dictionary = _region(world, start)
		_check(
			region.size() == int(leg[1]),
			"%s: the cave region at %s is %d cells, not the pinned %d." % [
				game_id, start, region.size(), int(leg[1]),
			]
		)
		_check(
			region.has(exit_cell),
			"%s: the cave region at %s does not reach its own way on at %s." % [
				game_id, start, exit_cell,
			]
		)
	var last: Gen2WorldAPI = _open(data, DUNGEONS_GROUP, number, Vector2i(17, 3))
	if last != null:
		var door: Dictionary = last.warp_at(Vector2i(15, 5))
		_check(
			int(door.get("map_group", -1)) == VIRIDIAN_GROUP
				and int(door.get("map_number", -1)) == ROUTE_2,
			"%s: the cave's %s does not open onto Route 2." % [game_id, Vector2i(15, 5)]
		)
	print("%s digletts cave: three regions of 14, 99 and 15 cells, crossed by two ladders." % game_id)


## Route 2 once its northern tree is cut: the crossing behind it is Pewter's.
func _verify_route_2_crossing(data: GameData, game_id: StringName, crystal: bool) -> void:
	var state := Gen2WorldState.new()
	state.set_engine_flag(
		Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_HIVE, crystal), true
	)
	var world: Gen2WorldAPI = _open(data, VIRIDIAN_GROUP, ROUTE_2, CAVE_LANDING_ON_ROUTE_2, state)
	if world == null:
		return
	world.player_cell = ROUTE_2_CUT_APPROACH
	world.player_facing = Gen2WorldSprite.FACING_UP
	if not _check(
		bool(world.cut_request().get("ok", false))
			and bool(world.complete_cut().get("ok", false)),
		"%s: Route 2's %s did not cut." % [game_id, ROUTE_2_CUT_TREE]
	):
		return
	var region: Dictionary = _region(world, ROUTE_2_CUT_APPROACH)
	var crossing: Dictionary = _crossing(world, region, "north")
	_check(
		int(crossing.get("map_group", -1)) == PEWTER_GROUP
			and int(crossing.get("map_number", -1)) == PEWTER_CITY,
		"%s: Route 2's north edge reaches %d/%d, not Pewter." % [
			game_id,
			int(crossing.get("map_group", -1)), int(crossing.get("map_number", -1)),
		]
	)
	print("%s route 2: the cut route crosses north onto Pewter City." % game_id)


## Pewter City and its gym.
func _verify_pewter(data: GameData, game_id: StringName, crystal: bool) -> void:
	var city: Gen2WorldAPI = _open(data, PEWTER_GROUP, PEWTER_CITY, PEWTER_SOUTH_LANDING)
	if city == null:
		return
	var flypoint: int = ENGINE_FLYPOINT_PEWTER if crystal \
		else ENGINE_FLYPOINT_PEWTER_GOLD_SILVER
	_check(
		city.state.is_engine_flag_active(flypoint),
		"%s: PewterCityFlypointCallback did not set engine flag %d on arrival." % [
			game_id, flypoint,
		]
	)
	var region: Dictionary = _region(city, PEWTER_SOUTH_LANDING)
	_check(
		region.size() == PEWTER_CITY_CELLS,
		"%s: Pewter City is %d cells from %s, not the pinned %d." % [
			game_id, region.size(), PEWTER_SOUTH_LANDING, PEWTER_CITY_CELLS,
		]
	)
	_check(
		region.has(PEWTER_GYM_DOOR),
		"%s: the south landing does not reach the gym door." % game_id
	)
	# The other two pockets along the same edge go nowhere, so the crossing cell
	# is not a matter of taste.
	for cell: Vector2i in PEWTER_SEALED_SOUTH_EDGE:
		_check(
			not _region(city, cell).has(PEWTER_GYM_DOOR),
			"%s: %s reaches the gym, so the south edge is not one corridor." % [game_id, cell]
		)

	var gym: Gen2WorldAPI = _open(data, PEWTER_GROUP, PEWTER_GYM, GYM_LANDING)
	if gym == null:
		return
	_check(
		gym.current_map.events.get("objects", []).size() == GYM_OBJECTS,
		"%s: Pewter Gym has %d objects, not the pinned %d." % [
			game_id, gym.current_map.events.get("objects", []).size(), GYM_OBJECTS,
		]
	)
	var gym_region: Dictionary = _region(gym, GYM_LANDING)
	_check(
		gym_region.has(BROCK_FACE),
		"%s: Brock's approach at %s is not reachable from the door." % [game_id, BROCK_FACE]
	)
	_check(
		gym.object_at(BROCK_CELL) != null,
		"%s: %s is not Brock's cell." % [game_id, BROCK_CELL]
	)
	# Camper Jerry watches the only column that reaches Brock, so his battle is
	# owed rather than optional.
	var lines: Dictionary = _sight_lines(data, PEWTER_GROUP, PEWTER_GYM, gym_region)
	var owed: Array = []
	for index: int in lines:
		if not _region(gym, GYM_LANDING, lines[index]).has(BROCK_FACE):
			owed.append(index)
	owed.sort()
	_check(
		owed == [JERRY_INDEX],
		"%s: Pewter Gym owes sight lines %s, not the pinned [%d]." % [
			game_id, owed, JERRY_INDEX,
		]
	)
	print("%s pewter: a %d-cell city from the south corridor, and a gym that owes Jerry." % [
		game_id, region.size(),
	])


## Every cell in [param region] a trainer sees the player on, as object index to
## the set of cells.
func _sight_lines(
	data: GameData, group: int, number: int, region: Dictionary
) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in region:
		var probe: Gen2WorldAPI = _open(data, group, number, cell)
		if probe == null:
			continue
		var sight: Array = probe.dispatch_sight_events()
		if sight.is_empty():
			continue
		var index: int = int((sight[0].get("source", {}) as Dictionary).get("object_index", -1))
		if not out.has(index):
			out[index] = {}
		(out[index] as Dictionary)[cell] = true
	return out


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
		var target: Dictionary = world.connection_target(edge, direction)
		if bool(target.get("ok", false)):
			return target
	return {}


func _open(
	data: GameData, group: int, number: int, cell: Vector2i, state: Gen2WorldState = null
) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, group, number, cell, state if state != null else Gen2WorldState.new()
	)
	if world == null:
		_fail("map %d/%d is missing." % [group, number])
		return null
	var _entry: Array = world.dispatch_map_entry()
	return world


## Ledge hops included, the way tools/validate_fuchsia.gd walks. [param closed]
## cells are treated as unwalkable, which is how an owed sight line is proved.
func _region(
	world: Gen2WorldAPI, start: Vector2i, closed: Dictionary = {}
) -> Dictionary:
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
			if seen.has(next) or closed.has(next):
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
		print("PASS pewter: the return chain, the Snorlax's east pocket, Diglett's Cave, Route 2's crossing and Pewter Gym verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL pewter: %d problems." % _failures.size())
	quit(1)
