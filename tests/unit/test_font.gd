extends GutTest

## Glyph blitting, against a cache this test writes itself.
##
## The font in the cache is three tiles standing in for codes $80 to $82, each
## solid ink, so where a glyph lands is visible as a block of index 3 and a code
## drawn in the wrong place cannot look right by accident.

const SHEET_TILES: int = 3
const WIDTH: int = SHEET_TILES * Gen2Font.TILE

var _directory: String = ""
var _font: Gen2Font = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"fontgame", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()
	_font = Gen2Font.from_data(GameData.open_directory(_directory))


func after_each() -> void:
	RomCache.clear(_directory)


## Three solid glyphs and one frame of six solid border tiles.
func _write_cache() -> void:
	var glyphs: PackedByteArray = PackedByteArray()
	glyphs.resize(WIDTH * Gen2Font.TILE)
	glyphs.fill(Gen2Tiles.INK)
	RomCache.write_indices(RomCache.tile_path(_directory, "font"), glyphs)

	var frames: PackedByteArray = PackedByteArray()
	frames.resize(RomLayout.FRAME_TILES * Gen2Font.TILE * Gen2Font.TILE)
	frames.fill(Gen2Tiles.INK)
	RomCache.write_indices(RomCache.tile_path(_directory, "frames"), frames)

	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "fontgame",
		"sha1": "0123456789abcdef",
		"complete": true,
		"tiles": {
			"font": {
				"width": WIDTH, "height": Gen2Font.TILE,
				"tiles": SHEET_TILES, "first_code": RomLayout.FONT_FIRST_CODE,
			},
			"frames": {
				"width": RomLayout.FRAME_TILES * Gen2Font.TILE, "height": Gen2Font.TILE,
				"tiles": RomLayout.FRAME_TILES, "first_code": RomLayout.FRAME_FIRST_CODE,
			},
		},
	})


func _canvas(tiles: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(tiles * Gen2Font.TILE * Gen2Font.TILE)
	return out


func test_a_cache_with_a_font_gives_one() -> void:
	assert_not_null(_font)
	assert_true(_font.is_usable())


func test_a_cache_without_one_does_not() -> void:
	# An older cache, or an import that stopped before the font.
	assert_null(Gen2Font.from_data(null))


func test_a_code_lands_at_the_position_it_is_given() -> void:
	var into: PackedByteArray = _canvas(2)
	_font.draw_code(RomLayout.FONT_FIRST_CODE, into, 2 * Gen2Font.TILE, Gen2Font.TILE, 0)
	assert_eq(into[0], 0, "nothing before it")
	assert_eq(into[Gen2Font.TILE], Gen2Tiles.INK, "and ink from the eighth pixel on")


func test_a_code_below_the_sheet_draws_nothing() -> void:
	# The space at $7F is exactly this case, and the hardware agrees.
	var into: PackedByteArray = _canvas(1)
	_font.draw_code(Gen2Text.SPACE, into, Gen2Font.TILE, 0, 0)
	assert_eq(into.count(0), into.size())


func test_a_code_past_the_end_of_the_sheet_draws_nothing() -> void:
	var into: PackedByteArray = _canvas(1)
	_font.draw_code(RomLayout.FONT_FIRST_CODE + SHEET_TILES, into, Gen2Font.TILE, 0, 0)
	assert_eq(into.count(0), into.size())


func test_text_advances_one_tile_per_glyph() -> void:
	var into: PackedByteArray = _canvas(3)
	var drawn: int = _font.draw_text("AB", into, 3 * Gen2Font.TILE, 0, 0)
	assert_eq(drawn, 2)
	assert_eq(into[0], Gen2Tiles.INK)
	assert_eq(into[Gen2Font.TILE], Gen2Tiles.INK)
	assert_eq(into[Gen2Font.TILE * 2], 0, "and stops after the second")


func test_text_reports_tiles_drawn_not_characters() -> void:
	# "AB" is in the sheet; the ligature would be one tile if it were.
	var into: PackedByteArray = _canvas(4)
	assert_eq(_font.draw_text("A B", into, 4 * Gen2Font.TILE, 0, 0), 3)


func test_drawing_off_the_edge_clips_instead_of_failing() -> void:
	# A box that runs off the screen should look wrong at the edge and be right
	# everywhere else.
	var into: PackedByteArray = _canvas(1)
	_font.draw_code(RomLayout.FONT_FIRST_CODE, into, Gen2Font.TILE, Gen2Font.TILE - 2, 0)
	assert_eq(into[Gen2Font.TILE - 1], Gen2Tiles.INK)
	assert_eq(into[0], 0)


func test_negative_positions_clip_too() -> void:
	var into: PackedByteArray = _canvas(1)
	_font.draw_code(RomLayout.FONT_FIRST_CODE, into, Gen2Font.TILE, -Gen2Font.TILE, 0)
	assert_eq(into.count(0), into.size())


func test_a_border_is_addressed_by_its_box_drawing_code() -> void:
	# The frame tiles are loaded at $79 so the charmap's ┌ ─ ┐ │ └ ┘ name them
	# directly; a border is printed as characters like anything else.
	var into: PackedByteArray = _canvas(1)
	_font.draw_frame_code(0, RomLayout.FRAME_FIRST_CODE, into, Gen2Font.TILE, 0, 0)
	assert_eq(into[0], Gen2Tiles.INK)


func test_a_code_outside_the_box_drawing_run_draws_no_border() -> void:
	var into: PackedByteArray = _canvas(1)
	_font.draw_frame_code(
		0, RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TILES, into, Gen2Font.TILE, 0, 0
	)
	assert_eq(into.count(0), into.size())


func test_a_frame_that_was_never_cached_draws_nothing() -> void:
	var into: PackedByteArray = _canvas(1)
	_font.draw_frame_code(7, RomLayout.FRAME_FIRST_CODE, into, Gen2Font.TILE, 0, 0)
	assert_eq(into.count(0), into.size())
	assert_eq(_font.frame_count(), 1, "this cache holds one")
