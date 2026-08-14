class_name Gen2CreditsPage
extends RefCounted

## The credits screen, on the tile grid the hardware uses.
##
## [Gen2Credits] owns the BG map and the attribute map, because
## `ConstructCreditsTilemap` and `ParseCredits` are what write them; this
## resolves a tile number to pixels and colours it through `CreditsPalettes`.
##
## `Credits`' own VRAM window:
##
## | Tiles | Contents |
## |---|---|
## | $00-$0f | the banner's current 4x4 mon cell, out of `CreditsMonsGFX` |
## | $20-$28 | `CreditsBorderGFX` |
## | $40-$4f | `TheEndGFX` |
## | $60-$7c | `CopyrightGFX`, where `LoadFontsBattleExtra` would put its strip |
## | $80+ | the font, untouched |
##
## The two border bands are the only thing that scrolls: `hLCDCPointer` is
## LOW(rSCX) and `Credits_LYOverride` fills eight scanlines of `wLYOverrides` per
## band, so those rows are sampled through an offset that walks two pixels a
## cycle.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = Gen2Credits.COLUMNS
const ROWS: int = Gen2Credits.ROWS
const WIDTH: int = COLUMNS * TILE

const BLANK_TILE: int = Gen2Credits.BLANK_TILE
## The banner cell is addressed by `Credits_LoadBorderGFX.Frames`' block rather
## than by tile number, so these sixteen are resolved against the block the frame
## is drawing and not against a strip position.
const BANNER_TILES: int = RomLayout.CREDITS_MON_FRAME_TILES

var font: Gen2Font = null
## The VRAM window, as one indices strip per tile number.
var _tiles: Dictionary = {}
## `CreditsMonsGFX` whole, which a block indexes into.
var _mons: PackedByteArray = PackedByteArray()
var _mons_width: int = 0


## Null on a cache with no credits graphics, which is the caller's cue not to
## open the screen.
static func from_data(data: GameData) -> Gen2CreditsPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null or data == null:
		return null
	var out := Gen2CreditsPage.new()
	out.font = glyphs
	out._load_sheet(data, "credits_border", RomLayout.CREDITS_BORDER_FIRST_CODE)
	out._load_sheet(data, "credits_the_end", RomLayout.CREDITS_THE_END_FIRST_CODE)
	out._load_sheet(data, "copyright", RomLayout.COPYRIGHT_FIRST_CODE)
	out._mons = data.tile_indices("credits_mons")
	out._mons_width = out._mons.size() / TILE if out._mons.size() > 0 else 0
	return out


func ready() -> bool:
	return font != null and _mons_width > 0 \
		and _tiles.has(RomLayout.CREDITS_BORDER_FIRST_CODE) \
		and _tiles.has(RomLayout.CREDITS_THE_END_FIRST_CODE)


## The whole 160x144 screen. [param state] is [method Gen2Credits.frame_state].
func image(data: GameData, state: Dictionary) -> Image:
	var map: PackedInt32Array = state.get("map", PackedInt32Array())
	var slots: PackedInt32Array = state.get("attributes", PackedInt32Array())
	var indices: PackedByteArray = compose(map, int(state.get("block", -1)))
	var out := Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	if map.size() < COLUMNS * ROWS or slots.size() < COLUMNS * ROWS:
		return out
	var scene: int = int(state.get("scene", 0))
	var palettes: Array = []
	for slot: int in [
		Gen2Credits.PALETTE_BANNER, Gen2Credits.PALETTE_BORDER, Gen2Credits.PALETTE_TEXT,
	]:
		palettes.append(palette(data, scene, slot))
	var scroll: int = int(state.get("scroll", 0))
	var scrolled: Array = state.get("scroll_rows", [])
	for row: int in ROWS:
		var shift: int = scroll if row in scrolled else 0
		for column: int in COLUMNS:
			var palette_colors: PackedColorArray = palettes[
				clampi(slots[row * COLUMNS + column], 0, palettes.size() - 1)
			]
			if palette_colors.is_empty():
				continue
			for y: int in TILE:
				for x: int in TILE:
					var at_x: int = column * TILE + x
					var at_y: int = row * TILE + y
					out.set_pixel(at_x, at_y, palette_colors[
						indices[at_y * WIDTH + (at_x + shift) % WIDTH]
					])
	return out


## `GetCreditsPalette`, whose Gold and Silver branch copies one four-colour
## palette into both of the slots it uses and then blacks out the border and text
## slot's last colour, which is the one the font's ink lands on.
func palette(data: GameData, scene: int, slot: int) -> PackedColorArray:
	var colors: PackedColorArray = data.credits_palette(scene, slot)
	if colors.size() < RomLayout.CREDITS_PALETTE_COLORS:
		return colors
	if slot == Gen2Credits.PALETTE_BORDER and not Gen2WorldState.is_crystal_profile(data):
		colors[RomLayout.CREDITS_PALETTE_COLORS - 1] = Color.BLACK
	return colors


## Resolves every tile number to pixels: the banner cell out of the mon run, the
## other three graphics out of the VRAM window, everything else out of the font.
func compose(map: PackedInt32Array, block: int) -> PackedByteArray:
	var indices := PackedByteArray()
	indices.resize(WIDTH * ROWS * TILE)
	if map.size() < COLUMNS * ROWS:
		return indices
	for row: int in ROWS:
		for column: int in COLUMNS:
			var tile: int = map[row * COLUMNS + column]
			var at := Vector2i(column * TILE, row * TILE)
			if tile < BANNER_TILES:
				_blit_banner(indices, block, tile, at)
			elif _tiles.has(tile):
				_blit(indices, _tiles[tile], at)
			elif tile != BLANK_TILE:
				font.draw_code(tile, indices, WIDTH, at.x, at.y, Gen2Text.FONT_MAIN)
	return indices


## `wCreditsBlankFrame2bpp` is sixteen tiles of solid colour 2, which is the
## background the four border mons are drawn on, so a cleared banner is that
## colour rather than blank.
func _blit_banner(
	indices: PackedByteArray, block: int, tile: int, at: Vector2i
) -> void:
	if block < 0:
		_fill(indices, at, Gen2Credits.BLANK_FRAME_INDEX)
		return
	var slot: int = block * BANNER_TILES + tile
	if (slot + 1) * TILE > _mons_width:
		return
	for y: int in TILE:
		for x: int in TILE:
			indices[(at.y + y) * WIDTH + at.x + x] = _mons[y * _mons_width + slot * TILE + x]


func _load_sheet(data: GameData, name: String, first_tile: int) -> void:
	var indices: PackedByteArray = data.tile_indices(name)
	if indices.is_empty():
		return
	var width: int = indices.size() / TILE
	@warning_ignore("integer_division")
	var count: int = width / TILE
	for tile: int in count:
		var cell := PackedByteArray()
		cell.resize(TILE * TILE)
		for y: int in TILE:
			for x: int in TILE:
				cell[y * TILE + x] = indices[y * width + tile * TILE + x]
		_tiles[first_tile + tile] = cell


func _blit(indices: PackedByteArray, cell: PackedByteArray, at: Vector2i) -> void:
	for y: int in TILE:
		for x: int in TILE:
			indices[(at.y + y) * WIDTH + at.x + x] = cell[y * TILE + x]


func _fill(indices: PackedByteArray, at: Vector2i, index: int) -> void:
	for y: int in TILE:
		for x: int in TILE:
			indices[(at.y + y) * WIDTH + at.x + x] = index
