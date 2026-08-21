class_name Gen2MartPage
extends RefCounted

## `BuyMenu`'s screen (`engine/items/mart.asm`): `BlankScreen`, the money box
## `PlaceMoneyTopRight` puts in the corner, `MenuHeader_Buy`'s scrolling list of
## names and BCD prices, and the speech box `UpdateItemDescription` writes into.
##
## [Gen2WorldMartHost] owns the list, the money and the transaction; this is the
## picture, and node-free so it can be read back headless. The quantity box is
## `BuyItem_MenuHeader`, which stands over the speech box rather than replacing
## it, and the yes/no over it is the host's own [Gen2MenuPage].
##
## Three things the source does that a redraw here has to keep:
##
## - `ScrollingMenu` draws no frame around the list. Only `ClearWholeMenuBox`
##   runs, so the names sit on the blank screen and the arrows stand where a
##   border would have been.
## - The fourth row's price lands on the box's own bottom coordinate, row 11,
##   because `.PrintBCDPrices` prints one row below a name that is already on
##   the last row the height allows.
## - `▼` is drawn whenever the list has arrows at all, while `▲` waits for
##   `wMenuScrollPosition` to leave zero.

const TILE: int = Gen2Font.TILE

## `MoneyTopRightMenuHeader`: `menu_coords 11, 0, SCREEN_WIDTH - 1, 2`, with
## `PlaceMoneyTextbox` printing `SCREEN_WIDTH + 1` past the border coordinate.
const MONEY_AT: Vector2i = Vector2i(11, 0)
const MONEY_SIZE: Vector2i = Vector2i(9, 3)
const MONEY_TEXT_AT: Vector2i = Vector2i(12, 1)

## `constants/script_constants.asm`'s COIN count, printed by `PrintNum` as two
## bytes in four digits with `PlaceString`'s own leading blanks in front of it.
const COIN_DIGITS: int = 4

## The other two boxes of `engine/menus/menu_2.asm`, which the overworld's
## `special DisplayCoinCaseBalance` and `special DisplayMoneyAndCoinBalance`
## write over the map. `Textbox`, not `MenuBox`: the coin box places "COIN" at
## `hlcoord 12, 0`, which is its own top border row.
const COIN_CASE_AT: Vector2i = Vector2i(11, 0)
const COIN_CASE_SIZE: Vector2i = Vector2i(9, 3)
const COIN_CASE_LABEL_AT: Vector2i = Vector2i(12, 0)
const COIN_CASE_COUNT_AT: Vector2i = Vector2i(13, 1)
const BALANCES_AT: Vector2i = Vector2i(5, 0)
const BALANCES_SIZE: Vector2i = Vector2i(15, 5)
const BALANCES_MONEY_LABEL_AT: Vector2i = Vector2i(6, 1)
const BALANCES_MONEY_AT: Vector2i = Vector2i(12, 1)
const BALANCES_COIN_LABEL_AT: Vector2i = Vector2i(6, 3)
const BALANCES_COIN_AT: Vector2i = Vector2i(15, 3)

## `MenuHeader_Buy`: `menu_coords 1, 3, SCREEN_WIDTH - 1, TEXTBOX_Y - 1`, four
## rows of eight columns. `ScrollingMenu_InitFlags` puts the cursor on the left
## border coordinate itself and steps `$20`, which is two rows.
const LIST_AT: Vector2i = Vector2i(1, 3)
const LIST_RIGHT: int = 19
const LIST_BOTTOM: int = 11
const LIST_HEIGHT: int = 4
const NAME_AT: Vector2i = Vector2i(2, 4)
const ROW_STEP: int = 2
## `ScrollingMenu_CallFunctions1and2` steps `wMenuData_ScrollingMenuWidth` from
## the name before it calls function 2.
const PRICE_COLUMN: int = NAME_AT.x + 8

## `UpdateItemDescription`: `hlcoord 0, 12` with `lb bc, 4, SCREEN_WIDTH - 2`,
## so a six-row frame across the screen, and the description at `decoord 1, 14`.
const TEXTBOX_AT: Vector2i = Vector2i(0, 12)
const TEXTBOX_SIZE: Vector2i = Vector2i(20, 6)
const TEXT_AT: Vector2i = Vector2i(1, 14)
const TEXT_SPACING: int = 2

## `BuyItem_MenuHeader`: `menu_coords 7, 15, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1`.
## `BuySellToss_UpdateQuantityDisplay` prints `×` and two digits one row in, and
## `BuySell_DisplaySubtotal` the running total one cell past them.
const QUANTITY_AT: Vector2i = Vector2i(7, 15)
const QUANTITY_SIZE: Vector2i = Vector2i(13, 3)
const QUANTITY_TEXT_AT: Vector2i = Vector2i(8, 16)
const QUANTITY_DIGITS: int = 2
const SUBTOTAL_AT: Vector2i = Vector2i(12, 16)

## `ScrollingMenu_UpdateDisplay.CancelString`, the row a list of any length ends
## with.
const CANCEL: String = "CANCEL"

## `Place2DMenuCursor`'s "▶" and the two arrows `SCROLLINGMENU_DISPLAY_ARROWS`
## draws. The up arrow is the one code no font strip carries.
const CURSOR_CODE: int = 0xED
const DOWN_ARROW_CODE: int = 0xEE

## `PRINTNUM_MONEY` with six digits: the `¥` is printed in front of the first
## significant digit rather than at the field's left edge, so the whole thing is
## seven cells right aligned.
const MONEY_CELLS: int = 7

var font: Gen2Font = null
## Which text-box border the player chose, for the three boxes this draws.
var frame_style: int = 0
## `FontsExtra2_UpArrowGFX`, the single tile `'▲'` is drawn from.
var _up_arrow: PackedByteArray = PackedByteArray()


static func from_data(data: GameData) -> Gen2MartPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null:
		return null
	var out := Gen2MartPage.new()
	out.font = glyphs
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	out._up_arrow = data.tile_indices("up_arrow")
	return out


## The whole screen. [param state] is what the host holds:
##
## [codeblock]
## {
##   "money": int,
##   "rows": Array,      # {"name": String, "price": int} or {"cancel": true}
##   "cursor": int,      # which visible row the arrow stands on
##   "scrolled": bool,   # wMenuScrollPosition is past zero
##   "text": String,     # the speech box's lines
##   "quantity": int,    # -1 while no quantity box is up
##   "subtotal": int,
## }
## [/codeblock]
func render(state: Dictionary) -> Image:
	if font == null:
		return null
	var width: int = Gen2Screen.WIDTH
	var indices := PackedByteArray()
	indices.resize(width * Gen2Screen.HEIGHT)
	_draw_money(indices, width, int(state.get("money", 0)))
	_draw_list(indices, width, state)
	_draw_textbox(indices, width, String(state.get("text", "")))
	if int(state.get("quantity", -1)) >= 0:
		_draw_quantity(
			indices, width, int(state["quantity"]), int(state.get("subtotal", 0))
		)
	return Gen2PicImage.from_indices(
		indices, width, Gen2Screen.HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)


## `PRINTNUM_MONEY`'s own shape: `¥` against the number, the pair right aligned
## in seven cells. `PrintBCDNumber` lays the prices down the same way.
static func money_string(amount: int) -> String:
	return ("¥%d" % maxi(amount, 0)).lpad(MONEY_CELLS)


## One of the three balance windows as an image and the tile it stands at:
## `{"image": Image, "at": Vector2i}`, empty when the font is missing. The three
## are one routine's neighbours, which is why they are drawn here rather than
## beside the overworld: `PlaceMoneyTopRight` is the box this screen already
## draws and the other two are the same file's.
static func balance_window(
	data: GameData, kind: StringName, money: int, coins: int
) -> Dictionary:
	var page: Gen2MartPage = Gen2MartPage.from_data(data)
	if page == null:
		return {}
	var at: Vector2i = MONEY_AT
	var box: Vector2i = MONEY_SIZE
	match kind:
		&"coin_case":
			at = COIN_CASE_AT
			box = COIN_CASE_SIZE
		&"money_and_coins":
			at = BALANCES_AT
			box = BALANCES_SIZE
	var width: int = Gen2Screen.WIDTH
	var indices := PackedByteArray()
	indices.resize(width * Gen2Screen.HEIGHT)
	page.font.draw_box(
		page.frame_style, indices, width, at.x * TILE, at.y * TILE, box.x, box.y
	)
	match kind:
		&"coin_case":
			page._text(indices, width, "COIN", COIN_CASE_LABEL_AT)
			page._text(indices, width, coin_string(coins), COIN_CASE_COUNT_AT)
		&"money_and_coins":
			page._text(indices, width, "MONEY", BALANCES_MONEY_LABEL_AT)
			page._text(indices, width, money_string(money), BALANCES_MONEY_AT)
			page._text(indices, width, "COIN", BALANCES_COIN_LABEL_AT)
			page._text(indices, width, coin_string(coins), BALANCES_COIN_AT)
		_:
			page._text(indices, width, money_string(money), MONEY_TEXT_AT)
	var image: Image = Gen2PicImage.from_indices(
		indices, width, Gen2Screen.HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)
	return {
		"image": image.get_region(Rect2i(at * TILE, box * TILE)),
		"at": at,
	}


## `PrintNum` with `lb bc, 2, 4`: four digits, right aligned, no `¥`.
static func coin_string(coins: int) -> String:
	return ("%d" % maxi(coins, 0)).lpad(COIN_DIGITS)


func _draw_money(indices: PackedByteArray, width: int, money: int) -> void:
	font.draw_box(
		frame_style, indices, width, MONEY_AT.x * TILE, MONEY_AT.y * TILE,
		MONEY_SIZE.x, MONEY_SIZE.y
	)
	_text(indices, width, money_string(money), MONEY_TEXT_AT)


func _draw_list(indices: PackedByteArray, width: int, state: Dictionary) -> void:
	var rows: Array = state.get("rows", [])
	var cursor: int = int(state.get("cursor", 0))
	for index: int in mini(rows.size(), LIST_HEIGHT + 1):
		var row: Dictionary = rows[index]
		var at: Vector2i = NAME_AT + Vector2i(0, index * ROW_STEP)
		if bool(row.get("cancel", false)):
			_text(indices, width, CANCEL, at)
			continue
		_text(indices, width, String(row.get("name", "")), at)
		_text(
			indices, width, money_string(int(row.get("price", 0))),
			Vector2i(PRICE_COLUMN, at.y + 1)
		)
	if cursor >= 0 and cursor < mini(rows.size(), LIST_HEIGHT + 1):
		_code(
			indices, width, CURSOR_CODE,
			Vector2i(LIST_AT.x, NAME_AT.y + cursor * ROW_STEP)
		)
	if bool(state.get("scrolled", false)):
		_up(indices, width, Vector2i(LIST_RIGHT, LIST_AT.y))
	_code(indices, width, DOWN_ARROW_CODE, Vector2i(LIST_RIGHT, LIST_BOTTOM))


func _draw_textbox(indices: PackedByteArray, width: int, text: String) -> void:
	font.draw_box(
		frame_style, indices, width, TEXTBOX_AT.x * TILE, TEXTBOX_AT.y * TILE,
		TEXTBOX_SIZE.x, TEXTBOX_SIZE.y
	)
	var line: int = 0
	for row: String in text.split("\n", false):
		_text(indices, width, row, TEXT_AT + Vector2i(0, line * TEXT_SPACING))
		line += 1


func _draw_quantity(
	indices: PackedByteArray, width: int, quantity: int, subtotal: int
) -> void:
	font.draw_box(
		frame_style, indices, width, QUANTITY_AT.x * TILE, QUANTITY_AT.y * TILE,
		QUANTITY_SIZE.x, QUANTITY_SIZE.y
	)
	## `PRINTNUM_LEADINGZEROS | 1` over two digits, which is what makes a single
	## item read `×01`.
	_text(
		indices, width,
		"×%s" % String.num_int64(maxi(quantity, 0)).lpad(QUANTITY_DIGITS, "0"),
		QUANTITY_TEXT_AT
	)
	_text(indices, width, money_string(subtotal), SUBTOTAL_AT)


func _text(indices: PackedByteArray, width: int, text: String, at: Vector2i) -> void:
	font.draw_text(text, indices, width, at.x * TILE, at.y * TILE)


func _code(indices: PackedByteArray, width: int, code: int, at: Vector2i) -> void:
	font.draw_code(code, indices, width, at.x * TILE, at.y * TILE)


## `'▲'` comes off its own imported tile: it sits inside the run the battle font
## owns, so neither strip [Gen2Font] draws from can answer for it. A cache
## imported without it leaves the corner empty rather than drawing a wrong tile.
func _up(indices: PackedByteArray, width: int, at: Vector2i) -> void:
	if _up_arrow.size() < TILE * TILE:
		return
	Gen2Font.blit_slot(_up_arrow, TILE, 0, indices, width, at.x * TILE, at.y * TILE)
