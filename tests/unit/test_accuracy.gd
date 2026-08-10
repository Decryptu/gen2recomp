extends GutTest

## Whether a move connects, and the table it is decided with.


func test_accuracy_is_a_byte_out_of_255_not_a_percentage() -> void:
	# A move stored as 100% is 255 and one stored as 90% is 229. Converting to a
	# percentage would lose the special case below.
	assert_eq(Gen2Accuracy.chance(255), 255)
	assert_eq(Gen2Accuracy.chance(229), 229)


func test_a_full_accuracy_move_cannot_miss() -> void:
	# Rolling against 255 would miss one time in 256, and the cartridge goes out
	# of its way not to.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for _try: int in 2000:
		assert_true(Gen2Accuracy.rolls_hit(rng, Gen2Accuracy.ALWAYS_HITS))


func test_a_move_below_full_accuracy_rolls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hits: int = 0
	for _try: int in 4000:
		if Gen2Accuracy.rolls_hit(rng, 128):
			hits += 1
	assert_between(hits, 1800, 2200, "roughly half of 4000")


func test_the_accuracy_table_is_not_the_stat_table() -> void:
	# The two curves have different shapes, so a stage of -1 is 75% here and 66%
	# on a stat. Sharing one table is the easy mistake.
	assert_eq(Gen2Accuracy.apply_stage(100, -1), 75)
	assert_eq(Gen2Stats.apply_stage(100, -1), 66)


func test_lowering_accuracy_makes_a_sure_thing_missable() -> void:
	assert_eq(Gen2Accuracy.chance(255, -1), 191)
	assert_eq(Gen2Accuracy.chance(255, -6), 84)


func test_evasion_is_read_from_the_other_end_of_the_same_table() -> void:
	# The cartridge keeps one table and subtracts, rather than keeping two. An
	# evasion of +2 is the multiplier accuracy uses at -2.
	assert_eq(Gen2Accuracy.chance(255, 0, 2), Gen2Accuracy.chance(255, -2, 0))


func test_accuracy_and_evasion_do_not_quite_cancel() -> void:
	# 166/100 and 60/100 are not reciprocals, so +2 on each side leaves the move
	# very slightly missable rather than back where it started. That is the
	# cartridge's rounding and not an artefact of doing it in this order: the
	# table is a list of rounded percentages, and two of them rarely multiply
	# back to one.
	assert_eq(Gen2Accuracy.chance(255, 1, 1), 254)
	assert_eq(Gen2Accuracy.chance(255, 2, 2), 253)
	assert_eq(Gen2Accuracy.chance(255, 3, 3), 255, "+3 is a clean 2/1, so this pair does")


func test_a_raised_accuracy_is_capped_only_once_at_the_end() -> void:
	# The intermediate is allowed past 255 so that a raise and a matching evasion
	# come back to where they started. Capping between the two would lose it.
	assert_eq(Gen2Accuracy.chance(200, 6, 0), Gen2Accuracy.ALWAYS_HITS)
	assert_eq(Gen2Accuracy.chance(200, 6, 6), 198, "600 halved twice over, not 255 halved")


func test_accuracy_never_falls_to_nothing() -> void:
	assert_gt(Gen2Accuracy.chance(1, -6, 6), 0)


func test_foresight_drops_the_stages_only_when_they_are_against_the_attacker() -> void:
	# Narrower than it sounds: it cannot undo an accuracy the attacker raised.
	assert_eq(Gen2Accuracy.chance(255, 0, 6, true), 255, "the evasion is ignored")
	assert_eq(
		Gen2Accuracy.chance(255, 2, 0, true), Gen2Accuracy.chance(255, 2, 0),
		"a raised accuracy still counts, because the evasion is the lower stage"
	)


func test_a_stage_past_the_ends_is_clamped() -> void:
	assert_eq(Gen2Accuracy.apply_stage(100, 99), Gen2Accuracy.apply_stage(100, Gen2Stats.MAX_STAGE))
	assert_eq(Gen2Accuracy.apply_stage(100, -99), Gen2Accuracy.apply_stage(100, Gen2Stats.MIN_STAGE))


## `.StatModifiers`' Foresight branch: `cp b / jr c, .skip_foresight_check` puts it
## behind a comparison, then `ret nz` returns before the multipliers, so the
## stored byte stands and neither stage is applied.
func test_foresight_drops_both_stages_when_the_evasion_is_the_higher() -> void:
	# 90% cut by a +4 evasion, then the same pair identified.
	assert_eq(Gen2Accuracy.chance(229, 0, 4), 98)
	assert_eq(Gen2Accuracy.chance(229, 0, 4, true), 229)
	# Equal stages still take the branch, since the comparison is "at least".
	assert_lt(Gen2Accuracy.chance(229, 2, 2), 229)
	assert_eq(Gen2Accuracy.chance(229, 2, 2, true), 229)


## And it cannot undo an accuracy the attacker raised: the branch is only reached
## when the evasion is at least the accuracy.
func test_foresight_leaves_a_higher_accuracy_alone() -> void:
	assert_eq(
		Gen2Accuracy.chance(100, 4, 0, true), Gen2Accuracy.chance(100, 4, 0),
		"the accuracy is the higher stage, so the branch is skipped"
	)
	assert_gt(Gen2Accuracy.chance(100, 4, 0), 100)
