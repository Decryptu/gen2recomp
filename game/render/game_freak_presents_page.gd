class_name Gen2GameFreakPresentsPage
extends RefCounted

## The GameFreak Presents screen, on the tile grid the hardware uses.
##
## A cleared background with two `PlaceString`s on it and one object layer over
## the top, which is where the two profiles part: Crystal's Ditto comes out of
## `GameFreakDittoGFX` and reads eleven OAM sets off one 16x16 sheet, while Gold
## and Silver's logo, star and sparkles are the tail of `GameFreakLogoGFX`
## followed by `GameFreakLogoStarsGFX`, one contiguous run from `vTiles1` tile
## $0d, which is what `SPRITE_ANIM_DICT_GS_SPLASH` maps to.
##
## [Gen2GameFreakPresents] owns the frames and the positions; this owns the
## pixels. Node-free like the other `render/*_page.gd`.

const TILE: int = Gen2Tiles.TILE_WIDTH
const COLUMNS: int = 20
const ROWS: int = 18
## `ClearTilemap` leaves the blank tile everywhere, which through
## PREDEFPAL_GAMEFREAK_LOGO_BG is black.
const BLANK_INDEX: int = 0
## A sprite never draws its first colour.
const TRANSPARENT_INDEX: int = 0

## Shadow OAM counts from (8, 16), so a coordinate reaches the screen eight less
## across and sixteen less down.
const OAM_ORIGIN := Vector2i(8, 16)
## `wShadowOAM` holds forty sprites, the name the other opening pages use.
const SHADOW_OAM_SPRITES: int = 40

## `.OAMData_GameFreakLogo1_3` and `.OAMData_GameFreakLogo4_11`, as
## (x, y, tile) with the `dbsprite` bytes already worked out. Crystal's Ditto is
## the only sprite that uses either.
const DITTO_SMALL: Array[Vector3i] = [
	Vector3i(-12, -16, 0x00), Vector3i(-4, -16, 0x01), Vector3i(4, -16, 0x02),
	Vector3i(-12, -8, 0x10), Vector3i(-4, -8, 0x11), Vector3i(4, -8, 0x12),
	Vector3i(-12, 0, 0x20), Vector3i(-4, 0, 0x21), Vector3i(4, 0, 0x22),
]
## The eleven `spriteanimoam` tile offsets, in `SPRITE_ANIM_OAMSET_GAMEFREAK_LOGO_*`
## order. The first three name the nine-sprite set, the rest the twenty-four.
const DITTO_BASES: Array[int] = [
	0xD0, 0xD3, 0xD6, 0x6C, 0x68, 0x64, 0x60, 0x0C, 0x08, 0x04, 0x00,
]
const DITTO_SMALL_SETS: int = 3
const DITTO_LARGE_COLUMNS: int = 4
const DITTO_LARGE_ROWS: int = 6

## `.OAMData_GSGameFreakLogo`: three across by five down, with the whole block a
## half-tile right and half a tile down of where the Ditto's sits.
const GOLD_LOGO_COLUMNS: int = 3
const GOLD_LOGO_ROWS: int = 5
const GOLD_LOGO_AT := Vector2i(-12, -20)
## `.OAMData_GSGameFreakLogoStar`, which draws two tiles and their X flips.
const GOLD_STAR: Array[Vector3i] = [
	Vector3i(-8, -8, 0), Vector3i(0, -8, 0), Vector3i(-8, 0, 1), Vector3i(0, 0, 1),
]
const GOLD_STAR_FLIPPED: Array[bool] = [false, true, false, true]
## `.OAMData_1x1_Palette0`, which every sparkle frame uses.
const GOLD_SPARKLE_AT := Vector2i(-4, -4)
## `SPRITE_ANIM_DICT_GS_SPLASH` is $8d, the first tile of `gamefreak_logo.1bpp`,
## so a sprite tile past the logo's fifteen is one of the star sheet's five.
const GOLD_SPRITE_FIRST_TILE: int = RomLayout.PRESENTS_WORD_TILES
## The VRAM tile the dictionary maps those objects to, which is what a shadow-OAM
## byte holds. Crystal decompresses the Ditto to `vTiles0` and counts from zero.
const GOLD_SPRITE_VRAM_BASE: int = 0x8D

var _profile: StringName = &"gold"
var _background: PackedColorArray = PackedColorArray()
var _object: PackedColorArray = PackedColorArray()
var _fade: PackedColorArray = PackedColorArray()

var _word_tiles: PackedByteArray = PackedByteArray()
var _word_width: int = 0
var _sprite_tiles: PackedByteArray = PackedByteArray()
var _sprite_width: int = 0
var _star_tiles: PackedByteArray = PackedByteArray()
var _star_width: int = 0


## Null on a cache with no GameFreak Presents art, which is the caller's cue to
## skip the phase rather than to run it blank.
static func from_data(data: GameData) -> Gen2GameFreakPresentsPage:
	if data == null:
		return null
	var sheet: Dictionary = data.tile_sheet("game_freak_logo")
	var indices: PackedByteArray = data.tile_indices("game_freak_logo")
	if sheet.is_empty() or indices.is_empty():
		return null
	var out := Gen2GameFreakPresentsPage.new()
	out._profile = data.id
	out._word_tiles = indices
	out._word_width = int(sheet.get("width", 0))
	out._background = data.copyright_palette()
	out._object = data.presents_palette("object")
	if out._word_width <= 0 or out._background.is_empty():
		return null
	if data.id == RomRegistry.CRYSTAL:
		var ditto: Dictionary = data.tile_sheet("game_freak_ditto")
		out._sprite_tiles = data.tile_indices("game_freak_ditto")
		out._sprite_width = int(ditto.get("width", 0))
		out._object = data.presents_palette("ditto")
		out._fade = data.presents_palette("ditto_fade")
	else:
		var stars: Dictionary = data.tile_sheet("game_freak_stars")
		out._star_tiles = data.tile_indices("game_freak_stars")
		out._star_width = int(stars.get("width", 0))
		out._sprite_tiles = indices
		out._sprite_width = out._word_width
	if out._sprite_tiles.is_empty() or out._object.is_empty():
		return null
	return out


## The whole 160x144 screen for one frame of [param phase].
func draw(phase: Gen2GameFreakPresents) -> Image:
	var width: int = COLUMNS * TILE
	var height: int = ROWS * TILE
	var indices := PackedByteArray()
	indices.resize(width * height)
	indices.fill(BLANK_INDEX)
	if phase != null:
		_draw_words(indices, width, phase)
	var image: Image = Gen2PicImage.from_indices(indices, width, height, _background)
	# The lower OAM index wins a pixel, so a slot only paints where no earlier
	# one did.
	var taken := PackedByteArray()
	taken.resize(width * height)
	for entry: Dictionary in shadow_oam(phase):
		_draw_sprite(image, phase, entry, taken)
	return image


## Every live struct expanded into the shadow OAM the hardware would hold, in
## struct order, which is the z-order `PlaySpriteAnimations` walks. One entry
## per drawn tile, `y` and `x` the OAM bytes and `tile` the byte `dbsprite`
## writes, so a trace of this compares to a cartridge's own buffer line for
## line. [method draw] blits this same list rather than re-deriving it.
func shadow_oam(phase: Gen2GameFreakPresents) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if phase == null:
		return out
	for sprite: Dictionary in phase.sprites():
		var kind: StringName = StringName(sprite["kind"])
		var at: Vector2i = sprite["at"]
		var flip_y: bool = bool(sprite.get("flip_y", false))
		for part: Dictionary in _oam_set(kind, int(sprite["set"])):
			# `UpdateAnimFrame` stops at `wShadowOAMEnd` rather than growing, so
			# a busier frame loses its last sprites. No frame here reaches it.
			if out.size() >= SHADOW_OAM_SPRITES:
				return out
			var offset: Vector2i = part["at"]
			# `dbsprite`'s own OAM_XFLIP flips the tile where it stands. Only the
			# struct's flip moves anything: `AddOrSubtractY` turns its offset into
			# -8 - offset, added to the coordinate as a byte, so the position is
			# worked out mod 256 and then clipped. Applying that to a per-tile
			# attribute drew the star's two halves on top of each other.
			if flip_y:
				offset.y = -TILE - offset.y
			out.append({
				"y": (at.y + offset.y) & 0xFF,
				"x": (at.x + offset.x) & 0xFF,
				"tile": (_vram_base() + int(part["tile"])) & 0xFF,
				"flip_x": bool(part.get("flip_x", false)),
				"flip_y": flip_y,
				"logo": kind == Gen2GameFreakPresents.SPRITE_LOGO,
			})
	return out


## `GameFreakPresents_PlaceGameFreak` and `_PlacePresents`, whichever of the two
## the scene has reached.
func _draw_words(
	indices: PackedByteArray, width: int, phase: Gen2GameFreakPresents
) -> void:
	var rows: Array[Vector2i] = phase.word_positions()
	var words: Array = [
		Gen2GameFreakPresents.WORD_GAME_FREAK, Gen2GameFreakPresents.WORD_PRESENTS,
	]
	for index: int in mini(phase.words(), words.size()):
		var at: Vector2i = rows[index]
		var column: int = 0
		for code: int in words[index]:
			_blit_tile(
				indices, width, _word_tiles, _word_width, code,
				Vector2i(at.x + column, at.y) * TILE
			)
			column += 1


## One shadow-OAM entry, drawn through the object palette whose first colour is
## transparent.
func _draw_sprite(
	image: Image, phase: Gen2GameFreakPresents, entry: Dictionary,
	taken: PackedByteArray
) -> void:
	# `dbsprite`'s attribute byte names the object palette. Only Gold's logo is
	# drawn through palette 1, which is the one the rotation moves.
	var palette: PackedColorArray = _object_palette(phase, bool(entry["logo"]))
	if palette.size() <= TRANSPARENT_INDEX:
		return
	_blit_sprite_tile(
		image, palette,
		int(entry["tile"]) - _vram_base(),
		Vector2i(int(entry["x"]) - OAM_ORIGIN.x, int(entry["y"]) - OAM_ORIGIN.y),
		bool(entry["flip_x"]), bool(entry["flip_y"]), taken
	)


## The palette a sprite is drawn through: Crystal's Ditto colours with the
## transform's own colour swapped in, or the order `rOBP1` currently reads
## PREDEFPAL_GAMEFREAK_LOGO_OB in.
func _object_palette(
	phase: Gen2GameFreakPresents, logo: bool
) -> PackedColorArray:
	if _profile != RomRegistry.CRYSTAL:
		return _rotated_object_palette(
			phase.logo_palette() if logo
			else Gen2GameFreakPresents.OBJECT_PALETTE_ORDER
		)
	var step: int = phase.fade_step()
	if step < 0 or step >= _fade.size():
		return _object
	var out: PackedColorArray = _object.duplicate()
	out[RomLayout.PRESENTS_DITTO_FADE_COLOR] = _fade[step]
	return out


## `CopyPals`: each colour of the live palette is the one `rOBP1`'s matching
## two bits name, which is how Gold turns the logo yellow without touching the
## graphic.
func _rotated_object_palette(order: int) -> PackedColorArray:
	var out := PackedColorArray()
	for index: int in _object.size():
		out.append(_object[(order >> (index * 2)) & 0x03])
	return out


## Where the profile's sprite sheet sits in VRAM, which shadow OAM counts from.
func _vram_base() -> int:
	return 0 if _profile == RomRegistry.CRYSTAL else GOLD_SPRITE_VRAM_BASE


## `.OAMData_*` for one set, as [code]{ at, tile, flip_x }[/code] with the tile
## already resolved to a position in the sheet it comes out of.
func _oam_set(kind: StringName, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match kind:
		Gen2GameFreakPresents.SPRITE_DITTO:
			var base: int = DITTO_BASES[clampi(index, 0, DITTO_BASES.size() - 1)]
			if index < DITTO_SMALL_SETS:
				for part: Vector3i in DITTO_SMALL:
					out.append({
						"at": Vector2i(part.x, part.y),
						"tile": (base + part.z) & 0xFF,
					})
				return out
			for row: int in DITTO_LARGE_ROWS:
				for column: int in DITTO_LARGE_COLUMNS:
					out.append({
						"at": Vector2i(
							(column - 2) * TILE + 4,
							(row - DITTO_LARGE_ROWS + 1) * TILE
						),
						"tile": (
							base + row * RomLayout.PRESENTS_DITTO_COLUMNS + column
						) & 0xFF,
					})
			return out
		Gen2GameFreakPresents.SPRITE_LOGO:
			for row: int in GOLD_LOGO_ROWS:
				for column: int in GOLD_LOGO_COLUMNS:
					out.append({
						"at": GOLD_LOGO_AT + Vector2i(column, row) * TILE,
						"tile": row * GOLD_LOGO_COLUMNS + column,
					})
			return out
		Gen2GameFreakPresents.SPRITE_STAR:
			for at: int in GOLD_STAR.size():
				var part: Vector3i = GOLD_STAR[at]
				out.append({
					"at": Vector2i(part.x, part.y),
					"tile": RomLayout.PRESENTS_LOGO_TILES + part.z,
					"flip_x": GOLD_STAR_FLIPPED[at],
				})
			return out
		Gen2GameFreakPresents.SPRITE_SPARKLE:
			out.append({
				"at": GOLD_SPARKLE_AT,
				"tile": RomLayout.PRESENTS_LOGO_TILES
					+ RomLayout.PRESENTS_STAR_TILES
					+ clampi(index, 0, RomLayout.PRESENTS_SPARKLE_TILES - 1),
			})
	return out


## One background tile of the word strip into the index buffer.
func _blit_tile(
	page: PackedByteArray, width: int, tiles: PackedByteArray, stride: int,
	tile: int, at: Vector2i
) -> void:
	if stride <= 0 or tile < 0:
		return
	for y: int in TILE:
		for x: int in TILE:
			var to: int = (at.y + y) * width + at.x + x
			var from: int = y * stride + tile * TILE + x
			if to < 0 or to >= page.size() or from < 0 or from >= tiles.size():
				continue
			page[to] = tiles[from]


## One object tile onto the drawn screen, clipped per axis so a sprite hanging
## off an edge cannot wrap onto the opposite one.
## [param taken] marks the pixels an earlier slot has already claimed.
func _blit_sprite_tile(
	image: Image, palette: PackedColorArray, tile: int, at: Vector2i,
	flip_x: bool, flip_y: bool, taken: PackedByteArray
) -> void:
	var tiles: PackedByteArray = _sprite_tiles
	var stride: int = _sprite_width
	var index: int = tile
	if _profile != RomRegistry.CRYSTAL:
		# The splash's object tiles run from `vTiles1` tile $0d: the logo's
		# fifteen out of `GameFreakLogoGFX`, then the star sheet's five.
		if tile < RomLayout.PRESENTS_LOGO_TILES:
			index = tile + GOLD_SPRITE_FIRST_TILE
		else:
			tiles = _star_tiles
			stride = _star_width
			index = tile - RomLayout.PRESENTS_LOGO_TILES
	if stride <= 0 or index < 0:
		return
	for y: int in TILE:
		var target_y: int = at.y + y
		if target_y < 0 or target_y >= image.get_height():
			continue
		for x: int in TILE:
			var target_x: int = at.x + x
			if target_x < 0 or target_x >= image.get_width():
				continue
			var source_x: int = TILE - 1 - x if flip_x else x
			var source_y: int = TILE - 1 - y if flip_y else y
			var from: int = source_y * stride + index * TILE + source_x
			if from < 0 or from >= tiles.size():
				continue
			var value: int = tiles[from]
			if value == TRANSPARENT_INDEX or value >= palette.size():
				continue
			var at_pixel: int = target_y * image.get_width() + target_x
			if taken[at_pixel] != 0:
				continue
			taken[at_pixel] = 1
			image.set_pixel(target_x, target_y, palette[value])
