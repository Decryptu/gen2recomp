class_name Gen2WorldServicePage
extends RefCounted

## The cartridge-sized menus hosted by the overworld service dispatcher. The
## caller supplies the imported rows; this page owns only MenuTextbox geometry.

const TILE: int = Gen2Font.TILE

var font: Gen2Font = null
var menu: Gen2MenuPage = null


static func from_data(data: GameData) -> Gen2WorldServicePage:
	var out := Gen2WorldServicePage.new()
	out.font = Gen2Font.from_data(data)
	out.menu = Gen2MenuPage.from_data(data)
	return out if out.font != null and out.menu != null else null


## `MenuTextbox` over the map: every box here carries `MENU_BACKUP_TILES`, so
## the map stays visible around it and nothing here fills the screen white.
## The caller supplies its own `menu_coords` box; an empty [param rows] draws
## no box at all, which is what a plain `MenuTextbox` print is.
func render(title: String, prompt: String, rows: Array, cursor: int,
		message: String = "", box: Gen2MenuBox = null) -> Image:
	var image := Image.create_empty(
		Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8
	)
	if not rows.is_empty() and box != null:
		_blit(image, menu.render(box, rows, cursor), box.border_position())
	var words: String = message if not message.is_empty() else prompt
	if words.is_empty():
		words = title
	if not words.is_empty():
		var pages: Array = Gen2TextLayout.lay_out(words, 18, 2)
		var lines: PackedStringArray = pages[0] if not pages.is_empty() else PackedStringArray()
		var indices := PackedByteArray()
		indices.resize(Gen2Screen.WIDTH * 6 * TILE)
		font.draw_box(Gen2OptionsStore.current().textbox_frame, indices,
			Gen2Screen.WIDTH, 0, 0, 20, 6)
		for row: int in mini(2, lines.size()):
			font.draw_text(lines[row], indices, Gen2Screen.WIDTH, TILE, (2 + row * 2) * TILE)
		var part: Image = Gen2PicImage.from_indices(indices, Gen2Screen.WIDTH, 6 * TILE,
			Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK])))
		image.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, 12 * TILE))
	return image


func _blit(into: Image, part: Image, at: Vector2i) -> void:
	if part != null:
		into.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), at * TILE)
