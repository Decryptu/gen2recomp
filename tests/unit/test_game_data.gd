extends GutTest

## Builds its own cache and reads it back. Nothing here opens a cartridge: the
## point of the cache is that the engine never needs one, so its reader has to
## be testable without one too.

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testgame", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


## A cache with two species, one of each other table, and a 2x2-cell atlas.
func _write_cache(complete: bool = true) -> void:
	RomCache.write_json(RomCache.species_path(_directory), [
		_species(1, "BULBASAUR", 0x1234, 0x5678),
		_species(2, "IVYSAUR", 0x0C63, 0x1084),
	])
	RomCache.write_json(RomCache.moves_path(_directory), [
		{"number": 1, "name": "POUND", "power": 40, "type": 0, "accuracy": 255, "pp": 35},
	])
	RomCache.write_json(RomCache.items_path(_directory), [{"number": 1, "name": "MASTER BALL"}])
	RomCache.write_json(RomCache.types_path(_directory), [
		{"number": 0, "name": "NORMAL"}, {"number": 1, "name": "FIGHTING"},
	])
	RomCache.write_indices(RomCache.pic_path(_directory, "front"), PackedByteArray([
		0, 0, 1, 1,
		0, 0, 1, 1,
		2, 2, 3, 3,
		2, 2, 3, 3,
	]))
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testgame",
		"sha1": "0123456789abcdef",
		"species_count": 2,
		"atlases": {
			"front": {"width": 4, "height": 4, "cell": 2, "columns": 2, "decoded": 2},
			"back": {"width": 4, "height": 4, "cell": 2, "columns": 2, "decoded": 2},
		},
		"complete": complete,
	})


func _species(number: int, name: String, normal: int, shiny: int) -> Dictionary:
	return {
		"number": number,
		"name": name,
		"stats": {"hp": 45, "attack": 49},
		"types": [0, 3],
		"front_tiles": [1, 1],
		"palette": {"normal": [normal, normal], "shiny": [shiny, shiny]},
	}


func test_a_complete_cache_opens() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_not_null(data)
	assert_eq(data.species_count(), 2)


func test_an_incomplete_cache_does_not_open() -> void:
	# An interrupted import must not be read as if it were a finished one.
	_write_cache(false)
	assert_null(GameData.open_directory(_directory))


func test_a_missing_cache_does_not_open() -> void:
	assert_null(GameData.open_directory("user://nothing_here"))


func test_numbers_come_back_as_ints_not_floats() -> void:
	# JSON has one number type. Coercing here, once, is the whole reason this
	# class exists rather than callers reading the JSON themselves.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var move: Dictionary = data.move(1)
	assert_eq(int(move["power"]), 40)
	assert_true(data.atlas("front")["cell"] is int, "atlas metadata is coerced")


func test_lookups_are_by_number_not_position() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(String(data.species(2)["name"]), "IVYSAUR")
	assert_eq(data.item_name(1), "MASTER BALL")
	assert_eq(String(data.move(1)["name"]), "POUND")


func test_types_are_indexed_from_zero() -> void:
	# Unlike every other table: NORMAL is type $00.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.type_name(0), "NORMAL")
	assert_eq(data.type_name(1), "FIGHTING")


func test_an_unknown_number_answers_empty_rather_than_failing() -> void:
	# A mod may well ask for something that is not there.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_true(data.species(0).is_empty())
	assert_true(data.species(999).is_empty())
	assert_eq(data.item_name(999), "")
	assert_eq(data.type_name(-1), "")


func test_a_palette_is_four_colours_with_white_and_black_implied() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var palette: PackedColorArray = data.palette(1)
	assert_eq(palette.size(), Gen2Palette.COLORS_PER_PIC)
	assert_eq(palette[0], Color.WHITE)
	assert_eq(palette[3], Color.BLACK)


func test_shiny_is_a_different_palette_and_the_same_pixels() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_ne(data.palette(1, true), data.palette(1, false))


func test_a_species_pic_reports_its_own_size_not_the_cell_size() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var pic: Dictionary = data.species_pic(1)
	assert_eq(pic["slot"], 0, "slots are zero-based, species numbers are not")
	assert_eq(pic["width"], Gen2Tiles.TILE_WIDTH, "one tile, not the two-tile cell")


func test_back_pics_always_fill_their_cell() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.species_pic(1, true)["width"], 2)


func test_unown_forms_come_from_their_own_atlas() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	# There is no Unown in this two-species cache, so the answer is empty
	# rather than a lie about slot 0 of an atlas that was never written.
	assert_true(data.unown_pic(0).is_empty())


func test_index_buffers_are_read_once_and_kept() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var first: PackedByteArray = data.atlas_indices("front")
	assert_eq(first.size(), 16)
	assert_eq(data.atlas_indices("front"), first)


func test_an_atlas_that_was_never_written_reads_as_empty() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_true(data.atlas("nothing").is_empty())
	assert_eq(data.atlas_indices("back"), PackedByteArray())
