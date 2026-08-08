extends GutTest

## The experience arithmetic, against the published totals for each curve.
##
## Every figure is hand-worked from [code]CalcExpAtLevel[/code] rather than
## recomputed the way the code computes it, like [Gen2Damage]'s tests: a test
## that runs the formula to check the formula agrees with a wrong one just as
## readily.


func test_medium_fast_is_a_plain_cube() -> void:
	# The textbook curve, and the easiest to get right, which is why it opens
	# the file: if this one is wrong, nothing else is worth trusting either.
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_FAST, 2), 8)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_FAST, 7), 343)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_FAST, 50), 125000)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_FAST, 100), 1000000)


func test_fast_is_four_fifths_of_the_cube() -> void:
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_FAST, 50), 100000)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_FAST, 100), 800000)


func test_slow_is_five_quarters_of_the_cube() -> void:
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_SLOW, 50), 156250)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_SLOW, 100), 1250000)


func test_medium_slow_is_the_s_curve() -> void:
	# Bulbasaur's own curve, and the one the underflow bug lives on.
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_SLOW, 2), 9)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_SLOW, 7), 236)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_SLOW, 50), 117360)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_SLOW, 100), 1059860)


func test_the_two_curves_no_species_uses_still_answer_the_formula() -> void:
	# Slightly Fast and Slightly Slow: found in the growth rate table and named
	# in pokecrystal's own constants, but no species in Gold, Silver or Crystal
	# is on either. Worth a formula check anyway, since the table entry is real.
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_SLIGHTLY_FAST, 100), 849970)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_SLIGHTLY_SLOW, 100), 949930)


func test_level_one_is_zero_on_every_curve_not_the_formulas_underflow() -> void:
	# Medium Slow's own formula goes negative at level 1
	# (floor(6/5) - 15 + 100 - 140 = -54), which the real cartridge stores into
	# an unsigned three-byte total and calls a bug rather than a rule. A level 1
	# Pokémon has no experience by definition on every curve, underflow or not.
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_SLOW, 1), 0)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_FAST, 1), 0)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_FAST, 1), 0)
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_SLOW, 1), 0)


func test_level_never_goes_below_one_or_past_the_cap() -> void:
	assert_eq(Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_FAST, 0), 0)
	assert_eq(
		Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_FAST, 200),
		Gen2Experience.total_exp_at(Gen2Experience.GROWTH_MEDIUM_FAST, Gen2Experience.MAX_LEVEL),
	)


func test_level_for_exp_is_the_forward_curve_walked_backward() -> void:
	var rate: int = Gen2Experience.GROWTH_MEDIUM_FAST
	assert_eq(Gen2Experience.level_for_exp(rate, 0), 1)
	assert_eq(Gen2Experience.level_for_exp(rate, 7), 1, "one short of level 2's 8")
	assert_eq(Gen2Experience.level_for_exp(rate, 8), 2, "exactly level 2's own threshold")
	assert_eq(Gen2Experience.level_for_exp(rate, 342), 6, "one short of level 7's 343")
	assert_eq(Gen2Experience.level_for_exp(rate, 343), 7)
	assert_eq(Gen2Experience.level_for_exp(rate, 1000000), 100)
	assert_eq(Gen2Experience.level_for_exp(rate, Gen2Experience.MAX_EXP), 100, "never past the cap")


func test_award_is_base_exp_times_level_over_seven() -> void:
	# A level 7 Pidgey, base exp 46 (Falkner's own lead): 46*7/7 = 46 exactly,
	# chosen because the division cancels and is not itself the thing under
	# test here.
	assert_eq(Gen2Experience.award_for(7, 46, false), 46)
	# A level 9 Pidgeotto, base exp 65: floor(65*9/7) = floor(83.57) = 83.
	assert_eq(Gen2Experience.award_for(9, 65, false), 83)


func test_a_trainer_battle_adds_half_again_truncated() -> void:
	# 83 without the boost; with it, 83 + floor(83/2) = 83 + 41 = 124, not the
	# 124.5 a plain multiply by 1.5 would suggest.
	assert_eq(Gen2Experience.award_for(9, 65, true), 124)


func test_stat_exp_is_not_split_for_a_single_participant() -> void:
	var defeated: Dictionary = {
		"hp": 40, "attack": 45, "defense": 40, "speed": 56, "special": 35,
	}
	var out: Dictionary = Gen2Experience.stat_exp_gain(defeated, 1)
	assert_eq(out, defeated, "one participant keeps the whole base stat")


func test_stat_exp_splits_evenly_for_two_or_more_participants() -> void:
	var defeated: Dictionary = {
		"hp": 40, "attack": 45, "defense": 40, "speed": 56, "special": 35,
	}
	var out: Dictionary = Gen2Experience.stat_exp_gain(defeated, 2)
	assert_eq(out["hp"], 20)
	assert_eq(out["attack"], 22, "45 / 2 truncated, not rounded")
	assert_eq(out["speed"], 28)


func test_stat_exp_split_truncates_per_stat_not_on_the_total() -> void:
	var defeated: Dictionary = {
		"hp": 45, "attack": 49, "defense": 49, "speed": 45, "special": 65,
	}
	var out: Dictionary = Gen2Experience.stat_exp_gain(defeated, 3)
	assert_eq(out["hp"], 15)
	assert_eq(out["attack"], 16, "49 / 3 truncated")
	assert_eq(out["special"], 21, "65 / 3 truncated")


## The block is the five base stats and the base experience together, because
## the cartridge keeps them in one run of bytes and divides all of them in one
## loop before reading any of them back.
func test_the_shared_block_divides_base_exp_alongside_the_base_stats() -> void:
	var defeated: Dictionary = {
		"hp": 45, "attack": 49, "defense": 49, "speed": 45, "special": 65,
	}

	var alone: Dictionary = Gen2Experience.shared_block(defeated, 64, false, 1)
	assert_eq(alone["base_exp"], 64, "one recipient skips the division entirely")
	assert_eq(alone["stats"], defeated)

	var split: Dictionary = Gen2Experience.shared_block(defeated, 64, false, 3)
	assert_eq(split["base_exp"], 21, "64 / 3 truncated")
	assert_eq(split["stats"]["attack"], 16)


## Exp. Share halves every byte once, before any division, and the halving
## truncates on its own so it is not the same as dividing by twice as many.
func test_halving_for_an_exp_share_truncates_before_the_split() -> void:
	var defeated: Dictionary = {
		"hp": 45, "attack": 49, "defense": 49, "speed": 45, "special": 65,
	}

	var halved: Dictionary = Gen2Experience.shared_block(defeated, 65, true, 1)
	assert_eq(halved["base_exp"], 32, "65 / 2 truncated")
	assert_eq(halved["stats"]["attack"], 24, "49 / 2 truncated")

	var halved_and_split: Dictionary = Gen2Experience.shared_block(defeated, 65, true, 2)
	assert_eq(halved_and_split["base_exp"], 16, "floor(floor(65/2)/2)")
	assert_eq(halved_and_split["stats"]["special"], 16)


func test_stat_exp_gain_still_answers_for_the_stats_alone() -> void:
	var defeated: Dictionary = {
		"hp": 40, "attack": 45, "defense": 40, "speed": 56, "special": 35,
	}
	assert_eq(
		Gen2Experience.stat_exp_gain(defeated, 2),
		Gen2Experience.shared_block(defeated, 0, false, 2)["stats"]
	)
