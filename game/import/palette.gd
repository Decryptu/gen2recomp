class_name Gen2Palette
extends RefCounted

## Game Boy Color palette entries.
##
## A colour is 15 bits packed little-endian as $0BBBBBGG GGGRRRRR — five bits
## per channel, red in the low bits. The hardware ignores bit 15.
##
## A Pokémon's stored palette holds only two colours. The other two are implied:
## every pic uses index 0 for white and index 3 for black, so only the middle
## pair varies. Each species stores two such pairs, normal and shiny, which is
## the whole of what being shiny means to the renderer.

const COLOR_BYTES: int = 2
## Two colours, normal and shiny.
const ENTRY_BYTES: int = 8
const COLORS_PER_PIC: int = 4


static func decode_color(data: PackedByteArray, offset: int) -> Color:
	if offset < 0 or offset + COLOR_BYTES > data.size():
		return Color.MAGENTA
	return from_packed(data[offset] | (data[offset + 1] << 8))


## The cache stores colours as the cartridge's own 15-bit value rather than as
## anything wider, so nothing is rounded on the way in and out.
static func from_packed(packed: int) -> Color:
	return Color(
		_expand(packed & 0x1F),
		_expand((packed >> 5) & 0x1F),
		_expand((packed >> 10) & 0x1F),
	)


## The four colours a pic is drawn with, in index order.
static func pic_palette(middle: PackedColorArray) -> PackedColorArray:
	var out: PackedColorArray = PackedColorArray([Color.WHITE])
	out.append_array(middle)
	out.append(Color.BLACK)
	return out


## Reads one species' entry as { normal, shiny }, each a two-colour array.
static func decode_entry(data: PackedByteArray, offset: int) -> Dictionary:
	return {
		"normal": PackedColorArray([
			decode_color(data, offset),
			decode_color(data, offset + COLOR_BYTES),
		]),
		"shiny": PackedColorArray([
			decode_color(data, offset + COLOR_BYTES * 2),
			decode_color(data, offset + COLOR_BYTES * 3),
		]),
	}


## 5 bits to a float. Scaling by 31 rather than 32 keeps $1F exactly white,
## which matters because the two implied colours are pure white and black.
static func _expand(component: int) -> float:
	return float(component) / 31.0
