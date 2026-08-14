extends RefCounted

var _r: RefCounted = null

## Verifies Vermilion City, its gym and the passage up from the dock against
## freshly imported real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## maps/VermilionCity.asm, maps/VermilionGym.asm, maps/VermilionPortPassage.asm
## and constants/map_constants.asm. `VermilionCity.asm` and `VermilionCity.blk`
## are byte identical between the pins and the gym differs only in Surge's text,
## so nothing here is profile split.
##
## The one thing worth pinning is that this gym is not its Gen 1 self. There is
## no trash-can puzzle: `VermilionGym_MapScripts` declares neither a scene nor a
## callback, so the gym is open from the door. The gate is outside it, in the
## city: the whole 42-cell gym yard is walled off by a single COLL_CUT_TREE on
## (13,18), which makes Cut the price of the Thunder Badge.
##
##   Godot --headless --path . -s res://tools/validate.gd -- vermilion


## constants/map_constants.asm: the VERMILION group is 12 and the FAST_SHIP
## group 15, which is where the port and its passage live.
const VERMILION_GROUP: int = 12
const CITY: int = 3
const GYM: int = 11
const FAST_SHIP_GROUP: int = 15
const PASSAGE: int = 9

const CITY_SIZE: Vector2i = Vector2i(40, 36)
const GYM_SIZE: Vector2i = Vector2i(10, 18)

## `maps/VermilionCity.asm`'s own event table.
const CITY_PASSAGE_DOORS: Array[Vector2i] = [Vector2i(19, 31), Vector2i(20, 31)]
const GYM_DOOR: Vector2i = Vector2i(10, 19)
const GYM_DOOR_APPROACH: Vector2i = Vector2i(10, 20)
const GYM_TREE: Vector2i = Vector2i(13, 18)
const GYM_TREE_APPROACH: Vector2i = Vector2i(13, 17)
const GYM_YARD_CELLS: int = 42

## `maps/VermilionPortPassage.asm`: warp 5 lands from the port, warps 3 and 4 are
## its own stair pair, and warps 1 and 2 open onto the city.
const PASSAGE_FROM_PORT: Vector2i = Vector2i(3, 14)
const PASSAGE_STAIRS_DOWN: Vector2i = Vector2i(3, 2)
const PASSAGE_STAIRS_UP: Vector2i = Vector2i(15, 4)
const PASSAGE_TO_CITY: Vector2i = Vector2i(15, 0)

## `maps/VermilionGym.asm`'s object events, in `object_const_def` order, with the
## trainer classes `constants/trainer_constants.asm` gives them.
const SURGE: Vector2i = Vector2i(5, 2)
const GYM_TRAINERS: Array[Vector2i] = [
	Vector2i(8, 8), Vector2i(4, 7), Vector2i(0, 10),
]
const GYM_WARPS: Array[Vector2i] = [Vector2i(4, 17), Vector2i(5, 17)]

## engine/overworld/tile_events.asm's CheckCutCollision entry for a tree, and
## ENGINE_HIVEBADGE's place in source badge order, which is the badge
## `.CheckAble` wants before it looks at the tile at all.
const COLL_CUT_TREE: int = 0x12
const BADGE_HIVE: int = 1


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_passage(data, game_id)
		_verify_city(data, game_id)
		_verify_gym(data, game_id)
		_drive_gym_tree(data, game_id)


## The passage is two regions joined by its own stair pair, the way Olivine's
## is, so the dock reaches the city in three warps rather than one.
func _verify_passage(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, FAST_SHIP_GROUP, PASSAGE, PASSAGE_FROM_PORT)
	if world == null:
		return
	var lower: Dictionary = _region(world, PASSAGE_FROM_PORT)
	var upper: Dictionary = _region(world, PASSAGE_STAIRS_UP)
	_r.check(
		lower.has(PASSAGE_STAIRS_DOWN),
		"%s: the passage's port landing does not reach its own stairs." % game_id
	)
	_r.check(
		not lower.has(PASSAGE_TO_CITY),
		"%s: the passage's port landing walks straight to the city." % game_id
	)
	_r.check(
		upper.has(PASSAGE_TO_CITY),
		"%s: the passage's upper region does not reach the city door." % game_id
	)
	_r.check(
		world.warp_index_at(PASSAGE_STAIRS_DOWN) == 4
			and world.warp_index_at(PASSAGE_STAIRS_UP) == 3,
		"%s: the passage's stair pair is not warps 3 and 4." % game_id
	)
	print("%s passage: two regions of %d and %d cells joined by their own stairs." % [
		game_id, lower.size(), upper.size(),
	])


## The city itself, and the one tree that seals the gym off.
func _verify_city(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, VERMILION_GROUP, CITY, CITY_PASSAGE_DOORS[0])
	if world == null:
		return
	_r.check(
		world.map_size_cells() == CITY_SIZE,
		"%s: Vermilion City is %s, not the pinned %s." % [
			game_id, world.map_size_cells(), CITY_SIZE,
		]
	)
	_r.check(
		world.collision_code_at(GYM_TREE) == COLL_CUT_TREE,
		"%s: %s is collision $%02X, not a cut tree." % [
			game_id, GYM_TREE, world.collision_code_at(GYM_TREE),
		]
	)
	var city: Dictionary = _region(world, CITY_PASSAGE_DOORS[0])
	var yard: Dictionary = _region(world, GYM_DOOR_APPROACH)
	_r.check(
		not city.has(GYM_DOOR) and not city.has(GYM_DOOR_APPROACH),
		"%s: the gym yard is reachable without cutting." % game_id
	)
	_r.check(
		yard.size() == GYM_YARD_CELLS,
		"%s: the gym yard is %d cells, not the pinned %d." % [
			game_id, yard.size(), GYM_YARD_CELLS,
		]
	)
	_r.check(
		city.has(GYM_TREE_APPROACH),
		"%s: the tree cannot be faced from the city side." % game_id
	)
	# And the tree really is the only join: every other cell bordering the yard
	# is wall, so no second route exists for a walk to find.
	var seams: Array[Vector2i] = []
	for cell: Vector2i in yard:
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if city.has(next):
				seams.append(next)
	_r.check(
		seams.is_empty(),
		"%s: the gym yard touches the city at %s without a tree between." % [game_id, seams]
	)
	_r.check(
		world.warp_index_at(GYM_DOOR) == 7,
		"%s: %s is not the gym door." % [game_id, GYM_DOOR]
	)
	# The gym door is a COLL_DOOR, so it forces a step south off itself; the mart
	# block above it is wall, which leaves (10,20) as its only approach.
	var approaches: Array[Vector2i] = []
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if world.can_walk_to(GYM_DOOR + direction):
			approaches.append(GYM_DOOR + direction)
	_r.check(
		approaches == [GYM_DOOR_APPROACH],
		"%s: the gym door is approached from %s, not %s alone." % [
			game_id, approaches, GYM_DOOR_APPROACH,
		]
	)
	print("%s city: a %d-cell yard behind one cut tree, and a gym door with one approach." % [
		game_id, yard.size(),
	])


## The gym has no puzzle: no scene scripts, no callbacks, and Surge answers as
## soon as he is faced.
func _verify_gym(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, VERMILION_GROUP, GYM, GYM_WARPS[0])
	if world == null:
		return
	_r.check(
		world.map_size_cells() == GYM_SIZE,
		"%s: Vermilion Gym is %s, not the pinned %s." % [
			game_id, world.map_size_cells(), GYM_SIZE,
		]
	)
	_r.check(
		world.current_map.scripts.get("scenes", []).is_empty(),
		"%s: Vermilion Gym ships a scene script; it should have none." % game_id
	)
	_r.check(
		world.current_map.scripts.get("callbacks", []).is_empty(),
		"%s: Vermilion Gym ships a callback; it should have none." % game_id
	)
	_r.check(
		world.object_at(SURGE) != null,
		"%s: no Surge on %s." % [game_id, SURGE]
	)
	for cell: Vector2i in GYM_TRAINERS:
		_r.check(
			world.object_at(cell) != null,
			"%s: no gym trainer on %s." % [game_id, cell]
		)
	for index: int in GYM_WARPS.size():
		_r.check(
			world.warp_index_at(GYM_WARPS[index]) == index + 1,
			"%s: %s is not gym warp %d." % [game_id, GYM_WARPS[index], index + 1]
		)
	# Both doors land on the same city cell, and Surge is reachable from either.
	var floor_cells: Dictionary = _region(world, GYM_WARPS[0])
	_r.check(
		floor_cells.has(SURGE + Vector2i.DOWN),
		"%s: Surge cannot be faced from the gym door." % game_id
	)
	print("%s gym: no scene, no callback, and Surge reachable across the pillar grid." % game_id)


## The cut itself, against the real cache: the tree opens, the yard joins, and a
## map load grows it back, so the gym door has to be taken in the same visit.
func _drive_gym_tree(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, VERMILION_GROUP, CITY, GYM_TREE_APPROACH)
	if world == null:
		return
	world.state.set_engine_flag(Gen2WorldState.badge_flag(
		BADGE_HIVE, Gen2WorldState.is_crystal_profile(data)
	))
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var request: Dictionary = world.cut_request()
	if not _r.check(
		bool(request.get("ok", false)),
		"%s: cut refused at %s: %s" % [game_id, GYM_TREE, request.get("reason", "")]
	):
		return
	var applied: Dictionary = world.complete_cut()
	if not _r.check(
		bool(applied.get("ok", false)),
		"%s: the cut failed: %s" % [game_id, applied.get("reason", "")]
	):
		return
	_r.check(
		_region(world, GYM_TREE_APPROACH).has(GYM_DOOR),
		"%s: the gym door is still unreachable after the cut." % game_id
	)
	var _reloaded: Dictionary = world.reload_current_map()
	_r.check(
		world.collision_code_at(GYM_TREE) == COLL_CUT_TREE,
		"%s: the tree did not grow back on a map load." % game_id
	)
	print("%s cut: the tree opens the yard and grows back on the next map load." % game_id)


func _open(data: GameData, group: int, number: int, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell)
	if world == null:
		_r.fail("map %d/%d is missing." % [group, number])
		return null
	_r.field_move_party(world)
	var _entry: Array = world.dispatch_map_entry()
	return world


func _region(world: Gen2WorldAPI, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if seen.has(next) or not world.can_walk_to(next, direction):
				continue
			seen[next] = true
			frontier.append(next)
	return seen
