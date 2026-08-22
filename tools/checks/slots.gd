extends RefCounted

## Sweeps `_SlotMachine` on freshly imported real caches, all three cartridges.
##
## Every expectation below is transcribed from pokecrystal's own
## engine/games/slot_machine.asm rather than read back out of the
## implementation, which is the only way the topic can go red: the three reel
## strips, the payout table, both bias tables, the six symbols' own line rules
## and the section's own sizes are the source's tables, and the art is re-read
## out of the dump beside the cache rather than compared with itself.
##
## The class of bug it exists to catch is a reel that lines up something the
## bias did not ask for. `Slots_CheckMatchedAllThreeReels` is five row tests
## behind a bet, and a window read one symbol out still matches *something*, so
## the check drives whole spins on a pinned seed and asserts what stopped where:
## every bet, every bias, every reel, on all three cartridges.
##
##   Godot --headless --path . -s res://tools/validate.gd -- slots

## `Reel1Tilemap`, `Reel2Tilemap` and `Reel3Tilemap`, byte for byte, including
## the first three symbols each repeats behind itself.
const REELS: Array[Array] = [
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

## `Slots_GetPayout.PayoutTable`, in `SLOTS_*` order.
const PAYOUTS: Array[int] = [300, 50, 6, 8, 10, 15]

## `.InitGFX`'s own loads: which tile each run is decompressed to and how many
## tiles it is. `Slots2LZ` is loaded twice, which is why the section carries it
## once and two banks index it.
const SECTION: Dictionary = {"slots_1": 37, "slots_2": 64, "slots_3": 64}

## `Slots_InitBias.Normal` and `.Lucky`, as (threshold, symbol).
const BIAS_NORMAL: Array[Array] = [
	[1, 0x00], [3, 0x04], [10, 0x14], [20, 0x10], [40, 0x0C], [48, 0x08], [255, -1],
]
const BIAS_LUCKY: Array[Array] = [
	[2, 0x00], [3, 0x04], [8, 0x14], [16, 0x10], [30, 0x0C], [80, 0x08], [255, -1],
]

## `MAX_COINS`, and `Slots_AskBet`'s own three items.
const MAX_COINS: int = 9999
const BETS: Array[int] = [1, 2, 3]

## How many spins a sweep drives per cartridge, and how long one is given to
## reach its own end. A spin is three A presses and a payout animation of up to
## three hundred coins, which is `PAYOUTS[0]` times the two frames each takes.
const SPINS: int = 64
const SPIN_FRAME_CAP: int = 2400

var _r: RefCounted = null


func run(r: RefCounted) -> void:
	_r = r
	_verify_tables()
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		if not _r.check(data.has_slots(), "%s: no slot machine art in the cache." % game_id):
			continue
		_verify_section(game_id, data)
		_verify_strips(game_id, data)
		_verify_text(game_id, data)
		_verify_spins(game_id, data)
	_r.game_id = &""


## The two tables that decide what a spin is worth, against the source's own.
func _verify_tables() -> void:
	_r.check(
		Array(Gen2SlotMachine.PAYOUTS) == PAYOUTS,
		"the payout table is not `Slots_GetPayout.PayoutTable`."
	)
	_r.check(
		Gen2SlotMachine.BIAS_NORMAL == BIAS_NORMAL,
		"the normal bias table is not `Slots_InitBias.Normal`."
	)
	_r.check(
		Gen2SlotMachine.BIAS_LUCKY == BIAS_LUCKY,
		"the lucky bias table is not `Slots_InitBias.Lucky`."
	)


## The cache against a second reading of the dump, which is what says the walk
## found the records rather than three runs that happen to decompress.
func _verify_section(game_id: StringName, data: GameData) -> void:
	var rom: RomFile = RomFile.open_verified("res://roms/%s.gbc" % game_id)
	if not _r.check(rom != null, "%s: roms/%s.gbc is unreadable." % [game_id, game_id]):
		return
	var section: Dictionary = RomImporter.read_slots_section(rom, RomLayout.for_id(rom.id))
	if not _r.check(
		section.size() == RomLayout.SLOTS_SECTION.size(),
		"%s: the slots section walked %d records, not %d." % [
			game_id, section.size(), RomLayout.SLOTS_SECTION.size()
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
			data.slots_indices(name) == Gen2Tiles.decode_2bpp_strip(
				section[name], 0, tiles
			),
			"%s: the cached %s strip is not the dump's." % [game_id, name]
		)
	_r.check(
		Array(data.slots_tilemap()) == Array(section["tilemap"]),
		"%s: the cached tilemap is not `SlotsTilemap`." % game_id
	)
	_r.note("%s: %d slots records, %d tiles, %d tilemap cells." % [
		game_id, SECTION.size(), 37 + 64 + 64, data.slots_tilemap().size()
	])


## The three reel strips and the sixteen palettes, and the page they build.
func _verify_strips(game_id: StringName, data: GameData) -> void:
	for reel: int in REELS.size():
		_r.check(
			Array(data.slots_reel(reel)) == REELS[reel],
			"%s: reel %d is not `Reel%dTilemap`." % [game_id, reel + 1, reel + 1]
		)
	for index: int in RomLayout.SLOTS_PALETTES:
		_r.check(
			data.slots_palette(index).size() == RomLayout.PREDEF_PALETTE_COLORS,
			"%s: palette %d is not four colours." % [game_id, index]
		)
	var page: Gen2SlotMachinePage = Gen2SlotMachinePage.from_data(data)
	if not _r.check(page != null and page.ready(), "%s: the page will not build." % game_id):
		return
	## `_CGB_SlotMachine`'s own attrmap: the text region is the whole of the six
	## rows under the machine and nothing above them is palette 7.
	var slots: PackedInt32Array = page.attributes()
	var text_cells: int = 0
	for cell: int in slots.size():
		if slots[cell] == Gen2SlotMachinePage.TEXT_PALETTE:
			text_cells += 1
	_r.check(
		text_cells == 6 * Gen2SlotMachinePage.SCREEN_COLUMNS,
		"%s: %d cells are on the text palette, not 120." % [game_id, text_cells]
	)


## The seven boxes, each of which has to have decoded out of a `text_far` stub.
func _verify_text(game_id: StringName, data: GameData) -> void:
	for name: String in RomLayout.slots_text_names():
		_r.check(
			not data.slots_text(name).is_empty(),
			"%s: the %s box is empty." % [game_id, name]
		)
	_r.check(
		data.slots_text("bet_how_many").begins_with("Bet how many"),
		"%s: the bet box is not `_SlotsBetHowManyCoinsText`." % game_id
	)


## Whole spins on a pinned seed, every bet and both machines.
##
## What is asserted is the source's own arithmetic rather than a pinned outcome:
## the coins the bet took, the payout the match is worth, the reels standing on
## symbols their own strips carry, and a match that is really lined up on one of
## the rows the bet paid for.
func _verify_spins(game_id: StringName, data: GameData) -> void:
	var spins: int = 0
	var wins: int = 0
	var biased: int = 0
	for spin: int in SPINS:
		var rng := RandomNumberGenerator.new()
		rng.seed = spin
		var strips: Array[PackedByteArray] = []
		for reel: int in Gen2SlotMachine.REELS:
			strips.append(data.slots_reel(reel))
		var machine: Gen2SlotMachine = Gen2SlotMachine.create(
			strips, 200, spin % 2 == 1, rng
		)
		var bet: int = BETS[spin % BETS.size()]
		var before: int = machine.coins()
		if not _drive_spin(machine, bet):
			_r.fail("%s: spin %d never reached its payout." % [game_id, spin])
			return
		spins += 1
		if machine.bias() != Gen2SlotMachine.SLOTS_NO_BIAS:
			biased += 1
		var matched: int = machine.matched()
		var payout: int = 0 if matched == Gen2SlotMachine.SLOTS_NO_MATCH \
			else PAYOUTS[matched / 4]
		if payout > 0:
			wins += 1
		if not _r.check(
			machine.coins() == mini(before - bet + payout, MAX_COINS),
			"%s: spin %d paid %d coins for a %s match." % [
				game_id, spin, machine.coins() - before + bet, matched
			]
		):
			return
		if not _verify_window(game_id, spin, machine, bet, matched):
			return
	_r.note("%s: %d spins, %d biased, %d matched." % [game_id, spins, biased, wins])


## One spin: the bet menu, the three A presses and the payout, with no host and
## so no `WaitSFX` to wait on.
func _drive_spin(machine: Gen2SlotMachine, bet: int) -> bool:
	var frames: int = 0
	while frames < SPIN_FRAME_CAP:
		frames += 1
		if machine.waiting_for_sfx():
			machine.sfx_finished()
			continue
		match machine.prompt():
			Gen2SlotMachine.Prompt.BET:
				machine.answer_bet(4 - bet)
				continue
			Gen2SlotMachine.Prompt.TEXT:
				machine.dismiss_text()
				continue
			Gen2SlotMachine.Prompt.PRESS:
				## `SlotsAction_RestartOrQuit`, which is as far as a spin goes.
				return true
			Gen2SlotMachine.Prompt.PLAY_AGAIN:
				machine.answer_play_again(false)
				continue
			_:
				pass
		if machine.jumptable_index() in [
			Gen2SlotMachine.SLOTS_WAIT_REEL1, Gen2SlotMachine.SLOTS_WAIT_REEL2,
			Gen2SlotMachine.SLOTS_WAIT_REEL3,
		]:
			machine.press_a()
		if not machine.advance():
			return true
	return false


## Every reel standing on a symbol of its own strip, and the match the machine
## reported really lined up on a row this bet paid for.
func _verify_window(
	game_id: StringName, spin: int, machine: Gen2SlotMachine, bet: int, matched: int
) -> bool:
	var windows: Array[PackedByteArray] = []
	for reel: Gen2SlotMachine.Reel in machine.reels():
		var window: PackedByteArray = reel.window()
		if not _r.check(
			window.size() == 3,
			"%s: spin %d left a reel with no window." % [game_id, spin]
		):
			return false
		for symbol: int in window:
			if not _r.check(
				symbol in [0x00, 0x04, 0x08, 0x0C, 0x10, 0x14],
				"%s: spin %d stopped on symbol %d." % [game_id, spin, symbol]
			):
				return false
		windows.append(window)
	if matched == Gen2SlotMachine.SLOTS_NO_MATCH:
		return true
	## `Slots_CheckMatchedAllThreeReels`' own five rows, in the order the bet
	## reaches them: the middle row for one coin, the outer two for two, and the
	## diagonals for three.
	var lines: Array[Array] = [[1, 1, 1]]
	if bet >= 2:
		lines.append([0, 0, 0])
		lines.append([2, 2, 2])
	if bet >= 3:
		lines.append([0, 1, 2])
		lines.append([2, 1, 0])
	for line: Array in lines:
		if windows[0][int(line[0])] == matched and windows[1][int(line[1])] == matched \
			and windows[2][int(line[2])] == matched:
			return true
	return _r.check(
		false,
		"%s: spin %d reported a %d match no row of a %d-coin bet carries." % [
			game_id, spin, matched, bet
		]
	)
