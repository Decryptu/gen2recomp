extends GutTest

## Field-move tables and the Cut boundary, against a synthetic cache built for
## this file so the shared world fixture stays untouched.
##
## The cache uses tileset number 1 (TILESET_JOHTO) so the real CutTreeBlockPointers
## rows apply: block $5b is a tree replaced by $3c, block $03 is grass replaced
## by $02. Tileset 5 is TILESET_PLAYERS_HOUSE, which the source table has no
## entry for.

const TILESET_CUTTABLE: int = Gen2WorldFieldMove.TILESET_JOHTO
const TILESET_NO_ENTRY: int = 5
const BLOCK_TREE: int = 0x5B
const BLOCK_TREE_CUT: int = 0x3C
const BLOCK_GRASS: int = 0x03
const BLOCK_GRASS_CUT: int = 0x02
const BLOCK_FLOOR: int = 0x01
const BLOCK_COUNT: int = 0x68

## The cut tree stands at block (1,1)'s bottom-left quadrant and the grass at
## block (2,1)'s, mirroring Ilex Forest's own block $0f layout.
const TREE_CELL: Vector2i = Vector2i(2, 3)
const TREE_BLOCK: Vector2i = Vector2i(1, 1)
const GRASS_CELL: Vector2i = Vector2i(4, 3)
const GRASS_BLOCK: Vector2i = Vector2i(2, 1)

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testfieldmove", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	RomCache.write_json(RomCache.species_path(_directory), [])
	RomCache.write_json(RomCache.moves_path(_directory), [])
	RomCache.write_json(RomCache.items_path(_directory), [])
	RomCache.write_json(RomCache.types_path(_directory), [])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [])

	RomCache.write_json(RomCache.world_tilesets_path(_directory), [
		_tileset(TILESET_CUTTABLE), _tileset(TILESET_NO_ENTRY),
	])
	RomCache.write_json(RomCache.world_maps_path(_directory), [
		_map(1, TILESET_CUTTABLE), _map(2, TILESET_NO_ENTRY),
	])

	var pixels := PackedByteArray()
	pixels.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	for index: int in pixels.size():
		pixels[index] = index % 4
	for number: int in [TILESET_CUTTABLE, TILESET_NO_ENTRY]:
		RomCache.write_indices(RomCache.world_tile_path(_directory, number), pixels)

	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testfieldmove",
		"sha1": "0123456789abcdef",
		"complete": true,
	})


func _tileset(number: int) -> Dictionary:
	var meta: Array = []
	for block: int in BLOCK_COUNT:
		for tile: int in 16:
			meta.append((block + tile) & 0xFF)
	var collision: Array = []
	collision.resize(BLOCK_COUNT * 4)
	for index: int in collision.size():
		collision[index] = 0
	# Quadrant order is top-left, top-right, bottom-left, bottom-right, so the
	# bottom-left cell is index 2. Only the uncut blocks carry a cuttable code.
	collision[BLOCK_TREE * 4 + 2] = 0x12   # COLL_CUT_TREE
	collision[BLOCK_GRASS * 4 + 2] = 0x18  # COLL_TALL_GRASS
	return {
		"number": number,
		"block_count": BLOCK_COUNT,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": collision,
	}


func _map(number: int, tileset: int) -> Dictionary:
	var blocks: Array = []
	for index: int in 16:
		blocks.append(BLOCK_FLOOR)
	blocks[TREE_BLOCK.y * 4 + TREE_BLOCK.x] = BLOCK_TREE
	blocks[GRASS_BLOCK.y * 4 + GRASS_BLOCK.x] = BLOCK_GRASS
	var collision: Array = []
	collision.resize(64)
	for index: int in collision.size():
		collision[index] = 0
	collision[TREE_CELL.y * 8 + TREE_CELL.x] = 0x12
	collision[GRASS_CELL.y * 8 + GRASS_CELL.x] = 0x18
	return {
		"group": 1,
		"number": number,
		"tileset": tileset,
		"width_blocks": 4,
		"height_blocks": 4,
		"blocks": blocks,
		"collision": collision,
		"collision_width": 8,
		"collision_height": 8,
		"events": {},
	}


func _gold_profile() -> void:
	var manifest: Dictionary = RomCache.read_json(RomCache.manifest_path(_directory))
	manifest["game_id"] = "gold"
	RomCache.write_json(RomCache.manifest_path(_directory), manifest)


## A world standing above the cut tree and facing it, with the Hive Badge set on
## whichever engine flag table the opened cache selects.
func _world(map_number: int = 1, badge: bool = true) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_HIVE, Gen2WorldState.is_crystal_profile(data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, map_number, TREE_CELL + Vector2i.UP, state
	)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	return world


func test_cuttable_carries_the_six_check_cut_collision_codes() -> void:
	for code: int in [0x12, 0x1A, 0x10, 0x18, 0x14, 0x1C]:
		assert_true(Gen2WorldFieldMove.cuttable(code), "code $%02x" % code)
	# Neighbours of the cuttable runs, and the codes the other field moves own.
	for code: int in [0x00, 0x11, 0x13, 0x15, 0x19, 0x1B, 0x1D, 0x24, 0x33, 0x07]:
		assert_false(Gen2WorldFieldMove.cuttable(code), "code $%02x" % code)


func test_cut_tree_block_table_matches_the_pinned_rows() -> void:
	var rows: Array = [
		# tileset, facing block, replacement, animation
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x03, 0x02, 1],
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x5B, 0x3C, 0],
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x5F, 0x3D, 0],
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x63, 0x3F, 0],
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x67, 0x3E, 0],
		[Gen2WorldFieldMove.TILESET_JOHTO_MODERN, 0x03, 0x02, 1],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x0B, 0x0A, 1],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x32, 0x6D, 0],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x33, 0x6C, 0],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x34, 0x6F, 0],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x35, 0x4C, 0],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x60, 0x6E, 0],
	]
	for row: Array in rows:
		for crystal: bool in [true, false]:
			var result: Dictionary = Gen2WorldFieldMove.cut_replacement(row[0], row[1], crystal)
			assert_true(bool(result.get("ok", false)), "tileset %d block $%02x" % [row[0], row[1]])
			assert_eq(int(result["block"]), int(row[2]))
			assert_eq(int(result["animation"]), int(row[3]))


func test_park_and_forest_tileset_numbers_are_profile_split() -> void:
	var park: Array = [[0x13, 0x03, 1], [0x03, 0x04, 1]]
	var forest: Array = [[0x0F, 0x17, 0]]
	var cases: Array = [
		[Gen2WorldFieldMove.TILESET_PARK_CRYSTAL, true, park],
		[Gen2WorldFieldMove.TILESET_PARK_GOLD_SILVER, false, park],
		[Gen2WorldFieldMove.TILESET_FOREST_CRYSTAL, true, forest],
		[Gen2WorldFieldMove.TILESET_FOREST_GOLD_SILVER, false, forest],
	]
	for case: Array in cases:
		for row: Array in case[2] as Array:
			var hit: Dictionary = Gen2WorldFieldMove.cut_replacement(case[0], row[0], case[1])
			assert_true(bool(hit.get("ok", false)), "tileset %d block $%02x" % [case[0], row[0]])
			assert_eq(int(hit["block"]), int(row[1]))
			assert_eq(int(hit["animation"]), int(row[2]))
			# The other profile numbers the same tileset differently, so its
			# number must not resolve there.
			var miss: Dictionary = Gen2WorldFieldMove.cut_replacement(
				case[0], row[0], not bool(case[1])
			)
			assert_false(bool(miss.get("ok", false)), "tileset %d on the other profile" % case[0])


func test_cut_replacement_refuses_an_absent_tileset_or_block() -> void:
	assert_false(bool(Gen2WorldFieldMove.cut_replacement(
		TILESET_NO_ENTRY, BLOCK_TREE, true
	).get("ok", false)))
	assert_false(bool(Gen2WorldFieldMove.cut_replacement(
		Gen2WorldFieldMove.TILESET_JOHTO, 0x00, true
	).get("ok", false)))


func test_cut_request_checks_the_badge_before_the_tile() -> void:
	# .CheckAble calls CheckBadge first, so a player facing a real tree without
	# the Hive Badge is told about the badge, not about the tree.
	var world: Gen2WorldAPI = _world(1, false)
	var refused: Dictionary = world.cut_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"badge_required")
	assert_true(world.pending_cut().is_empty())


func test_cut_request_reads_the_gold_silver_badge_flag() -> void:
	_gold_profile()
	var data: GameData = GameData.open_directory(_directory)
	assert_false(Gen2WorldState.is_crystal_profile(data))
	# Crystal's ENGINE_HIVEBADGE (28) must not answer on a Gold cache, whose
	# shorter engine flag table puts the same badge at 27.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_HIVEBADGE)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, TREE_CELL + Vector2i.UP, state
	)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	assert_eq(world.cut_request()["reason"], &"badge_required")

	state.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_HIVE, false))
	assert_true(bool(world.cut_request().get("ok", false)))


func test_cut_request_refuses_a_tile_that_is_not_cuttable() -> void:
	var world: Gen2WorldAPI = _world()
	world.player_cell = Vector2i(6, 6)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var refused: Dictionary = world.cut_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"nothing_to_cut")


func test_cut_request_refuses_a_tileset_without_a_block_list() -> void:
	# Map 2 carries the identical tree cell on TILESET_PLAYERS_HOUSE, which
	# CutTreeBlockPointers has no entry for.
	var world: Gen2WorldAPI = _world(2)
	assert_true(Gen2WorldFieldMove.cuttable(world.collision_code_at(TREE_CELL)))
	assert_eq(world.cut_request()["reason"], &"nothing_to_cut")


func test_cut_request_stages_without_changing_the_map() -> void:
	var world: Gen2WorldAPI = _world()
	assert_false(world.can_walk_to(TREE_CELL))
	var staged: Dictionary = world.cut_request()
	assert_true(bool(staged.get("ok", false)), JSON.stringify(staged))
	assert_eq(staged["block_cell"], TREE_BLOCK)
	assert_eq(int(staged["block"]), BLOCK_TREE_CUT)
	assert_eq(int(staged["animation"]), Gen2WorldFieldMove.ANIMATION_TREE)
	# Script_Cut writes the block only after its text, so nothing has moved yet.
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)
	assert_false(world.can_walk_to(TREE_CELL))
	assert_eq(world.pending_cut()["block"], BLOCK_TREE_CUT)


func test_complete_cut_replaces_the_block_and_opens_the_cell() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(bool(world.cut_request().get("ok", false)))
	var applied: Dictionary = world.complete_cut()
	assert_true(bool(applied.get("ok", false)), JSON.stringify(applied))
	assert_eq(applied["kind"], &"cut_applied")
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE_CUT)
	assert_eq(world.collision_code_at(TREE_CELL), 0x00)
	assert_true(world.can_walk_to(TREE_CELL))
	assert_true(world.pending_cut().is_empty())


func test_cutting_grass_keeps_the_cell_walkable_and_swaps_the_block() -> void:
	var world: Gen2WorldAPI = _world()
	world.player_cell = GRASS_CELL + Vector2i.UP
	# The four grass codes are LAND_TILE, so this cell was always walkable; only
	# the block changes.
	assert_true(world.can_walk_to(GRASS_CELL))
	var staged: Dictionary = world.cut_request()
	assert_true(bool(staged.get("ok", false)), JSON.stringify(staged))
	assert_eq(int(staged["animation"]), Gen2WorldFieldMove.ANIMATION_GRASS)
	assert_true(bool(world.complete_cut().get("ok", false)))
	assert_eq(world.block_at(GRASS_BLOCK.x, GRASS_BLOCK.y), BLOCK_GRASS_CUT)
	assert_true(world.can_walk_to(GRASS_CELL))


func test_a_second_request_refuses_while_one_is_staged() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(bool(world.cut_request().get("ok", false)))
	assert_eq(world.cut_request()["reason"], &"cut_in_progress")


func test_complete_cut_without_a_request_fails() -> void:
	var world: Gen2WorldAPI = _world()
	var applied: Dictionary = world.complete_cut()
	assert_false(bool(applied.get("ok", false)))
	assert_eq(applied["reason"], &"no_pending_cut")


func test_a_map_reload_regrows_the_tree_and_drops_a_staged_cut() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(bool(world.cut_request().get("ok", false)))
	assert_true(bool(world.complete_cut().get("ok", false)))
	assert_true(world.can_walk_to(TREE_CELL))
	# CutDownTreeOrGrass only writes wOverworldMapBlocks, and a map load re-reads
	# the block data from ROM, so the tree is back on the next visit.
	assert_true(bool(world.reload_current_map().get("ok", false)))
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)
	assert_false(world.can_walk_to(TREE_CELL))

	assert_true(bool(world.cut_request().get("ok", false)))
	world.reload_current_map()
	assert_true(world.pending_cut().is_empty())
