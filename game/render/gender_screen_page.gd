class_name Gen2GenderScreenPage
extends RefCounted

## `engine/menus/init_gender.asm`'s screen on the hardware tile grid: the
## question in the standard text box and the two-option menu over it.
##
## Positions are the source's own. The menu is [Gen2MenuPage]'s, drawn from
## `.MenuHeader`'s `menu_coords 6, 4, 12, 9` and its three flags, so nothing
## about the box is decided here.
##
## Crystal only, since pokegold ships neither the routine nor its text.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

## `.MenuHeader`: `menu_coords 6, 4, 12, 9`, STATICMENU_CURSOR | STATICMENU_WRAP
## | STATICMENU_DISABLE_B, two items, default option 1.
const MENU_LEFT: int = 6
const MENU_TOP: int = 4
const MENU_RIGHT: int = 12
const MENU_BOTTOM: int = 9
const MENU_FLAGS: int = (
	Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_WRAP
	| Gen2MenuBox.STATICMENU_DISABLE_B
)
## `.MenuData`'s two items, in its own order, so index 0 is Boy and 1 is Girl,
## which is what `ld a, [wMenuCursorY] / dec a` writes into wPlayerGender.
const OPTIONS: Array[String] = ["Boy", "Girl"]

## `PrintText`'s standard box, which is where the question lands.
const TEXT_BOX: Rect2i = Rect2i(0, 12, 20, 6)
const TEXT_AT: Vector2i = Vector2i(1, 14)
const LINE_SPACING: int = 2

var frame_style: int = 0
var font: Gen2Font = null
## `LoadGenderScreenPal`'s four colours, in its own order.
var palette: PackedColorArray = PackedColorArray()

var _menu: Gen2MenuPage = null
var _fill: int = 0


static func from_data(data: GameData) -> Gen2GenderScreenPage:
	var menu: Gen2MenuPage = Gen2MenuPage.from_data(data)
	if menu == null:
		return null
	var out := Gen2GenderScreenPage.new()
	out.font = menu.font
	out._menu = menu
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	out.palette = data.gender_screen_palette()
	out._fill = _fill_index(data)
	return out


## The one index `LoadGenderScreenLightBlueTile`'s tile carries, read from the
## imported tile rather than assumed, so a cache holding a different tile draws
## what it holds.
static func _fill_index(data: GameData) -> int:
	if data.tile_sheet("gender_screen").is_empty():
		return 0
	var tile: PackedByteArray = data.tile_indices("gender_screen")
	return 0 if tile.is_empty() else tile[0]


static func menu_box() -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(MENU_LEFT, MENU_TOP, MENU_RIGHT, MENU_BOTTOM, MENU_FLAGS)


## The whole 160x144 page as palette indices, with the arrow on [param cursor].
##
## `InitGenderScreen` ByteFills the whole tilemap with tile $00, which
## `LoadGenderScreenLightBlueTile` has just filled with one colour, so the field
## behind the box and the menu is that index rather than a blank.
func draw(question: String, cursor: int) -> PackedByteArray:
	var width: int = COLUMNS * TILE
	var indices := PackedByteArray()
	indices.resize(width * ROWS * TILE)
	if _fill != 0:
		indices.fill(_fill)
	if font == null:
		return indices

	_blank_interior(indices, width, TEXT_BOX)
	font.draw_box(
		frame_style, indices, width,
		TEXT_BOX.position.x * TILE, TEXT_BOX.position.y * TILE,
		TEXT_BOX.size.x, TEXT_BOX.size.y
	)
	var line: int = 0
	for text: String in question.split("\n"):
		font.draw_text(
			text, indices, width,
			TEXT_AT.x * TILE, (TEXT_AT.y + line * LINE_SPACING) * TILE
		)
		line += 1

	_menu.draw(menu_box(), OPTIONS, cursor, indices, width)
	return indices


## `TextboxBorder`'s own `' '` run across the interior rows, which is what keeps
## the field from showing through a box drawn over it. Elsewhere the buffer is
## already blank, so only a filled page needs this.
func _blank_interior(indices: PackedByteArray, width: int, box: Rect2i) -> void:
	for row: int in range((box.position.y + 1) * TILE, (box.position.y + box.size.y - 1) * TILE):
		var at: int = row * width + (box.position.x + 1) * TILE
		for column: int in (box.size.x - 2) * TILE:
			indices[at + column] = 0
