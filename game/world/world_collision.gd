class_name Gen2WorldCollision
extends RefCounted

## Generation 2 collision-code permissions.
##
## A map's collision grid stores the raw code from the tileset's four-cell table,
## which the game looks up in a second table before deciding whether ordinary
## walking can enter. Keeping that lookup here leaves the imported code available
## for water, ledges and warps.
##
## The table below is the source [code]CollisionPermissionTable[/code] entry for
## entry; all three games ship the same 256 bytes. Carried whole rather than as a
## list of interesting codes, because a code left off such a list silently
## becomes ordinary ground: that is how the waterfall, current and buoy families,
## and one of the two headbutt trees, were walkable here.

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


## Ledges: engine/overworld/player_movement.asm's .TryJump. Attempted only after
## an ordinary step into the faced cell is blocked, reading the collision code of
## the cell the player already stands on (wPlayerTileCollision). All eight hop
## codes are LAND_TILE in PERMISSIONS, so the player walks onto one normally; the
## hop bypasses collision on both the intervening and landing cells, as the
## source never checks either.
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


## wFacingDirection's FACE_* bit for a cardinal [param direction], or 0 for a
## diagonal or zero vector.
static func face_mask_for_direction(direction: Vector2i) -> int:
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
	var face: int = face_mask_for_direction(direction)
	if face == 0:
		return false
	var index: int = collision_code & 0x07
	return (LEDGE_FACE_MASK[index] & face) != 0


## Side walls and side buoys: home/map.asm's GetMovementPermissions and
## engine/overworld/npc_movement.asm's CanObjectLeaveTile/WillObjectBumpIntoTile.
## Unlike the ledge codes above, these stay their plain permission ($b0-$b7
## LAND_TILE, $c0-$c7 WATER_TILE in PERMISSIONS) and additionally wall off one
## or two of the standing tile's own edges by direction.
const HI_NYBBLE_SIDE_WALLS: int = 0xB0
const HI_NYBBLE_SIDE_BUOYS: int = 0xC0
const COLL_RIGHT_WALL: int = 0xB0
const COLL_LEFT_WALL: int = 0xB1
const COLL_UP_WALL: int = 0xB2
const COLL_DOWN_WALL: int = 0xB3
const COLL_DOWN_RIGHT_WALL: int = 0xB4
const COLL_DOWN_LEFT_WALL: int = 0xB5
const COLL_UP_RIGHT_WALL: int = 0xB6
const COLL_UP_LEFT_WALL: int = 0xB7

## .MovementPermissionsData, entry for entry, indexed by a wall/buoy code's low
## three bits: which of the standing tile's own edges it walls off, in FACE_*
## terms. Numerically identical to LEDGE_FACE_MASK above; kept as its own
## table because a ledge direction and a walled edge are different things, and
## the source keeps them as two separate tables too.
const SIDE_WALL_FACE_MASK: Array[int] = [
	FACE_RIGHT,               # COLL_RIGHT_WALL/BUOY
	FACE_LEFT,                # COLL_LEFT_WALL/BUOY
	FACE_UP,                  # COLL_UP_WALL/BUOY
	FACE_DOWN,                # COLL_DOWN_WALL/BUOY
	FACE_DOWN | FACE_RIGHT,   # COLL_DOWN_RIGHT_WALL/BUOY
	FACE_DOWN | FACE_LEFT,    # COLL_DOWN_LEFT_WALL/BUOY
	FACE_UP | FACE_RIGHT,     # COLL_UP_RIGHT_WALL/BUOY
	FACE_UP | FACE_LEFT,      # COLL_UP_LEFT_WALL/BUOY
]


## The FACE_* mask of edges [param collision_code] walls off, or 0 when it is
## not a side-wall or side-buoy code. .CheckHiNybble ANDs against $f0 before
## comparing, so $b8-$bf and $c8-$cf alias onto the same eight entries as
## $b0-$b7/$c0-$c7 rather than being rejected, the same way allows_hop()
## preserves the $a8-$af ledge alias above.
static func side_wall_face_mask(collision_code: int) -> int:
	if collision_code < 0 or collision_code > 0xFF:
		return 0
	var hi_nybble: int = collision_code & 0xF0
	if hi_nybble != HI_NYBBLE_SIDE_WALLS and hi_nybble != HI_NYBBLE_SIDE_BUOYS:
		return 0
	return SIDE_WALL_FACE_MASK[collision_code & 0x07]


## engine/overworld/npc_movement.asm's CanObjectLeaveTile (leave rule, on
## [param from_code]) and WillObjectBumpIntoTile (enter rule, on [param
## to_code] at the destination). Both routines index a differently bit-packed
## table than SIDE_WALL_FACE_MASK (GetSideWallDirectionMask's DOWN_MASK/
## UP_MASK/LEFT_MASK/RIGHT_MASK, keyed by wWalkingDirection rather than
## wFacingDirection), but produce the identical per-code, per-direction result;
## this reuses the FACE_* table rather than re-encoding the same rule twice.
## Both games ship byte-identical npc_movement.asm, so unlike tile_permissions()
## below this never takes a profile argument.
static func side_wall_step_blocked(from_code: int, to_code: int, direction: Vector2i) -> bool:
	var forward_face: int = face_mask_for_direction(direction)
	if forward_face == 0:
		return false
	if (side_wall_face_mask(from_code) & forward_face) != 0:
		return true
	return (side_wall_face_mask(to_code) & face_mask_for_direction(-direction)) != 0


## home/map.asm's GetMovementPermissions: the wTilePermissions byte for a
## player standing on [param standing_code] with the four cardinal neighbours
## already read. The leave rule (side_wall_face_mask of the standing code) is
## byte-identical between both games; the enter rule (whether a neighbour's own
## wall faces back at the player) is not. pokegold/pokecrystal diverge only in
## .ok_down/.ok_up/.ok_right/.ok_left: crystal ORs the matching FACE_* constant
## on a match, gold always sets bit RIGHT, numerically FACE_DOWN, since
## wFacingDirection and wWalkingDirection use transposed bit layouts and
## .ok_down/.ok_up/.ok_right/.ok_left were written with the latter's RIGHT by
## mistake. Every enter-rule match therefore blocks only DOWN on Gold/Silver.
## No shipped Gold/Silver map carries a side-wall code whose low three bits
## differ from 2 (COLL_UP_WALL, whose own FACE_UP mask cannot match any
## opposite-face test below), so this split changes no pinned map's
## reachability; it stays because a mod-authored map could reach it.
static func tile_permissions(
	standing_code: int, up_code: int, down_code: int, left_code: int, right_code: int,
	is_crystal: bool = true,
) -> int:
	var permissions: int = side_wall_face_mask(standing_code)
	if (side_wall_face_mask(down_code) & FACE_UP) != 0:
		# .ok_down already wants FACE_DOWN on both games, so the Gold quirk is
		# not observable here even though .Down shares the same shape.
		permissions |= FACE_DOWN
	if (side_wall_face_mask(up_code) & FACE_DOWN) != 0:
		permissions |= FACE_UP if is_crystal else FACE_DOWN
	if (side_wall_face_mask(right_code) & FACE_LEFT) != 0:
		permissions |= FACE_RIGHT if is_crystal else FACE_DOWN
	if (side_wall_face_mask(left_code) & FACE_RIGHT) != 0:
		permissions |= FACE_LEFT if is_crystal else FACE_DOWN
	return permissions


## Forced tiles: engine/overworld/player_movement.asm's DoPlayerMovement.CheckTile,
## which runs in all three movement modes after .GetAction and before .CheckTurning,
## .TryStep/.TrySurf and .CheckWarp. It reads the code of the cell the player
## already stands on and overwrites wWalkingDirection, so the pressed direction is
## discarded. A match reaches .continue_walk, whose .DoStep never consults
## permissions, so a forced step ignores collision entirely.
const HI_NYBBLE_CURRENT: int = 0x30
const HI_NYBBLE_WALK: int = 0x40
const HI_NYBBLE_WALK_ALT: int = 0x50
const HI_NYBBLE_WARPS: int = 0x70
const COLL_WHIRLPOOL: int = 0x24
const COLL_WHIRLPOOL_2C: int = 0x2C
const COLL_DOOR: int = 0x71
const COLL_DOOR_79: int = 0x79
const COLL_STAIRCASE: int = 0x7A
const COLL_CAVE: int = 0x7B

## .water_table, indexed by a current code's low two bits. The source masks
## NUM_DIRECTIONS, not seven, so every code $30-$3f reaches this table.
const CURRENT_DIRECTION: Array[Vector2i] = [
	Vector2i.RIGHT,   # COLL_WATERFALL_RIGHT
	Vector2i.LEFT,    # COLL_WATERFALL_LEFT
	Vector2i.UP,      # COLL_WATERFALL_UP
	Vector2i.DOWN,    # COLL_WATERFALL
]

## .land1_table and .land2_table, indexed by the low three bits. Vector2i.ZERO is
## the source's STANDING, which falls through to no forced movement.
const WALK_DIRECTION: Array[Vector2i] = [
	Vector2i.ZERO,    # COLL_BRAKE
	Vector2i.RIGHT,   # COLL_WALK_RIGHT
	Vector2i.LEFT,    # COLL_WALK_LEFT
	Vector2i.UP,      # COLL_WALK_UP
	Vector2i.DOWN,    # COLL_WALK_DOWN
	Vector2i.ZERO,    # COLL_BRAKE_45
	Vector2i.ZERO,    # COLL_BRAKE_46
	Vector2i.ZERO,    # COLL_BRAKE_47
]
const WALK_ALT_DIRECTION: Array[Vector2i] = [
	Vector2i.RIGHT,   # COLL_WALK_RIGHT_ALT
	Vector2i.LEFT,    # COLL_WALK_LEFT_ALT
	Vector2i.UP,      # COLL_WALK_UP_ALT
	Vector2i.DOWN,    # COLL_WALK_DOWN_ALT
	Vector2i.ZERO,    # COLL_BRAKE_ALT
	Vector2i.ZERO,    # COLL_BRAKE_55
	Vector2i.ZERO,    # COLL_BRAKE_56
	Vector2i.ZERO,    # COLL_BRAKE_57
]

## The .warps branch accepts four codes and refuses every other $7x.
const WARP_STEP_CODES: Array[int] = [COLL_DOOR, COLL_DOOR_79, COLL_STAIRCASE, COLL_CAVE]


## What .CheckTile does to a player standing on [param collision_code]:
## [code]none[/code], [code]force_turn[/code] (CheckWhirlpoolTile matched, so
## PLAYERMOVEMENT_FORCE_TURN queues Script_ForcedMovement) or [code]walk[/code]
## with the direction the tile imposes. Branch order is the source's.
static func forced_action(collision_code: int) -> Dictionary:
	if collision_code < 0 or collision_code > 0xFF:
		return {"kind": &"none"}
	if collision_code == COLL_WHIRLPOOL or collision_code == COLL_WHIRLPOOL_2C:
		return {"kind": &"force_turn"}
	var direction: Vector2i = Vector2i.ZERO
	match collision_code & 0xF0:
		HI_NYBBLE_CURRENT:
			direction = CURRENT_DIRECTION[collision_code & 0x03]
		HI_NYBBLE_WALK:
			direction = WALK_DIRECTION[collision_code & 0x07]
		HI_NYBBLE_WALK_ALT:
			direction = WALK_ALT_DIRECTION[collision_code & 0x07]
		HI_NYBBLE_WARPS:
			direction = Vector2i.DOWN if WARP_STEP_CODES.has(collision_code) else Vector2i.ZERO
	if direction == Vector2i.ZERO:
		return {"kind": &"none"}
	return {"kind": &"walk", "direction": direction}


## Tile-collision std scripts: engine/events/std_collision.asm's
## CheckFacingTileForStdScript, dispatched on A once object and background events
## both find nothing. data/collision/collision_stdscripts.asm is byte identical
## between the two repositories, but the std-script index each entry resolves to
## is not: PCScript is 49 in Crystal and 43 in Gold/Silver, because Crystal's
## table carries six extra phone entries earlier. Every other entry was recounted
## in both and lands on the same index.
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
