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


## `MonFaintedAnimation`'s own block, which is not the picture's: seven columns
## from one left of it, and seven rows ending one below, so the picture sinks
## through a margin rather than out of its own frame.
## `PlayerMonFaintedAnimation` and `EnemyMonFaintedAnimation` name the two.
const FAINT_AT: Dictionary = {false: Vector2i(12, 0), true: Vector2i(1, 5)}
const FAINT_COLUMNS: int = 7
const FAINT_ROWS: int = 7
## `ld b, 7` outer, each spending `ld c, 2 / DelayFrames`.
const FAINT_STEPS: int = 7
const FAINT_STEP_FRAMES: int = 2


## The map a battle sits at: both pictures whole, blank everywhere else.
static func seeded() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(COLUMNS * ROWS)
	out.fill(BLANK_TILE)
	stamp(out, false)
	stamp(out, true)
	return out


## One outer step of `MonFaintedAnimation`: the block's rows each take the one
## above, and its top row is blanked with the routine's own seven spaces. Seven
## of these sink the whole picture off its square.
static func faint_step(map: PackedByteArray, player_side: bool) -> void:
	if map.size() != COLUMNS * ROWS:
		return
	var at: Vector2i = FAINT_AT[player_side]
	for index: int in FAINT_ROWS - 1:
		var row: int = at.y + FAINT_ROWS - 1 - index
		var above: int = row - 1
		for column: int in FAINT_COLUMNS:
			var x: int = at.x + column
			if x < 0 or x >= COLUMNS or row < 0 or row >= ROWS:
				continue
			map[row * COLUMNS + x] = (
				map[above * COLUMNS + x] if above >= 0 else BLANK_TILE
			)
	for column: int in FAINT_COLUMNS:
		var x: int = at.x + column
		if x < 0 or x >= COLUMNS or at.y < 0 or at.y >= ROWS:
			continue
		map[at.y * COLUMNS + x] = BLANK_TILE


## `SlideBattlePicOut`, which is not the picture's box either: seven rows from
## one above the player's, and the whole of the enemy's, shifted a column at a
## time until the picture is off the screen.
##
## `DoBattle`'s `hlcoord 1, 5 / ld a, 9` walks the player's left and
## `ResetEnemyBattleVars`' `hlcoord 18, 0 / ld a, 8` walks the enemy's right, and
## the count is both how many columns are touched and how many steps it takes.
const SLIDE_AT: Dictionary = {false: Vector2i(18, 0), true: Vector2i(1, 5)}
const SLIDE_ROWS: int = 7
const SLIDE_STEPS: Dictionary = {false: 8, true: 9}
const SLIDE_STEP_FRAMES: int = 2


## One outer step of `SlideBattlePicOut`: every touched cell takes its
## neighbour's on the side the picture is leaving towards, which is `.back`'s
## `ld a, [hld] / ld [hli], a` for the player and `.forward`'s
## `ld a, [hli] / ld [hld], a` for the enemy.
static func slide_step(map: PackedByteArray, player_side: bool) -> void:
	if map.size() != COLUMNS * ROWS:
		return
	var at: Vector2i = SLIDE_AT[player_side]
	var count: int = int(SLIDE_STEPS[player_side])
	for row_index: int in SLIDE_ROWS:
		var y: int = at.y + row_index
		if y < 0 or y >= ROWS:
			continue
		for index: int in count:
			# The player's walk reads to the right of what it writes; the
			# enemy's reads to the left of it.
			var to: int = at.x + index - 1 if player_side else at.x - index + 1
			var from: int = at.x + index if player_side else at.x - index
			if to < 0 or to >= COLUMNS or from < 0 or from >= COLUMNS:
				continue
			map[y * COLUMNS + to] = map[y * COLUMNS + from]


## `InitBattleDisplay`'s `hlcoord 1, 5 / lb bc, 3, 7 / ClearBox`, which runs
## between `CopyBackpic` and the slide and takes the top two tile rows of the
## player's back pic off the map.
##
## It is what makes the slide's eighteen sprites necessary rather than a second
## copy of the same picture: those rows fall in the band the enemy's own scroll
## owns, so the background cannot carry them and `.LoadTrainerBackpicAsOAM`
## does. `PlaceGraphic` puts the whole pic back when the slide returns.
const INTRO_CLEAR_AT: Vector2i = Vector2i(1, 5)
const INTRO_CLEAR_COLUMNS: int = 7
const INTRO_CLEAR_ROWS: int = 3


static func clear_intro_box(map: PackedByteArray) -> void:
	if map.size() != COLUMNS * ROWS:
		return
	for row: int in INTRO_CLEAR_ROWS:
		var y: int = INTRO_CLEAR_AT.y + row
		if y < 0 or y >= ROWS:
			continue
		for column: int in INTRO_CLEAR_COLUMNS:
			var x: int = INTRO_CLEAR_AT.x + column
			if x < 0 or x >= COLUMNS:
				continue
			map[y * COLUMNS + x] = BLANK_TILE


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
