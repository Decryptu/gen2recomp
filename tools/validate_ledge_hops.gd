extends SceneTree

## Verifies ledge hopping against freshly imported real caches, for both
## command profiles. The expected codes come from the pinned pokecrystal and
## pokegold sources: engine/overworld/player_movement.asm's .TryJump, its
## .ledge_table, and data/collision/collision_permissions.asm.
##
## This is the real-cartridge counterpart to tests/unit/test_world_collision.gd
## and the ledge cases in tests/unit/test_world_api.gd, which use synthetic
## caches. It also pins the reason tools/preview_world_story.gd still reopens
## in Violet City instead of walking Route 30: the terrain and the hops carry
## the route, while a static search over occupied cells does not.
##
##   Godot --headless --path . -s res://tools/validate_ledge_hops.gd

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

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in [&"crystal", &"gold"]:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_permissions(game_id)
		_verify_route30(game_id, data)
	_finish()


## The eight hop codes stay LAND_TILE, which is what makes .TryStep walk onto
## a ledge cell normally and leaves .TryJump reachable only after the step
## into the faced cell is blocked.
func _verify_permissions(game_id: StringName) -> void:
	for code: int in range(0xA0, 0xA8):
		_check(
			Gen2WorldCollision.permission_for(code) == Gen2WorldCollision.LAND_TILE,
			"%s: hop code $%02X is not LAND_TILE." % [game_id, code]
		)
	var expected: Dictionary = {
		0xA0: Vector2i.RIGHT, 0xA1: Vector2i.LEFT, 0xA2: Vector2i.UP, 0xA3: Vector2i.DOWN,
	}
	for code: int in expected:
		_check(
			Gen2WorldCollision.allows_hop(code, expected[code]),
			"%s: hop code $%02X does not allow its own direction." % [game_id, code]
		)
		_check(
			not Gen2WorldCollision.allows_hop(code, -(expected[code] as Vector2i)),
			"%s: hop code $%02X allows its opposite direction." % [game_id, code]
		)


func _verify_route30(game_id: StringName, data: GameData) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ROUTE30_GROUP, ROUTE30_NUMBER, ROUTE30_ENTRY, Gen2WorldState.new()
	)
	if not _check(world != null, "%s: Route 30 map 26/1 is missing." % game_id):
		return

	# The imported ledge row decodes as COLL_HOP_DOWN with a wall beneath, so
	# an ordinary step bumps and .TryJump is what carries the player across.
	for column: int in ROUTE30_HOP_COLUMNS:
		var cell := Vector2i(column, ROUTE30_HOP_ROW)
		var code: int = world.collision_code_at(cell)
		_check(
			code == Gen2WorldCollision.COLL_HOP_DOWN,
			"%s: Route 30 %s is $%02X, not COLL_HOP_DOWN." % [game_id, cell, code]
		)
		_check(
			not world.can_walk_to(cell + Vector2i.DOWN),
			"%s: Route 30 %s has no wall below it." % [game_id, cell]
		)
		_check(
			Gen2WorldCollision.allows_hop(code, Vector2i.DOWN),
			"%s: Route 30 %s refuses a downward hop." % [game_id, cell]
		)

	# A hop from the ledge row commits two cells in one action.
	var hop_world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ROUTE30_GROUP, ROUTE30_NUMBER,
		Vector2i(ROUTE30_HOP_COLUMNS[0], ROUTE30_HOP_ROW), Gen2WorldState.new()
	)
	var hop: Dictionary = hop_world.move_result(Vector2i.DOWN)
	_check(
		bool(hop.get("ok", false)) and hop.get("kind", &"") == &"ledge_hop",
		"%s: Route 30 ledge did not produce a hop." % game_id
	)
	_check(
		hop_world.player_cell == Vector2i(ROUTE30_HOP_COLUMNS[0], ROUTE30_HOP_ROW + 2),
		"%s: Route 30 hop landed on %s, not two cells down." % [game_id, hop_world.player_cell]
	)

	# The northward corridor is ordinary floor the whole way to the north
	# edge, so nothing about the terrain blocks the route to Route 31.
	for column: int in ROUTE30_CORRIDOR_COLUMNS:
		for row: int in range(0, 8):
			var cell := Vector2i(column, row)
			_check(
				Gen2WorldCollision.permission_for(
					world.collision_code_at(cell)
				) == Gen2WorldCollision.LAND_TILE,
				"%s: Route 30 corridor cell %s is not land." % [game_id, cell]
			)

	# Terrain reachability, which is what the hops contribute to, reaches the
	# north edge. The same search resolving live occupancy does not, because
	# Route 30 parks objects on the single passable cell of its row 25
	# chokepoint. That difference is the open limitation recorded in
	# tools/preview_world_story.gd, and pinning it here keeps a future change
	# to either side from going unnoticed.
	var terrain: Dictionary = _reachable(world, true)
	var occupied: Dictionary = _reachable(world, false)
	_check(
		_reaches_north_edge(world, terrain),
		"%s: Route 30 north edge is unreachable even ignoring occupancy." % game_id
	)
	_check(
		not _reaches_north_edge(world, occupied),
		"%s: Route 30 north edge is now reachable through occupied cells; the story preview can walk the route and its Violet City reopen should be replaced." % game_id
	)
	_check(
		terrain.size() > occupied.size(),
		"%s: ignoring occupancy did not widen Route 30 reachability." % game_id
	)

	# No assertion is made that hops widen whole-map reachability. A ledge is
	# a shortcut, so the cells past it are normally also reachable the long
	# way round, and on Route 30 they are: a search with hops disabled finds
	# the same terrain. The evidence that the hop is load-bearing is local and
	# already checked above, where an ordinary step into the cell below the
	# ledge is refused and the hop crosses it anyway.


## Breadth-first reachability from the player's cell, following ordinary steps
## and ledge hops the same way tools/preview_world_story.gd's _reachable_step
## does. [param terrain_only] resolves cells by collision permission alone,
## ignoring live object occupancy; otherwise it uses the same
## Gen2WorldAPI.can_walk_to() the runtime and the story preview use.
func _reachable(world: Gen2WorldAPI, terrain_only: bool) -> Dictionary:
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
				open = Gen2WorldCollision.permission_for(
					world.collision_code_at(direct)
				) == Gen2WorldCollision.LAND_TILE if terrain_only else world.can_walk_to(direct)
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


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS ledge hops: permissions, Route 30 hop records and reachability verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
