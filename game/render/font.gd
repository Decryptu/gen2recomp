class_name Gen2Font
extends RefCounted

## The cartridge's own font, drawn a tile at a time.
##
## Text here is tilemapped, not typeset: every character is one 8x8 tile of equal
## width, and a character code is already the tile number that draws it. Nothing
## is measured or kerned; indices are copied into a buffer at multiples of eight.
##
## Both sheets are one row of tiles ([method Gen2Tiles.decode_1bpp_strip]), so a
## code is a horizontal offset and nothing else. A code with no tile draws
## nothing rather than a placeholder, which is what the space at $7F is and what
## the hardware does.
##
## Node-free: it writes into an index buffer, not the screen, so a whole text box
## can be laid out and checked headless.

const TILE: int = 8

var _glyphs: PackedByteArray = PackedByteArray()
var _glyph_width: int = 0
var _first_code: int = RomLayout.FONT_FIRST_CODE
var _glyph_tiles: int = 0

var _frames: PackedByteArray = PackedByteArray()
var _frame_width: int = 0
var _frame_first_code: int = RomLayout.FRAME_FIRST_CODE
var _frame_tiles: int = 0


## Reads both sheets out of a cache, or null if that cache has no font in it.
static func from_data(data: GameData) -> Gen2Font:
	if data == null:
		return null

	var font: Dictionary = data.tile_sheet("font")
	if font.is_empty():
		return null

	var out := Gen2Font.new()
	out._glyphs = data.tile_indices("font")
	out._glyph_width = int(font.get("width", 0))
	out._first_code = int(font.get("first_code", RomLayout.FONT_FIRST_CODE))
	out._glyph_tiles = int(font.get("tiles", 0))

	var frames: Dictionary = data.tile_sheet("frames")
	out._frames = data.tile_indices("frames")
	out._frame_width = int(frames.get("width", 0))
	out._frame_first_code = int(frames.get("first_code", RomLayout.FRAME_FIRST_CODE))
	out._frame_tiles = int(frames.get("tiles", 0))

	return out if out.is_usable() else null


func is_usable() -> bool:
	return _glyph_width > 0 and _glyphs.size() >= _glyph_width * TILE


func frame_count() -> int:
	if RomLayout.FRAME_TILES <= 0:
		return 0
	@warning_ignore("integer_division")
	return _frame_tiles / RomLayout.FRAME_TILES


## Draws one character code at a tile position, in pixels from the top left.
## A code with no tile draws nothing, which is what a space is.
func draw_code(
	code: int, into: PackedByteArray, into_width: int, at_x: int, at_y: int
) -> void:
	var slot: int = code - _first_code
	if slot < 0 or slot >= _glyph_tiles:
		return
	blit_slot(_glyphs, _glyph_width, slot, into, into_width, at_x, at_y)


## Draws a string left to right from [param at_x], advancing eight pixels per
## tile. Returns how many tiles were drawn, which is not the string's length
## when it contains a ligature.
func draw_text(
	text: String, into: PackedByteArray, into_width: int, at_x: int, at_y: int
) -> int:
	var codes: PackedByteArray = Gen2Text.encode(text)
	for i: int in codes.size():
		draw_code(codes[i], into, into_width, at_x + i * TILE, at_y)
	return codes.size()


## Draws one tile of one text box border. [param code] is a box-drawing code
## from the charmap ($79 to $7E), so a border is printed the way the hardware
## prints it: as characters.
func draw_frame_code(
	frame: int, code: int, into: PackedByteArray, into_width: int, at_x: int, at_y: int
) -> void:
	var within: int = code - _frame_first_code
	if within < 0 or within >= RomLayout.FRAME_TILES:
		return
	var slot: int = frame * RomLayout.FRAME_TILES + within
	if frame < 0 or slot >= _frame_tiles:
		return
	blit_slot(_frames, _frame_width, slot, into, into_width, at_x, at_y)


## Copies one tile out of a strip, clipped to the destination. Clipping rather
## than refusing, because a text box that runs off the edge of the screen should
## look wrong at the edge and be right everywhere else.
##
## Public because every sheet in this project is a strip and they all draw from
## one the same way; [Gen2BattleTiles] is the other caller.
static func blit_slot(
	strip: PackedByteArray,
	strip_width: int,
	slot: int,
	into: PackedByteArray,
	into_width: int,
	at_x: int,
	at_y: int
) -> void:
	if into_width <= 0 or strip_width <= 0:
		return
	@warning_ignore("integer_division")
	var into_height: int = into.size() / into_width
	var left: int = slot * TILE

	for y: int in TILE:
		var to_y: int = at_y + y
		if to_y < 0 or to_y >= into_height:
			continue
		var from: int = y * strip_width + left
		var to: int = to_y * into_width + at_x
		for x: int in TILE:
			var to_x: int = at_x + x
			if to_x < 0 or to_x >= into_width:
				continue
			if from + x >= strip.size():
				continue
			into[to + x] = strip[from + x]
