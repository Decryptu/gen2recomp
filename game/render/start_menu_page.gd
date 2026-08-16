class_name Gen2StartMenuPage
extends RefCounted

## `StartMenu`'s own box over the map, and the `_Option` screen behind it.
##
## Node-free presentation, like the other pages: geometry is [Gen2MenuBox]'s and
## the models are [Gen2WorldStartMenu] and [Gen2WorldOptionsMenu]. The list is a
## box in the top-right of the map with the map still showing around it, so it
## is drawn as a transparent overlay; OPTION owns the whole screen.

const TILE: int = Gen2Font.TILE
## The hardware tile grid, which every page in here counts in.
const COLUMNS: int = 20
const ROWS: int = 18

## `.MenuHeader`'s `menu_coords 10, 0, SCREEN_WIDTH - 1, SCREEN_HEIGHT - 1`, and
## `.ContestMenuHeader`, which is the same box two rows down.
const LIST_LEFT: int = 10
const LIST_RIGHT: int = COLUMNS - 1
const LIST_TOP: int = 0
const LIST_CONTEST_TOP: int = 2
## `.MenuData`'s own flags.
const LIST_FLAGS: int = (
	Gen2MenuBox.STATICMENU_CURSOR
	| Gen2MenuBox.STATICMENU_WRAP
	| Gen2MenuBox.STATICMENU_ENABLE_START
)

## `._DrawMenuAccount`'s `ClearBox` at `hlcoord 0, 13`, five rows of ten, and
## `.PrintMenuAccount`'s `decoord 0, 14` for the description itself. There is no
## frame around it: the routine clears the block and sets its palette, and the
## words stand on the cleared tiles.
const ACCOUNT_AT: Vector2i = Vector2i(0, 13)
const ACCOUNT_SIZE: Vector2i = Vector2i(10, 5)
const ACCOUNT_TEXT_ROW: int = 14

## `_Option`'s `Textbox` at `hlcoord 0, 0` with `b = SCREEN_HEIGHT - 2` and
## `c = SCREEN_WIDTH - 2`, which is a border around the whole screen.
const OPTIONS_FIRST_ROW: int = 2
const OPTIONS_LABEL_COLUMN: int = 2
## `StringOptions`' own `"        :"` row under each label.
const OPTIONS_COLON_COLUMN: int = 10
## Every `hlcoord 11, n` in the file, and `UpdateFrame`'s digit lands on 16
## because the value it draws opens with `TYPE `.
const OPTIONS_VALUE_COLUMN: int = 11
## `Options_UpdateCursorPosition` walks column 1 by two rows per option.
const OPTIONS_CURSOR_COLUMN: int = 1

var frame_style: int = 0
var font: Gen2Font = null
var menu: Gen2MenuPage = null


static func from_data(data: GameData) -> Gen2StartMenuPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	var box: Gen2MenuPage = Gen2MenuPage.from_data(data)
	if glyphs == null or box == null:
		return null
	var out := Gen2StartMenuPage.new()
	out.font = glyphs
	out.menu = box
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	return out


## `AutomaticGetMenuBottomCoord`: the box grows downward by two rows an entry
## plus its own border, so the header's bottom coordinate is never read.
static func list_box(count: int, contest: bool = false) -> Gen2MenuBox:
	var top: int = LIST_CONTEST_TOP if contest else LIST_TOP
	return Gen2MenuBox.from_coords(
		LIST_LEFT, top, LIST_RIGHT, top + 2 * maxi(count, 0) + 1, LIST_FLAGS
	)


## The menu over the map: the whole screen, transparent everywhere the map is
## still showing. [param description] is `.MenuDesc`'s two lines and is drawn
## only when MENU ACCOUNT is on, which is what `.IsMenuAccountOn` decides.
func render_list(
	labels: Array, cursor: int, description: String = "", contest: bool = false
) -> Image:
	if menu == null or font == null:
		return null
	var image: Image = Image.create_empty(
		Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8
	)
	var box: Gen2MenuBox = list_box(labels.size(), contest)
	var drawn: Image = menu.render(box, labels, cursor)
	if drawn != null:
		image.blit_rect(
			drawn, Rect2i(Vector2i.ZERO, drawn.get_size()),
			box.border_position() * TILE
		)
	if not description.is_empty():
		var account: Image = _render_account(description)
		if account != null:
			image.blit_rect(
				account, Rect2i(Vector2i.ZERO, account.get_size()), ACCOUNT_AT * TILE
			)
	return image


## `_Option`'s whole screen: the border, `StringOptions` and each row's own
## setting, with `Options_UpdateCursorPosition`'s arrow beside the chosen one.
func render_options(rows: Array, cursor: int) -> Image:
	if font == null:
		return null
	var indices := PackedByteArray()
	indices.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	font.draw_box(
		frame_style, indices, Gen2Screen.WIDTH, 0, 0,
		COLUMNS, ROWS
	)
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var label_row: int = OPTIONS_FIRST_ROW + 2 * index
		_text(indices, String(row.get("label", "")), OPTIONS_LABEL_COLUMN, label_row)
		var value: String = String(row.get("value", ""))
		if value.is_empty():
			continue
		_text(indices, ":", OPTIONS_COLON_COLUMN, label_row + 1)
		_text(indices, value, OPTIONS_VALUE_COLUMN, label_row + 1)
	if cursor >= 0 and cursor < rows.size():
		font.draw_code(
			Gen2MenuPage.CURSOR_CODE, indices, Gen2Screen.WIDTH,
			OPTIONS_CURSOR_COLUMN * TILE, (OPTIONS_FIRST_ROW + 2 * cursor) * TILE
		)
	return Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, _palette()
	)


## The account block, which is cleared tiles and two rows of words rather than a
## box: `ClearBox` writes the source's own blank, which draws as index 0.
func _render_account(description: String) -> Image:
	var width: int = ACCOUNT_SIZE.x * TILE
	var indices := PackedByteArray()
	indices.resize(width * ACCOUNT_SIZE.y * TILE)
	var row: int = ACCOUNT_TEXT_ROW - ACCOUNT_AT.y
	for line: String in description.split("\n"):
		font.draw_text(line, indices, width, 0, row * TILE)
		row += 1
	return Gen2PicImage.from_indices(
		indices, width, ACCOUNT_SIZE.y * TILE, _palette()
	)


func _text(indices: PackedByteArray, text: String, column: int, row: int) -> void:
	font.draw_text(text, indices, Gen2Screen.WIDTH, column * TILE, row * TILE)


## `PAL_BG_TEXT`, which is what every one of these boxes is drawn with.
func _palette() -> PackedColorArray:
	return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
