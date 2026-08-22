class_name Gen2UnownWallPage
extends RefCounted

## `DisplayUnownWords`' box on the hardware tile grid: `MenuBox`'s frame with
## [Gen2UnownWall]'s 2x2 letter blocks placed in it.
##
## The letters come out of the chamber's own tileset strip rather than a font,
## and wear `PAL_BG_BROWN` whatever the tileset's palette map says about those
## tile numbers, which is what `_DisplayUnownWords_FillAttr` writes.
##
## Node-free: the image is the whole product, so the box can be read back
## headless.

const TILE: int = Gen2Font.TILE


## The box for [param word] as an image of its own size, or null when the cache
## cannot answer for the tileset or the word holds a character with no tile.
static func render(
	data: GameData, tileset: Gen2WorldTileset, map: Gen2WorldMap, word: String,
	time_of_day: int = Gen2WorldPalette.TIME_MORNING
) -> Image:
	if data == null or tileset == null or map == null or word.is_empty():
		return null
	var blocks: Array = Gen2UnownWall.blocks(word)
	if blocks.is_empty():
		return null
	var indices: PackedByteArray = data.map_tile_indices(map, tileset)
	if indices.size() < RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS:
		return null
	var menu: Gen2MenuPage = Gen2MenuPage.from_data(data)
	if menu == null:
		return null
	var box: Gen2MenuBox = Gen2UnownWall.menu_box(word)
	var image: Image = menu.render(box, [], -1)
	var slots: Array = Gen2WorldPalette.palette_slots(map.environment, time_of_day)
	var palette: PackedColorArray = data.world_palette(
		int(slots[Gen2UnownWall.PALETTE_BROWN])
	)
	if palette.size() < 4:
		return null
	for index: int in blocks.size():
		var block: Dictionary = blocks[index]
		var at: Vector2i = (
			Gen2UnownWall.block_position(box, index) - box.border_position()
		) * TILE
		var tiles: Array = block["tiles"]
		var base: int = RomLayout.TILESET_BLOCK_STRIDE if bool(block["bank1"]) else 0
		for corner: int in tiles.size():
			_draw_tile(
				image, indices, palette, base + int(tiles[corner]),
				at + Vector2i((corner % 2) * TILE, (corner >> 1) * TILE)
			)
	return image


## One tile of the strip, painted opaque: the box covers the map behind it.
static func _draw_tile(
	image: Image, indices: PackedByteArray, palette: PackedColorArray,
	tile: int, at: Vector2i
) -> void:
	var stride: int = RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_WIDTH
	var left: int = tile * Gen2Tiles.TILE_WIDTH
	for y: int in Gen2Tiles.TILE_HEIGHT:
		for x: int in Gen2Tiles.TILE_WIDTH:
			var to: Vector2i = at + Vector2i(x, y)
			if to.x < 0 or to.y < 0 or to.x >= image.get_width() or to.y >= image.get_height():
				continue
			var color_index: int = int(indices[y * stride + left + x])
			image.set_pixelv(to, palette[mini(color_index, palette.size() - 1)])
