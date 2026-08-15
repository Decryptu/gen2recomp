extends GutTest

## `Pack_InitGFX`'s screen and the two listings that share it
## (`ScrollingMenu_UpdateDisplay`, `TMHM_DisplayPocketItems`), checked by where
## each write lands rather than by eye.
##
## The fixture fills the menu sheet with one index and gives each of the four
## pocket pictures a different one, so which pocket is on screen can be read off
## the pixels. Everything else on the page is [Gen2Font]'s own drawing.

const DIRECTORY_ID: StringName = &"packpagetest"
const SHA: String = "0123456789abcdef"
## The index the menu sheet is filled with, distinct from every pocket's.
const SHEET_INDEX: int = 1
## The tilemap piece each pocket's name is, one solid tile number per pocket so
## the four are told apart without any art.
const NAME_TILES: Array[int] = [0x10, 0x11, 0x12, 0x13]

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(DIRECTORY_ID, SHA)
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func test_attributes_are_the_five_filled_boxes() -> void:
	var attributes: PackedInt32Array = Gen2PackPage.attributes()
	assert_eq(attributes[0], 1, "the header's left half")
	assert_eq(attributes[10], 2, "the header's right half")
	assert_eq(attributes[2 * Gen2PackPage.COLUMNS + 7], 3, "the cursor column")
	assert_eq(attributes[10 * Gen2PackPage.COLUMNS + 7], 3, "the cursor column's foot")
	assert_eq(attributes[7 * Gen2PackPage.COLUMNS], 4, "the pocket name")
	assert_eq(attributes[3 * Gen2PackPage.COLUMNS], 5, "the pack picture")
	assert_eq(attributes[17 * Gen2PackPage.COLUMNS + 19], 0, "the text box")


func test_the_screen_is_the_source_s_own_writes() -> void:
	var map: PackedInt32Array = _page().pocket_map(0, [], -1, "", _name_piece(0))
	for column: int in Gen2PackPage.COLUMNS:
		assert_eq(
			map[column], Gen2PackPage.HEADER_FIRST_TILE + column,
			"the header row ascends from $28"
		)
	assert_eq(map[Gen2PackPage.COLUMNS], Gen2PackPage.FIELD_TILE, "the field")
	assert_eq(
		map[Gen2PackPage.COLUMNS + 5], Gen2PackPage.BLANK_TILE, "the listing is cleared"
	)
	assert_eq(
		map[3 * Gen2PackPage.COLUMNS], Gen2PackPage.PACK_FIRST_TILE, "the pack picture"
	)
	assert_eq(
		map[3 * Gen2PackPage.COLUMNS + 4], Gen2PackPage.PACK_FIRST_TILE + 4,
		"the picture's own run"
	)
	assert_eq(map[7 * Gen2PackPage.COLUMNS], NAME_TILES[0], "the pocket name")
	assert_eq(
		map[12 * Gen2PackPage.COLUMNS], RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TOP_LEFT,
		"the text box"
	)


func test_a_row_is_a_name_a_count_and_the_cursor() -> void:
	var rows: Array = [
		{"kind": Gen2PackPage.ROW_ITEM, "name": "AB", "quantity": 7, "show_quantity": true},
		{"kind": Gen2PackPage.ROW_CANCEL},
	]
	var map: PackedInt32Array = _page().pocket_map(0, rows, 1, "", _name_piece(0))
	var name_codes: PackedByteArray = Gen2Text.encode("AB")
	assert_eq(
		map[2 * Gen2PackPage.COLUMNS + Gen2PackPage.NAME_COLUMN], int(name_codes[0]),
		"the name starts in column 8 of row 2"
	)
	assert_eq(
		map[3 * Gen2PackPage.COLUMNS + 17], Gen2PackPage.TIMES_CODE,
		"the count sits a row under the name"
	)
	assert_eq(
		map[3 * Gen2PackPage.COLUMNS + 19], int(Gen2Text.encode("7")[0]),
		"and is two digits wide"
	)
	assert_eq(
		map[4 * Gen2PackPage.COLUMNS + Gen2PackPage.NAME_COLUMN],
		int(Gen2Text.encode("CANCEL")[0]), "CANCEL follows the last item"
	)
	assert_eq(
		map[4 * Gen2PackPage.COLUMNS + Gen2PackPage.CURSOR_COLUMN], Gen2PackPage.CURSOR_CODE,
		"the cursor is one column left of the names"
	)


## `PlaceMenuItemQuantity` asks `_CheckTossableItem` first, so a key item is a
## name and nothing else.
func test_an_untossable_row_has_no_count() -> void:
	var rows: Array = [
		{"kind": Gen2PackPage.ROW_ITEM, "name": "AB", "quantity": 1, "show_quantity": false},
	]
	var map: PackedInt32Array = _page().pocket_map(2, rows, 0, "", _name_piece(2))
	assert_eq(
		map[3 * Gen2PackPage.COLUMNS + 17], Gen2PackPage.BLANK_TILE, "no × is written"
	)


## `TMHM_DisplayPocketItems` prints its number in the column the other pockets
## leave empty: two digits with the leading zero for a TM, "H" and the number
## for an HM.
func test_the_tmhm_pocket_prints_its_number() -> void:
	var rows: Array = [
		{"kind": Gen2PackPage.ROW_TM, "name": "CUT", "number": 3, "hm": false,
			"quantity": 1, "show_quantity": true},
		{"kind": Gen2PackPage.ROW_TM, "name": "FLY", "number": 2, "hm": true,
			"quantity": 1, "show_quantity": false},
	]
	var map: PackedInt32Array = _page().pocket_map(3, rows, -1, "", _name_piece(3))
	var at: int = 2 * Gen2PackPage.COLUMNS + Gen2PackPage.TMHM_NUMBER_COLUMN
	assert_eq(map[at], int(Gen2Text.encode("0")[0]), "a TM keeps its leading zero")
	assert_eq(map[at + 1], int(Gen2Text.encode("3")[0]))
	var hm_at: int = 4 * Gen2PackPage.COLUMNS + Gen2PackPage.TMHM_NUMBER_COLUMN
	assert_eq(map[hm_at], int(Gen2Text.encode("H")[0]), "an HM is an H and its number")
	assert_eq(map[hm_at + 1], int(Gen2Text.encode("2")[0]))


## `PackGFXPointers` is not in pocket order: the sheet holds key items, items,
## TM/HM and balls, and each pocket indexes its own picture out of it.
func test_each_pocket_draws_its_own_picture() -> void:
	var page: Gen2PackPage = _page()
	var seen: Dictionary = {}
	for pocket: int in RomLayout.PACK_POCKETS:
		var map: PackedInt32Array = page.pocket_map(pocket, [], -1, "", _name_piece(pocket))
		var indices: PackedByteArray = page.compose(map, pocket)
		var pixel: int = indices[3 * Gen2PackPage.TILE * Gen2Screen.WIDTH]
		assert_eq(
			pixel, RomLayout.PACK_POCKET_PICTURES[pocket],
			"pocket %d draws its own piece" % pocket
		)
		seen[pixel] = pocket
	assert_eq(seen.size(), RomLayout.PACK_POCKETS, "four distinct pictures")


## `_CGB_PackPals` picks Kris's six palettes over Chris's, and her pack over his.
func test_the_female_pack_is_its_own_sheet_and_palettes() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var page: Gen2PackPage = Gen2PackPage.from_data(data)
	var map: PackedInt32Array = page.pocket_map(0, [], -1, "", _name_piece(0))
	assert_ne(
		page.compose(map, 0, true)[3 * Gen2PackPage.TILE * Gen2Screen.WIDTH],
		page.compose(map, 0, false)[3 * Gen2PackPage.TILE * Gen2Screen.WIDTH],
		"the two sheets are different pictures"
	)
	assert_ne(
		data.pack_palette(0, true)[1], data.pack_palette(0, false)[1],
		"and are drawn through different palettes"
	)


func _page() -> Gen2PackPage:
	return Gen2PackPage.from_data(GameData.open_directory(_directory))


func _name_piece(pocket: int) -> PackedByteArray:
	return GameData.open_directory(_directory).pack_pocket_name(pocket)


func _write_cache() -> void:
	var sheets: Dictionary = {}
	for name: String in ["font", "frames"]:
		var tiles: int = RomLayout.FONT_TILES if name == "font" \
			else RomLayout.FRAME_COUNT * RomLayout.FRAME_TILES
		var indices := PackedByteArray()
		indices.resize(tiles * Gen2Tiles.TILE_PIXELS)
		indices.fill(3)
		RomCache.write_indices(RomCache.tile_path(_directory, name), indices)
		sheets[name] = _sheet_entry(tiles, RomLayout.FONT_FIRST_CODE \
			if name == "font" else RomLayout.FRAME_FIRST_CODE)

	var menu := PackedByteArray()
	menu.resize(RomLayout.PACK_MENU_TILES * Gen2Tiles.TILE_PIXELS)
	menu.fill(SHEET_INDEX)
	RomCache.write_indices(RomCache.tile_path(_directory, "pack_menu"), menu)
	sheets["pack_menu"] = _sheet_entry(RomLayout.PACK_MENU_TILES, 0)

	# Piece p is filled with index p, and the female sheet with the piece after
	# it, so which sheet and which piece reached the screen are both readable.
	for name: String in ["pack_pockets", "pack_pockets_female"]:
		var strip := PackedByteArray()
		var width: int = RomLayout.PACK_TILES * Gen2Tiles.TILE_WIDTH
		strip.resize(width * Gen2Tiles.TILE_HEIGHT)
		var shift: int = 1 if name.ends_with("female") else 0
		for row: int in Gen2Tiles.TILE_HEIGHT:
			for column: int in width:
				@warning_ignore("integer_division")
				var piece: int = column / (RomLayout.PACK_POCKET_TILES * Gen2Tiles.TILE_WIDTH)
				strip[row * width + column] = (piece + shift) % RomLayout.PACK_POCKETS
		RomCache.write_indices(RomCache.tile_path(_directory, name), strip)
		sheets[name] = _sheet_entry(RomLayout.PACK_TILES, 0)

	var names: Array = []
	for pocket: int in RomLayout.PACK_POCKETS:
		for _cell: int in RomLayout.PACK_NAME_COLUMNS * RomLayout.PACK_NAME_ROWS:
			names.append(NAME_TILES[pocket])
	var palettes: Array = []
	var female_palettes: Array = []
	for index: int in RomLayout.PACK_PALETTES * RomLayout.PACK_PALETTE_COLORS:
		palettes.append(0x7FFF if index % RomLayout.PACK_PALETTE_COLORS == 0 else 0x001F)
		female_palettes.append(
			0x7FFF if index % RomLayout.PACK_PALETTE_COLORS == 0 else 0x7C00
		)

	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": String(DIRECTORY_ID),
		"sha1": SHA,
		"tiles": sheets,
		"pack": {
			"pocket_names": names,
			"palettes": palettes,
			"female_palettes": female_palettes,
		},
		"complete": true,
	})


func _sheet_entry(tiles: int, first_code: int) -> Dictionary:
	return {
		"width": tiles * Gen2Tiles.TILE_WIDTH,
		"height": Gen2Tiles.TILE_HEIGHT,
		"tiles": tiles,
		"first_code": first_code,
		"bits": 1,
	}
