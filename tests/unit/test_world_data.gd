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


func test_layout_carries_verified_world_table_shapes() -> void:
	var gold: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	var crystal: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	assert_eq(RomLayout.map_count(gold), 368)
	assert_eq(RomLayout.map_count(crystal), 388)
	assert_eq(RomLayout.tileset_count(gold), 29)
	assert_eq(RomLayout.tileset_count(crystal), 37)
	assert_eq(RomLayout.tileset_block_count(gold, 4), 64)
	assert_eq(RomLayout.tileset_block_count(crystal, 31), 40)
