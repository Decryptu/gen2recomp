extends SceneTree

## Verifies the walk north from Saffron to Cerulean City, and pins why the
## Cascade Badge's own errand is not reachable from there, against freshly
## imported real caches for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## maps/SaffronCity.asm, maps/Route5SaffronGate.asm, maps/Route5.asm,
## maps/CeruleanCity.asm, maps/CeruleanGym.asm, maps/Route9.asm,
## maps/Route10North.asm, maps/PowerPlant.asm and data/maps/attributes.asm.
##
## The load-bearing finding is the last one. Misty and her three swimmers all
## carry EVENT_TRAINERS_IN_CERULEAN_GYM as their hide flag and
## `InitializeEventsScript` sets it, so the gym is empty until
## `Route25MistyDate1Script` clears it; that scene is armed by the gym's own
## grunt, and the grunt by `PowerPlantManager`. So the badge waits on the Power
## Plant, and the Power Plant is not on Cerulean's side of Kanto: the city's east
## edge crosses on one cell into a fourteen-cell pocket of Route 9, whose only
## cut tree opens onto the Route 10 Pokecenter's fenced yard and nothing else,
## and the plant's own door sits in a region with no map edge at all, reached
## across two cells of water from Route 10 North's southern half. That half is
## entered from Route 10 South, which is Lavender's own connection.
##
##   Godot --headless --path . -s res://tools/validate_cerulean.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm: the CERULEAN group is 7, SAFFRON 25, LAVENDER 18.
const CERULEAN_GROUP: int = 7
const CERULEAN_CITY: int = 17
const CERULEAN_GYM: int = 6
const POWER_PLANT: int = 10
const ROUTE_9: int = 13
const ROUTE_10_NORTH: int = 14
const SAFFRON_GROUP: int = 25
const SAFFRON_CITY: int = 2
const ROUTE_5: int = 1
const ROUTE_5_SAFFRON_GATE: int = 14
const LAVENDER_GROUP: int = 18
const ROUTE_10_SOUTH: int = 3
const LAVENDER_TOWN: int = 4

## `maps/SaffronCity.asm` warp 9, and the gate cells it names.
const SAFFRON_GATE_DOOR: Vector2i = Vector2i(18, 3)
const GATE_FROM_CITY: Vector2i = Vector2i(4, 7)
const GATE_TO_ROUTE: Vector2i = Vector2i(4, 0)
const ROUTE_5_FROM_GATE: Vector2i = Vector2i(8, 17)

## `maps/CeruleanCity.asm` warp 5, and the one cell its east edge crosses on.
const CERULEAN_GYM_DOOR: Vector2i = Vector2i(30, 23)
const CERULEAN_GYM_APPROACH: Vector2i = Vector2i(30, 24)
const CERULEAN_EAST_EDGE: Vector2i = Vector2i(39, 22)
const ROUTE_9_FROM_CERULEAN: Vector2i = Vector2i(0, 4)

## Route 9's entry pocket, its one blocking tree, and what cutting it opens.
## $12 is CheckCutCollision's tree; the four grass codes on this route are
## LAND_TILE and block nothing.
const COLL_CUT_TREE: int = 0x12
const BADGE_HIVE: int = 1
const ROUTE_9_POCKET_CELLS: int = 14
const ROUTE_9_TREE: Vector2i = Vector2i(5, 8)
const ROUTE_9_TREE_APPROACH: Vector2i = Vector2i(4, 8)
const ROUTE_9_OPENED_CELLS: int = 368
const ROUTE_9_SOUTH_CROSSING: Vector2i = Vector2i(54, 17)

## Route 10 North: the yard that crossing lands in, and the Pokecenter door that
## is all it holds.
const ROUTE_10_FROM_ROUTE_9: Vector2i = Vector2i(14, 0)
const POKECENTER_YARD_CELLS: int = 37
const ROUTE_10_POKECENTER_DOOR: Vector2i = Vector2i(11, 1)

## The plant's own door, the cell it is entered from, and the water between that
## cell and the southern half of the map.
const POWER_PLANT_DOOR: Vector2i = Vector2i(3, 9)
const POWER_PLANT_APPROACH: Vector2i = Vector2i(3, 10)
const POWER_PLANT_POCKET_CELLS: int = 28
const ROUTE_10_SOUTH_HALF: Vector2i = Vector2i(0, 17)
const ROUTE_10_SOUTH_HALF_CELLS: int = 153
const POWER_PLANT_SHORE_CELLS: int = 13

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_route_5_gate(data, game_id)
		_verify_cerulean(data, game_id)
		_verify_route_9_dead_end(data, game_id)
		_verify_power_plant_is_water_locked(data, game_id)
	_finish()


## Saffron's north exit is a gate building the way its south and west ones are,
## and Route 5 connects straight onto Cerulean.
func _verify_route_5_gate(data: GameData, game_id: StringName) -> void:
	var city: Gen2WorldAPI = _open(data, SAFFRON_GROUP, SAFFRON_CITY, SAFFRON_GATE_DOOR)
	if city == null:
		return
	var warp: Dictionary = city.warp_at(SAFFRON_GATE_DOOR)
	_check(
		int(warp.get("map_group", -1)) == SAFFRON_GROUP
			and int(warp.get("map_number", -1)) == ROUTE_5_SAFFRON_GATE,
		"%s: Saffron's %s does not open onto the Route 5 gate." % [game_id, SAFFRON_GATE_DOOR]
	)
	var gate: Gen2WorldAPI = _open(data, SAFFRON_GROUP, ROUTE_5_SAFFRON_GATE, GATE_FROM_CITY)
	if gate == null:
		return
	_check(
		_region(gate, GATE_FROM_CITY).has(GATE_TO_ROUTE),
		"%s: the Route 5 gate's two doors are not joined on foot." % game_id
	)
	var far: Dictionary = gate.warp_at(GATE_TO_ROUTE)
	_check(
		int(far.get("map_group", -1)) == SAFFRON_GROUP
			and int(far.get("map_number", -1)) == ROUTE_5,
		"%s: the gate's %s does not open onto Route 5." % [game_id, GATE_TO_ROUTE]
	)

	var route: Gen2WorldAPI = _open(data, SAFFRON_GROUP, ROUTE_5, ROUTE_5_FROM_GATE)
	if route == null:
		return
	var crossed: Array = _crossings(data, SAFFRON_GROUP, ROUTE_5, route, "north", ROUTE_5_FROM_GATE)
	_check(
		not crossed.is_empty(),
		"%s: Route 5's north edge does not reach Cerulean City." % game_id
	)
	for entry: Array in crossed:
		_check(
			entry[1] == Vector2i(CERULEAN_GROUP, CERULEAN_CITY),
			"%s: Route 5's %s crosses onto %s, not Cerulean." % [game_id, entry[0], entry[1]]
		)
	print("%s route 5: a gate building out of Saffron and an open connection into Cerulean." % game_id)


## The city itself: its gym door, its flypoint callback, and the single cell its
## east edge crosses on.
func _verify_cerulean(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, CERULEAN_GROUP, CERULEAN_CITY, CERULEAN_GYM_APPROACH)
	if world == null:
		return
	_check(
		world.warp_index_at(CERULEAN_GYM_DOOR) == 5,
		"%s: %s is not Cerulean's gym door." % [game_id, CERULEAN_GYM_DOOR]
	)
	var city: Dictionary = _region(world, CERULEAN_GYM_APPROACH)
	var east: Array[Vector2i] = []
	for y: int in world.map_size_cells().y:
		var edge := Vector2i(world.map_size_cells().x - 1, y)
		if city.has(edge):
			east.append(edge)
	_check(
		east == [CERULEAN_EAST_EDGE],
		"%s: Cerulean's east edge is walkable on %s, not %s alone." % [
			game_id, east, CERULEAN_EAST_EDGE,
		]
	)
	var crossed: Array = _crossings(
		data, CERULEAN_GROUP, CERULEAN_CITY, world, "east", CERULEAN_GYM_APPROACH
	)
	_check(
		crossed.size() == 1 and crossed[0][1] == Vector2i(CERULEAN_GROUP, ROUTE_9)
			and crossed[0][2] == ROUTE_9_FROM_CERULEAN,
		"%s: Cerulean crosses east as %s, not once onto Route 9's %s." % [
			game_id, crossed, ROUTE_9_FROM_CERULEAN,
		]
	)

	# The gym's own four hide-flagged objects, which is what makes the badge an
	# errand rather than a walk.
	var gym: Gen2WorldAPI = _open(data, CERULEAN_GROUP, CERULEAN_GYM, Vector2i(4, 15))
	if gym == null:
		return
	var hidden: int = 0
	for row: Dictionary in gym.current_map.events.get("objects", []):
		if int(row.get("event_flag", -1)) == 1903:
			hidden += 1
	_check(
		hidden == 5,
		"%s: %d Cerulean Gym objects hide behind EVENT_TRAINERS_IN_CERULEAN_GYM, not 5." % [
			game_id, hidden,
		]
	)
	print("%s cerulean: one east crossing, and a gym of five objects behind one hide flag." % game_id)


## Route 9's entry pocket, and the fact that its one cut tree opens onto a yard
## holding nothing but the Route 10 Pokecenter.
func _verify_route_9_dead_end(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, CERULEAN_GROUP, ROUTE_9, ROUTE_9_FROM_CERULEAN)
	if world == null:
		return
	var pocket: Dictionary = _region(world, ROUTE_9_FROM_CERULEAN)
	_check(
		pocket.size() == ROUTE_9_POCKET_CELLS,
		"%s: Route 9's entry pocket is %d cells, not the pinned %d." % [
			game_id, pocket.size(), ROUTE_9_POCKET_CELLS,
		]
	)
	_check(
		pocket.has(ROUTE_9_TREE_APPROACH)
			and world.collision_code_at(ROUTE_9_TREE) == COLL_CUT_TREE,
		"%s: %s is not a cut tree the entry pocket can face." % [game_id, ROUTE_9_TREE]
	)

	world.state.set_engine_flag(Gen2WorldState.badge_flag(
		BADGE_HIVE, Gen2WorldState.is_crystal_profile(data)
	))
	world.player_cell = ROUTE_9_TREE_APPROACH
	world.player_facing = Gen2WorldSprite.FACING_RIGHT
	if not _check(
		bool(world.cut_request().get("ok", false))
			and bool(world.complete_cut().get("ok", false)),
		"%s: Route 9's tree refused the cut." % game_id
	):
		return
	var opened: Dictionary = _region(world, ROUTE_9_TREE_APPROACH)
	_check(
		opened.size() == ROUTE_9_OPENED_CELLS,
		"%s: cutting Route 9's tree opens %d cells, not the pinned %d." % [
			game_id, opened.size(), ROUTE_9_OPENED_CELLS,
		]
	)
	var south: Array[Vector2i] = []
	for x: int in world.map_size_cells().x:
		var edge := Vector2i(x, world.map_size_cells().y - 1)
		if opened.has(edge):
			south.append(edge)
	_check(
		south == [ROUTE_9_SOUTH_CROSSING],
		"%s: the opened region reaches south edge %s, not %s alone." % [
			game_id, south, ROUTE_9_SOUTH_CROSSING,
		]
	)

	# And what that crossing lands on is a yard with one door in it.
	var yard: Gen2WorldAPI = _open(data, CERULEAN_GROUP, ROUTE_10_NORTH, ROUTE_10_FROM_ROUTE_9)
	if yard == null:
		return
	var cells: Dictionary = _region(yard, ROUTE_10_FROM_ROUTE_9)
	_check(
		cells.size() == POKECENTER_YARD_CELLS,
		"%s: the Route 10 Pokecenter yard is %d cells, not the pinned %d." % [
			game_id, cells.size(), POKECENTER_YARD_CELLS,
		]
	)
	_check(
		yard.warp_index_at(ROUTE_10_POKECENTER_DOOR) == 1,
		"%s: %s is not the Route 10 Pokecenter door." % [game_id, ROUTE_10_POKECENTER_DOOR]
	)
	_check(
		not cells.has(POWER_PLANT_APPROACH),
		"%s: the Pokecenter yard reaches the Power Plant on foot." % game_id
	)
	print("%s route 9: a %d-cell pocket, one tree, and a yard with one Pokecenter in it." % [
		game_id, ROUTE_9_POCKET_CELLS,
	])


## The plant's door sits in a region with no map edge. It is entered across two
## cells of water from the southern half of Route 10 North, which is Route 10
## South's own connection and therefore Lavender's side of Kanto.
func _verify_power_plant_is_water_locked(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, CERULEAN_GROUP, ROUTE_10_NORTH, ROUTE_10_SOUTH_HALF)
	if world == null:
		return
	_check(
		world.warp_index_at(POWER_PLANT_DOOR) == 2,
		"%s: %s is not the Power Plant door." % [game_id, POWER_PLANT_DOOR]
	)
	var pocket: Dictionary = _region(world, POWER_PLANT_APPROACH)
	_check(
		pocket.size() == POWER_PLANT_POCKET_CELLS,
		"%s: the Power Plant's own region is %d cells, not the pinned %d." % [
			game_id, pocket.size(), POWER_PLANT_POCKET_CELLS,
		]
	)
	var size: Vector2i = world.map_size_cells()
	var edges: Array[Vector2i] = []
	for x: int in size.x:
		for edge: Vector2i in [Vector2i(x, 0), Vector2i(x, size.y - 1)]:
			if pocket.has(edge):
				edges.append(edge)
	for y: int in size.y:
		for edge: Vector2i in [Vector2i(0, y), Vector2i(size.x - 1, y)]:
			if pocket.has(edge):
				edges.append(edge)
	_check(
		edges.is_empty(),
		"%s: the Power Plant's region touches map edge %s; it should touch none." % [
			game_id, edges,
		]
	)

	var southern: Dictionary = _region(world, ROUTE_10_SOUTH_HALF)
	_check(
		southern.size() == ROUTE_10_SOUTH_HALF_CELLS,
		"%s: Route 10 North's southern half is %d cells, not the pinned %d." % [
			game_id, southern.size(), ROUTE_10_SOUTH_HALF_CELLS,
		]
	)
	# The crossing itself: a shore cell whose two cells of water end on the pocket.
	var shores: Array[Vector2i] = []
	for cell: Vector2i in southern:
		if world.collision_permission_at(cell + Vector2i.UP) != Gen2WorldCollision.WATER_TILE:
			continue
		if pocket.has(cell + Vector2i.UP * 3):
			shores.append(cell)
	_check(
		shores.size() == POWER_PLANT_SHORE_CELLS,
		"%s: %d shore cells surf onto the Power Plant's region, not the pinned %d." % [
			game_id, shores.size(), POWER_PLANT_SHORE_CELLS,
		]
	)
	# And the southern half is Route 10 South's, which is Lavender's connection.
	var crossed: Array = _crossings(
		data, CERULEAN_GROUP, ROUTE_10_NORTH, world, "south", ROUTE_10_SOUTH_HALF
	)
	_check(
		not crossed.is_empty(),
		"%s: Route 10 North's southern half does not reach Route 10 South." % game_id
	)
	for entry: Array in crossed:
		_check(
			entry[1] == Vector2i(LAVENDER_GROUP, ROUTE_10_SOUTH),
			"%s: %s crosses south onto %s, not Route 10 South." % [game_id, entry[0], entry[1]]
		)
	var lavender: Gen2WorldAPI = _open(data, LAVENDER_GROUP, ROUTE_10_SOUTH, Vector2i(6, 2))
	if lavender == null:
		return
	var joins: Array[StringName] = []
	for connection: Dictionary in lavender.current_map.connections:
		if int(connection.get("map_group", -1)) == LAVENDER_GROUP \
			and int(connection.get("map_number", -1)) == LAVENDER_TOWN:
			joins.append(StringName(connection.get("direction", "")))
	_check(
		joins == [&"south"],
		"%s: Route 10 South joins Lavender %s, not south alone." % [game_id, joins]
	)
	print("%s power plant: a %d-cell island reached by %d shore cells, from Lavender's side." % [
		game_id, pocket.size(), shores.size(),
	])


func _open(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell, Gen2WorldState.new())
	if world == null:
		_fail("map %d/%d is missing." % [group, number])
		return null
	var _entry: Array = world.dispatch_map_entry()
	return world


## Every crossing off [param axis] that a walk from [param start] can take, as
## [edge cell, landed map, landed cell]. Each attempt gets its own world, since
## a crossing moves the one it was taken on.
func _crossings(
	data: GameData, group: int, number: int, world: Gen2WorldAPI,
	axis: String, start: Vector2i,
) -> Array:
	var size: Vector2i = world.map_size_cells()
	var direction: Vector2i = {
		"north": Vector2i.UP, "south": Vector2i.DOWN,
		"west": Vector2i.LEFT, "east": Vector2i.RIGHT,
	}[axis]
	var region: Dictionary = _region(world, start)
	var out: Array = []
	for index: int in (size.y if axis in ["west", "east"] else size.x):
		var edge: Vector2i = Vector2i(index, 0) if axis == "north" \
			else Vector2i(index, size.y - 1) if axis == "south" \
			else Vector2i(0, index) if axis == "west" \
			else Vector2i(size.x - 1, index)
		if not region.has(edge):
			continue
		var attempt: Gen2WorldAPI = _open(data, group, number, edge)
		if attempt == null:
			continue
		if bool(attempt.move_result(direction).get("ok", false)):
			out.append([edge, attempt.map_id(), attempt.player_cell])
	return out


## Ledge hops included, mirroring `tools/preview_world_story.gd`'s
## _reachable_step(): a region drawn without them would claim walls that a real
## walk can cross, which is exactly the mistake these counts are here to catch.
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


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS cerulean: the Route 5 gate, the city's one east crossing and the water-locked Power Plant verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL cerulean: %d problems." % _failures.size())
	quit(1)
