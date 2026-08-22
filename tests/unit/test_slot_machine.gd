extends GutTest

## `_SlotMachine`'s rules (engine/games/slot_machine.asm), driven headless.
##
## The reel strips here are the cartridge's own, so a window is a real one; the
## art is `tools/checks/slots.gd` and the screen around it
## `tests/integration/test_world_slot_machine.gd`.
##
## What is asserted is what a reading gets wrong rather than what a spin looks
## like: that a bet is taken once and paid once, that an unbiased spin can only
## stop where nothing is lined up, that a seven keeps its own bias, and that the
## payout animation walks the coins over rather than adding them at once.

const REELS: Array = [
	[
		0x00, 0x08, 0x14, 0x0C, 0x10, 0x00, 0x08, 0x14, 0x0C, 0x10,
		0x04, 0x08, 0x14, 0x0C, 0x10, 0x00, 0x08, 0x14,
	],
	[
		0x00, 0x0C, 0x08, 0x10, 0x14, 0x04, 0x0C, 0x08, 0x10, 0x14,
		0x04, 0x0C, 0x08, 0x10, 0x14, 0x00, 0x0C, 0x08,
	],
	[
		0x00, 0x0C, 0x08, 0x10, 0x14, 0x0C, 0x08, 0x10, 0x14, 0x0C,
		0x04, 0x08, 0x10, 0x14, 0x0C, 0x00, 0x0C, 0x08,
	],
]

const FRAME_CAP: int = 2400


func _strips() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for reel: Array in REELS:
		var strip := PackedByteArray()
		for symbol: int in reel:
			strip.append(symbol)
		out.append(strip)
	return out


func _machine(coins: int = 200, lucky: bool = false, seed: int = 1) -> Gen2SlotMachine:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Gen2SlotMachine.create(_strips(), coins, lucky, rng)


## Drives to the next prompt, answering `WaitSFX` the way a screen with no audio
## player does. [param stop_at] is the prompt to stop on.
func _drive(machine: Gen2SlotMachine, stop_at: int, frames: int = FRAME_CAP) -> bool:
	for _frame: int in frames:
		if machine.prompt() == stop_at:
			return true
		if machine.waiting_for_sfx():
			machine.sfx_finished()
			continue
		if machine.prompt() == Gen2SlotMachine.Prompt.TEXT:
			machine.dismiss_text()
			continue
		if machine.jumptable_index() in [
			Gen2SlotMachine.SLOTS_WAIT_REEL1, Gen2SlotMachine.SLOTS_WAIT_REEL2,
			Gen2SlotMachine.SLOTS_WAIT_REEL3,
		]:
			machine.press_a()
		if not machine.advance():
			return machine.prompt() == stop_at
	return false


## One whole spin, from the bet menu to `SlotsAction_RestartOrQuit`'s own wait.
func _spin(machine: Gen2SlotMachine, bet: int) -> bool:
	if not _drive(machine, Gen2SlotMachine.Prompt.BET):
		return false
	machine.answer_bet(4 - bet)
	return _drive(machine, Gen2SlotMachine.Prompt.PRESS)


## `Slots_AskBet`: the menu's own row is `4 - wMenuCursorY` coins, and the
## sixteen-bit subtraction happens once.
func test_the_bet_is_taken_once() -> void:
	var machine: Gen2SlotMachine = _machine()
	assert_true(_drive(machine, Gen2SlotMachine.Prompt.BET))
	machine.answer_bet(1)
	assert_eq(machine.bet(), 3)
	assert_eq(machine.coins(), 197)


## `.DeductCoins`' own refusal: a balance under the bet reprints the box and
## goes back to the menu rather than spinning.
func test_a_bet_over_the_balance_is_refused() -> void:
	var machine: Gen2SlotMachine = _machine(2)
	assert_true(_drive(machine, Gen2SlotMachine.Prompt.BET))
	machine.answer_bet(1)
	assert_eq(machine.prompt(), Gen2SlotMachine.Prompt.TEXT)
	assert_eq(machine.prompt_name(), &"not_enough_coins")
	assert_eq(machine.coins(), 2)
	machine.dismiss_text()
	assert_eq(machine.prompt(), Gen2SlotMachine.Prompt.BET)


## B on the menu is `ret c`, which is the quit entry and not another bet.
func test_cancelling_the_menu_leaves_the_game() -> void:
	var machine: Gen2SlotMachine = _machine()
	assert_true(_drive(machine, Gen2SlotMachine.Prompt.BET))
	machine.answer_bet(-1)
	assert_eq(machine.jumptable_index(), Gen2SlotMachine.SLOTS_QUIT)
	for _frame: int in 8:
		if machine.waiting_for_sfx():
			machine.sfx_finished()
		machine.advance()
	assert_true(machine.finished())


## `ReelAction_StopReel3` has no way to stop on a match the bias did not ask
## for, and `SLOTS_NO_BIAS` matches nothing: an unbiased spin cannot pay.
func test_an_unbiased_spin_never_lines_anything_up() -> void:
	var unbiased: int = 0
	for seed: int in 24:
		var machine: Gen2SlotMachine = _machine(200, false, seed)
		assert_true(_spin(machine, 3), "spin %d must reach its payout" % seed)
		if machine.bias() != Gen2SlotMachine.SLOTS_NO_BIAS:
			continue
		unbiased += 1
		assert_eq(
			machine.matched(), Gen2SlotMachine.SLOTS_NO_MATCH,
			"an unbiased spin lined up %d" % machine.matched()
		)
	assert_gt(unbiased, 0, "the sweep must reach an unbiased spin at all")


## `Slots_GetPayout.PayoutTable` against `wCoins`, over whichever seeds pay.
func test_a_match_pays_its_own_table_row() -> void:
	var paid: int = 0
	for seed: int in 64:
		var machine: Gen2SlotMachine = _machine(200, true, seed)
		assert_true(_spin(machine, 3))
		var matched: int = machine.matched()
		if matched == Gen2SlotMachine.SLOTS_NO_MATCH:
			assert_eq(machine.coins(), 197, "a losing spin must pay nothing")
			continue
		paid += 1
		assert_eq(
			machine.coins(), 197 + Gen2SlotMachine.PAYOUTS[matched / 4],
			"a %d match must pay its own row" % matched
		)
	assert_gt(paid, 0, "the lucky machine must pay at least once in 64 spins")


## `SlotsAction_PayoutAnim` moves one coin every other frame, so a three hundred
## coin win is six hundred frames of animation rather than one addition.
func test_the_payout_is_walked_over_one_coin_at_a_time() -> void:
	var machine: Gen2SlotMachine = _machine(200, true, 3)
	assert_true(_drive(machine, Gen2SlotMachine.Prompt.BET))
	machine.answer_bet(1)
	## Drive to the payout and watch the balance climb rather than jump.
	var seen: Array[int] = []
	for _frame: int in FRAME_CAP:
		if machine.prompt() == Gen2SlotMachine.Prompt.PRESS:
			break
		if machine.waiting_for_sfx():
			machine.sfx_finished()
			continue
		if machine.prompt() == Gen2SlotMachine.Prompt.TEXT:
			machine.dismiss_text()
			continue
		if machine.jumptable_index() in [
			Gen2SlotMachine.SLOTS_WAIT_REEL1, Gen2SlotMachine.SLOTS_WAIT_REEL2,
			Gen2SlotMachine.SLOTS_WAIT_REEL3,
		]:
			machine.press_a()
		machine.advance()
		if not seen.has(machine.coins()):
			seen.append(machine.coins())
	## The bet was taken before the loop, so the balance it starts on is the one
	## already paid for.
	if machine.matched() == Gen2SlotMachine.SLOTS_NO_MATCH:
		assert_eq(seen.size(), 1, "a losing spin moves the balance nowhere")
		return
	assert_eq(
		seen.size(), 1 + Gen2SlotMachine.PAYOUTS[machine.matched() / 4],
		"every coin of the payout must be its own step"
	)


## `Slots_CheckCoinCaseFull`: a case at MAX_COINS takes no more, and the payout
## still counts down.
func test_a_full_coin_case_takes_no_more() -> void:
	var machine: Gen2SlotMachine = _machine(Gen2SlotMachine.MAX_COINS, true, 3)
	assert_true(_spin(machine, 3))
	assert_true(machine.coins() <= Gen2SlotMachine.MAX_COINS)
	assert_eq(machine.payout(), 0, "the payout must drain whether it lands or not")


## `Slots_AskPlayAgain`'s own exit: no coins left prints its line, spends sixty
## frames and quits without asking anything.
func test_running_out_of_coins_ends_the_game_without_asking() -> void:
	var machine: Gen2SlotMachine = _machine(0)
	machine._ask_play_again()
	assert_eq(machine.prompt(), Gen2SlotMachine.Prompt.NONE)
	assert_eq(machine.jumptable_index(), Gen2SlotMachine.SLOTS_QUIT)
	var printed: Array = []
	for event: Variant in machine.take_events():
		printed.append((event as Dictionary).get("name", &""))
	assert_true(printed.has(&"ran_out_of_coins"))


## The same routine with coins left asks, and YES goes back to `SLOTS_INIT`.
func test_playing_again_starts_the_machine_over() -> void:
	var machine: Gen2SlotMachine = _machine(10)
	machine._ask_play_again()
	assert_eq(machine.prompt(), Gen2SlotMachine.Prompt.PLAY_AGAIN)
	machine.answer_play_again(true)
	assert_eq(machine.jumptable_index(), Gen2SlotMachine.SLOTS_INIT)


## `Slots_InitBias`' own `ret z`: SLOTS_SEVEN is zero, so a spin that left the
## bias there rolls nothing and keeps it.
func test_a_seven_bias_is_kept_rather_than_rerolled() -> void:
	var machine: Gen2SlotMachine = _machine()
	machine._bias = Gen2SlotMachine.SLOTS_SEVEN
	machine._init_bias()
	assert_eq(machine.bias(), Gen2SlotMachine.SLOTS_SEVEN)


## `.SpinReel`: a reel's action runs on every sixteenth unit of distance and the
## rate is what walks the objects between two symbols.
func test_a_reel_steps_a_symbol_every_sixteen_units() -> void:
	var machine: Gen2SlotMachine = _machine()
	var reel: Gen2SlotMachine.Reel = machine.reels()[0]
	var before: int = reel.position
	reel.spin_rate = Gen2SlotMachine.RATE_NORMAL
	for _step: int in 4:
		machine._spin_reel(0)
	assert_eq(reel.spin_distance, 16)
	assert_eq(reel.position, (before + 1) % Gen2SlotMachine.REEL_SIZE)


## The strips repeat their own first three symbols, so a window at the end of a
## reel reads three real ones rather than wrapping.
func test_every_window_is_three_symbols_of_the_strip() -> void:
	var machine: Gen2SlotMachine = _machine()
	var reel: Gen2SlotMachine.Reel = machine.reels()[0]
	for position: int in Gen2SlotMachine.REEL_SIZE:
		reel.position = position
		var window: PackedByteArray = reel.window()
		assert_eq(window.size(), 3)
		for symbol: int in window:
			assert_true(symbol in [0x00, 0x04, 0x08, 0x0C, 0x10, 0x14])
