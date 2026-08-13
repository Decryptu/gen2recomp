extends GutTest

## The copyright screen's layout (`Copyright`, engine/menus/intro_menu.asm),
## checked as where each tile lands: the fixture's strip is a flat fill, so the
## picture says nothing and the placement is the whole content.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _page: Gen2CopyrightPage = null


func before_each() -> void:
	_data = Fixture.build()
	_page = Gen2CopyrightPage.from_data(_data)


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _index(indices: PackedByteArray, at: Vector2i) -> int:
	return indices[at.y * Gen2Screen.WIDTH + at.x]


func test_the_page_is_the_hardware_screen() -> void:
	assert_not_null(_page)
	assert_eq(_page.draw().size(), Gen2Screen.WIDTH * Gen2Screen.HEIGHT)


## `hlcoord 2, 7`, and `NextLineChar`'s own `ld bc, SCREEN_WIDTH * 2`: three rows
## in the same column, two rows apart.
func test_the_three_rows_start_in_one_column_two_rows_apart() -> void:
	var indices: PackedByteArray = _page.draw()
	var at: Vector2i = RomLayout.COPYRIGHT_AT * Gen2Font.TILE
	for row: int in RomLayout.COPYRIGHT_STRING_ROWS:
		var top: Vector2i = at + Vector2i(0, row * Gen2CopyrightPage.ROW_STRIDE * Gen2Font.TILE)
		assert_eq(_index(indices, top), 3, "row %d is drawn" % row)
		assert_eq(
			_index(indices, top - Vector2i(1, 0)), Gen2CopyrightPage.BLANK_INDEX,
			"and nothing is drawn left of it"
		)
	var between: Vector2i = at + Vector2i(0, Gen2Font.TILE)
	assert_eq(
		_index(indices, between), Gen2CopyrightPage.BLANK_INDEX,
		"the row between two of them is blank"
	)


func test_only_the_strings_own_columns_are_drawn() -> void:
	var indices: PackedByteArray = _page.draw()
	var at: Vector2i = RomLayout.COPYRIGHT_AT * Gen2Font.TILE
	var last: Vector2i = at + Vector2i((Fixture.COPYRIGHT_TILES - 1) * Gen2Font.TILE, 0)
	assert_eq(_index(indices, last), 3)
	assert_eq(
		_index(indices, last + Vector2i(Gen2Font.TILE, 0)), Gen2CopyrightPage.BLANK_INDEX
	)


## The screen is white on black: PREDEFPAL_GAMEFREAK_LOGO_BG's first colour is
## black, and `ClearTilemap` leaves index 0 everywhere the string is not.
func test_the_blank_screen_is_the_palettes_first_colour() -> void:
	assert_eq(_page.palette.size(), RomLayout.COPYRIGHT_PALETTE_COLORS)
	assert_eq(_page.palette[0], Color.BLACK)
	assert_eq(_page.palette[RomLayout.COPYRIGHT_PALETTE_COLORS - 1], Color.WHITE)
	assert_eq(_index(_page.draw(), Vector2i.ZERO), Gen2CopyrightPage.BLANK_INDEX)


## The codes are the strip's own tile numbers, so a page built from a cache with
## no copyright screen is null rather than a screen of blanks.
func test_a_cache_without_the_screen_builds_no_page() -> void:
	assert_null(Gen2CopyrightPage.from_data(null))
