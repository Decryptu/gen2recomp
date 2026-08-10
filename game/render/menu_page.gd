class_name Gen2MenuPage
extends RefCounted

## One cartridge menu box on the hardware tile grid: `MenuBox`'s frame,
## `PlaceVerticalMenuItems`' options, `PlaceMenuStrings`' title and
## `Place2DMenuCursor`'s arrow.
##
## The geometry is [Gen2MenuBox]'s and the selection [Gen2WorldMenu]'s; this is
## presentation only. Node-free, so a menu can be drawn into any buffer a screen
## already owns and read back headless: the naming screen and the gender screen
## both draw one over a page they built first.

const TILE: int = Gen2Font.TILE

## `charmap.asm`: `"▶"` is $ed, which is what `Place2DMenuCursor` writes.
const CURSOR_CODE: int = 0xED

## `Textbox` draws with wTextboxFrame, so a menu is drawn in whichever frame the
## player chose, the way the Hall of Fame panel and the world's own boxes are.
var frame_style: int = 0

var font: Gen2Font = null


static func from_data(data: GameData) -> Gen2MenuPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null:
		return null
	var out := Gen2MenuPage.new()
	out.font = glyphs
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	return out


## Draws [param box] with [param options] into [param indices], a buffer
## [param width] pixels across, with the arrow on [param cursor]. A negative
## cursor draws no arrow, which is what a menu without STATICMENU_CURSOR is.
##
## The box's interior is not cleared: `MenuBox` calls `Textbox`, which fills its
## own interior with blanks, and every caller here draws onto a buffer it has
## already filled.
func draw(
	box: Gen2MenuBox, options: Array, cursor: int,
	indices: PackedByteArray, width: int, title: String = "", title_indent: int = 0
) -> void:
	if font == null or box == null:
		return
	var size: Vector2i = box.border_size()
	var at: Vector2i = box.border_position()
	font.draw_box(frame_style, indices, width, at.x * TILE, at.y * TILE, size.x, size.y)
	_fill_interior(box, indices, width)

	if box.has_flag(Gen2MenuBox.STATICMENU_PLACE_TITLE) and title != "":
		var title_at: Vector2i = box.title_position(title_indent)
		font.draw_text(title, indices, width, title_at.x * TILE, title_at.y * TILE)

	for index: int in options.size():
		var item: Vector2i = box.item_position(index)
		font.draw_text(String(options[index]), indices, width, item.x * TILE, item.y * TILE)

	if cursor >= 0 and cursor < options.size() and box.has_flag(Gen2MenuBox.STATICMENU_CURSOR):
		var arrow: Vector2i = box.cursor_position(cursor)
		font.draw_code(CURSOR_CODE, indices, width, arrow.x * TILE, arrow.y * TILE)


## `Textbox`'s own `ClearBox` over the interior, so a menu drawn over a filled
## page does not show that page through its options. The blank the source fills
## with is $7f, which sits below the font and draws as index 0.
func _fill_interior(box: Gen2MenuBox, indices: PackedByteArray, width: int) -> void:
	var interior: Vector2i = box.interior()
	var left: int = (box.left + 1) * TILE
	var span: int = interior.x * TILE
	for row: int in interior.y * TILE:
		var start: int = ((box.top + 1) * TILE + row) * width + left
		if start < 0 or start + span > indices.size():
			continue
		for pixel: int in span:
			indices[start + pixel] = 0
