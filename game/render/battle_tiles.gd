class_name Gen2BattleTiles
extends RefCounted

## The battle screen's tile page, assembled the way the hardware assembles it.
##
## A battle loads four sheets into one run of tile numbers, overlapping on
## purpose: the battle font goes in first and the two HUD borders over the middle
## of it, so thirteen of its tiles are never seen. This copies them in the same
## order into one strip and keeps the cartridge's tile numbers, so the constants
## below are the disassembly's own.
##
## Node-free like the rest of the drawing layer: indices into a buffer, so a
## whole HUD can be laid out and checked with no display.

const TILE: int = Gen2Font.TILE

## The first and last tile numbers a battle's page covers.
const FIRST_TILE: int = 0x55
const LAST_TILE: int = 0x78

## `StatsScreen_LoadFont` reaches further down: `LoadStatsScreenPageTilesGFX`
## parks seventeen tiles at $31, so the stats screen and the move screen assemble
## the same strip starting there.
const STATS_FIRST_TILE: int = RomLayout.STATS_FIRST_TILE
const STATS_TILES_AT: int = RomLayout.STATS_FIRST_TILE

## The page indicator squares `StatsScreen_LoadPageIndicators` writes as 2x2
## blocks: the small one for a page that is not open and the large one for the
## one that is.
const PAGE_SQUARE_SMALL: int = 0x36
const PAGE_SQUARE_LARGE: int = 0x3A
## `'⁂'`, the shiny marker, at this sheet's own charmap code.
const SHINY: int = 0x3F
## The vertical divider both `StatsScreen_PlaceVerticalDivider` and each page
## draw, and the two exp bar end caps the pink page closes its bar with.
const STATS_DIVIDER: int = 0x31
const EXP_BAR_LEFT_CAP: int = 0x40
const EXP_BAR_RIGHT_CAP: int = 0x41

## Where each sheet is copied to, in the order the battle loads them.
const EXP_BAR_AT: int = 0x55
const BATTLE_FONT_AT: int = 0x60
const ENEMY_HUD_AT: int = 0x6C
const PLAYER_HUD_AT: int = 0x73

## "HP:", which is two tiles because the colon shares one with the bar's cap.
const HP_LABEL: int = 0x60
## The nine fill levels, from empty to eight pixels lit.
const HP_BAR_EMPTY: int = 0x62
const HP_BAR_FULL: int = 0x6A
## The cap that closes a bar. The player's HUD uses the tile after it, which is
## the same shape hanging off the other side.
const HP_BAR_END: int = 0x6B
## The seven partial fills of the exp bar. Its empty and full tiles are the HP
## bar's own: only the middle of it is drawn from a sheet of its own.
const EXP_BAR_FIRST_PARTIAL: int = 0x55

## The level symbol, printed before a number.
const LEVEL: int = 0x6E

## The enemy's HUD hangs from a side on its left; the player's from one on its
## right. Both close with a bottom edge and two corners.
const ENEMY_SIDE: int = 0x6D
const ENEMY_CORNER: int = 0x74
const ENEMY_BOTTOM_RIGHT: int = 0x78
const PLAYER_SIDE: int = 0x73
const PLAYER_BOTTOM_LEFT: int = 0x6F
const PLAYER_BOTTOM_RIGHT: int = 0x77
const HUD_BOTTOM: int = 0x76

var _tiles: PackedByteArray = PackedByteArray()
var _width: int = 0
## The tile number the strip starts and ends at, which is the one thing a
## battle's page and the stats screen's disagree on.
var _first: int = FIRST_TILE
var _last: int = LAST_TILE


## Builds the page out of a cache, or null if the battle graphics are not in it.
static func from_data(data: GameData) -> Gen2BattleTiles:
	if data == null:
		return null

	var out := Gen2BattleTiles.new()
	out._first = FIRST_TILE
	out._last = LAST_TILE
	out._width = (LAST_TILE - FIRST_TILE + 1) * TILE
	out._tiles.resize(out._width * TILE)

	# In load order, so that where two sheets claim a tile the later one wins,
	# exactly as it does in video memory.
	var sheets: Array = [
		["exp_bar", EXP_BAR_AT], ["battle_font", BATTLE_FONT_AT],
		["enemy_hud", ENEMY_HUD_AT], ["player_hud", PLAYER_HUD_AT],
	]
	var loaded: int = 0
	for sheet: Array in sheets:
		var name: String = sheet[0]
		var meta: Dictionary = data.tile_sheet(name)
		if meta.is_empty():
			continue
		if out._copy(data.tile_indices(name), int(meta.get("width", 0)), int(sheet[1])):
			loaded += 1

	return out if loaded == sheets.size() else null


## `StatsScreen_LoadFont`'s own page, which the stats screen and the move screen
## share. It differs from a battle's in three ways: the stats sheet is loaded at
## $31, the exp bar contributes eight tiles rather than nine, and the player HUD
## border is scattered rather than copied whole (`HPExpBarBorderGFX` tile 0 to
## $78 and its tiles 3 and 4 to $76), which leaves $73 to $75 as the battle-extra
## font's own `<ID>`, `№` and `…`.
static func stats_page(data: GameData) -> Gen2BattleTiles:
	if data == null:
		return null

	var out := Gen2BattleTiles.new()
	out._first = STATS_FIRST_TILE
	out._last = LAST_TILE
	out._width = (LAST_TILE - STATS_FIRST_TILE + 1) * TILE
	out._tiles.resize(out._width * TILE)

	var sheets: Array = [
		["stats_tiles", STATS_TILES_AT, 0, RomLayout.STATS_TILES],
		["exp_bar", EXP_BAR_AT, 0, 8],
		["battle_font", BATTLE_FONT_AT, 0, -1],
		["enemy_hud", ENEMY_HUD_AT, 0, -1],
		["player_hud", 0x78, 0, 1],
		["player_hud", 0x76, 3, 2],
	]
	var loaded: int = 0
	for sheet: Array in sheets:
		var name: String = sheet[0]
		var meta: Dictionary = data.tile_sheet(name)
		if meta.is_empty():
			continue
		if out._copy(
			data.tile_indices(name), int(meta.get("width", 0)), int(sheet[1]),
			int(sheet[2]), int(sheet[3])
		):
			loaded += 1
	return out if loaded == sheets.size() else null


## One tile of the page, drawn at a pixel position in [param into].
func draw(tile: int, into: PackedByteArray, into_width: int, at_x: int, at_y: int) -> void:
	if tile < _first or tile > _last:
		return
	Gen2Font.blit_slot(_tiles, _width, tile - _first, into, into_width, at_x, at_y)


## Draws the same tile across a run of columns, which is what a HUD's bottom
## edge and an empty bar both are.
func draw_run(
	tile: int, count: int, into: PackedByteArray, into_width: int, at_x: int, at_y: int
) -> void:
	for i: int in count:
		draw(tile, into, into_width, at_x + i * TILE, at_y)


## The same tile down a run of rows, which is what every vertical divider on the
## stats screen is.
func draw_run_down(
	tile: int, count: int, into: PackedByteArray, into_width: int, at_x: int, at_y: int
) -> void:
	for i: int in count:
		draw(tile, into, into_width, at_x, at_y + i * TILE)


## [param from] and [param count] copy a run out of the middle of a sheet, which
## only `StatsScreen_LoadFont`'s scattered HUD border needs; -1 takes the rest.
func _copy(
	strip: PackedByteArray, strip_width: int, at_tile: int,
	from: int = 0, count: int = -1
) -> bool:
	if strip_width <= 0 or strip.size() < strip_width * TILE:
		return false

	@warning_ignore("integer_division")
	var available: int = strip_width / TILE - from
	var tiles: int = available if count < 0 else mini(count, available)
	if tiles <= 0:
		return false
	for tile: int in tiles:
		var to: int = (at_tile - _first + tile) * TILE
		if to < 0 or to + TILE > _width:
			continue
		for y: int in TILE:
			var at: int = y * strip_width + (from + tile) * TILE
			for x: int in TILE:
				_tiles[y * _width + to + x] = strip[at + x]
	return true
