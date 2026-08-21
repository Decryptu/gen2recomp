extends GutTest

## `engine/events/daycare.asm` and `engine/pokemon/breeding.asm`, the rules half.
##
## Everything here is scene-free: the two slots are world state and
## [Gen2WorldDayCare] is static, so a case builds two Pokemon and reads an
## answer. The corpus sweep on real cartridges is `tools/checks/day_care.gd`; the
## point of these is the branches a corpus cannot single out, which is every one
## that turns on gender, on Ditto, or on the order two writes happen in.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

## The fixture's own species. Cubone and Hoothoot share EGG_FIELD, Bulbasaur is
## in two other groups, Marowak is the No Eggs species and Ditto is alone in its.
const CUBONE: int = Fixture.CUBONE
const MAROWAK: int = Fixture.MAROWAK
const HOOTHOOT: int = Fixture.HOOTHOOT
const BULBASAUR: int = Fixture.BULBASAUR
const IVYSAUR: int = 2
const DITTO: int = Fixture.DITTO

## Two DV words giving opposite genders at GENDER_F50, whose Defense DVs and
## Special low bits differ so `.CheckDVs` does not refuse the pair. The Attack
## and Speed nibbles are what `GetGender` reads: `$0` is male at a 127 ratio and
## `$F` is female.
const MALE_DVS: int = 0x0A05
const FEMALE_DVS: int = 0xF3FE

const CACHE_ID: StringName = &"daycaretest"
const CACHE_SHA1: String = "0123456789abcdef"

var _data: GameData = null


func before_each() -> void:
	_data = Fixture.build(RomCache.directory_for(CACHE_ID, CACHE_SHA1))


func _mon(species: int, dvs: int = MALE_DVS, ot_id: int = 100) -> Gen2SaveMon:
	var mon: Gen2SaveMon = Gen2SaveMon.new()
	mon.species = species
	mon.dvs = dvs
	mon.ot_id = ot_id
	mon.level = 10
	mon.hp = 20
	mon.exp = Gen2Experience.total_exp_at(
		int(_data.species(species).get("growth_rate", 0)), 10
	)
	mon.nickname = String(_data.species(species).get("name", ""))
	return mon


func _state() -> Gen2WorldState:
	return Gen2WorldState.new()


func _seeded(value: int) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = value
	return random


func test_a_no_eggs_species_is_refused_whatever_it_is_paired_with() -> void:
	assert_eq(
		Gen2WorldDayCare.compatibility(
			_data, _mon(MAROWAK, MALE_DVS), _mon(CUBONE, FEMALE_DVS)
		), 0
	)
	assert_eq(
		Gen2WorldDayCare.compatibility(
			_data, _mon(MAROWAK, MALE_DVS), _mon(DITTO, FEMALE_DVS)
		), 0
	)


func test_two_dittos_never_breed() -> void:
	assert_eq(
		Gen2WorldDayCare.compatibility(
			_data, _mon(DITTO, MALE_DVS), _mon(DITTO, FEMALE_DVS)
		), 0
	)


func test_ditto_breeds_with_a_genderless_species_no_other_pair_could() -> void:
	# `.genderless` is reached by the genderless parent and answered by the one
	# Ditto, which is the whole of why a Ditto pairing needs no gender at all.
	assert_gt(
		Gen2WorldDayCare.compatibility(_data, _mon(DITTO, MALE_DVS), _mon(CUBONE, FEMALE_DVS)),
		0
	)


func test_two_of_the_same_gender_are_refused() -> void:
	assert_eq(
		Gen2WorldDayCare.compatibility(
			_data, _mon(CUBONE, MALE_DVS, 100), _mon(HOOTHOOT, MALE_DVS + 0x0100, 200)
		), 0
	)


func test_matching_defence_and_special_dvs_are_the_255_refusal() -> void:
	# `.CheckDVs`, which answers 255 rather than 0: the pair reads as brimming
	# with energy and still never produces an egg.
	assert_eq(
		Gen2WorldDayCare.compatibility(
			_data, _mon(CUBONE, 0x0F05, 100), _mon(HOOTHOOT, 0xFF05, 200)
		), 255
	)
	assert_eq(Gen2WorldDayCare.compatibility_text_key(255), "brimming_with_energy")


func test_the_same_species_from_different_trainers_is_the_best_pair() -> void:
	assert_eq(
		Gen2WorldDayCare.compatibility(
			_data, _mon(CUBONE, MALE_DVS, 100), _mon(CUBONE, FEMALE_DVS, 200)
		), 254
	)


func test_a_shared_trainer_id_costs_seventy_seven() -> void:
	assert_eq(
		Gen2WorldDayCare.compatibility(
			_data, _mon(CUBONE, MALE_DVS, 100), _mon(CUBONE, FEMALE_DVS, 100)
		), 177
	)
	assert_eq(
		Gen2WorldDayCare.compatibility(
			_data, _mon(CUBONE, MALE_DVS, 100), _mon(HOOTHOOT, FEMALE_DVS, 100)
		), 51
	)


func test_the_five_compatibility_lines_are_the_routines_own_order() -> void:
	assert_eq(Gen2WorldDayCare.compatibility_text_key(0), "no_interest")
	assert_eq(Gen2WorldDayCare.compatibility_text_key(254), "appears_to_care")
	assert_eq(Gen2WorldDayCare.compatibility_text_key(177), "friendly")
	assert_eq(Gen2WorldDayCare.compatibility_text_key(51), "shows_interest")


func test_the_mother_is_the_female_and_the_non_ditto() -> void:
	assert_eq(
		Gen2WorldDayCare.mother_or_non_ditto(
			_data, _mon(CUBONE, FEMALE_DVS), _mon(HOOTHOOT, MALE_DVS)
		), Gen2WorldDayCare.SLOT_MAN
	)
	assert_eq(
		Gen2WorldDayCare.mother_or_non_ditto(
			_data, _mon(CUBONE, MALE_DVS), _mon(HOOTHOOT, FEMALE_DVS)
		), Gen2WorldDayCare.SLOT_LADY
	)
	# A Ditto decides it before any gender is read, in either slot.
	assert_eq(
		Gen2WorldDayCare.mother_or_non_ditto(
			_data, _mon(DITTO, FEMALE_DVS), _mon(CUBONE, FEMALE_DVS)
		), Gen2WorldDayCare.SLOT_LADY
	)


func test_the_egg_is_the_mothers_base_form() -> void:
	# Bulbasaur is the fixture's only evolution, so Ivysaur is the one species
	# with a pre-evolution to find.
	assert_eq(Gen2WorldDayCare.pre_evolution(_data, IVYSAUR), BULBASAUR)
	assert_eq(Gen2WorldDayCare.pre_evolution(_data, BULBASAUR), BULBASAUR)
	assert_eq(
		Gen2WorldDayCare.egg_species(_data, IVYSAUR, _seeded(1)), BULBASAUR
	)


func test_a_deposit_takes_the_member_out_of_the_party_whole() -> void:
	var state: Gen2WorldState = _state()
	var save: Gen2SaveData = Gen2SaveData.new()
	save.party = [_mon(CUBONE), _mon(HOOTHOOT)]
	assert_true(Gen2WorldDayCare.deposit(state, save, Gen2WorldDayCare.SLOT_MAN, 0))
	assert_eq(save.party.size(), 1)
	assert_true(state.day_care_has_mon(Gen2WorldDayCare.SLOT_MAN))
	assert_eq(state.day_care_mon(Gen2WorldDayCare.SLOT_MAN).species, CUBONE)


func test_a_slot_gains_one_point_of_experience_a_step() -> void:
	var state: Gen2WorldState = _state()
	var save: Gen2SaveData = Gen2SaveData.new()
	save.party = [_mon(CUBONE), _mon(HOOTHOOT)]
	Gen2WorldDayCare.deposit(state, save, Gen2WorldDayCare.SLOT_MAN, 0)
	var before: int = state.day_care_mon(Gen2WorldDayCare.SLOT_MAN).exp
	Gen2WorldDayCare.step(state, _data, _seeded(3))
	assert_eq(state.day_care_mon(Gen2WorldDayCare.SLOT_MAN).exp, before + 1)


func test_a_slot_at_the_level_cap_gains_nothing() -> void:
	var state: Gen2WorldState = _state()
	var mon: Gen2SaveMon = _mon(CUBONE)
	mon.level = Gen2WorldDayCare.MAX_LEVEL
	state.set_day_care_mon(Gen2WorldDayCare.SLOT_MAN, mon)
	state.set_day_care_has_mon(Gen2WorldDayCare.SLOT_MAN, true)
	var before: int = state.day_care_mon(Gen2WorldDayCare.SLOT_MAN).exp
	Gen2WorldDayCare.step(state, _data, _seeded(3))
	assert_eq(state.day_care_mon(Gen2WorldDayCare.SLOT_MAN).exp, before)


func test_a_retrieval_costs_a_hundred_a_level_plus_a_hundred() -> void:
	assert_eq(Gen2WorldDayCare.price_to_retrieve(0), 100)
	assert_eq(Gen2WorldDayCare.price_to_retrieve(7), 800)


func test_a_retrieved_member_comes_back_at_the_level_its_experience_bought() -> void:
	var state: Gen2WorldState = _state()
	var save: Gen2SaveData = Gen2SaveData.new()
	save.party = [_mon(CUBONE), _mon(HOOTHOOT)]
	Gen2WorldDayCare.deposit(state, save, Gen2WorldDayCare.SLOT_MAN, 0)
	var grown: Gen2SaveMon = state.day_care_mon(Gen2WorldDayCare.SLOT_MAN)
	var growth_rate: int = int(_data.species(CUBONE).get("growth_rate", 0))
	grown.exp = Gen2Experience.total_exp_at(growth_rate, 14) + 500
	state.set_day_care_mon(Gen2WorldDayCare.SLOT_MAN, grown)
	assert_eq(Gen2WorldDayCare.level_growth(_data, grown), 4)
	var out: Dictionary = Gen2WorldDayCare.retrieve(
		state, save, _data, Gen2WorldDayCare.SLOT_MAN
	)
	assert_eq(int(out["level"]), 14)
	assert_false(state.day_care_has_mon(Gen2WorldDayCare.SLOT_MAN))
	var back: Gen2SaveMon = save.party[int(out["party_index"])]
	# `CalcExpAtLevel` writes the experience back to the bottom of the level it
	# just reached, which is the source's own documented loss.
	assert_eq(back.exp, Gen2Experience.total_exp_at(growth_rate, 14))
	assert_eq(back.status, Gen2Status.NONE)
	assert_gt(back.hp, 0)


func test_a_full_party_cannot_take_a_member_back() -> void:
	var state: Gen2WorldState = _state()
	var save: Gen2SaveData = Gen2SaveData.new()
	for _slot: int in Gen2SaveData.MAX_PARTY:
		save.party.append(_mon(HOOTHOOT))
	state.set_day_care_mon(Gen2WorldDayCare.SLOT_MAN, _mon(CUBONE))
	state.set_day_care_has_mon(Gen2WorldDayCare.SLOT_MAN, true)
	assert_true(
		Gen2WorldDayCare.retrieve(state, save, _data, Gen2WorldDayCare.SLOT_MAN).is_empty()
	)


func test_one_member_never_reaches_the_party_list() -> void:
	var save: Gen2SaveData = Gen2SaveData.new()
	save.party = [_mon(CUBONE)]
	assert_eq(
		Gen2WorldDayCare.deposit_refusal(save, 0), Gen2WorldDayCare.TEXT_LAST_MON
	)


func test_an_egg_and_the_last_healthy_member_are_each_refused() -> void:
	var save: Gen2SaveData = Gen2SaveData.new()
	var egg: Gen2SaveMon = _mon(CUBONE)
	egg.is_egg = true
	save.party = [egg, _mon(HOOTHOOT)]
	assert_eq(
		Gen2WorldDayCare.deposit_refusal(save, 0),
		Gen2WorldDayCare.TEXT_CANT_BREED_EGG
	)
	# The egg cannot battle, so giving away the Hoothoot leaves nothing that can.
	assert_eq(
		Gen2WorldDayCare.deposit_refusal(save, 1),
		Gen2WorldDayCare.TEXT_LAST_ALIVE_MON
	)


func test_a_fainted_member_may_be_deposited_while_another_can_walk() -> void:
	var save: Gen2SaveData = Gen2SaveData.new()
	var fainted: Gen2SaveMon = _mon(CUBONE)
	fainted.hp = 0
	save.party = [fainted, _mon(HOOTHOOT)]
	assert_eq(Gen2WorldDayCare.deposit_refusal(save, 0), "")


func test_a_held_mail_is_refused() -> void:
	var save: Gen2SaveData = Gen2SaveData.new()
	var mailed: Gen2SaveMon = _mon(CUBONE)
	mailed.item = Gen2HeldItem.MAIL_ITEMS[0]
	save.party = [mailed, _mon(HOOTHOOT)]
	assert_eq(
		Gen2WorldDayCare.deposit_refusal(save, 0), Gen2WorldDayCare.TEXT_REMOVE_MAIL
	)


func _breeding_pair(state: Gen2WorldState) -> void:
	state.set_day_care_mon(Gen2WorldDayCare.SLOT_MAN, _mon(CUBONE, MALE_DVS, 100))
	state.set_day_care_has_mon(Gen2WorldDayCare.SLOT_MAN, true)
	state.set_day_care_mon(Gen2WorldDayCare.SLOT_LADY, _mon(CUBONE, FEMALE_DVS, 200))
	state.set_day_care_has_mon(Gen2WorldDayCare.SLOT_LADY, true)


func test_a_compatible_pair_starts_a_counter_of_at_least_a_hundred_and_fifty() -> void:
	var state: Gen2WorldState = _state()
	_breeding_pair(state)
	assert_true(Gen2WorldDayCare.init_breeding(state, _data, "RED", 1, _seeded(9)))
	assert_true(
		state.day_care_man_flags() & Gen2WorldDayCare.MAN_MONS_COMPATIBLE != 0
	)
	assert_gte(state.steps_to_egg(), Gen2WorldDayCare.FIRST_EGG_STEPS_MINIMUM)
	# The egg is built when the counter starts, not when it runs out.
	assert_not_null(state.day_care_egg())
	assert_true(state.day_care_egg().is_egg)
	assert_eq(state.day_care_egg().level, Gen2WorldDayCare.EGG_LEVEL)
	assert_eq(state.day_care_egg().original_trainer, "RED")


func test_only_one_slot_filled_starts_nothing() -> void:
	var state: Gen2WorldState = _state()
	state.set_day_care_mon(Gen2WorldDayCare.SLOT_MAN, _mon(CUBONE))
	state.set_day_care_has_mon(Gen2WorldDayCare.SLOT_MAN, true)
	assert_false(Gen2WorldDayCare.init_breeding(state, _data, "RED", 1, _seeded(9)))
	assert_eq(state.steps_to_egg(), 0)


func test_an_egg_hatch_counter_is_the_species_own() -> void:
	var state: Gen2WorldState = _state()
	_breeding_pair(state)
	Gen2WorldDayCare.init_breeding(state, _data, "RED", 1, _seeded(9))
	assert_eq(
		state.day_care_egg().happiness,
		int(_data.species(CUBONE).get("hatch_cycles", 0))
	)


func test_the_egg_takes_the_parents_defence_dv() -> void:
	var state: Gen2WorldState = _state()
	_breeding_pair(state)
	Gen2WorldDayCare.init_breeding(state, _data, "RED", 1, _seeded(9))
	var egg: Gen2SaveMon = state.day_care_egg()
	var mother: int = Gen2Stats.defense_dv(FEMALE_DVS)
	var father: int = Gen2Stats.defense_dv(MALE_DVS)
	assert_true(
		Gen2Stats.defense_dv(egg.dvs) in [mother, father],
		"the Defense DV comes from one of the two parents"
	)


func test_the_counter_runs_down_a_step_at_a_time_and_offers_an_egg() -> void:
	var state: Gen2WorldState = _state()
	_breeding_pair(state)
	Gen2WorldDayCare.init_breeding(state, _data, "RED", 1, _seeded(9))
	var random: RandomNumberGenerator = _seeded(4)
	var steps: int = state.steps_to_egg()
	for _pass: int in steps - 1:
		assert_false(Gen2WorldDayCare.step(state, _data, random))
	assert_eq(state.steps_to_egg(), 1)
	# The pass that empties the counter re-rolls it and rolls for the egg; it may
	# refuse, so the walk runs until one is offered rather than asserting on one.
	var offered: bool = false
	for _pass: int in 4000:
		if Gen2WorldDayCare.step(state, _data, random):
			offered = true
			break
	assert_true(offered, "a compatible pair eventually offers an egg")
	assert_true(state.day_care_man_flags() & Gen2WorldDayCare.MAN_HAS_EGG != 0)
	assert_true(
		state.day_care_man_flags() & Gen2WorldDayCare.MAN_MONS_COMPATIBLE == 0,
		"the pair stops counting while the egg is waiting outside"
	)


func test_the_egg_waiting_is_the_one_handed_over() -> void:
	var state: Gen2WorldState = _state()
	var save: Gen2SaveData = Gen2SaveData.new()
	_breeding_pair(state)
	Gen2WorldDayCare.init_breeding(state, _data, "RED", 1, _seeded(9))
	state.set_day_care_man_flags(
		state.day_care_man_flags() | Gen2WorldDayCare.MAN_HAS_EGG
	)
	var waiting: Gen2SaveMon = state.day_care_egg()
	var given: Dictionary = Gen2WorldDayCare.give_egg(state, save)
	assert_eq(int(given["species"]), waiting.species)
	assert_eq(save.party.size(), 1)
	assert_true((save.party[0] as Gen2SaveMon).is_egg)
	assert_null(state.day_care_egg())
	assert_true(state.day_care_man_flags() & Gen2WorldDayCare.MAN_HAS_EGG == 0)


func test_the_day_care_survives_a_save_round_trip() -> void:
	var state: Gen2WorldState = _state()
	_breeding_pair(state)
	Gen2WorldDayCare.init_breeding(state, _data, "RED", 1, _seeded(9))
	var restored: Gen2WorldState = Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.day_care_man_flags(), state.day_care_man_flags())
	assert_eq(restored.steps_to_egg(), state.steps_to_egg())
	assert_eq(
		restored.day_care_mon(Gen2WorldDayCare.SLOT_LADY).dvs,
		state.day_care_mon(Gen2WorldDayCare.SLOT_LADY).dvs
	)
	assert_eq(restored.day_care_egg().species, state.day_care_egg().species)


func test_a_state_written_before_the_day_care_restores_as_two_empty_slots() -> void:
	var restored: Gen2WorldState = Gen2WorldState.from_dict({"coins": 3})
	assert_false(restored.day_care_has_mon(Gen2WorldDayCare.SLOT_MAN))
	assert_false(restored.day_care_has_mon(Gen2WorldDayCare.SLOT_LADY))
	assert_null(restored.day_care_egg())
	assert_eq(restored.steps_to_egg(), 0)


func test_a_step_is_owed_by_the_walk_and_spent_by_the_screen() -> void:
	var state: Gen2WorldState = _state()
	state.count_step()
	state.count_step()
	assert_eq(state.take_pending_day_care_steps(), 2)
	assert_eq(state.take_pending_day_care_steps(), 0)


func test_an_egg_move_the_father_knows_reaches_the_egg() -> void:
	# Hoothoot's own egg-move list is the fixture's, and `GetEggMove`'s first
	# test is that list.
	assert_true(
		Gen2WorldDayCare.inherits_move(_data, HOOTHOOT, Fixture.MIST_MOVE, null)
	)
	assert_false(
		Gen2WorldDayCare.inherits_move(_data, CUBONE, Fixture.MIST_MOVE, null)
	)


func test_a_tm_move_the_egg_species_can_learn_is_inherited() -> void:
	assert_true(
		Gen2WorldDayCare.inherits_move(_data, CUBONE, Fixture.TM01_MOVE, null)
	)


func test_a_move_the_mother_knows_and_the_egg_learns_by_level_is_inherited() -> void:
	# `.found_eggmove`: the move has to be one of the mother's four AND one the
	# egg species learns on its own, and neither half is enough.
	var mother: Gen2SaveMon = _mon(Fixture.GEODUDE)
	mother.moves = [Fixture.SLASH, 0, 0, 0]
	assert_true(
		Gen2WorldDayCare.inherits_move(_data, Fixture.GEODUDE, Fixture.SLASH, mother)
	)
	assert_false(
		Gen2WorldDayCare.inherits_move(_data, Fixture.GEODUDE, Fixture.SLASH, null)
	)
