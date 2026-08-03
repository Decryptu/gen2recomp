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


func test_flinch_hit_is_the_secondary_shape_with_flinch_target_in_it() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.FLINCH_HIT)
	assert_true(Gen2MoveEffect.is_written(Gen2MoveEffect.FLINCH_HIT))
	assert_true(sequence.has(Gen2EffectCommands.FLINCH_TARGET))
	assert_true(sequence.has(Gen2EffectCommands.EFFECT_CHANCE))
	assert_true(sequence.has(Gen2EffectCommands.APPLY_DAMAGE), "the damage happens either way")


func test_flinch_target_sets_the_substatus_flag() -> void:
	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.FLINCH_TARGET, turn)
	assert_true(Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.FLINCHED))


func test_flinch_target_does_nothing_behind_a_failed_roll() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.failed_chance = true
	Gen2EffectCommands.run(Gen2EffectCommands.FLINCH_TARGET, turn)
	assert_false(Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.FLINCHED))


func test_a_flinched_pokemon_cannot_move_and_the_flag_clears_either_way() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.FLINCHED
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.ENEMY, 0, Fixture.TACKLE, _data.move(Fixture.TACKLE), []
	)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	assert_true(turn.ended)
	assert_eq(_first(turn.events, Gen2Battle.CANNOT_MOVE)["reason"], &"flinch")
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.FLINCHED))


func test_confuse_hit_is_the_secondary_shape_and_confuse_is_the_status_shape() -> void:
	var hit: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.CONFUSE_HIT)
	assert_true(hit.has(Gen2EffectCommands.CONFUSE_TARGET))
	assert_true(hit.has(Gen2EffectCommands.APPLY_DAMAGE))

	var status_move: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.CONFUSE)
	assert_true(status_move.has(Gen2EffectCommands.CONFUSE_TARGET))
	assert_false(status_move.has(Gen2EffectCommands.DAMAGE_CALC), "no power, so no matchup step")


func test_confuse_target_sets_the_flag_and_rolls_a_duration() -> void:
	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.CONFUSE_TARGET, turn)
	var defender: Gen2BattleMon = turn.defender()
	assert_true(Gen2Substatus.has(defender.substatus, Gen2Substatus.CONFUSED))
	assert_between(defender.confusion_turns, Gen2Substatus.MIN_CONFUSION, Gen2Substatus.MAX_CONFUSION)
	assert_eq(_first(turn.events, Gen2Battle.CONFUSE_INFLICTED)["target"], turn.target)


func test_an_already_confused_target_cannot_be_confused_again() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.defender().substatus |= Gen2Substatus.CONFUSED
	turn.defender().confusion_turns = 3
	Gen2EffectCommands.run(Gen2EffectCommands.CONFUSE_TARGET, turn)
	assert_eq(turn.defender().confusion_turns, 3, "not restarted")
	assert_eq(turn.events.size(), 0)


func test_a_confused_pokemon_that_is_not_hit_by_itself_carries_on_into_its_move() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.CONFUSED
	battle.player.confusion_turns = 3
	# A seed where the confusion-hit roll comes up short, so the turn's own
	# events are read rather than a self-hit's.
	_rng.seed = 1
	var turn: Gen2Turn = _turn(battle)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	assert_false(turn.ended)
	assert_eq(_first(turn.events, Gen2Battle.CONFUSED)["side"], Gen2Battle.PLAYER)


func test_a_confused_pokemon_that_hits_itself_never_reaches_its_move() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.CONFUSED
	battle.player.confusion_turns = 3
	var before: int = battle.player.hp
	# A seed where the confusion-hit roll comes up, so this is a self-hit rather
	# than the other branch: the pair proves both halves of the coin flip work.
	_rng.seed = 12345
	var turn: Gen2Turn = _turn(battle)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	assert_true(turn.ended)
	assert_lt(battle.player.hp, before)
	assert_eq(_first(turn.events, Gen2Battle.USED_MOVE), {}, "it never got to use anything")


func test_confusion_running_out_lets_the_move_through_the_same_turn() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.CONFUSED
	battle.player.confusion_turns = 1
	var turn: Gen2Turn = _turn(battle)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	assert_false(turn.ended)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CONFUSED))
	assert_eq(_first(turn.events, Gen2Battle.SNAPPED_OUT)["side"], Gen2Battle.PLAYER)


func test_recharge_hit_locks_the_user_out_after_it_connects() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.RECHARGE_HIT)
	assert_lt(
		sequence.find(Gen2EffectCommands.CHECK_HIT), sequence.find(Gen2EffectCommands.RECHARGE),
		"a miss ends the move before recharge is ever reached"
	)

	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.RECHARGE, turn)
	assert_true(Gen2Substatus.has(turn.attacker().substatus, Gen2Substatus.RECHARGING))


func test_a_recharging_pokemon_cannot_move_and_the_flag_clears() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.RECHARGING
	var turn: Gen2Turn = _turn(battle)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	assert_true(turn.ended)
	assert_eq(_first(turn.events, Gen2Battle.CANNOT_MOVE)["reason"], &"recharge")
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.RECHARGING))


func test_a_charge_move_ends_the_turn_before_the_damage_step() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.SOLARBEAM)
	assert_lt(
		sequence.find(Gen2EffectCommands.CHARGE_MOVE),
		sequence.find(Gen2EffectCommands.DAMAGE_CALC)
	)


func test_charge_move_locks_the_user_in_and_says_so() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.SOLARBEAM)
	Gen2EffectCommands.run(Gen2EffectCommands.CHARGE_MOVE, turn)
	var mon: Gen2BattleMon = turn.attacker()
	assert_true(Gen2Substatus.has(mon.substatus, Gen2Substatus.CHARGING))
	assert_eq(mon.charged_move, Fixture.SOLARBEAM)
	assert_true(turn.ended)
	assert_eq(_first(turn.events, Gen2Battle.CHARGING_UP)["side"], Gen2Battle.PLAYER)


func test_charge_move_releases_on_the_second_call_and_lets_the_rest_run() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.SOLARBEAM)
	var mon: Gen2BattleMon = turn.attacker()
	mon.substatus |= Gen2Substatus.CHARGING
	mon.charged_move = Fixture.SOLARBEAM

	Gen2EffectCommands.run(Gen2EffectCommands.CHARGE_MOVE, turn)
	assert_false(turn.ended)
	assert_false(Gen2Substatus.has(mon.substatus, Gen2Substatus.CHARGING))
	assert_eq(mon.charged_move, 0)


func test_skull_bash_raises_defense_after_the_hit_lands() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.SKULL_BASH)
	assert_lt(
		sequence.find(Gen2EffectCommands.CHECK_FAINT),
		sequence.find(Gen2EffectCommands.DEFENSE_UP)
	)


func test_toxic_starts_its_own_ramping_counter_rather_than_a_flat_poison() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.TOXIC)
	assert_true(sequence.has(Gen2EffectCommands.TOXIC_TARGET))
	assert_false(sequence.has(Gen2EffectCommands.POISON_TARGET))

	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.TOXIC_TARGET, turn)
	var defender: Gen2BattleMon = turn.defender()
	assert_true(Gen2Status.has(defender.status, Gen2Status.POISON))
	assert_eq(defender.toxic_counter, 1)
	assert_eq(_first(turn.events, Gen2Battle.STATUS_INFLICTED)["name"], &"toxic")


func test_toxic_refuses_an_already_afflicted_target() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.defender().status = Gen2Status.BURN
	Gen2EffectCommands.run(Gen2EffectCommands.TOXIC_TARGET, turn)
	assert_eq(turn.defender().status, Gen2Status.BURN, "not replaced")
	assert_eq(turn.defender().toxic_counter, 0)


func test_haze_clears_both_sides_stages_and_nothing_else() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.change_stage("attack", 3)
	battle.enemy.change_stage("speed", -2)
	battle.enemy.status = Gen2Status.BURN

	var turn: Gen2Turn = _turn(battle)
	Gen2EffectCommands.run(Gen2EffectCommands.HAZE, turn)

	assert_eq(battle.player.stage("attack"), 0)
	assert_eq(battle.enemy.stage("speed"), 0)
	assert_eq(battle.enemy.status, Gen2Status.BURN, "not a status cure")
	assert_eq(_first(turn.events, Gen2Battle.STAGES_CLEARED), {"type": Gen2Battle.STAGES_CLEARED, "side": Gen2Battle.PLAYER})


func test_belly_drum_maxes_attack_for_half_the_users_health() -> void:
	var turn: Gen2Turn = _turn(_battle())
	var mon: Gen2BattleMon = turn.attacker()
	var max_hp: int = mon.max_hp()

	Gen2EffectCommands.run(Gen2EffectCommands.BELLY_DRUM, turn)

	assert_eq(mon.stage("attack"), Gen2Stats.MAX_STAGE)
	@warning_ignore("integer_division")
	assert_eq(mon.hp, max_hp - max_hp / 2)
	assert_eq(_first(turn.events, Gen2Battle.STAT_CHANGED)["by"], 6)


func test_belly_drum_fails_without_cost_under_half_health() -> void:
	var turn: Gen2Turn = _turn(_battle())
	var mon: Gen2BattleMon = turn.attacker()
	mon.hp = 1

	Gen2EffectCommands.run(Gen2EffectCommands.BELLY_DRUM, turn)

	assert_eq(mon.stage("attack"), 0)
	assert_eq(mon.hp, 1, "nothing spent on a failed attempt")
	assert_eq(_first(turn.events, Gen2Battle.STAT_CHANGE_FAILED)["by"], 6)


func test_belly_drum_fails_once_attack_is_already_at_the_top() -> void:
	var turn: Gen2Turn = _turn(_battle())
	var mon: Gen2BattleMon = turn.attacker()
	mon.change_stage("attack", Gen2Stats.MAX_STAGE)
	var before: int = mon.hp

	Gen2EffectCommands.run(Gen2EffectCommands.BELLY_DRUM, turn)

	assert_eq(mon.hp, before)
	assert_eq(_of_type(turn.events, Gen2Battle.STAT_CHANGE_FAILED).size(), 1)


func test_psych_up_copies_the_targets_stages_onto_the_user() -> void:
	var turn: Gen2Turn = _turn(_battle())
	turn.defender().change_stage("speed", -2)
	turn.defender().change_stage("accuracy", 1)

	Gen2EffectCommands.run(Gen2EffectCommands.PSYCH_UP, turn)

	assert_eq(turn.attacker().stage("speed"), -2)
	assert_eq(turn.attacker().stage("accuracy"), 1)
	assert_eq(_of_type(turn.events, Gen2Battle.STAGES_COPIED).size(), 1)


func test_psych_up_fails_when_the_target_has_nothing_to_copy() -> void:
	var turn: Gen2Turn = _turn(_battle())
	Gen2EffectCommands.run(Gen2EffectCommands.PSYCH_UP, turn)
	assert_eq(turn.events.size(), 0)


func test_multi_hit_and_double_hit_share_one_command() -> void:
	var multi: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.MULTI_HIT)
	var double_hit: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.DOUBLE_HIT)
	assert_eq(multi, double_hit)
	assert_true(multi.has(Gen2EffectCommands.MULTI_HIT))
	assert_eq(
		multi.find(Gen2EffectCommands.CHECK_HIT) + 1, multi.find(Gen2EffectCommands.MULTI_HIT),
		"the accuracy roll happens once, right before the hits it covers"
	)


func test_double_hit_always_hits_exactly_twice() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.DOUBLE_HIT_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.MULTI_HIT, turn)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 2)
	assert_eq(int(_first(turn.events, Gen2Battle.HIT_TIMES)["times"]), 2)


func test_multi_hit_lands_between_two_and_five_times() -> void:
	# Twenty different seeds, so the roll's own range gets exercised rather than
	# whatever one seed happens to land on.
	for seed_value: int in range(1, 21):
		_rng.seed = seed_value
		var turn: Gen2Turn = _turn(_battle(), Fixture.MULTI_HIT_MOVE)
		Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
		Gen2EffectCommands.run(Gen2EffectCommands.MULTI_HIT, turn)
		var hits: int = _of_type(turn.events, Gen2Battle.HIT).size()
		assert_between(hits, 2, 5, "seed %d" % seed_value)
		assert_eq(int(_first(turn.events, Gen2Battle.HIT_TIMES)["times"]), hits)


func test_multi_hit_stops_and_says_nothing_once_the_target_is_down() -> void:
	# The cartridge's own loop jumps straight past the "hit N times" line the
	# moment a hit brings the target down, so no summary is the whole point.
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 1
	var turn: Gen2Turn = _turn(battle, Fixture.MULTI_HIT_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.MULTI_HIT, turn)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 1, "the one hit that finished it")
	assert_eq(_first(turn.events, Gen2Battle.HIT_TIMES), {})
	assert_true(turn.ended)
	assert_eq(_first(turn.events, Gen2Battle.FAINTED)["side"], Gen2Battle.ENEMY)


func test_twineedle_hits_twice_then_rolls_poison_once_for_both() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.TWINEEDLE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_HIT, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.EFFECT_CHANCE, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.MULTI_HIT, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.POISON_TARGET, turn)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 2)
	assert_true(
		Gen2Status.has(turn.defender().status, Gen2Status.POISON), "the 256-chance never fails"
	)
	assert_eq(_of_type(turn.events, Gen2Battle.STATUS_INFLICTED).size(), 1, "once, not per hit")


func test_drain_sequences_share_one_list_gated_by_check_hit() -> void:
	var leech: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.LEECH_HIT)
	var dream_eater: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.DREAM_EATER)
	assert_eq(leech, dream_eater)
	assert_true(leech.has(Gen2EffectCommands.DRAIN_TARGET))
	assert_lt(
		leech.find(Gen2EffectCommands.APPLY_DAMAGE), leech.find(Gen2EffectCommands.DRAIN_TARGET),
		"drained before checked for a faint, the same slot recoil takes"
	)
	assert_lt(
		leech.find(Gen2EffectCommands.DRAIN_TARGET), leech.find(Gen2EffectCommands.CHECK_FAINT)
	)


func test_drain_heals_half_of_what_was_calculated_not_what_was_taken() -> void:
	# A target with three hit points left takes three, but the drain reads the
	# uncapped fifty the formula worked out, the cartridge's own quirk.
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 3
	battle.player.hp = 1
	var turn: Gen2Turn = _turn(battle, Fixture.DRAIN_MOVE)
	turn.damage = 50
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)
	assert_eq(turn.dealt, 3, "clamped to what was left to take")

	Gen2EffectCommands.run(Gen2EffectCommands.DRAIN_TARGET, turn)
	assert_eq(int(_first(turn.events, Gen2Battle.DRAINED)["amount"]), 25, "half of fifty, not of three")
	assert_eq(_first(turn.events, Gen2Battle.DRAINED)["from"], turn.target)


func test_drain_heals_at_least_one() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.hp = 1
	var turn: Gen2Turn = _turn(battle, Fixture.DRAIN_MOVE)
	turn.damage = 1
	Gen2EffectCommands.run(Gen2EffectCommands.DRAIN_TARGET, turn)
	assert_eq(int(_first(turn.events, Gen2Battle.DRAINED)["amount"]), 1)


func test_dream_eater_misses_a_target_that_is_not_asleep() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.DREAM_EATER_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_HIT, turn)
	assert_true(turn.ended)
	assert_eq(_first(turn.events, Gen2Battle.MISSED)["target"], turn.target)


func test_dream_eater_connects_against_a_sleeping_target() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.status = Gen2Status.roll_sleep(_rng)
	var turn: Gen2Turn = _turn(battle, Fixture.DREAM_EATER_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_HIT, turn)
	assert_false(turn.ended)
	assert_eq(turn.events.size(), 0, "an ordinary hit, nothing to say about the check itself")


func test_the_four_fixed_damage_effects_share_one_list() -> void:
	var sequences: Array = [
		Gen2MoveEffect.sequence_for(Gen2MoveEffect.SUPER_FANG),
		Gen2MoveEffect.sequence_for(Gen2MoveEffect.STATIC_DAMAGE),
		Gen2MoveEffect.sequence_for(Gen2MoveEffect.LEVEL_DAMAGE),
		Gen2MoveEffect.sequence_for(Gen2MoveEffect.PSYWAVE),
	]
	for sequence: Array in sequences:
		assert_eq(sequence, sequences[0])
	assert_true(sequences[0].has(Gen2EffectCommands.FIXED_DAMAGE))
	assert_lt(
		sequences[0].find(Gen2EffectCommands.CHECK_IMMUNE),
		sequences[0].find(Gen2EffectCommands.FIXED_DAMAGE),
		"the roll DAMAGE_CALC already made is only kept for whether it is immune"
	)


func test_level_damage_deals_exactly_the_users_level() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.LEVEL_DAMAGE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
	assert_eq(turn.damage, turn.attacker().level)
	assert_false(turn.critical, "constant damage never criticals")
	assert_eq(turn.effectiveness, RomLayout.MATCHUP_EFFECTIVE, "no effectiveness line for it either")


func test_static_damage_deals_exactly_the_moves_own_power() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.STATIC_DAMAGE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
	assert_eq(turn.damage, 20, "Sonicboom's own power in the fixture")


func test_super_fang_halves_the_targets_current_hp() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 51
	var turn: Gen2Turn = _turn(battle, Fixture.SUPER_FANG_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
	assert_eq(turn.damage, 25, "floored, not rounded")


func test_super_fang_never_deals_less_than_one() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 1
	var turn: Gen2Turn = _turn(battle, Fixture.SUPER_FANG_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
	assert_eq(turn.damage, 1)


func test_psywave_stays_inside_its_own_range() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.PSYWAVE_MOVE)
	var level: int = turn.attacker().level
	@warning_ignore("integer_division")
	var upper: int = level / 2 + level
	for seed_value: int in range(1, 21):
		_rng.seed = seed_value
		Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
		Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
		assert_between(turn.damage, 1, upper - 1, "seed %d" % seed_value)


func test_ohko_has_no_ordinary_hit_or_damage_steps() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.OHKO)
	assert_true(sequence.has(Gen2EffectCommands.OHKO))
	assert_false(sequence.has(Gen2EffectCommands.CHECK_HIT))
	assert_false(sequence.has(Gen2EffectCommands.APPLY_DAMAGE))


func test_ohko_fails_outright_against_a_higher_level_target() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.level = 10
	battle.enemy.level = 50
	var turn: Gen2Turn = _turn(battle, Fixture.OHKO_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.OHKO, turn)
	assert_true(turn.ended)
	assert_eq(_first(turn.events, Gen2Battle.NO_EFFECT)["target"], turn.target)
	assert_eq(battle.enemy.hp, battle.enemy.max_hp(), "untouched, not even rolled for")


func test_ohko_can_still_miss_its_boosted_roll() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle, Fixture.OHKO_MOVE)
	turn.move = turn.move.duplicate()
	turn.move["accuracy"] = 0
	Gen2EffectCommands.run(Gen2EffectCommands.OHKO, turn)
	assert_eq(_first(turn.events, Gen2Battle.MISSED)["target"], turn.target)
	assert_eq(battle.enemy.hp, battle.enemy.max_hp())


func test_ohko_faints_the_target_outright_when_it_connects() -> void:
	# A hundred-level gap pushes the boosted accuracy past 255, which
	# Gen2Accuracy.rolls_hit treats as never missing, so this needs no seed.
	var battle: Gen2Battle = _battle()
	battle.player.level = 100
	battle.enemy.level = 5
	var turn: Gen2Turn = _turn(battle, Fixture.OHKO_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.OHKO, turn)
	assert_eq(battle.enemy.hp, 0)
	assert_eq(int(_first(turn.events, Gen2Battle.OHKO)["amount"]), battle.enemy.max_hp())
	assert_eq(_first(turn.events, Gen2Battle.FAINTED)["side"], Gen2Battle.ENEMY)


func _of_type(events: Array, type: StringName) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _first(events: Array, type: StringName) -> Dictionary:
	for event: Dictionary in events:
		if event["type"] == type:
			return event
	return {}
