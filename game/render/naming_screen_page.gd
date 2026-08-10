class_name Gen2NamingScreenPage
extends RefCounted

## `engine/menus/naming_screen.asm`'s screen on the hardware tile grid.
##
## The naming screen is a tilemap screen rather than a text one, the way the
## trainer card is, so the page keeps the cartridge's own VRAM window and writes
## tile numbers into a map: $60 the border `LoadNamingScreenGFX` copies over the
## font-extra slot, $eb and $f2 the two entry markers, and the font from $80 up.
##
## Positions are `NamingScreen_InitText` and `NamingScreen_ApplyTextInputMode`'s
## own. The layout is the same shape on both keyboards and differs only in where
## the two `ClearBox` calls land and how many rows are printed, which is the
## whole of `NamingScreen_IsTargetBox` here.
##
## Node-free: it writes indices into a buffer, so a page can be drawn and read
## back headless.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

## `NAMINGSCREEN_BORDER`, `NAMINGSCREEN_MIDDLELINE` and `NAMINGSCREEN_UNDERLINE`.
## The border replaces the font-extra tile at $60 and the two markers replace
## `→` and `.`, which is why neither code can be typed on any keyboard.
const BORDER_TILE: int = 0x60
const MIDDLE_LINE_TILE: int = Gen2NamingScreen.MIDDLELINE
const UNDER_LINE_TILE: int = Gen2NamingScreen.UNDERLINE
## `NAMINGSCREEN_CURSOR`, the two tiles the bracket is built from: a corner and
## the edge that runs between two corners. They are kept apart from the
## background window rather than beside it, because the cartridge loads them
## into `vTiles0` as sprites and $7f is the blank every cleared tile already is.
const CURSOR_CORNER_TILE: int = 0
const CURSOR_EDGE_TILE: int = 1

## `hlcoord 5, 2`, shared by every naming screen type.
const PROMPT_AT: Vector2i = Vector2i(5, 2)
## `.StoreSpriteIconParams`' `hlcoord 5, 6` against `.StoreBoxIconParams`'
## `hlcoord 5, 4`.
const ENTRY_AT_NAME: Vector2i = Vector2i(5, 6)
const ENTRY_AT_BOX: Vector2i = Vector2i(5, 4)
## `hlcoord 2, 8` and `hlcoord 2, 6`: where the live keyboard's first row prints.
const KEYBOARD_LEFT: int = 2
const KEYBOARD_TOP_NAME: int = 8
const KEYBOARD_TOP_BOX: int = 6
## The cursor steps two tiles per column and two per row, so a keyboard cell is
## two tiles wide even where its character is one.
const CELL: int = 2
## `.OAMData_TextEntryCursor`'s four sprites against
## `.OAMData_TextEntryCursorBig`'s ten: a 2x2 bracket over a letter and a 5x2
## one over a command, which is what makes UPPER fit inside it.
const COMMAND_CURSOR_WIDTH: int = 5
## `.CaseDelEnd` snaps the cursor to $00, $30 and $60, which is six tiles apart.
const COMMAND_CURSOR_STEP: int = 6

## `NamingScreen_InitText`'s and `NamingScreen_ApplyTextInputMode`'s `ClearBox`
## calls, as x, y, rows, columns. The last of each pair is the keyboard's own
## bottom row, cleared separately because the run above it stops short of it.
const CLEARED_NAME: Array = [[1, 1, 6, 18], [1, 8, 7, 18], [1, 16, 1, 18]]
const CLEARED_BOX: Array = [[1, 1, 4, 18], [1, 6, 9, 18], [1, 16, 1, 18]]

const BLANK_TILE: int = -1

var font: Gen2Font = null

var _tiles: Dictionary = {}
var _cursor_tiles: Dictionary = {}


static func from_data(data: GameData) -> Gen2NamingScreenPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null or data == null:
		return null
	var out := Gen2NamingScreenPage.new()
	out.font = glyphs
	out._load_sheet(data, "naming_border", out._tiles, BORDER_TILE, RomLayout.NAMING_BORDER_TILES)
	out._load_sheet(
		data, "naming_middle_line", out._tiles, MIDDLE_LINE_TILE, RomLayout.NAMING_MARKER_TILES
	)
	out._load_sheet(
		data, "naming_under_line", out._tiles, UNDER_LINE_TILE, RomLayout.NAMING_MARKER_TILES
	)
	out._load_sheet(
		data, "naming_cursor", out._cursor_tiles, CURSOR_CORNER_TILE, RomLayout.NAMING_CURSOR_TILES
	)
	return out


## Whether the cache carried every sheet this page needs.
func ready() -> bool:
	return font != null and _tiles.size() == 3 and _cursor_tiles.size() == 2


## The whole 160x144 page as palette indices, for [param screen] as it stands
## and the prompt printed above the entry.
func draw(screen: Gen2NamingScreen, prompt: String) -> PackedByteArray:
	var map: PackedInt32Array = PackedInt32Array()
	map.resize(COLUMNS * ROWS)
	map.fill(BORDER_TILE)
	for box: Array in (CLEARED_BOX if screen.is_box else CLEARED_NAME):
		_clear(map, int(box[0]), int(box[1]), int(box[2]), int(box[3]))

	_string(map, prompt, PROMPT_AT)
	_entry(map, screen)
	_keyboard(map, screen)

	var indices: PackedByteArray = _compose(map)
	_cursor(indices, screen)
	return indices


## The name being typed, printed as the raw buffer rather than as text: the two
## markers are tiles, not characters, and `.UpdateStringEntry` prints the whole
## buffer every frame rather than only what has been entered.
func _entry(map: PackedInt32Array, screen: Gen2NamingScreen) -> void:
	var at: Vector2i = ENTRY_AT_BOX if screen.is_box else ENTRY_AT_NAME
	for index: int in screen.max_length:
		_put(map, at + Vector2i(index, 0), screen.buffer[index])


## The live keyboard, 17 tiles a row two rows apart, which is what
## `NamingScreen_ApplyTextInputMode`'s `ld de, 2 * SCREEN_WIDTH - $11` steps.
func _keyboard(map: PackedInt32Array, screen: Gen2NamingScreen) -> void:
	var top: int = KEYBOARD_TOP_BOX if screen.is_box else KEYBOARD_TOP_NAME
	var rows: Array = screen.rows()
	for row: int in rows.size():
		var codes: Array = rows[row]
		for column: int in codes.size():
			_put(map, Vector2i(KEYBOARD_LEFT + column, top + row * CELL), int(codes[column]))


## The bracket over whatever the cursor is on. A letter takes the plain
## frameset, the command row the big one, and `NamingScreen_AnimateCursor` snaps
## the big one to its command group rather than leaving it on the raw column.
func _cursor(indices: PackedByteArray, screen: Gen2NamingScreen) -> void:
	var top: int = KEYBOARD_TOP_BOX if screen.is_box else KEYBOARD_TOP_NAME
	var at := Vector2i(
		KEYBOARD_LEFT + screen.column * CELL, top + screen.row * CELL
	)
	var width: int = CELL
	var command: int = screen.cursor_command()
	if command != Gen2NamingScreen.COMMAND_NONE:
		width = COMMAND_CURSOR_WIDTH
		at.x = KEYBOARD_LEFT + (command - 1) * COMMAND_CURSOR_STEP
	_bracket(indices, at, width)


## Four corners of the same tile flipped into place, with the edge tile running
## between them along the top and bottom rows.
func _bracket(indices: PackedByteArray, at: Vector2i, width: int) -> void:
	for column: int in width:
		var left_edge: bool = column == 0
		var right_edge: bool = column == width - 1
		var tile: int = CURSOR_CORNER_TILE if left_edge or right_edge else CURSOR_EDGE_TILE
		_blit(indices, _cursor_tiles, tile, at + Vector2i(column, 0), right_edge, false, true)
		_blit(indices, _cursor_tiles, tile, at + Vector2i(column, 1), right_edge, true, true)


func _clear(map: PackedInt32Array, x: int, y: int, rows: int, columns: int) -> void:
	for row: int in rows:
		for column: int in columns:
			_put(map, Vector2i(x + column, y + row), BLANK_TILE)


func _string(map: PackedInt32Array, text: String, at: Vector2i) -> void:
	var codes: PackedByteArray = Gen2Text.encode(text)
	for index: int in codes.size():
		_put(map, at + Vector2i(index, 0), codes[index])


func _put(map: PackedInt32Array, at: Vector2i, tile: int) -> void:
	if at.x < 0 or at.x >= COLUMNS or at.y < 0 or at.y >= ROWS:
		return
	map[at.y * COLUMNS + at.x] = tile


## Resolves every tile number to pixels: the screen's own graphics out of the
## VRAM window, everything else out of the font.
func _compose(map: PackedInt32Array) -> PackedByteArray:
	var width: int = COLUMNS * TILE
	var indices := PackedByteArray()
	indices.resize(width * ROWS * TILE)
	if font == null:
		return indices
	for row: int in ROWS:
		for column: int in COLUMNS:
			var tile: int = map[row * COLUMNS + column]
			if _tiles.has(tile):
				_blit(indices, _tiles, tile, Vector2i(column, row), false, false)
			elif tile != BLANK_TILE:
				font.draw_code(tile, indices, width, column * TILE, row * TILE)
	return indices


func _load_sheet(
	data: GameData, name: String, into: Dictionary, first_tile: int, count: int
) -> void:
	var indices: PackedByteArray = data.tile_indices(name)
	if indices.is_empty():
		return
	var width: int = indices.size() / TILE
	for tile: int in count:
		if (tile + 1) * TILE > width:
			break
		var cell := PackedByteArray()
		cell.resize(TILE * TILE)
		for y: int in TILE:
			for x: int in TILE:
				cell[y * TILE + x] = indices[y * width + tile * TILE + x]
		into[first_tile + tile] = cell


## One cached tile into the page, with the OAM flips the cursor's own bracket
## needs; everything else is drawn unflipped. [param transparent] is what makes
## the bracket a frame rather than a box: the cursor is an object, and index 0
## of an object is see-through, so the letter under it stays readable.
func _blit(
	indices: PackedByteArray, source: Dictionary, tile: int, at: Vector2i,
	flip_x: bool, flip_y: bool, transparent: bool = false
) -> void:
	if not source.has(tile):
		return
	var cell: PackedByteArray = source[tile]
	var width: int = COLUMNS * TILE
	for y: int in TILE:
		for x: int in TILE:
			var source_x: int = TILE - 1 - x if flip_x else x
			var source_y: int = TILE - 1 - y if flip_y else y
			var index: int = cell[source_y * TILE + source_x]
			if transparent and index == 0:
				continue
			var to: int = (at.y * TILE + y) * width + at.x * TILE + x
			if to >= 0 and to < indices.size():
				indices[to] = index
