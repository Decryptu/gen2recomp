class_name Gen2PicImage
extends RefCounted

## Colour indices plus a palette to an [Image].
##
## The cache stores what the cartridge stores: two bits per pixel, no colour. The
## palette is chosen here, at draw time, so a shiny sprite costs one different
## [PackedColorArray] rather than a second copy of the pixels.
##
## The image is built as one buffer for [method Image.create_from_data]:
## per-pixel [method Image.set_pixel] on a 56x56 sprite is 3136 binding calls for
## a table lookup, and a battle can want several sprites a frame.
##
## Node-free: an [Image] is data, not a scene, so this can be checked headless.

const CHANNELS: int = 4


## An image [param width] x [param height] pixels from a row-major index buffer.
##
## [param transparent_background] makes index 0 transparent. The hardware has no
## alpha and draws that index as white, which is right for a battle sprite in
## its window; it is wrong for a sprite over anything else.
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


## One cell out of a pic atlas, cropped to the pic's real size.
##
## [param pic] is what [method GameData.species_pic] returns: which atlas, which
## slot, and how much of the cell the sprite actually fills. Cropping matters
## because a cell is the size of the largest pic of its kind, so a 5x5 sprite
## carries two rows and columns of blank tiles it should not be positioned by.
static func from_atlas(
	indices: PackedByteArray,
	atlas: Dictionary,
	pic: Dictionary,
	palette: PackedColorArray,
	transparent_background: bool = false
) -> Image:
	var cell: int = int(atlas.get("cell", 0))
	var columns: int = int(atlas.get("columns", 0))
	var atlas_width: int = int(atlas.get("width", 0))
	var slot: int = int(pic.get("slot", -1))
	if cell <= 0 or columns <= 0 or atlas_width <= 0 or slot < 0:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)

	var width: int = mini(int(pic.get("width", cell)), cell)
	var height: int = mini(int(pic.get("height", cell)), cell)
	if width <= 0 or height <= 0:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)

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

	return from_indices(cropped, width, height, palette, transparent_background)


## The palette flattened to bytes, four per index, so the inner loop is a copy
## rather than a colour conversion.
static func _lookup(palette: PackedColorArray, transparent_background: bool) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(Gen2Palette.COLORS_PER_PIC * CHANNELS)

	for i: int in Gen2Palette.COLORS_PER_PIC:
		var color: Color = palette[i] if i < palette.size() else Color.MAGENTA
		var at: int = i * CHANNELS
		out[at] = int(roundf(color.r * 255.0))
		out[at + 1] = int(roundf(color.g * 255.0))
		out[at + 2] = int(roundf(color.b * 255.0))
		# The palette's own alpha, so a caller that wants one colour translucent
		# says so in the colour rather than needing a second flag. Every
		# cartridge palette is opaque, since Gen2Palette.decode_color builds an
		# opaque Color.
		out[at + 3] = 0 if transparent_background and i == 0 \
			else int(roundf(clampf(color.a, 0.0, 1.0) * 255.0))

	return out


## What `wBoxAlignment` produces, which is a plain horizontal mirror.
##
## The flag is read twice, and only both halves together make sense of it.
## `LoadOrientedFrontpic`'s `.x_flip` (`engine/gfx/load_pics.asm:401`) bit-
## reverses every byte of pic data as it loads, mirroring each tile's own
## pixels; `PlaceGraphic`'s `.right` (`engine/gfx/place_graphic.asm:30`) then
## walks the tile columns with `dec hl` instead of `inc hl`, so the pic's first
## tile column lands in the box's last. Reversing the columns without flipping
## the tiles scrambles the sprite, which is what a column-strip reversal alone
## did here.
##
## The two compose exactly into [method Image.flip_x]: a pixel at
## `x = 8 * column + px` lands at `8 * (columns - 1 - column) + (7 - px)`, which
## is `width - 1 - x`. `PrepMonFrontpic` (`home/pokemon.asm:61`) is the one
## caller that sets the flag and the Oak speech the one screen that reaches it.
static func x_flipped(image: Image) -> Image:
	if image == null:
		return image
	var out: Image = image.duplicate()
	out.flip_x()
	return out
