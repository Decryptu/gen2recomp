extends RefCounted

var _r: RefCounted = null

## Verifies the walk north from Saffron to Cerulean City and the way from there
## to the Power Plant, against freshly imported real caches for both command
## profiles.
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
## Plant, and the plant is not walked to: Cerulean's east edge crosses on one
## cell into a fourteen-cell pocket of Route 9 whose one cut tree opens 368 cells
## reaching a single south crossing, and what that lands in is a yard holding
## nothing but the Route 10 Pokecenter. The plant's own door sits in a region
## with no map edge and no walkable neighbour, and Route 10 North's southern half
## cannot even enter the water beside it, because row 14 is a buoy line whose own
## permission walls its north face. The way in is Route 9's river, whose shore
## the same cut opens: sixty cells of water that meet the south edge on columns
## 56 and 57 and come out in Route 10 North's own lake, one step from the
## plant's shore.
##
## The gym behind that errand is a pool. Its three swimmers stand on the water,
## and the walk to Misty cannot avoid Diana's sight line or both of the other
## two, so the badge needs approaches that cross water. They do, because
## SeenByTrainerScript is `applymovementlasttalked` and NormalStep consults no
## permission.
##
##   Godot --headless --path . -s res://tools/validate.gd -- cerulean


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

## Cerulean Gym: the door's landing, Misty and the cell she is faced from, and
## the grunt whose own scene clears him off the ladder column.
const CERULEAN_GYM_CELLS: Vector2i = Vector2i(10, 16)
const CERULEAN_GYM_LANDING: Vector2i = Vector2i(4, 15)
const MISTY_CELL: Vector2i = Vector2i(5, 3)
const MISTY_FACE: Vector2i = Vector2i(5, 4)
const EVENT_CERULEAN_GYM_ROCKET: int = 1901
const EVENT_TRAINERS_IN_CERULEAN_GYM: int = 1903
const CERULEAN_GYM_HIDDEN_OBJECTS: int = 5
## The three swimmers, as object index, cell, sight range, the cell each sees the
## player on, where its approach stops, the sight direction and its beaten flag.
## Every stopping cell is water, which is the point: the pool is what the
## approach crosses. Briana's is her own cell, since a sight distance of one
## gives TrainerWalkToPlayer an empty movement buffer.
const GYM_SWIMMERS: Array = [
	[4, Vector2i(8, 9), 3, Vector2i(5, 9), Vector2i(6, 9), Vector2i.LEFT, 1448],
	[2, Vector2i(4, 6), 3, Vector2i(7, 6), Vector2i(6, 6), Vector2i.RIGHT, 1017],
	[3, Vector2i(1, 9), 1, Vector2i(2, 9), Vector2i(1, 9), Vector2i.RIGHT, 1018],
]
## Diana's is the one sight line no walk to Misty can avoid. Parker's and
## Briana's guard the pool's two alternative columns, so shutting either leaves
## the other open while shutting both seals Misty off: one of the pair is always
## fought, whichever way round the pool the walk goes.
const GYM_SIGHT_UNAVOIDABLE: Array[int] = [2]
const GYM_SIGHT_ALTERNATIVES: Array[int] = [4, 3]

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

## The plant's own door and the cell it is entered from. The pocket both sit in
## has no map edge and no walkable neighbour, so the way in is the river.
const POWER_PLANT_DOOR: Vector2i = Vector2i(3, 9)
const POWER_PLANT_APPROACH: Vector2i = Vector2i(3, 10)
const POWER_PLANT_POCKET_CELLS: int = 28
const ROUTE_10_SOUTH_HALF: Vector2i = Vector2i(0, 17)
const ROUTE_10_SOUTH_HALF_CELLS: int = 153
## Route 10 North's row 14 is a `$b2` buoy line whose own permission walls its
## north face, so the southern half cannot enter that water at all. Every legal
## surf entry on the map is inside the plant's pocket, facing out of it.
const BUOY_ROW: int = 14
const BUOY_CODE: int = 0xB2
const BUOY_UP_WALL: int = 4
## Route 9's river, entered off the shore the cut opens, and where it comes out.
const ROUTE_9_SHORE: Vector2i = Vector2i(42, 4)
const ROUTE_9_RIVER_HEAD: Vector2i = Vector2i(42, 3)
const ROUTE_9_RIVER_CELLS: int = 60
const ROUTE_9_RIVER_MOUTH: Array[int] = [56, 57]
## Which is Route 10 North's own water, the connection offset being 20.
const ROUTE_10_LAKE_HEAD: Vector2i = Vector2i(16, 0)
const ROUTE_10_LAKE_CELLS: int = 56
const POWER_PLANT_LANDING: Vector2i = Vector2i(3, 12)
## ENGINE_FOGBADGE's place in source badge order, which `.TrySurf` wants first.
const BADGE_FOG: int = 3


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_route_5_gate(data, game_id)
		_verify_cerulean(data, game_id)
		_verify_cerulean_gym(data, game_id)
		_verify_route_9_dead_end(data, game_id)
		_verify_power_plant_is_reached_by_river(data, game_id)


## Saffron's north exit is a gate building the way its south and west ones are,
## and Route 5 connects straight onto Cerulean.
func _verify_route_5_gate(data: GameData, game_id: StringName) -> void:
	var city: Gen2WorldAPI = _open(data, SAFFRON_GROUP, SAFFRON_CITY, SAFFRON_GATE_DOOR)
	if city == null:
		return
	var warp: Dictionary = city.warp_at(SAFFRON_GATE_DOOR)
	_r.check(
		int(warp.get("map_group", -1)) == SAFFRON_GROUP
			and int(warp.get("map_number", -1)) == ROUTE_5_SAFFRON_GATE,
		"%s: Saffron's %s does not open onto the Route 5 gate." % [game_id, SAFFRON_GATE_DOOR]
	)
	var gate: Gen2WorldAPI = _open(data, SAFFRON_GROUP, ROUTE_5_SAFFRON_GATE, GATE_FROM_CITY)
	if gate == null:
		return
	_r.check(
		_region(gate, GATE_FROM_CITY).has(GATE_TO_ROUTE),
		"%s: the Route 5 gate's two doors are not joined on foot." % game_id
	)
	var far: Dictionary = gate.warp_at(GATE_TO_ROUTE)
	_r.check(
		int(far.get("map_group", -1)) == SAFFRON_GROUP
			and int(far.get("map_number", -1)) == ROUTE_5,
		"%s: the gate's %s does not open onto Route 5." % [game_id, GATE_TO_ROUTE]
	)

	var route: Gen2WorldAPI = _open(data, SAFFRON_GROUP, ROUTE_5, ROUTE_5_FROM_GATE)
	if route == null:
		return
	var crossed: Array = _crossings(data, SAFFRON_GROUP, ROUTE_5, route, "north", ROUTE_5_FROM_GATE)
	_r.check(
		not crossed.is_empty(),
		"%s: Route 5's north edge does not reach Cerulean City." % game_id
	)
	for entry: Array in crossed:
		_r.check(
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
	_r.check(
		world.warp_index_at(CERULEAN_GYM_DOOR) == 5,
		"%s: %s is not Cerulean's gym door." % [game_id, CERULEAN_GYM_DOOR]
	)
	var city: Dictionary = _region(world, CERULEAN_GYM_APPROACH)
	var east: Array[Vector2i] = []
	for y: int in world.map_size_cells().y:
		var edge := Vector2i(world.map_size_cells().x - 1, y)
		if city.has(edge):
			east.append(edge)
	_r.check(
		east == [CERULEAN_EAST_EDGE],
		"%s: Cerulean's east edge is walkable on %s, not %s alone." % [
			game_id, east, CERULEAN_EAST_EDGE,
		]
	)
	var crossed: Array = _crossings(
		data, CERULEAN_GROUP, CERULEAN_CITY, world, "east", CERULEAN_GYM_APPROACH
	)
	_r.check(
		crossed.size() == 1 and crossed[0][1] == Vector2i(CERULEAN_GROUP, ROUTE_9)
			and crossed[0][2] == ROUTE_9_FROM_CERULEAN,
		"%s: Cerulean crosses east as %s, not once onto Route 9's %s." % [
			game_id, crossed, ROUTE_9_FROM_CERULEAN,
		]
	)

	print("%s cerulean: one east crossing onto Route 9." % game_id)


## The gym, which is a pool with three swimmers standing on it.
##
## Five of its six objects hide behind EVENT_TRAINERS_IN_CERULEAN_GYM, which is
## what makes the badge an errand; the sixth is the grunt, whose own scene takes
## him off the ladder column. The load-bearing part is the last: no walk to Misty
## avoids Diana's sight line or both of the other two, and every approach stops
## on water that `can_object_walk_to()` refuses. They resolve anyway, because
## SeenByTrainerScript is `applymovementlasttalked` and every step in that buffer
## reaches NormalStep, which consults no permission at all.
func _verify_cerulean_gym(data: GameData, game_id: StringName) -> void:
	var gym: Gen2WorldAPI = _open(data, CERULEAN_GROUP, CERULEAN_GYM, CERULEAN_GYM_LANDING)
	if gym == null:
		return
	_r.check(
		gym.map_size_cells() == CERULEAN_GYM_CELLS,
		"%s: Cerulean Gym is %s cells, not the pinned %s." % [
			game_id, gym.map_size_cells(), CERULEAN_GYM_CELLS,
		]
	)
	var hidden: int = 0
	for row: Dictionary in gym.current_map.events.get("objects", []):
		if int(row.get("event_flag", -1)) == EVENT_TRAINERS_IN_CERULEAN_GYM:
			hidden += 1
	_r.check(
		hidden == CERULEAN_GYM_HIDDEN_OBJECTS,
		"%s: %d gym objects hide behind EVENT_TRAINERS_IN_CERULEAN_GYM, not %d." % [
			game_id, hidden, CERULEAN_GYM_HIDDEN_OBJECTS,
		]
	)
	_r.check(
		gym.collision_permission_at(MISTY_CELL) == Gen2WorldCollision.LAND_TILE
			and (gym.objects[1] as Gen2WorldObject).cell == MISTY_CELL,
		"%s: Misty does not stand on land at %s." % [game_id, MISTY_CELL]
	)
	for swimmer: Array in GYM_SWIMMERS:
		var object: Gen2WorldObject = gym.objects[swimmer[0]]
		_r.check(
			object.cell == swimmer[1] and object.sight_range == swimmer[2]
				and object.object_type == Gen2WorldObject.OBJECTTYPE_TRAINER,
			"%s: swimmer %d is %s with sight %d, not %s with %d." % [
				game_id, swimmer[0], object.cell, object.sight_range, swimmer[1], swimmer[2],
			]
		)
		# Misty sets all three herself, the way Surge, Erika and Sabrina do.
		_r.check(
			int(object.trainer_data.get("event_flag", -1)) == int(swimmer[6]),
			"%s: swimmer %d's beaten flag is %s, not %d." % [
				game_id, swimmer[0], object.trainer_data.get("event_flag", -1), swimmer[6],
			]
		)
		for cell: Vector2i in [swimmer[1], swimmer[4]]:
			_r.check(
				gym.collision_permission_at(cell) == Gen2WorldCollision.WATER_TILE,
				"%s: %s is not water, so swimmer %d proves nothing." % [
					game_id, cell, swimmer[0],
				]
			)
		_r.check(
			not gym.can_object_walk_to(swimmer[4], object, swimmer[5]),
			"%s: swimmer %d could wander onto %s, so the approach is not the check."
				% [game_id, swimmer[0], swimmer[4]]
		)

	# The grunt is gone by the time the badge is walked, so the walk is measured
	# with his flag set, the way the errand leaves it.
	var walked: Gen2WorldAPI = _open_gym_after_the_grunt(data)
	if walked == null:
		return
	var region: Dictionary = _region(walked, CERULEAN_GYM_LANDING)
	_r.check(
		region.has(MISTY_FACE),
		"%s: the gym door cannot reach %s, so Misty cannot be faced." % [game_id, MISTY_FACE]
	)
	# Which sight lines a walk to Misty cannot route around, checked by shutting
	# seen cells rather than by naming a path.
	var alternatives: Dictionary = {}
	for swimmer: Array in GYM_SWIMMERS:
		var avoidable: bool = _region(walked, CERULEAN_GYM_LANDING, {swimmer[3]: true}).has(
			MISTY_FACE
		)
		if int(swimmer[0]) in GYM_SIGHT_ALTERNATIVES:
			alternatives[swimmer[3]] = true
		_r.check(
			avoidable == (int(swimmer[0]) not in GYM_SIGHT_UNAVOIDABLE),
			"%s: shutting swimmer %d's %s %s Misty, which is the wrong way round." % [
				game_id, swimmer[0], swimmer[3],
				"still reaches" if avoidable else "seals off",
			]
		)
		# Every one of the three is seen from its own cell, avoidable or not, so
		# the sight lines themselves are pinned either way, and each approach is
		# driven whether or not the walk has to take it.
		var probe: Gen2WorldAPI = _open_gym_after_the_grunt(data, swimmer[3])
		if probe == null:
			continue
		var sight: Array = probe.dispatch_sight_events()
		_r.check(
			not sight.is_empty() and int(
				(sight[0].get("source", {}) as Dictionary).get("object_index", -1)
			) == int(swimmer[0]),
			"%s: swimmer %d does not see the player on %s." % [
				game_id, swimmer[0], swimmer[3],
			]
		)
		_verify_swimmer_approach(data, game_id, swimmer)
	_r.check(
		not _region(walked, CERULEAN_GYM_LANDING, alternatives).has(MISTY_FACE),
		"%s: Misty is reachable past both %s, so neither swimmer has to be fought."
			% [game_id, alternatives.keys()]
	)
	print(
		"%s cerulean gym: a pool, five hidden objects, three approaches over it and Diana unavoidable."
		% game_id
	)


## One swimmer's whole sight-to-approach sequence, driven through the runtime the
## world screen and the story preview both use.
func _verify_swimmer_approach(data: GameData, game_id: StringName, swimmer: Array) -> void:
	var index: int = int(swimmer[0])
	var world: Gen2WorldAPI = _open_gym_after_the_grunt(data, swimmer[3])
	if world == null:
		return
	var swimmer_object: Gen2WorldObject = world.objects[index]
	var sight: Array = world.dispatch_sight_events()
	if not _r.check(
		not sight.is_empty(),
		"%s: nobody sees the player on %s." % [game_id, swimmer[3]]
	):
		return
	var source: Dictionary = sight[0].get("source", {})
	_r.check(
		int(source.get("object_index", -1)) == index
			and int(source.get("distance", -1)) == int(swimmer[2])
			and source.get("direction", Vector2i.ZERO) == swimmer[5],
		"%s: %s is seen as %s, not by swimmer %d at distance %d facing %s." % [
			game_id, swimmer[3], source, index, swimmer[2], swimmer[5],
		]
	)
	var approach: Array = world.complete_runtime_request({"ok": true, "audio_played": false})
	_r.check(
		not approach.is_empty() and StringName(
			((approach[0].get("event", {}) as Dictionary).get("request", {}) as Dictionary)
				.get("kind", &"")
		) == &"trainer_approach_requested",
		"%s: swimmer %d's encounter music did not reach the approach request."
			% [game_id, index]
	)
	var plan: Dictionary = world.start_trainer_approach(index, swimmer[5], int(swimmer[2]))
	if not _r.check(
		bool(plan.get("ok", false)),
		"%s: swimmer %d's approach plan failed: %s" % [game_id, index, plan]
	):
		return
	_r.check(
		plan.get("target_cell", Vector2i.ZERO) == swimmer[4],
		"%s: swimmer %d stops on %s, not %s." % [
			game_id, index, plan.get("target_cell", Vector2i.ZERO), swimmer[4],
		]
	)
	for step_direction: Vector2i in plan.get("path", []):
		var step: Dictionary = world.advance_trainer_approach_step(index, step_direction)
		if not _r.check(
			bool(step.get("ok", false)),
			"%s: swimmer %d's step %s failed: %s" % [game_id, index, step_direction, step]
		):
			return
		_r.check(
			swimmer_object.step_frames_total == Gen2WorldAPI.STEP_FRAMES_WALK,
			"%s: swimmer %d steps over %d frames, not %d." % [
				game_id, index, swimmer_object.step_frames_total, Gen2WorldAPI.STEP_FRAMES_WALK,
			]
		)
	_r.check(
		swimmer_object.cell == swimmer[4],
		"%s: swimmer %d ended on %s, not %s." % [
			game_id, index, swimmer_object.cell, swimmer[4],
		]
	)
	_r.check(
		bool(world.finish_trainer_approach(index).get("ok", false)),
		"%s: swimmer %d's approach could not finish." % [game_id, index]
	)


func _open_gym_after_the_grunt(
	data: GameData, cell: Vector2i = CERULEAN_GYM_LANDING
) -> Gen2WorldAPI:
	var state := Gen2WorldState.new()
	state.set_event_flag(EVENT_CERULEAN_GYM_ROCKET, true)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, CERULEAN_GROUP, CERULEAN_GYM, cell, state
	)
	if world == null:
		_r.fail("Cerulean Gym is missing.")
		return null
	var _entry: Array = world.dispatch_map_entry()
	return world


## Route 9's entry pocket, and the fact that its one cut tree opens onto a yard
## holding nothing but the Route 10 Pokecenter.
func _verify_route_9_dead_end(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, CERULEAN_GROUP, ROUTE_9, ROUTE_9_FROM_CERULEAN)
	if world == null:
		return
	var pocket: Dictionary = _region(world, ROUTE_9_FROM_CERULEAN)
	_r.check(
		pocket.size() == ROUTE_9_POCKET_CELLS,
		"%s: Route 9's entry pocket is %d cells, not the pinned %d." % [
			game_id, pocket.size(), ROUTE_9_POCKET_CELLS,
		]
	)
	_r.check(
		pocket.has(ROUTE_9_TREE_APPROACH)
			and world.collision_code_at(ROUTE_9_TREE) == COLL_CUT_TREE,
		"%s: %s is not a cut tree the entry pocket can face." % [game_id, ROUTE_9_TREE]
	)

	world.state.set_engine_flag(Gen2WorldState.badge_flag(
		BADGE_HIVE, Gen2WorldState.is_crystal_profile(data)
	))
	world.player_cell = ROUTE_9_TREE_APPROACH
	world.player_facing = Gen2WorldSprite.FACING_RIGHT
	if not _r.check(
		bool(world.cut_request().get("ok", false))
			and bool(world.complete_cut().get("ok", false)),
		"%s: Route 9's tree refused the cut." % game_id
	):
		return
	var opened: Dictionary = _region(world, ROUTE_9_TREE_APPROACH)
	_r.check(
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
	_r.check(
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
	_r.check(
		cells.size() == POKECENTER_YARD_CELLS,
		"%s: the Route 10 Pokecenter yard is %d cells, not the pinned %d." % [
			game_id, cells.size(), POKECENTER_YARD_CELLS,
		]
	)
	_r.check(
		yard.warp_index_at(ROUTE_10_POKECENTER_DOOR) == 1,
		"%s: %s is not the Route 10 Pokecenter door." % [game_id, ROUTE_10_POKECENTER_DOOR]
	)
	_r.check(
		not cells.has(POWER_PLANT_APPROACH),
		"%s: the Pokecenter yard reaches the Power Plant on foot." % game_id
	)
	print("%s route 9: a %d-cell pocket, one tree, and a yard with one Pokecenter in it." % [
		game_id, ROUTE_9_POCKET_CELLS,
	])


## The plant's door sits in a region with no map edge and no walkable neighbour.
## It is not reached from Route 10 North's southern half either: row 14 is a
## `$b2` buoy line whose own permission walls its north face, so no cell down
## there can enter the water. The way in is Route 9's river, which the same cut
## that opens the route also opens the shore of.
func _verify_power_plant_is_reached_by_river(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, CERULEAN_GROUP, ROUTE_10_NORTH, ROUTE_10_SOUTH_HALF)
	if world == null:
		return
	_r.check(
		world.warp_index_at(POWER_PLANT_DOOR) == 2,
		"%s: %s is not the Power Plant door." % [game_id, POWER_PLANT_DOOR]
	)
	var pocket: Dictionary = _region(world, POWER_PLANT_APPROACH)
	_r.check(
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
	_r.check(
		edges.is_empty(),
		"%s: the Power Plant's region touches map edge %s; it should touch none." % [
			game_id, edges,
		]
	)
	var southern: Dictionary = _region(world, ROUTE_10_SOUTH_HALF)
	_r.check(
		southern.size() == ROUTE_10_SOUTH_HALF_CELLS,
		"%s: Route 10 North's southern half is %d cells, not the pinned %d." % [
			game_id, southern.size(), ROUTE_10_SOUTH_HALF_CELLS,
		]
	)

	# The buoy line, and the fact that it leaves the southern half no way in.
	for x: int in range(2, size.x - 2):
		var cell := Vector2i(x, BUOY_ROW)
		if not _r.check(
			world.collision_code_at(cell) == BUOY_CODE,
			"%s: %s is $%02X, not the pinned buoy $%02X." % [
				game_id, cell, world.collision_code_at(cell), BUOY_CODE,
			]
		):
			break
		if not _r.check(
			(world.tile_permissions_at(cell) & BUOY_UP_WALL) != 0,
			"%s: the buoy on %s does not wall its north face." % [game_id, cell]
		):
			break
	_r.check(
		_surf_entries(data, CERULEAN_GROUP, ROUTE_10_NORTH, southern).is_empty(),
		"%s: Route 10 North's southern half can enter the water; the buoys should refuse it." % game_id
	)

	# The river is the way, and the cut is what opens its shore.
	var route: Gen2WorldAPI = _open(data, CERULEAN_GROUP, ROUTE_9, ROUTE_9_FROM_CERULEAN)
	if route == null:
		return
	route.state.set_engine_flag(Gen2WorldState.badge_flag(
		BADGE_HIVE, Gen2WorldState.is_crystal_profile(data)
	))
	route.player_cell = ROUTE_9_TREE_APPROACH
	route.player_facing = Gen2WorldSprite.FACING_RIGHT
	if not _r.check(
		bool(route.cut_request().get("ok", false))
			and bool(route.complete_cut().get("ok", false)),
		"%s: Route 9's tree refused the cut." % game_id
	):
		return
	var opened: Dictionary = _region(route, ROUTE_9_TREE_APPROACH)
	_r.check(
		opened.has(ROUTE_9_SHORE),
		"%s: the cut does not open Route 9's shore on %s." % [game_id, ROUTE_9_SHORE]
	)
	var entries: Array = _surf_entries(data, CERULEAN_GROUP, ROUTE_9, opened, true)
	_r.check(
		not entries.is_empty(),
		"%s: nothing in Route 9's opened region can enter the river." % game_id
	)
	var river: Dictionary = _water(route, ROUTE_9_RIVER_HEAD)
	_r.check(
		river.size() == ROUTE_9_RIVER_CELLS,
		"%s: Route 9's river is %d cells, not the pinned %d." % [
			game_id, river.size(), ROUTE_9_RIVER_CELLS,
		]
	)
	var mouth: Array[int] = []
	for x: int in route.map_size_cells().x:
		if river.has(Vector2i(x, route.map_size_cells().y - 1)):
			mouth.append(x)
	_r.check(
		mouth == ROUTE_9_RIVER_MOUTH,
		"%s: the river meets the south edge on %s, not the pinned %s." % [
			game_id, mouth, ROUTE_9_RIVER_MOUTH,
		]
	)

	# And what it comes out into reaches the pocket's own shore.
	var lake: Dictionary = _water(world, ROUTE_10_LAKE_HEAD)
	_r.check(
		lake.size() == ROUTE_10_LAKE_CELLS,
		"%s: Route 10 North's water is %d cells, not the pinned %d." % [
			game_id, lake.size(), ROUTE_10_LAKE_CELLS,
		]
	)
	_r.check(
		lake.has(POWER_PLANT_LANDING) and pocket.has(POWER_PLANT_LANDING + Vector2i.UP),
		"%s: the water does not reach the Power Plant's own shore." % game_id
	)
	print("%s power plant: a %d-cell island, no shore entry past the buoys, and a %d-cell river in." % [
		game_id, pocket.size(), river.size(),
	])


## Every [cell, facing] in [param region] that `.TrySurf` accepts, with the Fog
## Badge granted and, for Route 9, its own tree already cut.
func _surf_entries(
	data: GameData, group: int, number: int, region: Dictionary, cut_route_9: bool = false,
) -> Array:
	var facings: Dictionary = {
		Vector2i.UP: Gen2WorldSprite.FACING_UP, Vector2i.DOWN: Gen2WorldSprite.FACING_DOWN,
		Vector2i.LEFT: Gen2WorldSprite.FACING_LEFT, Vector2i.RIGHT: Gen2WorldSprite.FACING_RIGHT,
	}
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	var out: Array = []
	for cell: Vector2i in region:
		for direction: Vector2i in facings:
			var state := Gen2WorldState.new()
			state.set_engine_flag(Gen2WorldState.badge_flag(BADGE_FOG, crystal))
			state.set_engine_flag(Gen2WorldState.badge_flag(BADGE_HIVE, crystal))
			var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell, state)
			if world == null:
				continue
			_r.field_move_party(world)
			var _entry: Array = world.dispatch_map_entry()
			if cut_route_9:
				world.player_cell = ROUTE_9_TREE_APPROACH
				world.player_facing = Gen2WorldSprite.FACING_RIGHT
				var _staged: Dictionary = world.cut_request()
				var _done: Dictionary = world.complete_cut()
				world.player_cell = cell
			world.player_facing = int(facings[direction])
			if bool(world.surf_request().get("ok", false)):
				out.append([cell, direction])
	return out


## The water body [param start] belongs to. Surfing crosses water only, so this
## is the frontier a ride is planned on.
func _water(world: Gen2WorldAPI, start: Vector2i) -> Dictionary:
	var size: Vector2i = world.map_size_cells()
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			if seen.has(next) \
				or world.collision_permission_at(next) != Gen2WorldCollision.WATER_TILE:
				continue
			seen[next] = true
			frontier.append(next)
	return seen


func _open(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell, Gen2WorldState.new())
	if world == null:
		_r.fail("map %d/%d is missing." % [group, number])
		return null
	_r.field_move_party(world)
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
##
## [param closed] cells are treated as unwalkable, which is how an unavoidable
## cell is proved: shut it and see what stops being reachable.
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
