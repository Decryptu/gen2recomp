class_name Gen2GoldSilverIntroPage
extends RefCounted

## `GoldSilverIntro`'s screen, on the tile grid the hardware uses.
##
## [Gen2GoldSilverIntro] owns the BG map, the palettes, the scroll and the
## sprite structs; this turns a tile number into pixels. The split is
## [Gen2IntroMoviePage]'s, with two differences that come from the movie itself:
##
## - The BG map is 32 tiles wide and wraps, and `hLCDCPointer` = LOW(rSCY) gives
##   every scanline its own `hSCY` rather than its own `hSCX`, so the screen is
##   sampled row by row through [method Gen2GoldSilverIntro.scroll_y_at].
## - Every attribute byte is zero, so there is one background palette rather
##   than eight: `IntroScene1` blanks the VRAM bank 1 map and each
##   `_CGB_GSIntro` scene ends in `WipeAttrmap`.
##
## The starters are the one thing not read out of the intro's own sheets.
## `Intro_GetMonFrontpic` decompresses three front pics into `vTiles0` over the
## fire sheet already there, so their OAM sets index the pic atlas the cache
## holds instead, column-major the way a `--columns` pic is stored.

const TILE: int = Gen2Tiles.TILE_WIDTH
const WIDTH: int = Gen2Screen.WIDTH
const HEIGHT: int = Gen2Screen.HEIGHT
const MAP_COLUMNS: int = Gen2GoldSilverIntro.MAP_COLUMNS
const MAP_ROWS: int = Gen2GoldSilverIntro.MAP_ROWS

## Shadow OAM counts from (8, 16).
const OAM_ORIGIN := Vector2i(8, 16)
## A sprite never draws its first colour.
const TRANSPARENT_INDEX: int = 0
## Where a BG tile number stops reading `vTiles2` and starts reading `vTiles1`,
## which only the fire cutscene loads a second sheet into.
const HIGH_TILE: int = 0x80

## `wShadowOAM`, which is forty `SPRITEOAMSTRUCT`s and no more.
const SHADOW_OAM_SPRITES: int = 40

## `dbsprite`'s attribute byte.
const ATTR_PALETTE: int = 0x07
const ATTR_XFLIP: int = 0x20
const ATTR_YFLIP: int = 0x40

## Which sheet each cutscene puts where: `bg` is what a tile below $80 reads,
## `bg_high` what one $80 and up reads, and `obj` what a sprite reads.
const CUTSCENE_SHEETS: Dictionary = {
	&"water": {"bg": "water1", "obj": "water2"},
	&"grass": {"bg": "grass1", "obj": "grass2"},
	&"fire": {"bg": "fire1", "bg_high": "fire2", "obj": "fire3"},
}

## `Intro_GetMonFrontpic`'s three, as the vtile each is decompressed to and the
## species whose atlas cell holds it. A sprite tile in one of those runs is read
## from the pic rather than from `fire3`.
const STARTER_PICS: Array[Dictionary] = [
	{"vtile": 0x10, "species": 152}, {"vtile": 0x29, "species": 155},
	{"vtile": 0x42, "species": 158},
]
## `.OAMData_GSIntroStarter` is twenty-five sprites of a five-by-five pic, and a
## pic is stored column-major, so tile n is column n / 5 and row n % 5.
const STARTER_TILES: int = 5

const OAM_SETS: Array[Dictionary] = [
	# 0: BUBBLE_1 (1x1_Palette0, 1)
	{"vtile": 0x4C, "parts": [[-4, -4, 0x00, 0x00]]},
	# 1: BUBBLE_2 (1x1_Palette0, 1)
	{"vtile": 0x5C, "parts": [[-4, -4, 0x00, 0x00]]},
	# 2: SHELLDER_1 (GSIntroShellder, 4)
	{"vtile": 0x6C, "parts": [
		[-8, -8, 0x00, 0x00], [-8, 0, 0x01, 0x00], [0, -8, 0x10, 0x00],
		[0, 0, 0x11, 0x00],
	]},
	# 3: SHELLDER_2 (GSIntroShellder, 4)
	{"vtile": 0x6E, "parts": [
		[-8, -8, 0x00, 0x00], [-8, 0, 0x01, 0x00], [0, -8, 0x10, 0x00],
		[0, 0, 0x11, 0x00],
	]},
	# 4: MAGIKARP_1 (GSIntroMagikarp, 6)
	{"vtile": 0x2D, "parts": [
		[-8, -12, 0x00, 0x01], [-8, -4, 0x01, 0x01], [-8, 4, 0x02, 0x01],
		[0, -12, 0x10, 0x01], [0, -4, 0x11, 0x01], [0, 4, 0x12, 0x01],
	]},
	# 5: MAGIKARP_2 (GSIntroMagikarp, 6)
	{"vtile": 0x4D, "parts": [
		[-8, -12, 0x00, 0x01], [-8, -4, 0x01, 0x01], [-8, 4, 0x02, 0x01],
		[0, -12, 0x10, 0x01], [0, -4, 0x11, 0x01], [0, 4, 0x12, 0x01],
	]},
	# 6: LAPRAS_1 (GSIntroLapras1, 27)
	{"vtile": 0x00, "parts": [
		[-24, -24, 0x00, 0x00], [-24, -16, 0x01, 0x00], [-24, -8, 0x02, 0x00],
		[-16, -24, 0x10, 0x00], [-16, -16, 0x11, 0x00], [-16, -8, 0x12, 0x00],
		[-8, -24, 0x20, 0x00], [-8, -16, 0x21, 0x00], [-8, -8, 0x22, 0x00],
		[-8, 0, 0x23, 0x00], [0, -24, 0x30, 0x80], [0, -16, 0x31, 0x80],
		[0, -8, 0x32, 0x80], [0, 0, 0x33, 0x80], [0, 8, 0x34, 0x80],
		[8, -24, 0x40, 0x80], [8, -16, 0x41, 0x80], [8, -8, 0x42, 0x80],
		[8, 0, 0x43, 0x80], [8, 8, 0x44, 0x80], [8, 16, 0x45, 0x80],
		[16, -24, 0x50, 0x80], [16, -16, 0x51, 0x80], [16, -8, 0x52, 0x80],
		[16, 0, 0x53, 0x80], [16, 8, 0x54, 0x80], [16, 16, 0x55, 0x80],
	]},
	# 7: LAPRAS_2 (GSIntroLapras2, 27)
	{"vtile": 0x00, "parts": [
		[-24, -24, 0x0D, 0x00], [-24, -16, 0x0E, 0x00], [-24, -8, 0x0F, 0x00],
		[-16, -24, 0x1D, 0x00], [-16, -16, 0x1E, 0x00], [-16, -8, 0x1F, 0x00],
		[-8, -24, 0x20, 0x00], [-8, -16, 0x21, 0x00], [-8, -8, 0x22, 0x00],
		[-8, 0, 0x23, 0x00], [0, -24, 0x30, 0x80], [0, -16, 0x31, 0x80],
		[0, -8, 0x32, 0x80], [0, 0, 0x33, 0x80], [0, 8, 0x34, 0x80],
		[8, -24, 0x40, 0x80], [8, -16, 0x41, 0x80], [8, -8, 0x42, 0x80],
		[8, 0, 0x43, 0x80], [8, 8, 0x44, 0x80], [8, 16, 0x45, 0x80],
		[16, -24, 0x50, 0x80], [16, -16, 0x51, 0x80], [16, -8, 0x52, 0x80],
		[16, 0, 0x53, 0x80], [16, 8, 0x54, 0x80], [16, 16, 0x55, 0x80],
	]},
	# 8: LAPRAS_3 (GSIntroLapras3, 29)
	{"vtile": 0x06, "parts": [
		[-24, -24, 0x00, 0x00], [-24, -16, 0x01, 0x00], [-24, -8, 0x02, 0x00],
		[-24, 0, 0x03, 0x00], [-16, -24, 0x10, 0x00], [-16, -16, 0x11, 0x00],
		[-16, -8, 0x12, 0x00], [-16, 0, 0x13, 0x00], [-8, -24, 0x20, 0x00],
		[-8, -16, 0x21, 0x00], [-8, -8, 0x22, 0x00], [-8, 0, 0x23, 0x00],
		[-8, 8, 0x24, 0x00], [0, -24, 0x30, 0x80], [0, -16, 0x31, 0x80],
		[0, -8, 0x32, 0x80], [0, 0, 0x33, 0x80], [0, 8, 0x34, 0x80],
		[8, -24, 0x40, 0x80], [8, -16, 0x41, 0x80], [8, -8, 0x42, 0x80],
		[8, 0, 0x43, 0x80], [8, 8, 0x44, 0x80], [8, 16, 0x45, 0x80],
		[16, -16, 0x51, 0x80], [16, -8, 0x52, 0x80], [16, 0, 0x53, 0x80],
		[16, 8, 0x54, 0x80], [16, 16, 0x55, 0x80],
	]},
	# 9: NOTE (GSIntroNote, 2)
	{"vtile": 0x0C, "parts": [[-8, -4, 0x00, 0x00], [0, -4, 0x10, 0x00]]},
	# 10: INVISIBLE_NOTE (1x1_Palette0, 1)
	{"vtile": 0x0D, "parts": [[-4, -4, 0x00, 0x00]]},
	# 11: JIGGLYPUFF_1 (GSIntroJigglypuffPikachu, 16)
	{"vtile": 0x00, "parts": [
		[-16, -16, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-16, 0, 0x02, 0x00],
		[-16, 8, 0x03, 0x00], [-8, -16, 0x10, 0x00], [-8, -8, 0x11, 0x00],
		[-8, 0, 0x12, 0x00], [-8, 8, 0x13, 0x00], [0, -16, 0x20, 0x00],
		[0, -8, 0x21, 0x00], [0, 0, 0x22, 0x00], [0, 8, 0x23, 0x00],
		[8, -16, 0x30, 0x00], [8, -8, 0x31, 0x00], [8, 0, 0x32, 0x00],
		[8, 8, 0x33, 0x00],
	]},
	# 12: JIGGLYPUFF_2 (GSIntroJigglypuffPikachu, 16)
	{"vtile": 0x04, "parts": [
		[-16, -16, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-16, 0, 0x02, 0x00],
		[-16, 8, 0x03, 0x00], [-8, -16, 0x10, 0x00], [-8, -8, 0x11, 0x00],
		[-8, 0, 0x12, 0x00], [-8, 8, 0x13, 0x00], [0, -16, 0x20, 0x00],
		[0, -8, 0x21, 0x00], [0, 0, 0x22, 0x00], [0, 8, 0x23, 0x00],
		[8, -16, 0x30, 0x00], [8, -8, 0x31, 0x00], [8, 0, 0x32, 0x00],
		[8, 8, 0x33, 0x00],
	]},
	# 13: JIGGLYPUFF_3 (GSIntroJigglypuffPikachu, 16)
	{"vtile": 0x08, "parts": [
		[-16, -16, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-16, 0, 0x02, 0x00],
		[-16, 8, 0x03, 0x00], [-8, -16, 0x10, 0x00], [-8, -8, 0x11, 0x00],
		[-8, 0, 0x12, 0x00], [-8, 8, 0x13, 0x00], [0, -16, 0x20, 0x00],
		[0, -8, 0x21, 0x00], [0, 0, 0x22, 0x00], [0, 8, 0x23, 0x00],
		[8, -16, 0x30, 0x00], [8, -8, 0x31, 0x00], [8, 0, 0x32, 0x00],
		[8, 8, 0x33, 0x00],
	]},
	# 14: PIKACHU_1 (GSIntroJigglypuffPikachu, 16)
	{"vtile": 0x40, "parts": [
		[-16, -16, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-16, 0, 0x02, 0x00],
		[-16, 8, 0x03, 0x00], [-8, -16, 0x10, 0x00], [-8, -8, 0x11, 0x00],
		[-8, 0, 0x12, 0x00], [-8, 8, 0x13, 0x00], [0, -16, 0x20, 0x00],
		[0, -8, 0x21, 0x00], [0, 0, 0x22, 0x00], [0, 8, 0x23, 0x00],
		[8, -16, 0x30, 0x00], [8, -8, 0x31, 0x00], [8, 0, 0x32, 0x00],
		[8, 8, 0x33, 0x00],
	]},
	# 15: PIKACHU_2 (GSIntroJigglypuffPikachu, 16)
	{"vtile": 0x44, "parts": [
		[-16, -16, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-16, 0, 0x02, 0x00],
		[-16, 8, 0x03, 0x00], [-8, -16, 0x10, 0x00], [-8, -8, 0x11, 0x00],
		[-8, 0, 0x12, 0x00], [-8, 8, 0x13, 0x00], [0, -16, 0x20, 0x00],
		[0, -8, 0x21, 0x00], [0, 0, 0x22, 0x00], [0, 8, 0x23, 0x00],
		[8, -16, 0x30, 0x00], [8, -8, 0x31, 0x00], [8, 0, 0x32, 0x00],
		[8, 8, 0x33, 0x00],
	]},
	# 16: PIKACHU_3 (GSIntroJigglypuffPikachu, 16)
	{"vtile": 0x48, "parts": [
		[-16, -16, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-16, 0, 0x02, 0x00],
		[-16, 8, 0x03, 0x00], [-8, -16, 0x10, 0x00], [-8, -8, 0x11, 0x00],
		[-8, 0, 0x12, 0x00], [-8, 8, 0x13, 0x00], [0, -16, 0x20, 0x00],
		[0, -8, 0x21, 0x00], [0, 0, 0x22, 0x00], [0, 8, 0x23, 0x00],
		[8, -16, 0x30, 0x00], [8, -8, 0x31, 0x00], [8, 0, 0x32, 0x00],
		[8, 8, 0x33, 0x00],
	]},
	# 17: PIKACHU_4 (GSIntroJigglypuffPikachu, 16)
	{"vtile": 0x4C, "parts": [
		[-16, -16, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-16, 0, 0x02, 0x00],
		[-16, 8, 0x03, 0x00], [-8, -16, 0x10, 0x00], [-8, -8, 0x11, 0x00],
		[-8, 0, 0x12, 0x00], [-8, 8, 0x13, 0x00], [0, -16, 0x20, 0x00],
		[0, -8, 0x21, 0x00], [0, 0, 0x22, 0x00], [0, 8, 0x23, 0x00],
		[8, -16, 0x30, 0x00], [8, -8, 0x31, 0x00], [8, 0, 0x32, 0x00],
		[8, 8, 0x33, 0x00],
	]},
	# 18: PIKACHU_TAIL_1 (GSIntroPikachuTail, 5)
	{"vtile": 0x80, "parts": [
		[-16, 24, 0x00, 0x00], [-16, 32, 0x01, 0x00], [-8, 16, 0x02, 0x00],
		[-8, 24, 0x03, 0x00], [0, 16, 0x04, 0x00],
	]},
	# 19: PIKACHU_TAIL_2 (GSIntroPikachuTail, 5)
	{"vtile": 0x85, "parts": [
		[-16, 24, 0x00, 0x00], [-16, 32, 0x01, 0x00], [-8, 16, 0x02, 0x00],
		[-8, 24, 0x03, 0x00], [0, 16, 0x04, 0x00],
	]},
	# 20: PIKACHU_TAIL_3 (GSIntroPikachuTail, 5)
	{"vtile": 0x8A, "parts": [
		[-16, 24, 0x00, 0x00], [-16, 32, 0x01, 0x00], [-8, 16, 0x02, 0x00],
		[-8, 24, 0x03, 0x00], [0, 16, 0x04, 0x00],
	]},
	# 21: SMALL_FIREBALL (GSIntroSmallFireball, 4)
	{"vtile": 0x00, "parts": [
		[-8, -8, 0x00, 0x00], [-8, 0, 0x00, 0x20], [0, -8, 0x00, 0x40],
		[0, 0, 0x00, 0x60],
	]},
	# 22: MED_FIREBALL (TradePoofBubble, 16)
	{"vtile": 0x01, "parts": [
		[-16, -16, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-8, -16, 0x02, 0x00],
		[-8, -8, 0x03, 0x00], [-16, 0, 0x01, 0x20], [-16, 8, 0x00, 0x20],
		[-8, 0, 0x03, 0x20], [-8, 8, 0x02, 0x20], [0, -16, 0x02, 0x40],
		[0, -8, 0x03, 0x40], [8, -16, 0x00, 0x40], [8, -8, 0x01, 0x40],
		[0, 0, 0x03, 0x60], [0, 8, 0x02, 0x60], [8, 0, 0x01, 0x60], [8, 8, 0x00, 0x60],
	]},
	# 23: BIG_FIREBALL (GSIntroBigFireball, 36)
	{"vtile": 0x09, "parts": [
		[-24, -24, 0x00, 0x00], [-24, -16, 0x01, 0x00], [-24, -8, 0x02, 0x00],
		[-16, -24, 0x03, 0x00], [-16, -16, 0x04, 0x00], [-16, -8, 0x05, 0x00],
		[-8, -24, 0x06, 0x00], [-8, -16, 0x05, 0x00], [-8, -8, 0x05, 0x00],
		[-24, 0, 0x02, 0x20], [-24, 8, 0x01, 0x20], [-24, 16, 0x00, 0x20],
		[-16, 0, 0x05, 0x20], [-16, 8, 0x04, 0x20], [-16, 16, 0x03, 0x20],
		[-8, 0, 0x05, 0x20], [-8, 8, 0x05, 0x20], [-8, 16, 0x06, 0x20],
		[0, -24, 0x06, 0x40], [0, -16, 0x05, 0x40], [0, -8, 0x05, 0x40],
		[8, -24, 0x03, 0x40], [8, -16, 0x04, 0x40], [8, -8, 0x05, 0x40],
		[16, -24, 0x00, 0x40], [16, -16, 0x01, 0x40], [16, -8, 0x02, 0x40],
		[0, 0, 0x05, 0x60], [0, 8, 0x05, 0x60], [0, 16, 0x06, 0x60], [8, 0, 0x05, 0x60],
		[8, 8, 0x04, 0x60], [8, 16, 0x03, 0x60], [16, 0, 0x02, 0x60],
		[16, 8, 0x01, 0x60], [16, 16, 0x00, 0x60],
	]},
	# 24: CHIKORITA (GSIntroStarter, 25)
	{"vtile": 0x10, "parts": [
		[-20, -20, 0x00, 0x00], [-12, -20, 0x01, 0x00], [-4, -20, 0x02, 0x00],
		[4, -20, 0x03, 0x00], [12, -20, 0x04, 0x00], [-20, -12, 0x05, 0x00],
		[-12, -12, 0x06, 0x00], [-4, -12, 0x07, 0x00], [4, -12, 0x08, 0x00],
		[12, -12, 0x09, 0x00], [-20, -4, 0x0A, 0x00], [-12, -4, 0x0B, 0x00],
		[-4, -4, 0x0C, 0x00], [4, -4, 0x0D, 0x00], [12, -4, 0x0E, 0x00],
		[-20, 4, 0x0F, 0x00], [-12, 4, 0x10, 0x00], [-4, 4, 0x11, 0x00],
		[4, 4, 0x12, 0x00], [12, 4, 0x13, 0x00], [-20, 12, 0x14, 0x00],
		[-12, 12, 0x15, 0x00], [-4, 12, 0x16, 0x00], [4, 12, 0x17, 0x00],
		[12, 12, 0x18, 0x00],
	]},
	# 25: CYNDAQUIL (GSIntroStarter, 25)
	{"vtile": 0x29, "parts": [
		[-20, -20, 0x00, 0x00], [-12, -20, 0x01, 0x00], [-4, -20, 0x02, 0x00],
		[4, -20, 0x03, 0x00], [12, -20, 0x04, 0x00], [-20, -12, 0x05, 0x00],
		[-12, -12, 0x06, 0x00], [-4, -12, 0x07, 0x00], [4, -12, 0x08, 0x00],
		[12, -12, 0x09, 0x00], [-20, -4, 0x0A, 0x00], [-12, -4, 0x0B, 0x00],
		[-4, -4, 0x0C, 0x00], [4, -4, 0x0D, 0x00], [12, -4, 0x0E, 0x00],
		[-20, 4, 0x0F, 0x00], [-12, 4, 0x10, 0x00], [-4, 4, 0x11, 0x00],
		[4, 4, 0x12, 0x00], [12, 4, 0x13, 0x00], [-20, 12, 0x14, 0x00],
		[-12, 12, 0x15, 0x00], [-4, 12, 0x16, 0x00], [4, 12, 0x17, 0x00],
		[12, 12, 0x18, 0x00],
	]},
	# 26: TOTODILE (GSIntroStarter, 25)
	{"vtile": 0x42, "parts": [
		[-20, -20, 0x00, 0x00], [-12, -20, 0x01, 0x00], [-4, -20, 0x02, 0x00],
		[4, -20, 0x03, 0x00], [12, -20, 0x04, 0x00], [-20, -12, 0x05, 0x00],
		[-12, -12, 0x06, 0x00], [-4, -12, 0x07, 0x00], [4, -12, 0x08, 0x00],
		[12, -12, 0x09, 0x00], [-20, -4, 0x0A, 0x00], [-12, -4, 0x0B, 0x00],
		[-4, -4, 0x0C, 0x00], [4, -4, 0x0D, 0x00], [12, -4, 0x0E, 0x00],
		[-20, 4, 0x0F, 0x00], [-12, 4, 0x10, 0x00], [-4, 4, 0x11, 0x00],
		[4, 4, 0x12, 0x00], [12, 4, 0x13, 0x00], [-20, 12, 0x14, 0x00],
		[-12, 12, 0x15, 0x00], [-4, 12, 0x16, 0x00], [4, 12, 0x17, 0x00],
		[12, 12, 0x18, 0x00],
	]},
]


var _data: GameData = null
## One tile-index strip per sheet name, read once.
var _sheets: Dictionary = {}


## Null on a cache without the movie's art, which is the caller's cue to skip
## the phase rather than to run it blank.
static func from_data(data: GameData) -> Gen2GoldSilverIntroPage:
	if data == null or not data.has_gs_intro():
		return null
	var out := Gen2GoldSilverIntroPage.new()
	out._data = data
	return out


## The whole 160x144 screen for one frame of [param movie].
func draw(movie: Gen2GoldSilverIntro) -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	if movie == null:
		return image
	_draw_background(image, movie)
	for entry: Dictionary in shadow_oam(movie):
		_draw_sprite(image, movie, entry)
	return image


## Every live struct expanded into the shadow OAM the hardware would hold, in
## struct order, which is the z-order `PlaySpriteAnimations` walks. `y` and `x`
## are the OAM bytes and `tile` the byte `dbsprite` writes. [method draw] blits
## this same list rather than re-deriving it, so a trace of it compares to a
## cartridge's own buffer line for line.
func shadow_oam(movie: Gen2GoldSilverIntro) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if movie == null:
		return out
	for sprite: Dictionary in movie.sprites():
		var index: int = int(sprite["set"])
		if index < 0 or index >= OAM_SETS.size():
			continue
		var set: Dictionary = OAM_SETS[index]
		var at: Vector2i = sprite["at"]
		var flip_x: bool = bool(sprite["flip_x"])
		for part: Array in set["parts"]:
			# `UpdateAnimFrame` stops at `wShadowOAMEnd` rather than growing.
			if out.size() >= SHADOW_OAM_SPRITES:
				return out
			var dx: int = int(part[1])
			var attrs: int = int(part[3])
			# `AddOrSubtractX`: a flipped frameset turns a part's own offset into
			# -8 - offset before it is added.
			if flip_x:
				dx = -TILE - dx
			out.append({
				# `UpdateAnimFrame` builds every position with `add`, so an
				# offset past the screen wraps rather than clamping.
				"y": (at.y + int(part[0])) & 0xFF,
				"x": (at.x + dx) & 0xFF,
				"tile": (int(sprite["vtile"]) + int(set["vtile"]) + int(part[2])) & 0xFF,
				"palette": 1 if attrs & ATTR_PALETTE else 0,
				"flip_x": bool(attrs & ATTR_XFLIP) != flip_x,
				"flip_y": bool(attrs & ATTR_YFLIP),
			})
	return out


## The BG map, sampled through `hSCX` and the scanline's own `hSCY`. Both are
## bytes and the map is 256 pixels square, so the sampling wraps rather than
## clipping.
func _draw_background(image: Image, movie: Gen2GoldSilverIntro) -> void:
	var map: PackedByteArray = movie.bg_map()
	if map.size() < MAP_COLUMNS * MAP_ROWS:
		return
	var palette: PackedColorArray = movie.palette()
	if palette.is_empty():
		return
	var sheets: Dictionary = CUTSCENE_SHEETS.get(movie.cutscene(), {})
	var low: PackedByteArray = _sheet(String(sheets.get("bg", "")))
	var high: PackedByteArray = _sheet(String(sheets.get("bg_high", "")))
	var scx: int = movie.scroll().x
	for y: int in HEIGHT:
		var scy: int = movie.scroll_y_at(y)
		var map_y: int = (y + scy) & 0xFF
		var row: int = (map_y / TILE) % MAP_ROWS
		var in_tile_y: int = map_y % TILE
		for x: int in WIDTH:
			var map_x: int = (x + scx) & 0xFF
			var column: int = (map_x / TILE) % MAP_COLUMNS
			var tile: int = map[row * MAP_COLUMNS + column]
			var strip: PackedByteArray = low
			var index: int = tile
			if tile >= HIGH_TILE:
				strip = high
				index = tile - HIGH_TILE
			image.set_pixel(
				x, y, palette[_pixel(strip, index, map_x % TILE, in_tile_y, false, false)]
			)


## One shadow-OAM entry, off the cutscene's own object sheet. The position is
## already the OAM byte, so it is only moved off OAM's own (8, 16) origin.
func _draw_sprite(image: Image, movie: Gen2GoldSilverIntro, entry: Dictionary) -> void:
	var palette: PackedColorArray = movie.object_palette(int(entry["palette"]))
	if palette.size() <= TRANSPARENT_INDEX:
		return
	_blit_sprite_tile(
		image,
		_sheet(String((CUTSCENE_SHEETS.get(movie.cutscene(), {}) as Dictionary).get("obj", ""))),
		palette, int(entry["tile"]),
		Vector2i(int(entry["x"]) - OAM_ORIGIN.x, int(entry["y"]) - OAM_ORIGIN.y),
		bool(entry["flip_x"]), bool(entry["flip_y"])
	)


func _blit_sprite_tile(
	image: Image, strip: PackedByteArray, palette: PackedColorArray, tile: int,
	at: Vector2i, flip_x: bool, flip_y: bool
) -> void:
	var starter: Dictionary = _starter_for(tile)
	for row: int in TILE:
		var y: int = at.y + row
		if y < 0 or y >= HEIGHT:
			continue
		for column: int in TILE:
			var x: int = at.x + column
			if x < 0 or x >= WIDTH:
				continue
			var pixel: int = _starter_pixel(starter, tile, column, row, flip_x, flip_y) \
				if not starter.is_empty() \
				else _pixel(strip, tile, column, row, flip_x, flip_y)
			if pixel == TRANSPARENT_INDEX:
				continue
			image.set_pixel(x, y, palette[pixel])


## Which of the three front pics a sprite tile lands in, if any.
func _starter_for(tile: int) -> Dictionary:
	for entry: Dictionary in STARTER_PICS:
		var first: int = int(entry["vtile"])
		if tile >= first and tile < first + STARTER_TILES * STARTER_TILES:
			return entry
	return {}


## One pixel of a pic in its atlas cell, addressed the way the OAM set does:
## column-major, five tiles down before the next column.
func _starter_pixel(
	entry: Dictionary, tile: int, x: int, y: int, flip_x: bool, flip_y: bool
) -> int:
	var pic: Dictionary = _data.species_pic(int(entry["species"]))
	if pic.is_empty():
		return 0
	var meta: Dictionary = _data.atlas(String(pic["atlas"]))
	var indices: PackedByteArray = _data.atlas_indices(String(pic["atlas"]))
	var columns: int = int(meta.get("columns", 0))
	var cell: int = int(meta.get("cell", 0))
	if columns <= 0 or cell <= 0 or indices.is_empty():
		return 0
	var slot: int = int(pic["slot"])
	var origin := Vector2i((slot % columns) * cell, (slot / columns) * cell)
	var within: int = tile - int(entry["vtile"])
	var at := Vector2i(
		origin.x + (within / STARTER_TILES) * TILE + ((TILE - 1 - x) if flip_x else x),
		origin.y + (within % STARTER_TILES) * TILE + ((TILE - 1 - y) if flip_y else y)
	)
	var width: int = int(meta.get("width", columns * cell))
	if at.x < 0 or at.x >= width:
		return 0
	var offset: int = at.y * width + at.x
	return indices[offset] if offset >= 0 and offset < indices.size() else 0


## One pixel of a tile in a horizontal strip of tile indices.
func _pixel(
	strip: PackedByteArray, tile: int, x: int, y: int, flip_x: bool, flip_y: bool
) -> int:
	if strip.is_empty():
		return 0
	var width: int = strip.size() / TILE
	var column: int = tile * TILE + ((TILE - 1 - x) if flip_x else x)
	var row: int = (TILE - 1 - y) if flip_y else y
	if column < 0 or column >= width:
		return 0
	return strip[row * width + column]


func _sheet(name: String) -> PackedByteArray:
	if name.is_empty() or _data == null:
		return PackedByteArray()
	if _sheets.has(name):
		return _sheets[name]
	var strip: PackedByteArray = _data.tile_indices("gs_intro_%s" % name)
	_sheets[name] = strip
	return strip
