extends RefCounted

var _r: RefCounted = null

## Verifies the walk south from Lavender Town to Fuchsia City and the Soul Badge,
## against freshly imported real caches for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## maps/Route12.asm, maps/Route13.asm, maps/Route14.asm, maps/Route15.asm,
## maps/Route15FuchsiaGate.asm, maps/FuchsiaCity.asm, maps/FuchsiaGym.asm and
## data/maps/attributes.asm.
##
## Two findings carry the leg. The way south is four plain connections with one
## gate at the end, so what it costs is trainers rather than errands, and which
## trainers is not the same question as how many: shutting each sight line's own
## cells in turn shows that Crystal owes two of Route 13's five and nothing at
## all on Routes 12, 14 and 15, while Gold and Silver owe a different set on
## three profile-split routes. And Fuchsia Gym is a maze rather than a gate: its
## fifty wall cells leave 130 walkable ones and its six objects stand on six of
## them, so the door reaches 124; none of those six is an
## OBJECTTYPE_TRAINER, and Janine sets her four disguised trainers' flags herself.
##
##   Godot --headless --path . -s res://tools/validate.gd -- fuchsia


## constants/map_constants.asm. Route 12 belongs to the LAVENDER group; Routes
## 13, 14 and 15 and the gate belong to FUCHSIA.
const LAVENDER_GROUP: int = 18
const LAVENDER_TOWN: int = 4
const ROUTE_12: int = 2
const FUCHSIA_GROUP: int = 17
const ROUTE_13: int = 1
const ROUTE_14: int = 2
const ROUTE_15: int = 3
const FUCHSIA_CITY: int = 5
const FUCHSIA_GYM: int = 8
const ROUTE_15_FUCHSIA_GATE: int = 13

## The chain, as [label, group, number, the cell it is entered on, the direction
## it leaves by]. Route 15 leaves through a warp rather than an edge, so its own
## exit is named below instead.
const SOUTHBOUND: Array = [
	["Route 12", LAVENDER_GROUP, ROUTE_12, Vector2i(8, 0), "south", 240],
	["Route 13", FUCHSIA_GROUP, ROUTE_13, Vector2i(54, 0), "south", 318],
	["Route 14", FUCHSIA_GROUP, ROUTE_14, Vector2i(11, 0), "west", 344],
	["Route 15", FUCHSIA_GROUP, ROUTE_15, Vector2i(39, 8), "", 213],
]
const ROUTE_15_GATE_DOOR: Vector2i = Vector2i(2, 4)
const LAVENDER_SOUTH_EDGE: Vector2i = Vector2i(8, 17)

## Which sight lines a walk to the next route cannot route around, by object
## index. Route 13 is byte identical between the pins; the other three are not,
## so their owed sets differ and are listed per profile.
const OWED_SIGHT: Dictionary = {
	# map number: [crystal indices, gold/silver indices]
	"Route 12": [[], [0, 2, 3]],
	"Route 13": [[2, 3], [2, 3]],
	"Route 14": [[], [0]],
	"Route 15": [[], []],
}

## The gate at the end, and the city behind it.
const GATE_FROM_ROUTE: Vector2i = Vector2i(9, 4)
const GATE_TO_CITY: Vector2i = Vector2i(0, 4)
const CITY_LANDING: Vector2i = Vector2i(37, 22)
const CITY_CELLS: int = 352
const ENGINE_FLYPOINT_FUCHSIA: int = 62
const ENGINE_FLYPOINT_FUCHSIA_GOLD_SILVER: int = 61
## `maps/FuchsiaCity.asm` warps 1 and 7. The mart door and the beta Safari Zone
## gate sit in other regions, which is why the leg only ever takes warp 3.
const CITY_UNREACHABLE_WARPS: Array[Vector2i] = [Vector2i(5, 13), Vector2i(18, 3)]
const FUCHSIA_GYM_DOOR: Vector2i = Vector2i(8, 27)

## The gym: its own door, its wall count, Janine and the cell she is faced from.
const GYM_LANDING: Vector2i = Vector2i(4, 17)
## Collision alone leaves 130 land cells; the six objects stand on six of them
## and the flood is `can_walk_to`, so 124 is what the door reaches. The pin was
## 128 while Janine's four disguised trainers did not occupy anything: they carry
## SPRITE_FUCHSIA_GYM_1 to _4, which are `SPRITE_VARS` rows no script assigns, and
## `GetMonSprite.NoBreedmon` answers WALKING_SPRITE for an unassigned one rather
## than nothing, so all four stand in the maze.
const GYM_CELLS: int = 124
const GYM_WALL_CELLS: int = 50
const JANINE_INDEX: int = 0
const JANINE_CELL: Vector2i = Vector2i(1, 10)
const JANINE_FACE: Vector2i = Vector2i(1, 9)
const GYM_OBJECTS: int = 6


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_chain(data, game_id, crystal)
		_verify_gate_and_city(data, game_id, crystal)
		_verify_gym(data, game_id)


## The four routes, and which of their eighteen sight lines each walk owes.
func _verify_chain(data: GameData, game_id: StringName, crystal: bool) -> void:
	var town: Gen2WorldAPI = _open(data, LAVENDER_GROUP, LAVENDER_TOWN, LAVENDER_SOUTH_EDGE)
	if town != null:
		var crossed: Dictionary = town.connection_target(LAVENDER_SOUTH_EDGE, Vector2i.DOWN)
		_r.check(
			bool(crossed.get("ok", false))
				and crossed.get("map_group", -1) == LAVENDER_GROUP
				and crossed.get("map_number", -1) == ROUTE_12,
			"%s: Lavender's %s does not cross south onto Route 12." % [
				game_id, LAVENDER_SOUTH_EDGE,
			]
		)

	for leg: Array in SOUTHBOUND:
		var label: String = leg[0]
		var group: int = int(leg[1])
		var number: int = int(leg[2])
		var start: Vector2i = leg[3]
		var world: Gen2WorldAPI = _open(data, group, number, start)
		if world == null:
			continue
		var region: Dictionary = _region(world, start)
		_r.check(
			region.size() == int(leg[5]),
			"%s: %s is %d cells from %s, not the pinned %d." % [
				game_id, label, region.size(), start, int(leg[5]),
			]
		)
		var exits: Dictionary = _exits(world, region, String(leg[4]))
		if not _r.check(
			not exits.is_empty(),
			"%s: %s has no way on from %s." % [game_id, label, start]
		):
			continue

		var lines: Dictionary = _sight_lines(data, group, number, region)
		var owed: Array = []
		for index: int in lines:
			var sealed: bool = true
			for exit_cell: Vector2i in exits:
				if _region(world, start, lines[index]).has(exit_cell):
					sealed = false
					break
			if sealed:
				owed.append(index)
		owed.sort()
		var expected: Array = (OWED_SIGHT[label] as Array)[0 if crystal else 1]
		_r.check(
			owed == expected,
			"%s: %s owes sight lines %s, not the pinned %s." % [
				game_id, label, owed, expected,
			]
		)
		print("%s %s: %d cells, %d sight lines, %s owed." % [
			game_id, label, region.size(), lines.size(), owed if not owed.is_empty() else "none",
		])


## Route 15's gate, and the city it opens onto.
func _verify_gate_and_city(data: GameData, game_id: StringName, crystal: bool) -> void:
	var route: Gen2WorldAPI = _open(data, FUCHSIA_GROUP, ROUTE_15, ROUTE_15_GATE_DOOR)
	if route != null:
		var door: Dictionary = route.warp_at(ROUTE_15_GATE_DOOR)
		_r.check(
			int(door.get("map_group", -1)) == FUCHSIA_GROUP
				and int(door.get("map_number", -1)) == ROUTE_15_FUCHSIA_GATE,
			"%s: Route 15's %s does not open onto the Fuchsia gate." % [
				game_id, ROUTE_15_GATE_DOOR,
			]
		)
	var gate: Gen2WorldAPI = _open(
		data, FUCHSIA_GROUP, ROUTE_15_FUCHSIA_GATE, GATE_FROM_ROUTE
	)
	if gate != null:
		_r.check(
			_region(gate, GATE_FROM_ROUTE).has(GATE_TO_CITY),
			"%s: the Fuchsia gate's two doors are not joined on foot." % game_id
		)
		var far: Dictionary = gate.warp_at(GATE_TO_CITY)
		_r.check(
			int(far.get("map_group", -1)) == FUCHSIA_GROUP
				and int(far.get("map_number", -1)) == FUCHSIA_CITY,
			"%s: the gate's %s does not open onto Fuchsia City." % [game_id, GATE_TO_CITY]
		)

	var city: Gen2WorldAPI = _open(data, FUCHSIA_GROUP, FUCHSIA_CITY, CITY_LANDING)
	if city == null:
		return
	var flypoint: int = ENGINE_FLYPOINT_FUCHSIA if crystal \
		else ENGINE_FLYPOINT_FUCHSIA_GOLD_SILVER
	_r.check(
		city.state.is_engine_flag_active(flypoint),
		"%s: FuchsiaCityFlypointCallback did not set engine flag %d on arrival." % [
			game_id, flypoint,
		]
	)
	var region: Dictionary = _region(city, CITY_LANDING)
	_r.check(
		region.size() == CITY_CELLS,
		"%s: Fuchsia City is %d cells from the gate, not the pinned %d." % [
			game_id, region.size(), CITY_CELLS,
		]
	)
	_r.check(
		region.has(FUCHSIA_GYM_DOOR) and city.warp_index_at(FUCHSIA_GYM_DOOR) == 3,
		"%s: %s is not the reachable gym door." % [game_id, FUCHSIA_GYM_DOOR]
	)
	for cell: Vector2i in CITY_UNREACHABLE_WARPS:
		_r.check(
			not region.has(cell),
			"%s: %s is reachable from the gate, so the city is not the pinned shape." % [
				game_id, cell,
			]
		)
	print("%s fuchsia city: 352 cells behind the gate, a flypoint and the gym door." % game_id)


## The gym, which is a maze with no sight lines in it.
func _verify_gym(data: GameData, game_id: StringName) -> void:
	var gym: Gen2WorldAPI = _open(data, FUCHSIA_GROUP, FUCHSIA_GYM, GYM_LANDING)
	if gym == null:
		return
	var walls: int = 0
	var size: Vector2i = gym.map_size_cells()
	for y: int in size.y:
		for x: int in size.x:
			if Gen2WorldCollision.permission_for(gym.collision_code_at(Vector2i(x, y))) \
				== Gen2WorldCollision.WALL_TILE:
				walls += 1
	_r.check(
		walls == GYM_WALL_CELLS,
		"%s: Fuchsia Gym has %d wall cells, not the pinned %d." % [
			game_id, walls, GYM_WALL_CELLS,
		]
	)
	var region: Dictionary = _region(gym, GYM_LANDING)
	_r.check(
		region.size() == GYM_CELLS,
		"%s: Fuchsia Gym is %d cells from its door, not the pinned %d." % [
			game_id, region.size(), GYM_CELLS,
		]
	)
	_r.check(
		gym.objects.size() == GYM_OBJECTS,
		"%s: Fuchsia Gym has %d objects, not %d." % [
			game_id, gym.objects.size(), GYM_OBJECTS,
		]
	)
	# None of them sees the player: Janine's four are OBJECTTYPE_SCRIPT, which is
	# what makes them optional and the maze the whole of the puzzle.
	for object: Gen2WorldObject in gym.objects:
		_r.check(
			object.object_type != Gen2WorldObject.OBJECTTYPE_TRAINER,
			"%s: Fuchsia Gym object %d is a sight trainer." % [game_id, object.index]
		)
	var janine: Gen2WorldObject = gym.objects[JANINE_INDEX]
	_r.check(
		janine.cell == JANINE_CELL and region.has(JANINE_FACE),
		"%s: Janine is on %s and faced from %s, not %s from %s." % [
			game_id, janine.cell, JANINE_FACE, JANINE_CELL, JANINE_FACE,
		]
	)
	print("%s fuchsia gym: a %d-cell maze behind %d walls, and nothing in it sees." % [
		game_id, region.size(), walls,
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


## The cells a walk can leave [param world] by. An empty [param axis] means the
## map is left through a warp, which on this chain is only Route 15's gate door.
func _exits(world: Gen2WorldAPI, region: Dictionary, axis: String) -> Dictionary:
	var out: Dictionary = {}
	if axis.is_empty():
		if region.has(ROUTE_15_GATE_DOOR):
			out[ROUTE_15_GATE_DOOR] = true
		return out
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
		# connection_target() rather than the edge coordinate: a connection spans
		# only part of its edge, and Route 13's south edge is sixty cells wide.
		if region.has(edge) and bool(world.connection_target(edge, direction).get("ok", false)):
			out[edge] = true
	return out


func _open(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell, Gen2WorldState.new())
	if world == null:
		_r.fail("map %d/%d is missing." % [group, number])
		return null
	var _entry: Array = world.dispatch_map_entry()
	return world


## Ledge hops included, the way `tools/preview_world_story.gd`'s own
## _reachable_step() walks. [param closed] cells are treated as unwalkable, which
## is how an owed sight line is proved: shut it and see what stops being
## reachable.
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
