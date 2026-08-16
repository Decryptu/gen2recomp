class_name Gen2WorldFieldMove
extends RefCounted

## Scene-free tables and gates for the overworld field moves
## (engine/events/overworld.asm).
##
## Cut, Surf and Whirlpool follow CutFunction's shape: badge, faced tile, then a
## change the text acknowledge commits. Strength is the odd one (BADGE_PLAIN),
## Flash checks the map rather than a tile ([method Gen2WorldPalette.is_dark]),
## and Headbutt checks a tile and no badge, its roll being [Gen2WorldTreemon]'s.

## constants/move_constants.asm, whose comment column is hex. The submenu, not
## the functions, is what checks a party Pokemon knows these.
const MOVE_CUT: int = 0x0F
const MOVE_SURF: int = 0x39
const MOVE_STRENGTH: int = 0x46
const MOVE_WHIRLPOOL: int = 0xFA
const MOVE_WATERFALL: int = 0x7F
const MOVE_FLASH: int = 0x94
const MOVE_HEADBUTT: int = 0x1D
const MOVE_ROCK_SMASH: int = 0xF9
## The escape rows: Fly picks a spawn off the region map, Teleport takes the last
## Pokemon Center's and Dig the warp the player came in through.
const MOVE_FLY: int = 0x13
const MOVE_DIG: int = 0x5B
const MOVE_TELEPORT: int = 0x64
## Neither a tile nor an escape: a wild encounter out of the map underfoot.
const MOVE_SWEET_SCENT: int = 0xE6
## `MonMenu_Softboiled_MilkDrink`, one routine for both: health between party
## members, no map.
const MOVE_SOFTBOILED: int = 0x87
const MOVE_MILK_DRINK: int = 0xD0

## Each function's own CheckBadge argument, as badge-order indices rather than
## flag numbers: ENGINE_HIVEBADGE is 28 in Crystal and 27 in Gold and Silver, and
## every badge past it splits the same way, so Gen2WorldState.badge_flag()
## resolves them.
const BADGE_HIVE: int = 1
## .TryStrength is the whole gate: no tile, no block table, no player state, and
## its .AlreadyUsingStrength branch is unreferenced in both pins.
const BADGE_PLAIN: int = 2
const BADGE_FOG: int = 3
const BADGE_GLACIER: int = 6
## `.TryFly`'s own `CheckBadge ENGINE_STORMBADGE`, the sixth badge.
const BADGE_STORM: int = 5
## WaterfallFunction's .TryWaterfall: ENGINE_RISINGBADGE.
const BADGE_RISING: int = 7
## FlashFunction's .CheckUseFlash: ENGINE_ZEPHYRBADGE, the least of the eight.
const BADGE_ZEPHYR: int = 0

## GetSurfType's comparison, constants/pokemon_constants.asm.
const SPECIES_PIKACHU: int = 0x19

## `SpecialMapMusic` returns this ahead of the map header's while the player is
## surfing, so it belongs to Surf. `UsedSurfScript` calls no PlaySFX.
const MUSIC_SURF: int = 0x21
## `BikeFunction` writes this to `wMapMusic`, so it survives a map load.
const MUSIC_BICYCLE: int = 0x13

## Which badge each gated field move asks `CheckBadge` for, as the badge-order
## index the constants above are. A move that is not here has no badge gate:
## Headbutt, Rock Smash, Dig, Teleport, Sweet Scent and the two heals.
const MOVE_BADGES: Dictionary = {
	MOVE_CUT: BADGE_HIVE,
	MOVE_SURF: BADGE_FOG,
	MOVE_STRENGTH: BADGE_PLAIN,
	MOVE_WHIRLPOOL: BADGE_GLACIER,
	MOVE_WATERFALL: BADGE_RISING,
	MOVE_FLASH: BADGE_ZEPHYR,
	MOVE_FLY: BADGE_STORM,
}


## The badge [param move] needs before the overworld will run it, or -1. The one
## fact a placement has to respect: an HM in the bag is not a way past anything
## until its badge is in hand.
static func badge_for_move(move: int) -> int:
	return int(MOVE_BADGES.get(move, -1))


## data/mon_menu.asm's MonMenuOptions rows, identical between the pins and the
## whole of IsFieldMove's submenu membership.
const FIELD_MOVES: Array[int] = [
	MOVE_CUT, MOVE_SURF, MOVE_STRENGTH, MOVE_WHIRLPOOL, MOVE_WATERFALL, MOVE_FLASH,
	MOVE_HEADBUTT, MOVE_ROCK_SMASH, MOVE_DIG, MOVE_TELEPORT, MOVE_SWEET_SCENT,
	MOVE_FLY, MOVE_SOFTBOILED, MOVE_MILK_DRINK,
]

## engine/overworld/tile_events.asm's CheckCutCollision, entry for entry: the
## four grass codes are LAND_TILE and cuttable, so this is not the permission.
const CUTTABLE_COLLISIONS: Array[int] = [
	0x12,  # COLL_CUT_TREE
	0x1A,  # COLL_CUT_TREE_1A
	0x10,  # COLL_TALL_GRASS_10
	0x18,  # COLL_TALL_GRASS
	0x14,  # COLL_LONG_GRASS
	0x1C,  # COLL_LONG_GRASS_1C
]

## OWCutAnimation's index in e, returned beside the replacement block by
## CheckOverworldTileArrays. This renderer draws neither.
const ANIMATION_TREE: int = 0
const ANIMATION_GRASS: int = 1

## constants/tileset_constants.asm: 1 to 3 agree, and pokegold ships three fewer
## tilesets after them, so PARK and FOREST shift.
const TILESET_JOHTO: int = 0x01
const TILESET_JOHTO_MODERN: int = 0x02
const TILESET_KANTO: int = 0x03
const TILESET_PARK_CRYSTAL: int = 0x19
const TILESET_PARK_GOLD_SILVER: int = 0x16
const TILESET_FOREST_CRYSTAL: int = 0x1F
const TILESET_FOREST_GOLD_SILVER: int = 0x1C

## data/collision/field_move_blocks.asm's CutTreeBlockPointers, byte identical
## between the pins: facing block to [replacement block, animation]. Only its
## tileset keys are profile split, which is what _cut_tables() picks.
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


## GetSurfType through ChrisStateSprites. The source keeps the Pikachu variant
## as its own wPlayerState value and only the sprite differs, so the two lookups
## collapse into the one number a renderer needs.
static func surf_sprite(species: int) -> int:
	return Gen2WorldSprite.SPRITE_SURFING_PIKACHU if species == SPECIES_PIKACHU \
		else Gen2WorldSprite.SPRITE_SURF


static func cuttable(collision_code: int) -> bool:
	return CUTTABLE_COLLISIONS.has(collision_code)


## CheckCutTreeTile, the two tree codes alone. TryTileCollisionEvent's `.cut`
## reads this rather than CheckCutCollision, so an A press at tall grass offers
## nothing while the submenu's CUT still cuts it.
const CUT_TREE_COLLISIONS: Array[int] = [0x12, 0x1A]


static func cut_tree_tile(collision_code: int) -> bool:
	return CUT_TREE_COLLISIONS.has(collision_code)


## A function rather than two constants, so the lists above stay single-sourced.
static func _cut_tables(is_crystal: bool) -> Dictionary:
	return {
		TILESET_JOHTO: CUT_BLOCKS_JOHTO,
		TILESET_JOHTO_MODERN: CUT_BLOCKS_JOHTO_MODERN,
		TILESET_KANTO: CUT_BLOCKS_KANTO,
		TILESET_PARK_CRYSTAL if is_crystal else TILESET_PARK_GOLD_SILVER: CUT_BLOCKS_PARK,
		TILESET_FOREST_CRYSTAL if is_crystal else TILESET_FOREST_GOLD_SILVER: CUT_BLOCKS_FOREST,
	}


## CheckOverworldTileArrays against CutTreeBlockPointers; an absent tileset and
## an absent block are the same "nothing to cut".
static func cut_replacement(tileset: int, block: int, is_crystal: bool) -> Dictionary:
	var blocks: Variant = _cut_tables(is_crystal).get(tileset)
	if blocks == null:
		return {"ok": false}
	var row: Variant = (blocks as Dictionary).get(block)
	if row == null:
		return {"ok": false}
	return {"ok": true, "block": int(row[0]), "animation": int(row[1])}


## home/map_objects.asm's CheckWhirlpoolTile. Both codes are WATER_TILE | TALK,
## so the cell can be surfed onto: what makes it an obstacle is
## Gen2WorldCollision.forced_action(), not the permission.
const WHIRLPOOL_COLLISIONS: Array[int] = [
	Gen2WorldCollision.COLL_WHIRLPOOL,
	Gen2WorldCollision.COLL_WHIRLPOOL_2C,
]

## WhirlpoolBlockPointers, which names only TILESET_JOHTO, $01 in both games, so
## unlike the cut table it needs no profile split.
const WHIRLPOOL_BLOCKS_JOHTO: Dictionary = {
	0x07: [0x36, ANIMATION_TREE],
}


static func whirlpool_tile(collision_code: int) -> bool:
	return WHIRLPOOL_COLLISIONS.has(collision_code)


## CheckOverworldTileArrays against WhirlpoolBlockPointers, cut_replacement()'s
## counterpart down to both misses answering the same way.
static func whirlpool_replacement(tileset: int, block: int) -> Dictionary:
	if tileset != TILESET_JOHTO:
		return {"ok": false}
	var row: Variant = WHIRLPOOL_BLOCKS_JOHTO.get(block)
	if row == null:
		return {"ok": false}
	return {"ok": true, "block": int(row[0]), "animation": int(row[1])}


## home/map_objects.asm's CheckWaterfallTile, on wTileUp. COLL_CURRENT_DOWN is
## unused in both pins and kept because the source compares both.
const WATERFALL_COLLISIONS: Array[int] = [
	Gen2WorldCollision.COLL_WATERFALL,
	Gen2WorldCollision.COLL_CURRENT_DOWN,
]


## No block table: Waterfall moves the player and changes nothing.
static func waterfall_tile(collision_code: int) -> bool:
	return WATERFALL_COLLISIONS.has(collision_code)


## home/map_objects.asm's CheckHeadbuttTreeTile, read by TryHeadbuttFromMenu and
## by the overworld A press.
const HEADBUTT_COLLISIONS: Array[int] = [
	Gen2WorldCollision.COLL_HEADBUTT_TREE,
	Gen2WorldCollision.COLL_HEADBUTT_TREE_1D,
]


## No block table either: ShakeHeadbuttTree is an animation and the tree stands.
static func headbutt_tile(collision_code: int) -> bool:
	return HEADBUTT_COLLISIONS.has(collision_code)
