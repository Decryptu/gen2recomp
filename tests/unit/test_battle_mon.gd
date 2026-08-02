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


func test_rolled_dvs_stay_inside_a_nibble_each() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _roll: int in 200:
		var dvs: int = Gen2BattleMon.random_dvs(rng)
		assert_between(Gen2Stats.attack_dv(dvs), 0, Gen2Stats.MAX_DV)
		assert_between(Gen2Stats.special_dv(dvs), 0, Gen2Stats.MAX_DV)
		assert_eq(dvs & ~0xFFFF, 0)
