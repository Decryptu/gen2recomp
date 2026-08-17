class_name Gen2WorldCollision
extends RefCounted

## Collision-code permissions. A map's grid stores the raw code from the
## tileset's four-cell table and the game looks it up in a second table before
## letting ordinary walking in; keeping that lookup here leaves the code itself
## available for water, ledges and warps.
##
## [constant PERMISSIONS] is [code]CollisionPermissionTable[/code] entry for
## entry, the same 256 bytes in all three games. Carried whole rather than as a
## list of interesting codes: a code left off such a list silently becomes
## ordinary ground, which is how the waterfall, current and buoy families and one
## of the two headbutt trees were once walkable here.

const LAND_TILE: int = 0x00
const WATER_TILE: int = 0x01
const WALL_TILE: int = 0x0F
## Set on a tile that answers to a button as well as blocking or floating: cut
## and headbutt trees, whirlpools and buoys. It rides on top of the permission,
## so it is masked off before the permission is compared.
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


## The engine's permission for [param collision_code], TALK masked off. Out of
## range answers wall rather than silently opening a corrupt map; every value a
## cartridge can store is in the table.
static func permission_for(collision_code: int) -> int:
	if collision_code < 0 or collision_code >= PERMISSIONS.size():
		return WALL_TILE
	return PERMISSIONS[collision_code] & ~TALK


## Whether the player may face [param collision_code] and press A. The permission
## still blocks or floats; this is the other half of the same byte.
static func talks(collision_code: int) -> bool:
	if collision_code < 0 or collision_code >= PERMISSIONS.size():
		return false
	return (PERMISSIONS[collision_code] & TALK) != 0


## Normal walking accepts LAND alone; water and the special codes are stateful.
static func is_walkable(collision_code: int) -> bool:
	return permission_for(collision_code) == LAND_TILE


## home/map_objects.asm's SetTallGrassFlags, which sets an object's IN_GRASS_F.
## Two kinds kept apart: CheckSuperTallGrassTile names the long grass alone (the
## Bug Contest doubles its encounter rate, `TryWildEncounter_BugContest`) and
## CheckGrassTile answers the rest by nybble. Neither is the encounter gate;
## [method gates_encounter] is.
const HI_NYBBLE_TALL_GRASS: int = 0x10
const HI_NYBBLE_WATER: int = 0x20
const LO_NYBBLE_GRASS: int = 0x07
const COLL_LONG_GRASS: int = 0x14
const COLL_LONG_GRASS_1C: int = 0x1C

const GRASS_NONE: int = 0
const GRASS_TALL: int = 1
const GRASS_LONG: int = 2


## Which grass a cell is, one call for a renderer drawing the two heights apart.
static func grass_kind(collision_code: int) -> int:
	if is_long_grass(collision_code):
		return GRASS_LONG
	if _check_grass_tile(collision_code):
		return GRASS_TALL
	return GRASS_NONE


## SetTallGrassFlags' own condition.
static func is_grass(collision_code: int) -> bool:
	return grass_kind(collision_code) != GRASS_NONE


## CheckSuperTallGrassTile: the two long-grass codes and nothing else.
static func is_long_grass(collision_code: int) -> bool:
	return collision_code == COLL_LONG_GRASS or collision_code == COLL_LONG_GRASS_1C


## engine/overworld/tile_events.asm's CheckGrassCollision, in its own order: a
## list rather than grass_kind()'s nybble test because COLL_WATER is on it, so
## one routine gates a surf roll, and COLL_TALL_GRASS_10 is not, so that code
## carries tufts without encounters.
const COLL_WATER: int = 0x29
const ENCOUNTER_TILE_CODES: Array[int] = [
	0x08,             # COLL_CUT_08
	0x18,             # COLL_TALL_GRASS
	COLL_LONG_GRASS,
	0x28,             # COLL_CUT_28
	COLL_WATER,
	0x48, 0x49, 0x4A, 0x4B, 0x4C,  # COLL_GRASS_48..COLL_GRASS_4C
]
## home/map_objects.asm's CheckIceTile, which CanEncounterWildMon reads after
## the grass test and a cave or dungeon reads instead of it.
const COLL_ICE: int = 0x23
const COLL_ICE_2B: int = 0x2B


## CheckGrassCollision: whether a wild encounter can be rolled here at all.
static func gates_encounter(collision_code: int) -> bool:
	return ENCOUNTER_TILE_CODES.has(collision_code)


## CheckIceTile: ice refuses an encounter wherever it is, cave included.
static func is_ice(collision_code: int) -> bool:
	return collision_code == COLL_ICE or collision_code == COLL_ICE_2B


## CheckGrassTile, nybble for nybble. Its water branch is a copy of its grass
## branch, which the source itself notes ("For some reason, the above code is
## duplicated down here"), so $20 and $28 answer grass here as they do there.
static func _check_grass_tile(collision_code: int) -> bool:
	if collision_code < 0 or collision_code > 0xFF:
		return false
	var high: int = collision_code & 0xF0
	if high != HI_NYBBLE_TALL_GRASS and high != HI_NYBBLE_WATER:
		return false
	return (collision_code & LO_NYBBLE_GRASS) == 0


## Ledges: engine/overworld/player_movement.asm's .TryJump, attempted only after
## an ordinary step is blocked and read off the cell the player already stands on
## (wPlayerTileCollision). All eight hop codes are LAND_TILE, so the player walks
## onto one normally, and the hop itself checks neither cell it crosses.
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

## .ledge_table, indexed by a hop code's low three bits. .TryJump checks the high
## nybble alone before masking with 7, so $A8-$AF alias into this table rather
## than being rejected; allows_hop() preserves that, since no pinned tileset uses
## those codes and the source does not special-case them.
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


## .TryJump bit for bit: the high nybble must be HI_NYBBLE_LEDGES and the low
## three must index a .ledge_table entry whose mask includes the press.
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


## Side walls and buoys: home/map.asm's GetMovementPermissions and
## engine/overworld/npc_movement.asm's CanObjectLeaveTile/WillObjectBumpIntoTile.
## These keep their plain permission ($b0-$b7 LAND, $c0-$c7 WATER) and wall off
## one or two of the standing tile's own edges as well.
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

## .MovementPermissionsData, indexed by a wall or buoy code's low three bits:
## which of the standing tile's edges it walls off, in FACE_* terms. Numerically
## identical to LEDGE_FACE_MASK, and two tables in the source as well.
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


## The FACE_* mask of edges [param collision_code] walls off, or 0. .CheckHiNybble
## ANDs against $f0 first, so $b8-$bf and $c8-$cf alias onto the same eight
## entries, the way allows_hop() keeps the $a8-$af ledge alias.
static func side_wall_face_mask(collision_code: int) -> int:
	if collision_code < 0 or collision_code > 0xFF:
		return 0
	var hi_nybble: int = collision_code & 0xF0
	if hi_nybble != HI_NYBBLE_SIDE_WALLS and hi_nybble != HI_NYBBLE_SIDE_BUOYS:
		return 0
	return SIDE_WALL_FACE_MASK[collision_code & 0x07]


## engine/overworld/npc_movement.asm's CanObjectLeaveTile (on [param from_code])
## and WillObjectBumpIntoTile (on [param to_code]). Both index a differently
## bit-packed table, GetSideWallDirectionMask's, keyed by wWalkingDirection
## rather than wFacingDirection, and produce the identical per-code result, so
## the FACE_* table is reused instead of encoding the rule twice. Both games ship
## npc_movement.asm byte identical, hence no profile argument here.
static func side_wall_step_blocked(from_code: int, to_code: int, direction: Vector2i) -> bool:
	var forward_face: int = face_mask_for_direction(direction)
	if forward_face == 0:
		return false
	if (side_wall_face_mask(from_code) & forward_face) != 0:
		return true
	return (side_wall_face_mask(to_code) & face_mask_for_direction(-direction)) != 0


## home/map.asm's GetMovementPermissions: the wTilePermissions byte for a player
## standing on [param standing_code] with its four neighbours already read. The
## leave rule is byte identical between the games; the enter rule is not. The
## pins diverge only in .ok_down/.ok_up/.ok_right/.ok_left, where Crystal ORs the
## matching FACE_* and Gold always sets bit RIGHT, numerically FACE_DOWN, because
## those four were written with wWalkingDirection's transposed bit layout. So
## every enter-rule match blocks DOWN alone on Gold and Silver. No shipped map of
## theirs carries a side-wall code whose low three bits differ from 2
## (COLL_UP_WALL, which no opposite-face test below can match), so the split
## changes no pinned map; it stays because a mod-authored map could reach it.
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


## Forced tiles: DoPlayerMovement.CheckTile, which runs in all three movement
## modes after .GetAction and before .CheckTurning, .TryStep/.TrySurf and
## .CheckWarp. It reads the cell the player already stands on and overwrites
## wWalkingDirection, discarding the press; a match reaches .continue_walk, whose
## .DoStep never consults permissions, so a forced step ignores collision.
const HI_NYBBLE_CURRENT: int = 0x30
const HI_NYBBLE_WALK: int = 0x40
const HI_NYBBLE_WALK_ALT: int = 0x50
const HI_NYBBLE_WARPS: int = 0x70
const COLL_WHIRLPOOL: int = 0x24
const COLL_WHIRLPOOL_2C: int = 0x2C
## home/map_objects.asm's CheckWaterfallTile. The second is marked unused in both
## pins and kept because the source still compares it.
const COLL_WATERFALL: int = 0x33
const COLL_CURRENT_DOWN: int = 0x3B
## CheckHeadbuttTreeTile, the same shape and the same unused second code. Both
## are WALL_TILE | TALK like the two cut-tree codes, so a tree blocks and is
## faced rather than stood on.
const COLL_HEADBUTT_TREE: int = 0x15
const COLL_HEADBUTT_TREE_1D: int = 0x1D
const COLL_DOOR: int = 0x71
const COLL_DOOR_79: int = 0x79
const COLL_STAIRCASE: int = 0x7A
const COLL_CAVE: int = 0x7B
const COLL_PIT: int = 0x60
const COLL_PIT_68: int = 0x68
## CheckDirectionalWarp's four carpets, keyed by the direction the player has to
## walk in to take them. `DoPlayerMovement.CheckWarp` indexes `.EdgeWarps` with
## wWalkingDirection, whose order is down, up, left, right.
const DIRECTIONAL_WARPS: Dictionary = {
	Vector2i.DOWN: 0x70,   # COLL_WARP_CARPET_DOWN
	Vector2i.UP: 0x78,     # COLL_WARP_CARPET_UP
	Vector2i.LEFT: 0x76,   # COLL_WARP_CARPET_LEFT
	Vector2i.RIGHT: 0x7E,  # COLL_WARP_CARPET_RIGHT
}


## CheckDirectionalWarp: a carpet clears carry, so `CheckWarpTile` refuses it and
## the step that lands on one takes no warp. Only `DoPlayerMovement.CheckWarp`
## takes these, and only for the one direction the carpet names.
static func is_directional_warp(collision_code: int) -> bool:
	return DIRECTIONAL_WARPS.values().has(collision_code)


## Which direction [param collision_code] has to be walked in to warp, or
## Vector2i.ZERO when it is not a carpet.
static func directional_warp_direction(collision_code: int) -> Vector2i:
	for direction: Vector2i in DIRECTIONAL_WARPS:
		if int(DIRECTIONAL_WARPS[direction]) == collision_code:
			return direction
	return Vector2i.ZERO


## CheckWarpCollision: the two pit codes or the whole $70 nybble, and nowhere
## else. A warp_event on ordinary floor is inert, which is what lets a player
## walk over Burned Tower B1F's (10,8) instead of being sent upstairs.
static func is_warp_tile(collision_code: int) -> bool:
	if is_pit_tile(collision_code):
		return true
	return (collision_code & 0xF0) == HI_NYBBLE_WARPS


## CheckPitTile, read by is_warp_tile() and by MovementFunction_Strength, which
## stops a boulder standing on one for good.
static func is_pit_tile(collision_code: int) -> bool:
	return collision_code == COLL_PIT or collision_code == COLL_PIT_68

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
## CheckWarpFacingDown, broader than WARP_STEP_CODES because RefreshPlayerSprite
## only chooses a drawing direction with it.
const SPAWN_FACING_DOWN_CODES: Array[int] = [
	COLL_DOOR, COLL_DOOR_79, COLL_STAIRCASE, 0x73, COLL_CAVE, 0x74, 0x7C, 0x75, 0x7D,
]


static func faces_down_on_spawn(collision_code: int) -> bool:
	return SPAWN_FACING_DOWN_CODES.has(collision_code)


## .CheckTile's answer: [code]none[/code], [code]force_turn[/code]
## (CheckWhirlpoolTile matched, so PLAYERMOVEMENT_FORCE_TURN queues
## Script_ForcedMovement) or [code]walk[/code]. Branch order is the source's.
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


## CheckCounterTile (`home/map_objects.asm`). $98 ships in the table but no map
## uses it.
const COLL_COUNTER: int = 0x90
const COLL_COUNTER_98: int = 0x98

const COLL_BOOKSHELF: int = 0x91
const COLL_PC: int = 0x93
const COLL_RADIO: int = 0x94
const COLL_TOWN_MAP: int = 0x95
const COLL_MART_SHELF: int = 0x96
const COLL_TV: int = 0x97
const COLL_WINDOW: int = 0x9D
const COLL_INCENSE_BURNER: int = 0x9F

## engine/events/std_collision.asm's CheckFacingTileForStdScript, dispatched on A
## once object and background events both find nothing.
## data/collision/collision_stdscripts.asm is byte identical between the pins but
## the index each entry resolves to is not: PCScript is 49 in Crystal and 43 in
## Gold and Silver, Crystal's table carrying six extra phone entries earlier.
## Every other entry was recounted in both and lands on the same index.
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


## CheckCounterTile: what CheckFacingObject doubles the facing distance over.
static func is_counter(collision_code: int) -> bool:
	return collision_code in [COLL_COUNTER, COLL_COUNTER_98]


## The std-script index dispatched on A, or -1 outside TileCollisionStdScripts.
static func tile_collision_std_index(collision_code: int, is_crystal: bool) -> int:
	var table: Dictionary = TILE_COLLISION_STD_INDEX_CRYSTAL if is_crystal \
		else TILE_COLLISION_STD_INDEX_GOLD_SILVER
	return int(table.get(collision_code, -1))
