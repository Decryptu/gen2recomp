extends GutTest

## The cache holds cartridge-derived data, so these tests build their own and
## clean it up. Nothing here reads a ROM.

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testgame", "0123456789abcdef")
	RomCache.clear(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


func test_the_cache_lives_under_user_not_in_the_project() -> void:
	# It is derived from a commercial cartridge: it must never be committable
	# or sweepable into an export.
	assert_true(RomCache.ROOT.begins_with("user://"))


func test_a_directory_is_named_by_game_and_hash() -> void:
	# Two revisions of the same game must not share one.
	var gold: String = RomCache.directory_for(RomRegistry.GOLD, "aaaaaaaabbbb")
	var other: String = RomCache.directory_for(RomRegistry.GOLD, "ccccccccdddd")
	assert_ne(gold, other)
	assert_true(gold.contains("gold"))


func test_each_table_gets_its_own_file() -> void:
	var paths: Array = [
		RomCache.species_path(_directory),
		RomCache.moves_path(_directory),
		RomCache.items_path(_directory),
		RomCache.types_path(_directory),
		RomCache.manifest_path(_directory),
	]
	for path: String in paths:
		assert_eq(paths.count(path), 1, "%s is not unique" % path)
		assert_true(path.begins_with(_directory))


func test_prepare_creates_the_tree() -> void:
	assert_true(RomCache.prepare(_directory))
	assert_true(DirAccess.dir_exists_absolute("%s/%s" % [_directory, RomCache.PICS_DIR]))
	assert_true(DirAccess.dir_exists_absolute("%s/%s" % [_directory, RomCache.TILES_DIR]))


func test_tile_sheets_and_pics_of_the_same_name_do_not_collide() -> void:
	assert_ne(RomCache.tile_path(_directory, "front"), RomCache.pic_path(_directory, "front"))


func test_json_round_trips() -> void:
	RomCache.prepare(_directory)
	var value: Dictionary = {"name": "BULBASAUR", "types": ["GRASS", "POISON"]}
	assert_true(RomCache.write_json(RomCache.species_path(_directory), value))
	assert_eq(RomCache.read_json(RomCache.species_path(_directory)), value)


func test_numbers_come_back_from_json_as_floats() -> void:
	# JSON has one number type, so every stat, index and byte read back out of
	# the cache is a float. Callers must coerce; asserting it here so nobody
	# rediscovers it by comparing a species number against an int and losing.
	RomCache.prepare(_directory)
	var path: String = RomCache.species_path(_directory)
	RomCache.write_json(path, {"number": 1})

	var read: Dictionary = RomCache.read_json(path)
	assert_true(read["number"] is float)
	assert_eq(int(read["number"]), 1)


func test_reading_a_missing_file_returns_null() -> void:
	assert_null(RomCache.read_json("%s/nothing.json" % _directory))


func test_index_buffers_round_trip_exactly() -> void:
	RomCache.prepare(_directory)
	var pixels: PackedByteArray = PackedByteArray()
	for i: int in 4096:
		pixels.append(i % 4)

	var path: String = RomCache.pic_path(_directory, "front")
	assert_true(RomCache.write_indices(path, pixels))
	assert_eq(RomCache.read_indices(path), pixels)


func test_reading_missing_index_data_yields_an_empty_buffer() -> void:
	assert_eq(RomCache.read_indices("%s/absent.idx" % _directory), PackedByteArray())


func test_a_cache_without_a_manifest_is_not_usable() -> void:
	RomCache.prepare(_directory)
	assert_false(RomCache.is_usable(_directory))


func test_an_incomplete_cache_is_not_usable() -> void:
	# An interrupted import must not be mistaken for a finished one.
	RomCache.prepare(_directory)
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION, "complete": false,
	})
	assert_false(RomCache.is_usable(_directory))


func test_a_cache_from_another_format_version_is_not_usable() -> void:
	RomCache.prepare(_directory)
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION - 1, "complete": true,
	})
	assert_false(RomCache.is_usable(_directory))


func test_a_complete_current_cache_is_usable() -> void:
	RomCache.prepare(_directory)
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION, "complete": true,
	})
	assert_true(RomCache.is_usable(_directory))


func test_clear_removes_subdirectories_too() -> void:
	RomCache.prepare(_directory)
	RomCache.write_indices(RomCache.pic_path(_directory, "front"), PackedByteArray([1, 2, 3]))
	RomCache.clear(_directory)
	assert_false(DirAccess.dir_exists_absolute(_directory))
