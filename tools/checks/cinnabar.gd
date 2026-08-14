extends RefCounted

var _r: RefCounted = null

## Verifies the walk south from Pewter to Cinnabar Island, east to Seafoam Gym,
## and back north to Viridian Gym, against freshly imported real caches for both
## command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## data/maps/attributes.asm, maps/PalletTown.asm, maps/Route21.asm,
## maps/CinnabarIsland.asm, maps/Route20.asm, maps/SeafoamGym.asm and
## maps/ViridianGym.asm.
##
## Three findings carry the leg. Cinnabar Island is two land regions with no
## seam between them, and the crossing off Route 21 can land on either, so which
## cell it lands on decides whether Blue is reachable at all. Route 20's west
## channel is walled off from the open sea on every side, so the island holding
## the gym mouth is landed on from the east and not the west. And Viridian Gym
## has no puzzle and no trainer: both its objects carry EVENT_VIRIDIAN_GYM_BLUE
## as their hide flag, so the whole gate is Cinnabar's Blue clearing it.
##
##   Godot --headless --path . -s res://tools/validate.gd -- cinnabar


## constants/map_constants.asm. Nothing on this leg splits between the profiles.
const PEWTER_GROUP: int = 14
const PEWTER_CITY: int = 2
const VIRIDIAN_GROUP: int = 23
const ROUTE_2: int = 1
const VIRIDIAN_CITY: int = 3
const VIRIDIAN_GYM: int = 4
const PALLET_GROUP: int = 13
const ROUTE_1: int = 1
const PALLET_TOWN: int = 2
const SEAFOAM_GROUP: int = 6
const SEAFOAM_GYM: int = 4
const ROUTE_20: int = 6
const ROUTE_21: int = 7
const CINNABAR_ISLAND: int = 8

## The land half of the walk south, as [label, group, number, the cell it is
## entered on, the target group and number its south edge crosses onto].
const SOUTHBOUND: Array = [
	["Pewter City", PEWTER_GROUP, PEWTER_CITY, Vector2i(18, 35), VIRIDIAN_GROUP, ROUTE_2],
	["Route 2", VIRIDIAN_GROUP, ROUTE_2, Vector2i(8, 0), VIRIDIAN_GROUP, VIRIDIAN_CITY],
	["Viridian City", VIRIDIAN_GROUP, VIRIDIAN_CITY, Vector2i(18, 0), PALLET_GROUP, ROUTE_1],
	["Route 1", PALLET_GROUP, ROUTE_1, Vector2i(8, 0), PALLET_GROUP, PALLET_TOWN],
]
const ENGINE_FLYPOINT_VIRIDIAN: int = 54
const ENGINE_FLYPOINT_PALLET: int = 53
const ENGINE_FLYPOINT_CINNABAR: int = 63

## Pallet Town's pond, which is the last land on the way down: sixteen water
## cells on x=4 to 7, rows 14 to 17, entered from (4,13).
const PALLET_SURF_APPROACH: Vector2i = Vector2i(4, 13)
const PALLET_POND_CELL: Vector2i = Vector2i(4, 14)
const PALLET_POND_CELLS: int = 16
const PALLET_LAND_CELLS: int = 205

## Route 21 is one sea, and its south edge crosses onto Cinnabar.
const ROUTE_21_CELL: Vector2i = Vector2i(4, 0)
const ROUTE_21_WATER_CELLS: int = 479

## Cinnabar Island. The west crossing cells stay water on both sides; the east
## ones exit onto the 89-cell region, which reaches neither Blue nor the
## Pokecenter door.
const CINNABAR_WEST_CROSSING: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
]
const CINNABAR_EAST_CROSSING: Vector2i = Vector2i(11, 0)
const CINNABAR_EAST_REGION_CELLS: int = 89
const CINNABAR_WATER_CELLS: int = 91
const CINNABAR_LANDING: Vector2i = Vector2i(4, 10)
const CINNABAR_BLUE_REGION_CELLS: int = 51
const BLUE_CELL: Vector2i = Vector2i(9, 6)
const BLUE_FACE: Vector2i = Vector2i(8, 6)
const CINNABAR_POKECENTER_DOOR: Vector2i = Vector2i(11, 11)
## The island's whole east edge, and it is water, so the leg surfs out of the
## same shore it landed on.
const CINNABAR_EAST_EDGE: Vector2i = Vector2i(19, 16)

## Route 20. The channel on x=26 and 27 runs up the gym island's west shore and
## is sealed from the sea, so (28,8) is not a landfall even though it is shore.
const ROUTE_20_SEA_CELL: Vector2i = Vector2i(42, 8)
const ROUTE_20_WATER_CELLS: int = 697
const ROUTE_20_WEST_CHANNEL: Vector2i = Vector2i(27, 8)
const ROUTE_20_LANDING: Vector2i = Vector2i(41, 8)
const ROUTE_20_ISLAND_CELLS: int = 88
const SEAFOAM_GYM_DOOR: Vector2i = Vector2i(38, 7)
const EVENT_CINNABAR_ROCKS_CLEARED: int = 215

## Seafoam Gym: thirteen cells, Blaine on (5,2) faced from below, and a guide
## his own script `appear`s.
const SEAFOAM_GYM_LANDING: Vector2i = Vector2i(5, 5)
const SEAFOAM_GYM_CELLS: int = 13
const BLAINE_CELL: Vector2i = Vector2i(5, 2)
const BLAINE_FACE: Vector2i = Vector2i(5, 3)
const EVENT_SEAFOAM_GYM_GYM_GUIDE: int = 1911

## Viridian Gym: both objects hidden by the same flag, so the gym is empty until
## Cinnabar's Blue clears it.
const VIRIDIAN_GYM_DOOR: Vector2i = Vector2i(32, 7)
const VIRIDIAN_GYM_LANDING: Vector2i = Vector2i(4, 17)
const VIRIDIAN_GYM_CELLS: int = 82
const VIRIDIAN_BLUE_CELL: Vector2i = Vector2i(5, 3)
const VIRIDIAN_BLUE_FACE: Vector2i = Vector2i(5, 4)
const EVENT_VIRIDIAN_GYM_BLUE: int = 1910
const VIRIDIAN_GYM_OBJECTS: int = 2


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_southbound(data, game_id, crystal)
		_verify_pallet_pond(data, game_id)
		_verify_cinnabar(data, game_id, crystal)
		_verify_route_20(data, game_id)
		_verify_seafoam_gym(data, game_id)
		_verify_viridian_gym(data, game_id)


## The land half: four connections, each proved by the map its region crosses
## onto, and the two flypoints the walk collects.
func _verify_southbound(data: GameData, game_id: StringName, crystal: bool) -> void:
	for leg: Array in SOUTHBOUND:
		var label: String = leg[0]
		var start: Vector2i = leg[3]
		var world: Gen2WorldAPI = _open(data, int(leg[1]), int(leg[2]), start)
		if world == null:
			continue
		var crossing: Dictionary = _crossing(world, _region(world, start), "south")
		_r.check(
			int(crossing.get("map_group", -1)) == int(leg[4])
				and int(crossing.get("map_number", -1)) == int(leg[5]),
			"%s: %s's south edge reaches %d/%d, not the pinned %d/%d." % [
				game_id, label,
				int(crossing.get("map_group", -1)), int(crossing.get("map_number", -1)),
				int(leg[4]), int(leg[5]),
			]
		)
	for pair: Array in [
		[VIRIDIAN_GROUP, VIRIDIAN_CITY, ENGINE_FLYPOINT_VIRIDIAN, Vector2i(18, 0)],
		[PALLET_GROUP, PALLET_TOWN, ENGINE_FLYPOINT_PALLET, Vector2i(8, 0)],
	]:
		var town: Gen2WorldAPI = _open(data, int(pair[0]), int(pair[1]), pair[3])
		if town == null:
			continue
		var flag: int = int(pair[2]) if crystal else int(pair[2]) - 1
		_r.check(
			town.state.is_engine_flag_active(flag),
			"%s: %d/%d did not set flypoint engine flag %d on arrival." % [
				game_id, int(pair[0]), int(pair[1]), flag,
			]
		)
	print("%s southbound: four connections from Pewter to Pallet, both flypoints." % game_id)


## Pallet's pond, and the fact that its south edge only crosses while surfing.
func _verify_pallet_pond(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, PALLET_GROUP, PALLET_TOWN, PALLET_SURF_APPROACH)
	if world == null:
		return
	_r.check(
		_region(world, PALLET_SURF_APPROACH).size() == PALLET_LAND_CELLS,
		"%s: Pallet's land is %d cells, not the pinned %d." % [
			game_id, _region(world, PALLET_SURF_APPROACH).size(), PALLET_LAND_CELLS,
		]
	)
	_r.check(
		world.collision_permission_at(PALLET_POND_CELL) == Gen2WorldCollision.WATER_TILE,
		"%s: %s is not water." % [game_id, PALLET_POND_CELL]
	)
	var pond: Dictionary = _water_region(world, PALLET_POND_CELL)
	_r.check(
		pond.size() == PALLET_POND_CELLS,
		"%s: Pallet's pond is %d cells, not the pinned %d." % [
			game_id, pond.size(), PALLET_POND_CELLS,
		]
	)
	# The crossing itself is a surfing question: connection_target reads the
	# player's own movement mode, so a walking player is refused at the same cell.
	var edge := Vector2i(PALLET_POND_CELL.x, world.map_size_cells().y - 1)
	_r.check(
		pond.has(edge),
		"%s: Pallet's pond does not reach its own south edge at %s." % [game_id, edge]
	)
	world.player_cell = edge
	_r.check(
		not bool(world.connection_target(edge, Vector2i.DOWN).get("ok", false)),
		"%s: Pallet's south edge crosses onto water while walking." % game_id
	)
	world.movement_mode = Gen2WorldAPI.MOVEMENT_SURF
	var crossed: Dictionary = world.connection_target(edge, Vector2i.DOWN)
	_r.check(
		bool(crossed.get("ok", false))
			and int(crossed.get("map_group", -1)) == SEAFOAM_GROUP
			and int(crossed.get("map_number", -1)) == ROUTE_21,
		"%s: Pallet's south edge does not surf onto Route 21." % game_id
	)

	var route: Gen2WorldAPI = _open(data, SEAFOAM_GROUP, ROUTE_21, ROUTE_21_CELL)
	if route == null:
		return
	var sea: Dictionary = _water_region(route, ROUTE_21_CELL)
	_r.check(
		sea.size() == ROUTE_21_WATER_CELLS,
		"%s: Route 21 is %d water cells, not the pinned %d." % [
			game_id, sea.size(), ROUTE_21_WATER_CELLS,
		]
	)
	route.movement_mode = Gen2WorldAPI.MOVEMENT_SURF
	var onward: Dictionary = _crossing(route, sea, "south")
	_r.check(
		int(onward.get("map_group", -1)) == SEAFOAM_GROUP
			and int(onward.get("map_number", -1)) == CINNABAR_ISLAND,
		"%s: Route 21's south edge does not reach Cinnabar." % game_id
	)
	print("%s pallet: a %d-cell pond that only crosses while surfing, and Route 21's %d-cell sea." % [
		game_id, pond.size(), sea.size(),
	])


## Cinnabar's two land regions, and which crossing reaches Blue.
func _verify_cinnabar(data: GameData, game_id: StringName, crystal: bool) -> void:
	var world: Gen2WorldAPI = _open(data, SEAFOAM_GROUP, CINNABAR_ISLAND, CINNABAR_LANDING)
	if world == null:
		return
	var flag: int = ENGINE_FLYPOINT_CINNABAR if crystal else ENGINE_FLYPOINT_CINNABAR - 1
	_r.check(
		world.state.is_engine_flag_active(flag),
		"%s: CinnabarIslandFlypointCallback did not set engine flag %d." % [game_id, flag]
	)

	var blue_region: Dictionary = _region(world, CINNABAR_LANDING)
	_r.check(
		blue_region.size() == CINNABAR_BLUE_REGION_CELLS,
		"%s: Cinnabar's west region is %d cells, not the pinned %d." % [
			game_id, blue_region.size(), CINNABAR_BLUE_REGION_CELLS,
		]
	)
	for cell: Vector2i in [BLUE_FACE, CINNABAR_POKECENTER_DOOR]:
		_r.check(
			blue_region.has(cell),
			"%s: Cinnabar's west region does not reach %s." % [game_id, cell]
		)
	_r.check(
		world.object_at(BLUE_CELL) != null,
		"%s: %s is not Blue's cell." % [game_id, BLUE_CELL]
	)

	var east_region: Dictionary = _region(world, CINNABAR_EAST_CROSSING)
	_r.check(
		east_region.size() == CINNABAR_EAST_REGION_CELLS,
		"%s: Cinnabar's east region is %d cells, not the pinned %d." % [
			game_id, east_region.size(), CINNABAR_EAST_REGION_CELLS,
		]
	)
	# The whole point of the west landing: the two regions share no seam.
	for cell: Vector2i in [BLUE_FACE, CINNABAR_POKECENTER_DOOR, CINNABAR_LANDING]:
		_r.check(
			not east_region.has(cell),
			"%s: Cinnabar's east region reaches %s, so the island is one region." % [
				game_id, cell,
			]
		)
	for cell: Vector2i in CINNABAR_WEST_CROSSING:
		_r.check(
			world.collision_permission_at(cell) == Gen2WorldCollision.WATER_TILE,
			"%s: %s is not one of Cinnabar's water crossing cells." % [game_id, cell]
		)

	var water: Dictionary = _water_region(world, CINNABAR_WEST_CROSSING[0])
	_r.check(
		water.size() == CINNABAR_WATER_CELLS,
		"%s: Cinnabar's water is %d cells, not the pinned %d." % [
			game_id, water.size(), CINNABAR_WATER_CELLS,
		]
	)
	_r.check(
		water.has(CINNABAR_EAST_EDGE),
		"%s: Cinnabar's water does not reach its east edge at %s." % [
			game_id, CINNABAR_EAST_EDGE,
		]
	)
	world.movement_mode = Gen2WorldAPI.MOVEMENT_SURF
	var east: Dictionary = _crossing(world, water, "east")
	_r.check(
		int(east.get("map_group", -1)) == SEAFOAM_GROUP
			and int(east.get("map_number", -1)) == ROUTE_20
			and Vector2i(east.get("edge", Vector2i.ZERO)) == CINNABAR_EAST_EDGE,
		"%s: Cinnabar's east crossing is not %s onto Route 20." % [game_id, CINNABAR_EAST_EDGE]
	)
	print("%s cinnabar: two land regions of %d and %d cells with no seam, and one east edge cell." % [
		game_id, east_region.size(), blue_region.size(),
	])


## Route 20's sealed west channel, its sea and the gym mouth behind the east
## landfall.
func _verify_route_20(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, SEAFOAM_GROUP, ROUTE_20, ROUTE_20_SEA_CELL)
	if world == null:
		return
	_r.check(
		world.event_flag_active(EVENT_CINNABAR_ROCKS_CLEARED),
		"%s: Route20ClearRocksCallback did not set event flag %d on arrival." % [
			game_id, EVENT_CINNABAR_ROCKS_CLEARED,
		]
	)
	var sea: Dictionary = _water_region(world, ROUTE_20_SEA_CELL)
	_r.check(
		sea.size() == ROUTE_20_WATER_CELLS,
		"%s: Route 20 is %d water cells, not the pinned %d." % [
			game_id, sea.size(), ROUTE_20_WATER_CELLS,
		]
	)
	_r.check(
		not sea.has(ROUTE_20_WEST_CHANNEL),
		"%s: the west channel at %s is reachable from the sea after all." % [
			game_id, ROUTE_20_WEST_CHANNEL,
		]
	)
	_r.check(
		world.collision_permission_at(ROUTE_20_WEST_CHANNEL)
			== Gen2WorldCollision.WATER_TILE,
		"%s: %s is not water, so it is not the channel." % [game_id, ROUTE_20_WEST_CHANNEL]
	)
	var island: Dictionary = _region(world, ROUTE_20_LANDING)
	_r.check(
		island.size() == ROUTE_20_ISLAND_CELLS,
		"%s: Route 20's island is %d cells, not the pinned %d." % [
			game_id, island.size(), ROUTE_20_ISLAND_CELLS,
		]
	)
	_r.check(
		island.has(SEAFOAM_GYM_DOOR),
		"%s: the island does not reach the gym mouth at %s." % [game_id, SEAFOAM_GYM_DOOR]
	)
	var mouth: Dictionary = world.warp_at(SEAFOAM_GYM_DOOR)
	_r.check(
		int(mouth.get("map_group", -1)) == SEAFOAM_GROUP
			and int(mouth.get("map_number", -1)) == SEAFOAM_GYM,
		"%s: %s is not the Seafoam Gym warp." % [game_id, SEAFOAM_GYM_DOOR]
	)
	print("%s route 20: a %d-cell sea, a sealed west channel, and the gym mouth on the east island." % [
		game_id, sea.size(),
	])


func _verify_seafoam_gym(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, SEAFOAM_GROUP, SEAFOAM_GYM, SEAFOAM_GYM_LANDING)
	if world == null:
		return
	var region: Dictionary = _region(world, SEAFOAM_GYM_LANDING)
	_r.check(
		region.size() == SEAFOAM_GYM_CELLS,
		"%s: Seafoam Gym is %d cells, not the pinned %d." % [
			game_id, region.size(), SEAFOAM_GYM_CELLS,
		]
	)
	_r.check(
		region.has(BLAINE_FACE) and world.object_at(BLAINE_CELL) != null,
		"%s: Blaine on %s is not faced from %s." % [game_id, BLAINE_CELL, BLAINE_FACE]
	)
	var trainers: int = 0
	for row: Variant in world.current_map.events.get("objects", []):
		if row is Dictionary and int((row as Dictionary).get("type", -1)) \
			== Gen2WorldObject.OBJECTTYPE_TRAINER:
			trainers += 1
	_r.check(trainers == 0, "%s: Seafoam Gym ships %d trainers." % [game_id, trainers])
	# The guide is hidden behind his own flag until Blaine's script appears him.
	var hidden := Gen2WorldState.new()
	hidden.set_event_flag(EVENT_SEAFOAM_GYM_GYM_GUIDE)
	var without: Gen2WorldAPI = _open(
		data, SEAFOAM_GROUP, SEAFOAM_GYM, SEAFOAM_GYM_LANDING, hidden
	)
	if without != null:
		_r.check(
			without.visible_objects().size() == world.visible_objects().size() - 1,
			"%s: the Seafoam Gym guide's hide flag changes nothing." % game_id
		)
	print("%s seafoam gym: %d cells, Blaine faced from below, no trainer in it." % [
		game_id, region.size(),
	])


## Viridian Gym, whose entire gate is one event flag on both of its objects.
func _verify_viridian_gym(data: GameData, game_id: StringName) -> void:
	var city: Gen2WorldAPI = _open(data, VIRIDIAN_GROUP, VIRIDIAN_CITY, Vector2i(18, 0))
	if city != null:
		_r.check(
			_region(city, Vector2i(18, 0)).has(VIRIDIAN_GYM_DOOR),
			"%s: Viridian's gym door at %s is not reachable from the north edge." % [
				game_id, VIRIDIAN_GYM_DOOR,
			]
		)
	var world: Gen2WorldAPI = _open(
		data, VIRIDIAN_GROUP, VIRIDIAN_GYM, VIRIDIAN_GYM_LANDING
	)
	if world == null:
		return
	var region: Dictionary = _region(world, VIRIDIAN_GYM_LANDING)
	_r.check(
		region.size() == VIRIDIAN_GYM_CELLS,
		"%s: Viridian Gym is %d cells, not the pinned %d." % [
			game_id, region.size(), VIRIDIAN_GYM_CELLS,
		]
	)
	_r.check(
		region.has(VIRIDIAN_BLUE_FACE) and world.object_at(VIRIDIAN_BLUE_CELL) != null,
		"%s: Blue on %s is not faced from %s." % [
			game_id, VIRIDIAN_BLUE_CELL, VIRIDIAN_BLUE_FACE,
		]
	)
	_r.check(
		world.visible_objects().size() == VIRIDIAN_GYM_OBJECTS,
		"%s: Viridian Gym shows %d objects with the flag clear, not %d." % [
			game_id, world.visible_objects().size(), VIRIDIAN_GYM_OBJECTS,
		]
	)
	var sealed := Gen2WorldState.new()
	sealed.set_event_flag(EVENT_VIRIDIAN_GYM_BLUE)
	var empty: Gen2WorldAPI = _open(
		data, VIRIDIAN_GROUP, VIRIDIAN_GYM, VIRIDIAN_GYM_LANDING, sealed
	)
	if empty != null:
		_r.check(
			empty.visible_objects().is_empty(),
			"%s: Viridian Gym is not empty while EVENT_VIRIDIAN_GYM_BLUE is set." % game_id
		)
	print("%s viridian gym: %d cells, two objects, and both gone behind one flag." % [
		game_id, region.size(),
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
		# connection_target reads the player's own cell for the leave-side face
		# mask, so a surfed crossing has to be asked from the edge itself.
		world.player_cell = edge
		var target: Dictionary = world.connection_target(edge, direction)
		if bool(target.get("ok", false)):
			target["edge"] = edge
			return target
	return {}


func _open(
	data: GameData, group: int, number: int, cell: Vector2i, state: Gen2WorldState = null
) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, group, number, cell, state if state != null else Gen2WorldState.new()
	)
	if world == null:
		_r.fail("map %d/%d is missing." % [group, number])
		return null
	_r.field_move_party(world)
	var _entry: Array = world.dispatch_map_entry()
	return world


## Ledge hops included, the way tools/checks/pewter.gd walks.
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


## The water a surfing player can cross without going ashore, which is what
## decides where a sea leg can and cannot land.
func _water_region(world: Gen2WorldAPI, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	var size: Vector2i = world.map_size_cells()
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			var face: int = Gen2WorldCollision.face_mask_for_direction(direction)
			if face != 0 and (world.tile_permissions_at(cell) & face) != 0:
				continue
			if world.collision_permission_at(next) != Gen2WorldCollision.WATER_TILE:
				continue
			if world.object_at(next) != null or seen.has(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen
