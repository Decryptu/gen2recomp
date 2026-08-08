extends GutTest

## The commands a move is made of, one at a time.
##
## test_battle.gd tests the turn loop through whole battles. This tests the
## machinery underneath: an effect picks a list, a command writes down what the
## next one reads, and a command that ends the move stops the ones behind it.

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


func _run_move(
	battle: Gen2Battle,
	move_number: int,
	locked: bool = false,
	move_override: Dictionary = {}
) -> Gen2Turn:
	var move: Dictionary = _data.move(move_number).duplicate()
	move.merge(move_override, true)
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, move_number, move, []
	)
	turn.locked = locked
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	for command: StringName in Gen2MoveEffect.sequence_for(turn.effect()):
		if turn.ended:
			break
		Gen2EffectCommands.run(command, turn)
	return turn


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


func test_counter_mirror_coat_and_selfdestruct_have_their_cartridge_sequences() -> void:
	var counter: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.COUNTER)
	var mirror: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.MIRROR_COAT)
	var selfdestruct: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.SELFDESTRUCT)
	assert_true(counter.has(Gen2EffectCommands.COUNTER))
	assert_true(mirror.has(Gen2EffectCommands.MIRROR_COAT))
	assert_true(selfdestruct.has(Gen2EffectCommands.SELFDESTRUCT))
	assert_lt(
		selfdestruct.find(Gen2EffectCommands.SELFDESTRUCT),
		selfdestruct.find(Gen2EffectCommands.APPLY_DAMAGE)
	)


func test_counter_only_reflects_a_physical_move_that_hit_this_action_pair() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT]),
		Gen2BattleMon.create(_data, Fixture.BULBASAUR, 50, [Fixture.COUNTER]),
		_rng
	)
	var events: Array = battle.take_turn(0, 0)
	var hits: Array = _of_type(events, Gen2Battle.HIT)
	assert_eq(hits.size(), 1, "the special-category check rejects Counter")
	assert_eq(_of_type(events, Gen2Battle.MOVE_FAILED).size(), 1)


func test_mirror_coat_only_reflects_a_special_move_that_hit_this_action_pair() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT]),
		Gen2BattleMon.create(_data, Fixture.BULBASAUR, 50, [Fixture.MIRROR_COAT]),
		_rng
	)
	var events: Array = battle.take_turn(0, 0)
	var hits: Array = _of_type(events, Gen2Battle.HIT)
	assert_eq(hits.size(), 2)
	assert_eq(int(hits[1]["amount"]), int(hits[0]["amount"]) * 2)


func test_selfdestruct_faints_the_user_after_dealing_its_damage() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.moves = [Fixture.SELFDESTRUCT]
	battle.player.pp = [5]
	var before: int = battle.enemy.hp
	var events: Array = battle.take_turn(0, 0)
	assert_eq(battle.player.hp, 0)
	assert_lt(battle.enemy.hp, before)
	assert_eq(_of_type(events, Gen2Battle.FAINTED).size(), 1)
	assert_eq(int(_first(events, Gen2Battle.FAINTED)["side"]), Gen2Battle.PLAYER)


func test_selfdestruct_still_faints_the_user_when_accuracy_fails() -> void:
	var battle: Gen2Battle = _battle()
	var move: Dictionary = _data.move(Fixture.SELFDESTRUCT).duplicate()
	move["accuracy"] = 0
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, Fixture.SELFDESTRUCT, move, []
	)
	for command: StringName in Gen2MoveEffect.SELFDESTRUCT_SEQUENCE:
		if turn.ended:
			break
		Gen2EffectCommands.run(command, turn)
	assert_eq(battle.player.hp, 0)
	assert_eq(_of_type(turn.events, Gen2Battle.MISSED).size(), 1)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 0)
	assert_eq(_of_type(turn.events, Gen2Battle.FAINTED).size(), 1)


func test_fly_makes_the_user_untouchable_until_its_release_turn() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.FLY]),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)
	var first: Array = battle.take_turn(0, 0)
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.FLYING))
	assert_eq(battle.player.hp, battle.player.max_hp())
	assert_eq(_of_type(first, Gen2Battle.MISSED).size(), 1)
	assert_eq(_of_type(first, Gen2Battle.MISSED)[0]["side"], Gen2Battle.ENEMY)

	var second: Array = battle.take_turn(0, 0)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.FLYING))
	assert_gt(_of_type(second, Gen2Battle.HIT).size(), 0)


func test_a_status_that_stops_fly_on_release_makes_the_user_visible_again() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.FLY]),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)
	battle.take_turn(0, 0)
	battle.player.substatus |= Gen2Substatus.FLINCHED
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.CANNOT_MOVE).size(), 1)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.FLYING))
	assert_eq(battle.player.charged_move, 0)


func test_dig_uses_underground_and_earthquake_can_hit_it() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.DIG]),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.EARTHQUAKE]),
		_rng
	)
	var first: Array = battle.take_turn(0, 0)
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.UNDERGROUND))
	assert_eq(_of_type(first, Gen2Battle.HIT).filter(
		func(event: Dictionary) -> bool: return int(event["side"]) == Gen2Battle.ENEMY
	).size(), 1)


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


## A quarter of [member Gen2Turn.damage], the number the formula calculated,
## never [member Gen2Turn.dealt], the number that actually came off a target
## with less left than that: the real cartridge's own recoil reads the same
## uncapped figure drain does. A target with 3 HP left against a hit worth 20
## costs the attacker a quarter of 20, not a quarter of 3.
func test_recoil_is_a_quarter_of_what_the_formula_calculated_and_never_nothing() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle)
	turn.damage = 20
	turn.dealt = 3
	Gen2EffectCommands.run(Gen2EffectCommands.RECOIL, turn)
	assert_eq(int(_first(turn.events, Gen2Battle.RECOIL)["amount"]), 5)

	var second: Gen2Turn = _turn(battle)
	second.damage = 2
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


func test_rollout_rampage_and_defense_curl_use_their_effect_sequences() -> void:
	var rollout: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.ROLLOUT)
	var rampage: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.RAMPAGE)
	var curl: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.DEFENSE_CURL)
	assert_true(Gen2MoveEffect.is_written(Gen2MoveEffect.ROLLOUT))
	assert_true(Gen2MoveEffect.is_written(Gen2MoveEffect.RAMPAGE))
	assert_true(Gen2MoveEffect.is_written(Gen2MoveEffect.DEFENSE_CURL))
	assert_lt(
		rollout.find(Gen2EffectCommands.CHECK_HIT),
		rollout.find(Gen2EffectCommands.ROLLOUT_POWER)
	)
	assert_lt(
		rampage.find(Gen2EffectCommands.RAMPAGE),
		rampage.find(Gen2EffectCommands.DAMAGE_CALC)
	)
	assert_lt(
		curl.find(Gen2EffectCommands.DEFENSE_UP), curl.find(Gen2EffectCommands.CURL)
	)


func test_defense_curl_raises_defense_and_leaves_the_rollout_flag() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.DEFENSE_CURL, false)
	assert_eq(battle.player.stage("defense"), 1)
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CURLED))
	assert_eq(_of_type(turn.events, Gen2Battle.STAT_CHANGED).size(), 1)


func test_rollout_counts_hits_and_forces_the_move_without_spending_more_pp() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.moves = [Fixture.ROLLOUT, Fixture.TACKLE]
	battle.player.restore_pp()
	battle.enemy.hp = 10000
	var always_hits: Dictionary = {"accuracy": 255}
	var first: Gen2Turn = _run_move(battle, Fixture.ROLLOUT, false, always_hits)
	assert_eq(battle.player.rollout_count, 1)
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ROLLOUT))
	assert_eq(battle.player.pp_left(0), 19)

	for hit_number: int in range(2, 5):
		var continuation: Gen2Turn = _run_move(
			battle, Fixture.ROLLOUT, true, always_hits
		)
		assert_eq(int(_first(continuation.events, Gen2Battle.USED_MOVE)["move"]), Fixture.ROLLOUT)
		assert_eq(battle.player.rollout_count, hit_number)
		assert_eq(battle.player.pp_left(0), 19)

	var fifth: Gen2Turn = _run_move(battle, Fixture.ROLLOUT, true, always_hits)
	assert_eq(battle.player.rollout_count, 5)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ROLLOUT))
	assert_eq(_of_type(fifth.events, Gen2Battle.HIT).size(), 1)
	assert_eq(battle.player.pp_left(0), 19)
	assert_gt(first.damage, 0)


func test_rollout_multiplier_is_applied_before_variation() -> void:
	var battle: Gen2Battle = _battle()
	var move: Dictionary = _data.move(Fixture.ROLLOUT)
	var plain: Dictionary = Gen2Damage.calculate_with(
		battle.player, battle.enemy, move, false, Gen2Damage.MAX_VARIATION
	)
	var doubled: Dictionary = Gen2Damage.calculate_with(
		battle.player, battle.enemy, move, false, Gen2Damage.MAX_VARIATION, false, 2
	)
	assert_eq(int(doubled["damage"]), int(plain["damage"]) * 2)


func test_rollout_ends_on_a_miss_or_immunity() -> void:
	var battle: Gen2Battle = _battle()
	var miss: Gen2Turn = _run_move(battle, Fixture.ROLLOUT, false, {"accuracy": 0})
	assert_eq(_of_type(miss.events, Gen2Battle.MISSED).size(), 1)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ROLLOUT))

	var immune: Gen2Turn = _run_move(
		battle, Fixture.ROLLOUT, false, {"accuracy": 255, "type": Fixture.ELECTRIC}
	)
	assert_eq(_of_type(immune.events, Gen2Battle.NO_EFFECT).size(), 1)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ROLLOUT))


func test_status_interruption_cancels_rollout_without_advancing_it() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 10000
	_run_move(battle, Fixture.ROLLOUT, false, {"accuracy": 255})
	battle.player.status = 2
	var stopped: Gen2Turn = _run_move(battle, Fixture.ROLLOUT, true, {"accuracy": 255})
	assert_true(stopped.ended)
	assert_eq(_of_type(stopped.events, Gen2Battle.CANNOT_MOVE).size(), 1)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ROLLOUT))
	assert_eq(battle.player.rollout_count, 1)


func test_rampage_forces_its_starting_move_and_confuses_after_the_last_turn() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.moves = [Fixture.THRASH, Fixture.TACKLE]
	battle.player.restore_pp()
	battle.enemy.hp = 10000
	var always_hits: Dictionary = {"accuracy": 255}
	_run_move(battle, Fixture.THRASH, false, always_hits)
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.RAMPAGING))
	assert_eq(battle.player.rampage_move, Fixture.THRASH)
	assert_between(
		battle.player.rampage_turns,
		Gen2Substatus.MIN_RAMPAGE_TURNS,
		Gen2Substatus.MAX_RAMPAGE_TURNS
	)
	assert_eq(battle.player.pp_left(0), 19)

	var future_turns: int = battle.player.rampage_turns
	for _turn_number: int in future_turns:
		var continuation: Gen2Turn = _run_move(
			battle, Fixture.THRASH, true, always_hits
		)
		assert_eq(int(_first(continuation.events, Gen2Battle.USED_MOVE)["move"]), Fixture.THRASH)
		assert_eq(battle.player.pp_left(0), 19)

	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.RAMPAGING))
	assert_eq(battle.player.rampage_move, 0)
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CONFUSED))
	assert_between(
		battle.player.confusion_turns,
		Gen2Substatus.MIN_RAMPAGE_CONFUSION,
		Gen2Substatus.MAX_RAMPAGE_CONFUSION
	)


func test_rampage_miss_keeps_the_chain_but_status_interrupt_cancels_it() -> void:
	var battle: Gen2Battle = _battle()
	_run_move(battle, Fixture.THRASH, false, {"accuracy": 0})
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.RAMPAGING))
	battle.player.status = 2
	var stopped: Gen2Turn = _run_move(battle, Fixture.THRASH, true, {"accuracy": 255})
	assert_true(stopped.ended)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.RAMPAGING))
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CONFUSED))


func test_rampage_can_force_each_of_its_three_move_numbers() -> void:
	var battle: Gen2Battle = _battle()
	for move_number: int in [Fixture.THRASH, Fixture.PETAL_DANCE, Fixture.OUTRAGE]:
		battle.player.substatus = Gen2Substatus.RAMPAGING
		battle.player.rampage_move = move_number
		assert_eq(battle.move_for(Gen2Battle.PLAYER, 1), move_number)
		battle.player.substatus = Gen2Substatus.NONE


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


func test_disable_attract_encore_mist_and_focus_energy_have_their_own_sequences() -> void:
	for effect: int in [
		Gen2MoveEffect.DISABLE, Gen2MoveEffect.ATTRACT, Gen2MoveEffect.ENCORE,
		Gen2MoveEffect.MIST, Gen2MoveEffect.FOCUS_ENERGY,
	]:
		assert_true(Gen2MoveEffect.is_written(effect))


func test_disable_locks_the_targets_own_last_move() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.last_move_used = Fixture.TACKLE
	var turn: Gen2Turn = _turn(battle, Fixture.DISABLE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DISABLE, turn)
	assert_eq(battle.enemy.disabled_slot, 0)
	assert_between(battle.enemy.disable_turns, Gen2Substatus.MIN_DISABLE, Gen2Substatus.MAX_DISABLE)
	assert_eq(int(_first(turn.events, Gen2Battle.DISABLE_INFLICTED)["slot"]), 0)


func test_disable_fails_against_a_target_that_has_not_moved_yet() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle, Fixture.DISABLE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DISABLE, turn)
	assert_eq(battle.enemy.disabled_slot, -1)
	assert_false(_first(turn.events, Gen2Battle.MOVE_FAILED).is_empty())


func test_disable_fails_against_struggle() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.last_move_used = Fixture.STRUGGLE
	var turn: Gen2Turn = _turn(battle, Fixture.DISABLE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DISABLE, turn)
	assert_eq(battle.enemy.disabled_slot, -1)


func test_disable_fails_against_an_already_disabled_target() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.last_move_used = Fixture.TACKLE
	battle.enemy.disabled_slot = 0
	battle.enemy.disable_turns = 3
	var turn: Gen2Turn = _turn(battle, Fixture.DISABLE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DISABLE, turn)
	assert_eq(battle.enemy.disable_turns, 3, "unchanged, not re-rolled")
	assert_false(_first(turn.events, Gen2Battle.MOVE_FAILED).is_empty())


func test_disable_fails_against_a_move_already_out_of_pp() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.last_move_used = Fixture.TACKLE
	battle.enemy.pp[0] = 0
	var turn: Gen2Turn = _turn(battle, Fixture.DISABLE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.DISABLE, turn)
	assert_eq(battle.enemy.disabled_slot, -1)


func test_a_disabled_slot_cannot_be_used() -> void:
	var mon: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 50, [Fixture.TACKLE, Fixture.THUNDERBOLT]
	)
	mon.disabled_slot = 0
	assert_false(mon.can_use(0))
	assert_true(mon.can_use(1))


func test_encore_locks_the_targets_own_last_move() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.last_move_used = Fixture.TACKLE
	var turn: Gen2Turn = _turn(battle, Fixture.ENCORE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.ENCORE, turn)
	assert_eq(battle.enemy.encored_slot, 0)
	assert_between(battle.enemy.encore_turns, Gen2Substatus.MIN_ENCORE, Gen2Substatus.MAX_ENCORE)
	assert_eq(int(_first(turn.events, Gen2Battle.ENCORE_INFLICTED)["slot"]), 0)


## 227 and 119 are Encore's and Mirror Move's own real move numbers, not this
## fixture's arbitrary ones: the exclusion the cartridge writes is by move
## number, checked before this project's own move list is ever searched, so
## the numbers matter here and the fixture's own [constant Fixture.ENCORE_MOVE]
## would not exercise it.
func test_encore_refuses_struggle_encore_itself_and_mirror_move() -> void:
	for excluded: int in [Fixture.STRUGGLE, 227, 119]:
		var battle: Gen2Battle = _battle()
		battle.enemy.last_move_used = excluded
		var turn: Gen2Turn = _turn(battle, Fixture.ENCORE_MOVE)
		Gen2EffectCommands.run(Gen2EffectCommands.ENCORE, turn)
		assert_eq(battle.enemy.encored_slot, -1)


func test_encore_fails_against_an_already_encored_target() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.last_move_used = Fixture.TACKLE
	battle.enemy.encored_slot = 0
	battle.enemy.encore_turns = 4
	var turn: Gen2Turn = _turn(battle, Fixture.ENCORE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.ENCORE, turn)
	assert_eq(battle.enemy.encore_turns, 4, "unchanged, not re-rolled")


func test_attract_succeeds_between_opposite_genders() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(
			_data, Fixture.BULBASAUR, 50, [Fixture.ATTRACT_MOVE], Gen2Stats.pack_dvs(0, 0, 0, 0)
		),
		Gen2BattleMon.create(
			_data, Fixture.BULBASAUR, 50, [Fixture.TACKLE], Gen2Stats.pack_dvs(15, 0, 15, 0)
		),
		_rng
	)
	var turn: Gen2Turn = _turn(battle, Fixture.ATTRACT_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.ATTRACT, turn)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.ATTRACTED))
	assert_false(_first(turn.events, Gen2Battle.ATTRACT_INFLICTED).is_empty())


func test_attract_fails_between_the_same_gender() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(
			_data, Fixture.BULBASAUR, 50, [Fixture.ATTRACT_MOVE], Gen2Stats.pack_dvs(0, 0, 0, 0)
		),
		Gen2BattleMon.create(
			_data, Fixture.BULBASAUR, 50, [Fixture.TACKLE], Gen2Stats.pack_dvs(0, 0, 0, 0)
		),
		_rng
	)
	var turn: Gen2Turn = _turn(battle, Fixture.ATTRACT_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.ATTRACT, turn)
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.ATTRACTED))
	assert_false(_first(turn.events, Gen2Battle.MOVE_FAILED).is_empty())


func test_attract_fails_against_a_genderless_target() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.BULBASAUR, 50, [Fixture.ATTRACT_MOVE]),
		Gen2BattleMon.create(_data, 6, 50, [Fixture.TACKLE]),
		_rng
	)
	var turn: Gen2Turn = _turn(battle, Fixture.ATTRACT_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.ATTRACT, turn)
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.ATTRACTED))


func test_attract_fails_against_an_already_smitten_target() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(
			_data, Fixture.BULBASAUR, 50, [Fixture.ATTRACT_MOVE], Gen2Stats.pack_dvs(0, 0, 0, 0)
		),
		Gen2BattleMon.create(
			_data, Fixture.BULBASAUR, 50, [Fixture.TACKLE], Gen2Stats.pack_dvs(15, 0, 15, 0)
		),
		_rng
	)
	battle.enemy.substatus |= Gen2Substatus.ATTRACTED
	var turn: Gen2Turn = _turn(battle, Fixture.ATTRACT_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.ATTRACT, turn)
	assert_false(_first(turn.events, Gen2Battle.MOVE_FAILED).is_empty())


func test_mist_sets_the_flag_and_fails_on_a_second_use() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle, Fixture.MIST_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.MIST, turn)
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.MIST))
	assert_false(_first(turn.events, Gen2Battle.MIST_SET).is_empty())

	var second: Gen2Turn = _turn(battle, Fixture.MIST_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.MIST, second)
	assert_false(_first(second.events, Gen2Battle.MOVE_FAILED).is_empty())


func test_focus_energy_sets_the_flag_and_fails_on_a_second_use() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle, Fixture.FOCUS_ENERGY_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.FOCUS_ENERGY, turn)
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.FOCUS_ENERGY))
	assert_false(_first(turn.events, Gen2Battle.FOCUS_ENERGY_SET).is_empty())

	var second: Gen2Turn = _turn(battle, Fixture.FOCUS_ENERGY_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.FOCUS_ENERGY, second)
	assert_false(_first(second.events, Gen2Battle.MOVE_FAILED).is_empty())


func test_mist_blocks_a_drop_aimed_at_its_own_side() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.MIST
	var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)
	Gen2EffectCommands.run(Gen2EffectCommands.ATTACK_DOWN, turn)
	assert_false(turn.stat_moved)
	assert_true(turn.stat_mist_blocked)
	assert_eq(battle.enemy.stage("attack"), 0)


func test_mist_never_blocks_the_users_own_rise() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.MIST
	var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)
	Gen2EffectCommands.run(Gen2EffectCommands.ATTACK_UP, turn)
	assert_true(turn.stat_moved)
	assert_eq(battle.player.stage("attack"), 1)


func test_mist_protected_gets_its_own_message_not_the_generic_fail() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.MIST
	var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)
	Gen2EffectCommands.run(Gen2EffectCommands.ATTACK_DOWN, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.STAT_DOWN_FAIL_TEXT, turn)
	assert_false(_first(turn.events, Gen2Battle.MIST_PROTECTED).is_empty())
	assert_true(_first(turn.events, Gen2Battle.STAT_CHANGE_FAILED).is_empty())


## `TrapTarget` is `NormalHit` with `traptarget` where `kingsrock` sits, behind
## the faint check; `MeanLook` is four commands with no `checkhit` at all, so
## neither Mean Look nor Spider Web can miss despite the 100% both carry.
func test_the_two_trapping_effects_have_their_cartridge_sequences() -> void:
	var trap: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.TRAP_TARGET)
	assert_true(Gen2MoveEffect.is_written(Gen2MoveEffect.TRAP_TARGET))
	assert_eq(trap.size(), Gen2MoveEffect.NORMAL_HIT.size() + 1)
	assert_lt(
		trap.find(Gen2EffectCommands.CHECK_FAINT),
		trap.find(Gen2EffectCommands.TRAP_TARGET)
	)

	var mean_look: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.MEAN_LOOK)
	assert_true(Gen2MoveEffect.is_written(Gen2MoveEffect.MEAN_LOOK))
	assert_eq(mean_look, [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.ARENA_TRAP,
		Gen2EffectCommands.END_MOVE,
	])


func test_a_trapping_move_binds_its_target_for_three_to_six_turns() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle, Fixture.WRAP)

	Gen2EffectCommands.run(Gen2EffectCommands.TRAP_TARGET, turn)

	assert_between(
		battle.enemy.trapped_turns,
		Gen2Substatus.MIN_TRAP_TURNS, Gen2Substatus.MAX_TRAP_TURNS
	)
	assert_eq(battle.enemy.trapping_move, Fixture.WRAP)
	assert_eq(int(_first(turn.events, Gen2Battle.TRAPPED)["move"]), Fixture.WRAP)


## `BattleCommand_TrapTarget` returns on an already-bound target without
## printing anything, so the second move neither re-rolls the counter nor takes
## the first move's place, and it is not a "But it failed!" either.
func test_a_second_trapping_move_leaves_an_already_bound_target_alone() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.trapped_turns = 4
	battle.enemy.trapping_move = Fixture.WRAP
	var turn: Gen2Turn = _turn(battle, Fixture.BIND)

	Gen2EffectCommands.run(Gen2EffectCommands.TRAP_TARGET, turn)

	assert_eq(battle.enemy.trapped_turns, 4)
	assert_eq(battle.enemy.trapping_move, Fixture.WRAP)
	assert_true(turn.events.is_empty())


## The flag goes on the user, which is the whole reason `TryToRunAwayFromBattle`
## reads `wEnemySubStatus5` to refuse the player.
func test_mean_look_flags_its_user_rather_than_its_target() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle, Fixture.MEAN_LOOK)

	Gen2EffectCommands.run(Gen2EffectCommands.ARENA_TRAP, turn)

	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CANT_RUN))
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.CANT_RUN))
	assert_false(_first(turn.events, Gen2Battle.CANT_ESCAPE_SET).is_empty())


func test_mean_look_fails_against_a_hidden_target_and_on_a_second_use() -> void:
	var flying: Gen2Battle = _battle()
	flying.enemy.substatus |= Gen2Substatus.FLYING
	var first: Gen2Turn = _turn(flying, Fixture.MEAN_LOOK)
	Gen2EffectCommands.run(Gen2EffectCommands.ARENA_TRAP, first)
	assert_false(Gen2Substatus.has(flying.player.substatus, Gen2Substatus.CANT_RUN))
	assert_false(_first(first.events, Gen2Battle.MOVE_FAILED).is_empty())

	# The "already trapped" check is the user's own flag, so a second Mean Look
	# from the same Pokémon is what fails.
	var again: Gen2Battle = _battle()
	again.player.substatus |= Gen2Substatus.CANT_RUN
	var second: Gen2Turn = _turn(again, Fixture.MEAN_LOOK)
	Gen2EffectCommands.run(Gen2EffectCommands.ARENA_TRAP, second)
	assert_false(_first(second.events, Gen2Battle.MOVE_FAILED).is_empty())


## Every secondary effect sits behind `checkfaint` in `data/moves/effects.asm`,
## and `BattleCommand_CheckFaint` ends on `jp EndMoveEffect`, so a knocked out
## target is never left burned, poisoned, flinching or confused either.
func test_a_knocked_out_target_takes_no_secondary_effect() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 1

	var turn: Gen2Turn = _run_move(battle, Fixture.EMBER_BURNS)

	assert_true(battle.enemy.is_fainted())
	assert_eq(battle.enemy.status, Gen2Status.NONE)
	assert_true(_first(turn.events, Gen2Battle.STATUS_INFLICTED).is_empty())


## `BattleCommand_CheckFaint` ends on `jp EndMoveEffect`, so nothing the
## cartridge places behind it reaches a target that has already gone down.
func test_a_knocked_out_target_is_never_bound() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 1
	battle.player.change_stage("accuracy", 6)

	var turn: Gen2Turn = _run_move(battle, Fixture.WRAP)

	assert_true(battle.enemy.is_fainted())
	assert_eq(battle.enemy.trapped_turns, 0)
	assert_true(_first(turn.events, Gen2Battle.TRAPPED).is_empty())


func _of_type(events: Array, type: StringName) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _first(events: Array, type: StringName) -> Dictionary:
	for event: Dictionary in events:
		if event["type"] == type:
			return event
	return {}
