class_name Gen2WorldCollision
extends RefCounted

## Generation 2 collision-code permissions.
##
## A map's collision grid stores the raw collision code from the tileset's
## four-cell table. The game looks that code up in a second table before it
## decides whether ordinary walking can enter the cell. Keeping that lookup
## here leaves the imported code available for water, ledges and warp handling.

const LAND_TILE: int = 0x00
const WATER_TILE: int = 0x01
const WALL_TILE: int = 0x0F

const _WATER_CODES: Array[int] = [
	0x20, 0x21, 0x22, 0x24, 0x25, 0x26, 0x28, 0x29,
	0x2A, 0x2C, 0x2D, 0x2E,
]

const _WALL_CODES: Array[int] = [
	0x07, 0x0F, 0x12, 0x1A, 0x1D, 0x27, 0x2F, 0x62, 0x6A,
	0x80, 0x81, 0x82, 0x83, 0x84,
	0x88, 0x89, 0x8A, 0x8B, 0x8C,
	0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
	0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F,
	0xFF,
]


## The permission used by the original engine for [param collision_code].
## Unknown and out-of-range values are treated as walls, which is the safe
## answer for a corrupt or incomplete map rather than silently opening it.
static func permission_for(collision_code: int) -> int:
	if collision_code < 0 or collision_code > 0xFF:
		return WALL_TILE
	if _WATER_CODES.has(collision_code):
		return WATER_TILE
	if _WALL_CODES.has(collision_code):
		return WALL_TILE
	return LAND_TILE


## Normal walking only accepts cells whose permission is LAND. Water and
## special collision codes need stateful movement rules that are not part of
## this first runtime slice.
static func is_walkable(collision_code: int) -> bool:
	return permission_for(collision_code) == LAND_TILE
