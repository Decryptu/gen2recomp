class_name Gen2Font
extends RefCounted

## The cartridge's own font, drawn a tile at a time.
##
## Text here is tilemapped, not typeset: every character is one 8x8 tile of equal
## width, and a character code is already the tile number that draws it. Nothing
## is measured or kerned; indices are copied into a buffer at multiples of eight.
##
## Every sheet is one row of tiles ([method Gen2Tiles.decode_1bpp_strip]), so a
## code is a horizontal offset and nothing else. A code with no tile draws
## nothing rather than a placeholder, which is what the space at $7F is and what
## the hardware does.
##
## Three sheets, because the hardware has three loaded at once and one of them
## changes. The main font covers $80 upward and the frames $79 to $7E in both
## strips; `_LoadFontsBattleExtra` replaces $60 to $78, which is where `№`,
## `<ID>` and `<LV>` live. Which of the two is up is [Gen2Text]'s font argument,
## carried through to the tile it addresses, so a caller says which screen it is
## drawing rather than which sheet a byte came from.
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

var _battle_extra: PackedByteArray = PackedByteArray()
var _battle_extra_width: int = 0
var _battle_extra_tiles: int = 0

## `FontExtra`, which `_LoadFontsExtra1` parks under the main font's own $80
## floor: the ellipsis, the two quotes, the middle dot and `<COLON>` all draw
## from here, and nothing else in this project can draw them.
var _extra: PackedByteArray = PackedByteArray()
var _extra_width: int = 0
var _extra_tiles: int = 0


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

	# Optional: a font with no battle-extra strip draws the main run and refuses
	# the other, which is what a cache written before this was read back holds.
	var battle_extra: Dictionary = data.tile_sheet("battle_font")
	out._battle_extra = data.tile_indices("battle_font")
	out._battle_extra_width = int(battle_extra.get("width", 0))
	out._battle_extra_tiles = int(battle_extra.get("tiles", 0))

	# Optional for the same reason.
	var extra: Dictionary = data.tile_sheet("font_extra")
	out._extra = data.tile_indices("font_extra")
	out._extra_width = int(extra.get("width", 0))
	out._extra_tiles = int(extra.get("tiles", 0))

	return out if out.is_usable() else null


func is_usable() -> bool:
	return _glyph_width > 0 and _glyphs.size() >= _glyph_width * TILE


func frame_count() -> int:
	if RomLayout.FRAME_TILES <= 0:
		return 0
	@warning_ignore("integer_division")
	return _frame_tiles / RomLayout.FRAME_TILES


## Whether the battle-extra strip was in the cache this was read from.
func has_battle_extra() -> bool:
	return _battle_extra_width > 0 and _battle_extra_tiles > 0


## Draws one character code at a tile position, in pixels from the top left.
## A code with no tile draws nothing, which is what a space is.
##
## [param font] says which strip is loaded. Under
## [constant Gen2Text.FONT_BATTLE_EXTRA] a code in $60 to $78 comes off the
## battle-extra sheet; everything else comes off the main font either way,
## because that load replaces only those tiles.
func draw_code(
	code: int, into: PackedByteArray, into_width: int, at_x: int, at_y: int,
	font: StringName = Gen2Text.FONT_MAIN
) -> void:
	if font == Gen2Text.FONT_BATTLE_EXTRA \
		and code >= Gen2Text.BATTLE_EXTRA_FIRST_CODE \
		and code <= Gen2Text.BATTLE_EXTRA_LAST_CODE:
		var within: int = code - RomLayout.BATTLE_FONT_FIRST_CODE
		if within < 0 or within >= _battle_extra_tiles:
			return
		blit_slot(_battle_extra, _battle_extra_width, within, into, into_width, at_x, at_y)
		return
	# `_LoadFontsExtra1`'s own run, which is under the main font everywhere the
	# battle's strip is not: a code below the font's $80 draws from FontExtra.
	if code >= RomLayout.FONT_EXTRA_LOADED_FIRST \
		and code <= RomLayout.FONT_EXTRA_LOADED_LAST:
		var extra_slot: int = code - RomLayout.FONT_EXTRA_FIRST_CODE
		if extra_slot < _extra_tiles:
			blit_slot(_extra, _extra_width, extra_slot, into, into_width, at_x, at_y)
		return
	var slot: int = code - _first_code
	if slot < 0 or slot >= _glyph_tiles:
		return
	blit_slot(_glyphs, _glyph_width, slot, into, into_width, at_x, at_y)


## Draws a string left to right from [param at_x], advancing eight pixels per
## tile. Returns how many tiles were drawn, which is not the string's length
## when it contains a ligature.
##
## [param max_tiles] stops the run short. `PlaceString` has no such bound and
## needs none: every cartridge string is written to fit the box it is placed in.
## A label a mod supplies is not, so a caller drawing into a fixed width passes
## the room it has and the rest of the string is dropped rather than written
## over whatever is beside the box. Negative means no bound.
func draw_text(
	text: String, into: PackedByteArray, into_width: int, at_x: int, at_y: int,
	font: StringName = Gen2Text.FONT_MAIN, max_tiles: int = -1
) -> int:
	var codes: PackedByteArray = Gen2Text.encode(text, font)
	var drawn: int = codes.size() if max_tiles < 0 else mini(codes.size(), max_tiles)
	for i: int in drawn:
		draw_code(codes[i], into, into_width, at_x + i * TILE, at_y, font)
	return drawn


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


## A whole box border, [param columns] by [param rows] tiles with its top-left
## at [param at_x]/[param at_y] in pixels. The right-hand side reuses the same
## vertical tile as the left and the bottom edge reuses the top's horizontal: a
## frame is six tiles, not eight, and the two it does not have are the two the
## hardware never needed.
func draw_box(
	frame: int,
	into: PackedByteArray,
	into_width: int,
	at_x: int,
	at_y: int,
	columns: int,
	rows: int
) -> void:
	if columns < 2 or rows < 2:
		return
	var right: int = at_x + (columns - 1) * TILE
	var bottom: int = at_y + (rows - 1) * TILE
	var vertical: int = RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_VERTICAL
	var horizontal: int = RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_HORIZONTAL

	draw_frame_code(
		frame, RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TOP_LEFT,
		into, into_width, at_x, at_y
	)
	draw_frame_code(
		frame, RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TOP_RIGHT,
		into, into_width, right, at_y
	)
	draw_frame_code(
		frame, RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_BOTTOM_LEFT,
		into, into_width, at_x, bottom
	)
	draw_frame_code(
		frame, RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_BOTTOM_RIGHT,
		into, into_width, right, bottom
	)
	for column: int in range(1, columns - 1):
		var x: int = at_x + column * TILE
		draw_frame_code(frame, horizontal, into, into_width, x, at_y)
		draw_frame_code(frame, horizontal, into, into_width, x, bottom)
	for row: int in range(1, rows - 1):
		var y: int = at_y + row * TILE
		draw_frame_code(frame, vertical, into, into_width, at_x, y)
		draw_frame_code(frame, vertical, into, into_width, right, y)


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
