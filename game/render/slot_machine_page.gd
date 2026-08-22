class_name Gen2SlotMachinePage
extends RefCounted

## `_SlotMachine`'s screen: `SlotsTilemap` under the three reels' own objects.
##
## Node-free, so the whole machine can be read back headless. [Gen2SlotMachine]
## owns the state and this is `.InitGFX`'s picture plus what `SlotsLoop` writes
## into it every frame.
##
## Four things the source states and a reading gets wrong:
##
## - **The reels are objects, not background.** `Slots_UpdateReelPositionAndOAM`
##   writes twenty-four shadow-OAM entries and `SlotsTilemap` leaves the three
##   columns they stand in empty, which is why a reel can sit between two
##   symbols at all: an object y is a pixel and a tilemap row is not.
## - **`.InitGFX` sets `rLCDC`'s `B_LCDC_OBJ_SIZE` itself**, so every object here
##   is eight by sixteen and draws its own tile and the one behind it, which is
##   why a symbol is two OAM entries and not four. The exit path resets it, and
##   no other screen in the game turns it on.
## - **An object's palette is its own tile number shifted twice.**
##   `.LoadOAM` writes `srl a / srl a / set B_OAM_PRIO, a` as the attribute
##   byte, so symbol `SLOTS_STARYU` ($14) draws in object palette 5. The unused
##   `GetUnknownSlotReelData` beside it is the table that would have said the
##   same thing.
## - **The bet lights are four cells each and thirteen apart.**
##   `Slots_TurnLightsOnOrOff` writes the tile at the coordinate, again at
##   `SCREEN_WIDTH / 2 + 3` past it, and then the tile behind it on the row
##   below both, which is the pair of lamps down each side of the window.

const TILE: int = Gen2Font.TILE
const SCREEN_COLUMNS: int = RomLayout.SLOTS_TILEMAP_COLUMNS
const SCREEN_ROWS: int = 18
const WIDTH: int = SCREEN_COLUMNS * TILE
const HEIGHT: int = SCREEN_ROWS * TILE
## Half the window, which is the run a tile number addresses: $00 to $7f.
const BANK_TILES: int = 128
const BANK_WIDTH: int = BANK_TILES * TILE

## `.InitGFX`'s two background loads: `Slots1LZ` into `vTiles2 tile $00` and
## `Slots2LZ` into `vTiles2 tile $25`. The font sits in the other half of the
## window and is reached by code, which is why nothing here loads it.
const SLOTS_1_FIRST_TILE: int = 0x00
const SLOTS_2_FIRST_TILE: int = 0x25
## The same `Slots2LZ` again in `vTiles0 tile $00`, which is what the reel
## symbols index, and `Slots3LZ` in `vTiles0 tile $40`, which is
## `SPRITE_ANIM_DICT_SLOTS`' own base and holds Golem, Chansey and the egg.
const OBJECT_SLOTS_2_FIRST_TILE: int = 0x00
const OBJECT_SLOTS_3_FIRST_TILE: int = 0x40

## `Slots_IlluminateBetLights`' own `$14` and `Slots_DeilluminateBetLights`' `$23`.
const LIGHT_ON_TILE: int = 0x14
const LIGHT_OFF_TILE: int = 0x23
## `Slots_TurnLightsOnOrOff`'s two steps: `SCREEN_WIDTH / 2 + 3` to the second
## lamp and `SCREEN_WIDTH / 2 - 3` down to the row behind it.
const LIGHT_COLUMN_STEP: int = SCREEN_COLUMNS / 2 + 3
## Which rows each bet lights, `Slots_Lights3OnOff` falling into `..._2` and
## `..._1`. A bet of three lights all five.
const LIGHT_ROWS: Array[Array] = [[6], [4, 8, 6], [2, 10, 4, 8, 6]]
const LIGHT_COLUMN: int = 3

## `.PrintCoinsAndPayout`: two `PrintNum` calls of two bytes in four digits,
## with `PRINTNUM_LEADINGZEROS`.
const COINS_AT: Vector2i = Vector2i(5, 1)
const PAYOUT_AT: Vector2i = Vector2i(11, 1)
const COUNT_DIGITS: int = 4

## `Slots_PayoutText.Text_PrintPayout` draws the matched symbol as a two by two
## block of `wSlotMatched + $25` at these two cells, which is the same strip the
## background is drawn from.
const PAYOUT_ICON_AT: Vector2i = Vector2i(2, 13)
const PAYOUT_ICON_FIRST_TILE: int = 0x25

## `TEXTBOX_Y`: the six rows under the tilemap, which every box here stands in.
const TEXTBOX_AT: Vector2i = Vector2i(0, 12)
const TEXTBOX_SIZE: Vector2i = Vector2i(20, 6)
const TEXT_AT: Vector2i = Vector2i(1, 14)
const TEXT_SPACING: int = 2

## `Slots_AskBet.MenuHeader`: `menu_coords 14, 10, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1`.
const BET_MENU_AT: Vector2i = Vector2i(14, 10)
const BET_MENU_SIZE: Vector2i = Vector2i(6, 8)
const BET_MENU_ITEMS: Array[String] = [" 3", " 2", " 1"]
## `Slots_AskPlayAgain`'s `lb bc, 14, 12`: `_YesNoBox` reads b as the left
## coordinate and c as the top, and adds 5 and 4 to them for the other corner,
## so the box is six by five at column 14 rather than at row 14.
const YES_NO_AT: Vector2i = Vector2i(14, 12)
const YES_NO_SIZE: Vector2i = Vector2i(6, 5)
## `GetMenuTextStartCoord` starts one row down, and again unless the header sets
## `STATICMENU_NO_TOP_SPACING`; `PlaceVerticalMenuItems` then steps
## `2 * SCREEN_WIDTH` an item. `YesNoMenuHeader` sets the flag and
## `Slots_AskBet.MenuData` does not.
const YES_NO_FIRST_ROW: int = 1
const BET_MENU_FIRST_ROW: int = 2
## `Place2DMenuCursor`'s own "▶".
const CURSOR_CODE: int = 0xED

## `_CGB_SlotMachine`'s `FillBoxCGB` calls, as (column, row, columns, rows,
## palette). `lb bc, rows, columns` is the argument order, so a `lb bc, 10, 3`
## is three columns of ten rows.
const ATTRIBUTE_BOXES: Array[Array] = [
	[0, 2, 3, 10, 2],
	[17, 2, 3, 10, 2],
	[0, 4, 3, 6, 3],
	[17, 4, 3, 6, 3],
	[0, 6, 3, 2, 4],
	[17, 6, 3, 2, 4],
	[4, 2, 12, 2, 1],
	[3, 2, 1, 10, 1],
	[16, 2, 1, 10, 1],
]
## The `ByteFill` behind them: every cell from row 12 down is the text palette.
const TEXT_PALETTE: int = 7
## `wOBPals1` starts at palette 8 of the sixteen `_CGB_SlotMachine` copies, so
## an object palette is that many on.
const FIRST_OBJECT_PALETTE: int = 8
## `.OAMData_SlotsGolem`'s own `OAM_PAL1` rows, and Chansey's.
const GOLEM_PALETTE: int = 5
const CHANSEY_PALETTE: int = 6
## `SPRITE_ANIM_OAMSET_SLOTS_EGG` is `.OAMData_1x1_Palette0` at vtile `$3a`.
const EGG_PALETTE: int = 0
const EGG_TILE: int = 0x3A

## `depixel 12, 13` and `depixel 12, 0`, the two spawn points, less the
## hardware's own OAM offsets.
const OAM_ORIGIN: Vector2i = Vector2i(8, 16)
const GOLEM_SPAWN: Vector2i = Vector2i(13 * TILE, 12 * TILE)
const CHANSEY_SPAWN: Vector2i = Vector2i(0, 12 * TILE)

## `.OAMData_SlotsGolem` and the five Chansey sets, as (x, y, vtile) with
## `dbsprite`'s own bytes worked out. Every object is eight by sixteen, so a
## vtile draws itself and the tile behind it.
const GOLEM_OBJECTS: Array[Array] = [
	[-12, -12, 0x00, false], [-4, -12, 0x02, false], [4, -12, 0x00, true],
	[-12, 4, 0x04, false], [-4, 4, 0x06, false], [4, 4, 0x04, true],
]
const CHANSEY_TOP: Array[Array] = [
	[-12, -12, 0x00], [-4, -12, 0x02], [4, -12, 0x04],
]
## The bottom row of each of the five sets, which is the only row that differs.
const CHANSEY_BOTTOMS: Array[Array] = [
	[0x06, 0x08, 0x0A], [0x0C, 0x0E, 0x10], [0x12, 0x14, 0x16], [0x18, 0x1A, 0x1C],
]
const CHANSEY_LAST_SET: Array[Array] = [
	[-12, -12, 0x1E], [-4, -12, 0x20], [4, -12, 0x22],
	[-12, 4, 0x24], [-4, 4, 0x26], [4, 4, 0x28],
]
## `.Frameset_SlotsGolem` and `.Frameset_SlotsChansey`: four entries of seven
## frames each, so a frameset turn is thirty-two frames.
const FRAME_LENGTH: int = 8
## `oamframe`'s own flips down the Golem's frameset.
const GOLEM_FRAMES: Array[Array] = [
	[0x00, false, false], [0x08, false, false],
	[0x00, false, true], [0x08, true, false],
]
## `.Frameset_SlotsChansey` and `..._2`, as indices into [constant CHANSEY_BOTTOMS].
const CHANSEY_FRAMES: Array[int] = [0, 1, 0, 2]
const CHANSEY_FRAMES_2: Array[int] = [0, 3, 4, 3, 0]

var font: Gen2Font = null
var frame_style: int = 0
## The two background strips and the two object ones, as index runs.
var _background_tiles: PackedByteArray = PackedByteArray()
var _object_tiles: PackedByteArray = PackedByteArray()
var _tilemap: PackedByteArray = PackedByteArray()
var _palettes: Array[PackedColorArray] = []


static func from_data(data: GameData) -> Gen2SlotMachinePage:
	if data == null or not data.has_slots():
		return null
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	var one: PackedByteArray = data.slots_indices("slots_1")
	var two: PackedByteArray = data.slots_indices("slots_2")
	var three: PackedByteArray = data.slots_indices("slots_3")
	var map: PackedByteArray = data.slots_tilemap()
	if glyphs == null or one.is_empty() or two.is_empty() or three.is_empty() \
		or map.size() < RomLayout.SLOTS_TILEMAP_BYTES:
		return null

	var page := Gen2SlotMachinePage.new()
	page.font = glyphs
	page.frame_style = Gen2OptionsStore.current().textbox_frame
	page._tilemap = map
	page._background_tiles = _bank(
		[[SLOTS_1_FIRST_TILE, one], [SLOTS_2_FIRST_TILE, two]]
	)
	page._object_tiles = _bank(
		[[OBJECT_SLOTS_2_FIRST_TILE, two], [OBJECT_SLOTS_3_FIRST_TILE, three]]
	)
	for index: int in RomLayout.SLOTS_PALETTES:
		page._palettes.append(data.slots_palette(index))
	return page


## One VRAM half as a strip of 128 tiles, each run laid at its own first tile
## the way `.InitGFX` decompresses it. A strip is one row of tiles, so a tile is
## a column of it and not a run of 64 bytes.
static func _bank(runs: Array) -> PackedByteArray:
	var bank := PackedByteArray()
	bank.resize(BANK_WIDTH * TILE)
	for run: Array in runs:
		var first: int = int(run[0])
		var strip: PackedByteArray = run[1]
		@warning_ignore("integer_division")
		var tiles: int = strip.size() / Gen2Tiles.TILE_PIXELS
		var strip_width: int = tiles * TILE
		for tile: int in tiles:
			var column: int = (first + tile) * TILE
			if column + TILE > BANK_WIDTH:
				continue
			for row: int in TILE:
				for pixel: int in TILE:
					bank[row * BANK_WIDTH + column + pixel] = strip[
						row * strip_width + tile * TILE + pixel
					]
	return bank


func ready() -> bool:
	return not _tilemap.is_empty() and not _palettes.is_empty()


## `_CGB_SlotMachine`'s attrmap: `WipeAttrmap` and then its own nine boxes, with
## every row from twelve down filled with the text palette.
func attributes() -> PackedInt32Array:
	var slots := PackedInt32Array()
	slots.resize(SCREEN_COLUMNS * SCREEN_ROWS)
	for box: Array in ATTRIBUTE_BOXES:
		for row: int in int(box[3]):
			for column: int in int(box[2]):
				var y: int = int(box[1]) + row
				var x: int = int(box[0]) + column
				if x < SCREEN_COLUMNS and y < SCREEN_ROWS:
					slots[y * SCREEN_COLUMNS + x] = int(box[4])
	for cell: int in range(TEXTBOX_AT.y * SCREEN_COLUMNS, slots.size()):
		slots[cell] = TEXT_PALETTE
	return slots


## The whole screen for [param machine]. [param state] is what the host holds
## over it:
##
## [codeblock]
## {
##   "text": String,   # the box under the machine, empty for none
##   "menu": int,      # which bet row the cursor is on, 0 for no menu
##   "yes_no": int,    # 1 or 2 while the play-again box is up, 0 for none
## }
## [/codeblock]
func render(machine: Gen2SlotMachine, state: Dictionary = {}) -> Image:
	if not ready():
		return null
	var indices := PackedByteArray()
	indices.resize(WIDTH * HEIGHT)
	var map: PackedByteArray = tilemap(machine)
	for row: int in RomLayout.SLOTS_TILEMAP_ROWS:
		for column: int in SCREEN_COLUMNS:
			_blit_background(
				indices, int(map[row * SCREEN_COLUMNS + column]),
				Vector2i(column * TILE, row * TILE)
			)
	_draw_boxes(indices, machine, state)

	var image: Image = Gen2PicImage.from_attributes(
		indices, WIDTH, HEIGHT, attributes(), SCREEN_COLUMNS, _background_palettes()
	)
	_draw_objects(image, machine, indices)
	return image


func _background_palettes() -> Array:
	var out: Array = []
	for index: int in FIRST_OBJECT_PALETTE:
		out.append(_palettes[index] if index < _palettes.size() else PackedColorArray())
	return out


## `SlotsTilemap` with the bet lights and the two counts written over it, which
## is every background write `SlotsLoop` makes.
func tilemap(machine: Gen2SlotMachine) -> PackedByteArray:
	var map: PackedByteArray = _tilemap.duplicate()
	_place_lights(map, machine.bet() if machine != null else 0)
	_place_number(map, COINS_AT, machine.coins() if machine != null else 0)
	_place_number(map, PAYOUT_AT, machine.payout() if machine != null else 0)
	return map


## `Slots_IlluminateBetLights`: the rows the bet reaches take the lit tile and
## every row takes the dark one, which is `Slots_DeilluminateBetLights` running
## over all five.
func _place_lights(map: PackedByteArray, bet: int) -> void:
	var lit: Array = LIGHT_ROWS[clampi(bet - 1, 0, LIGHT_ROWS.size() - 1)] if bet > 0 \
		else []
	for row: int in LIGHT_ROWS[LIGHT_ROWS.size() - 1]:
		_place_light(map, row, LIGHT_ON_TILE if lit.has(row) else LIGHT_OFF_TILE)


func _place_light(map: PackedByteArray, row: int, tile: int) -> void:
	for column: int in [LIGHT_COLUMN, LIGHT_COLUMN + LIGHT_COLUMN_STEP]:
		_write(map, Vector2i(column, row), tile)
		_write(map, Vector2i(column, row + 1), tile + 1)


## `PrintNum` with `PRINTNUM_LEADINGZEROS`, which is the digits as characters.
func _place_number(map: PackedByteArray, at: Vector2i, value: int) -> void:
	var digits: String = str(clampi(value, 0, 9999)).lpad(COUNT_DIGITS, "0")
	var codes: PackedByteArray = Gen2Text.encode(digits)
	for index: int in mini(codes.size(), COUNT_DIGITS):
		_write(map, at + Vector2i(index, 0), int(codes[index]))


func _write(map: PackedByteArray, at: Vector2i, tile: int) -> void:
	if at.x < 0 or at.x >= SCREEN_COLUMNS or at.y < 0 \
		or at.y >= RomLayout.SLOTS_TILEMAP_ROWS:
		return
	map[at.y * SCREEN_COLUMNS + at.x] = tile


## A background cell: a code under the font's own first is one of the two slots
## strips, and anything above it is a character.
func _blit_background(into: PackedByteArray, code: int, at: Vector2i) -> void:
	## The window is signed here, so a BG tile from $80 up is the font's own half
	## and anything below it is the slots' sheets, which is why `.InitGFX` loads
	## no font and the counts still print.
	if code >= RomLayout.FONT_FIRST_CODE:
		font.draw_code(code, into, WIDTH, at.x, at.y)
		return
	Gen2Font.blit_slot(_background_tiles, BANK_WIDTH, code, into, WIDTH, at.x, at.y)


## The text box and the two menus over it, which are `PrintText`'s own and
## `Slots_AskBet`'s.
func _draw_boxes(
	into: PackedByteArray, machine: Gen2SlotMachine, state: Dictionary
) -> void:
	var text: String = String(state.get("text", ""))
	if not text.is_empty():
		_fill_interior(into, TEXTBOX_AT, TEXTBOX_SIZE)
		font.draw_box(
			frame_style, into, WIDTH, TEXTBOX_AT.x * TILE, TEXTBOX_AT.y * TILE,
			TEXTBOX_SIZE.x, TEXTBOX_SIZE.y
		)
		var line: int = 0
		for row: String in text.split("\n"):
			font.draw_text(
				row, into, WIDTH, TEXT_AT.x * TILE,
				(TEXT_AT.y + line * TEXT_SPACING) * TILE
			)
			line += 1
	if machine != null and machine.matched() != Gen2SlotMachine.SLOTS_NO_MATCH \
		and not text.is_empty():
		_draw_payout_icon(into, machine.matched())
	var menu: int = int(state.get("menu", 0))
	if menu > 0:
		_draw_bet_menu(into, menu)
	var yes_no: int = int(state.get("yes_no", 0))
	if yes_no > 0:
		_draw_yes_no(into, yes_no)


## `.Text_PrintPayout`: `wSlotMatched + $25` and the three tiles behind it, down
## the column and then across, which is the symbol drawn beside its own line.
func _draw_payout_icon(into: PackedByteArray, matched: int) -> void:
	var first: int = PAYOUT_ICON_FIRST_TILE + matched
	var cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)
	]
	for index: int in cells.size():
		var at: Vector2i = PAYOUT_ICON_AT + cells[index]
		Gen2Font.blit_slot(
			_background_tiles, BANK_WIDTH, first + index, into, WIDTH,
			at.x * TILE, at.y * TILE
		)


## `Textbox`'s and `MenuBox`'s own `ClearBox`: the interior is blanked before
## anything is written into it, which is what keeps the machine from showing
## through the box standing over it. The blank is $7f, which draws as index 0.
func _fill_interior(into: PackedByteArray, at: Vector2i, box: Vector2i) -> void:
	for row: int in (box.y - 2) * TILE:
		var y: int = (at.y + 1) * TILE + row
		for pixel: int in (box.x - 2) * TILE:
			var x: int = (at.x + 1) * TILE + pixel
			if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
				continue
			into[y * WIDTH + x] = 0


func _draw_bet_menu(into: PackedByteArray, cursor: int) -> void:
	_fill_interior(into, BET_MENU_AT, BET_MENU_SIZE)
	font.draw_box(
		frame_style, into, WIDTH, BET_MENU_AT.x * TILE, BET_MENU_AT.y * TILE,
		BET_MENU_SIZE.x, BET_MENU_SIZE.y
	)
	for index: int in BET_MENU_ITEMS.size():
		var y: int = (BET_MENU_AT.y + BET_MENU_FIRST_ROW + index * TEXT_SPACING) * TILE
		if index == cursor - 1:
			font.draw_code(CURSOR_CODE, into, WIDTH, (BET_MENU_AT.x + 1) * TILE, y)
		font.draw_text(
			BET_MENU_ITEMS[index], into, WIDTH, (BET_MENU_AT.x + 2) * TILE, y
		)


func _draw_yes_no(into: PackedByteArray, cursor: int) -> void:
	_fill_interior(into, YES_NO_AT, YES_NO_SIZE)
	font.draw_box(
		frame_style, into, WIDTH, YES_NO_AT.x * TILE, YES_NO_AT.y * TILE,
		YES_NO_SIZE.x, YES_NO_SIZE.y
	)
	var rows: Array[String] = ["YES", "NO"]
	for index: int in rows.size():
		var y: int = (YES_NO_AT.y + YES_NO_FIRST_ROW + index * TEXT_SPACING) * TILE
		if index == cursor - 1:
			font.draw_code(CURSOR_CODE, into, WIDTH, (YES_NO_AT.x + 1) * TILE, y)
		font.draw_text(rows[index], into, WIDTH, (YES_NO_AT.x + 2) * TILE, y)


## Shadow OAM, one buffer per object palette so each is drawn through its own
## four colours, and the lower index wins a pixel the way the hardware does.
func _draw_objects(
	image: Image, machine: Gen2SlotMachine, background: PackedByteArray
) -> void:
	if machine == null:
		return
	var buffers: Dictionary = {}
	for reel: Gen2SlotMachine.Reel in machine.reels():
		_draw_reel(buffers, reel, background)
	if not machine.golem().is_empty():
		_draw_golem(buffers, machine.golem())
	if not machine.chansey().is_empty():
		_draw_chansey(buffers, machine.chansey())
	if not machine.egg().is_empty():
		_draw_egg(buffers, machine.egg())
	var palettes: Array = _palettes
	for palette: int in buffers:
		var colors: PackedColorArray = palettes[
			clampi(FIRST_OBJECT_PALETTE + palette, 0, palettes.size() - 1)
		]
		if machine.objects_inverted():
			colors = _inverted(colors)
		image.blend_rect(
			Gen2PicImage.from_indices(buffers[palette], WIDTH, HEIGHT, colors, true),
			Rect2i(0, 0, WIDTH, HEIGHT), Vector2i.ZERO
		)


## `SlotsAction_FlashScreen`'s `xor $ff` on `rOBP0`, which `DmgToCgbObjPals`
## turns into the palette's own order reversed.
static func _inverted(colors: PackedColorArray) -> PackedColorArray:
	var out := PackedColorArray()
	for index: int in colors.size():
		out.append(colors[colors.size() - 1 - index])
	return out


## `Slots_UpdateReelPositionAndOAM`'s eight objects: two columns of four, each
## eight by sixteen, and the palette taken off the symbol's own tile number.
func _draw_reel(
	buffers: Dictionary, reel: Gen2SlotMachine.Reel, background: PackedByteArray
) -> void:
	for row: int in reel.object_symbols.size():
		var symbol: int = reel.object_symbols[row]
		var y: int = reel.object_y[row * 2] if row * 2 < reel.object_y.size() else 0
		var palette: int = symbol >> 2
		for column: int in 2:
			_blit_object(
				buffers, palette, symbol + column * 2,
				Vector2i(reel.x + column * TILE, y) - OAM_ORIGIN, false, true,
				false, background
			)


## `Slots_AnimateGolem`'s object: the frameset's own flips, the fall's y offset
## and the roll's x, with `hSCY` moving the whole screen rather than the object.
func _draw_golem(buffers: Dictionary, golem: Dictionary) -> void:
	var frame: Array = GOLEM_FRAMES[
		(int(golem.get("frames", 0)) / FRAME_LENGTH) % GOLEM_FRAMES.size()
	]
	var at: Vector2i = GOLEM_SPAWN + Vector2i(
		int(golem.get("x", 0)), _signed(int(golem.get("y", 0)))
	)
	for object: Array in GOLEM_OBJECTS:
		_blit_object(
			buffers, GOLEM_PALETTE, int(frame[0]) + int(object[2]),
			at + Vector2i(int(object[0]), int(object[1])) - OAM_ORIGIN,
			bool(object[3]) != bool(frame[1]), bool(frame[2]), true
		)


func _draw_chansey(buffers: Dictionary, chansey: Dictionary) -> void:
	var second: bool = int(chansey.get("frameset", 0)) == 1
	var order: Array = CHANSEY_FRAMES_2 if second else CHANSEY_FRAMES
	var frame: int = order[(int(chansey.get("frames", 0)) / FRAME_LENGTH) % order.size()]
	var at: Vector2i = CHANSEY_SPAWN + Vector2i(int(chansey.get("x", 0)), 0)
	if frame >= CHANSEY_BOTTOMS.size():
		for object: Array in CHANSEY_LAST_SET:
			_blit_object(
				buffers, CHANSEY_PALETTE, int(object[2]),
				at + Vector2i(int(object[0]), int(object[1])) - OAM_ORIGIN, false, true
			)
		return
	for object: Array in CHANSEY_TOP:
		_blit_object(
			buffers, CHANSEY_PALETTE, int(object[2]),
			at + Vector2i(int(object[0]), int(object[1])) - OAM_ORIGIN, false, true
		)
	var bottom: Array = CHANSEY_BOTTOMS[frame]
	for column: int in bottom.size():
		_blit_object(
			buffers, CHANSEY_PALETTE, int(bottom[column]),
			at + Vector2i(-12 + column * TILE, 4) - OAM_ORIGIN, false, true
		)


func _draw_egg(buffers: Dictionary, egg: Dictionary) -> void:
	_blit_object(
		buffers, EGG_PALETTE, EGG_TILE,
		Vector2i(int(egg.get("x", 0)), int(egg.get("y", 0)) + _signed(
			int(egg.get("offset", 0))
		)) - OAM_ORIGIN, false, true
	)


## An eight by sixteen object: the tile and the one behind it, into the buffer
## its palette owns.
func _blit_object(
	buffers: Dictionary, palette: int, tile: int, at: Vector2i,
	flip_x: bool = false, tall: bool = true, flip_y: bool = false,
	behind: PackedByteArray = PackedByteArray()
) -> void:
	if not buffers.has(palette):
		var buffer := PackedByteArray()
		buffer.resize(WIDTH * HEIGHT)
		buffers[palette] = buffer
	var into: PackedByteArray = buffers[palette]
	var top: int = tile & 0xFE if tall else tile
	_blit_tile(into, top + (1 if flip_y and tall else 0), at, flip_x, flip_y, behind)
	if tall:
		_blit_tile(
			into, top + (0 if flip_y else 1), at + Vector2i(0, TILE), flip_x, flip_y,
			behind
		)


## [param behind] is the background a priority object is tested against:
## `.LoadOAM` sets `B_OAM_PRIO` on every reel sprite, so a symbol draws over the
## window's own colour 0 and disappears behind the machine either side of it.
func _blit_tile(
	into: PackedByteArray, tile: int, at: Vector2i, flip_x: bool, flip_y: bool,
	behind: PackedByteArray = PackedByteArray()
) -> void:
	var first: int = tile * TILE
	if tile < 0 or first + TILE > BANK_WIDTH:
		return
	for row: int in TILE:
		var y: int = at.y + (TILE - 1 - row if flip_y else row)
		if y < 0 or y >= HEIGHT:
			continue
		for pixel: int in TILE:
			var x: int = at.x + (TILE - 1 - pixel if flip_x else pixel)
			if x < 0 or x >= WIDTH:
				continue
			## Colour 0 is transparent for an object, which is what lets the
			## background through between two symbols.
			var index: int = _object_tiles[row * BANK_WIDTH + first + pixel]
			if index == 0:
				continue
			if not behind.is_empty() and behind[y * WIDTH + x] != 0:
				continue
			into[y * WIDTH + x] = index


## An OAM offset is a byte and a y or x offset past $7f is negative.
static func _signed(value: int) -> int:
	return value - 256 if value >= 0x80 else value
