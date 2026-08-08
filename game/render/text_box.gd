class_name Gen2TextBox
extends TextureRect

## A bordered text window, drawn the way the hardware draws one.
##
## Everything is on the tile grid, at the games' own measurements rather than by
## choice: the border is six tiles of the chosen frame printed as box-drawing
## characters, the interior is white, and text sits one tile in from the left on
## every second row, since a line is eight pixels tall in a box whose rows are
## sixteen apart.
##
## The box composes into one index buffer and goes through the same
## index-plus-palette path a sprite does, so a glyph and a Pokémon are lit by the
## same code. Only indices 0 and 3 appear: 1bpp graphics have no middle colours.
##
## Text reveals a tile at a time and waits at the end of each page.
## [method advance] and [method finish] are plain methods as well as key
## handlers, so a screen can be photographed mid-sentence.

## Emitted when the last page has been shown and advanced past.
signal finished

## The standard box: twenty tiles across, six down, at the foot of the screen.
const STANDARD_COLUMNS: int = 20
const STANDARD_ROWS: int = 6
const STANDARD_TOP: int = 12

## Text starts one tile in from the border, two rows down, and every second row
## after that.
const TEXT_LEFT: int = 1
const TEXT_TOP: int = 2
const LINE_SPACING: int = 2

const TILE: int = Gen2Font.TILE

## Tiles per second while a page is revealing. The games run this off the frame
## counter; a rate is the same thing said in a way that does not assume 60 Hz.
@export var reveal_speed: float = 30.0
@export var columns: int = STANDARD_COLUMNS
@export var rows: int = STANDARD_ROWS
@export_range(0, 7) var frame_style: int = 0

var font: Gen2Font = null

var _pages: Array = []
var _page: int = 0
var _lines: Array = []
var _tiles_on_page: int = 0
var _shown: float = 0.0


func _ready() -> void:
	# Nearest, or the integer-scaled viewport is undone on the last hop.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)


func _process(delta: float) -> void:
	if _shown >= float(_tiles_on_page):
		set_process(false)
		return

	_shown = minf(_shown + delta * reveal_speed, float(_tiles_on_page))
	_redraw()


## Puts the box where the games put it: flush to the left, six rows up from the
## bottom of the screen.
func place_at_bottom() -> void:
	position = Vector2(0, STANDARD_TOP * TILE)


## Lays [param text] out and starts revealing its first page.
func show_text(text: String) -> void:
	_pages = Gen2TextLayout.lay_out(text, text_columns(), text_rows())
	_page = 0
	_start_page()


## True while a page still has tiles left to reveal.
func is_revealing() -> bool:
	return _shown < float(_tiles_on_page)


## Reveals the rest of the current page at once.
func finish() -> void:
	_shown = float(_tiles_on_page)
	set_process(false)
	_redraw()


## What a button press does: completes the page if it is still revealing,
## otherwise moves to the next one. Returns false once there is nothing left,
## having emitted [signal finished].
func advance() -> bool:
	if _pages.is_empty():
		return false
	if is_revealing():
		finish()
		return true

	_page += 1
	if _page >= _pages.size():
		_pages = []
		_lines = []
		_tiles_on_page = 0
		finished.emit()
		return false

	_start_page()
	return true


## Redraws with a different border. All eight are in the cache; the games let
## the player pick.
func set_frame_style(style: int) -> void:
	var count: int = font.frame_count() if font != null else RomLayout.FRAME_COUNT
	frame_style = wrapi(style, 0, maxi(count, 1))
	_redraw()


## Tiles of text that fit across the interior.
func text_columns() -> int:
	return maxi(columns - TEXT_LEFT * 2, 0)


## Lines of text the box shows at once, given that they sit two rows apart.
func text_rows() -> int:
	@warning_ignore("integer_division")
	return maxi((rows - 1 - TEXT_TOP) / LINE_SPACING + 1, 0)


func _start_page() -> void:
	_lines = []
	_tiles_on_page = 0
	if _page < _pages.size():
		for line: String in _pages[_page]:
			var codes: PackedByteArray = Gen2Text.encode(line)
			_lines.append(codes)
			_tiles_on_page += codes.size()

	_shown = 0.0
	set_process(reveal_speed > 0.0 and _tiles_on_page > 0)
	if reveal_speed <= 0.0:
		_shown = float(_tiles_on_page)
	_redraw()


func _redraw() -> void:
	if font == null or columns <= 0 or rows <= 0:
		texture = null
		return

	var width: int = columns * TILE
	var height: int = rows * TILE
	var indices: PackedByteArray = PackedByteArray()
	indices.resize(width * height)

	_draw_border(indices, width)
	_draw_lines(indices, width)

	var image: Image = Gen2PicImage.from_indices(
		indices, width, height,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)
	texture = ImageTexture.create_from_image(image)
	size = Vector2(width, height)


func _draw_border(indices: PackedByteArray, width: int) -> void:
	font.draw_box(frame_style, indices, width, 0, 0, columns, rows)


func _draw_lines(indices: PackedByteArray, width: int) -> void:
	var left: int = 0
	for i: int in _lines.size():
		var codes: PackedByteArray = _lines[i]
		var top: int = (TEXT_TOP + i * LINE_SPACING) * TILE
		for tile: int in codes.size():
			if left + tile >= int(_shown):
				return
			font.draw_code(
				codes[tile], indices, width, (TEXT_LEFT + tile) * TILE, top
			)
		left += codes.size()
