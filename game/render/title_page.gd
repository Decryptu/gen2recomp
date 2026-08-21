class_name Gen2TitlePage
extends RefCounted

## The title screen, on the tile grid the hardware uses.
##
## Two screens under one name, the way [Gen2TitleScene] is. Crystal draws its
## logo with `DrawTitleGraphic`, keeps a strip of Suicune under it that
## `LoadSuicuneFrame` re-points every eighth frame, and stands the crystal in
## front as thirty 8x16 objects. Gold and Silver write `TitleScreenTilemap`
## straight into the BG map and fly one bird over it.
##
## [Gen2TitleScene] owns the frames and the positions; this owns the pixels.
## Node-free like the other `render/*_page.gd`.

const TILE: int = Gen2Tiles.TILE_WIDTH
const COLUMNS: int = 20
const ROWS: int = 18
## A sprite never draws its first colour.
const TRANSPARENT_INDEX: int = 0
## Shadow OAM counts from (8, 16), so a coordinate reaches the screen eight less
## across and sixteen less down.
const OAM_ORIGIN := Vector2i(8, 16)
## `wShadowOAM` holds forty sprites.
const SHADOW_OAM_SPRITES: int = 40
## `TILEMAP_WIDTH_PX`/`TILEMAP_HEIGHT_PX`: the BG map is 32 tiles square and
## wraps, and Crystal's `hSCY` of 8 is what makes the height matter.
const MAP_WIDTH: int = RomLayout.TITLE_TILEMAP_COLUMNS * Gen2Tiles.TILE_WIDTH
const MAP_HEIGHT: int = RomLayout.TITLE_TILEMAP_COLUMNS * Gen2Tiles.TILE_HEIGHT
## `set B_LCDC_OBJ_SIZE`: every object on this screen is two tiles tall.
const OBJECT_HEIGHT: int = 2

## `hlcoord 0, 3` with `lb bc, 7, 20` and a stride of 20: the Pokemon logo, and
## `TitleLogoGFX` is loaded at `vTiles1`, which the BG addresses from $80.
const CRYSTAL_LOGO_AT := Vector2i(0, 3)
const CRYSTAL_LOGO_COLUMNS: int = 20
const CRYSTAL_LOGO_ROWS: int = 7
const CRYSTAL_LOGO_FIRST_TILE: int = 0x80

## `TitleScreenPalettes` is sixteen palettes, and the attribute map picks one per
## row: the logo takes a gradient down its seven rows and the Suicune strip takes
## the first. `_TitleScreen` fills lines 3-4 with 2, then 3, 4, 5, and 8-9 with
## 6, so the seven rows read as the run below.
const CRYSTAL_LOGO_PALETTES: Array[int] = [2, 2, 3, 4, 5, 6, 6]
const CRYSTAL_VERSION_ROW: int = 9
const CRYSTAL_VERSION_AT: int = 5
const CRYSTAL_VERSION_TILES: int = 11
const CRYSTAL_VERSION_PALETTE: int = 1
## `hlbgcoord 3, 0, vBGMap1` with `lb bc, 1, 13` from tile $0c: the copyright
## line, in the window rather than in the background. `TitleLogoGFX` is 160 tiles
## and only its first 140 are the logo, so tile $0c of `vTiles2` is the sheet's
## own 140th: the decompress runs past `vTiles1` into the half the BG addresses
## from $00.
const CRYSTAL_COPYRIGHT_TILE: int = CRYSTAL_LOGO_COLUMNS * CRYSTAL_LOGO_ROWS
const CRYSTAL_COPYRIGHT_TILES: int = 13
const CRYSTAL_COPYRIGHT_AT: int = 3
## `hlbgcoord 0, 0, vBGMap3` fills the window's own row with palette 7.
const CRYSTAL_COPYRIGHT_PALETTE: int = 7
const CRYSTAL_SUICUNE_PALETTE: int = 0
## The hardware has eight of each, and `_TitleScreen` fills both sets from one
## sixteen-palette run.
const CRYSTAL_BG_PALETTES: int = 8

## `.OAMData_GSIntroHoOh1` through `5`, as `dbsprite` tile-and-pixel pairs
## already worked out: `(x, y, tile)` in pixels, with the 8x16 objects stepping
## the tile number by two.
const BIRD_OAM: Array[Array] = [
	[
		Vector3i(-32, -8, 0x00), Vector3i(-24, -16, 0x02), Vector3i(-24, 0, 0x04),
		Vector3i(-16, -24, 0x06), Vector3i(-16, -8, 0x08), Vector3i(-16, 8, 0x0A),
		Vector3i(-8, -24, 0x0C), Vector3i(-8, -8, 0x0E), Vector3i(-8, 8, 0x10),
		Vector3i(0, -24, 0x12), Vector3i(0, -8, 0x14), Vector3i(0, 8, 0x16),
		Vector3i(8, -24, 0x18), Vector3i(8, -8, 0x1A), Vector3i(8, 8, 0x1C),
		Vector3i(16, -8, 0x1E), Vector3i(16, 8, 0x20),
		Vector3i(24, -16, 0x22), Vector3i(24, 0, 0x24),
	],
	[
		Vector3i(-32, -8, 0x00), Vector3i(-24, -16, 0x02), Vector3i(-24, 0, 0x04),
		Vector3i(-16, -8, 0x26), Vector3i(-16, 8, 0x0A),
		Vector3i(-8, -24, 0x28), Vector3i(-8, -8, 0x2A), Vector3i(-8, 8, 0x10),
		Vector3i(0, -8, 0x2C), Vector3i(0, 8, 0x16),
		Vector3i(8, -8, 0x30), Vector3i(8, 8, 0x1C),
		Vector3i(16, -8, 0x1E), Vector3i(16, 8, 0x20),
		Vector3i(24, -16, 0x22), Vector3i(24, 0, 0x24),
	],
	[
		Vector3i(-32, -8, 0x00), Vector3i(-24, -16, 0x02), Vector3i(-24, 0, 0x32),
		Vector3i(-16, -8, 0x34), Vector3i(-16, 8, 0x36),
		Vector3i(-8, -8, 0x38), Vector3i(-8, 8, 0x3A),
		Vector3i(0, -8, 0x3C), Vector3i(0, 8, 0x3E),
		Vector3i(8, -8, 0x30), Vector3i(8, 8, 0x1C),
		Vector3i(16, -8, 0x1E), Vector3i(16, 8, 0x20),
		Vector3i(24, -16, 0x22), Vector3i(24, 0, 0x24),
	],
	[
		Vector3i(-32, -8, 0x00), Vector3i(-24, -16, 0x02), Vector3i(-24, 0, 0x04),
		Vector3i(-16, -8, 0x40), Vector3i(-16, 8, 0x42), Vector3i(-16, 24, 0x44),
		Vector3i(-8, -8, 0x46), Vector3i(-8, 8, 0x48), Vector3i(-8, 24, 0x4A),
		Vector3i(0, -8, 0x4C), Vector3i(0, 8, 0x4E),
		Vector3i(8, -8, 0x30), Vector3i(8, 8, 0x1C),
		Vector3i(16, -8, 0x1E), Vector3i(16, 8, 0x20),
		Vector3i(24, -16, 0x22), Vector3i(24, 0, 0x24),
	],
	[
		Vector3i(-32, -8, 0x00), Vector3i(-24, -16, 0x02), Vector3i(-24, 0, 0x04),
		Vector3i(-16, -8, 0x50), Vector3i(-16, 8, 0x0A),
		Vector3i(-8, -24, 0x52), Vector3i(-8, -8, 0x54), Vector3i(-8, 8, 0x10),
		Vector3i(0, -24, 0x56), Vector3i(0, -8, 0x2E), Vector3i(0, 8, 0x16),
		Vector3i(8, -8, 0x30), Vector3i(8, 8, 0x1C),
		Vector3i(16, -8, 0x1E), Vector3i(16, 8, 0x20),
		Vector3i(24, -16, 0x22), Vector3i(24, 0, 0x24),
	],
]
## `.OAMData_GSIntroLugia1` and `2`, which are what Silver's five sets are drawn
## from: the same two pictures at four `spriteanimoam` vtile offsets, so the
## sheet is cycled rather than the shape.
const LUGIA_OAM: Array[Array] = [
	[
		Vector3i(-40, -16, 0x00), Vector3i(-40, 0, 0x02),
		Vector3i(-32, -16, 0x04), Vector3i(-32, 0, 0x06),
		Vector3i(-24, -8, 0x08), Vector3i(-16, -8, 0x0A),
		Vector3i(-8, -16, 0x0C), Vector3i(-8, 0, 0x0E),
		Vector3i(0, -16, 0x10), Vector3i(0, 0, 0x12),
		Vector3i(8, -16, 0x14), Vector3i(8, 0, 0x16),
		Vector3i(16, -16, 0x18), Vector3i(16, 0, 0x1A),
		Vector3i(24, -8, 0x1C), Vector3i(32, -8, 0x1E),
	],
	[
		Vector3i(-40, -16, 0x00), Vector3i(-40, 0, 0x02),
		Vector3i(-32, -16, 0x04), Vector3i(-32, 0, 0x06),
		Vector3i(-24, -8, 0x08), Vector3i(-16, -8, 0x0A),
		Vector3i(-8, -16, 0x0C), Vector3i(-8, 0, 0x0E),
		Vector3i(0, -16, 0x10), Vector3i(0, 0, 0x12),
		Vector3i(8, -16, 0x14), Vector3i(8, 0, 0x16),
		Vector3i(16, -16, 0x18), Vector3i(16, 0, 0x1A),
		Vector3i(24, -16, 0x1C), Vector3i(32, -16, 0x1E),
	],
]
## `SpriteAnimOAMData`'s own rows for the five sets: which picture, and the
## `spriteanimoam` vtile offset added to every tile in it. Gold's five are five
## pictures at offset zero; Silver's are two pictures at four offsets.
const BIRD_SETS_GOLD: Array[Vector2i] = [
	Vector2i(0, 0x00), Vector2i(1, 0x00), Vector2i(2, 0x00),
	Vector2i(3, 0x00), Vector2i(4, 0x00),
]
const BIRD_SETS_SILVER: Array[Vector2i] = [
	Vector2i(0, 0x00), Vector2i(0, 0x20), Vector2i(1, 0x40),
	Vector2i(1, 0x60), Vector2i(0, 0x00),
]

## `.OAMData_GSTitleTrail`, which is not the same picture on the two cartridges.
## Gold's is one 8x16 object at `dbsprite -1, -1, 4, 4`, so its four pixels of
## offset take it half a tile up and left of the struct rather than a whole one;
## Silver's is two objects side by side at `-1, -1` and `0, -1` with no pixel
## offset, and its own tiles rather than a vtile base. Both are drawn through
## object palette 1.
const TRAIL_OAM_GOLD: Array[Vector3i] = [Vector3i(-4, -4, 0x00)]
const TRAIL_OAM_SILVER: Array[Vector3i] = [
	Vector3i(-8, -8, 0x00), Vector3i(0, -8, 0x02),
]
## `SPRITE_ANIM_OAMSET_GS_TITLE_TRAIL_1` and `_2` are Gold's one picture at vtile
## $f8 and $fa, which is what its frameset alternates. Silver's frameset reaches
## only `_1`, so nothing steps this there.
const TRAIL_TILES: Array[int] = [0x00, 0x02]
## `TitleScreen` copies the trail into `vTiles1 tile $78`, which the object
## layer addresses as tile $78 of the second sheet.
const TRAIL_PALETTE: int = 1
## `spriteanimoam $f8` and `$fa`: where those two tiles land in the object
## layer's own numbering, which is what a shadow-OAM byte holds. The bird and
## Crystal's crystal are both at the bottom of VRAM and count from zero.
const TRAIL_VRAM_BASE: int = 0xF8

## `TitleScreenGFX2` is loaded at `vTiles1` and `GFX1` at `vTiles2`, so a
## tilemap code below $80 is the top half and one at or above it the bottom.
const GS_TOP_FIRST_TILE: int = 0x80
## `FillTitleScreenPals`: attribute 1 over the top seven rows, 3 over the ten
## tiles of "VERSION" on row 6, and 4 over rows 12 and down. Everything else is
## palette 0.
const GS_TOP_ROWS: int = 7
const GS_TOP_PALETTE: int = 1
const GS_VERSION_ROW: int = 6
const GS_VERSION_AT: int = 5
const GS_VERSION_TILES: int = 10
const GS_VERSION_PALETTE: int = 3
const GS_BOTTOM_ROW: int = 12
const GS_BOTTOM_PALETTE: int = 4

var _profile: StringName = &"gold"
## Crystal's three strips, or Gold and Silver's four.
var _sheets: Dictionary = {}
var _widths: Dictionary = {}
var _background: Array[PackedColorArray] = []
var _object: Array[PackedColorArray] = []
var _tilemap: PackedByteArray = PackedByteArray()
var _drawn: PackedByteArray = PackedByteArray()
## Which pixels an object has already claimed this frame.
var _taken: PackedByteArray = PackedByteArray()
var _map: Image = null
var _map_indices: PackedByteArray = PackedByteArray()


## Null on a cache with no title art, which is the caller's cue to skip the
## phase rather than to run it blank.
static func from_data(data: GameData) -> Gen2TitlePage:
	if data == null:
		return null
	var out := Gen2TitlePage.new()
	out._profile = data.id
	var names: Array[String] = ["title_logo_bottom", "title_logo_top", "title_trail", "title_bird"]
	if data.id == RomRegistry.CRYSTAL:
		names = ["title_suicune", "title_logo", "title_crystal"]
	for name: String in names:
		var sheet: Dictionary = data.tile_sheet(name)
		var indices: PackedByteArray = data.tile_indices(name)
		if sheet.is_empty() or indices.is_empty():
			return null
		out._sheets[name] = indices
		out._widths[name] = int(sheet.get("width", 0))

	if data.id == RomRegistry.CRYSTAL:
		# `CopyBytes` writes sixteen palettes from `wBGPals1`, and `wOBPals1` is
		# the eight straight after it, so the run is the background's eight and
		# then the objects'.
		var all: Array[PackedColorArray] = data.title_palettes("palettes")
		out._background = all.slice(0, CRYSTAL_BG_PALETTES)
		out._object = all.slice(CRYSTAL_BG_PALETTES)
	else:
		out._background = data.title_palettes("bg_palettes")
		out._object = data.title_palettes("ob_palettes")
		out._tilemap = data.title_tilemap()
		if out._tilemap.is_empty():
			return null
	if out._background.is_empty() or out._object.is_empty():
		return null
	return out


## The whole 160x144 screen for one frame of [param scene].
##
## The background is built at the BG map's own 256 pixels across and then
## sampled through the scroll, because that map wraps: a cloud band walking left
## brings the map's own right-hand columns back round rather than leaving a gap.
func draw(scene: Gen2TitleScene) -> Image:
	var width: int = COLUMNS * TILE
	var height: int = ROWS * TILE
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var blank: Color = _background[0][0] if not _background[0].is_empty() else Color.BLACK
	image.fill(blank)
	# What colour index each pixel of the background ended up as, which is the
	# only thing `OAM_PRIO` reads: a sprite behind the background shows through
	# colour 0 and nowhere else.
	_drawn.resize(width * height)
	_drawn.fill(0)
	if scene == null:
		return image

	_map = Image.create_empty(MAP_WIDTH, MAP_HEIGHT, false, Image.FORMAT_RGBA8)
	_map.fill(blank)
	_map_indices.resize(MAP_WIDTH * MAP_HEIGHT)
	_map_indices.fill(0)
	if _profile == RomRegistry.CRYSTAL:
		_draw_crystal_background(scene)
	else:
		_draw_gs_background()
	_compose(image, scene)
	_draw_copyright_window(image, scene)

	# The lower OAM index wins a pixel, so a slot only paints where no earlier
	# one did: Gold's bird is copied into the last struct, so every trail spawned
	# after it still takes a lower slot and covers it.
	_taken.resize(width * height)
	_taken.fill(0)
	for entry: Dictionary in shadow_oam(scene):
		_draw_sprite(image, entry)
	return image


## Every object expanded into the shadow OAM the hardware would hold, in struct
## order, which is the z-order `PlaySpriteAnimations` walks. `y` and `x` are the
## OAM bytes and `tile` the byte `dbsprite` writes; the screen is in 8x16 mode,
## so one entry is two tiles and the second is `tile + 1`. [method draw] blits
## this same list rather than re-deriving it, and a trace of it compares to a
## cartridge's own buffer line for line.
func shadow_oam(scene: Gen2TitleScene) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if scene == null:
		return out
	for sprite: Dictionary in scene.sprites():
		var kind: StringName = StringName(sprite["kind"])
		var at: Vector2i = sprite["at"]
		var name: String = _sprite_sheet(kind)
		for part: Vector3i in _oam_set(kind, int(sprite.get("tile", 0))):
			# `UpdateAnimFrame` stops at `wShadowOAMEnd` rather than growing.
			if out.size() >= SHADOW_OAM_SPRITES:
				return out
			var tile: int = int(sprite.get("tile", 0)) if name == "title_crystal" else part.z
			out.append({
				# `UpdateAnimFrame` builds every position with `add`, so an
				# offset past the screen wraps rather than clamping.
				"y": (at.y + part.y) & 0xFF,
				"x": (at.x + part.x) & 0xFF,
				"tile": (_vram_base(name) + tile) & 0xFF,
				"palette": int(sprite.get("palette", 0)),
				"behind": bool(sprite.get("behind", false)),
				"sheet": name,
			})
	return out


## The BG map through `hSCX` and whatever `wLYOverrides` is writing over it, one
## scanline at a time.
func _compose(image: Image, scene: Gen2TitleScene) -> void:
	var offsets: PackedInt32Array = scene.line_offsets()
	var base: int = scene.scroll_x()
	var scy: int = scene.scroll_y()
	for y: int in image.get_height():
		# `LCD` fires on `STAT_MODE_0` and writes `wLYOverrides[rLY]` to rSCX,
		# which the line after it is drawn with; `VBlank_Cutscene` writes entry
		# zero, so the first two lines share it.
		var line: int = maxi(y - 1, 0)
		var shift: int = offsets[line] if line < offsets.size() else base
		var row: int = posmod(y + scy, MAP_HEIGHT)
		for x: int in image.get_width():
			var from: int = posmod(x + shift, MAP_WIDTH)
			image.set_pixel(x, y, _map.get_pixel(from, row))
			_drawn[y * image.get_width() + x] = _map_indices[row * MAP_WIDTH + from]


## The window layer, which on this screen is the copyright line and nothing
## else: one row of `vBGMap1` at `hWX` 7, so it starts at column 0 and covers
## whatever the background left under it.
func _draw_copyright_window(image: Image, scene: Gen2TitleScene) -> void:
	var top: int = scene.window_y()
	if top >= image.get_height():
		return
	var palette: PackedColorArray = _palette(_background, CRYSTAL_COPYRIGHT_PALETTE)
	if palette.is_empty():
		return
	for index: int in CRYSTAL_COPYRIGHT_TILES:
		_blit_window_tile(
			image, palette, CRYSTAL_COPYRIGHT_TILE + index,
			Vector2i((CRYSTAL_COPYRIGHT_AT + index) * TILE, top)
		)


## `DrawTitleGraphic` over the logo, then `LoadSuicuneFrame`'s own six rows of
## eight. `hSCX` is the entrance's own scroll and moves the whole background.
func _draw_crystal_background(scene: Gen2TitleScene) -> void:
	for row: int in CRYSTAL_LOGO_ROWS:
		var palette: PackedColorArray = _palette(
			_background, CRYSTAL_LOGO_PALETTES[row]
		)
		for column: int in CRYSTAL_LOGO_COLUMNS:
			_blit_background(
				"title_logo", row * CRYSTAL_LOGO_COLUMNS + column,
				Vector2i(CRYSTAL_LOGO_AT.x + column, CRYSTAL_LOGO_AT.y + row) * TILE,
				palette
			)
	# The eleven tiles of "CRYSTAL VERSION" sit on the logo's last row and take a
	# palette of their own.
	for index: int in CRYSTAL_VERSION_TILES:
		var column: int = CRYSTAL_VERSION_AT + index
		_blit_background(
			"title_logo",
			(CRYSTAL_VERSION_ROW - CRYSTAL_LOGO_AT.y) * CRYSTAL_LOGO_COLUMNS + column,
			Vector2i(column, CRYSTAL_VERSION_ROW) * TILE,
			_palette(_background, CRYSTAL_VERSION_PALETTE)
		)
	for placed: Vector3i in scene.suicune_tiles():
		_blit_background(
			"title_suicune", placed.z, Vector2i(placed.x, placed.y) * TILE,
			_palette(_background, CRYSTAL_SUICUNE_PALETTE)
		)


## `LoadTitleScreenTilemap` and `FillTitleScreenPals`: the stored map straight
## into the BG, and one palette per band of rows.
func _draw_gs_background() -> void:
	for row: int in ROWS:
		for column: int in RomLayout.TITLE_TILEMAP_COLUMNS:
			var at: int = row * RomLayout.TITLE_TILEMAP_COLUMNS + column
			if at >= _tilemap.size():
				continue
			var code: int = _tilemap[at]
			var name: String = "title_logo_bottom"
			var tile: int = code
			if code >= GS_TOP_FIRST_TILE:
				name = "title_logo_top"
				tile = code - GS_TOP_FIRST_TILE
			_blit_background(
				name, tile, Vector2i(column, row) * TILE,
				_palette(_background, _gs_palette(row, column))
			)


func _gs_palette(row: int, column: int) -> int:
	if row == GS_VERSION_ROW and column >= GS_VERSION_AT \
			and column < GS_VERSION_AT + GS_VERSION_TILES:
		return GS_VERSION_PALETTE
	if row < GS_TOP_ROWS:
		return GS_TOP_PALETTE
	if row >= GS_BOTTOM_ROW:
		return GS_BOTTOM_PALETTE
	return 0


## One shadow-OAM entry, drawn through an object palette whose first colour is
## transparent. The screen is in 8x16 mode, so the entry's tile is the top half
## and the one after it the bottom.
func _draw_sprite(image: Image, entry: Dictionary) -> void:
	var palette: PackedColorArray = _palette(_object, int(entry["palette"]))
	if palette.size() <= TRANSPARENT_INDEX:
		return
	var to := Vector2i(int(entry["x"]) - OAM_ORIGIN.x, int(entry["y"]) - OAM_ORIGIN.y)
	var sheet: String = String(entry["sheet"])
	for half: int in OBJECT_HEIGHT:
		_blit_sprite_tile(
			image, palette, sheet, int(entry["tile"]) - _vram_base(sheet) + half,
			Vector2i(to.x, to.y + half * TILE), bool(entry["behind"])
		)


## Where a sheet sits in the object layer's numbering, which shadow OAM counts
## from and the sheets themselves do not.
func _vram_base(sheet: String) -> int:
	return TRAIL_VRAM_BASE if sheet == "title_trail" else 0


func _sprite_sheet(kind: StringName) -> String:
	match kind:
		Gen2TitleScene.SPRITE_CRYSTAL:
			return "title_crystal"
		Gen2TitleScene.SPRITE_TRAIL:
			return "title_trail"
		_:
			return "title_bird"


## The `dbsprite` run behind one object. The crystal's is a single 8x16 part,
## the trail's the one `.OAMData_GSTitleTrail` names, and the bird's whichever of
## the five `.OAMData_GSIntroHoOh*` sets its frameset has reached.
func _oam_set(kind: StringName, frame: int) -> Array[Vector3i]:
	match kind:
		Gen2TitleScene.SPRITE_CRYSTAL:
			return [Vector3i(0, 0, 0)] as Array[Vector3i]
		Gen2TitleScene.SPRITE_TRAIL:
			if _profile == RomRegistry.SILVER:
				return TRAIL_OAM_SILVER
			# Gold's frameset alternates the two vtile bases over one picture.
			var step: int = TRAIL_TILES[clampi(frame, 0, TRAIL_TILES.size() - 1)]
			var trail: Array[Vector3i] = []
			for part: Vector3i in TRAIL_OAM_GOLD:
				trail.append(Vector3i(part.x, part.y, part.z + step))
			return trail
		_:
			var sets: Array[Vector2i] = (
				BIRD_SETS_GOLD if _profile == RomRegistry.GOLD else BIRD_SETS_SILVER
			)
			var pictures: Array[Array] = (
				BIRD_OAM if _profile == RomRegistry.GOLD else LUGIA_OAM
			)
			var row: Vector2i = sets[clampi(frame, 0, sets.size() - 1)]
			var out: Array[Vector3i] = []
			for part: Vector3i in pictures[row.x]:
				out.append(Vector3i(part.x, part.y, part.z + row.y))
			return out


func _palette(run: Array[PackedColorArray], index: int) -> PackedColorArray:
	if index < 0 or index >= run.size():
		return PackedColorArray()
	return run[index]


## One tile into the BG map, through the palette its attribute names. The map is
## what wraps and what the scroll is applied to; nothing here knows the screen.
func _blit_background(
	name: String, tile: int, at: Vector2i, palette: PackedColorArray
) -> void:
	var tiles: PackedByteArray = _sheets.get(name, PackedByteArray())
	var stride: int = int(_widths.get(name, 0))
	if stride <= 0 or tile < 0 or palette.is_empty():
		return
	for y: int in TILE:
		var target_y: int = at.y + y
		if target_y < 0 or target_y >= _map.get_height():
			continue
		for x: int in TILE:
			var target_x: int = at.x + x
			if target_x < 0 or target_x >= MAP_WIDTH:
				continue
			var from: int = y * stride + tile * TILE + x
			if from < 0 or from >= tiles.size():
				continue
			var value: int = tiles[from]
			if value >= palette.size():
				continue
			_map.set_pixel(target_x, target_y, palette[value])
			_map_indices[target_y * MAP_WIDTH + target_x] = value


## One window tile straight onto the screen. The window is drawn over the
## background and under nothing, so it needs neither the map's wrap nor a claim
## on [member _taken].
func _blit_window_tile(
	image: Image, palette: PackedColorArray, tile: int, at: Vector2i
) -> void:
	var tiles: PackedByteArray = _sheets.get("title_logo", PackedByteArray())
	var stride: int = int(_widths.get("title_logo", 0))
	if stride <= 0:
		return
	for y: int in TILE:
		var target_y: int = at.y + y
		if target_y < 0 or target_y >= image.get_height():
			continue
		for x: int in TILE:
			var target_x: int = at.x + x
			if target_x < 0 or target_x >= image.get_width():
				continue
			var from: int = y * stride + tile * TILE + x
			if from < 0 or from >= tiles.size():
				continue
			var value: int = tiles[from]
			if value >= palette.size():
				continue
			image.set_pixel(target_x, target_y, palette[value])


## One object tile onto the drawn screen, clipped per axis so a sprite hanging
## off an edge cannot wrap onto the opposite one. [param behind] is `OAM_PRIO`,
## which lets the background's colours 1 to 3 cover the object.
func _blit_sprite_tile(
	image: Image, palette: PackedColorArray, name: String, tile: int, at: Vector2i,
	behind: bool = false
) -> void:
	var tiles: PackedByteArray = _sheets.get(name, PackedByteArray())
	var stride: int = int(_widths.get(name, 0))
	if stride <= 0 or tile < 0:
		return
	for y: int in TILE:
		var target_y: int = at.y + y
		if target_y < 0 or target_y >= image.get_height():
			continue
		for x: int in TILE:
			var target_x: int = at.x + x
			if target_x < 0 or target_x >= image.get_width():
				continue
			var from: int = y * stride + tile * TILE + x
			if from < 0 or from >= tiles.size():
				continue
			var value: int = tiles[from]
			if value == TRANSPARENT_INDEX or value >= palette.size():
				continue
			var at_pixel: int = target_y * image.get_width() + target_x
			if _taken[at_pixel] != 0:
				continue
			# The claim comes first: an object that loses the pixel to the
			# background still wins it against the objects behind it.
			_taken[at_pixel] = 1
			if behind and _drawn[at_pixel] != 0:
				continue
			image.set_pixel(target_x, target_y, palette[value])
