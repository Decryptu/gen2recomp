class_name Gen2WorldFieldMove
extends RefCounted

## Scene-free tables and gates for the overworld field moves
## (engine/events/overworld.asm).
##
## Cut, Surf, Strength and Whirlpool are resolved here. Cut, Surf and Whirlpool
## follow the shape CutFunction defines: check the badge, then check the faced
## tile, then stage a change the text acknowledge commits. Strength is the odd
## one, see BADGE_PLAIN. Waterfall, Flash and Headbutt are not resolved yet.

## constants/move_constants.asm, whose comment column is hex. The submenu, not
## CutFunction, SurfFunction or WhirlpoolFunction, is what checks a party Pokemon
## knows these.
const MOVE_CUT: int = 0x0F
const MOVE_SURF: int = 0x39
const MOVE_STRENGTH: int = 0x46
const MOVE_WHIRLPOOL: int = 0xFA

## CheckBadge's arguments in CutFunction's .CheckAble, SurfFunction's .TrySurf,
## StrengthFunction's .TryStrength and WhirlpoolFunction's .TryWhirlpool, as
## source badge-order indices rather than flag numbers, so
## Gen2WorldState.badge_flag() resolves them on either profile:
## ENGINE_HIVEBADGE is 28 in Crystal and 27 in Gold/Silver, ENGINE_PLAINBADGE
## 29 and 28, ENGINE_FOGBADGE 30 and 29, ENGINE_GLACIERBADGE 33 and 32.
const BADGE_HIVE: int = 1
## .TryStrength is the whole gate: CheckBadge ENGINE_PLAINBADGE and nothing
## else. It checks no tile, no block table and no player state, unlike the other
## three, and its .AlreadyUsingStrength branch is marked unreferenced in both
## pins, so an already-active flag is not a refusal either.
const BADGE_PLAIN: int = 2
const BADGE_FOG: int = 3
const BADGE_GLACIER: int = 6

## GetSurfType's comparison, constants/pokemon_constants.asm.
const SPECIES_PIKACHU: int = 0x19

## constants/music_constants.asm. home/audio.asm's SpecialMapMusic returns this
## ahead of the map header's own music whenever the player state is surfing, so
## it belongs to Surf rather than to any one map. Surf has no sound effect:
## UsedSurfScript never calls PlaySFX.
const MUSIC_SURF: int = 0x21

## The data/mon_menu.asm MonMenuOptions field-move rows this project acts on.
## Both pins ship the same rows, so this needs no profile split. IsFieldMove
## decides submenu membership from this list alone, so a move stops appearing
## the moment it leaves it.
const FIELD_MOVES: Array[int] = [MOVE_CUT, MOVE_SURF, MOVE_STRENGTH, MOVE_WHIRLPOOL]

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


## GetSurfType resolved through ChrisStateSprites: the surfing player's sprite
## for the party member carrying the move. The source keeps the Pikachu variant
## as a separate wPlayerState value; only the sprite differs, so this collapses
## the two lookups into the one number a renderer needs.
static func surf_sprite(species: int) -> int:
	return Gen2WorldSprite.SPRITE_SURFING_PIKACHU if species == SPECIES_PIKACHU \
		else Gen2WorldSprite.SPRITE_SURF


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


## home/map_objects.asm's CheckWhirlpoolTile, which TryWhirlpoolMenu applies to
## the faced tile. Both codes are WATER_TILE | TALK, so the cell is reachable by
## surfing straight onto it; what makes it an obstacle is
## Gen2WorldCollision.forced_action(), not the permission.
const WHIRLPOOL_COLLISIONS: Array[int] = [
	Gen2WorldCollision.COLL_WHIRLPOOL,
	Gen2WorldCollision.COLL_WHIRLPOOL_2C,
]

## data/collision/field_move_blocks.asm's WhirlpoolBlockPointers, byte identical
## between the pins like CutTreeBlockPointers. It names only TILESET_JOHTO, which
## is $01 in both games, so unlike the cut table this needs no profile split.
const WHIRLPOOL_BLOCKS_JOHTO: Dictionary = {
	0x07: [0x36, ANIMATION_TREE],
}


## CheckWhirlpoolTile: whether the faced cell's collision code is one Whirlpool
## acts on. A match still needs a block in the tileset's list.
static func whirlpool_tile(collision_code: int) -> bool:
	return WHIRLPOOL_COLLISIONS.has(collision_code)


## CheckOverworldTileArrays against WhirlpoolBlockPointers, the counterpart of
## cut_replacement(). Both misses, absent tileset and absent block, are the
## source's same "nothing to do" answer.
static func whirlpool_replacement(tileset: int, block: int) -> Dictionary:
	if tileset != TILESET_JOHTO:
		return {"ok": false}
	var row: Variant = WHIRLPOOL_BLOCKS_JOHTO.get(block)
	if row == null:
		return {"ok": false}
	return {"ok": true, "block": int(row[0]), "animation": int(row[1])}
