extends RefCounted

## Sweeps `_UnownPuzzle` on freshly imported real caches, all three cartridges,
## all four pictures, all thirty-six cells and all sixteen pieces.
##
## Every expectation below is transcribed from pokecrystal's own
## engine/games/unown_puzzle.asm rather than read back out of the
## implementation, which is the only way the topic can go red: the corners, the
## solved configuration, the two OAM sets and the cursor's own hand-listed edges
## are the source's tables, and the art is re-read out of the dump beside the
## cache rather than compared with itself.
##
## The class of bug it exists to catch is the doubling. `ConvertLoadedPuzzlePieces`
## and `UnownPuzzle_AddPuzzlePieceBorders` are two passes over one strip, and a
## picture that is off by a nibble, a half-tile or a bitplane still draws
## something. So the check asserts the pixel identity per piece rather than a
## checksum: 144 tiles a picture, four pictures, three cartridges.
##
##   Godot --headless --path . -s res://tools/validate.gd -- unown_puzzle

const TILE: int = Gen2Tiles.TILE_WIDTH

## `.Corners`, the sixteen `GetCurrentPuzzlePieceVTileCorner` answers for pieces
## 1 to 16, and its own `$e0` for none.
const CORNERS: Array[int] = [
	0x00, 0x03, 0x06, 0x09,
	0x24, 0x27, 0x2A, 0x2D,
	0x48, 0x4B, 0x4E, 0x51,
	0x6C, 0x6F, 0x72, 0x75,
]
const NO_PIECE_CORNER: int = 0xE0

## `.SolvedPuzzleConfiguration`, byte for byte.
const SOLVED: Array[int] = [
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x01, 0x02, 0x03, 0x04, 0x00,
	0x00, 0x05, 0x06, 0x07, 0x08, 0x00,
	0x00, 0x09, 0x0A, 0x0B, 0x0C, 0x00,
	0x00, 0x0D, 0x0E, 0x0F, 0x10, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]

## `PuzzlePieceBorderData`'s destinations, and the one tile of a piece it leaves
## alone.
const BORDERED: Array[int] = [0x00, 0x01, 0x02, 0x0C, 0x0E, 0x18, 0x19, 0x1A]
const UNBORDERED_CENTRE: int = 0x0D

## `UnownPuzzleCoordData`'s tilemap column, `dwcoord x, y` per cell.
const MAP_COORDS: Array[Array] = [
	[1, 0], [4, 0], [7, 0], [10, 0], [13, 0], [16, 0],
	[1, 3], [4, 3], [7, 3], [10, 3], [13, 3], [16, 3],
	[1, 6], [4, 6], [7, 6], [10, 6], [13, 6], [16, 6],
	[1, 9], [4, 9], [7, 9], [10, 9], [13, 9], [16, 9],
	[1, 12], [4, 12], [7, 12], [10, 12], [13, 12], [16, 12],
	[1, 15], [4, 15], [7, 15], [10, 15], [13, 15], [16, 15],
]
## Its `dbpixel x, y, 4, 4` column, as the OAM bytes the macro emits.
const OAM_COORDS: Array[Array] = [
	[28, 28], [52, 28], [76, 28], [100, 28], [124, 28], [148, 28],
	[28, 52], [52, 52], [76, 52], [100, 52], [124, 52], [148, 52],
	[28, 76], [52, 76], [76, 76], [100, 76], [124, 76], [148, 76],
	[28, 100], [52, 100], [76, 100], [100, 100], [124, 100], [148, 100],
	[28, 124], [52, 124], [76, 124], [100, 124], [124, 124], [148, 124],
	[28, 148], [52, 148], [76, 148], [100, 148], [124, 148], [148, 148],
]
## Its own filler column: PUZZLE_BORDER for the ring, PUZZLE_VOID for the square.
const VACANT: Array[int] = [
	0xEE, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE,
	0xEE, 0xEF, 0xEF, 0xEF, 0xEF, 0xEE,
	0xEE, 0xEF, 0xEF, 0xEF, 0xEF, 0xEE,
	0xEE, 0xEF, 0xEF, 0xEF, 0xEF, 0xEE,
	0xEE, 0xEF, 0xEF, 0xEF, 0xEF, 0xEE,
	0xEE, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE,
]

## The strips the section carries and the tile count each is copied into VRAM as.
const STRIPS: Dictionary = {
	"tile_borders": 8, "cursor": 4, "start_cancel": 19,
	"hooh": 36, "aerodactyl": 36, "kabuto": 36, "omanyte": 36,
}

## `.d_up`, `.d_down`, `.d_left` and `.d_right` restated as the cells each
## refuses. Everything else steps by six or by one, less the two overflows.
const NO_STEP_UP: Array[int] = [0, 1, 2, 3, 4, 5]
const NO_STEP_DOWN: Array[int] = [25, 26, 27, 28, 30, 31, 32, 33, 34, 35]
const NO_STEP_LEFT: Array[int] = [0, 6, 12, 18, 24, 30]
const NO_STEP_RIGHT: Array[int] = [5, 11, 17, 23, 29, 35]

var _r: RefCounted = null


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		if not _r.check(
			data.has_unown_puzzle(), "%s: no Unown puzzle art in the cache." % game_id
		):
			continue
		_verify_section(game_id, data)
		_verify_palette(game_id, data)
		for puzzle: int in RomLayout.UNOWN_PUZZLE_PICTURES.size():
			_verify_bank(game_id, data, puzzle)
			_verify_board(game_id, data, puzzle)
	_r.game_id = &""
	_verify_rules()


## The cache against a second reading of the dump, which is what says the walk
## found the records rather than seven runs that happen to decompress.
func _verify_section(game_id: StringName, data: GameData) -> void:
	var rom: RomFile = RomFile.open_verified("res://roms/%s.gbc" % game_id)
	if not _r.check(rom != null, "%s: roms/%s.gbc is unreadable." % [game_id, game_id]):
		return
	var section: Dictionary = RomImporter.read_unown_puzzle_section(
		rom, RomLayout.for_id(rom.id)
	)
	if not _r.check(
		section.size() == STRIPS.size(),
		"%s: the puzzle section walked %d records, not %d." % [
			game_id, section.size(), STRIPS.size()
		]
	):
		return
	for name: String in STRIPS:
		var tiles: int = int(STRIPS[name])
		_r.check(
			int(section[name].size()) == tiles * Gen2Tiles.TILE_BYTES,
			"%s: %s is %d bytes, not %d tiles." % [
				game_id, name, section[name].size(), tiles
			]
		)
		_r.check(
			data.unown_puzzle_indices(name) == Gen2Tiles.decode_2bpp_strip(
				section[name], 0, tiles
			),
			"%s: the cached %s strip is not the dump's." % [game_id, name]
		)
	_r.note("%s: %d puzzle records, %d tiles." % [
		game_id, STRIPS.size(), _total_tiles()
	])


## `_CGB_UnownPuzzle`: one predef palette everywhere, and object colour 0 red.
func _verify_palette(game_id: StringName, data: GameData) -> void:
	var palette: PackedColorArray = data.unown_puzzle_palette()
	if not _r.check(
		palette.size() == RomLayout.PREDEF_PALETTE_COLORS,
		"%s: the puzzle palette has %d colours." % [game_id, palette.size()]
	):
		return
	var page: Gen2UnownPuzzlePage = Gen2UnownPuzzlePage.from_data(data, 0)
	if not _r.check(page != null, "%s: the puzzle page will not build." % game_id):
		return
	## `DmgToCgbBGPals $e4` is the identity, so the background is the entry as
	## imported.
	_r.check(
		page.background_palette() == palette,
		"%s: the background palette is not PREDEFPAL_UNOWN_PUZZLE." % game_id
	)
	var objects: PackedColorArray = page.object_palette()
	_r.check(
		objects.size() == 4 and objects[0] == Gen2UnownPuzzlePage.CURSOR_COLOR
			and objects[3] == Gen2UnownPuzzlePage.CURSOR_COLOR
			and objects[1] == palette[1] and objects[2] == palette[2],
		"%s: `DmgToCgbObjPal0 $24` over the red colour 0 is not what the cursor draws in." % game_id
	)


## `ConvertLoadedPuzzlePieces` and `UnownPuzzle_AddPuzzlePieceBorders`, per
## pixel, against the strip the cache holds rather than against the bank.
func _verify_bank(game_id: StringName, data: GameData, puzzle: int) -> void:
	var name: String = RomLayout.UNOWN_PUZZLE_PICTURES[puzzle]
	var page: Gen2UnownPuzzlePage = Gen2UnownPuzzlePage.from_data(data, puzzle)
	if not _r.check(page != null, "%s: %s will not build a bank." % [game_id, name]):
		return
	var picture: PackedByteArray = data.unown_puzzle_indices(name)
	var borders: PackedByteArray = data.unown_puzzle_indices("tile_borders")
	var side: int = RomLayout.UNOWN_PUZZLE_PICTURE_TILES
	var wrong_pixels: int = 0
	var wrong_borders: int = 0
	for piece: int in Gen2UnownPuzzle.PIECES:
		var corner: int = CORNERS[piece]
		for local: int in Gen2UnownPuzzlePage.PIECE_TILES * Gen2UnownPuzzlePage.PICTURE_TILES:
			var row: int = local / Gen2UnownPuzzlePage.PICTURE_TILES
			var column: int = local % Gen2UnownPuzzlePage.PICTURE_TILES
			if row >= Gen2UnownPuzzlePage.PIECE_TILES \
				or column >= Gen2UnownPuzzlePage.PIECE_TILES:
				continue
			var offset: int = row * Gen2UnownPuzzlePage.PICTURE_TILES + column
			var tile: PackedByteArray = page.tile_indices(corner + offset)
			## Where this tile sits in the doubled twelve-by-twelve grid.
			var grid: int = corner + offset
			var grid_row: int = grid / Gen2UnownPuzzlePage.PICTURE_TILES
			var grid_column: int = grid % Gen2UnownPuzzlePage.PICTURE_TILES
			var border: int = _border_for(offset)
			for y: int in TILE:
				for x: int in TILE:
					## The source pixel this one is a quarter of.
					var from_x: int = (grid_column * TILE + x) / 2
					var from_y: int = (grid_row * TILE + y) / 2
					var wanted: int = int(picture[_strip_at(from_x, from_y, side)])
					if border >= 0:
						wanted |= int(borders[y * STRIPS["tile_borders"] * TILE
							+ border * TILE + x])
					if int(tile[y * TILE + x]) != wanted:
						if border >= 0:
							wrong_borders += 1
						else:
							wrong_pixels += 1
	_r.check(
		wrong_pixels == 0,
		"%s: %s doubles %d pixels wrong." % [game_id, name, wrong_pixels]
	)
	_r.check(
		wrong_borders == 0,
		"%s: %s borders %d pixels wrong." % [game_id, name, wrong_borders]
	)
	## The centre tile takes no border, which is what says the eight destinations
	## are the eight and not the whole block.
	var centre: PackedByteArray = page.tile_indices(CORNERS[0] + UNBORDERED_CENTRE)
	var plain: bool = true
	for y: int in TILE:
		for x: int in TILE:
			if int(centre[y * TILE + x]) != int(picture[_strip_at(
				(UNBORDERED_CENTRE % Gen2UnownPuzzlePage.PICTURE_TILES) * TILE / 2 + x / 2,
				(UNBORDERED_CENTRE / Gen2UnownPuzzlePage.PICTURE_TILES) * TILE / 2 + y / 2,
				side
			)]):
				plain = false
	_r.check(plain, "%s: %s ORs a border onto a piece's centre tile." % [game_id, name])


## A pixel of the source picture, which the cache holds as one strip of
## `side * side` tiles.
func _strip_at(x: int, y: int, side: int) -> int:
	var tile: int = (y / TILE) * side + x / TILE
	return (y % TILE) * side * side * TILE + tile * TILE + x % TILE


## Which border tile, if any, a piece-local tile takes.
func _border_for(local: int) -> int:
	return BORDERED.find(local)


## `UnownPuzzle_UpdateTilemap` and `PlaceStartCancelBox` over a whole board, in
## both the scattered and the solved configuration.
func _verify_board(game_id: StringName, data: GameData, puzzle: int) -> void:
	var name: String = RomLayout.UNOWN_PUZZLE_PICTURES[puzzle]
	var page: Gen2UnownPuzzlePage = Gen2UnownPuzzlePage.from_data(data, puzzle)
	if page == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = puzzle + 1
	var board: Gen2UnownPuzzle = Gen2UnownPuzzle.create(rng)
	var placed: Array[int] = []
	for cell: int in Gen2UnownPuzzle.CELLS:
		var piece: int = board.piece_at(cell)
		if piece == 0:
			continue
		placed.append(piece)
		_r.check(
			cell in Gen2UnownPuzzle.START_CELLS,
			"%s: %s scattered a piece onto cell %d." % [game_id, name, cell]
		)
	placed.sort()
	_r.check(
		placed.size() == Gen2UnownPuzzle.PIECES
			and placed[0] == 1 and placed[-1] == Gen2UnownPuzzle.PIECES,
		"%s: %s scattered %d pieces." % [game_id, name, placed.size()]
	)

	var map: PackedByteArray = page.tilemap(board)
	var outside: int = 0
	for cell: int in Gen2UnownPuzzle.CELLS:
		var at: Array = MAP_COORDS[cell]
		var piece: int = board.piece_at(cell)
		for row: int in Gen2UnownPuzzlePage.PIECE_TILES:
			for column: int in Gen2UnownPuzzlePage.PIECE_TILES:
				var x: int = int(at[0]) + column
				var y: int = int(at[1]) + row
				if y >= 15:
					## The START>CANCEL box is placed over the bottom row after
					## the cells are, so those tiles are the box's own.
					continue
				var wanted: int = VACANT[cell] if piece == 0 else CORNERS[piece - 1] \
					+ row * Gen2UnownPuzzlePage.PICTURE_TILES + column
				if int(map[y * Gen2UnownPuzzlePage.SCREEN_COLUMNS + x]) != wanted:
					outside += 1
	_r.check(
		outside == 0,
		"%s: %s draws %d board tiles wrong." % [game_id, name, outside]
	)
	var unloaded: int = 0
	for tile: int in map:
		if tile > 0x8F and tile < 0xED:
			unloaded += 1
	_r.check(
		unloaded == 0,
		"%s: %s names %d tiles no strip loaded." % [game_id, name, unloaded]
	)
	## The cell each cursor object is centred on, which is the one number the
	## OAM sets are placed by.
	for cell: int in Gen2UnownPuzzle.CELLS:
		var point: Vector2i = Gen2UnownPuzzlePage.cell_point(cell)
		_r.check(
			point == Vector2i(int(OAM_COORDS[cell][0]), int(OAM_COORDS[cell][1]))
				- Gen2UnownPuzzlePage.OAM_ORIGIN,
			"%s: cell %d's OAM point is %s." % [game_id, cell, point]
		)


## The rules, which are cartridge-independent: the corners, the solved
## configuration and the cursor's own edges.
func _verify_rules() -> void:
	for piece: int in Gen2UnownPuzzle.PIECES:
		_r.check(
			Gen2UnownPuzzlePage.piece_corner_tile(piece + 1) == CORNERS[piece],
			"Piece %d's corner tile is not $%02X." % [piece + 1, CORNERS[piece]]
		)
	_r.check(
		Gen2UnownPuzzlePage.piece_corner_tile(0) == NO_PIECE_CORNER,
		"No piece selected is not $%02X." % NO_PIECE_CORNER
	)
	var solved_wrong: int = 0
	for cell: int in Gen2UnownPuzzle.CELLS:
		if Gen2UnownPuzzle.solved_piece_at(cell) != SOLVED[cell]:
			solved_wrong += 1
		if Gen2UnownPuzzlePage.vacant_tile(cell) != VACANT[cell]:
			solved_wrong += 1
	_r.check(
		solved_wrong == 0,
		"The solved configuration or the filler column differs in %d cells." % solved_wrong
	)
	_verify_walk()


## Every cell against every direction, which is the whole of `.Function`'s
## hand-listed edges rather than the four a screenshot would show.
func _verify_walk() -> void:
	var wrong: int = 0
	for cell: int in Gen2UnownPuzzle.CELLS:
		for direction: int in [
			Gen2Button.UP, Gen2Button.DOWN, Gen2Button.LEFT, Gen2Button.RIGHT
		]:
			var puzzle := Gen2UnownPuzzle.create(null)
			## The board is walked from cell 0, one step a press, so the cursor
			## is put where the case wants it by pressing there first.
			while puzzle.cursor() != cell:
				var towards: int = Gen2Button.DOWN \
					if puzzle.cursor() / Gen2UnownPuzzle.COLUMNS < cell / Gen2UnownPuzzle.COLUMNS \
					else Gen2Button.RIGHT
				var before: int = puzzle.cursor()
				puzzle.advance([towards], [towards])
				if puzzle.cursor() == before:
					break
			if puzzle.cursor() != cell:
				continue
			var from: int = puzzle.cursor()
			puzzle.advance([direction], [direction])
			if puzzle.cursor() != _wanted_step(from, direction):
				wrong += 1
	_r.check(wrong == 0, "The cursor walks %d of its cases wrong." % wrong)
	_r.note("Cursor: %d cells against four directions." % Gen2UnownPuzzle.CELLS)


## `.d_up`, `.d_down`, `.d_left` and `.d_right`, restated.
func _wanted_step(cell: int, direction: int) -> int:
	match direction:
		Gen2Button.UP:
			return cell if cell in NO_STEP_UP else cell - 6
		Gen2Button.DOWN:
			return cell if cell in NO_STEP_DOWN else cell + 6
		Gen2Button.LEFT:
			if cell == 35:
				return 30
			return cell if cell in NO_STEP_LEFT else cell - 1
		Gen2Button.RIGHT:
			if cell == 30:
				return 35
			return cell if cell in NO_STEP_RIGHT else cell + 1
	return cell


func _total_tiles() -> int:
	var total: int = 0
	for name: String in STRIPS:
		total += int(STRIPS[name])
	return total
