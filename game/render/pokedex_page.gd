class_name Gen2PokedexPage
extends RefCounted

## The Pokedex's own tile screens (engine/pokedex/pokedex.asm).
##
## [Gen2Pokedex] owns the listing, the cursor and the mode; this is the picture,
## the way [Gen2TownMapPage] is the region map's. Every layout here is one of the
## source's `Pokedex_Draw*BG` routines read as tile writes, so a screen is a
## 20x18 grid of tile numbers in the dex's own VRAM numbering and nothing else.
##
## Three sheets share that numbering, which is what `Pokedex_LoadGFX` leaves in
## `vTiles2`:
##
## - `$00` to `$30` is the font, **inverted**. `Pokedex_LoadInvertedFont` XORs
##   every byte, so a lit pixel becomes an unlit one and the whole screen is
##   light text on dark rather than the overworld's dark on light.
## - `$31` to `$6a` is `PokedexLZ`'s 58 tiles, which the decompress lands on top
##   of whatever was there.
## - `$6b` up is `LoadFontsExtra`, inverted by the same `Pokedex_InvertTiles`
##   pass over `$60` to `$7f`. Only the run past the dex sheet survives it.
##
## The main screen is the one that is not a plain grid: its listing is in the
## *window* layer at `hWX`, over a background scrolled by `POKEDEX_SCX`, so it
## is composed in pixels by [method image_main] rather than written into one map.

const COLUMNS: int = 20
const ROWS: int = 18
const TILE: int = 8
const WIDTH: int = COLUMNS * TILE
const HEIGHT: int = ROWS * TILE

## Where `PokedexLZ` lands, which is what a sheet tile number is offset by.
const SHEET_FIRST_TILE: int = 0x31

## `Pokedex_FillBackgroundColor2`'s fill, and the tile every cleared cell is.
const BACKGROUND_TILE: int = 0x32

## `Pokedex_PlaceBorder`'s nine tiles, in the order it writes them: the top row,
## then each middle row, then the bottom.
const BORDER_TOP_LEFT: int = 0x33
const BORDER_TOP: int = 0x34
const BORDER_TOP_RIGHT: int = 0x35
const BORDER_LEFT: int = 0x36
const BORDER_RIGHT: int = 0x37
const BORDER_BOTTOM_LEFT: int = 0x38
const BORDER_BOTTOM: int = 0x39
const BORDER_BOTTOM_RIGHT: int = 0x3A
## The border's inside, which is a space rather than one of its own tiles.
const BORDER_FILL: int = 0x7F

## The sidebar's own column and its three joints (`Pokedex_DrawMainScreenBG`).
const SIDEBAR_TOP: int = 0x59
const SIDEBAR: int = 0x5A
const SIDEBAR_BOTTOM: int = 0x5B
const SIDEBAR_SPLIT_TOP: int = 0x53
const SIDEBAR_SPLIT_BOTTOM: int = 0x54
## The search results screen's own pair below the split, where the main screen
## has the second box's top.
const RESULTS_SPLIT_TOP: int = 0x69
const RESULTS_SPLIT_BOTTOM: int = 0x6A

## `DrawPokedexListWindow`: the listing's frame, its scroll bar and the two
## tiles that replace the bar in DEXMODE_OLD.
const WINDOW_LEFT_JOINT: int = 0x3F
const WINDOW_LEFT_JOINT_BOTTOM: int = 0x40
const SCROLL_TOP: int = 0x50
const SCROLL: int = 0x51
const SCROLL_BOTTOM: int = 0x52
const NO_SCROLL_TOP: int = 0x66
const NO_SCROLL: int = 0x67
const NO_SCROLL_BOTTOM: int = 0x68

## The entry screen's divider under the picture, and the page marker beside it.
const ENTRY_DIVIDER: int = 0x61
const PAGE_MARKER_TOP: int = 0x55
const PAGE_MARKER: int = 0x56
const PAGE_ONE: int = 0x57
const PAGE_TWO: int = 0x58

## `Pokedex_DrawFootprint`'s four cells, and where they go.
const FOOTPRINT_TOP: int = 0x62
const FOOTPRINT_BOTTOM: int = 0x64
const FOOTPRINT_AT := Vector2i(18, 1)

## `.Number`'s two tiles, and the two the height line's feet and inches use.
const NUMBER_NO: int = 0x5C
const NUMBER_DOT: int = 0x5D
const HEIGHT_FEET: int = 0x5E
const HEIGHT_INCHES: int = 0x5F

## `Pokedex_PlaceCaughtSymbolIfCaught`'s own tile, which is a character.
const CAUGHT_SYMBOL: int = 0x4F
## `Pokedex_BlinkArrowCursor`'s two, which are characters as well.
const CURSOR_CODE: int = 0xED
const CURSOR_BLANK: int = 0x7F

## `POKEDEX_SCX`, the five pixels the main screen's background is scrolled by.
const MAIN_SCX: int = 5
## `hWX` less the hardware's own seven, for the two dex modes: `$47` for a mode
## with a scroll bar and `$4a` for DEXMODE_OLD, which has none. Neither is a tile
## boundary once the background is scrolled, which is why the main screen is
## composed in pixels.
const MAIN_WINDOW_X: int = 0x47 - 7
const MAIN_WINDOW_X_OLD: int = 0x4A - 7
## `DrawPokedexListWindow` writes twelve columns and no more.
const WINDOW_COLUMNS: int = 12

## `String_SELECT_OPTION` and `String_START_SEARCH`, which are tile runs rather
## than text: the two button pictures are drawn out of the dex sheet.
const SELECT_OPTION: Array[int] = [0x3B, 0x48, 0x49, 0x4A, 0x44, 0x45, 0x46, 0x47]
const START_SEARCH: Array[int] = [
	0x3C, 0x3B, 0x41, 0x42, 0x43, 0x4B, 0x4C, 0x4D, 0x4E, 0x3C,
]
## `.TypeLeftRightArrows`' two ends, and the pair the Unown screen puts under its
## own box.
const ARROW_LEFT: int = 0x3D
const ARROW_RIGHT: int = 0x3E

var font: Gen2Font = null
## The dex sheet, the Slowpoke picture and the footprint strip, each as the
## cache's own index buffer.
var _sheet: PackedByteArray = PackedByteArray()
var _slowpoke: PackedByteArray = PackedByteArray()
var _footprints: PackedByteArray = PackedByteArray()
var _unown_font: PackedByteArray = PackedByteArray()
var _palette: PackedColorArray = PackedColorArray()
var _question_mark: PackedColorArray = PackedColorArray()


## [param data] supplies the glyphs and all three sheets; a cache without them
## answers null rather than drawing a screen of blanks.
static func from_data(data: GameData) -> Gen2PokedexPage:
	if data == null:
		return null
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null:
		return null
	var out := Gen2PokedexPage.new()
	out.font = glyphs
	out._sheet = data.tile_indices("pokedex")
	out._slowpoke = data.tile_indices("pokedex_slowpoke")
	out._footprints = data.tile_indices("footprints")
	out._unown_font = data.tile_indices("unown_font")
	out._palette = data.pokedex_palette("interface")
	out._question_mark = data.pokedex_palette("question_mark")
	return out


func ready() -> bool:
	return font != null and not _sheet.is_empty() and not _footprints.is_empty() \
		and _palette.size() == Gen2Palette.COLORS_PER_PIC


## A screen filled the way `Pokedex_FillBackgroundColor2` fills one.
static func blank_map() -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(COLUMNS * ROWS)
	map.fill(BACKGROUND_TILE)
	return map


## `Pokedex_DrawMainScreenBG`: the left sidebar, the two boxes and the bottom
## bar. The listing is not in it; that is the window, and [method window_map]
## draws it.
##
## [param seen] and [param caught] are the two counts `CountSetBits` prints.
func main_background(seen: int, caught: int) -> PackedInt32Array:
	_unown_letters = false
	var map: PackedInt32Array = blank_map()
	_place_border(map, 0, 0, 7, 7)
	_place_border(map, 0, 9, 6, 7)
	_text(map, 1, 11, "SEEN")
	_number(map, 5, 12, seen, 3)
	_text(map, 1, 14, "OWN")
	_number(map, 5, 15, caught, 3)
	# `String_SELECT_OPTION` falls through into `String_START_SEARCH`, so the one
	# `Pokedex_PlaceString` at (1,17) writes both runs; the START one on its own
	# is in the window, which is what covers the right-hand half of this row.
	_tiles(map, 1, 17, SELECT_OPTION)
	_tiles(map, 1 + SELECT_OPTION.size(), 17, START_SEARCH)
	_column(map, 8, 1, 7, SIDEBAR)
	_column(map, 8, 10, 6, SIDEBAR)
	_put(map, 8, 0, SIDEBAR_TOP)
	_put(map, 8, 8, SIDEBAR_SPLIT_TOP)
	_put(map, 8, 9, SIDEBAR_SPLIT_BOTTOM)
	_put(map, 8, 16, SIDEBAR_BOTTOM)
	_place_pic_corner(map, 1, 1)
	return map


## `Pokedex_DrawSearchResultsScreenBG`, which is the main screen's sidebar with
## one box instead of two and the result count under it.
func search_results_background(count: int, type_line: String) -> PackedInt32Array:
	_unown_letters = false
	var map: PackedInt32Array = blank_map()
	_place_border(map, 0, 0, 7, 7)
	_place_border(map, 0, 11, 5, 18)
	_text(map, 1, 12, "SEARCH RESULTS")
	_text(map, 1, 13, "  TYPE")
	# `.BottomWindowText`'s third line and `Pokedex_PlaceSearchResultsTypeStrings`
	# are written into two different maps and overlap on screen; laid out as one
	# row here, which is the one thing on this screen the oracle has not settled.
	_text(map, 1, 14, type_line)
	_text(map, 9, 14, "FOUND!")
	_number(map, 1, 16, count, 3)
	_put(map, 8, 0, SIDEBAR_TOP)
	_column(map, 8, 1, 7, SIDEBAR)
	_put(map, 8, 8, SIDEBAR_SPLIT_TOP)
	_put(map, 8, 9, RESULTS_SPLIT_TOP)
	_put(map, 8, 10, RESULTS_SPLIT_BOTTOM)
	_place_pic_corner(map, 1, 1)
	return map


## `DrawPokedexListWindow` and `Pokedex_PrintListing`, as the twelve-column
## window the main screen and the results screen both put their listing in.
##
## [param rows] is [method Gen2Pokedex.rows]' own shape: `number`, `name`,
## `seen` and `caught` per visible entry. [param old_mode] swaps the scroll bar
## for the two tiles that replace it and is what prints a dex number above each
## name; [param cursor] is which row the arrow stands on, or -1 while it blinks
## off.
func window_map(rows: Array, old_mode: bool, cursor: int) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(WINDOW_COLUMNS * ROWS)
	map.fill(CURSOR_BLANK)
	# `DrawPokedexListWindow` fills its own row 17, and `Pokedex_InitMainScreen`
	# writes `String_START_SEARCH` over it: the bar under the listing is the
	# window's, not the background's.
	for column: int in WINDOW_COLUMNS:
		map[17 * WINDOW_COLUMNS + column] = BACKGROUND_TILE
	for index: int in START_SEARCH.size():
		map[17 * WINDOW_COLUMNS + index] = START_SEARCH[index]
	for column: int in 11:
		map[column] = BORDER_TOP
		map[16 * WINDOW_COLUMNS + column] = BORDER_BOTTOM
	map[5] = WINDOW_LEFT_JOINT
	map[16 * WINDOW_COLUMNS + 5] = WINDOW_LEFT_JOINT_BOTTOM
	map[11] = NO_SCROLL_TOP if old_mode else SCROLL_TOP
	for row: int in ROWS - 3:
		map[(row + 1) * WINDOW_COLUMNS + 11] = NO_SCROLL if old_mode else SCROLL
	map[(ROWS - 2) * WINDOW_COLUMNS + 11] = NO_SCROLL_BOTTOM if old_mode else SCROLL_BOTTOM

	_window_rows(map, rows, old_mode, cursor)
	return map


## `Pokedex_PrintListing`, which both listing screens share: one entry every two
## rows from row 2, the caught symbol one cell ahead of the name, and the arrow
## in column 0.
func _window_rows(
	map: PackedInt32Array, rows: Array, old_mode: bool, cursor: int
) -> void:
	for index: int in rows.size():
		var entry: Dictionary = rows[index]
		var row: int = 2 + index * 2
		if row >= ROWS:
			break
		if old_mode:
			_window_number(map, 1, row - 1, int(entry.get("number", 0)))
		if not bool(entry.get("seen", false)):
			_window_text(map, 2, row, Gen2Pokedex.NOT_SEEN_NAME)
			continue
		if bool(entry.get("caught", false)):
			map[row * WINDOW_COLUMNS + 1] = CAUGHT_SYMBOL
		_window_text(map, 2, row, String(entry.get("name", "")))
	if cursor >= 0 and cursor < rows.size():
		map[(2 + cursor * 2) * WINDOW_COLUMNS] = CURSOR_CODE


## How much of the results window reaches the screen; see [method
## results_window_map].
const RESULTS_WINDOW_ROWS: int = 11


## `DrawPokedexSearchResultsWindow`: two stacked frames rather than the main
## screen's one, with the four-row listing in the upper.
func results_window_map(rows: Array, cursor: int) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(WINDOW_COLUMNS * ROWS)
	map.fill(CURSOR_BLANK)
	# `DrawPokedexSearchResultsWindow` draws a second frame over rows 11 to 17,
	# which at `hWX` $4a would cut `.BottomWindowText` in the background box in
	# half. Only the listing's own frame is drawn until the oracle says what the
	# hardware puts there; see HANDOFF.md.
	for frame: Array in [[0, 10]]:
		var top: int = int(frame[0])
		var bottom: int = int(frame[1])
		for column: int in 11:
			map[top * WINDOW_COLUMNS + column] = BORDER_TOP
			map[bottom * WINDOW_COLUMNS + column] = BORDER_BOTTOM
		map[top * WINDOW_COLUMNS + 11] = NO_SCROLL_TOP
		for row: int in range(top + 1, bottom):
			map[row * WINDOW_COLUMNS + 11] = NO_SCROLL
		map[bottom * WINDOW_COLUMNS + 11] = NO_SCROLL_BOTTOM
	map[5] = WINDOW_LEFT_JOINT
	map[10 * WINDOW_COLUMNS + 5] = WINDOW_LEFT_JOINT_BOTTOM
	_window_rows(map, rows, false, cursor)
	return map


## `Pokedex_DrawDexEntryScreenBG` and `DisplayDexEntry`, as one grid.
##
## [param entry] is [method GameData.dex_entry]'s own record. A species that has
## not been caught keeps the placeholder height and weight the background draws,
## which is what the source's early `ret z` leaves on screen.
func entry_map(
	number: int, name: String, entry: Dictionary, caught: bool, page: int, cursor: int
) -> PackedInt32Array:
	_unown_letters = false
	var map: PackedInt32Array = blank_map()
	_place_border(map, 0, 0, 15, 18)
	_put(map, 19, 0, BORDER_TOP)
	_column(map, 19, 1, 15, CURSOR_BLANK)
	_put(map, 19, 16, BORDER_BOTTOM)
	_fill(map, 1, 10, 19, ENTRY_DIVIDER)
	_fill(map, 1, 17, 18, CURSOR_BLANK)
	_text(map, 9, 7, "HT  ?")
	_put(map, 14, 7, HEIGHT_FEET)
	_text(map, 15, 7, "??")
	_put(map, 17, 7, HEIGHT_INCHES)
	_text(map, 9, 9, "WT   ???lb")
	_put(map, 0, 17, SELECT_OPTION[0])
	_text(map, 1, 17, " PAGE AREA CRY PRNT")
	_place_pic_corner(map, 1, 1)

	_text(map, 9, 3, name)
	_text(map, 9, 5, String(entry.get("category", "")))
	_put(map, 2, 8, NUMBER_NO)
	_put(map, 3, 8, NUMBER_DOT)
	_number(map, 4, 8, number, 3, true)
	if caught:
		# `PrintNum` writes the height as four digits with two in front of the
		# point, and the point is then overwritten with the feet symbol; the
		# weight is five digits with four in front of it, which is tenths of a
		# pound. Both are the numbers the cartridge stores, not a conversion.
		var height: int = int(entry.get("height", 0))
		@warning_ignore("integer_division")
		_number(map, 12, 7, height / 100, 2)
		_put(map, 14, 7, HEIGHT_FEET)
		_number(map, 15, 7, height % 100, 2, true)
		_number(map, 11, 9, int(entry.get("weight", 0)), 5, false, 1)
	_put(map, 1, 9, PAGE_MARKER_TOP)
	_put(map, 2, 9, PAGE_MARKER_TOP)
	_put(map, 1, 10, PAGE_MARKER)
	_put(map, 2, 10, PAGE_ONE if page == Gen2Pokedex.PAGE_1 else PAGE_TWO)
	var pages: Array = entry.get("pages", []) as Array
	var body: String = String(pages[page]) if page < pages.size() else ""
	_paragraph(map, 2, 11, body)
	_place_footprint_cells(map)
	if cursor >= 0 and cursor < Gen2PokedexScreen.ENTRY_BUTTONS.size():
		_put(map, ENTRY_CURSOR_COLUMNS[cursor], 17, CURSOR_CODE)
	return map


## `DexEntryScreen_ArrowCursorData`'s four `dwcoord`s, which are all on row 17.
const ENTRY_CURSOR_COLUMNS: Array[int] = [1, 6, 11, 15]
## `.ArrowCursorData` on the OPTION screen and on SEARCH, whose rows are the ones
## the two `dwcoord` lists name.
const OPTION_CURSOR_ROWS: Array[int] = [4, 6, 8, 10]
const SEARCH_CURSOR_ROWS: Array[int] = [4, 6, 13, 15]


## `Pokedex_DrawOptionScreenBG`, whose fourth row is drawn only once
## `wUnlockedUnownMode` is set.
func option_map(
	unown_unlocked: bool, cursor: int, description: String = ""
) -> PackedInt32Array:
	_unown_letters = false
	var map: PackedInt32Array = blank_map()
	_place_border(map, 0, 2, 8, 18)
	_title(map, 1, "OPTION")
	for index: int in Gen2Pokedex.MODE_ROWS.size():
		if index == 3 and not unown_unlocked:
			break
		_text(map, 3, OPTION_CURSOR_ROWS[index], String(
			Gen2Pokedex.MODE_ROWS[index]["label"]
		))
	var rows: int = 4 if unown_unlocked else 3
	if cursor >= 0 and cursor < rows:
		_put(map, 2, OPTION_CURSOR_ROWS[cursor], CURSOR_CODE)
	_bottom_box(map, description)
	return map


## `Pokedex_DisplayModeDescription`, `Pokedex_DisplayChangingModesMessage` and
## `Pokedex_DisplayTypeNotFoundMessage` are the same box redrawn: four rows at
## (0,12) with two lines of words from (1,14).
func _bottom_box(map: PackedInt32Array, text: String) -> void:
	_place_border(map, 0, 12, 4, 18)
	var row: int = 0
	for line: String in text.split("\n"):
		if row >= 2:
			break
		_text(map, 1, 14 + row, line)
		row += 1


## `Pokedex_DrawSearchScreenBG`, with the two chosen type names in place.
func search_map(
	type_1: String, type_2: String, cursor: int, message: String = ""
) -> PackedInt32Array:
	_unown_letters = false
	var map: PackedInt32Array = blank_map()
	_place_border(map, 0, 2, 14, 18)
	_title(map, 1, "SEARCH")
	for row: int in [4, 6]:
		_put(map, 8, row, ARROW_LEFT)
		_put(map, 17, row, ARROW_RIGHT)
	_text(map, 3, 4, "TYPE1")
	_text(map, 3, 6, "TYPE2")
	_text(map, 10, 4, type_1)
	_text(map, 10, 6, type_2)
	_text(map, 3, 13, "BEGIN SEARCH!!")
	_text(map, 3, 15, "CANCEL")
	if cursor >= 0 and cursor < SEARCH_CURSOR_ROWS.size():
		_put(map, 2, SEARCH_CURSOR_ROWS[cursor], CURSOR_CODE)
	if not message.is_empty():
		_bottom_box(map, message)
	return map


## `Pokedex_DrawUnownModeBG` and its own letter walk.
##
## [param forms] is `wUnownDex`, the forms in catching order, and
## [constant UNOWN_COORDS] the table it indexes: the letter's cell and the cell
## the cursor stands in beside it, which are not always the same column.
## [param word] is `PrintUnownWord`'s own, the chamber word for the form the
## cursor is on.
func unown_map(forms: Array, cursor: int, word: String = "") -> PackedInt32Array:
	_unown_letters = true
	var map: PackedInt32Array = blank_map()
	_place_border(map, 2, 1, 10, 13)
	_place_border(map, 2, 14, 1, 13)
	_put(map, 2, 15, ARROW_LEFT)
	_put(map, 16, 15, ARROW_RIGHT)
	_place_pic_corner(map, 6, 5)
	for index: int in mini(forms.size(), UNOWN_COORDS.size()):
		var form: int = int(forms[index])
		if form <= 0:
			break
		var at: Array = UNOWN_COORDS[index]
		_put(map, int(at[0]), int(at[1]), UNOWN_FIRST_CHAR + form - 1)
		if index == cursor:
			_put(map, int(at[2]), int(at[3]), CURSOR_CODE)
	# `PrintUnownWord` clears twelve cells at (4,15) and prints the cursor's own
	# word into them.
	_fill(map, 4, 15, 12, CURSOR_BLANK)
	_text(map, 4, 15, word)
	return map


## `FIRST_UNOWN_CHAR`, which the letter walk adds the form to. The letters are
## `UnownFont` inverted into the dex sheet's own numbering, so a form's cell is a
## sheet tile rather than a character.
const UNOWN_FIRST_CHAR: int = RomLayout.UNOWN_FONT_FIRST_TILE
## `UnownModeLetterAndCursorCoords`, as (letter x, letter y, cursor x, cursor y)
## per form in catching order.
const UNOWN_COORDS: Array = [
	[4, 11, 3, 11], [4, 10, 3, 10], [4, 9, 3, 9], [4, 8, 3, 8],
	[4, 7, 3, 7], [4, 6, 3, 6], [4, 5, 3, 5], [4, 4, 3, 4],
	[4, 3, 3, 2], [5, 3, 5, 2], [6, 3, 6, 2], [7, 3, 7, 2],
	[8, 3, 8, 2], [9, 3, 9, 2], [10, 3, 10, 2], [11, 3, 11, 2],
	[12, 3, 12, 2], [13, 3, 13, 2], [14, 3, 15, 2], [14, 4, 15, 4],
	[14, 5, 15, 5], [14, 6, 15, 6], [14, 7, 15, 7], [14, 8, 15, 8],
	[14, 9, 15, 9], [14, 10, 15, 10],
]


## One grid as pixels. [param pic] is the species picture drawn into the 7x7 box
## the layout left blank, or null for a screen that shows none.
func image(map: PackedInt32Array, pic: Image = null, pic_at: Vector2i = Vector2i(1, 1)) -> Image:
	var indices := PackedByteArray()
	indices.resize(WIDTH * HEIGHT)
	for row: int in ROWS:
		for column: int in COLUMNS:
			_blit_tile(indices, WIDTH, map[row * COLUMNS + column], column * TILE, row * TILE)
	var out: Image = Gen2PicImage.from_indices(indices, WIDTH, HEIGHT, _palette)
	if pic != null:
		# `_PrepMonFrontpic` centres a pic in its seven-tile cell and sits it on
		# the cell's floor, so a 5x5 species is not drawn in the corner.
		var cell: int = 7 * TILE
		out.blend_rect(pic, Rect2i(Vector2i.ZERO, pic.get_size()), Vector2i(
			pic_at.x * TILE + (cell - pic.get_width()) / 2,
			pic_at.y * TILE + cell - pic.get_height()
		))
	return out


## The main screen, composed the way the hardware composes it: the background
## scrolled left by [constant MAIN_SCX] and the listing window blitted over it at
## its own `hWX`. Both layers wrap at the background map's 256 pixels, which is
## why the background is drawn wide and sampled rather than blitted.
func image_main(
	background: PackedInt32Array, window: PackedInt32Array, old_mode: bool,
	pic: Image = null, window_rows: int = ROWS
) -> Image:
	var out: Image = image(background, pic)
	var scrolled: Image = Image.create(WIDTH, HEIGHT, false, out.get_format())
	for x: int in WIDTH:
		scrolled.blit_rect(
			out, Rect2i((x + MAIN_SCX) % WIDTH, 0, 1, HEIGHT), Vector2i(x, 0)
		)
	var indices := PackedByteArray()
	indices.resize(WINDOW_COLUMNS * TILE * HEIGHT)
	for row: int in ROWS:
		for column: int in WINDOW_COLUMNS:
			_blit_tile(
				indices, WINDOW_COLUMNS * TILE,
				window[row * WINDOW_COLUMNS + column], column * TILE, row * TILE
			)
	var layer: Image = Gen2PicImage.from_indices(
		indices, WINDOW_COLUMNS * TILE, HEIGHT, _palette
	)
	var at: int = MAIN_WINDOW_X_OLD if old_mode else MAIN_WINDOW_X
	scrolled.blit_rect(
		layer,
		Rect2i(0, 0, mini(layer.get_width(), WIDTH - at), window_rows * TILE),
		Vector2i(at, 0)
	)
	return scrolled


## The Slowpoke picture, which is what `Pokedex_LoadSelectedMonTiles` puts in the
## box for a species that has not been seen. Drawn through its own palette, the
## one `_CGB_Pokedex` fills the 7x7 box with.
func unseen_pic() -> Image:
	if _slowpoke.is_empty():
		return null
	var colors: PackedColorArray = _question_mark if _question_mark.size() \
		== Gen2Palette.COLORS_PER_PIC else _palette
	var side: int = 7 * TILE
	var indices := PackedByteArray()
	indices.resize(side * side)
	for tile: int in mini(RomLayout.POKEDEX_SLOWPOKE_TILES, 49):
		@warning_ignore("integer_division")
		Gen2Font.blit_slot(
			_slowpoke, _slowpoke.size() / TILE, tile, indices, side,
			(tile / 7) * TILE, (tile % 7) * TILE
		)
	return Gen2PicImage.from_indices(indices, side, side, colors)


## `Pokedex_LoadCurrentFootprint`, as the four tiles the entry screen's grid
## names. Answers false when the cache carries no footprint for the species, in
## which case the four cells keep whatever the sheet has at those numbers.
func load_footprint(data: GameData, species: int) -> bool:
	_footprint = PackedInt32Array()
	if data == null:
		return false
	var tiles: PackedInt32Array = data.footprint_tiles(species)
	if tiles.is_empty():
		return false
	_footprint = tiles
	return true


var _footprint := PackedInt32Array()
## Whether `Pokedex_LoadUnownFont` has run, which only the Unown screen does.
var _unown_letters: bool = false


## `Pokedex_DrawFootprint`'s four cells at (18,1) and (18,2).
func _place_footprint_cells(map: PackedInt32Array) -> void:
	for index: int in 4:
		@warning_ignore("integer_division")
		_put(
			map, FOOTPRINT_AT.x + (index % 2), FOOTPRINT_AT.y + (index / 2),
			FOOTPRINT_TOP + index if index < 2 else FOOTPRINT_BOTTOM + index - 2
		)


## `Pokedex_PlaceBorder`: a box [param height] rows of inside tall and
## [param width] columns of inside wide, from its own top-left corner.
func _place_border(
	map: PackedInt32Array, x: int, y: int, height: int, width: int
) -> void:
	_put(map, x, y, BORDER_TOP_LEFT)
	for column: int in width:
		_put(map, x + 1 + column, y, BORDER_TOP)
	_put(map, x + 1 + width, y, BORDER_TOP_RIGHT)
	for row: int in height:
		_put(map, x, y + 1 + row, BORDER_LEFT)
		for column: int in width:
			_put(map, x + 1 + column, y + 1 + row, BORDER_FILL)
		_put(map, x + 1 + width, y + 1 + row, BORDER_RIGHT)
	_put(map, x, y + 1 + height, BORDER_BOTTOM_LEFT)
	for column: int in width:
		_put(map, x + 1 + column, y + 1 + height, BORDER_BOTTOM)
	_put(map, x + 1 + width, y + 1 + height, BORDER_BOTTOM_RIGHT)


## `Pokedex_PlaceFrontpicAtHL`: the 7x7 run of tile numbers the picture is drawn
## through, counted down each column, which is how a pic is stored.
func _place_pic_corner(map: PackedInt32Array, x: int, y: int) -> void:
	for row: int in 7:
		for column: int in 7:
			_put(map, x + column, y + row, row + column * 7)


## `.Title`'s own three pieces: the SELECT picture, the name, and the START one.
func _title(map: PackedInt32Array, y: int, label: String) -> void:
	_put(map, 0, y, SELECT_OPTION[0])
	_text(map, 1, y, " %s " % label)
	_put(map, 2 + label.length(), y, START_SEARCH[0])


func _column(map: PackedInt32Array, x: int, y: int, height: int, tile: int) -> void:
	for row: int in height:
		_put(map, x, y + row, tile)


func _fill(map: PackedInt32Array, x: int, y: int, width: int, tile: int) -> void:
	for column: int in width:
		_put(map, x + column, y, tile)


func _tiles(map: PackedInt32Array, x: int, y: int, run: Array[int]) -> void:
	for index: int in run.size():
		_put(map, x + index, y, run[index])


## `PlaceString`, whose `CheckDict` expands the shorthand before a tile is drawn.
## That expansion is [method Gen2Text.encode]'s, which matters here more than
## elsewhere: `$54` is a dex sheet tile on this screen, so a byte placed as
## itself would draw part of the frame.
func _text(map: PackedInt32Array, x: int, y: int, text: String) -> void:
	var codes: PackedByteArray = Gen2Text.encode(text)
	for index: int in codes.size():
		_put(map, x + index, y, codes[index])


## `PrintNum`, as the digits it writes. [param leading_zeros] is its own flag;
## [param decimals] splits the run the way the height and weight lines do.
func _number(
	map: PackedInt32Array, x: int, y: int, value: int, width: int,
	leading_zeros: bool = false, decimals: int = 0
) -> void:
	var text: String = String.num_int64(maxi(value, 0))
	if leading_zeros:
		text = text.lpad(width, "0")
	else:
		text = text.lpad(width, " ")
	if decimals > 0 and text.length() > decimals:
		text = "%s.%s" % [
			text.substr(0, text.length() - decimals),
			text.substr(text.length() - decimals),
		]
	_text(map, x, y, text)


## One dex entry's page, wrapped into the five rows `ClearBox` cleared for it.
func _paragraph(map: PackedInt32Array, x: int, y: int, text: String) -> void:
	var row: int = 0
	for line: String in text.split("\n"):
		if row >= 5:
			break
		_text(map, x, y + row, line)
		row += 1


func _put(map: PackedInt32Array, x: int, y: int, tile: int) -> void:
	if x < 0 or x >= COLUMNS or y < 0 or y >= ROWS:
		return
	map[y * COLUMNS + x] = tile


func _window_text(map: PackedInt32Array, x: int, y: int, text: String) -> void:
	var codes: PackedByteArray = Gen2Text.encode(text)
	for index: int in codes.size():
		var column: int = x + index
		if column >= WINDOW_COLUMNS or y >= ROWS:
			break
		map[y * WINDOW_COLUMNS + column] = codes[index]


func _window_number(map: PackedInt32Array, x: int, y: int, value: int) -> void:
	var text: String = String.num_int64(maxi(value, 0)).lpad(3, "0")
	_window_text(map, x, y, text)


## One tile of the dex's own VRAM into an index buffer. `$31` to `$6a` is the
## dex sheet, the footprint cells are the four the strip was loaded with, and
## everything else is the font, inverted the way `Pokedex_LoadInvertedFont`
## leaves it.
func _blit_tile(
	into: PackedByteArray, into_width: int, tile: int, at_x: int, at_y: int
) -> void:
	# `Pokedex_LoadUnownFont` lands on top of the sheet, so this run is the
	# alphabet on the Unown screen and the sheet's own tiles everywhere else.
	if _unown_letters and tile >= UNOWN_FIRST_CHAR \
		and tile < UNOWN_FIRST_CHAR + RomLayout.UNOWN_FONT_TILES:
		@warning_ignore("integer_division")
		Gen2Font.blit_slot(
			_unown_font, _unown_font.size() / TILE, tile - UNOWN_FIRST_CHAR,
			into, into_width, at_x, at_y
		)
		_invert(into, into_width, at_x, at_y)
		return
	var footprint: int = _footprint_slot(tile)
	if footprint >= 0:
		@warning_ignore("integer_division")
		Gen2Font.blit_slot(
			_footprints, _footprints.size() / TILE, footprint,
			into, into_width, at_x, at_y
		)
		_invert(into, into_width, at_x, at_y)
		return
	if tile >= SHEET_FIRST_TILE and tile < SHEET_FIRST_TILE + RomLayout.POKEDEX_TILES:
		@warning_ignore("integer_division")
		Gen2Font.blit_slot(
			_sheet, _sheet.size() / TILE, tile - SHEET_FIRST_TILE,
			into, into_width, at_x, at_y
		)
		return
	font.draw_code(tile, into, into_width, at_x, at_y)
	_invert(into, into_width, at_x, at_y)


## Which of the four loaded footprint tiles a cell names, or -1 for a cell that
## is not one. The numbers are `Pokedex_DrawFootprint`'s own.
func _footprint_slot(tile: int) -> int:
	if _footprint.size() != 4:
		return -1
	if tile == FOOTPRINT_TOP:
		return _footprint[0]
	if tile == FOOTPRINT_TOP + 1:
		return _footprint[1]
	if tile == FOOTPRINT_BOTTOM:
		return _footprint[2]
	if tile == FOOTPRINT_BOTTOM + 1:
		return _footprint[3]
	return -1


## `Pokedex_LoadInvertedFont`'s `xor $ff`, which on a 1bpp tile swaps the two
## indices a pixel can be: 3 is lit and 0 is not (`Serve1bppRequest` writes each
## byte into both planes).
func _invert(into: PackedByteArray, into_width: int, at_x: int, at_y: int) -> void:
	@warning_ignore("integer_division")
	var height: int = into.size() / into_width
	for y: int in TILE:
		var row: int = at_y + y
		if row < 0 or row >= height:
			continue
		for x: int in TILE:
			var column: int = at_x + x
			if column < 0 or column >= into_width:
				continue
			var at: int = row * into_width + column
			into[at] = 0 if into[at] == 3 else 3
