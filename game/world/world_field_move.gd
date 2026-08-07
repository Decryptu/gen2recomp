class_name Gen2WorldFieldMove
extends RefCounted

## Scene-free tables and gates for the overworld field moves
## (engine/events/overworld.asm).
##
## Only Cut is resolved here so far. The shape each remaining move reuses is the
## one CutFunction defines: check the badge, then check the faced tile, then look
## the standing block up in a per-tileset replacement table.

## constants/move_constants.asm. The submenu, not CutFunction, is what checks a
## party Pokemon knows this.
const MOVE_CUT: int = 15

## CheckBadge's argument in CutFunction's .CheckAble, as a source badge-order
## index rather than a flag number, so Gen2WorldState.badge_flag() resolves it
## on either profile: ENGINE_HIVEBADGE is 28 in Crystal and 27 in Gold/Silver.
const BADGE_HIVE: int = 1

## data/mon_menu.asm's MonMenuOptions field-move rows, in table order. Both pins
## ship the same rows, so this needs no profile split. Cut is the only one this
## project acts on; the rest are listed because IsFieldMove decides submenu
## membership from this table alone, and a move missing from it would silently
## stop appearing when the next one lands.
const FIELD_MOVES: Array[int] = [MOVE_CUT]

## engine/overworld/tile_events.asm's CheckCutCollision, entry for entry. Two of
## the six block ($12, $1a); the four grass codes are LAND_TILE and cuttable
## anyway, which is why membership here is separate from the permission.
const CUTTABLE_COLLISIONS: Array[int] = [
	0x12,  # COLL_CUT_TREE
	0x1A,  # COLL_CUT_TREE_1A
	0x10,  # COLL_TALL_GRASS_10
	0x18,  # COLL_TALL_GRASS
	0x14,  # COLL_LONG_GRASS
	0x1C,  # COLL_LONG_GRASS_1C
]

## OWCutAnimation's index in e: which of the two cut animations the replacement
## plays. Recorded because CheckOverworldTileArrays returns it beside the
## replacement block; this renderer draws neither.
const ANIMATION_TREE: int = 0
const ANIMATION_GRASS: int = 1

## constants/tileset_constants.asm. Numbers 1 to 3 agree between the pins, but
## pokegold has no BATTLE_TOWER_OUTSIDE, POKECOM_CENTER or BATTLE_TOWER_INSIDE,
## so everything above $03 is shifted. PARK and FOREST are the two tilesets in
## the cut table that this reaches.
const TILESET_JOHTO: int = 0x01
const TILESET_JOHTO_MODERN: int = 0x02
const TILESET_KANTO: int = 0x03
const TILESET_PARK_CRYSTAL: int = 0x19
const TILESET_PARK_GOLD_SILVER: int = 0x16
const TILESET_FOREST_CRYSTAL: int = 0x1F
const TILESET_FOREST_GOLD_SILVER: int = 0x1C

## data/collision/field_move_blocks.asm's CutTreeBlockPointers, byte identical
## between the pins: facing block to [replacement block, animation]. Only the
## tileset numbers keying it are profile split, so the lists are shared and
## _cut_tables() picks the keys.
const CUT_BLOCKS_JOHTO: Dictionary = {
	0x03: [0x02, ANIMATION_GRASS],
	0x5B: [0x3C, ANIMATION_TREE],
	0x5F: [0x3D, ANIMATION_TREE],
	0x63: [0x3F, ANIMATION_TREE],
	0x67: [0x3E, ANIMATION_TREE],
}
const CUT_BLOCKS_JOHTO_MODERN: Dictionary = {
	0x03: [0x02, ANIMATION_GRASS],
}
const CUT_BLOCKS_KANTO: Dictionary = {
	0x0B: [0x0A, ANIMATION_GRASS],
	0x32: [0x6D, ANIMATION_TREE],
	0x33: [0x6C, ANIMATION_TREE],
	0x34: [0x6F, ANIMATION_TREE],
	0x35: [0x4C, ANIMATION_TREE],
	0x60: [0x6E, ANIMATION_TREE],
}
const CUT_BLOCKS_PARK: Dictionary = {
	0x13: [0x03, ANIMATION_GRASS],
	0x03: [0x04, ANIMATION_GRASS],
}
const CUT_BLOCKS_FOREST: Dictionary = {
	0x0F: [0x17, ANIMATION_TREE],
}


static func is_field_move(move: int) -> bool:
	return FIELD_MOVES.has(move)


## CheckCutCollision: whether the faced cell's collision code is one Cut acts on
## at all. A match still needs a block in the tileset's list.
static func cuttable(collision_code: int) -> bool:
	return CUTTABLE_COLLISIONS.has(collision_code)


## The tileset-to-block-list mapping for one profile. Kept as a function rather
## than two constants so the shared lists above stay single-sourced.
static func _cut_tables(is_crystal: bool) -> Dictionary:
	return {
		TILESET_JOHTO: CUT_BLOCKS_JOHTO,
		TILESET_JOHTO_MODERN: CUT_BLOCKS_JOHTO_MODERN,
		TILESET_KANTO: CUT_BLOCKS_KANTO,
		TILESET_PARK_CRYSTAL if is_crystal else TILESET_PARK_GOLD_SILVER: CUT_BLOCKS_PARK,
		TILESET_FOREST_CRYSTAL if is_crystal else TILESET_FOREST_GOLD_SILVER: CUT_BLOCKS_FOREST,
	}


## CheckOverworldTileArrays against CutTreeBlockPointers: the replacement for
## [param block] in [param tileset], or a not-ok result when the tileset carries
## no list or the block is not in it. Both misses are the source's same
## "nothing to cut" answer.
static func cut_replacement(tileset: int, block: int, is_crystal: bool) -> Dictionary:
	var blocks: Variant = _cut_tables(is_crystal).get(tileset)
	if blocks == null:
		return {"ok": false}
	var row: Variant = (blocks as Dictionary).get(block)
	if row == null:
		return {"ok": false}
	return {"ok": true, "block": int(row[0]), "animation": int(row[1])}
