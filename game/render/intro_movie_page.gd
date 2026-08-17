class_name Gen2IntroMoviePage
extends RefCounted

## The intro movie's screen, on the tile grid the hardware uses.
##
## [Gen2IntroMovie] owns the BG map, the attribute plane, the palettes, the
## scroll and the sprite structs; this turns a tile number into pixels. The
## split is the credits' and the title screen's.
##
## Two things here are not a plain tilemap draw:
##
## - The BG map is 32 tiles wide and wraps. `hSCX` and `hSCY` are bytes, the
##   panorama scenes scroll past both edges, and `hLCDCPointer` = LOW(rSCX)
##   gives every scanline its own `hSCX`, which is what
##   `Intro_PerspectiveScrollBG` uses to run the grass and the trees at
##   different speeds. So the screen is sampled scanline by scanline rather than
##   blitted tile by tile.
## - A BG tile number below $80 reads from `vTiles2` and $80 and up from
##   `vTiles1`, which are two different sheets in the scenes that load both.
##
## An object is drawn through the palette its own `dbsprite` attribute names,
## which is one of the eight a scene's palette run wrote past the background
## buffer's end.
##
## Shadow OAM holds forty sprites and `UpdateAnimFrame` stops filling it at
## `wShadowOAMEnd`, so a frame that asks for more loses the last of them rather
## than growing. `IntroScene10` is the one frame that does: Wooper's sixteen and
## Pichu's twenty-five come to forty-one, and Pichu's last tile is not drawn.

const TILE: int = Gen2Tiles.TILE_WIDTH
const WIDTH: int = Gen2Screen.WIDTH
const HEIGHT: int = Gen2Screen.HEIGHT
const MAP_COLUMNS: int = RomLayout.INTRO_MAP_COLUMNS
const MAP_ROWS: int = RomLayout.INTRO_MAP_ROWS
## The screen `Intro_LoadTilemap` copies into `wTilemap`, which is the part of
## the BG map the two Suicune scenes rewrite in place.
const COLUMNS: int = Gen2IntroMovie.COLUMNS
const ROWS: int = Gen2IntroMovie.ROWS

## Shadow OAM counts from (8, 16).
const OAM_ORIGIN := Vector2i(8, 16)
## A sprite never draws its first colour.
const TRANSPARENT_INDEX: int = 0
## Where a BG tile number stops reading from the low sheet and starts reading
## from the one at `vTiles1`.
const HIGH_TILE: int = 0x80

## `wShadowOAM`, which is forty `SPRITEOAMSTRUCT`s and no more.
const SHADOW_OAM_SPRITES: int = 40

## `dbsprite`'s attribute byte.
const ATTR_PALETTE: int = 0x07
const ATTR_BANK1: int = 0x08
const ATTR_XFLIP: int = 0x20
const ATTR_YFLIP: int = 0x40
## `OAM_PRIO`: the background wins wherever its own colour is not 0. Only
## `.OAMData_IntroSuicuneAway` carries it, on all twenty of its tiles.
const ATTR_PRIORITY: int = 0x80

const OAM_SETS: Array[Dictionary] = [
	# 0: SPRITE_ANIM_OAMSET_INTRO_SUICUNE_1 (.OAMData_IntroSuicune1, 36 sprites)
	{"vtile": 0x00, "parts": [
		[-24, 8, 0x05, 0x00], [-24, 16, 0x06, 0x00], [-24, 24, 0x07, 0x00],
		[-16, -24, 0x11, 0x00], [-16, -16, 0x12, 0x00], [-16, -8, 0x13, 0x00],
		[-16, 0, 0x14, 0x00], [-16, 8, 0x15, 0x00], [-16, 16, 0x16, 0x00],
		[-16, 24, 0x17, 0x00], [-8, -32, 0x20, 0x00], [-8, -24, 0x21, 0x00],
		[-8, -16, 0x22, 0x00], [-8, -8, 0x23, 0x00], [-8, 0, 0x24, 0x00],
		[-8, 8, 0x25, 0x00], [-8, 16, 0x26, 0x00], [-8, 24, 0x27, 0x00],
		[0, -32, 0x30, 0x00], [0, -24, 0x31, 0x00], [0, -16, 0x32, 0x00],
		[0, -8, 0x33, 0x00], [0, 0, 0x34, 0x00], [0, 8, 0x35, 0x00], [0, 16, 0x36, 0x00],
		[8, -32, 0x40, 0x00], [8, -24, 0x41, 0x00], [8, -16, 0x42, 0x00],
		[8, -8, 0x43, 0x00], [8, 0, 0x44, 0x00], [8, 8, 0x45, 0x00], [8, 16, 0x46, 0x00],
		[8, 24, 0x47, 0x00], [16, -32, 0x50, 0x00], [16, -24, 0x51, 0x00],
		[16, 24, 0x57, 0x00]
	]},
	# 1: SPRITE_ANIM_OAMSET_INTRO_SUICUNE_2 (.OAMData_IntroSuicune2, 28 sprites)
	{"vtile": 0x08, "parts": [
		[-24, 0, 0x04, 0x00], [-24, 8, 0x05, 0x00], [-24, 16, 0x06, 0x00],
		[-16, -24, 0x11, 0x00], [-16, -16, 0x12, 0x00], [-16, -8, 0x13, 0x00],
		[-16, 0, 0x14, 0x00], [-16, 8, 0x15, 0x00], [-16, 16, 0x16, 0x00],
		[-8, -24, 0x21, 0x00], [-8, -16, 0x22, 0x00], [-8, -8, 0x23, 0x00],
		[-8, 0, 0x24, 0x00], [-8, 8, 0x25, 0x00], [-8, 16, 0x26, 0x00],
		[0, -32, 0x30, 0x00], [0, -24, 0x31, 0x00], [0, -16, 0x32, 0x00],
		[0, -8, 0x33, 0x00], [0, 0, 0x34, 0x00], [0, 8, 0x35, 0x00], [8, -16, 0x42, 0x00],
		[8, -8, 0x43, 0x00], [8, 0, 0x44, 0x00], [8, 8, 0x45, 0x00], [16, -8, 0x53, 0x00],
		[16, 0, 0x54, 0x00], [16, 8, 0x55, 0x00]
	]},
	# 2: SPRITE_ANIM_OAMSET_INTRO_SUICUNE_3 (.OAMData_IntroSuicune3, 30 sprites)
	{"vtile": 0x60, "parts": [
		[-24, 0, 0x04, 0x00], [-24, 8, 0x05, 0x00], [-16, -24, 0x11, 0x00],
		[-16, -16, 0x12, 0x00], [-16, -8, 0x13, 0x00], [-16, 0, 0x14, 0x00],
		[-16, 8, 0x15, 0x00], [-16, 16, 0x16, 0x00], [-16, 24, 0x17, 0x00],
		[-8, -32, 0x20, 0x00], [-8, -24, 0x21, 0x00], [-8, -16, 0x22, 0x00],
		[-8, -8, 0x23, 0x00], [-8, 0, 0x24, 0x00], [-8, 8, 0x25, 0x00],
		[-8, 16, 0x26, 0x00], [0, -32, 0x30, 0x00], [0, -24, 0x31, 0x00],
		[0, -16, 0x32, 0x00], [0, -8, 0x33, 0x00], [0, 0, 0x34, 0x00], [0, 8, 0x35, 0x00],
		[8, -16, 0x42, 0x00], [8, -8, 0x43, 0x00], [8, 0, 0x44, 0x00], [8, 8, 0x45, 0x00],
		[16, -16, 0x52, 0x00], [16, -8, 0x53, 0x00], [16, 0, 0x54, 0x00],
		[16, 8, 0x55, 0x00]
	]},
	# 3: SPRITE_ANIM_OAMSET_INTRO_SUICUNE_4 (.OAMData_IntroSuicune4, 31 sprites)
	{"vtile": 0x68, "parts": [
		[-16, -24, 0x11, 0x00], [-16, -16, 0x12, 0x00], [-16, -8, 0x13, 0x00],
		[-16, 0, 0x14, 0x00], [-16, 8, 0x15, 0x00], [-16, 16, 0x16, 0x00],
		[-16, 24, 0x17, 0x00], [-8, -32, 0x20, 0x00], [-8, -24, 0x21, 0x00],
		[-8, -16, 0x22, 0x00], [-8, -8, 0x23, 0x00], [-8, 0, 0x24, 0x00],
		[-8, 8, 0x25, 0x00], [-8, 16, 0x26, 0x00], [-8, 24, 0x27, 0x00],
		[0, -32, 0x30, 0x00], [0, -24, 0x31, 0x00], [0, -16, 0x32, 0x00],
		[0, -8, 0x33, 0x00], [0, 0, 0x34, 0x00], [0, 8, 0x35, 0x00], [0, 16, 0x36, 0x00],
		[8, -24, 0x41, 0x00], [8, -16, 0x42, 0x00], [8, -8, 0x43, 0x00],
		[8, 0, 0x44, 0x00], [8, 8, 0x45, 0x00], [16, -24, 0x51, 0x00],
		[16, -16, 0x52, 0x00], [16, 0, 0x54, 0x00], [16, 8, 0x55, 0x00]
	]},
	# 4: SPRITE_ANIM_OAMSET_INTRO_PICHU_1 (.OAMData_IntroPichu, 25 sprites)
	{"vtile": 0x00, "parts": [
		[-20, -20, 0x00, 0x09], [-20, -12, 0x01, 0x09], [-20, -4, 0x02, 0x09],
		[-20, 4, 0x03, 0x09], [-20, 12, 0x04, 0x09], [-12, -20, 0x10, 0x09],
		[-12, -12, 0x11, 0x09], [-12, -4, 0x12, 0x09], [-12, 4, 0x13, 0x09],
		[-12, 12, 0x14, 0x09], [-4, -20, 0x20, 0x09], [-4, -12, 0x21, 0x09],
		[-4, -4, 0x22, 0x09], [-4, 4, 0x23, 0x09], [-4, 12, 0x24, 0x09],
		[4, -20, 0x30, 0x09], [4, -12, 0x31, 0x09], [4, -4, 0x32, 0x09],
		[4, 4, 0x33, 0x09], [4, 12, 0x34, 0x09], [12, -20, 0x40, 0x09],
		[12, -12, 0x41, 0x09], [12, -4, 0x42, 0x09], [12, 4, 0x43, 0x09],
		[12, 12, 0x44, 0x09]
	]},
	# 5: SPRITE_ANIM_OAMSET_INTRO_PICHU_2 (.OAMData_IntroPichu, 25 sprites)
	{"vtile": 0x05, "parts": [
		[-20, -20, 0x00, 0x09], [-20, -12, 0x01, 0x09], [-20, -4, 0x02, 0x09],
		[-20, 4, 0x03, 0x09], [-20, 12, 0x04, 0x09], [-12, -20, 0x10, 0x09],
		[-12, -12, 0x11, 0x09], [-12, -4, 0x12, 0x09], [-12, 4, 0x13, 0x09],
		[-12, 12, 0x14, 0x09], [-4, -20, 0x20, 0x09], [-4, -12, 0x21, 0x09],
		[-4, -4, 0x22, 0x09], [-4, 4, 0x23, 0x09], [-4, 12, 0x24, 0x09],
		[4, -20, 0x30, 0x09], [4, -12, 0x31, 0x09], [4, -4, 0x32, 0x09],
		[4, 4, 0x33, 0x09], [4, 12, 0x34, 0x09], [12, -20, 0x40, 0x09],
		[12, -12, 0x41, 0x09], [12, -4, 0x42, 0x09], [12, 4, 0x43, 0x09],
		[12, 12, 0x44, 0x09]
	]},
	# 6: SPRITE_ANIM_OAMSET_INTRO_PICHU_3 (.OAMData_IntroPichu, 25 sprites)
	{"vtile": 0x0A, "parts": [
		[-20, -20, 0x00, 0x09], [-20, -12, 0x01, 0x09], [-20, -4, 0x02, 0x09],
		[-20, 4, 0x03, 0x09], [-20, 12, 0x04, 0x09], [-12, -20, 0x10, 0x09],
		[-12, -12, 0x11, 0x09], [-12, -4, 0x12, 0x09], [-12, 4, 0x13, 0x09],
		[-12, 12, 0x14, 0x09], [-4, -20, 0x20, 0x09], [-4, -12, 0x21, 0x09],
		[-4, -4, 0x22, 0x09], [-4, 4, 0x23, 0x09], [-4, 12, 0x24, 0x09],
		[4, -20, 0x30, 0x09], [4, -12, 0x31, 0x09], [4, -4, 0x32, 0x09],
		[4, 4, 0x33, 0x09], [4, 12, 0x34, 0x09], [12, -20, 0x40, 0x09],
		[12, -12, 0x41, 0x09], [12, -4, 0x42, 0x09], [12, 4, 0x43, 0x09],
		[12, 12, 0x44, 0x09]
	]},
	# 7: SPRITE_ANIM_OAMSET_INTRO_WOOPER (.OAMData_IntroWooper, 16 sprites)
	{"vtile": 0x50, "parts": [
		[-16, -20, 0x00, 0x0A], [-16, -12, 0x01, 0x0A], [-16, -4, 0x02, 0x0A],
		[-16, 4, 0x03, 0x0A], [-8, -20, 0x04, 0x0A], [-8, -12, 0x05, 0x0A],
		[-8, -4, 0x06, 0x0A], [-8, 4, 0x07, 0x0A], [0, -20, 0x08, 0x0A],
		[0, -12, 0x09, 0x0A], [0, -4, 0x0A, 0x0A], [0, 4, 0x0B, 0x0A],
		[8, -20, 0x0C, 0x0A], [8, -12, 0x0D, 0x0A], [8, -4, 0x0E, 0x0A],
		[8, 4, 0x0F, 0x0A]
	]},
	# 8: SPRITE_ANIM_OAMSET_INTRO_UNOWN_1 (.OAMData_IntroUnown1, 1 sprites)
	{"vtile": 0x00, "parts": [
		[-4, -4, 0x00, 0x00]
	]},
	# 9: SPRITE_ANIM_OAMSET_INTRO_UNOWN_2 (.OAMData_IntroUnown2, 3 sprites)
	{"vtile": 0x01, "parts": [
		[0, -8, 0x00, 0x00], [-8, -8, 0x01, 0x00], [-8, 0, 0x02, 0x00]
	]},
	# 10: SPRITE_ANIM_OAMSET_INTRO_UNOWN_3 (.OAMData_IntroUnown3, 7 sprites)
	{"vtile": 0x04, "parts": [
		[8, -16, 0x00, 0x00], [0, -16, 0x01, 0x00], [-8, -16, 0x02, 0x00],
		[-8, -8, 0x03, 0x00], [-16, -8, 0x04, 0x00], [-16, 0, 0x05, 0x00],
		[-16, 8, 0x06, 0x00]
	]},
	# 11: SPRITE_ANIM_OAMSET_INTRO_UNOWN_F_2_1 (.OAMData_IntroUnownF2_1, 4 sprites)
	{"vtile": 0x00, "parts": [
		[-8, -8, 0x00, 0x00], [-8, 0, 0x00, 0x20], [0, -8, 0x00, 0x40], [0, 0, 0x00, 0x60]
	]},
	# 12: SPRITE_ANIM_OAMSET_INTRO_UNOWN_F_2_2 (.OAMData_IntroUnownF2_2, 8 sprites)
	{"vtile": 0x01, "parts": [
		[-8, -16, 0x00, 0x00], [-8, -8, 0x01, 0x00], [-8, 0, 0x01, 0x20],
		[-8, 8, 0x00, 0x20], [0, -16, 0x00, 0x40], [0, -8, 0x01, 0x40], [0, 0, 0x01, 0x60],
		[0, 8, 0x00, 0x60]
	]},
	# 13: SPRITE_ANIM_OAMSET_INTRO_UNOWN_F_2_3 (.OAMData_IntroUnownF2_3, 12 sprites)
	{"vtile": 0x03, "parts": [
		[-24, -8, 0x00, 0x00], [-16, -8, 0x01, 0x00], [-8, -8, 0x02, 0x00],
		[-24, 0, 0x00, 0x20], [-16, 0, 0x01, 0x20], [-8, 0, 0x02, 0x20],
		[0, -8, 0x02, 0x40], [8, -8, 0x01, 0x40], [16, -8, 0x00, 0x40], [0, 0, 0x02, 0x60],
		[8, 0, 0x01, 0x60], [16, 0, 0x00, 0x60]
	]},
	# 14: SPRITE_ANIM_OAMSET_INTRO_UNOWN_F_2_4 (.OAMData_IntroUnownF2_4_5, 20 sprites)
	{"vtile": 0x08, "parts": [
		[-20, -16, 0x00, 0x00], [-20, -8, 0x01, 0x00], [-20, 0, 0x02, 0x00],
		[-20, 8, 0x03, 0x00], [-12, -16, 0x04, 0x00], [-12, -8, 0x05, 0x00],
		[-12, 0, 0x06, 0x00], [-12, 8, 0x07, 0x00], [-4, -16, 0x08, 0x00],
		[-4, -8, 0x09, 0x00], [-4, 0, 0x0A, 0x00], [-4, 8, 0x0B, 0x00],
		[4, -16, 0x0C, 0x00], [4, -8, 0x0D, 0x00], [4, 0, 0x0E, 0x00], [4, 8, 0x0F, 0x00],
		[12, -16, 0x10, 0x00], [12, -8, 0x11, 0x00], [12, 0, 0x12, 0x00],
		[12, 8, 0x13, 0x00]
	]},
	# 15: SPRITE_ANIM_OAMSET_INTRO_UNOWN_F_2_5 (.OAMData_IntroUnownF2_4_5, 20 sprites)
	{"vtile": 0x1C, "parts": [
		[-20, -16, 0x00, 0x00], [-20, -8, 0x01, 0x00], [-20, 0, 0x02, 0x00],
		[-20, 8, 0x03, 0x00], [-12, -16, 0x04, 0x00], [-12, -8, 0x05, 0x00],
		[-12, 0, 0x06, 0x00], [-12, 8, 0x07, 0x00], [-4, -16, 0x08, 0x00],
		[-4, -8, 0x09, 0x00], [-4, 0, 0x0A, 0x00], [-4, 8, 0x0B, 0x00],
		[4, -16, 0x0C, 0x00], [4, -8, 0x0D, 0x00], [4, 0, 0x0E, 0x00], [4, 8, 0x0F, 0x00],
		[12, -16, 0x10, 0x00], [12, -8, 0x11, 0x00], [12, 0, 0x12, 0x00],
		[12, 8, 0x13, 0x00]
	]},
	# 16: SPRITE_ANIM_OAMSET_INTRO_SUICUNE_AWAY (.OAMData_IntroSuicuneAway, 20 sprites)
	{"vtile": 0x80, "parts": [
		[0, 8, 0x00, 0x81], [8, 16, 0x00, 0x81], [16, 24, 0x00, 0x81],
		[24, 32, 0x00, 0x81], [32, 40, 0x00, 0x81], [24, 48, 0x00, 0x81],
		[16, 56, 0x00, 0x81], [8, 64, 0x00, 0x81], [0, 72, 0x00, 0x81],
		[8, 80, 0x00, 0x81], [16, 88, 0x00, 0x81], [24, 96, 0x00, 0x81],
		[32, 104, 0x00, 0x81], [24, 112, 0x00, 0x81], [16, 120, 0x00, 0x81],
		[8, -128, 0x00, 0x81], [0, -120, 0x00, 0x81], [8, -112, 0x00, 0x81],
		[16, -104, 0x00, 0x81], [24, -96, 0x00, 0x81]
	]},
]


var _data: GameData = null
## One tile-index strip per sheet name, read once.
var _sheets: Dictionary = {}


## Null on a cache without the intro movie's art, which is the caller's cue to
## skip the phase rather than to run it blank.
static func from_data(data: GameData) -> Gen2IntroMoviePage:
	if data == null or not data.has_intro_movie():
		return null
	var out := Gen2IntroMoviePage.new()
	out._data = data
	return out


## The whole 160x144 screen for one frame of [param movie].
func draw(movie: Gen2IntroMovie) -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	if movie == null:
		return image
	var background: Array = _draw_background(image, movie)
	var behind: PackedByteArray = background[0]
	var forced: PackedByteArray = background[1]
	# The lower OAM index wins a pixel, so a slot only paints where no earlier
	# one did.
	var taken := PackedByteArray()
	taken.resize(WIDTH * HEIGHT)
	for entry: Dictionary in shadow_oam(movie):
		_draw_sprite(image, movie, entry, behind, forced, taken)
	return image


## Every live struct expanded into the shadow OAM the hardware would hold, in
## struct order, which is the z-order `PlaySpriteAnimations` walks. `y` and `x`
## are the OAM bytes and `tile` the byte `dbsprite` writes. [method draw] blits
## this same list rather than re-deriving it, so a trace of it compares to a
## cartridge's own buffer line for line.
func shadow_oam(movie: Gen2IntroMovie) -> Array[Dictionary]:
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
		var flip_y: bool = bool(sprite["flip_y"])
		for part: Array in set["parts"]:
			# `UpdateAnimFrame` stops at `wShadowOAMEnd` rather than growing.
			if out.size() >= SHADOW_OAM_SPRITES:
				return out
			var dy: int = int(part[0])
			var dx: int = int(part[1])
			var attrs: int = int(part[3])
			# `AddOrSubtractX`/`_Y`: a flipped frameset turns a part's own offset
			# into -8 - offset before it is added.
			if flip_x:
				dx = -TILE - dx
			if flip_y:
				dy = -TILE - dy
			out.append({
				# `UpdateAnimFrame` builds every position with `add`, so an
				# offset past the screen wraps rather than clamping.
				"y": (at.y + dy) & 0xFF,
				"x": (at.x + dx) & 0xFF,
				"tile": (int(sprite["vtile"]) + int(set["vtile"]) + int(part[2])) & 0xFF,
				"palette": attrs & ATTR_PALETTE,
				"flip_x": bool(attrs & ATTR_XFLIP) != flip_x,
				"flip_y": bool(attrs & ATTR_YFLIP) != flip_y,
				"priority": bool(attrs & ATTR_PRIORITY),
				"bank1": bool(sprite["bank1"]),
			})
	return out


## The BG map, sampled through `hSCY` and the scanline's own `hSCX`. Both are
## bytes and the map is 256 pixels square, so the sampling wraps rather than
## clipping.
func _draw_background(image: Image, movie: Gen2IntroMovie) -> Array:
	var behind := PackedByteArray()
	# The same indices where the tile's own attribute carries the priority bit,
	# which wins over every sprite rather than only over the ones marked
	# `OAM_PRIO`. The panorama's grass row carries it, which is what puts the
	# blades over Pichu's ears.
	var forced := PackedByteArray()
	var map: PackedByteArray = movie.bg_map()
	var attr: PackedByteArray = movie.bg_attr()
	if map.size() < RomLayout.INTRO_MAP_BYTES:
		return [behind, forced]
	behind.resize(WIDTH * HEIGHT)
	forced.resize(WIDTH * HEIGHT)
	var screen: PackedByteArray = movie.screen_tilemap()
	var palettes: Array[PackedColorArray] = []
	for slot: int in Gen2IntroMovie.BG_PALETTES:
		palettes.append(movie.palette(slot))
	var low: PackedByteArray = _sheet(movie, movie.sheet("bg"))
	var low_first: int = movie.sheet_first_tile("bg")
	var high: PackedByteArray = _sheet(movie, movie.sheet("bg_high"))
	var high_first: int = movie.sheet_first_tile("bg_high")
	# A bare `Request2bpp` writes over whichever sheet the tile number would
	# otherwise read, so the run it covers is looked at before either of them.
	var overlay: Array = movie.tile_overlay()
	var overlay_strip: PackedByteArray = _sheet(
		movie, String(overlay[2])
	) if overlay.size() == 3 else PackedByteArray()
	var overlay_first: int = int(overlay[0]) if overlay.size() == 3 else 0
	var overlay_count: int = int(overlay[1]) if overlay.size() == 3 else 0
	var scy: int = movie.scroll().y
	for y: int in HEIGHT:
		var scx: int = movie.scroll_x_at(y)
		var map_y: int = (y + scy) & 0xFF
		var row: int = (map_y / TILE) % MAP_ROWS
		var in_tile_y: int = map_y % TILE
		for x: int in WIDTH:
			var map_x: int = (x + scx) & 0xFF
			var column: int = (map_x / TILE) % MAP_COLUMNS
			var cell: int = row * MAP_COLUMNS + column
			var tile: int = map[cell]
			# `hBGMapMode` 1 pushes `wTilemap` over the map's own top-left
			# screen, which is the only part `Intro_ColoredSuicuneFrameSwap`
			# changes.
			if not screen.is_empty() and column < COLUMNS and row < ROWS:
				tile = screen[row * COLUMNS + column]
			var byte: int = attr[cell] if cell < attr.size() else 0
			var strip: PackedByteArray = low
			var index: int = tile + low_first
			if not overlay_strip.is_empty() and tile >= overlay_first \
					and tile < overlay_first + overlay_count:
				strip = overlay_strip
				index = tile - overlay_first
			elif tile >= HIGH_TILE:
				strip = high
				index = tile - HIGH_TILE + high_first
			var palette: PackedColorArray = palettes[byte & ATTR_PALETTE]
			if palette.is_empty():
				continue
			var pixel: int = _pixel(
				strip, index, map_x % TILE, in_tile_y,
				bool(byte & ATTR_XFLIP), bool(byte & ATTR_YFLIP)
			)
			behind[y * WIDTH + x] = pixel
			if byte & ATTR_PRIORITY != 0:
				forced[y * WIDTH + x] = pixel
			image.set_pixel(x, y, palette[pixel])
	return [behind, forced]


## One shadow-OAM entry, off the sheet its struct was loaded into. The position
## is already the OAM byte, so it is only moved off OAM's own (8, 16) origin.
func _draw_sprite(
	image: Image, movie: Gen2IntroMovie, entry: Dictionary,
	behind: PackedByteArray, forced: PackedByteArray, taken: PackedByteArray
) -> void:
	var tile: int = int(entry["tile"])
	var strip: PackedByteArray = _sheet(
		movie, movie.sheet("obj_bank1" if bool(entry["bank1"]) else "obj")
	)
	# A sprite tile counts from `vTiles0`, so $80 and up is the `vTiles1` half of
	# the window, which the last two Suicune scenes load a sheet of their own
	# into. A bare `Request2bpp` on top of either half wins over both.
	var overlay: Array = movie.tile_overlay()
	## `Intro_RustleGrass` writes vTiles2 in VRAM bank 0. Pichu and Wooper read
	## the same tile numbers from bank 1, where their own sheet remains intact.
	if not bool(entry["bank1"]) and overlay.size() == 3 and tile >= int(overlay[0]) \
			and tile < int(overlay[0]) + int(overlay[1]):
		strip = _sheet(movie, String(overlay[2]))
		tile -= int(overlay[0])
	elif tile >= HIGH_TILE:
		strip = _sheet(movie, movie.sheet("obj_high"))
		tile -= HIGH_TILE
	if strip.is_empty():
		return
	var palette: PackedColorArray = movie.object_palette(int(entry["palette"]))
	if palette.size() <= TRANSPARENT_INDEX:
		return
	_blit_sprite_tile(
		image, strip, palette, tile,
		Vector2i(int(entry["x"]) - OAM_ORIGIN.x, int(entry["y"]) - OAM_ORIGIN.y),
		bool(entry["flip_x"]), bool(entry["flip_y"]), taken,
		behind if bool(entry.get("priority", false)) else forced
	)


## [param taken] marks the pixels an earlier slot has already claimed, and
## [param behind] is the background's own colour indices: every one of them when
## the entry carries `OAM_PRIO`, and only the tiles whose attribute carries the
## priority bit otherwise. The claim comes first: a sprite that loses the pixel
## to the background still wins it against the sprites behind it.
func _blit_sprite_tile(
	image: Image, strip: PackedByteArray, palette: PackedColorArray, tile: int,
	at: Vector2i, flip_x: bool, flip_y: bool, taken: PackedByteArray,
	behind: PackedByteArray
) -> void:
	for row: int in TILE:
		var y: int = at.y + row
		if y < 0 or y >= HEIGHT:
			continue
		for column: int in TILE:
			var x: int = at.x + column
			if x < 0 or x >= WIDTH:
				continue
			var pixel: int = _pixel(strip, tile, column, row, flip_x, flip_y)
			if pixel == TRANSPARENT_INDEX:
				continue
			var at_pixel: int = y * WIDTH + x
			if taken[at_pixel] != 0:
				continue
			taken[at_pixel] = 1
			if not behind.is_empty() and behind[at_pixel] != TRANSPARENT_INDEX:
				continue
			image.set_pixel(x, y, palette[pixel])


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


func _sheet(movie: Gen2IntroMovie, name: String) -> PackedByteArray:
	if name.is_empty() or _data == null:
		return PackedByteArray()
	if _sheets.has(name):
		return _sheets[name]
	var strip: PackedByteArray = _data.tile_indices("intro_%s" % name)
	_sheets[name] = strip
	return strip
