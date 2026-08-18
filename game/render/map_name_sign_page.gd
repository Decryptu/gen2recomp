class_name Gen2MapNameSignPage
extends RefCounted

## `PlaceMapNameFrame` and `PlaceMapNameCenterAlign`
## (engine/events/map_name_sign.asm): the sign a map entry raises, drawn out of
## `MapEntryFrameGFX`'s own fourteen tiles with the landmark's name centred on
## its lower interior row.
##
## Four rows of the window, which the hardware can only start at a scanline and
## run to the bottom of the screen from: `rWY` $70 is what puts the sign in the
## bottom four rows rather than the top.
##
## Crystal's own screen. Gold and Silver ship neither `InitMapNameSign` nor the
## sheet, so a cache without it renders nothing at all.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 4

## `PlaceMapNameSign`'s `ld a, $70 / ldh [rWY]`, in pixels down the screen.
const TOP: int = 0x70

## Offsets from `MAP_NAME_SIGN_START`, which is where `LoadMapNameSignGFX`
## requests the sheet: the strip is stored in the cartridge's order, so each is
## its index in it. Tile 0 is named by nothing.
const TILE_TOP_LEFT: int = 1
const TILE_TOP: int = 2
const TILE_TOP_RIGHT: int = 4
const TILE_LEFT_UPPER: int = 5
const TILE_LEFT_LOWER: int = 6
const TILE_BOTTOM_LEFT: int = 7
const TILE_BOTTOM: int = 8
const TILE_BOTTOM_RIGHT: int = 10
const TILE_RIGHT_UPPER: int = 11
const TILE_RIGHT_LOWER: int = 12
const TILE_INTERIOR: int = 13

## `PlaceMapNameCenterAlign`'s `hlcoord 0, 2`: the name sits on the second
## interior row, not the first.
const NAME_ROW: int = 2


## `PAL_BG_TEXT`, the slot `InitMapSignAttrmap` writes over every tile of the
## sign. On a map that is the map's OWN palette 7, which `LoadMapPalettes` fills
## out of `bg_tiles.pal`'s per-environment, per-time-of-day "text" row: cream,
## cream, brown, black, which is what makes the sign read as wood. The blue
## `Palette_TextBG7` this used to draw with is `LoadOW_BGPal7`'s, and nothing in
## `MapSetupScript_Connection` or `RefreshMapSprites` runs that before the sign
## is placed.
const PAL_BG_TEXT: int = 7


## The sign holding [param name], or null when the cache carries no sheet, no
## font or no palette, which is every Gold and Silver cache.
##
## [param environment] and [param time_of_day] are the map's, since the slot the
## sign is drawn through is one of the eight the map loaded.
static func render(
	data: GameData,
	name: String,
	environment: int = Gen2WorldAPI.ENVIRONMENT_TOWN,
	time_of_day: int = Gen2WorldPalette.TIME_MORNING,
) -> Image:
	if data == null:
		return null
	var sheet: PackedByteArray = data.tile_indices("map_entry_sign")
	if sheet.size() < RomLayout.MAP_ENTRY_SIGN_TILES * TILE * TILE:
		return null
	var font: Gen2Font = Gen2Font.from_data(data)
	if font == null:
		return null
	var slots: Array = Gen2WorldPalette.palette_slots(environment, time_of_day)
	var palette: PackedColorArray = data.world_palette(int(slots[PAL_BG_TEXT]))
	if palette.size() < 4:
		palette = Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	var width: int = COLUMNS * TILE
	var indices := PackedByteArray()
	indices.resize(width * ROWS * TILE)
	var strip_width: int = RomLayout.MAP_ENTRY_SIGN_TILES * TILE
	for row: int in ROWS:
		var tiles: Array[int] = _row_tiles(row)
		for column: int in COLUMNS:
			Gen2Font.blit_slot(
				sheet, strip_width, tiles[column], indices, width,
				column * TILE, row * TILE
			)
	font.draw_text(name, indices, width, name_column(name) * TILE, NAME_ROW * TILE)
	return Gen2PicImage.from_indices(indices, width, ROWS * TILE, palette)


## `PlaceMapNameCenterAlign`: `(SCREEN_WIDTH - length) >> 1`, where the length is
## `.GetNameLength`'s, one per character placed.
static func name_column(name: String) -> int:
	return maxi(0, (COLUMNS - Gen2Text.encoded_length(name)) >> 1)


## One row of the frame. The top and bottom rows are `.FillTopBottom`, whose loop
## writes its first pair from the incremented tile and every pair after that in
## twos: two of `tile + 1`, then four repeats of `tile, tile, tile + 1,
## tile + 1`.
static func _row_tiles(row: int) -> Array[int]:
	match row:
		0:
			return _edge_row(TILE_TOP_LEFT, TILE_TOP, TILE_TOP_RIGHT)
		ROWS - 1:
			return _edge_row(TILE_BOTTOM_LEFT, TILE_BOTTOM, TILE_BOTTOM_RIGHT)
		1:
			return _interior_row(TILE_LEFT_UPPER, TILE_RIGHT_UPPER)
	return _interior_row(TILE_LEFT_LOWER, TILE_RIGHT_LOWER)


static func _edge_row(left: int, fill: int, right: int) -> Array[int]:
	var out: Array[int] = [left, fill + 1, fill + 1]
	while out.size() < COLUMNS - 1:
		out.append_array([fill, fill, fill + 1, fill + 1])
	out.append(right)
	return out


static func _interior_row(left: int, right: int) -> Array[int]:
	var out: Array[int] = [left]
	for _column: int in COLUMNS - 2:
		out.append(TILE_INTERIOR)
	out.append(right)
	return out
