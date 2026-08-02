extends Control

## Development view: the cartridge's font and text box on a real 160x144 screen.
##
## Scaffolding, like `pic_viewer.tscn`, and for the same reason: a wrong decode
## has to be visible. A font that has slid by one tile still draws letters, and
## a border whose six tiles are in the wrong order still draws a box, so both
## are checked by looking at them rather than by counting bytes.
##
## The chart draws all 128 glyphs in code order. The alphabet runs, the gaps
## between them and the digits at the end are the shape the charmap describes,
## and anything out of place shows up as a blank in the middle of a word or a
## letter where a gap should be.
##
## Space advances, F cycles the border, C toggles the chart. Each is also a
## plain method so `tools/screenshot.gd` can drive it.

const BACKGROUND: Color = Color.WHITE

const SAMPLE_COUNT: int = 3

var _data: GameData = null
var _font: Gen2Font = null
var _sample: int = 0
var _chart_shown: bool = false

var _box: Gen2TextBox = null
var _chart: TextureRect = null

@onready var _screen: Gen2Screen = %Screen
@onready var _caption: Label = %Caption
@onready var _hint: Label = %Hint


func _ready() -> void:
	_data = GameData.open_any()
	_font = Gen2Font.from_data(_data)
	if _font == null:
		_caption.text = "No font in the cache"
		_hint.text = "Run tools/import_rom.gd first."
		return

	var field := ColorRect.new()
	field.color = BACKGROUND
	field.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_screen.display(field)

	_chart = TextureRect.new()
	_chart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chart.visible = false
	_screen.display(_chart)
	_build_chart()

	_box = Gen2TextBox.new()
	_box.font = _font
	_screen.display(_box)
	_box.place_at_bottom()

	_show_sample()
	_hint.text = "space advance    F border    C chart"


func _unhandled_key_input(event: InputEvent) -> void:
	if _font == null or not event.is_pressed():
		return

	var key: InputEventKey = event as InputEventKey
	if key == null:
		return

	match key.keycode:
		KEY_SPACE, KEY_ENTER:
			advance()
		KEY_F:
			next_frame_style()
		KEY_C:
			toggle_chart()
		_:
			return
	accept_event()


## Finishes the page, or moves to the next one, or starts the next sample once
## the current one has run out.
func advance() -> void:
	if _box == null:
		return
	if not _box.advance():
		_sample += 1
		_show_sample()


func next_frame_style() -> void:
	if _box == null:
		return
	_box.set_frame_style(_box.frame_style + 1)
	_refresh_caption()


func toggle_chart() -> void:
	_chart_shown = not _chart_shown
	if _chart != null:
		_chart.visible = _chart_shown


## Reveals the whole page at once, for a screenshot that should not depend on
## how long the capture took to arrive.
func finish() -> void:
	if _box != null:
		_box.finish()


func _show_sample() -> void:
	if _data == null or _box == null:
		return

	_sample = wrapi(_sample, 0, SAMPLE_COUNT)
	_box.show_text(_sample_text(_sample))
	_refresh_caption()


## Sentences assembled out of decoded content rather than written here, so the
## view exercises the codec on the way to the screen. The apostrophes are
## deliberate: each is a ligature, one tile for two characters, and a line that
## wraps a column early is what a renderer counting characters looks like.
func _sample_text(index: int) -> String:
	var species: String = String(_data.species(1).get("name", "?"))
	var move: String = String(_data.move(33).get("name", "?"))
	var item: String = String(_data.item(21).get("name", "?"))

	match index:
		0:
			return "%s used %s! It's not very effective..." % [species, move]
		1:
			return "%s's %s restored its HP by 20 points!" % [species, item]
	return "There's a time and place for everything, but not now. Come and see me later."


func _refresh_caption() -> void:
	if _data == null or _box == null:
		return
	_caption.text = "%s   text box   border %d" % [_data.title(), _box.frame_style + 1]


## All 128 glyphs in code order, sixteen to a row, centred on the screen.
func _build_chart() -> void:
	var sheet: Dictionary = _data.tile_sheet("font")
	if sheet.is_empty():
		return

	var columns: int = 16
	@warning_ignore("integer_division")
	var rows: int = int(sheet["tiles"]) / columns
	var width: int = columns * Gen2Font.TILE
	var height: int = rows * Gen2Font.TILE
	var indices: PackedByteArray = PackedByteArray()
	indices.resize(width * height)

	for tile: int in int(sheet["tiles"]):
		@warning_ignore("integer_division")
		var row: int = tile / columns
		_font.draw_code(
			int(sheet["first_code"]) + tile, indices, width,
			(tile % columns) * Gen2Font.TILE, row * Gen2Font.TILE
		)

	var image: Image = Gen2PicImage.from_indices(
		indices, width, height,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)
	_chart.texture = ImageTexture.create_from_image(image)
	_chart.size = Vector2(width, height)
	_chart.position = Vector2(int((Gen2Screen.WIDTH - width) / 2), 8)
