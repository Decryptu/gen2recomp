class_name Gen2WorldReachability
extends RefCounted

## Which maps a player can stand on with a given set of field moves, derived from
## the cartridge's own collision, warps and connections.
##
## The half of a progression proof that is not about rewards. A shuffled badge is
## only completable if the gym holding it can be WALKED to, and walking is gated
## by Surf, Cut, Strength, Whirlpool and Waterfall, each of which is gated by a
## badge. Nothing here is written down: the flood asks
## [Gen2WorldCollision] and [Gen2WorldFieldMove] the same questions
## `DoPlayerMovement` asks.
##
## The unit is the MAP, not the cell. A cell-exact frontier would be the truer
## model and is not the one to build: it would need the block-level surf rules,
## the ledge one-way tests and the forced-tile paths as a second copy of
## `Gen2WorldAPI`'s, and the two would drift. A map is reachable here when some
## walkable cell of it is, which is the granularity a placement is decided at
## anyway, since a check sits on a map.
##
## Deliberately CONSERVATIVE in one direction only: an edge is offered when the
## cartridge's own collision says a step across it is possible, so this can call
## a map reachable that a cell-exact walk would not. It never calls a reachable
## map unreachable, which is the direction that would reject a good seed.

## The moves an edge can ask for, in the order a report lists them.
const GATE_MOVES: Array[int] = [
	Gen2WorldFieldMove.MOVE_SURF,
	Gen2WorldFieldMove.MOVE_CUT,
	Gen2WorldFieldMove.MOVE_WHIRLPOOL,
	Gen2WorldFieldMove.MOVE_WATERFALL,
]

## Guard on the flood, not a limit anything real reaches: Crystal has 388 maps.
const MAX_MAPS: int = 1024

var _data: GameData = null
## Move-set key to the exit graph that move set opens: map key to the map keys
## its usable exits lead to. See [method _edges_for].
var _edges: Dictionary = {}


static func build(data: GameData) -> Gen2WorldReachability:
	var out := Gen2WorldReachability.new()
	out._data = data
	return out


static func map_key(group: int, number: int) -> int:
	return (group & 0xFF) << 8 | (number & 0xFF)


## Every map reachable from [param start] with [param moves] in hand, as a set of
## [method map_key]s. The moves are the field moves the player can actually USE,
## which is the caller's job to work out: an HM without its badge is not one.
func reachable(start: Vector2i, moves: Dictionary) -> Dictionary:
	if _data == null:
		return {}
	var edges: Dictionary = _edges_for(moves)
	var out: Dictionary = {}
	var frontier: Array = [map_key(start.x, start.y)]
	out[frontier[0]] = true
	for _step: int in MAX_MAPS:
		if frontier.is_empty():
			break
		var next: Array = []
		for key: int in frontier:
			for target: int in edges.get(key, []):
				if out.has(target):
					continue
				out[target] = true
				next.append(target)
		frontier = next
	return out


## The fewest moves that make [param to_key] reachable from the start, or an
## empty array when it already is. What a report names when a placement puts
## something behind a move the seed cannot reach.
func gates_for(start: Vector2i, to_key: int) -> Array:
	if reachable(start, {}).has(to_key):
		return []
	for count: int in GATE_MOVES.size():
		for mask: int in 1 << GATE_MOVES.size():
			var moves: Dictionary = {}
			for index: int in GATE_MOVES.size():
				if (mask & (1 << index)) != 0:
					moves[GATE_MOVES[index]] = true
			if moves.size() != count + 1:
				continue
			if reachable(start, moves).has(to_key):
				return moves.keys()
	return GATE_MOVES.duplicate()


func map_count() -> int:
	return _data.world_maps().size() if _data != null else 0


## One pass over every map: which of its exits are usable with which moves,
## worked out by FLOODING the map's own collision grid from the cells a player
## arrives on. An exit the flood cannot touch without Surf is a Surf exit.
##
## Taken once per move set rather than once, because the flood is what the moves
## change: with Cut in hand a tree stops being a wall and a whole wing of a map
## opens. [method reachable] asks for the set it needs and the answer is kept.
func _edges_for(moves: Dictionary) -> Dictionary:
	var key: int = _moves_key(moves)
	if _edges.has(key):
		return _edges[key]
	var out: Dictionary = {}
	for map: Gen2WorldMap in _data.world_maps():
		var tileset: Gen2WorldTileset = _data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var world := Gen2WorldAPI.new(
			_data, map, tileset, Vector2i.ZERO, Gen2WorldState.new()
		)
		out[map_key(map.group, map.number)] = _exits(world, map, moves)
	_edges[key] = out
	return out


## The maps one map's usable exits lead to. An exit is usable when it stands in
## the same flooded region as some cell a player can arrive on.
func _exits(world: Gen2WorldAPI, map: Gen2WorldMap, moves: Dictionary) -> Array:
	var region: Dictionary = _flood(world, map, moves)
	var out: Array = []
	var seen: Dictionary = {}
	for raw: Variant in map.events.get("warps", []):
		if not raw is Dictionary:
			continue
		var warp: Dictionary = raw as Dictionary
		if not region.has(_cell_key(int(warp.get("x", 0)), int(warp.get("y", 0)))):
			continue
		var target: int = map_key(
			int(warp.get("map_group", 0)), int(warp.get("map_number", 0))
		)
		if not seen.has(target):
			seen[target] = true
			out.append(target)
	for raw: Variant in map.connections:
		if not raw is Dictionary:
			continue
		var connection: Dictionary = raw as Dictionary
		if not _edge_reached(region, map, String(connection.get("direction", ""))):
			continue
		var target: int = map_key(
			int(connection.get("map_group", 0)), int(connection.get("map_number", 0))
		)
		if not seen.has(target):
			seen[target] = true
			out.append(target)
	return out


## Every cell a player standing anywhere on the map could get to, as a set. The
## seeds are every warp cell and every edge cell, since a player arrives through
## one of those; a region no seed touches is not part of the map for this.
func _flood(world: Gen2WorldAPI, map: Gen2WorldMap, moves: Dictionary) -> Dictionary:
	var region: Dictionary = {}
	var frontier: Array = []
	for raw: Variant in map.events.get("warps", []):
		if raw is Dictionary:
			_seed(world, map, moves, region, frontier,
				Vector2i(int((raw as Dictionary).get("x", 0)), int((raw as Dictionary).get("y", 0))))
	for x: int in map.collision_width:
		_seed(world, map, moves, region, frontier, Vector2i(x, 0))
		_seed(world, map, moves, region, frontier, Vector2i(x, map.collision_height - 1))
	for y: int in map.collision_height:
		_seed(world, map, moves, region, frontier, Vector2i(0, y))
		_seed(world, map, moves, region, frontier, Vector2i(map.collision_width - 1, y))
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			_seed(world, map, moves, region, frontier, cell + step)
	return region


func _seed(
	world: Gen2WorldAPI, map: Gen2WorldMap, moves: Dictionary, region: Dictionary,
	frontier: Array, cell: Vector2i
) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.collision_width \
		or cell.y >= map.collision_height:
		return
	var key: int = _cell_key(cell.x, cell.y)
	if region.has(key) or not _standable(world.collision_code_at(cell), moves):
		return
	region[key] = true
	frontier.append(cell)


## Whether a player with [param moves] can be on a cell of this code. The four
## water gates are the cartridge's own tile tests; everything else is the
## permission byte, which is what makes a wall a wall.
static func _standable(code: int, moves: Dictionary) -> bool:
	match Gen2WorldCollision.permission_for(code):
		Gen2WorldCollision.LAND_TILE:
			return true
		Gen2WorldCollision.WATER_TILE:
			if Gen2WorldFieldMove.waterfall_tile(code):
				return moves.has(Gen2WorldFieldMove.MOVE_WATERFALL)
			if Gen2WorldFieldMove.whirlpool_tile(code):
				return moves.has(Gen2WorldFieldMove.MOVE_WHIRLPOOL)
			return moves.has(Gen2WorldFieldMove.MOVE_SURF)
	## A cut tree is not walkable until it is cut, and then it is ordinary ground.
	return Gen2WorldFieldMove.cuttable(code) and moves.has(Gen2WorldFieldMove.MOVE_CUT)


## Whether the flood touched the side a connection leaves by.
static func _edge_reached(region: Dictionary, map: Gen2WorldMap, direction: String) -> bool:
	match direction:
		"north", "south":
			var y: int = 0 if direction == "north" else map.collision_height - 1
			for x: int in map.collision_width:
				if region.has(_cell_key(x, y)):
					return true
		"west", "east":
			var x: int = 0 if direction == "west" else map.collision_width - 1
			for y: int in map.collision_height:
				if region.has(_cell_key(x, y)):
					return true
	return false


static func _cell_key(x: int, y: int) -> int:
	return (x & 0xFF) << 8 | (y & 0xFF)


## A move set as one number, so a flood taken for it can be found again.
static func _moves_key(moves: Dictionary) -> int:
	var key: int = 0
	for index: int in GATE_MOVES.size():
		if moves.has(GATE_MOVES[index]):
			key |= 1 << index
	return key
