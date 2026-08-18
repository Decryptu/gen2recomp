class_name Gen2MenuPage
extends RefCounted

## One menu box on the hardware tile grid: `MenuBox`'s frame,
## `PlaceVerticalMenuItems`' options, `PlaceMenuStrings`' title and
## `Place2DMenuCursor`'s arrow. Geometry is [Gen2MenuBox]'s and selection
## [Gen2WorldMenu]'s; this is presentation, and node-free so a menu can be drawn
## into any buffer a screen already owns and read back headless.

const TILE: int = Gen2Font.TILE

## `charmap.asm`: `"▶"` is $ed, which is what `Place2DMenuCursor` writes.
const CURSOR_CODE: int = 0xED

## `Textbox` draws with wTextboxFrame, so a menu wears the player's chosen frame.
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
## [param extras] are `PlaceString` calls the caller makes at absolute tile
## coordinates, as [code]{"text": String, "at": Vector2i}[/code]: the battle's
## `MoveInfoBox` writes its type and PP into a plain `Textbox` that way rather
## than as menu items.
func draw(
	box: Gen2MenuBox, options: Array, cursor: int,
	indices: PackedByteArray, width: int, title: String = "", title_indent: int = 0,
	extras: Array = []
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

	# Every cartridge label is written to fit its box, so `PlaceVerticalMenuItems`
	# needs no bound; a label a mod registers can be any length, and unbounded it
	# is drawn straight through the right-hand border and over the map beside it.
	var last_column: int = box.left + box.interior().x
	for index: int in options.size():
		var item: Vector2i = box.item_position(index)
		font.draw_text(
			String(options[index]), indices, width, item.x * TILE, item.y * TILE,
			Gen2Text.FONT_MAIN, maxi(0, last_column - item.x + 1)
		)

	for extra: Dictionary in extras:
		var extra_at: Vector2i = extra.get("at", Vector2i.ZERO)
		font.draw_text(
			String(extra.get("text", "")), indices, width,
			extra_at.x * TILE, extra_at.y * TILE
		)

	if cursor >= 0 and cursor < options.size() and box.has_flag(Gen2MenuBox.STATICMENU_CURSOR):
		var arrow: Vector2i = box.cursor_position(cursor)
		font.draw_code(CURSOR_CODE, indices, width, arrow.x * TILE, arrow.y * TILE)


## The same menu as an image of its frame alone, for a screen that composes
## layers: drawn into a screen-sized buffer at its own coordinates and cropped
## back, so [method draw]'s placement stays the one piece of arithmetic. Opaque,
## because `MenuBox` fills its interior.
##
## [param palette] is the four colours the box is drawn with, and defaults to
## `PAL_BG_TEXT`'s black on white. A box a CGB layout fills with a palette of the
## map's own passes that one instead, which is what `_CGB_Pokepic` does.
func render(
	box: Gen2MenuBox, options: Array, cursor: int,
	title: String = "", title_indent: int = 0, extras: Array = [],
	palette: PackedColorArray = PackedColorArray()
) -> Image:
	var width: int = Gen2Screen.WIDTH
	var indices: PackedByteArray = PackedByteArray()
	indices.resize(width * Gen2Screen.HEIGHT)
	draw(box, options, cursor, indices, width, title, title_indent, extras)
	var colors: PackedColorArray = palette if palette.size() >= 4 \
		else Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	return Gen2PicImage.from_indices(
		indices, width, Gen2Screen.HEIGHT, colors
	).get_region(Rect2i(box.border_position() * TILE, box.border_size() * TILE))


## `Textbox`'s own `ClearBox`, so a menu over a filled page does not show it
## through. The source's blank is $7f, below the font, which draws as index 0.
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
