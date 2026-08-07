extends SceneTree

## Verifies Cut against freshly imported real caches, for both command profiles.
##
## The expected values come from the pinned pokecrystal and pokegold sources:
## engine/events/overworld.asm's CutFunction and CheckMapForSomethingToCut,
## engine/overworld/tile_events.asm's CheckCutCollision,
## data/collision/field_move_blocks.asm's CutTreeBlockPointers, and
## constants/tileset_constants.asm, whose PARK and FOREST numbers are the only
## part of that table that differs between the two games.
##
## The real-cartridge counterpart to tests/unit/test_world_field_move.gd, which
## uses a synthetic cache. Ilex Forest is the acceptance case, because its single
## cut tree is what gates the route west out of the forest.
##
##   Godot --headless --path . -s res://tools/validate_cut.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm, DUNGEONS group. Crystal's extra maps push
## Ilex Forest eight places later within the same group.
const ILEX_GROUP: int = 3
const ILEX_NUMBER_CRYSTAL: int = 52
const ILEX_NUMBER_GOLD_SILVER: int = 44
## maps/IlexForest.blk, identical in both pins: one block $0f, whose bottom-left
## quadrant is the COLL_CUT_TREE cell (data/tilesets/forest_collision.asm).
const ILEX_BLOCK := Vector2i(4, 12)
const ILEX_TREE_CELL := Vector2i(8, 25)
const ILEX_BLOCK_UNCUT: int = 0x0F
const ILEX_BLOCK_CUT: int = 0x17

## Census of the real caches, pinned so a cache change is loud. Crystal offers
## 28 more cuttable cells than it can act on: park blocks $33 and $3f are
## all-LONG_GRASS (data/tilesets/park_collision.asm) but CutTreeBlockPointers'
## .park list holds only $13 and $03, so the cartridge answers "nothing to cut"
## on them too. Every Gold/Silver cuttable cell resolves.
const EXPECTED_CENSUS: Dictionary = {
	# game id: [cuttable cells, cells resolving to a replacement, maps]
	&"gold": [3404, 3404, 54],
	&"silver": [3404, 3404, 54],
	&"crystal": [3444, 3416, 54],
}

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_tileset_numbers(game_id, data, crystal)
		_census(game_id, data, crystal)
		_verify_ilex_forest(game_id, data, crystal)
	_finish()


## Every tileset CutTreeBlockPointers names must exist in this cache under the
## number this profile uses, so a wrong split would fail loudly rather than
## quietly making a tileset uncuttable.
func _verify_tileset_numbers(game_id: StringName, data: GameData, crystal: bool) -> void:
	var expected: Array[int] = [
		Gen2WorldFieldMove.TILESET_JOHTO,
		Gen2WorldFieldMove.TILESET_JOHTO_MODERN,
		Gen2WorldFieldMove.TILESET_KANTO,
		Gen2WorldFieldMove.TILESET_PARK_CRYSTAL if crystal \
			else Gen2WorldFieldMove.TILESET_PARK_GOLD_SILVER,
		Gen2WorldFieldMove.TILESET_FOREST_CRYSTAL if crystal \
			else Gen2WorldFieldMove.TILESET_FOREST_GOLD_SILVER,
	]
	for number: int in expected:
		_check(
			data.world_tileset(number) != null,
			"%s: tileset %d from CutTreeBlockPointers is missing." % [game_id, number]
		)


## Counts the cells a real cache actually offers Cut, so a cache change that
## moves a block or a collision code is loud rather than silently making the
## forest uncuttable.
func _census(game_id: StringName, data: GameData, crystal: bool) -> void:
	var cuttable_cells: int = 0
	var resolved_cells: int = 0
	var maps_with_cut: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		var found: bool = false
		for y: int in map.collision_height:
			for x: int in map.collision_width:
				if not Gen2WorldFieldMove.cuttable(map.collision_at(x, y)):
					continue
				cuttable_cells += 1
				var replacement: Dictionary = Gen2WorldFieldMove.cut_replacement(
					map.tileset, map.block_at(x >> 1, y >> 1), crystal
				)
				if bool(replacement.get("ok", false)):
					resolved_cells += 1
					found = true
		if found:
			maps_with_cut[Vector2i(map.group, map.number)] = true
	var counts: Array = [cuttable_cells, resolved_cells, maps_with_cut.size()]
	print("%s: %d cuttable cells, %d resolving to a replacement across %d maps." % [
		game_id, counts[0], counts[1], counts[2],
	])
	_check(
		counts == EXPECTED_CENSUS.get(game_id, []),
		"%s: census is %s, not the pinned %s." % [
			game_id, counts, EXPECTED_CENSUS.get(game_id, []),
		]
	)


func _verify_ilex_forest(game_id: StringName, data: GameData, crystal: bool) -> void:
	var number: int = ILEX_NUMBER_CRYSTAL if crystal else ILEX_NUMBER_GOLD_SILVER
	var badge: int = Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_HIVE, crystal)
	var state := Gen2WorldState.new()
	state.set_engine_flag(badge)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ILEX_GROUP, number, ILEX_TREE_CELL + Vector2i.UP, state
	)
	if not _check(
		world != null, "%s: Ilex Forest map %d/%d is missing." % [game_id, ILEX_GROUP, number]
	):
		return
	world.player_facing = Gen2WorldSprite.FACING_DOWN

	var tileset: int = world.current_map.tileset
	var expected_tileset: int = Gen2WorldFieldMove.TILESET_FOREST_CRYSTAL if crystal \
		else Gen2WorldFieldMove.TILESET_FOREST_GOLD_SILVER
	_check(
		tileset == expected_tileset,
		"%s: Ilex Forest is tileset %d, not the expected FOREST %d." % [
			game_id, tileset, expected_tileset,
		]
	)
	var block: int = world.block_at(ILEX_BLOCK.x, ILEX_BLOCK.y)
	_check(
		block == ILEX_BLOCK_UNCUT,
		"%s: Ilex Forest block %s is $%02X, not $%02X." % [
			game_id, ILEX_BLOCK, block, ILEX_BLOCK_UNCUT,
		]
	)
	var code: int = world.collision_code_at(ILEX_TREE_CELL)
	_check(
		code == 0x12,
		"%s: Ilex Forest %s is $%02X, not COLL_CUT_TREE." % [game_id, ILEX_TREE_CELL, code]
	)
	_check(
		not world.can_walk_to(ILEX_TREE_CELL),
		"%s: Ilex Forest cut tree at %s does not block." % [game_id, ILEX_TREE_CELL]
	)

	var staged: Dictionary = world.cut_request()
	if not _check(
		bool(staged.get("ok", false)),
		"%s: Ilex Forest refused Cut: %s." % [game_id, staged.get("reason", "unknown")]
	):
		return
	_check(
		int(staged.get("block", -1)) == ILEX_BLOCK_CUT
			and staged.get("block_cell", Vector2i.ZERO) == ILEX_BLOCK,
		"%s: Ilex Forest staged %s, not block $%02X at %s." % [
			game_id, JSON.stringify(staged), ILEX_BLOCK_CUT, ILEX_BLOCK,
		]
	)
	# Script_Cut writes the block only after UseCutText, so staging alone must
	# leave the map exactly as it was.
	_check(
		world.block_at(ILEX_BLOCK.x, ILEX_BLOCK.y) == ILEX_BLOCK_UNCUT
			and not world.can_walk_to(ILEX_TREE_CELL),
		"%s: Ilex Forest changed before the cut was committed." % game_id
	)

	_check(
		bool(world.complete_cut().get("ok", false)),
		"%s: Ilex Forest cut did not commit." % game_id
	)
	_check(
		world.block_at(ILEX_BLOCK.x, ILEX_BLOCK.y) == ILEX_BLOCK_CUT,
		"%s: Ilex Forest block is $%02X after the cut." % [
			game_id, world.block_at(ILEX_BLOCK.x, ILEX_BLOCK.y),
		]
	)
	_check(
		world.can_walk_to(ILEX_TREE_CELL),
		"%s: Ilex Forest %s is still blocked after the cut." % [game_id, ILEX_TREE_CELL]
	)
	print("%s: Ilex Forest %d/%d %s $%02X -> $%02X, cell %s opened." % [
		game_id, ILEX_GROUP, number, ILEX_BLOCK, ILEX_BLOCK_UNCUT, ILEX_BLOCK_CUT,
		ILEX_TREE_CELL,
	])

	# CutDownTreeOrGrass only writes wOverworldMapBlocks, which a map load
	# re-reads from ROM, so the tree is back on the next visit.
	world.reload_current_map()
	_check(
		world.block_at(ILEX_BLOCK.x, ILEX_BLOCK.y) == ILEX_BLOCK_UNCUT
			and not world.can_walk_to(ILEX_TREE_CELL),
		"%s: Ilex Forest tree did not regrow on a map reload." % game_id
	)

	# .CheckAble tests the badge before the tile, on whichever engine flag table
	# this profile numbers ENGINE_HIVEBADGE on.
	var unbadged := Gen2WorldState.new()
	var unbadged_world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ILEX_GROUP, number, ILEX_TREE_CELL + Vector2i.UP, unbadged
	)
	unbadged_world.player_facing = Gen2WorldSprite.FACING_DOWN
	_check(
		StringName(unbadged_world.cut_request().get("reason", &"")) == &"badge_required",
		"%s: Ilex Forest allowed Cut without engine flag %d." % [game_id, badge]
	)
	# The other profile's flag number must not answer for this one.
	var wrong := Gen2WorldState.new()
	wrong.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_HIVE, not crystal))
	var wrong_world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ILEX_GROUP, number, ILEX_TREE_CELL + Vector2i.UP, wrong
	)
	wrong_world.player_facing = Gen2WorldSprite.FACING_DOWN
	_check(
		StringName(wrong_world.cut_request().get("reason", &"")) == &"badge_required",
		"%s: Ilex Forest accepted the other profile's Hive Badge flag." % game_id
	)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS cut: block tables, tileset numbers and Ilex Forest verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
