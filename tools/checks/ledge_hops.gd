extends RefCounted

var _r: RefCounted = null

## Verifies ledge hopping against freshly imported real caches, for both
## command profiles. The expected codes come from the pinned pokecrystal and
## pokegold sources: engine/overworld/player_movement.asm's .TryJump, its
## .ledge_table, and data/collision/collision_permissions.asm.
##
## The real-cartridge counterpart to tests/unit/test_world_collision.gd and the
## ledge cases in tests/unit/test_world_api.gd, which use synthetic caches. It
## also pins what gates Route 30's corridor north, which
## tools/preview_world_story.gd walks: terrain and hops carry the route, and
## EVENT_ROUTE_30_BATTLE opens the last two cells.
##
##   Godot --headless --path . -s res://tools/validate.gd -- ledge_hops

const ROUTE30_GROUP: int = 26
const ROUTE30_NUMBER: int = 1
## The Cherrygrove-side entry cell, matching the connection the story preview
## walks through (data/maps/attributes.asm, CherrygroveCity north, offset 5).
const ROUTE30_ENTRY := Vector2i(7, 53)
## Route30's southbound ledge above the row 25 chokepoint: four COLL_HOP_DOWN
## cells at row 24 with wall below, so the hop lands on row 26.
const ROUTE30_HOP_ROW: int = 24
const ROUTE30_HOP_COLUMNS: Array[int] = [2, 3, 4]
## The northward corridor is plain floor from row 7 to the map's north edge.
const ROUTE30_CORRIDOR_COLUMNS: Array[int] = [6, 7]
## constants/event_flags.asm's EVENT_ROUTE_30_BATTLE, carried by the objects
## standing on the corridor north and set by maps/ElmsLab.asm.
const ROUTE30_BATTLE_EVENT_FLAG: int = 1812


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in [&"crystal", &"gold"]:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_permissions(game_id)
		_verify_route30(game_id, data)


## The eight hop codes stay LAND_TILE, which is what makes .TryStep walk onto
## a ledge cell normally and leaves .TryJump reachable only after the step
## into the faced cell is blocked.
func _verify_permissions(game_id: StringName) -> void:
	for code: int in range(0xA0, 0xA8):
		_r.check(
			Gen2WorldCollision.permission_for(code) == Gen2WorldCollision.LAND_TILE,
			"%s: hop code $%02X is not LAND_TILE." % [game_id, code]
		)
	var expected: Dictionary = {
		0xA0: Vector2i.RIGHT, 0xA1: Vector2i.LEFT, 0xA2: Vector2i.UP, 0xA3: Vector2i.DOWN,
	}
	for code: int in expected:
		_r.check(
			Gen2WorldCollision.allows_hop(code, expected[code]),
			"%s: hop code $%02X does not allow its own direction." % [game_id, code]
		)
		_r.check(
			not Gen2WorldCollision.allows_hop(code, -(expected[code] as Vector2i)),
			"%s: hop code $%02X allows its opposite direction." % [game_id, code]
		)


func _verify_route30(game_id: StringName, data: GameData) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ROUTE30_GROUP, ROUTE30_NUMBER, ROUTE30_ENTRY, Gen2WorldState.new()
	)
	if not _r.check(world != null, "%s: Route 30 map 26/1 is missing." % game_id):
		return

	# The imported ledge row decodes as COLL_HOP_DOWN with a wall beneath, so
	# an ordinary step bumps and .TryJump is what carries the player across.
	for column: int in ROUTE30_HOP_COLUMNS:
		var cell := Vector2i(column, ROUTE30_HOP_ROW)
		var code: int = world.collision_code_at(cell)
		_r.check(
			code == Gen2WorldCollision.COLL_HOP_DOWN,
			"%s: Route 30 %s is $%02X, not COLL_HOP_DOWN." % [game_id, cell, code]
		)
		_r.check(
			not world.can_walk_to(cell + Vector2i.DOWN),
			"%s: Route 30 %s has no wall below it." % [game_id, cell]
		)
		_r.check(
			Gen2WorldCollision.allows_hop(code, Vector2i.DOWN),
			"%s: Route 30 %s refuses a downward hop." % [game_id, cell]
		)

	# A hop from the ledge row commits two cells in one action.
	var hop_world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ROUTE30_GROUP, ROUTE30_NUMBER,
		Vector2i(ROUTE30_HOP_COLUMNS[0], ROUTE30_HOP_ROW), Gen2WorldState.new()
	)
	var hop: Dictionary = hop_world.move_result(Vector2i.DOWN)
	_r.check(
		bool(hop.get("ok", false)) and hop.get("kind", &"") == &"ledge_hop",
		"%s: Route 30 ledge did not produce a hop." % game_id
	)
	_r.check(
		hop_world.player_cell == Vector2i(ROUTE30_HOP_COLUMNS[0], ROUTE30_HOP_ROW + 2),
		"%s: Route 30 hop landed on %s, not two cells down." % [game_id, hop_world.player_cell]
	)

	# The northward corridor is ordinary floor the whole way to the north
	# edge, so nothing about the terrain blocks the route to Route 31.
	for column: int in ROUTE30_CORRIDOR_COLUMNS:
		for row: int in range(0, 8):
			var cell := Vector2i(column, row)
			_r.check(
				Gen2WorldCollision.permission_for(
					world.collision_code_at(cell)
				) == Gen2WorldCollision.LAND_TILE,
				"%s: Route 30 corridor cell %s is not land." % [game_id, cell]
			)

	# The corridor north is a story gate, not terrain or pathfinding. Two objects
	# stand on its single-cell rows 24 and 25, both carrying
	# EVENT_ROUTE_30_BATTLE, and CheckObjectFlag
	# (engine/overworld/map_objects_2.asm) masks an object whose flag is set.
	# maps/ElmsLab.asm's ElmAfterTheftScript sets it on the Mystery Egg handover,
	# so the route opens when the cartridge opens it. Both halves are pinned:
	# sealed before the egg return, walkable after, occupancy enforced in both.
	var occupied: Dictionary = _reachable(world)
	_r.check(
		not _reaches_north_edge(world, occupied),
		"%s: Route 30 north edge is reachable before EVENT_ROUTE_30_BATTLE is set." % game_id
	)

	var opened_state := Gen2WorldState.new()
	opened_state.set_event_flag(ROUTE30_BATTLE_EVENT_FLAG)
	var opened_world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ROUTE30_GROUP, ROUTE30_NUMBER, ROUTE30_ENTRY, opened_state
	)
	if not _r.check(opened_world != null, "%s: Route 30 did not reopen." % game_id):
		return
	_r.check(
		opened_world.object_at(Vector2i(5, 24)) == null
			and opened_world.object_at(Vector2i(5, 25)) == null,
		"%s: EVENT_ROUTE_30_BATTLE did not clear the corridor objects." % game_id
	)
	var opened: Dictionary = _reachable(opened_world)
	_r.check(
		_reaches_north_edge(opened_world, opened),
		"%s: Route 30 north edge is still unreachable after EVENT_ROUTE_30_BATTLE." % game_id
	)
	_r.check(
		opened.size() > occupied.size(),
		"%s: EVENT_ROUTE_30_BATTLE did not widen Route 30 reachability." % game_id
	)

	# No assertion is made that hops widen whole-map reachability. A ledge is
	# a shortcut, so the cells past it are normally also reachable the long
	# way round, and on Route 30 they are: a search with hops disabled finds
	# the same terrain. The evidence that the hop is load-bearing is local and
	# already checked above, where an ordinary step into the cell below the
	# ledge is refused and the hop crosses it anyway.


## Breadth-first reachability from the player's cell, following ordinary steps
## and ledge hops the same way tools/preview_world_story.gd's _reachable_step
## does. Cells resolve through the same Gen2WorldAPI.can_walk_to() the runtime
## and the story preview use, so live object occupancy counts.
func _reachable(world: Gen2WorldAPI) -> Dictionary:
	var size: Vector2i = world.map_size_cells()
	var frontier: Array[Vector2i] = [world.player_cell]
	var seen: Dictionary = {world.player_cell: true}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for step: Vector2i in directions:
			var direct: Vector2i = cell + step
			var next: Vector2i = Vector2i(-1, -1)
			var open: bool = false
			if direct.x >= 0 and direct.y >= 0 and direct.x < size.x and direct.y < size.y:
				open = world.can_walk_to(direct)
			if open:
				next = direct
			elif Gen2WorldCollision.allows_hop(world.collision_code_at(cell), step):
				var landing: Vector2i = cell + step * 2
				if landing.x >= 0 and landing.y >= 0 \
					and landing.x < size.x and landing.y < size.y:
					next = landing
			if next.x < 0 or seen.has(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen


func _reaches_north_edge(world: Gen2WorldAPI, seen: Dictionary) -> bool:
	for x: int in world.map_size_cells().x:
		if seen.has(Vector2i(x, 0)):
			return true
	return false
