class_name Gen2StartMenuPage
extends RefCounted

## `StartMenu`'s own box over the map, the `_Option` screen behind it, and
## `SaveMenu`'s three boxes over the map as well.
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

## `DisplaySaveInfoOnSave`'s `lb de, 4, 0` through `_OffsetMenuHeader`, which
## keeps `menu_coords 0, 0, 15, 9`'s span and moves its left edge to column 4.
const SAVE_INFO_LEFT: int = 4
const SAVE_INFO_TOP: int = 0
const SAVE_INFO_RIGHT: int = 19
const SAVE_INFO_BOTTOM: int = 9
## `.MenuData_Dex`'s own `db 0`: no cursor, no title and the ordinary top
## spacing, so the four rows start at (5, 2) and step two.
const SAVE_INFO_FLAGS: int = 0
## `Continue_DisplayBadgesDexPlayerName`'s three `decoord`s and
## `Continue_PrintGameTime`'s, each an offset from `MenuBoxCoord2Tile`'s corner
## and so four columns right of what the source writes.
const SAVE_NAME_AT: Vector2i = Vector2i(SAVE_INFO_LEFT + 8, 2)
const SAVE_BADGES_AT: Vector2i = Vector2i(SAVE_INFO_LEFT + 13, 4)
const SAVE_DEX_AT: Vector2i = Vector2i(SAVE_INFO_LEFT + 12, 6)
const SAVE_TIME_AT: Vector2i = Vector2i(SAVE_INFO_LEFT + 9, 8)
## Each value's `PrintNum` width: `lb bc, 1, 2` for the badges, `1, 3` for the
## dex count and `2, 3` then `PRINTNUM_LEADINGZEROS | 1, 2` for the timer.
const SAVE_BADGE_CELLS: int = 2
const SAVE_DEX_CELLS: int = 3
const SAVE_HOUR_CELLS: int = 3

## `SpeechTextbox`: `hlcoord 0, 12` with `TEXTBOX_INNERH`/`TEXTBOX_INNERW`, and
## `PrintText`'s own two rows inside it.
const SAVE_TEXTBOX_AT: Vector2i = Vector2i(0, 12)
const SAVE_TEXTBOX_SIZE: Vector2i = Vector2i(20, 6)
const SAVE_TEXT_AT: Vector2i = Vector2i(1, 14)
const SAVE_TEXT_SPACING: int = 2
## How many of a text's lines the box shows at once, which is what makes
## `_ContText` a scroll rather than a third row.
const SAVE_TEXT_ROWS: int = 2

## `SaveTheGame_yesorno`'s `lb bc, 0, 7` into `_YesNoBox`, which stores the left
## coordinate, adds 5 for the right, the top, and adds 4 for the bottom.
## `YesNoMenuHeader.MenuData` is where the flags and the two strings come from.
const SAVE_YES_NO_AT: Vector2i = Vector2i(0, 7)
const SAVE_YES_NO_SPAN: Vector2i = Vector2i(5, 4)
const SAVE_YES_NO_FLAGS: int = (
	Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_NO_TOP_SPACING
)
const SAVE_YES_NO_OPTIONS: Array[String] = ["YES", "NO"]

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
	_blit(image, menu.render(box, labels, cursor), box.border_position())
	if not description.is_empty():
		_blit(image, _render_account(description), ACCOUNT_AT)
	return image


## `SaveMenu`'s screen: `DisplaySaveInfoOnSave`'s box in the top-right,
## `SpeechTextbox` at the foot, and `PlaceYesNoBox`'s own box on the left when a
## question is up. Transparent everywhere else, since the map stays behind it.
##
## [param state] is what [Gen2StartMenuScreen] holds:
##
## [codeblock]
## {
##   "player_name": String,
##   "badges": int,
##   "pokedex": bool,     # STATUSFLAGS_POKEDEX_F, which blanks the #DEX row
##   "caught": int,
##   "hours": int, "minutes": int,
##   "lines": Array,      # the text's own lines, whole
##   "line": int,         # which of them is on the box's top row
##   "cursor": int,       # -1 while no yes/no box is up
## }
## [/codeblock]
func render_save(state: Dictionary) -> Image:
	if menu == null or font == null:
		return null
	var image: Image = Image.create_empty(
		Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8
	)
	_blit(image, _render_save_info(state), Vector2i(SAVE_INFO_LEFT, SAVE_INFO_TOP))
	_blit(image, _render_save_textbox(state), SAVE_TEXTBOX_AT)
	var cursor: int = int(state.get("cursor", -1))
	if cursor >= 0:
		var box: Gen2MenuBox = Gen2MenuBox.from_coords(
			SAVE_YES_NO_AT.x, SAVE_YES_NO_AT.y,
			SAVE_YES_NO_AT.x + SAVE_YES_NO_SPAN.x,
			SAVE_YES_NO_AT.y + SAVE_YES_NO_SPAN.y, SAVE_YES_NO_FLAGS
		)
		_blit(image, menu.render(box, SAVE_YES_NO_OPTIONS, cursor), SAVE_YES_NO_AT)
	return image


## `Continue_LoadMenuHeader`'s four rows and the three values
## `Continue_DisplayBadgesDexPlayerName` prints over them. `.MenuData_NoDex`
## blanks the third row's label, and `Continue_DisplayPokedexNumCaught` returns
## before its own `PrintNum`, so a player without the Pokedex is shown neither.
func _render_save_info(state: Dictionary) -> Image:
	var dex: bool = bool(state.get("pokedex", false))
	var box: Gen2MenuBox = Gen2MenuBox.from_coords(
		SAVE_INFO_LEFT, SAVE_INFO_TOP, SAVE_INFO_RIGHT, SAVE_INFO_BOTTOM,
		SAVE_INFO_FLAGS
	)
	var extras: Array = [
		{"text": String(state.get("player_name", "")), "at": SAVE_NAME_AT},
		{
			"text": ("%d" % int(state.get("badges", 0))).lpad(SAVE_BADGE_CELLS),
			"at": SAVE_BADGES_AT,
		},
		{
			"text": "%s:%02d" % [
				("%d" % int(state.get("hours", 0))).lpad(SAVE_HOUR_CELLS),
				int(state.get("minutes", 0)),
			],
			"at": SAVE_TIME_AT,
		},
	]
	if dex:
		extras.append({
			"text": ("%d" % int(state.get("caught", 0))).lpad(SAVE_DEX_CELLS),
			"at": SAVE_DEX_AT,
		})
	return menu.render(
		box, ["PLAYER", "BADGES", "#DEX" if dex else " ", "TIME"], -1, "", 0, extras
	)


## The speech box and the two lines of the text standing in it. A text longer
## than the box is scrolled by [code]state["line"][/code], which is what
## `_ContText` does to `AlreadyASaveFileText`'s third line.
func _render_save_textbox(state: Dictionary) -> Image:
	var width: int = SAVE_TEXTBOX_SIZE.x * TILE
	var indices := PackedByteArray()
	indices.resize(width * SAVE_TEXTBOX_SIZE.y * TILE)
	font.draw_box(
		frame_style, indices, width, 0, 0, SAVE_TEXTBOX_SIZE.x, SAVE_TEXTBOX_SIZE.y
	)
	var lines: Array = state.get("lines", [])
	var first: int = maxi(int(state.get("line", 0)), 0)
	var at: Vector2i = SAVE_TEXT_AT - SAVE_TEXTBOX_AT
	for row: int in SAVE_TEXT_ROWS:
		var index: int = first + row
		if index < 0 or index >= lines.size():
			continue
		font.draw_text(
			String(lines[index]), indices, width,
			at.x * TILE, (at.y + row * SAVE_TEXT_SPACING) * TILE
		)
	return Gen2PicImage.from_indices(
		indices, width, SAVE_TEXTBOX_SIZE.y * TILE, _palette()
	)


func _blit(into: Image, part: Image, at: Vector2i) -> void:
	if part == null:
		return
	into.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), at * TILE)


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
