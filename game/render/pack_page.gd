class_name Gen2PackPage
extends RefCounted

## The pack's own tile screen (`Pack_InitGFX`, engine/items/pack.asm).
##
## [Gen2WorldPack] owns the pockets and what a row may do; this is the picture,
## the way [Gen2PokedexPage] is the dex's. The screen is a 20x18 grid of tile
## numbers plus one palette per cell, since `_CGB_PackPals` fills the attrmap
## with six palettes at once and a single-palette blit cannot say what it draws.
##
## `Pack_InitGFX`'s VRAM window:
##
## | Tiles | Contents |
## |---|---|
## | $00-$4f | `PackMenuGFX`, the background, the header row and the pocket names |
## | $50-$5e | the current pocket's picture, which `DrawPackGFX` swaps per pocket |
## | $80+ | the font, so printed text addresses glyphs as usual |
##
## The copy is `$60 tiles` of an 80-tile sheet, so the sixteen it lands on $50
## are `PackGFX`'s own first sixteen; `DrawPackGFX` overwrites fifteen of them
## before the screen is shown and no tilemap names the sixteenth.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

const SHEET_TILES: int = RomLayout.PACK_MENU_TILES
const PACK_FIRST_TILE: int = RomLayout.PACK_FIRST_TILE
const BLANK_TILE: int = 0x7F

## `Pack_InitGFX`'s own three writes: the field `ByteFill`ed over rows 1 to 11,
## the header row of twenty ascending tiles from $28, and the 5x3 corner the
## pocket picture is placed in.
const FIELD_TILE: int = 0x24
const FIELD_AT: Vector2i = Vector2i(0, 1)
const FIELD_ROWS: int = 11
const HEADER_FIRST_TILE: int = 0x28
const PACK_AT: Vector2i = Vector2i(0, 3)
const PACK_COLUMNS: int = 5
const PACK_ROWS: int = 3
## `DrawPocketName`'s own corner, the same shape one row above the text box.
const NAME_AT: Vector2i = Vector2i(0, 7)

## `hlcoord 5, 1 / lb bc, 11, 15`, the listing's own cleared box.
const LIST_AT: Vector2i = Vector2i(5, 1)
const LIST_COLUMNS: int = 15
const LIST_ROWS: int = 11

## `hlcoord 0, SCREEN_HEIGHT - 4 - 2 / lb bc, 4, SCREEN_WIDTH - 2`, which is a
## four-row interior and so a six-row frame across the screen.
const TEXTBOX_AT: Vector2i = Vector2i(0, 12)
const TEXTBOX_COLUMNS: int = 20
const TEXTBOX_ROWS: int = 6
## Where `PrintItemDescription` is handed, and the row spacing every text box on
## the hardware is written with. `TEXTBOX_INNERH` is two lines, so a longer text
## is paged rather than drawn through the frame.
const TEXT_AT: Vector2i = Vector2i(1, 14)
const TEXT_SPACING: int = 2
const TEXTBOX_ROWS_OF_TEXT: int = 2

## `ForgetMove`'s `hlcoord 5, 2 / ld b, NUM_MOVES * 2 / ld c, MOVE_NAME_LENGTH`,
## whose border runs from that corner to (19, 11).
const FORGET_AT: Vector2i = Vector2i(5, 2)
const FORGET_SIZE: Vector2i = Vector2i(15, 10)
const FORGET_NAME_COLUMN: int = 7
const FORGET_CURSOR_COLUMN: int = 6
const FORGET_FIRST_ROW: int = 4

## `ItemsPocketMenuHeader`: `menu_coords 7, 1, 19, 11` with five rows of eight
## columns. `ScrollingMenu_UpdateDisplay` starts one cell in from that corner and
## steps two rows, `w2DMenuCursorInitX` is the border column itself, and
## `PlaceMenuItemQuantity` writes `SCREEN_WIDTH + 1` past the name's own width.
const LIST_HEIGHT: int = 5
const CURSOR_COLUMN: int = 7
const NAME_COLUMN: int = 8
const FIRST_ROW: int = 2
const ROW_SPACING: int = 2
const QUANTITY_AT: Vector2i = Vector2i(17, 3)
const QUANTITY_DIGITS: int = 2

## `TMHM_DisplayPocketItems`, which is a listing of its own rather than a
## scrolling menu: the TM number sits in the column the other pockets leave
## empty and the move name three cells past it, on the same rows.
const TMHM_NUMBER_COLUMN: int = 5

## `Place2DMenuCursor`'s "▶" and the "×" `PlaceMenuItemQuantity` writes.
const CURSOR_CODE: int = 0xED
const TIMES_CODE: int = 0xF1

## `ScrollingMenu_UpdateDisplay.CancelString` and `TMHM_CancelString`, which are
## the same word in both listings.
const CANCEL: String = "CANCEL"

## A row of [method pocket_map]'s listing. `item` is every pocket but TM/HM,
## `tm` carries the number the TM/HM pocket prints beside the move name, and
## `cancel` is the row both listings end with.
const ROW_ITEM: StringName = &"item"
const ROW_TM: StringName = &"tm"
const ROW_CANCEL: StringName = &"cancel"

## `_CGB_PackPals`' five `FillBoxCGB` calls, as (x, y, width, height, palette)
## over an attrmap `WipeAttrmap` left on palette 0.
const ATTRIBUTES: Array = [
	[0, 0, 10, 1, 1],
	[10, 0, 10, 1, 2],
	[7, 2, 1, 9, 3],
	[0, 7, 5, 3, 4],
	[0, 3, 5, 3, 5],
]

var font: Gen2Font = null
## Which text-box border the player chose, for the box the description sits in.
var frame_style: int = 0
## The VRAM window, as one indices strip per tile number.
var _tiles: Dictionary = {}
## `PackGFX` and `PackFGFX`, each as the whole four-pocket strip.
var _pockets: PackedByteArray = PackedByteArray()
var _pockets_female: PackedByteArray = PackedByteArray()


## [param data] supplies the glyphs and both sheets; a cache without them answers
## null rather than drawing a screen of blanks.
static func from_data(data: GameData) -> Gen2PackPage:
	if data == null:
		return null
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null:
		return null
	var out := Gen2PackPage.new()
	out.font = glyphs
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	out._load_sheet(data.tile_indices("pack_menu"))
	out._pockets = data.tile_indices("pack_pockets")
	out._pockets_female = data.tile_indices("pack_pockets_female")
	return out


func ready() -> bool:
	return font != null and _tiles.size() >= SHEET_TILES and not _pockets.is_empty()


func _load_sheet(indices: PackedByteArray) -> void:
	if indices.is_empty():
		return
	@warning_ignore("integer_division")
	var width: int = indices.size() / TILE
	for tile: int in SHEET_TILES:
		if (tile + 1) * TILE > width:
			break
		var cell := PackedByteArray()
		cell.resize(TILE * TILE)
		for y: int in TILE:
			for x: int in TILE:
				cell[y * TILE + x] = indices[y * width + tile * TILE + x]
		_tiles[tile] = cell


## The whole screen as tile numbers, in the order `Pack_InitGFX` writes them.
##
## [param pocket] is `wCurPocket`, which picks both the picture and the name.
## [param rows] is the visible listing, at most [constant LIST_HEIGHT] entries of
## the three shapes [constant ROW_ITEM] names, and [param cursor] which of them
## the arrow stands on, or -1 while `PlaceHollowCursor` has taken it away.
func pocket_map(
	pocket: int, rows: Array, cursor: int, description: String,
	pocket_name: PackedByteArray = PackedByteArray()
) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(COLUMNS * ROWS)
	map.fill(BLANK_TILE)
	for row: int in FIELD_ROWS:
		for column: int in COLUMNS:
			_put(map, Vector2i(column, FIELD_AT.y + row), FIELD_TILE)
	for row: int in LIST_ROWS:
		for column: int in LIST_COLUMNS:
			_put(map, LIST_AT + Vector2i(column, row), BLANK_TILE)
	for column: int in COLUMNS:
		_put(map, Vector2i(column, 0), HEADER_FIRST_TILE + column)
	for row: int in PACK_ROWS:
		for column: int in PACK_COLUMNS:
			_put(
				map, PACK_AT + Vector2i(column, row),
				PACK_FIRST_TILE + row * PACK_COLUMNS + column
			)
	for cell: int in pocket_name.size():
		@warning_ignore("integer_division")
		_put(
			map,
			NAME_AT + Vector2i(cell % RomLayout.PACK_NAME_COLUMNS, cell / RomLayout.PACK_NAME_COLUMNS),
			pocket_name[cell]
		)
	_draw_textbox(map, description)
	_draw_rows(map, rows, cursor)
	return map


## `ScrollingMenu_UpdateDisplay` and `TMHM_DisplayPocketItems`, which write the
## same rows out of different fields.
func _draw_rows(map: PackedInt32Array, rows: Array, cursor: int) -> void:
	for index: int in mini(rows.size(), LIST_HEIGHT + 1):
		var entry: Dictionary = rows[index]
		var top: int = FIRST_ROW + index * ROW_SPACING
		match StringName(entry.get("kind", ROW_ITEM)):
			ROW_CANCEL:
				_string(map, Vector2i(NAME_COLUMN, top), CANCEL)
			ROW_TM:
				_string(map, Vector2i(TMHM_NUMBER_COLUMN, top), _tm_label(entry))
				_string(map, Vector2i(NAME_COLUMN, top), String(entry.get("name", "")))
				_quantity(map, index, entry)
			_:
				_string(map, Vector2i(NAME_COLUMN, top), String(entry.get("name", "")))
				_quantity(map, index, entry)
	if cursor >= 0 and cursor < mini(rows.size(), LIST_HEIGHT + 1):
		_put(
			map, Vector2i(CURSOR_COLUMN, FIRST_ROW + cursor * ROW_SPACING), CURSOR_CODE
		)


## `PlaceMenuItemQuantity`, which prints nothing for a row `_CheckTossableItem`
## refuses: a key item and an HM have no count on the cartridge either.
func _quantity(map: PackedInt32Array, index: int, entry: Dictionary) -> void:
	if not bool(entry.get("show_quantity", false)):
		return
	var at: Vector2i = QUANTITY_AT + Vector2i(0, index * ROW_SPACING)
	_put(map, at, TIMES_CODE)
	_string(
		map, at + Vector2i(1, 0),
		String.num_int64(maxi(int(entry.get("quantity", 0)), 0)).lpad(QUANTITY_DIGITS, " ")
	)


## The TM/HM pocket's own number column: a TM is two digits with its leading
## zero, an HM an "H" and its number left aligned.
func _tm_label(entry: Dictionary) -> String:
	var number: int = maxi(int(entry.get("number", 0)), 0)
	if bool(entry.get("hm", false)):
		return "H%d" % number
	return String.num_int64(number).lpad(2, "0")


## `Textbox`: the chosen frame around a cleared interior, with the description
## printed a tile in and on every second row.
func _draw_textbox(map: PackedInt32Array, text: String) -> void:
	draw_frame(map, TEXTBOX_AT, Vector2i(TEXTBOX_COLUMNS, TEXTBOX_ROWS))
	var line: int = 0
	for row_text: String in text.split("\n", false):
		if line >= TEXTBOX_ROWS_OF_TEXT:
			break
		_string(map, TEXT_AT + Vector2i(0, line * TEXT_SPACING), row_text)
		line += 1


## `TextboxBorder` and the `ClearBox` behind it, at any corner and any size in
## tiles including the frame. Every box the pack opens over its own screen is one
## of these, so the arithmetic lives here once.
func draw_frame(map: PackedInt32Array, at: Vector2i, size: Vector2i) -> void:
	var first: int = RomLayout.FRAME_FIRST_CODE
	var right: int = at.x + size.x - 1
	var bottom: int = at.y + size.y - 1
	for column: int in range(at.x + 1, right):
		_put(map, Vector2i(column, at.y), first + RomLayout.FRAME_HORIZONTAL)
		_put(map, Vector2i(column, bottom), first + RomLayout.FRAME_HORIZONTAL)
	for row: int in range(at.y + 1, bottom):
		_put(map, Vector2i(at.x, row), first + RomLayout.FRAME_VERTICAL)
		_put(map, Vector2i(right, row), first + RomLayout.FRAME_VERTICAL)
		for column: int in range(at.x + 1, right):
			_put(map, Vector2i(column, row), BLANK_TILE)
	_put(map, at, first + RomLayout.FRAME_TOP_LEFT)
	_put(map, Vector2i(right, at.y), first + RomLayout.FRAME_TOP_RIGHT)
	_put(map, Vector2i(at.x, bottom), first + RomLayout.FRAME_BOTTOM_LEFT)
	_put(map, Vector2i(right, bottom), first + RomLayout.FRAME_BOTTOM_RIGHT)


## `MenuBox` and `PlaceVerticalMenuItems`: one of the pack's `MENU_BACKUP_TILES`
## submenus, drawn over the screen already in [param map] so it wears the
## attrmap's own palette rather than a layer of its own.
func draw_menu(
	map: PackedInt32Array, box: Gen2MenuBox, options: Array, cursor: int
) -> void:
	draw_frame(map, box.border_position(), box.border_size())
	var last_column: int = box.left + box.interior().x
	for index: int in options.size():
		var at: Vector2i = box.item_position(index)
		_string(map, at, String(options[index]), maxi(0, last_column - at.x + 1))
	if cursor >= 0 and cursor < options.size() \
		and box.has_flag(Gen2MenuBox.STATICMENU_CURSOR):
		_put(map, box.cursor_position(cursor), CURSOR_CODE)


## `BuySellToss_UpdateQuantityDisplay`: the frame, then `'×'` and
## `PRINTNUM_LEADINGZEROS | 1, 2` one cell in from its own corner.
func draw_quantity(map: PackedInt32Array, box: Gen2MenuBox, quantity: int) -> void:
	draw_frame(map, box.border_position(), box.border_size())
	var at: Vector2i = box.border_position() + Vector2i.ONE
	_put(map, at, TIMES_CODE)
	_string(
		map, at + Vector2i(1, 0),
		String.num_int64(maxi(quantity, 0)).lpad(QUANTITY_DIGITS, "0")
	)


## `ForgetMove`'s own list: a `Textbox` at `hlcoord 5, 2` holding `NUM_MOVES * 2`
## rows of `MOVE_NAME_LENGTH`, `ListMoves` two cells in from that corner with
## `wListMovesLineSpacing` of two rows, and `w2DMenuCursorInitX` one cell left.
func draw_move_list(map: PackedInt32Array, names: Array, cursor: int) -> void:
	draw_frame(map, FORGET_AT, FORGET_SIZE)
	for index: int in names.size():
		var row: int = FORGET_FIRST_ROW + index * ROW_SPACING
		_string(map, Vector2i(FORGET_NAME_COLUMN, row), String(names[index]))
	if cursor >= 0 and cursor < names.size():
		_put(
			map,
			Vector2i(FORGET_CURSOR_COLUMN, FORGET_FIRST_ROW + cursor * ROW_SPACING),
			CURSOR_CODE
		)


## `_CGB_PackPals`' attrmap, as one palette index per cell.
static func attributes() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(COLUMNS * ROWS)
	for box: Array in ATTRIBUTES:
		for row: int in int(box[3]):
			for column: int in int(box[2]):
				var x: int = int(box[0]) + column
				var y: int = int(box[1]) + row
				if x < COLUMNS and y < ROWS:
					out[y * COLUMNS + x] = int(box[4])
	return out


## The whole screen as pixels. [param female] is Kris's pack and her own
## palettes, which only Crystal carries.
func image(
	data: GameData, map: PackedInt32Array, pocket: int, female: bool = false
) -> Image:
	var indices: PackedByteArray = compose(map, pocket, female)
	var slots: PackedInt32Array = attributes()
	var palettes: Array = []
	for slot: int in RomLayout.PACK_PALETTES:
		var colors: PackedColorArray = data.pack_palette(slot, female)
		palettes.append(colors if not colors.is_empty() else data.pack_palette(slot))
	var out := Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	for row: int in ROWS:
		for column: int in COLUMNS:
			var palette: PackedColorArray = palettes[
				clampi(slots[row * COLUMNS + column], 0, palettes.size() - 1)
			]
			if palette.is_empty():
				continue
			for y: int in TILE:
				for x: int in TILE:
					var at_x: int = column * TILE + x
					var at_y: int = row * TILE + y
					out.set_pixel(at_x, at_y, palette[
						clampi(indices[at_y * Gen2Screen.WIDTH + at_x], 0, palette.size() - 1)
					])
	return out


## Resolves every tile number to pixels: the menu sheet, the pocket's own
## fifteen tiles where `DrawPackGFX` put them, the text box out of the chosen
## frame, and everything else out of the font.
func compose(
	map: PackedInt32Array, pocket: int, female: bool = false
) -> PackedByteArray:
	var width: int = COLUMNS * TILE
	var indices := PackedByteArray()
	indices.resize(width * ROWS * TILE)
	var strip: PackedByteArray = _pockets_female if female \
		and not _pockets_female.is_empty() else _pockets
	@warning_ignore("integer_division")
	var strip_tiles: int = strip.size() / TILE
	var picture: int = RomLayout.PACK_POCKET_PICTURES[
		clampi(pocket, 0, RomLayout.PACK_POCKETS - 1)
	] * RomLayout.PACK_POCKET_TILES
	for row: int in ROWS:
		for column: int in COLUMNS:
			var tile: int = map[row * COLUMNS + column]
			var at := Vector2i(column * TILE, row * TILE)
			if tile >= PACK_FIRST_TILE \
				and tile < PACK_FIRST_TILE + RomLayout.PACK_POCKET_TILES:
				Gen2Font.blit_slot(
					strip, strip_tiles, picture + tile - PACK_FIRST_TILE,
					indices, width, at.x, at.y
				)
			elif _tiles.has(tile):
				_blit(indices, width, _tiles[tile], at)
			elif tile >= RomLayout.FRAME_FIRST_CODE \
				and tile < RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TILES:
				font.draw_frame_code(frame_style, tile, indices, width, at.x, at.y)
			elif tile != BLANK_TILE:
				font.draw_code(tile, indices, width, at.x, at.y, Gen2Text.FONT_MAIN)
	return indices


## [param max_tiles] below zero is unbounded; a menu passes the room its box has,
## since a label a mod registers is not written to fit the way every cartridge
## one is.
func _string(
	map: PackedInt32Array, at: Vector2i, text: String, max_tiles: int = -1
) -> void:
	var cell: Vector2i = at
	var drawn: int = 0
	for code: int in Gen2Text.encode(text):
		if max_tiles >= 0 and drawn >= max_tiles:
			return
		_put(map, cell, code)
		cell.x += 1
		drawn += 1


func _put(map: PackedInt32Array, at: Vector2i, tile: int) -> void:
	if at.x < 0 or at.y < 0 or at.x >= COLUMNS or at.y >= ROWS:
		return
	map[at.y * COLUMNS + at.x] = tile


func _blit(
	indices: PackedByteArray, width: int, cell: PackedByteArray, at: Vector2i
) -> void:
	for y: int in TILE:
		for x: int in TILE:
			indices[(at.y + y) * width + at.x + x] = cell[y * TILE + x]
