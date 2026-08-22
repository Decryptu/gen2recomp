extends RefCounted

## Sweeps `_CardFlip` on freshly imported real caches, all three cartridges.
##
## Every expectation below is transcribed from pokecrystal's own
## engine/games/card_flip.asm rather than read back out of the implementation,
## which is the only way the topic can go red: the win jumptable's own
## forty-eight entries, the deck's twenty-four pictures, the section's sizes and
## the board's own tilemap are the source's tables, and the art is re-read out
## of the dump beside the cache rather than compared with itself.
##
## The class of bug it exists to catch is a bet that pays the wrong cell.
## `CardFlip_CheckWinCondition` is a jumptable of forty-eight, most of whose
## entries differ from their neighbour by one bit test, so a cursor read one
## cell out still pays *something*. The check therefore drives the whole
## forty-eight by twenty-four grid against the jumptable rather than sampling,
## and drives whole games on a pinned seed for the rest: the shuffle, the deck's
## twelve rounds and the board's own discard marks.
##
##   Godot --headless --path . -s res://tools/validate.gd -- card_flip

## `_CardFlip`'s own loads: which run is decompressed to how many tiles.
const SECTION: Dictionary = {
	"card_flip_3": 7, "card_flip_off": 1, "card_flip_on": 1,
	"card_flip_1": 62, "card_flip_2": 52,
}

## `CardFlipTilemap` (gfx/card_flip/card_flip.tilemap), byte for byte.
const BOARD: Array[int] = [
	0xEF, 0x15, 0x27, 0x2A, 0x2A, 0x06, 0x27, 0x2A, 0x2A, 0x06, 0x27,
	0xEF, 0x07, 0x27, 0x3E, 0x3F, 0x42, 0x43, 0x46, 0x47, 0x4A, 0x4B,
	0xEF, 0x17, 0x26, 0x40, 0x41, 0x44, 0x45, 0x48, 0x49, 0x4C, 0x4D,
	0xEF, 0x25, 0x04, 0x00, 0x01, 0x00, 0x01, 0x00, 0x01, 0x00, 0x01,
	0xEF, 0x05, 0x14, 0x10, 0x11, 0x10, 0x11, 0x10, 0x11, 0x10, 0x11,
	0xEF, 0x16, 0x24, 0x20, 0x21, 0x20, 0x21, 0x20, 0x21, 0x20, 0x21,
	0xEF, 0x25, 0x04, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02,
	0xEF, 0x05, 0x14, 0x10, 0x12, 0x10, 0x12, 0x10, 0x12, 0x10, 0x12,
	0xEF, 0x16, 0x24, 0x20, 0x22, 0x20, 0x22, 0x20, 0x22, 0x20, 0x22,
	0xEF, 0x25, 0x04, 0x00, 0x03, 0x00, 0x03, 0x00, 0x03, 0x00, 0x03,
	0xEF, 0x05, 0x14, 0x10, 0x13, 0x10, 0x13, 0x10, 0x13, 0x10, 0x13,
	0xEF, 0x16, 0x24, 0x20, 0x23, 0x20, 0x23, 0x20, 0x23, 0x20, 0x23,
]

## `CardFlip_DisplayCardFaceUp.Deck`, both columns: the level as a character and
## the picture's own anchor tile, in card order.
const DECK: Array[Array] = [
	["1", 0x4E], ["1", 0x57], ["1", 0x69], ["1", 0x60],
	["2", 0x4E], ["2", 0x57], ["2", 0x69], ["2", 0x60],
	["3", 0x4E], ["3", 0x57], ["3", 0x69], ["3", 0x60],
	["4", 0x4E], ["4", 0x57], ["4", 0x69], ["4", 0x60],
	["5", 0x4E], ["5", 0x57], ["5", 0x69], ["5", 0x60],
	["6", 0x4E], ["6", 0x57], ["6", 0x69], ["6", 0x60],
]

## `CardFlip_CheckWinCondition.Jumptable`, one name per cell in its own order.
const JUMPTABLE: Array[String] = [
	"Impossible", "Impossible", "PikaJiggly", "PikaJiggly", "PoliOddish", "PoliOddish",
	"Impossible", "Impossible", "Pikachu", "Jigglypuff", "Poliwag", "Oddish",
	"OneTwo", "One", "PikaOne", "JigglyOne", "PoliOne", "OddOne",
	"OneTwo", "Two", "PikaTwo", "JigglyTwo", "PoliTwo", "OddTwo",
	"ThreeFour", "Three", "PikaThree", "JigglyThree", "PoliThree", "OddThree",
	"ThreeFour", "Four", "PikaFour", "JigglyFour", "PoliFour", "OddFour",
	"FiveSix", "Five", "PikaFive", "JigglyFive", "PoliFive", "OddFive",
	"FiveSix", "Six", "PikaSix", "JigglySix", "PoliSix", "OddSix",
]
## The entries that name one card outright, in `.CheckWin72`'s own `ld e` order.
const EXACT: Array[String] = [
	"PikaOne", "JigglyOne", "PoliOne", "OddOne",
	"PikaTwo", "JigglyTwo", "PoliTwo", "OddTwo",
	"PikaThree", "JigglyThree", "PoliThree", "OddThree",
	"PikaFour", "JigglyFour", "PoliFour", "OddFour",
	"PikaFive", "JigglyFive", "PoliFive", "OddFive",
	"PikaSix", "JigglySix", "PoliSix", "OddSix",
]
## The four single-Pokemon entries, in the `and $3` value each tests.
const SINGLE_MON: Array[String] = ["Pikachu", "Jigglypuff", "Poliwag", "Oddish"]
## The six single-number entries, in the `and $1c` value each tests.
const SINGLE_NUMBER: Array[String] = ["One", "Two", "Three", "Four", "Five", "Six"]
## The three two-number entries, in the `and $18` value each tests.
const NUMBER_PAIR: Array[String] = ["OneTwo", "ThreeFour", "FiveSix"]

## The eight boxes, in `data/text/common_3.asm`'s own order.
const TEXTS: Dictionary = {
	"play_with_three_coins": "Play with three\ncoins?",
	"not_enough_coins": "Not enough coins…",
	"choose_a_card": "Choose a card.",
	"place_your_bet": "Place your bet.",
	"play_again": "Want to play\nagain?",
	"shuffled": "The cards have\nbeen shuffled.",
	"yeah": "Yeah!",
	"darn": "Darn…",
}

## How many whole games a sweep drives per cartridge, and how long one is given
## to reach its own end. A round is two deals of twenty frames, a toggle, three
## flashes and a payout of up to seventy-two coins at two frames each.
const GAMES: int = 24
const GAME_FRAME_CAP: int = 24000

var _r: RefCounted = null


func run(r: RefCounted) -> void:
	_r = r
	_verify_win_conditions()
	_verify_cursor_walk()
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		if not _r.check(
			data.has_card_flip(), "%s: no card flip art in the cache." % game_id
		):
			continue
		_verify_section(game_id, data)
		_verify_text(game_id, data)
		_verify_cards(game_id, data)
		_verify_games(game_id, data)
	_r.game_id = &""


## `CardFlip_CheckWinCondition`, every cell against every card: the jumptable's
## own name decides what should pay, and the implementation is asked separately.
func _verify_win_conditions() -> void:
	var checked: int = 0
	for cell: int in JUMPTABLE.size():
		@warning_ignore("integer_division")
		var at := Vector2i(cell % Gen2CardFlip.CURSOR_COLUMNS, cell / Gen2CardFlip.CURSOR_COLUMNS)
		for card: int in Gen2CardFlip.DECK_SIZE:
			var wanted: int = _expected_payout(JUMPTABLE[cell], card)
			var got: int = Gen2CardFlip.payout_for(at, card)
			if not _r.check(
				got == wanted,
				"cell %d,%d (.%s) pays %d for card %d, not %d." % [
					at.x, at.y, JUMPTABLE[cell], got, card, wanted
				]
			):
				return
			checked += 1
	_r.note("%d cell and card pairs against `.Jumptable`." % checked)


## One jumptable entry's own branch, written as the test the source makes.
func _expected_payout(entry: String, card: int) -> int:
	match entry:
		"Impossible":
			return 0
		"PikaJiggly":
			return 0 if (card & 0x2) != 0 else Gen2CardFlip.PAYOUT_PAIR
		"PoliOddish":
			return Gen2CardFlip.PAYOUT_PAIR if (card & 0x2) != 0 else 0
		_:
			pass
	var index: int = NUMBER_PAIR.find(entry)
	if index >= 0:
		return Gen2CardFlip.PAYOUT_NUMBER_PAIR if (card & 0x18) == index * 8 else 0
	index = SINGLE_MON.find(entry)
	if index >= 0:
		return Gen2CardFlip.PAYOUT_MON if (card & 0x3) == index else 0
	index = SINGLE_NUMBER.find(entry)
	if index >= 0:
		return Gen2CardFlip.PAYOUT_NUMBER if (card & 0x1C) == index * 4 else 0
	index = EXACT.find(entry)
	return Gen2CardFlip.PAYOUT_EXACT if index >= 0 and card == index else 0


## `ChooseCard_HandleJoypad`: every cell the pad can walk to from the start, and
## the ones the source's own `.Impossible` entries prove it cannot. Each node is
## reached by replaying the presses that found it on a fresh table, since the
## cursor exists only inside `.PlaceYourBet` and nothing else can place it.
func _verify_cursor_walk() -> void:
	var paths: Dictionary = {Gen2CardFlip.CURSOR_START: PackedInt32Array()}
	var pending: Array[Vector2i] = [Gen2CardFlip.CURSOR_START]
	var steps: int = 0
	while not pending.is_empty():
		var at: Vector2i = pending.pop_back()
		for button: int in [
			Gen2Button.LEFT, Gen2Button.RIGHT, Gen2Button.UP, Gen2Button.DOWN
		]:
			var path: PackedInt32Array = (paths[at] as PackedInt32Array).duplicate()
			path.append(button)
			var next: Vector2i = _walked(path)
			steps += 1
			if paths.has(next):
				continue
			paths[next] = path
			pending.append(next)
	for cell: int in JUMPTABLE.size():
		@warning_ignore("integer_division")
		var at := Vector2i(cell % Gen2CardFlip.CURSOR_COLUMNS, cell / Gen2CardFlip.CURSOR_COLUMNS)
		var reachable: bool = paths.has(at)
		if not _r.check(
			reachable != (JUMPTABLE[cell] == "Impossible"),
			"cell %d,%d is %s and its entry is .%s." % [
				at.x, at.y, "reachable" if reachable else "unreachable", JUMPTABLE[cell]
			]
		):
			return
	_r.note("%d of %d cells reachable over %d pad steps, and the four .Impossible ones are not." % [
		paths.size(), JUMPTABLE.size(), steps
	])


## Where a run of presses leaves the cursor, driven through the game's own
## routine on a table that is waiting for a bet.
func _walked(path: PackedInt32Array) -> Vector2i:
	var game: Gen2CardFlip = _bet_ready(1)
	if game == null:
		return Gen2CardFlip.CURSOR_START
	for button: int in path:
		game.move_cursor(button)
	return game.cursor()


## A table driven to `.PlaceYourBet`, which is where the cursor exists at all.
func _bet_ready(seed: int) -> Gen2CardFlip:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var board := PackedByteArray()
	board.resize(RomLayout.CARD_FLIP_TILEMAP_BYTES)
	var game: Gen2CardFlip = Gen2CardFlip.create(board, 100, rng)
	for _frame: int in GAME_FRAME_CAP:
		if game.prompt() == Gen2CardFlip.Prompt.BET:
			return game
		game.advance()
		game.take_events()
		if game.waiting_for_sfx():
			game.sfx_finished()
		match game.prompt():
			Gen2CardFlip.Prompt.YES_NO:
				game.answer_yes_no(true)
			Gen2CardFlip.Prompt.PRESS:
				game.dismiss_text()
			Gen2CardFlip.Prompt.CHOOSE:
				game.press_a()
			_:
				pass
	return null


## The cache against a second reading of the dump, which is what says the walk
## found the records rather than five runs that happen to decompress.
func _verify_section(game_id: StringName, data: GameData) -> void:
	var rom: RomFile = RomFile.open_verified("res://roms/%s.gbc" % game_id)
	if not _r.check(rom != null, "%s: roms/%s.gbc is unreadable." % [game_id, game_id]):
		return
	var section: Dictionary = RomImporter.read_card_flip_section(
		rom, RomLayout.for_id(rom.id)
	)
	if not _r.check(
		section.size() == RomLayout.CARD_FLIP_SECTION.size() + 1,
		"%s: the card flip section walked %d records, not %d." % [
			game_id, section.size(), RomLayout.CARD_FLIP_SECTION.size() + 1
		]
	):
		return
	for name: String in SECTION:
		var tiles: int = int(SECTION[name])
		_r.check(
			int(section[name].size()) == tiles * Gen2Tiles.TILE_BYTES,
			"%s: %s is %d bytes, not %d tiles." % [
				game_id, name, section[name].size(), tiles
			]
		)
		_r.check(
			data.card_flip_indices(name) == Gen2Tiles.decode_2bpp_strip(
				section[name], 0, tiles
			),
			"%s: the cached %s strip is not the dump's." % [game_id, name]
		)
	_r.check(
		Array(data.card_flip_tilemap()) == BOARD,
		"%s: the cached tilemap is not `CardFlipTilemap`." % game_id
	)
	for index: int in RomLayout.CARD_FLIP_PALETTES:
		_r.check(
			data.card_flip_palette(index).size() == RomLayout.PREDEF_PALETTE_COLORS,
			"%s: card flip palette %d is not four colours." % [game_id, index]
		)
	_r.note("%s: %d card flip records, %d tiles, %d tilemap cells, %d palettes." % [
		game_id, SECTION.size(), 7 + 1 + 1 + 62 + 52, BOARD.size(),
		RomLayout.CARD_FLIP_PALETTES
	])


func _verify_text(game_id: StringName, data: GameData) -> void:
	for name: String in TEXTS:
		_r.check(
			data.card_flip_text(name) == String(TEXTS[name]),
			"%s: the %s box is \"%s\"." % [
				game_id, name, data.card_flip_text(name).replace("\n", "\\n")
			]
		)
	_r.note("%s: %d card flip boxes." % [game_id, TEXTS.size()])


## `CardFlip_DisplayCardFaceUp`: the level and the picture the page draws for
## every one of the twenty-four cards, against `.Deck` itself.
func _verify_cards(game_id: StringName, data: GameData) -> void:
	var page: Gen2CardFlipPage = Gen2CardFlipPage.from_data(data)
	if not _r.check(
		page != null and page.ready(), "%s: the card flip page did not build." % game_id
	):
		return
	for card: int in DECK.size():
		var row: Array = DECK[card]
		_r.check(
			RomLayout.FONT_DIGIT_ZERO_CODE + ((card & 0x1C) >> 2) + 1
				== int(Gen2Text.encode(String(row[0]))[0]),
			"%s: card %d is not level %s." % [game_id, card, row[0]]
		)
		_r.check(
			Gen2CardFlip.CARD_PIC_TILES[card & 0x3] == int(row[1]),
			"%s: card %d does not draw from tile $%02x." % [game_id, card, row[1]]
		)
	_r.note("%s: %d cards against `.Deck`." % [game_id, DECK.size()])


## Whole games on a pinned seed. What is asserted is what a reading gets wrong:
## every shuffle is a permutation of the twenty-four, no round deals a card the
## discard pile already holds, and the twelfth round reshuffles rather than
## running off the end of `wDeck`.
func _verify_games(game_id: StringName, data: GameData) -> void:
	var deals: int = 0
	for run: int in GAMES:
		var rng := RandomNumberGenerator.new()
		rng.seed = run + 1
		var page: Gen2CardFlipPage = Gen2CardFlipPage.from_data(data)
		if page == null:
			return
		var game: Gen2CardFlip = Gen2CardFlip.create(page.board(), 100, rng)
		var seen: Dictionary = {}
		var deck: PackedByteArray = PackedByteArray()
		var round_index: int = -1
		## `.ChooseACard`'s toggle swaps the lit card every four frames, so a
		## driver that presses A the instant the prompt appears always takes the
		## top one. Holding a different number of frames per run is what reaches
		## `wCardFlipWhichCard` 1 at all.
		var hold: int = run % (Gen2CardFlip.TOGGLE_FRAMES * 2)
		var held: int = 0
		for _frame: int in GAME_FRAME_CAP:
			if game.finished():
				break
			game.advance()
			game.take_events()
			if game.waiting_for_sfx():
				game.sfx_finished()
			match game.prompt():
				Gen2CardFlip.Prompt.YES_NO:
					game.answer_yes_no(true)
				Gen2CardFlip.Prompt.PRESS:
					game.dismiss_text()
				Gen2CardFlip.Prompt.CHOOSE:
					held += 1
					if held > hold:
						held = 0
						game.press_a()
				Gen2CardFlip.Prompt.BET:
					game.press_a()
				_:
					pass
			if game.state() != Gen2CardFlip.State.TABULATE_THE_RESULT \
				or game.cards_played() == round_index:
				continue
			round_index = game.cards_played()
			deals += 1
			## `.Continue`'s twelfth round reshuffles and clears the discard pile
			## with it, so a deck that is not the last one is where `seen` begins.
			if game.deck() != deck:
				deck = game.deck()
				seen = {}
			if not _verify_deal(game_id, run, game, seen):
				return
	_r.note("%s: %d games, %d cards dealt, every deck a permutation." % [
		game_id, GAMES, deals
	])


## One deal: the shuffle behind it and the card it turned over.
func _verify_deal(
	game_id: StringName, run: int, game: Gen2CardFlip, seen: Dictionary
) -> bool:
	var deck: PackedByteArray = game.deck()
	var present: Dictionary = {}
	for card: int in deck:
		present[card] = true
	if not _r.check(
		present.size() == Gen2CardFlip.DECK_SIZE,
		"%s: game %d shuffled a deck of %d distinct cards." % [
			game_id, run, present.size()
		]
	):
		return false
	var card: int = game.face_up_card()
	if not _r.check(
		not seen.has(card),
		"%s: game %d dealt card %d twice before a shuffle." % [game_id, run, card]
	):
		return false
	seen[card] = true
	return _r.check(
		game.discarded()[card] != 0,
		"%s: game %d turned card %d over without discarding it." % [game_id, run, card]
	)
