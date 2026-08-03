extends GutTest

## The commands a move is made of, one at a time.
##
## The turn loop is tested through whole battles in test_battle.gd. What is
## tested here is the machinery underneath it: that an effect picks a list, that
## a command writes down what the next one reads, and that a command which ends
## the move really does stop the ones behind it. Those are the properties every
## effect written from here on will lean on.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"effecttest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 12345


func after_each() -> void:
	RomCache.clear(_directory)


func _battle() -> Gen2Battle:
	return Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)


func _turn(battle: Gen2Battle, move_number: int = Fixture.TACKLE) -> Gen2Turn:
	return Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, move_number, _data.move(move_number), []
	)


func test_an_effect_nobody_has_written_is_an_ordinary_attack() -> void:
	# Most of the table is, and so is every effect still waiting to be written,
	# which is why a move with one behaves rather than doing nothing.
	assert_eq(Gen2MoveEffect.sequence_for(0), Gen2MoveEffect.NORMAL_HIT)
	assert_eq(Gen2MoveEffect.sequence_for(0xFF), Gen2MoveEffect.NORMAL_HIT)
	assert_false(Gen2MoveEffect.is_written(0xFF))


func test_recoil_is_the_ordinary_list_with_a_step_in_it() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.RECOIL_HIT)
	assert_true(Gen2MoveEffect.is_written(Gen2MoveEffect.RECOIL_HIT))
	assert_true(sequence.has(Gen2EffectCommands.RECOIL))
	assert_eq(sequence.size(), Gen2MoveEffect.NORMAL_HIT.size() + 1)
	# Before the faint check, so an attacker that goes down to its own recoil is
	# reported in the same breath as the defender.
	assert_lt(
		sequence.find(Gen2EffectCommands.RECOIL),
		sequence.find(Gen2EffectCommands.CHECK_FAINT)
	)


func test_the_stat_runs_land_on_the_right_stat() -> void:
	# Effect 20 is the down-by-one run's third stop (18 + 2) and String Shot is
	# published as lowering Speed; effect 72 is the down-on-hit run's fifth stop
	# (68 + 4) and Psychic is published as lowering Sp.Defense. Both are the
	# numbers most likely to be off by one, and neither shows up in a passing
	# battle unless the wrong stat actually moves.
	assert_true(Gen2MoveEffect.sequence_for(20).has(Gen2EffectCommands.SPEED_DOWN))
	assert_true(
		Gen2MoveEffect.sequence_for(72).has(Gen2EffectCommands.SP_DEFENSE_DOWN)
	)


func test_a_stat_that_only_rises_cannot_miss() -> void:
	# Swords Dance's own effect byte, 50, is the first stop of the up-by-two run.
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.STAT_UP_2_BASE)
	assert_false(sequence.has(Gen2EffectCommands.CHECK_HIT))
	assert_true(sequence.has(Gen2EffectCommands.ATTACK_UP_2))


func test_a_stat_that_can_be_lowered_can_also_be_missed() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.STAT_DOWN_BASE)
	assert_true(sequence.has(Gen2EffectCommands.CHECK_HIT))
	assert_lt(
		sequence.find(Gen2EffectCommands.CHECK_HIT),
		sequence.find(Gen2EffectCommands.ATTACK_DOWN)
	)


func test_a_stage_already_at_the_top_reports_failure_not_a_rise() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.attacker().change_stage("attack", Gen2Stats.MAX_STAGE)

	Gen2EffectCommands.run(Gen2EffectCommands.ATTACK_UP, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.STAT_UP_MESSAGE, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.STAT_UP_FAIL_TEXT, turn)

	assert_eq(turn.attacker().stage("attack"), Gen2Stats.MAX_STAGE)
	assert_eq(_first(turn.events, Gen2Battle.STAT_CHANGED), {})
	assert_eq(int(_first(turn.events, Gen2Battle.STAT_CHANGE_FAILED)["by"]), 1)


func test_a_secondary_effects_failed_roll_costs_the_stat_and_not_the_damage() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.failed_chance = true

	Gen2EffectCommands.run(Gen2EffectCommands.SP_DEFENSE_DOWN, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.STAT_DOWN_MESSAGE, turn)

	assert_eq(turn.defender().stage("sp_defense"), 0)
	assert_eq(turn.events.size(), 0, "a failed roll behind a hit says nothing at all")


func test_a_hit_based_stat_drop_that_fails_says_nothing() -> void:
	# The one difference from a status move's own sequence: there is no fail-text
	# step behind a secondary effect, so a stage already at the bottom is silent
	# rather than reporting it could not go lower.
	var turn: Gen2Turn = _turn(_battle())
	turn.defender().change_stage("sp_defense", Gen2Stats.MIN_STAGE)

	Gen2EffectCommands.run(Gen2EffectCommands.SP_DEFENSE_DOWN, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.STAT_DOWN_MESSAGE, turn)

	assert_eq(turn.events.size(), 0)


func test_ancientpower_raises_all_five_real_stats_as_one_event() -> void:
	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.ALL_STATS_UP, turn)

	for key: String in ["attack", "defense", "speed", "sp_attack", "sp_defense"]:
		assert_eq(turn.attacker().stage(key), 1, key)
	assert_eq(turn.attacker().stage("accuracy"), 0, "not among the five it raises")
	assert_eq(turn.events.size(), 1)
	assert_eq(String(turn.events[0]["stat"]), "all")


func test_ancientpower_does_nothing_behind_a_failed_roll() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.failed_chance = true
	Gen2EffectCommands.run(Gen2EffectCommands.ALL_STATS_UP, turn)

	assert_eq(turn.attacker().stage("attack"), 0)
	assert_eq(turn.events.size(), 0)


func test_a_turn_knows_who_is_on_the_other_side_of_it() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle)
	assert_eq(turn.target, Gen2Battle.ENEMY)
	assert_eq(turn.attacker(), battle.player)
	assert_eq(turn.defender(), battle.enemy)


func test_every_event_carries_the_side_that_caused_it() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.emit(Gen2Battle.MISSED, {"target": turn.target})
	assert_eq(turn.events.size(), 1)
	assert_eq(int(turn.events[0]["side"]), Gen2Battle.PLAYER)
	assert_eq(int(turn.events[0]["target"]), Gen2Battle.ENEMY)


func test_the_damage_step_writes_down_what_the_step_after_it_reads() -> void:
	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	assert_gt(turn.damage, 0, "Tackle off a level 50 Pikachu does something")
	assert_eq(turn.dealt, 0, "nothing has been applied yet")

	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)
	assert_eq(turn.dealt, turn.damage)
	assert_eq(int(_first(turn.events, Gen2Battle.HIT)["amount"]), turn.dealt)


func test_what_is_dealt_is_what_was_there_to_take() -> void:
	# A Pokémon with three hit points left takes three from a hit worth forty,
	# and the event says three, because that is what the bar has to move by.
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 3
	var turn: Gen2Turn = _turn(battle)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)
	assert_eq(turn.dealt, 3)
	assert_eq(battle.enemy.hp, 0)


func test_a_command_that_ends_the_move_says_so() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.immune = true
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_IMMUNE, turn)
	assert_true(turn.ended)
	assert_eq(turn.events[0]["type"], Gen2Battle.NO_EFFECT)


func test_an_immunity_is_not_a_miss() -> void:
	# They read differently on screen and they are different questions: one is
	# about the type chart and the other about a roll.
	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_IMMUNE, turn)
	assert_false(turn.ended)
	assert_eq(turn.events.size(), 0)


func test_struggle_spends_nothing() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, Fixture.STRUGGLE, _data.move(Fixture.STRUGGLE), []
	)
	var before: int = int(battle.player.pp[0])
	Gen2EffectCommands.run(Gen2EffectCommands.DO_TURN, turn)
	assert_eq(int(battle.player.pp[0]), before)


func test_an_ordinary_move_spends_its_slot() -> void:
	var battle: Gen2Battle = _battle()
	var before: int = int(battle.player.pp[0])
	Gen2EffectCommands.run(Gen2EffectCommands.DO_TURN, _turn(battle))
	assert_eq(int(battle.player.pp[0]), before - 1)


func test_recoil_is_a_quarter_of_what_was_dealt_and_never_nothing() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle)
	turn.dealt = 20
	Gen2EffectCommands.run(Gen2EffectCommands.RECOIL, turn)
	assert_eq(int(_first(turn.events, Gen2Battle.RECOIL)["amount"]), 5)

	var second: Gen2Turn = _turn(battle)
	second.dealt = 2
	Gen2EffectCommands.run(Gen2EffectCommands.RECOIL, second)
	assert_eq(int(_first(second.events, Gen2Battle.RECOIL)["amount"]), 1)


func test_a_move_that_dealt_nothing_costs_nothing_in_recoil() -> void:
	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.RECOIL, turn)
	assert_eq(turn.events.size(), 0)


func _first(events: Array, type: StringName) -> Dictionary:
	for event: Dictionary in events:
		if event["type"] == type:
			return event
	return {}
