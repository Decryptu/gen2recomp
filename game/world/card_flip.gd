class_name Gen2CardFlip
extends RefCounted

## `_CardFlip`'s own state (engine/games/card_flip.asm), node-free.
##
## [Gen2CardFlipPage] owns the picture and [Gen2CardFlipScreen] the pump; this
## is `.MasterLoop`: one pass of `.Jumptable` a frame, with the background this
## screen writes kept here because almost everything the game shows is a
## tilemap write rather than a state a page could infer.
##
## Five things the source states that a reading gets wrong:
##
## - **The deck is dealt, not drawn.** `CardFlip_ShuffleDeck` fills `wDeck` with
##   an ordering once, and `.CheckTheCard` reads
##   `wDeck[wCardFlipNumCardsPlayed * 2 + wCardFlipWhichCard]`, so the two cards
##   on the table are the pair for this round and picking one decides which of
##   two known cards turns over. Twelve rounds exhaust the twenty-four.
## - **`.ChooseACard`'s toggle is the choice.** There is no cursor over the two
##   cards: `wCardFlipWhichCard` flips every four frames on its own and A takes
##   whichever is lit, which is what the border sprite is drawn on.
## - **A bet is one of forty-eight cells, and six of them are unreachable.**
##   `CollapseCursorPosition` is `y * 6 + x` and `CardFlip_CheckWinCondition`'s
##   jumptable has four `.Impossible` entries, which lose. The four exist
##   because `ChooseCard_HandleJoypad` cannot walk into columns 0 and 1 of the
##   two Pokemon rows and does not test for them.
## - **The board's own marks are drawn one round late.** `.KeepTheCurrentDeck`
##   calls `CardFlip_BlankDiscardedCardSlot` for the card just turned over, and
##   the pair it belongs to is what decides the tile: a cell whose other half is
##   already discarded gets `$3d` rather than its own triangle.
## - **A shuffle is not a reset.** `.Continue` reshuffles only on the twelfth
##   round, and `CardFlip_ShuffleDeck` clears `wDiscardPile` with it, so the
##   board's marks and the twelve lights are cleared by the same call.
##
## Randomness is injected: every `Random` here is a byte off the generator the
## caller owns, so a seeded run repeats.

## `CARDFLIP_DECK_SIZE`, which is four Pokemon by six levels.
const DECK_SIZE: int = 24
const MONS: int = 4
const LEVELS: int = 6
## `MAX_COINS`, which `.IsCoinCaseFull` refuses to pass.
const MAX_COINS: int = 9999
## `.DeductCoins`' own `cp 3`, and the `ld de, -3` behind it.
const COST: int = 3
## `.Continue`'s `cp 12`: a round is two cards, so twelve of them is the deck.
const ROUNDS: int = DECK_SIZE / 2

const SCREEN_COLUMNS: int = 20
const SCREEN_ROWS: int = 18

## `.Jumptable`'s eight entries, which `wJumptableIndex` walks.
enum State {
	ASK_PLAY_WITH_THREE,
	DEDUCT_COINS,
	CHOOSE_A_CARD,
	PLACE_YOUR_BET,
	CHECK_THE_CARD,
	TABULATE_THE_RESULT,
	PLAY_AGAIN,
	QUIT,
}

## What the loop is holding on, which is where the cartridge's own blocking call
## would have stood.
enum Prompt {
	NONE,
	## `YesNoBox`, for `.AskPlayWithThree` and `.PlayAgain`.
	YES_NO,
	## `.ChooseACard`'s `.loop`, which reads A alone while the pair toggles.
	CHOOSE,
	## `.PlaceYourBet`'s `.betloop`: the pad moves the cursor and A takes it.
	BET,
	## A `prompt`-terminated box, or `WaitPressAorB_BlinkCursor`.
	PRESS,
}

## The sound effects the routine names.
const SFX_WRONG: int = 0x19
const SFX_TRANSACTION: int = 0x22
const SFX_SLOT_MACHINE_START: int = 0x2C
const SFX_KINESIS: int = 0x2F
const SFX_POKEBALLS_PLACED_ON_TABLE: int = 0x03
const SFX_PAY_DAY: int = 0x68
const SFX_2ND_PLACE: int = 0x98
const SFX_CHOOSE_A_CARD: int = 0x9A
const SFX_QUIT_SLOTS: int = 0x9D
## `MUSIC_NONE` and the `MUSIC_GAME_CORNER` `_CardFlip` starts once its screen
## is up, which is the same track the map was already playing.
const MUSIC_NONE: int = 0x00
const MUSIC_GAME_CORNER: int = 0x12

## `.ChooseACard`'s two `ld c, 20` and the `ld c, 4` its toggle and its three
## flashes each spend.
const DEAL_FRAMES: int = 20
const TOGGLE_FRAMES: int = 4
## `.loop2`'s own `ld a, $3`.
const FLASHES: int = 3
## `.Payout`'s `ld c, 2` per coin.
const PAYOUT_FRAMES: int = 2

## The two boxes that end in `prompt` rather than `done`, which is the only
## thing that reaches `LoadBlinkingCursor`. `.TabulateTheResult` waits with
## `WaitPressAorB_BlinkCursor` on a box that loaded none, and the routine's own
## comment says so: no arrow blinks over "Yeah!" or "Darn…".
const PROMPT_TEXTS: Array[String] = ["not_enough_coins", "shuffled"]

## `CardFlip_InitTilemap`'s `ld a, $29`, which is the green felt.
const GREEN_TILE: int = 0x29
## `CardFlipTilemap` sits at `hlcoord 9, 0`; the two cards stand in the nine
## columns and twelve rows left of it, which `.ChooseACard` fills green.
const BOARD_AT: Vector2i = Vector2i(RomLayout.CARD_FLIP_TILEMAP_AT_COLUMN, 0)
const TABLE_SIZE: Vector2i = Vector2i(9, 12)
const CARD_SIZE: Vector2i = Vector2i(5, 6)
## `GetCoordsOfChosenCard`'s two `hlcoord`s, in the order `wCardFlipWhichCard`
## indexes them.
const CARD_AT: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 6)]

## `PlaceCardFaceDown.FaceDownCardTilemap` and
## `CardFlip_DisplayCardFaceUp.FaceUpCardTilemap`, five wide and six tall.
const FACE_DOWN_TILEMAP: Array[int] = [
	0x08, 0x09, 0x09, 0x09, 0x0A,
	0x0B, 0x28, 0x2B, 0x28, 0x0C,
	0x0B, 0x2C, 0x2D, 0x2E, 0x0C,
	0x0B, 0x2F, 0x30, 0x31, 0x0C,
	0x0B, 0x32, 0x33, 0x34, 0x0C,
	0x0D, 0x0E, 0x0E, 0x0E, 0x0F,
]
const FACE_UP_TILEMAP: Array[int] = [
	0x18, 0x19, 0x19, 0x19, 0x1A,
	0x1B, 0x35, 0x7F, 0x7F, 0x1C,
	0x0B, 0x28, 0x28, 0x28, 0x0C,
	0x0B, 0x28, 0x28, 0x28, 0x0C,
	0x0B, 0x28, 0x28, 0x28, 0x0C,
	0x1D, 0x1E, 0x1E, 0x1E, 0x1F,
]
## `.Deck`'s second column, the top-left tile of each Pokemon's three by three
## picture. Its first column is the level as a character and is the digit for
## the card's own level, so it is not a table here.
const CARD_PIC_TILES: Array[int] = [0x4E, 0x57, 0x69, 0x60]
## Where the level and the picture land inside the card, off the two `add hl`
## in `CardFlip_DisplayCardFaceUp`: `3 + SCREEN_WIDTH` and `SCREEN_HEIGHT` on
## top of it, which lands one column in and two rows down.
const CARD_LEVEL_AT: Vector2i = Vector2i(3, 1)
const CARD_PIC_AT: Vector2i = Vector2i(1, 2)
const CARD_PIC_SIZE: int = 3

## `CardFlip_BlankDiscardedCardSlot`'s six branches, by level: the row the pair
## of tiles starts on and the two tiles for a live pair, with `$3d` replacing
## whichever of them is the discarded half's own. The column is `13 + 2 * mon`
## in every branch.
const DISCARD_COLUMN: int = 13
const DISCARD_ROWS: Array[int] = [3, 4, 6, 7, 9, 10]
## (top tile, bottom tile, which of the two `$3d` replaces when the paired card
## is already discarded). `.Level1`, `.Level3` and `.Level5` mark the bottom and
## the even levels the top, which is the half of the cell each owns.
const DISCARD_TILES: Array[Array] = [
	[0x36, 0x37, 1],
	[0x3B, 0x3A, 0],
	[0x36, 0x38, 1],
	[0x3C, 0x3A, 0],
	[0x36, 0x39, 1],
	[0x3C, 0x3A, 0],
]
const DISCARD_BLANK_TILE: int = 0x3D
## `.Level1` looks four cards forward and `.Level2` four back, which is the
## other member of the pair sharing the cell.
const DISCARD_PAIR_STEP: int = 4

## `CardFlip_CheckWinCondition`'s payouts, by the kind of bet.
const PAYOUT_PAIR: int = 6
const PAYOUT_NUMBER_PAIR: int = 9
const PAYOUT_MON: int = 12
const PAYOUT_NUMBER: int = 18
const PAYOUT_EXACT: int = 72

## The cursor's own grid: `CollapseCursorPosition`'s `y * 6 + x`.
const CURSOR_COLUMNS: int = 6
const CURSOR_ROWS: int = 8
## `_CardFlip`'s own `ld a, $2` into both, which is Pikachu's column of the
## Pokemon row.
const CURSOR_START: Vector2i = Vector2i(2, 2)
## The two rows above the numbers: a pair of Pokemon and a single one.
const ROW_MON_PAIR: int = 0
const ROW_MON: int = 1
## The first number row. Rows from here on come in pairs, the even one of each
## being where a two-number bet stands.
const ROW_FIRST_NUMBER: int = 2
## Column 0 is a two-number bet, column 1 a single number and 2 to 5 a Pokemon.
const COLUMN_NUMBER_PAIR: int = 0
const COLUMN_NUMBER: int = 1
const COLUMN_FIRST_MON: int = 2

var _rng: RandomNumberGenerator = null
var _coins: int = 0
var _state: int = State.ASK_PLAY_WITH_THREE
var _prompt: int = Prompt.NONE
var _done: bool = false
## `wDeck`: the twenty-four cards in the order they are dealt.
var _deck: PackedByteArray = PackedByteArray()
## `wDiscardPile`, one flag a card.
var _discarded: PackedByteArray = PackedByteArray()
var _cards_played: int = 0
var _which_card: int = 0
var _face_up_card: int = -1
var _cursor: Vector2i = CURSOR_START
## `wTilemap` and `wAttrmap` for the twelve rows above the text box, which is
## every background write the routine makes.
var _tilemap: PackedByteArray = PackedByteArray()
var _attrmap: PackedByteArray = PackedByteArray()
## What is in shadow OAM: the border around the lit card, the bet cursor, or
## neither.
var _border_at: int = -1
var _cursor_visible: bool = false
## `CardFlipTilemap`, the board the cache carries.
var _board: PackedByteArray = PackedByteArray()
## Whether the box standing now loaded a cursor.
var _blinking: bool = false
## Frames left in whatever the current pass is spending, and where in the
## current state's own sequence the next pass picks up.
var _delay: int = 0
var _step: int = 0
## Half-steps left in `.loop2`'s three flashes, on then off.
var _flash_left: int = 0
var _waiting_for_sfx: bool = false
## Coins still to be paid out one at a time, and the payout's own frame counter.
var _payout_left: int = 0
var _events: Array = []


## [param coins] is `wCoins` and [param rng] the generator every `Random` is
## drawn from.
static func create(
	board: PackedByteArray, coins: int, rng: RandomNumberGenerator
) -> Gen2CardFlip:
	var game := Gen2CardFlip.new()
	game._rng = rng
	game._board = board
	game._coins = clampi(coins, 0, MAX_COINS)
	game._deck.resize(DECK_SIZE)
	game._discarded.resize(DECK_SIZE)
	game._tilemap.resize(SCREEN_COLUMNS * SCREEN_ROWS)
	game._attrmap.resize(SCREEN_COLUMNS * SCREEN_ROWS)
	game._init_tilemap()
	game._init_attributes()
	game._emit({"kind": &"music", "index": MUSIC_NONE})
	game._emit({"kind": &"music", "index": MUSIC_GAME_CORNER})
	game._enter_ask_play()
	return game


func _random() -> int:
	return _rng.randi() & 0xFF if _rng != null else 0


func coins() -> int:
	return _coins


func state() -> int:
	return _state


func prompt() -> int:
	return _prompt


func finished() -> bool:
	return _done


func cursor() -> Vector2i:
	return _cursor


func which_card() -> int:
	return _which_card


func face_up_card() -> int:
	return _face_up_card


func cards_played() -> int:
	return _cards_played


func deck() -> PackedByteArray:
	return _deck.duplicate()


func discarded() -> PackedByteArray:
	return _discarded.duplicate()


func tilemap() -> PackedByteArray:
	return _tilemap.duplicate()


func attributes() -> PackedByteArray:
	return _attrmap.duplicate()


## Which of the two cards the border sprite stands on, or -1 for no border.
func border_at() -> int:
	return _border_at


func cursor_visible() -> bool:
	return _cursor_visible


func waiting_for_sfx() -> bool:
	return _waiting_for_sfx


func sfx_finished() -> void:
	_waiting_for_sfx = false


func take_events() -> Array:
	var out: Array = _events
	_events = []
	return out


func _emit(event: Dictionary) -> void:
	_events.append(event)


func _text(name: String) -> void:
	_blinking = PROMPT_TEXTS.has(name)
	_emit({"kind": &"text", "name": name})


## Whether `LoadBlinkingCursor` put a "▼" in the box's corner.
func blinking_cursor() -> bool:
	return _blinking


func _sound(index: int) -> void:
	_emit({"kind": &"sound", "index": index})


## One pass of `.MasterLoop`. Answers false once `JUMPTABLE_EXIT_F` is set,
## which is what takes the screen down.
func advance() -> bool:
	if _done:
		return false
	## `YesNoBox` and `WaitPressAorB_BlinkCursor` do not return until the player
	## answers; `.ChooseACard`'s toggle and `.PlaceYourBet`'s cursor read the
	## joypad on frames the loop is still spending, so neither holds the pass.
	if _waiting_for_sfx or _prompt == Prompt.YES_NO or _prompt == Prompt.PRESS:
		return true
	if _delay > 0:
		_delay -= 1
		if _delay > 0:
			return true
	match _state:
		State.CHOOSE_A_CARD:
			_choose_a_card_pass()
		State.CHECK_THE_CARD:
			_check_the_card_pass()
		State.PLACE_YOUR_BET:
			_cursor_visible = true
		State.TABULATE_THE_RESULT:
			_payout_pass()
		State.QUIT:
			_quit_pass()
		_:
			pass
	return not _done


## `.AskPlayWithThree`, which is the loop's own entry and the one `.PlayAgain`
## does not return to.
func _enter_ask_play() -> void:
	_state = State.ASK_PLAY_WITH_THREE
	_text("play_with_three_coins")
	_prompt = Prompt.YES_NO


## `YesNoBox`'s answer for whichever of the two boxes is up.
func answer_yes_no(yes: bool) -> void:
	if _prompt != Prompt.YES_NO:
		return
	_prompt = Prompt.NONE
	if _state == State.ASK_PLAY_WITH_THREE:
		if not yes:
			_enter_quit()
			return
		_shuffle_deck()
		_enter_deduct()
		return
	if not yes:
		_enter_quit()
		return
	_continue_round()


## `WaitPressAorB_BlinkCursor` and every `prompt`-terminated box.
func dismiss_text() -> void:
	if _prompt != Prompt.PRESS:
		return
	_prompt = Prompt.NONE
	match _state:
		State.DEDUCT_COINS:
			_enter_quit()
		State.TABULATE_THE_RESULT:
			_enter_play_again()
		State.PLAY_AGAIN:
			_enter_deduct()
		_:
			pass


## A press of A, which `.ChooseACard` and `.PlaceYourBet` each read.
func press_a() -> void:
	match _prompt:
		Prompt.CHOOSE:
			_prompt = Prompt.NONE
			_sound(SFX_SLOT_MACHINE_START)
			_step = 4
			_flash_left = FLASHES * 2 - 1
			_delay = TOGGLE_FRAMES
			_border_at = _which_card
		Prompt.BET:
			_prompt = Prompt.NONE
			_enter_check_the_card()
		_:
			pass


## `.DeductCoins`: the balance is checked before it is charged, and a player who
## cannot pay is shown the line and then leaves.
func _enter_deduct() -> void:
	_state = State.DEDUCT_COINS
	if _coins < COST:
		_text("not_enough_coins")
		_prompt = Prompt.PRESS
		return
	_coins -= COST
	_sound(SFX_TRANSACTION)
	_waiting_for_sfx = true
	_enter_choose_a_card()


## `.ChooseACard`: the table is wiped, this round's light comes on, and the two
## cards are dealt twenty frames apart before the toggle starts.
func _enter_choose_a_card() -> void:
	_state = State.CHOOSE_A_CARD
	_step = 0
	_delay = 0
	_border_at = -1
	_cursor_visible = false
	_fill(Vector2i.ZERO, TABLE_SIZE, GREEN_TILE)
	_write(Vector2i(BOARD_AT.x, _cards_played), RomLayout.CARD_FLIP_LIGHT_ON_TILE)


## The deal and the toggle, one pass a frame.
func _choose_a_card_pass() -> void:
	match _step:
		0:
			_step = 1
			_delay = DEAL_FRAMES
		1:
			_place_card(0, FACE_DOWN_TILEMAP)
			_step = 2
			_delay = DEAL_FRAMES
		2:
			_place_card(1, FACE_DOWN_TILEMAP)
			_text("choose_a_card")
			_which_card = 0
			_toggle_pass()
		3:
			## `.loop`'s own `xor $1` runs at the end of an iteration, so the
			## card the border is standing on is the one A takes.
			_which_card ^= 1
			_toggle_pass()
		_:
			_flash_pass()


## `.loop`: the border is drawn on the lit card and four frames pass. A is read
## on every one of them, which is `Prompt.CHOOSE`.
func _toggle_pass() -> void:
	_sound(SFX_KINESIS)
	_border_at = _which_card
	_delay = TOGGLE_FRAMES
	_step = 3
	_prompt = Prompt.CHOOSE


## `.loop2`: three flashes of four frames on and four off, then the card that
## was not taken is wiped off the table.
func _flash_pass() -> void:
	if _flash_left > 0:
		_flash_left -= 1
		_border_at = -1 if _flash_left % 2 == 1 else _which_card
		_delay = TOGGLE_FRAMES
		return
	_border_at = -1
	_fill(CARD_AT[_which_card ^ 1], CARD_SIZE, GREEN_TILE)
	_enter_place_your_bet()


func _enter_place_your_bet() -> void:
	_state = State.PLACE_YOUR_BET
	_text("place_your_bet")
	_cursor_visible = true
	_prompt = Prompt.BET


## `ChooseCard_HandleJoypad`. [param direction] is a [enum Gen2Button] value.
func move_cursor(direction: int) -> void:
	if _prompt != Prompt.BET:
		return
	var moved: bool = false
	match direction:
		Gen2Button.LEFT:
			moved = _cursor_left()
		Gen2Button.RIGHT:
			moved = _cursor_right()
		Gen2Button.UP:
			moved = _cursor_up()
		Gen2Button.DOWN:
			moved = _cursor_down()
		_:
			return
	if moved:
		_sound(SFX_POKEBALLS_PLACED_ON_TABLE)


## `.d_left`. The two Pokemon rows step out of their own columns and land on
## `.left_to_number_gp`'s fixed cell rather than on column 1.
func _cursor_left() -> bool:
	if _cursor.y == ROW_MON_PAIR:
		_cursor.x &= 0xE
		if _cursor.x < 3:
			return _to_number_group()
		_cursor.x -= 2
		return true
	if _cursor.y == ROW_MON:
		if _cursor.x < 3:
			return _to_number_group()
		_cursor.x -= 1
		return true
	if _cursor.x == 0:
		return false
	_cursor.x -= 1
	return true


## `.d_right`.
func _cursor_right() -> bool:
	if _cursor.y == ROW_MON_PAIR:
		_cursor.x &= 0xE
		if _cursor.x >= 4:
			return false
		_cursor.x += 2
		return true
	if _cursor.x >= CURSOR_COLUMNS - 1:
		return false
	_cursor.x += 1
	return true


## `.d_up`. A two-number bet walks two rows at a time, since its own cell spans
## the pair.
func _cursor_up() -> bool:
	if _cursor.x == COLUMN_NUMBER_PAIR:
		_cursor.y &= 0xE
		if _cursor.y < 3:
			return _to_mon_group()
		_cursor.y -= 2
		return true
	if _cursor.x == COLUMN_NUMBER:
		if _cursor.y < 3:
			return _to_mon_group()
		_cursor.y -= 1
		return true
	if _cursor.y == 0:
		return false
	_cursor.y -= 1
	return true


## `.d_down`.
func _cursor_down() -> bool:
	if _cursor.x == COLUMN_NUMBER_PAIR:
		_cursor.y &= 0xE
		if _cursor.y >= CURSOR_ROWS - 2:
			return false
		_cursor.y += 2
		return true
	if _cursor.y >= CURSOR_ROWS - 1:
		return false
	_cursor.y += 1
	return true


## `.left_to_number_gp`, which every leftward step out of the Pokemon rows ends
## on whichever column it started in.
func _to_number_group() -> bool:
	_cursor = Vector2i(COLUMN_NUMBER, ROW_FIRST_NUMBER)
	return true


## `.up_to_mon_group`, its opposite.
func _to_mon_group() -> bool:
	_cursor = Vector2i(COLUMN_FIRST_MON, ROW_MON)
	return true


## `.CheckTheCard`: the card the deck already holds for this round is turned
## over and marked used.
func _enter_check_the_card() -> void:
	_state = State.CHECK_THE_CARD
	_cursor_visible = true
	_sound(SFX_CHOOSE_A_CARD)
	_waiting_for_sfx = true


## The card turns over on the pass behind that effect, which is the `WaitSFX`
## between `PlaySFX` and the read of `wDeck`.
func _check_the_card_pass() -> void:
	var index: int = _cards_played * 2 + _which_card
	_face_up_card = int(_deck[index]) if index < _deck.size() else 0
	_discarded[_face_up_card] = 1
	_place_card(_which_card, FACE_UP_TILEMAP)
	_draw_card_face(_which_card, _face_up_card)
	_enter_tabulate()


## `.TabulateTheResult`, which is `CardFlip_CheckWinCondition` and then a press.
func _enter_tabulate() -> void:
	_state = State.TABULATE_THE_RESULT
	var won: int = payout_for(_cursor, _face_up_card)
	if won <= 0:
		_sound(SFX_WRONG)
		_text("darn")
		_waiting_for_sfx = true
		_prompt = Prompt.PRESS
		return
	_text("yeah")
	_sound(SFX_2ND_PLACE)
	_waiting_for_sfx = true
	_payout_left = won
	## `.loop` adds the coin and *then* spends its `ld c, 2`, so the first is
	## paid on the pass the line goes up rather than two frames behind it.
	_delay = 0


## `.Payout`'s `.loop`: one coin every two frames, and a full case is counted
## without being paid.
func _payout_pass() -> void:
	if _payout_left <= 0:
		return
	_payout_left -= 1
	if _coins < MAX_COINS:
		_coins += 1
		_sound(SFX_PAY_DAY)
	if _payout_left > 0:
		_delay = PAYOUT_FRAMES
		return
	_prompt = Prompt.PRESS


## `.PlayAgain`.
func _enter_play_again() -> void:
	_state = State.PLAY_AGAIN
	_cursor_visible = false
	_border_at = -1
	_text("play_again")
	_prompt = Prompt.YES_NO


## `.Continue`: the round counter moves first, and the twelfth one is what
## reshuffles instead of marking the card just used.
func _continue_round() -> void:
	_cards_played += 1
	if _cards_played >= ROUNDS:
		_init_tilemap()
		_shuffle_deck()
		_text("shuffled")
		_prompt = Prompt.PRESS
		return
	_mark_discarded(_face_up_card)
	_enter_deduct()


func _enter_quit() -> void:
	_state = State.QUIT
	_prompt = Prompt.NONE
	_cursor_visible = false
	_border_at = -1
	_step = 0
	_sound(SFX_QUIT_SLOTS)
	_waiting_for_sfx = true


func _quit_pass() -> void:
	_done = true


## `CardFlip_ShuffleDeck`: an ordering rather than a shuffle. Each of the
## twenty-four values in turn is dropped into a slot rolled from `Random and
## $1f`, rerolled while the slot is out of range or already taken, so the value
## walks down from `CARDFLIP_DECK_SIZE - 1` to 1 and slot zero is whatever is
## left. That last card is card 0, which `dec c / jr nz` never writes.
func _shuffle_deck() -> void:
	for index: int in DECK_SIZE:
		_deck[index] = 0
	var value: int = DECK_SIZE - 1
	while value > 0:
		var slot: int = _random() & 0x1F
		if slot >= DECK_SIZE or _deck[slot] != 0:
			continue
		_deck[slot] = value
		value -= 1
	_cards_played = 0
	for index: int in DECK_SIZE:
		_discarded[index] = 0


## `CardFlip_CheckWinCondition`'s jumptable, as arithmetic on the same two
## numbers it branches on. Answers the coins the bet pays, or 0 for a loss.
static func payout_for(at: Vector2i, card: int) -> int:
	if card < 0 or card >= DECK_SIZE:
		return 0
	var mon: int = card & 0x3
	var level: int = (card & 0x1C) >> 2
	if at.y == ROW_MON_PAIR:
		## `.PikaJiggly` and `.PoliOddish`, which are the halves bit 1 splits.
		if at.x < COLUMN_FIRST_MON:
			return 0
		var upper: bool = at.x >= COLUMN_FIRST_MON + 2
		return PAYOUT_PAIR if (mon >= 2) == upper else 0
	if at.y == ROW_MON:
		if at.x < COLUMN_FIRST_MON:
			return 0
		return PAYOUT_MON if mon == at.x - COLUMN_FIRST_MON else 0
	var row: int = at.y - ROW_FIRST_NUMBER
	if at.x == COLUMN_NUMBER_PAIR:
		## `.OneTwo`, `.ThreeFour` and `.FiveSix`, which test `card and $18`:
		## the pair a row's own even half names.
		@warning_ignore("integer_division")
		var pair: int = row / 2
		@warning_ignore("integer_division")
		return PAYOUT_NUMBER_PAIR if level / 2 == pair else 0
	if at.x == COLUMN_NUMBER:
		return PAYOUT_NUMBER if level == row else 0
	## `.CheckWin72`: the cell names one card outright.
	return PAYOUT_EXACT if card == row * MONS + (at.x - COLUMN_FIRST_MON) else 0


## `CardFlip_InitTilemap`: the whole screen green, then `CardFlipTilemap` at
## column nine. The six rows the text box owns are left green here and drawn by
## the page, which is where `Textbox` puts them.
func _init_tilemap() -> void:
	for cell: int in _tilemap.size():
		_tilemap[cell] = GREEN_TILE
	_draw_board()


func _draw_board() -> void:
	for row: int in RomLayout.CARD_FLIP_TILEMAP_ROWS:
		for column: int in RomLayout.CARD_FLIP_TILEMAP_COLUMNS:
			_write(
				BOARD_AT + Vector2i(column, row),
				int(_board[row * RomLayout.CARD_FLIP_TILEMAP_COLUMNS + column])
			)


## `CardFlip_InitAttrPals`: the four Pokemon heads take their own palette and
## the light column takes the first, which is what makes a lit bulb yellow.
func _init_attributes() -> void:
	for cell: int in _attrmap.size():
		_attrmap[cell] = 0
	for mon: int in MONS:
		_fill_attributes(Vector2i(12 + mon * 2, 1), Vector2i(2, 2), mon + 1)
	_fill_attributes(BOARD_AT, Vector2i(1, RomLayout.CARD_FLIP_TILEMAP_ROWS), 1)


## `CardFlip_CopyToBox` for one of the two card slots.
func _place_card(slot: int, rows: Array[int]) -> void:
	var at: Vector2i = CARD_AT[slot]
	for row: int in CARD_SIZE.y:
		for column: int in CARD_SIZE.x:
			_write(at + Vector2i(column, row), rows[row * CARD_SIZE.x + column])


## `CardFlip_DisplayCardFaceUp`'s own two writes and its `CardFlip_FillBox`: the
## level as a character, the three by three picture under it, and the whole card
## on the Pokemon's own palette.
func _draw_card_face(slot: int, card: int) -> void:
	var at: Vector2i = CARD_AT[slot]
	var mon: int = card & 0x3
	var level: int = (card & 0x1C) >> 2
	_write(at + CARD_LEVEL_AT, RomLayout.FONT_DIGIT_ZERO_CODE + level + 1)
	var first: int = CARD_PIC_TILES[mon]
	for row: int in CARD_PIC_SIZE:
		for column: int in CARD_PIC_SIZE:
			_write(
				at + CARD_PIC_AT + Vector2i(column, row),
				first + row * CARD_PIC_SIZE + column
			)
	_fill_attributes(at, CARD_SIZE, mon + 1)


## `CardFlip_BlankDiscardedCardSlot`: the cell for the card just used, with the
## tile deciding whether its other half is already gone.
func _mark_discarded(card: int) -> void:
	if card < 0 or card >= DECK_SIZE:
		return
	var mon: int = card & 0x3
	var level: int = (card & 0x1C) >> 2
	var row: Array = DISCARD_TILES[level]
	var paired: int = card + (
		DISCARD_PAIR_STEP if level % 2 == 0 else -DISCARD_PAIR_STEP
	)
	var gone: bool = paired >= 0 and paired < DECK_SIZE and _discarded[paired] != 0
	var tiles: Array[int] = [int(row[0]), int(row[1])]
	if gone:
		tiles[int(row[2])] = DISCARD_BLANK_TILE
	var at := Vector2i(DISCARD_COLUMN + mon * 2, DISCARD_ROWS[level])
	_write(at, tiles[0])
	_write(at + Vector2i(0, 1), tiles[1])


func _fill(at: Vector2i, size: Vector2i, tile: int) -> void:
	for row: int in size.y:
		for column: int in size.x:
			_write(at + Vector2i(column, row), tile)


func _fill_attributes(at: Vector2i, size: Vector2i, palette: int) -> void:
	for row: int in size.y:
		for column: int in size.x:
			var cell: Vector2i = at + Vector2i(column, row)
			if cell.x < 0 or cell.x >= SCREEN_COLUMNS or cell.y < 0 \
				or cell.y >= SCREEN_ROWS:
				continue
			_attrmap[cell.y * SCREEN_COLUMNS + cell.x] = palette


func _write(at: Vector2i, tile: int) -> void:
	if at.x < 0 or at.x >= SCREEN_COLUMNS or at.y < 0 or at.y >= SCREEN_ROWS:
		return
	_tilemap[at.y * SCREEN_COLUMNS + at.x] = tile
