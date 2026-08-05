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
	}])
	var pixels := PackedByteArray()
	pixels.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	RomCache.write_indices(RomCache.world_tile_path(_directory, 0), pixels)

	var palettes: Array = []
	for _group: int in RomLayout.WORLD_PALETTE_GROUP_COUNT:
		palettes.append([0x7FFF, 0x421F, 0x2108, 0])
	RomCache.write_json(RomCache.world_palettes_path(_directory), palettes)

	var water: Array = []
	water.resize(64)
	for index: int in water.size():
		water[index] = 0
	for y: int in 8:
		water[y * 2] = 0xFF
	RomCache.write_json(RomCache.world_animation_assets_path(_directory), {"water": water})
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


func test_advance_paces_commands_by_elapsed_time_not_by_rendered_frames() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	# A frame shorter than one hardware frame runs no command at all, so a fast
	# display cannot make the sequence run faster than the cartridge does.
	assert_false(animation.advance(Gen2WorldAnimation.FRAME_SECONDS * 0.5))
	assert_eq(animation.current_indices()[0], 0)

	# The remainder carries over: two half frames are one whole one.
	assert_true(animation.advance(Gen2WorldAnimation.FRAME_SECONDS * 0.5))
	assert_eq(animation.current_indices()[0], 1)


func test_advance_reports_no_redraw_when_the_command_changes_nothing() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	assert_true(animation.advance(Gen2WorldAnimation.FRAME_SECONDS))
	# "done" only rewinds the command index, so nothing new is drawn and the
	# renderer must not rebuild its atlas for it.
	assert_false(animation.advance(Gen2WorldAnimation.FRAME_SECONDS))
	# The water command runs again, but writes the frame that is already there.
	assert_false(animation.advance(Gen2WorldAnimation.FRAME_SECONDS))


func test_advance_drops_frames_after_a_stall_instead_of_running_the_backlog() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	# Ten seconds of stall is close to 600 hardware frames. Only the capped
	# catch-up runs, so recovery costs a bounded amount of work.
	animation.advance(10.0)
	assert_lt(animation.command_index(), Gen2WorldAnimation.MAX_CATCHUP_FRAMES + 1)
