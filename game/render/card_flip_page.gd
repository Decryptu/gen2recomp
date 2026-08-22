class_name Gen2CardFlipPage
extends RefCounted

## `_CardFlip`'s screen: `CardFlipTilemap` and the two card slots beside it,
## under the border and cursor objects `CardFlip_CopyOAM` writes.
##
## Node-free, so the whole table can be read back headless. [Gen2CardFlip] owns
## the state and the background it writes; this is the two boxes over it, the
## palettes and shadow OAM.
##
## Four things the source states that a reading gets wrong:
##
## - **Every object here is eight by eight.** `_CardFlip` never touches
##   `B_LCDC_OBJ_SIZE`, and the slot machine's `set` is its own, reset on the way
##   out; the intro menu leaves the hardware on 8x8. A cursor tile is one tile.
## - **The objects are drawn in the map's own palettes.** `CardFlip_InitAttrPals`
##   writes `wBGPals1` and nothing else, and `DmgToCgbObjPals` reorders
##   `wOBPals1` into the live buffer with `%11100100`, which is the identity. So
##   object palette 0 is still `PAL_OW_RED` from the Game Corner's own map.
## - **The lamps are characters.** `_CardFlip` copies its two bulbs over the
##   font's "♂" and "♀", so `CARD_FLIP_LIGHT_OFF_TILE` sits in the font's
##   half of the window and every other cell of the board is under it.
## - **Crystal's digits stand one pixel higher.** `CardFlip_ShiftDigitsUpOnePixel`
##   copies each of "0" to "9" back two bytes over itself, which is one pixel
##   row, and blanks the last row of "9". pokegold marks the routine
##   `; unreferenced` and its digits sit where the font puts them.

const TILE: int = Gen2Font.TILE
const SCREEN_COLUMNS: int = Gen2CardFlip.SCREEN_COLUMNS
const SCREEN_ROWS: int = Gen2CardFlip.SCREEN_ROWS
const WIDTH: int = SCREEN_COLUMNS * TILE
const HEIGHT: int = SCREEN_ROWS * TILE

## `_CardFlip`'s three background loads: `CardFlipLZ01` into `vTiles2 tile $00`
## and `CardFlipLZ02` into `vTiles2 tile $3e`, with the font in the half above
## them. `CardFlipLZ03` goes to `vTiles0 tile $00` and is the objects' alone.
const SHEET_1_FIRST_TILE: int = 0x00
const SHEET_2_FIRST_TILE: int = 0x3E
## The run a background tile number can address before it is a character.
const BACKGROUND_TILES: int = 128
const BACKGROUND_WIDTH: int = BACKGROUND_TILES * TILE
const OBJECT_TILES: int = 7
const OBJECT_WIDTH: int = OBJECT_TILES * TILE

## `CardFlip_UpdateCoinBalanceDisplay`'s `Textbox` at `hlcoord 0, 12` with
## `b, 4 / c, SCREEN_WIDTH - 2`, and the text it prints at `hlcoord 1, 14`.
const TEXTBOX_AT: Vector2i = Vector2i(0, 12)
const TEXTBOX_SIZE: Vector2i = Vector2i(20, 6)
const TEXT_AT: Vector2i = Vector2i(1, 14)
const TEXT_SPACING: int = 2
## `CardFlip_PrintCoinBalance`: its own box at `hlcoord 9, 15`, "COIN" at
## `hlcoord 10, 16` and four leading-zero digits at `hlcoord 15, 16`.
const COIN_BOX_AT: Vector2i = Vector2i(9, 15)
const COIN_BOX_SIZE: Vector2i = Vector2i(11, 3)
const COIN_LABEL_AT: Vector2i = Vector2i(10, 16)
const COIN_COUNT_AT: Vector2i = Vector2i(15, 16)
const COIN_DIGITS: int = 4
## `YesNoBox`'s own `lb bc, SCREEN_WIDTH - 6, 7`, which `_YesNoBox` reads as the
## left and top coordinates and adds 5 and 4 to.
const YES_NO_AT: Vector2i = Vector2i(14, 7)
const YES_NO_SIZE: Vector2i = Vector2i(6, 5)
## `YesNoMenuHeader` sets `STATICMENU_NO_TOP_SPACING`, so YES stands one row
## inside the box, and `PlaceVerticalMenuItems` steps two rows to NO.
## `Place2DMenuCursor`'s own "▶".
const CURSOR_CODE: int = 0xED
## `LoadBlinkingCursor`'s "▼" and its `ldcoord_a 18, 17`.
const BLINK_CODE: int = 0xEE
const BLINK_AT: Vector2i = Vector2i(18, 17)
## `_BlinkCursor` shows it for eight of every sixteen frames.
const BLINK_PERIOD: int = 16

## The hardware's own OAM offsets, which every base and every object byte here
## is expressed in.
const OAM_ORIGIN: Vector2i = Vector2i(8, 16)
## `GetCoordsOfChosenCard`'s two `bcpixel`s, as (x, y) OAM bytes.
const CARD_OAM_BASE: Array[Vector2i] = [Vector2i(24, 16), Vector2i(24, 64)]

## Which shape `CardFlip_UpdateCursorOAM.OAMData` names for a cell.
enum Shape { SINGLE, MON, NUMBER, NUMBER_PAIR, MON_PAIR, IMPOSSIBLE }

## `PlaceOAMCardBorder.SpriteData` and the six cursor shapes, each row
## (y, x, tile, x flip, y flip, priority) with `dbsprite`'s own bytes worked out.
const BORDER_OBJECTS: Array[Array] = [
	[0, 0, 0x04, false, false, false],
	[0, 8, 0x06, false, false, false],
	[0, 16, 0x06, false, false, false],
	[0, 24, 0x06, false, false, false],
	[0, 32, 0x04, true, false, false],
	[8, 0, 0x05, false, false, false],
	[8, 32, 0x05, true, false, false],
	[16, 0, 0x05, false, false, false],
	[16, 32, 0x05, true, false, false],
	[24, 0, 0x05, false, false, false],
	[24, 32, 0x05, true, false, false],
	[32, 0, 0x05, false, false, false],
	[32, 32, 0x05, true, false, false],
	[40, 0, 0x04, false, true, false],
	[40, 8, 0x06, false, true, false],
	[40, 16, 0x06, false, true, false],
	[40, 24, 0x06, false, true, false],
	[40, 32, 0x04, true, true, false],
]
const CURSOR_SINGLE: Array[Array] = [
	[0, 255, 0x00, false, false, true],
	[0, 0, 0x02, false, false, true],
	[0, 8, 0x03, false, false, true],
	[5, 255, 0x00, false, true, true],
	[5, 0, 0x02, false, true, true],
	[5, 8, 0x03, false, false, true],
]
const CURSOR_MON: Array[Array] = [
	[0, 255, 0x00, false, false, true],
	[0, 0, 0x02, false, false, true],
	[0, 8, 0x00, true, false, true],
	[8, 255, 0x01, false, false, true],
	[8, 8, 0x01, true, false, true],
	[16, 255, 0x01, false, false, true],
	[16, 8, 0x03, false, false, true],
	[24, 255, 0x01, false, false, true],
	[24, 8, 0x03, false, false, true],
	[32, 255, 0x01, false, false, true],
	[32, 8, 0x03, false, false, true],
	[40, 255, 0x01, false, false, true],
	[40, 8, 0x03, false, false, true],
	[48, 255, 0x01, false, false, true],
	[48, 8, 0x03, false, false, true],
	[56, 255, 0x01, false, false, true],
	[56, 8, 0x03, false, false, true],
	[64, 255, 0x01, false, false, true],
	[64, 8, 0x03, false, false, true],
	[72, 255, 0x01, false, false, true],
	[72, 8, 0x03, false, false, true],
	[80, 255, 0x01, false, false, true],
	[80, 8, 0x03, false, false, true],
	[81, 255, 0x00, false, true, true],
	[81, 0, 0x02, false, true, true],
	[81, 8, 0x03, false, false, true],
]
const CURSOR_NUMBER: Array[Array] = [
	[0, 255, 0x00, false, false, true],
	[0, 0, 0x02, false, false, true],
	[0, 8, 0x02, false, false, true],
	[0, 16, 0x03, false, false, true],
	[0, 24, 0x02, false, false, true],
	[0, 32, 0x03, false, false, true],
	[0, 40, 0x02, false, false, true],
	[0, 48, 0x03, false, false, true],
	[0, 56, 0x02, false, false, true],
	[0, 64, 0x03, false, false, true],
	[5, 255, 0x00, false, true, true],
	[5, 0, 0x02, false, true, true],
	[5, 8, 0x02, false, true, true],
	[5, 16, 0x03, false, false, true],
	[5, 24, 0x02, false, true, true],
	[5, 32, 0x03, false, false, true],
	[5, 40, 0x02, false, true, true],
	[5, 48, 0x03, false, false, true],
	[5, 56, 0x02, false, true, true],
	[5, 64, 0x03, false, false, true],
]
const CURSOR_NUMBER_PAIR: Array[Array] = [
	[0, 0, 0x00, false, false, true],
	[0, 8, 0x02, false, false, true],
	[0, 16, 0x02, false, false, true],
	[0, 24, 0x03, false, false, true],
	[0, 32, 0x02, false, false, true],
	[0, 40, 0x03, false, false, true],
	[0, 48, 0x02, false, false, true],
	[0, 56, 0x03, false, false, true],
	[0, 64, 0x02, false, false, true],
	[0, 72, 0x03, false, false, true],
	[8, 0, 0x01, false, false, true],
	[8, 24, 0x03, false, false, true],
	[8, 40, 0x03, false, false, true],
	[8, 56, 0x03, false, false, true],
	[8, 72, 0x03, false, false, true],
	[16, 0, 0x01, false, false, true],
	[16, 24, 0x03, false, false, true],
	[16, 40, 0x03, false, false, true],
	[16, 56, 0x03, false, false, true],
	[16, 72, 0x03, false, false, true],
	[17, 0, 0x00, false, true, true],
	[17, 8, 0x02, false, true, true],
	[17, 16, 0x02, false, true, true],
	[17, 24, 0x03, false, false, true],
	[17, 32, 0x03, false, false, true],
	[17, 40, 0x03, false, false, true],
	[17, 48, 0x03, false, false, true],
	[17, 56, 0x03, false, false, true],
	[17, 64, 0x03, false, false, true],
	[17, 72, 0x03, false, false, true],
]
const CURSOR_MON_PAIR: Array[Array] = [
	[0, 255, 0x00, false, false, true],
	[0, 24, 0x00, true, false, true],
	[8, 255, 0x01, false, false, true],
	[8, 24, 0x01, true, false, true],
	[16, 255, 0x01, false, false, true],
	[16, 24, 0x01, true, false, true],
	[24, 255, 0x01, false, false, true],
	[24, 8, 0x03, false, false, true],
	[24, 24, 0x03, false, false, true],
	[32, 255, 0x01, false, false, true],
	[32, 8, 0x03, false, false, true],
	[32, 24, 0x03, false, false, true],
	[40, 255, 0x01, false, false, true],
	[40, 8, 0x03, false, false, true],
	[40, 24, 0x03, false, false, true],
	[48, 255, 0x01, false, false, true],
	[48, 8, 0x03, false, false, true],
	[48, 24, 0x03, false, false, true],
	[56, 255, 0x01, false, false, true],
	[56, 8, 0x03, false, false, true],
	[56, 24, 0x03, false, false, true],
	[64, 255, 0x01, false, false, true],
	[64, 8, 0x03, false, false, true],
	[64, 24, 0x03, false, false, true],
	[72, 255, 0x01, false, false, true],
	[72, 8, 0x03, false, false, true],
	[72, 24, 0x03, false, false, true],
	[80, 255, 0x01, false, false, true],
	[80, 8, 0x03, false, false, true],
	[80, 24, 0x03, false, false, true],
	[88, 255, 0x01, false, false, true],
	[88, 8, 0x03, false, false, true],
	[88, 24, 0x03, false, false, true],
	[89, 255, 0x00, false, true, true],
	[89, 0, 0x02, false, true, true],
	[89, 8, 0x03, false, true, true],
	[89, 16, 0x02, false, true, true],
	[89, 24, 0x03, true, true, true],
]
const CURSOR_IMPOSSIBLE: Array[Array] = [
	[0, 0, 0x00, false, false, true],
	[0, 8, 0x00, true, false, true],
	[8, 0, 0x00, false, true, true],
	[8, 8, 0x00, true, true, true],
]
## The shapes by the name the jumptable gives them.
const CURSOR_SHAPES: Array[Array] = [
	CURSOR_SINGLE, CURSOR_MON, CURSOR_NUMBER, CURSOR_NUMBER_PAIR,
	CURSOR_MON_PAIR, CURSOR_IMPOSSIBLE,
]

## `CardFlip_UpdateCursorOAM.OAMData`, one row per `CollapseCursorPosition`
## answer: the OAM x and y the shape is copied at, and the shape.
const CURSOR_CELLS: Array[Array] = [
	[88, 16, Shape.IMPOSSIBLE],
	[96, 16, Shape.IMPOSSIBLE],
	[104, 16, Shape.MON_PAIR],
	[104, 16, Shape.MON_PAIR],
	[136, 16, Shape.MON_PAIR],
	[136, 16, Shape.MON_PAIR],
	[88, 24, Shape.IMPOSSIBLE],
	[96, 24, Shape.IMPOSSIBLE],
	[104, 24, Shape.MON],
	[120, 24, Shape.MON],
	[136, 24, Shape.MON],
	[152, 24, Shape.MON],
	[88, 40, Shape.NUMBER_PAIR],
	[96, 40, Shape.NUMBER],
	[104, 40, Shape.SINGLE],
	[120, 40, Shape.SINGLE],
	[136, 40, Shape.SINGLE],
	[152, 40, Shape.SINGLE],
	[88, 40, Shape.NUMBER_PAIR],
	[96, 52, Shape.NUMBER],
	[104, 52, Shape.SINGLE],
	[120, 52, Shape.SINGLE],
	[136, 52, Shape.SINGLE],
	[152, 52, Shape.SINGLE],
	[88, 64, Shape.NUMBER_PAIR],
	[96, 64, Shape.NUMBER],
	[104, 64, Shape.SINGLE],
	[120, 64, Shape.SINGLE],
	[136, 64, Shape.SINGLE],
	[152, 64, Shape.SINGLE],
	[88, 64, Shape.NUMBER_PAIR],
	[96, 76, Shape.NUMBER],
	[104, 76, Shape.SINGLE],
	[120, 76, Shape.SINGLE],
	[136, 76, Shape.SINGLE],
	[152, 76, Shape.SINGLE],
	[88, 88, Shape.NUMBER_PAIR],
	[96, 88, Shape.NUMBER],
	[104, 88, Shape.SINGLE],
	[120, 88, Shape.SINGLE],
	[136, 88, Shape.SINGLE],
	[152, 88, Shape.SINGLE],
	[88, 88, Shape.NUMBER_PAIR],
	[96, 100, Shape.NUMBER],
	[104, 100, Shape.SINGLE],
	[120, 100, Shape.SINGLE],
	[136, 100, Shape.SINGLE],
	[152, 100, Shape.SINGLE],
]


var font: Gen2Font = null
var frame_style: int = 0
## Whether `CardFlip_ShiftDigitsUpOnePixel` ran, which is Crystal alone.
var digits_lifted: bool = false
var _background_tiles: PackedByteArray = PackedByteArray()
var _object_tiles: PackedByteArray = PackedByteArray()
var _light_off: PackedByteArray = PackedByteArray()
var _light_on: PackedByteArray = PackedByteArray()
var _board: PackedByteArray = PackedByteArray()
var _palettes: Array[PackedColorArray] = []
## `wOBPals1` palette 0, which the map screen left standing.
var _object_palette: PackedColorArray = PackedColorArray()


static func from_data(data: GameData) -> Gen2CardFlipPage:
	if data == null or not data.has_card_flip():
		return null
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	var one: PackedByteArray = data.card_flip_indices("card_flip_1")
	var two: PackedByteArray = data.card_flip_indices("card_flip_2")
	var three: PackedByteArray = data.card_flip_indices("card_flip_3")
	var board: PackedByteArray = data.card_flip_tilemap()
	if glyphs == null or one.is_empty() or two.is_empty() or three.is_empty() \
		or board.size() < RomLayout.CARD_FLIP_TILEMAP_BYTES:
		return null

	var page := Gen2CardFlipPage.new()
	page.font = glyphs
	page.frame_style = Gen2OptionsStore.current().textbox_frame
	page.digits_lifted = data.id == RomRegistry.CRYSTAL
	page._board = board
	page._background_tiles = _bank(
		[[SHEET_1_FIRST_TILE, one], [SHEET_2_FIRST_TILE, two]], BACKGROUND_TILES
	)
	page._object_tiles = three
	page._light_off = data.card_flip_indices("card_flip_off")
	page._light_on = data.card_flip_indices("card_flip_on")
	for index: int in RomLayout.CARD_FLIP_PALETTES:
		page._palettes.append(data.card_flip_palette(index))
	return page


## The half of the window a background tile number addresses, as one strip with
## each run laid at its own first tile.
static func _bank(runs: Array, tiles: int) -> PackedByteArray:
	var width: int = tiles * TILE
	var bank := PackedByteArray()
	bank.resize(width * TILE)
	for run: Array in runs:
		var first: int = int(run[0])
		var strip: PackedByteArray = run[1]
		@warning_ignore("integer_division")
		var count: int = strip.size() / Gen2Tiles.TILE_PIXELS
		var strip_width: int = count * TILE
		for tile: int in count:
			var column: int = (first + tile) * TILE
			if column + TILE > width:
				continue
			for row: int in TILE:
				for pixel: int in TILE:
					bank[row * width + column + pixel] = strip[
						row * strip_width + tile * TILE + pixel
					]
	return bank


func ready() -> bool:
	return not _board.is_empty() and not _palettes.is_empty()


## `CardFlipTilemap`, which [Gen2CardFlip] draws into its own background.
func board() -> PackedByteArray:
	return _board


## `PAL_OW_RED` out of the map the player is standing on, which is the palette
## every object here is drawn through.
func set_object_palette(colors: PackedColorArray) -> void:
	_object_palette = colors


## The whole screen for [param game]. [param state] is what the host holds over
## it:
##
## [codeblock]
## {
##   "text": String,   # the box under the table, empty for none
##   "yes_no": int,    # 1 or 2 while a YES/NO box is up, 0 for none
##   "blink": int,     # the frame a loaded blinking cursor is counted on, -1 none
## }
## [/codeblock]
func render(game: Gen2CardFlip, state: Dictionary = {}) -> Image:
	if not ready():
		return null
	var indices := PackedByteArray()
	indices.resize(WIDTH * HEIGHT)
	var map: PackedByteArray = game.tilemap() if game != null else PackedByteArray()
	for row: int in SCREEN_ROWS:
		for column: int in SCREEN_COLUMNS:
			var cell: int = row * SCREEN_COLUMNS + column
			_blit_background(
				indices, int(map[cell]) if cell < map.size() else Gen2CardFlip.GREEN_TILE,
				Vector2i(column * TILE, row * TILE)
			)
	_draw_boxes(indices, game, state)

	var image: Image = Gen2PicImage.from_attributes(
		indices, WIDTH, HEIGHT, _attributes(game), SCREEN_COLUMNS, _palettes
	)
	_draw_objects(image, game, indices)
	return image


func _attributes(game: Gen2CardFlip) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(SCREEN_COLUMNS * SCREEN_ROWS)
	if game == null:
		return out
	var attributes: PackedByteArray = game.attributes()
	for cell: int in mini(out.size(), attributes.size()):
		out[cell] = int(attributes[cell])
	return out


## A background cell. The two lamps are characters `_CardFlip` overwrote, so
## they are tested before the font and before the sheets.
func _blit_background(into: PackedByteArray, code: int, at: Vector2i) -> void:
	if code == RomLayout.CARD_FLIP_LIGHT_OFF_TILE:
		Gen2Font.blit_slot(_light_off, TILE, 0, into, WIDTH, at.x, at.y)
		return
	if code == RomLayout.CARD_FLIP_LIGHT_ON_TILE:
		Gen2Font.blit_slot(_light_on, TILE, 0, into, WIDTH, at.x, at.y)
		return
	if code >= RomLayout.FONT_FIRST_CODE:
		_draw_code(code, into, at.x, at.y)
		return
	Gen2Font.blit_slot(_background_tiles, BACKGROUND_WIDTH, code, into, WIDTH, at.x, at.y)


## `CardFlip_ShiftDigitsUpOnePixel`: a digit's rows move up one and its last row
## is blank, which the routine gets for free from the row above being blank.
func _draw_code(code: int, into: PackedByteArray, at_x: int, at_y: int) -> void:
	var digit: bool = code >= RomLayout.FONT_DIGIT_ZERO_CODE \
		and code < RomLayout.FONT_DIGIT_ZERO_CODE + 10
	if not digits_lifted or not digit:
		font.draw_code(code, into, WIDTH, at_x, at_y)
		return
	var glyph := PackedByteArray()
	glyph.resize(TILE * TILE)
	font.draw_code(code, glyph, TILE, 0, 0)
	for row: int in TILE - 1:
		for pixel: int in TILE:
			var y: int = at_y + row
			var x: int = at_x + pixel
			if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
				continue
			into[y * WIDTH + x] = glyph[(row + 1) * TILE + pixel]


## The two boxes `CardFlip_UpdateCoinBalanceDisplay` draws and the YES/NO one
## over them.
func _draw_boxes(
	into: PackedByteArray, game: Gen2CardFlip, state: Dictionary
) -> void:
	_fill_interior(into, TEXTBOX_AT, TEXTBOX_SIZE)
	font.draw_box(
		frame_style, into, WIDTH, TEXTBOX_AT.x * TILE, TEXTBOX_AT.y * TILE,
		TEXTBOX_SIZE.x, TEXTBOX_SIZE.y
	)
	var line: int = 0
	for row: String in String(state.get("text", "")).split("\n"):
		font.draw_text(
			row, into, WIDTH, TEXT_AT.x * TILE, (TEXT_AT.y + line * TEXT_SPACING) * TILE
		)
		line += 1
	_fill_interior(into, COIN_BOX_AT, COIN_BOX_SIZE)
	font.draw_box(
		frame_style, into, WIDTH, COIN_BOX_AT.x * TILE, COIN_BOX_AT.y * TILE,
		COIN_BOX_SIZE.x, COIN_BOX_SIZE.y
	)
	font.draw_text("COIN", into, WIDTH, COIN_LABEL_AT.x * TILE, COIN_LABEL_AT.y * TILE)
	var coins: String = str(clampi(
		game.coins() if game != null else 0, 0, Gen2CardFlip.MAX_COINS
	)).lpad(COIN_DIGITS, "0")
	for index: int in COIN_DIGITS:
		_draw_code(
			RomLayout.FONT_DIGIT_ZERO_CODE + coins.unicode_at(index) - "0".unicode_at(0),
			into, (COIN_COUNT_AT.x + index) * TILE, COIN_COUNT_AT.y * TILE
		)
	var blink: int = int(state.get("blink", -1))
	if blink >= 0 and blink % BLINK_PERIOD < BLINK_PERIOD / 2:
		font.draw_code(BLINK_CODE, into, WIDTH, BLINK_AT.x * TILE, BLINK_AT.y * TILE)
	var yes_no: int = int(state.get("yes_no", 0))
	if yes_no > 0:
		_draw_yes_no(into, yes_no)


## `Textbox`'s own `ClearBox`: the interior is blanked before anything is
## written into it, which is what keeps the table from showing through.
func _fill_interior(into: PackedByteArray, at: Vector2i, box: Vector2i) -> void:
	for row: int in (box.y - 2) * TILE:
		var y: int = (at.y + 1) * TILE + row
		for pixel: int in (box.x - 2) * TILE:
			var x: int = (at.x + 1) * TILE + pixel
			if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
				continue
			into[y * WIDTH + x] = 0


func _draw_yes_no(into: PackedByteArray, cursor: int) -> void:
	_fill_interior(into, YES_NO_AT, YES_NO_SIZE)
	font.draw_box(
		frame_style, into, WIDTH, YES_NO_AT.x * TILE, YES_NO_AT.y * TILE,
		YES_NO_SIZE.x, YES_NO_SIZE.y
	)
	var rows: Array[String] = ["YES", "NO"]
	for index: int in rows.size():
		var y: int = (YES_NO_AT.y + 1 + index * TEXT_SPACING) * TILE
		if index == cursor - 1:
			font.draw_code(CURSOR_CODE, into, WIDTH, (YES_NO_AT.x + 1) * TILE, y)
		font.draw_text(rows[index], into, WIDTH, (YES_NO_AT.x + 2) * TILE, y)


## Shadow OAM: `PlaceOAMCardBorder` or `CardFlip_UpdateCursorOAM`, never both,
## since each opens with the other's slots cleared.
func _draw_objects(
	image: Image, game: Gen2CardFlip, background: PackedByteArray
) -> void:
	if game == null:
		return
	var buffer := PackedByteArray()
	buffer.resize(WIDTH * HEIGHT)
	if game.border_at() >= 0:
		_copy_oam(
			buffer, BORDER_OBJECTS, CARD_OAM_BASE[game.border_at() & 1], background
		)
	elif game.cursor_visible():
		var cell: Vector2i = game.cursor()
		var index: int = cell.y * Gen2CardFlip.CURSOR_COLUMNS + cell.x
		if index >= 0 and index < CURSOR_CELLS.size():
			var row: Array = CURSOR_CELLS[index]
			_copy_oam(
				buffer, CURSOR_SHAPES[int(row[2])],
				Vector2i(int(row[0]), int(row[1])), background
			)
	image.blend_rect(
		Gen2PicImage.from_indices(buffer, WIDTH, HEIGHT, _object_colors(), true),
		Rect2i(0, 0, WIDTH, HEIGHT), Vector2i.ZERO
	)


func _object_colors() -> PackedColorArray:
	return _object_palette if _object_palette.size() >= 4 \
		else (_palettes[0] if not _palettes.is_empty() else PackedColorArray())


## `CardFlip_CopyOAM`: the base is added to each object's own byte in eight bits,
## so an object at x $ff sits one pixel left of the base rather than off screen.
func _copy_oam(
	into: PackedByteArray, objects: Array, base: Vector2i,
	background: PackedByteArray
) -> void:
	for object: Array in objects:
		var at := Vector2i(
			((base.x + int(object[1])) & 0xFF) - OAM_ORIGIN.x,
			((base.y + int(object[0])) & 0xFF) - OAM_ORIGIN.y
		)
		_blit_object(
			into, int(object[2]), at, bool(object[3]), bool(object[4]),
			background if bool(object[5]) else PackedByteArray()
		)


## One eight by eight object. [param behind] is the background a priority object
## is tested against: `OAM_PRIO` loses every pixel the tilemap already colours.
func _blit_object(
	into: PackedByteArray, tile: int, at: Vector2i, flip_x: bool, flip_y: bool,
	behind: PackedByteArray
) -> void:
	var first: int = tile * TILE
	if tile < 0 or first + TILE > OBJECT_WIDTH:
		return
	for row: int in TILE:
		var y: int = at.y + (TILE - 1 - row if flip_y else row)
		if y < 0 or y >= HEIGHT:
			continue
		for pixel: int in TILE:
			var x: int = at.x + (TILE - 1 - pixel if flip_x else pixel)
			if x < 0 or x >= WIDTH:
				continue
			var index: int = _object_tiles[row * OBJECT_WIDTH + first + pixel]
			if index == 0:
				continue
			if not behind.is_empty() and behind[y * WIDTH + x] != 0:
				continue
			into[y * WIDTH + x] = index
