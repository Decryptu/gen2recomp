extends GutTest

## The four routes a move's animation reaches the screen by.
##
## `moveanim` and `moveanimnosub` sit in the effect lists, `statupanim` and
## `statdownanim` between a stat change and its message, and `AnimateCurrentMove`
## inside individual command bodies rather than in any list at all. All four
## write the same event, since the engine is scene-free and the screen is what
## spends the frames.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"animcommandtest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 4242


func after_each() -> void:
	RomCache.clear(_directory)


func _battle(player_moves: Array, enemy_moves: Array = [Fixture.TACKLE]) -> Gen2Battle:
	return Gen2Battle.create(
		_data,
		Gen2BattleMon.create(_data, Fixture.PIKACHU, 50, player_moves),
		Gen2BattleMon.create(_data, Fixture.CHARMANDER, 50, enemy_moves),
		_rng
	)


func _run_move(battle: Gen2Battle, move_number: int, side: int = Gen2Battle.PLAYER) -> Array:
	var events: Array = []
	var turn: Gen2Turn = Gen2Turn.create(
		battle, side, 0, move_number, _data.move(move_number), events
	)
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	for command: StringName in Gen2MoveEffect.sequence_for(turn.effect()):
		if turn.ended:
			break
		Gen2EffectCommands.run(command, turn)
	return events


func _animations(events: Array) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		if StringName(event["type"]) == Gen2Battle.ANIMATION:
			out.append(event)
	return out


func _index_of(events: Array, type: StringName) -> int:
	for index: int in events.size():
		if StringName(events[index]["type"]) == type:
			return index
	return -1


func test_an_ordinary_attack_animates_between_the_hit_check_and_the_damage() -> void:
	var events: Array = _run_move(_battle([Fixture.TACKLE]), Fixture.TACKLE)
	var animations: Array = _animations(events)
	assert_eq(animations.size(), 1)
	# `wFXAnimID` is the move's own animation byte, which the importer has
	# already checked is the move's number.
	assert_eq(int(animations[0]["index"]), Fixture.TACKLE)
	assert_lt(
		_index_of(events, Gen2Battle.ANIMATION), _index_of(events, Gen2Battle.HIT),
		"moveanim runs before applydamage"
	)


func test_the_damage_flash_is_aimed_at_whoever_was_hit() -> void:
	var player: Array = _animations(_run_move(_battle([Fixture.TACKLE]), Fixture.TACKLE))
	assert_eq(
		int(player[0]["after_anim"]), Gen2BattleAnimPlayer.AFTER_ANIM_ENEMY_DAMAGE
	)
	assert_false(bool(player[0]["enemy_turn"]))

	var enemy: Array = _animations(
		_run_move(_battle([Fixture.TACKLE]), Fixture.TACKLE, Gen2Battle.ENEMY)
	)
	assert_eq(
		int(enemy[0]["after_anim"]), Gen2BattleAnimPlayer.AFTER_ANIM_PLAYER_DAMAGE
	)
	assert_true(bool(enemy[0]["enemy_turn"]))


func test_a_missed_attack_plays_nothing() -> void:
	var battle: Gen2Battle = _battle([Fixture.TACKLE])
	# `BattleCommand_MoveAnimNoSub` falls to `BattleCommand_MoveDelay` on a miss;
	# here `checkhit` has already ended the move before the step is reached.
	battle.player.stages["accuracy"] = -6
	battle.enemy.stages["evasion"] = 6
	var events: Array = _run_move(battle, Fixture.TACKLE)
	assert_eq(_index_of(events, Gen2Battle.MISSED) >= 0, true)
	assert_eq(_animations(events).size(), 0)


func test_a_stat_move_animates_between_the_change_and_its_message() -> void:
	var events: Array = _run_move(_battle([Fixture.SWORDS_DANCE]), Fixture.SWORDS_DANCE)
	var animations: Array = _animations(events)
	assert_eq(animations.size(), 1)
	# `BattleCommand_StatUpAnim`'s own `xor a`: one animation for both sides and
	# no damage flash behind it.
	assert_eq(int(animations[0]["after_anim"]), Gen2BattleAnimPlayer.AFTER_ANIM_NONE)
	assert_lt(
		_index_of(events, Gen2Battle.ANIMATION), _index_of(events, Gen2Battle.STAT_CHANGED),
		"statupanim runs before statupmessage"
	)


func test_a_stat_drop_picks_its_after_anim_by_whose_turn_it_is() -> void:
	var player: Array = _animations(_run_move(_battle([Fixture.SCREECH]), Fixture.SCREECH))
	assert_eq(
		int(player[0]["after_anim"]), Gen2BattleAnimPlayer.AFTER_ANIM_ENEMY_STAT_DOWN
	)
	var battle: Gen2Battle = _battle([Fixture.SCREECH], [Fixture.SCREECH])
	# Screech is 85 percent and this is about which animation it picks, not
	# about the roll.
	battle.enemy.stages["accuracy"] = Gen2Stats.MAX_STAGE
	var enemy: Array = _animations(_run_move(battle, Fixture.SCREECH, Gen2Battle.ENEMY))
	assert_eq(int(enemy[0]["after_anim"]), Gen2BattleAnimPlayer.AFTER_ANIM_WOBBLE)


func test_a_stat_already_at_its_ceiling_still_animates() -> void:
	# `RaiseStat` sets `wFailedMessage`, not `wAttackMissed`, and only the second
	# is what `BattleCommand_StatUpAnim` reads.
	var battle: Gen2Battle = _battle([Fixture.SWORDS_DANCE])
	battle.player.stages["attack"] = Gen2Stats.MAX_STAGE
	var events: Array = _run_move(battle, Fixture.SWORDS_DANCE)
	assert_eq(_animations(events).size(), 1)
	assert_true(_index_of(events, Gen2Battle.STAT_CHANGE_FAILED) >= 0)


func test_a_status_move_with_no_animation_command_still_animates() -> void:
	# Thunder Wave's list carries no animation command at all: the whole of its
	# animation is `BattleCommand_Paralyze`'s own `AnimateCurrentMove`.
	for command: StringName in Gen2MoveEffect.sequence_for(Gen2MoveEffect.PARALYZE):
		assert_ne(command, Gen2EffectCommands.MOVE_ANIM)
	var events: Array = _run_move(
		_battle([Fixture.THUNDER_WAVE]), Fixture.THUNDER_WAVE
	)
	var animations: Array = _animations(events)
	assert_eq(animations.size(), 1)
	assert_eq(int(animations[0]["index"]), Fixture.THUNDER_WAVE)
	assert_eq(int(animations[0]["after_anim"]), Gen2BattleAnimPlayer.AFTER_ANIM_NONE)


func test_a_secondary_paralysis_does_not_animate_a_second_time() -> void:
	# `BattleCommand_ParalyzeTarget` has no `AnimateCurrentMove`: the move that
	# carried it played its own `moveanim` already.
	var events: Array = _run_move(_battle([Fixture.EMBER_BURNS]), Fixture.EMBER_BURNS)
	assert_eq(_animations(events).size(), 1)


func test_a_multi_hit_animates_every_hit_and_flashes_only_the_last() -> void:
	var events: Array = _run_move(_battle([Fixture.DOUBLE_HIT_MOVE]), Fixture.DOUBLE_HIT_MOVE)
	var animations: Array = _animations(events)
	assert_eq(animations.size(), 2)
	assert_eq(int(animations[0]["after_anim"]), Gen2BattleAnimPlayer.AFTER_ANIM_NONE)
	assert_eq(
		int(animations[1]["after_anim"]), Gen2BattleAnimPlayer.AFTER_ANIM_ENEMY_DAMAGE
	)
	# `.alternate_anim` flips the low bit rather than clearing the param.
	assert_ne(int(animations[0]["param"]), int(animations[1]["param"]))


func test_an_ordinary_attack_clears_the_animation_param() -> void:
	var battle: Gen2Battle = _battle([Fixture.TACKLE])
	battle.battle_anim_param = 1
	var animations: Array = _animations(_run_move(battle, Fixture.TACKLE))
	assert_eq(int(animations[0]["param"]), 0)
	assert_eq(battle.battle_anim_param, 0)


func test_only_fly_and_dig_ask_for_the_user_picture_back() -> void:
	# `BattleCommand_MoveAnimNoSub`'s own tail: `cp FLY` / `cp DIG`, then
	# `AppearUserLowerSub`. Nothing else in the game reaches it.
	var battle: Gen2Battle = _battle([Fixture.TACKLE])
	assert_false(bool(_animations(_run_move(battle, Fixture.TACKLE))[0]["restore_user_pic"]))
	assert_eq(Gen2MoveEffect.FLY_MOVE, 19)
	assert_eq(Gen2MoveEffect.DIG_MOVE, 91)


func test_haze_animates_from_inside_its_own_command() -> void:
	var events: Array = _run_move(_battle([Fixture.HAZE]), Fixture.HAZE)
	assert_eq(_animations(events).size(), 1)
	assert_lt(
		_index_of(events, Gen2Battle.ANIMATION), _index_of(events, Gen2Battle.STAGES_CLEARED),
		"AnimateCurrentMove runs before EliminatedStatsText"
	)
