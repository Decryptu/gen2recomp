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


## `.PlaceString_MonsNest`: the top row is blanked whole and the header written
## from column 2, with the bar one row down and nothing else over the map.
func test_the_dex_area_header_replaces_the_name_box() -> void:
	var header: PackedByteArray = Gen2Text.encode("RATTATA")
	header.append_array(Gen2Text.encode(Gen2TownMapScreen.NEST_HEADER_SUFFIX))
	var map: PackedInt32Array = _page.tilemap(
		_data.town_map_region("johto"), header, Gen2TownMap.SCREEN_DEX_AREA
	)
	assert_eq(_at(map, Vector2i(0, 0)), Gen2TownMapPage.BLANK_TILE)
	assert_eq(_at(map, Vector2i(1, 0)), Gen2TownMapPage.BLANK_TILE)
	assert_eq(_at(map, Vector2i(2, 0)), Gen2Text.encode("R")[0])
	assert_eq(_at(map, Vector2i(9, 0)), Gen2Text.encode("'")[0], "'S NEST follows the name")
	assert_eq(_at(map, Vector2i(19, 0)), Gen2TownMapPage.BLANK_TILE)
	assert_eq(_at(map, Vector2i(0, 1)), Gen2TownMapPage.TOWN_MAP_FRAME_LEFT_TILE)
	assert_eq(_at(map, Vector2i(10, 1)), Gen2TownMapPage.TOWN_MAP_FRAME_TOP_TILE)
	assert_eq(_at(map, Vector2i(19, 1)), Gen2TownMapPage.TOWN_MAP_FRAME_RIGHT_TILE)
	assert_eq(_at(map, Vector2i(0, 2)), Fixture.TOWN_MAP_JOHTO_TILE)


## `Textbox`'s own border codes, which every card draws under itself and which
## `compose` resolves through the chosen frame rather than through the font.
func test_every_card_draws_the_source_text_box() -> void:
	assert_true(_page.cards_ready())
	for map: PackedInt32Array in [
		_page.clock_tilemap([], 0, 0, 0, ""),
		_page.radio_tilemap([], ""),
		_page.phone_tilemap([], [], 0, true, ""),
	]:
		assert_eq(
			_at(map, Gen2TownMapPage.CARD_TEXTBOX_AT),
			RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TOP_LEFT
		)
		assert_eq(
			_at(map, Vector2i(19, 17)),
			RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_BOTTOM_RIGHT
		)
		assert_eq(_at(map, Vector2i(1, 13)), Gen2TownMapPage.BLANK_TILE)


## `Pokegear_FinishTilemap` runs after every card's own jumptable entry, so the
## icon row is on all four screens rather than on the MAP card alone.
func test_a_card_carries_the_icon_row() -> void:
	var map: PackedInt32Array = _page.clock_tilemap([&"map", &"radio"], 0, 0, 0, "")
	assert_eq(
		_at(map, Gen2TownMapPage.CARD_POKEGEAR_ICON_AT),
		Gen2TownMapPage.CARD_POKEGEAR_ICON_TILE
	)
	assert_eq(_at(map, Vector2i(2, 0)), 0x40)
	assert_eq(_at(map, Vector2i(6, 0)), 0x42)
	## The PHONE card is not owned here, so its two cells keep the blank
	## `Pokegear_FinishTilemap` filled them with.
	assert_eq(_at(map, Vector2i(4, 0)), Gen2TownMapPage.CARD_BLANK_TILE)


## `PrintHoursMins`: twelve-hour, the hour space-padded and the minute not, and
## both midnight and noon printed as twelve.
func test_the_clock_card_prints_the_source_reading() -> void:
	assert_eq(Gen2TownMapPage._clock_reading(0, 7), "12:07 AM")
	assert_eq(Gen2TownMapPage._clock_reading(12, 0), "12:00 PM")
	assert_eq(Gen2TownMapPage._clock_reading(9, 30), " 9:30 AM")
	assert_eq(Gen2TownMapPage._clock_reading(23, 59), "11:59 PM")
	var map: PackedInt32Array = _page.clock_tilemap([], 3, 13, 5, "")
	assert_eq(_text(map, Gen2TownMapPage.CLOCK_DAY_AT, 9), "WEDNESDAY")
	assert_eq(_text(map, Gen2TownMapPage.CLOCK_TIME_AT, 8), " 1:05 PM")
	assert_eq(_text(map, Gen2TownMapPage.CLOCK_SWITCH_AT, 8), " SWITCH▶")


## `UpdateRadioStation` places a station's name and `NoRadioStation` places
## nothing, which is a dial between two channels.
func test_the_radio_card_prints_only_a_tuned_station() -> void:
	assert_eq(
		_text(_page.radio_tilemap([], "LUCKY CHANNEL"), Gen2TownMapPage.RADIO_STATION_AT, 13),
		"LUCKY CHANNEL"
	)
	## The card's own art is left where a name would go, which in the fixture is
	## its flat fill.
	assert_eq(
		_at(_page.radio_tilemap([], ""), Gen2TownMapPage.RADIO_STATION_AT),
		Gen2TownMapPage.CARD_BLANK_TILE
	)


## `GetCallerName`: a trainer's own name with a colon and their class on the line
## below, everyone else on one line, and `.PlacePhoneBars`' fourth tile only
## where there is service.
func test_the_phone_card_lists_callers_the_source_way() -> void:
	var rows: Array = [
		{"name": "MOM:"}, {"name": "JACK", "class": "SCHOOLBOY"},
	]
	var map: PackedInt32Array = _page.phone_tilemap([], rows, 1, true, "")
	assert_eq(_text(map, Vector2i(Gen2TownMapPage.PHONE_NAME_COLUMN, 4), 4), "MOM:")
	assert_eq(_text(map, Vector2i(Gen2TownMapPage.PHONE_NAME_COLUMN, 6), 5), "JACK:")
	assert_eq(_text(map, Vector2i(Gen2TownMapPage.PHONE_CLASS_COLUMN, 7), 9), "SCHOOLBOY")
	assert_eq(
		_at(map, Vector2i(Gen2TownMapPage.PHONE_CURSOR_COLUMN, 6)),
		Gen2TownMapPage.PHONE_CURSOR_CODE
	)
	assert_eq(_at(map, Gen2TownMapPage.PHONE_SERVICE_AT), Gen2TownMapPage.PHONE_SERVICE_TILE)
	assert_eq(
		_at(_page.phone_tilemap([], rows, 0, false, ""), Gen2TownMapPage.PHONE_SERVICE_AT),
		Gen2TownMapPage.CARD_BLANK_TILE
	)


## `PokegearPhoneContactSubmenu`: the cursor in the strings' own column, the
## text one tile right of it, and a two-option box opening two rows lower than a
## three-option one so both end on the same row.
func test_the_phone_submenu_sits_where_its_strings_do() -> void:
	var map: PackedInt32Array = _page.phone_tilemap([], [], 0, true, "")
	_page.draw_phone_submenu(map, ["CALL", "DELETE", "CANCEL"], 1)
	assert_eq(_text(map, Vector2i(11, 6), 4), "CALL")
	assert_eq(_text(map, Vector2i(11, 8), 6), "DELETE")
	assert_eq(_text(map, Vector2i(11, 10), 6), "CANCEL")
	assert_eq(
		_at(map, Vector2i(Gen2TownMapPage.PHONE_SUBMENU_CURSOR_COLUMN, 8)),
		Gen2TownMapPage.PHONE_CURSOR_CODE
	)
	var short_map: PackedInt32Array = _page.phone_tilemap([], [], 0, true, "")
	_page.draw_phone_submenu(short_map, ["CALL", "CANCEL"], 0)
	assert_eq(_text(short_map, Vector2i(11, 8), 4), "CALL")
	assert_eq(_text(short_map, Vector2i(11, 10), 6), "CANCEL")


## `YesNoBox`'s `lb bc, SCREEN_WIDTH - 6, 7`, which DELETE opens over the card.
func test_the_yes_no_box_is_at_the_source_corner() -> void:
	var map: PackedInt32Array = _page.phone_tilemap([], [], 0, true, "")
	_page.draw_yes_no(map, 1)
	assert_eq(
		_at(map, Vector2i(Gen2TownMapPage.YES_NO_BOX[0], Gen2TownMapPage.YES_NO_BOX[1])),
		RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TOP_LEFT
	)
	assert_eq(_text(map, Vector2i(16, 8), 3), "YES")
	assert_eq(_text(map, Vector2i(16, 10), 2), "NO")
	assert_eq(_at(map, Vector2i(15, 10)), Gen2TownMapPage.PHONE_CURSOR_CODE)


## A run of the tile map read back as text, which is what the page printed.
func _text(map: PackedInt32Array, at: Vector2i, length: int) -> String:
	var out: String = ""
	for column: int in length:
		out += Gen2Text.character(_at(map, at + Vector2i(column, 0)))
	return out
