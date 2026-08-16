class_name Gen2PokepicPage
extends RefCounted

## `Pokepic` (engine/events/pokepic.asm): the box a script's `pokepic` command
## shows a species in, on the hardware tile grid. `MenuBox` at
## `menu_coords 6, 4, 14, 13`, then `PlaceGraphic` writing a 7x7 block of the
## front pic one tile in from the box's top-left corner.
##
## `_CGB_Pokepic` fills the whole box with `PAL_BG_GRAY`, so the pic wears the
## map's first background palette rather than the species' own colours: the
## picture a script shows is grey.
##
## Node-free: the image is the whole product, so the box can be read back
## headless.

const TILE: int = Gen2Font.TILE

## `PokepicMenuHeader`'s `menu_coords 6, 4, 14, 13`. Its flags byte is
## MENU_BACKUP_TILES, which restores the map behind the box when `ClosePokepic`
## runs; an overlay that is removed does that by existing, so no flag is carried.
const BOX_LEFT: int = 6
const BOX_TOP: int = 4
const BOX_RIGHT: int = 14
const BOX_BOTTOM: int = 13

## `Coord2Tile` on `wMenuBorderTopCoord + 1` and `wMenuBorderLeftCoord + 1`:
## the pic starts one tile inside the frame, which leaves the bottom interior
## row of this box empty.
const PIC_OFFSET: Vector2i = Vector2i(1, 1)

## `_CGB_Pokepic`'s `ld a, PAL_BG_GRAY`, which is index 0 of
## `constants/palette_constants.asm`'s background list and so slot 0 of whatever
## eight the map is drawn with.
const PALETTE_GRAY: int = 0


static func menu_box() -> Gen2MenuBox:
	return Gen2MenuBox.from_coords(BOX_LEFT, BOX_TOP, BOX_RIGHT, BOX_BOTTOM, 0)


## The box holding [param species] as an image of its own size, or null when the
## cache cannot answer for the pic, the font or the palette.
static func render(
	data: GameData, species: int, map: Gen2WorldMap,
	time_of_day: int = Gen2WorldPalette.TIME_MORNING
) -> Image:
	if data == null or map == null:
		return null
	var pic: Dictionary = data.species_pic(species)
	if pic.is_empty():
		return null
	var cell: Dictionary = Gen2PicImage.atlas_cell(
		data.atlas_indices(pic["atlas"]), data.atlas(pic["atlas"]), pic
	)
	if cell.is_empty():
		return null
	var menu: Gen2MenuPage = Gen2MenuPage.from_data(data)
	if menu == null:
		return null
	var slots: Array = Gen2WorldPalette.palette_slots(map.environment, time_of_day)
	var palette: PackedColorArray = data.world_palette(int(slots[PALETTE_GRAY]))
	if palette.size() < 4:
		return null
	var box: Gen2MenuBox = menu_box()
	var image: Image = menu.render(box, [], -1, "", 0, [], palette)
	image.blend_rect(
		Gen2PicImage.from_indices(
			cell["indices"], int(cell["width"]), int(cell["height"]), palette
		),
		Rect2i(Vector2i.ZERO, Vector2i(int(cell["width"]), int(cell["height"]))),
		pic_position(int(cell["width"]) / TILE, int(cell["height"]) / TILE)
	)
	return image


## Where a [param width] x [param height] pic lands inside the rendered box, in
## pixels from its top-left corner: `PlaceGraphic`'s 7x7 block plus
## [method Gen2PicImage.frontpic_pad_columns]' padding inside it.
static func pic_position(width: int, height: int) -> Vector2i:
	return (
		PIC_OFFSET + Vector2i(
			Gen2PicImage.frontpic_pad_columns(width),
			Gen2PicImage.FRONTPIC_TILES - height
		)
	) * TILE
