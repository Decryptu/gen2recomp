class_name Gen2WorldSprite
extends RefCounted

## One entry from the cartridge's OverworldSprites table plus its decoded
## indexed tile strip. The source uses three sprite types: walking sprites have
## twelve tiles, standing sprites use the same facing layout without movement,
## and still sprites contain one four-tile image.

const TYPE_WALKING: int = 1
const TYPE_STANDING: int = 2
const TYPE_STILL: int = 3

const FACING_DOWN: int = 0
const FACING_UP: int = 1
const FACING_LEFT: int = 2
const FACING_RIGHT: int = 3

var number: int = 0
var address: int = 0
var bank: int = 0
var bytes: int = 0
var tiles: int = 0
var sprite_type: int = TYPE_STILL
var default_palette: int = 0


static func from_cache(value: Dictionary) -> Gen2WorldSprite:
	var out := Gen2WorldSprite.new()
	out.number = int(value.get("number", 0))
	out.address = int(value.get("address", 0))
	out.bank = int(value.get("bank", 0))
	out.bytes = int(value.get("bytes", 0))
	out.tiles = int(value.get(
		"tiles", floori(float(out.bytes) / float(Gen2Tiles.TILE_BYTES))
	))
	out.sprite_type = int(value.get("type", TYPE_STILL))
	out.default_palette = int(value.get("palette", 0))
	return out


func is_walking() -> bool:
	return sprite_type == TYPE_WALKING


## Returns the first tile of a 4-tile frame in the source strip. The original
## data has down, up and left facings in four-frame groups; right reuses left
## with a horizontal flip in the renderer.
func frame_tile_offset(facing: int, frame: int) -> int:
	if tiles <= 4 or sprite_type == TYPE_STILL:
		return 0
	var facing_index: int = clampi(facing, FACING_DOWN, FACING_RIGHT)
	if facing_index == FACING_RIGHT:
		facing_index = FACING_LEFT
	return facing_index * 4 + clampi(frame, 0, 3)


## Composes one 16x16 object image from the source's horizontal tile strip.
## Colour index zero is transparent under the Game Boy object-palette rules.
static func image_for(
	sprite: Gen2WorldSprite,
	indices: PackedByteArray,
	palette: PackedColorArray,
	facing: int = FACING_DOWN,
	frame: int = 0,
) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if sprite == null or sprite.tiles < 4:
		return image
	var width: int = sprite.tiles * Gen2Tiles.TILE_WIDTH
	var source_tile: int = sprite.frame_tile_offset(facing, frame)
	if source_tile < 0 or source_tile + 4 > sprite.tiles or indices.size() < width * 8:
		return image

	for tile: int in 4:
		var source_x: int = (source_tile + tile) * Gen2Tiles.TILE_WIDTH
		var destination_x: int = (tile & 1) * Gen2Tiles.TILE_WIDTH
		var destination_y: int = (tile >> 1) * Gen2Tiles.TILE_HEIGHT
		for y: int in Gen2Tiles.TILE_HEIGHT:
			for x: int in Gen2Tiles.TILE_WIDTH:
				var color_index: int = int(indices[y * width + source_x + x])
				var color := Color.MAGENTA
				if color_index < palette.size():
					color = palette[color_index]
				if color_index == 0:
					color.a = 0.0
				image.set_pixel(destination_x + x, destination_y + y, color)

	if facing == FACING_RIGHT:
		image.flip_x()
	return image
