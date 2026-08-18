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


## Holds the player where it stands, the two ways the cartridge can: Mean Look's
## flag on whoever cast it, or a binding move's counter on whoever it caught.
func _hold(battle: Gen2Battle, held_by: StringName) -> void:
	if held_by == &"mean_look":
		battle.mon(Gen2Battle.ENEMY).substatus |= Gen2Substatus.CANT_RUN
		return
	battle.mon(Gen2Battle.PLAYER).trapped_turns = 3
	battle.mon(Gen2Battle.PLAYER).trapping_move = Fixture.WRAP


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


## `_GetFrontpic` draws Unown by `wUnownLetter`, so the letter travels with the
## send-out the way the level and the HP do. Every other species carries zero.
func test_a_send_out_carries_the_unown_letter_its_dvs_name() -> void:
	var letter_dvs: int = Gen2Stats.pack_dvs(2, 0, 0, 0)
	var battle: Gen2Battle = _party_battle(
		[
			_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
			Gen2BattleMon.create(
				_data, RomLayout.UNOWN_SPECIES, 20, [Fixture.TACKLE], letter_dvs
			),
		],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	var sent: Dictionary = _first(
		battle.send_out(Gen2Battle.PLAYER, 1), Gen2Battle.SENT_OUT
	)
	assert_eq(int(sent["unown_form"]), Gen2Stats.unown_letter(letter_dvs))
	assert_gt(int(sent["unown_form"]), 1, "and it is not form A by default")
	assert_eq(
		int(_first(battle.send_out(Gen2Battle.PLAYER, 0), Gen2Battle.SENT_OUT)["unown_form"]),
		0,
		"anything else is not an Unown"
	)


## `HandlePlayerMonFaint` and `HandleEnemyMonFaint`'s replacement tail, which is
## the only entry point besides a turn that moves a battle on.
func _replacement_battle(player: Array, enemy: Array, trainer: bool) -> Gen2Battle:
	return Gen2Battle.create_parties(
		_data, Gen2Party.create(player), Gen2Party.create(enemy), _rng, trainer
	)


## `AskUseNextPokemon` returns before printing in a trainer battle, since "that
## decision is made for us".
func test_only_a_wild_faint_asks_whether_to_use_the_next_pokemon() -> void:
	var wild: Gen2Battle = _replacement_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])], false
	)
	_faint(wild.player)
	assert_true(wild.asking_use_next())

	var trainer: Gen2Battle = _replacement_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])], true
	)
	_faint(trainer.player)
	assert_false(trainer.asking_use_next())
	assert_eq(trainer.answer_use_next(false), [], "and there is no answer to give")


func test_yes_answers_nothing_and_leaves_the_forced_choice_standing() -> void:
	var battle: Gen2Battle = _replacement_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])], false
	)
	_faint(battle.player)
	assert_eq(battle.answer_use_next(true), [])
	assert_false(battle.asking_use_next(), "the question is asked once")
	assert_true(battle.must_replace(Gen2Battle.PLAYER))


## NO is `jp TryToRunAwayFromBattle`, and a run that gets away ends the battle in
## the same DRAW the battle menu's own run does.
func test_no_runs_and_getting_away_ends_the_battle() -> void:
	var battle: Gen2Battle = _replacement_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 5, [Fixture.TACKLE])], false
	)
	_faint(battle.player)
	var events: Array = battle.answer_use_next(false)
	assert_eq(_first(events, Gen2Battle.FLED)["how"], &"speed")
	assert_eq(_first(events, Gen2Battle.OVER)["winner"], null, "running is a draw")
	assert_true(battle.has_fled())


## `ld hl, wPartyMon1Speed`: the first party slot's, not the Pokémon that
## fainted, whose battle copy the source is done with. Geodude is out and is
## slower than the Magcargo chasing it, so an escape on speed alone can only have
## been measured against the Pikachu in slot one.
func test_the_run_after_a_faint_reads_the_first_party_slots_speed() -> void:
	var battle: Gen2Battle = _replacement_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.MAGCARGO, 50, [Fixture.TACKLE])], false
	)
	battle.send_out(Gen2Battle.PLAYER, 1)
	assert_lt(battle.player.stat("speed"), battle.mon(Gen2Battle.ENEMY).stat("speed"))
	assert_gt(
		int(battle.party(Gen2Battle.PLAYER).at(0).stats["speed"]),
		battle.mon(Gen2Battle.ENEMY).stat("speed")
	)

	_faint(battle.player)
	assert_eq(_first(battle.answer_use_next(false), Gen2Battle.FLED)["how"], &"speed")


## A run that does not get away falls through to `ForcePlayerMonChoice` rather
## than asking again.
func test_a_failed_run_is_not_asked_a_second_time() -> void:
	var battle: Gen2Battle = _replacement_battle(
		[_mon(Fixture.PIKACHU, 5, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 5, [Fixture.TACKLE])],
		[_mon(Fixture.MAGCARGO, 50, [Fixture.TACKLE])], false
	)
	battle.battle_type = Gen2Battle.BATTLETYPE_TRAP
	_faint(battle.player)
	var events: Array = battle.answer_use_next(false)
	assert_eq(_first(events, Gen2Battle.RUN_BLOCKED)["reason"], &"battle_type")
	assert_false(battle.has_fled())
	assert_false(battle.asking_use_next())
	assert_true(battle.must_replace(Gen2Battle.PLAYER))


## The row is refused the way the party menu refuses it, so the question stays
## standing rather than being approximated into an answer.
func test_replacing_refuses_a_row_the_party_would_refuse() -> void:
	var battle: Gen2Battle = _replacement_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])], true
	)
	_faint(battle.player)
	assert_eq(battle.replace_fallen(0), [], "the one that just fainted")
	assert_eq(battle.replace_fallen(9), [], "nobody at all")
	assert_true(battle.must_replace(Gen2Battle.PLAYER))

	assert_eq(_first(battle.replace_fallen(1), Gen2Battle.SENT_OUT)["index"], 1)
	assert_false(battle.must_replace(Gen2Battle.PLAYER))


## `FindMonInOTPartyToSwitchIntoBattle` rather than the first standing: Pikachu's
## Thunderbolt is super effective against the Hoothoot out, and Bulbasaur ahead
## of it in the party is not.
func test_a_trainer_replaces_its_own_faint_with_the_ai_pick() -> void:
	var battle: Gen2Battle = _replacement_battle(
		[_mon(Fixture.HOOTHOOT, 20, [Fixture.TACKLE])],
		[
			_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE]),
			_mon(Fixture.BULBASAUR, 20, [Fixture.TACKLE]),
			_mon(Fixture.PIKACHU, 20, [Fixture.THUNDERBOLT]),
		], true
	)
	battle.battle_style_set = true
	_faint(battle.enemy)
	assert_eq(battle.replacement_target(Gen2Battle.ENEMY), 2)
	assert_eq(_first(battle.replace_fallen(), Gen2Battle.SENT_OUT)["index"], 2)
	assert_eq(battle.enemy.species, Fixture.PIKACHU)


## `EnemySwitch` is what a trainer replacing on its own reaches, so SHIFT asks
## the player about a switch here as well. With no turn behind it,
## [method Gen2Battle.answer_switch_offer] finishes on the two entrances.
func test_shift_offers_a_switch_when_a_trainer_replaces_its_own_faint() -> void:
	var battle: Gen2Battle = _replacement_battle(
		[
			_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
			_mon(Fixture.BULBASAUR, 20, [Fixture.TACKLE]),
		],
		[
			_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE]),
			_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE]),
		], true
	)
	_faint(battle.enemy)
	var offered: Array = battle.replace_fallen()
	assert_eq(_first(offered, Gen2Battle.SWITCH_OFFERED)["index"], 1)
	assert_eq(battle.awaiting_switch_offer(), 1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 0, "nobody is out yet")

	var answered: Array = battle.answer_switch_offer(1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 1, "the player changed too")
	assert_eq(_of_type(answered, Gen2Battle.OVER).size(), 0, "no turn was behind it")


## `DoubleSwitch`: the player enters first and the trainer follows through
## `EnemySwitch_SetMode`, which asks nothing even in SHIFT.
func test_a_double_faint_sends_the_player_in_first_and_offers_nothing() -> void:
	var battle: Gen2Battle = _replacement_battle(
		[
			_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
			_mon(Fixture.BULBASAUR, 20, [Fixture.TACKLE]),
		],
		[
			_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE]),
			_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE]),
		], true
	)
	_faint(battle.player)
	_faint(battle.enemy)

	var sent: Array = _of_type(battle.replace_fallen(1), Gen2Battle.SENT_OUT)
	assert_eq(sent.size(), 2)
	assert_eq(int(sent[0]["side"]), Gen2Battle.PLAYER)
	assert_eq(int(sent[1]["side"]), Gen2Battle.ENEMY)
	assert_eq(battle.awaiting_switch_offer(), -1, "no offer was raised")
	assert_false(battle.awaiting_replacement())


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
	# Whether it is still frozen afterwards is `HandleDefrost`'s roll and belongs
	# to the thaw tests below, not to this one.


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


func test_a_freeze_thaws_on_its_own_before_long() -> void:
	# `HandleDefrost` is the whole of what makes a Generation 2 freeze temporary.
	# Bounded rather than seeded: 25 in 256 a turn means holding out for 300 turns
	# is a one-in-ten-trillion event, so this cannot go the other way by luck.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	battle.player.status = Gen2Status.FREEZE
	var thawed_on: int = -1
	for turn: int in 300:
		var events: Array = battle.take_turn(0, 0)
		if not _of_type(events, Gen2Battle.THAWED).is_empty():
			thawed_on = turn
			break
	assert_gt(thawed_on, -1, "a freeze does not last forever")
	assert_eq(battle.player.status, Gen2Status.NONE)


func test_a_pokemon_frozen_this_turn_does_not_thaw_on_the_same_turn() -> void:
	# `wEnemyJustGotFrozen`, which `HandleDefrost` reads before it rolls. No seed
	# is involved: the flag refuses before `BattleRandom` is reached at all.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.ICE_BEAM_ALWAYS_FREEZES]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(battle.enemy.status, Gen2Status.FREEZE, "the freeze landed")
	assert_eq(_of_type(events, Gen2Battle.THAWED).size(), 0)


func test_the_just_frozen_flag_only_holds_for_the_turn_that_set_it() -> void:
	# Slot 1 is Growl, so the turns after the freeze do no damage: the target has
	# to survive long enough to be given the chance to thaw.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.ICE_BEAM_ALWAYS_FREEZES, Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.enemy.status, Gen2Status.FREEZE)
	var thawed_on: int = -1
	for turn: int in 300:
		if not _of_type(battle.take_turn(1, 0), Gen2Battle.THAWED).is_empty():
			thawed_on = turn
			break
	assert_gt(thawed_on, -1, "the flag is cleared at the top of every turn")


func test_a_turn_with_nobody_frozen_rolls_nothing_for_thawing() -> void:
	# `bit FRZ` comes before `BattleRandom`, so adding the defrost tick did not
	# move any other roll in the game along.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	battle.rng.seed = 99
	battle.take_turn(0, 0)
	var with_no_freeze: int = battle.rng.state

	var again: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	again.rng.seed = 99
	again.take_turn(0, 0)
	assert_eq(int(again.rng.state), with_no_freeze)


func test_a_fire_type_is_not_burned_by_a_fire_move() -> void:
	# `CheckMoveTypeMatchesTarget`, which compares the move's type against the
	# target's two. Charmander is Fire/Fire and Ember is Fire.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.EMBER_BURNS]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.enemy.status, Gen2Status.NONE)


func test_a_normal_move_burns_anything_it_hits() -> void:
	# `.normal` returns non-zero without comparing anything, which is Tri
	# Attack's case: a Normal-type move matches no target type at all.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.BODY_SLAM_ALWAYS_PARALYZES]),
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.enemy.status, Gen2Status.PARALYSIS, "an Electric-type is still paralysed")


func test_a_poison_type_is_not_poisoned_by_anything() -> void:
	# `CheckIfTargetIsPoisonType` compares the target against POISON itself
	# rather than against the move's type, so it refuses whatever the move is.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SLUDGE_BOMB_ALWAYS_POISONS]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.GROWL])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.enemy.status, Gen2Status.NONE, "Bulbasaur is Grass/Poison")


func test_a_non_poison_type_is_still_poisoned() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SLUDGE_BOMB_ALWAYS_POISONS]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.enemy.status, Gen2Status.POISON)


func test_a_poison_type_is_not_badly_poisoned_either() -> void:
	# Toxic is `BattleCommand_Poison` with a different tail, so the same
	# `CheckIfTargetIsPoisonType` refuses it.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TOXIC]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.GROWL])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.enemy.status, Gen2Status.NONE)
	assert_eq(battle.enemy.toxic_counter, 0)


func test_a_burn_move_defrosts_a_frozen_target_instead_of_burning_it() -> void:
	# `BattleCommand_BurnTarget`'s `jp nz, Defrost`: the target already carries a
	# status, so the burn cannot land, and a freeze is cleared rather than kept.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.EMBER_BURNS]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	battle.enemy.status = Gen2Status.FREEZE
	var events: Array = battle.take_turn(0, 0)
	var thawed: Dictionary = _first(events, Gen2Battle.THAWED)
	assert_false(thawed.is_empty(), "the target was defrosted")
	assert_eq(int(thawed["side"]), Gen2Battle.ENEMY, "the target, not the user")
	assert_eq(battle.enemy.status, Gen2Status.NONE, "and not burned either")


func test_a_burn_move_leaves_any_other_status_on_the_target() -> void:
	# `Defrost`'s own `and 1 << FRZ / ret z`: only a freeze is cleared.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.EMBER_BURNS]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	battle.enemy.status = Gen2Status.PARALYSIS
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.THAWED).size(), 0)
	assert_eq(battle.enemy.status, Gen2Status.PARALYSIS)


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


## A host that decided a battle without playing it, which is what the story walk
## does: every enemy is paid for in party order, at the same figures a fought
## faint would have paid, and the party ends up levelled rather than merely told
## it won.
func test_a_won_battle_can_be_paid_for_without_being_fought() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 5, [Fixture.THUNDERBOLT])),
		Gen2Party.create([
			_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE]),
			_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE]),
		]), _rng, true
	)
	var before: int = battle.player.level
	var events: Array = battle.award_win_experience()

	var gains: Array = _of_type(events, Gen2Battle.EXP_GAINED)
	assert_eq(gains.size(), 2, "one for each of the trainer's Pokémon")
	for gain: Dictionary in gains:
		assert_eq(gain["amount"], 67, "the same 45 plus the trainer bonus a fought faint pays")
	assert_true(battle.party(Gen2Battle.ENEMY).is_wiped(), "the whole party is beaten")
	assert_gt(battle.player.level, before, "134 experience is more than one level at five")


## Base experience is the seventh byte of the same block as the base stats, and
## `.EvenlyDivideExpAmongParticipants` divides the whole block in one loop before
## `GiveExperiencePoints` reads any of it. So the award divides too, and it
## divides at the base-exp byte rather than at the finished figure.
func test_experience_and_stat_experience_both_divide_among_participants() -> void:
	# Geodude, base exp 86, at level 20, two participants: the byte becomes
	# floor(86/2) = 43, and the award is floor(43*20/7) = 122. Its own base stats
	# (40/80/100/20/30) are split the same two ways in the same loop.
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
		assert_eq(gain["amount"], 122, "half the base exp byte, then the formula")
		assert_false(bool(gain["exp_share"]), "earned by fighting, not by holding")

	var stat_gains: Array = _of_type(events, Gen2Battle.STAT_EXP_GAINED)
	assert_eq(stat_gains.size(), 2)
	for stat_gain: Dictionary in stat_gains:
		assert_eq(stat_gain["gains"]["attack"], 40, "80 / 2, truncated")
		assert_eq(stat_gain["gains"]["speed"], 10, "20 / 2")


## The rules a battle was built with are the ones it keeps and the ones the
## formula's statics read, so a test or a tool cannot resolve half a fight under
## one set and half under another.
func test_a_battle_installs_the_rules_it_was_created_with() -> void:
	var rules := Gen2Rules.new()
	rules.set_flag(&"metal_powder_overflow", false)
	var battle: Gen2Battle = Gen2Battle.create(
		_data, _mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE]), _rng, rules
	)
	assert_same(battle.rules, rules)
	assert_false(Gen2Rules.hardware(&"metal_powder_overflow"))

	Gen2Rules.install(null)
	var plain: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])
	)
	assert_not_null(plain.rules, "a battle with no rules of its own plays the installed set")
	assert_true(Gen2Rules.hardware(&"metal_powder_overflow"))


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
## a real turn's `critical` step reads the flag at all.
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
	Gen2EffectCommands.run(Gen2EffectCommands.CRITICAL, without_boost)
	assert_false(without_boost.critical, "the base rate misses this particular roll")

	battle.rng.seed = 12
	battle.player.substatus |= Gen2Substatus.FOCUS_ENERGY
	var with_boost: Gen2Turn = Gen2Turn.create(
		battle, Gen2Battle.PLAYER, 0, Fixture.TACKLE, _data.move(Fixture.TACKLE), []
	)
	Gen2EffectCommands.run(Gen2EffectCommands.CRITICAL, with_boost)
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


## `.cant_escape` prints and returns without writing
## `BATTLEPLAYERACTION_USEITEM`, so `BattleMenu_Run` falls through to
## `jp BattleMenu`: unlike the roll that comes up short, neither trapping check
## spends the turn or counts as an attempt.
func test_a_trapped_runner_is_refused_without_spending_the_turn() -> void:
	for held_by: StringName in [&"mean_look", &"wrap"]:
		# A matchup that would otherwise get away on speed alone, so the refusal
		# is the only thing that can be answering.
		var battle: Gen2Battle = _battle(
			_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
		)
		_hold(battle, held_by)
		var before: int = battle.mon(Gen2Battle.PLAYER).hp

		var events: Array = battle.take_actions(
			Gen2Battle.run_away(), Gen2Battle.use_move(0)
		)

		assert_eq(_of_type(events, Gen2Battle.RUN_BLOCKED).size(), 1, JSON.stringify(events))
		assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 0, "the wild attacked anyway")
		assert_eq(battle.mon(Gen2Battle.PLAYER).hp, before)
		assert_eq(battle.flee_attempts, 0)
		assert_false(battle.has_fled())


## Both checks sit ahead of the Smoke Ball in `TryToRunAwayFromBattle`, so
## holding one is no way out of either.
func test_the_smoke_ball_does_not_carry_a_trapped_runner_out() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	battle.mon(Gen2Battle.PLAYER).item = Fixture.SMOKE_BALL
	assert_eq(battle.run_odds()["how"], &"item", "the item has to be the answer without a trap")

	battle.mon(Gen2Battle.PLAYER).trapped_turns = 3

	var attempt: Dictionary = battle.run_odds()

	assert_eq(attempt["outcome"], &"blocked", JSON.stringify(attempt))
	assert_eq(attempt["reason"], &"trapped")


## `TryPlayerSwitch` refuses at menu time and jumps back to
## `BattleMenuPKMN_Loop`, so the refusal is free: no switch, no enemy move.
func test_a_trapped_pokemon_cannot_be_recalled() -> void:
	for held_by: StringName in [&"mean_look", &"wrap"]:
		var battle: Gen2Battle = _party_battle(
			[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
			[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
		)
		_hold(battle, held_by)
		var before: int = battle.mon(Gen2Battle.PLAYER).hp

		var events: Array = battle.take_actions(
			Gen2Battle.switch_to(1), Gen2Battle.use_move(0)
		)

		assert_eq(_of_type(events, Gen2Battle.SWITCH_BLOCKED).size(), 1, JSON.stringify(events))
		assert_eq(_of_type(events, Gen2Battle.SENT_OUT).size(), 0)
		assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 0, "the enemy moved anyway")
		assert_eq(battle.party(Gen2Battle.PLAYER).active, 0)
		assert_eq(battle.mon(Gen2Battle.PLAYER).hp, before)


## `AI_Switch` makes neither check, so the asymmetry is the cartridge's: only the
## player is held.
func test_the_enemy_switches_out_of_a_trap_the_player_could_not_leave() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])]
	)
	battle.mon(Gen2Battle.ENEMY).trapped_turns = 3
	battle.mon(Gen2Battle.PLAYER).substatus |= Gen2Substatus.CANT_RUN

	var events: Array = battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.switch_to(1)
	)

	assert_eq(_of_type(events, Gen2Battle.SENT_OUT).size(), 1, JSON.stringify(events))
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)


## `HandleWrap` decrements before it looks, so the turn the counter reaches zero
## is the release and costs nothing. Three to six turns of counter are two to
## five turns of damage, which is what the source comments.
func test_being_bound_costs_a_sixteenth_a_turn_until_the_release() -> void:
	for counter: int in range(
		Gen2Substatus.MIN_TRAP_TURNS, Gen2Substatus.MAX_TRAP_TURNS + 1
	):
		# Growl both sides, so nothing but the binding takes any health and the
		# battle cannot end partway through the count.
		var battle: Gen2Battle = _battle(
			_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
			_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
		)
		var bound: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
		var expected: int = Gen2Substatus.trap_damage(bound.max_hp())
		bound.trapped_turns = counter
		bound.trapping_move = Fixture.WRAP

		var hurt: int = 0
		var released: int = 0
		for _turn: int in counter:
			var events: Array = battle.take_actions(
				Gen2Battle.use_move(0), Gen2Battle.use_move(0)
			)
			for event: Dictionary in _of_type(events, Gen2Battle.HURT_BY_TRAP):
				if int(event["side"]) == Gen2Battle.PLAYER:
					hurt += 1
					assert_eq(int(event["amount"]), expected)
					assert_eq(int(event["move"]), Fixture.WRAP)
			for event: Dictionary in _of_type(events, Gen2Battle.RELEASED_FROM_TRAP):
				if int(event["side"]) == Gen2Battle.PLAYER:
					released += 1
					assert_eq(int(event["move"]), Fixture.WRAP)

		assert_eq(hurt, counter - 1, "a counter of %d is %d turns of damage" % [
			counter, counter - 1
		])
		assert_eq(released, 1, "a counter of %d was never released" % counter)
		assert_eq(bound.trapped_turns, 0)
		assert_eq(bound.trapping_move, 0)


## `HandleBetweenTurnEffects` runs wrap after the poison and burn each side took
## inside its own move, and `HandleEncore` after all of it.
func test_the_wrap_tick_sits_between_the_status_damage_and_encore() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var bound: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	bound.status = Gen2Status.POISON
	bound.trapped_turns = 3
	bound.trapping_move = Fixture.WRAP
	bound.encored_slot = 0
	bound.encore_turns = 1
	bound.substatus |= Gen2Substatus.ENCORED

	var events: Array = battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_move(0)
	)
	var types: Array = events.map(func(event: Dictionary) -> StringName: return event["type"])

	assert_lt(
		types.find(Gen2Battle.HURT_BY_STATUS), types.find(Gen2Battle.HURT_BY_TRAP)
	)
	assert_lt(
		types.find(Gen2Battle.HURT_BY_TRAP), types.find(Gen2Battle.ENCORE_ENDED)
	)


## `HandleWrap` is `SetPlayerTurn` then `SetEnemyTurn` outside a link battle, so
## it does not follow the order the two sides moved in the way `ResidualDamage`,
## which runs inside a turn, does.
func test_the_wrap_tick_is_always_the_player_first() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		battle.mon(side).trapped_turns = 3
		battle.mon(side).trapping_move = Fixture.WRAP

	var events: Array = battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_move(0)
	)
	var hurt: Array = _of_type(events, Gen2Battle.HURT_BY_TRAP)

	assert_eq(_first(events, Gen2Battle.USED_MOVE)["side"], Gen2Battle.ENEMY, "the enemy is faster")
	assert_eq(hurt.size(), 2)
	assert_eq(int(hurt[0]["side"]), Gen2Battle.PLAYER)
	assert_eq(int(hurt[1]["side"]), Gen2Battle.ENEMY)


## `NewBattleMonStatus` and `NewEnemyMonStatus` each clear both wrap counters and
## the opponent's `SUBSTATUS_CANT_RUN`, so a send-out by either side ends the
## whole relationship rather than only its own half.
func test_a_send_out_frees_both_sides_of_a_trap() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
	)
	battle.mon(Gen2Battle.ENEMY).trapped_turns = 3
	battle.mon(Gen2Battle.ENEMY).trapping_move = Fixture.WRAP
	battle.mon(Gen2Battle.ENEMY).substatus |= Gen2Substatus.CANT_RUN
	# The player is the one leaving, and the enemy's half of the state is the
	# half [method Gen2BattleMon.reset_volatile] cannot reach.
	battle.mon(Gen2Battle.PLAYER).substatus |= Gen2Substatus.CANT_RUN

	battle.send_out(Gen2Battle.PLAYER, 1)

	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		assert_eq(battle.mon(side).trapped_turns, 0)
		assert_eq(battle.mon(side).trapping_move, 0)
		assert_false(Gen2Substatus.has(battle.mon(side).substatus, Gen2Substatus.CANT_RUN))


## Being bound stops a Pokémon leaving, not moving: `HandleWrap` takes the
## sixteenth and nothing in `CheckStatus` reads the counter at all.
func test_being_bound_does_not_stop_the_bound_pokemon_moving() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.mon(Gen2Battle.PLAYER).trapped_turns = 3
	battle.mon(Gen2Battle.PLAYER).trapping_move = Fixture.WRAP

	var events: Array = battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_move(0)
	)

	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 2, JSON.stringify(events))


## A Pokémon that goes down to the binding faints there, the same shape a burn
## or a poison already has.
func test_a_pokemon_can_faint_to_the_binding() -> void:
	# Growl both sides, so the binding is the only thing that can take the last
	# point of health.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var bound: Gen2BattleMon = battle.mon(Gen2Battle.ENEMY)
	bound.hp = 1
	bound.trapped_turns = 3
	bound.trapping_move = Fixture.WRAP

	var events: Array = battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_move(0)
	)

	assert_false(_first(events, Gen2Battle.HURT_BY_TRAP).is_empty(), JSON.stringify(events))
	assert_true(bound.is_fainted())
	assert_true(battle.is_over())


## `HandleWeather` decrements before it prints, so a count of five is four turns
## of weather and a fifth that ends it, the turn the move was used counting as
## the first of them.
func test_weather_lasts_five_turns_counting_the_one_that_set_it() -> void:
	# Rain Dance in the first slot and Growl in the second, because a second Rain
	# Dance would restart the count rather than let it run down.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.RAIN_DANCE, Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)

	var setting: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_false(_first(setting, Gen2Battle.WEATHER_STARTED).is_empty(), JSON.stringify(setting))
	assert_eq(_of_type(setting, Gen2Battle.WEATHER_CONTINUES).size(), 1, "the setting turn ticks")
	assert_eq(battle.weather_turns, Gen2Weather.TURNS - 1)

	var continued: int = 0
	for _turn: int in 10:
		var events: Array = battle.take_actions(Gen2Battle.use_move(1), Gen2Battle.use_move(0))
		continued += _of_type(events, Gen2Battle.WEATHER_CONTINUES).size()
		if not _first(events, Gen2Battle.WEATHER_ENDED).is_empty():
			break

	assert_eq(continued, Gen2Weather.TURNS - 2, "four turns of rain in all, then the ending")
	assert_eq(battle.weather, Gen2Weather.NONE)
	assert_eq(battle.weather_turns, 0)


## The turn the count reaches zero prints the ending line and nothing else, so a
## Sandstorm's last turn costs no health.
func test_the_turn_a_sandstorm_ends_deals_no_damage() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.weather = Gen2Weather.SANDSTORM
	battle.weather_turns = 1

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_false(_first(events, Gen2Battle.WEATHER_ENDED).is_empty(), JSON.stringify(events))
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_SANDSTORM).size(), 0)


## `.SandstormDamage` exempts Rock, Ground and Steel and nothing else. Flying is
## not among them, and neither is a Pokémon in mid-Fly: only Dig hides from it.
func test_a_sandstorm_takes_an_eighth_from_whoever_it_can_reach() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	battle.weather = Gen2Weather.SANDSTORM
	battle.weather_turns = Gen2Weather.TURNS
	var exposed: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	var expected: int = Gen2Weather.sandstorm_damage(exposed.max_hp())

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var hurt: Array = _of_type(events, Gen2Battle.HURT_BY_SANDSTORM)

	assert_eq(hurt.size(), 1, "the Rock/Ground Geodude was hit too: %s" % JSON.stringify(events))
	assert_eq(int(hurt[0]["side"]), Gen2Battle.PLAYER)
	assert_eq(int(hurt[0]["amount"]), expected)


func test_only_dig_hides_a_pokemon_from_a_sandstorm() -> void:
	for pair: Array in [
		[Gen2Substatus.UNDERGROUND, 0], [Gen2Substatus.FLYING, 1], [Gen2Substatus.NONE, 1],
	]:
		var battle: Gen2Battle = _battle(
			_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
			_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
		)
		battle.weather = Gen2Weather.SANDSTORM
		battle.weather_turns = Gen2Weather.TURNS
		battle.mon(Gen2Battle.PLAYER).substatus |= int(pair[0])

		var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

		assert_eq(
			_of_type(events, Gen2Battle.HURT_BY_SANDSTORM).size(), int(pair[1]),
			"substatus %d" % int(pair[0])
		)


## `HandleBetweenTurnEffects` is future sight, weather, wrap, perish song, then
## the leftovers block, with `HandleEncore` last.
func test_the_weather_tick_sits_between_the_status_damage_and_the_wrap_tick() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.weather = Gen2Weather.SANDSTORM
	battle.weather_turns = Gen2Weather.TURNS
	var caught: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	caught.status = Gen2Status.POISON
	caught.trapped_turns = 3
	caught.trapping_move = Fixture.WRAP

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var types: Array = events.map(func(event: Dictionary) -> StringName: return event["type"])

	assert_lt(types.find(Gen2Battle.HURT_BY_STATUS), types.find(Gen2Battle.WEATHER_CONTINUES))
	assert_lt(types.find(Gen2Battle.WEATHER_CONTINUES), types.find(Gen2Battle.HURT_BY_SANDSTORM))
	assert_lt(types.find(Gen2Battle.HURT_BY_SANDSTORM), types.find(Gen2Battle.HURT_BY_TRAP))


## The same `SetPlayerTurn` then `SetEnemyTurn` the wrap tick follows.
func test_the_sandstorm_hits_the_player_first_whoever_moved_first() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL]),
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL])
	)
	battle.weather = Gen2Weather.SANDSTORM
	battle.weather_turns = Gen2Weather.TURNS
	# Neither of these two is exempt, so both take it: Geodude is the exempt one
	# and it is not in this battle.
	battle.parties[Gen2Battle.PLAYER] = Gen2Party.of(_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL]))

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var hurt: Array = _of_type(events, Gen2Battle.HURT_BY_SANDSTORM)

	assert_eq(_first(events, Gen2Battle.USED_MOVE)["side"], Gen2Battle.ENEMY, "the enemy is faster")
	assert_eq(hurt.size(), 2, JSON.stringify(events))
	assert_eq(int(hurt[0]["side"]), Gen2Battle.PLAYER)
	assert_eq(int(hurt[1]["side"]), Gen2Battle.ENEMY)


func test_a_pokemon_can_faint_to_a_sandstorm() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.weather = Gen2Weather.SANDSTORM
	battle.weather_turns = Gen2Weather.TURNS
	battle.mon(Gen2Battle.ENEMY).hp = 1

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_false(_first(events, Gen2Battle.HURT_BY_SANDSTORM).is_empty(), JSON.stringify(events))
	assert_true(battle.mon(Gen2Battle.ENEMY).is_fainted())
	assert_true(battle.is_over())


## A battle carries its own sky and nothing outside one has weather at all.
func test_a_fresh_battle_has_no_weather() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	assert_eq(battle.weather, Gen2Weather.NONE)
	assert_eq(battle.weather_turns, 0)


## `BattleCommand_DoTurn` counts the turn behind the same charging check that
## decides whether PP is spent, so a two-turn release counts once, on the turn
## the move was chosen, and a switch starts the count again.
func test_a_pokemon_counts_the_turns_it_has_actually_acted_on() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.SOLARBEAM, Fixture.TACKLE]),
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])]
	)
	var acting: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	assert_eq(acting.turns_taken, 0, "nothing has happened yet")

	battle.take_actions(Gen2Battle.use_move(1), Gen2Battle.use_move(0))
	assert_eq(acting.turns_taken, 1)

	# The charge turn counts; the release turn is the same turn continuing.
	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(acting.turns_taken, 2)
	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(acting.turns_taken, 2, "the release spent no turn of its own")

	battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(battle.mon(Gen2Battle.PLAYER).turns_taken, 0, "a fresh Pokémon has acted on none")


## The increment sits ahead of the Struggle check, so a Pokémon with nothing left
## still counts the turns it spends struggling.
func test_struggling_counts_as_a_turn_even_though_it_spends_no_pp() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var struggling: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	struggling.pp[0] = 0

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_eq(battle.move_for(Gen2Battle.PLAYER, 0), Gen2Damage.STRUGGLE)
	assert_eq(struggling.turns_taken, 1)


## `DetermineMoveOrder`'s `.equal_priority` block: a Quick Claw is rolled after
## priority and before speed, so it turns over a matchup the speeds had already
## settled.
func test_a_quick_claw_can_beat_a_faster_pokemon_to_the_punch() -> void:
	var claimed: int = 0
	for seed: int in 200:
		var battle: Gen2Battle = _battle(
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
		)
		battle.rng.seed = seed
		battle.mon(Gen2Battle.PLAYER).item = Fixture.QUICK_CLAW

		if battle.order({Gen2Battle.PLAYER: Fixture.TACKLE, Gen2Battle.ENEMY: Fixture.TACKLE})[0] \
			== Gen2Battle.PLAYER:
			claimed += 1

	assert_between(claimed, 25, 70, "roughly sixty in 256 across two hundred seeds")


## Priority is settled first, so no claw carries a Quick Attack.
func test_a_quick_claw_never_overrides_priority() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	battle.mon(Gen2Battle.PLAYER).item = Fixture.QUICK_CLAW
	for seed: int in 50:
		battle.rng.seed = seed
		# Counter is priority 0 against Tackle's 1, so the player is last however
		# the claw rolls.
		var acting: Array = battle.order({
			Gen2Battle.PLAYER: Fixture.COUNTER, Gen2Battle.ENEMY: Fixture.TACKLE,
		})
		assert_eq(acting[0], Gen2Battle.ENEMY)


## `.both_have_quick_claw` rolls the enemy's first outside a link battle, and the
## player's only after it has come up short.
func test_two_quick_claws_roll_the_enemys_first() -> void:
	var enemy_first: int = 0
	var player_first: int = 0
	for seed: int in 300:
		var battle: Gen2Battle = _battle(
			_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
		)
		battle.rng.seed = seed
		battle.mon(Gen2Battle.PLAYER).item = Fixture.QUICK_CLAW
		battle.mon(Gen2Battle.ENEMY).item = Fixture.QUICK_CLAW

		if battle.order({
			Gen2Battle.PLAYER: Fixture.TACKLE, Gen2Battle.ENEMY: Fixture.TACKLE,
		})[0] == Gen2Battle.ENEMY:
			enemy_first += 1
		else:
			player_first += 1

	# Pikachu is faster, so it leads on speed whenever neither claw fires. The
	# enemy can only lead through its own claw, which is the point.
	assert_gt(enemy_first, 0, "the enemy's claw has to be able to fire")
	assert_gt(player_first, enemy_first, "and it is the rarer of the two")


## With no claw anywhere the order is the speed comparison it always was.
func test_no_quick_claw_leaves_the_order_to_speed() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	for seed: int in 30:
		battle.rng.seed = seed
		assert_eq(
			battle.order({
				Gen2Battle.PLAYER: Fixture.TACKLE, Gen2Battle.ENEMY: Fixture.TACKLE,
			})[0],
			Gen2Battle.ENEMY
		)


## `HandleLeftovers`: a sixteenth back every turn, and nothing on a Pokémon
## already at full health.
func test_leftovers_gives_back_a_sixteenth_a_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var holder: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	holder.item = Fixture.LEFTOVERS
	var expected: int = Gen2HeldItem.leftovers_healing(holder.max_hp())

	var full: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(_of_type(full, Gen2Battle.RECOVERED_WITH_ITEM).size(), 0, "already at full health")

	holder.hp = holder.max_hp() - expected - 5
	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var healed: Dictionary = _first(events, Gen2Battle.RECOVERED_WITH_ITEM)

	assert_false(healed.is_empty(), JSON.stringify(events))
	assert_eq(int(healed["amount"]), expected)
	assert_eq(int(healed["item"]), Fixture.LEFTOVERS, "and it is not spent")
	assert_eq(holder.item, Fixture.LEFTOVERS)


## `HandleHPHealingItem` wants the holder strictly under half, and the berry is
## spent when it fires: `UseOpponentItem` reaches `ConsumeHeldItem`.
func test_a_berry_fires_under_half_health_and_is_spent() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var holder: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	holder.item = Fixture.GOLD_BERRY

	@warning_ignore("integer_division")
	holder.hp = holder.max_hp() / 2
	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(holder.item, Fixture.GOLD_BERRY, "half is not under half")

	holder.hp = 10
	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var used: Dictionary = _first(events, Gen2Battle.RECOVERED_USING_ITEM)

	assert_false(used.is_empty(), JSON.stringify(events))
	assert_eq(int(used["amount"]), 30, "the Gold Berry's own parameter")
	assert_eq(holder.hp, 40)
	assert_eq(holder.item, 0, "spent")


## `HandleMysteryberry` refills the first move that ran out, five points or one
## for Sketch, and spends itself doing it.
func test_mysteryberry_refills_the_first_empty_move() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL, Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var holder: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	holder.item = Fixture.MYSTERYBERRY
	holder.pp[1] = 0

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var restored: Dictionary = _first(events, Gen2Battle.RESTORED_PP)

	assert_false(restored.is_empty(), JSON.stringify(events))
	assert_eq(int(restored["slot"]), 1)
	assert_eq(holder.pp_left(1), Gen2HeldItem.RESTORED_PP)
	assert_eq(holder.item, 0, "spent")


## `UseHeldStatusHealingItem` answers the moment the status lands rather than
## waiting for the end of the turn.
func test_a_status_berry_answers_the_moment_the_status_lands() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDER_WAVE]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	var holder: Gen2BattleMon = battle.mon(Gen2Battle.ENEMY)
	holder.item = Fixture.MIRACLEBERRY

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var types: Array = events.map(func(event: Dictionary) -> StringName: return event["type"])

	assert_eq(holder.status, Gen2Status.NONE)
	assert_eq(holder.item, 0)
	assert_lt(
		types.find(Gen2Battle.STATUS_INFLICTED), types.find(Gen2Battle.RECOVERED_USING_ITEM),
		"the berry answers behind the status, not at the end of the turn"
	)
	# And the enemy still got its move: the berry costs nothing.
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 2)


## A berry that answers for one status says nothing about another.
func test_a_status_berry_only_answers_for_its_own_status() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var holder: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	holder.item = Fixture.PSNCUREBERRY
	holder.status = Gen2Status.BURN

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(holder.status, Gen2Status.BURN, "a poison berry is no use against a burn")
	assert_eq(holder.item, Fixture.PSNCUREBERRY)

	holder.status = Gen2Status.POISON
	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(holder.status, Gen2Status.NONE)
	assert_eq(holder.item, 0)


## `UseConfusionHealingItem` takes Bitter Berry and Miracleberry alike, and the
## Miracleberry is spent by whichever of the two came first: the status byte is
## read before the confusion, so a Pokémon carrying both keeps the confusion.
func test_a_miracleberry_answers_only_one_of_a_status_and_a_confusion() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var holder: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	holder.item = Fixture.MIRACLEBERRY
	holder.status = Gen2Status.BURN
	holder.substatus |= Gen2Substatus.CONFUSED
	holder.confusion_turns = 4

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_eq(holder.status, Gen2Status.NONE, "the status went first")
	assert_true(Gen2Substatus.has(holder.substatus, Gen2Substatus.CONFUSED))
	assert_eq(holder.item, 0)


func test_a_bitter_berry_clears_a_confusion() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var holder: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	holder.item = Fixture.BITTER_BERRY
	holder.substatus |= Gen2Substatus.CONFUSED
	holder.confusion_turns = 4

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_false(_first(events, Gen2Battle.ITEM_HEALED_CONFUSION).is_empty())
	assert_false(Gen2Substatus.has(holder.substatus, Gen2Substatus.CONFUSED))
	assert_eq(holder.confusion_turns, 0)
	assert_eq(holder.item, 0)


## `HandleLeftovers` and `HandleMysteryberry` read `GetUserItem` after
## `SetPlayerTurn`, so the player is handled first; `HandleHealingItems` reads
## `GetOpponentItem` after the same call, so the enemy is.
func test_the_between_turn_items_do_not_agree_on_an_order() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		battle.mon(side).hp = 10

	battle.mon(Gen2Battle.PLAYER).item = Fixture.LEFTOVERS
	battle.mon(Gen2Battle.ENEMY).item = Fixture.LEFTOVERS
	var leftovers: Array = _of_type(
		battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0)),
		Gen2Battle.RECOVERED_WITH_ITEM
	)
	assert_eq(leftovers.size(), 2)
	assert_eq(int(leftovers[0]["side"]), Gen2Battle.PLAYER)

	battle.mon(Gen2Battle.PLAYER).item = Fixture.GOLD_BERRY
	battle.mon(Gen2Battle.ENEMY).item = Fixture.GOLD_BERRY
	var berries: Array = _of_type(
		battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0)),
		Gen2Battle.RECOVERED_USING_ITEM
	)
	assert_eq(berries.size(), 2)
	assert_eq(int(berries[0]["side"]), Gen2Battle.ENEMY, "the healing items go the other way")


## The heal family through a whole turn rather than a bare command: Recover
## reaches the caller's event list with the numbers a screen draws from.
func test_recover_reaches_the_turn_loop_with_the_numbers_a_screen_needs() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.RECOVER])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 5, [Fixture.TACKLE])
	var battle: Gen2Battle = _battle(pikachu, geodude)
	pikachu.hp = 1

	var events: Array = battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_move(0)
	)

	var restored: Dictionary = _first(events, Gen2Battle.HP_RESTORED)
	assert_false(restored.is_empty(), JSON.stringify(events))
	assert_eq(int(restored["side"]), Gen2Battle.PLAYER)
	assert_eq(int(restored["max_hp"]), pikachu.max_hp())
	# The event carries what the bar read at the moment of the heal, not what is
	# left at the end of the turn: Pikachu is the faster of the two, so Geodude's
	# attack lands after this and takes some of it straight back.
	@warning_ignore("integer_division")
	assert_eq(int(restored["hp"]), 1 + pikachu.max_hp() / 2)
	assert_lt(pikachu.hp, int(restored["hp"]))


## Exp. Share. `UpdateFaintedPlayerMon` halves the block once, then splits that
## halved block among the participants and again among the holders, so each
## group is dividing half of it.
func test_an_exp_share_halves_the_fighters_award_and_pays_the_bench() -> void:
	# Bulbasaur, base exp 64, at level 5. Halved: floor(64/2) = 32, one
	# participant and one holder, so neither pass divides again. The award each
	# way is floor(32*5/7) = 22, against the 45 an unshared faint pays.
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
			_mon(Fixture.CHARMANDER, 5, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])), _rng
	)
	battle.party(Gen2Battle.PLAYER).at(1).item = Fixture.EXP_SHARE

	var gains: Array = _of_type(battle.take_turn(0, 0), Gen2Battle.EXP_GAINED)

	assert_eq(gains.size(), 2, "the fighter and the holder")
	assert_eq(gains[0]["index"], 0)
	assert_eq(gains[0]["amount"], 22, "half of what it would have earned alone")
	assert_false(bool(gains[0]["exp_share"]))
	assert_eq(gains[1]["index"], 1)
	assert_eq(gains[1]["amount"], 22)
	assert_true(bool(gains[1]["exp_share"]), "earned by holding")


## A Pokémon that both fought and holds one is in both passes, and the cartridge
## awards it twice rather than merging the two shares.
func test_a_fighter_holding_the_exp_share_is_paid_by_both_passes() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])
	)
	battle.player.item = Fixture.EXP_SHARE
	var before: int = battle.player.exp

	var gains: Array = _of_type(battle.take_turn(0, 0), Gen2Battle.EXP_GAINED)

	assert_eq(gains.size(), 2, "once for fighting and once for holding")
	assert_eq(gains[0]["amount"], 22)
	assert_eq(gains[1]["amount"], 22)
	assert_false(bool(gains[0]["exp_share"]))
	assert_true(bool(gains[1]["exp_share"]))
	# Two halves back to a whole, which is not the same as never having halved:
	# 22 + 22 is 44, one short of the 45 a lone unshared winner takes.
	assert_eq(battle.player.exp - before, 44)


## `IsAnyMonHoldingExpShare` checks HP before it looks at the item, so a fainted
## holder neither collects nor counts towards the split, and with no living
## holder left nothing is halved at all.
func test_a_fainted_exp_share_holder_neither_collects_nor_halves() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
			_mon(Fixture.CHARMANDER, 5, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])), _rng
	)
	var bench: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(1)
	bench.item = Fixture.EXP_SHARE
	bench.hp = 0

	var gains: Array = _of_type(battle.take_turn(0, 0), Gen2Battle.EXP_GAINED)

	assert_eq(gains.size(), 1, "only the fighter")
	assert_eq(gains[0]["amount"], 45, "the full award, nothing halved")


## Two holders split the halved block between them, on top of the participants
## splitting their own copy of it.
func test_two_exp_share_holders_split_their_half() -> void:
	# Geodude, base exp 86, at level 20. Halved: 43. One participant takes it
	# whole, floor(43*20/7) = 122; two holders take floor(43/2) = 21 each, which
	# is floor(21*20/7) = 60.
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 100, [Fixture.TACKLE]),
			_mon(Fixture.CHARMANDER, 5, [Fixture.TACKLE]),
			_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])), _rng
	)
	battle.party(Gen2Battle.PLAYER).at(1).item = Fixture.EXP_SHARE
	battle.party(Gen2Battle.PLAYER).at(2).item = Fixture.EXP_SHARE
	battle.enemy.hp = 1

	var gains: Array = _of_type(battle.take_turn(0, 0), Gen2Battle.EXP_GAINED)

	assert_eq(gains.size(), 3)
	assert_eq(gains[0]["amount"], 122, "the lone participant, on the halved block")
	assert_eq(gains[1]["amount"], 60)
	assert_eq(gains[2]["amount"], 60)


## The stat experience rides the same seven bytes, so it is halved and split by
## exactly the same arithmetic.
func test_an_exp_share_halves_the_stat_experience_too() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
			_mon(Fixture.CHARMANDER, 5, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])), _rng
	)
	battle.party(Gen2Battle.PLAYER).at(1).item = Fixture.EXP_SHARE

	var stat_gains: Array = _of_type(battle.take_turn(0, 0), Gen2Battle.STAT_EXP_GAINED)

	assert_eq(stat_gains.size(), 2)
	for gain: Dictionary in stat_gains:
		# Bulbasaur's 45/49/49/45/65, each byte halved on its own.
		assert_eq(gain["gains"], {
			"hp": 22, "attack": 24, "defense": 24, "speed": 22, "special": 32,
		})


## `DoItemEffect` with `wBattleMode` set. The player's own bag: the effect lands
## at menu time, and the turn it costs is spent afterwards.
func test_a_bag_potion_heals_the_chosen_party_member() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
			_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])), _rng
	)
	var bench: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(1)
	bench.hp = 1

	var used: Dictionary = battle.use_bag_item(Fixture.POTION, 1)

	assert_true(bool(used.get("ok", false)), String(used.get("reason", "")))
	assert_eq(int((used["effect"] as Dictionary)["healed"]), 20)
	assert_eq(bench.hp, 21)
	# A member already at full health is `WontHaveAnyEffect_NotUsedMessage`.
	battle.mon(Gen2Battle.PLAYER).hp = battle.mon(Gen2Battle.PLAYER).max_hp()
	var refused: Dictionary = battle.use_bag_item(Fixture.POTION, 0)
	assert_false(bool(refused.get("ok", false)))
	assert_eq(StringName(refused["reason"]), &"item_has_no_effect")


## `UseStatusHealer`'s mask, and `IsItemUsedOnConfusedMon` behind it: only a
## `%11111111` item cures confusion, and only on the Pokemon that is out.
func test_a_full_heal_takes_the_status_and_the_confusion_of_the_one_out() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])
	)
	var user: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	user.status = Gen2Status.PARALYSIS
	user.substatus |= Gen2Substatus.CONFUSED
	user.confusion_turns = 3

	var used: Dictionary = battle.use_bag_item(Fixture.FULL_HEAL, 0)

	assert_true(bool(used.get("ok", false)), String(used.get("reason", "")))
	assert_eq(user.status, Gen2Status.NONE)
	assert_false(Gen2Substatus.has(user.substatus, Gen2Substatus.CONFUSED))
	assert_true(bool((used["effect"] as Dictionary)["unconfused"]))


## `RevivePokemon`: a revive is refused on anything still standing, and the one
## it brings back joins the experience split again.
func test_a_revive_only_answers_a_fainted_member_and_puts_it_back_on_the_split() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
			_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])), _rng
	)
	assert_eq(StringName(battle.use_bag_item(Fixture.REVIVE, 0)["reason"]), &"item_has_no_effect")

	var bench: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(1)
	bench.hp = 0
	var used: Dictionary = battle.use_bag_item(Fixture.REVIVE, 1)

	assert_true(bool(used.get("ok", false)), String(used.get("reason", "")))
	assert_eq(bench.hp, maxi(bench.max_hp() / 2, 1))


## `XItemEffect` and `GuardSpecEffect` act on whoever is out, and each refuses
## once there is nothing left to raise or set.
func test_an_x_item_raises_the_stage_once_and_then_has_no_effect() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])
	)
	var user: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)

	assert_true(bool(battle.use_bag_item(Fixture.X_ATTACK).get("ok", false)))
	assert_eq(user.stage("attack"), 1)

	assert_true(bool(battle.use_bag_item(Fixture.GUARD_SPEC).get("ok", false)))
	assert_true(Gen2Substatus.has(user.substatus, Gen2Substatus.MIST))
	assert_eq(
		StringName(battle.use_bag_item(Fixture.GUARD_SPEC)["reason"]), &"item_has_no_effect"
	)

	user.change_stage("attack", Gen2Stats.MAX_STAGE)
	assert_eq(
		StringName(battle.use_bag_item(Fixture.X_ATTACK)["reason"]), &"item_has_no_effect"
	)


## `PokeDollEffect`: a wild battle ends as a DRAW the moment it is used, and a
## trainer battle leaves `wItemEffectSucceeded` clear.
func test_a_poke_doll_ends_a_wild_battle_and_does_nothing_to_a_trainer() -> void:
	var wild: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])
	)
	assert_true(bool(wild.use_bag_item(Fixture.POKE_DOLL).get("ok", false)))
	assert_true(wild.is_over())
	assert_true(wild.was_forced_out())
	assert_null(wild.winner())

	var trainer: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE])),
		Gen2Party.of(_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])), _rng, true
	)
	assert_eq(
		StringName(trainer.use_bag_item(Fixture.POKE_DOLL)["reason"]), &"item_has_no_effect"
	)
	assert_false(trainer.is_over())


## `RestorePPEffect`: an Elixer fills every slot and an Ether the one it was
## asked for, and neither is spent on a moveset that is already full.
func test_the_pp_items_fill_one_slot_and_all_of_them() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE, Fixture.EMBER]),
		_mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])
	)
	var user: Gen2BattleMon = battle.mon(Gen2Battle.PLAYER)
	assert_eq(StringName(battle.use_bag_item(Fixture.ELIXER, 0)["reason"]), &"item_has_no_effect")

	var full: int = user.pp_left(0)
	user.pp[0] = 0
	user.pp[1] = 0
	assert_true(bool(battle.use_bag_item(Fixture.ETHER, 0, 0).get("ok", false)))
	assert_eq(user.pp_left(0), mini(full, 10))
	assert_eq(user.pp_left(1), 0, "the slot the Ether was not used on")

	assert_true(bool(battle.use_bag_item(Fixture.ELIXER, 0).get("ok", false)))
	assert_eq(user.pp_left(1), mini(int(_data.move(Fixture.EMBER).get("pp", 0)), 10))


## `BATTLEPLAYERACTION_USEITEM`: the item is already spent when the turn runs, so
## the player takes no move and the enemy's own still lands.
func test_a_bag_item_costs_the_turn_and_the_enemy_still_moves() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var enemy_hp: int = battle.enemy.hp
	battle.mon(Gen2Battle.PLAYER).hp = 5

	assert_true(bool(battle.use_bag_item(Fixture.POTION, 0).get("ok", false)))
	var events: Array = battle.take_actions(
		Gen2Battle.use_item(Fixture.POTION), Gen2Battle.use_move(0)
	)

	assert_eq(battle.enemy.hp, enemy_hp, "the player threw nothing")
	assert_eq(_of_type(events, Gen2Battle.HIT).size(), 1, JSON.stringify(events))
	assert_eq(int((events[0] as Dictionary).get("side", -1)), Gen2Battle.ENEMY)


## A trainer's item is an action rather than a move: it costs the turn, it lands
## before the player's move whatever the speeds say, and the item is gone.
func test_a_trainer_item_resolves_before_the_players_move_and_is_spent() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 100, [Fixture.TACKLE])),
		Gen2Party.of(_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])), _rng, true
	)
	battle.enemy_items = [Gen2AIItems.MAX_POTION]
	battle.enemy.hp = 1

	var events: Array = battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_item(Gen2AIItems.MAX_POTION)
	)

	var used: Dictionary = _first(events, Gen2Battle.TRAINER_USED_ITEM)
	assert_false(used.is_empty(), JSON.stringify(events))
	assert_eq(int(used["side"]), Gen2Battle.ENEMY)
	assert_eq(int(used["item"]), Gen2AIItems.MAX_POTION)
	assert_eq(battle.enemy_items, [] as Array[int], "spent, and gone for the rest of the battle")
	# Pikachu at 100 outspeeds a level 50 Geodude, and the item still went first:
	# the heal is in the events before the hit that follows it.
	assert_lt(
		events.find(used),
		events.find(_first(events, Gen2Battle.HIT)),
		"the item beat a faster Pokemon to the turn"
	)
	# Healed to full, then hit once, so it is neither at 1 nor at its maximum.
	assert_gt(battle.enemy.hp, 1)


## The enemy's item costs it the turn: nothing of its own is thrown that turn.
func test_a_trainer_using_an_item_does_not_also_attack() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 100, [Fixture.TACKLE])),
		Gen2Party.of(_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])), _rng, true
	)
	battle.enemy_items = [Gen2AIItems.X_ATTACK]
	var before: int = battle.player.hp

	battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_item(Gen2AIItems.X_ATTACK)
	)

	assert_eq(battle.player.hp, before, "the enemy spent its turn on the bag")
	assert_eq(battle.enemy.stage("attack"), 1)


## An X Accuracy makes everything the holder throws land, checked ahead of the
## stat modifiers and the roll.
func test_an_x_accuracy_makes_the_enemys_moves_stop_missing() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])),
		Gen2Party.of(_mon(Fixture.GEODUDE, 50, [Fixture.SUPERSONIC])), _rng, true
	)
	# Evasion at the top would otherwise make Supersonic miss most of the time.
	battle.player.change_stage("evasion", Gen2Stats.MAX_STAGE)
	Gen2AIItems.apply(battle.enemy, Gen2AIItems.X_ACCURACY)

	var landed: int = 0
	for seed: int in 32:
		battle.rng.seed = seed
		battle.player.substatus = Gen2Substatus.NONE
		battle.player.confusion_turns = 0
		# Both back to full, or Geodude faints partway through; and its PP back,
		# or it runs Supersonic dry around turn twenty and Struggles instead.
		battle.player.hp = battle.player.max_hp()
		battle.enemy.hp = battle.enemy.max_hp()
		battle.enemy.restore_pp()
		var events: Array = battle.take_turn(0, 0)
		if not _first(events, Gen2Battle.CONFUSE_INFLICTED).is_empty():
			landed += 1
	assert_eq(landed, 32, "an X Accuracy skips the roll entirely")


func test_a_class_with_no_items_carries_none_into_the_battle() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.load_trainer_items(0)
	assert_eq(battle.enemy_items, [] as Array[int])


## `UpdateUsedMoves`: what the player has thrown is remembered once each, and
## `NewBattleMonStatus` empties the list when the player sends somebody else in.
func test_the_players_used_moves_are_remembered_once_and_cleared_on_a_switch() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE, Fixture.THUNDERBOLT]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])), _rng, true
	)

	battle.take_turn(0, 0)
	battle.take_turn(1, 0)
	battle.take_turn(0, 0)

	assert_eq(battle.player_used_moves, [Fixture.TACKLE, Fixture.THUNDERBOLT] as Array[int])

	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))

	assert_eq(battle.player_used_moves, [] as Array[int], "the list describes the Pokemon")


## The enemy's own send-out leaves the list alone: it records what the player has
## shown, not what it is being shown to.
func test_an_enemy_switch_leaves_the_used_move_list_alone() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])),
		Gen2Party.create([
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		]), _rng, true
	)

	battle.take_turn(0, 0)
	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.switch_to(1))

	assert_eq(battle.player_used_moves, [Fixture.TACKLE] as Array[int])


## `BattleCommand_Screen` sets the bit on the user's own side and loads five,
## and `HandleScreens` takes one off on that same turn, so a Reflect covers the
## turn it went up and four more.
func test_a_screen_lasts_five_turns_counting_the_one_that_set_it() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.REFLECT, Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)

	var setting: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_eq(_first(setting, Gen2Battle.SCREEN_SET)["screen"], Gen2Screens.REFLECT)
	assert_true(Gen2Screens.has(battle.screens[Gen2Battle.PLAYER], Gen2Screens.REFLECT))
	assert_eq(battle.reflect_turns[Gen2Battle.PLAYER], Gen2Screens.TURNS - 1)
	assert_eq(battle.screens[Gen2Battle.ENEMY], Gen2Screens.NONE, "one side only")

	var faded: Dictionary = {}
	var turns: int = 0
	for _turn: int in 10:
		var events: Array = battle.take_actions(Gen2Battle.use_move(1), Gen2Battle.use_move(0))
		turns += 1
		faded = _first(events, Gen2Battle.SCREEN_FADED)
		if not faded.is_empty():
			break

	assert_eq(turns, Gen2Screens.TURNS - 1, "four more turns after the one that set it")
	assert_eq(faded["screen"], Gen2Screens.REFLECT)
	assert_eq(battle.screens[Gen2Battle.PLAYER], Gen2Screens.NONE)
	assert_eq(battle.reflect_turns[Gen2Battle.PLAYER], 0)


## Reflect and Light Screen have counts of their own rather than sharing one, so
## a side can hold both and lose them on different turns.
func test_the_two_screens_run_down_separately() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.REFLECT, Fixture.LIGHT_SCREEN, Fixture.GROWL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	battle.take_actions(Gen2Battle.use_move(1), Gen2Battle.use_move(0))

	assert_eq(battle.reflect_turns[Gen2Battle.PLAYER], Gen2Screens.TURNS - 2)
	assert_eq(battle.light_screen_turns[Gen2Battle.PLAYER], Gen2Screens.TURNS - 1)
	assert_true(Gen2Screens.has(
		battle.screens[Gen2Battle.PLAYER], Gen2Screens.REFLECT | Gen2Screens.LIGHT_SCREEN
	))

	var reflect_fell_on: int = -1
	var light_screen_fell_on: int = -1
	for turn: int in 8:
		var events: Array = battle.take_actions(Gen2Battle.use_move(2), Gen2Battle.use_move(0))
		for event: Dictionary in _of_type(events, Gen2Battle.SCREEN_FADED):
			if int(event["screen"]) == Gen2Screens.REFLECT:
				reflect_fell_on = turn
			else:
				light_screen_fell_on = turn

	assert_eq(reflect_fell_on, 2)
	assert_eq(light_screen_fell_on, 3, "one turn behind, the turn it was put up later")


## A second use fails outright rather than restarting the count, which is
## `BattleCommand_Screen`'s `.failed` branch and not Rain Dance's behaviour.
func test_a_second_screen_fails_without_restarting_the_count() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.REFLECT]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var again: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_false(_first(again, Gen2Battle.MOVE_FAILED).is_empty(), JSON.stringify(again))
	assert_eq(_of_type(again, Gen2Battle.SCREEN_SET).size(), 0)
	assert_eq(battle.reflect_turns[Gen2Battle.PLAYER], Gen2Screens.TURNS - 2)


## The screen belongs to the side, not to the Pokémon: nothing clears it on a
## switch, which is the whole difference between it and a [Gen2Substatus] flag.
func test_a_screen_outlives_the_pokemon_that_put_it_up() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.create([
			_mon(Fixture.PIKACHU, 50, [Fixture.REFLECT]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])), _rng, true
	)

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))

	assert_true(Gen2Screens.has(battle.screens[Gen2Battle.PLAYER], Gen2Screens.REFLECT))


## `BattleCommand_CheckSafeguard` is the loud half: the move is refused with
## `SafeguardProtectText` and ends there.
func test_safeguard_refuses_a_status_move_and_says_so() -> void:
	# Pikachu is the faster of the two, so the veil goes up on its own turn
	# first and the status move is tried against it on the next.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL, Fixture.THUNDER_WAVE]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.SAFEGUARD])
	)

	var raising: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var events: Array = battle.take_actions(Gen2Battle.use_move(1), Gen2Battle.use_move(0))

	assert_eq(_first(raising, Gen2Battle.SCREEN_SET)["screen"], Gen2Screens.SAFEGUARD)
	var protected: Dictionary = _first(events, Gen2Battle.SAFEGUARD_PROTECTED)
	assert_false(protected.is_empty(), JSON.stringify(events))
	assert_eq(protected["target"], Gen2Battle.ENEMY)
	assert_eq(battle.enemy.status, Gen2Status.NONE)


## `SafeCheckSafeguard` is the quiet half: a secondary status is refused with
## nothing said, because only the four moves carrying `checksafeguard` speak.
func test_safeguard_refuses_a_secondary_status_silently() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.EMBER_BURNS]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.GROWL])
	)
	battle.screens[Gen2Battle.ENEMY] = Gen2Screens.SAFEGUARD
	battle.safeguard_turns[Gen2Battle.ENEMY] = Gen2Screens.TURNS

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_eq(_of_type(events, Gen2Battle.STATUS_INFLICTED).size(), 0, JSON.stringify(events))
	assert_eq(_of_type(events, Gen2Battle.SAFEGUARD_PROTECTED).size(), 0, "nothing is said")
	assert_eq(battle.enemy.status, Gen2Status.NONE)
	assert_false(_first(events, Gen2Battle.HIT).is_empty(), "the hit itself still lands")


## `HandleSafeguard` runs ahead of `HandleScreens` and off a count of its own.
func test_safeguard_runs_down_and_stops_protecting() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDER_WAVE]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.screens[Gen2Battle.ENEMY] = Gen2Screens.SAFEGUARD
	battle.safeguard_turns[Gen2Battle.ENEMY] = 1

	var ending: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_false(_first(ending, Gen2Battle.SAFEGUARD_PROTECTED).is_empty(), "still up this turn")
	assert_eq(_first(ending, Gen2Battle.SCREEN_FADED)["screen"], Gen2Screens.SAFEGUARD)
	assert_eq(battle.screens[Gen2Battle.ENEMY], Gen2Screens.NONE)

	var after: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_eq(_of_type(after, Gen2Battle.SAFEGUARD_PROTECTED).size(), 0)
	assert_true(Gen2Status.has(battle.enemy.status, Gen2Status.PARALYSIS))


## `BattleCommand_PerishSong` names `wPlayerSubStatus1` and `wEnemySubStatus1`
## rather than the user and the target, so the singer is caught by its own song.
## The count is four and the first tick spends one of them, which is why the
## line promises three turns.
func test_perish_song_catches_both_sides_and_starts_at_three() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_eq(_of_type(events, Gen2Battle.PERISH_SONG_STARTED).size(), 1, JSON.stringify(events))
	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		assert_true(
			Gen2Substatus.has(battle.mon(side).substatus, Gen2Substatus.PERISH),
			"side %d heard it" % side,
		)
		assert_eq(battle.mon(side).perish_count, 3)

	var counted: Array = _of_type(events, Gen2Battle.PERISH_COUNT)
	assert_eq(counted.size(), 2, "both sides are counted down, player first")
	assert_eq(counted[0]["side"], Gen2Battle.PLAYER)
	assert_eq(counted[0]["count"], 3)
	assert_eq(counted[1]["side"], Gen2Battle.ENEMY)


## `.failed` is reached only when both sides already carry the flag: the song
## fails outright rather than restarting either count.
func test_perish_song_fails_when_both_are_already_counting_down() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var again: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_false(_first(again, Gen2Battle.MOVE_FAILED).is_empty(), JSON.stringify(again))
	assert_eq(_of_type(again, Gen2Battle.PERISH_SONG_STARTED).size(), 0)
	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		assert_eq(battle.mon(side).perish_count, 2, "the second song reset nothing")


## `.ok` sets the flag on each side that lacks it and leaves the count of a side
## that already has one alone, so the two clocks stay out of step.
func test_perish_song_catches_only_the_side_that_missed_it() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.enemy.substatus |= Gen2Substatus.PERISH
	battle.enemy.perish_count = 2

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	assert_false(_first(events, Gen2Battle.PERISH_SONG_STARTED).is_empty(), JSON.stringify(events))
	assert_eq(battle.player.perish_count, 3, "the singer starts a fresh four")
	assert_eq(battle.enemy.perish_count, 1, "the count already running is not restarted")


## The zero tick clears the flag and empties the HP word outright, which is not
## damage: nothing rolls, nothing is a fraction of anything, and both sides go
## down on the same turn end.
func test_perish_song_finishes_both_on_the_fourth_turn_end() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)

	var last: Array = []
	for turn: int in 4:
		last = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))

	var counted: Array = _of_type(last, Gen2Battle.PERISH_COUNT)
	assert_eq(counted.size(), 2)
	assert_eq(counted[0]["count"], 0, "the line prints on the tick that kills too")
	assert_eq(_of_type(last, Gen2Battle.FAINTED).size(), 2, JSON.stringify(last))
	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		assert_eq(battle.mon(side).hp, 0)
		assert_true(battle.mon(side).is_fainted())
		assert_false(Gen2Substatus.has(battle.mon(side).substatus, Gen2Substatus.PERISH))


## `NewBattleMonStatus` clears all five substatus bytes on a send-out, so the
## Pokémon that comes in has heard nothing. The count behind the flag goes with
## it, which is what [method Gen2BattleMon.reset_volatile] is for.
func test_a_switch_escapes_perish_song() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.create([
			_mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG]),
			_mon(Fixture.BULBASAUR, 50, [Fixture.GROWL]),
		]),
		Gen2Party.of(_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])), _rng, true
	)

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var switching: Array = battle.take_actions(
		Gen2Battle.switch_to(1), Gen2Battle.use_move(0)
	)

	assert_false(
		Gen2Substatus.has(battle.player.substatus, Gen2Substatus.PERISH),
		"the Pokémon sent out never heard the song",
	)
	assert_eq(battle.player.perish_count, 0)
	var counted: Array = _of_type(switching, Gen2Battle.PERISH_COUNT)
	assert_eq(counted.size(), 1, "only the enemy is still counting")
	assert_eq(counted[0]["side"], Gen2Battle.ENEMY)
	assert_true(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.PERISH))


## `HandleBetweenTurnEffects` runs `HandleWrap`, then `HandlePerishSong`, then
## its leftovers block, of which `HandleSafeguard` is a part.
func test_perish_song_ticks_after_wrap_and_before_the_leftovers_block() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.player.substatus |= Gen2Substatus.PERISH
	battle.player.perish_count = 3
	battle.player.trapped_turns = 3
	battle.player.trapping_move = Fixture.WRAP
	battle.screens[Gen2Battle.PLAYER] = Gen2Screens.SAFEGUARD
	battle.safeguard_turns[Gen2Battle.PLAYER] = 1

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var order: Array = events.map(func(event: Dictionary) -> StringName: return event["type"])

	assert_true(order.has(Gen2Battle.HURT_BY_TRAP), JSON.stringify(events))
	assert_true(order.has(Gen2Battle.SCREEN_FADED), JSON.stringify(events))
	assert_lt(
		order.find(Gen2Battle.HURT_BY_TRAP), order.find(Gen2Battle.PERISH_COUNT),
		"the wrap tick comes first",
	)
	assert_lt(
		order.find(Gen2Battle.PERISH_COUNT), order.find(Gen2Battle.SCREEN_FADED),
		"the leftovers block, Safeguard included, comes after",
	)


## `ResidualDamage` runs poison, then Leech Seed, then Nightmare, then Curse,
## with a `HasUserFainted` between each pair.
func test_the_three_residuals_run_behind_poison_in_the_sources_order() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.player.status = Gen2Status.POISON
	battle.player.substatus |= Gen2Substatus.LEECH_SEED \
		| Gen2Substatus.NIGHTMARE | Gen2Substatus.CURSE

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var order: Array = events.map(func(event: Dictionary) -> StringName: return event["type"])

	assert_lt(order.find(Gen2Battle.HURT_BY_STATUS), order.find(Gen2Battle.LEECH_SEED_SAPPED))
	assert_lt(order.find(Gen2Battle.LEECH_SEED_SAPPED), order.find(Gen2Battle.HURT_BY_NIGHTMARE))
	assert_lt(order.find(Gen2Battle.HURT_BY_NIGHTMARE), order.find(Gen2Battle.HURT_BY_CURSE))


## The `HasUserFainted` between them is not decoration: a Pokémon that goes down
## to its poison pays none of the three behind it.
func test_a_faint_to_poison_stops_the_residuals_behind_it() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.player.status = Gen2Status.POISON
	battle.player.substatus |= Gen2Substatus.LEECH_SEED | Gen2Substatus.CURSE
	battle.player.hp = 1

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_true(battle.player.is_fainted())
	assert_eq(_of_type(events, Gen2Battle.LEECH_SEED_SAPPED).size(), 0)
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_CURSE).size(), 0)


## An eighth off the seeded Pokémon and the same figure onto the one opposite,
## which `RestoreHP` caps at that one's maximum.
func test_leech_seed_moves_an_eighth_across_the_field() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.player.substatus |= Gen2Substatus.LEECH_SEED
	var eighth: int = Gen2Substatus.leech_seed_damage(battle.player.max_hp())
	var sapper_full: int = battle.enemy.max_hp()
	battle.enemy.hp = sapper_full - eighth - 5
	var seeded_before: int = battle.player.hp

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	var sapped: Dictionary = _first(events, Gen2Battle.LEECH_SEED_SAPPED)

	assert_eq(battle.player.hp, seeded_before - eighth)
	assert_eq(battle.enemy.hp, sapper_full - 5)
	assert_eq(int(sapped["amount"]), eighth)
	assert_eq(int(sapped["to"]), Gen2Battle.ENEMY)


## `SubtractHP` leaves the pre-hit health in `bc` when the eighth would have gone
## below zero, so what the sapper takes is what the seed actually got.
func test_leech_seed_hands_on_only_what_it_could_take() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.player.substatus |= Gen2Substatus.LEECH_SEED
	battle.player.hp = 2
	battle.enemy.hp = 1

	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_true(battle.player.is_fainted())
	assert_eq(battle.enemy.hp, 3, "two taken, two given")
	assert_eq(int(_first(events, Gen2Battle.LEECH_SEED_SAPPED)["to_amount"]), 2)


func test_a_nightmare_and_a_curse_each_cost_a_quarter() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.GROWL]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.GROWL])
	)
	battle.player.substatus |= Gen2Substatus.NIGHTMARE
	battle.enemy.substatus |= Gen2Substatus.CURSE
	var player_full: int = battle.player.hp
	var enemy_full: int = battle.enemy.hp

	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(battle.player.hp, player_full - Gen2Substatus.quarter_damage(battle.player.max_hp()))
	assert_eq(battle.enemy.hp, enemy_full - Gen2Substatus.quarter_damage(battle.enemy.max_hp()))


## `SpikesDamage` runs behind every entrance's own `SetPlayerTurn`, so the flag
## read is the one lying on the side walking in.
func test_spikes_are_paid_by_whoever_walks_onto_them() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
	)
	battle.screens[Gen2Battle.PLAYER] |= Gen2Screens.SPIKES

	var events: Array = battle.send_out(Gen2Battle.PLAYER, 1)
	var entering: Gen2BattleMon = battle.player
	assert_eq(
		entering.hp,
		entering.max_hp() - Gen2Screens.spikes_damage(entering.max_hp())
	)
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_SPIKES).size(), 1)


## Field state, so the same spikes charge every entrance rather than one.
func test_spikes_outlive_the_pokemon_that_walked_into_them() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
	)
	battle.screens[Gen2Battle.PLAYER] |= Gen2Screens.SPIKES

	battle.send_out(Gen2Battle.PLAYER, 1)
	var second: Array = battle.send_out(Gen2Battle.PLAYER, 0)
	assert_eq(_of_type(second, Gen2Battle.HURT_BY_SPIKES).size(), 1)
	assert_true(Gen2Screens.has(battle.screens[Gen2Battle.PLAYER], Gen2Screens.SPIKES))


func test_a_flying_type_walks_over_spikes() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.HOOTHOOT, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
	)
	battle.screens[Gen2Battle.PLAYER] |= Gen2Screens.SPIKES

	var events: Array = battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(battle.player.hp, battle.player.max_hp())
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_SPIKES).size(), 0)


## The other side's spikes are the other side's: `SpikesDamage` never reads them.
func test_spikes_on_one_side_do_not_charge_the_other() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
	)
	battle.screens[Gen2Battle.ENEMY] |= Gen2Screens.SPIKES

	var events: Array = battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(battle.player.hp, battle.player.max_hp())
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_SPIKES).size(), 0)


## A doll is `SUBSTATUS_SUBSTITUTE` and nothing else, so `NewBattleMonStatus`
## zeroing the substatus block is what a switch costs it.
func test_a_switch_leaves_the_substitute_behind() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
	)
	var leaving: Gen2BattleMon = battle.player
	leaving.substatus |= Gen2Substatus.SUBSTITUTE
	leaving.substitute_hp = 40

	battle.send_out(Gen2Battle.PLAYER, 1)
	assert_false(Gen2Substatus.has(leaving.substatus, Gen2Substatus.SUBSTITUTE))
	assert_eq(leaving.substitute_hp, 0)


## `wEnemyGoesFirst`, and the wrapper each side's action runs inside.
##
## [method Gen2Battle.opponent_went_first] is what Protect and Endure read, and
## it is [method Gen2Battle.order]'s own answer rather than a second decision, so
## every branch of the order has to leave it right.
func test_who_went_first_is_recorded_for_every_branch_of_the_order() -> void:
	var fast: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	fast.take_turn(0, 0)
	assert_false(fast.enemy_goes_first, "110 Speed against 30")
	assert_false(fast.opponent_went_first(Gen2Battle.PLAYER))
	assert_true(fast.opponent_went_first(Gen2Battle.ENEMY))

	# Priority beats speed: Protect is 3 and Tackle is 1.
	var priority: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.PROTECT])
	)
	priority.take_turn(0, 0)
	assert_true(priority.enemy_goes_first, "priority 3 beats a faster Tackle")

	# A switching side is settled first whatever its speed.
	var switching: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]), _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])]
	)
	switching.take_actions(Gen2Battle.use_move(0), Gen2Battle.switch_to(1))
	assert_true(switching.enemy_goes_first, "the enemy's switch settles before the move")


## `EndOpponentProtectEndureDestinyBond` behind the opponent's own action: a
## Protect covers exactly one opposing move and is gone after it.
func test_a_protect_is_cleared_by_the_move_it_turned_away() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PROTECT]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var first: Array = battle.take_turn(0, 0)

	assert_eq(_of_type(first, Gen2Battle.PROTECTED_ITSELF).size(), 1)
	assert_eq(_of_type(first, Gen2Battle.PROTECTING_ITSELF).size(), 1, "the Tackle was turned away")
	assert_eq(_of_type(first, Gen2Battle.HIT).size(), 0)
	assert_false(
		Gen2Substatus.has(battle.player.substatus, Gen2Substatus.PROTECT),
		"and the enemy's own move cleared it behind itself"
	)


## The player's half of the wrapper runs on every action it spends the turn on,
## because `DoPlayerTurn`'s `ret nz` skips only the move and not the two clears
## around it. So a player switch ends an enemy's Protect.
func test_a_player_switch_ends_the_enemys_protect() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])]
	)
	battle.enemy.substatus |= Gen2Substatus.PROTECT
	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))

	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.PROTECT))


## The enemy's half is skipped outright when it switches instead of moving, which
## is `.switched_or_used_item` jumping past `EnemyTurn_End...`. So the player's
## own Protect outlives an enemy switch and is still up for the move after it.
func test_a_player_protect_outlives_an_enemy_switch() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]), _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])]
	)
	battle.player.substatus |= Gen2Substatus.PROTECT
	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.switch_to(1))

	assert_true(
		Gen2Substatus.has(battle.player.substatus, Gen2Substatus.PROTECT),
		"nothing on the enemy's side of the turn clears it"
	)


## A bond covers exactly the opponent's next move, and the two brackets are what
## decide which move that is.
##
## A user that goes first is answered on the same turn and its bond is cleared
## behind the reply, so the interesting arrangement is the slow one: the bond
## goes up after the opponent has already moved and is still up when the
## opponent moves again.
func test_a_destiny_bond_from_a_slow_user_survives_into_the_next_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.DESTINY_BOND]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	battle.take_turn(0, 0)
	assert_true(battle.enemy_goes_first, "110 Speed against 30")
	assert_true(
		Gen2Substatus.has(battle.player.substatus, Gen2Substatus.DESTINY_BOND),
		"the enemy had already moved, so nothing was left to clear it"
	)

	battle.player.hp = 1
	var events: Array = battle.take_turn(0, 0)
	assert_true(battle.player.is_fainted())
	assert_true(battle.enemy.is_fainted(), "and the bond collected on the next move")
	assert_eq(_of_type(events, Gen2Battle.TOOK_DOWN_WITH_IT).size(), 1)


## A user that goes first is answered the same turn, and its own bond is cleared
## behind the answer rather than left standing.
func test_a_destiny_bond_from_a_fast_user_is_cleared_by_the_reply() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.DESTINY_BOND]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.take_turn(0, 0)

	assert_false(battle.enemy_goes_first)
	assert_false(
		Gen2Substatus.has(battle.player.substatus, Gen2Substatus.DESTINY_BOND),
		"the enemy's own move cleared it behind itself"
	)


## A switch clears all three flags and both counters, since they sit inside the
## five substatus bytes `NewBattleMonStatus` zeroes.
func test_a_switch_clears_the_three_flags_and_the_protect_count() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])]
	)
	var leaving: Gen2BattleMon = battle.player
	leaving.substatus |= (
		Gen2Substatus.PROTECT | Gen2Substatus.ENDURE | Gen2Substatus.DESTINY_BOND
	)
	leaving.protect_count = 4
	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	battle.send_out(Gen2Battle.PLAYER, 0)

	assert_eq(battle.player.substatus & (
		Gen2Substatus.PROTECT | Gen2Substatus.ENDURE | Gen2Substatus.DESTINY_BOND
	), 0)
	assert_eq(battle.player.protect_count, 0)


## `ParsePlayerAction`'s `cp EFFECT_FURY_CUTTER`: the chain is kept only while
## Fury Cutter is the move being used, so any other move in between breaks it.
func test_another_move_breaks_the_fury_cutter_chain() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.FURY_CUTTER, Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.player.fury_cutter_count, 1)
	battle.take_turn(0, 0)
	assert_eq(battle.player.fury_cutter_count, 2, "two in a row keeps counting")

	battle.take_turn(1, 0)
	assert_eq(battle.player.fury_cutter_count, 0, "a Tackle in between resets it")
	battle.take_turn(0, 0)
	assert_eq(battle.player.fury_cutter_count, 1, "so the next one starts over")


## The same rule on Protect's own counter, and Endure does not break it because
## the two share one.
##
## The shared ladder is read at the count that cannot roll rather than by
## counting a success, so no seed decides the answer: an Endure behind a spent
## Protect chain has to fail, where an Endure with a ladder of its own would be a
## first use and could not.
func test_another_move_breaks_the_protect_chain_but_endure_does_not() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PROTECT, Fixture.TACKLE, Fixture.ENDURE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.protect_count = 8
	battle.take_turn(2, 0)
	assert_false(
		Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ENDURE),
		"Endure inherited Protect's spent ladder"
	)

	battle.take_turn(1, 0)
	assert_eq(battle.player.protect_count, 0, "a Tackle in between resets it")
	battle.take_turn(0, 0)
	assert_eq(battle.player.protect_count, 1, "so the next Protect starts over and lands")


## `.reset_bide` falls into `.locked_in`, so a failed run empties both counters
## the way any other spent turn does.
func test_a_failed_run_empties_both_counters() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 1, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 100, [Fixture.TACKLE])
	)
	battle.player.protect_count = 3
	battle.player.fury_cutter_count = 3
	var events: Array = battle.take_actions(Gen2Battle.run_away(), Gen2Battle.use_move(0))

	assert_eq(
		_of_type(events, Gen2Battle.RUN_FAILED).size(), 1,
		"a level 1 Pikachu does not outrun a level 100 Geodude: %s" % JSON.stringify(events)
	)
	assert_eq(battle.player.protect_count, 0)
	assert_eq(battle.player.fury_cutter_count, 0)


## `AI_TryItem` does the same on the enemy's side.
func test_a_trainer_item_empties_both_counters() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])),
		Gen2Party.of(_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])), _rng, true
	)
	battle.enemy_items = [Gen2AIItems.MAX_POTION]
	battle.enemy.hp = 1
	battle.enemy.protect_count = 5
	battle.enemy.fury_cutter_count = 5
	battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.use_item(Gen2AIItems.MAX_POTION)
	)

	assert_eq(battle.enemy.protect_count, 0)
	assert_eq(battle.enemy.fury_cutter_count, 0)


## Whirlwind and Roar through a whole turn, which is where the went-first gate
## stops being something a test has to arrange: priority 0 puts them second.
func test_a_trainers_roar_drags_the_players_pokemon_out() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		]),
		Gen2Party.of(_mon(Fixture.GEODUDE, 50, [Fixture.ROAR])), _rng, true
	)
	var events: Array = battle.take_turn(0, 0)

	assert_true(battle.enemy_goes_first == false, "Pikachu outspeeds Geodude")
	assert_eq(
		battle.party(Gen2Battle.PLAYER).active, 1,
		"Roar is priority 0, so it moved second and the gate passed: %s" % JSON.stringify(events)
	)
	assert_eq(_of_type(events, Gen2Battle.DRAGGED_OUT).size(), 1)
	assert_false(battle.is_over())


## The same move in a wild battle ends it rather than switching anybody, and the
## parties are left exactly as they stood.
func test_a_wild_roar_ends_the_battle_with_both_sides_standing() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.ROAR])
	)
	var events: Array = battle.take_turn(0, 0)

	assert_true(battle.is_over())
	assert_true(battle.was_forced_out())
	assert_false(battle.has_fled(), "it was not the player's own decision")
	assert_eq(battle.forced_out_side(), Gen2Battle.PLAYER)
	assert_null(battle.winner())
	assert_eq(_of_type(events, Gen2Battle.FLED_IN_FEAR).size(), 1)
	assert_false(_first(events, Gen2Battle.OVER).is_empty())
	assert_false(battle.player.is_fainted())
	assert_false(battle.enemy.is_fainted())


## `BreakAttraction` runs on every entrance and clears the flag on both sides,
## not only the incoming Pokemon's: whoever was in love has nothing left to be in
## love with.
func test_a_switch_breaks_attraction_on_both_sides() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])]
	)
	battle.player.substatus |= Gen2Substatus.ATTRACTED
	battle.enemy.substatus |= Gen2Substatus.ATTRACTED
	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))

	assert_false(Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ATTRACTED))
	assert_false(
		Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.ATTRACTED),
		"the side that did not switch loses it too"
	)


## Baton Pass, which is the first move that hands the Pokemon behind it
## everything the position was carrying, and the first that can stop a turn part
## way through.
func _pass_party(moves: Array) -> Gen2Battle:
	return _party_battle(
		[_mon(Fixture.PIKACHU, 50, moves), _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])],
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])]
	)


func test_a_players_baton_pass_stops_the_turn_until_it_is_answered() -> void:
	var battle: Gen2Battle = _pass_party([Fixture.BATON_PASS])
	var opened: Array = battle.take_turn(0, 0)

	assert_eq(battle.awaiting_baton_pass(), Gen2Battle.PLAYER)
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 0, "nobody has come in yet")
	assert_eq(
		_of_type(opened, Gen2Battle.HIT).size(), 0,
		"and the enemy has not moved either: %s" % JSON.stringify(opened)
	)

	assert_eq(
		battle.take_turn(0, 0), [] as Array,
		"a turn already standing cannot be started again"
	)

	var finished: Array = battle.pass_to(1)
	assert_eq(battle.awaiting_baton_pass(), -1)
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 1)
	assert_eq(_of_type(finished, Gen2Battle.SENT_OUT).size(), 1)
	assert_eq(
		_of_type(finished, Gen2Battle.HIT).size(), 1,
		"the rest of the turn ran once it was answered: %s" % JSON.stringify(finished)
	)


## `ForcePickSwitchMonInBattle` redisplays its list rather than taking somebody
## who cannot come in, so a refused answer leaves the question standing.
func test_a_refused_baton_pass_target_leaves_the_question_standing() -> void:
	var battle: Gen2Battle = _pass_party([Fixture.BATON_PASS])
	battle.take_turn(0, 0)

	var bench: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(1)
	bench.take_damage(bench.max_hp())
	assert_eq(battle.pass_to(1), [] as Array, "a fainted target")
	assert_eq(battle.pass_to(0), [] as Array, "the Pokemon already out")
	assert_eq(battle.pass_to(9), [] as Array, "nobody at all")
	assert_eq(battle.awaiting_baton_pass(), Gen2Battle.PLAYER)


## The stat stages are the point of the move, and they are position state on the
## cartridge rather than the Pokemon's, so they move across and the Pokemon that
## left keeps none of them.
func test_a_pass_carries_the_stages_and_leaves_the_passer_with_none() -> void:
	var battle: Gen2Battle = _pass_party([Fixture.BATON_PASS])
	var passer: Gen2BattleMon = battle.player
	passer.stages["attack"] = 4
	passer.stages["speed"] = -2
	battle.take_turn(0, 0)
	battle.pass_to(1)

	assert_eq(battle.player.stage("attack"), 4, "the newcomer is handed them")
	assert_eq(battle.player.stage("speed"), -2)
	assert_eq(passer.stage("attack"), 0, "and the passer keeps nothing")


## So do the substatus flags and the counters beside them: a doll, a seed and a
## perish count all survive the switch that would ordinarily end them.
func test_a_pass_carries_the_doll_the_seed_and_the_perish_count() -> void:
	var battle: Gen2Battle = _pass_party([Fixture.BATON_PASS])
	var passer: Gen2BattleMon = battle.player
	passer.substatus |= (
		Gen2Substatus.SUBSTITUTE | Gen2Substatus.LEECH_SEED | Gen2Substatus.PERISH
	)
	# A doll big enough to survive the Tackle that lands behind the pass, since
	# the enemy still gets its move once the turn resumes.
	passer.substitute_hp = 250
	passer.perish_count = 2
	battle.take_turn(0, 0)
	battle.pass_to(1)

	var arriving: Gen2BattleMon = battle.player
	assert_true(Gen2Substatus.has(arriving.substatus, Gen2Substatus.SUBSTITUTE))
	assert_lt(arriving.substitute_hp, 250, "the doll took the Tackle behind the pass")
	assert_gt(arriving.substitute_hp, 0, "and survived it")
	assert_true(Gen2Substatus.has(arriving.substatus, Gen2Substatus.LEECH_SEED))
	# The count carried and then the end-of-turn tick spent one of it, which is
	# what a count that did not carry could never do: a fresh Pokemon has none.
	assert_true(Gen2Substatus.has(arriving.substatus, Gen2Substatus.PERISH))
	assert_eq(arriving.perish_count, 1)


## `ResetBatonPassStatus` names what does not survive: Disable, Encore, the last
## move used, attraction on both sides and both wrap counters.
func test_a_pass_drops_what_reset_baton_pass_status_names() -> void:
	# Baton Pass is in slot 0, so the disabled slot has to be the other one:
	# a disabled slot 0 would answer Struggle and never reach the pass at all.
	var battle: Gen2Battle = _pass_party([Fixture.BATON_PASS, Fixture.TACKLE])
	var passer: Gen2BattleMon = battle.player
	passer.disabled_slot = 1
	passer.disable_turns = 3
	passer.substatus |= Gen2Substatus.ENCORED
	passer.encored_slot = 0
	passer.encore_turns = 2
	passer.last_move_used = Fixture.TACKLE
	passer.trapped_turns = 3
	battle.enemy.trapped_turns = 3
	battle.take_turn(0, 0)
	battle.pass_to(1)

	var arriving: Gen2BattleMon = battle.player
	assert_eq(arriving.disabled_slot, -1)
	assert_eq(arriving.disable_turns, 0)
	assert_false(Gen2Substatus.has(arriving.substatus, Gen2Substatus.ENCORED))
	assert_eq(arriving.encored_slot, -1)
	assert_eq(arriving.last_move_used, 0)
	assert_eq(arriving.trapped_turns, 0)
	assert_eq(battle.enemy.trapped_turns, 0, "the wrap counters go on both sides")


## Attraction goes with them, on both sides, and is asked of the entrance
## directly: an attracted passer has a coin flip in front of its own move, and
## `ResetBatonPassStatus` is what this is about rather than `CheckTurn`.
func test_a_pass_breaks_attraction_on_both_sides() -> void:
	var battle: Gen2Battle = _pass_party([Fixture.BATON_PASS])
	battle.player.substatus |= Gen2Substatus.ATTRACTED
	battle.enemy.substatus |= Gen2Substatus.ATTRACTED
	battle.baton_pass_send_out(Gen2Battle.PLAYER, 1)

	assert_false(
		Gen2Substatus.has(battle.player.substatus, Gen2Substatus.ATTRACTED),
		"the arriving Pokemon is not handed the passer's"
	)
	assert_false(Gen2Substatus.has(battle.enemy.substatus, Gen2Substatus.ATTRACTED))


## Nightmare is the one that reads the *arriving* Pokemon, because
## `ResetBatonPassStatus` runs behind the entrance: it survives a pass only into
## somebody already asleep.
func test_a_nightmare_survives_a_pass_only_into_a_sleeping_pokemon() -> void:
	for asleep: bool in [false, true]:
		var battle: Gen2Battle = _pass_party([Fixture.BATON_PASS])
		battle.player.substatus |= Gen2Substatus.NIGHTMARE
		if asleep:
			battle.party(Gen2Battle.PLAYER).at(1).status = 3
		battle.take_turn(0, 0)
		battle.pass_to(1)

		assert_eq(
			Gen2Substatus.has(battle.player.substatus, Gen2Substatus.NIGHTMARE), asleep,
			"arriving asleep: %s" % asleep
		)


## The enemy's half needs no answer at all: its target is picked for it, so the
## turn runs straight through.
func test_an_enemy_baton_pass_resolves_inside_the_turn() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])),
		Gen2Party.create([
			_mon(Fixture.GEODUDE, 50, [Fixture.BATON_PASS]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		]), _rng, true
	)
	battle.enemy.stages["defense"] = 3
	var events: Array = battle.take_turn(0, 0)

	assert_eq(battle.awaiting_baton_pass(), -1, "nothing was asked")
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)
	assert_eq(battle.enemy.stage("defense"), 3, "and the stages went with it")
	assert_false(_first(events, Gen2Battle.SENT_OUT).is_empty())


## A wild Pokemon has no party behind it, and neither has a lone one.
func test_a_baton_pass_with_nobody_behind_it_fails() -> void:
	var wild: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.BATON_PASS])
	)
	assert_eq(_of_type(wild.take_turn(0, 0), Gen2Battle.MOVE_FAILED).size(), 1)
	assert_eq(wild.awaiting_baton_pass(), -1)

	var lone: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.BATON_PASS]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	assert_eq(_of_type(lone.take_turn(0, 0), Gen2Battle.MOVE_FAILED).size(), 1)
	assert_eq(lone.awaiting_baton_pass(), -1, "and no question was asked")


## `PursuitSwitch`, which the cartridge calls from `BattleMonEntrance` and from
## `AI_Switch`: the side that chose Pursuit takes its whole turn in front of the
## recall, against the Pokémon on its way out.
func test_pursuit_hits_the_pokemon_on_its_way_out() -> void:
	var battle: Gen2Battle = _party_battle(
		[
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		],
		[_mon(Fixture.PIKACHU, 50, [Fixture.PURSUIT])]
	)
	var leaving: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(0)
	var events: Array = battle.take_actions(
		Gen2Battle.switch_to(1), Gen2Battle.use_move(0)
	)

	var types: Array = events.map(func(event: Dictionary) -> StringName: return event["type"])
	assert_true(types.has(Gen2Battle.HIT), "the pursuer landed a hit")
	assert_lt(
		types.find(Gen2Battle.HIT), types.find(Gen2Battle.WITHDREW),
		"in front of the recall, which is where `PursuitSwitch` sits"
	)
	assert_lt(leaving.hp, leaving.max_hp(), "the Pokemon that left took it")
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 1, "the switch still happened")
	# `ld a, CANNOT_MOVE`: the pursuer has nothing left to spend this turn.
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1)


## `wPlayerIsSwitching` is what `pursuit` reads, so the doubling only happens on
## the turn the other side is leaving.
func test_pursuit_doubles_only_against_a_side_that_is_leaving() -> void:
	var against_switch: int = _pursuit_damage(true)
	var against_move: int = _pursuit_damage(false)

	assert_gt(against_switch, against_move)
	# Twice the figure, and the spread was already applied when `pursuit` ran, so
	# the two are exactly double with the same seed.
	assert_eq(against_switch, against_move * 2)


## One Pursuit against a side that either switches or stands and fights, with the
## same seed so only the doubling can differ.
func _pursuit_damage(switching: bool) -> int:
	var battle: Gen2Battle = _party_battle(
		[
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		],
		[_mon(Fixture.PIKACHU, 50, [Fixture.PURSUIT])]
	)
	battle.rng.seed = 4242
	var target: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(0)
	var before: int = target.hp
	battle.take_actions(
		Gen2Battle.switch_to(1) if switching else Gen2Battle.use_move(0),
		Gen2Battle.use_move(0)
	)
	return before - target.hp


## `PassedBattleMonEntrance` calls no `PursuitSwitch`, so a Baton Pass is not
## pursued even though it is a switch made from inside a move.
func test_a_baton_pass_is_not_pursued() -> void:
	var battle: Gen2Battle = _party_battle(
		[
			_mon(Fixture.GEODUDE, 50, [Fixture.BATON_PASS]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		],
		[_mon(Fixture.PIKACHU, 50, [Fixture.PURSUIT])]
	)
	var leaving: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(0)
	battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(battle.awaiting_baton_pass(), Gen2Battle.PLAYER)
	var full: int = leaving.hp
	battle.pass_to(1)

	assert_eq(leaving.hp, full, "nothing hit it on the way out")


## `ForcePlayerMonChoice` calls none either: a replacement after a faint is not a
## chosen switch and nothing pursues it.
func test_a_replacement_after_a_faint_is_not_pursued() -> void:
	var battle: Gen2Battle = _party_battle(
		[
			_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
			_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE]),
		],
		[_mon(Fixture.PIKACHU, 50, [Fixture.PURSUIT])]
	)
	_faint(battle.party(Gen2Battle.PLAYER).at(0))
	var arriving: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(1)
	battle.send_out(Gen2Battle.PLAYER, 1)

	assert_eq(arriving.hp, arriving.max_hp())
	assert_false(battle.is_switching(Gen2Battle.PLAYER),
		"no turn is in flight, so no flag is up")


## Teleport in a whole turn: the wild battle ends and the turn stops where it is,
## the same shape a Whirlwind against a wild takes.
func test_teleport_ends_the_turn_and_the_battle() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TELEPORT]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)

	assert_true(battle.is_over())
	assert_eq(battle.forced_out_side(), Gen2Battle.PLAYER)
	assert_null(battle.winner())
	assert_eq(_of_type(events, Gen2Battle.FLED_FROM_BATTLE).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.OVER).size(), 1)
	# Pikachu at 50 outruns Geodude, so the enemy's own move is what does not run.
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1)


## The same `ret nz` a Whirlwind against a wild reaches, which is the end-of-turn
## tail rather than the other side's move here: Whirlwind's priority of 0 puts it
## second against an ordinary attack, so both Pokémon have already moved.
func test_a_wild_force_switch_skips_the_end_of_turn_tail() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.WHIRLWIND]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.weather = Gen2Weather.SANDSTORM
	battle.weather_turns = Gen2Weather.TURNS
	var events: Array = battle.take_turn(0, 0)

	assert_true(battle.was_forced_out())
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_SANDSTORM).size(), 0,
		"`ResidualDamage` sits behind the `ret nz`")
	assert_eq(battle.weather_turns, Gen2Weather.TURNS, "and so does the weather count")
	assert_eq(_of_type(events, Gen2Battle.OVER).size(), 1)


## `PlayBattleMusic` (engine/battle/start_battle.asm), whose whole answer is the
## battle type, the trainer class and id, the landmark and `wTimeOfDay`.
const JOHTO_LANDMARK: int = Gen2WorldRadio.LANDMARK_RUINS_OF_ALPH
const KANTO_LANDMARK: int = Gen2WorldRadio.KANTO_LANDMARK


func _music(
	trainer_class: int = 0,
	landmark: int = JOHTO_LANDMARK,
	time_of_day: int = Gen2WorldPalette.TIME_DAY,
	trainer_id: int = 1,
	battle_type: int = Gen2Battle.BATTLETYPE_NORMAL,
) -> int:
	return Gen2Battle.battle_music(
		battle_type, trainer_class, trainer_id, landmark, time_of_day
	)


func test_a_wild_battle_takes_the_region_and_the_hour() -> void:
	assert_eq(_music(), Gen2Battle.MUSIC_JOHTO_WILD_BATTLE)
	assert_eq(
		_music(0, JOHTO_LANDMARK, Gen2WorldPalette.TIME_NIGHT),
		Gen2Battle.MUSIC_JOHTO_WILD_BATTLE_NIGHT
	)
	## Kanto has one wild track, so the hour does not reach it.
	assert_eq(_music(0, KANTO_LANDMARK), Gen2Battle.MUSIC_KANTO_WILD_BATTLE)
	assert_eq(
		_music(0, KANTO_LANDMARK, Gen2WorldPalette.TIME_NIGHT),
		Gen2Battle.MUSIC_KANTO_WILD_BATTLE
	)


## `cp BATTLETYPE_SUICUNE` and `cp BATTLETYPE_ROAMING` both `jp z, .done` with
## `MUSIC_SUICUNE_BATTLE` already in `de`, and both sit in front of the trainer
## check, so a trainer class cannot take either of them off.
func test_the_two_battle_types_in_front_answer_before_anything_else() -> void:
	for battle_type: int in [Gen2Battle.BATTLETYPE_SUICUNE, Gen2Battle.BATTLETYPE_ROAMING]:
		assert_eq(
			_music(0, JOHTO_LANDMARK, Gen2WorldPalette.TIME_DAY, 1, battle_type),
			Gen2Battle.MUSIC_SUICUNE_BATTLE
		)
		assert_eq(
			_music(
				Gen2Battle.TRAINER_CLASS_CHAMPION, KANTO_LANDMARK,
				Gen2WorldPalette.TIME_DAY, 1, battle_type
			),
			Gen2Battle.MUSIC_SUICUNE_BATTLE
		)


func test_the_champion_and_red_answer_before_the_leader_lists() -> void:
	assert_eq(_music(Gen2Battle.TRAINER_CLASS_CHAMPION), Gen2Battle.MUSIC_CHAMPION_BATTLE)
	assert_eq(_music(Gen2Battle.TRAINER_CLASS_RED), Gen2Battle.MUSIC_CHAMPION_BATTLE)


## `docs/bugs_and_glitches.md`: only the two grunt classes reach the Rocket
## track. EXECUTIVEM and EXECUTIVEF fall through to the ordinary trainer rows.
func test_only_the_two_grunt_classes_reach_the_rocket_track() -> void:
	assert_eq(_music(Gen2Battle.TRAINER_CLASS_GRUNTM), Gen2Battle.MUSIC_ROCKET_BATTLE)
	assert_eq(_music(Gen2Battle.TRAINER_CLASS_GRUNTF), Gen2Battle.MUSIC_ROCKET_BATTLE)
	assert_eq(_music(0x33), Gen2Battle.MUSIC_JOHTO_TRAINER_BATTLE, "EXECUTIVEM")
	assert_eq(_music(0x37), Gen2Battle.MUSIC_JOHTO_TRAINER_BATTLE, "EXECUTIVEF")
	assert_eq(_music(0x14), Gen2Battle.MUSIC_JOHTO_TRAINER_BATTLE, "SCIENTIST")


func test_the_kanto_list_is_checked_before_the_johto_one() -> void:
	for leader: int in Gen2Battle.KANTO_GYM_LEADERS:
		assert_eq(
			_music(leader), Gen2Battle.MUSIC_KANTO_GYM_LEADER_BATTLE,
			"class %d" % leader
		)
	for leader: int in Gen2Battle.JOHTO_GYM_LEADERS:
		if leader in [Gen2Battle.TRAINER_CLASS_CHAMPION, Gen2Battle.TRAINER_CLASS_RED]:
			continue
		assert_eq(
			_music(leader), Gen2Battle.MUSIC_JOHTO_GYM_LEADER_BATTLE,
			"class %d" % leader
		)


## `cp RIVAL2_2_CHIKORITA / jr c, .done` keeps the three ids below the Indigo
## Plateau rematch on the rival's own track and gives it the champion's.
func test_the_second_rival_class_splits_on_its_trainer_id() -> void:
	assert_eq(_music(Gen2Battle.TRAINER_CLASS_RIVAL1), Gen2Battle.MUSIC_RIVAL_BATTLE)
	for id: int in [1, 2, 3]:
		assert_eq(
			_music(Gen2Battle.TRAINER_CLASS_RIVAL2, JOHTO_LANDMARK,
				Gen2WorldPalette.TIME_DAY, id),
			Gen2Battle.MUSIC_RIVAL_BATTLE, "id %d" % id
		)
	for id: int in [4, 5, 6]:
		assert_eq(
			_music(Gen2Battle.TRAINER_CLASS_RIVAL2, JOHTO_LANDMARK,
				Gen2WorldPalette.TIME_DAY, id),
			Gen2Battle.MUSIC_CHAMPION_BATTLE, "id %d" % id
		)


func test_an_ordinary_trainer_takes_the_region() -> void:
	assert_eq(_music(0x16), Gen2Battle.MUSIC_JOHTO_TRAINER_BATTLE, "YOUNGSTER in Johto")
	assert_eq(
		_music(0x16, KANTO_LANDMARK), Gen2Battle.MUSIC_KANTO_TRAINER_BATTLE,
		"YOUNGSTER in Kanto"
	)


## `RegionCheck` is not `IsInJohto`: the Fast Ship is Johto on both, and so is
## Victory Road and everything above it, which `IsInJohto` calls Kanto.
func test_region_check_keeps_the_fast_ship_and_victory_road_in_johto() -> void:
	assert_false(Gen2Battle.region_is_kanto(Gen2WorldRadio.LANDMARK_FAST_SHIP))
	assert_false(Gen2Battle.region_is_kanto(Gen2Battle.LANDMARK_VICTORY_ROAD))
	assert_false(Gen2Battle.region_is_kanto(Gen2Battle.LANDMARK_VICTORY_ROAD + 1))
	assert_true(Gen2Battle.region_is_kanto(Gen2Battle.LANDMARK_VICTORY_ROAD - 1))
	assert_true(Gen2Battle.region_is_kanto(Gen2WorldRadio.KANTO_LANDMARK))
	assert_false(Gen2Battle.region_is_kanto(Gen2WorldRadio.KANTO_LANDMARK - 1))
	## Gold and Silver's table is one shorter from LANDMARK_BATTLE_TOWER on.
	assert_true(Gen2Battle.region_is_kanto(Gen2WorldRadio.KANTO_LANDMARK - 1, false))
	assert_false(Gen2Battle.region_is_kanto(Gen2WorldRadio.LANDMARK_FAST_SHIP - 1, false))
