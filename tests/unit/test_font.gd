extends GutTest

## Glyph blitting, against a cache this test writes itself.
##
## The font in the cache is three tiles standing in for codes $80 to $82, each
## solid ink, so where a glyph lands is visible as a block of index 3 and a code
## drawn in the wrong place cannot look right by accident.

const SHEET_TILES: int = 3
const WIDTH: int = SHEET_TILES * Gen2Font.TILE

const BATTLE_EXTRA_WIDTH: int = RomLayout.BATTLE_FONT_TILES * Gen2Font.TILE
const FONT_EXTRA_WIDTH: int = RomLayout.FONT_EXTRA_TILES * Gen2Font.TILE
## Not [constant Gen2Tiles.INK], so a pixel says which strip it came from.
const BATTLE_EXTRA_INK: int = 2
const FONT_EXTRA_INK: int = 1

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

	# The battle-extra strip, filled with a different index so a glyph taken
	# from it cannot be mistaken for one taken from the main font.
	var battle_extra: PackedByteArray = PackedByteArray()
	battle_extra.resize(BATTLE_EXTRA_WIDTH * Gen2Font.TILE)
	battle_extra.fill(BATTLE_EXTRA_INK)
	RomCache.write_indices(RomCache.tile_path(_directory, "battle_font"), battle_extra)

	# FontExtra, which is under that same run whenever the battle strip is not.
	var extra: PackedByteArray = PackedByteArray()
	extra.resize(FONT_EXTRA_WIDTH * Gen2Font.TILE)
	extra.fill(FONT_EXTRA_INK)
	RomCache.write_indices(RomCache.tile_path(_directory, "font_extra"), extra)

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
			"battle_font": {
				"width": BATTLE_EXTRA_WIDTH, "height": Gen2Font.TILE,
				"tiles": RomLayout.BATTLE_FONT_TILES, "first_code": 0,
			},
			"font_extra": {
				"width": FONT_EXTRA_WIDTH, "height": Gen2Font.TILE,
				"tiles": RomLayout.FONT_EXTRA_TILES,
				"first_code": RomLayout.FONT_EXTRA_FIRST_CODE,
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


## _LoadFontsBattleExtra replaces $60 to $78 and leaves the rest of video memory
## alone, so which sheet a code addresses depends on the strip and the run.

func test_a_battle_extra_code_is_drawn_from_that_strip() -> void:
	var into: PackedByteArray = _canvas(1)
	# $74 is № there, at tile $74 - $60 within the sheet.
	_font.draw_code(0x74, into, Gen2Font.TILE, 0, 0, Gen2Text.FONT_BATTLE_EXTRA)
	assert_eq(into[0], BATTLE_EXTRA_INK)


func test_the_same_code_is_font_extras_with_the_main_font_loaded() -> void:
	# `_LoadFontsExtra1` is what stands in that run outside a battle, so $74 is
	# № under one strip and the middle dot under the other.
	var into: PackedByteArray = _canvas(1)
	_font.draw_code(0x74, into, Gen2Font.TILE, 0, 0)
	assert_eq(into[0], FONT_EXTRA_INK)


## The three codes below `_LoadFontsExtra1`'s own `vTiles2 tile '<BOLD_D>'` are
## overwritten by black, the up arrow and the phone icon, so FontExtra's first
## three tiles never reach the screen through this path.
func test_the_run_below_bold_d_is_not_drawn_from_font_extra() -> void:
	var into: PackedByteArray = _canvas(1)
	_font.draw_code(RomLayout.FONT_EXTRA_LOADED_FIRST - 1, into, Gen2Font.TILE, 0, 0)
	assert_eq(into[0], 0)


func test_a_cache_without_font_extra_draws_that_run_blank() -> void:
	var manifest: Dictionary = RomCache.read_manifest(_directory)
	(manifest["tiles"] as Dictionary).erase("font_extra")
	RomCache.write_json(RomCache.manifest_path(_directory), manifest)

	var font: Gen2Font = Gen2Font.from_data(GameData.open_directory(_directory))
	assert_not_null(font)
	var into: PackedByteArray = _canvas(1)
	font.draw_code(Gen2Text.ELLIPSIS_CODE, into, Gen2Font.TILE, 0, 0)
	assert_eq(into[0], 0)


func test_letters_still_come_from_the_main_font_under_the_battle_strip() -> void:
	var into: PackedByteArray = _canvas(1)
	_font.draw_code(
		RomLayout.FONT_FIRST_CODE, into, Gen2Font.TILE, 0, 0, Gen2Text.FONT_BATTLE_EXTRA
	)
	assert_eq(into[0], Gen2Tiles.INK, "$80 is outside the run that load replaces")


func test_a_cache_without_the_battle_strip_refuses_that_run_rather_than_guessing() -> void:
	# A cache written before anything read this strip: the main font still works
	# and the other run draws nothing, rather than reaching into the wrong sheet.
	var manifest: Dictionary = RomCache.read_manifest(_directory)
	(manifest["tiles"] as Dictionary).erase("battle_font")
	RomCache.write_json(RomCache.manifest_path(_directory), manifest)

	var font: Gen2Font = Gen2Font.from_data(GameData.open_directory(_directory))
	assert_not_null(font)
	assert_false(font.has_battle_extra())
	var into: PackedByteArray = _canvas(1)
	font.draw_code(0x74, into, Gen2Font.TILE, 0, 0, Gen2Text.FONT_BATTLE_EXTRA)
	assert_eq(into[0], 0)
	# And the letters it does have still draw.
	font.draw_code(RomLayout.FONT_FIRST_CODE, into, Gen2Font.TILE, 0, 0)
	assert_eq(into[0], Gen2Tiles.INK)
