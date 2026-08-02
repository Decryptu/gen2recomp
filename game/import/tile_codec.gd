class_name Gen2Tiles
extends RefCounted

## Game Boy 2bpp tile data to one-byte-per-pixel colour indices.
##
## A tile is 8x8 pixels in 16 bytes: two bytes per row, the first holding the
## low bit of every pixel in that row and the second the high bit. Bit 7 is the
## leftmost pixel.
##
## Decoding stops at indices 0-3. Turning those into colours needs a palette,
## which is a separate concern; see [Gen2Palette]. Keeping the two apart is
## what makes shiny variants free: same pixels, different palette.

const TILE_WIDTH: int = 8
const TILE_HEIGHT: int = 8
const TILE_PIXELS: int = 64
## Bytes of 2bpp data per tile.
const TILE_BYTES: int = 16


## Decodes one tile into [param out] starting at [param out_offset], as 8 rows
## of 8 indices. [param out] must already be large enough.
static func decode_tile_into(
	data: PackedByteArray, offset: int, out: PackedByteArray, out_offset: int
) -> void:
	for row: int in TILE_HEIGHT:
		var low: int = data[offset + row * 2]
		var high: int = data[offset + row * 2 + 1]
		for column: int in TILE_WIDTH:
			var shift: int = 7 - column
			var index: int = ((low >> shift) & 1) | (((high >> shift) & 1) << 1)
			out[out_offset + row * TILE_WIDTH + column] = index


static func decode_tile(data: PackedByteArray, offset: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(TILE_PIXELS)
	if offset < 0 or offset + TILE_BYTES > data.size():
		return out
	decode_tile_into(data, offset, out, 0)
	return out


## Decodes a Pokémon or trainer pic into a row-major index buffer
## [param columns] * 8 wide and [param rows] * 8 tall.
##
## Pics store their tiles column-major, the whole left column top to bottom and
## then the next, because the game streams them into VRAM a column at a time.
## Every other tilemap in these games is row-major, so this is the one place
## that ordering flips.
##
## Trailing data is ignored: Crystal's front pics carry the frames of the
## Pokédex animation after the still image, so a stream is routinely longer
## than [param columns] * [param rows] tiles.
static func decode_pic(data: PackedByteArray, columns: int, rows: int) -> PackedByteArray:
	var width: int = columns * TILE_WIDTH
	var out: PackedByteArray = PackedByteArray()
	out.resize(width * rows * TILE_HEIGHT)

	if columns <= 0 or rows <= 0 or data.size() < columns * rows * TILE_BYTES:
		return out

	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(TILE_PIXELS)

	for column: int in columns:
		for row: int in rows:
			var tile: int = column * rows + row
			decode_tile_into(data, tile * TILE_BYTES, pixels, 0)
			for y: int in TILE_HEIGHT:
				var destination: int = (row * TILE_HEIGHT + y) * width + column * TILE_WIDTH
				for x: int in TILE_WIDTH:
					out[destination + x] = pixels[y * TILE_WIDTH + x]

	return out


## Copies an index buffer into a larger one. Pics are stored in fixed-size atlas
## cells so the renderer can index them arithmetically, and a 5x5 pic has to
## land in a 7x7 cell somewhere.
static func blit(
	source: PackedByteArray,
	source_width: int,
	destination: PackedByteArray,
	destination_width: int,
	at_x: int,
	at_y: int
) -> void:
	if source_width <= 0:
		return
	var height: int = source.size() / source_width
	for y: int in height:
		var from: int = y * source_width
		var to: int = (at_y + y) * destination_width + at_x
		for x: int in source_width:
			destination[to + x] = source[from + x]
