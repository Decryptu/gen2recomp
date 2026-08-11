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


## The default enemy is a Geodude, which is Ground and so immune to Electric.
## Anything testing Thunder needs a target it can actually reach.
func _electric_battle() -> Gen2Battle:
	return Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		Gen2BattleMon.create(_data, Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		_rng
	)


func _turn(battle: Gen2Battle, move_number: int = Fixture.TACKLE) -> Gen2Turn:
	return Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, move_number, _data.move(move_number), []
	)


## The five steps a hit is worked out in, in the order every damaging list in
## `data/moves/effects.asm` runs them. A test that wants a damage figure wants
## all five, since `damagecalc` on its own divides by stats `damagestats` has
## not picked yet.
func _run_damage_steps(turn: Gen2Turn) -> void:
	for command: StringName in [
		Gen2EffectCommands.CRITICAL, Gen2EffectCommands.DAMAGE_STATS,
		Gen2EffectCommands.DAMAGE_CALC, Gen2EffectCommands.STAB,
		Gen2EffectCommands.DAMAGE_VARIATION,
	]:
		Gen2EffectCommands.run(command, turn)


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


## The same run from the other side of the field, for a move whose whole point is
## what it leaves on the Pokémon opposite.
func _run_enemy_move(battle: Gen2Battle, move_number: int) -> Gen2Turn:
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.ENEMY, 0, move_number, _data.move(move_number), []
	)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	for command: StringName in Gen2MoveEffect.sequence_for(turn.effect()):
		if turn.ended:
			break
		Gen2EffectCommands.run(command, turn)
	return turn


## A battle whose player side has a bench, which only Heal Bell needs: it is the
## one move that reaches past the Pokémon on the field.
func _party_battle() -> Gen2Battle:
	return Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.HEAL_BELL]),
			Gen2BattleMon.create(_data, Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
			Gen2BattleMon.create(_data, Fixture.BULBASAUR, 50, [Fixture.TACKLE]),
		]),
		Gen2Party.create([
			Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		]),
		_rng
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
	_run_damage_steps(turn)
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
	_run_damage_steps(turn)
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
	assert_false(status_move.has(Gen2EffectCommands.STAB), "no power, so no matchup step")


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
	var event: Dictionary = _first(turn.events, Gen2Battle.CHARGING_UP)
	assert_eq(event["side"], Gen2Battle.PLAYER)
	## `.UsedText` picks its line by move number, so the move travels with it.
	assert_eq(int(event["move"]), Fixture.SOLARBEAM)


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


func test_rollout_doubles_between_the_matchup_and_the_spread() -> void:
	# `rolloutpower` is both halves of Rollout, the count and the doubling, and
	# sits after `stab` and the hit check: the doubling lands on the matched-up
	# damage and the spread is taken from the doubled figure.
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.ROLLOUT)
	assert_lt(
		sequence.find(Gen2EffectCommands.STAB),
		sequence.find(Gen2EffectCommands.ROLLOUT_POWER)
	)
	assert_lt(
		sequence.find(Gen2EffectCommands.ROLLOUT_POWER),
		sequence.find(Gen2EffectCommands.DAMAGE_VARIATION)
	)

	# One doubling is spent doing nothing, which is `inc [hl]` then `dec b`: the
	# first hit is worth its own power and the fifth sixteen times it.
	var battle: Gen2Battle = _battle()
	for pair: Array in [[1, 1], [2, 2], [3, 4], [4, 8], [5, 16]]:
		battle.player.rollout_count = int(pair[0]) - 1
		battle.player.substatus |= Gen2Substatus.ROLLOUT
		var turn: Gen2Turn = _turn(battle, Fixture.ROLLOUT)
		turn.damage = 100
		Gen2EffectCommands.run(Gen2EffectCommands.ROLLOUT_POWER, turn)
		assert_eq(turn.damage, 100 * int(pair[1]), "hit %d" % int(pair[0]))


func test_defense_curl_is_worth_one_more_doubling_to_a_rollout() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.CURLED
	var turn: Gen2Turn = _turn(battle, Fixture.ROLLOUT)
	turn.damage = 100
	Gen2EffectCommands.run(Gen2EffectCommands.ROLLOUT_POWER, turn)
	assert_eq(turn.damage, 200, "the first hit of a curled Rollout is already two")


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
	_run_damage_steps(turn)
	Gen2EffectCommands.run(Gen2EffectCommands.MULTI_HIT, turn)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 2)
	assert_eq(int(_first(turn.events, Gen2Battle.HIT_TIMES)["times"]), 2)


func test_multi_hit_lands_between_two_and_five_times() -> void:
	# Twenty different seeds, so the roll's own range gets exercised rather than
	# whatever one seed happens to land on.
	for seed_value: int in range(1, 21):
		_rng.seed = seed_value
		var turn: Gen2Turn = _turn(_battle(), Fixture.MULTI_HIT_MOVE)
		_run_damage_steps(turn)
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
	_run_damage_steps(turn)
	Gen2EffectCommands.run(Gen2EffectCommands.MULTI_HIT, turn)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 1, "the one hit that finished it")
	assert_eq(_first(turn.events, Gen2Battle.HIT_TIMES), {})
	assert_true(turn.ended)
	assert_eq(_first(turn.events, Gen2Battle.FAINTED)["side"], Gen2Battle.ENEMY)


func test_twineedle_hits_twice_then_rolls_poison_once_for_both() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.TWINEEDLE_MOVE)
	_run_damage_steps(turn)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_HIT, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.EFFECT_CHANCE, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.MULTI_HIT, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.POISON_TARGET, turn)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 2)
	assert_true(
		Gen2Status.has(turn.defender().status, Gen2Status.POISON), "the 256-chance never fails"
	)
	assert_eq(_of_type(turn.events, Gen2Battle.STATUS_INFLICTED).size(), 1, "once, not per hit")


## The two lists differ in exactly one step: `LeechHit` ends on `kingsrock` and
## `DreamEater` does not, which is the only thing separating them in
## `data/moves/effects.asm`. Everything else about Dream Eater, including the
## sleep gate, is [constant Gen2EffectCommands.CHECK_HIT]'s.
func test_the_two_drain_lists_differ_only_in_the_kings_rock_step() -> void:
	var leech: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.LEECH_HIT)
	var dream_eater: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.DREAM_EATER)
	assert_true(leech.has(Gen2EffectCommands.KINGS_ROCK))
	assert_false(dream_eater.has(Gen2EffectCommands.KINGS_ROCK))
	assert_eq(
		leech.filter(func(c: StringName) -> bool: return c != Gen2EffectCommands.KINGS_ROCK),
		dream_eater
	)
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
		"the matchup STAB worked out is only kept for whether it is immune"
	)


func test_level_damage_deals_exactly_the_users_level() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.LEVEL_DAMAGE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.RESET_TYPE_MATCHUP, turn)
	assert_eq(turn.damage, turn.attacker().level)
	assert_false(turn.critical, "constant damage never criticals")
	assert_eq(turn.effectiveness, RomLayout.MATCHUP_EFFECTIVE, "no effectiveness line for it either")


func test_static_damage_deals_exactly_the_moves_own_power() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.STATIC_DAMAGE_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.RESET_TYPE_MATCHUP, turn)
	assert_eq(turn.damage, 20, "Sonicboom's own power in the fixture")


func test_super_fang_halves_the_targets_current_hp() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 51
	var turn: Gen2Turn = _turn(battle, Fixture.SUPER_FANG_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.RESET_TYPE_MATCHUP, turn)
	assert_eq(turn.damage, 25, "floored, not rounded")


func test_super_fang_never_deals_less_than_one() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 1
	var turn: Gen2Turn = _turn(battle, Fixture.SUPER_FANG_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.RESET_TYPE_MATCHUP, turn)
	assert_eq(turn.damage, 1)


func test_psywave_stays_inside_its_own_range() -> void:
	var turn: Gen2Turn = _turn(_battle(), Fixture.PSYWAVE_MOVE)
	var level: int = turn.attacker().level
	@warning_ignore("integer_division")
	var upper: int = level / 2 + level
	for seed_value: int in range(1, 21):
		_rng.seed = seed_value
		Gen2EffectCommands.run(Gen2EffectCommands.FIXED_DAMAGE, turn)
		Gen2EffectCommands.run(Gen2EffectCommands.RESET_TYPE_MATCHUP, turn)
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
	assert_eq(trap.size(), Gen2MoveEffect.NORMAL_HIT.size(), "one step swapped, none added")
	assert_false(trap.has(Gen2EffectCommands.KINGS_ROCK))
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


## The three weather moves are three commands and a terminator each, with no
## accuracy step: Rain Dance and Sunny Day carry 90% and neither ever rolls it.
func test_the_weather_moves_have_their_cartridge_sequences() -> void:
	for effect: int in [
		Gen2MoveEffect.RAIN_DANCE, Gen2MoveEffect.SUNNY_DAY, Gen2MoveEffect.SANDSTORM
	]:
		var sequence: Array = Gen2MoveEffect.sequence_for(effect)
		assert_true(Gen2MoveEffect.is_written(effect), "effect %d" % effect)
		assert_eq(sequence.size(), 4, "effect %d" % effect)
		assert_false(sequence.has(Gen2EffectCommands.CHECK_HIT), "effect %d rolls" % effect)


func test_each_weather_move_sets_its_own_weather_for_five_turns() -> void:
	for pair: Array in [
		[Fixture.RAIN_DANCE, Gen2Weather.RAIN],
		[Fixture.SUNNY_DAY, Gen2Weather.SUN],
		[Fixture.SANDSTORM, Gen2Weather.SANDSTORM],
	]:
		var battle: Gen2Battle = _battle()

		var turn: Gen2Turn = _run_move(battle, int(pair[0]))

		assert_eq(battle.weather, int(pair[1]), JSON.stringify(turn.events))
		assert_eq(battle.weather_turns, Gen2Weather.TURNS)
		assert_eq(int(_first(turn.events, Gen2Battle.WEATHER_STARTED)["weather"]), int(pair[1]))


## Only `BattleCommand_StartSandstorm` has a failure branch, and only against its
## own weather. Sunny Day in sun restarts the count instead.
func test_only_sandstorm_refuses_to_set_its_own_weather_again() -> void:
	var sandy: Gen2Battle = _battle()
	sandy.weather = Gen2Weather.SANDSTORM
	sandy.weather_turns = 2

	var refused: Gen2Turn = _run_move(sandy, Fixture.SANDSTORM)

	assert_eq(sandy.weather_turns, 2, "the count was restarted")
	assert_false(_first(refused.events, Gen2Battle.MOVE_FAILED).is_empty())

	var sunny: Gen2Battle = _battle()
	sunny.weather = Gen2Weather.SUN
	sunny.weather_turns = 2

	var restarted: Gen2Turn = _run_move(sunny, Fixture.SUNNY_DAY)

	assert_eq(sunny.weather_turns, Gen2Weather.TURNS)
	assert_true(_first(restarted.events, Gen2Battle.MOVE_FAILED).is_empty())


## Either of the other two replaces a Sandstorm outright: neither one checks the
## weather at all before writing it.
func test_rain_and_sun_replace_a_sandstorm() -> void:
	for pair: Array in [
		[Fixture.RAIN_DANCE, Gen2Weather.RAIN], [Fixture.SUNNY_DAY, Gen2Weather.SUN]
	]:
		var battle: Gen2Battle = _battle()
		battle.weather = Gen2Weather.SANDSTORM
		battle.weather_turns = 3

		_run_move(battle, int(pair[0]))

		assert_eq(battle.weather, int(pair[1]))
		assert_eq(battle.weather_turns, Gen2Weather.TURNS)


## `BattleCommand_ThunderAccuracy` writes `wPlayerMoveStruct + MOVE_ACC`, a
## per-turn copy, which is why this lands on the turn and not on the move.
func test_thunder_takes_its_accuracy_from_the_weather() -> void:
	for pair: Array in [
		[Gen2Weather.NONE, -1], [Gen2Weather.SANDSTORM, -1],
		[Gen2Weather.SUN, Gen2EffectCommands.THUNDER_SUN_ACCURACY],
		[Gen2Weather.RAIN, Gen2Accuracy.ALWAYS_HITS],
	]:
		var battle: Gen2Battle = _electric_battle()
		battle.weather = int(pair[0])
		var turn: Gen2Turn = _turn(battle, Fixture.THUNDER)

		Gen2EffectCommands.run(Gen2EffectCommands.THUNDER_ACCURACY, turn)

		assert_eq(turn.accuracy, int(pair[1]), "weather %d" % int(pair[0]))
		assert_eq(int(_data.move(Fixture.THUNDER)["accuracy"]), 178, "the cached row was written")


## `.ThunderRain` sits among `CheckHit`'s always-hit branches, ahead of the stat
## modifiers, so evasion cannot take it away either.
func test_thunder_cannot_miss_in_rain() -> void:
	var battle: Gen2Battle = _electric_battle()
	battle.weather = Gen2Weather.RAIN
	battle.enemy.change_stage("evasion", 6)

	for _attempt: int in 20:
		var turn: Gen2Turn = _turn(battle, Fixture.THUNDER)
		Gen2EffectCommands.run(Gen2EffectCommands.CHECK_HIT, turn)
		assert_false(turn.missed)


## Thunder is a paralysing move through its own effect byte, not through
## `EFFECT_PARALYZE_HIT`, which is why it did nothing but damage until the
## weather gave the effect a reason to exist.
func test_thunder_paralyses_behind_its_own_effect() -> void:
	var battle: Gen2Battle = _electric_battle()
	battle.weather = Gen2Weather.RAIN

	var turn: Gen2Turn = _run_move(battle, Fixture.THUNDER_ALWAYS_PARALYZES)

	assert_false(turn.missed, JSON.stringify(turn.events))
	assert_true(Gen2Status.has(battle.enemy.status, Gen2Status.PARALYSIS))


## `BattleCommand_SkipSunCharge` skips past the charge command the way
## `checkcharge` does, so Solarbeam fires the turn it is chosen.
func test_solarbeam_skips_its_charge_turn_in_sun() -> void:
	var sunny: Gen2Battle = _battle()
	sunny.weather = Gen2Weather.SUN

	var fired: Gen2Turn = _run_move(sunny, Fixture.SOLARBEAM)

	assert_false(Gen2Substatus.has(sunny.player.substatus, Gen2Substatus.CHARGING))
	assert_eq(sunny.player.charged_move, 0)
	assert_false(_first(fired.events, Gen2Battle.HIT).is_empty(), JSON.stringify(fired.events))

	var plain: Gen2Battle = _battle()

	var charging: Gen2Turn = _run_move(plain, Fixture.SOLARBEAM)

	assert_true(Gen2Substatus.has(plain.player.substatus, Gen2Substatus.CHARGING))
	assert_false(_first(charging.events, Gen2Battle.CHARGING_UP).is_empty())


## Sun that arrives while a Solarbeam is already charging does not strand it:
## `checkcharge` runs ahead of `skipsuncharge` and answers the release turn
## first, which is [method Gen2EffectCommands._charge_move]'s own first branch.
func test_sun_arriving_mid_charge_still_releases_the_beam() -> void:
	var battle: Gen2Battle = _battle()

	_run_move(battle, Fixture.SOLARBEAM)
	battle.weather = Gen2Weather.SUN

	var released: Gen2Turn = _run_move(battle, Fixture.SOLARBEAM, true)

	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CHARGING))
	assert_false(_first(released.events, Gen2Battle.HIT).is_empty(), JSON.stringify(released.events))


## `BattleCommand_FreezeTarget` returns in sun, before it has written anything.
func test_nothing_freezes_in_sun() -> void:
	var battle: Gen2Battle = _battle()
	battle.weather = Gen2Weather.SUN
	var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)

	Gen2EffectCommands.run(Gen2EffectCommands.FREEZE_TARGET, turn)

	assert_eq(battle.enemy.status, Gen2Status.NONE)

	battle.weather = Gen2Weather.RAIN
	var wet: Gen2Turn = _turn(battle, Fixture.TACKLE)

	Gen2EffectCommands.run(Gen2EffectCommands.FREEZE_TARGET, wet)

	assert_true(Gen2Status.has(battle.enemy.status, Gen2Status.FREEZE))


func _of_type(events: Array, type: StringName) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _first(events: Array, type: StringName) -> Dictionary:
	for event: Dictionary in events:
		if event["type"] == type:
			return event
	return {}


## `.BrightPowder` comes off the accuracy after the stat modifiers and before the
## roll, floored at zero. Twenty off a move that always hit is the whole point:
## 255 is the one chance that skips the roll, so anything taken off it puts the
## move back on the dice.
func test_brightpowder_takes_its_parameter_off_the_accuracy() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.item = Fixture.BRIGHTPOWDER

	var missed: int = 0
	for seed: int in 200:
		battle.rng.seed = seed
		var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)
		Gen2EffectCommands.run(Gen2EffectCommands.CHECK_HIT, turn)
		if turn.missed:
			missed += 1

	assert_gt(missed, 0, "a 255 move can miss behind BrightPowder")
	assert_lt(missed, 40, "twenty in 255, not more")

	battle.enemy.item = 0
	for seed: int in 50:
		battle.rng.seed = seed
		var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)
		Gen2EffectCommands.run(Gen2EffectCommands.CHECK_HIT, turn)
		assert_false(turn.missed, "and without it the same move never misses")


## `BattleCommand_HeldFlinch` is a chance out of the item's own parameter and is
## not a secondary effect: nothing gates it on the move's own chance byte.
func test_kings_rock_flinches_out_of_its_own_parameter() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.item = Fixture.KINGS_ROCK

	var flinched: int = 0
	for seed: int in 256:
		battle.rng.seed = seed
		battle.enemy.substatus = Gen2Substatus.NONE
		var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)
		Gen2EffectCommands.run(Gen2EffectCommands.KINGS_ROCK, turn)
		if Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.FLINCHED):
			flinched += 1

	assert_between(flinched, 10, 60, "roughly thirty in 256 across 256 seeds")

	battle.player.item = 0
	battle.enemy.substatus = Gen2Substatus.NONE
	Gen2EffectCommands.run(Gen2EffectCommands.KINGS_ROCK, _turn(battle, Fixture.TACKLE))
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.FLINCHED))


## `kingsrock` sits at the tail of every ordinary attack and on none of the moves
## that carry a flinch of their own, which is the whole of the difference between
## `NormalHit` and `FlinchHit`.
func test_only_the_lists_the_cartridge_gives_kings_rock_have_it() -> void:
	for effect: int in [
		Gen2MoveEffect.LEECH_HIT, Gen2MoveEffect.SELFDESTRUCT, Gen2MoveEffect.RECOIL_HIT,
		Gen2MoveEffect.MULTI_HIT, Gen2MoveEffect.TWINEEDLE, Gen2MoveEffect.SUPER_FANG,
		Gen2MoveEffect.ROLLOUT, Gen2MoveEffect.SKULL_BASH, Gen2MoveEffect.SOLARBEAM,
		Gen2MoveEffect.COUNTER, Gen2MoveEffect.MIRROR_COAT, Gen2MoveEffect.RAMPAGE,
		Gen2MoveEffect.SKY_ATTACK, Gen2MoveEffect.RAZOR_WIND, Gen2MoveEffect.FLY_OR_DIG,
	]:
		assert_true(
			Gen2MoveEffect.sequence_for(effect).has(Gen2EffectCommands.KINGS_ROCK),
			"effect %d should carry it" % effect
		)

	for effect: int in [
		Gen2MoveEffect.DREAM_EATER, Gen2MoveEffect.OHKO, Gen2MoveEffect.TRAP_TARGET,
		Gen2MoveEffect.RECHARGE_HIT, Gen2MoveEffect.THUNDER, Gen2MoveEffect.DEFENSE_CURL,
		Gen2MoveEffect.FLINCH_HIT, Gen2MoveEffect.BURN_HIT, Gen2MoveEffect.MEAN_LOOK,
		Gen2MoveEffect.RAIN_DANCE,
	]:
		assert_false(
			Gen2MoveEffect.sequence_for(effect).has(Gen2EffectCommands.KINGS_ROCK),
			"effect %d should not" % effect
		)

	# PoisonMultiHit puts it ahead of its own poison, not behind it.
	var twineedle: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.TWINEEDLE)
	assert_lt(
		twineedle.find(Gen2EffectCommands.KINGS_ROCK),
		twineedle.find(Gen2EffectCommands.POISON_TARGET)
	)


## `BattleCommand_ApplyDamage`'s Focus Band branch calls `BattleCommand_FalseSwipe`,
## which is what leaves the Pokémon on one hit point rather than none.
func test_a_focus_band_can_hold_a_pokemon_on_one_hit_point() -> void:
	var survived: int = 0
	for seed: int in 200:
		var battle: Gen2Battle = _battle()
		battle.rng.seed = seed
		battle.enemy.item = Fixture.FOCUS_BAND
		battle.enemy.hp = 1
		var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)
		turn.damage = 500
		Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)
		if not battle.enemy.is_fainted():
			survived += 1
			assert_eq(battle.enemy.hp, 1)
			assert_false(_first(turn.events, Gen2Battle.ENDURED).is_empty())

	assert_between(survived, 5, 50, "roughly thirty in 256")


## The roll only shows on a hit that would have finished the Pokémon: anything it
## survives anyway takes its damage in full.
func test_a_focus_band_changes_nothing_about_a_hit_that_was_not_lethal() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.item = Fixture.FOCUS_BAND
	var before: int = battle.enemy.hp

	for seed: int in 50:
		battle.rng.seed = seed
		battle.enemy.hp = before
		var turn: Gen2Turn = _turn(battle, Fixture.TACKLE)
		turn.damage = 5
		Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)
		assert_eq(battle.enemy.hp, before - 5)
		assert_true(_first(turn.events, Gen2Battle.ENDURED).is_empty())


## The heal family. `BattleCommand_Heal` for the four that just heal, and
## `BattleCommand_TimeBasedHealContinue` for the three that read the clock and
## the sky.
func test_recover_takes_back_half_the_maximum() -> void:
	var battle: Gen2Battle = _battle()
	var mon: Gen2BattleMon = battle.player
	mon.hp = 1

	var turn: Gen2Turn = _run_move(battle, Fixture.RECOVER)

	@warning_ignore("integer_division")
	assert_eq(mon.hp, 1 + mon.max_hp() / 2)
	assert_false(_first(turn.events, Gen2Battle.HP_RESTORED).is_empty())


func test_a_heal_at_full_health_fails_and_costs_the_turn() -> void:
	var battle: Gen2Battle = _battle()
	var mon: Gen2BattleMon = battle.player
	var before: int = mon.hp

	var turn: Gen2Turn = _run_move(battle, Fixture.SOFTBOILED)

	assert_eq(mon.hp, before)
	assert_false(_first(turn.events, Gen2Battle.HP_ALREADY_FULL).is_empty())
	assert_true(_first(turn.events, Gen2Battle.HP_RESTORED).is_empty())


## Rest is the whole bar rather than half, which is what the move number buys:
## the other three moves on this effect byte run the same command.
func test_rest_fills_the_bar_where_milk_drink_takes_half() -> void:
	var rested: Gen2Battle = _battle()
	rested.player.hp = 1
	var sleeping: Gen2Turn = _run_move(rested, Fixture.REST)

	assert_eq(rested.player.hp, rested.player.max_hp())
	assert_eq(Gen2Status.sleep_turns(rested.player.status), Gen2Status.REST_SLEEP_TURNS + 1)
	assert_false(_first(sleeping.events, Gen2Battle.WENT_TO_SLEEP).is_empty())

	var milk: Gen2Battle = _battle()
	milk.player.hp = 1

	_run_move(milk, Fixture.MILK_DRINK)

	@warning_ignore("integer_division")
	assert_eq(milk.player.hp, 1 + milk.player.max_hp() / 2)
	assert_eq(Gen2Status.sleep_turns(milk.player.status), 0, "only Rest sleeps")


## Rest writes its counter over the whole status byte, so it is the one move in
## the game that cures a burn, and it clears Toxic's ramp with it.
func test_rest_clears_every_other_status_and_the_toxic_ramp() -> void:
	var battle: Gen2Battle = _battle()
	var mon: Gen2BattleMon = battle.player
	mon.hp = 1
	mon.status = Gen2Status.POISON
	mon.toxic_counter = 4

	var turn: Gen2Turn = _run_move(battle, Fixture.REST)

	assert_false(Gen2Status.has(mon.status, Gen2Status.POISON))
	assert_eq(mon.toxic_counter, 0)
	assert_eq(Gen2Status.sleep_turns(mon.status), Gen2Status.REST_SLEEP_TURNS + 1)
	# "fell asleep and became healthy" rather than "went to sleep", chosen on
	# whether there was a status to clear.
	assert_false(_first(turn.events, Gen2Battle.RESTED).is_empty())
	assert_true(_first(turn.events, Gen2Battle.WENT_TO_SLEEP).is_empty())


## The full-HP refusal is checked before the Rest branch, so a burned Pokémon at
## full health neither sleeps nor loses the burn.
func test_rest_at_full_health_fails_without_sleeping() -> void:
	var battle: Gen2Battle = _battle()
	var mon: Gen2BattleMon = battle.player
	mon.status = Gen2Status.BURN

	var turn: Gen2Turn = _run_move(battle, Fixture.REST)

	assert_eq(mon.status, Gen2Status.BURN, "the burn survives")
	assert_eq(Gen2Status.sleep_turns(mon.status), 0)
	assert_false(_first(turn.events, Gen2Battle.HP_ALREADY_FULL).is_empty())


## Half by default, and matching the move's own time of day buys nothing: it is
## missing it that costs a step. `BattleCommand_TimeBasedHealContinue` skips its
## `dec c` when `wTimeOfDay` equals the label's own `MORN_F`/`DAY_F`/`NITE_F`.
func test_a_timed_heal_is_half_in_its_own_time_and_a_quarter_outside_it() -> void:
	var morning: Gen2Battle = _battle()
	morning.time_of_day = Gen2WorldPalette.TIME_MORNING
	morning.player.hp = 1

	_run_move(morning, Fixture.MORNING_SUN)

	@warning_ignore("integer_division")
	assert_eq(morning.player.hp, 1 + morning.player.max_hp() / 2)

	var midday: Gen2Battle = _battle()
	midday.time_of_day = Gen2WorldPalette.TIME_DAY
	midday.player.hp = 1

	_run_move(midday, Fixture.MORNING_SUN)

	@warning_ignore("integer_division")
	assert_eq(midday.player.hp, 1 + midday.player.max_hp() / 4)


## Synthesis asks for the day and Moonlight for the night, which is the only
## thing separating the three moves.
func test_synthesis_and_moonlight_ask_for_their_own_times() -> void:
	var day: Gen2Battle = _battle()
	day.time_of_day = Gen2WorldPalette.TIME_DAY
	day.player.hp = 1

	_run_move(day, Fixture.SYNTHESIS)

	@warning_ignore("integer_division")
	assert_eq(day.player.hp, 1 + day.player.max_hp() / 2)

	var night: Gen2Battle = _battle()
	night.time_of_day = Gen2WorldPalette.TIME_NIGHT
	night.player.hp = 1

	_run_move(night, Fixture.MOONLIGHT)

	@warning_ignore("integer_division")
	assert_eq(night.player.hp, 1 + night.player.max_hp() / 2)


## Sun is one step up the table and any other weather one step down, never two:
## `.Weather` increments first and only then takes two off for a sky that is not
## the sun.
func test_sun_doubles_a_timed_heal_and_rain_or_sand_halves_it() -> void:
	var sunny: Gen2Battle = _battle()
	sunny.time_of_day = Gen2WorldPalette.TIME_MORNING
	sunny.weather = Gen2Weather.SUN
	sunny.player.hp = 1

	_run_move(sunny, Fixture.MORNING_SUN)

	assert_eq(sunny.player.hp, sunny.player.max_hp(), "the whole bar")

	for weather: int in [Gen2Weather.RAIN, Gen2Weather.SANDSTORM]:
		var battle: Gen2Battle = _battle()
		battle.time_of_day = Gen2WorldPalette.TIME_MORNING
		battle.weather = weather
		battle.player.hp = 1

		_run_move(battle, Fixture.MORNING_SUN)

		@warning_ignore("integer_division")
		assert_eq(battle.player.hp, 1 + battle.player.max_hp() / 4, str(weather))


## The floor of the table, reached only by missing both the time and the sun.
func test_the_wrong_time_in_the_rain_heals_an_eighth() -> void:
	var battle: Gen2Battle = _battle()
	battle.time_of_day = Gen2WorldPalette.TIME_NIGHT
	battle.weather = Gen2Weather.RAIN
	battle.player.hp = 1

	_run_move(battle, Fixture.MORNING_SUN)

	@warning_ignore("integer_division")
	assert_eq(battle.player.hp, 1 + maxi(battle.player.max_hp() / 4, 1) / 2)


## `GetEighthMaxHP` halves `GetQuarterMaxHP`'s answer rather than dividing by
## eight, and both apply their own floor of one, so the smallest heal in the game
## is still one hit point.
func test_the_smallest_timed_heal_is_still_one_hit_point() -> void:
	var battle: Gen2Battle = _battle()
	battle.time_of_day = Gen2WorldPalette.TIME_NIGHT
	battle.weather = Gen2Weather.RAIN
	battle.player.stats["hp"] = 2
	battle.player.hp = 1

	_run_move(battle, Fixture.MORNING_SUN)

	assert_eq(battle.player.hp, 2)


func test_a_timed_heal_at_full_health_fails() -> void:
	var battle: Gen2Battle = _battle()
	battle.time_of_day = Gen2WorldPalette.TIME_MORNING

	var turn: Gen2Turn = _run_move(battle, Fixture.MORNING_SUN)

	assert_eq(battle.player.hp, battle.player.max_hp())
	assert_false(_first(turn.events, Gen2Battle.HP_ALREADY_FULL).is_empty())


func test_the_heal_family_has_its_cartridge_sequences() -> void:
	for effect: int in [
		Gen2MoveEffect.HEAL, Gen2MoveEffect.MORNING_SUN,
		Gen2MoveEffect.SYNTHESIS, Gen2MoveEffect.MOONLIGHT,
	]:
		assert_true(Gen2MoveEffect.is_written(effect), str(effect))
		# Announce, spend, heal, end: no accuracy roll, and no obedience check,
		# which this engine does not model on any list.
		assert_eq(Gen2MoveEffect.sequence_for(effect).size(), 4, str(effect))


## `BattleCommand_Charge.UsedText` names six moves by number, and Fly and Dig do
## not share a sentence although they share an effect byte.
func test_each_two_turn_move_has_its_own_charge_line() -> void:
	var text: Dictionary = Gen2BattleScreen.CHARGE_TEXT
	assert_eq(text[Gen2MoveEffect.RAZOR_WIND_MOVE], "made a whirlwind!")
	assert_eq(text[Gen2MoveEffect.SOLARBEAM_MOVE], "took in sunlight!")
	assert_eq(text[Gen2MoveEffect.SKULL_BASH_MOVE], "lowered its head!")
	assert_eq(text[Gen2MoveEffect.SKY_ATTACK_MOVE], "is glowing!")
	assert_eq(text[Gen2MoveEffect.FLY_MOVE], "flew up high!")
	assert_eq(text[Gen2MoveEffect.DIG_MOVE], "dug a hole!")
	assert_ne(
		text[Gen2MoveEffect.FLY_MOVE], text[Gen2MoveEffect.DIG_MOVE],
		"one effect byte, two sentences"
	)


## `.UsedText`'s Dig branch is the only one of the six with no `jr z` behind it,
## so it is what a move reaching that dispatch without matching prints.
func test_the_charge_line_falls_through_to_dig() -> void:
	assert_eq(Gen2BattleScreen.CHARGE_DUG, Gen2BattleScreen.CHARGE_TEXT[Gen2MoveEffect.DIG_MOVE])


## The effects whose whole job is a number the move table does not hold. Every
## one of these moves ships with a power of 1 or 10 and is worthless until the
## step that fills it in runs, so the arithmetic is what the tests are about.

func test_return_and_frustration_read_the_happiness_from_either_end() -> void:
	# `happiness * 10 / 25`, truncating, and 255 minus it for Frustration.
	assert_eq(Gen2Damage.happiness_power(0), 0)
	assert_eq(Gen2Damage.happiness_power(70), 28)
	assert_eq(Gen2Damage.happiness_power(255), 102)
	assert_eq(Gen2Damage.happiness_power(255, true), 0)
	assert_eq(Gen2Damage.happiness_power(0, true), 102)
	assert_eq(Gen2Damage.happiness_power(70, true), 74)


func test_the_two_ends_that_deal_nothing_are_the_cartridges_own_bug() -> void:
	# `BattleCommand_HappinessPower` is commented as a bug in the source and is
	# reproduced rather than fixed: a power of zero is refused by `damagecalc`,
	# so a hated Pokémon's Return does nothing at all.
	var battle: Gen2Battle = _battle()
	battle.player.happiness = 0
	var turn: Gen2Turn = _run_move(battle, Fixture.RETURN)
	assert_eq(turn.power_override, 0)
	assert_eq(turn.damage, 0)


func test_return_off_a_normal_happiness_is_a_real_hit() -> void:
	var battle: Gen2Battle = _battle()
	assert_eq(battle.player.happiness, Gen2BattleMon.BASE_HAPPINESS)
	var turn: Gen2Turn = _run_move(battle, Fixture.RETURN)
	assert_eq(turn.power_override, 28)
	assert_gt(turn.damage, 2, "a power of 28 is not a power of 1")


func test_the_magnitude_table_is_the_cartridges_own_thresholds() -> void:
	# `percent` truncates, so `5 percent + 1` is 13 and `15 percent` is 38. The
	# first row whose threshold is at or above the roll wins.
	for pair: Array in [
		[0, 10, 4], [13, 10, 4], [14, 30, 5], [38, 30, 5], [39, 50, 6],
		[89, 50, 6], [90, 70, 7], [166, 70, 7], [167, 90, 8], [217, 90, 8],
		[218, 110, 9], [242, 110, 9], [243, 150, 10], [255, 150, 10],
	]:
		var row: Array = Gen2Damage.magnitude_row(int(pair[0]))
		assert_eq(int(row[1]), int(pair[1]), "power at roll %d" % int(pair[0]))
		assert_eq(int(row[2]), int(pair[2]), "number at roll %d" % int(pair[0]))


func test_magnitude_says_which_one_it_rolled_before_it_lands() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.MAGNITUDE)
	var said: Dictionary = _first(turn.events, Gen2Battle.MAGNITUDE)
	assert_false(said.is_empty(), "the line is printed")
	assert_between(int(said["magnitude"]), 4, 10)
	assert_lt(
		turn.events.find(said), turn.events.size(),
		"and before whatever the hit did"
	)
	assert_gt(turn.power_override, 1, "the stored power of 1 was overwritten")


func test_the_flail_table_is_read_off_how_much_health_is_left() -> void:
	# `HP_BAR_LENGTH_PX` is 48, so the index is 48ths of the bar and the emptier
	# it is the earlier the walk stops.
	for pair: Array in [
		[1, 48, 200], [2, 48, 150], [4, 48, 150], [5, 48, 100], [9, 48, 100],
		[10, 48, 80], [16, 48, 80], [17, 48, 40], [32, 48, 40], [33, 48, 20],
		[48, 48, 20],
	]:
		assert_eq(
			Gen2Damage.flail_reversal_power(int(pair[0]), int(pair[1])),
			int(pair[2]), "%d of %d" % [int(pair[0]), int(pair[1])]
		)


func test_a_maximum_over_a_byte_divides_both_sides_down_first() -> void:
	# `.reversal` shifts the product and the divisor right two bits each before
	# the divide, because the routine's divisor is one byte wide. The answer is
	# the cartridge's, not a rounding of the exact one.
	assert_eq(Gen2Damage.flail_reversal_power(300, 300), 20, "a full bar is weakest")
	assert_eq(Gen2Damage.flail_reversal_power(1, 300), 200, "and an empty one strongest")
	assert_eq(Gen2Damage.flail_reversal_power(150, 300), 40)


func test_flail_at_deaths_door_hits_far_harder_than_at_full_health() -> void:
	var healthy: Gen2Battle = _battle()
	var healthy_turn: Gen2Turn = _run_move(healthy, Fixture.FLAIL)

	var hurt: Gen2Battle = _battle()
	hurt.player.hp = 1
	var hurt_turn: Gen2Turn = _run_move(hurt, Fixture.FLAIL)

	assert_eq(healthy_turn.power_override, 20)
	assert_eq(hurt_turn.power_override, 200)
	assert_gt(hurt_turn.damage, healthy_turn.damage)


func test_reversal_keeps_the_matchup_the_constant_damage_moves_throw_away() -> void:
	# Its list carries `stab` where the other four carry `resettypematchup`, so
	# Flail is the one branch of `constantdamage` whose effectiveness is real.
	# Normal against Geodude's Rock is half.
	assert_true(
		Gen2MoveEffect.sequence_for(Gen2MoveEffect.REVERSAL).has(Gen2EffectCommands.STAB)
	)
	assert_false(
		Gen2MoveEffect.sequence_for(Gen2MoveEffect.LEVEL_DAMAGE).has(Gen2EffectCommands.STAB)
	)
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.FLAIL)
	assert_eq(turn.effectiveness, RomLayout.MATCHUP_NOT_VERY_EFFECTIVE)


func test_hidden_power_reads_a_type_and_a_power_out_of_the_dvs() -> void:
	# Perfect DVs are 15 across, so every top bit is set and every low pair is 3:
	# the nibble is %1111, power is (15 * 5 + 3) / 2 + 31 = 70, and the type is
	# 3 | (3 << 2) = 15, then 16 past Normal, 17 past BIRD and 27 past the ten
	# unused, which is Dark: the flawless Hidden Power every guide names.
	var perfect: Dictionary = Gen2Damage.hidden_power(Gen2BattleMon.PERFECT_DVS)
	assert_eq(int(perfect["power"]), 70)
	assert_eq(int(perfect["type"]), RomLayout.TYPE_DARK)

	# All zero: the nibble is 0, power is 0 / 2 + 31 = 31, and the type is 0,
	# which becomes 1 on the skip past Normal.
	var empty: Dictionary = Gen2Damage.hidden_power(0)
	assert_eq(int(empty["power"]), 31)
	assert_eq(int(empty["type"]), RomLayout.TYPE_FIGHTING)


func test_hidden_powers_type_steps_over_bird_and_the_unused_run() -> void:
	# No DV pair can produce either, which is the whole reason for the two skips.
	for attack: int in range(0, 16):
		for defense: int in range(0, 16):
			var dvs: int = Gen2Stats.pack_dvs(attack, defense, 0, 0)
			var resolved: int = int(Gen2Damage.hidden_power(dvs)["type"])
			assert_ne(resolved, RomLayout.TYPE_NORMAL, "never Normal")
			assert_ne(resolved, RomLayout.TYPE_BIRD, "never BIRD")
			assert_false(
				resolved >= RomLayout.TYPE_UNUSED_START
					and resolved < RomLayout.TYPE_UNUSED_END,
				"never one of the ten unused"
			)


func test_hidden_power_runs_damagestats_off_the_type_it_chose() -> void:
	# Its list carries no `damagestats`: the command runs it once the type is
	# known, because whether the move is physical or special follows from it.
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.HIDDEN_POWER)
	assert_false(sequence.has(Gen2EffectCommands.DAMAGE_STATS))
	assert_lt(
		sequence.find(Gen2EffectCommands.HIDDEN_POWER),
		sequence.find(Gen2EffectCommands.DAMAGE_CALC)
	)

	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.HIDDEN_POWER)
	assert_eq(turn.type_override, RomLayout.TYPE_DARK)
	assert_eq(turn.power_override, 70)
	assert_gt(turn.attack_stat, 0, "the stats were picked after the type was")


func test_the_present_table_has_three_hits_and_a_heal() -> void:
	for pair: Array in [
		[0, 40], [102, 40], [103, 80], [179, 80], [180, 120], [204, 120],
		[205, -1], [255, -1],
	]:
		assert_eq(
			Gen2Damage.present_power(int(pair[0])), int(pair[1]),
			"roll %d" % int(pair[0])
		)


func test_presents_fourth_row_heals_the_target_a_quarter() -> void:
	# The source switches turn around the heal, so `RegainedHealthText` names the
	# Pokémon that got the present rather than the one that gave it.
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 1
	var found: bool = false
	for seed_value: int in range(1, 60):
		_rng.seed = seed_value
		battle.enemy.hp = 1
		var turn: Gen2Turn = _run_move(battle, Fixture.PRESENT)
		var restored: Dictionary = _first(turn.events, Gen2Battle.HP_RESTORED)
		if restored.is_empty():
			continue
		found = true
		assert_eq(int(restored["side"]), Gen2Battle.ENEMY, "the target regained it")
		@warning_ignore("integer_division")
		var quarter: int = maxi(battle.enemy.max_hp() / 4, 1)
		assert_eq(int(restored["amount"]), quarter)
		assert_eq(battle.enemy.hp, 1 + quarter)
		break
	assert_true(found, "one roll in five reaches the heal row")


func test_a_present_to_a_target_at_full_health_is_refused() -> void:
	var battle: Gen2Battle = _battle()
	var found: bool = false
	for seed_value: int in range(1, 60):
		_rng.seed = seed_value
		battle.enemy.hp = battle.enemy.max_hp()
		var turn: Gen2Turn = _run_move(battle, Fixture.PRESENT)
		var refused: Dictionary = _first(turn.events, Gen2Battle.PRESENT_REFUSED)
		if refused.is_empty():
			continue
		found = true
		assert_eq(int(refused["target"]), Gen2Battle.ENEMY)
		assert_eq(battle.enemy.hp, battle.enemy.max_hp(), "and nothing was healed")
		break
	assert_true(found, "the same one roll in five")


func test_fury_cutter_doubles_once_per_consecutive_hit_and_stops_at_sixteen() -> void:
	# Driven a command at a time rather than through whole moves: the spread
	# turns each figure into a range, and what is being checked here is the
	# doubling itself, which is exact.
	var battle: Gen2Battle = _battle()
	for pair: Array in [[1, 1], [2, 2], [3, 4], [4, 8], [5, 16], [6, 16], [9, 16]]:
		battle.player.fury_cutter_count = int(pair[0]) - 1
		var turn: Gen2Turn = _turn(battle, Fixture.FURY_CUTTER)
		turn.damage = 100
		Gen2EffectCommands.run(Gen2EffectCommands.FURY_CUTTER, turn)
		assert_eq(battle.player.fury_cutter_count, int(pair[0]), "hit %d" % int(pair[0]))
		assert_eq(turn.damage, 100 * int(pair[1]), "worth %dx" % int(pair[1]))


func test_a_run_of_fury_cutters_really_does_get_stronger() -> void:
	# The stored 95% is overridden so every one of the five connects: a miss is
	# the other test, and one here would put the count back to nothing.
	var battle: Gen2Battle = _battle()
	var seen: Array = []
	for run: int in 5:
		battle.enemy.hp = battle.enemy.max_hp()
		var turn: Gen2Turn = _run_move(
			battle, Fixture.FURY_CUTTER, false, {"accuracy": 255}
		)
		seen.append(turn.damage)
	assert_eq(battle.player.fury_cutter_count, 5, "every one of them connected")
	for step: int in 4:
		assert_gt(int(seen[step + 1]), int(seen[step]), "hit %d" % (step + 2))
	assert_gt(int(seen[4]), int(seen[0]) * 8, "the fifth is worth sixteen firsts")


func test_a_missed_fury_cutter_starts_the_count_again() -> void:
	var battle: Gen2Battle = _battle()
	_run_move(battle, Fixture.FURY_CUTTER, false, {"accuracy": 255})
	assert_eq(battle.player.fury_cutter_count, 1)
	# An accuracy of nothing, so the roll cannot land. The list runs on past the
	# miss, which is what `furycutter` is doing there rather than behind
	# `moveanim` with the rest of the damage steps.
	var missed: Gen2Turn = _run_move(battle, Fixture.FURY_CUTTER, false, {"accuracy": 0})
	assert_true(missed.missed)
	assert_eq(battle.player.fury_cutter_count, 0)


func test_a_switch_takes_the_fury_cutter_count_with_it() -> void:
	# `NewBattleMonStatus` zeroes it on a send-out, which is what
	# [method Gen2BattleMon.reset_volatile] mirrors.
	var battle: Gen2Battle = _battle()
	_run_move(battle, Fixture.FURY_CUTTER, false, {"accuracy": 255})
	assert_eq(battle.player.fury_cutter_count, 1)
	battle.player.reset_volatile()
	assert_eq(battle.player.fury_cutter_count, 0)


func test_triple_kick_is_three_kicks_each_worth_one_more() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.TRIPLE_KICK)
	assert_lt(
		sequence.find(Gen2EffectCommands.DAMAGE_CALC),
		sequence.find(Gen2EffectCommands.TRIPLE_KICK),
		"the multiply is on the calculated figure"
	)
	assert_lt(
		sequence.find(Gen2EffectCommands.TRIPLE_KICK),
		sequence.find(Gen2EffectCommands.STAB),
		"and before the matchup, not after it"
	)

	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle, Fixture.TRIPLE_KICK)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_STATS, turn)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, turn)
	var one_kick: int = turn.damage
	for kick: int in 3:
		turn.damage = one_kick
		turn.battle.battle_anim_param = kick
		Gen2EffectCommands.run(Gen2EffectCommands.TRIPLE_KICK, turn)
		assert_eq(turn.damage, one_kick * (kick + 1), "kick %d" % (kick + 1))
		Gen2EffectCommands.run(Gen2EffectCommands.KICK_COUNTER, turn)
	assert_eq(turn.battle.battle_anim_param, 3, "and the counter walked all three")


func test_false_swipe_leaves_the_target_standing_on_one() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.hp = 3
	var turn: Gen2Turn = _run_move(battle, Fixture.FALSE_SWIPE)
	assert_eq(battle.enemy.hp, 1)
	assert_false(battle.enemy.is_fainted())


func test_false_swipe_leaves_a_hit_it_could_not_have_killed_alone() -> void:
	var battle: Gen2Battle = _battle()
	var full: int = battle.enemy.max_hp()
	var turn: Gen2Turn = _run_move(battle, Fixture.FALSE_SWIPE)
	assert_lt(battle.enemy.hp, full, "it still hurts")
	assert_gt(battle.enemy.hp, 1, "and was not cut down to one")


func test_heal_bell_clears_the_whole_of_the_users_party() -> void:
	var battle: Gen2Battle = _party_battle()
	for mon: Gen2BattleMon in battle.party(Gen2Battle.PLAYER).mons:
		mon.status = Gen2Status.PARALYSIS
	battle.enemy.status = Gen2Status.PARALYSIS

	var turn: Gen2Turn = _run_move(battle, Fixture.HEAL_BELL)
	assert_false(_first(turn.events, Gen2Battle.BELL_CHIMED).is_empty())
	for mon: Gen2BattleMon in battle.party(Gen2Battle.PLAYER).mons:
		assert_eq(mon.status, Gen2Status.NONE, "every slot, not only the one out")
	assert_eq(battle.enemy.status, Gen2Status.PARALYSIS, "and nobody else's party")


func test_heal_bell_needs_no_stat_recalculation() -> void:
	# The source's trailing `CalcPlayerStats` has no counterpart here, because a
	# burn and a paralysis are applied when a stat is read rather than baked into
	# a copy. This is what says that stays true.
	var battle: Gen2Battle = _party_battle()
	var healthy: int = battle.player.stat("attack")
	battle.player.status = Gen2Status.BURN
	assert_lt(battle.player.stat("attack"), healthy, "a burn halves it")
	_run_move(battle, Fixture.HEAL_BELL)
	assert_eq(battle.player.stat("attack"), healthy, "and the bell gives it back")


func test_heal_bell_clears_the_toxic_ramp_with_the_poison() -> void:
	var battle: Gen2Battle = _party_battle()
	battle.player.status = Gen2Status.POISON
	battle.player.toxic_counter = 4
	_run_move(battle, Fixture.HEAL_BELL)
	assert_eq(battle.player.status, Gen2Status.NONE)
	assert_eq(battle.player.toxic_counter, 0)


func test_snore_fails_awake_and_lands_asleep() -> void:
	var awake: Gen2Battle = _battle()
	var awake_turn: Gen2Turn = _run_move(awake, Fixture.SNORE)
	assert_false(_first(awake_turn.events, Gen2Battle.MOVE_FAILED).is_empty())
	assert_eq(awake.enemy.hp, awake.enemy.max_hp(), "and did nothing")

	var asleep: Gen2Battle = _battle()
	# Set the sleep counter high enough that `CheckPlayerTurn` does not wake it
	# on the way in, which is what would otherwise cost the turn.
	asleep.player.status = 3
	var asleep_turn: Gen2Turn = _run_move(asleep, Fixture.SNORE)
	assert_true(_first(asleep_turn.events, Gen2Battle.MOVE_FAILED).is_empty())
	assert_lt(asleep.enemy.hp, asleep.enemy.max_hp())


func test_tri_attack_reaches_all_three_statuses_and_no_fourth() -> void:
	var seen: Dictionary = {}
	for seed_value: int in range(1, 200):
		var battle: Gen2Battle = _battle()
		battle.rng.seed = seed_value
		var turn: Gen2Turn = _run_move(battle, Fixture.TRI_ATTACK)
		var inflicted: Dictionary = _first(turn.events, Gen2Battle.STATUS_INFLICTED)
		if inflicted.is_empty():
			continue
		seen[battle.enemy.status] = true
	assert_true(seen.has(Gen2Status.PARALYSIS), "paralysis")
	assert_true(seen.has(Gen2Status.FREEZE), "freeze")
	assert_true(seen.has(Gen2Status.BURN), "burn")
	assert_eq(seen.size(), 3, "and nothing else")


func test_flame_wheel_thaws_its_user_only_once_the_hit_has_landed() -> void:
	# `CheckPlayerTurn` lets the move happen and clears no bit: the thaw is the
	# `defrost` step, which sits behind `applydamage` in the list.
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.FLAME_WHEEL)
	assert_lt(
		sequence.find(Gen2EffectCommands.APPLY_DAMAGE),
		sequence.find(Gen2EffectCommands.DEFROST)
	)
	assert_eq(
		Gen2MoveEffect.sequence_for(Gen2MoveEffect.SACRED_FIRE), sequence,
		"and Sacred Fire is the same list"
	)

	var battle: Gen2Battle = _battle()
	battle.player.status = Gen2Status.FREEZE
	var turn: Gen2Turn = _run_move(battle, Fixture.FLAME_WHEEL)
	assert_eq(battle.player.status, Gen2Status.NONE)
	assert_eq(_of_type(turn.events, Gen2Battle.THAWED).size(), 1)


func test_a_flame_wheel_that_never_connects_leaves_its_user_frozen() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.status = Gen2Status.FREEZE
	battle.enemy.change_stage("evasion", 6)
	battle.player.change_stage("accuracy", -6)
	var turn: Gen2Turn = _run_move(battle, Fixture.FLAME_WHEEL)
	assert_eq(_of_type(turn.events, Gen2Battle.MISSED).size(), 1)
	assert_eq(battle.player.status, Gen2Status.FREEZE, "still frozen solid")


func test_splash_says_nothing_happened_and_means_it() -> void:
	var battle: Gen2Battle = _battle()
	var before: int = battle.enemy.hp
	var turn: Gen2Turn = _run_move(battle, Fixture.SPLASH)
	assert_false(_first(turn.events, Gen2Battle.NOTHING_HAPPENED).is_empty())
	assert_eq(battle.enemy.hp, before)
	assert_eq(turn.damage, 0)


func test_swift_lands_through_an_evasion_nothing_else_could() -> void:
	# `EFFECT_ALWAYS_HIT` points at `NormalHit`: one comparison inside the hit
	# check is the whole of it, which is why Swift carries a stored accuracy of
	# 100 and never rolls it.
	var battle: Gen2Battle = _battle()
	battle.enemy.change_stage("evasion", 6)
	battle.player.change_stage("accuracy", -6)
	for attempt: int in 10:
		battle.enemy.hp = battle.enemy.max_hp()
		var turn: Gen2Turn = _run_move(battle, Fixture.SWIFT)
		assert_false(turn.missed, "attempt %d" % attempt)


func test_a_missed_jump_kick_costs_its_user_an_eighth_of_the_miss() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.change_stage("evasion", 6)
	battle.player.change_stage("accuracy", -6)
	var before: int = battle.player.hp
	var turn: Gen2Turn = _run_move(battle, Fixture.JUMP_KICK)
	assert_true(turn.missed)
	var crashed: Dictionary = _first(turn.events, Gen2Battle.CRASHED)
	assert_false(crashed.is_empty(), "and it hurt")
	assert_eq(int(crashed["amount"]), maxi(turn.damage >> 3, 1))
	assert_eq(battle.player.hp, before - int(crashed["amount"]))


func test_a_jump_kick_that_connects_costs_nothing() -> void:
	var battle: Gen2Battle = _battle()
	var before: int = battle.player.hp
	var turn: Gen2Turn = _run_move(battle, Fixture.JUMP_KICK)
	assert_false(turn.missed)
	assert_true(_first(turn.events, Gen2Battle.CRASHED).is_empty())
	assert_eq(battle.player.hp, before)


func test_steel_wing_is_the_raise_on_hit_run_that_was_missing() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.DEFENSE_UP_HIT)
	assert_true(sequence.has(Gen2EffectCommands.DEFENSE_UP))
	assert_true(sequence.has(Gen2EffectCommands.STAT_UP_MESSAGE))
	# The same list as the Attack raise-on-hit run, one command apart, which is
	# what says the run's seventh member was the only thing missing.
	var attack_run: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.ATTACK_UP_HIT)
	assert_eq(sequence.size(), attack_run.size())
	assert_eq(
		sequence.find(Gen2EffectCommands.DEFENSE_UP),
		attack_run.find(Gen2EffectCommands.ATTACK_UP)
	)

	var battle: Gen2Battle = _battle()
	_run_move(battle, Fixture.STEEL_WING, false, {"effect_chance": 256})
	assert_eq(battle.player.stage("defense"), 1)


func test_gust_and_earthquake_double_against_a_target_out_of_sight() -> void:
	var flying: Gen2Battle = _battle()
	flying.player.substatus |= Gen2Substatus.FLYING
	var against_flier: Gen2Turn = _run_enemy_move(flying, Fixture.GUST)
	var plain: Gen2Battle = _battle()
	var against_ground: Gen2Turn = _run_enemy_move(plain, Fixture.GUST)
	assert_gt(against_flier.damage, against_ground.damage)


func test_neither_gust_nor_earthquake_carries_a_kings_rock() -> void:
	# The two lists really do leave `kingsrock` out, which is the only thing
	# separating them from `NormalHit` besides the doubling.
	for effect: int in [Gen2MoveEffect.GUST, Gen2MoveEffect.EARTHQUAKE]:
		var sequence: Array = Gen2MoveEffect.sequence_for(effect)
		assert_false(sequence.has(Gen2EffectCommands.KINGS_ROCK), str(effect))
		assert_true(sequence.has(Gen2EffectCommands.DOUBLE_DAMAGE))


func test_the_doubling_lands_behind_the_spread_rather_than_in_front_of_it() -> void:
	for effect: int in [
		Gen2MoveEffect.GUST, Gen2MoveEffect.EARTHQUAKE, Gen2MoveEffect.TWISTER,
		Gen2MoveEffect.STOMP,
	]:
		var sequence: Array = Gen2MoveEffect.sequence_for(effect)
		assert_lt(
			sequence.find(Gen2EffectCommands.DAMAGE_VARIATION),
			sequence.find(Gen2EffectCommands.DOUBLE_DAMAGE), str(effect)
		)


func test_minimize_is_what_makes_a_stomp_hurt_twice_as_much() -> void:
	var battle: Gen2Battle = _battle()
	assert_false(battle.enemy.minimized)
	_run_enemy_move(battle, Fixture.MINIMIZE)
	assert_true(battle.enemy.minimized, "the flag is set off the move number")

	var plain: Gen2Battle = _battle()
	var against_plain: Gen2Turn = _run_move(plain, Fixture.STOMP)
	var against_small: Gen2Turn = _run_move(battle, Fixture.STOMP)
	assert_gt(against_small.damage, against_plain.damage)


func test_a_switch_takes_the_minimize_flag_with_it() -> void:
	var battle: Gen2Battle = _battle()
	_run_enemy_move(battle, Fixture.MINIMIZE)
	assert_true(battle.enemy.minimized)
	battle.enemy.reset_volatile()
	assert_false(battle.enemy.minimized)


func test_swagger_raises_the_targets_attack_and_confuses_it() -> void:
	# The two `switchturn` pairs are what put the ordinary `attackup2` on the
	# other side of the field.
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.SWAGGER)
	assert_eq(battle.enemy.stage("attack"), 2, "the target's, not the user's")
	assert_eq(battle.player.stage("attack"), 0)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.CONFUSED))
	assert_eq(turn.side, Gen2Battle.PLAYER, "and the turn was put back")


func test_switch_turn_is_its_own_inverse() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle)
	Gen2EffectCommands.run(Gen2EffectCommands.SWITCH_TURN, turn)
	assert_eq(turn.side, Gen2Battle.ENEMY)
	assert_eq(turn.target, Gen2Battle.PLAYER)
	Gen2EffectCommands.run(Gen2EffectCommands.SWITCH_TURN, turn)
	assert_eq(turn.side, Gen2Battle.PLAYER)
	assert_eq(turn.target, Gen2Battle.ENEMY)


func test_every_effect_this_tranche_wrote_has_a_list_of_its_own() -> void:
	for effect: int in [
		Gen2MoveEffect.ALWAYS_HIT, Gen2MoveEffect.TRI_ATTACK,
		Gen2MoveEffect.JUMP_KICK, Gen2MoveEffect.SPLASH, Gen2MoveEffect.SNORE,
		Gen2MoveEffect.REVERSAL, Gen2MoveEffect.FALSE_SWIPE,
		Gen2MoveEffect.HEAL_BELL, Gen2MoveEffect.TRIPLE_KICK,
		Gen2MoveEffect.FLAME_WHEEL, Gen2MoveEffect.SACRED_FIRE,
		Gen2MoveEffect.SWAGGER, Gen2MoveEffect.FURY_CUTTER,
		Gen2MoveEffect.RETURN, Gen2MoveEffect.PRESENT,
		Gen2MoveEffect.FRUSTRATION, Gen2MoveEffect.MAGNITUDE,
		Gen2MoveEffect.HIDDEN_POWER, Gen2MoveEffect.DEFENSE_UP_HIT,
		Gen2MoveEffect.TWISTER, Gen2MoveEffect.STOMP, Gen2MoveEffect.GUST,
		Gen2MoveEffect.EARTHQUAKE, Gen2MoveEffect.SUBSTITUTE,
		Gen2MoveEffect.LEECH_SEED, Gen2MoveEffect.NIGHTMARE,
		Gen2MoveEffect.CURSE, Gen2MoveEffect.SPIKES, Gen2MoveEffect.RAPID_SPIN,
	]:
		assert_true(Gen2MoveEffect.is_written(effect), "effect %d" % effect)


## A Gastly, which is the only Ghost-type this fixture has and so the only user
## that reaches `BattleCommand_Curse`'s other branch.
func _ghost_battle() -> Gen2Battle:
	return Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.GASTLY, 50, [Fixture.CURSE]),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)


## Puts a doll in front of the enemy without running the move, for the fifteen
## commands whose whole question is what happens when one is standing.
func _raise_enemy_substitute(battle: Gen2Battle) -> void:
	battle.enemy.substatus |= Gen2Substatus.SUBSTITUTE
	battle.enemy.substitute_hp = Gen2Substatus.substitute_hp_for(battle.enemy.max_hp())


func test_a_substitute_costs_a_quarter_of_the_users_own_maximum() -> void:
	var battle: Gen2Battle = _battle()
	var user: Gen2BattleMon = battle.player
	var full: int = user.max_hp()
	var turn: Gen2Turn = _run_move(battle, Fixture.SUBSTITUTE)

	assert_eq(user.hp, full - (full >> 2))
	assert_eq(user.substitute_hp, full >> 2)
	assert_true(Gen2Substatus.has(user.substatus, Gen2Substatus.SUBSTITUTE))
	assert_eq(int(_first(turn.events, Gen2Battle.SUBSTITUTE_MADE)["amount"]), full >> 2)


## The cost is a bare `srl a / rr b` twice with no `GetQuarterMaxHP` behind it,
## so it is never floored at one the way every residual in the game is.
func test_the_substitute_cost_is_the_unfloored_shift() -> void:
	assert_eq(Gen2Substatus.substitute_hp_for(100), 25)
	assert_eq(Gen2Substatus.substitute_hp_for(3), 0, "no floor at one")
	assert_eq(Gen2Substatus.quarter_damage(3), 1, "unlike every quarter that has one")


func test_a_second_substitute_says_the_first_is_still_standing() -> void:
	var battle: Gen2Battle = _battle()
	_run_move(battle, Fixture.SUBSTITUTE)
	var before: int = battle.player.hp
	var turn: Gen2Turn = _run_move(battle, Fixture.SUBSTITUTE)

	assert_eq(battle.player.hp, before, "and costs nothing")
	assert_eq(_of_type(turn.events, Gen2Battle.SUBSTITUTE_ALREADY).size(), 1)
	assert_eq(_of_type(turn.events, Gen2Battle.SUBSTITUTE_MADE).size(), 0)


## `jr c` on the borrow *or* `or e / jr z` on a result of zero, so a user sitting
## on exactly a quarter fails rather than making a doll and fainting.
func test_a_user_on_exactly_a_quarter_is_too_weak_to_make_one() -> void:
	var battle: Gen2Battle = _battle()
	var user: Gen2BattleMon = battle.player
	user.hp = user.max_hp() >> 2
	var turn: Gen2Turn = _run_move(battle, Fixture.SUBSTITUTE)

	assert_eq(user.hp, user.max_hp() >> 2, "still standing on it")
	assert_false(Gen2Substatus.has(user.substatus, Gen2Substatus.SUBSTITUTE))
	assert_eq(_of_type(turn.events, Gen2Battle.SUBSTITUTE_TOO_WEAK).size(), 1)


func test_one_more_than_a_quarter_is_enough() -> void:
	var battle: Gen2Battle = _battle()
	var user: Gen2BattleMon = battle.player
	user.hp = (user.max_hp() >> 2) + 1
	_run_move(battle, Fixture.SUBSTITUTE)

	assert_eq(user.hp, 1)
	assert_true(Gen2Substatus.has(user.substatus, Gen2Substatus.SUBSTITUTE))


## The doll steps out of whatever was binding the Pokémon behind it. Its own
## side only: nothing here frees the opponent.
func test_making_a_substitute_frees_its_user_from_a_bind() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.trapped_turns = 4
	battle.player.trapping_move = Fixture.WRAP
	battle.enemy.trapped_turns = 3

	_run_move(battle, Fixture.SUBSTITUTE)
	assert_eq(battle.player.trapped_turns, 0)
	assert_eq(battle.player.trapping_move, 0)
	assert_eq(battle.enemy.trapped_turns, 3, "the other side's bind is not the doll's business")


func test_a_hit_is_spent_on_the_doll_and_not_on_the_pokemon() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	# Big enough that a Tackle cannot break it, so this is about where the damage
	# went rather than about the break.
	battle.enemy.substitute_hp = 250
	var before: int = battle.enemy.hp
	var turn: Gen2Turn = _run_move(battle, Fixture.TACKLE)

	assert_eq(battle.enemy.hp, before, "the real health never moves")
	assert_lt(battle.enemy.substitute_hp, 250)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.SUBSTITUTE))
	assert_eq(_of_type(turn.events, Gen2Battle.SUBSTITUTE_TOOK_DAMAGE).size(), 1)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 0)
	assert_eq(turn.dealt, 0)


func test_a_doll_taken_to_exactly_zero_breaks() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	var turn: Gen2Turn = _turn(battle)
	battle.enemy.substitute_hp = 20
	turn.damage = 20
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)

	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.SUBSTITUTE))
	assert_eq(_of_type(turn.events, Gen2Battle.SUBSTITUTE_FADED).size(), 1)


func test_a_doll_taken_below_zero_breaks_and_one_short_survives() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	var turn: Gen2Turn = _turn(battle)
	battle.enemy.substitute_hp = 20
	turn.damage = 19
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.SUBSTITUTE))
	assert_eq(battle.enemy.substitute_hp, 1)

	var second: Gen2Turn = _turn(battle)
	second.damage = 2
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, second)
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.SUBSTITUTE))


## `ld a, [hli] / and a / jr nz, .broke`: the damage is a word against a one-byte
## counter, so anything from 256 up breaks the doll with no arithmetic at all.
func test_a_hit_of_two_hundred_and_fifty_six_breaks_any_doll() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	battle.enemy.substitute_hp = 255
	var turn: Gen2Turn = _turn(battle)
	turn.damage = 256
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)

	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.SUBSTITUTE))


## `xor a / ld [hl], a` over `wPlayerMoveStruct + MOVE_EFFECT`, so everything
## behind the break reads an ordinary attack.
func test_a_broken_doll_stamps_normal_hit_over_the_moves_effect() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	battle.enemy.substitute_hp = 1
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, Fixture.EMBER_BURNS,
		_data.move(Fixture.EMBER_BURNS), []
	)
	turn.damage = 5
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)

	assert_eq(turn.effect(), Gen2MoveEffect.NORMAL_HIT_EFFECT)


## The five the source exempts, because each one's own command reads the byte
## back to know how many hits it is partway through.
func test_a_broken_doll_leaves_a_multi_hit_effect_alone() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	battle.enemy.substitute_hp = 1
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, Fixture.DOUBLE_HIT_MOVE,
		_data.move(Fixture.DOUBLE_HIT_MOVE), []
	)
	turn.damage = 5
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)

	assert_eq(turn.effect(), Gen2MoveEffect.DOUBLE_HIT)


## `.update_damage_taken` returns before it records anything when the target has
## a doll, which is what stops Counter answering a hit the doll took.
func test_counter_cannot_answer_a_hit_a_doll_took() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	_run_move(battle, Fixture.TACKLE)

	assert_true(battle.last_damage_taken(Gen2Battle.ENEMY).is_empty())


## `.DrainSub`, which is the one place a Substitute reads as a miss rather than
## as a hit that did nothing.
func test_a_drain_move_reads_as_a_miss_against_a_doll() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	var doll: int = battle.enemy.substitute_hp
	var turn: Gen2Turn = _run_move(battle, Fixture.DRAIN_MOVE)

	assert_true(turn.missed)
	assert_eq(battle.enemy.substitute_hp, doll, "not even the doll is touched")
	assert_eq(_of_type(turn.events, Gen2Battle.DRAINED).size(), 0)


func test_an_ordinary_attack_still_reaches_a_doll() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	var turn: Gen2Turn = _run_move(battle, Fixture.TACKLE)
	assert_false(turn.missed, "only the two draining effects read as a miss")


## `BattleCommand_EffectChance` jumps to `.failed` before `BattleRandom`, so a
## secondary effect aimed at a doll costs no randomness at all.
func test_a_secondary_effect_against_a_doll_draws_no_roll() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	var turn: Gen2Turn = _turn(battle, Fixture.EMBER_BURNS)
	var before: int = _rng.state
	Gen2EffectCommands.run(Gen2EffectCommands.EFFECT_CHANCE, turn)

	assert_true(turn.failed_chance)
	assert_eq(_rng.state, before, "the roll was never drawn")


func test_a_doll_refuses_a_status_a_flinch_a_confusion_and_a_bind() -> void:
	for pair: Array in [
		[Fixture.EMBER_BURNS, Gen2EffectCommands.BURN_TARGET],
		[Fixture.ROLLING_KICK_ALWAYS, Gen2EffectCommands.FLINCH_TARGET],
		[Fixture.CONFUSION_ALWAYS, Gen2EffectCommands.CONFUSE_TARGET],
		[Fixture.WRAP, Gen2EffectCommands.TRAP_TARGET],
	]:
		var battle: Gen2Battle = _battle()
		_raise_enemy_substitute(battle)
		var turn: Gen2Turn = _turn(battle, int(pair[0]))
		var before: int = _rng.state
		Gen2EffectCommands.run(StringName(pair[1]), turn)

		assert_eq(battle.enemy.status, Gen2Status.NONE, "move %d" % int(pair[0]))
		assert_eq(battle.enemy.substatus & ~Gen2Substatus.SUBSTITUTE, Gen2Substatus.NONE)
		assert_eq(battle.enemy.trapped_turns, 0)
		assert_eq(_rng.state, before, "and none of the four rolled")


## `BattleCommand_BurnTarget`'s `CheckSubstituteOpp` is in front of the status
## check, so a doll stops even the thaw a burn move would otherwise have given.
func test_a_doll_stops_a_burn_move_thawing_the_pokemon_behind_it() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	battle.enemy.status = Gen2Status.FREEZE
	var turn: Gen2Turn = _turn(battle, Fixture.EMBER_BURNS)
	Gen2EffectCommands.run(Gen2EffectCommands.BURN_TARGET, turn)

	assert_true(Gen2Status.has(battle.enemy.status, Gen2Status.FREEZE))


## `BattleCommand_StatDown`'s `.DidntMiss`, and `BattleCommand_HeldFlinch`'s
## check between the item and the roll.
func test_a_doll_refuses_a_stat_drop_and_a_kings_rock() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	var turn: Gen2Turn = _turn(battle, Fixture.SCREECH)
	Gen2EffectCommands.run(Gen2EffectCommands.DEFENSE_DOWN_2, turn)
	assert_eq(battle.enemy.stage("defense"), 0)
	assert_false(turn.stat_moved)

	battle.player.item = Fixture.KINGS_ROCK
	var rock: Gen2Turn = _turn(battle)
	var before: int = _rng.state
	Gen2EffectCommands.run(Gen2EffectCommands.KINGS_ROCK, rock)
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.FLINCHED))
	assert_eq(_rng.state, before)


## The Focus Band is in front of the doll rather than behind it, so it rolls, it
## clamps against the *real* health, and the clamped figure is what the doll
## spends. "Hung on" is printed over a Pokémon that was never in danger.
func test_a_focus_band_still_fires_in_front_of_a_doll() -> void:
	var fired: int = 0
	for seed: int in 200:
		var battle: Gen2Battle = _battle()
		battle.rng.seed = seed
		_raise_enemy_substitute(battle)
		battle.enemy.substitute_hp = 200
		battle.enemy.item = Fixture.FOCUS_BAND
		battle.enemy.hp = 10
		var turn: Gen2Turn = _turn(battle)
		turn.damage = 300
		Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)

		if _of_type(turn.events, Gen2Battle.ENDURED).is_empty():
			# No band, so the word is over a byte and the doll goes outright.
			assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.SUBSTITUTE))
			continue

		fired += 1
		assert_eq(battle.enemy.hp, 10, "the real health never moved")
		assert_eq(
			battle.enemy.substitute_hp, 200 - 9,
			"the clamp is against the real health and the doll pays the clamped figure"
		)

	assert_between(fired, 5, 50, "roughly thirty in 256")


## Leech Seed is the one of the five that carries `checkhit`, so every test of
## what it does behind the roll overrides its real 90% up to the 255 that skips
## the roll entirely.
const ALWAYS: Dictionary = {"accuracy": 255}


func test_a_seed_lands_and_a_grass_type_shrugs_it_off() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.LEECH_SEED, false, ALWAYS)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.LEECH_SEED))
	assert_eq(_of_type(turn.events, Gen2Battle.WAS_SEEDED).size(), 1)

	var grass: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.LEECH_SEED]),
		Gen2BattleMon.create(_data, Fixture.BULBASAUR, 50, [Fixture.TACKLE]),
		_rng
	)
	var refused: Gen2Turn = _run_move(grass, Fixture.LEECH_SEED, false, ALWAYS)
	assert_false(Gen2Substatus.has(grass.enemy.substatus, Gen2Substatus.LEECH_SEED))
	assert_eq(_of_type(refused.events, Gen2Battle.NO_EFFECT).size(), 1)


func test_a_second_seed_and_a_seed_at_a_doll_both_evade() -> void:
	var battle: Gen2Battle = _battle()
	_run_move(battle, Fixture.LEECH_SEED, false, ALWAYS)
	var again: Gen2Turn = _run_move(battle, Fixture.LEECH_SEED, false, ALWAYS)
	assert_eq(_of_type(again.events, Gen2Battle.EVADED).size(), 1)

	var walled: Gen2Battle = _battle()
	_raise_enemy_substitute(walled)
	var turn: Gen2Turn = _run_move(walled, Fixture.LEECH_SEED, false, ALWAYS)
	assert_false(Gen2Substatus.has(walled.enemy.substatus, Gen2Substatus.LEECH_SEED))
	assert_eq(_of_type(turn.events, Gen2Battle.EVADED).size(), 1)


func test_a_nightmare_needs_a_sleeping_target_and_lands_once() -> void:
	var battle: Gen2Battle = _battle()
	var awake: Gen2Turn = _run_move(battle, Fixture.NIGHTMARE)
	assert_eq(_of_type(awake.events, Gen2Battle.MOVE_FAILED).size(), 1)

	battle.enemy.status = Gen2Status.roll_sleep(_rng)
	var landed: Gen2Turn = _run_move(battle, Fixture.NIGHTMARE)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.NIGHTMARE))
	assert_eq(_of_type(landed.events, Gen2Battle.NIGHTMARE_STARTED).size(), 1)

	var again: Gen2Turn = _run_move(battle, Fixture.NIGHTMARE)
	assert_eq(_of_type(again.events, Gen2Battle.MOVE_FAILED).size(), 1)


func test_a_nightmare_is_refused_by_a_doll_and_by_a_target_out_of_sight() -> void:
	var walled: Gen2Battle = _battle()
	_raise_enemy_substitute(walled)
	walled.enemy.status = Gen2Status.roll_sleep(_rng)
	_run_move(walled, Fixture.NIGHTMARE)
	assert_false(Gen2Substatus.has(walled.enemy.substatus, Gen2Substatus.NIGHTMARE))

	var flying: Gen2Battle = _battle()
	flying.enemy.status = Gen2Status.roll_sleep(_rng)
	flying.enemy.substatus |= Gen2Substatus.FLYING
	_run_move(flying, Fixture.NIGHTMARE)
	assert_false(Gen2Substatus.has(flying.enemy.substatus, Gen2Substatus.NIGHTMARE))


## The non-Ghost branch, which reads the *user's* own types and moves the user's
## own three stages.
func test_curse_trades_the_users_speed_for_its_attack_and_defense() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.CURSE)

	assert_eq(battle.player.stage("speed"), -1)
	assert_eq(battle.player.stage("attack"), 1)
	assert_eq(battle.player.stage("defense"), 1)
	assert_eq(battle.enemy.stage("speed"), 0, "the user's stages, never the target's")
	assert_eq(_of_type(turn.events, Gen2Battle.STAT_CHANGED).size(), 3)


## `.cantraise` needs *both* to be at the top, and names `StatNames`' eighth row
## rather than either stat it looked at.
func test_curse_fails_only_when_attack_and_defense_are_both_at_the_top() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.change_stage("attack", 6)
	var one: Gen2Turn = _run_move(battle, Fixture.CURSE)
	assert_eq(battle.player.stage("defense"), 1, "Defense could still rise")
	assert_eq(_of_type(one.events, Gen2Battle.STAT_CHANGE_FAILED).size(), 0)

	battle.player.change_stage("defense", 6)
	var both: Gen2Turn = _run_move(battle, Fixture.CURSE)
	var failed: Dictionary = _first(both.events, Gen2Battle.STAT_CHANGE_FAILED)
	assert_eq(String(failed["stat"]), Gen2EffectCommands.CURSE_FAILED_STAT)
	assert_eq(int(failed["by"]), 1, "so the line reads 'won't rise anymore'")


## A Speed already at the floor says nothing and swallows nothing: `ResetMiss`
## between the three is what keeps the two raises coming.
func test_curse_still_raises_when_the_speed_cannot_fall() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.change_stage("speed", -6)
	var turn: Gen2Turn = _run_move(battle, Fixture.CURSE)

	assert_eq(battle.player.stage("attack"), 1)
	assert_eq(battle.player.stage("defense"), 1)
	assert_eq(_of_type(turn.events, Gen2Battle.STAT_CHANGED).size(), 2)


func test_a_ghost_curse_cuts_half_its_own_health_and_lands_a_curse() -> void:
	var battle: Gen2Battle = _ghost_battle()
	var user: Gen2BattleMon = battle.player
	var full: int = user.max_hp()
	var turn: Gen2Turn = _run_move(battle, Fixture.CURSE)

	assert_eq(user.hp, full - Gen2Substatus.half_damage(full))
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.CURSE))
	assert_eq(int(_first(turn.events, Gen2Battle.CURSE_SET)["target"]), Gen2Battle.ENEMY)
	assert_eq(battle.player.stage("attack"), 0, "the other branch never ran")


## `GetHalfMaxHP` and `SubtractHPFromUser` with nothing between them: a Ghost on
## less than half its maximum goes down to its own move.
func test_a_ghost_curse_can_faint_its_own_user() -> void:
	var battle: Gen2Battle = _ghost_battle()
	battle.player.hp = 3
	var turn: Gen2Turn = _run_move(battle, Fixture.CURSE)

	assert_true(battle.player.is_fainted())
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.CURSE))
	assert_eq(int(_first(turn.events, Gen2Battle.FAINTED)["side"]), Gen2Battle.PLAYER)


func test_a_ghost_curse_is_refused_twice_and_by_a_doll() -> void:
	var battle: Gen2Battle = _ghost_battle()
	_run_move(battle, Fixture.CURSE)
	var before: int = battle.player.hp
	var again: Gen2Turn = _run_move(battle, Fixture.CURSE)
	assert_eq(battle.player.hp, before, "and it costs nothing to fail")
	assert_eq(_of_type(again.events, Gen2Battle.MOVE_FAILED).size(), 1)

	var walled: Gen2Battle = _ghost_battle()
	_raise_enemy_substitute(walled)
	_run_move(walled, Fixture.CURSE)
	assert_false(Gen2Substatus.has(walled.enemy.substatus, Gen2Substatus.CURSE))


func test_spikes_land_on_the_far_side_and_refuse_a_second_time() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.SPIKES)

	assert_true(Gen2Screens.has(battle.screens[Gen2Battle.ENEMY], Gen2Screens.SPIKES))
	assert_false(Gen2Screens.has(battle.screens[Gen2Battle.PLAYER], Gen2Screens.SPIKES))
	assert_eq(int(_first(turn.events, Gen2Battle.SPIKES_SET)["target"]), Gen2Battle.ENEMY)

	var again: Gen2Turn = _run_move(battle, Fixture.SPIKES)
	assert_eq(_of_type(again.events, Gen2Battle.MOVE_FAILED).size(), 1)


## All three of `BattleCommand_ClearHazards`, in its own order, and all three on
## the user's own side.
func test_rapid_spin_sheds_the_seed_the_spikes_and_the_bind() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.LEECH_SEED
	battle.screens[Gen2Battle.PLAYER] |= Gen2Screens.SPIKES
	battle.screens[Gen2Battle.ENEMY] |= Gen2Screens.SPIKES
	battle.player.trapped_turns = 3
	battle.player.trapping_move = Fixture.WRAP

	var turn: Gen2Turn = _run_move(battle, Fixture.RAPID_SPIN)
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.LEECH_SEED))
	assert_false(Gen2Screens.has(battle.screens[Gen2Battle.PLAYER], Gen2Screens.SPIKES))
	assert_true(
		Gen2Screens.has(battle.screens[Gen2Battle.ENEMY], Gen2Screens.SPIKES),
		"the other side's spikes are not the spinner's business"
	)
	assert_eq(battle.player.trapped_turns, 0)
	assert_eq(
		battle.player.trapping_move, Fixture.WRAP,
		"`clearhazards` zeroes the counter and leaves the move byte alone"
	)

	var types: Array = turn.events.map(func(event: Dictionary) -> StringName: return event["type"])
	assert_true(types.find(Gen2Battle.SHED_LEECH_SEED) < types.find(Gen2Battle.BLEW_SPIKES))
	assert_true(types.find(Gen2Battle.BLEW_SPIKES) < types.find(Gen2Battle.RELEASED_BY))


## `clearhazards` sits in front of `checkfaint`, so a spin that knocks its target
## out still clears the spinner's own side.
func test_rapid_spin_clears_even_when_the_hit_was_lethal() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.LEECH_SEED
	battle.enemy.hp = 1

	var turn: Gen2Turn = _run_move(battle, Fixture.RAPID_SPIN)
	assert_true(battle.enemy.is_fainted())
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.LEECH_SEED))
	assert_eq(_of_type(turn.events, Gen2Battle.SHED_LEECH_SEED).size(), 1)


## `DefenseDownHit` is the one row of the seven that rolls twice, which is what
## lets its drop land on a Pokémon whose doll the same hit broke.
func test_only_the_defense_drop_on_hit_carries_two_rolls() -> void:
	for offset: int in Gen2MoveEffect.STAT_RUN_LENGTH:
		var effect: int = Gen2MoveEffect.STAT_DOWN_HIT_BASE + offset
		var rolls: int = Gen2MoveEffect.sequence_for(effect).count(
			Gen2EffectCommands.EFFECT_CHANCE
		)
		assert_eq(rolls, 2 if effect == Gen2MoveEffect.DEFENSE_DOWN_HIT else 1,
			"effect %d" % effect)


## And the second roll is what clears the first one's failure, since
## `BattleCommand_EffectChance` opens by zeroing `wEffectFailed`.
func test_a_second_effect_chance_clears_the_first_ones_failure() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _turn(battle, Fixture.NEVER_BURNS)
	Gen2EffectCommands.run(Gen2EffectCommands.EFFECT_CHANCE, turn)
	assert_true(turn.failed_chance)

	turn.move = _data.move(Fixture.EMBER_BURNS)
	Gen2EffectCommands.run(Gen2EffectCommands.EFFECT_CHANCE, turn)
	assert_false(turn.failed_chance)


## `BattleCommand_StatDown`'s order: Mist and the stage that cannot move are both
## settled before `wEffectFailed` is read, so each keeps its own line.
func test_a_stat_drop_names_its_own_reason_even_when_the_roll_failed() -> void:
	var misted: Gen2Battle = _battle()
	misted.enemy.substatus |= Gen2Substatus.MIST
	var turn: Gen2Turn = _turn(misted, Fixture.PSYCHIC_NEVER)
	turn.failed_chance = true
	Gen2EffectCommands.run(Gen2EffectCommands.SP_DEFENSE_DOWN, turn)
	assert_true(turn.stat_mist_blocked)

	var floored: Gen2Battle = _battle()
	floored.enemy.change_stage("sp_defense", -6)
	var bottom: Gen2Turn = _turn(floored, Fixture.PSYCHIC_NEVER)
	bottom.failed_chance = true
	Gen2EffectCommands.run(Gen2EffectCommands.SP_DEFENSE_DOWN, bottom)
	assert_false(bottom.stat_mist_blocked)
	assert_false(bottom.stat_moved)


## `applydamage` is inside `MultiHit`'s own loop, so every hit is spent on the
## doll and the doll can break partway through a move.
func test_a_multi_hit_spends_every_hit_on_the_doll() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	battle.enemy.substitute_hp = 250
	var before: int = battle.enemy.hp
	var turn: Gen2Turn = _run_move(battle, Fixture.DOUBLE_HIT_MOVE)

	assert_eq(battle.enemy.hp, before, "the real health never moves")
	assert_eq(_of_type(turn.events, Gen2Battle.SUBSTITUTE_TOOK_DAMAGE).size(), 2)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 0)


## And a doll broken by the first hit lets the second through to the Pokémon,
## which is only true because the effect byte survived the break.
func test_a_doll_broken_by_the_first_hit_lets_the_second_through() -> void:
	var battle: Gen2Battle = _battle()
	_raise_enemy_substitute(battle)
	battle.enemy.substitute_hp = 1
	var before: int = battle.enemy.hp
	var turn: Gen2Turn = _run_move(battle, Fixture.DOUBLE_HIT_MOVE)

	assert_eq(_of_type(turn.events, Gen2Battle.SUBSTITUTE_FADED).size(), 1)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 1, "the second hit lands")
	assert_lt(battle.enemy.hp, before)
	assert_eq(turn.effect(), Gen2MoveEffect.DOUBLE_HIT, "and the loop kept its own byte")


## Protect, Detect, Endure and Destiny Bond.
##
## The first three are `ProtectChance` under two flags and one counter; the
## fourth rolls nothing at all. `_run_move` leaves
## [member Gen2Battle.enemy_goes_first] false, so the player is first and the
## went-first gate passes unless a test says otherwise.
func test_protect_and_detect_share_one_effect_and_one_count() -> void:
	assert_eq(
		int(_data.move(Fixture.DETECT).get("effect", -1)),
		int(_data.move(Fixture.PROTECT).get("effect", -1)),
		"one effect byte under two move numbers"
	)

	var battle: Gen2Battle = _battle()
	_run_move(battle, Fixture.PROTECT)
	assert_eq(battle.player.protect_count, 1)
	_run_move(battle, Fixture.DETECT)
	assert_eq(battle.player.protect_count, 2, "Detect counts against Protect's own ladder")


## A count of zero cannot fail: `ld b, $ff` against a draw of 1..255 leaves no
## value that loses.
func test_the_first_protect_of_a_chain_always_lands() -> void:
	for seed_value: int in range(0, 40):
		var battle: Gen2Battle = _battle()
		battle.rng.seed = seed_value
		var turn: Gen2Turn = _run_move(battle, Fixture.PROTECT)
		assert_true(
			Gen2Substatus.has(battle.player.substatus, Gen2Substatus.PROTECT),
			"seed %d" % seed_value
		)
		assert_eq(_of_type(turn.events, Gen2Battle.PROTECTED_ITSELF).size(), 1)
		assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 0)


## The ladder halves once per consecutive use and runs out at eight, which is the
## one count that cannot roll at all.
##
## `srl b` from $ff gives 127, 63, 31, 15, 7, 3, 1 and then nothing, and the draw
## it is compared against is 1..255, so the share that lands is the ceiling over
## 255. The four counts checked against a figure are the four whose ceiling is
## large enough for the sample to say anything.
const PROTECT_LADDER_SAMPLES: int = 510
const PROTECT_LADDER_CEILINGS: Array[int] = [255, 127, 63, 31, 15, 7, 3, 1, 0]


func test_the_protect_ladder_halves_and_runs_out_at_eight() -> void:
	var battle: Gen2Battle = _battle()
	var landed: Array[int] = []
	for count: int in PROTECT_LADDER_CEILINGS.size():
		var hits: int = 0
		for seed_value: int in PROTECT_LADDER_SAMPLES:
			battle.rng.seed = seed_value
			battle.player.protect_count = count
			battle.player.substatus &= ~Gen2Substatus.PROTECT
			_run_move(battle, Fixture.PROTECT)
			if Gen2Substatus.has(battle.player.substatus, Gen2Substatus.PROTECT):
				hits += 1
		landed.append(hits)

	assert_eq(landed[0], PROTECT_LADDER_SAMPLES, "a ceiling of 255 against a draw of 1..255")
	assert_eq(landed[8], 0, "the eighth shift empties the ceiling before any roll")
	for count: int in range(1, landed.size()):
		assert_lte(landed[count], landed[count - 1], "count %d is no likelier than %d" % [
			count, count - 1,
		])
	for count: int in range(1, 5):
		var expected: int = PROTECT_LADDER_SAMPLES * PROTECT_LADDER_CEILINGS[count] / 255
		assert_almost_eq(
			landed[count], expected, expected / 5,
			"count %d lands about %d times in %d" % [count, expected, PROTECT_LADDER_SAMPLES]
		)


## And the count that cannot land draws nothing: `.failed` is reached before
## `.rand`, so a chain that has run out spends no randomness.
func test_a_protect_that_has_run_out_draws_no_randomness() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.protect_count = 8
	var before: int = battle.rng.state
	_run_move(battle, Fixture.PROTECT)
	assert_eq(battle.rng.state, before)


## A failure puts the count back to nothing, so the Protect after a failed one is
## a first Protect again.
func test_a_failed_protect_empties_its_own_count() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.protect_count = 8
	var turn: Gen2Turn = _run_move(battle, Fixture.PROTECT)

	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.PROTECT))
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)
	assert_eq(battle.player.protect_count, 0)


## `CheckOpponentWentFirst`: going second fails outright, in front of the ladder.
func test_protect_fails_outright_for_a_side_that_moved_second() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy_goes_first = true
	var turn: Gen2Turn = _run_move(battle, Fixture.PROTECT)

	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.PROTECT))
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


## And the Substitute it refuses is the user's own, not the target's.
func test_protect_refuses_a_user_behind_its_own_doll() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.substatus |= Gen2Substatus.SUBSTITUTE
	battle.player.substitute_hp = 20
	assert_false(
		Gen2Substatus.has(_run_move(battle, Fixture.PROTECT).battle.player.substatus,
		Gen2Substatus.PROTECT)
	)

	var opposite: Gen2Battle = _battle()
	opposite.enemy.substatus |= Gen2Substatus.SUBSTITUTE
	opposite.enemy.substitute_hp = 20
	_run_move(opposite, Fixture.PROTECT)
	assert_true(
		Gen2Substatus.has(opposite.player.substatus, Gen2Substatus.PROTECT),
		"a doll on the other side is not asked about"
	)


## `BattleCommand_CheckHit`'s `.Protect` is one gate for every list that carries
## `checkhit`, which is why a status move and a stat drop are turned away as
## surely as an attack.
##
## Thunder Wave is run against the Charmander rather than the default Geodude:
## `checkimmune` stands in for `failuretext` here and sits in front of
## `checkhit`, so a Ground-type would end the move before the gate is reached.
## That ordering is the standing divergence rather than anything about Protect.
func test_a_protect_turns_away_an_attack_a_status_move_and_a_stat_drop() -> void:
	for move_number: int in [Fixture.TACKLE, Fixture.THUNDER_WAVE, Fixture.GROWL]:
		var battle: Gen2Battle = _electric_battle()
		battle.enemy.substatus |= Gen2Substatus.PROTECT
		var before: int = battle.enemy.hp
		var turn: Gen2Turn = _run_move(battle, move_number)

		assert_eq(
			_of_type(turn.events, Gen2Battle.PROTECTING_ITSELF).size(), 1,
			"move %d says so" % move_number
		)
		assert_eq(_of_type(turn.events, Gen2Battle.MISSED).size(), 1)
		assert_eq(battle.enemy.hp, before)
		assert_eq(battle.enemy.status, Gen2Status.NONE)
		assert_eq(battle.enemy.stage("attack"), 0)


## The refusal is printed before the miss, since `.Protect` prints inside
## `CheckHit` and `failuretext` comes later.
func test_the_protect_line_comes_before_the_miss() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.PROTECT
	var types: Array = []
	for event: Dictionary in _run_move(battle, Fixture.TACKLE).events:
		types.append(StringName(event["type"]))

	assert_lt(
		types.find(Gen2Battle.PROTECTING_ITSELF), types.find(Gen2Battle.MISSED),
		"protecting itself, then the attack missed"
	)


func test_endure_sets_its_own_flag_off_the_shared_count() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.ENDURE)

	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ENDURE))
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.PROTECT))
	assert_eq(_of_type(turn.events, Gen2Battle.BRACED_ITSELF).size(), 1)
	assert_eq(battle.player.protect_count, 1)

	_run_move(battle, Fixture.PROTECT)
	assert_eq(battle.player.protect_count, 2, "one ladder for all three moves")


func test_endure_leaves_its_holder_on_one_hit_point() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.ENDURE
	battle.enemy.hp = 12
	var turn: Gen2Turn = _turn(battle)
	turn.damage = 400
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)

	assert_eq(battle.enemy.hp, 1)
	assert_eq(_of_type(turn.events, Gen2Battle.ENDURED_HIT).size(), 1)
	assert_eq(
		_of_type(turn.events, Gen2Battle.ENDURED).size(), 0,
		"the Focus Band's own line is a different text and did not fire"
	)


## `FalseSwipe` reports whether it clamped, so a hit that was never lethal says
## nothing at all.
func test_a_survivable_hit_against_an_enduring_target_says_nothing() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.ENDURE
	battle.enemy.hp = 100
	var turn: Gen2Turn = _turn(battle)
	turn.damage = 10
	Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)

	assert_eq(battle.enemy.hp, 90)
	assert_eq(_of_type(turn.events, Gen2Battle.ENDURED_HIT).size(), 0)


## Nothing spends the flag, so a multi-hit move is clamped on every hit rather
## than only the first.
func test_endure_clamps_every_hit_of_a_multi_hit_move() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.ENDURE
	battle.enemy.hp = 1
	var turn: Gen2Turn = _run_move(battle, Fixture.DOUBLE_HIT_MOVE)

	assert_eq(battle.enemy.hp, 1, "still standing after both")
	assert_eq(_of_type(turn.events, Gen2Battle.ENDURED_HIT).size(), 2)


## `jr z, .focus_band`: an enduring target never reaches the band, so it draws no
## randomness there. Counting the draws is the only way to see that.
func test_an_enduring_target_never_rolls_its_focus_band() -> void:
	var drawn: Dictionary = {}
	for enduring: bool in [false, true]:
		var battle: Gen2Battle = _battle()
		battle.rng.seed = 99
		battle.enemy.item = Fixture.FOCUS_BAND
		battle.enemy.hp = 40
		if enduring:
			battle.enemy.substatus |= Gen2Substatus.ENDURE
		var turn: Gen2Turn = _turn(battle)
		turn.damage = 5
		Gen2EffectCommands.run(Gen2EffectCommands.APPLY_DAMAGE, turn)
		drawn[enduring] = battle.rng.state

	assert_ne(
		int(drawn[false]), int(drawn[true]),
		"the band's roll is drawn only when Endure did not answer first"
	)


func test_destiny_bond_goes_up_with_no_roll_and_never_fails() -> void:
	var battle: Gen2Battle = _battle()
	for _use: int in 3:
		var turn: Gen2Turn = _run_move(battle, Fixture.DESTINY_BOND)
		assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.DESTINY_BOND))
		assert_eq(_of_type(turn.events, Gen2Battle.DESTINY_BOND_SET).size(), 1)
		assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 0)
	assert_eq(battle.player.protect_count, 0, "it is not on Protect's ladder")


## `BattleCommand_CheckFaint` reads the *target's* flag, and empties the
## attacker's health outright rather than damaging it.
func test_destiny_bond_takes_the_attacker_down_with_its_holder() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.DESTINY_BOND
	battle.enemy.hp = 1
	var turn: Gen2Turn = _run_move(battle, Fixture.TACKLE)

	assert_true(battle.enemy.is_fainted())
	assert_true(battle.player.is_fainted(), "the attacker goes with it")

	var types: Array = []
	for event: Dictionary in turn.events:
		types.append(StringName(event["type"]))
	assert_eq(_of_type(turn.events, Gen2Battle.TOOK_DOWN_WITH_IT).size(), 1)
	assert_lt(
		types.find(Gen2Battle.TOOK_DOWN_WITH_IT), types.find(Gen2Battle.FAINTED),
		"the line comes before either faint"
	)
	var faints: Array = _of_type(turn.events, Gen2Battle.FAINTED)
	assert_eq(faints.size(), 2)
	assert_eq(int(faints[0]["side"]), Gen2Battle.ENEMY, "the holder is reported first")
	assert_eq(int(faints[1]["side"]), Gen2Battle.PLAYER)


func test_a_destiny_bond_holder_that_survives_takes_nobody_with_it() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.DESTINY_BOND
	var turn: Gen2Turn = _run_move(battle, Fixture.TACKLE)

	assert_false(battle.enemy.is_fainted())
	assert_false(battle.player.is_fainted())
	assert_eq(_of_type(turn.events, Gen2Battle.TOOK_DOWN_WITH_IT).size(), 0)


## Selfdestruct clears the *target's* bond before its damage lands
## (`BATTLE_VARS_SUBSTATUS5_OPP`), which is what stops an explosion being
## answered by one.
func test_selfdestruct_clears_the_targets_destiny_bond_before_it_lands() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.DESTINY_BOND
	battle.enemy.hp = 1
	var turn: Gen2Turn = _run_move(battle, Fixture.SELFDESTRUCT)

	assert_true(battle.enemy.is_fainted())
	assert_eq(
		_of_type(turn.events, Gen2Battle.TOOK_DOWN_WITH_IT).size(), 0,
		"the bond was cleared, so nothing collected"
	)


## Whirlwind and Roar: one effect byte, two endings.
##
## `_run_move` leaves [member Gen2Battle.enemy_goes_first] false, which is the
## player having moved first, and the trainer half refuses that outright. Every
## trainer case below therefore sets it, which is what priority 0 does in a real
## turn anyway.
func _trainer_battle(player: Array, enemy: Array) -> Gen2Battle:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.create(player), Gen2Party.create(enemy), _rng, true
	)
	battle.enemy_goes_first = true
	return battle


func _party_of(species: Array) -> Array:
	var out: Array = []
	for number: int in species:
		out.append(Gen2BattleMon.create(_data, number, 50, [Fixture.TACKLE]))
	return out


func test_a_force_switch_drags_out_a_standing_party_member() -> void:
	var battle: Gen2Battle = _trainer_battle(
		_party_of([Fixture.PIKACHU]),
		_party_of([Fixture.GEODUDE, Fixture.CHARMANDER])
	)
	var turn: Gen2Turn = _run_move(battle, Fixture.WHIRLWIND)

	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1, "the other member is out")
	assert_eq(_of_type(turn.events, Gen2Battle.DRAGGED_OUT).size(), 1)
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 0)


## `DraggedOutText` is printed once the replacement is out and before it walks
## into anything, so the three events are in that order.
func test_the_dragged_out_line_sits_between_the_entrance_and_the_spikes() -> void:
	var battle: Gen2Battle = _trainer_battle(
		_party_of([Fixture.PIKACHU]),
		_party_of([Fixture.GEODUDE, Fixture.CHARMANDER])
	)
	battle.screens[Gen2Battle.ENEMY] |= Gen2Screens.SPIKES
	var types: Array = []
	for event: Dictionary in _run_move(battle, Fixture.WHIRLWIND).events:
		types.append(StringName(event["type"]))

	assert_lt(types.find(Gen2Battle.SENT_OUT), types.find(Gen2Battle.DRAGGED_OUT))
	assert_lt(types.find(Gen2Battle.DRAGGED_OUT), types.find(Gen2Battle.HURT_BY_SPIKES))


## `FindAliveEnemyMons` and `CheckPlayerHasMonToSwitchTo`: a lone Pokemon, or a
## bench that is all down, has nothing to drag out.
func test_a_force_switch_fails_with_nobody_left_to_drag_out() -> void:
	var lone: Gen2Battle = _trainer_battle(
		_party_of([Fixture.PIKACHU]), _party_of([Fixture.GEODUDE])
	)
	assert_eq(_of_type(_run_move(lone, Fixture.WHIRLWIND).events,
		Gen2Battle.MOVE_FAILED).size(), 1, "a lone Pokemon")

	var downed: Gen2Battle = _trainer_battle(
		_party_of([Fixture.PIKACHU]),
		_party_of([Fixture.GEODUDE, Fixture.CHARMANDER])
	)
	var bench: Gen2BattleMon = downed.party(Gen2Battle.ENEMY).at(1)
	bench.take_damage(bench.max_hp())
	assert_eq(_of_type(_run_move(downed, Fixture.WHIRLWIND).events,
		Gen2Battle.MOVE_FAILED).size(), 1, "a bench that is all down")


## The went-first gate: both halves of the source refuse unless the opponent
## moved first, so a force switch that somehow moved first does nothing.
func test_a_force_switch_that_moved_first_does_nothing() -> void:
	var battle: Gen2Battle = _trainer_battle(
		_party_of([Fixture.PIKACHU]),
		_party_of([Fixture.GEODUDE, Fixture.CHARMANDER])
	)
	battle.enemy_goes_first = false
	var turn: Gen2Turn = _run_move(battle, Fixture.WHIRLWIND)

	assert_eq(battle.party(Gen2Battle.ENEMY).active, 0, "nobody moved")
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


## Only the target's side is dragged out, and only ever to somebody standing.
func test_a_force_switch_only_ever_picks_a_standing_member_of_the_targets_party() -> void:
	for seed_value: int in 60:
		var battle: Gen2Battle = _trainer_battle(
			_party_of([Fixture.PIKACHU, Fixture.CHARMANDER]),
			_party_of([Fixture.GEODUDE, Fixture.CHARMANDER, Fixture.BULBASAUR])
		)
		battle.rng.seed = seed_value
		var fainted: Gen2BattleMon = battle.party(Gen2Battle.ENEMY).at(1)
		fainted.take_damage(fainted.max_hp())
		_run_move(battle, Fixture.ROAR)

		assert_eq(battle.party(Gen2Battle.ENEMY).active, 2, "the only one standing")
		assert_eq(battle.party(Gen2Battle.PLAYER).active, 0, "the user's side never moves")


## Against a wild the battle ends instead, with nobody beaten. A user at or above
## the target's level always succeeds, so this needs no seed.
func test_a_force_switch_ends_a_wild_battle_as_a_draw() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.WHIRLWIND)

	assert_true(battle.is_over())
	assert_true(battle.was_forced_out())
	assert_eq(battle.forced_out_side(), Gen2Battle.ENEMY)
	assert_null(battle.winner(), "SetBattleDraw: nobody beat anybody")
	assert_false(battle.player.is_fainted())
	assert_false(battle.enemy.is_fainted())
	assert_eq(_of_type(turn.events, Gen2Battle.BLOWN_AWAY).size(), 1)


## Roar and Whirlwind are the same effect and differ only in that line.
func test_roar_and_whirlwind_print_different_lines() -> void:
	var roared: Gen2Turn = _run_move(_battle(), Fixture.ROAR)
	assert_eq(_of_type(roared.events, Gen2Battle.FLED_IN_FEAR).size(), 1)
	assert_eq(_of_type(roared.events, Gen2Battle.BLOWN_AWAY).size(), 0)

	var blown: Gen2Turn = _run_move(_battle(), Fixture.WHIRLWIND)
	assert_eq(_of_type(blown.events, Gen2Battle.BLOWN_AWAY).size(), 1)
	assert_eq(_of_type(blown.events, Gen2Battle.FLED_IN_FEAR).size(), 0)


## Below the target's level it goes on the dice, and a quarter of the target's
## level is the share that fails. A level 4 user against a level 50 target fails
## whenever the roll lands under 12, out of the 55 it is drawn from.
func test_a_weaker_user_rolls_against_a_quarter_of_the_targets_level() -> void:
	var failures: int = 0
	var samples: int = 200
	for seed_value: int in samples:
		var battle: Gen2Battle = Gen2Battle.create(
			_data,
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 4, [Fixture.TACKLE]),
			Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_rng
		)
		battle.rng.seed = seed_value
		if _of_type(_run_move(battle, Fixture.WHIRLWIND).events,
			Gen2Battle.MOVE_FAILED).size() > 0:
			failures += 1

	var expected: int = samples * 12 / 55
	assert_almost_eq(failures, expected, expected / 3,
		"roughly twelve of the fifty-five values it can draw")


## And the four scripted encounters refuse before any of that is asked.
func test_the_four_scripted_battle_types_refuse_a_force_switch() -> void:
	for battle_type: int in Gen2EffectCommands.FORCE_SWITCH_REFUSED_TYPES:
		var battle: Gen2Battle = _battle()
		battle.battle_type = battle_type
		var turn: Gen2Turn = _run_move(battle, Fixture.WHIRLWIND)

		assert_false(battle.is_over(), "battle type %d" % battle_type)
		assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


## The last row of `data/moves/effects.asm`, which is where the count of unwritten
## effect bytes stood before these landed.
func test_the_last_row_of_the_effects_table_is_written() -> void:
	for effect: int in [
		Gen2MoveEffect.PAIN_SPLIT, Gen2MoveEffect.LOCK_ON, Gen2MoveEffect.SPITE,
		Gen2MoveEffect.THIEF, Gen2MoveEffect.FORESIGHT, Gen2MoveEffect.PURSUIT,
		Gen2MoveEffect.TELEPORT, Gen2MoveEffect.BEAT_UP,
	]:
		assert_true(Gen2MoveEffect.is_written(effect), "effect %d" % effect)
		assert_ne(Gen2MoveEffect.sequence_for(effect), Gen2MoveEffect.NORMAL_HIT,
			"effect %d has a list of its own" % effect)


## Thief inserts two steps into the ordinary list and Pursuit one, each where the
## cartridge puts it.
func test_thief_and_pursuit_are_the_ordinary_list_with_steps_in_it() -> void:
	var thief: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.THIEF)
	assert_eq(thief.size(), Gen2MoveEffect.NORMAL_HIT.size() + 2)
	# The steal is behind the damage and in front of the faint check, so a Pokémon
	# knocked out by Thief still loses its item.
	assert_lt(
		thief.find(Gen2EffectCommands.APPLY_DAMAGE),
		thief.find(Gen2EffectCommands.THIEF)
	)
	assert_lt(
		thief.find(Gen2EffectCommands.THIEF),
		thief.find(Gen2EffectCommands.CHECK_FAINT)
	)

	var pursuit: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.PURSUIT)
	assert_eq(pursuit.size(), Gen2MoveEffect.NORMAL_HIT.size() + 1)
	# Between the spread and the roll, which is the last point the finished figure
	# can still be multiplied.
	assert_lt(
		pursuit.find(Gen2EffectCommands.DAMAGE_VARIATION),
		pursuit.find(Gen2EffectCommands.PURSUIT)
	)
	assert_lt(
		pursuit.find(Gen2EffectCommands.PURSUIT),
		pursuit.find(Gen2EffectCommands.CHECK_HIT)
	)


## Beat Up carries no `damagestats` and no `stab`, which is what makes it hit for
## base stats and never for a matchup.
func test_beat_up_carries_neither_damage_stats_nor_stab() -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(Gen2MoveEffect.BEAT_UP)
	assert_false(sequence.has(Gen2EffectCommands.DAMAGE_STATS))
	assert_false(sequence.has(Gen2EffectCommands.STAB))
	assert_false(sequence.has(Gen2EffectCommands.CHECK_IMMUNE))
	# One accuracy roll for the whole move: `endloop` jumps back to `critical`, so
	# `checkhit` sits outside the loop.
	assert_lt(
		sequence.find(Gen2EffectCommands.CHECK_HIT),
		sequence.find(Gen2EffectCommands.BEAT_UP)
	)


func test_foresight_identifies_the_target_and_refuses_a_second() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.FORESIGHT)

	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.IDENTIFIED),
		"the flag sits on the Pokemon that was identified")
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.IDENTIFIED))
	assert_eq(_of_type(turn.events, Gen2Battle.IDENTIFIED_SET).size(), 1)

	var again: Gen2Turn = _run_move(battle, Fixture.FORESIGHT)
	assert_eq(_of_type(again.events, Gen2Battle.MOVE_FAILED).size(), 1)


## A target out of sight is not identified. Foresight's own `CheckHiddenOpponent`
## is not what refuses it: `checkhit` sits in front of the command and sets
## `wAttackMissed` first, which is the standing `failuretext` divergence, so the
## line is the miss rather than "But it failed!".
func test_foresight_refuses_a_target_that_is_out_of_sight() -> void:
	for flag: int in [Gen2Substatus.FLYING, Gen2Substatus.UNDERGROUND]:
		var battle: Gen2Battle = _battle()
		battle.enemy.substatus |= flag
		var turn: Gen2Turn = _run_move(battle, Fixture.FORESIGHT)

		assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.IDENTIFIED))
		assert_true(turn.missed)
		assert_eq(_of_type(turn.events, Gen2Battle.MISSED).size(), 1)


## `.StatModifiers`' Foresight branch returns before it multiplies anything, and
## only when the evasion stage is at least the accuracy stage: it cannot undo an
## accuracy the attacker raised.
func test_an_identified_target_loses_the_evasion_it_had_raised() -> void:
	var raised: int = Gen2Accuracy.chance(229, 0, 4)
	assert_lt(raised, 229, "a raised evasion cuts a 90% move down")
	assert_eq(Gen2Accuracy.chance(229, 0, 4, true), 229,
		"identified, the stored byte stands")
	# The attacker's own raise survives, since the branch is behind `jr c`.
	assert_eq(
		Gen2Accuracy.chance(100, 4, 0, true), Gen2Accuracy.chance(100, 4, 0),
		"an accuracy above the evasion is multiplied either way"
	)


## `BattleCommand_Stab`'s matchup walk skips the rows past the `-2` marker unless
## the target has been identified, and those two rows are Ghost's immunities.
func test_an_identified_ghost_can_be_hit_by_normal_and_fighting() -> void:
	for attacking: int in [Fixture.NORMAL, Fixture.FIGHTING]:
		assert_eq(_data.type_matchup(attacking, Fixture.GHOST), 0,
			"immune while unidentified")
		assert_eq(
			_data.type_matchup(attacking, Fixture.GHOST, true),
			RomLayout.MATCHUP_EFFECTIVE,
			"identified, the immunity is gone"
		)
	# Nothing else moves: Psychic against Dark is not a Ghost immunity.
	assert_eq(_data.type_matchup(Fixture.PSYCHIC_TYPE, Fixture.DARK, true), 0)


func test_a_tackle_reaches_an_identified_gastly() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		Gen2BattleMon.create(_data, Fixture.GASTLY, 50, [Fixture.TACKLE]),
		_rng
	)
	var blocked: Gen2Turn = _run_move(battle, Fixture.TACKLE)
	assert_true(blocked.immune, "Normal cannot touch a Ghost")

	battle.enemy.substatus |= Gen2Substatus.IDENTIFIED
	var reaches: Gen2Turn = _run_move(battle, Fixture.TACKLE)
	assert_false(reaches.immune)
	assert_gt(reaches.damage, 0)


func test_lock_on_marks_the_target_and_the_next_hit_check_spends_it() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.LOCK_ON)

	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.LOCK_ON),
		"the flag sits on the Pokemon that was aimed at")
	assert_eq(_of_type(turn.events, Gen2Battle.TOOK_AIM).size(), 1)

	# `res SUBSTATUS_LOCK_ON` runs on every hit check, set or not, so one move
	# spends it.
	_run_move(battle, Fixture.TACKLE)
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.LOCK_ON))


## Mind Reader is the same effect byte and the same command.
func test_mind_reader_is_lock_on() -> void:
	assert_eq(
		int(_data.move(Fixture.MIND_READER)["effect"]),
		int(_data.move(Fixture.LOCK_ON)["effect"])
	)
	var battle: Gen2Battle = _battle()
	_run_move(battle, Fixture.MIND_READER)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.LOCK_ON))


func test_lock_on_is_refused_by_a_substitute() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.SUBSTITUTE
	battle.enemy.substitute_hp = 20
	var turn: Gen2Turn = _run_move(battle, Fixture.LOCK_ON)

	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.LOCK_ON))
	assert_eq(_of_type(turn.events, Gen2Battle.NO_EFFECT).size(), 1)


## A locked-on move connects whatever the accuracy says, which is what makes an
## otherwise unwinnable roll certain.
func test_a_locked_on_move_cannot_miss() -> void:
	for seed_value: int in 40:
		var battle: Gen2Battle = _battle()
		battle.rng.seed = seed_value
		battle.enemy.substatus |= Gen2Substatus.LOCK_ON
		# Evasion at the ceiling, which would otherwise cut a 90% move to a third.
		battle.enemy.stages["evasion"] = 6
		var turn: Gen2Turn = _run_move(battle, Fixture.SCREECH)
		assert_false(turn.missed, "seed %d" % seed_value)


## `.LockOn` names three moves that still cannot reach a target above them, and
## `.FlyDigMoves` behind it is what turns them away.
##
## Only two of the three are reachable. `OHKOHit` carries no `checkhit` at all, so
## Fissure never reads the flag and the branch naming it is source no move gets
## to; the test below owns that half.
func test_a_locked_on_flying_target_is_still_missed_by_the_ground_moves() -> void:
	for move: int in [Fixture.EARTHQUAKE, Fixture.MAGNITUDE]:
		var battle: Gen2Battle = _battle()
		battle.enemy.substatus |= Gen2Substatus.LOCK_ON | Gen2Substatus.FLYING
		var turn: Gen2Turn = _run_move(battle, move)
		assert_true(turn.missed, "move %d" % move)

	# The same target is reached by anything else, since the lock-on is read in
	# front of the hidden check.
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.LOCK_ON | Gen2Substatus.FLYING
	assert_false(_run_move(battle, Fixture.TACKLE).missed)


## Fissure's own list has no `checkhit`, so the flag it is named against is
## neither read nor spent by it.
func test_fissure_never_reaches_the_lock_on_read() -> void:
	assert_false(
		Gen2MoveEffect.sequence_for(Gen2MoveEffect.OHKO).has(Gen2EffectCommands.CHECK_HIT),
		"`OHKOHit` rolls its own accuracy instead"
	)
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.LOCK_ON
	_run_move(battle, Fixture.FISSURE)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.LOCK_ON))


## `.Protect` is asked before `.LockOn`, so a Protect turns a locked-on move away
## and the flag is left standing for the move behind it.
func test_a_protect_turns_a_locked_on_move_away_without_spending_the_flag() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.LOCK_ON | Gen2Substatus.PROTECT
	var turn: Gen2Turn = _run_move(battle, Fixture.TACKLE)

	assert_true(turn.missed)
	assert_eq(_of_type(turn.events, Gen2Battle.PROTECTING_ITSELF).size(), 1)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.LOCK_ON),
		"`res` sits behind the Protect branch, so the flag survives it")


func test_spite_takes_two_to_five_pp_off_the_targets_last_move() -> void:
	var seen: Dictionary = {}
	for seed_value: int in 60:
		var battle: Gen2Battle = _battle()
		battle.rng.seed = seed_value
		battle.enemy.last_move_used = Fixture.TACKLE
		var turn: Gen2Turn = _run_move(battle, Fixture.SPITE)

		var event: Dictionary = _first(turn.events, Gen2Battle.PP_REDUCED)
		var amount: int = int(event["amount"])
		assert_between(amount, 2, 5, "seed %d" % seed_value)
		assert_eq(int(event["slot"]), 0)
		assert_eq(int(event["move"]), Fixture.TACKLE)
		assert_eq(battle.enemy.pp_left(0), 35 - amount)
		seen[amount] = true

	assert_eq(seen.size(), 4, "all four of the two-bit roll's values come up")


## `cp b / jr nc` keeps the roll only while the slot has that much: a slot with one
## PP left loses one.
func test_spite_clamps_to_the_pp_that_is_there() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.last_move_used = Fixture.TACKLE
	battle.enemy.pp[0] = 1
	var turn: Gen2Turn = _run_move(battle, Fixture.SPITE)

	assert_eq(battle.enemy.pp_left(0), 0)
	assert_eq(int(_first(turn.events, Gen2Battle.PP_REDUCED)["amount"]), 1)


func test_spite_refuses_a_target_with_nothing_to_drain() -> void:
	# Nothing used yet.
	var fresh: Gen2Battle = _battle()
	assert_eq(_of_type(_run_move(fresh, Fixture.SPITE).events,
		Gen2Battle.NO_EFFECT).size(), 1)

	# Struggle, which is not in any list to drain.
	var struggled: Gen2Battle = _battle()
	struggled.enemy.last_move_used = Gen2Damage.STRUGGLE
	assert_eq(_of_type(_run_move(struggled, Fixture.SPITE).events,
		Gen2Battle.NO_EFFECT).size(), 1)

	# A slot already empty.
	var spent: Gen2Battle = _battle()
	spent.enemy.last_move_used = Fixture.TACKLE
	spent.enemy.pp[0] = 0
	assert_eq(_of_type(_run_move(spent, Fixture.SPITE).events,
		Gen2Battle.NO_EFFECT).size(), 1)

	# A move no longer in the list, which the cartridge's own unbounded loop would
	# have run off the end of.
	var replaced: Gen2Battle = _battle()
	replaced.enemy.last_move_used = Fixture.SLASH
	assert_eq(_of_type(_run_move(replaced, Fixture.SPITE).events,
		Gen2Battle.NO_EFFECT).size(), 1)


func test_pain_split_averages_both_totals() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.hp = 10
	battle.enemy.hp = 40
	var turn: Gen2Turn = _run_move(battle, Fixture.PAIN_SPLIT)

	assert_eq(battle.player.hp, 25)
	assert_eq(battle.enemy.hp, 25)
	assert_eq(_of_type(turn.events, Gen2Battle.SHARED_PAIN).size(), 1)
	# Floored, not rounded: the sixteen-bit sum is shifted right once.
	var odd: Gen2Battle = _battle()
	odd.player.hp = 10
	odd.enemy.hp = 11
	_run_move(odd, Fixture.PAIN_SPLIT)
	assert_eq(odd.player.hp, 10)
	assert_eq(odd.enemy.hp, 10)


## `.EnemyShareHP`'s `jr nc, .skip` keeps the maximum when the average is past it,
## so a Pokémon with a small maximum is filled rather than overfilled.
func test_pain_split_clamps_each_side_to_its_own_maximum() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.GASTLY, 5, [Fixture.PAIN_SPLIT]),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 80, [Fixture.TACKLE]),
		_rng
	)
	var small: int = battle.player.max_hp()
	battle.player.hp = 1
	assert_gt(battle.enemy.hp / 2, small, "the average is past the small maximum")

	_run_move(battle, Fixture.PAIN_SPLIT)
	assert_eq(battle.player.hp, small, "filled, not overfilled")


## The health words are written by hand, so no doll stands in the way and there is
## nothing for one to take.
func test_pain_split_is_refused_by_a_substitute() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.hp = 10
	battle.enemy.substatus |= Gen2Substatus.SUBSTITUTE
	battle.enemy.substitute_hp = 20
	var turn: Gen2Turn = _run_move(battle, Fixture.PAIN_SPLIT)

	assert_eq(battle.player.hp, 10, "nothing moved")
	assert_eq(_of_type(turn.events, Gen2Battle.NO_EFFECT).size(), 1)


func test_thief_takes_the_targets_item() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.item = Fixture.MAGNET
	var turn: Gen2Turn = _run_move(battle, Fixture.THIEF)

	assert_eq(battle.player.item, Fixture.MAGNET)
	assert_eq(battle.enemy.item, 0)
	assert_eq(int(_first(turn.events, Gen2Battle.STOLE_ITEM)["item"]), Fixture.MAGNET)
	# The party member and the Pokemon on the field are one object here, which is
	# what makes a stolen item gone for good.
	assert_eq(battle.party(Gen2Battle.PLAYER).at(0).item, Fixture.MAGNET)


func test_thief_refuses_a_thief_that_is_already_carrying_something() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.item = Fixture.LEFTOVERS
	battle.enemy.item = Fixture.MAGNET
	var turn: Gen2Turn = _run_move(battle, Fixture.THIEF)

	assert_eq(battle.player.item, Fixture.LEFTOVERS)
	assert_eq(battle.enemy.item, Fixture.MAGNET)
	assert_eq(_of_type(turn.events, Gen2Battle.STOLE_ITEM).size(), 0)
	# Silently: every one of Thief's refusals is a bare `ret`.
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 0)


func test_thief_leaves_mail_where_it_is() -> void:
	assert_true(Gen2HeldItem.is_mail(Fixture.FLOWER_MAIL))
	assert_false(Gen2HeldItem.is_mail(Fixture.MAGNET))

	var battle: Gen2Battle = _battle()
	battle.enemy.item = Fixture.FLOWER_MAIL
	var turn: Gen2Turn = _run_move(battle, Fixture.THIEF)

	assert_eq(battle.enemy.item, Fixture.FLOWER_MAIL)
	assert_eq(battle.player.item, 0)
	assert_eq(_of_type(turn.events, Gen2Battle.STOLE_ITEM).size(), 0)
	# The hit still landed: the steal is behind `applydamage`.
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 1)


func test_teleport_takes_its_own_user_out_of_a_wild_battle() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.TELEPORT)

	assert_true(battle.is_over())
	assert_true(battle.was_forced_out())
	assert_eq(battle.forced_out_side(), Gen2Battle.PLAYER, "the user is who left")
	assert_null(battle.winner(), "SetBattleDraw: nobody beat anybody")
	assert_eq(_of_type(turn.events, Gen2Battle.FLED_FROM_BATTLE).size(), 1)


func test_teleport_is_refused_in_a_trainer_battle() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TELEPORT])]),
		Gen2Party.create([Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE])]),
		_rng, true
	)
	var turn: Gen2Turn = _run_move(battle, Fixture.TELEPORT)

	assert_false(battle.is_over())
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


func test_teleport_is_refused_by_the_four_scripted_battle_types() -> void:
	for battle_type: int in Gen2EffectCommands.FORCE_SWITCH_REFUSED_TYPES:
		var battle: Gen2Battle = _battle()
		battle.battle_type = battle_type
		var turn: Gen2Turn = _run_move(battle, Fixture.TELEPORT)

		assert_false(battle.is_over(), "battle type %d" % battle_type)
		assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


## `wEnemySubStatus5`'s own `SUBSTATUS_CANT_RUN`, which is what Mean Look and
## Spider Web leave on the Pokemon doing the holding.
func test_teleport_is_refused_while_the_opponent_holds_the_user() -> void:
	var battle: Gen2Battle = _battle()
	battle.enemy.substatus |= Gen2Substatus.CANT_RUN
	var turn: Gen2Turn = _run_move(battle, Fixture.TELEPORT)

	assert_false(battle.is_over())
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


## Below the other's level the player's half goes on the dice, drawn out of the two
## levels summed and one more, and fails under a quarter of the other's level. A
## level 4 user against a level 50 fails on the twelve values under 12, out of 55.
func test_a_weaker_player_rolls_for_teleport() -> void:
	var failures: int = 0
	var samples: int = 200
	for seed_value: int in samples:
		var battle: Gen2Battle = Gen2Battle.create(
			_data,
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 4, [Fixture.TELEPORT]),
			Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_rng
		)
		battle.rng.seed = seed_value
		if _of_type(_run_move(battle, Fixture.TELEPORT).events,
			Gen2Battle.MOVE_FAILED).size() > 0:
			failures += 1

	var expected: int = samples * 12 / 55
	assert_almost_eq(failures, expected, expected / 3,
		"roughly twelve of the fifty-five values it can draw")


## `docs/bugs_and_glitches.md`: the enemy's own `jr nc, .run_away` falls into
## `.run_away`, so the roll it draws decides nothing and a wild Pokemon always
## teleports. The roll is still drawn.
func test_a_wild_pokemon_always_teleports_and_still_draws_the_roll() -> void:
	for seed_value: int in 40:
		var battle: Gen2Battle = Gen2Battle.create(
			_data,
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TACKLE]),
			Gen2BattleMon.create(_data, Fixture.GEODUDE, 4, [Fixture.TELEPORT]),
			_rng
		)
		battle.rng.seed = seed_value
		var before: int = battle.rng.state
		var turn: Gen2Turn = _run_enemy_move(battle, Fixture.TELEPORT)

		assert_true(battle.is_over(), "seed %d" % seed_value)
		assert_eq(battle.forced_out_side(), Gen2Battle.ENEMY)
		assert_eq(_of_type(turn.events, Gen2Battle.FLED_FROM_BATTLE).size(), 1)
		assert_ne(battle.rng.state, before, "the roll is drawn and thrown away")


## `pursuit` reads the other side's switching flag and doubles nothing without it.
## The flag itself is [method Gen2Battle.is_switching], which only a turn in
## flight can raise; test_battle.gd owns the switch-time half.
func test_pursuit_doubles_nothing_outside_a_switch() -> void:
	var battle: Gen2Battle = _battle()
	assert_false(battle.is_switching(Gen2Battle.ENEMY),
		"nothing is switching between turns")

	var turn: Gen2Turn = _turn(battle, Fixture.PURSUIT)
	turn.damage = 100
	Gen2EffectCommands.run(Gen2EffectCommands.PURSUIT, turn)
	assert_eq(turn.damage, 100)


## One swing per party member, in party order, each named.
func test_beat_up_swings_once_per_party_member() -> void:
	var battle: Gen2Battle = _beat_up_battle()
	var turn: Gen2Turn = _run_move(battle, Fixture.BEAT_UP)

	var swings: Array = _of_type(turn.events, Gen2Battle.BEAT_UP_ATTACK)
	assert_eq(swings.size(), 3)
	assert_eq(int(swings[0]["index"]), 0)
	assert_eq(int(swings[1]["index"]), 1)
	assert_eq(int(swings[2]["index"]), 2)
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 3)
	# `.beat_up_2` skips `endloop`'s summary line for this effect alone.
	assert_eq(_of_type(turn.events, Gen2Battle.HIT_TIMES).size(), 0)
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 0)


## `damagecalc` is handed the member's own base Attack and level and the target's
## base Defense, none of them touched by a stage, an item or the truncation
## `damagestats` would have done.
func test_beat_up_uses_base_stats_and_each_members_own_level() -> void:
	var battle: Gen2Battle = _beat_up_battle()
	# A stage the formula must not see, since there is no `damagestats` to read it.
	battle.player.stages["attack"] = 6
	var turn: Gen2Turn = _run_move(battle, Fixture.BEAT_UP)

	# The last member's numbers are what the turn is left holding: Bulbasaur's own
	# base Attack of 49 at level 10, against Gastly's base Defense of 30.
	assert_eq(turn.attack_stat, 49)
	assert_eq(turn.defense_stat, 30)
	assert_eq(turn.level_override, 10)
	assert_eq(turn.power_override, 10, "the move's own power, not a stat")
	# No `stab`, so no matchup and no immunity however the chart reads.
	assert_eq(turn.effectiveness, RomLayout.MATCHUP_EFFECTIVE)
	assert_false(turn.immune)


## `.beatup_fail` skips that member's hit and lets the loop carry on.
func test_beat_up_skips_a_fainted_or_statused_member() -> void:
	var battle: Gen2Battle = _beat_up_battle()
	battle.party(Gen2Battle.PLAYER).at(1).status = Gen2Status.PARALYSIS
	battle.party(Gen2Battle.PLAYER).at(2).hp = 0
	var turn: Gen2Turn = _run_move(battle, Fixture.BEAT_UP)

	var swings: Array = _of_type(turn.events, Gen2Battle.BEAT_UP_ATTACK)
	assert_eq(swings.size(), 1)
	assert_eq(int(swings[0]["index"]), 0)
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 0,
		"one member landed a hit, so `beatupfailtext` says nothing")


func test_beat_up_says_it_failed_when_no_member_could_swing() -> void:
	var battle: Gen2Battle = _beat_up_battle()
	for index: int in 3:
		battle.party(Gen2Battle.PLAYER).at(index).status = Gen2Status.PARALYSIS
	var turn: Gen2Turn = _run_move(battle, Fixture.BEAT_UP)

	assert_eq(_of_type(turn.events, Gen2Battle.BEAT_UP_ATTACK).size(), 0)
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


## `.only_one_beatup`, which `docs/bugs_and_glitches.md` records: the one hit lands
## and then `jp EndMoveEffect` takes the rest of the list with it.
func test_beat_up_with_one_party_member_ends_before_kings_rock() -> void:
	var alone: Array = _commands_run(_battle(), Fixture.BEAT_UP)
	assert_true(alone.has(Gen2EffectCommands.BEAT_UP))
	assert_false(alone.has(Gen2EffectCommands.KINGS_ROCK),
		"`.only_one_beatup` takes the rest of the list with it")

	# A party of three falls out of the loop instead and reaches the item.
	var party: Array = _commands_run(_beat_up_battle(), Fixture.BEAT_UP)
	assert_true(party.has(Gen2EffectCommands.KINGS_ROCK))


func test_the_called_and_copy_move_effects_have_their_source_wrappers() -> void:
	var rows: Dictionary = {
		Gen2MoveEffect.MIRROR_MOVE: Gen2EffectCommands.MIRROR_MOVE,
		Gen2MoveEffect.CONVERSION: Gen2EffectCommands.CONVERSION,
		Gen2MoveEffect.MIMIC: Gen2EffectCommands.MIMIC,
		Gen2MoveEffect.METRONOME: Gen2EffectCommands.METRONOME,
		Gen2MoveEffect.CONVERSION_2: Gen2EffectCommands.CONVERSION_2,
		Gen2MoveEffect.SKETCH: Gen2EffectCommands.SKETCH,
		Gen2MoveEffect.SLEEP_TALK: Gen2EffectCommands.SLEEP_TALK,
	}
	for effect: int in rows:
		var sequence: Array = Gen2MoveEffect.sequence_for(effect)
		assert_true(Gen2MoveEffect.is_written(effect), "effect %d" % effect)
		assert_eq(sequence[sequence.size() - 2], rows[effect], "effect %d" % effect)


func test_metronome_calls_an_allowed_move_without_spending_its_pp() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.METRONOME]),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)
	var before_pp: int = battle.player.pp_left(0)
	var events: Array = battle.take_turn(0, 0)
	var used: Array = _of_type(events, Gen2Battle.USED_MOVE)
	assert_gte(used.size(), 3)
	assert_eq(int(used[0]["move"]), Fixture.METRONOME)
	var called: int = int(used[1]["move"])
	assert_false(Gen2EffectCommands.METRONOME_EXCEPTS.has(called))
	assert_false(battle.player.moves.has(called))
	assert_eq(battle.player.pp_left(0), before_pp - 1)
	assert_eq(battle.player.turns_taken, 1, "the called move is not a second turn")
	assert_eq(battle.player.last_move_used, 0, "ClearLastMove survives the nested used text")


func test_mirror_move_replays_the_faster_opponents_move() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.MIRROR_MOVE]),
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_rng
	)
	var enemy_before: int = battle.enemy.hp
	var mirror_pp: int = battle.player.pp_left(0)
	var events: Array = battle.take_turn(0, 0)
	var used: Array = _of_type(events, Gen2Battle.USED_MOVE)
	assert_eq(used.size(), 3)
	assert_eq(int(used[0]["move"]), Fixture.TACKLE)
	assert_eq(int(used[1]["move"]), Fixture.MIRROR_MOVE)
	assert_eq(int(used[2]["move"]), Fixture.TACKLE)
	assert_lt(battle.enemy.hp, enemy_before)
	assert_eq(battle.player.pp_left(0), mirror_pp - 1)
	assert_eq(battle.player.last_move_used, 0)


func test_mirror_move_refuses_a_move_the_user_already_knows() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(
			_data, Fixture.PIKACHU, 50, [Fixture.MIRROR_MOVE, Fixture.TACKLE]
		),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)
	battle.enemy.last_move_used = Fixture.TACKLE
	var turn: Gen2Turn = _turn(battle, Fixture.MIRROR_MOVE)
	Gen2EffectCommands.run(Gen2EffectCommands.MIRROR_MOVE, turn)
	assert_true(turn.ended)
	assert_eq(turn.called_move_number, 0)
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


func test_sleep_talk_calls_an_empty_pp_move_while_still_asleep() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(
			_data, Fixture.PIKACHU, 50, [Fixture.SLEEP_TALK, Fixture.TACKLE]
		),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)
	battle.player.status = 3
	battle.player.pp[1] = 0
	var sleep_talk_pp: int = battle.player.pp_left(0)
	var before: int = battle.enemy.hp
	var events: Array = battle.take_turn(0, 0)
	var used: Array = _of_type(events, Gen2Battle.USED_MOVE)
	assert_eq(int(used[0]["move"]), Fixture.SLEEP_TALK)
	assert_eq(int(used[1]["move"]), Fixture.TACKLE)
	assert_lt(battle.enemy.hp, before)
	assert_eq(battle.player.pp_left(0), sleep_talk_pp - 1)
	assert_eq(battle.player.pp_left(1), 0, "the called move spends no PP")
	assert_eq(_of_type(events, Gen2Battle.CANNOT_MOVE).size(), 1, "fast asleep is still said")


func test_sleep_talk_fails_awake_or_without_an_allowed_move() -> void:
	for status: int in [Gen2Status.NONE, 3]:
		var moves: Array = (
			[Fixture.SLEEP_TALK] if status == Gen2Status.NONE
			else [Fixture.SLEEP_TALK, Fixture.FLY]
		)
		var battle: Gen2Battle = Gen2Battle.create(
			_data,
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, moves),
			Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_rng
		)
		battle.player.status = status
		var events: Array = battle.take_turn(0, 0)
		assert_eq(_of_type(events, Gen2Battle.MOVE_FAILED).size(), 1, "status %d" % status)


func test_mimic_replaces_only_the_active_battle_move_with_five_pp() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.MIMIC]),
			Gen2BattleMon.create(_data, Fixture.BULBASAUR, 50, [Fixture.GROWL]),
		]),
		Gen2Party.create([
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		]),
		_rng
	)
	var events: Array = battle.take_turn(0, 0)
	var mimic: Gen2BattleMon = battle.player
	assert_eq(mimic.moves[0], Fixture.TACKLE)
	assert_eq(mimic.pp_left(0), 5)
	assert_eq(mimic.persistent_move(0), Fixture.MIMIC)
	assert_eq(mimic.persistent_pp(0), 9, "Mimic itself still spent one PP")
	assert_eq(_of_type(events, Gen2Battle.MIMIC_LEARNED).size(), 1)
	var saved: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(mimic)
	assert_eq(saved.moves[0], Fixture.MIMIC)
	assert_eq(saved.pp[0], 9)
	battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(battle.party(Gen2Battle.PLAYER).at(0).moves[0], Fixture.MIMIC)
	assert_eq(battle.party(Gen2Battle.PLAYER).at(0).pp_left(0), 9)


func test_sketch_replaces_the_party_move_at_the_copied_moves_base_pp() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.SKETCH]),
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_rng
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(battle.player.moves[0], Fixture.TACKLE)
	assert_eq(battle.player.pp_left(0), int(_data.move(Fixture.TACKLE)["pp"]))
	assert_eq(battle.player.persistent_move(0), Fixture.TACKLE)
	assert_eq(_of_type(events, Gen2Battle.SKETCHED_MOVE).size(), 1)
	var saved: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(battle.player)
	assert_eq(saved.moves[0], Fixture.TACKLE)
	assert_eq(saved.pp[0], int(_data.move(Fixture.TACKLE)["pp"]))


func test_mimic_and_sketch_refuse_invalid_or_already_known_moves() -> void:
	for number: int in [Fixture.MIMIC, Fixture.SKETCH]:
		var battle: Gen2Battle = Gen2Battle.create(
			_data,
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [number, Fixture.TACKLE]),
			Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_rng
		)
		battle.enemy.last_move_used = Fixture.TACKLE
		var turn: Gen2Turn = _turn(battle, number)
		Gen2EffectCommands.run(
			Gen2EffectCommands.MIMIC if number == Fixture.MIMIC else Gen2EffectCommands.SKETCH,
			turn
		)
		assert_true(turn.ended, "move %d" % number)
		assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1, "move %d" % number)


func test_sketch_is_refused_by_the_targets_substitute() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.moves = [Fixture.SKETCH]
	battle.player.pp = [1]
	battle.enemy.last_move_used = Fixture.TACKLE
	battle.enemy.substatus = Gen2Substatus.SUBSTITUTE
	var turn: Gen2Turn = _turn(battle, Fixture.SKETCH)
	Gen2EffectCommands.run(Gen2EffectCommands.SKETCH, turn)
	assert_eq(battle.player.moves[0], Fixture.SKETCH)
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


func test_conversion_takes_a_different_type_from_the_users_moves() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(
			_data, Fixture.PIKACHU, 50,
			[Fixture.CONVERSION, Fixture.TACKLE, Fixture.THUNDERBOLT]
		),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)
	var turn: Gen2Turn = _run_move(battle, Fixture.CONVERSION)
	assert_eq(battle.player.types(), [Fixture.NORMAL, Fixture.NORMAL])
	assert_eq(_of_type(turn.events, Gen2Battle.TYPE_CHANGED).size(), 1)
	assert_eq(int(_first(turn.events, Gen2Battle.TYPE_CHANGED)["type_number"]), Fixture.NORMAL)


func test_conversion_fails_when_every_move_matches_a_current_type() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data,
		Gen2BattleMon.create(
			_data, Fixture.HOOTHOOT, 50, [Fixture.CONVERSION, Fixture.TACKLE]
		),
		Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_rng
	)
	var turn: Gen2Turn = _run_move(battle, Fixture.CONVERSION)
	assert_eq(battle.player.types(), [Fixture.NORMAL, Fixture.FLYING])
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)


func test_conversion2_picks_a_type_that_resists_the_last_move() -> void:
	var battle: Gen2Battle = _battle()
	battle.player.moves = [Fixture.CONVERSION_2]
	battle.player.pp = [30]
	battle.enemy.last_move_used = Fixture.TACKLE
	var turn: Gen2Turn = _run_move(battle, Fixture.CONVERSION_2)
	var picked: int = int(battle.player.types()[0])
	assert_lt(
		_data.type_effectiveness(Fixture.NORMAL, [picked, picked]),
		RomLayout.MATCHUP_EFFECTIVE
	)
	assert_eq(battle.player.types()[1], picked)
	assert_eq(_of_type(turn.events, Gen2Battle.TYPE_CHANGED).size(), 1)


func test_conversion2_refuses_no_move_and_curse_type() -> void:
	for last_move: int in [0, Fixture.CURSE]:
		var battle: Gen2Battle = _battle()
		battle.player.moves = [Fixture.CONVERSION_2]
		battle.player.pp = [30]
		battle.enemy.last_move_used = last_move
		var turn: Gen2Turn = _run_move(battle, Fixture.CONVERSION_2)
		assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1, "move %d" % last_move)


func test_a_switch_restores_species_types_after_conversion() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.CONVERSION]),
			Gen2BattleMon.create(_data, Fixture.BULBASAUR, 50, [Fixture.TACKLE]),
		]),
		Gen2Party.create([
			Gen2BattleMon.create(_data, Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		]),
		_rng
	)
	_run_move(battle, Fixture.CONVERSION)
	assert_eq(battle.player.types(), [Fixture.NORMAL, Fixture.NORMAL])
	battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(
		battle.party(Gen2Battle.PLAYER).at(0).types(),
		[Fixture.ELECTRIC, Fixture.ELECTRIC]
	)


## `.wild`: no party to walk, so one ordinary hit off the wild Pokemon's own real
## stats, and `.only_one_beatup` prints "But it failed!" behind a hit that landed.
func test_a_wild_beat_up_swings_once_and_says_it_failed_anyway() -> void:
	var battle: Gen2Battle = _battle()
	var turn: Gen2Turn = _run_enemy_move(battle, Fixture.BEAT_UP)

	var swings: Array = _of_type(turn.events, Gen2Battle.BEAT_UP_ATTACK)
	assert_eq(swings.size(), 1)
	assert_eq(int(swings[0]["index"]), -1, "a wild Pokemon has no party slot")
	assert_eq(_of_type(turn.events, Gen2Battle.HIT).size(), 1)
	assert_eq(_of_type(turn.events, Gen2Battle.MOVE_FAILED).size(), 1)
	assert_eq(turn.level_override, -1, "its own level, through the ordinary steps")
	assert_gt(turn.attack_stat, 0, "`damagestats` ran, so these are real stats")


## Three party members over two levels, against a target whose base Defense is low
## enough for a power of 10 to show.
func _beat_up_battle() -> Gen2Battle:
	return Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, [Fixture.BEAT_UP]),
			Gen2BattleMon.create(_data, Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
			Gen2BattleMon.create(_data, Fixture.BULBASAUR, 10, [Fixture.TACKLE]),
		]),
		Gen2Party.create([
			Gen2BattleMon.create(_data, Fixture.GASTLY, 60, [Fixture.TACKLE]),
		]),
		_rng, true
	)


## Which steps a move actually reached, for the two effects that end their own
## list part way and so leave the commands behind them unrun.
func _commands_run(battle: Gen2Battle, move_number: int) -> Array:
	var turn: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, move_number, _data.move(move_number), []
	)
	var ran: Array = []
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	for command: StringName in Gen2MoveEffect.sequence_for(turn.effect()):
		if turn.ended:
			break
		ran.append(command)
		Gen2EffectCommands.run(command, turn)
	return ran
