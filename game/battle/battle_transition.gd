class_name Gen2BattleTransition
extends RefCounted

## `DoBattleTransition` (engine/battle/battle_transition.asm): what the overworld
## does between the encounter and the battle screen.
##
## Four animations, picked by the lead's level against the opponent's and by the
## environment, each of them a Poke Ball drawn over the map for a trainer, three
## passes of a palette flash, and then one of four ways of going black. The
## jumptable is walked one entry per frame, which is what `DoBattleTransition`'s
## own `.loop` does with its `DelayFrame`.
##
## Node-free: it answers with a screen of cells, a DMG palette order and a
## per-scanline offset, and the world screen draws those over whatever it was
## already drawing. Nothing here reaches a renderer, so a whole transition can be
## stepped and read headless.

const COLUMNS: int = 20
const ROWS: int = 18

## What a cell of [method cells] holds. `BATTLETRANSITION_SQUARE` and
## `..._BLACK` are the two tiles `LoadBattleTransitionGFX` loads, and a cell the
## transition has not written is the map showing through.
const CELL_NONE: int = 0
const CELL_SQUARE: int = 1
const CELL_BLACK: int = 2

## `%11100100`, the order that draws every colour as itself.
const IDENTITY: int = 0xE4

## `ld a, [wBattleMonLevel] / add 3`: the lead has to be more than this far under
## the opponent for the stronger pair of animations.
const STRONGER_MARGIN: int = 3

## `StartTrainerBattle_Flash.pals`, the thirteen `dc` bytes it walks two frames
## at a time. The last is not a palette: `cp %00000001` is what ends the pass.
const FLASH_PALETTES: Array[int] = [
	0xF9, 0xFE, 0xFF, 0xFE, 0xF9, 0xE4, 0x90, 0x40, 0x00, 0x40, 0x90, 0xE4, 0x01,
]
const FLASH_TERMINATOR: int = 0x01

## `PokeBallTransition`, the 16x16 overlay, one big-endian word per row.
const POKE_BALL: Array[int] = [
	0b0000001111000000, 0b0000111111110000, 0b0011110000111100, 0b0011000000001100,
	0b0110000000000110, 0b0110001111000110, 0b1100011000110011, 0b1111110000111111,
	0b1111110000111111, 0b1100011000110011, 0b0110001111000110, 0b0110000000000110,
	0b0011000000001100, 0b0011110000111100, 0b0000111111110000, 0b0000001111000000,
]
## `hlcoord 2, 1` and the sixteen rows `ld b, SCREEN_WIDTH - 4` walks.
const BALL_AT := Vector2i(2, 1)
const BALL_SIDE: int = 16

## The four animations, as the jumptable's own runs of scenes. `TRANS_STRONGER_F`
## is set when the lead is more than three levels under the opponent and
## `TRANS_NO_CAVE_F` when the environment is not a cave, and the pair indexes
## `StartTrainerBattle_DetermineWhichAnimation.StartingPoints`.
const SCENES: Array = [
	## BATTLETRANSITION_CAVE. `init` is `.InitGFX` in front of the jumptable
	## rather than an entry in it.
	[&"init", &"ball", &"bgmap", &"flash", &"flash", &"flash", &"next", &"wavy_setup", &"sine"],
	## BATTLETRANSITION_CAVE_STRONGER, which has no setup of its own
	[&"init", &"ball", &"bgmap", &"flash", &"flash", &"flash", &"next", &"zoom"],
	## BATTLETRANSITION_NO_CAVE
	[&"init", &"ball", &"bgmap", &"flash", &"flash", &"flash", &"next", &"spin_setup", &"spin"],
	## BATTLETRANSITION_NO_CAVE_STRONGER
	[&"init", &"ball", &"bgmap", &"flash", &"flash", &"flash", &"next", &"scatter_setup", &"scatter"],
]

## `StartTrainerBattle_SpinToBlack.spin_quadrants`: which corner a wedge is
## drawn from, which wedge, and where it starts. Bit 0 is
## `RIGHT_QUADRANT_F` and bit 1 `LOWER_QUADRANT_F`.
const UPPER_LEFT: int = 0
const UPPER_RIGHT: int = 1
const LOWER_LEFT: int = 2
const LOWER_RIGHT: int = 3
const SPIN_QUADRANTS: Array = [
	[UPPER_LEFT, 1, 1, 6], [UPPER_LEFT, 2, 0, 3], [UPPER_LEFT, 3, 1, 0],
	[UPPER_LEFT, 4, 5, 0], [UPPER_LEFT, 5, 9, 0],
	[UPPER_RIGHT, 5, 10, 0], [UPPER_RIGHT, 4, 14, 0], [UPPER_RIGHT, 3, 18, 0],
	[UPPER_RIGHT, 2, 19, 3], [UPPER_RIGHT, 1, 18, 6],
	[LOWER_RIGHT, 1, 18, 11], [LOWER_RIGHT, 2, 19, 14], [LOWER_RIGHT, 3, 18, 17],
	[LOWER_RIGHT, 4, 14, 17], [LOWER_RIGHT, 5, 10, 17],
	[LOWER_LEFT, 5, 9, 17], [LOWER_LEFT, 4, 5, 17], [LOWER_LEFT, 3, 1, 17],
	[LOWER_LEFT, 2, 0, 14], [LOWER_LEFT, 1, 1, 11],
]
## `.wedge1` to `.wedge5`, read as pairs: how many cells to black out along the
## row, then how many to step back before the next one. `-1` ends the wedge.
const WEDGES: Dictionary = {
	1: [2, 3, 5, 4, 9, -1],
	2: [1, 1, 2, 2, 4, 2, 4, 2, 3, -1],
	3: [2, 1, 3, 1, 4, 1, 4, 1, 4, 1, 3, 1, 2, 1, 1, 1, 1, -1],
	4: [4, 1, 4, 0, 3, 1, 3, 0, 2, 1, 2, 0, 1, -1],
	5: [4, 0, 3, 0, 3, 0, 2, 0, 2, 0, 1, 0, 1, 0, 1, -1],
}
## `ld c, 2 / DelayFrames` between wedges, and the three frames the walk spends
## after the last one.
const SPIN_STEP_FRAMES: int = 2
const SPIN_END_FRAMES: int = 3

## `StartTrainerBattle_ZoomToBlack.boxes`: width, height and the top-left corner
## of each, one `WaitBGMap` apart.
const ZOOM_BOXES: Array = [
	[4, 2, 8, 8], [6, 4, 7, 7], [8, 6, 6, 6], [10, 8, 5, 5], [12, 10, 4, 4],
	[14, 12, 3, 3], [16, 14, 2, 2], [18, 16, 1, 1], [20, 18, 0, 0],
]

## `StartTrainerBattle_SetUpForRandomScatterOutro`'s `ld a, $10`, and the twelve
## tiles a frame of `..._SpeckleToBlack` blacks out.
const SCATTER_FRAMES: int = 0x10
const SCATTER_PER_FRAME: int = 12

## `StartTrainerBattle_SineWave`'s own `cp $60`, and the two-scanline step its
## loop walks the screen with.
const SINE_FRAMES: int = 0x60
const SINE_STEP: int = 2
const SCREEN_LINES: int = 144

## The two frames `LoadPokeBallGraphics` spends before the next scene.
const BALL_FRAMES: int = 2

## `DoBattleTransition.InitGFX` before the jumptable, and `.done` after it.
##
## Both are runs of VRAM copies this port does at once: `ReanchorBGMap`,
## `Request2bpp` twice for the two tiles and again for the forty the BG map is
## filled with, `BattleStart_CopyTilemapAtOnce`, and then the palette wipe at the
## end. The counts are measured against a real cartridge rather than derived,
## because a `WaitBGMap` is worth whatever the copy in front of it left.
const LEAD_FRAMES: int = 19
const TAIL_FRAMES: int = 3

var _scene: Array = []
var _step: int = 0
var _counter: int = 0
var _sine_offset: int = 0
var _delay: int = 0
## Whether the scene that set [member _delay] had already handed on: a scene's
## own frames belong to it rather than to the one it hands to.
var _pending_next: bool = false
var _finished: bool = false
var _trainer: bool = false
var _darkness: bool = false
var _order: int = IDENTITY
var _ball_drawn: bool = false
var _cells: PackedByteArray = PackedByteArray()
var _sine: PackedByteArray = PackedByteArray()
var _rng: RandomNumberGenerator = null


## [param stronger] is `TRANS_STRONGER_F`, [param cave] the environment test,
## [param trainer] `wOtherTrainerClass`, [param darkness]
## `wTimeOfDayPalset`'s `DARKNESS_PALSET`, which is the one thing that skips the
## flash. [param sine] is `sine_table 32` as the cartridge stores it, which the
## wavy outro reads; the battle animations' own copy is the same table.
static func create(
	stronger: bool, cave: bool, trainer: bool, darkness: bool,
	rng: RandomNumberGenerator = null, sine: PackedByteArray = PackedByteArray()
) -> Gen2BattleTransition:
	var out := Gen2BattleTransition.new()
	out._scene = SCENES[(1 if stronger else 0) | (0 if cave else 2)]
	out._trainer = trainer
	out._darkness = darkness
	out._sine = sine
	out._rng = rng if rng != null else RandomNumberGenerator.new()
	out._cells = PackedByteArray()
	out._cells.resize(COLUMNS * ROWS)
	return out


## Which scene of the jumptable is running, for a test or a trace: `ball`,
## `bgmap`, `flash`, `next`, one of the four setups or one of the four outros.
func scene() -> StringName:
	if _finished or _step >= _scene.size():
		return &""
	return StringName(_scene[_step])


## `wJumptableIndex`'s exit bit.
func finished() -> bool:
	return _finished


## What the screen is holding: one entry per cell, [constant CELL_NONE] where the
## map is still showing.
func cells() -> PackedByteArray:
	return _cells


## The DMG order every background palette is drawn through, which is `wBGP` and
## `DmgToCgbBGPals`.
func palette_order() -> int:
	return _order


## Whether the Poke Ball is up, which is also when `.pal_loop` has put every
## background tile on `PAL_BG_TEXT` and `.copypals` has filled it.
func ball_drawn() -> bool:
	return _ball_drawn


## `wLYOverrides`, the per-scanline `rSCX` the wavy outro writes. Empty for the
## three that write none.
func raster_offsets() -> PackedInt32Array:
	var out := PackedInt32Array()
	if StringName(_scene[mini(_step, _scene.size() - 1)]) != &"sine" or _sine.is_empty():
		return out
	out.resize(SCREEN_LINES)
	var amplitude: int = _counter
	for line: int in SCREEN_LINES:
		out[line] = _sine_wave(_sine_offset + line * SINE_STEP, amplitude)
	return out


## One frame of `DoBattleTransition.loop`: one jumptable entry, then its
## `DelayFrame`. A scene that spends frames of its own answers for them here
## rather than running ahead.
func advance_frame() -> bool:
	if _delay > 0:
		_delay -= 1
		if _delay == 0 and _pending_next:
			_pending_next = false
			_step += 1
		return true
	if _finished:
		return false
	_run()
	return true


func _run() -> void:
	if _step >= _scene.size():
		_finished = true
		return
	match StringName(_scene[_step]):
		&"init":
			_delay = LEAD_FRAMES
			_next()
		&"ball":
			_load_poke_ball_graphics()
		&"bgmap":
			_counter = 0
			_next()
		&"flash":
			_flash()
		&"next":
			_next()
		&"wavy_setup":
			_counter = 0
			_sine_offset = 0
			_next()
		&"sine":
			_sine_wave_step()
		&"spin_setup":
			_counter = 0
			_next()
		&"spin":
			_spin_step()
		&"scatter_setup":
			_counter = SCATTER_FRAMES
			_next()
		&"scatter":
			_scatter_step()
		&"zoom":
			_zoom_step()


func _next() -> void:
	if _delay > 0:
		_pending_next = true
		return
	_step += 1


## `StartTrainerBattle_LoadPokeBallGraphics`, which returns at once for a wild
## battle: the ball is what says a person is on the other side.
func _load_poke_ball_graphics() -> void:
	if not _trainer:
		_next()
		return
	for row: int in BALL_SIDE:
		var bits: int = int(POKE_BALL[row])
		for column: int in BALL_SIDE:
			# `sla a` walks from bit 7 down and `and a / jr z` stops on a byte
			# whose remaining bits are all clear, so a zero never writes a cell.
			if (bits & (1 << (BALL_SIDE - 1 - column))) == 0:
				continue
			_write(BALL_AT.x + column, BALL_AT.y + row, CELL_SQUARE)
	_ball_drawn = true
	_delay = BALL_FRAMES
	_next()


## `StartTrainerBattle_Flash.DoFlashAnimation`, two frames a palette. Darkness is
## the one palset it does nothing for, and the pass ends on the entry that is not
## a palette at all.
func _flash() -> void:
	if _darkness:
		_counter = 0
		_next()
		return
	@warning_ignore("integer_division")
	var index: int = _counter / 2
	_counter += 1
	var value: int = int(FLASH_PALETTES[mini(index, FLASH_PALETTES.size() - 1)])
	if value == FLASH_TERMINATOR:
		_counter = 0
		_order = IDENTITY
		_next()
		return
	_order = value


## `StartTrainerBattle_SineWave`, whose counter is the amplitude and whose
## offset walks the phase.
func _sine_wave_step() -> void:
	if _counter >= SINE_FRAMES:
		_finish()
		return
	_sine_offset = (_sine_offset + 1) & 0xFF
	_counter = (_counter + _sine_offset) & 0xFF


## `calc_sine_wave`: `d * sin(a * pi/32)` out of the cartridge's own table, as a
## signed byte.
func _sine_wave(phase: int, amplitude: int) -> int:
	var index: int = phase & 0x3F
	var negative: bool = index >= 0x20
	if negative:
		index &= 0x1F
	var word: int = 0
	if index * 2 + 1 < _sine.size():
		word = int(_sine[index * 2]) | (int(_sine[index * 2 + 1]) << 8)
	var value: int = ((word * amplitude) >> 8) & 0xFF
	if negative:
		value = (-value) & 0xFF
	return value - 256 if value >= 128 else value


## `StartTrainerBattle_SpinToBlack`, one wedge a step.
func _spin_step() -> void:
	if _counter >= SPIN_QUADRANTS.size():
		_delay = SPIN_END_FRAMES
		_finish()
		return
	var entry: Array = SPIN_QUADRANTS[_counter]
	_draw_wedge(int(entry[0]), int(entry[1]), Vector2i(int(entry[2]), int(entry[3])))
	_counter += 1
	_delay = SPIN_STEP_FRAMES


## `.load`: a run of cells blacked out along a row, then a step back and down
## (or up), until the wedge's own `-1`. Which way each of those goes is the
## quadrant's two bits.
func _draw_wedge(quadrant: int, wedge: int, at: Vector2i) -> void:
	var data: Array = WEDGES[wedge]
	var right: bool = (quadrant & 1) != 0
	var lower: bool = (quadrant & 2) != 0
	var cursor: Vector2i = at
	var index: int = 0
	while index < data.size():
		var run: int = int(data[index])
		index += 1
		var head: Vector2i = cursor
		for _cell: int in run:
			_write(cursor.x, cursor.y, CELL_BLACK)
			cursor.x += 1 if right else -1
		cursor = head
		# `ld bc, SCREEN_WIDTH / jr z, .upper / ld bc, -SCREEN_WIDTH`: an upper
		# quadrant's wedge grows down the screen and a lower one grows up it.
		cursor.y += -1 if lower else 1
		if index >= data.size():
			return
		var back: int = int(data[index])
		index += 1
		if back < 0:
			return
		cursor.x += (-back if right else back)


## `StartTrainerBattle_SpeckleToBlack`: twelve tiles a frame, resampling a tile
## that is already black rather than counting it.
func _scatter_step() -> void:
	if _counter <= 0:
		_delay = SPIN_END_FRAMES
		_finish()
		return
	_counter -= 1
	for _tile: int in SCATTER_PER_FRAME:
		var guard: int = 256
		while guard > 0:
			guard -= 1
			var y: int = _rng.randi_range(0, ROWS - 1)
			var x: int = _rng.randi_range(0, COLUMNS - 1)
			if _cells[y * COLUMNS + x] == CELL_BLACK:
				continue
			_cells[y * COLUMNS + x] = CELL_BLACK
			break


## `StartTrainerBattle_ZoomToBlack`, one box a frame: its own loop spends a
## `WaitBGMap` between them.
func _zoom_step() -> void:
	if _counter >= ZOOM_BOXES.size():
		_finish()
		return
	var box: Array = ZOOM_BOXES[_counter]
	for row: int in int(box[1]):
		for column: int in int(box[0]):
			_write(int(box[3]) + column, int(box[2]) + row, CELL_BLACK)
	_counter += 1


## `StartTrainerBattle_Finish`, and `DoBattleTransition.done` behind it: every
## background palette is filled with zero, which is what takes whatever the
## outro left to black.
func _finish() -> void:
	_delay = TAIL_FRAMES
	_finished = true
	_order = IDENTITY
	_cells.fill(CELL_BLACK)


func _write(x: int, y: int, value: int) -> void:
	if x < 0 or x >= COLUMNS or y < 0 or y >= ROWS:
		return
	_cells[y * COLUMNS + x] = value
