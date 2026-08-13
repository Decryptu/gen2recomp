extends SceneTree

## Verifies the gates between Blackthorn Gym's door and the Rising Badge,
## against freshly imported real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `maps/BlackthornGym2F.asm`, `maps/BlackthornGym1F.asm`,
## `maps/BlackthornCity.asm` and `maps/DragonsDenB1F.asm`. Gym 2F's map events
## and `BlackthornGym1FBouldersCallback` are byte identical between the pins;
## Gold and Silver have no Dragon Shrine, so their B1F carries no warp to it and
## the shrine checks are Crystal only.
##
## What is worth pinning here is not the scripts but the four places the leg
## would silently stop: the two boulders that seal 2F's pockets, the two 1F
## `changeblock`s that actually open Clair's room, the lake that is the only way
## to the Dragon's Den door, and the whirlpool between the den ladder and the
## shrine's one landfall.
##
##   Godot --headless --path . -s res://tools/validate_rising_badge.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## data/maps/maps.asm group/number pairs. The gym floors and the city sit at the
## same pair in both games; Crystal's own extra maps push Dragon's Den B1F eight
## places down the Dungeons group.
const BLACKTHORN_GYM_1F: Array = [5, 1]
const BLACKTHORN_GYM_2F: Array = [5, 2]
const BLACKTHORN_CITY: Array = [5, 10]
const DRAGONS_DEN_B1F: Dictionary = {
	&"gold": [3, 73],
	&"silver": [3, 73],
	&"crystal": [3, 81],
}

## constants/event_flags.asm, same numbers in both pins. Each boulder's own
## object event flag, which its `stonetable` fall script sets and
## BlackthornGym1FBouldersCallback reads back as a `changeblock`.
const EVENT_BOULDER_1: int = 1798
const EVENT_BOULDER_2: int = 1799
const EVENT_BOULDER_3: int = 1800
const EVENT_BEAT_CLAIR: int = 1220
const EVENT_GRAMPS_BLOCKS_DRAGONS_DEN: int = 1868

## `maps/BlackthornGym2F.asm`'s object rows in order. The first three are the
## `stonetable` boulders; BOULDER4 is scenery and BOULDER5 and BOULDER6 are the
## two that seal the pockets.
const GYM_2F_BOULDERS: Array = [
	Vector2i(8, 2), Vector2i(2, 3), Vector2i(6, 16),
	Vector2i(3, 3), Vector2i(6, 1), Vector2i(8, 14),
]
## The three holes, from the same file's `def_warp_events`.
const GYM_2F_HOLES: Array = [Vector2i(2, 5), Vector2i(8, 7), Vector2i(8, 3)]
## The staircase 2F is entered by; its other one, (7,9), drops into the 1F
## pocket the fallen boulders join to Clair's room.
const GYM_2F_STAIRS: Vector2i = Vector2i(1, 7)

## 1F's staircase from 2F's (7,9), and the cell Clair is faced from.
const GYM_1F_LANDING: Vector2i = Vector2i(7, 9)
const GYM_1F_FACE_CLAIR: Vector2i = Vector2i(5, 4)

## Blackthorn City: the den door, the shore the route surfs from, and the cell
## it lands on. (20,4) below the landing is COLL_WATER, which is what makes the
## crossing the only way in.
const CITY_DEN_DOOR: Vector2i = Vector2i(20, 1)
const CITY_GYM_DOOR: Vector2i = Vector2i(18, 11)
const CITY_SURF_SHORE: Vector2i = Vector2i(22, 12)
const CITY_DEN_LANDFALL: Vector2i = Vector2i(20, 3)
const CITY_DEN_WATER: Vector2i = Vector2i(20, 4)

## Dragon's Den B1F: the ladder from 1F, the whirlpool in the way, and the one
## cell the shrine's own region can be walked ashore on.
const DEN_LADDER: Vector2i = Vector2i(20, 3)
const DEN_WHIRLPOOL: Vector2i = Vector2i(10, 20)
const DEN_LANDFALL: Vector2i = Vector2i(14, 31)
const DEN_SHRINE_WARP: Vector2i = Vector2i(19, 29)

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_gym_2f(data, game_id)
		_verify_gym_1f(data, game_id)
		_verify_city_lake(data, game_id)
		_verify_dragons_den(data, game_id)
	_finish()


## The six boulders, the three holes, and the two pockets BOULDER5 and BOULDER6
## seal. Neither of those two is in the `stonetable` or carries an event flag,
## so nothing else in the cache says they matter.
func _verify_gym_2f(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, BLACKTHORN_GYM_2F, GYM_2F_STAIRS, [])
	if world == null:
		_fail("%s: Blackthorn Gym 2F is missing." % game_id)
		return

	var boulders: Array = []
	for object: Gen2WorldObject in world.objects:
		if object.is_strength_boulder():
			boulders.append(object.cell)
	_check(
		boulders == GYM_2F_BOULDERS,
		"%s: 2F's boulders are at %s, not the pinned %s." % [
			game_id, boulders, GYM_2F_BOULDERS,
		]
	)
	for hole: Vector2i in GYM_2F_HOLES:
		_check(
			Gen2WorldCollision.is_pit_tile(world.collision_code_at(hole))
				and world.warp_index_at(hole) > 0,
			"%s: 2F's hole at %s is not a warp on a pit tile." % [game_id, hole]
		)

	# The push cells for the two `stonetable` boulders, both sealed until the
	# scenery boulders move.
	_check(
		not _reaches(world, GYM_2F_STAIRS, Vector2i(8, 1)),
		"%s: 2F's (8,1) is reachable with BOULDER5 still on (6,1)." % game_id
	)
	_check(
		not _reaches(world, GYM_2F_STAIRS, Vector2i(6, 17)),
		"%s: 2F's (6,17) is reachable with BOULDER6 still on (8,14)." % game_id
	)
	# BOULDER3's run north stops on the wall above (6,7), which is what puts it
	# on the row its hole is on.
	for y: int in range(7, 17):
		_check(
			world.collision_permission_at(Vector2i(6, y)) == Gen2WorldCollision.LAND_TILE,
			"%s: 2F's (6,%d) is not floor, so the north push cannot cross it." % [game_id, y]
		)
	_check(
		not world.can_walk_to(Vector2i(6, 6)),
		"%s: 2F's (6,6) is open, so the north push would not stop on (6,7)." % game_id
	)


## Which fallen boulders actually open Clair's room. Two of the three do;
## BOULDER2's `changeblock` adds one cell beside the entrance and reaches
## nothing, which is why the walked route leaves it alone.
func _verify_gym_1f(data: GameData, game_id: StringName) -> void:
	var sealed: Gen2WorldAPI = _open(data, BLACKTHORN_GYM_1F, GYM_1F_LANDING, [])
	if sealed == null:
		_fail("%s: Blackthorn Gym 1F is missing." % game_id)
		return
	_check(
		not _reaches(sealed, GYM_1F_LANDING, GYM_1F_FACE_CLAIR),
		"%s: Clair is reachable with no boulder fallen." % game_id
	)

	var one: Gen2WorldAPI = _open(data, BLACKTHORN_GYM_1F, GYM_1F_LANDING, [EVENT_BOULDER_1])
	_check(
		not _reaches(one, GYM_1F_LANDING, GYM_1F_FACE_CLAIR),
		"%s: the first boulder alone reaches Clair." % game_id
	)
	var three: Gen2WorldAPI = _open(data, BLACKTHORN_GYM_1F, GYM_1F_LANDING, [EVENT_BOULDER_3])
	_check(
		not _reaches(three, GYM_1F_LANDING, GYM_1F_FACE_CLAIR),
		"%s: the third boulder alone reaches Clair." % game_id
	)
	var both: Gen2WorldAPI = _open(
		data, BLACKTHORN_GYM_1F, GYM_1F_LANDING, [EVENT_BOULDER_1, EVENT_BOULDER_3]
	)
	_check(
		_reaches(both, GYM_1F_LANDING, GYM_1F_FACE_CLAIR),
		"%s: the first and third boulders together do not reach Clair." % game_id
	)

	var second: Gen2WorldAPI = _open(data, BLACKTHORN_GYM_1F, GYM_1F_LANDING, [EVENT_BOULDER_2])
	_check(
		_region(second, GYM_1F_LANDING).size() == _region(sealed, GYM_1F_LANDING).size(),
		"%s: the second boulder changes the landing's region, so it is not a dead end." % game_id
	)


## The Dragon's Den door is across the lake. Every land route from the town
## centre is walled off, and (20,4) below the door's shore is water.
func _verify_city_lake(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(
		data, BLACKTHORN_CITY, CITY_GYM_DOOR,
		[EVENT_BEAT_CLAIR, EVENT_GRAMPS_BLOCKS_DRAGONS_DEN]
	)
	if world == null:
		_fail("%s: Blackthorn City is missing." % game_id)
		return
	_check(
		not _reaches(world, CITY_GYM_DOOR, CITY_DEN_DOOR),
		"%s: the Dragon's Den door is walkable from the gym door." % game_id
	)
	_check(
		world.collision_permission_at(CITY_DEN_WATER) == Gen2WorldCollision.WATER_TILE,
		"%s: %s below the den's shore is not water." % [game_id, CITY_DEN_WATER]
	)
	_check(
		world.collision_permission_at(CITY_SURF_SHORE + Vector2i.UP)
			== Gen2WorldCollision.WATER_TILE,
		"%s: the cell the route surfs into from %s is not water." % [game_id, CITY_SURF_SHORE]
	)
	var lake: Dictionary = _water_region(world, CITY_DEN_WATER)
	_check(
		lake.has(CITY_SURF_SHORE + Vector2i.UP),
		"%s: the shore at %s faces a different body of water than the den's." % [
			game_id, CITY_SURF_SHORE,
		]
	)
	_check(
		world.can_walk_to(CITY_DEN_LANDFALL)
			and _reaches(world, CITY_DEN_LANDFALL, CITY_DEN_DOOR),
		"%s: the den landfall %s does not reach the door." % [game_id, CITY_DEN_LANDFALL]
	)


## The den's own lake, the whirlpool across it, and the shrine's one landfall.
## Gold and Silver have no Dragon Shrine, so only the water is checked there.
func _verify_dragons_den(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, DRAGONS_DEN_B1F[game_id], DEN_LADDER, [])
	if world == null:
		_fail("%s: Dragon's Den B1F is missing." % game_id)
		return
	var forced: Dictionary = Gen2WorldCollision.forced_action(
		world.collision_code_at(DEN_WHIRLPOOL)
	)
	_check(
		StringName(forced.get("kind", &"none")) == &"force_turn",
		"%s: %s is not a whirlpool." % [game_id, DEN_WHIRLPOOL]
	)
	var lake: Dictionary = _water_region(world, DEN_WHIRLPOOL)
	_check(
		lake.has(DEN_LANDFALL + Vector2i.LEFT),
		"%s: the shrine landfall %s is not on the whirlpool's water." % [game_id, DEN_LANDFALL]
	)

	if game_id != &"crystal":
		_check(
			world.warp_index_at(DEN_SHRINE_WARP) <= 0,
			"%s has a Dragon Shrine warp, which only Crystal ships." % game_id
		)
		return
	_check(
		world.warp_index_at(DEN_SHRINE_WARP) > 0,
		"crystal: %s is not the Dragon Shrine warp." % DEN_SHRINE_WARP
	)
	_check(
		not _reaches(world, DEN_LADDER, DEN_SHRINE_WARP),
		"crystal: the shrine is walkable from the B1F ladder."
	)
	_check(
		_reaches(world, DEN_LANDFALL, DEN_SHRINE_WARP),
		"crystal: the landfall %s does not reach the shrine." % DEN_LANDFALL
	)


func _open(data: GameData, id: Array, cell: Vector2i, flags: Array) -> Gen2WorldAPI:
	var state := Gen2WorldState.new()
	for flag: int in flags:
		state.set_event_flag(flag)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, id[0], id[1], cell, state)
	if world == null:
		return null
	var _entry: Array = world.dispatch_map_entry()
	for _step: int in 8:
		if not world.pending_script_wait().is_empty():
			world.finish_script_waits()
			continue
		if world.pending_script_input().is_empty():
			break
		world.run_event_queue(true)
	return world


## Plain walking reachability, which is what every gate above turns on. Warp
## tiles are walls unless they are the target, the way a walked route has it:
## stepping onto one takes it.
func _region(world: Gen2WorldAPI, from: Vector2i, target: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var seen: Dictionary = {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for step: Vector2i in STEPS:
			var next: Vector2i = cell + step
			if seen.has(next) or not world.can_walk_to(next, step):
				continue
			if next != target and not world.warp_at(next).is_empty() \
				and Gen2WorldCollision.is_warp_tile(world.collision_code_at(next)):
				continue
			# can_walk_to() reads the leave/enter mask at the API's own player
			# cell; from a frontier it has to be anchored on the frontier cell,
			# the way tools/preview_world_story.gd's _reachable_step() does.
			var face: int = Gen2WorldCollision.face_mask_for_direction(step)
			if face != 0 and (world.tile_permissions_at(cell) & face) != 0:
				continue
			seen[next] = true
			frontier.append(next)
	return seen


func _reaches(world: Gen2WorldAPI, from: Vector2i, target: Vector2i) -> bool:
	return world != null and _region(world, from, target).has(target)


func _water_region(world: Gen2WorldAPI, from: Vector2i) -> Dictionary:
	var seen: Dictionary = {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for step: Vector2i in STEPS:
			var next: Vector2i = cell + step
			if seen.has(next) \
				or world.collision_permission_at(next) != Gen2WorldCollision.WATER_TILE:
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
		print("PASS rising badge: the gym pockets, 1F block changes and both crossings verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL rising badge: %d problems." % _failures.size())
	quit(1)
