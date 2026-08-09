class_name Gen2BattleScreenMap
extends RefCounted

## `wTilemap` as a battle leaves it: which tile of which battler's picture sits
## in each of the 20x18 cells.
##
## A battle animation does not draw a picture, it edits this map:
## `BattleBGEffect_HideMon` blanks a battler's box, `..._RemoveMon` shifts it a
## column at a time, `..._EnterMon` and `..._ReturnMon` stamp smaller
## arrangements of the same tiles, and `AppearUser` puts a whole one back. The
## screen owns the map, hands it to [Gen2BattleAnimBackground] before an
## animation and takes back whatever the animation left, which is why a Fly is
## still gone after its own animation ends.
##
## Node-free: a map is data, so what an effect did to one can be asserted
## headless.

const COLUMNS: int = Gen2BattleAnimBackground.SCREEN_WIDTH
const ROWS: int = Gen2BattleAnimBackground.SCREEN_HEIGHT

## `GetEnemyFrontpicCoords` and `GetPlayerBackpicCoords`: where each box sits and
## how many tiles square it is.
const ENEMY_AT: Vector2i = Vector2i(12, 0)
const PLAYER_AT: Vector2i = Vector2i(2, 6)
const ENEMY_SIDE: int = 7
const PLAYER_SIDE: int = 6

## Where each picture's tiles start in VRAM. `AppearUser` names both, `xor a` for
## the enemy and `ld a, $31` for the player, and `.BGSquares`' own offsets are
## counted from the same two.
const ENEMY_BASE_TILE: int = 0x00
const PLAYER_BASE_TILE: int = 0x31

const BLANK_TILE: int = Gen2BattleAnimBackground.BLANK_TILE


## The map a battle sits at: both pictures whole, blank everywhere else.
static func seeded() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(COLUMNS * ROWS)
	out.fill(BLANK_TILE)
	stamp(out, false)
	stamp(out, true)
	return out


## `PlaceGraphic` over one battler's box: a tile is
## [code]base + column * side + row[/code], the column-major order `.BGSquares`
## indexes and `AppearUser` restores.
static func stamp(map: PackedByteArray, player_side: bool) -> void:
	if map.size() != COLUMNS * ROWS:
		return
	var at: Vector2i = PLAYER_AT if player_side else ENEMY_AT
	var side: int = PLAYER_SIDE if player_side else ENEMY_SIDE
	var base: int = PLAYER_BASE_TILE if player_side else ENEMY_BASE_TILE
	for column: int in side:
		for row: int in side:
			var x: int = at.x + column
			var y: int = at.y + row
			if x < 0 or x >= COLUMNS or y < 0 or y >= ROWS:
				continue
			map[y * COLUMNS + x] = (base + column * side + row) & 0xFF
