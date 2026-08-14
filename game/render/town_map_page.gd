class_name Gen2TownMapPage
extends RefCounted

## The region map (`_TownMap` and `InitPokegearTilemap.Map`), on the tile grid
## the hardware uses.
##
## Like the trainer card this is a tilemap screen: `FillTownMap` writes one tile
## number per cell of the whole screen out of `JohtoMap` or `KantoMap`, the frame
## overwrites a few of them and only the landmark's name is printed text. So the
## page builds a map of tile numbers, colours it through `TownMapPals` and then
## resolves each number to pixels.
##
## `Pokegear_LoadGFX`'s VRAM window:
##
## | Tiles | Contents |
## |---|---|
## | $00-$2f | `TownMapGFX`, which is every tile a region map names |
## | $30-$5d | `PokegearGFX`, the card frame and its icons |
## | $60+ | the font, so printed text addresses glyphs as usual |

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

const TOWN_MAP_FIRST_TILE: int = RomLayout.TOWN_MAP_FIRST_TILE
const POKEGEAR_FIRST_TILE: int = RomLayout.POKEGEAR_FIRST_TILE
const BLANK_TILE: int = 0x7F

## `_TownMap.InitTilemap`'s corner box: a lid across the top left, a wall down
## its right and a bar along row 2. The region map shows through the rest.
const TOWN_MAP_FRAME_LEFT_TILE: int = 0x06
const TOWN_MAP_FRAME_TOP_TILE: int = 0x07
const TOWN_MAP_FRAME_RIGHT_TILE: int = 0x17
const TOWN_MAP_FRAME_WALL_TILE: int = 0x16
const TOWN_MAP_FRAME_JOINT_TILE: int = 0x26
const TOWN_MAP_FRAME_TOP_WIDTH: int = 6
const TOWN_MAP_FRAME_CORNER: Vector2i = Vector2i(7, 0)
## `ld bc, NAME_LENGTH` for the bar right of the joint.
const TOWN_MAP_FRAME_BAR_AT: Vector2i = Vector2i(8, 2)
const TOWN_MAP_FRAME_BAR_WIDTH: int = 11

## `InitPokegearTilemap.Map`'s single bar under the card icons.
const CARD_BAR_ROW: int = 2

## `Pokegear_FinishTilemap`. The eight cells left of the name box are blanked
## with the Pokegear sheet's own blank, then one 2x2 icon is stamped per owned
## card and the Pokegear's own icon over the corner.
const CARD_BLANK_TILE: int = 0x4F
const CARD_BLANK_WIDTH: int = 8
const CARD_ICONS: Array[Dictionary] = [
	{"card": &"map", "at": Vector2i(2, 0), "tile": 0x40},
	{"card": &"phone", "at": Vector2i(4, 0), "tile": 0x44},
	{"card": &"radio", "at": Vector2i(6, 0), "tile": 0x42},
]
const CARD_POKEGEAR_ICON_AT: Vector2i = Vector2i(0, 0)
const CARD_POKEGEAR_ICON_TILE: int = 0x46
## `.PlacePokegearCardIcon`'s `add $f` after two `inc a`, which is what puts the
## lower half of an icon sixteen tiles along rather than two.
const CARD_ICON_ROW_STRIDE: int = 16

## `PokegearMap_UpdateLandmarkName`: a 2x12 box cleared at (8,0), the name placed
## at (9,0) and the sheet's own marker left in the corner it opened.
const NAME_BOX_AT: Vector2i = Vector2i(8, 0)
const NAME_BOX_ROWS: int = 2
const NAME_BOX_COLUMNS: int = 12
const NAME_MARKER_TILE: int = 0x34
const NAME_AT: Vector2i = Vector2i(9, 0)
## `TownMap_ConvertLineBreakCharacters` rewrites the first of these as `<LF>`,
## which `LineFeedChar` answers by dropping one row at the string's own column.
const NAME_BREAK_CODES: Array[int] = [0x1F, 0x25]

## `PAL_TOWNMAP_CITY`, the one slot `FemalePokegearPals` changes.
const CITY_PALETTE: int = 3

var font: Gen2Font = null
## The VRAM window, as one indices strip per tile number.
var _tiles: Dictionary = {}


## [param data] supplies the glyphs and both graphics sheets; a cache without
## them answers null rather than drawing a screen of blanks.
static func from_data(data: GameData) -> Gen2TownMapPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null or data == null:
		return null
	var out := Gen2TownMapPage.new()
	out.font = glyphs
	out._load_sheet(data, "town_map", TOWN_MAP_FIRST_TILE, RomLayout.TOWN_MAP_TILES)
	out._load_sheet(data, "pokegear", POKEGEAR_FIRST_TILE, RomLayout.POKEGEAR_TILES)
	return out


func ready() -> bool:
	return font != null and _tiles.size() >= RomLayout.TOWN_MAP_TILES + RomLayout.POKEGEAR_TILES


func _load_sheet(data: GameData, name: String, first_tile: int, count: int) -> void:
	var indices: PackedByteArray = data.tile_indices(name)
	if indices.is_empty():
		return
	var width: int = indices.size() / TILE
	for tile: int in count:
		if (tile + 1) * TILE > width:
			break
		var cell := PackedByteArray()
		cell.resize(TILE * TILE)
		for y: int in TILE:
			for x: int in TILE:
				cell[y * TILE + x] = indices[y * width + tile * TILE + x]
		_tiles[first_tile + tile] = cell


## The whole screen as tile numbers, in the order the source writes them: the
## region map over everything, then the screen's own frame, then the name.
##
## [param cards] is `wPokegearFlags`, as the card names `Pokegear_FinishTilemap`
## tests; it is read only by the Pokegear card's frame.
func tilemap(
	region: PackedByteArray,
	name_codes: PackedByteArray,
	screen: StringName = Gen2TownMap.SCREEN_TOWN_MAP,
	cards: Array = [],
) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(COLUMNS * ROWS)
	map.fill(BLANK_TILE)
	for cell: int in mini(region.size(), map.size()):
		map[cell] = region[cell]
	if screen == Gen2TownMap.SCREEN_POKEGEAR_CARD:
		_draw_card_bar(map)
		_draw_name(map, name_codes)
		_draw_card_icons(map, cards)
	else:
		_draw_town_map_frame(map)
		_draw_name(map, name_codes)
	return map


func _draw_town_map_frame(map: PackedInt32Array) -> void:
	for column: int in TOWN_MAP_FRAME_TOP_WIDTH:
		_put(map, Vector2i(1 + column, 0), TOWN_MAP_FRAME_TOP_TILE)
	_put(map, Vector2i.ZERO, TOWN_MAP_FRAME_LEFT_TILE)
	_put(map, TOWN_MAP_FRAME_CORNER, TOWN_MAP_FRAME_RIGHT_TILE)
	_put(map, TOWN_MAP_FRAME_CORNER + Vector2i(0, 1), TOWN_MAP_FRAME_WALL_TILE)
	_put(map, TOWN_MAP_FRAME_CORNER + Vector2i(0, 2), TOWN_MAP_FRAME_JOINT_TILE)
	for column: int in TOWN_MAP_FRAME_BAR_WIDTH:
		_put(map, TOWN_MAP_FRAME_BAR_AT + Vector2i(column, 0), TOWN_MAP_FRAME_TOP_TILE)
	_put(map, Vector2i(COLUMNS - 1, TOWN_MAP_FRAME_BAR_AT.y), TOWN_MAP_FRAME_RIGHT_TILE)


func _draw_card_bar(map: PackedInt32Array) -> void:
	for column: int in range(1, COLUMNS - 1):
		_put(map, Vector2i(column, CARD_BAR_ROW), TOWN_MAP_FRAME_TOP_TILE)
	_put(map, Vector2i(0, CARD_BAR_ROW), TOWN_MAP_FRAME_LEFT_TILE)
	_put(map, Vector2i(COLUMNS - 1, CARD_BAR_ROW), TOWN_MAP_FRAME_RIGHT_TILE)


## `Pokegear_FinishTilemap`, which runs after the name is placed and so blanks
## only the eight cells left of the name box.
func _draw_card_icons(map: PackedInt32Array, cards: Array) -> void:
	for row: int in 2:
		for column: int in CARD_BLANK_WIDTH:
			_put(map, Vector2i(column, row), CARD_BLANK_TILE)
	for icon: Dictionary in CARD_ICONS:
		if StringName(icon["card"]) in cards:
			_draw_card_icon(map, icon["at"], int(icon["tile"]))
	_draw_card_icon(map, CARD_POKEGEAR_ICON_AT, CARD_POKEGEAR_ICON_TILE)


func _draw_card_icon(map: PackedInt32Array, at: Vector2i, tile: int) -> void:
	_put(map, at, tile)
	_put(map, at + Vector2i(1, 0), tile + 1)
	_put(map, at + Vector2i(0, 1), tile + CARD_ICON_ROW_STRIDE)
	_put(map, at + Vector2i(1, 1), tile + CARD_ICON_ROW_STRIDE + 1)


## `PokegearMap_UpdateLandmarkName` and `TownMap_ConvertLineBreakCharacters`
## together: the box is cleared, the name placed at (9,0) with its one break
## dropping a row, and the marker written into the corner afterwards.
func _draw_name(map: PackedInt32Array, name_codes: PackedByteArray) -> void:
	for row: int in NAME_BOX_ROWS:
		for column: int in NAME_BOX_COLUMNS:
			_put(map, NAME_BOX_AT + Vector2i(column, row), BLANK_TILE)
	var at: Vector2i = NAME_AT
	var broken: bool = false
	for code: int in name_codes:
		if not broken and code in NAME_BREAK_CODES:
			broken = true
			at = Vector2i(NAME_AT.x, NAME_AT.y + 1)
			continue
		_put(map, at, code)
		at.x += 1
	_put(map, NAME_BOX_AT, NAME_MARKER_TILE)


## `TownMapPals`, as one palette slot per tile.
func attributes(data: GameData, map: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(map.size())
	for cell: int in map.size():
		out[cell] = data.town_map_palette_of(map[cell])
	return out


## The whole screen as pixels, each tile coloured through the palette
## `TownMapPals` gave it. [param female] is Kris's own city colours.
##
## This cannot go through [method Gen2PicImage.from_indices] whole: the screen is
## six palettes at once.
func image(data: GameData, map: PackedInt32Array, female: bool = false) -> Image:
	var indices: PackedByteArray = compose(map)
	var slots: PackedInt32Array = attributes(data, map)
	var out := Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	var palettes: Array = []
	for slot: int in RomLayout.TOWN_MAP_PALETTES:
		palettes.append(data.town_map_palette(slot, female))
	for row: int in ROWS:
		for column: int in COLUMNS:
			var palette: PackedColorArray = palettes[
				clampi(slots[row * COLUMNS + column], 0, palettes.size() - 1)
			]
			if palette.is_empty():
				continue
			for y: int in TILE:
				for x: int in TILE:
					var at_x: int = column * TILE + x
					var at_y: int = row * TILE + y
					out.set_pixel(at_x, at_y, palette[
						clampi(indices[at_y * Gen2Screen.WIDTH + at_x], 0, palette.size() - 1)
					])
	return out


## Resolves every tile number to pixels: the two graphics sheets out of the VRAM
## window, everything else out of the font.
func compose(map: PackedInt32Array) -> PackedByteArray:
	var width: int = COLUMNS * TILE
	var indices := PackedByteArray()
	indices.resize(width * ROWS * TILE)
	for row: int in ROWS:
		for column: int in COLUMNS:
			var tile: int = map[row * COLUMNS + column]
			var at := Vector2i(column * TILE, row * TILE)
			if _tiles.has(tile):
				_blit(indices, width, _tiles[tile], at)
			elif tile != BLANK_TILE:
				font.draw_code(tile, indices, width, at.x, at.y, Gen2Text.FONT_MAIN)
	return indices


func _put(map: PackedInt32Array, at: Vector2i, tile: int) -> void:
	if at.x < 0 or at.y < 0 or at.x >= COLUMNS or at.y >= ROWS:
		return
	map[at.y * COLUMNS + at.x] = tile


func _blit(
	indices: PackedByteArray, width: int, cell: PackedByteArray, at: Vector2i
) -> void:
	for y: int in TILE:
		for x: int in TILE:
			indices[(at.y + y) * width + at.x + x] = cell[y * TILE + x]
