extends RefCounted

var _r: RefCounted = null

## Verifies side-wall and side-buoy directional masks against freshly imported
## real caches, for both command profiles. The expected codes come from the
## pinned pokecrystal and pokegold sources: home/map.asm's
## GetMovementPermissions and engine/overworld/npc_movement.asm's
## CanObjectLeaveTile/WillObjectBumpIntoTile.
##
## The real-cartridge counterpart to the side-wall cases in
## tests/unit/test_world_collision.gd and tests/unit/test_world_api.gd, which
## use synthetic caches. It also pins the map census HANDOFF.md's open-work
## entry measured against these caches, so a future cache change is loud.
##
##   Godot --headless --path . -s res://tools/validate.gd -- side_walls

## constants/map_constants.asm's CELADON_MANSION_ROOF, Crystal map group 21
## number 15. The only map in either pinned cartridge with $b0 or $b1 cells: a
## COLL_RIGHT_WALL column at x=4 and a COLL_LEFT_WALL column at x=5, rows 2-6,
## plus two COLL_LEFT_WALL cells at the row-1 staircase landings.
const ROOF_GROUP: int = 21
const ROOF_NUMBER: int = 15

## Every code the CanObjectMoveInDirection/GetMovementPermissions family
## recognizes, and its FACE_* mask of walled-off edges (home/map.asm's
## .MovementPermissionsData, recounted by hand per code).
const EXPECTED_FACE_MASK: Dictionary = {
	0xB0: Gen2WorldCollision.FACE_RIGHT,
	0xB1: Gen2WorldCollision.FACE_LEFT,
	0xB2: Gen2WorldCollision.FACE_UP,
	0xB3: Gen2WorldCollision.FACE_DOWN,
	0xB4: Gen2WorldCollision.FACE_DOWN | Gen2WorldCollision.FACE_RIGHT,
	0xB5: Gen2WorldCollision.FACE_DOWN | Gen2WorldCollision.FACE_LEFT,
	0xB6: Gen2WorldCollision.FACE_UP | Gen2WorldCollision.FACE_RIGHT,
	0xB7: Gen2WorldCollision.FACE_UP | Gen2WorldCollision.FACE_LEFT,
}

## Measured against the three real caches in user://rom_cache, 2026-08-07.
## Silver is not scanned separately: it shares Gold's command profile and
## import layout, and Gold's count here already matches Silver's.
const EXPECTED_CENSUS: Dictionary = {
	&"crystal": {0xB0: 5, 0xB1: 7, 0xB2: 2343},
	&"gold": {0xB2: 2320},
}


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in [&"crystal", &"gold"]:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_codes(game_id)
		_verify_census(game_id, data)
	_verify_celadon_mansion_roof()


## $b0-$b7/$c0-$c7 stay their plain permission (LAND/WATER) and additionally
## wall off the edges EXPECTED_FACE_MASK names. $b8-$bf/$c8-$cf alias onto the
## same eight entries, matching the $a8-$af ledge alias; $af is a ledge code
## and never a side wall, so it must answer 0 here.
func _verify_codes(game_id: StringName) -> void:
	for wall_code: int in EXPECTED_FACE_MASK:
		var buoy_code: int = wall_code + 0x10
		var alias_code: int = wall_code + 0x08
		_r.check(
			Gen2WorldCollision.permission_for(wall_code) == Gen2WorldCollision.LAND_TILE,
			"%s: $%02X is not LAND_TILE." % [game_id, wall_code]
		)
		_r.check(
			Gen2WorldCollision.permission_for(buoy_code) == Gen2WorldCollision.WATER_TILE,
			"%s: $%02X is not WATER_TILE." % [game_id, buoy_code]
		)
		_r.check(
			Gen2WorldCollision.side_wall_face_mask(wall_code) == EXPECTED_FACE_MASK[wall_code],
			"%s: $%02X's face mask does not match .MovementPermissionsData." % [game_id, wall_code]
		)
		_r.check(
			Gen2WorldCollision.side_wall_face_mask(buoy_code) == EXPECTED_FACE_MASK[wall_code],
			"%s: $%02X's face mask does not match .MovementPermissionsData." % [game_id, buoy_code]
		)
		_r.check(
			Gen2WorldCollision.side_wall_face_mask(alias_code) == EXPECTED_FACE_MASK[wall_code],
			"%s: $%02X does not alias %s's entry." % [game_id, alias_code, wall_code]
		)
	_r.check(
		Gen2WorldCollision.side_wall_face_mask(0xAF) == 0,
		"%s: $AF (a ledge code) answers a side-wall face mask." % game_id
	)


## Pins HANDOFF.md's map census so a future cache change is loud rather than
## silently changing which cells this feature affects.
func _verify_census(game_id: StringName, data: GameData) -> void:
	var expected: Dictionary = EXPECTED_CENSUS[game_id]
	var counts: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		for code: int in map.collision:
			if code >= 0xB0 and code <= 0xCF:
				counts[code] = int(counts.get(code, 0)) + 1
	for code: int in expected:
		_r.check(
			int(counts.get(code, 0)) == int(expected[code]),
			"%s: $%02X census is %d cells, expected %d." % [
				game_id, code, int(counts.get(code, 0)), int(expected[code]),
			]
		)
	for code: int in counts:
		if code in expected:
			continue
		_r.check(
			false,
			"%s: $%02X has %d cells with no expected count; census is stale." % [
				game_id, code, int(counts[code]),
			]
		)


## Live checks against Crystal's Celadon Mansion Roof, the only map in either
## pinned cartridge carrying $b0 or $b1.
func _verify_celadon_mansion_roof() -> void:
	var data: GameData = GameData.open(&"crystal")
	if data == null:
		return
	var right_wall := Gen2WorldAPI.open(
		data, ROOF_GROUP, ROOF_NUMBER, Vector2i(4, 4), Gen2WorldState.new()
	)
	if not _r.check(right_wall != null, "crystal: Celadon Mansion Roof (21/15) is missing."):
		return
	_r.check(
		right_wall.collision_code_at(Vector2i(4, 4)) == 0xB0,
		"crystal: roof (4,4) is not COLL_RIGHT_WALL."
	)
	var blocked_right: Dictionary = right_wall.move_result(Vector2i.RIGHT)
	_r.check(
		not bool(blocked_right.get("ok", false)),
		"crystal: roof (4,4) did not block moving RIGHT off its own wall."
	)

	var left_wall := Gen2WorldAPI.open(
		data, ROOF_GROUP, ROOF_NUMBER, Vector2i(5, 4), Gen2WorldState.new()
	)
	_r.check(
		left_wall.collision_code_at(Vector2i(5, 4)) == 0xB1,
		"crystal: roof (5,4) is not COLL_LEFT_WALL."
	)
	var blocked_left: Dictionary = left_wall.move_result(Vector2i.LEFT)
	_r.check(
		not bool(blocked_left.get("ok", false)),
		"crystal: roof (5,4) did not block moving LEFT off its own wall."
	)

	var vertical := Gen2WorldAPI.open(
		data, ROOF_GROUP, ROOF_NUMBER, Vector2i(4, 3), Gen2WorldState.new()
	)
	var down: Dictionary = vertical.move_result(Vector2i.DOWN)
	_r.check(
		bool(down.get("ok", false)) and vertical.player_cell == Vector2i(4, 4),
		"crystal: roof (4,3) could not step down its own wall column."
	)

	var staircase_left := Gen2WorldAPI.open(
		data, ROOF_GROUP, ROOF_NUMBER, Vector2i(2, 1), Gen2WorldState.new()
	)
	var landing_left: Dictionary = staircase_left.move_result(Vector2i.LEFT)
	_r.check(
		not bool(landing_left.get("ok", false)),
		"crystal: roof (2,1) did not block leaving its own COLL_LEFT_WALL."
	)

	# (1,1) is the staircase landing itself, COLL_STAIRCASE, so .CheckTile answers
	# before .TryStep ever reaches the enter rule: pressing RIGHT there steps DOWN
	# off the staircase. The enter rule is checked directly for that reason.
	var staircase_right := Gen2WorldAPI.open(
		data, ROOF_GROUP, ROOF_NUMBER, Vector2i(1, 1), Gen2WorldState.new()
	)
	_r.check(
		not staircase_right.can_walk_to(Vector2i(2, 1), Vector2i.RIGHT),
		"crystal: roof (1,1) did not block entering (2,1)'s COLL_LEFT_WALL."
	)
	var forced_off: Dictionary = staircase_right.move_result(Vector2i.RIGHT)
	_r.check(
		bool(forced_off.get("ok", false))
			and staircase_right.player_cell == Vector2i(1, 2),
		"crystal: roof (1,1) staircase did not force the player down off it."
	)

	var staircase_up := Gen2WorldAPI.open(
		data, ROOF_GROUP, ROOF_NUMBER, Vector2i(1, 2), Gen2WorldState.new()
	)
	var climbed: Dictionary = staircase_up.move_result(Vector2i.UP)
	_r.check(
		bool(climbed.get("ok", false)) and staircase_up.player_cell == Vector2i(1, 1),
		"crystal: roof (1,2) could not climb to the staircase landing."
	)
