class_name Gen2Battle
extends RefCounted

## A battle: two parties, a turn at a time.
##
## [RefCounted] and scene-free, with its randomness injected, so a whole battle
## can be fought inside a test with no display. It knows nothing about how a
## battle is drawn.
##
## A turn answers with a list of events rather than with a new state or a string.
## An event says what happened and carries the numbers behind it; turning that
## into a sentence, an animation or a bar that drains is the screen's job, and
## keeping the two apart is what lets a battle be asserted on rather than read.
##
## A side is a party, and a wild encounter is a party of one. Two things are the
## caller's to decide rather than this class's, because the cartridge asks a
## person or an AI for both and neither exists yet: which action a side takes,
## and who replaces a Pokémon that has fainted. A turn that ends with somebody
## down stops there and says so through [method must_replace]; nothing is sent
## out until [method send_out] is called.

## The two sides, as plain numbers rather than an enum: they are dictionary keys
## and event payloads throughout, and an enum buys nothing where everything that
## reads one is comparing it against these two constants.
const PLAYER: int = 0
const ENEMY: int = 1

## What a turn can report. Every event carries [code]side[/code], which is
## whoever acted, and the rest depends on the type.
const USED_MOVE: StringName = &"used_move"
const MISSED: StringName = &"missed"
const NO_EFFECT: StringName = &"no_effect"
const HIT: StringName = &"hit"
const RECOIL: StringName = &"recoil"
const FAINTED: StringName = &"fainted"
## A multi-hit move's own summary, once every planned hit has landed. Not
## shown at all if the target faints partway through: the cartridge's own
## loop jumps straight to ending the move on a faint, before it ever reaches
## the line that would have said how many times it hit.
const HIT_TIMES: StringName = &"hit_times"
## A draining move healed the attacker off what it dealt.
const DRAINED: StringName = &"drained"
## A one-hit KO landed. Its own event rather than a flag on [constant HIT]:
## the cartridge shows neither a critical hit nor an effectiveness line for
## one, since the damage was never actually multiplied by either.
const OHKO: StringName = &"ohko"
## A status stopped a Pokémon moving. [code]reason[/code] says which one, since
## the six read differently and not all of them are a surprise: [code]&"sleep"[/code],
## [code]&"freeze"[/code], [code]&"paralysis"[/code], [code]&"flinch"[/code],
## [code]&"recharge"[/code].
const CANNOT_MOVE: StringName = &"cannot_move"
const WOKE_UP: StringName = &"woke_up"
const THAWED: StringName = &"thawed"
## A status put on a Pokémon, and a slice taken off by one it already had.
const STATUS_INFLICTED: StringName = &"status_inflicted"
const HURT_BY_STATUS: StringName = &"hurt_by_status"
## Confusion put on a target. Not [constant STATUS_INFLICTED]: confusion lives
## on [Gen2Substatus] rather than the status byte, and a Pokémon can carry both
## at once.
const CONFUSE_INFLICTED: StringName = &"confuse_inflicted"
## Confusion said every turn it is still there, and the turn it lifts.
const CONFUSED: StringName = &"confused"
const SNAPPED_OUT: StringName = &"snapped_out"
## A confused Pokémon hit itself instead of moving.
const HURT_ITSELF: StringName = &"hurt_itself"
## The first half of a two-turn move: the user is locked in and nothing else
## happens this turn. See [method move_for] for the second half.
const CHARGING_UP: StringName = &"charging_up"
## Haze: every stage on both sides is gone. About both sides, like [constant OVER].
const STAGES_CLEARED: StringName = &"stages_cleared"
## Psych Up: the target's stages, now the user's too.
const STAGES_COPIED: StringName = &"stages_copied"
## A stat moved a stage, or tried to and could not. [code]stat[/code] is the key
## [Gen2BattleMon] keeps it under, or [code]"all"[/code] for the five Ancientpower
## moves at once; [code]by[/code] is how many stages, signed.
const STAT_CHANGED: StringName = &"stat_changed"
const STAT_CHANGE_FAILED: StringName = &"stat_change_failed"
## A Pokémon called back, and a Pokémon put out. They are two events rather than
## one because a replacement after a faint is only the second half: there is
## nobody to call back, and the screen has one sentence to say rather than two.
const WITHDREW: StringName = &"withdrew"
const SENT_OUT: StringName = &"sent_out"
const OVER: StringName = &"over"

## Experience, once whoever fainted's own opponent has somebody left to award
## it to. Never emitted for [constant ENEMY]: the cartridge's own
## [code]GiveExperiencePoints[/code] only ever reads the player's own party
## structure, so a trainer's Pokémon are never on the receiving end of this,
## only ever the reason for it.
const EXP_GAINED: StringName = &"exp_gained"
## The five stats in [constant Gen2Experience.STAT_EXP_KEYS], split among
## [constant Gen2Battle] participants the way [method Gen2Experience.stat_exp_gain]
## splits them, none of it the same number as [constant EXP_GAINED].
const STAT_EXP_GAINED: StringName = &"stat_exp_gained"
## A level gained from the experience just awarded. [code]old_stats[/code] and
## [code]new_stats[/code] are both [Gen2BattleMon.stats], so a screen can show
## what moved without asking the Pokémon twice.
const GREW_LEVEL: StringName = &"grew_level"
## A move learned into a slot that had nothing in it, no question asked because
## the cartridge does not ask one when there is nowhere for the answer to go.
const MOVE_LEARNED: StringName = &"move_learned"
## Every slot already held something, so nothing was learned automatically:
## see [method must_learn_move].
const MOVE_OFFERED: StringName = &"move_offered"
## The offer from [constant MOVE_OFFERED] was answered, one way or the other.
const MOVE_FORGOTTEN: StringName = &"move_forgotten"
const MOVE_DECLINED: StringName = &"move_declined"

## Disable, Attract, Encore, Mist and Focus Energy each refuse for their own
## reason (a target with nothing to disable, a same-gender or genderless
## target, an already-encored target, and so on) rather than missing or doing
## nothing to a type: not [constant MISSED], whose accuracy was rolled and
## lost, and not [constant NO_EFFECT], which is about a type matchup. One event
## for every one of the five, the same "but it failed!" the cartridge shares
## across all of them.
const MOVE_FAILED: StringName = &"move_failed"

## Disable locked a slot, and later let it go. [code]slot[/code] and
## [code]move[/code] on the first are the target's own, read off
## [member Gen2BattleMon.disabled_slot] before it moves; the belt-and-suspenders
## refusal for a Pokémon that is still locked into the disabled move itself is
## [constant CANNOT_MOVE]'s own [code]&"disabled"[/code] reason, not this.
const DISABLE_INFLICTED: StringName = &"disable_inflicted"
const DISABLE_ENDED: StringName = &"disable_ended"

## Attract's own two events: falling in love, which is
## [constant Gen2Substatus.ATTRACTED] set and stays set until a switch, and the
## turn a fresh roll finds the target too smitten to move, which is
## [constant CANNOT_MOVE]'s own [code]&"attract"[/code] reason rather than an
## event of its own, the same shape flinch and confusion already use.
const ATTRACT_INFLICTED: StringName = &"attract_inflicted"

## Encore locked a slot, and later let it go, the same pair
## [constant DISABLE_INFLICTED] and [constant DISABLE_ENDED] are for Disable.
const ENCORE_INFLICTED: StringName = &"encore_inflicted"
const ENCORE_ENDED: StringName = &"encore_ended"

## Mist and Focus Energy, set on the user. Both fail with [constant MOVE_FAILED]
## on a second use rather than silently re-applying.
const MIST_SET: StringName = &"mist_set"
const FOCUS_ENERGY_SET: StringName = &"focus_energy_set"

## A stat drop blocked by the target's own Mist. Not [constant STAT_CHANGE_FAILED]:
## the cartridge prints a line of its own ("It's protected by mist!") rather
## than the generic "won't go any lower" a drop already at its floor gets, and a
## screen that read this as the generic failure would say the wrong thing.
const MIST_PROTECTED: StringName = &"mist_protected"

## What a side does with its turn. Switching is not a move with a very high
## priority: it is settled before priority is looked at, which is why it is an
## action rather than a move number.
const ACTION_MOVE: StringName = &"move"
const ACTION_SWITCH: StringName = &"switch"

## Priority runs from 0 to 3 and most moves are 1, so a move can go below the
## ordinary as well as above it. The values are keyed by the move's effect byte,
## which the cache already carries.
const BASE_PRIORITY: int = 1
const EFFECT_PRIORITIES: Dictionary = {
	0x6F: 3,  # Protect
	0x74: 3,  # Endure
	0x67: 2,  # Quick Attack, Extreme Speed, Mach Punch
	0x1C: 0,  # Whirlwind and Roar
	0x59: 0,  # Counter
	0x90: 0,  # Mirror Coat
}

## Vital Throw is slower than everything and says so in the move itself rather
## than through its effect, so it is the one move the table cannot answer for.
const VITAL_THROW: int = 0xE9


var data: GameData = null
var rng: RandomNumberGenerator = null

## Whether beating this opponent is worth the 1.5x [Gen2Experience] gives a
## trainer battle. A wild encounter (the default, and every existing caller's
## meaning before this field existed) never sets it.
var is_trainer_battle: bool = false

## The two sides, keyed by [constant PLAYER] and [constant ENEMY].
var parties: Dictionary = {}

## Which of a side's own party indices have fought since the opponent currently
## out was sent in, kept as a Dictionary used for its keys. Seeded with the
## lead at [method create_parties], added to on every [method send_out], and
## reset to just whoever is left standing once experience has been given for
## the opponent that just fainted: see [method _award_experience].
##
## Only [constant PLAYER]'s side is ever read for anything, mirroring the
## cartridge's own asymmetry (see [constant EXP_GAINED]), but both sides are
## tracked the same way rather than leaving one of them a special case.
var _participants: Dictionary = {PLAYER: {}, ENEMY: {}}

## The last direct damage each side took during the current pair of actions.
## Counter and Mirror Coat read this after the faster side has acted. It is
## cleared at the start of every action pair, because the cartridge's own
## `wCurDamage` is a move-local value rather than a battle-long history.
var _last_damage_taken: Dictionary = {PLAYER: {}, ENEMY: {}}

## Moves waiting on [method learn_move] or [method decline_move], one queue per
## side, FIFO: a level that teaches two moves into a full six-move team asks
## about both, one at a time, in the order they were learned.
var _move_learn_queue: Dictionary = {PLAYER: [], ENEMY: []}

## Whoever is out on each side. Read through the party every time rather than
## kept in step with it: a switch changes who this is, and a copy that had to be
## updated is a copy that will one day not be.
var player: Gen2BattleMon:
	get:
		return party(PLAYER).active_mon()
var enemy: Gen2BattleMon:
	get:
		return party(ENEMY).active_mon()


## Two parties, each led by whoever is first in it.
static func create_parties(
	game_data: GameData,
	player_party: Gen2Party,
	enemy_party: Gen2Party,
	generator: RandomNumberGenerator,
	trainer_battle: bool = false
) -> Gen2Battle:
	if game_data == null or player_party == null or enemy_party == null:
		return null
	if player_party.is_wiped() or enemy_party.is_wiped():
		return null

	var out := Gen2Battle.new()
	out.data = game_data
	out.parties = {PLAYER: player_party, ENEMY: enemy_party}
	out.rng = generator if generator != null else RandomNumberGenerator.new()
	out.is_trainer_battle = trainer_battle
	out._participants = {PLAYER: {player_party.active: true}, ENEMY: {enemy_party.active: true}}
	return out


## One Pokémon a side, which is what a wild encounter is.
static func create(
	game_data: GameData,
	player_mon: Gen2BattleMon,
	enemy_mon: Gen2BattleMon,
	generator: RandomNumberGenerator
) -> Gen2Battle:
	if player_mon == null or enemy_mon == null:
		return null
	return create_parties(
		game_data, Gen2Party.of(player_mon), Gen2Party.of(enemy_mon), generator
	)


## What a side asks for with its turn.
static func use_move(slot: int) -> Dictionary:
	return {"type": ACTION_MOVE, "slot": slot}


static func switch_to(index: int) -> Dictionary:
	return {"type": ACTION_SWITCH, "index": index}


func party(side: int) -> Gen2Party:
	return parties[side]


func mon(side: int) -> Gen2BattleMon:
	return party(side).active_mon()


func opponent_of(side: int) -> int:
	return ENEMY if side == PLAYER else PLAYER


## Clears the damage that Counter and Mirror Coat are allowed to remember.
## Residual damage is deliberately not recorded: the cartridge's counter move
## reads the damage produced by the opponent's move, not end-of-turn status loss.
func reset_damage_taken() -> void:
	_last_damage_taken = {PLAYER: {}, ENEMY: {}}


## Keeps the uncapped damage figure, the move that produced it and its source
## side. The command layer calls this before HP clamping, matching the
## cartridge's `wCurDamage` rather than the amount that happened to remain.
func record_damage_taken(target: int, source: int, move_number: int, effect: int, amount: int) -> void:
	if amount <= 0 or target not in [PLAYER, ENEMY] or source not in [PLAYER, ENEMY]:
		return
	_last_damage_taken[target] = {
		"damage": amount,
		"source": source,
		"move": move_number,
		"effect": effect,
	}


func last_damage_taken(side: int) -> Dictionary:
	return _last_damage_taken.get(side, {})


## A battle is lost when a whole party is down, not when the Pokémon that is out
## has fainted. One of those is a defeat and the other is a Pokémon to replace.
func is_over() -> bool:
	return party(PLAYER).is_wiped() or party(ENEMY).is_wiped()


## Whoever is still standing, or null if the battle is not over. Both sides can
## go down in one turn, through recoil; the cartridge gives it to whoever is left
## and there is nobody, so this answers null for that too.
func winner() -> Variant:
	if not is_over():
		return null
	if party(PLAYER).is_wiped() and party(ENEMY).is_wiped():
		return null
	return ENEMY if party(PLAYER).is_wiped() else PLAYER


## Whether a side is waiting for somebody to be sent out: the Pokémon that was
## out has fainted and there is still a party behind it. Nothing else can happen
## on either side until it is answered, which is the cartridge's order too.
func must_replace(side: int) -> bool:
	var current: Gen2Party = party(side)
	return current.active_mon().is_fainted() and not current.is_wiped()


func awaiting_replacement() -> bool:
	return must_replace(PLAYER) or must_replace(ENEMY)


## Whether [param side] has a move waiting on [method learn_move] or
## [method decline_move]: every slot already held something when a level
## taught it a new one, so nothing was learned without asking, the same
## refusal-until-answered shape [method must_replace] already uses.
func must_learn_move(side: int) -> bool:
	return not (_move_learn_queue.get(side, []) as Array).is_empty()


func awaiting_move_learn() -> bool:
	return must_learn_move(PLAYER) or must_learn_move(ENEMY)


## The offer waiting on [param side], or an empty Dictionary if there is none.
## [code]species[/code], [code]index[/code], [code]move[/code] and
## [code]level[/code] are enough to say "your FOO wants to learn BAR" without
## asking the Pokémon anything a caller cannot already read off the event that
## put this here.
func pending_learn(side: int) -> Dictionary:
	var queue: Array = _move_learn_queue.get(side, [])
	return queue[0] if not queue.is_empty() else {}


## Answers a pending offer by giving up [param forget_slot] for it. Refuses if
## there is nothing pending: an answer to a question nobody asked is not
## approximated into one that was.
func learn_move(side: int, forget_slot: int) -> Array:
	if not must_learn_move(side):
		return []

	var offer: Dictionary = (_move_learn_queue[side] as Array).pop_front()
	var learner: Gen2BattleMon = party(side).at(int(offer["index"]))
	if learner == null or forget_slot < 0 or forget_slot >= learner.moves.size():
		return []

	var forgot: int = int(learner.moves[forget_slot])
	if not learner.replace_move(forget_slot, int(offer["move"])):
		return []

	return [{
		"type": MOVE_FORGOTTEN, "side": side, "index": int(offer["index"]),
		"species": learner.species, "forgot": forgot, "learned": int(offer["move"]), "slot": forget_slot,
	}]


## Answers a pending offer by refusing it: the Pokémon keeps its four moves and
## never learns the fifth.
func decline_move(side: int) -> Array:
	if not must_learn_move(side):
		return []

	var offer: Dictionary = (_move_learn_queue[side] as Array).pop_front()
	return [{
		"type": MOVE_DECLINED, "side": side, "index": int(offer["index"]),
		"species": int(offer["species"]), "move": int(offer["move"]),
	}]


## Sends a side's [param index] out, whether as a replacement or between turns.
## Returns the events, which is one event or none: a switch that cannot be made
## is refused rather than approximated.
func send_out(side: int, index: int) -> Array:
	var events: Array = []
	if is_over():
		return events

	var current: Gen2Party = party(side)
	var leaving: int = current.active
	var leaving_species: int = current.active_mon().species
	var withdrawing: bool = not current.active_mon().is_fainted()
	if not current.send_out(index):
		return events

	# Nothing is called back after a faint, so the first half of the pair is only
	# there when there was somebody to call back.
	if withdrawing:
		events.append({
			"type": WITHDREW, "side": side, "index": leaving, "species": leaving_species,
		})
	events.append({
		"type": SENT_OUT, "side": side, "index": index,
		"species": current.active_mon().species, "level": current.active_mon().level,
		"hp": current.active_mon().hp, "max_hp": current.active_mon().max_hp(),
	})
	(_participants[side] as Dictionary)[index] = true
	return events


## Both sides act, and the turn plays out. Returns the events in the order they
## happened.
##
## An action is [method use_move] or [method switch_to]. Nothing happens while
## either side owes a replacement, and a faint ends the turn where it is: a
## Pokémon that is knocked out before it has moved does not get to move, which is
## most of what speed is for.
##
## The move each side is credited with for [method order]'s own priority check
## is worked out once, before either side has acted, because that is the
## moment the cartridge's own move order is decided too. What actually runs is
## worked out again, fresh, right before [method _act]: Encore can land on a
## side that has not gone yet this same turn, and the cartridge's own
## `CheckOpponentWentFirst` forces that side's already-chosen action over for
## the very turn it lands, not just the ones after it. Recomputing at the
## point of use rather than committing to [param chosen] gets that for free,
## since nothing about which move a side actually uses is settled until this
## reaches it.
func take_actions(player_action: Dictionary, enemy_action: Dictionary) -> Array:
	var events: Array = []
	if is_over() or awaiting_replacement() or awaiting_move_learn():
		return events
	reset_damage_taken()

	var actions: Dictionary = {PLAYER: player_action, ENEMY: enemy_action}
	var chosen: Dictionary = {
		PLAYER: _move_for_action(PLAYER, player_action),
		ENEMY: _move_for_action(ENEMY, enemy_action),
	}

	var acting: Array = order(chosen, actions)
	for side: int in acting:
		if _is_switch(actions[side]):
			events.append_array(send_out(side, int(actions[side].get("index", -1))))
			continue
		if mon(side).is_fainted() or mon(opponent_of(side)).is_fainted():
			break
		var slot: int = effective_slot(side, int(actions[side].get("slot", 0)))
		_act(side, slot, move_for(side, slot), events)

	_residual_damage(acting, events)
	_tick_encore(acting, events)
	_award_experience(events)

	if is_over():
		events.append({"type": OVER, "winner": winner()})
	return events


## Both sides use a move slot, which is the common case and the whole of a battle
## that has one Pokémon a side.
func take_turn(player_slot: int, enemy_slot: int) -> Array:
	return take_actions(use_move(player_slot), use_move(enemy_slot))


## What a burn or a poison takes at the end of the turn, from each side in the
## order it acted.
##
## After both moves rather than after each, and skipping whoever is already down:
## a Pokémon that has fainted this turn is not burned any further, and one that
## goes down to its burn faints here rather than in the middle of somebody's move.
##
## A poisoned Pokémon with a running [member Gen2BattleMon.toxic_counter] is
## the one Toxic left, and it ramps instead of taking the flat eighth every
## other poison and every burn take; the counter itself goes up here, once a
## turn, so the turn it was inflicted on counts as the first.
func _residual_damage(acting: Array, events: Array) -> void:
	for side: int in acting:
		var current: Gen2BattleMon = mon(side)
		if current.is_fainted():
			continue
		if not Gen2Status.has(current.status, Gen2Status.BURN | Gen2Status.POISON):
			continue

		var amount: int
		if Gen2Status.has(current.status, Gen2Status.POISON) and current.toxic_counter > 0:
			amount = Gen2Status.toxic_damage(current.max_hp(), current.toxic_counter)
			current.toxic_counter += 1
		else:
			amount = Gen2Status.residual_damage(current.max_hp())

		var taken: int = current.take_damage(amount)
		events.append({
			"type": HURT_BY_STATUS,
			"side": side,
			"status": current.status,
			"name": Gen2Status.name_of(current.status),
			"amount": taken,
			"hp": current.hp,
			"max_hp": current.max_hp(),
		})
		if current.is_fainted():
			events.append({"type": FAINTED, "side": side})


## Encore's own countdown, once a turn rather than once a side's move: the
## cartridge's own `HandleEncore` runs after both sides have acted, the same
## timing [method _residual_damage] already uses for a burn or a poison.
##
## Ends early, before the counter reaches zero, the moment the encored slot
## itself runs out of PP: the cartridge checks that every turn Encore ticks,
## not only when the counter would have expired on its own.
func _tick_encore(acting: Array, events: Array) -> void:
	for side: int in acting:
		var current: Gen2BattleMon = mon(side)
		if current.is_fainted() or current.encored_slot < 0:
			continue

		current.encore_turns -= 1
		if current.encore_turns > 0 and current.pp_left(current.encored_slot) > 0:
			continue

		current.encored_slot = -1
		current.encore_turns = 0
		events.append({"type": ENCORE_ENDED, "side": side})


## Experience for every enemy Pokémon that fainted this turn, whether the faint
## came from a move ([method _act], already in [param events] by the time this
## runs) or from status damage ([method _residual_damage], run just before
## this).
##
## A side's own [constant FAINTED] clears its fainted member out of
## [member _participants] regardless of which side it is, because that half of
## the rule (a fainted Pokémon stops participating) is not specific to the
## side that receives experience; only [method _give_experience_for] is.
func _award_experience(events: Array) -> void:
	for event: Dictionary in events.duplicate():
		if StringName(event.get("type", "")) != FAINTED:
			continue
		var side: int = int(event["side"])
		(_participants[side] as Dictionary).erase(party(side).active)
		if side == ENEMY:
			_give_experience_for(mon(ENEMY), events)


## Splits the exp and the stat exp [param defeated] is worth among every
## [constant PLAYER] party index that has fought since it was sent in, then
## resets that set to whoever is left standing: the next enemy Pokémon, if the
## trainer has one, starts its own participant count fresh.
func _give_experience_for(defeated: Gen2BattleMon, events: Array) -> void:
	var participants: Array = (_participants[PLAYER] as Dictionary).keys()
	if not participants.is_empty():
		var award: int = Gen2Experience.award_for(
			defeated.level, defeated.base_exp(), is_trainer_battle
		)
		var stat_gains: Dictionary = Gen2Experience.stat_exp_gain(
			defeated.base_stat_exp_shape(), participants.size()
		)
		for index: int in participants:
			var learner: Gen2BattleMon = party(PLAYER).at(int(index))
			if learner != null and not learner.is_fainted():
				_give_experience_to(learner, int(index), award, stat_gains, events)

	_participants[PLAYER] = {party(PLAYER).active: true}


func _give_experience_to(
	learner: Gen2BattleMon, index: int, award: int, stat_gains: Dictionary, events: Array
) -> void:
	learner.gain_exp(award)
	events.append({
		"type": EXP_GAINED, "side": PLAYER, "index": index,
		"species": learner.species, "amount": award, "exp": learner.exp,
	})

	learner.gain_stat_exp(stat_gains)
	events.append({
		"type": STAT_EXP_GAINED, "side": PLAYER, "index": index, "gains": stat_gains,
	})

	var target_level: int = learner.level_for_exp()
	while learner.level < target_level:
		var old_level: int = learner.level
		var old_stats: Dictionary = learner.stats.duplicate()
		learner.level_up()
		events.append({
			"type": GREW_LEVEL, "side": PLAYER, "index": index, "species": learner.species,
			"old_level": old_level, "new_level": learner.level,
			"old_stats": old_stats, "new_stats": learner.stats.duplicate(),
		})
		_offer_moves_learned_at(learner, index, learner.level, events)


## What [param learner] is taught at exactly [param level]: straight into an
## empty slot with no question asked, the same as the cartridge asks none when
## there is nowhere for the answer to go, or queued for [method learn_move] or
## [method decline_move] when every slot already holds something.
func _offer_moves_learned_at(learner: Gen2BattleMon, index: int, level: int, events: Array) -> void:
	for move: int in data.moves_learned_at(learner.species, level):
		if learner.moves.has(move):
			continue
		if learner.learn_move(move):
			events.append({
				"type": MOVE_LEARNED, "side": PLAYER, "index": index,
				"species": learner.species, "move": move, "slot": learner.moves.size() - 1,
			})
		else:
			(_move_learn_queue[PLAYER] as Array).append({
				"index": index, "move": move, "level": level, "species": learner.species,
			})
			events.append({
				"type": MOVE_OFFERED, "side": PLAYER, "index": index,
				"species": learner.species, "move": move, "level": level,
			})


static func _is_switch(action: Dictionary) -> bool:
	return StringName(action.get("type", ACTION_MOVE)) == ACTION_SWITCH


## The move an action commits a side to, which is nothing at all for a switch.
## Struggle stands in there so that the order can be worked out without a special
## case; a switching side never reaches the point of using it.
func _move_for_action(side: int, action: Dictionary) -> int:
	if _is_switch(action):
		return Gen2Damage.STRUGGLE
	return move_for(side, int(action.get("slot", 0)))


## The slot PP is actually spent from, which is not always the slot a caller
## asks for: Encore forces whichever slot it locked in, the same way a
## two-turn move's release turn forces its own move number regardless of which
## slot [method move_for] is asked about. Falls back to the encored slot only
## while it is still usable, so an encored move that has run out of PP does not
## reach for it once [method _tick_encore] has already ended the effect.
func effective_slot(side: int, requested_slot: int) -> int:
	var attacker: Gen2BattleMon = mon(side)
	if attacker.encored_slot >= 0 and attacker.can_use(attacker.encored_slot):
		return attacker.encored_slot
	return requested_slot


## Which move a side will actually use.
##
## A Pokémon locked into a two-turn move's release turn answers with what it
## charged, whatever slot the caller asks for: on the cartridge nothing is
## chosen on that turn at all, so nothing here is either. Failing that, Encore
## answers with whatever [method effective_slot] resolves to, which may not be
## the slot the caller asked for either.
##
## Failing that, a slot with nothing usable in it answers Struggle, which is
## the cartridge's answer for a Pokémon with no PP anywhere. Here it is also the
## answer for a slot that is empty, spent or disabled while others are not,
## because a caller that points at one has asked for something that cannot
## happen, and Struggle is the only move that is always available.
func move_for(side: int, slot: int) -> int:
	var attacker: Gen2BattleMon = mon(side)
	if attacker.charged_move != 0:
		return attacker.charged_move
	var chosen_slot: int = effective_slot(side, slot)
	return int(attacker.moves[chosen_slot]) if attacker.can_use(chosen_slot) else Gen2Damage.STRUGGLE


## Who goes first, as the two sides in the order they act.
##
## A switch is settled before any of this: the cartridge sends the incoming
## Pokémon out and then lets the other side's move hit it, so a side that is
## switching acts first however fast the other one is and whatever priority its
## move has. Two switches in the same turn go to the player, which is what the
## cartridge does outside a link battle.
##
## Failing that, priority decides it; equal priority goes to the faster Pokémon,
## by its speed with stages applied; and a genuine tie is a coin flip. The
## cartridge weighs a held Quick Claw between the priority and the speed, which
## nothing here carries yet.
func order(chosen: Dictionary, actions: Dictionary = {}) -> Array:
	var player_switching: bool = _is_switch(actions.get(PLAYER, {}))
	var enemy_switching: bool = _is_switch(actions.get(ENEMY, {}))
	if player_switching or enemy_switching:
		return _sides(player_switching)

	var player_priority: int = priority_of(data.move(int(chosen[PLAYER])))
	var enemy_priority: int = priority_of(data.move(int(chosen[ENEMY])))
	if player_priority != enemy_priority:
		return _sides(player_priority > enemy_priority)

	var player_speed: int = player.stat("speed")
	var enemy_speed: int = enemy.stat("speed")
	if player_speed != enemy_speed:
		return _sides(player_speed > enemy_speed)

	return _sides(rng.randi_range(0, 255) < 128)


func _sides(player_first: bool) -> Array:
	return [PLAYER, ENEMY] if player_first else [ENEMY, PLAYER]


## A move's priority, from its effect byte.
static func priority_of(move: Dictionary) -> int:
	if int(move.get("number", 0)) == VITAL_THROW:
		return 0
	return int(EFFECT_PRIORITIES.get(int(move.get("effect", -1)), BASE_PRIORITY))


## One side's move, run as the list of commands its effect is made of.
##
## Nothing about what a particular move does lives here. The effect byte picks a
## sequence out of [Gen2MoveEffect], the commands in it are run in order against
## a [Gen2Turn] until one of them says the move is finished, and every rule about
## announcing, spending, rolling, applying and fainting is one of those commands.
## That is the cartridge's own arrangement, and it is what lets the rest of
## Generation 2 be written as commands rather than as branches in here.
func _act(side: int, slot: int, move_number: int, events: Array) -> void:
	var move: Dictionary = data.move(move_number)
	if move.is_empty():
		return

	var turn: Gen2Turn = Gen2Turn.create(self, side, slot, move_number, move, events)
	# The release turn of a two-turn move: the PP for it was already spent on
	# the charge turn, and [method Gen2EffectCommands._do_turn] reads this so it
	# is not spent again.
	turn.locked = mon(side).charged_move == move_number and move_number != 0

	# Whether the Pokémon can move at all is asked before the effect is looked up,
	# which is the cartridge's arrangement: every move goes through it, so no
	# sequence has to remember to include it.
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)

	for command: StringName in Gen2MoveEffect.sequence_for(turn.effect()):
		if turn.ended:
			return
		Gen2EffectCommands.run(command, turn)
