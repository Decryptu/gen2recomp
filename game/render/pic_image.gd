class_name Gen2PicImage
extends RefCounted

## Colour indices plus a palette to an [Image]. The cache stores what the
## cartridge stores, two bits per pixel and no colour, so the palette is chosen
## here at draw time and a shiny sprite costs one [PackedColorArray] rather than
## a second copy of the pixels.
##
## Built as one buffer for [method Image.create_from_data]: per-pixel
## [method Image.set_pixel] on a 56x56 sprite is 3136 binding calls for a table
## lookup, and a battle can want several sprites a frame. Node-free, so headless.

const CHANNELS: int = 4

## `PadFrontpic`'s box: every front pic is placed as 7x7 tiles whatever its own
## size is.
const FRONTPIC_TILES: int = 7


## An image [param width] x [param height] from a row-major index buffer.
## [param transparent_background] makes index 0 transparent: the hardware has no
## alpha and draws it white, which is right for a battle sprite in its window and
## wrong for one over anything else.
static func from_indices(
	indices: PackedByteArray,
	width: int,
	height: int,
	palette: PackedColorArray,
	transparent_background: bool = false
) -> Image:
	if width <= 0 or height <= 0 or indices.size() < width * height:
		return Image.create_empty(maxi(width, 1), maxi(height, 1), false, Image.FORMAT_RGBA8)

	var lookup: PackedByteArray = _lookup(palette, transparent_background)
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(width * height * CHANNELS)

	for i: int in width * height:
		var at: int = int(indices[i]) * CHANNELS
		var to: int = i * CHANNELS
		pixels[to] = lookup[at]
		pixels[to + 1] = lookup[at + 1]
		pixels[to + 2] = lookup[at + 2]
		pixels[to + 3] = lookup[at + 3]

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)


## An image from a row-major index buffer plus `wAttrmap`: one palette index per
## tile, so a screen the hardware draws in several palettes is one buffer here
## too rather than a layer per colour. [param slots] is [param columns] wide and
## row-major, and a slot naming no palette falls back on the first.
##
## `FillBoxCGB` and `ByteFill` over an attrmap `WipeAttrmap` cleared are what
## every `_CGB_*` layout writes, so a caller's own `attributes()` is that list of
## boxes flattened once.
static func from_attributes(
	indices: PackedByteArray,
	width: int,
	height: int,
	slots: PackedInt32Array,
	columns: int,
	palettes: Array
) -> Image:
	if palettes.is_empty():
		return Image.create_empty(maxi(width, 1), maxi(height, 1), false, Image.FORMAT_RGBA8)
	if width <= 0 or height <= 0 or indices.size() < width * height:
		return Image.create_empty(maxi(width, 1), maxi(height, 1), false, Image.FORMAT_RGBA8)

	var lookups: Array[PackedByteArray] = []
	for palette: Variant in palettes:
		lookups.append(_lookup(palette as PackedColorArray, false))

	var tile: int = Gen2Font.TILE
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(width * height * CHANNELS)
	for y: int in height:
		@warning_ignore("integer_division")
		var row: int = (y / tile) * columns
		for x: int in width:
			@warning_ignore("integer_division")
			var slot: int = row + x / tile
			var lookup: PackedByteArray = lookups[
				clampi(slots[slot] if slot < slots.size() else 0, 0, lookups.size() - 1)
			]
			var at: int = int(indices[y * width + x]) * CHANNELS
			var to: int = (y * width + x) * CHANNELS
			pixels[to] = lookup[at]
			pixels[to + 1] = lookup[at + 1]
			pixels[to + 2] = lookup[at + 2]
			pixels[to + 3] = lookup[at + 3]

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)


## An attrmap from a list of `FillBoxCGB` boxes, each (x, y, width, height,
## palette) over the zeroes `WipeAttrmap` leaves.
static func attribute_boxes(
	boxes: Array, columns: int, rows: int
) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(columns * rows)
	for box: Variant in boxes:
		var cells: Array = box as Array
		for row: int in int(cells[3]):
			for column: int in int(cells[2]):
				var x: int = int(cells[0]) + column
				var y: int = int(cells[1]) + row
				if x >= 0 and x < columns and y >= 0 and y < rows:
					out[y * columns + x] = int(cells[4])
	return out


## One cell out of a pic atlas, cropped to the pic's real size.
## [param pic] is [method GameData.species_pic]'s answer: which atlas, which slot
## and how much of the cell is filled. A cell is the size of the largest pic of
## its kind, so a 5x5 sprite carries blank tiles it must not be positioned by.
static func from_atlas(
	indices: PackedByteArray,
	atlas: Dictionary,
	pic: Dictionary,
	palette: PackedColorArray,
	transparent_background: bool = false
) -> Image:
	var cell: Dictionary = atlas_cell(indices, atlas, pic)
	if cell.is_empty():
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	return from_indices(
		cell["indices"], int(cell["width"]), int(cell["height"]),
		palette, transparent_background
	)


## The same cell before a palette is chosen: { indices, width, height }, or empty
## for a slot the atlas does not hold. Split out so a palette fade over a
## frontpic swaps colours rather than cropping the atlas again.
##
## A [param pic] carrying its own [code]indices[/code] is a mod's picture and has
## no cell to crop: the atlases hold exactly the cartridge's slots. Answering it
## here is what lets every screen draw one without knowing which it has.
static func atlas_cell(
	indices: PackedByteArray, atlas: Dictionary, pic: Dictionary
) -> Dictionary:
	if pic.has("indices"):
		var supplied: Variant = pic["indices"]
		var pic_width: int = int(pic.get("width", 0))
		var pic_height: int = int(pic.get("height", 0))
		if not supplied is PackedByteArray or pic_width <= 0 or pic_height <= 0 \
			or (supplied as PackedByteArray).size() < pic_width * pic_height:
			return {}
		return {"indices": supplied, "width": pic_width, "height": pic_height}

	var cell: int = int(atlas.get("cell", 0))
	var columns: int = int(atlas.get("columns", 0))
	var atlas_width: int = int(atlas.get("width", 0))
	var slot: int = int(pic.get("slot", -1))
	if cell <= 0 or columns <= 0 or atlas_width <= 0 or slot < 0:
		return {}

	var width: int = mini(int(pic.get("width", cell)), cell)
	var height: int = mini(int(pic.get("height", cell)), cell)
	if width <= 0 or height <= 0:
		return {}

	var left: int = (slot % columns) * cell
	var top: int = (slot / columns) * cell
	var cropped: PackedByteArray = PackedByteArray()
	cropped.resize(width * height)

	for y: int in height:
		var from: int = (top + y) * atlas_width + left
		if from + width > indices.size():
			break
		for x: int in width:
			cropped[y * width + x] = indices[from + x]

	return {"indices": cropped, "width": width, "height": height}


## Four bytes per index, so the inner loop copies rather than converting colours.
static func _lookup(palette: PackedColorArray, transparent_background: bool) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(Gen2Palette.COLORS_PER_PIC * CHANNELS)

	for i: int in Gen2Palette.COLORS_PER_PIC:
		var color: Color = palette[i] if i < palette.size() else Color.MAGENTA
		var at: int = i * CHANNELS
		out[at] = int(roundf(color.r * 255.0))
		out[at + 1] = int(roundf(color.g * 255.0))
		out[at + 2] = int(roundf(color.b * 255.0))
		# The palette's own alpha, so a translucent colour needs no second
		# flag. Every cartridge palette is opaque, Gen2Palette.decode_color
		# building an opaque Color.
		out[at + 3] = 0 if transparent_background and i == 0 \
			else int(roundf(clampf(color.a, 0.0, 1.0) * 255.0))

	return out


## What `wBoxAlignment` produces, a plain horizontal mirror. The flag is read
## twice and only both halves make sense of it: `LoadOrientedFrontpic`'s
## `.x_flip` bit-reverses every byte as it loads, mirroring each tile's pixels,
## and `PlaceGraphic`'s `.right` then walks the tile columns with `dec hl`, so
## the first column lands in the box's last. Reversing the columns alone
## scrambles the sprite, which is what a column-strip reversal did here.
##
## The two compose exactly into [method Image.flip_x]: a pixel at
## `x = 8 * column + px` lands at `8 * (columns - 1 - column) + (7 - px)`, which
## is `width - 1 - x`. `PrepMonFrontpic` is the one caller that sets the flag and
## the Oak speech the one screen that reaches it.
static func x_flipped(image: Image) -> Image:
	if image == null:
		return image
	var out: Image = image.duplicate()
	out.flip_x()
	return out


## `PadFrontpic` (engine/gfx/load_pics.asm) fills the 7x7 block a front pic is
## placed in, and does not centre a smaller pic: it lays one blank tile column
## before it and blank rows above it, so the pic is bottom-aligned one column in.
## This is that left pad, in tiles, for a [param width]-tile-wide pic.
##
## [param mirrored] is `wBoxAlignment`, which `LoadOrientedFrontpic` reads:
## reversing the columns leaves the trailing blank on the left instead, which for
## a 5x5 is one column further in than a 6x6.
static func frontpic_pad_columns(width: int, mirrored: bool = false) -> int:
	if width >= FRONTPIC_TILES or width <= 0:
		return 0
	return FRONTPIC_TILES - 1 - width if mirrored else 1


## The same pad above the pic, in tiles. `PadFrontpic` writes its blank tiles in
## front of each column, so a shorter pic is bottom-aligned in the box whichever
## way `wBoxAlignment` runs its columns.
static func frontpic_pad_rows(height: int) -> int:
	if height >= FRONTPIC_TILES or height <= 0:
		return 0
	return FRONTPIC_TILES - height


## The same mirror on an index buffer, for a caller that will recolour it.
static func x_flipped_indices(indices: PackedByteArray, width: int) -> PackedByteArray:
	if width <= 0:
		return indices
	var out := PackedByteArray()
	out.resize(indices.size())
	@warning_ignore("integer_division")
	var height: int = indices.size() / width
	for y: int in height:
		var row: int = y * width
		for x: int in width:
			out[row + x] = indices[row + width - 1 - x]
	return out
