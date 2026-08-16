class_name Gen2TrainerCardPage
extends RefCounted

## One page of the trainer card (`engine/menus/trainer_card.asm`), on the tile
## grid the hardware uses.
##
## The card is a tilemap screen rather than a text screen: most of what it draws
## are raw tile numbers into the window the card graphics are loaded at, and only
## the player's name, the numbers and a handful of labels are printed text. So
## this keeps the cartridge's own VRAM window and writes tile numbers into a map,
## exactly like `TrainerCard_InitBorder` and `TrainerCardSetup_PlaceTilemapString`
## do, then resolves each number to pixels at the end.
##
## VRAM, as `_Option`'s `.InitRAM` and each page's LoadGFX build it:
##
## | Tiles | Contents |
## |---|---|
## | $00-$22 | `GetCardPic`'s 35-tile player pic, gender selected |
## | $1c | Crystal only, overwritten by `CardRightCornerGFX` |
## | $23-$28 | `TrainerCardGFX`, the card's own frame pieces |
## | $29-$7e | 86 tiles: `CardStatusGFX` on page 1, `LeaderGFX` on pages 2 and 3 |
## | $80+ | the font, so printed text addresses glyphs as usual |
##
## Page 1's 86 tiles start at `CardStatusGFX`, which is only six tiles long, so
## the copy runs straight on into `LeaderGFX`. That overrun is the cartridge's
## own and is why the status strip and the leader strip overlap.
##
## Node-free: it writes tile numbers and then indices into a buffer, so a page
## can be drawn and read back headless. The badge sprites are not in that buffer;
## they are objects with their own palette, composed over the page by the screen.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

const PAGE_1: int = 0
const PAGE_2: int = 1
const PAGE_3: int = 2

## Where each block of the cartridge's VRAM window begins.
const PIC_FIRST_TILE: int = 0x00
const FRAME_FIRST_TILE: int = 0x23
const STATUS_FIRST_TILE: int = 0x29
const STATUS_TILES: int = 86

## `TrainerCard_InitBorder`'s own tiles: $23 is the border, $24 the bottom-left
## piece and $1c the top-right corner. Crystal loads a tile of its own there;
## Gold and Silver point at a tile inside the card pic instead, which is the one
## thing the two versions of this routine disagree on.
const BORDER_TILE: int = 0x23
const BORDER_BOTTOM_LEFT_TILE: int = 0x24
const CORNER_TILE_CRYSTAL: int = 0x1C
const CORNER_TILE_GOLD_SILVER: int = 0x04
const BLANK_TILE: int = 0x7F

## `TrainerCard_PrintTopHalfOfCard` and `TrainerCard_Page1_PrintDexCaught_GameTime`.
const TOP_BORDER_ROWS: int = 5
const BOTTOM_BORDER_ROWS: int = 6
const BOTTOM_BORDER_AT: Vector2i = Vector2i(0, 8)

## `.Name_Money` is one string placed at (2,2), and its `next` macro is
## `<NEXT>`, which `NextLineChar` moves `SCREEN_WIDTH * 2` by, so its three lines
## land two rows apart: NAME/ on row 2, the empty line on row 4 where the ID
## tiles go, and MONEY on row 6.
const NAME_LABEL_AT: Vector2i = Vector2i(2, 2)
const MONEY_LABEL_AT: Vector2i = Vector2i(2, 6)
const NAME_LABEL: String = "NAME/"
const MONEY_LABEL: String = "MONEY"
const PLAYER_NAME_AT: Vector2i = Vector2i(7, 2)
const ID_LABEL_AT: Vector2i = Vector2i(2, 4)
## `.ID_No`'s `db $27, $28`, two tiles of the card's own graphics rather than
## letters, which is why "ID No" is not spelled with the font.
const ID_LABEL_TILES: Array[int] = [0x27, 0x28]
const ID_NUMBER_AT: Vector2i = Vector2i(5, 4)
const ID_DIGITS: int = 5
const MONEY_AT: Vector2i = Vector2i(7, 6)
const MONEY_DIGITS: int = 6
const DIVIDER_AT: Vector2i = Vector2i(1, 3)
## `.HorizontalDivider`'s twelve $25 pieces and the $26 that ends it.
const DIVIDER_TILE: int = 0x25
const DIVIDER_END_TILE: int = 0x26
const DIVIDER_LENGTH: int = 12

## `hlcoord 14, 1` with `lb bc, 5, 7`: the pic is five tiles wide and seven tall.
const PIC_AT: Vector2i = Vector2i(14, 1)
const PIC_COLUMNS: int = 5
const PIC_ROWS: int = 7

## `.Dex_PlayTime`, one string at (2,10) whose own `next` puts PLAY TIME two
## rows down, beside the timer at (11,12).
const DEX_LABEL_AT: Vector2i = Vector2i(2, 10)
const PLAY_TIME_LABEL_AT: Vector2i = Vector2i(2, 12)
const DEX_LABEL: String = "#DEX"
const PLAY_TIME_LABEL: String = "PLAY TIME"
const DEX_COUNT_AT: Vector2i = Vector2i(15, 10)
const DEX_DIGITS: int = 3
## `hlcoord 11, 12` for the hours, then `inc hl` past the separator column.
const HOURS_AT: Vector2i = Vector2i(11, 12)
const HOURS_DIGITS: int = 4
const SEPARATOR_AT: Vector2i = Vector2i(15, 12)
const MINUTES_AT: Vector2i = Vector2i(16, 12)
const MINUTES_DIGITS: int = 2
## `xor ' ' ^ $2e` every 32 frames: the colon and a space, alternating.
const SEPARATOR_COLON_TILE: int = 0x2E

## `.StatusTilemap`'s five tiles, the "STATUS" strip over page 1's lower box.
const STATUS_TILEMAP_AT: Vector2i = Vector2i(2, 8)
const STATUS_TILEMAP: Array[int] = [0x29, 0x2A, 0x2B, 0x2C, 0x2D]

## `.Badges`, printed text rather than tiles, and the one string whose column is
## profile split: pokegold prints it two columns further right.
const BADGES_LABEL: String = "  BADGES"
const BADGES_LABEL_GOLD_SILVER: String = "BADGES"
const BADGES_LABEL_AT: Vector2i = Vector2i(10, 15)
const BADGES_LABEL_AT_GOLD_SILVER: Vector2i = Vector2i(12, 15)
## The arrow that ends it. Part of the same string on the cartridge; kept apart
## here only because it is a character code rather than a letter.
const BADGES_ARROW_CODE: int = 0xED

## Pages 2 and 3: `.BadgesTilemap`'s "BADGES" in card tiles, then the leaders'
## faces, four to a row, at $29 and $51.
const BADGES_TILEMAP_AT: Vector2i = Vector2i(2, 8)
const BADGES_TILEMAP: Array[int] = [0x79, 0x7A, 0x7B, 0x7C, 0x7D]
const LEADER_ROW_1_AT: Vector2i = Vector2i(2, 10)
const LEADER_ROW_1_FIRST_TILE: int = 0x29
const LEADER_ROW_2_AT: Vector2i = Vector2i(2, 13)
const LEADER_ROW_2_FIRST_TILE: int = 0x51
const LEADERS_PER_ROW: int = 4
## `TrainerCard_Page2_3_PlaceLeadersFaces` writes 4 tiles, then 3, then 3, all
## from one run, so a face is ten tiles in a 4x3 box with a hole at its corner.
const LEADER_FACE_COLUMNS: int = 4
const LEADER_FACE_ROWS: int = 3
const LEADER_FACE_TILES: int = 10
const LEADER_STRIDE: int = 4

## `_CGB_TrainerCard`'s attribute map, as `FillBoxCGB` writes it: rows first,
## then columns. Its palette slots are [constant RomLayout.CARD_PALETTE_CLASSES]'
## own order, and the leader boxes are filled whatever page is on screen, since
## the layout runs once in `.InitRAM`.
##
## Both gender branches are the source's: the whole card takes the opposite
## gender's palette and the pic area the player's own, Clair's box is filled only
## for Kris, and the top-right corner is written twice, the second write being
## the one that lasts.
const ATTRIBUTE_LEADER_BOXES: Array[Dictionary] = [
	{"at": Vector2i(2, 11), "palette": 1},
	{"at": Vector2i(6, 11), "palette": 2},
	{"at": Vector2i(10, 11), "palette": 3},
	{"at": Vector2i(14, 11), "palette": 4},
	{"at": Vector2i(2, 14), "palette": 5},
	{"at": Vector2i(6, 14), "palette": 6},
	{"at": Vector2i(10, 14), "palette": 7},
]
const ATTRIBUTE_BOX_ROWS: int = 2
const ATTRIBUTE_BOX_COLUMNS: int = 4
const CLAIR_BOX_AT: Vector2i = Vector2i(14, 14)
const CORNER_AT: Vector2i = Vector2i(18, 1)

var font: Gen2Font = null
var crystal: bool = true
var female: bool = false
## The cartridge's VRAM window, as one indices strip per tile number.
var _tiles: Dictionary = {}


## [param data] supplies both the glyphs and the card's graphics; a cache
## without them answers null rather than drawing a card of blanks.
static func from_data(
	data: GameData, is_female: bool, is_crystal: bool
) -> Gen2TrainerCardPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null or data == null:
		return null
	var out := Gen2TrainerCardPage.new()
	out.font = glyphs
	out.crystal = is_crystal
	out.female = is_female
	out._load_vram(data, is_female)
	return out


## Whether the cache carried every sheet this page needs.
func ready() -> bool:
	return font != null and not _tiles.is_empty()


## `GetCardPic`, `CardRightCornerGFX` and each page's own `Request2bpp`, in the
## order the cartridge copies them, so a later copy overwrites an earlier one at
## the same tile exactly as it does in VRAM.
func _load_vram(data: GameData, is_female: bool) -> void:
	var pic: String = "card_pic_female" if is_female and crystal else "card_pic_male"
	_load_sheet(data, pic, PIC_FIRST_TILE, RomLayout.CARD_PIC_TILES)
	_load_sheet(data, "card_frame", FRAME_FIRST_TILE, RomLayout.CARD_FRAME_TILES)
	if crystal:
		_load_sheet(data, "card_right_corner", CORNER_TILE_CRYSTAL, 1)


## The 86 tiles a page loads at $29. Page 1 takes them from the status strip and
## pages 2 and 3 from the leaders', which is the only difference between them.
func load_page_tiles(data: GameData, page: int) -> void:
	var sheet: String = "card_status" if page == PAGE_1 else "card_leaders"
	_load_sheet(data, sheet, STATUS_FIRST_TILE, STATUS_TILES)


func _load_sheet(data: GameData, name: String, first_tile: int, count: int) -> void:
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
		_tiles[first_tile + tile] = cell


## The whole 160x144 page as palette indices. [param page] is a `TRAINERCARD*`
## page number and [param card] one row of [method Gen2TrainerCard.page].
func draw(page: Dictionary) -> PackedByteArray:
	var map: PackedInt32Array = _blank_map()
	_draw_border(map, Vector2i.ZERO, TOP_BORDER_ROWS)
	_draw_border(map, BOTTOM_BORDER_AT, BOTTOM_BORDER_ROWS)
	_draw_top_half(map, page)
	match int(page.get("page", PAGE_1)):
		PAGE_1:
			_draw_page_1(map, page)
		_:
			_draw_badge_page(map)
	return _compose(map)


## `TrainerCard_InitBorder`: a solid row of $23, then [param rows] rows walled
## with $23, then a row that opens with $23 $24 and closes with $23, then a
## second solid row. The first row's own right-hand end carries the corner tile.
func _draw_border(map: PackedInt32Array, at: Vector2i, rows: int) -> void:
	for column: int in COLUMNS:
		_put(map, Vector2i(column, at.y), BORDER_TILE)
	_put(map, Vector2i(0, at.y + 1), BORDER_TILE)
	for column: int in range(1, COLUMNS - 2):
		_put(map, Vector2i(column, at.y + 1), BLANK_TILE)
	_put(map, Vector2i(COLUMNS - 2, at.y + 1), corner_tile())
	_put(map, Vector2i(COLUMNS - 1, at.y + 1), BORDER_TILE)
	for row: int in range(at.y + 2, at.y + 2 + rows - 1):
		_put(map, Vector2i(0, row), BORDER_TILE)
		for column: int in range(1, COLUMNS - 1):
			_put(map, Vector2i(column, row), BLANK_TILE)
		_put(map, Vector2i(COLUMNS - 1, row), BORDER_TILE)
	var closing: int = at.y + 1 + rows
	_put(map, Vector2i(0, closing), BORDER_TILE)
	_put(map, Vector2i(1, closing), BORDER_BOTTOM_LEFT_TILE)
	for column: int in range(2, COLUMNS - 1):
		_put(map, Vector2i(column, closing), BLANK_TILE)
	_put(map, Vector2i(COLUMNS - 1, closing), BORDER_TILE)
	for column: int in COLUMNS:
		_put(map, Vector2i(column, closing + 1), BORDER_TILE)


## Which tile the border's top-right corner is. Crystal loads a tile of its own
## over the pic's $1c; Gold and Silver reach into the pic at $04 instead.
func corner_tile() -> int:
	return CORNER_TILE_CRYSTAL if crystal else CORNER_TILE_GOLD_SILVER


func _draw_top_half(map: PackedInt32Array, page: Dictionary) -> void:
	_text(map, NAME_LABEL, NAME_LABEL_AT)
	_text(map, MONEY_LABEL, MONEY_LABEL_AT)
	_tilemap(map, ID_LABEL_TILES, ID_LABEL_AT)
	_text(map, String(page.get("player_name", "")), PLAYER_NAME_AT)
	## PRINTNUM_LEADINGZEROS over five digits, so the ID keeps its columns.
	_text(map, "%0*d" % [ID_DIGITS, int(page.get("player_id", 0))], ID_NUMBER_AT)
	## PRINTNUM_MONEY over six digits, which pads with spaces rather than zeros.
	_text(map, "%*d" % [MONEY_DIGITS, int(page.get("money", 0))], MONEY_AT)
	for index: int in DIVIDER_LENGTH:
		_put(map, DIVIDER_AT + Vector2i(index, 0), DIVIDER_TILE)
	_put(map, DIVIDER_AT + Vector2i(DIVIDER_LENGTH, 0), DIVIDER_END_TILE)
	_draw_pic(map)


## `predef PlaceGraphic` at (14,1), five wide and seven tall. The importer has
## already turned Crystal's column-major pic into the picture, so both profiles
## number these tiles the same way here.
func _draw_pic(map: PackedInt32Array) -> void:
	for row: int in PIC_ROWS:
		for column: int in PIC_COLUMNS:
			_put(
				map, PIC_AT + Vector2i(column, row),
				PIC_FIRST_TILE + row * PIC_COLUMNS + column
			)


func _draw_page_1(map: PackedInt32Array, page: Dictionary) -> void:
	_text(map, DEX_LABEL, DEX_LABEL_AT)
	_text(map, PLAY_TIME_LABEL, PLAY_TIME_LABEL_AT)
	_tilemap(map, STATUS_TILEMAP, STATUS_TILEMAP_AT)
	_draw_badges_label(map)
	## `CountSetBits` over wPokedexCaught, three digits and no leading zeros.
	if bool(page.get("pokedex", false)):
		_text(map, "%*d" % [DEX_DIGITS, int(page.get("caught", 0))], DEX_COUNT_AT)
	_text(map, String(page.get("hours", "")), HOURS_AT)
	_text(map, String(page.get("minutes", "")), MINUTES_AT)
	if bool(page.get("separator", true)):
		_put(map, SEPARATOR_AT, SEPARATOR_COLON_TILE)


## `.Badges` and the arrow that ends it. The string and its column are the one
## profile split on this page.
func _draw_badges_label(map: PackedInt32Array) -> void:
	var label: String = BADGES_LABEL if crystal else BADGES_LABEL_GOLD_SILVER
	var at: Vector2i = BADGES_LABEL_AT if crystal else BADGES_LABEL_AT_GOLD_SILVER
	_text(map, label, at)
	_code(map, BADGES_ARROW_CODE, at + Vector2i(label.length(), 0))


## `TrainerCard_Page2_3_InitObjectsAndStrings`. The badges themselves are
## objects, so the page under them is the leaders' faces and nothing else.
func _draw_badge_page(map: PackedInt32Array) -> void:
	_tilemap(map, BADGES_TILEMAP, BADGES_TILEMAP_AT)
	_draw_leader_row(map, LEADER_ROW_1_AT, LEADER_ROW_1_FIRST_TILE)
	_draw_leader_row(map, LEADER_ROW_2_AT, LEADER_ROW_2_FIRST_TILE)


## Four faces across, each `TrainerCard_Page2_3_PlaceLeadersFaces`' own ten
## tiles: a full row of four, then three, then three, the last column of the
## lower two rows left as it was.
func _draw_leader_row(map: PackedInt32Array, at: Vector2i, first_tile: int) -> void:
	var tile: int = first_tile
	for face: int in LEADERS_PER_ROW:
		var origin: Vector2i = at + Vector2i(face * LEADER_STRIDE, 0)
		for row: int in LEADER_FACE_ROWS:
			var width: int = LEADER_FACE_COLUMNS if row == 0 else LEADER_FACE_COLUMNS - 1
			for column: int in width:
				_put(map, origin + Vector2i(column, row), tile)
				tile += 1


## `_CGB_TrainerCard`, as one palette slot per tile.
func attributes() -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(COLUMNS * ROWS)
	map.fill(1 if not female else 0)
	_fill_attributes(map, PIC_AT, PIC_ROWS, PIC_COLUMNS, 0 if not female else 1)
	for box: Dictionary in ATTRIBUTE_LEADER_BOXES:
		_fill_attributes(
			map, box["at"], ATTRIBUTE_BOX_ROWS, ATTRIBUTE_BOX_COLUMNS, int(box["palette"])
		)
	if female:
		_fill_attributes(map, CLAIR_BOX_AT, ATTRIBUTE_BOX_ROWS, ATTRIBUTE_BOX_COLUMNS, 1)
	## The corner is written twice; this second write is the one that stands, and
	## it is the border's palette rather than the pic's.
	map[CORNER_AT.y * COLUMNS + CORNER_AT.x] = 1 if not female else 0
	return map


func _fill_attributes(
	map: PackedInt32Array, at: Vector2i, rows: int, columns: int, palette: int
) -> void:
	for row: int in rows:
		for column: int in columns:
			var x: int = at.x + column
			var y: int = at.y + row
			if x < 0 or y < 0 or x >= COLUMNS or y >= ROWS:
				continue
			map[y * COLUMNS + x] = palette


func _blank_map() -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(COLUMNS * ROWS)
	map.fill(BLANK_TILE)
	return map


func _put(map: PackedInt32Array, at: Vector2i, tile: int) -> void:
	if at.x < 0 or at.y < 0 or at.x >= COLUMNS or at.y >= ROWS:
		return
	map[at.y * COLUMNS + at.x] = tile


func _tilemap(map: PackedInt32Array, tiles: Array[int], at: Vector2i) -> void:
	for index: int in tiles.size():
		_put(map, at + Vector2i(index, 0), tiles[index])


## Printed text is character codes, which are tile numbers in the font's own
## window, so it goes into the same map as everything else.
##
## `#` ($54) is not a tile: [method Gen2Text.encode] prints `PlacePOKe`'s four
## characters for it, so the label the source writes as "#DEX" occupies seven
## columns and reads POKéDEX.
func _text(map: PackedInt32Array, text: String, at: Vector2i) -> void:
	var codes: PackedByteArray = Gen2Text.encode(text)
	for index: int in codes.size():
		_put(map, at + Vector2i(index, 0), codes[index])


func _code(map: PackedInt32Array, code: int, at: Vector2i) -> void:
	_put(map, at, code)


## Resolves every tile number to pixels: the card's own graphics out of the VRAM
## window, everything else out of the font.
func _compose(map: PackedInt32Array) -> PackedByteArray:
	var width: int = COLUMNS * TILE
	var indices := PackedByteArray()
	indices.resize(width * ROWS * TILE)
	for row: int in ROWS:
		for column: int in COLUMNS:
			var tile: int = map[row * COLUMNS + column]
			var at := Vector2i(column * TILE, row * TILE)
			if _tiles.has(tile):
				_blit(indices, width, _tiles[tile], at)
			elif tile != BLANK_TILE:
				font.draw_code(tile, indices, width, at.x, at.y, Gen2Text.FONT_MAIN)
	return indices


func _blit(
	indices: PackedByteArray, width: int, cell: PackedByteArray, at: Vector2i
) -> void:
	for y: int in TILE:
		for x: int in TILE:
			indices[(at.y + y) * width + at.x + x] = cell[y * TILE + x]
