extends SceneTree

## Verifies why the walked route stops on Route 27, against freshly imported
## real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `maps/Route27.asm`, `maps/TohjoFalls.asm` and
## `engine/overworld/player_movement.asm`. `TohjoFalls.blk` is byte identical
## between the pins; `Route27.blk` is not, so its land census is profile split
## while every water figure happens to match.
##
## The claim being pinned is a negative one, and negative claims rot quietly.
## Route 27's landfall region reaches no map edge; the only crossing of the
## channel east of it starts in a pocket that can only be left through Tohjo
## Falls; and the cave's two lower channels reach each other only over
## `COLL_WATERFALL` cells, which `.CheckTile` will only ever step a player down.
## So Route 26 and everything past it need HM07 and a Waterfall field move. When
## one lands, this tool is what says so.
##
##   Godot --headless -s res://tools/validate_route_27.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## data/maps/maps.asm group/number pairs. Route 27 sits at the same pair in both
## games; Crystal's own extra maps push Tohjo Falls nine places down the
## Dungeons group.
const ROUTE_27: Array = [24, 2]
const TOHJO_FALLS: Dictionary = {
	&"gold": [3, 74],
	&"silver": [3, 74],
	&"crystal": [3, 83],
}

## Route 27. The landfall is the cell a surf from New Bark Town comes ashore on,
## and one of the two SCENE_ROUTE27_FIRST_STEP_INTO_KANTO coord cells. The two
## mouths are Tohjo Falls' doors, the pocket is the cell below the east mouth,
## and the shore is the pocket's own edge on the channel.
const LANDFALL: Vector2i = Vector2i(18, 10)
const WEST_MOUTH: Vector2i = Vector2i(26, 5)
const EAST_MOUTH: Vector2i = Vector2i(36, 5)
const EAST_POCKET: Vector2i = Vector2i(36, 6)
const POCKET_SHORE: Vector2i = Vector2i(39, 6)
const LANDFALL_WATER: Vector2i = Vector2i(18, 9)
const CHANNEL_WATER: Vector2i = Vector2i(42, 6)
const EAST_WATER: Vector2i = Vector2i(79, 8)

## Route 27's three water bodies, identical in both pins: the sea New Bark's
## crossing arrives on, the channel the east pocket surfs, and the sea on the
## Route 26 edge.
const WEST_SEA_CELLS: int = 120
const CHANNEL_CELLS: int = 48
const EAST_SEA_CELLS: int = 12

## Tohjo Falls. The two lower channels each touch their own door's land, and the
## pool is what the waterfalls fall from.
const WEST_CHANNEL: Vector2i = Vector2i(9, 14)
const EAST_CHANNEL: Vector2i = Vector2i(21, 14)
const POOL: Vector2i = Vector2i(12, 4)
const WEST_CHANNEL_CELLS: int = 40
const EAST_CHANNEL_CELLS: int = 34
const POOL_CELLS: int = 144
## TILESET_CAVE block $2c is four WATERFALL quadrants and the cave writes ten of
## them (`data/tilesets/cave_collision.asm`). COLL_WATERFALL is $33.
const COLL_WATERFALL: int = 0x33
const WATERFALL_CELLS: int = 40

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var _failures: PackedStringArray = []


func _initialize() -> void:
	_verify_forced_tiles()
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_route_27(data, game_id)
		_verify_tohjo_falls(data, game_id)
	_finish()


## `.CheckTile`'s `.warps` branch: four codes force a step DOWN and every other
## $7x falls through to `.no_walk`. That one table is what makes a cave mouth a
## one-way doorway, so a player leaving one always ends south of it.
func _verify_forced_tiles() -> void:
	for code: int in [
		Gen2WorldCollision.COLL_DOOR, Gen2WorldCollision.COLL_DOOR_79,
		Gen2WorldCollision.COLL_STAIRCASE, Gen2WorldCollision.COLL_CAVE,
	]:
		var forced: Dictionary = Gen2WorldCollision.forced_action(code)
		_check(
			StringName(forced.get("kind", &"none")) == &"walk"
				and forced.get("direction", Vector2i.ZERO) == Vector2i.DOWN,
			"$%02x does not force a step down, so a cave mouth is not one-way." % code
		)
	for code: int in range(0x70, 0x80):
		if Gen2WorldCollision.WARP_STEP_CODES.has(code):
			continue
		_check(
			StringName(Gen2WorldCollision.forced_action(code).get("kind", &"none")) == &"none",
			"$%02x forces a step, but .warps accepts only four codes." % code
		)


## The landfall region is sealed, and the pocket that could leave it is on the
## far side of a cave door.
func _verify_route_27(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, ROUTE_27, LANDFALL)
	if world == null:
		_fail("%s: Route 27 is missing." % game_id)
		return
	var size: Vector2i = world.map_size_cells()

	for mouth: Vector2i in [WEST_MOUTH, EAST_MOUTH]:
		_check(
			world.collision_code_at(mouth) == Gen2WorldCollision.COLL_CAVE
				and not world.warp_at(mouth).is_empty(),
			"%s: Route 27's mouth at %s is not a COLL_CAVE warp." % [game_id, mouth]
		)

	var region: Dictionary = _region(world, LANDFALL)
	var on_edge: bool = false
	for y: int in size.y:
		on_edge = on_edge or region.has(Vector2i(size.x - 1, y))
	_check(
		not on_edge,
		"%s: Route 27's landfall region reaches the Route 26 edge on foot." % game_id
	)
	_check(
		not region.has(EAST_POCKET) and not region.has(POCKET_SHORE),
		"%s: Route 27's landfall region reaches the east pocket without the cave." % game_id
	)

	# Surfing does not get around it either: the sea the crossing from New Bark
	# arrives on touches neither the channel nor the Route 26 edge.
	var west_sea: Dictionary = _swim(world, LANDFALL_WATER)
	_check(
		west_sea.size() == WEST_SEA_CELLS,
		"%s: Route 27's west sea is %d cells, not the pinned %d." % [
			game_id, west_sea.size(), WEST_SEA_CELLS,
		]
	)
	_check(
		not west_sea.has(CHANNEL_WATER) and not west_sea.has(EAST_WATER),
		"%s: Route 27's west sea reaches the channel or the east sea." % game_id
	)
	_check(
		_swim(world, CHANNEL_WATER).size() == CHANNEL_CELLS,
		"%s: Route 27's channel is not %d cells." % [game_id, CHANNEL_CELLS]
	)
	_check(
		_swim(world, EAST_WATER).size() == EAST_SEA_CELLS,
		"%s: Route 27's east sea is not %d cells." % [game_id, EAST_SEA_CELLS]
	)


## The cave the pocket is behind cannot be crossed: its two lower channels only
## ever receive the pool, never reach it.
func _verify_tohjo_falls(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, TOHJO_FALLS[game_id], WEST_CHANNEL)
	if world == null:
		_fail("%s: Tohjo Falls is missing." % game_id)
		return
	var size: Vector2i = world.map_size_cells()

	var waterfalls: int = 0
	for y: int in size.y:
		for x: int in size.x:
			if world.collision_code_at(Vector2i(x, y)) == COLL_WATERFALL:
				waterfalls += 1
	_check(
		waterfalls == WATERFALL_CELLS,
		"%s: Tohjo Falls has %d waterfall cells, not the pinned %d." % [
			game_id, waterfalls, WATERFALL_CELLS,
		]
	)

	var west: Dictionary = _swim(world, WEST_CHANNEL)
	var east: Dictionary = _swim(world, EAST_CHANNEL)
	var pool: Dictionary = _swim(world, POOL)
	_check(
		west.size() == WEST_CHANNEL_CELLS and east.size() == EAST_CHANNEL_CELLS
			and pool.size() == POOL_CELLS,
		"%s: Tohjo Falls' bodies are %d/%d/%d, not the pinned %d/%d/%d." % [
			game_id, west.size(), east.size(), pool.size(),
			WEST_CHANNEL_CELLS, EAST_CHANNEL_CELLS, POOL_CELLS,
		]
	)
	_check(
		not west.has(EAST_CHANNEL) and not west.has(POOL),
		"%s: Tohjo Falls' west channel climbs out without Waterfall." % game_id
	)
	_check(
		not east.has(WEST_CHANNEL) and not east.has(POOL),
		"%s: Tohjo Falls' east channel climbs out without Waterfall." % game_id
	)
	_check(
		pool.has(WEST_CHANNEL) and pool.has(EAST_CHANNEL),
		"%s: Tohjo Falls' pool does not fall into both channels." % game_id
	)


func _open(data: GameData, id: Array, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, id[0], id[1], cell, Gen2WorldState.new())
	if world == null:
		return null
	var _entry: Array = world.dispatch_map_entry()
	for _step: int in 8:
		if world.pending_script_input().is_empty():
			break
		world.run_event_queue(true)
	return world


## Plain walking reachability, the way tools/preview_world_story.gd's
## _reachable_step() has it: a warp tile is a wall, because stepping onto one
## takes it.
func _region(world: Gen2WorldAPI, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for step: Vector2i in STEPS:
			var next: Vector2i = cell + step
			if seen.has(next) or not world.can_walk_to(next, step):
				continue
			if not world.warp_at(next).is_empty() \
				and Gen2WorldCollision.is_warp_tile(world.collision_code_at(next)):
				continue
			var face: int = Gen2WorldCollision.face_mask_for_direction(step)
			if face != 0 and (world.tile_permissions_at(cell) & face) != 0:
				continue
			seen[next] = true
			frontier.append(next)
	return seen


## Surfing reachability with the source `.CheckTile` rule applied: a player
## standing on a waterfall cell has the pressed direction discarded and is
## stepped down, so a waterfall is an edge that only ever points one way.
func _swim(world: Gen2WorldAPI, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		var forced: Dictionary = Gen2WorldCollision.forced_action(world.collision_code_at(cell))
		for step: Vector2i in STEPS:
			if StringName(forced.get("kind", &"none")) == &"walk" \
				and forced.get("direction", Vector2i.ZERO) != step:
				continue
			var next: Vector2i = cell + step
			if seen.has(next) \
				or world.collision_permission_at(next) != Gen2WorldCollision.WATER_TILE:
				continue
			var face: int = Gen2WorldCollision.face_mask_for_direction(step)
			if face != 0 and (world.tile_permissions_at(cell) & face) != 0:
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
		print("PASS route 27: the landfall is sealed and Tohjo Falls needs Waterfall.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL route 27: %d problems." % _failures.size())
	quit(1)
