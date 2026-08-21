extends GutTest

## Animation tests run against a cache-shaped fixture. The real cartridge import
## is covered by the ROM tool; this keeps the runtime interpreter fast and
## deterministic in the unit suite.

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testanimation", "fedcba9876543210")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	for path: String in [
		RomCache.species_path(_directory), RomCache.moves_path(_directory),
		RomCache.items_path(_directory), RomCache.types_path(_directory),
		RomCache.matchups_path(_directory), RomCache.trainers_path(_directory),
	]:
		RomCache.write_json(path, [])

	var meta: Array = []
	for _index: int in 16:
		meta.append(0)
	RomCache.write_json(RomCache.world_tilesets_path(_directory), [{
		"number": 0,
		"block_count": 1,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [],
		"palette_map": [0],
		"animation_commands": [
			{"operation": "water", "tile": 0},
			{"operation": "done"},
		],
	}, {
		# The same tile animated properly: a timer bump per pass, so the water
		# command walks all four frames of the asset instead of standing on the
		# first. What tile_frames() has to recover.
		"number": 1,
		"block_count": 1,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [],
		"palette_map": [0],
		"animation_commands": [
			{"operation": "timer_8"},
			{"operation": "water", "tile": 0},
			{"operation": "done"},
		],
	}, {
		# `TilesetForestAnim`'s own four tree commands, in its order: the pair
		# and then the pair the source offsets by a frame, with the timer bump
		# after both so all four see the same `wTileAnimationTimer`.
		"number": 2,
		"block_count": 1,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [],
		"palette_map": [0],
		"animation_commands": [
			{"operation": "forest_left"},
			{"operation": "forest_right"},
			{"operation": "forest_left_2"},
			{"operation": "forest_right_2"},
			{"operation": "timer_8"},
			{"operation": "done"},
		],
	}])
	RomCache.write_json(RomCache.world_maps_path(_directory), [{
		"group": 1,
		"number": 1,
		"tileset": 0,
		"environment": 0,
		"width_blocks": 1,
		"height_blocks": 1,
		"blocks": [0],
		"collision": [0, 0, 0, 0],
		"collision_width": 2,
		"collision_height": 2,
	}, {
		"group": 1,
		"number": 3,
		"tileset": 2,
		"environment": 0,
		"width_blocks": 1,
		"height_blocks": 1,
		"blocks": [0],
		"collision": [0, 0, 0, 0],
		"collision_width": 2,
		"collision_height": 2,
	}, {
		"group": 1,
		"number": 2,
		"tileset": 1,
		"environment": 0,
		"width_blocks": 1,
		"height_blocks": 1,
		"blocks": [0],
		"collision": [0, 0, 0, 0],
		"collision_width": 2,
		"collision_height": 2,
	}])
	var pixels := PackedByteArray()
	pixels.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	RomCache.write_indices(RomCache.world_tile_path(_directory, 0), pixels)
	RomCache.write_indices(RomCache.world_tile_path(_directory, 1), pixels)
	RomCache.write_indices(RomCache.world_tile_path(_directory, 2), pixels)

	var palettes: Array = []
	for _group: int in RomLayout.WORLD_PALETTE_GROUP_COUNT:
		palettes.append([0x7FFF, 0x421F, 0x2108, 0])
	RomCache.write_json(RomCache.world_palettes_path(_directory), palettes)

	var water: Array = []
	water.resize(64)
	for index: int in water.size():
		water[index] = 0
	# Frame 0 is a solid low plane; the other three are one, two and three lit
	# rows, so the four frames are told apart by their contents.
	for y: int in 8:
		water[y * 2] = 0xFF
	for frame: int in range(1, 4):
		for y: int in frame:
			water[frame * 16 + y * 2] = 0xFF
	# `ForestTreeLeftFrames` and `ForestTreeRightFrames`, four tiles in a row,
	# each filled with its own index so a written tile names the frame it came
	# from: 1 and 2 are the left tree's, 3 and 4 the right tree's.
	var forest: Array = []
	forest.resize(64)
	for index: int in forest.size():
		forest[index] = 0
	for tile: int in 4:
		for y: int in 8:
			forest[tile * 16 + y * 2] = 0xFF if (tile & 1) == 0 else 0
			forest[tile * 16 + y * 2 + 1] = 0xFF if (tile & 1) == 1 else 0
	RomCache.write_json(
		RomCache.world_animation_assets_path(_directory), {"water": water, "forest": forest}
	)
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testanimation",
		"sha1": "fedcba9876543210",
		"complete": true,
	})


func test_water_command_writes_the_imported_frame_and_done_loops() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	assert_true(animation.tick())
	assert_eq(animation.current_indices()[0], 1)
	assert_eq(animation.current_indices()[7], 1)
	assert_true(animation.tick())
	assert_true(animation.tick())
	assert_eq(animation.current_indices()[0], 1)


func test_advance_frame_reports_no_redraw_when_the_command_changes_nothing() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	assert_true(animation.advance_frame())
	# "done" only rewinds the command index, so nothing new is drawn and the
	# renderer must not rebuild its atlas for it.
	assert_false(animation.advance_frame())
	# The water command runs again, but writes the frame that is already there.
	assert_false(animation.advance_frame())


func test_changed_tiles_reports_exactly_the_tiles_a_frame_rewrote() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	# A renderer repaints only the reported tiles, so an under-report leaves a
	# stale tile on screen and an over-report costs the work this replaced.
	for _frame: int in 240:
		var before: PackedByteArray = animation.current_indices().duplicate()
		var redraw: bool = animation.advance_frame()
		var after: PackedByteArray = animation.current_indices()
		var actually_changed: Array = []
		var width: int = RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_WIDTH
		for tile: int in RomLayout.TILESET_TILE_COUNT:
			for pixel: int in Gen2Tiles.TILE_PIXELS:
				@warning_ignore("integer_division")
				var at: int = (pixel / Gen2Tiles.TILE_WIDTH) * width \
					+ tile * Gen2Tiles.TILE_WIDTH + pixel % Gen2Tiles.TILE_WIDTH
				if before[at] != after[at]:
					actually_changed.append(tile)
					break
		assert_eq(Array(animation.changed_tiles()), actually_changed)
		assert_eq(redraw, not actually_changed.is_empty() or animation.palette_changed())


func test_tile_frames_answers_every_frame_in_order_without_moving_the_sequence() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 2, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)
	for _frame: int in 5:
		animation.advance_frame()
	var before: PackedByteArray = animation.current_indices().duplicate()
	var at: int = animation.command_index()

	# The tileset's own tile, then the four the water command plays.
	var frames: Array[PackedByteArray] = animation.tile_frames(0)
	assert_eq(frames.size(), 5)
	# The asset's four frames light 8, 1, 2 and 3 rows, in that play order.
	var lit: Array[int] = []
	for frame: PackedByteArray in frames:
		lit.append(frame.count(1))
	assert_eq(lit, [0, 64, 8, 16, 24] as Array[int])
	# A mod shares this object with the running game, so asking must not step it.
	assert_eq(animation.current_indices(), before)
	assert_eq(animation.command_index(), at)
	# A tile no command touches has no frames, rather than one of itself.
	assert_eq(animation.tile_frames(1).size(), 0)


func test_reload_tileset_keeps_the_place_a_connection_crossing_left() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)
	for _frame: int in 3:
		animation.advance_frame()
	var at: int = animation.command_index()
	assert_ne(at, 0)

	# `MapSetupScript_Connection` carries `LoadMapTileset` and no
	# `LoadMapGraphics`, so nothing resets `hTileAnimFrame`: the neighbour's own
	# command list is loaded where the sequence stands.
	var neighbour := Gen2WorldAPI.open(data, 1, 2, Vector2i.ZERO)
	animation.reload_tileset(neighbour)
	assert_eq(animation.command_index(), at)
	assert_eq(animation.tileset.number, 1)
	# A warp is the other setup script and does reset it.
	animation.configure(neighbour)
	assert_eq(animation.command_index(), 0)


## The four tree commands read `wCelebiEvent` on every tick, so an ordinary visit
## to Ilex Forest draws both trees on their first frame and the restless one
## alternates, with `...Animation2`'s `xor %10` a frame ahead of its pair.
func test_the_forest_trees_stand_still_until_the_celebi_event_is_set() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 3, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	# Two whole cycles of the six commands, which leaves wTileAnimationTimer at
	# 2 and both trees on the frame the `jr nz` branch never leaves.
	for _command: int in 12:
		animation.tick()
	assert_eq(_tree_frame(animation, 0x0C), 0)
	assert_eq(_tree_frame(animation, 0x0F), 0)

	world.state.set_engine_flag(Gen2WorldState.engine_flag(
		Gen2WorldState.ENGINE_FOREST_IS_RESTLESS, Gen2WorldState.is_crystal_profile(data)
	))
	# An even timer is `GetForestTreeFrame`'s own zero, so the pair draws the
	# first frame and the `xor %10` pair the second.
	_tick_pair(animation)
	assert_eq(_tree_frame(animation, 0x0C), 0)
	assert_eq(_tree_frame(animation, 0x0F), 0)
	_tick_pair(animation)
	assert_eq(_tree_frame(animation, 0x0C), 1)
	assert_eq(_tree_frame(animation, 0x0F), 1)

	# The bump and the rewind, and then the odd timer answers the other way round.
	_tick_pair(animation)
	_tick_pair(animation)
	assert_eq(_tree_frame(animation, 0x0C), 1)
	assert_eq(_tree_frame(animation, 0x0F), 1)
	_tick_pair(animation)
	assert_eq(_tree_frame(animation, 0x0C), 0)
	assert_eq(_tree_frame(animation, 0x0F), 0)


func _tick_pair(animation: Gen2WorldAnimation) -> void:
	animation.tick()
	animation.tick()


## Which of the two frames a tree tile is holding, read off the fixture asset's
## own marking: frame 0 lights the first plane and frame 1 the second, so the
## palette index of a lit pixel is 1 or 2. The strip is one row of tiles, so a
## tile's first pixel is its own column of row zero rather than a tile-sized
## stride into the array.
func _tree_frame(animation: Gen2WorldAnimation, tile: int) -> int:
	return 0 if animation.current_indices()[tile * Gen2Tiles.TILE_WIDTH] == 1 else 1
