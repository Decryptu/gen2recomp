extends GutTest

## `engine/games/unown_puzzle.asm`, the rules half.
##
## Scene-free: [Gen2UnownPuzzle] is the board and its generator is injected, so a
## case is a scatter, a walk and a press. The corpus sweep on real cartridges is
## `tools/checks/unown_puzzle.gd`, which owns the art, the doubling and the
## thirty-six cells against four directions; the point of these is the branches
## a sweep cannot single out, which is every one that turns on what the cursor is
## carrying or on the order two presses happen in.

const UP: int = Gen2Button.UP
const DOWN: int = Gen2Button.DOWN
const LEFT: int = Gen2Button.LEFT
const RIGHT: int = Gen2Button.RIGHT
const A: int = Gen2Button.A
const START: int = Gen2Button.START


func _press(puzzle: Gen2UnownPuzzle, button: int) -> Dictionary:
	return puzzle.advance([button], [button])


## Walk the cursor to [param cell] from wherever it stands. Up and left both
## refuse at the edge, so pressing each six times parks it on cell 0, and the
## board is walked from there down the first column and along the row.
func _walk_to(puzzle: Gen2UnownPuzzle, cell: int) -> void:
	for _step: int in Gen2UnownPuzzle.ROWS:
		_press(puzzle, LEFT)
		_press(puzzle, UP)
	for _step: int in cell / Gen2UnownPuzzle.COLUMNS:
		_press(puzzle, DOWN)
	for _step: int in cell % Gen2UnownPuzzle.COLUMNS:
		_press(puzzle, RIGHT)
	assert_eq(puzzle.cursor(), cell, "the cursor did not reach cell %d" % cell)


func test_scatter_is_a_permutation_of_the_sixteen_start_cells() -> void:
	## `InitUnownPuzzlePiecePositions` rerolls a taken cell, so sixteen pieces
	## land on sixteen of the twenty ring cells and never on the four the
	## START>CANCEL box stands on.
	for seed_value: int in 8:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(rng)
		var seen: Array[int] = []
		for cell: int in Gen2UnownPuzzle.CELLS:
			var piece: int = puzzle.piece_at(cell)
			if piece == 0:
				continue
			assert_true(
				cell in Gen2UnownPuzzle.START_CELLS,
				"seed %d put a piece on cell %d" % [seed_value, cell]
			)
			assert_false(seen.has(piece), "seed %d placed piece %d twice" % [seed_value, piece])
			seen.append(piece)
		assert_eq(seen.size(), Gen2UnownPuzzle.PIECES)


func test_the_same_seed_scatters_the_same_board() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 12345
	second.seed = 12345
	assert_eq(
		Gen2UnownPuzzle.create(first).pieces(),
		Gen2UnownPuzzle.create(second).pieces(),
		"a replayed run must scatter the board it recorded"
	)


func test_the_cursor_crosses_the_start_cancel_box_at_its_two_ends() -> void:
	## `.right_overflow` and `.left_overflow`: cell 30 steps straight to 35 over
	## the four cells the box covers, and back.
	var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
	_walk_to(puzzle, Gen2UnownPuzzle.BOX_LEFT_CELL)
	_press(puzzle, RIGHT)
	assert_eq(puzzle.cursor(), Gen2UnownPuzzle.BOX_RIGHT_CELL)
	_press(puzzle, LEFT)
	assert_eq(puzzle.cursor(), Gen2UnownPuzzle.BOX_LEFT_CELL)


func test_the_bottom_inner_row_steps_nowhere_down() -> void:
	## `.d_down`'s four `ret z`, which is what stops the cursor walking into the
	## box from above.
	for cell: int in Gen2UnownPuzzle.NO_STEP_DOWN:
		var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
		_walk_to(puzzle, cell)
		_press(puzzle, DOWN)
		assert_eq(puzzle.cursor(), cell, "cell %d stepped down" % cell)


func test_a_held_direction_repeats_after_fifteen_frames_then_every_fifth() -> void:
	## `JoyTextDelay`: the press acts, then `wTextDelayFrames` holds for fifteen
	## frames and `.restartframedelay` acts every fifth after that.
	var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
	puzzle.advance([RIGHT], [RIGHT])
	assert_eq(puzzle.cursor(), 1, "the press itself must step")
	var steps: Array[int] = []
	for frame: int in 30:
		var before: int = puzzle.cursor()
		puzzle.advance([], [RIGHT])
		if puzzle.cursor() != before:
			steps.append(frame)
	assert_eq(
		steps, [14, 19, 24, 29] as Array[int],
		"the repeat is fifteen frames and then one in five"
	)


func test_a_released_direction_stops_repeating() -> void:
	var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
	puzzle.advance([RIGHT], [RIGHT])
	for _frame: int in 40:
		puzzle.advance([], [])
	assert_eq(puzzle.cursor(), 1, "a board with nothing held must not walk")


func test_lifting_an_empty_cell_is_refused_with_a_sound() -> void:
	## `UnownPuzzle_InvalidAction`, which plays SFX_WRONG and waits it out rather
	## than doing nothing.
	var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
	_walk_to(puzzle, 7)
	var result: Dictionary = _press(puzzle, A)
	assert_eq(result["sounds"], [Gen2UnownPuzzle.SFX_REFUSED] as Array[int])
	assert_true(bool(result["wait_sfx"]), "the refusal spends its own frame")
	assert_false(puzzle.holding())


func test_a_piece_is_lifted_and_put_down_on_an_empty_cell() -> void:
	var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
	var piece: int = puzzle.piece_at(0)
	assert_gt(piece, 0, "cell 0 is a start cell")
	var lifted: Dictionary = _press(puzzle, A)
	assert_eq(lifted["sounds"], [Gen2UnownPuzzle.SFX_LIFT_PIECE] as Array[int])
	assert_true(puzzle.holding())
	assert_eq(puzzle.held_piece(), piece)
	assert_eq(puzzle.piece_at(0), 0, "the cell the piece came off is empty")

	## A held piece moves with the cursor and answers a different sound doing it.
	_press(puzzle, DOWN)
	var moved: Dictionary = _press(puzzle, RIGHT)
	assert_eq(moved["sounds"], [Gen2UnownPuzzle.SFX_MOVE_HELD_PIECE] as Array[int])
	var placed: Dictionary = _press(puzzle, A)
	assert_eq(placed["sounds"], [Gen2UnownPuzzle.SFX_PLACE_PIECE] as Array[int])
	assert_false(puzzle.holding())
	assert_eq(puzzle.piece_at(7), piece)


func test_placing_onto_an_occupied_cell_is_refused_and_keeps_the_piece() -> void:
	var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
	var piece: int = puzzle.piece_at(0)
	_press(puzzle, A)
	_press(puzzle, RIGHT)
	var refused: Dictionary = _press(puzzle, A)
	assert_eq(refused["sounds"], [Gen2UnownPuzzle.SFX_REFUSED] as Array[int])
	assert_true(puzzle.holding(), "the refusal must not drop the piece")
	assert_eq(puzzle.held_piece(), piece)


func test_start_leaves_the_board_unsolved() -> void:
	var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
	_press(puzzle, START)
	assert_true(puzzle.finished())
	assert_false(puzzle.solved())


func test_solving_the_board_takes_one_more_press_before_it_leaves() -> void:
	## `CheckSolvedUnownPuzzle` returning carry runs the fanfare and then
	## `SimpleWaitPressAorB`, so the last piece going down does not leave.
	var puzzle: Gen2UnownPuzzle = Gen2UnownPuzzle.create(null)
	var solved_sounds: Array = _solve(puzzle)
	assert_eq(
		solved_sounds,
		[Gen2UnownPuzzle.SFX_PLACE_PIECE, Gen2UnownPuzzle.SFX_SOLVED] as Array[int]
	)
	assert_false(puzzle.finished(), "the solved board waits for a press")
	assert_false(
		puzzle.box_text_visible(),
		"`PlaceStartCancelBoxBorder` runs before the press, not after it"
	)
	assert_false(puzzle.cursor_visible(Gen2UnownPuzzle.BLINK_MASK), "`ClearSprites` too")
	_press(puzzle, A)
	assert_true(puzzle.finished())
	assert_true(puzzle.solved())


## Moves every piece into `.SolvedPuzzleConfiguration`'s own cell and answers the
## sounds the last placement made.
func _solve(puzzle: Gen2UnownPuzzle) -> Array:
	var sounds: Array = []
	for piece: int in range(1, Gen2UnownPuzzle.PIECES + 1):
		var from: int = -1
		for cell: int in Gen2UnownPuzzle.CELLS:
			if puzzle.piece_at(cell) == piece:
				from = cell
				break
		assert_gt(from, -1, "piece %d is on the board" % piece)
		_walk_to(puzzle, from)
		_press(puzzle, A)
		var to: int = -1
		for cell: int in Gen2UnownPuzzle.CELLS:
			if Gen2UnownPuzzle.solved_piece_at(cell) == piece:
				to = cell
				break
		_walk_to(puzzle, to)
		sounds = _press(puzzle, A)["sounds"]
	return sounds
