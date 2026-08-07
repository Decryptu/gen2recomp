extends GutTest

## TM/HM tables and gates against a synthetic cache built for this file, so the
## shared world fixture stays untouched.
##
## The table is TMHMMoves' real shape: fifty TMs, seven HMs, three tutors. Only
## the rows the tests name carry meaningful moves; the rest are filler, which is
## enough because every routine here indexes rather than searches by content.

const TM_COUNT: int = RomLayout.TMHM_TM_COUNT
const HM_COUNT: int = RomLayout.TMHM_HM_COUNT
const TUTOR_COUNT: int = 3
const ENTRY_COUNT: int = TM_COUNT + HM_COUNT + TUTOR_COUNT

## The four HM moves this project acts on, at their real TMNUMs: HM01 is 51.
const MOVE_CUT: int = 0x0F
const MOVE_SURF: int = 0x39
const MOVE_STRENGTH: int = 0x46
const MOVE_WHIRLPOOL: int = 0xFA
## TM01's move, so the first row is a real one too.
const MOVE_DYNAMICPUNCH: int = 0xDF

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testtmhm", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	var moves: Array = []
	for number: int in range(1, 0x100):
		moves.append({
			"number": number, "name": "MOVE%02X" % number, "effect": 0, "power": 40,
			"type": 0, "accuracy": 255, "pp": 10 + (number % 5), "effect_chance": 0,
		})
	moves[MOVE_CUT - 1]["name"] = "CUT"
	moves[MOVE_SURF - 1]["name"] = "SURF"
	moves[MOVE_STRENGTH - 1]["name"] = "STRENGTH"
	moves[MOVE_WHIRLPOOL - 1]["name"] = "WHIRLPOOL"
	moves[MOVE_DYNAMICPUNCH - 1]["name"] = "DYNAMICPUNCH"
	RomCache.write_json(RomCache.moves_path(_directory), moves)

	var table: Array = []
	for index: int in ENTRY_COUNT:
		# Filler rows sit in $60-$9b, which holds none of the named moves below,
		# so tmhm_number_for_move() cannot match two entries by accident.
		table.append(0x60 + index)
	table[0] = MOVE_DYNAMICPUNCH
	table[TM_COUNT + 0] = MOVE_CUT
	table[TM_COUNT + 2] = MOVE_SURF
	table[TM_COUNT + 3] = MOVE_STRENGTH
	table[TM_COUNT + 5] = MOVE_WHIRLPOOL
	RomCache.write_json(RomCache.tmhm_moves_path(_directory), table)

	# Species 1 learns HM04 (TMNUM 54) and TM01 (TMNUM 1); species 2 learns
	# neither. Bit index is TMNUM - 1, byte index >> 3, bit index & 7 from the
	# low bit, which is what SmallFarFlagAction does.
	RomCache.write_json(RomCache.species_path(_directory), [
		_species(1, [1, 54]), _species(2, []), _species(3, [51]),
	])
	RomCache.write_json(RomCache.items_path(_directory), [])
	RomCache.write_json(RomCache.types_path(_directory), [])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [])
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testtmhm",
		"sha1": "0123456789abcdef",
		"complete": true,
	})


func _species(number: int, learnable: Array) -> Dictionary:
	var flags: Array = []
	flags.resize(RomLayout.TMHM_BYTES)
	for index: int in flags.size():
		flags[index] = 0
	for tmnum: int in learnable:
		var bit: int = tmnum - 1
		flags[bit >> 3] = int(flags[bit >> 3]) | (1 << (bit & 7))
	return {"number": number, "name": "MON%d" % number, "tmhm": flags}


func _data() -> GameData:
	return GameData.open_directory(_directory)


## engine/items/items.asm's GetTMHMNumber and GetNumberedTMHM. The run is not
## contiguous: ITEM_C3 sits between TM04 and TM05 and ITEM_DC between TM28 and
## TM29, so a plain subtraction is wrong on either side of both.
func test_item_numbers_skip_the_two_dummy_items() -> void:
	for pair: Array in [
		[0xBF, 1], [0xC0, 2], [0xC2, 4],   # TM01, TM02, TM04
		[0xC4, 5], [0xDB, 28],             # TM05 and TM28 straddle ITEM_C3
		[0xDD, 29], [0xF2, 50],            # TM29 and TM50 straddle ITEM_DC
		[0xF3, 51], [0xF6, 54], [0xF9, 57],  # HM01, HM04, HM07
	]:
		assert_eq(
			RomLayout.tmhm_number_for_item(int(pair[0]), ENTRY_COUNT), int(pair[1]),
			"item $%02x" % int(pair[0])
		)
		assert_eq(
			RomLayout.item_for_tmhm_number(int(pair[1]), ENTRY_COUNT), int(pair[0]),
			"number %d" % int(pair[1])
		)
	# Both dummies and everything below TM01 have no number of their own.
	for item: int in [0x00, 0x01, 0xBE, 0xC3, 0xDC]:
		assert_eq(
			RomLayout.tmhm_number_for_item(item, ENTRY_COUNT), 0, "item $%02x" % item
		)
	# Every number in range maps to exactly one item and back.
	var seen: Dictionary = {}
	for number: int in range(1, ENTRY_COUNT + 1):
		var item: int = RomLayout.item_for_tmhm_number(number, ENTRY_COUNT)
		assert_false(seen.has(item), "item $%02x claimed twice" % item)
		seen[item] = true
		assert_eq(RomLayout.tmhm_number_for_item(item, ENTRY_COUNT), number)


func test_is_tm_hm_and_is_hm_follow_the_source_thresholds() -> void:
	assert_false(Gen2WorldTMHM.is_tm_hm(0xBE))
	assert_true(Gen2WorldTMHM.is_tm_hm(0xBF))
	assert_true(Gen2WorldTMHM.is_tm_hm(0xF6))
	assert_false(Gen2WorldTMHM.is_hm(0xF2))
	assert_true(Gen2WorldTMHM.is_hm(0xF3))
	assert_true(Gen2WorldTMHM.is_hm(0xF9))


func test_move_for_item_resolves_through_the_imported_table() -> void:
	var data: GameData = _data()
	assert_eq(Gen2WorldTMHM.move_for_item(data, 0xBF), MOVE_DYNAMICPUNCH)
	assert_eq(Gen2WorldTMHM.move_for_item(data, 0xF3), MOVE_CUT)
	assert_eq(Gen2WorldTMHM.move_for_item(data, 0xF5), MOVE_SURF)
	assert_eq(Gen2WorldTMHM.move_for_item(data, 0xF6), MOVE_STRENGTH)
	assert_eq(Gen2WorldTMHM.move_for_item(data, 0xF8), MOVE_WHIRLPOOL)
	# Not a TM/HM, and a dummy item inside the range.
	assert_eq(Gen2WorldTMHM.move_for_item(data, 0x12), 0)
	assert_eq(Gen2WorldTMHM.move_for_item(data, 0xC3), 0)
	assert_eq(Gen2WorldTMHM.move_for_item(null, 0xF6), 0)


func test_tmhm_number_for_move_is_the_inverse_of_tmhm_move() -> void:
	var data: GameData = _data()
	assert_eq(data.tmhm_moves().size(), ENTRY_COUNT)
	assert_eq(data.tmhm_number_for_move(MOVE_STRENGTH), 54)
	assert_eq(data.tmhm_move(54), MOVE_STRENGTH)
	assert_eq(data.tmhm_number_for_move(MOVE_CUT), 51)
	# A move no TM or HM teaches, and both ends of the range.
	assert_eq(data.tmhm_number_for_move(0), 0)
	assert_eq(data.tmhm_move(0), 0)
	assert_eq(data.tmhm_move(ENTRY_COUNT + 1), 0)


## CanLearnTMHMMove reads bit (TMNUM - 1) of the species' eight flag bytes, and
## SmallFarFlagAction counts that bit from the low end of its byte.
func test_can_learn_reads_the_species_flag_for_that_tm_number() -> void:
	var data: GameData = _data()
	assert_true(Gen2WorldTMHM.can_learn(data, 1, MOVE_STRENGTH))
	assert_true(Gen2WorldTMHM.can_learn(data, 1, MOVE_DYNAMICPUNCH))
	assert_false(Gen2WorldTMHM.can_learn(data, 1, MOVE_CUT))
	assert_false(Gen2WorldTMHM.can_learn(data, 2, MOVE_STRENGTH))
	assert_true(Gen2WorldTMHM.can_learn(data, 3, MOVE_CUT))
	assert_false(Gen2WorldTMHM.can_learn(data, 3, MOVE_STRENGTH))
	# .end: a move no TM/HM teaches leaves c at zero, which is "cannot learn".
	assert_false(Gen2WorldTMHM.can_learn(data, 1, 0x02))
	assert_false(Gen2WorldTMHM.can_learn(null, 1, MOVE_STRENGTH))


func test_knows_move_and_first_empty_slot_match_learn_moves_own_search() -> void:
	assert_true(Gen2WorldTMHM.knows_move([MOVE_CUT, 0, 0, 0], MOVE_CUT))
	assert_false(Gen2WorldTMHM.knows_move([MOVE_CUT, 0, 0, 0], MOVE_SURF))
	assert_eq(Gen2WorldTMHM.first_empty_slot([MOVE_CUT, 0, 0, 0]), 1)
	assert_eq(Gen2WorldTMHM.first_empty_slot([MOVE_CUT, MOVE_SURF, 0, MOVE_STRENGTH]), 2)
	assert_eq(
		Gen2WorldTMHM.first_empty_slot([MOVE_CUT, MOVE_SURF, MOVE_STRENGTH, MOVE_WHIRLPOOL]),
		-1
	)


## BootedTMText/BootedHMText then ContainedMoveText, which is the one prompt
## AskTeachTMHM shows before its yes/no.
func test_teach_prompt_names_the_move_and_distinguishes_a_tm_from_an_hm() -> void:
	var data: GameData = _data()
	var hm: Dictionary = Gen2WorldTMHM.teach_prompt(data, 0xF6)
	assert_true(hm["ok"])
	assert_true(hm["hm"])
	assert_eq(int(hm["move"]), MOVE_STRENGTH)
	assert_eq(String(hm["move_name"]), "STRENGTH")
	assert_eq(
		String(hm["text"]),
		"Booted up an HM. It contained STRENGTH. Teach STRENGTH to a #MON?"
	)

	var tm: Dictionary = Gen2WorldTMHM.teach_prompt(data, 0xBF)
	assert_true(tm["ok"])
	assert_false(tm["hm"])
	assert_true(String(tm["text"]).begins_with("Booted up a TM."))

	# .NotTMHM: an item below TM01 never reaches the prompt at all.
	var ordinary: Dictionary = Gen2WorldTMHM.teach_prompt(data, 0x12)
	assert_false(ordinary["ok"])
	assert_eq(StringName(ordinary["reason"]), &"not_a_tm_hm")
