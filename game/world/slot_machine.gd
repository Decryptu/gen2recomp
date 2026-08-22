class_name Gen2SlotMachine
extends RefCounted

## `_SlotMachine`'s own state (engine/games/slot_machine.asm), node-free.
##
## [Gen2SlotMachinePage] owns the picture and [Gen2SlotMachineScreen] the pump;
## this is `SlotsLoop`: one pass a frame, `SlotsJumptable` then
## `Slots_SpinReels` then the two sprite objects, with the reels' own
## `ReelActionJumptable` under them.
##
## Five things the source states that a reading gets wrong:
##
## - **A reel is manipulated after the button, not before.** `Slots_StopReel1`
##   through `..._StopReel3` pick an action rather than a stop, and the action
##   walks the reel on up to `REEL_MANIP_COUNTER` further slots looking for the
##   biased symbol. The bias is rolled once a bet in `Slots_InitBias` and is
##   what decides the spin; the button decides when the search starts.
## - **`Slots_InitBias` keeps a seven.** Its first two lines are
##   `ld a, [wSlotBias] / and a / ret z`, and SLOTS_SEVEN is zero, so a spin
##   that left the bias on seven rolls nothing and stays there.
##   `Slots_PayoutText.LinedUpSevens` is what clears it, on a roll whose odds
##   `wKeepSevenBiasChance` picked at the top of the game.
## - **Golem, Chansey and the slow advance are searches, not decorations.**
##   Each is entered only when the third reel is standing on a match it must not
##   keep, and each advances the reel until `Slots_CheckMatchedAllThreeReels`
##   answers what the bias wants. `Slots_GetNumberOfGolems` runs that search
##   ahead of the animation and hands it the count.
## - **A reel action runs once every sixteen units of spin distance**, not once
##   a frame: `.SpinReel` tests `REEL_SPIN_DISTANCE and $f` before calling it,
##   and a rate of 0 stops the reel where it stands without ending its action.
## - **The three reel strips repeat their own first three symbols.** A window is
##   three consecutive bytes from `(position - 1) and $f`, so nothing wraps.
##
## Randomness is injected: every `Random` here is a byte off the generator the
## caller owns, so a seeded run repeats.

## `wSlotMatched` values, which are the reel strips' own bytes.
const SLOTS_SEVEN: int = 0x00
const SLOTS_POKEBALL: int = 0x04
const SLOTS_CHERRY: int = 0x08
const SLOTS_PIKACHU: int = 0x0C
const SLOTS_SQUIRTLE: int = 0x10
const SLOTS_STARYU: int = 0x14
const NUM_SLOT_REELS: int = 6
const SLOTS_NO_MATCH: int = -1
const SLOTS_NO_BIAS: int = -1

const REEL_SIZE: int = RomLayout.SLOTS_REEL_SIZE
const REELS: int = 3
## `MAX_COINS`, which `Slots_CheckCoinCaseFull` refuses to pass.
const MAX_COINS: int = 9999

## `SlotsJumptable` indices. `SLOTS_END_LOOP_F` is bit 7 of the same byte, which
## is what `SlotsLoop` leaves on.
const SLOTS_INIT: int = 0
const SLOTS_BET_AND_START: int = 1
const SLOTS_WAIT_START: int = 2
const SLOTS_WAIT_REEL1: int = 3
const SLOTS_WAIT_STOP_REEL1: int = 4
const SLOTS_WAIT_REEL2: int = 5
const SLOTS_WAIT_STOP_REEL2: int = 6
const SLOTS_WAIT_REEL3: int = 7
const SLOTS_WAIT_STOP_REEL3: int = 8
const SLOTS_NEXT_09: int = 9
const SLOTS_FLASH_IF_WIN: int = 12
const SLOTS_FLASH_SCREEN: int = 13
const SLOTS_GIVE_EARNED_COINS: int = 14
const SLOTS_PAYOUT_TEXT_AND_ANIM: int = 15
const SLOTS_PAYOUT_ANIM: int = 16
const SLOTS_RESTART_OR_QUIT: int = 17
const SLOTS_QUIT: int = 18
const SLOTS_END_LOOP_F: int = 7

## `ReelActionJumptable` indices.
const REEL_ACTION_DO_NOTHING: int = 0
const REEL_ACTION_STOP_REEL_IGNORE_JOYPAD: int = 1
const REEL_ACTION_NORMAL_RATE: int = 4
const REEL_ACTION_STOP_REEL1: int = 7
const REEL_ACTION_STOP_REEL2: int = 8
const REEL_ACTION_STOP_REEL3: int = 9
const REEL_ACTION_SET_UP_REEL2_SKIP_TO_7: int = 10
const REEL_ACTION_WAIT_REEL2_SKIP_TO_7: int = 11
const REEL_ACTION_FAST_SPIN_REEL2_UNTIL_LINED_UP_7S: int = 12
const REEL_ACTION_START_SLOW_ADVANCE_REEL3: int = 16
const REEL_ACTION_WAIT_SLOW_ADVANCE_REEL3: int = 17
const REEL_ACTION_INIT_GOLEM: int = 18
const REEL_ACTION_WAIT_GOLEM: int = 19
const REEL_ACTION_END_GOLEM: int = 20
const REEL_ACTION_INIT_CHANSEY: int = 21
const REEL_ACTION_WAIT_CHANSEY: int = 22
const REEL_ACTION_WAIT_EGG: int = 23
const REEL_ACTION_DROP_REEL: int = 24

## `ReelAction_*Rate`, the value each writes into `REEL_SPIN_RATE`.
const RATE_NORMAL: int = 4
const RATE_DOUBLE: int = 8
const RATE_QUADRUPLE: int = 16
const RATE_QUARTER: int = 1

## `Slots_GetPayout.PayoutTable`, in `SLOTS_*` order.
const PAYOUTS: Array[int] = [300, 50, 6, 8, 10, 15]

## The sound effects `Slots_PlaySFX` and its callers name.
const SFX_GOT_SAFARI_BALLS: int = 0x0C
const SFX_JUMP_OVER_LEDGE: int = 0x16
const SFX_PLACE_PUZZLE_PIECE_DOWN: int = 0x1E
const SFX_THROW_BALL: int = 0x28
const SFX_SLOT_MACHINE_START: int = 0x2C
const SFX_GET_COIN_FROM_SLOTS: int = 0x67
const SFX_PAY_DAY: int = 0x68
const SFX_PRESENT: int = 0x8E
const SFX_3RD_PLACE: int = 0x94
const SFX_2ND_PLACE: int = 0x98
const SFX_QUIT_SLOTS: int = 0x9D
const SFX_STOP_SLOT: int = 0xBA
## `MUSIC_GAME_CORNER`, which `.InitGFX` starts and nothing here stops.
const MUSIC_GAME_CORNER: int = 0x12

## `SlotsAction_BetAndStart`'s own `ld a, 32`, and `SlotsAction_FlashIfWin`'s 16.
const START_DELAY: int = 32
const FLASH_FRAMES: int = 16
## `Slots_WaitSFX`, which is sixteen frames rather than a wait, and
## `Slots_AskPlayAgain`'s own sixty behind the ran-out-of-coins line.
const WAIT_SFX_FRAMES: int = 16
const RAN_OUT_FRAMES: int = 60
## `REEL_MANIP_COUNTER`'s own 4, one per reel.
const MANIP_COUNTER: int = 4
## `Slots_StopReel`'s `REEL_STOP_DELAY`.
const STOP_DELAY: int = 3

## `Slots_InitBias.Normal` and `.Lucky`: (threshold, symbol), walked until the
## rolled byte is at or below a threshold. The thresholds are `percent`, which
## is `x * $ff / 100` and so 2 for one percent, plus the source's own `+ 1` and
## `- 1` where it has them; they are written out because rgbasm evaluates them
## and GDScript will not call a function inside a constant.
const BIAS_NORMAL: Array[Array] = [
	[1, SLOTS_SEVEN],     # 1 percent - 1
	[3, SLOTS_POKEBALL],  # 1 percent + 1
	[10, SLOTS_STARYU],   # 4 percent
	[20, SLOTS_SQUIRTLE], # 8 percent
	[40, SLOTS_PIKACHU],  # 16 percent
	[48, SLOTS_CHERRY],   # 19 percent
	[255, SLOTS_NO_BIAS], # 100 percent
]
const BIAS_LUCKY: Array[Array] = [
	[2, SLOTS_SEVEN],     # 1 percent
	[3, SLOTS_POKEBALL],  # 1 percent + 1
	[8, SLOTS_STARYU],    # 3 percent + 1
	[16, SLOTS_SQUIRTLE], # 6 percent + 1
	[30, SLOTS_PIKACHU],  # 12 percent
	[80, SLOTS_CHERRY],   # 31 percent + 1
	[255, SLOTS_NO_BIAS], # 100 percent
]

## `Slots_UpdateReelPositionAndOAM`: the first row's own y and the step down the
## reel, in pixels, and how many objects one reel writes.
const REEL_TOP_Y: int = 10 * 8
const REEL_ROW_STEP: int = 2 * 8
const REEL_OBJECTS: int = 8
## `Slots_InitReelTiles`' three `REEL_X_COORD` writes.
const REEL_X: Array[int] = [6 * 8, 10 * 8, 14 * 8]

## What the host is being asked for, when it is being asked.
enum Prompt {
	NONE,
	## `Slots_AskBet`'s `VerticalMenu`: three items, " 3" first.
	BET,
	## A box ending in `prompt`, which waits for a button.
	TEXT,
	## `WaitPressAorB_BlinkCursor` at the top of `SlotsAction_RestartOrQuit`.
	PRESS,
	## `Slots_AskPlayAgain`'s `PlaceYesNoBox`.
	PLAY_AGAIN,
}


## One `slot_reel` struct (macros/ram.asm), plus the strip it reads.
class Reel extends RefCounted:
	var action: int = Gen2SlotMachine.REEL_ACTION_DO_NOTHING
	var position: int = Gen2SlotMachine.REEL_SIZE - 1
	var spin_distance: int = 0
	var spin_rate: int = 0
	var manip_counter: int = 0
	var manip_delay: int = 0
	var drop_counter: int = 0
	var stop_delay: int = 0
	var x: int = 0
	## `REEL_TILEMAP_ADDR`'s own strip: fifteen symbols and the first three again.
	var strip: PackedByteArray = PackedByteArray()
	## The eight object y coordinates `.LoadOAM` writes and `.SpinReel` walks.
	var object_y: PackedInt32Array = PackedInt32Array()
	## The symbol each of the four drawn rows is showing, top row last.
	var object_symbols: PackedInt32Array = PackedInt32Array()

	## `Slots_GetCurrentReelState`: the three symbols from `(position - 1) and $f`,
	## bottom row first.
	func window() -> PackedByteArray:
		var at: int = (((Gen2SlotMachine.REEL_SIZE if position == 0 else position) - 1)) & 0xF
		return strip.slice(at, at + 3)


var _rng: RandomNumberGenerator = null
var _reels: Array[Reel] = []
## `wJumptableIndex`, `wSlotsDelay`, `wSlotBet`, `wSlotBias`, `wSlotMatched`.
var _index: int = SLOTS_INIT
var _delay: int = 0
var _bet: int = 0
var _bias: int = SLOTS_NO_BIAS
var _matched: int = SLOTS_NO_MATCH
var _payout: int = 0
var _coins: int = 0
## `wFirstTwoReelsMatching`, `wFirstTwoReelsMatchingSevens`, `wSlotBuildingMatch`.
var _first_two_matching: bool = false
var _first_two_sevens: bool = false
var _building_match: int = SLOTS_NO_MATCH
## `wReel1Stopped` and `wReel2Stopped`, the windows the reels stopped on.
var _stopped: Array[PackedByteArray] = [
	PackedByteArray(), PackedByteArray(), PackedByteArray()
]
## `wKeepSevenBiasChance`, rolled once at `.InitGFX` and read by `.LinedUpSevens`.
var _keep_seven_chance: bool = false
## `wScriptVar`, which the map's own `setval` in front of the special leaves.
var _lucky: bool = false
## `hJoypadSum`, which the loop clears and a press adds to.
var _pressed_a: bool = false
## Which sub-step of a blocking routine is next, and what is being asked for.
var _prompt: int = Prompt.NONE
var _prompt_name: StringName = &""
var _resume: StringName = &""
## `DelayFrames` inside an action, which the whole loop spends rather than a pass.
var _stall: int = 0
## `WaitSFX`, which the host answers off its own driver.
var _waiting_sfx: bool = false
## The steps of an action that outlive the pass it started on: the `WaitSFX`,
## `PlaySFX` and `PrintText` run a routine ends in, in the routine's own order.
## A `wait` step holds the whole loop until the host says the channels are free.
var _script: Array = []
## The `PlaySFX`, `PrintText` and palette writes of this pass, for the host.
var _events: Array = []
## The two sprite objects `SlotsLoop` pumps, and the light the flash is on.
var _golem: Dictionary = {}
var _chansey: Dictionary = {}
var _egg: Dictionary = {}
## `rOBP0`'s own inversion, which `SlotsAction_FlashScreen` walks.
var _objects_inverted: bool = false


## `percent`, which is `x * $ff / 100`.
static func _percent(value: int) -> int:
	return value * 0xFF / 100


## [param coins] is `wCoins`, [param lucky] the `wScriptVar` the map set, and
## [param rng] the generator every `Random` here is drawn from.
static func create(
	strips: Array[PackedByteArray], coins: int, lucky: bool, rng: RandomNumberGenerator
) -> Gen2SlotMachine:
	var machine := Gen2SlotMachine.new()
	machine._rng = rng
	machine._coins = clampi(coins, 0, MAX_COINS)
	machine._lucky = lucky
	for reel: int in REELS:
		var state := Reel.new()
		state.strip = strips[reel] if reel < strips.size() else PackedByteArray()
		state.x = REEL_X[reel]
		machine._reels.append(state)
		machine._update_reel_objects(state)
	## `.InitGFX`'s own tail: 12.5 percent of games take the lower streak odds.
	machine._keep_seven_chance = (machine._random() & 0b00101010) == 0
	machine._events.append({"kind": &"music", "index": MUSIC_GAME_CORNER})
	return machine


## `Random`, one byte.
func _random() -> int:
	return _rng.randi() & 0xFF if _rng != null else 0


func coins() -> int:
	return _coins


func payout() -> int:
	return _payout


func bet() -> int:
	return _bet


func bias() -> int:
	return _bias


func matched() -> int:
	return _matched


func jumptable_index() -> int:
	return _index


func reels() -> Array[Reel]:
	return _reels


func golem() -> Dictionary:
	return _golem


func chansey() -> Dictionary:
	return _chansey


func egg() -> Dictionary:
	return _egg


func objects_inverted() -> bool:
	return _objects_inverted


## Whether `SlotsLoop` has left, which is `SLOTS_END_LOOP_F`.
func finished() -> bool:
	return (_index & (1 << SLOTS_END_LOOP_F)) != 0


## What the host is being asked for this frame, and by which box.
func prompt() -> int:
	return _prompt


func prompt_name() -> StringName:
	return _prompt_name


func waiting_for_sfx() -> bool:
	return _waiting_sfx


## The sounds, boxes and palette writes of the last pass, drained by the host.
func take_events() -> Array:
	var out: Array = _events
	_events = []
	return out


## `WaitSFX` answered: the host says the effect channels are free again.
func sfx_finished() -> void:
	_waiting_sfx = false


## `hJoypadSum`, which the three `SlotsAction_WaitReel*` read and clear. A press
## is remembered rather than sampled, so a tap between two frames is not lost.
func press_a() -> void:
	_pressed_a = true


## One pass of `SlotsLoop`. Answers false once the loop has left.
func advance() -> bool:
	if _waiting_sfx:
		return true
	if not _script.is_empty():
		_drain_script()
		return true
	if finished():
		return false
	if _prompt != Prompt.NONE:
		return true
	if _stall > 0:
		_stall -= 1
		return true
	_run_action()
	if _prompt != Prompt.NONE or _stall > 0 or _waiting_sfx:
		return true
	_spin_reels()
	_animate_objects()
	return not finished()


## `Slots_AskBet`'s `VerticalMenu` answered. [param option] is `wMenuCursorY`,
## 1 for " 3" and 3 for " 1"; -1 is B, which `ret c` takes to the quit entry.
func answer_bet(option: int) -> void:
	if _prompt != Prompt.BET:
		return
	_prompt = Prompt.NONE
	_prompt_name = &""
	if option < 1 or option > 3:
		_index = SLOTS_QUIT
		return
	_bet = 4 - option
	if not _can_afford(_bet):
		_print(&"not_enough_coins", Prompt.TEXT)
		_resume = &"ask_bet"
		return
	_take_bet()


## A box ending in `prompt` pressed past.
func dismiss_text() -> void:
	if _prompt != Prompt.TEXT and _prompt != Prompt.PRESS:
		return
	_prompt = Prompt.NONE
	_prompt_name = &""
	var resume: StringName = _resume
	_resume = &""
	match resume:
		&"ask_bet":
			_ask_bet()
		&"ask_play_again":
			_ask_play_again()
		_:
			pass


## `Slots_AskPlayAgain`'s YES/NO answered.
func answer_play_again(yes: bool) -> void:
	if _prompt != Prompt.PLAY_AGAIN:
		return
	_prompt = Prompt.NONE
	_prompt_name = &""
	_index = SLOTS_INIT if yes else SLOTS_QUIT


## The steps of `_script` up to the next `WaitSFX`, which holds the loop.
func _drain_script() -> void:
	while not _script.is_empty():
		var step: Dictionary = _script.pop_front()
		if step.get("kind", &"") == &"wait":
			_waiting_sfx = true
			return
		_events.append(step)


## `WaitSFX` and then the steps behind it, run once the driver is free.
func _wait_then(steps: Array) -> void:
	_script.append({"kind": &"wait"})
	_script.append_array(steps)


func _print(name: StringName, kind: int = Prompt.NONE) -> void:
	_events.append({"kind": &"text", "name": name})
	if kind != Prompt.NONE:
		_prompt = kind
		_prompt_name = name


func _play(index: int, wait: bool = false) -> void:
	_events.append({"kind": &"sound", "index": index})
	if wait:
		_waiting_sfx = true


## `SlotsJumptable`, one entry a pass.
func _run_action() -> void:
	match _index:
		SLOTS_INIT:
			_index += 1
			_first_two_matching = false
			_first_two_sevens = false
			_matched = SLOTS_NO_MATCH
		SLOTS_BET_AND_START:
			_ask_bet()
		SLOTS_WAIT_START:
			if _delay > 0:
				_delay -= 1
				return
			_index += 1
			_pressed_a = false
		SLOTS_WAIT_REEL1, SLOTS_WAIT_REEL2, SLOTS_WAIT_REEL3:
			_wait_reel((_index - SLOTS_WAIT_REEL1) / 2)
		SLOTS_WAIT_STOP_REEL1, SLOTS_WAIT_STOP_REEL2, SLOTS_WAIT_STOP_REEL3:
			_wait_stop_reel((_index - SLOTS_WAIT_STOP_REEL1) / 2)
		9, 10, 11:
			_index += 1
		SLOTS_FLASH_IF_WIN:
			if _matched == SLOTS_NO_MATCH:
				_index += 2
				return
			_index += 1
			_delay = FLASH_FRAMES
		SLOTS_FLASH_SCREEN:
			_flash_screen()
		SLOTS_GIVE_EARNED_COINS:
			_first_two_matching = false
			_first_two_sevens = false
			_objects_inverted = false
			_payout = 0 if _matched == SLOTS_NO_MATCH else PAYOUTS[_matched / 4]
			_delay = 0
			_index += 1
		SLOTS_PAYOUT_TEXT_AND_ANIM:
			_payout_text()
			_index += 1
			_payout_anim()
		SLOTS_PAYOUT_ANIM:
			_payout_anim()
		SLOTS_RESTART_OR_QUIT:
			## `Slots_DeilluminateBetLights` and then the wait, which is where
			## the lights go out and the board stands still.
			_bet = 0
			_prompt = Prompt.PRESS
			_prompt_name = &"restart"
			_resume = &"ask_play_again"
		SLOTS_QUIT:
			_index |= 1 << SLOTS_END_LOOP_F
			_wait_then([{"kind": &"sound", "index": SFX_QUIT_SLOTS}])
			_script.append({"kind": &"wait"})
		_:
			pass


## `Slots_AskBet`, up to its `VerticalMenu`.
func _ask_bet() -> void:
	_print(&"bet_how_many")
	_prompt = Prompt.BET
	_prompt_name = &"bet_how_many"


func _can_afford(amount: int) -> bool:
	return _coins >= amount


## `.Start`: the sixteen-bit subtraction, the transaction sound and the line.
func _take_bet() -> void:
	_coins -= _bet
	## `.Start` waits the last game's own fanfare out before the transaction,
	## and `.proceed` waits that out before the reels start.
	_wait_then([
		{"kind": &"sound", "index": SFX_PAY_DAY},
		{"kind": &"text", "name": &"start"},
	])
	_index += 1
	_init_bias()
	_delay = START_DELAY
	for reel: Reel in _reels:
		reel.action = REEL_ACTION_NORMAL_RATE
		reel.manip_counter = MANIP_COUNTER
	_wait_then([{"kind": &"sound", "index": SFX_SLOT_MACHINE_START}])


## `Slots_InitBias`. A bias already on SLOTS_SEVEN is kept, which is the whole
## of the seven streak: zero is the symbol and `ret z` is the test.
func _init_bias() -> void:
	if _bias == SLOTS_SEVEN:
		return
	var roll: int = _random()
	for row: Array in (BIAS_LUCKY if _lucky else BIAS_NORMAL):
		if int(row[0]) >= roll:
			_bias = int(row[1])
			return
	_bias = SLOTS_NO_BIAS


## `SlotsAction_WaitReel1` and its two copies: the A press picks the reel's stop
## action, and `..._WaitStopReel*` waits for that action to end.
func _wait_reel(reel: int) -> void:
	if not _pressed_a:
		return
	_index += 1
	match reel:
		0:
			_reels[0].action = REEL_ACTION_STOP_REEL1
		1:
			_reels[1].action = _stop_reel2_action()
		_:
			_reels[2].action = _stop_reel3_action()


func _wait_stop_reel(reel: int) -> void:
	if _reels[reel].action != REEL_ACTION_DO_NOTHING:
		return
	_play(SFX_STOP_SLOT)
	_stopped[reel] = _reels[reel].window()
	_index += 1
	_pressed_a = false


## `Slots_StopReel2`: a bet of two or more, a seven anywhere in reel one and a
## spin that is unbiased or biased to seven give a 31.25 percent chance of the
## skip-to-seven mode.
func _stop_reel2_action() -> int:
	if _bet < 2:
		return REEL_ACTION_STOP_REEL2
	if _bias != SLOTS_SEVEN and _bias != SLOTS_NO_BIAS:
		return REEL_ACTION_STOP_REEL2
	if not _reel1_has_seven():
		return REEL_ACTION_STOP_REEL2
	if _random() >= _percent(31) + 1:
		return REEL_ACTION_STOP_REEL2
	return REEL_ACTION_SET_UP_REEL2_SKIP_TO_7


## `.CheckReel1ForASeven`, which is zero anywhere in the stopped window.
func _reel1_has_seven() -> bool:
	for symbol: int in _stopped[0]:
		if symbol == SLOTS_SEVEN:
			return true
	return false


## `Slots_StopReel3`'s four-way roll, whose odds depend on whether the first two
## reels stopped on matching sevens and on whether the spin is biased to seven.
func _stop_reel3_action() -> int:
	if not _first_two_matching or not _first_two_sevens:
		return REEL_ACTION_STOP_REEL3
	if _bias != SLOTS_SEVEN:
		var roll: int = _random()
		if roll >= _percent(71) - 1:
			return REEL_ACTION_STOP_REEL3
		if roll >= _percent(47) + 1:
			return REEL_ACTION_START_SLOW_ADVANCE_REEL3
		if roll >= _percent(24) - 1:
			return REEL_ACTION_INIT_GOLEM
		return REEL_ACTION_INIT_CHANSEY
	var biased: int = _random()
	if biased >= _percent(63):
		return REEL_ACTION_STOP_REEL3
	if biased >= _percent(31) + 1:
		return REEL_ACTION_START_SLOW_ADVANCE_REEL3
	return REEL_ACTION_INIT_GOLEM


## `SlotsAction_FlashScreen`: sixteen frames, the object palettes inverted on
## every other one, and `Slots_GetPals` putting them back at the end.
func _flash_screen() -> void:
	if _delay == 0:
		_objects_inverted = false
		_index += 1
		return
	var before: int = _delay
	_delay -= 1
	## `dec [hl]` then `srl a`: the shift reads the value before the decrement,
	## so the last frame of the sixteen is the one that inverts nothing.
	if (before >> 1) == 0:
		return
	_objects_inverted = not _objects_inverted


## `Slots_PayoutText`, which is the box and the win's own sound.
func _payout_text() -> void:
	if _matched == SLOTS_NO_MATCH:
		_print(&"darn")
		return
	match _matched:
		SLOTS_SEVEN:
			_play(SFX_2ND_PLACE)
			_roll_seven_streak()
		SLOTS_POKEBALL:
			_play(SFX_3RD_PLACE)
		_:
			_play(SFX_PRESENT)
	## Each of the three `.LinedUp*` routines ends in `WaitSFX`, and the box is
	## printed behind it rather than over it.
	_wait_then([{"kind": &"text", "name": &"lined_up"}])


## `.LinedUpSevens`' own tail: the rarer `wKeepSevenBiasChance` is the one with
## the *worse* odds of keeping the bias, which the source calls odd itself.
func _roll_seven_streak() -> void:
	var mask: int = 0b0011100 if _keep_seven_chance else 0b0010100
	if (_random() & mask) == 0:
		return
	_bias = SLOTS_NO_BIAS


## `SlotsAction_PayoutAnim`: one coin every other frame, a sound every eighth,
## and a coin case that has filled up takes no more.
func _payout_anim() -> void:
	_delay = (_delay + 1) & 0xFF
	if (_delay & 1) == 0:
		return
	if _payout == 0:
		_index += 1
		return
	_payout -= 1
	if _coins < MAX_COINS:
		_coins += 1
	if (_delay & 0x7) == 0:
		return
	_play(SFX_GET_COIN_FROM_SLOTS)


## `Slots_AskPlayAgain`. No coins left is the one exit that asks nothing.
func _ask_play_again() -> void:
	if _coins == 0:
		_print(&"ran_out_of_coins")
		_stall = RAN_OUT_FRAMES
		_index = SLOTS_QUIT
		return
	_print(&"play_again")
	_prompt = Prompt.PLAY_AGAIN
	_prompt_name = &"play_again"


## `Slots_SpinReels`, all three.
func _spin_reels() -> void:
	for reel: int in REELS:
		_spin_reel(reel)


## `.SpinReel`: the action runs on every sixteenth unit of distance, and the
## rate is added to the distance and to each object's own y.
func _spin_reel(index: int) -> void:
	var reel: Reel = _reels[index]
	if (reel.spin_distance & 0xF) == 0:
		_reel_action(index)
	var rate: int = reel.spin_rate
	if rate == 0:
		return
	reel.spin_distance = (reel.spin_distance + rate) & 0xFF
	if (reel.spin_distance & 0xF) == 0:
		_update_reel_objects(reel)
		return
	for object: int in reel.object_y.size():
		reel.object_y[object] = (reel.object_y[object] + rate) & 0xFF


## `Slots_UpdateReelPositionAndOAM`: the eight objects put back at the top of
## their travel, and the position stepped one symbol on.
func _update_reel_objects(reel: Reel) -> void:
	reel.object_y = PackedInt32Array()
	reel.object_symbols = PackedInt32Array()
	var y: int = REEL_TOP_Y
	var at: int = reel.position
	while y >= REEL_ROW_STEP * 2:
		var symbol: int = int(reel.strip[at]) if at < reel.strip.size() else 0
		reel.object_symbols.append(symbol)
		reel.object_y.append(y)
		reel.object_y.append(y)
		at += 1
		y -= REEL_ROW_STEP
	var next: int = (reel.position + 1) & 0xF
	reel.position = 0 if next == REEL_SIZE else next


## `ReelActionJumptable`, on the reel this pass is spinning.
func _reel_action(index: int) -> void:
	var reel: Reel = _reels[index]
	match reel.action:
		REEL_ACTION_DO_NOTHING:
			return
		REEL_ACTION_STOP_REEL_IGNORE_JOYPAD:
			_stop_reel_delay(reel)
		2, 3, REEL_ACTION_NORMAL_RATE, 5, 6:
			reel.spin_rate = [16, 8, 4, 2, 1][reel.action - 2]
		REEL_ACTION_STOP_REEL1:
			_action_stop_reel1(reel)
		REEL_ACTION_STOP_REEL2:
			_action_stop_reel2(reel)
		REEL_ACTION_STOP_REEL3:
			_action_stop_reel3(reel)
		REEL_ACTION_SET_UP_REEL2_SKIP_TO_7:
			_action_set_up_skip(reel)
		REEL_ACTION_WAIT_REEL2_SKIP_TO_7:
			_action_wait_skip(reel)
		REEL_ACTION_FAST_SPIN_REEL2_UNTIL_LINED_UP_7S:
			if _check_first_two(reel) and _first_two_sevens:
				_stop_reel(reel)
		REEL_ACTION_START_SLOW_ADVANCE_REEL3:
			_action_start_slow_advance(reel)
		REEL_ACTION_WAIT_SLOW_ADVANCE_REEL3:
			_action_wait_slow_advance(reel)
		REEL_ACTION_INIT_GOLEM:
			_action_init_golem(reel)
		REEL_ACTION_WAIT_GOLEM:
			_action_wait_golem(reel)
		REEL_ACTION_END_GOLEM:
			_delay = 0
			reel.action = REEL_ACTION_WAIT_GOLEM
			reel.spin_rate = 0
		REEL_ACTION_INIT_CHANSEY:
			_action_init_chansey(reel)
		REEL_ACTION_WAIT_CHANSEY:
			_action_wait_chansey(reel)
		REEL_ACTION_WAIT_EGG:
			_action_wait_egg(reel)
		REEL_ACTION_DROP_REEL:
			_action_drop_reel(reel)
		_:
			return


## `Slots_StopReel`, which is the rate, the ignore-joypad action and the delay.
func _stop_reel(reel: Reel) -> void:
	reel.spin_rate = 0
	reel.action = REEL_ACTION_STOP_REEL_IGNORE_JOYPAD
	reel.stop_delay = STOP_DELAY
	_stop_reel_delay(reel)


func _stop_reel_delay(reel: Reel) -> void:
	if reel.stop_delay == 0:
		reel.action = REEL_ACTION_DO_NOTHING
		return
	reel.stop_delay -= 1


## `ReelAction_StopReel1`: an unbiased spin stops where it stands; a biased one
## walks up to four further slots looking for its symbol anywhere in the window.
func _action_stop_reel1(reel: Reel) -> void:
	if _bias != SLOTS_NO_BIAS and reel.manip_counter > 0:
		reel.manip_counter -= 1
		## `.CheckForBias` returns Z when the symbol is in the window and the
		## caller's `ret nz` is what keeps the reel turning, so finding it is
		## what stops the reel rather than what lets it run on.
		var found: bool = false
		for symbol: int in reel.window():
			if symbol == _bias:
				found = true
		if not found:
			return
	_stop_reel(reel)


## `ReelAction_StopReel2`: the search stops once the two reels are building the
## biased symbol's own match.
func _action_stop_reel2(reel: Reel) -> void:
	if _check_first_two(reel) and _building_match == _bias:
		_stop_reel(reel)
		return
	if _bias != SLOTS_NO_BIAS and reel.manip_counter > 0:
		reel.manip_counter -= 1
		return
	_stop_reel(reel)


## `ReelAction_StopReel3`: a match the bias wants is kept, a match it does not
## is walked past, and an unbiased spin stops as soon as nothing is lined up.
func _action_stop_reel3(reel: Reel) -> void:
	if _check_all_three(reel):
		if _matched == _bias:
			_stop_reel(reel)
			return
		if reel.manip_counter == 0:
			return
		reel.manip_counter -= 1
		return
	if _bias != SLOTS_NO_BIAS and reel.manip_counter > 0:
		reel.manip_counter -= 1
		return
	_stop_reel(reel)


## `ReelAction_SetUpReel2SkipTo7`: reel two stops, waits and then spins fast
## until the sevens line up, which is most often only a way to raise hopes.
func _action_set_up_skip(reel: Reel) -> void:
	if _check_first_two(reel) and _first_two_sevens:
		_stop_reel(reel)
		return
	_play(SFX_STOP_SLOT)
	reel.action = REEL_ACTION_WAIT_REEL2_SKIP_TO_7
	reel.manip_delay = 32
	reel.spin_rate = 0


func _action_wait_skip(reel: Reel) -> void:
	if reel.manip_delay > 0:
		reel.manip_delay -= 1
		return
	_play(SFX_THROW_BALL)
	reel.action = REEL_ACTION_FAST_SPIN_REEL2_UNTIL_LINED_UP_7S
	reel.spin_rate = RATE_DOUBLE


## `ReelAction_StartSlowAdvanceReel3`: entered only from a match that must not
## be kept, and it advances a quarter rate for sixteen units before testing.
func _action_start_slow_advance(reel: Reel) -> void:
	if _check_all_three(reel):
		return
	_play(SFX_STOP_SLOT)
	_stall = WAIT_SFX_FRAMES
	reel.spin_rate = RATE_QUARTER
	reel.action = REEL_ACTION_WAIT_SLOW_ADVANCE_REEL3
	reel.manip_delay = 16


func _action_wait_slow_advance(reel: Reel) -> void:
	if reel.manip_delay > 0:
		reel.manip_delay -= 1
		_play(SFX_GOT_SAFARI_BALLS)
		return
	if _bias == SLOTS_SEVEN:
		## Seven is the one bias this mode can satisfy: it advances until the
		## sevens themselves are lined up and past anything else.
		if _check_all_three(reel) and _matched == SLOTS_SEVEN:
			_stop_reel(reel)
			_waiting_sfx = true
			return
		_play(SFX_GOT_SAFARI_BALLS)
		return
	## Every other bias, SLOTS_NO_BIAS included, advances until nothing is
	## lined up at all.
	if _check_all_three(reel):
		_play(SFX_GOT_SAFARI_BALLS)
		return
	_stop_reel(reel)
	_waiting_sfx = true


## `ReelAction_InitGolem`: the search runs first and the animation is handed the
## number of Golems it produced.
func _action_init_golem(reel: Reel) -> void:
	if _check_all_three(reel):
		return
	_play(SFX_STOP_SLOT)
	_stall = WAIT_SFX_FRAMES
	reel.action = REEL_ACTION_WAIT_GOLEM
	reel.spin_rate = 0
	_golem = {"jumptable": 0, "count": _number_of_golems(reel), "var1": 0, "x": 0, "y": 0}
	_delay = 0


func _action_wait_golem(reel: Reel) -> void:
	if _delay == 2:
		_check_all_three(reel)
		_stop_reel(reel)
		return
	if _delay != 1:
		return
	reel.action = REEL_ACTION_END_GOLEM
	reel.spin_rate = RATE_DOUBLE


## `ReelAction_InitChansey`: reachable only from a seven bias, and the egg is
## what advances the reel seventeen slots at a time until the sevens show up.
func _action_init_chansey(reel: Reel) -> void:
	if _check_all_three(reel):
		return
	_play(SFX_STOP_SLOT)
	_stall = WAIT_SFX_FRAMES
	reel.action = REEL_ACTION_WAIT_CHANSEY
	reel.spin_rate = 0
	_chansey = {"jumptable": 0, "x": 0, "var1": 0}
	_delay = 0


func _action_wait_chansey(reel: Reel) -> void:
	if _delay == 0:
		return
	reel.action = REEL_ACTION_WAIT_EGG
	_delay = 2
	_action_wait_egg(reel)


func _action_wait_egg(reel: Reel) -> void:
	if _delay < 4:
		return
	reel.action = REEL_ACTION_DROP_REEL
	reel.spin_rate = RATE_QUADRUPLE
	reel.manip_delay = 17
	_action_drop_reel(reel)


func _action_drop_reel(reel: Reel) -> void:
	if reel.manip_delay > 0:
		reel.manip_delay -= 1
		return
	if _check_all_three(reel) and _matched == SLOTS_SEVEN:
		_delay = 5
		_stop_reel(reel)
		return
	reel.spin_rate = 0
	reel.action = REEL_ACTION_WAIT_CHANSEY
	_delay = 1


## `Slots_GetNumberOfGolems`. The search walks the reel's own position and puts
## it back, so the count is known before a single Golem is drawn.
func _number_of_golems(reel: Reel) -> int:
	var saved: int = reel.position
	var count: int = 0
	if _bias == SLOTS_SEVEN:
		while true:
			reel.position += 1
			count += 1
			if _check_all_three(reel) and _matched == SLOTS_SEVEN:
				break
			if count > 0xFF:
				break
	else:
		var step: int = _random() & 0x7
		while step < 4:
			step = _random() & 0x7
		while true:
			reel.position = (reel.position + step) & 0xFF
			step += 1
			if not _check_all_three(reel):
				break
			if step > 0xFF:
				break
		count = step
	reel.position = saved
	return count


## `Slots_CheckMatchedFirstTwoReels`, on the reel the pass is spinning: the rows
## the bet pays for, compared against reel one's own stopped window.
func _check_first_two(reel: Reel) -> bool:
	_first_two_matching = false
	_first_two_sevens = false
	_building_match = SLOTS_NO_MATCH
	var current: PackedByteArray = reel.window()
	var first: PackedByteArray = _stopped[0]
	if first.size() < 3 or current.size() < 3:
		return false
	var lines: int = _bet & 3
	if lines >= 3:
		_store_first_two(first[0], current[1])
		_store_first_two(first[2], current[1])
	if lines >= 2:
		_store_first_two(first[0], current[0])
		_store_first_two(first[2], current[2])
	if lines >= 1:
		_store_first_two(first[1], current[1])
	return _first_two_matching


func _store_first_two(one: int, two: int) -> void:
	if one != two:
		return
	_building_match = one
	## `.StoreResult`'s own order: the sevens flag is set for a *non-zero*
	## symbol falling through, which is why zero is the one that sets it.
	if one == SLOTS_SEVEN:
		_first_two_sevens = true
	_first_two_matching = true


## `Slots_CheckMatchedAllThreeReels`. Leaves `wSlotMatched` behind it, which is
## what every caller reads next.
func _check_all_three(reel: Reel) -> bool:
	_matched = SLOTS_NO_MATCH
	var current: PackedByteArray = reel.window()
	var one: PackedByteArray = _stopped[0]
	var two: PackedByteArray = _stopped[1]
	if one.size() < 3 or two.size() < 3 or current.size() < 3:
		return false
	var lines: int = _bet & 3
	if lines >= 3:
		_store_match(one[0], two[1], current[2])
		_store_match(one[2], two[1], current[0])
	if lines >= 2:
		_store_match(one[0], two[0], current[0])
		_store_match(one[2], two[2], current[2])
	if lines >= 1:
		_store_match(one[1], two[1], current[1])
	return _matched != SLOTS_NO_MATCH


func _store_match(one: int, two: int, three: int) -> void:
	if one != three or one != two:
		return
	_matched = one


## `Slots_AnimateGolem`, `Slots_AnimateChansey` and
## `SpriteAnimFunc_SlotsChanseyEgg`, the objects `DoNextFrameForFirst16Sprites`
## pumps. All three write `wSlotsDelay`, which is what the reel actions above
## are waiting on, so none of them is decoration.
##
## Each is a Dictionary rather than a struct because a slot is either taken or
## empty: `DeinitializeSprite` clears the index and nothing else.
func _animate_objects() -> void:
	if not _golem.is_empty():
		_animate_golem()
	if not _chansey.is_empty():
		_animate_chansey()
	if not _egg.is_empty():
		_animate_egg()


## `Slots_AnimateGolem`: `.init` spends one Golem of the count the search
## produced, `.fall` drops it and `.roll` rolls it off the screen.
func _animate_golem() -> void:
	## `GetSpriteAnimFrame`'s own counter, which the frameset is read with.
	_golem["frames"] = int(_golem.get("frames", 0)) + 1
	match int(_golem.get("jumptable", 0)):
		0:
			if int(_golem.get("count", 0)) == 0:
				## The last Golem: the reel is let go rather than thrown at.
				_delay = 2
				_golem = {}
				return
			_golem["count"] = int(_golem["count"]) - 1
			_golem["jumptable"] = 1
			_golem["var1"] = 0x30
			_golem["x"] = 0
			_animate_golem_fall()
		1:
			_animate_golem_fall()
		_:
			_animate_golem_roll()


## `.fall`: `BattleAnim_Sine_e` of the counter as it walks $30 down to $20, and
## the landing sound at the bottom.
func _animate_golem_fall() -> void:
	var var1: int = int(_golem.get("var1", 0))
	if var1 >= 0x20:
		_golem["var1"] = var1 - 1
		_golem["y"] = _sine(var1, 14 * 8)
		return
	_golem["jumptable"] = 2
	_golem["var2"] = 2
	_delay = 1
	_play(SFX_PLACE_PUZZLE_PIECE_DOWN)


## `.roll`: two pixels a frame across nine tiles, and `hSCY` shaken by the sign
## of VAR2 every fourth of them, which is the screen jolting under the Golem.
func _animate_golem_roll() -> void:
	var x: int = int(_golem.get("x", 0))
	_golem["x"] = x + 2
	if x >= 9 * 8:
		_golem["jumptable"] = 0
		_golem["shake"] = 0
		return
	if (x & 0x3) != 0:
		return
	_golem["var2"] = (-int(_golem.get("var2", 0))) & 0xFF
	_golem["shake"] = int(_golem["var2"])


## `Slots_AnimateChansey` and the wrapper behind it: the walk on, the wait, the
## egg, and `SpriteAnimFunc_SlotsChansey`'s own `wSlotsDelay` 2 to 3, which is
## also where the second frameset is loaded.
func _animate_chansey() -> void:
	_chansey["frames"] = int(_chansey.get("frames", 0)) + 1
	match int(_chansey.get("jumptable", 0)):
		0:
			_animate_chansey_walk()
		1:
			_animate_chansey_wait()
		_:
			_animate_chansey_egg()
	if _chansey.is_empty() or _delay != 2:
		return
	_delay = 3
	## `_ReinitSpriteAnimFrame` loads `..._CHANSEY_2` and starts it from its own
	## first entry rather than carrying the count on.
	_chansey["frameset"] = 1
	_chansey["frames"] = 0


## `.walk`: one pixel a frame to thirteen tiles, a hop every sixteen.
func _animate_chansey_walk() -> void:
	var x: int = int(_chansey.get("x", 0))
	_chansey["x"] = x + 1
	if x == 13 * 8:
		_chansey["jumptable"] = 1
		_delay = 1
		_animate_chansey_wait()
		return
	if (x & 0xF) == 0:
		_play(SFX_JUMP_OVER_LEDGE)


## `.one`: `wSlotsDelay` of 2 opens the egg's own countdown and 5 takes Chansey
## off the screen, which is what `ReelAction_DropReel` writes on a match.
func _animate_chansey_wait() -> void:
	if _delay == 2:
		_chansey["jumptable"] = 2
		_chansey["var1"] = 8
		_animate_chansey_egg()
		return
	if _delay != 5:
		return
	_chansey = {}


## `.two`: eight frames and then the egg, after which the object goes back to
## `.one` and waits for the reel to answer.
func _animate_chansey_egg() -> void:
	var var1: int = int(_chansey.get("var1", 0))
	if var1 > 0:
		_chansey["var1"] = var1 - 1
		return
	_chansey["jumptable"] = 1
	## `depixel 12, 13, 0, 4`, which is (y, x) and so x 108, y 96 in shadow OAM.
	_egg = {"jumptable": 0, "x": 13 * 8 + 4, "y": 12 * 8}


## `SpriteAnimFunc_SlotsChanseyEgg`: the jumptable index is a counter running
## backwards, moving the egg right on its odd values and placing it on a sine of
## itself on the even ones. Past fifteen tiles it deletes itself, sets
## `wSlotsDelay` to 4 and drops.
func _animate_egg() -> void:
	var counter: int = int(_egg.get("jumptable", 0))
	_egg["jumptable"] = (counter - 1) & 0xFF
	if (counter & 1) != 0:
		var x: int = int(_egg.get("x", 0))
		if x >= 15 * 8:
			_egg = {}
			_delay = 4
			_play(SFX_PLACE_PUZZLE_PIECE_DOWN)
			return
		_egg["x"] = x + 1
	_egg["offset"] = _sine(counter, 32)


## `_Sine`, which is `calc_sine_wave` over the same `sine_table 32` the battle
## animations read: `a = d * sin(e * pi / 32)`, as a signed byte. Entry 16 is
## $0100 rather than $00FF, which is why the table is read and not derived.
static func _sine(angle: int, amplitude: int) -> int:
	var index: int = angle & 0x3F
	var negative: bool = index >= 0x20
	var at: int = (index & 0x1F) * 2
	var word: int = RomLayout.BATTLE_ANIM_SINE_WAVE[at] \
		| (RomLayout.BATTLE_ANIM_SINE_WAVE[at + 1] << 8)
	var value: int = (((amplitude & 0xFF) * word) >> 8) & 0xFF
	return (-value) & 0xFF if negative else value
