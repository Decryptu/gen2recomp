extends SceneTree

## Verifies the way west from Saffron City to Celadon City and its gym against
## freshly imported real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## maps/SaffronCity.asm, maps/Route7SaffronGate.asm, maps/Route7.asm,
## maps/CeladonCity.asm, maps/CeladonGym.asm and data/maps/attributes.asm.
## Route7.asm, Route7SaffronGate.asm and all four .blk files are byte identical
## between the pins; CeladonCity.asm and CeladonGym.asm differ only in NPC text
## and an `_CRYSTAL_AU` block, so nothing here is profile split.
##
## Three things are worth pinning. Saffron has a real west connection to Route 7
## and it is a dead end, landing in a sealed four-cell corner, so
## `ROUTE_7_SAFFRON_GATE` carries that crossing the way it does the Route 6 one.
## Route 7's own west edge is the open half: a real connection onto Celadon City
## that needs no gate. And the gate that replaces it is inside the city, one
## COLL_CUT_TREE on (28,35) sealing the whole gym yard, which makes Cut the price
## of the Rainbow Badge the way it was of the Thunder Badge.
##
##   Godot --headless --path . -s res://tools/validate_celadon.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm: the CELADON group is 21 and the SAFFRON group 25.
const CELADON_GROUP: int = 21
const ROUTE_7: int = 1
const CELADON_CITY: int = 4
const CELADON_GYM: int = 21
const ROUTE_7_SAFFRON_GATE: int = 25
const SAFFRON_GROUP: int = 25
const SAFFRON_CITY: int = 2

const CITY_SIZE: Vector2i = Vector2i(40, 36)
const ROUTE_7_SIZE: Vector2i = Vector2i(20, 18)
const GATE_SIZE: Vector2i = Vector2i(10, 8)
const GYM_SIZE: Vector2i = Vector2i(10, 18)

## `maps/SaffronCity.asm` warps 10 and 11, and the gate cells they name.
const SAFFRON_GATE_DOORS: Array[Vector2i] = [Vector2i(0, 24), Vector2i(0, 25)]
const GATE_FROM_CITY: Vector2i = Vector2i(9, 4)
const GATE_TO_ROUTE: Vector2i = Vector2i(0, 4)
## `maps/Route7.asm` warp 1, which is where the gate lands the player.
const ROUTE_7_FROM_GATE: Vector2i = Vector2i(15, 6)
## The two cells Saffron's own west edge crosses on, and the sealed corner of
## Route 7 they land in.
const SAFFRON_WEST_EDGE: Array[Vector2i] = [Vector2i(0, 34), Vector2i(0, 35)]
const ROUTE_7_SEALED_CORNER: Array[Vector2i] = [Vector2i(19, 16), Vector2i(19, 17)]
const ROUTE_7_SEALED_CELLS: int = 4
## Route 7's west edge and the Celadon cells it opens onto, connection offset -5
## (`data/maps/attributes.asm`).
const ROUTE_7_WEST_EDGE: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
const CELADON_FROM_ROUTE_7: Array[Vector2i] = [Vector2i(39, 10), Vector2i(39, 11)]

## `maps/CeladonCity.asm` warp 8 and the cell below it, and the tree between the
## city and the yard the gym door sits in.
const GYM_DOOR: Vector2i = Vector2i(10, 29)
const GYM_DOOR_APPROACH: Vector2i = Vector2i(10, 30)
const GYM_TREE: Vector2i = Vector2i(28, 35)
const GYM_TREE_APPROACH: Vector2i = Vector2i(28, 34)
const GYM_TREE_RETURN: Vector2i = Vector2i(27, 35)
## One cell fewer than this pin held until 2026-08-10. The cell is (27,11),
## where `maps/CeladonCity.asm` stands a `SPRITE_POLIWAG` object: a Pokemon
## sprite, which this build cannot draw yet, and which stopped occupying its
## cell as well until Gen2WorldAPI.object_at() was separated from
## visible_objects(). It blocks on the cartridge, so 618 is the real count.
const CITY_CELLS: int = 618
const GYM_YARD_CELLS: int = 70

## engine/overworld/tile_events.asm's CheckCutCollision entry for a tree, the
## `CutTreeBlockPointers` row TILESET_KANTO gives it
## (`data/collision/field_move_blocks.asm`), and ENGINE_HIVEBADGE's place in
## source badge order, which is the badge `.CheckAble` wants before the tile.
const COLL_CUT_TREE: int = 0x12
const TREE_BLOCK_UNCUT: int = 0x60
const TREE_BLOCK_CUT: int = 0x6E
const TREE_BLOCK: Vector2i = Vector2i(14, 17)
const BADGE_HIVE: int = 1

## `maps/CeladonGym.asm`'s object events, in `object_const_def` order, and its
## two door warps.
const ERIKA: Vector2i = Vector2i(5, 3)
const ERIKA_APPROACH: Vector2i = Vector2i(5, 4)
const GYM_WARPS: Array[Vector2i] = [Vector2i(4, 17), Vector2i(5, 17)]
## Each trainer's own sight cells, from the facing and range its object event
## gives it: Michelle STANDING_LEFT range 2 on (7,8), Tanya STANDING_RIGHT
## range 2 on (2,8), Julia STANDING_RIGHT range 2 on (3,5), and the twins
## STANDING_DOWN range 1 on (4,10) and (5,10).
const GYM_TRAINERS: Array[Vector2i] = [
	Vector2i(7, 8), Vector2i(2, 8), Vector2i(3, 5), Vector2i(4, 10), Vector2i(5, 10),
]
const SIGHT_TWINS: Array[Vector2i] = [Vector2i(4, 11), Vector2i(5, 11)]
const SIGHT_JULIA: Array[Vector2i] = [Vector2i(4, 5), Vector2i(5, 5)]
const SIGHT_TANYA: Array[Vector2i] = [Vector2i(3, 8), Vector2i(4, 8)]
const SIGHT_MICHELLE: Array[Vector2i] = [Vector2i(5, 8), Vector2i(6, 8)]

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_gate_carries_saffron(data, game_id)
		_verify_route_7_connection(data, game_id)
		_verify_city(data, game_id)
		_verify_gym(data, game_id)
		_drive_gym_tree(data, game_id)
	_finish()


## Saffron's west edge is a real connection and a dead end: the only two cells it
## crosses on land in a sealed corner of Route 7, so the gate carries it.
func _verify_gate_carries_saffron(data: GameData, game_id: StringName) -> void:
	var city: Gen2WorldAPI = _open(data, SAFFRON_GROUP, SAFFRON_CITY, SAFFRON_GATE_DOORS[0])
	if city == null:
		return
	# Each cell gets its own world, since a crossing moves the one it was taken on.
	var crossed: Array[Vector2i] = []
	for y: int in city.map_size_cells().y:
		var edge := Vector2i(0, y)
		if not city.can_walk_to(edge):
			continue
		var attempt: Gen2WorldAPI = _open(data, SAFFRON_GROUP, SAFFRON_CITY, edge)
		if attempt == null:
			continue
		if not bool(attempt.move_result(Vector2i.LEFT).get("ok", false)):
			continue
		crossed.append(edge)
	_check(
		crossed == SAFFRON_WEST_EDGE,
		"%s: Saffron's west edge crosses on %s, not %s." % [
			game_id, crossed, SAFFRON_WEST_EDGE,
		]
	)

	var route: Gen2WorldAPI = _open(data, CELADON_GROUP, ROUTE_7, ROUTE_7_FROM_GATE)
	if route == null:
		return
	_check(
		route.map_size_cells() == ROUTE_7_SIZE,
		"%s: Route 7 is %s, not the pinned %s." % [
			game_id, route.map_size_cells(), ROUTE_7_SIZE,
		]
	)
	var gate_side: Dictionary = _region(route, ROUTE_7_FROM_GATE)
	for cell: Vector2i in ROUTE_7_SEALED_CORNER:
		_check(
			not gate_side.has(cell),
			"%s: Route 7's %s is reachable from the gate landing." % [game_id, cell]
		)
		_check(
			_region(route, cell).size() == ROUTE_7_SEALED_CELLS,
			"%s: Route 7's corner at %s is %d cells, not the pinned %d." % [
				game_id, cell, _region(route, cell).size(), ROUTE_7_SEALED_CELLS,
			]
		)

	for index: int in SAFFRON_GATE_DOORS.size():
		var warp: Dictionary = city.warp_at(SAFFRON_GATE_DOORS[index])
		_check(
			int(warp.get("map_group", -1)) == CELADON_GROUP
				and int(warp.get("map_number", -1)) == ROUTE_7_SAFFRON_GATE,
			"%s: Saffron's %s does not open onto the Route 7 gate." % [
				game_id, SAFFRON_GATE_DOORS[index],
			]
		)
	var gate: Gen2WorldAPI = _open(
		data, CELADON_GROUP, ROUTE_7_SAFFRON_GATE, GATE_FROM_CITY
	)
	if gate == null:
		return
	_check(
		gate.map_size_cells() == GATE_SIZE,
		"%s: the Route 7 gate is %s, not the pinned %s." % [
			game_id, gate.map_size_cells(), GATE_SIZE,
		]
	)
	_check(
		_region(gate, GATE_FROM_CITY).has(GATE_TO_ROUTE),
		"%s: the Route 7 gate's two doors are not joined on foot." % game_id
	)
	var far: Dictionary = gate.warp_at(GATE_TO_ROUTE)
	_check(
		int(far.get("map_group", -1)) == CELADON_GROUP
			and int(far.get("map_number", -1)) == ROUTE_7,
		"%s: the gate's %s does not open onto Route 7." % [game_id, GATE_TO_ROUTE]
	)
	print("%s gate: Saffron's west edge is a sealed crossing, so the gate carries it." % game_id)


## Route 7's own west edge is the open half of the leg: a real connection onto
## Celadon City, with no gate building between them.
func _verify_route_7_connection(data: GameData, game_id: StringName) -> void:
	var route: Gen2WorldAPI = _open(data, CELADON_GROUP, ROUTE_7, ROUTE_7_FROM_GATE)
	if route == null:
		return
	var gate_side: Dictionary = _region(route, ROUTE_7_FROM_GATE)
	var crossed: Array[Vector2i] = []
	var landed: Array[Vector2i] = []
	for y: int in route.map_size_cells().y:
		var edge := Vector2i(0, y)
		if not gate_side.has(edge):
			continue
		var attempt: Gen2WorldAPI = _open(data, CELADON_GROUP, ROUTE_7, edge)
		if attempt == null:
			continue
		if not bool(attempt.move_result(Vector2i.LEFT).get("ok", false)):
			continue
		if attempt.map_id() != Vector2i(CELADON_GROUP, CELADON_CITY):
			continue
		crossed.append(edge)
		landed.append(attempt.player_cell)
	_check(
		crossed == ROUTE_7_WEST_EDGE and landed == CELADON_FROM_ROUTE_7,
		"%s: Route 7 crosses west on %s into %s, not %s into %s." % [
			game_id, crossed, landed, ROUTE_7_WEST_EDGE, CELADON_FROM_ROUTE_7,
		]
	)
	print("%s route 7: an open west connection onto Celadon City on %s." % [game_id, crossed])


## The city itself, and the one tree that seals the gym yard off.
func _verify_city(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, CELADON_GROUP, CELADON_CITY, CELADON_FROM_ROUTE_7[0])
	if world == null:
		return
	_check(
		world.map_size_cells() == CITY_SIZE,
		"%s: Celadon City is %s, not the pinned %s." % [
			game_id, world.map_size_cells(), CITY_SIZE,
		]
	)
	# One cuttable cell in the whole city, and it is the seam.
	var cuttable: Array[Vector2i] = []
	for y: int in CITY_SIZE.y:
		for x: int in CITY_SIZE.x:
			var cell := Vector2i(x, y)
			if Gen2WorldFieldMove.CUTTABLE_COLLISIONS.has(world.collision_code_at(cell)):
				cuttable.append(cell)
	_check(
		cuttable == [GYM_TREE],
		"%s: Celadon's cuttable cells are %s, not %s alone." % [game_id, cuttable, GYM_TREE]
	)
	_check(
		world.collision_code_at(GYM_TREE) == COLL_CUT_TREE,
		"%s: %s is collision $%02X, not a cut tree." % [
			game_id, GYM_TREE, world.collision_code_at(GYM_TREE),
		]
	)

	var city: Dictionary = _region(world, CELADON_FROM_ROUTE_7[0])
	var yard: Dictionary = _region(world, GYM_DOOR_APPROACH)
	_check(
		city.size() == CITY_CELLS,
		"%s: Celadon's walkable city is %d cells, not the pinned %d." % [
			game_id, city.size(), CITY_CELLS,
		]
	)
	_check(
		yard.size() == GYM_YARD_CELLS,
		"%s: the gym yard is %d cells, not the pinned %d." % [
			game_id, yard.size(), GYM_YARD_CELLS,
		]
	)
	_check(
		not city.has(GYM_DOOR) and not city.has(GYM_DOOR_APPROACH),
		"%s: the gym yard is reachable without cutting." % game_id
	)
	_check(
		city.has(GYM_TREE_APPROACH) and yard.has(GYM_TREE_RETURN),
		"%s: the tree cannot be faced from both sides." % game_id
	)
	# And the tree really is the only join, checked by walking the yard's whole
	# border rather than by naming a cell.
	var seams: Array[Vector2i] = []
	for cell: Vector2i in yard:
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if city.has(cell + direction):
				seams.append(cell + direction)
	_check(
		seams.is_empty(),
		"%s: the gym yard touches the city at %s without a tree between." % [game_id, seams]
	)
	_check(
		world.warp_index_at(GYM_DOOR) == 8,
		"%s: %s is not Celadon's gym door." % [game_id, GYM_DOOR]
	)
	print("%s city: a %d-cell yard behind the city's only cut tree." % [game_id, yard.size()])


## The gym has no puzzle either: no scene scripts, no callbacks, and Erika
## answers as soon as she is faced. The gate is the flower beds, which leave
## three of the five trainers no cell to route around.
func _verify_gym(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, CELADON_GROUP, CELADON_GYM, GYM_WARPS[0])
	if world == null:
		return
	_check(
		world.map_size_cells() == GYM_SIZE,
		"%s: Celadon Gym is %s, not the pinned %s." % [
			game_id, world.map_size_cells(), GYM_SIZE,
		]
	)
	_check(
		world.current_map.scripts.get("scenes", []).is_empty(),
		"%s: Celadon Gym ships a scene script; it should have none." % game_id
	)
	_check(
		world.current_map.scripts.get("callbacks", []).is_empty(),
		"%s: Celadon Gym ships a callback; it should have none." % game_id
	)
	_check(
		world.object_at(ERIKA) != null,
		"%s: no Erika on %s." % [game_id, ERIKA]
	)
	for cell: Vector2i in GYM_TRAINERS:
		_check(
			world.object_at(cell) != null,
			"%s: no gym trainer on %s." % [game_id, cell]
		)
	for index: int in GYM_WARPS.size():
		_check(
			world.warp_index_at(GYM_WARPS[index]) == index + 1,
			"%s: %s is not gym warp %d." % [game_id, GYM_WARPS[index], index + 1]
		)
	_check(
		_region(world, GYM_WARPS[0]).has(ERIKA_APPROACH),
		"%s: Erika cannot be faced from the gym door." % game_id
	)

	# The twins and Julia each watch the only gap in a row, and row 8's four
	# cells are covered by Tanya and Michelle between them, so three fights are
	# unavoidable while either of those two alone can be dodged.
	for sealed: Array in [SIGHT_TWINS, SIGHT_JULIA, SIGHT_TANYA + SIGHT_MICHELLE]:
		_check(
			not _region(world, GYM_WARPS[0], sealed).has(ERIKA_APPROACH),
			"%s: Erika is reachable without crossing %s." % [game_id, sealed]
		)
	for dodged: Array in [SIGHT_TANYA, SIGHT_MICHELLE]:
		_check(
			_region(world, GYM_WARPS[0], dodged).has(ERIKA_APPROACH),
			"%s: %s cannot be dodged, but the other row-8 trainer's line is open." % [
				game_id, dodged,
			]
		)
	print("%s gym: no scene, no callback, and three sight lines with no way around." % game_id)


## The cut itself, against the real cache: the tree opens from either side, the
## yard joins, and a map load grows it back. Leaving the gym reloads the city, so
## the way out is cut a second time exactly as the way in was.
func _drive_gym_tree(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, CELADON_GROUP, CELADON_CITY, GYM_TREE_APPROACH)
	if world == null:
		return
	world.state.set_engine_flag(Gen2WorldState.badge_flag(
		BADGE_HIVE, Gen2WorldState.is_crystal_profile(data)
	))
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var request: Dictionary = world.cut_request()
	if not _check(
		bool(request.get("ok", false)),
		"%s: cut refused at %s: %s" % [game_id, GYM_TREE, request.get("reason", "")]
	):
		return
	_check(
		int(request.get("block", -1)) == TREE_BLOCK_CUT
			and request.get("block_cell", Vector2i.ZERO) == TREE_BLOCK,
		"%s: the tree staged %s, not block $%02X at %s." % [
			game_id, JSON.stringify(request), TREE_BLOCK_CUT, TREE_BLOCK,
		]
	)
	# Script_Cut writes the block only after UseCutText, so staging alone must
	# leave the map exactly as it was.
	_check(
		world.block_at(TREE_BLOCK.x, TREE_BLOCK.y) == TREE_BLOCK_UNCUT
			and not world.can_walk_to(GYM_TREE),
		"%s: Celadon changed before the cut was committed." % game_id
	)
	if not _check(
		bool(world.complete_cut().get("ok", false)),
		"%s: the cut did not commit." % game_id
	):
		return
	_check(
		_region(world, GYM_TREE_APPROACH).has(GYM_DOOR_APPROACH),
		"%s: the gym door is still unreachable after the cut." % game_id
	)
	var _reloaded: Dictionary = world.reload_current_map()
	_check(
		world.collision_code_at(GYM_TREE) == COLL_CUT_TREE,
		"%s: the tree did not grow back on a map load." % game_id
	)

	# And the same tree faced from the yard side, which is the cut the walk out
	# of the gym has to make.
	var back: Gen2WorldAPI = _open(data, CELADON_GROUP, CELADON_CITY, GYM_TREE_RETURN)
	if back == null:
		return
	back.state.set_engine_flag(Gen2WorldState.badge_flag(
		BADGE_HIVE, Gen2WorldState.is_crystal_profile(data)
	))
	back.player_facing = Gen2WorldSprite.FACING_RIGHT
	if not _check(
		bool(back.cut_request().get("ok", false))
			and bool(back.complete_cut().get("ok", false)),
		"%s: the tree refused the cut from the yard side." % game_id
	):
		return
	_check(
		_region(back, GYM_TREE_RETURN).has(CELADON_FROM_ROUTE_7[0]),
		"%s: the yard still cannot reach the city after the return cut." % game_id
	)
	print("%s cut: the tree opens from either side and grows back on the next map load." % game_id)


func _open(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell)
	if world == null:
		_fail("map %d/%d is missing." % [group, number])
		return null
	_field_move_party(world)
	var _entry: Array = world.dispatch_map_entry()
	return world


## [param sealed] cells are treated as wall, which is how a sight line is asked
## whether a walk could have gone around it.
func _region(world: Gen2WorldAPI, start: Vector2i, sealed: Array = []) -> Dictionary:
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if seen.has(next) or sealed.has(next) or not world.can_walk_to(next, direction):
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
		print("PASS celadon: the gate, the open Route 7 connection, the gym yard's tree and the gym verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL celadon: %d problems." % _failures.size())
	quit(1)


## CheckPartyMove gates every field move, and this file is about the map rather
## than the party, so every world it opens carries one member that knows all
## five. The route preview is where a real party earning them is proved.
func _field_move_party(world: Gen2WorldAPI) -> void:
	world.set_party_summary(
		1, false, [1] as Array[int], [Gen2WorldFieldMove.FIELD_MOVES.duplicate()],
		["MON"], [false]
	)
