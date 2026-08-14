extends GutTest

## The region map's tile layout (`_TownMap.InitTilemap`,
## `InitPokegearTilemap.Map` and `Pokegear_FinishTilemap`), checked as the tile
## map rather than as pixels: the fixture's region maps are flat fills, so what a
## page is worth testing for is where each thing lands.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _page: Gen2TownMapPage = null


func before_each() -> void:
	_data = Fixture.build()
	_page = Gen2TownMapPage.from_data(_data)


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _at(map: PackedInt32Array, at: Vector2i) -> int:
	return map[at.y * Gen2TownMapPage.COLUMNS + at.x]


func _johto(
	screen: StringName = Gen2TownMap.SCREEN_TOWN_MAP, cards: Array = []
) -> PackedInt32Array:
	return _page.tilemap(
		_data.town_map_region("johto"),
		_data.landmark(1).get("codes", PackedByteArray()),
		screen,
		cards,
	)


func test_a_cache_with_the_pokegear_sheets_is_ready() -> void:
	assert_not_null(_page)
	assert_true(_page.ready())


func test_the_region_map_covers_the_whole_screen() -> void:
	var map: PackedInt32Array = _johto()
	assert_eq(map.size(), Gen2TownMapPage.COLUMNS * Gen2TownMapPage.ROWS)
	assert_eq(_at(map, Vector2i(0, 17)), Fixture.TOWN_MAP_JOHTO_TILE)
	assert_eq(_at(map, Vector2i(19, 17)), Fixture.TOWN_MAP_JOHTO_TILE)
	var kanto: PackedInt32Array = _page.tilemap(_data.town_map_region("kanto"), PackedByteArray())
	assert_eq(_at(kanto, Vector2i(0, 17)), Fixture.TOWN_MAP_KANTO_TILE)


## `_TownMap.InitTilemap`'s corner box: a lid over the top left, a wall down
## column 7 and a bar along row 2. Row 1 left of the wall is not written, so the
## region map shows through it.
func test_the_town_map_frame_is_the_source_corner_box() -> void:
	var map: PackedInt32Array = _johto()
	assert_eq(_at(map, Vector2i(0, 0)), Gen2TownMapPage.TOWN_MAP_FRAME_LEFT_TILE)
	assert_eq(_at(map, Vector2i(3, 0)), Gen2TownMapPage.TOWN_MAP_FRAME_TOP_TILE)
	assert_eq(_at(map, Vector2i(7, 0)), Gen2TownMapPage.TOWN_MAP_FRAME_RIGHT_TILE)
	assert_eq(_at(map, Vector2i(7, 1)), Gen2TownMapPage.TOWN_MAP_FRAME_WALL_TILE)
	assert_eq(_at(map, Vector2i(7, 2)), Gen2TownMapPage.TOWN_MAP_FRAME_JOINT_TILE)
	assert_eq(_at(map, Vector2i(3, 1)), Fixture.TOWN_MAP_JOHTO_TILE)
	assert_eq(_at(map, Vector2i(18, 2)), Gen2TownMapPage.TOWN_MAP_FRAME_TOP_TILE)
	assert_eq(_at(map, Vector2i(19, 2)), Gen2TownMapPage.TOWN_MAP_FRAME_RIGHT_TILE)


## `Pokegear_FinishTilemap`: the eight cells left of the name box are blanked and
## one 2x2 icon stamped per owned card, the Pokegear's own always.
func test_the_card_frame_draws_only_the_owned_cards() -> void:
	var map: PackedInt32Array = _johto(Gen2TownMap.SCREEN_POKEGEAR_CARD, [&"map", &"radio"])
	assert_eq(_at(map, Vector2i(0, 2)), Gen2TownMapPage.TOWN_MAP_FRAME_LEFT_TILE)
	assert_eq(_at(map, Vector2i(10, 2)), Gen2TownMapPage.TOWN_MAP_FRAME_TOP_TILE)
	assert_eq(_at(map, Vector2i(19, 2)), Gen2TownMapPage.TOWN_MAP_FRAME_RIGHT_TILE)

	assert_eq(_at(map, Vector2i(0, 0)), Gen2TownMapPage.CARD_POKEGEAR_ICON_TILE)
	assert_eq(_at(map, Vector2i(1, 0)), Gen2TownMapPage.CARD_POKEGEAR_ICON_TILE + 1)
	assert_eq(
		_at(map, Vector2i(0, 1)),
		Gen2TownMapPage.CARD_POKEGEAR_ICON_TILE + Gen2TownMapPage.CARD_ICON_ROW_STRIDE
	)
	assert_eq(_at(map, Vector2i(2, 0)), 0x40, "MAP")
	assert_eq(_at(map, Vector2i(6, 0)), 0x42, "RADIO")
	assert_eq(_at(map, Vector2i(4, 0)), Gen2TownMapPage.CARD_BLANK_TILE, "no PHONE card")


## `TownMap_ConvertLineBreakCharacters`: the name is placed at (9,0) and its one
## `<BSP>` drops a row at the string's own column.
func test_the_landmark_name_breaks_on_its_own_bsp() -> void:
	var map: PackedInt32Array = _johto()
	assert_eq(_at(map, Gen2TownMapPage.NAME_BOX_AT), Gen2TownMapPage.NAME_MARKER_TILE)
	assert_eq(_at(map, Vector2i(9, 0)), Gen2Text.encode("N")[0])
	assert_eq(_at(map, Vector2i(16, 0)), Gen2Text.encode("K")[0])
	assert_eq(_at(map, Vector2i(17, 0)), Gen2TownMapPage.BLANK_TILE)
	assert_eq(_at(map, Vector2i(9, 1)), Gen2Text.encode("T")[0])
	assert_eq(_at(map, Vector2i(12, 1)), Gen2Text.encode("N")[0])


func test_a_name_with_no_break_stays_on_one_row() -> void:
	var map: PackedInt32Array = _page.tilemap(
		_data.town_map_region("johto"), _data.landmark(2).get("codes", PackedByteArray())
	)
	assert_eq(_at(map, Vector2i(9, 0)), Gen2Text.encode("R")[0])
	assert_eq(_at(map, Vector2i(9, 1)), Gen2TownMapPage.BLANK_TILE)


## `TownMapPals`: the nybble table covers $00 to $5f and $60 and above take
## palette 0, which is what puts the printed name on the border's colours.
func test_attributes_follow_the_palette_map_and_stop_at_the_font() -> void:
	var map: PackedInt32Array = _johto()
	var slots: PackedInt32Array = _page.attributes(_data, map)
	assert_eq(_at(slots, Vector2i(0, 17)), Fixture.TOWN_MAP_EARTH)
	assert_eq(_at(slots, Vector2i(7, 0)), Fixture.TOWN_MAP_MOUNTAIN, "$17 is odd")
	assert_eq(_at(slots, Vector2i(9, 0)), 0, "a glyph is past the table")


func test_the_page_composes_the_hardware_screen() -> void:
	var image: Image = _page.image(_data, _johto())
	assert_eq(image.get_width(), Gen2Screen.WIDTH)
	assert_eq(image.get_height(), Gen2Screen.HEIGHT)


## Kris's own city colours, which only Crystal ships.
func test_the_female_palette_replaces_the_male_one() -> void:
	var map: PackedInt32Array = _johto()
	assert_ne(
		_page.image(_data, map, true).get_pixel(0, 143),
		_page.image(_data, map, false).get_pixel(0, 143)
	)
