class_name Gen2WorldTileset
extends RefCounted

## Runtime data for one overworld tileset.
##
## Graphics are kept in the cache as an indexed tile strip and loaded lazily by
## GameData. The metatile and collision tables stay here because map expansion
## needs them without opening the cartridge.

var number: int = 0
var block_count: int = 0
var tile_count: int = RomLayout.TILESET_TILE_COUNT
## The three lookup tables are cartridge bytes and are read once per drawn tile,
## so they are packed rather than kept as Arrays of Variants. Only the animation
## command list stays an Array, because its entries are records.
var meta: PackedByteArray = PackedByteArray()
var collision: PackedByteArray = PackedByteArray()
var animation_pointer: int = 0
var palette_map_pointer: int = 0
var palette_map: PackedByteArray = PackedByteArray()
var animation_commands: Array = []


static func from_cache(value: Dictionary) -> Gen2WorldTileset:
	var out := Gen2WorldTileset.new()
	out.number = int(value.get("number", 0))
	out.block_count = int(value.get("block_count", 0))
	out.tile_count = int(value.get("tile_count", RomLayout.TILESET_TILE_COUNT))
	out.meta = RomCache.packed_bytes(value.get("meta", []))
	out.collision = RomCache.packed_bytes(value.get("collision", []))
	out.animation_pointer = int(value.get("animation_pointer", 0))
	out.palette_map_pointer = int(value.get("palette_map_pointer", 0))
	out.palette_map = RomCache.packed_bytes(value.get("palette_map", []))
	out.animation_commands = value.get("animation_commands", []) if value.get("animation_commands", []) is Array else []
	return out


## Which tile of the strip one of a block's sixteen positions draws, in the
## metatile byte's own numbering: 0..95 is the first graphics block and 128..223
## the second. A byte past the strip is an unused block's $FF placeholder and
## resolves to 0, so a caller can index [method GameData.world_tileset_indices]
## with the answer.
func tile_index(block: int, tile: int) -> int:
	if block < 0 or block >= block_count or tile < 0 or tile >= RomLayout.MAP_BLOCK_TILE_WIDTH * RomLayout.MAP_BLOCK_TILE_WIDTH:
		return 0
	var at: int = block * RomLayout.TILESET_META_BYTES_PER_BLOCK + tile
	if at >= meta.size():
		return 0
	var index: int = meta[at]
	return index if index < tile_count else 0


func collision_index(block: int, cell_x: int, cell_y: int) -> int:
	if block <= 0 or block >= block_count or cell_x < 0 or cell_x >= 2 or cell_y < 0 or cell_y >= 2:
		return -1
	var at: int = block * RomLayout.TILESET_COLLISION_BYTES_PER_BLOCK + cell_x + cell_y * 2
	return collision[at] if at < collision.size() else -1


## Which of the eight background palette slots a tile of the strip draws with.
##
## Palette maps store two assignments per byte, low nibble first, over the whole
## 224-tile span. Bit 3 of a nibble is the VRAM bank the cartridge draws that
## tile from and is dropped here: the strip is flat, so the tile number already
## says which graphics block it came from.
func palette_index(tile: int) -> int:
	if tile < 0 or tile >= tile_count:
		return 0
	var at: int = tile >> 1
	if at >= palette_map.size():
		return 0
	var packed: int = palette_map[at]
	var nibble: int = packed & 0x0F if (tile & 1) == 0 else packed >> 4
	return nibble & 0x07
