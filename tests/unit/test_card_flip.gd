extends GutTest

## `engine/games/card_flip.asm`, the rules half.
##
## Scene-free: [Gen2CardFlip] is the table and its generator is injected, so a
## case is a shuffle, a walk and a press. The corpus sweep on real cartridges is
## `tools/checks/card_flip.gd`, which owns the art, the eight boxes and the
## forty-eight cells against twenty-four cards; the point of these is the
## branches a sweep cannot single out, which is every one that turns on the
## order two things happen in.

const Prompt := Gen2CardFlip.Prompt
const State := Gen2CardFlip.State


func _table(coins: int = 100, seed_value: int = 1) -> Gen2CardFlip:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var board := PackedByteArray()
	board.resize(RomLayout.CARD_FLIP_TILEMAP_BYTES)
	return Gen2CardFlip.create(board, coins, rng)


## One pass, with the driver's own `WaitSFX` cut the way a headless host cuts it.
func _step(game: Gen2CardFlip) -> void:
	game.advance()
	game.take_events()
	if game.waiting_for_sfx():
		game.sfx_finished()


## Spends passes until the table asks for [param prompt].
func _drive_to(game: Gen2CardFlip, prompt: int, frames: int = 2400) -> bool:
	for _frame: int in frames:
		if game.finished():
			return false
		if game.prompt() == prompt:
			return true
		_step(game)
		match game.prompt():
			Prompt.YES_NO when prompt != Prompt.YES_NO:
				game.answer_yes_no(true)
			Prompt.PRESS when prompt != Prompt.PRESS:
				game.dismiss_text()
			Prompt.CHOOSE when prompt != Prompt.CHOOSE:
				game.press_a()
			Prompt.BET when prompt != Prompt.BET:
				game.press_a()
			_:
				pass
	return false


## `.AskPlayWithThree`'s `.SaidNo` jumps straight to `.Quit`, so a no takes
## nothing: the three coins are `.DeductCoins`' and it never runs.
func test_saying_no_at_the_door_costs_nothing() -> void:
	var game: Gen2CardFlip = _table()
	assert_eq(game.prompt(), Prompt.YES_NO, "the table opens on its own question")
	game.answer_yes_no(false)
	for _frame: int in 16:
		_step(game)
	assert_true(game.finished(), "no must leave the game")
	assert_eq(game.coins(), 100, "no coin is charged for leaving")


## `.DeductCoins` charges three before a card is dealt, which is why the balance
## has already moved by the time `.ChooseACard` runs.
func test_a_round_costs_three_coins_before_the_deal() -> void:
	var game: Gen2CardFlip = _table()
	game.answer_yes_no(true)
	_step(game)
	assert_eq(game.coins(), 97, "the bet is taken at `.DeductCoins`")
	assert_eq(game.state(), State.CHOOSE_A_CARD)


## `.DeductCoins`' own `cp 3`: two coins is not enough and the line it prints
## ends in `prompt`, so the table waits for a button and then leaves.
func test_two_coins_is_not_enough_and_ends_the_game() -> void:
	var game: Gen2CardFlip = _table(2)
	game.answer_yes_no(true)
	_step(game)
	assert_eq(game.prompt(), Prompt.PRESS, "the refusal waits for a button")
	assert_true(game.blinking_cursor(), "a `prompt` box loads the cursor")
	assert_eq(game.coins(), 2, "nothing is charged for a refused round")
	game.dismiss_text()
	for _frame: int in 16:
		_step(game)
	assert_true(game.finished())


## `.loop`'s `xor $1` runs at the end of an iteration, so the card A takes is the
## one the border is standing on rather than the one it is about to move to.
func test_a_press_takes_the_card_the_border_is_on() -> void:
	var game: Gen2CardFlip = _table()
	assert_true(_drive_to(game, Prompt.CHOOSE))
	var lit: int = game.border_at()
	assert_eq(lit, game.which_card(), "the border stands on the lit card")
	game.press_a()
	assert_eq(game.which_card(), lit, "the press takes the card it was showing")


## `.loop2` flashes three times before the bet, so the border is still the only
## thing in OAM until `.PlaceYourBet` puts the cursor there.
func test_the_cursor_and_the_border_are_never_up_together() -> void:
	var game: Gen2CardFlip = _table()
	assert_true(_drive_to(game, Prompt.CHOOSE))
	game.press_a()
	for _frame: int in 240:
		assert_false(
			game.border_at() >= 0 and game.cursor_visible(),
			"`ClearSprites` stands between the two sets"
		)
		if game.prompt() == Prompt.BET:
			return
		_step(game)
	fail_test("the flashes must reach `.PlaceYourBet`")


## `ChooseCard_HandleJoypad`'s `.left_to_number_gp` and `.up_to_mon_group`: the
## two group columns jump to one fixed cell in the other block rather than
## stepping into it, which is what makes the walk between the two blocks
## one-way per side.
func test_leaving_the_pokemon_rows_lands_on_one_cell() -> void:
	var game: Gen2CardFlip = _table()
	assert_true(_drive_to(game, Prompt.BET))
	game.move_cursor(Gen2Button.LEFT)
	assert_eq(game.cursor(), Vector2i(1, 2), "a Pokemon column steps left one cell")
	game.move_cursor(Gen2Button.UP)
	assert_eq(game.cursor(), Vector2i(2, 1), "`.up_to_mon_group`'s own fixed cell")
	game.move_cursor(Gen2Button.LEFT)
	assert_eq(game.cursor(), Vector2i(1, 2), "`.left_to_number_gp`'s own fixed cell")


## `.num_pair_down`'s `and $e` and its `cp $6`: a two-number bet only stands on
## the even rows and stops on the last pair.
func test_a_two_number_bet_walks_two_rows_at_a_time() -> void:
	var game: Gen2CardFlip = _table()
	assert_true(_drive_to(game, Prompt.BET))
	game.move_cursor(Gen2Button.LEFT)
	game.move_cursor(Gen2Button.LEFT)
	assert_eq(game.cursor(), Vector2i(0, 2))
	for _step_count: int in 6:
		game.move_cursor(Gen2Button.DOWN)
	assert_eq(game.cursor(), Vector2i(0, 6), "the last pair is where it stops")


## `CardFlip_ShuffleDeck`'s `dec c / jr nz` never writes card 0, so the slot it
## never rolled keeps the zero `ByteFill` left: the deck is still a permutation.
func test_the_shuffle_is_a_permutation_of_the_twenty_four() -> void:
	for seed_value: int in range(1, 9):
		var game: Gen2CardFlip = _table(100, seed_value)
		game.answer_yes_no(true)
		var seen: Dictionary = {}
		for card: int in game.deck():
			seen[card] = true
		assert_eq(
			seen.size(), Gen2CardFlip.DECK_SIZE,
			"seed %d shuffled a deck with a repeat in it" % seed_value
		)


## `.Payout` pays one coin every two frames and `.IsCoinCaseFull` counts the
## ones it cannot pay, so a full case ends the loop at `MAX_COINS`.
func test_a_full_coin_case_takes_no_more() -> void:
	var game: Gen2CardFlip = _table(Gen2CardFlip.MAX_COINS)
	assert_true(_drive_to(game, Prompt.BET))
	game.press_a()
	for _frame: int in 480:
		if game.prompt() == Prompt.PRESS:
			break
		_step(game)
	assert_true(
		game.coins() <= Gen2CardFlip.MAX_COINS,
		"the case cannot pass `MAX_COINS`"
	)


## `.Continue` marks the card just used, and `CardFlip_BlankDiscardedCardSlot`
## writes `$3d` over the half whose pair has already gone.
func test_the_board_marks_a_used_pair_with_the_blank_tile() -> void:
	var game: Gen2CardFlip = _table()
	var marks: int = 0
	for _frame: int in 24000:
		if game.finished():
			break
		_step(game)
		match game.prompt():
			Prompt.YES_NO:
				game.answer_yes_no(true)
			Prompt.PRESS:
				game.dismiss_text()
			Prompt.CHOOSE, Prompt.BET:
				game.press_a()
			_:
				pass
		var map: PackedByteArray = game.tilemap()
		marks = 0
		for cell: int in map.size():
			if map[cell] == Gen2CardFlip.DISCARD_BLANK_TILE:
				marks += 1
		if marks > 0:
			break
	assert_gt(marks, 0, "a second card out of one cell must blank its half")


## `.TabulateTheResult` waits on `WaitPressAorB_BlinkCursor` over a box that
## ends in `done`, and the routine's own note says no cursor is shown for one.
func test_the_result_box_blinks_no_arrow() -> void:
	var game: Gen2CardFlip = _table()
	assert_true(_drive_to(game, Prompt.BET))
	game.press_a()
	assert_true(_drive_to(game, Prompt.PRESS))
	assert_eq(game.state(), State.TABULATE_THE_RESULT)
	assert_false(game.blinking_cursor(), "\"Yeah!\" and \"Darn…\" load no cursor")
