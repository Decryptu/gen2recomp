class_name Gen2WorldSprite
extends RefCounted

## One entry from the cartridge's OverworldSprites table plus its decoded
## indexed tile strip. The source uses three sprite types: walking sprites have
## twelve tiles, standing sprites use the same facing layout without movement,
## and still sprites contain one four-tile image.

const TYPE_WALKING: int = 1
const TYPE_STANDING: int = 2
const TYPE_STILL: int = 3

const FACING_DOWN: int = 0
const FACING_UP: int = 1
const FACING_LEFT: int = 2
const FACING_RIGHT: int = 3

## Tiles in one half of a walking or standing sprite's strip: three facings of
## four. It is what `OverworldSprites` records as the whole length, because
## `GetUsedSprite` copies that many twice; see [method frame_tile_offset].
const WALKING_HALF_TILES: int = 12

## data/sprites/player_sprites.asm's ChrisStateSprites and KrisStateSprites, the
## wPlayerState to sprite lookup GetPlayerSprite walks. ChrisStateSprites is
## identical in both pins and the numbers themselves
## (constants/sprite_constants.asm) agree too; pokegold ships no KrisStateSprites
## at all, which is why the female rows are Crystal only.
##
## The two tables differ in their PLAYER_NORMAL and PLAYER_BIKE rows and share
## PLAYER_SURF and PLAYER_SURF_PIKA, so surfing looks the same either way.
const SPRITE_PLAYER: int = 0x01
const SPRITE_PLAYER_BIKE: int = 0x02
const SPRITE_SURFING_PIKACHU: int = 0x34
const SPRITE_SURF: int = 0x53
const SPRITE_KRIS: int = 0x60
const SPRITE_KRIS_BIKE: int = 0x61

## constants/sprite_data_constants.asm. `InitPlayerObject` writes one of these
## onto the player object rather than taking the sprite's own default row, and
## the female branch is the only thing that chooses between them.
const PAL_NPC_RED: int = 8
const PAL_NPC_BLUE: int = 9


## `GetPlayerSprite`'s PLAYER_NORMAL row. The bike rows exist in both tables but
## no bike does, so nothing asks for them yet.
static func player_normal_sprite(female: bool) -> int:
	return SPRITE_KRIS if female else SPRITE_PLAYER


## `InitPlayerObject`'s `ln e, PAL_NPC_RED` and its female branch.
static func player_palette(female: bool) -> int:
	return PAL_NPC_BLUE if female else PAL_NPC_RED

var number: int = 0
var address: int = 0
var bank: int = 0
var bytes: int = 0
var tiles: int = 0
var sprite_type: int = TYPE_STILL
var default_palette: int = 0


static func from_cache(value: Dictionary) -> Gen2WorldSprite:
	var out := Gen2WorldSprite.new()
	out.number = int(value.get("number", 0))
	out.address = int(value.get("address", 0))
	out.bank = int(value.get("bank", 0))
	out.bytes = int(value.get("bytes", 0))
	out.tiles = int(value.get(
		"tiles", floori(float(out.bytes) / float(Gen2Tiles.TILE_BYTES))
	))
	out.sprite_type = int(value.get("type", TYPE_STILL))
	out.default_palette = int(value.get("palette", 0))
	return out


func is_walking() -> bool:
	return sprite_type == TYPE_WALKING


## Returns the first tile of a 4-tile frame in the source strip.
##
## A walking sprite's strip is two halves of twelve tiles: down, up and left
## standing, then the same three walking. `GetUsedSprite`
## (engine/overworld/overworld.asm) copies the first half to `vTiles0` and the
## second to `vTiles1`, which is the `$80` the walking rows of `Facings`
## (data/sprites/facings.asm) add to the object's own base tile.
##
## `Facings` gives each direction four frames: 0 and 2 are the standing drawing,
## 1 and 3 the walking one. Right reuses left, flipped by the renderer, and so
## does frame 3 of down and up: `FacingStepDown3` is `FacingStepDown1` with
## `OAM_XFLIP` on every tile and its two columns swapped.
func frame_tile_offset(facing: int, frame: int) -> int:
	if tiles <= 4 or sprite_type == TYPE_STILL:
		return 0
	var facing_index: int = clampi(facing, FACING_DOWN, FACING_RIGHT)
	if facing_index == FACING_RIGHT:
		facing_index = FACING_LEFT
	var offset: int = facing_index * 4
	if is_walking_frame(frame) and tiles >= WALKING_HALF_TILES * 2:
		offset += WALKING_HALF_TILES
	return offset


## Whether [param frame] is one of the two walking drawings rather than one of
## the two standing ones.
static func is_walking_frame(frame: int) -> bool:
	return (clampi(frame, 0, 3) & 1) == 1


## Whether the whole 16x16 image is mirrored: right always is, since it reuses
## left, and so is frame 3 of down and up.
static func frame_is_mirrored(facing: int, frame: int) -> bool:
	if facing == FACING_RIGHT:
		return true
	return clampi(frame, 0, 3) == 3 and facing in [FACING_DOWN, FACING_UP]


## Composes one 16x16 object image from the source's horizontal tile strip.
## Colour index zero is transparent under the Game Boy object-palette rules.
static func image_for(
	sprite: Gen2WorldSprite,
	indices: PackedByteArray,
	palette: PackedColorArray,
	facing: int = FACING_DOWN,
	frame: int = 0,
) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if sprite == null or sprite.tiles < 4:
		return image
	var width: int = sprite.tiles * Gen2Tiles.TILE_WIDTH
	var source_tile: int = sprite.frame_tile_offset(facing, frame)
	if source_tile < 0 or source_tile + 4 > sprite.tiles or indices.size() < width * 8:
		return image

	for tile: int in 4:
		var source_x: int = (source_tile + tile) * Gen2Tiles.TILE_WIDTH
		var destination_x: int = (tile & 1) * Gen2Tiles.TILE_WIDTH
		var destination_y: int = (tile >> 1) * Gen2Tiles.TILE_HEIGHT
		for y: int in Gen2Tiles.TILE_HEIGHT:
			for x: int in Gen2Tiles.TILE_WIDTH:
				var color_index: int = int(indices[y * width + source_x + x])
				var color := Color.MAGENTA
				if color_index < palette.size():
					color = palette[color_index]
				if color_index == 0:
					color.a = 0.0
				image.set_pixel(destination_x + x, destination_y + y, color)

	if frame_is_mirrored(facing, frame):
		image.flip_x()
	return image
