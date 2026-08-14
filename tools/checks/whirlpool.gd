extends RefCounted

var _r: RefCounted = null

## Verifies Whirlpool and the forced-tile layer against freshly imported real
## caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## engine/events/overworld.asm's WhirlpoolFunction and TryWhirlpoolMenu,
## home/map_objects.asm's CheckWhirlpoolTile, data/collision/field_move_blocks.asm's
## WhirlpoolBlockPointers and engine/overworld/player_movement.asm's
## DoPlayerMovement.CheckTile. All four are byte identical between the pins, and
## WhirlpoolBlockPointers names only TILESET_JOHTO, which is $01 in both games, so
## nothing here is profile split except the badge flag number and Dragon's Den's
## map number.
##
## The real-cartridge counterpart to tests/unit/test_world_field_move.gd and the
## forced-tile tests in tests/unit/test_world_api.gd. Dragon's Den B1F is the
## acceptance case, because its whirlpool is the one a Crystal playthrough meets.
##
##   Godot --headless --path . -s res://tools/validate.gd -- whirlpool


## constants/map_constants.asm, DUNGEONS group. Crystal's extra maps push
## Dragon's Den B1F eight places later within the same group.
const DEN_GROUP: int = 3
const DEN_NUMBER_CRYSTAL: int = 81
const DEN_NUMBER_GOLD_SILVER: int = 73
## maps/DragonsDenB1F.blk: one block $07, whose bottom-left quadrant carries
## COLL_WHIRLPOOL (data/tilesets/johto_collision.asm).
const DEN_BLOCK := Vector2i(5, 10)
const DEN_CELL := Vector2i(10, 20)
const DEN_BLOCK_WHIRLPOOL: int = 0x07
const DEN_BLOCK_GONE: int = 0x36

## Census of the real caches, pinned so a cache change is loud. Every whirlpool
## cell in all three cartridges sits on TILESET_JOHTO block $07, so all of them
## resolve; the maps are Dragon's Den B1F, Route 41 and Route 27.
const EXPECTED_CENSUS: Dictionary = {
	# game id: [whirlpool cells, cells resolving to a replacement, maps]
	&"gold": [6, 6, 3],
	&"silver": [6, 6, 3],
	&"crystal": [6, 6, 3],
}

## .CheckTile's warp branch forces DOWN off door, staircase and cave tiles, and
## .DoStep never checks permissions, so the handful of cells with no walkable
## ground below are pinned rather than special-cased. All of them are on a map's
## bottom edge except Route 34's, which has COLL_WALL below it.
const EXPECTED_WARP_STEP_CENSUS: Dictionary = {
	# game id: [warp-family cells, cells with no walkable cell below]
	&"gold": [356, 2],
	&"silver": [356, 2],
	&"crystal": [387, 4],
}

## The only forced-tile families any pinned cartridge ships. The forced-walk
## tables ($40-$47, $50-$57) and the second whirlpool code ($2c) are implemented
## from the source table but unused, like the $a8-$af ledge alias.
const EXPECTED_FORCED_CODES: Dictionary = {
	&"gold": {0x24: 6, 0x33: 164, 0x71: 234, 0x7A: 74, 0x7B: 48},
	&"silver": {0x24: 6, 0x33: 164, 0x71: 234, 0x7A: 74, 0x7B: 48},
	&"crystal": {0x24: 6, 0x33: 164, 0x71: 257, 0x7A: 78, 0x7B: 52},
}


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_census(game_id, data)
		_verify_dragons_den(game_id, data, Gen2WorldState.is_crystal_profile(data))


## Counts every cell .CheckTile or Whirlpool acts on, so a cache change that moves
## a block or a collision code is loud rather than quietly reopening a route.
func _census(game_id: StringName, data: GameData) -> void:
	var whirlpool_cells: int = 0
	var resolved_cells: int = 0
	var whirlpool_maps: Dictionary = {}
	var forced_codes: Dictionary = {}
	var warp_step_cells: int = 0
	var warp_step_blocked: int = 0
	for map: Gen2WorldMap in data.world_maps():
		for y: int in map.collision_height:
			for x: int in map.collision_width:
				var code: int = map.collision_at(x, y)
				var forced: Dictionary = Gen2WorldCollision.forced_action(code)
				if StringName(forced.get("kind", &"none")) != &"none":
					forced_codes[code] = int(forced_codes.get(code, 0)) + 1
				if Gen2WorldCollision.WARP_STEP_CODES.has(code):
					warp_step_cells += 1
					var below: int = map.collision_at(x, y + 1) if y + 1 < map.collision_height else -1
					if not Gen2WorldCollision.is_walkable(below):
						warp_step_blocked += 1
				if not Gen2WorldFieldMove.whirlpool_tile(code):
					continue
				whirlpool_cells += 1
				if bool(Gen2WorldFieldMove.whirlpool_replacement(
					map.tileset, map.block_at(x >> 1, y >> 1)
				).get("ok", false)):
					resolved_cells += 1
					whirlpool_maps[Vector2i(map.group, map.number)] = true

	var counts: Array = [whirlpool_cells, resolved_cells, whirlpool_maps.size()]
	print("%s: %d whirlpool cells, %d resolving to a replacement across %d maps." % [
		game_id, counts[0], counts[1], counts[2],
	])
	_r.check(
		counts == EXPECTED_CENSUS.get(game_id, []),
		"%s: whirlpool census is %s, not the pinned %s." % [
			game_id, counts, EXPECTED_CENSUS.get(game_id, []),
		]
	)

	var warp_counts: Array = [warp_step_cells, warp_step_blocked]
	print("%s: %d door/staircase/cave cells, %d with no walkable cell below." % [
		game_id, warp_counts[0], warp_counts[1],
	])
	_r.check(
		warp_counts == EXPECTED_WARP_STEP_CENSUS.get(game_id, []),
		"%s: forced-step census is %s, not the pinned %s." % [
			game_id, warp_counts, EXPECTED_WARP_STEP_CENSUS.get(game_id, []),
		]
	)
	_r.check(
		forced_codes == EXPECTED_FORCED_CODES.get(game_id, {}),
		"%s: forced-tile codes are %s, not the pinned %s." % [
			game_id, forced_codes, EXPECTED_FORCED_CODES.get(game_id, {}),
		]
	)


func _verify_dragons_den(game_id: StringName, data: GameData, crystal: bool) -> void:
	var number: int = DEN_NUMBER_CRYSTAL if crystal else DEN_NUMBER_GOLD_SILVER
	var badge: int = Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_GLACIER, crystal)
	var state := Gen2WorldState.new()
	state.set_engine_flag(badge)
	var approach: Vector2i = DEN_CELL + Vector2i.UP
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, DEN_GROUP, number, approach, state)
	if not _r.check(
		world != null, "%s: Dragon's Den B1F %d/%d is missing." % [game_id, DEN_GROUP, number]
	):
		return
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	_r.field_move_party(world)
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)

	_r.check(
		world.current_map.tileset == Gen2WorldFieldMove.TILESET_JOHTO,
		"%s: Dragon's Den B1F is tileset %d, not JOHTO." % [game_id, world.current_map.tileset]
	)
	_r.check(
		world.block_at(DEN_BLOCK.x, DEN_BLOCK.y) == DEN_BLOCK_WHIRLPOOL,
		"%s: Dragon's Den block %s is $%02X, not $%02X." % [
			game_id, DEN_BLOCK, world.block_at(DEN_BLOCK.x, DEN_BLOCK.y), DEN_BLOCK_WHIRLPOOL,
		]
	)
	_r.check(
		world.collision_code_at(DEN_CELL) == Gen2WorldCollision.COLL_WHIRLPOOL,
		"%s: Dragon's Den %s is $%02X, not COLL_WHIRLPOOL." % [
			game_id, DEN_CELL, world.collision_code_at(DEN_CELL),
		]
	)

	# .CheckSurfable reads the permission with TALK masked off, so the whirlpool
	# is water and a surfing player swims onto it. .CheckTile then traps them:
	# Script_ForcedMovement only spins the player around.
	_r.check(
		bool(world.move_result(Vector2i.DOWN).get("ok", false))
			and world.player_cell == DEN_CELL,
		"%s: Dragon's Den whirlpool refused a surfing step onto it." % game_id
	)
	var spun: Dictionary = world.move_result(Vector2i.DOWN)
	_r.check(
		StringName(spun.get("kind", &"")) == &"forced_turn"
			and world.player_cell == DEN_CELL
			and world.player_facing == Gen2WorldSprite.FACING_UP,
		"%s: Dragon's Den whirlpool did not spin the player in place: %s." % [
			game_id, JSON.stringify(spun),
		]
	)

	world.player_cell = approach
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var staged: Dictionary = world.whirlpool_request()
	if not _r.check(
		bool(staged.get("ok", false)),
		"%s: Dragon's Den refused Whirlpool: %s." % [game_id, staged.get("reason", "unknown")]
	):
		return
	_r.check(
		int(staged.get("block", -1)) == DEN_BLOCK_GONE
			and staged.get("block_cell", Vector2i.ZERO) == DEN_BLOCK,
		"%s: Dragon's Den staged %s, not block $%02X at %s." % [
			game_id, JSON.stringify(staged), DEN_BLOCK_GONE, DEN_BLOCK,
		]
	)
	# Script_UsedWhirlpool reaches DisappearWhirlpool only after UseWhirlpoolText.
	_r.check(
		world.block_at(DEN_BLOCK.x, DEN_BLOCK.y) == DEN_BLOCK_WHIRLPOOL
			and world.collision_code_at(DEN_CELL) == Gen2WorldCollision.COLL_WHIRLPOOL,
		"%s: Dragon's Den changed before the whirlpool was committed." % game_id
	)

	_r.check(
		bool(world.complete_whirlpool().get("ok", false)),
		"%s: Dragon's Den whirlpool did not commit." % game_id
	)
	_r.check(
		world.block_at(DEN_BLOCK.x, DEN_BLOCK.y) == DEN_BLOCK_GONE,
		"%s: Dragon's Den block is $%02X after the whirlpool." % [
			game_id, world.block_at(DEN_BLOCK.x, DEN_BLOCK.y),
		]
	)
	_r.check(
		StringName(Gen2WorldCollision.forced_action(
			world.collision_code_at(DEN_CELL)
		)["kind"]) == &"none",
		"%s: Dragon's Den %s still forces movement after the whirlpool." % [game_id, DEN_CELL]
	)
	_r.check(
		bool(world.move_result(Vector2i.DOWN).get("ok", false))
			and world.player_cell == DEN_CELL,
		"%s: Dragon's Den %s is still trapped after the whirlpool." % [game_id, DEN_CELL]
	)
	print("%s: Dragon's Den B1F %d/%d %s $%02X -> $%02X, cell %s freed." % [
		game_id, DEN_GROUP, number, DEN_BLOCK, DEN_BLOCK_WHIRLPOOL, DEN_BLOCK_GONE, DEN_CELL,
	])

	# DisappearWhirlpool only writes wOverworldMapBlocks, which a map load re-reads
	# from ROM, so the whirlpool is back on the next visit.
	world.reload_current_map()
	_r.check(
		world.block_at(DEN_BLOCK.x, DEN_BLOCK.y) == DEN_BLOCK_WHIRLPOOL
			and world.collision_code_at(DEN_CELL) == Gen2WorldCollision.COLL_WHIRLPOOL,
		"%s: Dragon's Den whirlpool did not return on a map reload." % game_id
	)

	# .TryWhirlpool tests the badge before the tile, on whichever engine flag table
	# this profile numbers ENGINE_GLACIERBADGE on.
	var unbadged: Gen2WorldAPI = Gen2WorldAPI.open(
		data, DEN_GROUP, number, approach, Gen2WorldState.new()
	)
	unbadged.player_facing = Gen2WorldSprite.FACING_DOWN
	_r.field_move_party(unbadged)
	_r.check(
		StringName(unbadged.whirlpool_request().get("reason", &"")) == &"badge_required",
		"%s: Dragon's Den allowed Whirlpool without engine flag %d." % [game_id, badge]
	)
	var wrong := Gen2WorldState.new()
	wrong.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_GLACIER, not crystal))
	var wrong_world: Gen2WorldAPI = Gen2WorldAPI.open(data, DEN_GROUP, number, approach, wrong)
	wrong_world.player_facing = Gen2WorldSprite.FACING_DOWN
	_r.field_move_party(wrong_world)
	_r.check(
		StringName(wrong_world.whirlpool_request().get("reason", &"")) == &"badge_required",
		"%s: Dragon's Den accepted the other profile's Glacier Badge flag." % game_id
	)
