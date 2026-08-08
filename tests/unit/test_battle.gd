extends GutTest

## The turn loop: who goes first, what connects, and when it is over.
##
## The rolls are made by a seeded [RandomNumberGenerator], so a test that has to
## be sure of an outcome arranges one that cannot go the other way (a move that
## always hits, a Pokémon that cannot survive) rather than leaning on a seed.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"battletest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 12345


func after_each() -> void:
	RomCache.clear(_directory)


func _mon(species: int, level: int, moves: Array) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, species, level, moves)


func _battle(player: Gen2BattleMon, enemy: Gen2BattleMon) -> Gen2Battle:
	return Gen2Battle.create(_data, player, enemy, _rng)


func _of_type(events: Array, type: StringName) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _first(events: Array, type: StringName) -> Dictionary:
	var found: Array = _of_type(events, type)
	return found[0] if not found.is_empty() else {}


func test_the_faster_pokemon_moves_first() -> void:
	# Pikachu at 50 has 110 Speed and Geodude has 30, so nothing about the roll
	# can change this.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_first(events, Gen2Battle.USED_MOVE)["side"], Gen2Battle.PLAYER)


func test_the_slower_pokemon_moves_first_when_it_is_the_other_way_round() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	assert_eq(
		_first(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)["side"], Gen2Battle.ENEMY
	)


func test_speed_is_read_with_its_stage_applied() -> void:
	# Geodude is far slower until it is not. A stage is a lens on a stat, and
	# turn order is the first thing that has to look through it.
	var slow: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	slow.change_stage("speed", 6)
	var battle: Gen2Battle = _battle(slow, _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]))
	assert_eq(
		_first(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)["side"], Gen2Battle.PLAYER
	)


func test_priority_beats_speed() -> void:
	# The effect byte carries it, and the cache already has the effect byte.
	assert_eq(Gen2Battle.priority_of({"number": 1, "effect": 0}), Gen2Battle.BASE_PRIORITY)
	assert_eq(Gen2Battle.priority_of({"number": 1, "effect": 0x67}), 2, "Quick Attack")
	assert_eq(Gen2Battle.priority_of({"number": 1, "effect": 0x6F}), 3, "Protect")
	assert_eq(Gen2Battle.priority_of({"number": 1, "effect": 0x59}), 0, "Counter")


func test_counter_doubles_the_raw_damage_taken_by_the_slower_side() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.COUNTER])
	)
	var events: Array = battle.take_turn(0, 0)
	var hits: Array = _of_type(events, Gen2Battle.HIT)
	assert_eq(hits.size(), 2)
	assert_eq(int(hits[1]["amount"]), int(hits[0]["amount"]) * 2)


func test_counter_does_not_keep_damage_from_a_previous_action_pair() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE, Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL, Fixture.COUNTER])
	)
	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var events: Array = battle.take_actions(Gen2Battle.use_move(1), Gen2Battle.use_move(1))
	assert_eq(_of_type(events, Gen2Battle.MOVE_FAILED).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.HIT).size(), 0)


func test_vital_throw_says_it_is_last_in_the_move_and_not_in_the_effect() -> void:
	# The one move the effect table cannot answer for.
	assert_eq(Gen2Battle.priority_of({"number": Gen2Battle.VITAL_THROW, "effect": 17}), 0)


func test_a_move_costs_a_pp() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT])
	var battle: Gen2Battle = _battle(attacker, _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]))
	battle.take_turn(0, 0)
	assert_eq(attacker.pp_left(0), 14)


func test_a_pokemon_with_nothing_left_struggles_and_it_costs_nothing() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT])
	for _spend: int in 15:
		attacker.spend_pp(0)

	var battle: Gen2Battle = _battle(attacker, _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE]))
	var used: Array = _of_type(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)
	assert_eq(int(used[0]["move"]), Gen2Damage.STRUGGLE)
	assert_eq(attacker.pp_left(0), 0, "there was nothing to spend")


func test_struggle_costs_the_attacker_a_quarter_of_what_it_dealt() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [])
	var battle: Gen2Battle = _battle(attacker, _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE]))
	var events: Array = battle.take_turn(0, 0)

	var hit: Dictionary = _first(events, Gen2Battle.HIT)
	var recoil: Dictionary = _first(events, Gen2Battle.RECOIL)
	assert_false(recoil.is_empty(), "Struggle recoils")
	assert_eq(int(recoil["amount"]), maxi(int(hit["amount"]) / 4, 1))
	# Against the health the event carries, not against the Pokémon: Bulbasaur
	# gets its own turn afterwards and takes more off.
	assert_eq(int(recoil["hp"]), attacker.max_hp() - int(recoil["amount"]))


func test_an_immunity_is_reported_rather_than_a_hit_for_nothing() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.NO_EFFECT).size(), 1)
	assert_true(_of_type(events, Gen2Battle.HIT).filter(
		func(event: Dictionary) -> bool: return event["side"] == Gen2Battle.PLAYER
	).is_empty(), "no hit event for a move that does not affect it")
	assert_eq(battle.enemy.hp, battle.enemy.max_hp())


func test_a_hit_carries_the_numbers_the_screen_needs() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	var hit: Dictionary = _first(battle.take_turn(0, 0), Gen2Battle.HIT)
	assert_eq(hit["side"], Gen2Battle.PLAYER)
	assert_eq(hit["target"], Gen2Battle.ENEMY)
	assert_eq(int(hit["effectiveness"]), 5, "Grass resists Electric")
	assert_between(int(hit["amount"]), 22, 52)
	assert_eq(int(hit["hp"]), battle.enemy.hp)
	assert_eq(int(hit["max_hp"]), battle.enemy.max_hp())


func test_a_faint_ends_the_turn_before_the_other_side_answers() -> void:
	# A level 5 Bulbasaur cannot survive a level 100 Pikachu, and a Pokémon that
	# has fainted does not get its turn.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1, "only the first side acted")
	assert_eq(_first(events, Gen2Battle.FAINTED)["side"], Gen2Battle.ENEMY)
	assert_true(battle.is_over())
	assert_eq(battle.winner(), Gen2Battle.PLAYER)


func test_a_battle_that_is_over_does_not_take_another_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.take_turn(0, 0), [])


func test_the_last_event_of_a_finished_battle_says_who_won() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(events[events.size() - 1]["type"], Gen2Battle.OVER)
	assert_eq(events[events.size() - 1]["winner"], Gen2Battle.PLAYER)


func test_a_battle_runs_to_an_end_rather_than_going_round_forever() -> void:
	# The one thing a turn loop has to do. Two Pokémon that will run out of PP
	# long before they run out of health, so this only terminates if Struggle and
	# its recoil both work.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 20, [Fixture.THUNDERBOLT]),
		_mon(Fixture.PIKACHU, 20, [Fixture.THUNDERBOLT])
	)
	var turns: int = 0
	while not battle.is_over() and turns < 500:
		battle.take_turn(0, 0)
		turns += 1
	assert_true(battle.is_over(), "still going after %d turns" % turns)
	assert_lt(turns, 500)


func test_an_unusable_slot_answers_struggle_rather_than_nothing() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	assert_eq(battle.move_for(Gen2Battle.PLAYER, 0), Fixture.THUNDERBOLT)
	assert_eq(battle.move_for(Gen2Battle.PLAYER, 3), Gen2Damage.STRUGGLE)


func test_a_real_rollout_continuation_forces_the_move_and_keeps_its_pp() -> void:
	var attacker: Gen2BattleMon = _mon(
		Fixture.PIKACHU, 50, [Fixture.ROLLOUT, Fixture.TACKLE]
	)
	var battle: Gen2Battle = _battle(attacker, _mon(Fixture.GEODUDE, 50, [Fixture.GROWL]))
	battle.enemy.hp = 10000
	# Make the stored 90% Rollout deterministic for this integration check while
	# leaving the fixture's real accuracy byte intact.
	attacker.change_stage("accuracy", Gen2Stats.MAX_STAGE)
	battle.enemy.change_stage("evasion", Gen2Stats.MIN_STAGE)
	var first: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(int(_first(first, Gen2Battle.USED_MOVE)["move"]), Fixture.ROLLOUT)
	assert_true(Gen2Substatus.has(attacker.substatus, Gen2Substatus.ROLLOUT))
	assert_eq(attacker.pp_left(0), 19)

	var continuation: Array = battle.take_actions(
		Gen2Battle.use_move(1), Gen2Battle.use_move(0)
	)
	assert_eq(int(_first(continuation, Gen2Battle.USED_MOVE)["move"]), Fixture.ROLLOUT)
	assert_eq(attacker.pp_left(0), 19)


func test_a_battle_needs_both_sides() -> void:
	assert_null(Gen2Battle.create(_data, null, _mon(Fixture.PIKACHU, 5, []), _rng))
	assert_null(Gen2Battle.create(null, _mon(Fixture.PIKACHU, 5, []), _mon(
		Fixture.PIKACHU, 5, []
	), _rng))


## Two Pokémon a side, which is what everything below is about.
func _party_battle(player: Array, enemy: Array) -> Gen2Battle:
	return Gen2Battle.create_parties(
		_data, Gen2Party.create(player), Gen2Party.create(enemy), _rng
	)


func _faint(mon: Gen2BattleMon) -> void:
	mon.take_damage(mon.max_hp())


func test_a_battle_is_not_over_while_a_party_still_has_somebody() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	_faint(battle.player)
	assert_false(battle.is_over(), "one down is a replacement, not a defeat")
	assert_true(battle.must_replace(Gen2Battle.PLAYER))
	assert_false(battle.must_replace(Gen2Battle.ENEMY))


func test_nothing_happens_while_a_replacement_is_owed() -> void:
	# The cartridge's order: the field is settled before the next turn is taken.
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	_faint(battle.player)
	assert_eq(battle.take_turn(0, 0), [])


func test_sending_one_out_after_a_faint_calls_nobody_back() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	_faint(battle.player)
	var events: Array = battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(_of_type(events, Gen2Battle.WITHDREW).size(), 0, "there was nobody to call back")
	assert_eq(_first(events, Gen2Battle.SENT_OUT)["index"], 1)
	assert_eq(battle.player.species, Fixture.GEODUDE)
	assert_false(battle.must_replace(Gen2Battle.PLAYER))


func test_a_switch_between_turns_calls_one_back_and_sends_one_out() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	var events: Array = battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(events.size(), 2)
	assert_eq(events[0]["type"], Gen2Battle.WITHDREW)
	assert_eq(int(events[0]["index"]), 0)
	assert_eq(events[1]["type"], Gen2Battle.SENT_OUT)


func test_a_battle_is_over_when_a_whole_party_is_down() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	_faint(battle.party(Gen2Battle.PLAYER).at(0))
	_faint(battle.party(Gen2Battle.PLAYER).at(1))
	assert_true(battle.is_over())
	assert_eq(battle.winner(), Gen2Battle.ENEMY)


func test_a_switch_goes_before_a_move_however_slow_the_switcher_is() -> void:
	# Not a very fast move: the cartridge settles a switch before it looks at
	# priority at all, which is why a switching side takes the incoming Pokémon's
	# hit rather than trading with the outgoing one.
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]), _mon(Fixture.MAGCARGO, 50, [Fixture.TACKLE])],
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])]
	)
	var events: Array = battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	assert_eq(events[0]["type"], Gen2Battle.WITHDREW)
	assert_eq(events[1]["type"], Gen2Battle.SENT_OUT)
	assert_eq(_first(events, Gen2Battle.USED_MOVE)["side"], Gen2Battle.ENEMY)
	assert_eq(_first(events, Gen2Battle.HIT)["target"], Gen2Battle.PLAYER)


func test_the_pokemon_that_came_in_is_the_one_that_gets_hit() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]), _mon(Fixture.MAGCARGO, 50, [Fixture.TACKLE])],
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])]
	)
	var incoming: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(1)
	var outgoing: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(0)
	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	assert_lt(incoming.hp, incoming.max_hp())
	assert_eq(outgoing.hp, outgoing.max_hp(), "the one that left is untouched")


func test_a_switch_that_cannot_be_made_is_refused_rather_than_approximated() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
	)
	_faint(battle.party(Gen2Battle.PLAYER).at(1))
	var events: Array = battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	assert_eq(_of_type(events, Gen2Battle.SENT_OUT).size(), 0)
	assert_eq(battle.player.species, Fixture.PIKACHU)


func test_a_pokemon_knocked_out_before_it_moves_does_not_move() -> void:
	# Most of what speed is for, and the reason a faint ends the turn where it is.
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT])],
		[_mon(Fixture.CHARMANDER, 5, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 5, [Fixture.TACKLE])]
	)
	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.FAINTED).size(), 1)
	assert_false(battle.is_over(), "there is another one behind it")
	assert_true(battle.must_replace(Gen2Battle.ENEMY))


func test_a_burn_halves_what_a_pokemon_hits_with() -> void:
	# Through the stat rather than through the stored one: a Pokémon cured of a
	# burn has its Attack back with nothing recalculated.
	var mon: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	var healthy: int = mon.stat("attack")
	mon.status = Gen2Status.BURN
	assert_eq(mon.stat("attack"), Gen2Status.apply_burn(healthy))
	assert_eq(mon.unmodified_stat("attack"), healthy, "a critical hit is free of it")


func test_paralysis_quarters_what_a_pokemon_moves_at() -> void:
	var mon: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	var healthy: int = mon.stat("speed")
	mon.status = Gen2Status.PARALYSIS
	assert_eq(mon.stat("speed"), Gen2Status.apply_paralysis(healthy))


func test_a_paralysed_pokemon_loses_the_turn_order_it_had() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
	)
	assert_eq(_first(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)["side"], Gen2Battle.PLAYER)

	battle.player.status = Gen2Status.PARALYSIS
	assert_eq(
		_first(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)["side"], Gen2Battle.ENEMY,
		"110 Speed quartered is under Charmander's 65"
	)


func test_a_sleeping_pokemon_does_not_move() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = 3
	var events: Array = battle.take_turn(0, 0)
	var stopped: Dictionary = _first(events, Gen2Battle.CANNOT_MOVE)
	assert_eq(int(stopped["side"]), Gen2Battle.PLAYER)
	assert_eq(stopped["reason"], &"sleep")
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1, "only the enemy moved")


func test_waking_up_does_not_cost_the_turn() -> void:
	# Generation 2's rule and not Generation 1's: the counter runs out, the
	# Pokémon is told it woke, and it attacks in the same breath.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = 1
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.WOKE_UP).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.CANNOT_MOVE).size(), 0)
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 2, "both of them moved")
	assert_eq(battle.player.status, Gen2Status.NONE)


func test_a_frozen_pokemon_does_not_move() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = Gen2Status.FREEZE
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_first(events, Gen2Battle.CANNOT_MOVE)["reason"], &"freeze")
	assert_eq(battle.player.status, Gen2Status.FREEZE, "and stays frozen")


func test_flame_wheel_is_used_through_a_freeze_and_thaws_it() -> void:
	# The only two moves in the game that do, and the reason they are named by
	# number rather than by effect: nothing about their effect says it.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.FLAME_WHEEL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = Gen2Status.FREEZE
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.THAWED).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.CANNOT_MOVE).size(), 0)
	assert_eq(battle.player.status, Gen2Status.NONE)


func test_a_burn_takes_an_eighth_at_the_end_of_the_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = Gen2Status.BURN
	var before: int = battle.player.hp
	var hurt: Dictionary = _first(battle.take_turn(0, 0), Gen2Battle.HURT_BY_STATUS)
	assert_eq(hurt["name"], &"burn")
	assert_eq(int(hurt["amount"]), Gen2Status.residual_damage(battle.player.max_hp()))
	assert_lt(battle.player.hp, before)


func test_a_poison_can_be_the_thing_that_faints_a_pokemon() -> void:
	# The enemy growls rather than attacking, so that the only thing that can put
	# the player down is the poison.
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.MAGCARGO, 50, [Fixture.GROWL])]
	)
	battle.player.status = Gen2Status.POISON
	battle.player.hp = 1
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_STATUS).size(), 1)
	assert_true(battle.player.is_fainted())
	assert_eq(_of_type(events, Gen2Battle.FAINTED).size(), 1)
	assert_true(battle.must_replace(Gen2Battle.PLAYER))


func test_a_pokemon_that_has_already_fainted_is_not_burned_further() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 5, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 5, [Fixture.TACKLE])],
		[_mon(Fixture.MAGCARGO, 50, [Fixture.SLASH])]
	)
	battle.player.status = Gen2Status.BURN
	battle.player.hp = 1
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_STATUS).size(), 0)


func test_a_status_move_puts_its_status_on() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SLEEP_POWDER]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
	)
	var inflicted: Dictionary = _first(battle.take_turn(0, 0), Gen2Battle.STATUS_INFLICTED)
	assert_eq(inflicted["name"], &"sleep")
	assert_true(Gen2Status.is_asleep(battle.enemy.status))


func test_one_status_at_a_time() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SLEEP_POWDER]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
	)
	battle.enemy.status = Gen2Status.BURN
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.STATUS_INFLICTED).size(), 0)
	assert_eq(battle.enemy.status, Gen2Status.BURN, "the burn is not replaced")


func test_a_type_that_cannot_be_touched_cannot_be_paralysed_either() -> void:
	# Thunder Wave against a Ground type. A status move is stopped by an immunity
	# exactly as an attack is, and it says so rather than saying it missed.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDER_WAVE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.NO_EFFECT).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.STATUS_INFLICTED).size(), 0)
	assert_eq(battle.enemy.status, Gen2Status.NONE)


func test_a_secondary_effect_that_comes_up_leaves_its_status_behind() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.EMBER_BURNS]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.HIT).size(), 2, "both of them attacked")
	assert_true(Gen2Status.has(battle.enemy.status, Gen2Status.BURN))


func test_a_secondary_effect_that_does_not_come_up_still_does_its_damage() -> void:
	# The roll sits between the hit and the status, so a failed one costs the
	# status and nothing else.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.NEVER_BURNS]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_gt(int(_first(events, Gen2Battle.HIT)["amount"]), 0)
	assert_eq(battle.enemy.status, Gen2Status.NONE)


func test_a_stat_drop_actually_bends_the_stat_the_damage_formula_reads() -> void:
	# Not just an event: the stage has to reach Gen2BattleMon.stat() itself, which
	# is what a battle asserted only on the event log would miss.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var before: int = battle.player.stat("attack")
	battle.take_turn(0, 0)
	assert_lt(battle.player.stat("attack"), before)


func test_ancientpower_raises_the_users_stats_as_one_event() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.ANCIENTPOWER]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(battle.player.stage("attack"), 1)
	assert_eq(battle.player.stage("speed"), 1)
	assert_eq(_of_type(events, Gen2Battle.STAT_CHANGED).size(), 1, "one event for all five")


func test_a_secondary_stat_drop_that_never_rolls_still_deals_its_damage() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PSYCHIC_NEVER]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_gt(int(_first(events, Gen2Battle.HIT)["amount"]), 0)
	assert_eq(battle.enemy.stage("sp_defense"), 0)


func test_a_status_move_that_cannot_rise_further_says_so() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SWORDS_DANCE]),
		_mon(Fixture.MAGCARGO, 50, [Fixture.TACKLE])
	)
	battle.player.change_stage("attack", Gen2Stats.MAX_STAGE)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.STAT_CHANGED).size(), 0)
	assert_eq(_of_type(events, Gen2Battle.STAT_CHANGE_FAILED).size(), 1)


func test_a_flinch_from_the_faster_side_costs_the_slower_side_its_turn() -> void:
	# Pikachu moves first and flinches Geodude with a roll that cannot fail;
	# Geodude's own move never happens this turn.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.ROLLING_KICK_ALWAYS]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1, "only Pikachu got to move")
	var stopped: Dictionary = _first(events, Gen2Battle.CANNOT_MOVE)
	assert_eq(int(stopped["side"]), Gen2Battle.ENEMY)
	assert_eq(stopped["reason"], &"flinch")
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.FLINCHED), "cleared behind it")


func test_a_flinch_that_never_rolls_leaves_the_slower_side_free_to_move() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.ROLLING_KICK_NEVER]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 2)
	assert_eq(_of_type(events, Gen2Battle.CANNOT_MOVE).size(), 0)


func test_a_status_move_confuses_rather_than_touching_the_status_byte() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SUPERSONIC]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.CONFUSED))
	assert_eq(battle.enemy.status, Gen2Status.NONE, "confusion is not a status")
	assert_eq(_of_type(events, Gen2Battle.CONFUSE_INFLICTED).size(), 1)


func test_a_confused_pokemon_that_hits_itself_never_lands_its_own_move() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.substatus |= Gen2Substatus.CONFUSED
	battle.player.confusion_turns = 3
	var before: int = battle.player.hp
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.HURT_ITSELF).size(), 1)
	assert_lt(battle.player.hp, before)
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1, "only the enemy's own move")


func test_a_pokemon_confused_and_paralysed_can_still_be_stopped_by_either() -> void:
	# The two live on different bytes and are asked about independently, so a
	# Pokémon can carry both, unlike two entries on the status byte itself.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = Gen2Status.PARALYSIS
	battle.player.substatus |= Gen2Substatus.CONFUSED
	battle.player.confusion_turns = 3
	assert_true(Gen2Status.has(battle.player.status, Gen2Status.PARALYSIS))
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CONFUSED))


func test_hyper_beam_locks_the_user_out_the_turn_after_it_connects() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.HYPER_BEAM]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var first_turn: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(first_turn, Gen2Battle.HIT).filter(
		func(event: Dictionary) -> bool: return int(event["side"]) == Gen2Battle.PLAYER
	).size(), 1, "Hyper Beam connected")
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.RECHARGING))

	var second_turn: Array = battle.take_turn(0, 0)
	var stopped: Dictionary = _first(second_turn, Gen2Battle.CANNOT_MOVE)
	assert_eq(int(stopped["side"]), Gen2Battle.PLAYER)
	assert_eq(stopped["reason"], &"recharge")
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.RECHARGING))


func test_switching_out_clears_confusion_and_recharge() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])]
	)
	battle.player.substatus |= Gen2Substatus.CONFUSED | Gen2Substatus.RECHARGING
	battle.player.confusion_turns = 4
	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	var bulbasaur: Gen2BattleMon = battle.player
	assert_eq(bulbasaur.substatus, Gen2Substatus.NONE)
	assert_eq(bulbasaur.confusion_turns, 0)


func test_a_two_turn_move_charges_then_hits_on_the_next() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SOLARBEAM]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var before: int = int(battle.player.pp[0])

	var first_turn: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(first_turn, Gen2Battle.CHARGING_UP).size(), 1)
	assert_eq(_of_type(first_turn, Gen2Battle.HIT).filter(
		func(event: Dictionary) -> bool: return int(event["side"]) == Gen2Battle.PLAYER
	).size(), 0, "nothing lands on the charge turn")
	assert_eq(int(battle.player.pp[0]), before - 1, "the PP goes on the charge turn")
	assert_true(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CHARGING))

	var second_turn: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(second_turn, Gen2Battle.HIT).filter(
		func(event: Dictionary) -> bool: return int(event["side"]) == Gen2Battle.PLAYER
	).size(), 1, "the release turn lands it")
	assert_eq(int(battle.player.pp[0]), before - 1, "nothing more is spent on release")
	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.CHARGING))


func test_a_two_turn_move_ignores_the_slot_it_is_asked_for_on_release() -> void:
	# Whatever slot the caller passes on the release turn, the move that
	# actually happens is the one that was charged, because nothing is chosen
	# on that turn at all on the cartridge.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SOLARBEAM, Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.take_turn(0, 0)
	var second_turn: Array = battle.take_turn(1, 0)
	assert_eq(int(_first(second_turn, Gen2Battle.USED_MOVE)["move"]), Fixture.SOLARBEAM)


func test_skull_bashs_charge_raises_defense_only_once_it_lands() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SKULL_BASH]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.player.stage("defense"), 0, "nothing moves on the charge turn")

	battle.take_turn(0, 0)
	assert_eq(battle.player.stage("defense"), 1)


func test_toxic_takes_more_each_turn_than_an_ordinary_poison_would() -> void:
	# Poison Powder rather than Tackle on the enemy, so nothing but the toxic
	# counter changes what the residual step takes off Geodude.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TOXIC]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var max_hp: int = battle.enemy.max_hp()

	# The turn Toxic lands, the residual step already reads the counter it just
	# started: one sixteenth, and then it ramps to two.
	var first_turn: Array = battle.take_turn(0, 0)
	assert_eq(int(_first(first_turn, Gen2Battle.HURT_BY_STATUS)["amount"]), Gen2Status.toxic_damage(max_hp, 1))
	assert_eq(battle.enemy.toxic_counter, 2)

	var second_turn: Array = battle.take_turn(0, 0)
	assert_eq(int(_first(second_turn, Gen2Battle.HURT_BY_STATUS)["amount"]), Gen2Status.toxic_damage(max_hp, 2))
	assert_eq(battle.enemy.toxic_counter, 3)
	assert_gt(
		int(_first(second_turn, Gen2Battle.HURT_BY_STATUS)["amount"]),
		int(_first(first_turn, Gen2Battle.HURT_BY_STATUS)["amount"]),
		"the counter ramped"
	)


func test_switching_out_a_toxic_pokemon_resets_the_ramp() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])]
	)
	battle.player.status = Gen2Status.POISON
	battle.player.toxic_counter = 4
	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	assert_eq(battle.player.toxic_counter, 0, "cleared with the rest of the volatiles")


func test_haze_wipes_out_both_sides_stages_in_the_middle_of_a_battle() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.HAZE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.change_stage("speed", 2)
	battle.enemy.change_stage("defense", -2)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(battle.player.stage("speed"), 0)
	assert_eq(battle.enemy.stage("defense"), 0, "both sides, not just the user's own")
	assert_eq(_of_type(events, Gen2Battle.STAGES_CLEARED).size(), 1)


func test_belly_drum_costs_the_user_half_its_health_for_a_maxed_attack() -> void:
	# Thunder Wave rather than Tackle or Growl on the enemy: it neither damages
	# Pikachu nor touches the stage Belly Drum is being checked against.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.BELLY_DRUM]),
		_mon(Fixture.GEODUDE, 50, [Fixture.THUNDER_WAVE])
	)
	var max_hp: int = battle.player.max_hp()
	battle.take_turn(0, 0)
	assert_eq(battle.player.stage("attack"), Gen2Stats.MAX_STAGE)
	@warning_ignore("integer_division")
	assert_eq(battle.player.hp, max_hp - max_hp / 2)


func test_psych_up_copies_stat_changes_across_in_a_real_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PSYCH_UP]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.enemy.change_stage("defense", 3)
	battle.take_turn(0, 0)
	assert_eq(battle.player.stage("defense"), 3)


func test_a_multi_hit_move_lands_more_than_once_in_a_real_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.MULTI_HIT_MOVE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.THUNDER_WAVE])
	)
	var events: Array = battle.take_turn(0, 0)
	var hits: int = _of_type(events, Gen2Battle.HIT).size()
	assert_between(hits, 2, 5)
	assert_eq(int(_first(events, Gen2Battle.HIT_TIMES)["times"]), hits)


func test_a_draining_move_heals_the_user_in_a_real_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.DRAIN_MOVE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.THUNDER_WAVE])
	)
	battle.player.hp = 1
	var before: int = battle.player.hp
	battle.take_turn(0, 0)
	assert_gt(battle.player.hp, before)


func test_seismic_toss_deals_the_users_level_however_the_formula_would_read_it() -> void:
	# Geodude's real Defense would cut an ordinary Normal-type hit down hard;
	# Seismic Toss ignores every bit of that and lands exactly 50.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.LEVEL_DAMAGE_MOVE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.THUNDER_WAVE])
	)
	var before: int = battle.enemy.hp
	battle.take_turn(0, 0)
	assert_eq(before - battle.enemy.hp, 50)


func test_guillotine_faints_its_target_outright_in_a_real_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.OHKO_MOVE]),
		_mon(Fixture.GEODUDE, 5, [Fixture.THUNDER_WAVE])
	)
	# A hundred-level gap pushes the boosted accuracy past 255, which never
	# misses, so the outcome needs no seed to be sure of.
	battle.take_turn(0, 0)
	assert_eq(battle.enemy.hp, 0)


## Experience: what a wild faint is worth, a trainer battle's own 1.5x, how it
## splits among participants, and what a level crossed on the way there
## actually teaches. [Gen2Experience]'s own arithmetic is checked in
## [code]test_experience.gd[/code]; what matters here is that [Gen2Battle]
## calls it with the right numbers at the right moment.


func test_a_wild_faint_awards_experience_to_the_winner() -> void:
	# Bulbasaur, base exp 64, at level 5: floor(64*5/7) = 45. A wild battle,
	# [method _battle]'s own shape, never adds the trainer bonus.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	var gained: Dictionary = _first(events, Gen2Battle.EXP_GAINED)
	assert_eq(gained["side"], Gen2Battle.PLAYER)
	assert_eq(gained["index"], 0)
	assert_eq(gained["amount"], 45)

	var stats: Dictionary = _first(events, Gen2Battle.STAT_EXP_GAINED)
	# One participant, so nothing is divided: Bulbasaur's own base stats,
	# plain, with base Sp. Attack (65) filling the shared "special" slot.
	assert_eq(stats["gains"], {"hp": 45, "attack": 49, "defense": 49, "speed": 45, "special": 65})
	assert_eq(battle.player.stat_exp, stats["gains"])


func test_a_trainer_battle_adds_the_experience_bonus() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT])),
		Gen2Party.of(_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])), _rng, true
	)
	var events: Array = battle.take_turn(0, 0)
	# 45 without the bonus (see the wild test above); with it, 45 + floor(45/2).
	assert_eq(_first(events, Gen2Battle.EXP_GAINED)["amount"], 67)


func test_experience_is_not_divided_among_participants_but_stat_experience_is() -> void:
	# Geodude, base exp 86, at level 20: floor(86*20/7) = 245, the same number
	# for every participant. Its own base stats (40/80/100/20/30), split two
	# ways, truncated per stat, are the only thing that divides.
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
		]),
		Gen2Party.create([_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])]), _rng
	)
	battle.send_out(Gen2Battle.PLAYER, 1)
	battle.enemy.hp = 1
	var events: Array = battle.take_turn(0, 0)

	var gains: Array = _of_type(events, Gen2Battle.EXP_GAINED)
	assert_eq(gains.size(), 2, "both the lead and the one switched in")
	for gain: Dictionary in gains:
		assert_eq(gain["amount"], 245, "full, unsplit, for every participant")

	var stat_gains: Array = _of_type(events, Gen2Battle.STAT_EXP_GAINED)
	assert_eq(stat_gains.size(), 2)
	for stat_gain: Dictionary in stat_gains:
		assert_eq(stat_gain["gains"]["attack"], 40, "80 / 2, truncated")
		assert_eq(stat_gain["gains"]["speed"], 10, "20 / 2")


func test_participants_narrow_to_whoever_is_active_once_an_enemy_faints() -> void:
	# Three enemies, one at a time. The lead player Pokémon is credited for the
	# first kill by default; switching in the second one adds it without
	# dropping the lead, since both are still on the field's own roster for
	# that enemy's life; only once experience has actually been given does the
	# set narrow back down to whoever is active, which is what the third kill
	# is here to prove.
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
		]),
		Gen2Party.create([
			_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE]),
			_mon(Fixture.MAGCARGO, 20, [Fixture.TACKLE]),
			_mon(Fixture.BULBASAUR, 20, [Fixture.TACKLE]),
		]),
		_rng
	)

	battle.enemy.hp = 1
	var first_kill: Array = battle.take_turn(0, 0)
	assert_eq(
		_of_type(first_kill, Gen2Battle.EXP_GAINED).map(func(e: Dictionary) -> int: return e["index"]),
		[0], "only the lead fought Geodude"
	)
	battle.send_out(Gen2Battle.ENEMY, 1)
	battle.send_out(Gen2Battle.PLAYER, 1)

	battle.enemy.hp = 1
	var second_kill: Array = battle.take_turn(0, 0)
	assert_eq(
		(_of_type(second_kill, Gen2Battle.EXP_GAINED)
			.map(func(e: Dictionary) -> int: return e["index"]) as Array), [0, 1],
		"index 0 was still active when Magcargo's life began, so it still counts"
	)
	battle.send_out(Gen2Battle.ENEMY, 2)

	battle.enemy.hp = 1
	var third_kill: Array = battle.take_turn(0, 0)
	assert_eq(
		_of_type(third_kill, Gen2Battle.EXP_GAINED).map(func(e: Dictionary) -> int: return e["index"]),
		[1], "index 0 was never sent back in during Bulbasaur's own life"
	)


func test_levelling_up_learns_a_move_into_an_empty_slot_without_asking() -> void:
	# Charmander's own curve reads 135 at level 5. Beating a level 20 Geodude
	# (245 exp) lands at 380, which is level 8: level 6 teaches Ember, and
	# Charmander still has an empty fourth slot for it to go into.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.CHARMANDER, 5, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])
	)
	# The level gap that makes the exp worth crossing three levels also makes
	# Geodude both faster and hard enough hitting to otherwise flatten a level 5
	# Charmander before it gets a turn at all, which is not what this test is
	# about; a healthy Charmander guaranteed to survive one hit is.
	battle.player.hp = battle.player.max_hp() * 10
	battle.enemy.hp = 1
	var events: Array = battle.take_turn(0, 0)

	assert_eq(_of_type(events, Gen2Battle.GREW_LEVEL).size(), 3, "5 to 6, 6 to 7, 7 to 8")
	var learned: Dictionary = _first(events, Gen2Battle.MOVE_LEARNED)
	assert_eq(learned["move"], Fixture.EMBER)
	assert_eq(learned["slot"], 1)
	assert_eq(battle.player.moves, [Fixture.TACKLE, Fixture.EMBER])
	assert_false(battle.must_learn_move(Gen2Battle.PLAYER))


func test_a_full_moveset_is_offered_a_new_move_rather_than_taught_it() -> void:
	# Geodude's own curve also reads 135 at level 5. A level 33 Magcargo (base
	# exp 154) is worth floor(154*33/7) = 726 exactly, landing at 861, which is
	# level 11: level 6 auto-learns Growl into the one empty slot, and level 11's
	# own Slash finds every slot full.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 5, [Fixture.TACKLE, Fixture.EMBER, Fixture.THUNDERBOLT]),
		_mon(Fixture.MAGCARGO, 33, [Fixture.TACKLE])
	)
	battle.enemy.hp = 1
	battle.take_turn(0, 0)

	assert_true(battle.must_learn_move(Gen2Battle.PLAYER))
	var offer: Dictionary = battle.pending_learn(Gen2Battle.PLAYER)
	assert_eq(offer["move"], Fixture.SLASH)
	assert_eq(offer["level"], 11)
	assert_eq(battle.player.moves, [
		Fixture.TACKLE, Fixture.EMBER, Fixture.THUNDERBOLT, Fixture.GROWL,
	], "Growl already took the one empty slot on the way up")


func test_a_battle_refuses_to_continue_until_the_offered_move_is_answered() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 5, [Fixture.TACKLE, Fixture.EMBER, Fixture.THUNDERBOLT]),
		_mon(Fixture.MAGCARGO, 33, [Fixture.TACKLE])
	)
	battle.enemy.hp = 1
	battle.take_turn(0, 0)
	assert_true(battle.must_learn_move(Gen2Battle.PLAYER))

	assert_eq(battle.take_turn(0, 0), [], "a battle cannot go on with an unanswered offer")

	var events: Array = battle.learn_move(Gen2Battle.PLAYER, 1)
	assert_eq(events[0]["forgot"], Fixture.EMBER)
	assert_eq(events[0]["learned"], Fixture.SLASH)
	assert_eq(battle.player.moves[1], Fixture.SLASH)
	assert_false(battle.must_learn_move(Gen2Battle.PLAYER))


## ForgetMove's .hmmove branch redisplays the list instead of answering, so an
## HM slot is not an answer the source can produce. Refusing it has to leave the
## offer standing, or the move would be lost to a press the cartridge ignores.
func test_an_hm_slot_is_refused_and_leaves_the_offer_pending() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 5, [Fixture.TACKLE, Fixture.EMBER, Fixture.THUNDERBOLT]),
		_mon(Fixture.MAGCARGO, 33, [Fixture.TACKLE])
	)
	battle.enemy.hp = 1
	battle.take_turn(0, 0)
	assert_true(battle.must_learn_move(Gen2Battle.PLAYER))
	# Slot 2 becomes SURF, HM03, which ForgetMove refuses to give up.
	battle.player.moves[2] = 0x39
	var before: Array = battle.player.moves.duplicate()

	assert_eq(battle.learn_move(Gen2Battle.PLAYER, 2), [])
	assert_eq(battle.player.moves, before, "nothing is overwritten")
	assert_true(battle.must_learn_move(Gen2Battle.PLAYER), "the offer still stands")

	## An ordinary slot still answers it afterwards.
	assert_eq(battle.learn_move(Gen2Battle.PLAYER, 1).size(), 1)
	assert_false(battle.must_learn_move(Gen2Battle.PLAYER))


## An out-of-range slot is not an answer either, so it must not swallow the
## offer on its way to refusing.
func test_an_out_of_range_slot_leaves_the_offer_pending() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 5, [Fixture.TACKLE, Fixture.EMBER, Fixture.THUNDERBOLT]),
		_mon(Fixture.MAGCARGO, 33, [Fixture.TACKLE])
	)
	battle.enemy.hp = 1
	battle.take_turn(0, 0)

	assert_eq(battle.learn_move(Gen2Battle.PLAYER, 9), [])
	assert_eq(battle.learn_move(Gen2Battle.PLAYER, -1), [])
	assert_true(battle.must_learn_move(Gen2Battle.PLAYER))


## LearnMove clears a Disable naming the move that just went (its wDisabledMove
## check, in battle only). Disable is a slot here and the new move takes the
## forgotten one's slot, so the test is slot equality.
func test_forgetting_the_disabled_move_clears_the_disable() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 5, [Fixture.TACKLE, Fixture.EMBER, Fixture.THUNDERBOLT]),
		_mon(Fixture.MAGCARGO, 33, [Fixture.TACKLE])
	)
	battle.enemy.hp = 1
	battle.take_turn(0, 0)
	battle.player.disabled_slot = 1
	battle.player.disable_turns = 4

	battle.learn_move(Gen2Battle.PLAYER, 1)

	assert_eq(battle.player.disabled_slot, -1)
	assert_eq(battle.player.disable_turns, 0)
	assert_true(battle.player.can_use(1), "the slot is usable again")


## A different slot leaves the Disable where it was: the cartridge compares the
## forgotten move against wDisabledMove rather than clearing unconditionally.
func test_forgetting_another_move_leaves_the_disable_alone() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 5, [Fixture.TACKLE, Fixture.EMBER, Fixture.THUNDERBOLT]),
		_mon(Fixture.MAGCARGO, 33, [Fixture.TACKLE])
	)
	battle.enemy.hp = 1
	battle.take_turn(0, 0)
	battle.player.disabled_slot = 0
	battle.player.disable_turns = 4

	battle.learn_move(Gen2Battle.PLAYER, 1)

	assert_eq(battle.player.disabled_slot, 0)
	assert_eq(battle.player.disable_turns, 4)


func test_declining_the_offered_move_keeps_the_four_already_known() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 5, [Fixture.TACKLE, Fixture.EMBER, Fixture.THUNDERBOLT]),
		_mon(Fixture.MAGCARGO, 33, [Fixture.TACKLE])
	)
	battle.enemy.hp = 1
	battle.take_turn(0, 0)
	var before: Array = battle.player.moves.duplicate()

	var events: Array = battle.decline_move(Gen2Battle.PLAYER)

	assert_eq(events[0]["type"], Gen2Battle.MOVE_DECLINED)
	assert_eq(events[0]["move"], Fixture.SLASH)
	assert_eq(battle.player.moves, before)
	assert_false(battle.must_learn_move(Gen2Battle.PLAYER))


func _used_move_by(events: Array, side: int) -> Dictionary:
	for event: Dictionary in events:
		if event["type"] == Gen2Battle.USED_MOVE and int(event["side"]) == side:
			return event
	return {}


## Pikachu outspeeds Geodude, so Encore lands before Geodude acts this turn.
## `CheckOpponentWentFirst` overrides an already-chosen action for the turn it
## lands on as well as later ones; this engine gets that by not committing to a
## move until [method Gen2Battle._act] reaches it, so Geodude's Slash is
## overridden back to Tackle in the very turn Encore lands.
func test_encore_forces_the_targets_last_move_even_the_turn_it_lands() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE, Fixture.ENCORE_MOVE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE, Fixture.SLASH])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.enemy.last_move_used, Fixture.TACKLE)

	var events: Array = battle.take_turn(1, 1)
	assert_eq(battle.enemy.encored_slot, 0)
	assert_eq(
		int(_used_move_by(events, Gen2Battle.ENEMY)["move"]), Fixture.TACKLE,
		"forced back to Tackle despite asking for Slash"
	)


func test_encore_keeps_forcing_the_locked_slot_on_a_later_turn_too() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE, Fixture.SLASH])
	)
	battle.enemy.encored_slot = 0
	battle.enemy.encore_turns = 5

	var events: Array = battle.take_turn(0, 1)
	assert_eq(
		int(_used_move_by(events, Gen2Battle.ENEMY)["move"]), Fixture.TACKLE,
		"still locked, whatever slot is asked for"
	)


func test_encore_ends_when_its_own_counter_runs_out() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE, Fixture.SLASH])
	)
	battle.enemy.encored_slot = 0
	battle.enemy.encore_turns = 1

	var events: Array = battle.take_turn(0, 1)
	assert_eq(
		int(_used_move_by(events, Gen2Battle.ENEMY)["move"]), Fixture.TACKLE,
		"still forced for the turn the counter reaches zero on"
	)
	assert_eq(battle.enemy.encored_slot, -1)
	assert_eq(battle.enemy.encore_turns, 0)
	assert_false(_first(events, Gen2Battle.ENCORE_ENDED).is_empty())


func test_encore_ends_early_once_its_own_move_runs_out_of_pp() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE, Fixture.SLASH])
	)
	battle.enemy.encored_slot = 0
	battle.enemy.encore_turns = 5
	battle.enemy.pp[0] = 1

	var events: Array = battle.take_turn(0, 1)
	assert_eq(battle.enemy.pp[0], 0)
	assert_eq(battle.enemy.encored_slot, -1, "ran out of PP mid-encore, not the counter")
	assert_false(_first(events, Gen2Battle.ENCORE_ENDED).is_empty())


## A regression test for a real bug found while writing this: comparing
## [member Gen2Turn.slot] against the disabled slot inside
## [constant Gen2EffectCommands.CHECK_STATUS] fired even when
## [method Gen2BattleMon.can_use] had already rerouted the request to Struggle,
## reading an ordinary Struggle turn as a false "cannot move: disabled". The
## fix compares the move that is actually about to run, by number, instead.
func test_a_disabled_slot_falls_back_to_struggle_rather_than_a_false_cannot_move() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE, Fixture.THUNDERBOLT]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.disabled_slot = 1
	battle.player.disable_turns = 3

	var events: Array = battle.take_turn(1, 0)
	assert_eq(int(_used_move_by(events, Gen2Battle.PLAYER)["move"]), Gen2Damage.STRUGGLE)
	assert_true(_first(events, Gen2Battle.CANNOT_MOVE).is_empty())


func test_disable_wears_off_and_the_slot_becomes_usable_again() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE, Fixture.THUNDERBOLT]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.disabled_slot = 1
	battle.player.disable_turns = 1

	# Ticks down whichever move is actually used this turn: the countdown is
	# unconditional, the same as confusion's own counter.
	var events: Array = battle.take_turn(0, 0)
	assert_eq(battle.player.disabled_slot, -1)
	assert_eq(battle.player.disable_turns, 0)
	assert_false(_first(events, Gen2Battle.DISABLE_ENDED).is_empty())
	assert_true(battle.player.can_use(1))


## Pinned against seed 12345, the same fixed seed [method before_each] already
## sets for every test in this file: a bare coin flip like this one has no
## accuracy field to guarantee it the way a move's own miss chance does, and
## [method test_a_confused_pokemon_that_hits_itself_never_lands_its_own_move]
## already leans on this same seed for the same reason.
func test_attract_can_stop_a_pokemon_moving_on_the_immobilise_roll() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.substatus |= Gen2Substatus.ATTRACTED

	var events: Array = battle.take_turn(0, 0)
	var stopped: Dictionary = _first(events, Gen2Battle.CANNOT_MOVE)
	assert_eq(int(stopped["side"]), Gen2Battle.PLAYER)
	assert_eq(stopped["reason"], &"attract")
	assert_true(_used_move_by(events, Gen2Battle.PLAYER).is_empty())


func test_switching_out_clears_attract_disable_and_encore() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])]
	)
	battle.player.substatus |= Gen2Substatus.ATTRACTED | Gen2Substatus.ENCORED
	battle.player.disabled_slot = 0
	battle.player.disable_turns = 3
	battle.player.encored_slot = 0
	battle.player.encore_turns = 3
	battle.player.last_move_used = Fixture.TACKLE

	var pikachu: Gen2BattleMon = battle.player
	battle.send_out(Gen2Battle.PLAYER, 1)

	assert_eq(pikachu.substatus, Gen2Substatus.NONE)
	assert_eq(pikachu.disabled_slot, -1)
	assert_eq(pikachu.encored_slot, -1)
	assert_eq(pikachu.last_move_used, 0)


## test_damage.gd confirms statistically that Focus Energy raises the rate,
## against [method Gen2Damage.critical_level]; this only checks the wiring, that
## a real turn's damage calc reads the flag at all.
## Seed 12, found by search, is one where the same first roll misses Tackle's
## critical chance at the base rate and lands it at the Focus Energy rate: one
## draw read two ways, which proves the flag reaches the roll directly rather
## than statistically.
func test_focus_energy_reaches_the_damage_calc_of_a_real_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.rng.seed = 12
	var without_boost: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, Fixture.TACKLE, _data.move(Fixture.TACKLE), []
	)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, without_boost)
	assert_false(without_boost.critical, "the base rate misses this particular roll")

	battle.rng.seed = 12
	battle.player.substatus |= Gen2Substatus.FOCUS_ENERGY
	var with_boost: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, Fixture.TACKLE, _data.move(Fixture.TACKLE), []
	)
	Gen2EffectCommands.run(Gen2EffectCommands.DAMAGE_CALC, with_boost)
	assert_true(with_boost.critical, "the same roll lands once Focus Energy raises the rate")


## `TryToRunAwayFromBattle`'s speed comparison, which is the whole check when
## the runner is at least as fast: `CompareBytes` then `jr nc, .can_escape`, so a
## tie gets away too.
func test_a_runner_at_least_as_fast_as_the_wild_always_gets_away() -> void:
	for pair: Array in [
		[Fixture.PIKACHU, Fixture.GEODUDE],
		[Fixture.GEODUDE, Fixture.GEODUDE],
	]:
		var battle: Gen2Battle = _battle(
			_mon(int(pair[0]), 50, [Fixture.TACKLE]),
			_mon(int(pair[1]), 50, [Fixture.TACKLE])
		)

		var attempt: Dictionary = battle.run_odds()

		assert_eq(attempt["outcome"], &"fled", JSON.stringify(attempt))
		assert_eq(attempt["how"], &"speed")


## The odds themselves: `player_speed * 32 / ((enemy_speed / 4) & $ff)`, then
## thirty per attempt after the first. The fixture's mon carry maximum DVs, so
## Geodude at level 50 has 40 Speed and Pikachu 110, and the first attempt is
## `1280 / 27`, which is 47.
func test_the_flee_odds_are_the_source_arithmetic_and_rise_per_attempt() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)

	for expected: Array in [[0, 47], [1, 77], [2, 107], [3, 137]]:
		battle.flee_attempts = int(expected[0])

		var attempt: Dictionary = battle.run_odds()

		assert_eq(attempt["outcome"], &"roll", JSON.stringify(attempt))
		assert_eq(int(attempt["odds"]), int(expected[1]), "after %d attempts" % int(expected[0]))
		assert_eq(int(attempt["attempts"]), int(expected[0]) + 1)

	# Once the bonus carries the odds past a byte the roll never happens, which
	# is the source's `jr c, .can_escape` out of the loop.
	battle.flee_attempts = 8

	var certain: Dictionary = battle.run_odds()

	assert_eq(certain["outcome"], &"fled", JSON.stringify(certain))
	assert_eq(certain["how"], &"odds")


## A trainer battle refuses outright and costs nothing: `BattleMenu_Run` prints
## `BattleText_TheresNoEscapeFromTrainerBattle` and jumps back to `BattleMenu`,
## so no turn is spent and the enemy does not move.
func test_a_trainer_battle_refuses_the_run_and_spends_no_turn() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.of(_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])),
		Gen2Party.of(_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])),
		_rng, true
	)
	var before: int = battle.mon(Gen2Battle.PLAYER).hp

	var events: Array = battle.take_actions(
		Gen2Battle.run_away(), Gen2Battle.use_move(0)
	)

	assert_eq(_of_type(events, Gen2Battle.RUN_BLOCKED).size(), 1, JSON.stringify(events))
	assert_eq(events[0]["reason"], &"trainer")
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 0, "the enemy moved anyway")
	assert_eq(battle.mon(Gen2Battle.PLAYER).hp, before)
	assert_false(battle.is_over())
	assert_eq(battle.flee_attempts, 0, "a refusal is not an attempt")


## The four battle types that cannot be escaped and the two that always can
## (`wBattleType`, checked before anything else).
func test_the_battle_type_decides_before_speed_does() -> void:
	for row: Array in [
		[Gen2Battle.BATTLETYPE_TRAP, &"blocked"],
		[Gen2Battle.BATTLETYPE_CELEBI, &"blocked"],
		[Gen2Battle.BATTLETYPE_FORCESHINY, &"blocked"],
		[Gen2Battle.BATTLETYPE_SUICUNE, &"blocked"],
		[Gen2Battle.BATTLETYPE_DEBUG, &"fled"],
		[Gen2Battle.BATTLETYPE_CONTEST, &"fled"],
	]:
		# A matchup the speed check would refuse, so the type is what answered.
		var battle: Gen2Battle = _battle(
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
		)
		battle.battle_type = int(row[0])

		var attempt: Dictionary = battle.run_odds()

		assert_eq(attempt["outcome"], StringName(row[1]), "battle type %d" % int(row[0]))
		assert_eq(attempt["battle_type"], int(row[0]))


## The Smoke Ball is checked before the odds are, so it gets away from anything.
func test_the_smoke_ball_escapes_whatever_the_speeds_are() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	assert_eq(battle.run_odds()["outcome"], &"roll", "the matchup has to be one that rolls")
	battle.mon(Gen2Battle.PLAYER).item = Fixture.SMOKE_BALL

	var attempt: Dictionary = battle.run_odds()

	assert_eq(attempt["outcome"], &"fled", JSON.stringify(attempt))
	assert_eq(attempt["how"], &"item")
	assert_eq(int(attempt["item"]), Fixture.SMOKE_BALL)


## Getting away ends the battle with nobody having won, which is the DRAW the
## cartridge writes into `wBattleResult`.
func test_getting_away_ends_the_battle_with_no_winner() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)

	var events: Array = battle.take_actions(
		Gen2Battle.run_away(), Gen2Battle.use_move(0)
	)

	assert_eq(_of_type(events, Gen2Battle.FLED).size(), 1, JSON.stringify(events))
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 0, "the wild moved anyway")
	assert_true(battle.is_over())
	assert_true(battle.has_fled())
	assert_null(battle.winner())
	assert_false(battle.party(Gen2Battle.PLAYER).is_wiped(), "nobody was beaten")
	assert_false(battle.party(Gen2Battle.ENEMY).is_wiped())


## Choosing FIGHT clears the attempts the runs before it built up, which is
## `BattleMenu_Fight`'s own `xor a` on `wNumFleeAttempts`.
func test_fighting_clears_the_odds_a_run_had_built_up() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	battle.flee_attempts = 4
	assert_eq(int(battle.run_odds()["odds"]), 167)

	var _events: Array = battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_move(0)
	)

	assert_eq(battle.flee_attempts, 0)
	assert_eq(int(battle.run_odds()["odds"]), 47, "the odds went back to a first attempt")


## A roll that comes up short spends the turn: `.cant_escape_2` sets
## `wBattlePlayerAction` to `BATTLEPLAYERACTION_USEITEM`, so the player does
## nothing and the wild attacks anyway. The attempt still counts, which is what
## raises the odds behind the next one.
##
## Seeded rather than arranged, because the roll really is a roll: the odds here
## are 47 out of 256, so most seeds fail and this one is only pinning which.
func test_a_failed_run_costs_the_turn_and_the_wild_still_attacks() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	battle.rng.seed = 12345
	assert_eq(int(battle.run_odds()["odds"]), 47, "the matchup has to be one that rolls")
	var before: int = battle.mon(Gen2Battle.PLAYER).hp

	var events: Array = battle.take_actions(
		Gen2Battle.run_away(), Gen2Battle.use_move(0)
	)

	assert_eq(_of_type(events, Gen2Battle.RUN_FAILED).size(), 1, JSON.stringify(events))
	assert_eq(_of_type(events, Gen2Battle.FLED).size(), 0)
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1, "the wild did not attack")
	assert_lt(battle.mon(Gen2Battle.PLAYER).hp, before, "the turn was not spent")
	assert_false(battle.is_over())
	assert_eq(battle.flee_attempts, 1)
	assert_eq(int(battle.run_odds()["odds"]), 77, "the failed attempt did not raise the odds")
