extends SceneTree

## Verifies the TM/HM table and compatibility flags against freshly imported
## real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## data/moves/tmhm_moves.asm's TMHMMoves, engine/items/items.asm's
## GetTMHMNumber and GetNumberedTMHM, engine/items/tmhm2.asm's CanLearnTMHMMove
## and engine/items/tmhm.asm's AskTeachTMHM and TeachTMHM. All are byte identical
## between the pins apart from one stubbed trainer-ranking call, so nothing here
## is profile split except the table's own length.
##
## The real-cartridge counterpart to tests/unit/test_world_tmhm.gd. The census is
## what actually pins it: every species' learnable set is compared against the
## table rather than spot checked, so a wrong flag bit order shows up at once.
##
##   Godot --headless --path . -s res://tools/validate_tmhm.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/item_constants.asm: fifty TMs and seven HMs in both games, plus
## Crystal's three move tutors. The first fifty-seven rows are byte identical.
const EXPECTED_ENTRIES: Dictionary = {
	&"gold": 57,
	&"silver": 57,
	&"crystal": 60,
}

## The four HM moves this project acts on, at their real TMNUMs. HM01 is 51, so
## these also pin where the TM run ends and the HM run starts.
const EXPECTED_HM_ROWS: Dictionary = {
	51: 0x0F,  # HM01 CUT
	52: 0x13,  # HM02 FLY
	53: 0x39,  # HM03 SURF
	54: 0x46,  # HM04 STRENGTH
	55: 0x94,  # HM05 FLASH
	56: 0xFA,  # HM06 WHIRLPOOL
	57: 0x7F,  # HM07 WATERFALL
}

## Census of the real caches, pinned so a cache change is loud: the total number
## of species-and-TM pairs the flags allow, over all 251 species. Both totals are
## counted independently from the pins' own data/pokemon/base_stats/*.asm `tmhm`
## lines, and Crystal's extra 220 are exactly its three move tutor rows.
const EXPECTED_LEARNABLE_PAIRS: Dictionary = {
	&"gold": 6372,
	&"silver": 6372,
	&"crystal": 6592,
}
## Caterpie, Ditto, Kakuna, Magikarp, Metapod, Smeargle, Unown, Weedle and
## Wobbuffet, the same nine in both games.
const EXPECTED_SPECIES_WITH_NONE: int = 9

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_table(game_id, data)
		_verify_item_numbers(game_id, data)
		_census(game_id, data)
	_finish()


func _verify_table(game_id: StringName, data: GameData) -> void:
	var table: Array[int] = data.tmhm_moves()
	_check(
		table.size() == int(EXPECTED_ENTRIES.get(game_id, -1)),
		"%s: TMHMMoves has %d entries, not the pinned %d." % [
			game_id, table.size(), int(EXPECTED_ENTRIES.get(game_id, -1)),
		]
	)
	for number: int in EXPECTED_HM_ROWS:
		var expected: int = int(EXPECTED_HM_ROWS[number])
		_check(
			data.tmhm_move(number) == expected,
			"%s: TM/HM %d teaches $%02X, not the pinned $%02X." % [
				game_id, number, data.tmhm_move(number), expected,
			]
		)
	# CanLearnTMHMMove takes the first match when it scans for a move, so a
	# duplicated row would silently shadow one of them.
	var seen: Dictionary = {}
	for move: int in table:
		_check(
			not seen.has(move),
			"%s: move $%02X appears in TMHMMoves twice." % [game_id, move]
		)
		seen[move] = true
		_check(
			not data.move(move).is_empty(),
			"%s: TMHMMoves names move $%02X, which the move table does not have." % [
				game_id, move,
			]
		)
	print("%s: %d TM/HM/tutor entries, HM01 through HM07 verified." % [game_id, table.size()])


## GetTMHMNumber and GetNumberedTMHM against every number the cartridge carries.
## The two dummy items inside the run are what make this worth checking: a plain
## subtraction is wrong on either side of both.
func _verify_item_numbers(game_id: StringName, data: GameData) -> void:
	var count: int = data.tmhm_moves().size()
	var claimed: Dictionary = {}
	for number: int in range(1, count + 1):
		var item: int = RomLayout.item_for_tmhm_number(number, count)
		_check(
			not claimed.has(item),
			"%s: item $%02X is claimed by two TM/HM numbers." % [game_id, item]
		)
		claimed[item] = number
		_check(
			RomLayout.tmhm_number_for_item(item, count) == number,
			"%s: item $%02X answers TM/HM %d, not %d." % [
				game_id, item, RomLayout.tmhm_number_for_item(item, count), number,
			]
		)
		_check(
			Gen2WorldTMHM.move_for_item(data, item) == data.tmhm_move(number),
			"%s: item $%02X teaches the wrong move for TM/HM %d." % [game_id, item, number]
		)
	for item: int in [RomLayout.ITEM_DUMMY_TM04_05, RomLayout.ITEM_DUMMY_TM28_29]:
		_check(
			RomLayout.tmhm_number_for_item(item, count) == 0,
			"%s: dummy item $%02X answered a TM/HM number." % [game_id, item]
		)
	# HM01 is where the HM run starts, which is also where ConsumeTM stops.
	_check(
		Gen2WorldTMHM.is_hm(RomLayout.ITEM_HM01)
			and not Gen2WorldTMHM.is_hm(RomLayout.ITEM_HM01 - 1),
		"%s: the HM threshold is not at $%02X." % [game_id, RomLayout.ITEM_HM01]
	)


## Every species against every TM/HM number, so a wrong bit order or byte order
## cannot hide behind a lucky spot check.
func _census(game_id: StringName, data: GameData) -> void:
	var table: Array[int] = data.tmhm_moves()
	var pairs: int = 0
	var species_with_none: int = 0
	for species: int in range(1, data.species_count() + 1):
		var flags: Array = data.species(species).get("tmhm", [])
		if not _check(
			flags.size() == RomLayout.TMHM_BYTES,
			"%s: species %d carries %d TM/HM flag bytes." % [game_id, species, flags.size()]
		):
			return
		var learnable: int = 0
		for number: int in range(1, table.size() + 1):
			if Gen2WorldTMHM.can_learn(data, species, data.tmhm_move(number)):
				learnable += 1
		# The top four bits of the eight-byte run are past the last TM/HM number
		# in both games, so no species may set them.
		var spare: int = int(flags[RomLayout.TMHM_BYTES - 1]) >> (table.size() - 56)
		_check(
			spare == 0,
			"%s: species %d sets a flag past TM/HM %d." % [game_id, species, table.size()]
		)
		pairs += learnable
		if learnable == 0:
			species_with_none += 1
	print("%s: %d learnable species/TM pairs, %d species learn none." % [
		game_id, pairs, species_with_none,
	])
	_check(
		pairs == int(EXPECTED_LEARNABLE_PAIRS.get(game_id, -1)),
		"%s: learnable census is %d, not the pinned %d." % [
			game_id, pairs, int(EXPECTED_LEARNABLE_PAIRS.get(game_id, -1)),
		]
	)
	_check(
		species_with_none == EXPECTED_SPECIES_WITH_NONE,
		"%s: %d species learn no TM or HM, not the pinned %d." % [
			game_id, species_with_none, EXPECTED_SPECIES_WITH_NONE,
		]
	)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS tmhm: table, item numbers and compatibility census verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
