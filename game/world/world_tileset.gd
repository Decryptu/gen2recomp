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
var meta: Array = []
var collision: Array = []
var animation_pointer: int = 0
var palette_map_pointer: int = 0


static func from_cache(value: Dictionary) -> Gen2WorldTileset:
	var out := Gen2WorldTileset.new()
	out.number = int(value.get("number", 0))
	out.block_count = int(value.get("block_count", 0))
	out.tile_count = int(value.get("tile_count", RomLayout.TILESET_TILE_COUNT))
	out.meta = value.get("meta", []) if value.get("meta", []) is Array else []
	out.collision = value.get("collision", []) if value.get("collision", []) is Array else []
	out.animation_pointer = int(value.get("animation_pointer", 0))
	out.palette_map_pointer = int(value.get("palette_map_pointer", 0))
	return out


func tile_index(block: int, tile: int) -> int:
	if block < 0 or block >= block_count or tile < 0 or tile >= RomLayout.MAP_BLOCK_TILE_WIDTH * RomLayout.MAP_BLOCK_TILE_WIDTH:
		return 0
	var at: int = block * RomLayout.TILESET_META_BYTES_PER_BLOCK + tile
	return int(meta[at]) if at < meta.size() else 0


func collision_index(block: int, cell_x: int, cell_y: int) -> int:
	if block <= 0 or block >= block_count or cell_x < 0 or cell_x >= 2 or cell_y < 0 or cell_y >= 2:
		return -1
	var at: int = block * RomLayout.TILESET_COLLISION_BYTES_PER_BLOCK + cell_x + cell_y * 2
	return int(collision[at]) if at < collision.size() else -1
