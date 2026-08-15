extends RefCounted

var _r: RefCounted = null

## Verifies where a wild encounter can be rolled at all, against freshly
## imported real caches, for all three cartridges.
##
## The expected shape comes from engine/overworld/events.asm's RandomEncounter,
## CanEncounterWildMon and CheckWildEncounterCooldown,
## engine/overworld/tile_events.asm's CheckGrassCollision and
## home/map_objects.asm's CheckIceTile. The real-cartridge counterpart to the
## gate cases in tests/unit/test_world_api.gd, which use a hand-built map.
##
## The census is the point: an encounter cell is a small minority of a map's
## walkable cells, and the defect this topic exists to catch was every land cell
## rolling. A route whose grass moves, or a collision code that stops being read
## as grass, moves these counts.
##
##   Godot --headless --path . -s res://tools/validate.gd -- wild_encounters

## Census of the real caches, pinned so a cache or a rule change is loud.
## Per game: encounter cells, maps holding one, and cells refused for ice.
const EXPECTED_CENSUS: Dictionary = {
	&"gold": [39058, 138, 775],
	&"silver": [39058, 138, 775],
	&"crystal": [40156, 146, 779],
}

## Route 29, the first grass a new game walks into, and the same map number in
## all three games (constants/map_constants.asm, group 24).
const ROUTE_29_GROUP: int = 24
const ROUTE_29_NUMBER: int = 3

## Union Cave 1F, whose whole floor rolls because its environment is CAVE.
## pokecrystal inserts eight Ruins of Alph rooms ahead of it in group 3.
const UNION_CAVE_GROUP: int = 3
const UNION_CAVE_NUMBER_CRYSTAL: int = 37
const UNION_CAVE_NUMBER_GOLD_SILVER: int = 29


func run(r: RefCounted) -> void:
	_r = r
	_r.each_game(func() -> void:
		_verify_route_29()
		_verify_union_cave()
		_census()
	)


## An outdoor map: only the tiles CheckGrassCollision names roll, and the path
## between them does not.
func _verify_route_29() -> void:
	var world: Gen2WorldAPI = _r.open_world(
		ROUTE_29_GROUP, ROUTE_29_NUMBER, Vector2i.ZERO
	)
	if world == null:
		return
	world.state.set_wild_encounter_cooldown(0)
	var counts: Dictionary = _map_counts(world)
	_r.check(
		world.current_map.environment == Gen2WorldPhoneHost.ENVIRONMENT_ROUTE,
		"Route 29 is environment %d, not ROUTE." % world.current_map.environment
	)
	_r.check(
		int(counts["encounter"]) > 0,
		"Route 29 offers no encounter cell at all."
	)
	_r.check(
		int(counts["encounter"]) < int(counts["walkable"]),
		"Route 29 rolls on all %d of its walkable cells." % int(counts["walkable"])
	)
	_r.note("Route 29: %d encounter cells of %d walkable." % [
		int(counts["encounter"]), int(counts["walkable"]),
	])


## A CAVE map: every walkable cell rolls, which is the branch that skips
## CheckGrassCollision entirely.
func _verify_union_cave() -> void:
	var number: int = UNION_CAVE_NUMBER_CRYSTAL if _r.crystal \
		else UNION_CAVE_NUMBER_GOLD_SILVER
	var world: Gen2WorldAPI = _r.open_world(UNION_CAVE_GROUP, number, Vector2i.ZERO)
	if world == null:
		return
	world.state.set_wild_encounter_cooldown(0)
	if not _r.check(
		world.current_map.environment == Gen2WorldAPI.ENVIRONMENT_CAVE,
		"Union Cave 1F is environment %d, not CAVE." % world.current_map.environment
	):
		return
	var counts: Dictionary = _map_counts(world)
	_r.check(
		int(counts["encounter"]) == int(counts["walkable"]),
		"Union Cave 1F rolls on %d of its %d walkable cells." % [
			int(counts["encounter"]), int(counts["walkable"]),
		]
	)
	_r.note("Union Cave 1F: %d cells, all of them CAVE." % int(counts["encounter"]))


## Every map in the cache, so a rule change is one number rather than one map.
func _census() -> void:
	var cells: int = 0
	var maps: Dictionary = {}
	var iced: int = 0
	for map: Gen2WorldMap in _r.data.world_maps():
		var tileset: Gen2WorldTileset = _r.data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var world := Gen2WorldAPI.new(
			_r.data, map, tileset, Vector2i.ZERO, Gen2WorldState.new()
		)
		world.state.set_wild_encounter_cooldown(0)
		var counts: Dictionary = _map_counts(world)
		cells += int(counts["encounter"])
		iced += int(counts["ice"])
		if int(counts["encounter"]) > 0:
			maps[map.group * 256 + map.number] = true
	var found: Array = [cells, maps.size(), iced]
	_r.note("encounter cells %d over %d maps, %d refused for ice." % [
		cells, maps.size(), iced,
	])
	var expected: Array = EXPECTED_CENSUS[_r.game_id]
	_r.check(
		found == expected,
		"census is %s, not the pinned %s." % [str(found), str(expected)]
	)


## What one map offers: walkable cells, cells CanEncounterWildMon accepts, and
## cells it would have accepted but for the ice test.
func _map_counts(world: Gen2WorldAPI) -> Dictionary:
	var walkable: int = 0
	var encounter: int = 0
	var ice: int = 0
	var map: Gen2WorldMap = world.current_map
	for y: int in map.collision_height:
		for x: int in map.collision_width:
			var cell := Vector2i(x, y)
			var permission: int = world.collision_permission_at(cell)
			if permission != Gen2WorldCollision.LAND_TILE \
				and permission != Gen2WorldCollision.WATER_TILE:
				continue
			walkable += 1
			world.player_cell = cell
			if world.can_encounter_wild_mon():
				encounter += 1
			elif Gen2WorldCollision.is_ice(world.collision_code_at(cell)):
				ice += 1
	return {"walkable": walkable, "encounter": encounter, "ice": ice}
