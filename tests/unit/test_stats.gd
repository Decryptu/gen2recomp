extends GutTest

## The stat arithmetic, against numbers a player could look up.
##
## Every figure asserted here is the published one for that Pokémon at that
## level, which is the point: the formula is easy to write in a form that is
## almost right, and a stat that is one out is invisible until a battle turns on
## it.


func test_the_square_root_is_a_ceiling_not_a_floor() -> void:
	# The cartridge scans a table of squares for the first entry that is not
	# smaller than the value, so it rounds up. Rounding down instead puts a
	# trained stat one out, which is exactly the kind of thing nothing catches.
	assert_eq(Gen2Stats.square_root(4), 2)
	assert_eq(Gen2Stats.square_root(5), 3, "not 2")
	assert_eq(Gen2Stats.square_root(64516), 254, "254 squared exactly")
	assert_eq(Gen2Stats.square_root(64517), 255)


func test_no_stat_experience_still_answers_one() -> void:
	# The table starts at one, so an untrained Pokémon gets 1, not 0. It divides
	# by four to nothing either way, which is why this is easy to get wrong and
	# never notice.
	assert_eq(Gen2Stats.square_root(0), 1)
	assert_eq(Gen2Stats.square_root(1), 1)


func test_stat_experience_stops_paying_at_the_end_of_the_table() -> void:
	# The most a full stat experience bar is worth is 63, because the table of
	# squares ends at 255 and the root is quartered.
	assert_eq(Gen2Stats.square_root(Gen2Stats.MAX_STAT_EXP), Gen2Stats.MAX_SQUARE_ROOT)


func test_a_fully_trained_pikachu_at_a_hundred() -> void:
	# Published maximums: 273 HP and 208 Attack.
	assert_eq(Gen2Stats.calculate(35, 15, Gen2Stats.MAX_STAT_EXP, 100, true), 273)
	assert_eq(Gen2Stats.calculate(55, 15, Gen2Stats.MAX_STAT_EXP, 100), 208)


func test_an_untrained_pikachu_at_a_hundred() -> void:
	# The same Pokémon with nothing invested: (35+15)*2 = 100, plus 110.
	assert_eq(Gen2Stats.calculate(35, 15, 0, 100, true), 210)
	assert_eq(Gen2Stats.calculate(55, 15, 0, 100), 145)


func test_hp_ends_differently_from_every_other_stat() -> void:
	# HP adds the level and ten; everything else adds five. Same Pokémon, same
	# base, so the gap is the ending and nothing else.
	assert_eq(Gen2Stats.calculate(50, 15, 0, 50, true), 125)
	assert_eq(Gen2Stats.calculate(50, 15, 0, 50), 70)


func test_a_level_one_pokemon_is_all_floor() -> void:
	assert_eq(Gen2Stats.calculate(5, 0, 0, 1), Gen2Stats.STAT_MIN_NORMAL + 0)
	assert_eq(Gen2Stats.calculate(5, 0, 0, 1, true), Gen2Stats.STAT_MIN_HP + 1)


func test_a_stat_is_capped() -> void:
	assert_eq(Gen2Stats.calculate(255, 15, Gen2Stats.MAX_STAT_EXP, 255), Gen2Stats.MAX_STAT_VALUE)


func test_hp_dv_is_assembled_from_the_low_bit_of_the_other_four() -> void:
	# It is not stored. The same nibbles decide whether the Pokémon is shiny.
	assert_eq(Gen2Stats.hp_dv(Gen2Stats.pack_dvs(15, 15, 15, 15)), 15)
	assert_eq(Gen2Stats.hp_dv(Gen2Stats.pack_dvs(0, 0, 0, 0)), 0)
	assert_eq(Gen2Stats.hp_dv(Gen2Stats.pack_dvs(1, 0, 0, 0)), 8, "attack is the top bit")
	assert_eq(Gen2Stats.hp_dv(Gen2Stats.pack_dvs(0, 0, 0, 1)), 1, "special is the bottom one")
	assert_eq(Gen2Stats.hp_dv(Gen2Stats.pack_dvs(14, 14, 14, 14)), 0, "even DVs contribute nothing")


func test_dvs_pack_into_the_word_the_cartridge_stores() -> void:
	var packed: int = Gen2Stats.pack_dvs(1, 2, 3, 4)
	assert_eq(Gen2Stats.attack_dv(packed), 1)
	assert_eq(Gen2Stats.defense_dv(packed), 2)
	assert_eq(Gen2Stats.speed_dv(packed), 3)
	assert_eq(Gen2Stats.special_dv(packed), 4)
	assert_eq(packed, 0x1234)


func test_a_stage_of_zero_leaves_a_stat_alone() -> void:
	assert_eq(Gen2Stats.apply_stage(100, 0), 100)


func test_the_drops_are_rounded_percentages_not_clean_fractions() -> void:
	# -1 is 66/100, not two thirds. On a stat of 150 the two disagree, and the
	# cartridge's answer is the lower one.
	assert_eq(Gen2Stats.apply_stage(150, -1), 99)
	assert_eq(Gen2Stats.apply_stage(100, -2), 50)
	assert_eq(Gen2Stats.apply_stage(100, -6), 25)


func test_the_rises_go_up_to_four_times() -> void:
	assert_eq(Gen2Stats.apply_stage(100, 1), 150)
	assert_eq(Gen2Stats.apply_stage(100, 2), 200)
	assert_eq(Gen2Stats.apply_stage(100, 6), 400)


func test_a_stage_never_takes_a_stat_below_one_or_above_the_cap() -> void:
	assert_eq(Gen2Stats.apply_stage(1, -6), 1)
	assert_eq(Gen2Stats.apply_stage(600, 6), Gen2Stats.MAX_STAT_VALUE)


func test_a_stage_past_the_ends_is_clamped_rather_than_read_off_the_table() -> void:
	assert_eq(Gen2Stats.apply_stage(100, 99), Gen2Stats.apply_stage(100, Gen2Stats.MAX_STAGE))
	assert_eq(Gen2Stats.apply_stage(100, -99), Gen2Stats.apply_stage(100, Gen2Stats.MIN_STAGE))
