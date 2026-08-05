extends GutTest

## The cache-facing world records are deliberately node-free, so their geometry
## and collision conventions can be checked without opening a scene or a ROM.


func test_map_uses_row_major_blocks_and_collision_cells() -> void:
	var map := Gen2WorldMap.from_cache({
		"group": 2,
		"number": 3,
		"width_blocks": 2,
		"height_blocks": 1,
		"blocks": [4, 5],
		"collision_width": 4,
		"collision_height": 2,
		"collision": [10, 11, 12, 13, 14, 15, 16, 17],
	})

	assert_eq(map.block_at(0, 0), 4)
	assert_eq(map.block_at(1, 0), 5)
	assert_eq(map.block_at(2, 0), 0)
	assert_eq(map.collision_at(0, 0), 10)
	assert_eq(map.collision_at(3, 1), 17)
	assert_eq(map.collision_at(4, 0), -1)


func test_map_reads_directional_connections_and_signed_offsets() -> void:
	var map := Gen2WorldMap.from_cache({
		"group": 1,
		"number": 1,
		"width_blocks": 4,
		"height_blocks": 3,
		"connection_flags": RomLayout.MAP_CONNECTION_FLAG_NORTH,
		"connections": [{
			"direction": "north", "map_group": 2, "map_number": 4,
			"length": 5, "target_width_blocks": 8,
			"x_offset": -10, "y_offset": 11,
		}],
	})

	assert_eq(map.connection_flags, RomLayout.MAP_CONNECTION_FLAG_NORTH)
	assert_eq(map.connections.size(), 1)
	assert_eq(map.connections[0]["direction"], "north")
	assert_eq(map.connections[0]["map_group"], 2)
	assert_eq(map.connections[0]["x_offset"], -10)
	assert_eq(map.connections[0]["y_offset"], 11)


func test_tileset_expands_four_by_four_tiles_and_two_by_two_collision() -> void:
	var meta: Array = []
	for value: int in 32:
		meta.append(value)
	var collision: Array = [0, 0, 0, 0, 20, 21, 22, 23]
	var tileset := Gen2WorldTileset.from_cache({
		"number": 7,
		"block_count": 2,
		"meta": meta,
		"collision": collision,
	})

	assert_eq(tileset.tile_index(0, 0), 0)
	assert_eq(tileset.tile_index(1, 15), 31)
	assert_eq(tileset.collision_index(0, 0, 0), -1)
	assert_eq(tileset.collision_index(1, 0, 0), 20)
	assert_eq(tileset.collision_index(1, 1, 1), 23)


func test_tileset_palette_map_reads_low_nibble_first() -> void:
	var tileset := Gen2WorldTileset.from_cache({
		"number": 2,
		"block_count": 1,
		"tile_count": 6,
		"palette_map": [0x21, 0x43, 0x65],
	})

	assert_eq(tileset.palette_index(0), 1)
	assert_eq(tileset.palette_index(1), 2)
	assert_eq(tileset.palette_index(2), 3)
	assert_eq(tileset.palette_index(3), 4)
	assert_eq(tileset.palette_index(4), 5)
	assert_eq(tileset.palette_index(5), 6)


func test_world_palette_environment_rows_match_the_cartridge_table() -> void:
	assert_eq(
		Gen2WorldPalette.palette_slots(Gen2WorldMap.new().environment, Gen2WorldPalette.TIME_MORNING),
		[0, 1, 2, 40, 4, 5, 6, 7],
	)
	assert_eq(
		Gen2WorldPalette.palette_slots(3, Gen2WorldPalette.TIME_NIGHT),
		[16, 17, 18, 19, 20, 21, 22, 7],
	)
	assert_eq(
		Gen2WorldPalette.palette_slots(7, Gen2WorldPalette.TIME_DARK),
		[24, 25, 26, 27, 28, 29, 30, 31],
	)


func test_layout_carries_verified_world_table_shapes() -> void:
	var gold: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	var crystal: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	assert_eq(RomLayout.map_count(gold), 368)
	assert_eq(RomLayout.map_count(crystal), 388)
	assert_eq(RomLayout.tileset_count(gold), 29)
	assert_eq(RomLayout.tileset_count(crystal), 37)
	assert_eq(RomLayout.tileset_block_count(gold, 4), 64)
	assert_eq(RomLayout.tileset_block_count(crystal, 31), 40)
	assert_eq(RomLayout.overworld_sprite_count(gold), 95)
	assert_eq(RomLayout.overworld_sprite_count(crystal), 99)
	assert_eq(RomLayout.overworld_sprite_offset(gold, 1), 0x147DE)
	assert_eq(RomLayout.overworld_sprite_offset(crystal, 1), 0x14736)
