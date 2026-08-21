class_name Gen2UnownPuzzlePage
extends RefCounted

## `_UnownPuzzle`'s screen: the board tilemap and the two object sets over it.
##
## Node-free, so the whole board can be read back headless. The tile bank is
## built once per opened puzzle and the render is one index buffer.
##
## Four things the source states and a reading gets wrong:
##
## - **A puzzle picture is doubled, not drawn.** `ConvertLoadedPuzzlePieces`
##   enlarges the 6x6 strip into a 12x12 one by taking each nibble through
##   `.EnlargedTiles`, which is a two-times nearest scale of the whole picture:
##   destination tile `(2r + h, 2c + w)` is source tile `(r, c)`'s own quarter.
##   The sixteen three-by-three pieces are cut from that grid, so piece n's
##   corner tile is `((n - 1) / 4) * 36 + ((n - 1) % 4) * 3`, which is
##   `GetCurrentPuzzlePieceVTileCorner.Corners`.
## - **The borders are ORed onto the pieces, in bitplanes.**
##   `UnownPuzzle_AddPuzzlePieceBorders` runs `or [hl]` over the 2bpp bytes,
##   which is a bitwise OR of the colour index per pixel, and it reaches the
##   eight tiles around each piece's own centre rather than the picture's edge.
## - **The board is drawn in vTiles0 and so from tile $00.** `ld a, %10010011`
##   into `rLCDC` is the unsigned tile base, which is why a piece tile number is
##   a small one and START>CANCEL sits at the top of the bank.
## - **The cursor is red because of a palette write, not a tile.**
##   `_CGB_UnownPuzzle` copies PREDEFPAL_UNOWN_PUZZLE everywhere and then
##   overwrites object colour 0 with `palred 31`; `DmgToCgbObjPal0 $24` maps
##   colour 3 onto colour 0, so the cursor's own ink draws in it.

const TILE: int = Gen2Tiles.TILE_WIDTH
const TILE_PIXELS: int = Gen2Tiles.TILE_PIXELS
## `SCREEN_WIDTH` and `SCREEN_HEIGHT`.
const SCREEN_COLUMNS: int = 20
const SCREEN_ROWS: int = 18
const WIDTH: int = SCREEN_COLUMNS * TILE
const HEIGHT: int = SCREEN_ROWS * TILE
## The whole vTiles0 bank the board indexes into.
const BANK_TILES: int = 256

## `PUZZLE_BORDER` and `PUZZLE_VOID`, the two tiles a vacant cell is filled with.
const PUZZLE_BORDER: int = 0xEE
const PUZZLE_VOID: int = 0xEF
## `UnownPuzzleStartCancelLZ` goes to `vTiles0 tile $ed`, so the strip's own tile
## 0 is $ed and PUZZLE_BORDER and PUZZLE_VOID are its next two.
const START_CANCEL_FIRST_TILE: int = 0xED
## `UnownPuzzleCursorGFX` goes to `vTiles0 tile $e0`.
const CURSOR_FIRST_TILE: int = 0xE0

## The doubled picture: twelve tiles across, which is the stride a piece's own
## three-by-three block steps by.
const PICTURE_TILES: int = 12
## `.Corners`' own arithmetic.
const PIECE_TILES: int = 3
const PIECE_ROW_STRIDE: int = PICTURE_TILES * PIECE_TILES

## `PuzzlePieceBorderData`: which tile of a piece each of the eight border tiles
## is ORed onto, in the table's own order. The centre takes none.
const BORDER_PIECE_TILES: Array[int] = [0, 1, 2, 12, 14, 24, 25, 26]

## `UnownPuzzleCoordData`, one row per cell: the OAM point the cursor is centred
## on and the tilemap corner the three-by-three block is drawn at. The vacant
## tile is the ring's `PUZZLE_BORDER` or the inner square's `PUZZLE_VOID`, which
## is derivable from the cell and so is not carried.
const CELL_OAM_ORIGIN: Vector2i = Vector2i(3 * TILE + 4, 3 * TILE + 4)
const CELL_OAM_STEP: int = 3 * TILE
const CELL_MAP_ORIGIN: Vector2i = Vector2i(1, 0)
const CELL_MAP_STEP: int = 3

## `PlaceStartCancelBoxBorder`'s own tiles and corner, and the ten
## `PlaceStartCancelBox` writes into the row between them.
const BOX_CORNER: Vector2i = Vector2i(4, 15)
const BOX_INNER_COLUMNS: int = 10
const BOX_TOP_LEFT: int = 0xF0
const BOX_TOP: int = 0xF1
const BOX_TOP_RIGHT: int = 0xF2
const BOX_SIDE: int = 0xF3
const BOX_BOTTOM_LEFT: int = 0xF4
const BOX_BOTTOM_RIGHT: int = 0xF5
const BOX_TEXT_FIRST: int = 0xF6

## `.OAM_NotHoldingPiece` and `.OAM_HoldingPiece`, as
## (offset from the cell's point, tile, x flip, y flip). Both are three by three
## objects around the point; the empty cursor is four tiles mirrored into nine
## and the held piece is the piece's own nine.
const CURSOR_OBJECTS: Array[Array] = [
	[Vector2i(-12, -12), 0x00, false, false],
	[Vector2i(-4, -12), 0x01, false, false],
	[Vector2i(4, -12), 0x00, true, false],
	[Vector2i(-12, -4), 0x02, false, false],
	[Vector2i(-4, -4), 0x03, false, false],
	[Vector2i(4, -4), 0x02, true, false],
	[Vector2i(-12, 4), 0x00, false, true],
	[Vector2i(-4, 4), 0x01, false, true],
	[Vector2i(4, 4), 0x00, true, true],
]
const HELD_OBJECTS: Array[Array] = [
	[Vector2i(-12, -12), 0x00],
	[Vector2i(-4, -12), 0x01],
	[Vector2i(4, -12), 0x02],
	[Vector2i(-12, -4), 0x0C],
	[Vector2i(-4, -4), 0x0D],
	[Vector2i(4, -4), 0x0E],
	[Vector2i(-12, 4), 0x18],
	[Vector2i(-4, 4), 0x19],
	[Vector2i(4, 4), 0x1A],
]
## The hardware's own OAM offsets, which a shadow-OAM value carries.
const OAM_ORIGIN: Vector2i = Vector2i(8, 16)

## `DmgToCgbBGPals $e4` and `DmgToCgbObjPal0 $24`, the two `CopyPals` orders the
## screen is drawn through.
const BG_ORDER: int = 0xE4
const OBJECT_ORDER: int = 0x24
## `palred 31 + palgreen 0 + palblue 0`, written over object colour 0.
const CURSOR_COLOR: Color = Color(1.0, 0.0, 0.0, 1.0)

var _tiles: PackedByteArray = PackedByteArray()
var _background: PackedColorArray = PackedColorArray()
var _objects: PackedColorArray = PackedColorArray()


## The bank for one puzzle, [param puzzle] a `UNOWNPUZZLE_*` index.
## `maskbits NUM_UNOWN_PUZZLES` is what bounds it on the cartridge, so an
## operand outside the four wraps rather than failing.
static func from_data(data: GameData, puzzle: int) -> Gen2UnownPuzzlePage:
	if data == null or not data.has_unown_puzzle():
		return null
	var page := Gen2UnownPuzzlePage.new()
	var names: Array[String] = RomLayout.UNOWN_PUZZLE_PICTURES
	var picture: PackedByteArray = data.unown_puzzle_indices(
		names[posmod(puzzle, names.size())]
	)
	var borders: PackedByteArray = data.unown_puzzle_indices("tile_borders")
	var cursor: PackedByteArray = data.unown_puzzle_indices("cursor")
	var box: PackedByteArray = data.unown_puzzle_indices("start_cancel")
	var side: int = RomLayout.UNOWN_PUZZLE_PICTURE_TILES
	if picture.size() < side * side * TILE_PIXELS or borders.is_empty() \
		or cursor.is_empty() or box.is_empty():
		return null

	page._tiles.resize(BANK_TILES * TILE_PIXELS)
	page._load_picture(picture, side)
	page._add_piece_borders(borders)
	page._load_strip(cursor, CURSOR_FIRST_TILE)
	page._load_strip(box, START_CANCEL_FIRST_TILE)

	var palette: PackedColorArray = data.unown_puzzle_palette()
	if palette.size() < 4:
		return null
	page._background = Gen2WorldPalette.fade_palette(palette, BG_ORDER)
	var objects: PackedColorArray = palette.duplicate()
	objects[0] = CURSOR_COLOR
	page._objects = Gen2WorldPalette.fade_palette(objects, OBJECT_ORDER)
	return page


func ready() -> bool:
	return not _tiles.is_empty()


func background_palette() -> PackedColorArray:
	return _background


func object_palette() -> PackedColorArray:
	return _objects


## The bank, as one index strip [constant BANK_TILES] tiles wide. Kept for the
## check topic, which compares the doubling and the borders against the strips
## the cache holds.
func tile_indices(tile: int) -> PackedByteArray:
	if tile < 0 or tile >= BANK_TILES:
		return PackedByteArray()
	return _tiles.slice(tile * TILE_PIXELS, (tile + 1) * TILE_PIXELS)


## The whole screen for [param board]. [param frame] is `hVBlankCounter`, which
## is what the empty cursor blinks off; a board that has been solved has lost the
## START>CANCEL row and draws no objects at all, which is `PlaceStartCancelBoxBorder`
## and `ClearSprites` on the way out.
func render(board: Gen2UnownPuzzle, frame: int = Gen2UnownPuzzle.BLINK_MASK) -> Image:
	var map: PackedByteArray = tilemap(board)
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(WIDTH * HEIGHT)
	for row: int in SCREEN_ROWS:
		for column: int in SCREEN_COLUMNS:
			_blit(pixels, WIDTH, int(map[row * SCREEN_COLUMNS + column]),
				Vector2i(column * TILE, row * TILE))
	var image: Image = Gen2PicImage.from_indices(pixels, WIDTH, HEIGHT, _background)
	if board == null or not board.cursor_visible(frame):
		return image

	var sprites: PackedByteArray = PackedByteArray()
	sprites.resize(WIDTH * HEIGHT)
	var point: Vector2i = cell_point(board.cursor())
	if board.holding():
		var corner: int = piece_corner_tile(board.held_piece())
		for object: Array in HELD_OBJECTS:
			_blit(sprites, WIDTH, corner + int(object[1]), point + (object[0] as Vector2i))
	else:
		for object: Array in CURSOR_OBJECTS:
			_blit(
				sprites, WIDTH, CURSOR_FIRST_TILE + int(object[1]),
				point + (object[0] as Vector2i), bool(object[2]), bool(object[3])
			)
	image.blend_rect(
		Gen2PicImage.from_indices(sprites, WIDTH, HEIGHT, _objects, true),
		Rect2i(0, 0, WIDTH, HEIGHT), Vector2i.ZERO
	)
	return image


## `UnownPuzzle_UpdateTilemap` over a screen `ByteFill`ed with PUZZLE_BORDER and
## a twelve-by-twelve of PUZZLE_VOID, with `PlaceStartCancelBox` over the bottom.
func tilemap(board: Gen2UnownPuzzle) -> PackedByteArray:
	var map: PackedByteArray = PackedByteArray()
	map.resize(SCREEN_COLUMNS * SCREEN_ROWS)
	map.fill(PUZZLE_BORDER)
	for cell: int in Gen2UnownPuzzle.CELLS:
		var piece: int = board.piece_at(cell) if board != null else 0
		var at: Vector2i = cell_corner(cell)
		var corner: int = piece_corner_tile(piece) if piece > 0 else -1
		for row: int in PIECE_TILES:
			for column: int in PIECE_TILES:
				var tile: int = vacant_tile(cell)
				if corner >= 0:
					tile = corner + row * PICTURE_TILES + column
				var to: Vector2i = at + Vector2i(column, row)
				map[to.y * SCREEN_COLUMNS + to.x] = tile
	_place_box(map, board == null or board.box_text_visible())
	return map


## `PlaceStartCancelBoxBorder`, and `PlaceStartCancelBox`'s ten text tiles when
## the puzzle is still open. Solving it redraws the border alone, which leaves
## the row PUZZLE_VOID.
func _place_box(map: PackedByteArray, text: bool) -> void:
	var right: int = BOX_CORNER.x + BOX_INNER_COLUMNS + 1
	_write(map, Vector2i(BOX_CORNER.x, BOX_CORNER.y), BOX_TOP_LEFT)
	_write(map, Vector2i(right, BOX_CORNER.y), BOX_TOP_RIGHT)
	_write(map, Vector2i(BOX_CORNER.x, BOX_CORNER.y + 1), BOX_SIDE)
	_write(map, Vector2i(right, BOX_CORNER.y + 1), BOX_SIDE)
	_write(map, Vector2i(BOX_CORNER.x, BOX_CORNER.y + 2), BOX_BOTTOM_LEFT)
	_write(map, Vector2i(right, BOX_CORNER.y + 2), BOX_BOTTOM_RIGHT)
	for column: int in BOX_INNER_COLUMNS:
		var x: int = BOX_CORNER.x + 1 + column
		_write(map, Vector2i(x, BOX_CORNER.y), BOX_TOP)
		_write(map, Vector2i(x, BOX_CORNER.y + 1),
			BOX_TEXT_FIRST + column if text else PUZZLE_VOID)
		_write(map, Vector2i(x, BOX_CORNER.y + 2), BOX_TOP)


func _write(map: PackedByteArray, at: Vector2i, tile: int) -> void:
	map[at.y * SCREEN_COLUMNS + at.x] = tile


## `GetUnownPuzzleCoordData`'s filler column: the inner four by four is
## PUZZLE_VOID and the ring around it PUZZLE_BORDER.
static func vacant_tile(cell: int) -> int:
	var row: int = cell / Gen2UnownPuzzle.COLUMNS
	var column: int = cell % Gen2UnownPuzzle.COLUMNS
	var inner: bool = row >= 1 and row <= Gen2UnownPuzzle.PIECE_COLUMNS \
		and column >= 1 and column <= Gen2UnownPuzzle.PIECE_COLUMNS
	return PUZZLE_VOID if inner else PUZZLE_BORDER


## The cell's tilemap corner, `dwcoord`'s own column of `UnownPuzzleCoordData`.
static func cell_corner(cell: int) -> Vector2i:
	return CELL_MAP_ORIGIN + Vector2i(
		(cell % Gen2UnownPuzzle.COLUMNS) * CELL_MAP_STEP,
		(cell / Gen2UnownPuzzle.COLUMNS) * CELL_MAP_STEP
	)


## The cell's OAM point in screen pixels, `dbpixel`'s own column with the
## hardware's offsets taken back off.
static func cell_point(cell: int) -> Vector2i:
	return CELL_OAM_ORIGIN - OAM_ORIGIN + Vector2i(
		(cell % Gen2UnownPuzzle.COLUMNS) * CELL_OAM_STEP,
		(cell / Gen2UnownPuzzle.COLUMNS) * CELL_OAM_STEP
	)


## `GetCurrentPuzzlePieceVTileCorner.Corners` as the arithmetic it is.
static func piece_corner_tile(piece: int) -> int:
	if piece < 1 or piece > Gen2UnownPuzzle.PIECES:
		return CURSOR_FIRST_TILE
	var index: int = piece - 1
	return (index / Gen2UnownPuzzle.PIECE_COLUMNS) * PIECE_ROW_STRIDE \
		+ (index % Gen2UnownPuzzle.PIECE_COLUMNS) * PIECE_TILES


## `ConvertLoadedPuzzlePieces`, which is a two-times nearest scale of the
## picture into the twelve-by-twelve grid the pieces are cut from.
## The cache holds a picture as a strip of `side * side` tiles side by side and
## eight rows tall, not as a square, so a source pixel is found through its own
## tile rather than through a row of 48.
func _load_picture(picture: PackedByteArray, side: int) -> void:
	var stride: int = side * side * TILE
	var pixels: int = side * TILE
	for y: int in pixels * 2:
		for x: int in pixels * 2:
			var from_x: int = x >> 1
			var from_y: int = y >> 1
			var from: int = (from_y % TILE) * stride \
				+ ((from_y / TILE) * side + from_x / TILE) * TILE + from_x % TILE
			var tile: int = (y / TILE) * PICTURE_TILES + x / TILE
			_tiles[tile * TILE_PIXELS + (y % TILE) * TILE + x % TILE] = int(picture[from])


## `UnownPuzzle_AddPuzzlePieceBorders`: eight tiles ORed onto the eight around
## every piece's own centre, `or [hl]` on the bitplanes being a bitwise OR of the
## colour index.
func _add_piece_borders(borders: PackedByteArray) -> void:
	var count: int = borders.size() / (TILE * TILE)
	for index: int in mini(count, BORDER_PIECE_TILES.size()):
		for piece: int in range(1, Gen2UnownPuzzle.PIECES + 1):
			var tile: int = piece_corner_tile(piece) + BORDER_PIECE_TILES[index]
			for y: int in TILE:
				for x: int in TILE:
					var at: int = tile * TILE_PIXELS + y * TILE + x
					_tiles[at] = int(_tiles[at]) | int(borders[y * count * TILE + index * TILE + x])


## One decoded strip into the bank from [param first], which is the
## `ld de, vTiles0 tile $xx` each `Decompress` or `CopyBytes` is handed.
func _load_strip(strip: PackedByteArray, first: int) -> void:
	var count: int = strip.size() / (TILE * TILE)
	for tile: int in count:
		if first + tile >= BANK_TILES:
			break
		for y: int in TILE:
			for x: int in TILE:
				_tiles[(first + tile) * TILE_PIXELS + y * TILE + x] = \
					strip[y * count * TILE + tile * TILE + x]


## One tile into an index buffer, with the two OAM flips a cursor object carries.
func _blit(
	buffer: PackedByteArray, width: int, tile: int, at: Vector2i,
	flip_x: bool = false, flip_y: bool = false
) -> void:
	if tile < 0 or tile >= BANK_TILES:
		return
	var base: int = tile * TILE_PIXELS
	for y: int in TILE:
		var to_y: int = at.y + y
		if to_y < 0 or to_y >= HEIGHT:
			continue
		var from_y: int = TILE - 1 - y if flip_y else y
		for x: int in TILE:
			var to_x: int = at.x + x
			if to_x < 0 or to_x >= width:
				continue
			var from_x: int = TILE - 1 - x if flip_x else x
			buffer[to_y * width + to_x] = _tiles[base + from_y * TILE + from_x]
