class_name Gen2WorldCollision
extends RefCounted

## Generation 2 collision-code permissions.
##
## A map's collision grid stores the raw collision code from the tileset's
## four-cell table. The game looks that code up in a second table before it
## decides whether ordinary walking can enter the cell. Keeping that lookup
## here leaves the imported code available for water, ledges and warp handling.
##
## The table below is the source [code]CollisionPermissionTable[/code], entry for
## entry; Gold, Silver and Crystal ship the same 256 bytes. It is carried whole
## rather than as a list of the interesting codes, because a code left off such a
## list silently becomes ordinary ground: that is how the waterfall, current and
## buoy families, and one of the two headbutt trees, were walkable here.

const LAND_TILE: int = 0x00
const WATER_TILE: int = 0x01
const WALL_TILE: int = 0x0F
## The bit the source sets on a tile that answers to a button as well as
## blocking or floating: cut and headbutt trees, whirlpools and buoys. It rides
## on top of the permission rather than replacing it, so it is masked off before
## the permission is compared.
const TALK: int = 0x10

## One permission per collision code, sixteen to a row.
const PERMISSIONS: Array[int] = [
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F,  # $00
	0x00, 0x00, 0x1F, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x1F, 0x00, 0x00,  # $10
	0x01, 0x01, 0x11, 0x00, 0x11, 0x01, 0x01, 0x0F, 0x01, 0x01, 0x11, 0x00, 0x11, 0x01, 0x01, 0x0F,  # $20
	0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,  # $30
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # $40
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # $50
	0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00,  # $60
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # $70
	0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x00, 0x00, 0x00, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x00, 0x00, 0x00,  # $80
	0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F,  # $90
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # $A0
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # $B0
	0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,  # $C0
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # $D0
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # $E0
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F,  # $F0
]


## The permission the original engine uses for [param collision_code], with the
## TALK bit masked off. Out-of-range values answer wall, which is the safe answer
## for a corrupt map rather than silently opening it; every value a cartridge can
## store is in the table.
static func permission_for(collision_code: int) -> int:
	if collision_code < 0 or collision_code >= PERMISSIONS.size():
		return WALL_TILE
	return PERMISSIONS[collision_code] & ~TALK


## Whether the source lets the player face [param collision_code] and press A:
## a cut or headbutt tree, a whirlpool or a buoy. The permission still blocks or
## floats; this is the other half of the same byte.
static func talks(collision_code: int) -> bool:
	if collision_code < 0 or collision_code >= PERMISSIONS.size():
		return false
	return (PERMISSIONS[collision_code] & TALK) != 0


## Normal walking only accepts cells whose permission is LAND. Water and
## special collision codes need stateful movement rules that are not part of
## this first runtime slice.
static func is_walkable(collision_code: int) -> bool:
	return permission_for(collision_code) == LAND_TILE


## Ledges: engine/overworld/player_movement.asm's .TryJump. A hop is only
## attempted after an ordinary step into the faced cell is blocked, and it
## reads the collision code of the cell the player is already standing on
## (wPlayerTileCollision), not the faced cell. All eight hop codes are
## LAND_TILE in PERMISSIONS, so the player already walks onto one normally;
## the hop itself bypasses collision on both the intervening and landing
## cells, matching the source, which never checks either.
const HI_NYBBLE_LEDGES: int = 0xA0
const COLL_HOP_RIGHT: int = 0xA0
const COLL_HOP_LEFT: int = 0xA1
const COLL_HOP_UP: int = 0xA2
const COLL_HOP_DOWN: int = 0xA3
const COLL_HOP_DOWN_RIGHT: int = 0xA4
const COLL_HOP_DOWN_LEFT: int = 0xA5
const COLL_HOP_UP_RIGHT: int = 0xA6
const COLL_HOP_UP_LEFT: int = 0xA7

## wFacingDirection bit values (constants/ram_constants.asm): FACE_DOWN = 8,
## FACE_UP = 4, FACE_LEFT = 2, FACE_RIGHT = 1. .TryJump ANDs this against the
## matching .ledge_table entry.
const FACE_RIGHT: int = 1
const FACE_LEFT: int = 2
const FACE_UP: int = 4
const FACE_DOWN: int = 8

## .ledge_table, entry for entry, indexed by a hop code's low three bits.
## .TryJump computes this index as [code] & 7 after only checking the high
## nybble is HI_NYBBLE_LEDGES, so codes $A8-$AF alias into this same table
## rather than being rejected; that quirk is preserved by allows_hop() below
## rather than papered over, since those codes are unused in every pinned
## tileset and the source itself does not special-case them.
const LEDGE_FACE_MASK: Array[int] = [
	FACE_RIGHT,               # COLL_HOP_RIGHT
	FACE_LEFT,                # COLL_HOP_LEFT
	FACE_UP,                  # COLL_HOP_UP
	FACE_DOWN,                # COLL_HOP_DOWN
	FACE_RIGHT | FACE_DOWN,   # COLL_HOP_DOWN_RIGHT
	FACE_DOWN | FACE_LEFT,    # COLL_HOP_DOWN_LEFT
	FACE_UP | FACE_RIGHT,     # COLL_HOP_UP_RIGHT
	FACE_UP | FACE_LEFT,      # COLL_HOP_UP_LEFT
]


static func _face_mask_for_direction(direction: Vector2i) -> int:
	if direction == Vector2i.UP:
		return FACE_UP
	if direction == Vector2i.DOWN:
		return FACE_DOWN
	if direction == Vector2i.LEFT:
		return FACE_LEFT
	if direction == Vector2i.RIGHT:
		return FACE_RIGHT
	return 0


## Whether standing on [param collision_code] lets the player hop toward
## [param direction], matching .TryJump bit for bit: the high nybble must be
## HI_NYBBLE_LEDGES and the low three bits must index a .ledge_table entry
## whose mask includes the pressed direction.
static func allows_hop(collision_code: int, direction: Vector2i) -> bool:
	if collision_code < 0 or collision_code > 0xFF:
		return false
	if (collision_code & 0xF0) != HI_NYBBLE_LEDGES:
		return false
	var face: int = _face_mask_for_direction(direction)
	if face == 0:
		return false
	var index: int = collision_code & 0x07
	return (LEDGE_FACE_MASK[index] & face) != 0


## Tile-collision std scripts: engine/events/std_collision.asm's
## CheckFacingTileForStdScript, dispatched on A after object and background
## events both find nothing. data/collision/collision_stdscripts.asm is byte
## identical between pokecrystal and pokegold, but the std-script index each
## entry resolves to is not: engine/events/std_scripts.asm lists PCScript at
## index 49 in Crystal and 43 in Gold/Silver, because Crystal's table carries
## six extra phone entries earlier in the same list. Every other entry here
## was recounted in both pinned repositories and lands on the same index in
## both games.
const COLL_BOOKSHELF: int = 0x91
const COLL_PC: int = 0x93
const COLL_RADIO: int = 0x94
const COLL_TOWN_MAP: int = 0x95
const COLL_MART_SHELF: int = 0x96
const COLL_TV: int = 0x97
const COLL_WINDOW: int = 0x9D
const COLL_INCENSE_BURNER: int = 0x9F

const TILE_COLLISION_STD_INDEX_CRYSTAL: Dictionary = {
	COLL_BOOKSHELF: 3,        # MagazineBookshelfScript
	COLL_PC: 49,              # PCScript
	COLL_RADIO: 11,           # Radio1Script
	COLL_TOWN_MAP: 7,         # TownMapScript
	COLL_MART_SHELF: 6,       # MerchandiseShelfScript
	COLL_TV: 9,               # TVScript
	COLL_WINDOW: 8,           # WindowScript
	COLL_INCENSE_BURNER: 5,   # IncenseBurnerScript
}

const TILE_COLLISION_STD_INDEX_GOLD_SILVER: Dictionary = {
	COLL_BOOKSHELF: 3,        # MagazineBookshelfScript
	COLL_PC: 43,              # PCScript
	COLL_RADIO: 11,           # Radio1Script
	COLL_TOWN_MAP: 7,         # TownMapScript
	COLL_MART_SHELF: 6,       # MerchandiseShelfScript
	COLL_TV: 9,               # TVScript
	COLL_WINDOW: 8,           # WindowScript
	COLL_INCENSE_BURNER: 5,   # IncenseBurnerScript
}


## The std-script index [param collision_code] dispatches to on A, or -1 when
## the code has no entry in TileCollisionStdScripts.
static func tile_collision_std_index(collision_code: int, is_crystal: bool) -> int:
	var table: Dictionary = TILE_COLLISION_STD_INDEX_CRYSTAL if is_crystal \
		else TILE_COLLISION_STD_INDEX_GOLD_SILVER
	return int(table.get(collision_code, -1))
