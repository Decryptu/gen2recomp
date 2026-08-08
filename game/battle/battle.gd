class_name Gen2Battle
extends RefCounted

## A battle: two parties, a turn at a time.
##
## [RefCounted], scene-free, randomness injected, so a whole battle can be fought
## in a test with no display.
##
## A turn answers with a list of events, not a new state or a string. An event
## says what happened and carries its numbers; sentences, animation and draining
## bars are the screen's job.
##
## A side is a party, and a wild encounter is a party of one. The caller decides
## which action a side takes and who replaces a fainted Pokémon: a turn that ends
## with somebody down stops and says so through [method must_replace], and
## nothing is sent out until [method send_out].

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
## The player got away. `how` says which branch answered: [code]&"battle_type"[/code]
## for the two types that always escape, [code]&"item"[/code] for the Smoke Ball,
## [code]&"speed"[/code] for the plain comparison, [code]&"odds"[/code] for the
## accumulated odds and [code]&"roll"[/code] for the last random check.
const FLED: StringName = &"fled"
## The roll came up short. The turn is spent and the enemy still acts, which is
## `.cant_escape_2` setting `wBattlePlayerAction` to `BATTLEPLAYERACTION_USEITEM`.
const RUN_FAILED: StringName = &"run_failed"
## Running was refused outright, which costs no turn at all: `BattleMenu_Run`
## reopens the menu. `reason` is [code]&"trainer"[/code] or
## [code]&"battle_type"[/code].
const RUN_BLOCKED: StringName = &"run_blocked"
const OVER: StringName = &"over"

## Experience, once the fainted Pokémon's opponent has somebody to award it to.
## Never emitted for [constant ENEMY]: [code]GiveExperiencePoints[/code] only
## reads the player's party structure, so a trainer's Pokémon are the reason for
## this, never the recipient.
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
## reason (nothing to disable, a same-gender or genderless target, an already
## encored target) rather than missing a roll ([constant MISSED]) or losing to a
## type ([constant NO_EFFECT]). One event for all five, the "but it failed!" the
## cartridge shares across them.
const MOVE_FAILED: StringName = &"move_failed"

## Disable locked a slot, and later let it go. [code]slot[/code] and
## [code]move[/code] on the first are the target's, read off
## [member Gen2BattleMon.disabled_slot] before it moves. A Pokémon still locked
## into the disabled move is refused through [constant CANNOT_MOVE]'s
## [code]&"disabled"[/code] reason, not here.
const DISABLE_INFLICTED: StringName = &"disable_inflicted"
const DISABLE_ENDED: StringName = &"disable_ended"

## Attract's two events: falling in love, [constant Gen2Substatus.ATTRACTED] set
## until a switch, and a turn where a fresh roll finds the target too smitten to
## move, which is [constant CANNOT_MOVE]'s [code]&"attract"[/code] reason rather
## than an event, the shape flinch and confusion use.
const ATTRACT_INFLICTED: StringName = &"attract_inflicted"

## Encore locked a slot, and later let it go, the same pair
## [constant DISABLE_INFLICTED] and [constant DISABLE_ENDED] are for Disable.
const ENCORE_INFLICTED: StringName = &"encore_inflicted"
const ENCORE_ENDED: StringName = &"encore_ended"

## What a held item gave back between turns. Leftovers keeps its own event
## because its line is the cartridge's own "recovered with", while a berry says
## "recovered using a"; [constant RECOVERED_USING_ITEM] covers both the HP berry
## and the status berries, which share `UseOpponentItem` and its text.
## [code]item[/code] on all four is what did it, and on the three consumable ones
## it is the number the Pokémon no longer holds.
const RECOVERED_WITH_ITEM: StringName = &"recovered_with_item"
const RECOVERED_USING_ITEM: StringName = &"recovered_using_item"
const RESTORED_PP: StringName = &"restored_pp"
const ITEM_HEALED_CONFUSION: StringName = &"item_healed_confusion"

## A Focus Band held the Pokémon on one hit point through what would have
## finished it. [code]item[/code] is what did it, since the cartridge's line
## names the item rather than the effect.
const ENDURED: StringName = &"endured"

## Rain Dance, Sunny Day and Sandstorm. [code]weather[/code] on all four is the
## [Gen2Weather] value, so a screen names it without being told twice.
## [constant WEATHER_CONTINUES] is the line printed on every turn the weather
## survives, which is the same turn a Sandstorm's damage lands on.
const WEATHER_STARTED: StringName = &"weather_started"
const WEATHER_CONTINUES: StringName = &"weather_continues"
const WEATHER_ENDED: StringName = &"weather_ended"
const HURT_BY_SANDSTORM: StringName = &"hurt_by_sandstorm"

## Bind, Wrap, Fire Spin, Clamp and Whirlpool: the target was bound, lost a
## sixteenth of its health to the binding, or was let go. [code]move[/code] on all
## three is the move that did it, which is what the cartridge's own texts name
## through `wStringBuffer1`. The release carries no damage, because the turn the
## counter reaches zero costs nothing.
const TRAPPED: StringName = &"trapped"
const HURT_BY_TRAP: StringName = &"hurt_by_trap"
const RELEASED_FROM_TRAP: StringName = &"released_from_trap"

## Mean Look and Spider Web landed. Set on the user, cleared by any send-out;
## a second one from the same user is [constant MOVE_FAILED].
const CANT_ESCAPE_SET: StringName = &"cant_escape_set"

## A switch `TryPlayerSwitch` refused, which costs nothing at all: it prints
## `BattleText_MonCantBeRecalled` and jumps back to `BattleMenuPKMN_Loop`, so no
## turn is spent and the enemy does not move. The same shape as
## [constant RUN_BLOCKED].
const SWITCH_BLOCKED: StringName = &"switch_blocked"

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
## Running is settled before the turn rather than inside it, because
## `BattleMenu_Run` runs at menu time: a successful run ends the battle before
## either side moves, and a refusal the player can do nothing about sends them
## back to the menu with no turn spent at all.
const ACTION_RUN: StringName = &"run"

## `wBattleType`. Only the values `TryToRunAwayFromBattle` branches on are named;
## everything else reaches the ordinary speed check.
const BATTLETYPE_NORMAL: int = 0
const BATTLETYPE_DEBUG: int = 2
const BATTLETYPE_CONTEST: int = 6
const BATTLETYPE_FORCESHINY: int = 7
const BATTLETYPE_TRAP: int = 9
const BATTLETYPE_CELEBI: int = 11
const BATTLETYPE_SUICUNE: int = 12
## The two lists it reads them against, in source order.
const ALWAYS_ESCAPES: Array[int] = [BATTLETYPE_DEBUG, BATTLETYPE_CONTEST]
const NEVER_ESCAPES: Array[int] = [
	BATTLETYPE_TRAP, BATTLETYPE_CELEBI, BATTLETYPE_FORCESHINY, BATTLETYPE_SUICUNE,
]

## `TryToRunAwayFromBattle`'s own arithmetic. The odds are
## `player_speed * 32 / ((enemy_speed / 4) & $ff)`, then 30 per attempt after the
## first, and anything over a byte gets away without a roll.
const FLEE_SPEED_MULTIPLIER: int = 32
const FLEE_ENEMY_SPEED_SHIFT: int = 2
const FLEE_ATTEMPT_BONUS: int = 30
const FLEE_ODDS_RANGE: int = 256

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

## `wBattleType`, which only running reads so far. A `loadvar VAR_BATTLETYPE`
## before `startbattle` is what sets it on the world path; everything else is
## BATTLETYPE_NORMAL.
var battle_type: int = BATTLETYPE_NORMAL

## `wNumFleeAttempts`. Every failed run raises the odds behind the next one, and
## choosing FIGHT clears it again, which is `BattleMenu_Fight`'s own `xor a`.
var flee_attempts: int = 0

## `wBattleWeather` and `wWeatherCount`. One of each for the whole battle rather
## than one per side, and neither survives it: nothing outside a battle has
## weather, so a fresh [Gen2Battle] starts clear.
var weather: int = Gen2Weather.NONE
var weather_turns: int = 0

## Set once the player has run. The battle is over with no winner, which is the
## DRAW `wBattleResult` the cartridge writes.
var _fled: bool = false

## The two sides, keyed by [constant PLAYER] and [constant ENEMY].
var parties: Dictionary = {}

## Which of a side's party indices have fought since the current opponent was
## sent in, a Dictionary used for its keys. Seeded with the lead at
## [method create_parties], added to on every [method send_out], and reset to
## whoever is left standing once experience is awarded: see
## [method _award_experience]. Only [constant PLAYER]'s side is read, mirroring
## the cartridge's asymmetry, but both are tracked the same way.
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


static func run_away() -> Dictionary:
	return {"type": ACTION_RUN}


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
	return _fled or party(PLAYER).is_wiped() or party(ENEMY).is_wiped()


## Whether the player has run from this battle. The parties are both still
## standing, so [method is_over] alone does not say which ending it was.
func has_fled() -> bool:
	return _fled


## `TryToRunAwayFromBattle`, resolved without spending anything.
##
## Answers `outcome`: [code]&"fled"[/code], [code]&"failed"[/code] for the roll
## that came up short and costs the turn, or [code]&"blocked"[/code] for a
## refusal that costs nothing. `how` or `reason` says which branch answered.
##
## Both trapping checks are refusals that cost nothing rather than failed rolls:
## `.cant_escape` prints and returns without writing
## `BATTLEPLAYERACTION_USEITEM`, so `BattleMenu_Run` falls through to
## `jp BattleMenu`. Only `.cant_escape_2`, the roll that came up short, spends
## the turn.
func run_odds() -> Dictionary:
	if battle_type in ALWAYS_ESCAPES:
		return {"outcome": &"fled", "how": &"battle_type", "battle_type": battle_type}
	if battle_type in NEVER_ESCAPES:
		return {"outcome": &"blocked", "reason": &"battle_type", "battle_type": battle_type}
	if is_trainer_battle:
		return {"outcome": &"blocked", "reason": &"trainer"}

	var runner: Gen2BattleMon = mon(PLAYER)
	var chaser: Gen2BattleMon = mon(ENEMY)

	# Both ahead of the Smoke Ball, which is the source's order, so a trapped
	# holder does not walk out on the item either. The flag is read off whoever
	# is doing the trapping and the counter off whoever is bound.
	if Gen2Substatus.has(chaser.substatus, Gen2Substatus.CANT_RUN):
		return {"outcome": &"blocked", "reason": &"cant_run"}
	if runner.trapped_turns > 0:
		return {"outcome": &"blocked", "reason": &"trapped", "move": runner.trapping_move}

	if _held_effect(runner) == Gen2HeldItem.ESCAPE:
		return {"outcome": &"fled", "how": &"item", "item": runner.item}

	# wNumFleeAttempts rises before the arithmetic reads it, so the first attempt
	# counts as one and the bonus loop below runs one fewer time than that.
	var attempts: int = flee_attempts + 1
	var speed: int = runner.stat("speed")
	var enemy_speed: int = chaser.stat("speed")
	if speed >= enemy_speed:
		return {"outcome": &"fled", "how": &"speed", "attempts": attempts}

	# The divisor is one byte of enemy_speed >> 2, so a fast enough enemy wraps
	# it to zero and the run simply succeeds. That is the cartridge's own
	# `and a; jr z, .can_escape`, not a guard against dividing by zero.
	var divisor: int = (enemy_speed >> FLEE_ENEMY_SPEED_SHIFT) & 0xFF
	if divisor == 0:
		return {"outcome": &"fled", "how": &"speed", "attempts": attempts}

	# The dividend is the low sixteen bits of the product, which is what taking
	# hProduct + 2 and + 3 leaves behind.
	var odds: int = ((speed * FLEE_SPEED_MULTIPLIER) & 0xFFFF) / divisor
	if odds > 0xFF:
		return {"outcome": &"fled", "how": &"odds", "odds": odds, "attempts": attempts}
	for _bonus: int in attempts - 1:
		odds += FLEE_ATTEMPT_BONUS
		if odds > 0xFF:
			return {"outcome": &"fled", "how": &"odds", "odds": odds, "attempts": attempts}
	return {
		"outcome": &"roll", "odds": odds, "attempts": attempts,
		"range": FLEE_ODDS_RANGE,
	}


## The held effect of whatever [param battler] is carrying, or zero. The item's
## own `effect` field is `ItemAttributes`' held effect byte.
func _held_effect(battler: Gen2BattleMon) -> int:
	if battler == null:
		return Gen2HeldItem.NONE
	return Gen2HeldItem.effect_of(data, battler.item)


## Whoever is still standing, or null if the battle is not over. Both sides can
## go down in one turn, through recoil; the cartridge gives it to whoever is left
## and there is nobody, so this answers null for that too.
func winner() -> Variant:
	if not is_over():
		return null
	# Running is a DRAW: both parties are still standing and nobody beat anybody.
	if _fled:
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


## The offer waiting on [param side], or an empty Dictionary. [code]species[/code],
## [code]index[/code], [code]move[/code] and [code]level[/code] are enough to say
## "your FOO wants to learn BAR" without asking the Pokémon anything the event
## did not already carry.
func pending_learn(side: int) -> Dictionary:
	var queue: Array = _move_learn_queue.get(side, [])
	return queue[0] if not queue.is_empty() else {}


## Answers a pending offer by giving up [param forget_slot] for it. Refuses if
## there is nothing pending: an answer to a question nobody asked is not
## approximated into one that was.
##
## An HM slot is refused too, because `ForgetMove` never returns one: its
## `.hmmove` branch prints `MoveCantForgetHMText` and redisplays the list
## (engine/pokemon/learn.asm). A refused answer leaves the offer pending, so
## [method must_learn_move] still holds and the caller can ask again.
func learn_move(side: int, forget_slot: int) -> Array:
	if not must_learn_move(side):
		return []

	var offer: Dictionary = (_move_learn_queue[side] as Array)[0]
	var learner: Gen2BattleMon = party(side).at(int(offer["index"]))
	if learner == null or forget_slot < 0 or forget_slot >= learner.moves.size():
		return []

	var forgot: int = int(learner.moves[forget_slot])
	if Gen2MoveForget.is_hm_move(forgot):
		return []
	if not learner.replace_move(forget_slot, int(offer["move"])):
		return []
	(_move_learn_queue[side] as Array).pop_front()

	# LearnMove clears a Disable naming the move that just went, but only in
	# battle. The cartridge compares move numbers against wDisabledMove; Disable
	# is a slot here, and the new move takes the forgotten one's slot, so slot
	# equality is the same test.
	if learner.disabled_slot == forget_slot:
		learner.disabled_slot = -1
		learner.disable_turns = 0

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
	_clear_trapping()

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


## Ends the whole trapping relationship, on both sides at once.
##
## `NewBattleMonStatus` and `NewEnemyMonStatus` each clear both wrap counters and
## the opponent's `SUBSTATUS_CANT_RUN` beside their own substatus block, so a
## send-out by either side frees the other as well.
## [method Gen2BattleMon.reset_volatile] cannot answer for that on its own: it
## runs on the Pokémon leaving, and half of this state lives on the one staying.
func _clear_trapping() -> void:
	for side: int in [PLAYER, ENEMY]:
		var battler: Gen2BattleMon = mon(side)
		battler.trapped_turns = 0
		battler.trapping_move = 0
		battler.substatus &= ~Gen2Substatus.CANT_RUN


## Whether `TryPlayerSwitch` would refuse to recall the player's Pokémon: it is
## bound, or the opponent is holding it with Mean Look or Spider Web.
##
## Player-only, as the cartridge's is. `AI_Switch` makes no such check, so the
## enemy switches out of either one, and that asymmetry is the cartridge's rather
## than an omission here.
func switch_blocked() -> bool:
	return mon(PLAYER).trapped_turns > 0 \
		or Gen2Substatus.has(mon(ENEMY).substatus, Gen2Substatus.CANT_RUN)


## Both sides act, and the turn plays out. Returns the events in the order they
## happened.
##
## An action is [method use_move] or [method switch_to]. Nothing happens while
## either side owes a replacement, and a faint ends the turn where it is.
##
## [method order]'s priority check reads the move each side is credited with once,
## before either has acted, which is when the cartridge decides order. What
## actually runs is recomputed just before [method _act], because Encore can land
## on a side that has not gone yet and `CheckOpponentWentFirst` overrides that
## side's chosen action for the very turn it lands.
func take_actions(player_action: Dictionary, enemy_action: Dictionary) -> Array:
	var events: Array = []
	if is_over() or awaiting_replacement() or awaiting_move_learn():
		return events

	# Settled before anything is spent, because `TryPlayerSwitch` runs at menu
	# time: the refusal jumps back to `BattleMenuPKMN_Loop` with no turn taken.
	if _is_switch(player_action) and switch_blocked():
		events.append({
			"type": SWITCH_BLOCKED, "side": PLAYER,
			"index": party(PLAYER).active, "species": mon(PLAYER).species,
		})
		return events

	reset_damage_taken()

	if _is_run(player_action):
		var attempt: Dictionary = run_odds()
		var outcome: StringName = StringName(attempt.get("outcome", &"roll"))
		if outcome == &"roll":
			# BattleRandom against the accumulated odds. The comparison is
			# `cp b; jr nc`, so the odds getting away on a tie is the source's.
			flee_attempts += 1
			var rolled: int = rng.randi_range(0, FLEE_ODDS_RANGE - 1)
			attempt["roll"] = rolled
			outcome = &"fled" if int(attempt["odds"]) >= rolled else &"failed"
			attempt["how"] = &"roll"
		elif outcome != &"blocked":
			flee_attempts += 1
		if outcome == &"fled":
			_fled = true
			events.append(_run_event(FLED, attempt))
			events.append({"type": OVER, "winner": winner(), "fled": true})
			return events
		if outcome == &"blocked":
			# BattleMenu_Run's `jp BattleMenu`: nothing was spent, so no residual
			# damage and no enemy move either.
			events.append(_run_event(RUN_BLOCKED, attempt))
			return events
		events.append(_run_event(RUN_FAILED, attempt))

	# BattleMenu_Fight clears wNumFleeAttempts, so the odds a run has built up
	# survive only a run followed by another run.
	if StringName(player_action.get("type", ACTION_MOVE)) == ACTION_MOVE:
		flee_attempts = 0

	var actions: Dictionary = {PLAYER: player_action, ENEMY: enemy_action}
	var chosen: Dictionary = {
		PLAYER: _move_for_action(PLAYER, player_action),
		ENEMY: _move_for_action(ENEMY, enemy_action),
	}

	var acting: Array = order(chosen, actions)
	for side: int in acting:
		if _is_run(actions[side]):
			continue
		if _is_switch(actions[side]):
			events.append_array(send_out(side, int(actions[side].get("index", -1))))
			continue
		if mon(side).is_fainted() or mon(opponent_of(side)).is_fainted():
			break
		var slot: int = effective_slot(side, int(actions[side].get("slot", 0)))
		_act(side, slot, move_for(side, slot), events)

	_residual_damage(acting, events)
	_tick_weather(events)
	_tick_wrap(events)
	_tick_held_items(events)
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
## After both moves rather than after each, skipping whoever is already down, so
## a Pokémon that faints to its burn does so here rather than mid-move.
##
## A running [member Gen2BattleMon.toxic_counter] means Toxic, which ramps
## instead of taking the flat eighth. The counter rises here, once a turn, so the
## turn it was inflicted counts as the first.
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


## `HandleWeather`: one turn off the count, the line that goes with it, and a
## Sandstorm's eighth off whoever it can reach.
##
## Ahead of [method _tick_wrap] because `HandleBetweenTurnEffects` runs weather
## before wrap. The countdown happens before the message, so the turn the count
## reaches zero prints the ending line and deals no Sandstorm damage; the turn
## the weather was set counts as one of its own, since `HandleWeather` runs on
## that turn too.
##
## Player first whoever moved first, the same `SetPlayerTurn` then
## `SetEnemyTurn` [method _tick_wrap] follows.
func _tick_weather(events: Array) -> void:
	if not Gen2Weather.is_active(weather):
		return

	weather_turns -= 1
	if weather_turns <= 0:
		var ended: int = weather
		weather = Gen2Weather.NONE
		weather_turns = 0
		events.append({"type": WEATHER_ENDED, "weather": ended})
		return

	events.append({"type": WEATHER_CONTINUES, "weather": weather})
	if weather != Gen2Weather.SANDSTORM:
		return

	for side: int in [PLAYER, ENEMY]:
		var current: Gen2BattleMon = mon(side)
		if current.is_fainted():
			continue
		if not Gen2Weather.hits_in_sandstorm(current.types(), current.substatus):
			continue

		var taken: int = current.take_damage(Gen2Weather.sandstorm_damage(current.max_hp()))
		events.append({
			"type": HURT_BY_SANDSTORM,
			"side": side,
			"amount": taken,
			"hp": current.hp,
			"max_hp": current.max_hp(),
		})
		if current.is_fainted():
			events.append({"type": FAINTED, "side": side})


## `HandleWrap`: one turn off each bound Pokémon's counter, and a sixteenth of
## its health with it.
##
## Between [method _residual_damage] and [method _tick_encore] because
## `HandleBetweenTurnEffects` runs future sight, weather, wrap and perish song
## before its leftovers block and `HandleEncore` last, while poison and burn are
## taken inside each side's own move well ahead of any of it.
##
## Always the player first, whoever moved first: unlike `ResidualDamage`, which
## runs inside a turn and so follows it, `HandleWrap` is `SetPlayerTurn` then
## `SetEnemyTurn` outside a link battle.
##
## The turn the counter reaches zero is the release and costs nothing, which is
## why the rolled three to six turns are two to five turns of damage.
func _tick_wrap(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		var current: Gen2BattleMon = mon(side)
		if current.is_fainted() or current.trapped_turns <= 0:
			continue

		var move_number: int = current.trapping_move
		current.trapped_turns -= 1
		if current.trapped_turns <= 0:
			current.trapping_move = 0
			events.append({"type": RELEASED_FROM_TRAP, "side": side, "move": move_number})
			continue

		var taken: int = current.take_damage(Gen2Substatus.trap_damage(current.max_hp()))
		events.append({
			"type": HURT_BY_TRAP,
			"side": side,
			"move": move_number,
			"amount": taken,
			"hp": current.hp,
			"max_hp": current.max_hp(),
		})
		if current.is_fainted():
			events.append({"type": FAINTED, "side": side})


## The leftovers block of `HandleBetweenTurnEffects`: `HandleLeftovers`,
## `HandleMysteryberry` and then `HandleHealingItems`, after the wrap tick and
## before Encore.
##
## The three do not agree on an order. The first two are `SetPlayerTurn` then
## `SetEnemyTurn` reading `GetUserItem`, so the player is handled first; the
## third is the same two calls reading `GetOpponentItem`, so the enemy is. The
## two skipped between them, `HandleDefrost` and `HandleSafeguard`/`HandleScreens`,
## are not item effects.
func _tick_held_items(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		_use_leftovers(side, events)
	for side: int in [PLAYER, ENEMY]:
		_use_pp_berry(side, events)
	for side: int in [ENEMY, PLAYER]:
		use_hp_berry(side, events)
		use_status_berry(side, events)
		use_confusion_berry(side, events)


## `HandleLeftovers`: a sixteenth back every turn, and nothing at all on a
## Pokémon already at full health.
func _use_leftovers(side: int, events: Array) -> void:
	var holder: Gen2BattleMon = mon(side)
	if holder.is_fainted() or holder.hp >= holder.max_hp():
		return
	if _held_effect(holder) != Gen2HeldItem.LEFTOVERS:
		return

	var healed: int = holder.heal(Gen2HeldItem.leftovers_healing(holder.max_hp()))
	events.append({
		"type": RECOVERED_WITH_ITEM, "side": side, "item": holder.item,
		"amount": healed, "hp": holder.hp, "max_hp": holder.max_hp(),
	})


## `HandleMysteryberry`: five points back into the first move that ran out, or
## one for Sketch. It is consumed by its own code rather than through
## `ConsumeHeldItem`, which is why it is not on `ConsumableEffects`.
func _use_pp_berry(side: int, events: Array) -> void:
	var holder: Gen2BattleMon = mon(side)
	if holder.is_fainted() or _held_effect(holder) != Gen2HeldItem.RESTORE_PP:
		return

	for slot: int in holder.moves.size():
		if int(holder.moves[slot]) == 0:
			break
		if holder.pp_left(slot) > 0:
			continue

		var move_number: int = int(holder.moves[slot])
		var restored: int = Gen2HeldItem.restored_pp(move_number)
		holder.pp[slot] = holder.pp_left(slot) + restored
		var used: int = holder.item
		holder.item = 0
		events.append({
			"type": RESTORED_PP, "side": side, "item": used,
			"slot": slot, "move": move_number, "amount": restored,
		})
		return


## `HandleHPHealingItem`: a Berry, Gold Berry or Berry Juice puts its own
## parameter back once the holder is strictly under half health, and is spent.
func use_hp_berry(side: int, events: Array) -> bool:
	var holder: Gen2BattleMon = mon(side)
	if holder.is_fainted() or _held_effect(holder) != Gen2HeldItem.BERRY:
		return false
	if not Gen2HeldItem.wants_hp_berry(holder.hp, holder.max_hp()):
		return false

	var healed: int = holder.heal(Gen2HeldItem.parameter_of(data, holder.item))
	var used: int = holder.item
	holder.item = 0
	events.append({
		"type": RECOVERED_USING_ITEM, "side": side, "item": used,
		"amount": healed, "hp": holder.hp, "max_hp": holder.max_hp(),
	})
	return true


## `UseHeldStatusHealingItem`, which is reached both from here and from the
## moment a status lands: the berry answers immediately rather than waiting for
## the end of the turn.
func use_status_berry(side: int, events: Array) -> bool:
	var holder: Gen2BattleMon = mon(side)
	if holder.status == Gen2Status.NONE:
		return false
	if not Gen2HeldItem.heals_status(_held_effect(holder), holder.status):
		return false

	# The status byte and nothing else: `UseHeldStatusHealingItem` clears
	# `wBattleMonStatus` and never touches `SUBSTATUS_TOXIC`, so a Pokémon cured
	# of a Toxic keeps the flag that makes its next poison ramp.
	# [member Gen2BattleMon.toxic_counter] is that flag and that counter folded
	# into one, so leaving it alone is what keeps the two in step.
	holder.status = Gen2Status.NONE
	var used: int = holder.item
	holder.item = 0
	events.append({"type": RECOVERED_USING_ITEM, "side": side, "item": used})
	return true


## `UseConfusionHealingItem`. A Miracleberry answers for this as well as for the
## status byte, but it is spent by whichever came first, which is why the two are
## separate calls rather than one.
func use_confusion_berry(side: int, events: Array) -> bool:
	var holder: Gen2BattleMon = mon(side)
	if not Gen2Substatus.has(holder.substatus, Gen2Substatus.CONFUSED):
		return false
	if not Gen2HeldItem.heals_confusion(_held_effect(holder)):
		return false

	holder.substatus &= ~Gen2Substatus.CONFUSED
	holder.confusion_turns = 0
	var used: int = holder.item
	holder.item = 0
	events.append({"type": ITEM_HEALED_CONFUSION, "side": side, "item": used})
	return true


## Encore's countdown, once a turn rather than once a side's move: `HandleEncore`
## runs after both sides act, the timing [method _residual_damage] uses. Ends
## early the moment the encored slot runs out of PP, which the cartridge checks
## every tick, not only at expiry.
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


## Experience for every enemy Pokémon that fainted this turn, from a move
## ([method _act]) or from status damage ([method _residual_damage]).
##
## [constant FAINTED] clears the fainted member out of [member _participants] on
## either side, since a fainted Pokémon stops participating regardless of which
## side receives experience; only [method _give_experience_for] is asymmetric.
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


static func _is_run(action: Dictionary) -> bool:
	return StringName(action.get("type", ACTION_MOVE)) == ACTION_RUN


## The event a run attempt produces, carrying whatever branch answered it.
func _run_event(type: StringName, attempt: Dictionary) -> Dictionary:
	var out: Dictionary = attempt.duplicate(true)
	out.erase("outcome")
	out["type"] = type
	out["side"] = PLAYER
	return out


## The move an action commits a side to, which is nothing at all for a switch.
## Struggle stands in there so that the order can be worked out without a special
## case; a switching side never reaches the point of using it.
func _move_for_action(side: int, action: Dictionary) -> int:
	if _is_switch(action) or _is_run(action):
		return Gen2Damage.STRUGGLE
	return move_for(side, int(action.get("slot", 0)))


## The slot PP is actually spent from, not always the slot asked for: Encore
## forces the slot it locked in, as a two-turn release forces its move number.
## The encored slot is used only while still usable, so a move out of PP is not
## reached for once [method _tick_encore] has ended the effect.
func effective_slot(side: int, requested_slot: int) -> int:
	var attacker: Gen2BattleMon = mon(side)
	if attacker.encored_slot >= 0 and attacker.can_use(attacker.encored_slot):
		return attacker.encored_slot
	return requested_slot


## Which move a side will actually use.
##
## A release turn answers with the charged move whatever slot is asked for, since
## the cartridge chooses nothing on that turn. Rollout and rampage continuations
## force the move that started the chain the same way. Failing that, Encore
## answers with [method effective_slot], which may also not be the asked slot.
##
## Failing that, an unusable slot answers Struggle. That is the cartridge's
## answer for a Pokémon with no PP anywhere, and it is used here for an empty,
## spent or disabled slot too: the caller asked for something that cannot happen,
## and Struggle is the only always-available move.
func move_for(side: int, slot: int) -> int:
	var attacker: Gen2BattleMon = mon(side)
	if attacker.charged_move != 0:
		return attacker.charged_move
	if Gen2Substatus.has(attacker.substatus, Gen2Substatus.ROLLOUT):
		return Gen2MoveEffect.ROLLOUT_MOVE
	if Gen2Substatus.has(attacker.substatus, Gen2Substatus.RAMPAGING) \
		and attacker.rampage_move != 0:
		return attacker.rampage_move
	var chosen_slot: int = effective_slot(side, slot)
	return int(attacker.moves[chosen_slot]) if attacker.can_use(chosen_slot) else Gen2Damage.STRUGGLE


## Who goes first, as the two sides in the order they act.
##
## A switch is settled first: the incoming Pokémon comes out and then takes the
## other side's move, so a switching side acts first at any speed or priority.
## Two switches in one turn go to the player, as outside a link battle.
##
## Otherwise priority decides, then speed with stages applied, then a coin flip.
## The cartridge weighs a held Quick Claw between priority and speed; no held
## items exist here yet.
func order(chosen: Dictionary, actions: Dictionary = {}) -> Array:
	# A failed run is settled before the enemy moves, the way a switch is: the
	# cartridge spends the turn as BATTLEPLAYERACTION_USEITEM, which resolves at
	# once and leaves the enemy's move behind it.
	var player_switching: bool = _is_switch(actions.get(PLAYER, {})) \
		or _is_run(actions.get(PLAYER, {}))
	var enemy_switching: bool = _is_switch(actions.get(ENEMY, {}))
	if player_switching or enemy_switching:
		return _sides(player_switching)

	var player_priority: int = priority_of(data.move(int(chosen[PLAYER])))
	var enemy_priority: int = priority_of(data.move(int(chosen[ENEMY])))
	if player_priority != enemy_priority:
		return _sides(player_priority > enemy_priority)

	var claw: Variant = _quick_claw()
	if claw != null:
		return _sides(bool(claw))

	var player_speed: int = player.stat("speed")
	var enemy_speed: int = enemy.stat("speed")
	if player_speed != enemy_speed:
		return _sides(player_speed > enemy_speed)

	return _sides(rng.randi_range(0, 255) < 128)


## `DetermineMoveOrder`'s `.equal_priority` block: whether a Quick Claw settles
## the turn before the speeds are looked at.
##
## Answers true for the player going first, false for the enemy, and null for
## "the claw said nothing", which is what falls through to speed. The order is
## the cartridge's: the player's claw is rolled first and only reaches the
## enemy's when the player has none, and when both sides carry one the enemy's
## roll is taken first outside a link battle.
func _quick_claw() -> Variant:
	var player_claw: bool = _held_effect(mon(PLAYER)) == Gen2HeldItem.QUICK_CLAW
	var enemy_claw: bool = _held_effect(mon(ENEMY)) == Gen2HeldItem.QUICK_CLAW
	if not player_claw and not enemy_claw:
		return null

	if player_claw and not enemy_claw:
		return true if _claw_fires(mon(PLAYER)) else null
	if enemy_claw and not player_claw:
		return false if _claw_fires(mon(ENEMY)) else null

	# `.both_have_quick_claw`: two rolls, the enemy's read first, and the player
	# only wins on its own roll after the enemy's has already come up short.
	if _claw_fires(mon(ENEMY)):
		return false
	if _claw_fires(mon(PLAYER)):
		return true
	return null


func _claw_fires(battler: Gen2BattleMon) -> bool:
	return Gen2HeldItem.rolls_under(rng, Gen2HeldItem.parameter_of(data, battler.item))


func _sides(player_first: bool) -> Array:
	return [PLAYER, ENEMY] if player_first else [ENEMY, PLAYER]


## A move's priority, from its effect byte.
static func priority_of(move: Dictionary) -> int:
	if int(move.get("number", 0)) == VITAL_THROW:
		return 0
	return int(EFFECT_PRIORITIES.get(int(move.get("effect", -1)), BASE_PRIORITY))


## One side's move, run as the list of commands its effect is made of.
##
## Nothing about a particular move lives here. The effect byte picks a sequence
## out of [Gen2MoveEffect] and its commands run in order against a [Gen2Turn]
## until one says the move is finished; announcing, spending, rolling, applying
## and fainting are all commands. That is the cartridge's arrangement, and it is
## why the rest of Generation 2 is commands rather than branches in here.
func _act(side: int, slot: int, move_number: int, events: Array) -> void:
	var move: Dictionary = data.move(move_number)
	if move.is_empty():
		return

	var turn: Gen2Turn = Gen2Turn.create(self, side, slot, move_number, move, events)
	# The release turn of a two-turn move, or any Rollout/rampage continuation:
	# the PP was already spent on the first turn, and
	# [method Gen2EffectCommands._do_turn] reads this so it is not spent again.
	var active_substatus: int = mon(side).substatus
	turn.locked = (
		mon(side).charged_move == move_number
		or Gen2Substatus.has(active_substatus, Gen2Substatus.ROLLOUT)
		or Gen2Substatus.has(active_substatus, Gen2Substatus.RAMPAGING)
	) and move_number != 0

	# Whether the Pokémon can move at all is asked before the effect is looked up,
	# which is the cartridge's arrangement: every move goes through it, so no
	# sequence has to remember to include it.
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)

	for command: StringName in Gen2MoveEffect.sequence_for(turn.effect()):
		if turn.ended:
			return
		Gen2EffectCommands.run(command, turn)
