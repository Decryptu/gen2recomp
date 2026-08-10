extends GutTest

## A Pokémon as a battle sees it: its stats, its PP and its stages.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"battletest", "0123456789abcdef")
	_data = Fixture.build(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


func test_a_pokemon_is_built_at_full_health_with_its_stats_worked_out() -> void:
	# Pikachu at 50 with perfect DVs and nothing trained.
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	assert_eq(mon.max_hp(), 110)
	assert_eq(mon.hp, 110)
	assert_eq(mon.stats["attack"], 75)
	assert_eq(mon.stats["defense"], 50)
	assert_eq(mon.stats["speed"], 110)
	assert_eq(mon.stats["sp_attack"], 70)
	assert_eq(mon.stats["sp_defense"], 60)


func test_the_two_special_stats_share_a_dv_and_differ_by_their_base() -> void:
	# Generation 2 split the special base stats and left the DV alone, so the two
	# halves move together for any given Pokémon.
	var mon: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 50, [], Gen2Stats.pack_dvs(15, 15, 15, 0)
	)
	assert_eq(mon.stats["sp_attack"], 55)
	assert_eq(mon.stats["sp_defense"], 45)


func test_a_species_the_cache_does_not_have_is_refused() -> void:
	# A battle with a Pokémon that has no base stats is not worth papering over.
	assert_null(Gen2BattleMon.create(_data, 9999, 50))
	assert_null(Gen2BattleMon.create(null, Fixture.PIKACHU, 50))


func test_a_single_type_pokemon_carries_its_type_twice() -> void:
	assert_eq(Gen2BattleMon.create(_data, Fixture.PIKACHU, 5).types(),
		[Fixture.ELECTRIC, Fixture.ELECTRIC])
	assert_eq(Gen2BattleMon.create(_data, Fixture.GEODUDE, 5).types(),
		[Fixture.ROCK, Fixture.GROUND])


func test_pp_comes_from_the_move_table() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT, Fixture.GROWL]
	)
	assert_eq(mon.pp_left(0), 15)
	assert_eq(mon.pp_left(1), 40)
	mon.spend_pp(0)
	assert_eq(mon.pp_left(0), 14)


func test_pp_never_goes_below_zero_and_an_empty_slot_answers_nothing() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT])
	for _spend: int in 30:
		mon.spend_pp(0)
	assert_eq(mon.pp_left(0), 0)
	assert_false(mon.can_use(0))
	assert_eq(mon.pp_left(3), 0, "a slot that holds nothing")
	assert_false(mon.can_use(3))


func test_a_pokemon_with_nothing_left_says_so() -> void:
	# What the cartridge answers Struggle to. Answering the question is this
	# class's job; deciding what to do about it is the battle's.
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT])
	assert_false(mon.is_out_of_pp())
	for _spend: int in 15:
		mon.spend_pp(0)
	assert_true(mon.is_out_of_pp())


func test_only_four_moves_fit() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 50,
		[Fixture.TACKLE, Fixture.GROWL, Fixture.EMBER, Fixture.THUNDERBOLT, Fixture.SLASH]
	)
	assert_eq(mon.moves.size(), Gen2BattleMon.MAX_MOVES)


func test_damage_comes_off_and_stops_at_zero() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	assert_eq(mon.take_damage(10), 10)
	assert_eq(mon.hp, 100)
	# The answer is what landed, not what was asked for, which is what a battle
	# reports.
	assert_eq(mon.take_damage(500), 100)
	assert_eq(mon.hp, 0)
	assert_true(mon.is_fainted())


func test_healing_stops_at_full() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.take_damage(30)
	assert_eq(mon.heal(500), 30)
	assert_eq(mon.hp, mon.max_hp())


func test_a_stage_changes_what_a_stat_reads_but_not_what_it_is() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.change_stage("attack", 2)
	assert_eq(mon.stat("attack"), 150)
	assert_eq(mon.unmodified_stat("attack"), 75, "the stat itself is untouched")


func test_stages_apply_to_the_stat_rather_than_to_each_other() -> void:
	# Six down and six up leaves the stat where it started. Compounding would
	# grind it away through twelve truncations instead.
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.change_stage("attack", -6)
	mon.change_stage("attack", 6)
	assert_eq(mon.stat("attack"), 75)


func test_a_stage_at_the_end_of_its_range_reports_that_it_did_not_move() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	assert_true(mon.change_stage("attack", 6))
	assert_false(mon.change_stage("attack", 1), "already at the top")
	assert_eq(mon.stage("attack"), Gen2Stats.MAX_STAGE)


func test_hp_has_no_stage() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	assert_false(mon.change_stage("hp", 2))
	assert_eq(mon.stat("hp"), 110)


func test_stages_reset() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.change_stage("speed", -4)
	mon.reset_stages()
	assert_eq(mon.stat("speed"), 110)


## A field added here and forgotten in [method Gen2BattleMon.reset_volatile]
## is a bug that only shows up after a switch, so every volatile field is set
## before this asks for a blank one back.
func test_every_volatile_field_clears() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.substatus = Gen2Substatus.CONFUSED | Gen2Substatus.FLINCHED
	mon.confusion_turns = 3
	mon.charged_move = Fixture.TACKLE
	mon.rollout_count = 4
	mon.rampage_turns = 2
	mon.rampage_move = Fixture.TACKLE
	mon.toxic_counter = 2
	mon.disabled_slot = 1
	mon.disable_turns = 4
	mon.encored_slot = 2
	mon.encore_turns = 3
	mon.last_move_used = Fixture.TACKLE
	mon.trapped_turns = 3
	mon.trapping_move = Fixture.TACKLE
	mon.perish_count = 2
	mon.substitute_hp = 25
	mon.turns_taken = 6
	mon.fury_cutter_count = 4
	mon.protect_count = 5
	mon.minimized = true

	mon.reset_volatile()

	assert_eq(mon.substatus, Gen2Substatus.NONE)
	assert_eq(mon.confusion_turns, 0)
	assert_eq(mon.charged_move, 0)
	assert_eq(mon.rollout_count, 0)
	assert_eq(mon.rampage_turns, 0)
	assert_eq(mon.rampage_move, 0)
	assert_eq(mon.toxic_counter, 0)
	assert_eq(mon.disabled_slot, -1)
	assert_eq(mon.disable_turns, 0)
	assert_eq(mon.encored_slot, -1)
	assert_eq(mon.encore_turns, 0)
	assert_eq(mon.last_move_used, 0)
	assert_eq(mon.trapped_turns, 0)
	assert_eq(mon.trapping_move, 0)
	assert_eq(mon.perish_count, 0)
	assert_eq(mon.substitute_hp, 0)
	assert_eq(mon.turns_taken, 0)
	assert_eq(mon.fury_cutter_count, 0)
	assert_eq(mon.protect_count, 0)
	assert_false(mon.minimized)


## Attract's "opposite gender" rule reads [method Gen2BattleMon.gender], which
## `GetGender` works out from the species ratio and the Attack and Speed DVs
## combined into one byte, not a coin flip. Bulbasaur is 12.5% female (ratio 31);
## Pikachu is an even 50/50 (ratio 127), which is why it checks the boundary,
## since a combined value equal to the ratio reads female.
func test_gender_reads_the_combined_dv_byte_against_the_species_ratio() -> void:
	var mostly_male := func(attack: int, speed: int) -> Gen2BattleMon:
		var dvs: int = Gen2Stats.pack_dvs(attack, 0, speed, 0)
		return Gen2BattleMon.create(_data, Fixture.BULBASAUR, 50, [], dvs)

	assert_eq(mostly_male.call(0, 0).gender(), &"male")
	assert_eq(mostly_male.call(15, 15).gender(), &"female")

	var even_odds := func(attack: int, speed: int) -> Gen2BattleMon:
		var dvs: int = Gen2Stats.pack_dvs(attack, 0, speed, 0)
		return Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [], dvs)

	# 126 is one under Pikachu's own ratio of 127; 127 is the ratio itself, and
	# the cartridge reads a value equal to the ratio as female, not male.
	assert_eq(even_odds.call(7, 14).gender(), &"male")
	assert_eq(even_odds.call(7, 15).gender(), &"female")


func test_gender_is_none_for_a_genderless_species() -> void:
	# Every species this fixture does not name outright reads a gender ratio of
	# 255, the cartridge's own "genderless" marker.
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, 6, 50)
	assert_eq(mon.gender(), &"genderless")


func test_a_pokemon_is_created_already_on_its_curve_not_at_zero() -> void:
	# Pikachu is medium fast, so a level 50 Pikachu is created already carrying
	# 50 cubed, not zero, the same as a box screen always agreeing with a
	# Pokémon's level.
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	assert_eq(mon.growth_rate(), Gen2Experience.GROWTH_MEDIUM_FAST)
	assert_eq(mon.base_exp(), 82)
	assert_eq(mon.exp, 125000)
	assert_eq(mon.level_for_exp(), 50)


func test_base_stat_exp_shape_uses_special_attacks_base_never_defenses() -> void:
	# Pikachu: 35/55/30/90/50/40. The shared "special" slot borrows Sp. Attack's
	# 50 and never Sp. Defense's 40, the same asymmetry the base stats table
	# itself carries.
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	assert_eq(mon.base_stat_exp_shape(), {
		"hp": 35, "attack": 55, "defense": 30, "speed": 90, "special": 50,
	})


func test_gaining_experience_can_cross_a_level_threshold() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	assert_eq(mon.level_for_exp(), 50)
	mon.gain_exp(132651 - 125000)
	assert_eq(mon.level_for_exp(), 51, "51 cubed is exactly 132651")


func test_experience_is_capped_at_the_three_byte_maximum() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.gain_exp(Gen2Experience.MAX_EXP)
	assert_eq(mon.exp, Gen2Experience.MAX_EXP)


func test_stat_experience_accumulates_across_more_than_one_gain() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.gain_stat_exp({"attack": 45, "speed": 90})
	mon.gain_stat_exp({"attack": 45, "hp": 35})
	assert_eq(mon.stat_exp.get("attack"), 90)
	assert_eq(mon.stat_exp.get("speed"), 90)
	assert_eq(mon.stat_exp.get("hp"), 35)


func test_stat_experience_gain_is_capped_the_same_as_training_it_by_hand() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.gain_stat_exp({"attack": Gen2Stats.MAX_STAT_EXP + 1000})
	assert_eq(mon.stat_exp.get("attack"), Gen2Stats.MAX_STAT_EXP)


func test_levelling_up_recalculates_stats_and_grows_current_hp_by_the_delta() -> void:
	# Pikachu's own max HP is 110 at 50 and 112 at 51: a Pokémon that took five
	# points of damage before levelling comes out with two more than it had,
	# not refilled and not left where it was.
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, 50)
	mon.take_damage(5)
	assert_eq(mon.hp, 105)

	mon.level_up()

	assert_eq(mon.level, 51)
	assert_eq(mon.max_hp(), 112)
	assert_eq(mon.hp, 107, "105 plus the two extra the new max hp is worth")


func test_levelling_up_refuses_past_the_cap() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(_data, Fixture.PIKACHU, Gen2Experience.MAX_LEVEL)
	var before_hp: int = mon.hp
	mon.level_up()
	assert_eq(mon.level, Gen2Experience.MAX_LEVEL)
	assert_eq(mon.hp, before_hp)


func test_rolled_dvs_stay_inside_a_nibble_each() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _roll: int in 200:
		var dvs: int = Gen2BattleMon.random_dvs(rng)
		assert_between(Gen2Stats.attack_dv(dvs), 0, Gen2Stats.MAX_DV)
		assert_between(Gen2Stats.special_dv(dvs), 0, Gen2Stats.MAX_DV)
		assert_eq(dvs & ~0xFFFF, 0)
