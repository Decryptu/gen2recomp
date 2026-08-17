class_name Gen2ClockSetPage
extends RefCounted

## `InitClock` and `SetDayOfWeek` on the hardware tile grid. The two one-tile
## arrows stand where the source loads its temporary arrow graphics.

const TILE: int = Gen2Font.TILE
var font: Gen2Font = null
var menu: Gen2MenuPage = null


static func from_data(data: GameData) -> Gen2ClockSetPage:
	var out := Gen2ClockSetPage.new()
	out.font = Gen2Font.from_data(data)
	out.menu = Gen2MenuPage.from_data(data)
	return out if out.font != null and out.menu != null else null


func render(value: String, prompt: String, confirm_cursor: int, day: bool) -> Image:
	var indices := PackedByteArray()
	indices.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	var dial := Gen2MenuBox.from_coords(9 if day else 3, 3 if day else 7, 19, 7 if day else 11,
		Gen2MenuBox.STATICMENU_NO_TOP_SPACING)
	menu.draw(dial, [], -1, indices, Gen2Screen.WIDTH)
	var value_at := Vector2i(10, 5) if day else Vector2i(4, 9)
	font.draw_text(value, indices, Gen2Screen.WIDTH, value_at.x * TILE, value_at.y * TILE)
	var arrow_x: int = 14 if day else (15 if value.contains("min.") else 11)
	var arrow_top: int = 4 if day else 8
	_draw_arrow(indices, arrow_x * TILE, arrow_top * TILE, false)
	_draw_arrow(indices, arrow_x * TILE, (arrow_top + 3) * TILE, true)
	var speech := Gen2MenuBox.from_coords(0, 12, 19, 17, 0)
	menu.draw(speech, [], -1, indices, Gen2Screen.WIDTH)
	var pages: Array = Gen2TextLayout.lay_out(prompt, 18, 2)
	var lines: PackedStringArray = pages[0] if not pages.is_empty() else PackedStringArray()
	for row: int in mini(2, lines.size()):
		font.draw_text(String(lines[row]), indices, Gen2Screen.WIDTH,
			TILE, (14 + row * 2) * TILE)
	if confirm_cursor >= 0:
		var yes_no := Gen2MenuBox.from_coords(14, 7, 19, 11,
			Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_NO_TOP_SPACING)
		menu.draw(yes_no, ["YES", "NO"], confirm_cursor, indices, Gen2Screen.WIDTH)
	return Gen2PicImage.from_indices(indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK])))


func _draw_arrow(indices: PackedByteArray, x: int, y: int, down: bool) -> void:
	for row: int in 5:
		var span: int = (row + 1) if not down else (5 - row)
		for pixel: int in span:
			var px: int = x + 3 - int((span - 1) / 2) + pixel
			var py: int = y + row
			indices[py * Gen2Screen.WIDTH + px] = 3
