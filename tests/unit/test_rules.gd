extends GutTest

## The rules object itself: what a mode answers, what an override does to it, and
## what survives the options file. Each flag's own BEHAVIOUR is tested where the
## branch is, at the layer that owns it, not here.

const FIRST_FLAG: StringName = &"belly_drum_boosts_below_half_hp"
const REPRODUCED_TODAY: StringName = &"metal_powder_overflow"


func after_each() -> void:
	Gen2Rules.install(null)


## The default is what shipped, which is a mix: some cartridge bugs are
## reproduced and some are corrected, and a mode is what makes that uniform.
func test_the_default_is_todays_behaviour_and_the_two_modes_are_its_ends() -> void:
	var rules := Gen2Rules.new()
	assert_eq(rules.mode, Gen2Rules.MODE_CURRENT)
	assert_eq(rules.mode_of(), Gen2Rules.MODE_CURRENT)
	assert_false(rules.reproduces(FIRST_FLAG))
	assert_true(rules.reproduces(REPRODUCED_TODAY), "reproduced before any flag existed")

	rules.set_mode(Gen2Rules.MODE_VANILLA)
	for flag: StringName in Gen2Rules.FLAGS:
		assert_true(rules.reproduces(flag), String(flag))
	rules.set_mode(Gen2Rules.MODE_QOL)
	for flag: StringName in Gen2Rules.FLAGS:
		assert_false(rules.reproduces(flag), String(flag))


func test_an_override_moves_one_flag_and_names_the_set_custom() -> void:
	var rules := Gen2Rules.new()
	assert_true(rules.set_flag(FIRST_FLAG, true))
	assert_true(rules.reproduces(FIRST_FLAG))
	assert_eq(rules.mode_of(), Gen2Rules.MODE_CUSTOM)
	# Set back to what the mode already says and the override is gone rather than
	# kept as a value that agrees with it.
	assert_true(rules.set_flag(FIRST_FLAG, false))
	assert_true(rules.overrides.is_empty())
	assert_eq(rules.mode_of(), Gen2Rules.MODE_CURRENT)

	assert_false(rules.set_flag(&"no_such_bug", true), "a flag this build lacks is refused")
	assert_true(rules.overrides.is_empty())


## A mode is a starting point, not a reset: what the player moved by hand stays
## moved. `clear_flags` is the reset.
func test_a_mode_change_keeps_a_hand_moved_flag() -> void:
	var rules := Gen2Rules.new()
	rules.set_flag(FIRST_FLAG, true)
	rules.set_mode(Gen2Rules.MODE_QOL)
	assert_true(rules.reproduces(FIRST_FLAG))
	assert_false(rules.reproduces(REPRODUCED_TODAY))
	assert_eq(rules.mode_of(), Gen2Rules.MODE_CUSTOM)

	# Under vanilla that same override agrees with the mode, so it stops being one.
	rules.set_mode(Gen2Rules.MODE_VANILLA)
	assert_true(rules.overrides.is_empty())
	assert_eq(rules.mode_of(), Gen2Rules.MODE_VANILLA)

	rules.set_flag(REPRODUCED_TODAY, false)
	rules.clear_flags()
	assert_eq(rules.mode_of(), Gen2Rules.MODE_VANILLA)


## Only the overrides are written, so a flag added by a later build is not
## recorded in a file that never chose it and keeps its own default.
func test_only_what_differs_is_written_and_read_back() -> void:
	var rules := Gen2Rules.new()
	rules.set_mode(Gen2Rules.MODE_VANILLA)
	rules.difficulty = Gen2Rules.DIFFICULTY_HARD
	rules.set_flag(REPRODUCED_TODAY, false)

	var written: Dictionary = rules.to_dict()
	assert_eq(written["mode"], String(Gen2Rules.MODE_VANILLA))
	assert_eq(written["flags"], {String(REPRODUCED_TODAY): false})

	var restored: Gen2Rules = Gen2Rules.parse(written)
	assert_true(restored.matches(rules))
	assert_eq(restored.difficulty, Gen2Rules.DIFFICULTY_HARD)
	assert_false(restored.reproduces(REPRODUCED_TODAY))
	assert_true(restored.reproduces(FIRST_FLAG))


func test_an_unreadable_block_falls_back_rather_than_refusing_the_rest() -> void:
	var rules: Gen2Rules = Gen2Rules.parse({
		"mode": "sideways", "difficulty": "impossible", "flags": {"no_such_bug": true},
	})
	assert_eq(rules.mode, Gen2Rules.MODE_CURRENT)
	assert_eq(rules.difficulty, Gen2Rules.DIFFICULTY_NORMAL)
	assert_true(rules.overrides.is_empty())
	assert_true(Gen2Rules.parse("not a block").matches(Gen2Rules.new()))


## The difficulty rewrites which AI layers score rather than inventing a level or
## a stat, so it can only ever ask for bits the scorer already reads.
func test_the_difficulty_rewrites_a_trainer_classes_own_ai_layers() -> void:
	var rules := Gen2Rules.new()
	var imported: int = RomLayout.AI_BASIC | RomLayout.AI_SMART
	assert_eq(rules.ai_move_weights(imported), imported, "normal is the cartridge's own")

	rules.difficulty = Gen2Rules.DIFFICULTY_EASY
	assert_eq(rules.ai_move_weights(imported), RomLayout.AI_BASIC)

	rules.difficulty = Gen2Rules.DIFFICULTY_HARD
	assert_eq(rules.ai_move_weights(imported), RomLayout.AI_MOVE_WEIGHTS_MASK)
	assert_eq(
		rules.ai_move_weights(0) & ~RomLayout.AI_MOVE_WEIGHTS_MASK, 0,
		"and never a bit the scorer does not read"
	)

	rules.difficulty = Gen2Rules.DIFFICULTY_NORMAL
	assert_eq(
		rules.ai_move_weights(RomLayout.AI_BASIC | (1 << 15)), RomLayout.AI_BASIC,
		"a patched trainer cannot smuggle one in either"
	)


## One installed set at a time, because the statics that read the rules
## ([Gen2Damage], [Gen2Experience], [Gen2BattleAI]) take no engine object and two
## sources would let them disagree with the battle they are resolving.
func test_the_installed_set_is_what_a_static_reads() -> void:
	assert_false(Gen2Rules.hardware(FIRST_FLAG))
	var rules := Gen2Rules.new()
	rules.set_flag(FIRST_FLAG, true)
	Gen2Rules.install(rules)
	assert_true(Gen2Rules.hardware(FIRST_FLAG))
	assert_same(Gen2Rules.active(), rules)

	Gen2Rules.install(null)
	assert_false(Gen2Rules.hardware(FIRST_FLAG), "and nothing is left installed")
	assert_false(Gen2Rules.hardware(&"no_such_bug"), "an unknown flag is not hardware")


func test_a_copy_is_independent_of_what_it_was_copied_from() -> void:
	var rules := Gen2Rules.new()
	rules.set_flag(FIRST_FLAG, true)
	var copy: Gen2Rules = rules.duplicate_rules()
	assert_true(copy.matches(rules))
	copy.set_flag(FIRST_FLAG, false)
	assert_true(rules.reproduces(FIRST_FLAG))
	assert_false(copy.matches(rules))
	assert_false(rules.matches(null))
