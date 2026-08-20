class_name Gen2Credits
extends RefCounted

## The credits (`engine/movie/credits.asm`), as the frame-driven state machine
## they are.
##
## `Credits_Jumptable` runs one entry per frame and loops back after thirteen, so
## a `CREDITS_WAIT` tick is thirteen frames and not one: `ParseCredits` is the
## first entry and spends a tick each time it comes round. The rest of the cycle
## is what moves. `Credits_UpdateGFXRequestPath` steps the banner's frame, twice
## a cycle on Crystal and once on Gold and Silver;`Credits_LYOverride` walks the
## two border bands sideways two pixels, down on Crystal and up on the other two;
## and the three `Credits_Next` entries behind a wait are the frames
## `UpdateBGMap` spends copying the tilemap to the BG map a third at a time.
##
## That copy is why this owns two maps rather than one. `.parse` clears the text
## region and places the next batch into `wTilemap` with `hBGMapMode` off, and
## only `CREDITS_WAIT` turns the copy back on: a batch ending on `CREDITS_WAIT2`
## or on `CREDITS_END` is written and never shown. The End stays on screen for
## exactly that reason, since the clear in front of `CREDITS_END` is never
## pushed.
##
## [Gen2CreditsPage] turns [method bg_map] into pixels; nothing here draws.

## `MUSIC_CREDITS` and the `MUSIC_POST_CREDITS` `.end` fades into, both the same
## number on all three cartridges.
const MUSIC_CREDITS: int = 0x24
const MUSIC_POST_CREDITS: int = 0x5C
## `ld a, 32 / ld [wMusicFade], a`.
const POST_CREDITS_FADE_FRAMES: int = 32

const COLUMNS: int = 20
const ROWS: int = 18
## `UpdateBGMap` copies `SCREEN_HEIGHT / 3` rows a frame, and `hBGMapThird`
## wraps, so a cycle whose wait leaves the copy on for four frames re-copies the
## top rows rather than stopping.
const THIRDS: int = 3
const THIRD_ROWS: int = ROWS / THIRDS

## `.Jumptable`'s own length, which is what makes a tick thirteen frames.
const CYCLE_FRAMES: int = 13
## `ParseCredits`, always the entry the cycle opens on.
const STEP_PARSE: int = 0
## The entries running `Credits_UpdateGFXRequestPath`.
const GFX_STEPS: Array[int] = [4, 10]
const GFX_STEPS_GOLD_SILVER: Array[int] = [5]
## `Credits_LYOverride` and its `dec a / dec a`, which Gold and Silver replace
## with `inc a / inc a`.
const LY_STEP: int = 6
const LY_STEP_GOLD_SILVER: int = 7
const LY_DELTA: int = -2
const LY_DELTA_GOLD_SILVER: int = 2

## `ConstructCreditsTilemap`. The screen is a banner of five 4x4 mon cells, a
## border band, the text region and a second border; Gold and Silver put a second
## banner under the lower border where Crystal gives the text four more rows.
const BANNER_ROWS: int = 4
const BANNER_COLUMNS: int = 4
const BLANK_TILE: int = 0x7F
## `DrawCreditsBorder`'s two bases, four tiles repeated five times across.
const BORDER_TOP_TILE: int = 0x24
const BORDER_BOTTOM_TILE: int = 0x20
const BORDER_TILES: int = 4
const BORDER_TOP_ROW: int = 4
const BORDER_BOTTOM_ROW: int = 17
const BORDER_BOTTOM_ROW_GOLD_SILVER: int = 13

## `.parse`'s `hlcoord 0, 5` and the rows it fills.
const TEXT_FIRST_ROW: int = 5
## `hlcoord 0, 6` plus `SCREEN_WIDTH * 2` per line, so a batch's lines sit two
## rows apart.
const TEXT_TOP_ROW: int = 6
const TEXT_LINE_SPACING: int = 2
## `.copyright`'s own `hlcoord 2, 6`; every other string starts at column 0.
const COPYRIGHT_COLUMN: int = 2

## `Credits_TheEnd`, sixteen tiles from $40 laid out eight across and two down.
const THE_END_TILE: int = 0x40
const THE_END_COLUMNS: int = 8
const THE_END_AT: Vector2i = Vector2i(6, 9)
const THE_END_AT_GOLD_SILVER: Vector2i = Vector2i(6, 8)

## `wAttrmap`'s three slots: the banner, the border bands and the text region.
## Gold and Silver give the border and the text one slot between them and the
## banners the other.
const PALETTE_BANNER: int = 0
const PALETTE_BORDER: int = 1
const PALETTE_TEXT: int = 2

## `PlacePOKe`, which prints `PlacePOKeText` rather than a tile: "#" is a
## dictionary entry in `PlaceNextChar`, not a glyph.
const CODE_POKE: int = 0x54
const POKE_TEXT: String = "POKé"
## `NextLineChar`, which drops two rows at the string's own starting column.
const CODE_NEXT_LINE: int = 0x4E

## `wCreditsBorderFrame`'s $ff, which `Credits_LoadBorderGFX.init` answers with
## the blank frame and leaves alone, so a cleared banner stays cleared.
const BLANK_FRAME: int = -1
## `ld de, `22222222`: the blank frame is sixteen tiles of colour 2, which is the
## background the four border mons are drawn on rather than an empty cell.
const BLANK_FRAME_INDEX: int = 2

## `Credits_HandleBButton`: the skip refuses until `wCreditsPos` has passed the
## header, so the version screen cannot be jumped over even on a replay.
const SKIP_FROM_POSITION: int = 0x0D

var _data: GameData = null
var _script: PackedByteArray = PackedByteArray()
var _copyright_index: int = -1
var _crystal: bool = true
## `wJumptableIndex`'s low nibble and its JUMPTABLE_EXIT_F.
var _step: int = STEP_PARSE
var _finished: bool = false
## `wCreditsPos` and `wCreditsTimer`.
var _position: int = 0
var _timer: int = 0
## `wCreditsBorderMon` and `wCreditsBorderFrame`.
var _scene: int = 0
var _frame: int = BLANK_FRAME
## Which sixteen-tile block of the mon run the banner draws, or -1 for
## `wCreditsBlankFrame2bpp`.
var _block: int = -1
## `wCreditsLYOverride`, the rSCX the two border bands are sampled through.
var _scroll: int = 0
## `wTilemap`, `wAttrmap` and the BG map the first is copied into.
var _tilemap := PackedInt32Array()
var _attributes := PackedInt32Array()
var _bg_map := PackedInt32Array()
## `hBGMapMode` and `hBGMapThird`.
var _copying: bool = false
var _third: int = 0
## `bit STATUSFLAGS_HALL_OF_FAME_F, b`: the credits cannot be skipped the first
## time they are watched.
var _skippable: bool = false


## [param skippable] is `STATUSFLAGS_HALL_OF_FAME_F`, which is set by the time
## the induction it follows has been through once. Null when the cache carries no
## credits script.
static func create(data: GameData, can_skip: bool = false) -> Gen2Credits:
	if data == null:
		return null
	var script: PackedByteArray = data.credits_script()
	if script.is_empty():
		return null
	var out := Gen2Credits.new()
	out._data = data
	out._script = script
	out._copyright_index = data.credits_index("copyright")
	out._crystal = Gen2WorldState.is_crystal_profile(data)
	out._skippable = can_skip
	out._construct()
	return out


func scene() -> int:
	return _scene


## The mon run block the banner draws this frame, or -1 while `CREDITS_CLEAR`
## holds it blank.
func banner_block() -> int:
	return _block


## The BG map, which is what is on screen: one tile number per cell.
func bg_map() -> PackedInt32Array:
	return _bg_map.duplicate()


## `wTilemap`, which is what has been written but not necessarily shown.
func tilemap() -> PackedInt32Array:
	return _tilemap.duplicate()


## `wAttrmap`, one palette slot per cell. Fixed by `ConstructCreditsTilemap` and
## never written again.
func attributes() -> PackedInt32Array:
	return _attributes.duplicate()


## The two rows `Credits_LYOverride` fills scanlines for, which are the border
## bands. The source's fills sit one scanline higher than the tile row, since the
## override for a line is written during the one before it.
func scroll_rows() -> Array[int]:
	return [BORDER_TOP_ROW, _bottom_border_row()]


## Whether `CREDITS_END` has run. The source keeps looping here until A is held,
## which is what [method may_finish] answers.
func finished() -> bool:
	return _finished


func scroll() -> int:
	return _scroll


func position() -> int:
	return _position


func timer() -> int:
	return _timer


## `wJumptableIndex`'s low nibble, which is the entry of the thirteen-frame cycle
## the next frame runs. Only `STEP_PARSE` spends a tick of the wait, so it is
## what separates a frame `Credits_HandleBButton` is the sole author of from one
## `ParseCredits` also takes from.
func step() -> int:
	return _step


func skippable() -> bool:
	return _skippable


## What [Gen2CreditsPage] needs to draw one frame.
func frame_state() -> Dictionary:
	return {
		"map": bg_map(),
		"attributes": attributes(),
		"scene": _scene,
		"block": _block,
		"scroll": _scroll,
		"scroll_rows": scroll_rows(),
	}


## One frame of `.execution_loop`: the B skip, the jumptable entry, then the
## VBlank behind `DelayFrame`.
##
## [param held] is `hJoypadDown`, since both of the loop's buttons are held
## states rather than presses. Returns the events the frame asked for, which is
## the two `PlayMusic` calls and nothing else.
func advance_frame(held: Array = []) -> Array:
	var events: Array = []
	if Gen2Button.B in held:
		_skip()
	var at_step: int = _step
	_step = STEP_PARSE if at_step >= CYCLE_FRAMES - 1 else at_step + 1
	if at_step == STEP_PARSE:
		events = _parse()
	elif at_step in _gfx_steps():
		_load_banner()
		## `Credits_UpdateGFXRequestPath` and `Credits_RequestGFX` both clear
		## `hBGMapMode`, which is what stops the copy after its three thirds.
		_copying = false
	elif at_step == _ly_step():
		_scroll = (_scroll + _ly_delta()) & 0xFF
	elif at_step == _prep_step():
		_copying = false
	_copy_third()
	return events


## Whether holding A now leaves, which `Credits_HandleAButton` only allows once
## the script has run out.
func may_finish(held: Array = []) -> bool:
	return _finished and Gen2Button.A in held


## `Credits_HandleBButton`, which burns one tick of the wait a frame rather than
## jumping anywhere.
func _skip() -> void:
	if not _skippable or _position < SKIP_FROM_POSITION or _timer <= 0:
		return
	_timer -= 1


## `UpdateBGMap.Tiles`, one third of the rows per VBlank while `hBGMapMode` is on.
func _copy_third() -> void:
	if not _copying:
		return
	var first: int = _third * THIRD_ROWS * COLUMNS
	for cell: int in THIRD_ROWS * COLUMNS:
		_bg_map[first + cell] = _tilemap[first + cell]
	_third = (_third + 1) % THIRDS


## `Credits_LoadBorderGFX`: the block the banner draws is the frame the counter
## holds, and the counter moves on afterwards. A cleared banner neither draws nor
## counts.
func _load_banner() -> void:
	if _frame == BLANK_FRAME:
		_block = -1
		return
	_block = _data.credits_frame_block(_scene, _frame)
	_frame = (_frame + 1) % RomLayout.CREDITS_SCENE_FRAMES


## `ParseCredits`. A tick is spent here, or the whole batch up to the next wait is
## read at once, which is why the strings between two waits appear together.
func _parse() -> Array:
	if _finished:
		return []
	if _timer > 0:
		_timer -= 1
		return []
	_clear_text()
	var events: Array = []
	while true:
		var command: int = _next()
		match command:
			RomLayout.CREDITS_END:
				_finished = true
				events.append({
					"type": &"music_fade_requested",
					"music": MUSIC_POST_CREDITS,
					"frames": POST_CREDITS_FADE_FRAMES,
				})
				return events
			RomLayout.CREDITS_WAIT:
				_timer = _next()
				_copying = true
				_third = 0
				return events
			RomLayout.CREDITS_WAIT2:
				## The same wait with no BG map update behind it, so the batch it
				## closes is written and never shown.
				_timer = _next()
				return events
			RomLayout.CREDITS_SCENE:
				_scene = _next() % RomLayout.CREDITS_SCENES
				_frame = 0
			RomLayout.CREDITS_CLEAR:
				_frame = BLANK_FRAME
			RomLayout.CREDITS_MUSIC:
				events.append({"type": &"music_requested", "music": MUSIC_CREDITS})
			RomLayout.CREDITS_THEEND:
				_draw_the_end()
			_:
				_place_string(command, _next())
	return events


## `.get`, which walks `wCreditsPos` a byte at a time and never turns back. A
## fixture that runs off its own end reads as `CREDITS_END`, so the parse loop
## always terminates; the importer refuses a script that does.
func _next() -> int:
	if _position >= _script.size():
		return RomLayout.CREDITS_END
	var byte: int = _script[_position]
	_position += 1
	return byte


## `.print`: the string's own column, [param line] lines down from row 6.
func _place_string(index: int, line: int) -> void:
	var column: int = COPYRIGHT_COLUMN if index == _copyright_index else 0
	var at := Vector2i(column, TEXT_TOP_ROW + line * TEXT_LINE_SPACING)
	for code: int in _data.credits_string(index):
		if code == CODE_NEXT_LINE:
			at = Vector2i(column, at.y + TEXT_LINE_SPACING)
			continue
		if code == CODE_POKE:
			for glyph: int in Gen2Text.encode(POKE_TEXT):
				_put(at, glyph)
				at.x += 1
			continue
		_put(at, code)
		at.x += 1


func _clear_text() -> void:
	for row: int in range(TEXT_FIRST_ROW, _bottom_border_row()):
		for column: int in COLUMNS:
			## `ld a, ' '`, which is the same $7f the region opened blank in.
			_put(Vector2i(column, row), BLANK_TILE)


func _draw_the_end() -> void:
	var at: Vector2i = THE_END_AT if _crystal else THE_END_AT_GOLD_SILVER
	for tile: int in RomLayout.CREDITS_THE_END_TILES:
		@warning_ignore("integer_division")
		var row: int = tile / THE_END_COLUMNS
		_put(
			at + Vector2i(tile % THE_END_COLUMNS, row),
			THE_END_TILE + tile
		)


## `ConstructCreditsTilemap`, run once: the banner cells, the two border bands,
## the blank text region and the attribute map, then a full copy to the BG map.
func _construct() -> void:
	_tilemap.resize(COLUMNS * ROWS)
	_attributes.resize(COLUMNS * ROWS)
	_tilemap.fill(BLANK_TILE)
	_attributes.fill(PALETTE_TEXT if _crystal else PALETTE_BORDER)
	_draw_banner(0)
	_draw_border(BORDER_TOP_ROW, BORDER_TOP_TILE)
	_draw_border(_bottom_border_row(), BORDER_BOTTOM_TILE)
	for row: int in BANNER_ROWS:
		_fill_attributes(row, PALETTE_BANNER)
	_fill_attributes(BORDER_TOP_ROW, PALETTE_BORDER)
	_fill_attributes(_bottom_border_row(), PALETTE_BORDER)
	if not _crystal:
		var second: int = _bottom_border_row() + 1
		_draw_banner(second)
		for row: int in BANNER_ROWS:
			_fill_attributes(second + row, PALETTE_BANNER)
	_bg_map = _tilemap.duplicate()


## `.InitTopPortion`: five copies of one 4x4 cell, numbered across then down.
func _draw_banner(first_row: int) -> void:
	for row: int in BANNER_ROWS:
		for column: int in COLUMNS:
			_put(
				Vector2i(column, first_row + row),
				row * BANNER_COLUMNS + column % BANNER_COLUMNS
			)


func _draw_border(row: int, base: int) -> void:
	for column: int in COLUMNS:
		_put(Vector2i(column, row), base + column % BORDER_TILES)


func _fill_attributes(row: int, slot: int) -> void:
	for column: int in COLUMNS:
		_attributes[row * COLUMNS + column] = slot


func _put(at: Vector2i, tile: int) -> void:
	if at.x < 0 or at.y < 0 or at.x >= COLUMNS or at.y >= ROWS:
		return
	_tilemap[at.y * COLUMNS + at.x] = tile


func _bottom_border_row() -> int:
	return BORDER_BOTTOM_ROW if _crystal else BORDER_BOTTOM_ROW_GOLD_SILVER


func _gfx_steps() -> Array[int]:
	return GFX_STEPS if _crystal else GFX_STEPS_GOLD_SILVER


func _ly_step() -> int:
	return LY_STEP if _crystal else LY_STEP_GOLD_SILVER


func _ly_delta() -> int:
	return LY_DELTA if _crystal else LY_DELTA_GOLD_SILVER


## `Credits_PrepBGMapUpdate`, the entry in front of the first graphics request.
func _prep_step() -> int:
	return _gfx_steps()[0] - 1
