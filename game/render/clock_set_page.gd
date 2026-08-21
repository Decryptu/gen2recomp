class_name Gen2ClockSetPage
extends RefCounted

## `InitClock` and `SetDayOfWeek` on the hardware tile grid. The two one-tile
## arrows stand where the source loads its temporary arrow graphics.
##
## The speech box is drawn here only for a caller that has no [Gen2TextBox] of
## its own: `InitClock` reaches every one of its lines through `PrintText`, so
## [Gen2ClockSetScreen] passes an empty prompt and puts a real box over this.

const TILE: int = Gen2Font.TILE

## `.loop`, `.HourIsSet` and `SetDayOfWeek.loop` each place their own `Textbox`,
## its two arrows and its value, and differ in nothing else. Each row is the box
## as (left, top, right, bottom), the column both arrows stand in, and where the
## value is printed; both arrows sit on the box's own border rows.
const DIALS: Dictionary = {
	&"hour": {"box": Vector4i(3, 7, 19, 11), "arrow_x": 11, "value": Vector2i(4, 9)},
	&"minutes": {"box": Vector4i(11, 7, 19, 11), "arrow_x": 15, "value": Vector2i(12, 9)},
	&"day": {"box": Vector4i(9, 3, 19, 7), "arrow_x": 14, "value": Vector2i(10, 5)},
}

var font: Gen2Font = null
var menu: Gen2MenuPage = null


static func from_data(data: GameData) -> Gen2ClockSetPage:
	var out := Gen2ClockSetPage.new()
	out.font = Gen2Font.from_data(data)
	out.menu = Gen2MenuPage.from_data(data)
	return out if out.font != null and out.menu != null else null


## [param kind] is which of [constant DIALS] is drawn, and empty draws none.
## `InitClock`'s `.ClearScreen` runs before each `YesNoBox`, so a confirm has
## no dial; `SetDayOfWeek` keeps its own up behind the question instead.
func render(
	value: String, prompt: String, confirm_cursor: int, kind: StringName,
	palette: PackedColorArray = PackedColorArray()
) -> Image:
	var indices := PackedByteArray()
	indices.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	if DIALS.has(kind):
		var dial: Dictionary = DIALS[kind]
		var at: Vector4i = dial["box"]
		var box := Gen2MenuBox.from_coords(at.x, at.y, at.z, at.w,
			Gen2MenuBox.STATICMENU_NO_TOP_SPACING)
		menu.draw(box, [], -1, indices, Gen2Screen.WIDTH)
		var value_at: Vector2i = dial["value"]
		font.draw_text(value, indices, Gen2Screen.WIDTH, value_at.x * TILE, value_at.y * TILE)
		var arrow_x: int = int(dial["arrow_x"]) * TILE
		_draw_arrow(indices, arrow_x, (at.y + 1) * TILE, false)
		_draw_arrow(indices, arrow_x, at.w * TILE, true)
	if not prompt.is_empty():
		var speech := Gen2MenuBox.from_coords(0, 12, 19, 17, 0)
		menu.draw(speech, [], -1, indices, Gen2Screen.WIDTH)
		var pages: Array = Gen2TextLayout.lay_out(prompt, 18, 2)
		var lines: PackedStringArray = pages[0] if not pages.is_empty() else PackedStringArray()
		for row: int in mini(2, lines.size()):
			font.draw_text(String(lines[row]), indices, Gen2Screen.WIDTH,
				TILE, (14 + row * 2) * TILE)
	if confirm_cursor >= 0:
		# `YesNoBox`'s `lb bc, SCREEN_WIDTH - 6, 7`, which `_YesNoBox` turns into
		# left 14, right 19, top 7, bottom 11.
		var yes_no := Gen2MenuBox.from_coords(14, 7, 19, 11,
			Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_NO_TOP_SPACING)
		menu.draw(yes_no, ["YES", "NO"], confirm_cursor, indices, Gen2Screen.WIDTH)
	return Gen2PicImage.from_indices(indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT,
		palette if palette.size() == 4 else Gen2Palette.pic_palette(
			PackedColorArray([Color.WHITE, Color.BLACK])))


func _draw_arrow(indices: PackedByteArray, x: int, y: int, down: bool) -> void:
	for row: int in 5:
		var span: int = (row + 1) if not down else (5 - row)
		for pixel: int in span:
			var px: int = x + 3 - int((span - 1) / 2) + pixel
			var py: int = y + row
			indices[py * Gen2Screen.WIDTH + px] = 3
