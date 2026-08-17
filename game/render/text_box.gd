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

## `LoadBlinkingCursor` writes '▼' at screen tile (18, 17) and
## `UnloadBlinkingCursor` puts the '─' of the border back. The box's own top
## row is 12, so that is column 18 of its bottom row, and the arrow is what
## every wait for a button looks like: `Paragraph`, `_ContText` and
## `PromptText` all load it before `PromptButton` and unload it after.
const CURSOR_CODE: int = 0xEE
const CURSOR_COLUMN: int = 18
## `PromptButton.blink_cursor` reads `hVBlankCounter` and `and 1 << 4`, so the
## arrow is up for sixteen frames and the border's own '─' is back for the
## next sixteen (`home/joypad.asm`). Counted in seconds rather than frames for
## the reason [member reveal_speed] is a rate: the period is the same either
## way and this does not assume 60 Hz.
const CURSOR_BLINK_FRAMES: int = 16
const FRAME_SECONDS: float = 1.0 / 60.0

## `TextScroll` shifts the whole interior up one tile row, blanks the row it
## leaves at the bottom and spends five frames. `_ContText` and
## `_ContTextNoPause` both call it twice, which is one text line, since a box's
## lines sit two rows apart.
const SCROLL_STEPS: int = 2
const SCROLL_STEP_FRAMES: int = 5

const TILE: int = Gen2Font.TILE

## Tiles per second while a page is revealing. The games run this off the frame
## counter; a rate is the same thing said in a way that does not assume 60 Hz.
@export var reveal_speed: float = 30.0
## Per-scanline background offsets for the box's own rows, empty when the
## background is sitting still. A box is drawn into the background plane like
## everything else, so a routine that scrolls the plane scrolls the box with it;
## see [Gen2Raster].
@export var raster_scx: PackedInt32Array = PackedInt32Array():
	set(value):
		raster_scx = value
		_redraw()
@export var columns: int = STANDARD_COLUMNS
@export var rows: int = STANDARD_ROWS
@export_range(0, 7) var frame_style: int = 0
## How opaque the box's field is drawn. The cartridge has no alpha and needs
## none: it draws a box over its own white background. Over a renderer on the
## screen's native layer that same box is a slab across the map, so a renderer
## may ask for the field to be drawn through; see
## [constant Gen2ModHost.RENDERER_INTERFACE_OPACITY_METHOD]. The frame's lines
## and the glyphs are ink and stay opaque whatever this is.
@export_range(0.0, 1.0) var field_opacity: float = 1.0:
	set(value):
		var next: float = clampf(value, 0.0, 1.0)
		if is_equal_approx(next, field_opacity):
			return
		field_opacity = next
		_redraw()

## The four colours the box is drawn through, index 0 the field and 3 the ink.
## Empty is the ordinary black-on-white; the intro sets it because a palette
## fade there remaps every BG palette on screen, the text one included.
var palette: PackedColorArray = PackedColorArray():
	set(value):
		palette = value
		_redraw()

var font: Gen2Font = null

var _pages: Array = []
var _page: int = 0
var _lines: Array = []
var _tiles_on_page: int = 0
var _shown: float = 0.0
var _blink: float = 0.0
## The rows on their way off the top of the box while `TextScroll` runs, how far
## up they have moved, and the page to start once they are gone. `_scroll_page`
## is -1 whenever nothing is scrolling.
var _scroll_lines: Array = []
var _scroll_rows: int = 0
var _scroll_elapsed: float = 0.0
var _scroll_page: int = -1


func _ready() -> void:
	# Nearest, or the integer-scaled viewport is undone on the last hop.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)


## One hardware frame of the reveal, for a caller spending frames by hand rather
## than by real time: the overworld's own pump while an overlay is up, a check, a
## screenshot driver, a replay. `PrintLetterDelay` is a frame count on the
## cartridge, so this is the same clock [method _process] converts real time into.
func advance_frame() -> void:
	_process(FRAME_SECONDS)


func _process(delta: float) -> void:
	if _scroll_page >= 0:
		_advance_scroll(delta)
		return
	if _shown < float(_tiles_on_page):
		_shown = minf(_shown + delta * reveal_speed, float(_tiles_on_page))
		_redraw()
		return
	if _pages.is_empty():
		set_process(false)
		return
	if _enter_of(_page + 1) == &"scroll_nowait":
		# `_ContTextNoPause` has no `PromptButton` in front of it: the printer
		# reaches the code, scrolls and carries on.
		_begin_scroll(_page + 1)
		return
	# Waiting: only the arrow changes, and only when it crosses a half period.
	var was_up: bool = _cursor_up()
	_blink = fmod(_blink + delta, FRAME_SECONDS * float(CURSOR_BLINK_FRAMES) * 2.0)
	if _cursor_up() != was_up:
		_redraw()


## Puts the box where the games put it: flush to the left, six rows up from the
## bottom of the screen.
func place_at_bottom() -> void:
	position = Vector2(0, STANDARD_TOP * TILE)


## Lays [param text] out and starts revealing its first page.
func show_text(text: String) -> void:
	_pages = Gen2TextLayout.lay_out_pages(text, text_columns(), text_rows())
	_page = 0
	_scroll_page = -1
	_scroll_lines = []
	_start_page()


## True while a page still has tiles left to reveal, or while the box is in the
## middle of a scroll: neither has reached its `PromptButton` yet.
func is_revealing() -> bool:
	return _scroll_page >= 0 or _shown < float(_tiles_on_page)


## Every line the box is holding, its pages in order. What is on screen is read
## through this rather than through the pagination behind it.
func text_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for page: Dictionary in _pages:
		out.append_array(page["lines"])
	return out


## Whether a page after this one is still waiting, which is what the blinking
## arrow means. A screen putting a menu over the box waits for both this and
## [method is_revealing] to be false, since the cartridge prints the whole text
## before it opens one.
func has_pages_left() -> bool:
	return _page + 1 < _pages.size()


## Reveals the rest of the current page at once.
func finish() -> void:
	if _scroll_page >= 0:
		_end_scroll()
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

	if _enter_of(_page + 1) == &"scroll":
		_begin_scroll(_page + 1)
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


## The rectangle the box covers, in hardware pixels, and an empty one whenever
## nothing is drawn. A renderer composing around the box reads this rather than
## assuming the standard twenty by six at row twelve, since a box can be any
## size and is not always on screen.
func occupied_rect() -> Rect2i:
	if not visible or texture == null:
		return Rect2i()
	return Rect2i(Vector2i(position.floor()), Vector2i(size.floor()))


## Tiles of text that fit across the interior.
func text_columns() -> int:
	return maxi(columns - TEXT_LEFT * 2, 0)


## Lines of text the box shows at once, given that they sit two rows apart.
func text_rows() -> int:
	@warning_ignore("integer_division")
	return maxi((rows - 1 - TEXT_TOP) / LINE_SPACING + 1, 0)


## How the page at [param index] is reached, and `&""` when there is no such
## page.
func _enter_of(index: int) -> StringName:
	if index < 0 or index >= _pages.size():
		return &""
	return StringName(_pages[index].get("enter", &"page"))


## Starts `TextScroll`'s two steps, with the lines that are on screen moving up
## through the interior and off the top of it.
func _begin_scroll(next_page: int) -> void:
	_scroll_lines = _lines.duplicate()
	_scroll_rows = 1
	_scroll_elapsed = 0.0
	_scroll_page = next_page
	_lines = []
	_tiles_on_page = 0
	_shown = 0.0
	set_process(true)
	_redraw()


func _advance_scroll(delta: float) -> void:
	advance_scroll_frames(delta / FRAME_SECONDS)


## [param frames] hardware frames of `TextScroll`. Counted in frames rather than
## seconds so a tool spending them one at a time lands on the same step the
## clock does; see [method is_scrolling].
func advance_scroll_frames(frames: float) -> void:
	if _scroll_page < 0:
		return
	_scroll_elapsed += frames
	while _scroll_elapsed >= float(SCROLL_STEP_FRAMES):
		_scroll_elapsed -= float(SCROLL_STEP_FRAMES)
		if _scroll_rows >= SCROLL_STEPS:
			_end_scroll()
			return
		_scroll_rows += 1
		_redraw()


## Whether `TextScroll`'s two steps are running, which is the one wait that is
## neither a page turn nor a reveal.
func is_scrolling() -> bool:
	return _scroll_page >= 0


## Puts the page the scroll was heading for up. Its first line is the one that
## was underneath, which is where `_ContText` leaves it.
func _end_scroll() -> void:
	var next_page: int = _scroll_page
	_scroll_page = -1
	_scroll_lines = []
	_scroll_rows = 0
	if next_page < 0:
		return
	_page = next_page
	if _page >= _pages.size():
		_pages = []
		_lines = []
		_tiles_on_page = 0
		finished.emit()
		return
	_start_page()


func _start_page() -> void:
	_lines = []
	_tiles_on_page = 0
	if _page < _pages.size():
		for line: String in _pages[_page]["lines"]:
			var codes: PackedByteArray = Gen2Text.encode(line)
			_lines.append(codes)
			_tiles_on_page += codes.size()

	_shown = 0.0
	_blink = 0.0
	set_process(_tiles_on_page > 0)
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
	_draw_cursor(indices, width)

	var image: Image = Gen2PicImage.from_indices(
		indices, width, height, _colors()
	)
	if not raster_scx.is_empty():
		image = Gen2Raster.scroll(image, raster_scx, Gen2BattleIntro.MAP_WIDTH)
	texture = ImageTexture.create_from_image(image)
	size = Vector2(width, height)


## Index 0 is the field and index 3 the ink; 1bpp graphics have no middle
## colours, so the two between them are never drawn. Written out rather than
## taken from Gen2Palette.pic_palette because only the field carries alpha, and
## [member field_opacity] is applied to whichever palette is in force.
func _colors() -> PackedColorArray:
	var source: PackedColorArray = (
		palette if palette.size() == 4
		else PackedColorArray([Color.WHITE, Color.WHITE, Color.BLACK, Color.BLACK])
	)
	var field := Color(source[0], field_opacity)
	return PackedColorArray([field, Color(source[1], field_opacity), source[2], source[3]])


## Which half of the blink the box is in. `UnloadBlinkingCursor` puts the
## border's '─' back rather than a blank, and the border is redrawn under the
## arrow anyway, so the off half simply does not draw.
func _cursor_up() -> bool:
	return _blink < FRAME_SECONDS * float(CURSOR_BLINK_FRAMES)


func _draw_border(indices: PackedByteArray, width: int) -> void:
	font.draw_box(frame_style, indices, width, 0, 0, columns, rows)


## The arrow, drawn only while the box is actually waiting: a page still
## revealing has not reached its `PromptButton` yet.
func _draw_cursor(indices: PackedByteArray, width: int) -> void:
	if _pages.is_empty() or is_revealing() or not _cursor_up():
		return
	if _enter_of(_page + 1) == &"scroll_nowait":
		return
	if CURSOR_COLUMN >= columns or rows <= 0:
		return
	font.draw_code(
		CURSOR_CODE, indices, width, CURSOR_COLUMN * TILE, (rows - 1) * TILE
	)


func _draw_lines(indices: PackedByteArray, width: int) -> void:
	if _scroll_page >= 0:
		_draw_scrolling_lines(indices, width)
		return
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


## The interior mid-`TextScroll`: every line one tile row higher per step, and
## the row that reaches the border gone, which is what the second copy does to
## the first line on the cartridge.
func _draw_scrolling_lines(indices: PackedByteArray, width: int) -> void:
	for i: int in _scroll_lines.size():
		var codes: PackedByteArray = _scroll_lines[i]
		var row: int = TEXT_TOP + i * LINE_SPACING - _scroll_rows
		if row < 1:
			continue
		for tile: int in codes.size():
			font.draw_code(
				codes[tile], indices, width, (TEXT_LEFT + tile) * TILE, row * TILE
			)
