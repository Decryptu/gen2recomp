extends SceneTree

## Verifies the walk east out of Saffron to Lavender Town and the EXPN CARD the
## Kanto Radio Tower hands over, against freshly imported real caches for both
## command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## maps/SaffronCity.asm, maps/Route8SaffronGate.asm, maps/Route8.asm,
## maps/LavenderTown.asm, maps/LavRadioTower1F.asm and data/maps/attributes.asm.
##
## Two findings carry the leg. Route 8's five trainers look like a wall and are
## not one: the three bikers stand in a column facing west, and the route's eight
## `$a3` hop-down ledges drop an eastbound walk onto row 8 east of them, so only
## Super Nerd Tom's line cannot be routed around. And the town needs no errand of
## its own, but the tower does: `LavRadioTower1FGentlemanScript` gates the EXPN
## CARD on EVENT_RETURNED_MACHINE_PART, so the Power Plant the Cascade Badge
## needed is what puts the Kanto station back on the air.
##
##   Godot --headless --path . -s res://tools/validate_lavender.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm: gates belong to the group of the route they open
## onto, so the Route 8 gate is a LAVENDER map rather than a SAFFRON one.
const SAFFRON_GROUP: int = 25
const SAFFRON_CITY: int = 2
const LAVENDER_GROUP: int = 18
const ROUTE_8: int = 1
const ROUTE_12: int = 2
const ROUTE_10_SOUTH: int = 3
const LAVENDER_TOWN: int = 4
const LAV_RADIO_TOWER_1F: int = 12
const ROUTE_8_SAFFRON_GATE: int = 13

## `maps/SaffronCity.asm` warp 14, and the gate cells on either side of it.
const SAFFRON_GATE_DOOR: Vector2i = Vector2i(39, 22)
const GATE_FROM_CITY: Vector2i = Vector2i(0, 4)
const GATE_TO_ROUTE: Vector2i = Vector2i(9, 4)
const ROUTE_8_FROM_GATE: Vector2i = Vector2i(4, 4)

## Route 8 and the one cell of its east edge a walk from the gate can reach.
const ROUTE_8_CELLS: int = 322
const ROUTE_8_EAST_EDGE: Vector2i = Vector2i(39, 8)
const LAVENDER_FROM_ROUTE_8: Vector2i = Vector2i(0, 8)
## The ledges that decide which trainers the walk owes. `$a3` is COLL_HOP_DOWN.
const COLL_HOP_DOWN: int = 0xA3
const ROUTE_8_LEDGES: Array[Vector2i] = [
	Vector2i(12, 6), Vector2i(13, 6), Vector2i(14, 6), Vector2i(15, 6),
	Vector2i(12, 8), Vector2i(13, 8), Vector2i(14, 8), Vector2i(15, 8),
]
## The three bikers are identical in both pins; both Super Nerds are a profile
## split, so their cells are read off the cache rather than pinned here. Object
## index 4 is Tom either way, and his is the only unavoidable line.
const ROUTE_8_BIKERS: Array = [
	[0, Vector2i(10, 8)], [1, Vector2i(10, 9)], [2, Vector2i(10, 10)],
]
const ROUTE_8_UNAVOIDABLE_SIGHT: int = 4

## Lavender Town: its region, the radio tower door and the two edges it opens.
const LAVENDER_CELLS: int = 155
const RADIO_TOWER_DOOR: Vector2i = Vector2i(14, 5)
const RADIO_TOWER_WARP: int = 7
const LAVENDER_NORTH_EDGE_COLUMNS: Array[int] = [6, 7, 8, 9, 10, 11]
const LAVENDER_SOUTH_EDGE_COLUMNS: Array[int] = [8, 9]
const ENGINE_FLYPOINT_LAVENDER: int = 59
const ENGINE_FLYPOINT_LAVENDER_GOLD_SILVER: int = 58

## `maps/LavRadioTower1F.asm`: the tower's own landing, the gentleman on (9,1)
## and the cell he is faced from. ENGINE_EXPN_CARD is three in both pins, sitting
## in wPokegearFlags ahead of the Crystal-only ENGINE_MOBILE_SYSTEM.
const TOWER_LANDING: Vector2i = Vector2i(2, 7)
const GENTLEMAN_INDEX: int = 3
const GENTLEMAN_CELL: Vector2i = Vector2i(9, 1)
const GENTLEMAN_FACE: Vector2i = Vector2i(9, 2)
const ENGINE_EXPN_CARD: int = 3
const EVENT_RETURNED_MACHINE_PART: int = 201
const SCRIPT_STEP_BUDGET: int = 32

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_route_8_gate(data, game_id)
		_verify_route_8(data, game_id)
		_verify_lavender_town(data, game_id)
		_verify_expn_card(data, game_id)
	_finish()


## Saffron's east exit is a gate building, the third of its four exits to be one.
func _verify_route_8_gate(data: GameData, game_id: StringName) -> void:
	var city: Gen2WorldAPI = _open(data, SAFFRON_GROUP, SAFFRON_CITY, SAFFRON_GATE_DOOR)
	if city == null:
		return
	var warp: Dictionary = city.warp_at(SAFFRON_GATE_DOOR)
	_check(
		int(warp.get("map_group", -1)) == LAVENDER_GROUP
			and int(warp.get("map_number", -1)) == ROUTE_8_SAFFRON_GATE,
		"%s: Saffron's %s does not open onto the Route 8 gate." % [game_id, SAFFRON_GATE_DOOR]
	)
	var gate: Gen2WorldAPI = _open(
		data, LAVENDER_GROUP, ROUTE_8_SAFFRON_GATE, GATE_FROM_CITY
	)
	if gate == null:
		return
	_check(
		_region(gate, GATE_FROM_CITY).has(GATE_TO_ROUTE),
		"%s: the Route 8 gate's two doors are not joined on foot." % game_id
	)
	var far: Dictionary = gate.warp_at(GATE_TO_ROUTE)
	_check(
		int(far.get("map_group", -1)) == LAVENDER_GROUP
			and int(far.get("map_number", -1)) == ROUTE_8,
		"%s: the gate's %s does not open onto Route 8." % [game_id, GATE_TO_ROUTE]
	)
	print("%s route 8 gate: a gate building out of Saffron." % game_id)


## Route 8, and which of its five sight lines the walk east actually owes.
func _verify_route_8(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, LAVENDER_GROUP, ROUTE_8, ROUTE_8_FROM_GATE)
	if world == null:
		return
	var region: Dictionary = _region(world, ROUTE_8_FROM_GATE)
	_check(
		region.size() == ROUTE_8_CELLS,
		"%s: Route 8 is %d cells from the gate, not the pinned %d." % [
			game_id, region.size(), ROUTE_8_CELLS,
		]
	)
	var east: Array[Vector2i] = []
	for y: int in world.map_size_cells().y:
		var edge := Vector2i(world.map_size_cells().x - 1, y)
		if region.has(edge):
			east.append(edge)
	_check(
		east == [ROUTE_8_EAST_EDGE],
		"%s: Route 8's east edge is reachable on %s, not %s alone." % [
			game_id, east, ROUTE_8_EAST_EDGE,
		]
	)
	var crossed: Gen2WorldAPI = _open(data, LAVENDER_GROUP, ROUTE_8, ROUTE_8_EAST_EDGE)
	if crossed != null:
		_check(
			bool(crossed.move_result(Vector2i.RIGHT).get("ok", false))
				and crossed.map_id() == Vector2i(LAVENDER_GROUP, LAVENDER_TOWN)
				and crossed.player_cell == LAVENDER_FROM_ROUTE_8,
			"%s: %s does not cross onto Lavender's %s." % [
				game_id, ROUTE_8_EAST_EDGE, LAVENDER_FROM_ROUTE_8,
			]
		)
	for ledge: Vector2i in ROUTE_8_LEDGES:
		_check(
			world.collision_code_at(ledge) == COLL_HOP_DOWN,
			"%s: Route 8's %s is $%02x, not the pinned hop-down $%02x." % [
				game_id, ledge, world.collision_code_at(ledge), COLL_HOP_DOWN,
			]
		)
	for biker: Array in ROUTE_8_BIKERS:
		var object: Gen2WorldObject = world.objects[biker[0]]
		_check(
			object.cell == biker[1]
				and object.facing == Gen2WorldSprite.FACING_LEFT
				and object.object_type == Gen2WorldObject.OBJECTTYPE_TRAINER
				and object.sight_range == 5,
			"%s: biker %d is %s facing %d with sight %d, not %s facing left with 5." % [
				game_id, biker[0], object.cell, object.facing, object.sight_range, biker[1],
			]
		)

	# The load-bearing part: every line is measured off the cache, and only one
	# of them seals the east edge when it is shut.
	var lines: Dictionary = _sight_lines(data, region)
	_check(
		lines.size() == ROUTE_8_BIKERS.size() + 2,
		"%s: Route 8 has %d sight lines on its walkable cells, not five." % [
			game_id, lines.size(),
		]
	)
	var everything: Dictionary = {}
	for index: int in lines:
		var line: Dictionary = lines[index]
		var open: bool = _region(world, ROUTE_8_FROM_GATE, line).has(ROUTE_8_EAST_EDGE)
		_check(
			open == (index != ROUTE_8_UNAVOIDABLE_SIGHT),
			"%s: shutting object %d's line %s %s the east edge, the wrong way round." % [
				game_id, index, line.keys(), "leaves open" if open else "seals",
			]
		)
		for cell: Vector2i in line:
			everything[cell] = true
	_check(
		not _region(world, ROUTE_8_FROM_GATE, everything).has(ROUTE_8_EAST_EDGE),
		"%s: Route 8's east edge is reachable past all five sight lines." % game_id
	)
	print("%s route 8: 322 cells, one east crossing, eight ledges and one owed trainer." % game_id)


## Lavender Town: no gate of its own, and the two edges it opens northward and
## southward.
func _verify_lavender_town(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(
		data, LAVENDER_GROUP, LAVENDER_TOWN, LAVENDER_FROM_ROUTE_8
	)
	if world == null:
		return
	var flypoint: int = ENGINE_FLYPOINT_LAVENDER if Gen2WorldState.is_crystal_profile(data) \
		else ENGINE_FLYPOINT_LAVENDER_GOLD_SILVER
	_check(
		world.state.is_engine_flag_active(flypoint),
		"%s: LavenderTownFlypointCallback did not set engine flag %d on arrival." % [
			game_id, flypoint,
		]
	)
	var region: Dictionary = _region(world, LAVENDER_FROM_ROUTE_8)
	_check(
		region.size() == LAVENDER_CELLS,
		"%s: Lavender Town is %d cells, not the pinned %d." % [
			game_id, region.size(), LAVENDER_CELLS,
		]
	)
	_check(
		world.warp_index_at(RADIO_TOWER_DOOR) == RADIO_TOWER_WARP
			and region.has(RADIO_TOWER_DOOR),
		"%s: %s is not the reachable Radio Tower door." % [game_id, RADIO_TOWER_DOOR]
	)
	for axis: String in ["north", "south"]:
		var expected: Array[int] = LAVENDER_NORTH_EDGE_COLUMNS if axis == "north" \
			else LAVENDER_SOUTH_EDGE_COLUMNS
		var target: int = ROUTE_10_SOUTH if axis == "north" else ROUTE_12
		var columns: Array[int] = []
		for entry: Array in _crossings(data, LAVENDER_GROUP, LAVENDER_TOWN, world, axis):
			_check(
				entry[1] == Vector2i(LAVENDER_GROUP, target),
				"%s: Lavender's %s crossing on %s lands on %s, not %d/%d." % [
					game_id, axis, entry[0], entry[1], LAVENDER_GROUP, target,
				]
			)
			columns.append(int((entry[0] as Vector2i).x))
		_check(
			columns == expected,
			"%s: Lavender crosses %s on columns %s, not %s." % [
				game_id, axis, columns, expected,
			]
		)
	print("%s lavender town: 155 cells, a flypoint, the tower door and two open edges." % game_id)


## The gentleman inside, whose EXPN CARD the Cascade Badge's own errand unlocks.
func _verify_expn_card(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(
		data, LAVENDER_GROUP, LAV_RADIO_TOWER_1F, TOWER_LANDING
	)
	if world == null:
		return
	var gentleman: Gen2WorldObject = world.objects[GENTLEMAN_INDEX]
	_check(
		gentleman.cell == GENTLEMAN_CELL,
		"%s: the Radio Tower gentleman is on %s, not %s." % [
			game_id, gentleman.cell, GENTLEMAN_CELL,
		]
	)
	_check(
		_region(world, TOWER_LANDING).has(GENTLEMAN_FACE),
		"%s: the tower's door cannot reach %s." % [game_id, GENTLEMAN_FACE]
	)

	# Without the machine part he only complains about the Power Plant.
	var refused: Gen2WorldAPI = _open(
		data, LAVENDER_GROUP, LAV_RADIO_TOWER_1F, GENTLEMAN_FACE
	)
	if refused == null:
		return
	_check(
		not _talk(refused).is_empty()
			and not refused.state.is_engine_flag_active(ENGINE_EXPN_CARD),
		"%s: the gentleman handed over the EXPN CARD with the plant still down." % game_id
	)

	# With it, once.
	var state := Gen2WorldState.new()
	state.set_event_flag(EVENT_RETURNED_MACHINE_PART, true)
	var given: Gen2WorldAPI = Gen2WorldAPI.open(
		data, LAVENDER_GROUP, LAV_RADIO_TOWER_1F, GENTLEMAN_FACE, state
	)
	if given == null:
		_fail("%s: Radio Tower 1F is missing." % game_id)
		return
	var _entry: Array = given.dispatch_map_entry()
	_check(
		not _talk(given).is_empty()
			and given.state.is_engine_flag_active(ENGINE_EXPN_CARD),
		"%s: the gentleman did not set ENGINE_EXPN_CARD after the machine part." % game_id
	)
	# A second talk reaches .GotExpnCard, which writes nothing.
	_check(
		not _talk(given).is_empty()
			and given.state.is_engine_flag_active(ENGINE_EXPN_CARD),
		"%s: talking to the gentleman again did not finish." % game_id
	)
	print("%s lavender radio tower: the EXPN CARD waits on the Power Plant." % game_id)


## Faces the gentleman and presses through his script. Returns the statuses it
## saw, empty when the script never finished.
func _talk(world: Gen2WorldAPI) -> Array:
	world.player_facing = Gen2WorldSprite.FACING_UP
	var statuses: Array = []
	var results: Array = world.interact()
	for _step: int in SCRIPT_STEP_BUDGET:
		if results.is_empty():
			return []
		var status: StringName = StringName(results[0].get("status", &""))
		statuses.append(status)
		if status == &"complete":
			return statuses
		if status != &"waiting":
			return []
		if not world.pending_script_wait().is_empty():
			results = world.finish_script_waits()
			continue
		results = world.run_event_queue(true)
	return []


## Every cell in [param region] a trainer sees the player on, as object index to
## the set of cells.
func _sight_lines(data: GameData, region: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in region:
		var probe: Gen2WorldAPI = _open(data, LAVENDER_GROUP, ROUTE_8, cell)
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


func _open(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell, Gen2WorldState.new())
	if world == null:
		_fail("map %d/%d is missing." % [group, number])
		return null
	var _entry: Array = world.dispatch_map_entry()
	return world


## Every crossing off [param axis] a walk from [param world]'s own cell can take,
## as [edge cell, landed map, landed cell]. Each attempt gets its own world,
## since a crossing moves the one it was taken on.
func _crossings(
	data: GameData, group: int, number: int, world: Gen2WorldAPI, axis: String
) -> Array:
	var size: Vector2i = world.map_size_cells()
	var direction: Vector2i = Vector2i.UP if axis == "north" else Vector2i.DOWN
	var region: Dictionary = _region(world, world.player_cell)
	var out: Array = []
	for x: int in size.x:
		var edge: Vector2i = Vector2i(x, 0) if axis == "north" else Vector2i(x, size.y - 1)
		if not region.has(edge):
			continue
		var attempt: Gen2WorldAPI = _open(data, group, number, edge)
		if attempt == null:
			continue
		if bool(attempt.move_result(direction).get("ok", false)):
			out.append([edge, attempt.map_id(), attempt.player_cell])
	return out


## Ledge hops included, the way `tools/preview_world_story.gd`'s own
## _reachable_step() walks: Route 8 is the map where leaving them out would claim
## a wall of three bikers the eastbound walk never meets.
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


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS lavender: the Saffron gate, Route 8's one owed trainer, the town and the EXPN CARD verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL lavender: %d problems." % _failures.size())
	quit(1)
