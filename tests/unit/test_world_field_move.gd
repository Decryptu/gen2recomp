extends GutTest

## Field-move tables and the Cut and Surf boundaries, against a synthetic cache
## built for this file so the shared world fixture stays untouched.
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
## Two blocks CutTreeBlockPointers has no row for, so the surf fixture cannot
## disturb any Cut case.
const BLOCK_WATER: int = 0x20
const BLOCK_WALLED_SHORE: int = 0x21
const BLOCK_COUNT: int = 0x68

## The cut tree stands at block (1,1)'s bottom-left quadrant and the grass at
## block (2,1)'s, mirroring Ilex Forest's own block $0f layout.
const TREE_CELL: Vector2i = Vector2i(2, 3)
const TREE_BLOCK: Vector2i = Vector2i(1, 1)
const GRASS_CELL: Vector2i = Vector2i(4, 3)
const GRASS_BLOCK: Vector2i = Vector2i(2, 1)

## A shore in block (3,1): land above COLL_WATER, the New Bark Town shape the
## real-cache validator drives. The second shore in block (0,3) stands on
## COLL_DOWN_WALL, whose own edge mask is what CheckDirection reads.
const WATER_CELL: Vector2i = Vector2i(6, 3)
const SHORE_CELL: Vector2i = Vector2i(6, 2)
const WALLED_WATER_CELL: Vector2i = Vector2i(0, 7)
const WALLED_SHORE_CELL: Vector2i = Vector2i(0, 6)
const COLL_WATER: int = 0x29
const COLL_DOWN_WALL: int = 0xB3

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
	collision[BLOCK_WATER * 4 + 2] = COLL_WATER
	collision[BLOCK_WALLED_SHORE * 4 + 0] = COLL_DOWN_WALL
	collision[BLOCK_WALLED_SHORE * 4 + 2] = COLL_WATER
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
	blocks[1 * 4 + 3] = BLOCK_WATER
	blocks[3 * 4 + 0] = BLOCK_WALLED_SHORE
	var collision: Array = []
	collision.resize(64)
	for index: int in collision.size():
		collision[index] = 0
	collision[TREE_CELL.y * 8 + TREE_CELL.x] = 0x12
	collision[GRASS_CELL.y * 8 + GRASS_CELL.x] = 0x18
	collision[WATER_CELL.y * 8 + WATER_CELL.x] = COLL_WATER
	collision[WALLED_SHORE_CELL.y * 8 + WALLED_SHORE_CELL.x] = COLL_DOWN_WALL
	collision[WALLED_WATER_CELL.y * 8 + WALLED_WATER_CELL.x] = COLL_WATER
	# A warp pair between the shore and the water cell of the other map, so a map
	# transition can land the player on either kind of tile. Destinations are
	# one-based, so both point at the other map's only warp.
	var warp_cell: Vector2i = SHORE_CELL if number == 1 else WATER_CELL
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
		"events": {"warps": [{
			"x": warp_cell.x, "y": warp_cell.y, "destination": 1,
			"map_group": 1, "map_number": 2 if number == 1 else 1,
		}]},
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


## A world standing on the shore facing the water, with the Fog Badge set on
## whichever engine flag table the opened cache selects.
func _surf_world(badge: bool = true, stand: Vector2i = SHORE_CELL) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_FOG, Gen2WorldState.is_crystal_profile(data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, stand, state)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	return world


func test_cut_and_surf_are_the_field_moves_the_submenu_offers() -> void:
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_CUT))
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_SURF))
	assert_eq(Gen2WorldFieldMove.MOVE_CUT, 0x0F)
	assert_eq(Gen2WorldFieldMove.MOVE_SURF, 0x39)
	# MonMenuOptions rows this project does not act on yet must stay out, or the
	# submenu would offer an entry nothing answers: FLY, STRENGTH, FLASH,
	# WATERFALL, WHIRLPOOL, HEADBUTT.
	for move: int in [0x13, 0x46, 0x94, 0x7F, 0xFA, 0x1D]:
		assert_false(Gen2WorldFieldMove.is_field_move(move), "move $%02x" % move)


func test_surf_sprite_follows_get_surf_type() -> void:
	assert_eq(
		Gen2WorldFieldMove.surf_sprite(Gen2WorldFieldMove.SPECIES_PIKACHU),
		Gen2WorldSprite.SPRITE_SURFING_PIKACHU
	)
	assert_eq(Gen2WorldFieldMove.SPECIES_PIKACHU, 25)
	assert_eq(Gen2WorldSprite.SPRITE_SURF, 83)
	assert_eq(Gen2WorldSprite.SPRITE_SURFING_PIKACHU, 52)
	for species: int in [0, 1, 24, 26, 251]:
		assert_eq(Gen2WorldFieldMove.surf_sprite(species), Gen2WorldSprite.SPRITE_SURF)


func test_surf_request_checks_the_badge_before_the_state_and_the_tile() -> void:
	# .TrySurf calls CheckBadge first, so a player without the Fog Badge is told
	# about the badge whether or not the tile in front of them is surfable.
	var world: Gen2WorldAPI = _surf_world(false)
	var refused: Dictionary = world.surf_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"badge_required")
	assert_true(world.pending_surf().is_empty())

	# Facing land, and already surfing, still answer the badge first.
	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(world.surf_request()["reason"], &"badge_required")
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.surf_request()["reason"], &"badge_required")


func test_surf_request_reads_the_gold_silver_badge_flag() -> void:
	_gold_profile()
	var data: GameData = GameData.open_directory(_directory)
	assert_false(Gen2WorldState.is_crystal_profile(data))
	# Crystal's ENGINE_FOGBADGE (30) must not answer on a Gold cache, whose
	# shorter engine flag table puts the same badge at 29.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_FOGBADGE)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, SHORE_CELL, state)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	assert_eq(world.surf_request()["reason"], &"badge_required")

	state.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_FOG, false))
	assert_true(bool(world.surf_request().get("ok", false)))


func test_surf_request_refuses_a_tile_that_is_not_water() -> void:
	var world: Gen2WorldAPI = _surf_world()
	world.player_facing = Gen2WorldSprite.FACING_UP
	var refused: Dictionary = world.surf_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"cannot_surf")


func test_surf_request_refuses_when_the_standing_tile_walls_the_direction() -> void:
	# CheckDirection ANDs wTilePermissions against the facing bit, so a
	# COLL_DOWN_WALL shore refuses even with water directly below it.
	var world: Gen2WorldAPI = _surf_world(true, WALLED_SHORE_CELL)
	assert_eq(
		world.collision_permission_at(WALLED_WATER_CELL), Gen2WorldCollision.WATER_TILE
	)
	assert_eq(
		world.tile_permissions_at(WALLED_SHORE_CELL) & Gen2WorldCollision.FACE_DOWN,
		Gen2WorldCollision.FACE_DOWN
	)
	assert_eq(world.surf_request()["reason"], &"cannot_surf")


func test_surf_request_stages_without_moving_the_player() -> void:
	var world: Gen2WorldAPI = _surf_world()
	var staged: Dictionary = world.surf_request()
	assert_true(bool(staged.get("ok", false)), JSON.stringify(staged))
	assert_eq(staged["kind"], &"surf_requested")
	assert_eq(staged["cell"], WATER_CELL)
	assert_eq(staged["direction"], Vector2i.DOWN)
	assert_eq(int(staged["sprite"]), Gen2WorldSprite.SPRITE_SURF)
	# UsedSurfScript shows its text before writevar VAR_MOVEMENT, so nothing has
	# changed yet.
	assert_eq(world.player_cell, SHORE_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_PLAYER)
	assert_eq(world.pending_surf()["cell"], WATER_CELL)


func test_complete_surf_enters_the_water_without_spending_a_step() -> void:
	var world: Gen2WorldAPI = _surf_world()
	world.state.set_repel_steps(20)
	assert_true(bool(world.surf_request().get("ok", false)))
	var applied: Dictionary = world.complete_surf()
	assert_true(bool(applied.get("ok", false)), JSON.stringify(applied))
	assert_eq(applied["kind"], &"surf_applied")
	assert_eq(world.player_cell, WATER_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURF)
	# SurfStartStep is an applymovement, not player input: no repel step is
	# consumed and no encounter is rolled.
	assert_eq(world.state.repel_steps(), 20)
	assert_true(world.player_step_in_progress())
	assert_true(world.pending_surf().is_empty())


func test_complete_surf_carries_the_pikachu_variant() -> void:
	var world: Gen2WorldAPI = _surf_world()
	assert_true(bool(
		world.surf_request(Gen2WorldFieldMove.SPECIES_PIKACHU).get("ok", false)
	))
	assert_eq(
		int(world.complete_surf()["sprite"]), Gen2WorldSprite.SPRITE_SURFING_PIKACHU
	)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURFING_PIKACHU)


func test_surf_request_refuses_while_staged_or_already_surfing() -> void:
	var world: Gen2WorldAPI = _surf_world()
	assert_true(bool(world.surf_request().get("ok", false)))
	assert_eq(world.surf_request()["reason"], &"surf_in_progress")
	assert_true(bool(world.complete_surf().get("ok", false)))
	assert_eq(world.surf_request()["reason"], &"already_surfing")


func test_complete_surf_without_a_request_fails() -> void:
	var world: Gen2WorldAPI = _surf_world()
	var applied: Dictionary = world.complete_surf()
	assert_false(bool(applied.get("ok", false)))
	assert_eq(applied["reason"], &"no_pending_surf")
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)


func test_a_map_transition_rederives_the_player_state_from_the_landing_cell() -> void:
	# CheckUpdatePlayerSprite runs on every warp and connection: .CheckSurfing
	# starts surfing on water, .ResetSurfingOrBikingState restores walking
	# anywhere else. Without it a warp taken from water strands the player on
	# land in a mode where only water is a legal step.
	var world: Gen2WorldAPI = _surf_world()
	var onto_water: Dictionary = world.try_warp()
	assert_true(bool(onto_water.get("ok", false)), JSON.stringify(onto_water))
	assert_eq(world.player_cell, WATER_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURF)

	var onto_land: Dictionary = world.try_warp()
	assert_true(bool(onto_land.get("ok", false)), JSON.stringify(onto_land))
	assert_eq(world.player_cell, SHORE_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_PLAYER)


func test_a_map_transition_keeps_the_pikachu_surf_variant() -> void:
	# .CheckSurfing keeps an existing surf state rather than overwriting it, so
	# the Pikachu sprite survives a warp between two water cells.
	var world: Gen2WorldAPI = _surf_world()
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	world.player_sprite_number = Gen2WorldSprite.SPRITE_SURFING_PIKACHU
	assert_true(bool(world.try_warp().get("ok", false)))
	assert_eq(world.player_cell, WATER_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURFING_PIKACHU)


func test_a_map_reload_drops_a_staged_surf() -> void:
	var world: Gen2WorldAPI = _surf_world()
	assert_true(bool(world.surf_request().get("ok", false)))
	assert_true(bool(world.reload_current_map().get("ok", false)))
	assert_true(world.pending_surf().is_empty())


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
