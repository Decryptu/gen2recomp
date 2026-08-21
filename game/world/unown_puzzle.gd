class_name Gen2UnownPuzzle
extends RefCounted

## `_UnownPuzzle` (engine/games/unown_puzzle.asm), the sliding-piece puzzle the
## four Ruins of Alph chambers open.
##
## The board is `wPuzzlePieces`, six by six cells holding a piece number 1 to 16
## or zero. Only the inner four by four is the picture; the ring around it is
## where the sixteen pieces are scattered, less the four cells the START>CANCEL
## box stands on, which is why `.PuzzlePieceInitialPositions` is sixteen entries
## for sixteen pieces and the scatter is a permutation rather than a placement.
##
## Node-free and scene-free: the screen owns the frames and the sound, this owns
## the rules, and the generator is injected so a run replays.
##
## Three things a reading gets wrong:
##
## - **The cursor walks cells, not tiles, and its edges are hand-listed.** The
##   bottom border row is reachable at its two ends alone: `.d_right`'s own
##   `.right_overflow` jumps cell 30 straight to 35 over the four the box
##   covers, and `.d_left` jumps back. Nothing steps down out of the bottom
##   inner row either, which is the four `ret z` in front of `.d_down`'s bound.
## - **A press is refused rather than ignored.** Lifting from an empty cell and
##   placing onto a full one both reach `UnownPuzzle_InvalidAction`, which plays
##   `SFX_WRONG` and waits it out, so the frame is spent either way.
## - **Holding a piece stops the cursor blinking.** `_UnownPuzzle.loop` reads
##   `hVBlankCounter and $10` only when `wHoldingUnownPuzzlePiece` is clear, so
##   the empty cursor is up sixteen frames in thirty-two and a held piece is up
##   on every one of them.

## `wPuzzlePieces` is six by six and `puzcoord` is `row * 6 + column`.
const COLUMNS: int = 6
const ROWS: int = 6
const CELLS: int = COLUMNS * ROWS
## The sixteen pieces, which is also the inner four by four.
const PIECES: int = 16
const PIECE_COLUMNS: int = 4

## `.PuzzlePieceInitialPositions`: the whole top row and then the two end columns
## of the five below it, which is every ring cell the START>CANCEL box does not
## stand on.
const START_CELLS: Array[int] = [
	0, 1, 2, 3, 4, 5,
	6, 11,
	12, 17,
	18, 23,
	24, 29,
	30, 35,
]

## The two cells `.right_overflow` and `.left_overflow` jump between, which is
## how the cursor crosses the START>CANCEL box without entering it.
const BOX_LEFT_CELL: int = 30
const BOX_RIGHT_CELL: int = 35

## `.d_down`'s four `ret z`: the bottom inner row steps nowhere.
const NO_STEP_DOWN: Array[int] = [25, 26, 27, 28]

## `JoyTextDelay`'s own repeat, which is what makes a held direction walk. The
## frame a button is newly pressed reloads `wTextDelayFrames` with fifteen and
## acts; after that `.restartframedelay` acts only on the frames the counter has
## reached zero and reloads it with five.
const REPEAT_DELAY_FRAMES: int = 15
const REPEAT_RATE_FRAMES: int = 5

## `hVBlankCounter and $10`: the empty cursor is drawn on the frames bit 4 is
## set and cleared off the screen on the rest.
const BLINK_MASK: int = 0x10

## The six sounds, as constants/sfx_constants.asm's own indices. The comments
## there are hexadecimal and the run has no gaps, so each is its position in the
## enum. `SFX_PLACE_PUZZLE_PIECE_DOWN` is shared with `OWCutAnimation`.
const SFX_MOVE_CURSOR: int = 0x31
const SFX_MOVE_HELD_PIECE: int = 0x32
const SFX_LIFT_PIECE: int = 0x3E
const SFX_PLACE_PIECE: int = 0x1E
const SFX_REFUSED: int = 0x19
const SFX_SOLVED: int = 0x99

var _pieces: PackedByteArray = PackedByteArray()
var _cursor: int = 0
var _holding: bool = false
var _held: int = 0
var _solved: bool = false
var _finished: bool = false
## `wTextDelayFrames`, which the VBlank handler decrements and `JoyTextDelay`
## reloads. Carried here because the repeat is part of how the board is walked.
var _delay: int = 0
## Whether the board is waiting out `SimpleWaitPressAorB` after the last piece
## went down, which is the one press the puzzle takes after it is solved.
var _awaiting_solved_press: bool = false


## `InitUnownPuzzlePiecePositions`, which walks 1 to 16 and drops each on a
## random free start cell, rerolling on a taken one. Rerolling is a permutation
## whatever the generator answers, so the shuffle is drawn as one rather than
## looped: the roll order is the same set of outcomes and costs no unbounded
## loop, and no caller can see the difference.
static func create(rng: RandomNumberGenerator) -> Gen2UnownPuzzle:
	var puzzle := Gen2UnownPuzzle.new()
	puzzle._pieces.resize(CELLS)
	var free: Array[int] = START_CELLS.duplicate()
	for piece: int in range(1, PIECES + 1):
		var at: int = 0
		if rng != null and free.size() > 1:
			at = rng.randi_range(0, free.size() - 1)
		puzzle._pieces[free[at]] = piece
		free.remove_at(at)
	return puzzle


func pieces() -> PackedByteArray:
	return _pieces.duplicate()


func piece_at(cell: int) -> int:
	return int(_pieces[cell]) if cell >= 0 and cell < CELLS else 0


func cursor() -> int:
	return _cursor


func holding() -> bool:
	return _holding


func held_piece() -> int:
	return _held


func solved() -> bool:
	return _solved


## `JUMPTABLE_EXIT_F`, which START sets and the solved board sets after its own
## press.
func finished() -> bool:
	return _finished


## Whether the cursor is drawn this frame. A held piece is always up; an empty
## cursor blinks off `hVBlankCounter`. The solved tail's own `ClearSprites` runs
## in front of `SimpleWaitPressAorB`, so nothing is drawn from the frame the last
## piece went down.
func cursor_visible(frame: int) -> bool:
	if _awaiting_solved_press or _solved:
		return false
	return _holding or (frame & BLINK_MASK) != 0


## Whether the START>CANCEL row is still written. The solved tail redraws
## `PlaceStartCancelBoxBorder` alone, which leaves that row PUZZLE_VOID, and it
## does so before the press rather than after it.
func box_text_visible() -> bool:
	return not (_awaiting_solved_press or _solved)


## One pass of `_UnownPuzzle.loop`, [param pressed] the buttons that went down
## this frame (`hJoyPressed`) and [param held] the ones still down
## (`hJoyDown`, which is what `hJoyLast` carries with `hInMenu` set).
##
## Answers the sounds `PlaySFX` was handed, in order, plus whether the pass
## solved the board. A caller spends the frame either way: `UnownPuzzle_A` and
## `UnownPuzzle_InvalidAction` both end on `WaitSFX`.
func advance(pressed: Array = [], held: Array = []) -> Dictionary:
	var sounds: Array[int] = []
	if _finished:
		return {"sounds": sounds, "solved": _solved, "wait_sfx": false}

	if _awaiting_solved_press:
		## `SimpleWaitPressAorB`, the one press between the solved fanfare and
		## the exit. No other button reaches it.
		if Gen2Button.A in pressed or Gen2Button.B in pressed:
			_awaiting_solved_press = false
			_solved = true
			_finished = true
		return {"sounds": sounds, "solved": _solved, "wait_sfx": false}

	var repeating: bool = _joy_text_delay(not pressed.is_empty())

	if Gen2Button.START in pressed:
		_finished = true
		return {"sounds": sounds, "solved": false, "wait_sfx": false}

	if Gen2Button.A in pressed:
		return _press_a()

	if repeating:
		var step: int = _step_for(pressed + held)
		if step != _cursor:
			_cursor = step
			sounds.append(SFX_MOVE_HELD_PIECE if _holding else SFX_MOVE_CURSOR)
	return {"sounds": sounds, "solved": false, "wait_sfx": false}


## `JoyTextDelay` with `hInMenu` set, which is what `_UnownPuzzle` sets on the
## way in: `hJoyLast` is the held buttons on the frame a press starts and on
## every fifth frame after fifteen, and zero on the rest. The counter is
## decremented by the VBlank the loop's own `DelayFrame` waits for, which is
## after the pass rather than before it.
func _joy_text_delay(newly_pressed: bool) -> bool:
	var acts: bool = true
	if newly_pressed:
		_delay = REPEAT_DELAY_FRAMES
	elif _delay > 0:
		acts = false
	else:
		_delay = REPEAT_RATE_FRAMES
	_delay = maxi(_delay - 1, 0)
	return acts


## `UnownPuzzle_A`: lift the piece under the cursor, or put the held one down.
## Both halves refuse rather than doing nothing, and the placement that fills the
## board runs `CheckSolvedUnownPuzzle`.
func _press_a() -> Dictionary:
	var sounds: Array[int] = []
	var occupant: int = int(_pieces[_cursor])
	if not _holding:
		if occupant == 0:
			sounds.append(SFX_REFUSED)
			return {"sounds": sounds, "solved": false, "wait_sfx": true}
		sounds.append(SFX_LIFT_PIECE)
		_pieces[_cursor] = 0
		_held = occupant
		_holding = true
		return {"sounds": sounds, "solved": false, "wait_sfx": true}

	if occupant != 0:
		sounds.append(SFX_REFUSED)
		return {"sounds": sounds, "solved": false, "wait_sfx": true}
	sounds.append(SFX_PLACE_PIECE)
	_pieces[_cursor] = _held
	_held = 0
	_holding = false
	if not _is_solved():
		return {"sounds": sounds, "solved": false, "wait_sfx": true}

	## The solved tail: the box loses its START>CANCEL row, the cursor goes off
	## the screen and the fanfare is waited out before the one press that leaves.
	sounds.append(SFX_SOLVED)
	_awaiting_solved_press = true
	return {"sounds": sounds, "solved": true, "wait_sfx": true}


## `CheckSolvedUnownPuzzle`: piece n sits at inner row `(n - 1) / 4` and column
## `(n - 1) % 4`, and every ring cell is empty.
func _is_solved() -> bool:
	for cell: int in CELLS:
		if int(_pieces[cell]) != solved_piece_at(cell):
			return false
	return true


## `.SolvedPuzzleConfiguration`'s own byte for [param cell].
static func solved_piece_at(cell: int) -> int:
	var row: int = cell / COLUMNS
	var column: int = cell % COLUMNS
	if row < 1 or row > PIECE_COLUMNS or column < 1 or column > PIECE_COLUMNS:
		return 0
	return (row - 1) * PIECE_COLUMNS + column


## Where the cursor lands for the direction in [param buttons], or where it
## already is when the step is refused. `.Function` tests up, down, left and
## right in that order and takes the first, so a diagonal is one direction.
func _step_for(buttons: Array) -> int:
	var column: int = _cursor % COLUMNS
	if Gen2Button.UP in buttons:
		return _cursor - COLUMNS if _cursor >= COLUMNS else _cursor
	if Gen2Button.DOWN in buttons:
		if _cursor in NO_STEP_DOWN or _cursor >= BOX_LEFT_CELL:
			return _cursor
		return _cursor + COLUMNS
	if Gen2Button.LEFT in buttons:
		if _cursor == BOX_RIGHT_CELL:
			return BOX_LEFT_CELL
		return _cursor if column == 0 else _cursor - 1
	if Gen2Button.RIGHT in buttons:
		if _cursor == BOX_LEFT_CELL:
			return BOX_RIGHT_CELL
		return _cursor if column == COLUMNS - 1 else _cursor + 1
	return _cursor
