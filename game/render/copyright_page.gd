class_name Gen2CopyrightPage
extends RefCounted

## The copyright screen (`Copyright`, `engine/menus/intro_menu.asm`), on the tile
## grid the hardware uses.
##
## The whole screen is one graphic and one code run: `ClearTilemap` blanks the
## map, `CopyrightGFX` is requested into `vTiles2 tile $60`, and
## `CopyrightString` is placed at (2,7). None of its codes is a character, so
## nothing here reads the font: each code is a tile of that strip, and the
## screen is white everywhere else.
##
## `PlaceString` pushes the line's own start and `NextLineChar` pops it and adds
## `SCREEN_WIDTH * 2`, so the three rows start in the same column, two rows
## apart: (2,7), (2,9) and (2,11).
##
## Node-free, like the other `render/*_page.gd`: it writes indices into a buffer,
## so a page can be drawn and read back headless.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18
## `NextLineChar`'s own `ld bc, SCREEN_WIDTH * 2`.
const ROW_STRIDE: int = 2
## `ClearTilemap` leaves the map on the blank below the font, which draws
## nothing: index 0 through the default background palette.
const BLANK_INDEX: int = 0

## PREDEFPAL_GAMEFREAK_LOGO_BG, which `_CGB_GamefreakLogo` loads before this
## screen is drawn. Its first colour is black and its last white, so the blank
## map is a black screen and the letters are the light end of the graphic.
var palette: PackedColorArray = PackedColorArray()

## The strip as one row of tiles, and the code its first tile draws.
var _indices: PackedByteArray = PackedByteArray()
var _width: int = 0
var _first_code: int = RomLayout.COPYRIGHT_FIRST_CODE
var _tiles: int = 0
var _string: PackedByteArray = PackedByteArray()


## Null on a cache with no copyright screen, which is the caller's cue not to
## run the phase rather than to draw an empty one.
static func from_data(data: GameData) -> Gen2CopyrightPage:
	if data == null:
		return null
	var sheet: Dictionary = data.tile_sheet("copyright")
	var indices: PackedByteArray = data.tile_indices("copyright")
	var codes: PackedByteArray = data.copyright_string()
	if sheet.is_empty() or indices.is_empty() or codes.is_empty():
		return null
	var out := Gen2CopyrightPage.new()
	out._indices = indices
	out._width = int(sheet.get("width", 0))
	out._tiles = int(sheet.get("tiles", 0))
	out._first_code = int(sheet.get("first_code", RomLayout.COPYRIGHT_FIRST_CODE))
	out._string = codes
	out.palette = data.copyright_palette()
	if out._width <= 0 or out._tiles <= 0:
		return null
	return out


func string_codes() -> PackedByteArray:
	return _string


## The whole 160x144 screen as palette indices.
func draw() -> PackedByteArray:
	var width: int = COLUMNS * TILE
	var page := PackedByteArray()
	page.resize(width * ROWS * TILE)
	page.fill(BLANK_INDEX)
	var at: Vector2i = RomLayout.COPYRIGHT_AT
	var column: int = 0
	var row: int = 0
	for code: int in _string:
		if code == RomLayout.COPYRIGHT_STRING_NEXT:
			row += ROW_STRIDE
			column = 0
			continue
		_blit_tile(page, width, code, at + Vector2i(column, row))
		column += 1
	return page


func _blit_tile(page: PackedByteArray, width: int, code: int, at: Vector2i) -> void:
	var tile: int = code - _first_code
	if tile < 0 or tile >= _tiles:
		return
	if at.x < 0 or at.y < 0 or at.x >= COLUMNS or at.y >= ROWS:
		return
	for y: int in TILE:
		for x: int in TILE:
			page[(at.y * TILE + y) * width + at.x * TILE + x] = _indices[
				y * _width + tile * TILE + x
			]
