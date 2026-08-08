class_name Gen2EffectCommands
extends RefCounted

## The steps a move is made of.
##
## A move is a short program, not a switch case: the cartridge keeps a command
## list per effect and runs it in order. An ordinary attack announces the move,
## spends the PP, works out damage, rolls the hit, applies it and checks for a
## faint; every other move is that list with steps added, removed or replaced.
##
## Keeping the shape is what makes the rest of Generation 2 additive: a burn is
## an appended command, a move that cannot miss is a list without the roll, a
## two-turn move is a list that ends early the first time. None of it reaches
## [Gen2Battle], which only knows how to run a list.
##
## The names are the cartridge's, so a sequence reads against
## [code]data/moves/effects.asm[/code] line for line. [Gen2MoveEffect] holds the
## lists.

## Announces the move. First, because a move that fails still says it was used.
const USED_MOVE_TEXT: StringName = &"usedmovetext"

## Spends the PP.
const DO_TURN: StringName = &"doturn"

## Works out what the move would do: the critical, the type matchup, the STAB and
## the random spread. Nothing is applied here, and nothing has been rolled for
## whether it connects.
const DAMAGE_CALC: StringName = &"damagecalc"

## Ends the move if the defender cannot be touched by it at all. Separate from
## the roll, because an immunity is not a miss and does not read as one.
const CHECK_IMMUNE: StringName = &"checkimmune"

## Rolls whether the move connects, and ends it if it does not.
const CHECK_HIT: StringName = &"checkhit"

## Counter and Mirror Coat do not roll their own accuracy. They validate the
## move that just hit the user, then leave the doubled damage for APPLY_DAMAGE.
const COUNTER: StringName = &"counter"
const MIRROR_COAT: StringName = &"mirrorcoat"

## Selfdestruct and Explosion faint their user after the hit check, even when
## the hit missed or was immune. The damage step still runs first so effect byte
## 7 can halve the defender's Defense in the ordinary formula.
const SELFDESTRUCT: StringName = &"selfdestruct"

## Takes the damage off, and reports what was actually taken.
const APPLY_DAMAGE: StringName = &"applydamage"

## Takes a quarter of what was dealt off the attacker.
const RECOIL: StringName = &"recoil"

## Reports whoever is down. Both can be, since recoil can take the attacker with
## the defender.
const CHECK_FAINT: StringName = &"checkfaint"

## The end of the list. It does nothing except be the end, which is worth having
## as a step so a sequence reads the way the cartridge's does.
const END_MOVE: StringName = &"endmove"

## Whether the move happens at all. Sleep, freeze and paralysis are checked here,
## in that order, and any of them can cost the turn.
##
## Not part of any sequence: the cartridge runs it before looking the effect up,
## so every move goes through it and no list has to remember to. [Gen2Battle]
## runs it ahead of the list for the same reason.
const CHECK_STATUS: StringName = &"checkstatus"

## Whether a secondary effect happens, out of the move's own chance. A move whose
## sequence has this in it does its damage either way; what is behind it is what
## the roll decides.
const EFFECT_CHANCE: StringName = &"effectchance"

## The five things a move can leave on a Pokémon. Each refuses a target that
## already has something, which is the rule the status byte encodes: one at a
## time, and a second is a failure rather than an addition.
const SLEEP_TARGET: StringName = &"sleeptarget"
const POISON_TARGET: StringName = &"poisontarget"
const BURN_TARGET: StringName = &"burntarget"
const FREEZE_TARGET: StringName = &"freezetarget"
const PARALYZE_TARGET: StringName = &"paralyzetarget"

## What Toxic leaves behind: [constant POISON_TARGET]'s poison flag plus the
## ramping counter. Its own command rather than an extra step after
## [constant POISON_TARGET], because the counter has to start before the first
## residual turn sees it.
const TOXIC_TARGET: StringName = &"toxictarget"

## The two things a move can leave on [Gen2Substatus] rather than the status
## byte. Flinch is only ever a secondary effect, obeying
## [member Gen2Turn.failed_chance] like the five above; confusion comes both ways,
## as its own status move (Confuse Ray, Supersonic) and as a secondary effect
## (Confusion, Psybeam), so [Gen2MoveEffect] reaches for it from both shapes.
const FLINCH_TARGET: StringName = &"flinchtarget"
const CONFUSE_TARGET: StringName = &"confusetarget"

## Heals the attacker for half of what the hit calculated, the same command for
## Absorb-family drain and, gated by [constant Gen2MoveEffect.DREAM_EATER]'s own
## rule inside [constant CHECK_HIT], for Dream Eater.
const DRAIN_TARGET: StringName = &"draintarget"

## Two to five hits for [constant Gen2MoveEffect.MULTI_HIT], exactly two for
## [constant Gen2MoveEffect.DOUBLE_HIT] and [constant Gen2MoveEffect.TWINEEDLE]:
## one command repeating the roll and the hit rather than a runner-repeated
## sequence, as [constant ALL_STATS_UP] repeats a stage change five times in one
## command.
const MULTI_HIT: StringName = &"multihit"

## Overwrites what [constant DAMAGE_CALC] worked out with the number
## [constant Gen2MoveEffect.SUPER_FANG], [constant Gen2MoveEffect.STATIC_DAMAGE],
## [constant Gen2MoveEffect.LEVEL_DAMAGE] and [constant Gen2MoveEffect.PSYWAVE]
## actually deal. [constant DAMAGE_CALC]'s own roll still ran first, and its
## immunity answer is the one thing about it this keeps.
const FIXED_DAMAGE: StringName = &"fixeddamage"

## Guillotine, Horn Drill and Fissure's own accuracy rule and their own damage:
## nothing here is [constant CHECK_HIT] or [constant APPLY_DAMAGE].
const OHKO: StringName = &"ohko"

## Recharge: locks the user out of its next turn, the tail of Hyper Beam's own
## list rather than anything a target-facing command touches.
const RECHARGE: StringName = &"recharge"

## A two-turn move's charge. First run: lock the user in, announce, end the move.
## Second run, the release turn: clear the lock and let the rest of the list run
## as an ordinary attack. [method Gen2Battle.move_for] is what makes that second
## call the user's only option.
const CHARGE_MOVE: StringName = &"chargemove"

## Rollout checks whether a chain is already active, applies its power state and
## then advances the successful-hit count. The first command resets a completed
## chain before PP and damage are processed.
const ROLLOUT_CHECK: StringName = &"rolloutcheck"
const ROLLOUT_POWER: StringName = &"rolloutpower"

## Starts or advances Thrash, Petal Dance and Outrage, and marks Defense Curl's
## persistent substatus for Rollout.
const RAMPAGE: StringName = &"rampage"
const CURL: StringName = &"curl"

## Clears every stage on both sides. Only the stages: nothing here touches
## either Pokémon's status byte or [Gen2Substatus].
const HAZE: StringName = &"haze"

## Costs half the user's maximum HP to raise its own Attack straight to the top
## of its range. Fails without costing anything if the user does not have more
## than half its health, or if Attack is already there.
const BELLY_DRUM: StringName = &"bellydrum"

## Copies the target's stages onto the user, all seven at once. Fails if the
## target has nothing raised or lowered to copy.
const PSYCH_UP: StringName = &"psychup"

## Locks the target's last-used move slot for a few turns. Fails if the target
## has not moved, if that move was Struggle, if the slot is out of PP, or if the
## target is already disabled: one slot at a time.
const DISABLE: StringName = &"disable"

## Locks the target into repeating its own last move for a few turns. The same
## exclusions as [constant DISABLE] apply, plus two the cartridge names outright
## rather than leaving to a structural check: the last move cannot have been
## Encore itself or Mirror Move, neither of which means anything repeated.
const ENCORE: StringName = &"encore"

## Puts the target in love, provided the user and the target have opposite,
## known genders and the target is not already smitten. Persists until a
## switch; [constant Gen2EffectCommands.CHECK_STATUS] is what rolls, every turn,
## whether that stops the target moving at all.
const ATTRACT: StringName = &"attract"

## Shields the user from the opponent's own stat-lowering moves, until a
## switch. Blocks a drop aimed at the user; never a rise, and never the user's
## own drop aimed at the opponent. Fails, without re-applying, on a second use.
const MIST: StringName = &"mist"

## Raises the user's own critical-hit rate for the rest of the battle, until a
## switch. Fails, without re-applying, on a second use.
const FOCUS_ENERGY: StringName = &"focusenergy"

## Binds the target for a rolled number of turns: it can neither run nor be
## recalled, and loses a sixteenth of its health at the end of each of them.
## Nothing here stops it moving, which is the Generation 2 rule. A target that is
## already bound is left alone without a failure message, since
## `BattleCommand_TrapTarget` simply returns.
const TRAP_TARGET: StringName = &"traptarget"

## Mean Look and Spider Web: the target can neither run nor be recalled, with no
## counter and no damage behind it. The flag goes on the user, which is what
## [constant Gen2Substatus.CANT_RUN] documents.
const ARENA_TRAP: StringName = &"arenatrap"

## The three moves that change the sky, each for [constant Gen2Weather.TURNS].
## Only Sandstorm refuses to re-set its own weather; Rain Dance and Sunny Day
## restart their count without failing, which is the cartridge's own asymmetry.
const START_RAIN: StringName = &"startrain"
const START_SUN: StringName = &"startsun"
const START_SANDSTORM: StringName = &"startsandstorm"

## Thunder's own accuracy, replacing the move's byte for this turn only: half in
## sun, and certain in rain. The rain half is redundant with
## [constant CHECK_HIT]'s own always-hits branch, which the cartridge says so
## itself.
const THUNDER_ACCURACY: StringName = &"thunderaccuracy"

## King's Rock, at the tail of every ordinary attack's list. It is a chance out
## of the item's own parameter and it is not a secondary effect: no
## [constant EFFECT_CHANCE] gates it, and the moves that carry their own flinch
## do not have this step at all.
const KINGS_ROCK: StringName = &"kingsrock"

## Solarbeam in sun: `BattleCommand_SkipSunCharge` skips past the charge command
## exactly as `checkcharge` does on a release turn, so the beam fires the turn it
## is chosen.
const SKIP_SUN_CHARGE: StringName = &"skipsuncharge"

## Raises and lowers a stat by one stage or two, named as the cartridge names
## them and in [constant Gen2BattleMon.STAGED_STATS] plus
## [constant Gen2BattleMon.STAGED_ODDS] order, which is also the order the effect
## bytes run in: seven in a row for "up by one", seven more for "down by one",
## and so on. [Gen2MoveEffect] turns that run into a table; this names the stops.
const ATTACK_UP: StringName = &"attackup"
const DEFENSE_UP: StringName = &"defenseup"
const SPEED_UP: StringName = &"speedup"
const SP_ATTACK_UP: StringName = &"specialattackup"
const SP_DEFENSE_UP: StringName = &"specialdefenseup"
const ACCURACY_UP: StringName = &"accuracyup"
const EVASION_UP: StringName = &"evasionup"

const ATTACK_UP_2: StringName = &"attackup2"
const DEFENSE_UP_2: StringName = &"defenseup2"
const SPEED_UP_2: StringName = &"speedup2"
const SP_ATTACK_UP_2: StringName = &"specialattackup2"
const SP_DEFENSE_UP_2: StringName = &"specialdefenseup2"
const ACCURACY_UP_2: StringName = &"accuracyup2"
const EVASION_UP_2: StringName = &"evasionup2"

const ATTACK_DOWN: StringName = &"attackdown"
const DEFENSE_DOWN: StringName = &"defensedown"
const SPEED_DOWN: StringName = &"speeddown"
const SP_ATTACK_DOWN: StringName = &"specialattackdown"
const SP_DEFENSE_DOWN: StringName = &"specialdefensedown"
const ACCURACY_DOWN: StringName = &"accuracydown"
const EVASION_DOWN: StringName = &"evasiondown"

const ATTACK_DOWN_2: StringName = &"attackdown2"
const DEFENSE_DOWN_2: StringName = &"defensedown2"
const SPEED_DOWN_2: StringName = &"speeddown2"
const SP_ATTACK_DOWN_2: StringName = &"specialattackdown2"
const SP_DEFENSE_DOWN_2: StringName = &"specialdefensedown2"
const ACCURACY_DOWN_2: StringName = &"accuracydown2"
const EVASION_DOWN_2: StringName = &"evasiondown2"

## Raises the user's five real stats at once, which is what Ancientpower leaves
## behind on a roll. Accuracy and evasion are not among them: the cartridge's own
## command is a loop over the five stats a stage multiplies a real number for,
## and the two odds are not that.
const ALL_STATS_UP: StringName = &"allstatsup"

## The stat commands in the run order the cartridge's effect bytes use, indexed
## by [Gen2MoveEffect] rather than named one at a time there. Each entry is
## [param stat_key, param amount, param targets_user]: the key
## [method Gen2BattleMon.change_stage] takes, how many stages it moves by, and
## whether the move points it at whoever used it rather than the other side.
const STAT_COMMANDS: Dictionary = {
	ATTACK_UP: ["attack", 1, true], DEFENSE_UP: ["defense", 1, true],
	SPEED_UP: ["speed", 1, true], SP_ATTACK_UP: ["sp_attack", 1, true],
	SP_DEFENSE_UP: ["sp_defense", 1, true], ACCURACY_UP: ["accuracy", 1, true],
	EVASION_UP: ["evasion", 1, true],

	ATTACK_UP_2: ["attack", 2, true], DEFENSE_UP_2: ["defense", 2, true],
	SPEED_UP_2: ["speed", 2, true], SP_ATTACK_UP_2: ["sp_attack", 2, true],
	SP_DEFENSE_UP_2: ["sp_defense", 2, true], ACCURACY_UP_2: ["accuracy", 2, true],
	EVASION_UP_2: ["evasion", 2, true],

	ATTACK_DOWN: ["attack", -1, false], DEFENSE_DOWN: ["defense", -1, false],
	SPEED_DOWN: ["speed", -1, false], SP_ATTACK_DOWN: ["sp_attack", -1, false],
	SP_DEFENSE_DOWN: ["sp_defense", -1, false], ACCURACY_DOWN: ["accuracy", -1, false],
	EVASION_DOWN: ["evasion", -1, false],

	ATTACK_DOWN_2: ["attack", -2, false], DEFENSE_DOWN_2: ["defense", -2, false],
	SPEED_DOWN_2: ["speed", -2, false], SP_ATTACK_DOWN_2: ["sp_attack", -2, false],
	SP_DEFENSE_DOWN_2: ["sp_defense", -2, false], ACCURACY_DOWN_2: ["accuracy", -2, false],
	EVASION_DOWN_2: ["evasion", -2, false],
}

## The five real stats [constant ALL_STATS_UP] raises, in the cartridge's order.
const ALL_STATS_KEYS: Array = ["attack", "defense", "speed", "sp_attack", "sp_defense"]

## Reports a stat change, or says nothing for one folded into a hit. Separate
## from the change itself, because a status move that fails to move a stat says
## so and a secondary effect that fails says nothing: two steps, not one asking
## both questions.
const STAT_UP_MESSAGE: StringName = &"statupmessage"
const STAT_DOWN_MESSAGE: StringName = &"statdownmessage"

## Reports that a stat could not go any higher or lower. Only on a status move's
## own sequence: a secondary effect's sequence has no step here at all, so its
## failure is silent, the way a failed [constant EFFECT_CHANCE] already is.
const STAT_UP_FAIL_TEXT: StringName = &"statupfailtext"
const STAT_DOWN_FAIL_TEXT: StringName = &"statdownfailtext"

## Recoil is a quarter of the damage dealt, never less than one, and it is the
## same quarter for every move that has it rather than a figure per move.
const RECOIL_DIVISOR: int = 4

## What [constant THUNDER_ACCURACY] leaves behind in sun: the cartridge's
## `50 percent + 1`, one past the `x * 255 / 100` the rest of the engine uses.
const THUNDER_SUN_ACCURACY: int = 128

## The two moves a frozen Pokémon can use, which thaw it in the using. Flame
## Wheel and Sacred Fire, by move number.
const THAWING_MOVES: Array = [172, 221]

## What Encore refuses to lock a target into, by move number: Encore itself and
## Mirror Move, since forcing either to repeat means nothing. Encore on Encore
## locks in nothing new, and Mirror Move copies the opponent's last move rather
## than repeating itself.
const ENCORE_EXCLUDED_MOVES: Array = [119, 227]


## Every step name this file answers to, read off its own constants so the list
## cannot drift from the match below.
static var _engine_commands: Dictionary = {}


## Whether [param command] is one of the engine's own steps. What
## [method Gen2MoveEffect.register_command] refuses a mod, so a registration can
## never shadow a step every move in the game depends on.
static func is_engine_command(command: StringName) -> bool:
	if _engine_commands.is_empty():
		var constants: Dictionary = Gen2EffectCommands.new().get_script().get_script_constant_map()
		for value: Variant in constants.values():
			if value is StringName:
				_engine_commands[value] = true
	return _engine_commands.has(command)


## Runs one command against [param turn].
##
## An unknown command is an error, not a no-op: a sequence naming a step nobody
## wrote would otherwise play out as a move that quietly does less than it says.
## A mod's own step is reached through [Gen2MoveEffect]'s registry, after this
## match has refused the name.
static func run(command: StringName, turn: Gen2Turn) -> void:
	match command:
		USED_MOVE_TEXT:
			_used_move_text(turn)
		DO_TURN:
			_do_turn(turn)
		DAMAGE_CALC:
			_damage_calc(turn)
		CHECK_IMMUNE:
			_check_immune(turn)
		CHECK_HIT:
			_check_hit(turn)
		COUNTER:
			_counter(turn, false)
		MIRROR_COAT:
			_counter(turn, true)
		SELFDESTRUCT:
			_selfdestruct(turn)
		APPLY_DAMAGE:
			_apply_damage(turn)
		RECOIL:
			_recoil(turn)
		CHECK_FAINT:
			_check_faint(turn)
		END_MOVE:
			turn.end()
		CHECK_STATUS:
			_check_status(turn)
		EFFECT_CHANCE:
			_effect_chance(turn)
		SLEEP_TARGET:
			_status_target(turn, Gen2Status.SLEEP_MASK)
		POISON_TARGET:
			_status_target(turn, Gen2Status.POISON)
		BURN_TARGET:
			_status_target(turn, Gen2Status.BURN)
		FREEZE_TARGET:
			_status_target(turn, Gen2Status.FREEZE)
		PARALYZE_TARGET:
			_status_target(turn, Gen2Status.PARALYSIS)
		TOXIC_TARGET:
			_toxic_target(turn)
		FLINCH_TARGET:
			_flinch_target(turn)
		CONFUSE_TARGET:
			_confuse_target(turn)
		DRAIN_TARGET:
			_drain_target(turn)
		MULTI_HIT:
			_multi_hit(turn)
		FIXED_DAMAGE:
			_fixed_damage(turn)
		OHKO:
			_ohko(turn)
		RECHARGE:
			_recharge(turn)
		CHARGE_MOVE:
			_charge_move(turn)
		ROLLOUT_CHECK:
			_rollout_check(turn)
		ROLLOUT_POWER:
			_rollout_power(turn)
		RAMPAGE:
			_rampage(turn)
		CURL:
			_curl(turn)
		HAZE:
			_haze(turn)
		BELLY_DRUM:
			_belly_drum(turn)
		PSYCH_UP:
			_psych_up(turn)
		DISABLE:
			_disable(turn)
		ENCORE:
			_encore(turn)
		ATTRACT:
			_attract(turn)
		MIST:
			_mist(turn)
		FOCUS_ENERGY:
			_focus_energy(turn)
		TRAP_TARGET:
			_trap_target(turn)
		ARENA_TRAP:
			_arena_trap(turn)
		START_RAIN:
			_start_weather(turn, Gen2Weather.RAIN)
		START_SUN:
			_start_weather(turn, Gen2Weather.SUN)
		START_SANDSTORM:
			_start_weather(turn, Gen2Weather.SANDSTORM)
		THUNDER_ACCURACY:
			_thunder_accuracy(turn)
		SKIP_SUN_CHARGE:
			_skip_sun_charge(turn)
		KINGS_ROCK:
			_kings_rock(turn)
		ALL_STATS_UP:
			_all_stats_up(turn)
		STAT_UP_MESSAGE, STAT_DOWN_MESSAGE:
			_stat_message(turn)
		STAT_UP_FAIL_TEXT, STAT_DOWN_FAIL_TEXT:
			_stat_fail_text(turn)
		_:
			if STAT_COMMANDS.has(command):
				_stat_change(command, turn)
			elif not Gen2MoveEffect.run_registered_command(command, turn):
				push_error("No such effect command: %s" % command)


## Announces the move, and records it as what Disable and Encore will find if
## the opponent's next move searches for "what did this Pokémon last use".
##
## The cartridge skips that second part on a two-turn release, so Disable and
## Encore landing mid-charge see the charging move rather than the released one.
## This always records the move announced, differing only in that one narrow
## interaction.
static func _used_move_text(turn: Gen2Turn) -> void:
	turn.attacker().last_move_used = turn.move_number
	turn.emit(Gen2Battle.USED_MOVE, {"move": turn.move_number})


## Struggle is what a Pokémon does when there is nothing left to spend, so it
## spends nothing, and it is the one move that arrives without a slot. Neither
## does the release turn of a two-turn move: the PP for it went on the charge
## turn, which is what [member Gen2Turn.locked] means here.
static func _do_turn(turn: Gen2Turn) -> void:
	if turn.locked:
		return

	# "If we've gotten this far, this counts as a turn", ahead of the Struggle
	# check, so Struggle counts even though it spends nothing.
	turn.attacker().turns_taken += 1

	if turn.slot >= 0 and turn.move_number != Gen2Damage.STRUGGLE:
		turn.attacker().spend_pp(turn.slot)


static func _damage_calc(turn: Gen2Turn) -> void:
	var rollout_multiplier: int = 1
	if turn.effect() == Gen2MoveEffect.ROLLOUT:
		rollout_multiplier = 1 << turn.attacker().rollout_count
		if Gen2Substatus.has(turn.attacker().substatus, Gen2Substatus.CURLED):
			rollout_multiplier *= 2
	var result: Dictionary = Gen2Damage.calculate(
		turn.attacker(), turn.defender(), turn.move, turn.rng(),
		Gen2Substatus.has(turn.attacker().substatus, Gen2Substatus.FOCUS_ENERGY),
		turn.effect() == Gen2MoveEffect.SELFDESTRUCT,
		rollout_multiplier,
		turn.battle.weather
	)
	turn.damage = int(result["damage"])
	turn.critical = bool(result["critical"])
	turn.effectiveness = int(result["effectiveness"])
	turn.immune = bool(result["immune"])
	if _doubles_flying_damage(turn) or _doubles_underground_damage(turn):
		turn.damage = mini(turn.damage * 2, 0xFFFF)


static func _check_immune(turn: Gen2Turn) -> void:
	if not turn.immune:
		return
	turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
	turn.end()


## Dream Eater's own rule ("a Pokémon that isn't asleep cannot be eaten from")
## is not a step of its own: the real cartridge folds it into this same shared
## check, reading as a miss on a target that is not asleep rather than as a
## distinct failure.
static func _check_hit(turn: Gen2Turn) -> void:
	if turn.immune:
		turn.missed = true
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		if turn.effect() != Gen2MoveEffect.SELFDESTRUCT \
			and turn.effect() != Gen2MoveEffect.ROLLOUT:
			turn.end()
		return

	if _is_hidden(turn.defender().substatus) \
		and not _can_hit_hidden(turn.move_number, turn.defender().substatus):
		turn.missed = true
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		if turn.effect() != Gen2MoveEffect.SELFDESTRUCT \
			and turn.effect() != Gen2MoveEffect.ROLLOUT:
			turn.end()
		return

	if turn.effect() == Gen2MoveEffect.DREAM_EATER \
		and not Gen2Status.is_asleep(turn.defender().status):
		turn.missed = true
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		if turn.effect() != Gen2MoveEffect.SELFDESTRUCT \
			and turn.effect() != Gen2MoveEffect.ROLLOUT:
			turn.end()
		return

	# `.ThunderRain`, ahead of the stat modifiers and the roll: Thunder never
	# misses in rain, whatever either side's accuracy and evasion say.
	if turn.effect() == Gen2MoveEffect.THUNDER \
		and turn.battle.weather == Gen2Weather.RAIN:
		return

	var chance: int = Gen2Accuracy.chance(
		turn.accuracy if turn.accuracy >= 0 \
			else int(turn.move.get("accuracy", Gen2Accuracy.ALWAYS_HITS)),
		turn.attacker().stage("accuracy"), turn.defender().stage("evasion")
	)

	# `.BrightPowder`, after the stat modifiers and before the roll: the item's
	# own parameter comes straight off the accuracy, floored at zero rather than
	# allowed to wrap. A chance of exactly 255 is the one that skips the roll, so
	# taking anything off it puts the move back on the dice.
	var powder: Gen2BattleMon = turn.defender()
	if Gen2HeldItem.effect_of(turn.data(), powder.item) == Gen2HeldItem.BRIGHTPOWDER:
		chance = maxi(chance - Gen2HeldItem.parameter_of(turn.data(), powder.item), 0)

	if Gen2Accuracy.rolls_hit(turn.rng(), chance):
		return
	turn.missed = true
	turn.emit(Gen2Battle.MISSED, {"target": turn.target})
	if turn.effect() != Gen2MoveEffect.SELFDESTRUCT \
		and turn.effect() != Gen2MoveEffect.ROLLOUT:
		turn.end()


## Takes the damage off, and reports what was actually taken.
##
## `BattleCommand_ApplyDamage` rolls the defender's Focus Band before it does,
## and a band that fires calls `BattleCommand_FalseSwipe`, which is what leaves
## the Pokémon on one hit point. The roll happens whether or not the hit would
## have been lethal, and only the survival shows.
static func _apply_damage(turn: Gen2Turn) -> void:
	if turn.missed or turn.damage <= 0:
		return
	var defender: Gen2BattleMon = turn.defender()
	turn.battle.record_damage_taken(
		turn.target, turn.side, turn.move_number, turn.effect(), turn.damage
	)

	var band: bool = Gen2HeldItem.effect_of(turn.data(), defender.item) == Gen2HeldItem.FOCUS_BAND \
		and Gen2HeldItem.rolls_under(
			turn.rng(), Gen2HeldItem.parameter_of(turn.data(), defender.item)
		)
	if band and turn.damage >= defender.hp:
		turn.dealt = defender.take_damage(defender.hp - 1)
		turn.emit(Gen2Battle.HIT, {
			"target": turn.target,
			"amount": turn.dealt,
			"critical": turn.critical,
			"effectiveness": turn.effectiveness,
			"hp": defender.hp,
			"max_hp": defender.max_hp(),
		})
		turn.emit(Gen2Battle.ENDURED, {"target": turn.target, "item": defender.item})
		return

	turn.dealt = defender.take_damage(turn.damage)
	turn.emit(Gen2Battle.HIT, {
		"target": turn.target,
		"amount": turn.dealt,
		"critical": turn.critical,
		"effectiveness": turn.effectiveness,
		"hp": defender.hp,
		"max_hp": defender.max_hp(),
	})


static func _counter(turn: Gen2Turn, mirror_coat: bool) -> void:
	var remembered: Dictionary = turn.battle.last_damage_taken(turn.side)
	var expected_effect: int = (
		Gen2MoveEffect.MIRROR_COAT if mirror_coat else Gen2MoveEffect.COUNTER
	)
	var last_move: Dictionary = turn.data().move(int(remembered.get("move", 0)))
	var valid: bool = not remembered.is_empty() \
		and int(remembered.get("source", -1)) == turn.target \
		and int(remembered.get("effect", -1)) != expected_effect \
		and not last_move.is_empty() \
		and int(last_move.get("power", 0)) > 0 \
		and Gen2Damage.is_physical(int(last_move.get("type", RomLayout.TYPE_NORMAL))) != mirror_coat \
		and int(remembered.get("damage", 0)) > 0

	if valid:
		var matchup: int = turn.data().type_effectiveness(
			int(turn.move.get("type", RomLayout.TYPE_NORMAL)), turn.defender().types()
		)
		if matchup == RomLayout.MATCHUP_NO_EFFECT:
			turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
			turn.end()
			return

		turn.damage = mini(int(remembered["damage"]) * 2, 0xFFFF)
		turn.critical = false
		turn.effectiveness = matchup
		turn.immune = false
		turn.missed = false
		return

	turn.emit(Gen2Battle.MOVE_FAILED)
	turn.end()


## Selfdestruct's command clears the user's status and sets its HP to zero.
## The faint event itself remains in CHECK_FAINT so the target is still reported
## first when the explosion also brings it down.
static func _selfdestruct(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	attacker.status = Gen2Status.NONE
	attacker.substatus &= ~(Gen2Substatus.CHARGING | Gen2Substatus.FLYING | Gen2Substatus.UNDERGROUND)
	attacker.take_damage(attacker.hp)


static func _is_hidden(substatus: int) -> bool:
	return Gen2Substatus.has(substatus, Gen2Substatus.FLYING | Gen2Substatus.UNDERGROUND)


static func _can_hit_hidden(move_number: int, substatus: int) -> bool:
	if Gen2Substatus.has(substatus, Gen2Substatus.FLYING):
		return [Gen2MoveEffect.GUST_MOVE, Gen2MoveEffect.WHIRLWIND_MOVE,
			Gen2MoveEffect.THUNDER_MOVE, Gen2MoveEffect.TWISTER_MOVE].has(move_number)
	if Gen2Substatus.has(substatus, Gen2Substatus.UNDERGROUND):
		return [Gen2MoveEffect.EARTHQUAKE_MOVE, Gen2MoveEffect.FISSURE_MOVE,
			Gen2MoveEffect.MAGNITUDE_MOVE].has(move_number)
	return false


static func _doubles_flying_damage(turn: Gen2Turn) -> bool:
	return Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.FLYING) \
		and [Gen2MoveEffect.GUST_MOVE, Gen2MoveEffect.TWISTER_MOVE].has(turn.move_number)


static func _doubles_underground_damage(turn: Gen2Turn) -> bool:
	return Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.UNDERGROUND) \
		and [Gen2MoveEffect.EARTHQUAKE_MOVE, Gen2MoveEffect.FISSURE_MOVE,
			Gen2MoveEffect.MAGNITUDE_MOVE].has(turn.move_number)


## A quarter of [member Gen2Turn.damage], the calculated number, at least one, and
## never [member Gen2Turn.dealt]. `BattleCommand_Recoil` reads the same uncapped
## `wCurDamage` [constant Gen2EffectCommands.DRAIN_TARGET] reads, so a move
## calculating fifty against a target with three HP left costs a quarter of
## fifty.
static func _recoil(turn: Gen2Turn) -> void:
	if turn.damage <= 0:
		return

	var attacker: Gen2BattleMon = turn.attacker()
	@warning_ignore("integer_division")
	var taken: int = attacker.take_damage(maxi(turn.damage / RECOIL_DIVISOR, 1))
	turn.emit(Gen2Battle.RECOIL, {
		"amount": taken, "hp": attacker.hp, "max_hp": attacker.max_hp(),
	})


## The defender first, then the attacker, which is the order they can go down in.
##
## A defender that went down ends the move: `BattleCommand_CheckFaint` finishes
## on `jp EndMoveEffect`, so the steps the cartridge places behind it, which is
## every secondary status and [constant TRAP_TARGET], never run against something
## that has already fainted. The attacker going down to its own recoil ends
## nothing, because the cartridge tests only the opponent's HP here.
##
## The commands behind it keep their own fainted-target check as well, since the
## lists that have no faint step at all, Twineedle's among them, can still reach
## one through [constant MULTI_HIT].
static func _check_faint(turn: Gen2Turn) -> void:
	for side: int in [turn.target, turn.side]:
		if turn.battle.mon(side).is_fainted():
			turn.events.append({"type": Gen2Battle.FAINTED, "side": side})
	if turn.battle.mon(turn.target).is_fainted():
		turn.end()


## CantMove on the cartridge cancels a pending two-turn move, Rollout or
## rampage. For Fly and Dig that also makes the user visible again, so a sleep,
## flinch or paralysis on the release turn cannot leave a Pokémon permanently
## untouchable.
static func _cancel_charge(mon: Gen2BattleMon) -> void:
	mon.substatus &= ~(Gen2Substatus.CHARGING | Gen2Substatus.FLYING | Gen2Substatus.UNDERGROUND)
	mon.charged_move = 0
	mon.substatus &= ~(Gen2Substatus.ROLLOUT | Gen2Substatus.RAMPAGING)
	mon.rampage_move = 0
	mon.rampage_turns = 0


## Recharge, then sleep, then freeze, then flinch, then Disable's own
## countdown, then confusion, then Attract's immobilise roll, then a
## belt-and-suspenders refusal for a Pokémon still locked into the disabled
## move itself, then paralysis. This is the cartridge's own order.
##
## A frozen Pokémon is never asked about paralysis, since the status byte cannot
## say both; a confused one that hits itself has already spent its turn.
##
## Waking up does not cost the turn: the counter runs out, the wake is printed,
## and the remaining checks continue, so the Pokémon attacks the same turn. That
## is Generation 2's rule, not Generation 1's. Confusion and Disable expire the
## same way, and [method Gen2BattleMon.can_use] has already refused a disabled
## slot before this runs.
static func _check_status(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()

	if Gen2Substatus.has(mon.substatus, Gen2Substatus.RECHARGING):
		_cancel_charge(mon)
		mon.substatus &= ~Gen2Substatus.RECHARGING
		turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"recharge"})
		turn.end()
		return

	if Gen2Status.is_asleep(mon.status):
		mon.status = Gen2Status.tick_sleep(mon.status)
		if Gen2Status.is_asleep(mon.status):
			_cancel_charge(mon)
			turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"sleep"})
			turn.end()
			return
		turn.emit(Gen2Battle.WOKE_UP)

	if Gen2Status.has(mon.status, Gen2Status.FREEZE):
		# Flame Wheel and Sacred Fire are used through a freeze, and thaw the
		# Pokémon using them; nothing else in the game does.
		if not THAWING_MOVES.has(turn.move_number):
			_cancel_charge(mon)
			turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"freeze"})
			turn.end()
			return
		mon.status &= ~Gen2Status.FREEZE
		turn.emit(Gen2Battle.THAWED)

	if Gen2Substatus.has(mon.substatus, Gen2Substatus.FLINCHED):
		_cancel_charge(mon)
		mon.substatus &= ~Gen2Substatus.FLINCHED
		turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"flinch"})
		turn.end()
		return

	if mon.disabled_slot >= 0:
		mon.disable_turns -= 1
		if mon.disable_turns <= 0:
			var slot: int = mon.disabled_slot
			mon.disabled_slot = -1
			mon.disable_turns = 0
			turn.emit(Gen2Battle.DISABLE_ENDED, {"slot": slot})

	if Gen2Substatus.has(mon.substatus, Gen2Substatus.CONFUSED):
		mon.confusion_turns -= 1
		if mon.confusion_turns <= 0:
			mon.substatus &= ~Gen2Substatus.CONFUSED
			turn.emit(Gen2Battle.SNAPPED_OUT)
		else:
			turn.emit(Gen2Battle.CONFUSED)
			if Gen2Substatus.rolls_confusion_hit(turn.rng()):
				_cancel_charge(mon)
				var dealt: int = mon.take_damage(Gen2Damage.confusion_damage(mon, turn.rng()))
				turn.emit(Gen2Battle.HURT_ITSELF, {
					"amount": dealt, "hp": mon.hp, "max_hp": mon.max_hp(),
				})
				turn.end()
				return

	if Gen2Substatus.has(mon.substatus, Gen2Substatus.ATTRACTED) \
		and Gen2Substatus.rolls_attract_immobile(turn.rng()):
		_cancel_charge(mon)
		turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"attract"})
		turn.end()
		return

	# Last line of defence against using a disabled move. By move number, not by
	# slot: can_use() has already turned a request for the disabled slot into
	# Struggle, while Gen2Turn.slot still names the slot asked for, so comparing
	# slots would refuse that Struggle too.
	if mon.disabled_slot >= 0 and mon.disabled_slot < mon.moves.size() \
		and turn.move_number == int(mon.moves[mon.disabled_slot]):
		_cancel_charge(mon)
		turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"disabled"})
		turn.end()
		return

	if Gen2Status.has(mon.status, Gen2Status.PARALYSIS) \
		and Gen2Status.rolls_full_paralysis(turn.rng()):
		_cancel_charge(mon)
		turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"paralysis"})
		turn.end()


## A secondary effect's roll: a byte out of 256 in the move's table, like
## accuracy, gating only what comes after it, since the damage in front has
## already landed. A chance of zero never fires, which is what the cartridge's
## comparison does too: zero means never, not "unspecified".
static func _effect_chance(turn: Gen2Turn) -> void:
	var chance: int = int(turn.move.get("effect_chance", 0))
	if turn.rng().randi_range(0, Gen2Status.CHANCE_RANGE - 1) >= chance:
		turn.failed_chance = true


## Puts a status on the defender, or fails.
##
## One status at a time: a Pokémon that already has something on its byte is
## refused rather than added to, and so is one whose type makes it immune. A
## sleep is rolled for how long it lasts; the rest are a flag.
static func _status_target(turn: Gen2Turn, flag: int) -> void:
	if turn.failed_chance:
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted() or Gen2Status.is_afflicted(defender.status):
		return

	# `BattleCommand_FreezeTarget` refuses outright in sun. It is the only one of
	# the five statuses the weather has anything to say about.
	if flag == Gen2Status.FREEZE and turn.battle.weather == Gen2Weather.SUN:
		return

	if flag == Gen2Status.SLEEP_MASK:
		defender.status = Gen2Status.roll_sleep(turn.rng())
	else:
		defender.status |= flag

	turn.emit(Gen2Battle.STATUS_INFLICTED, {
		"target": turn.target,
		"status": defender.status,
		"name": Gen2Status.name_of(defender.status),
	})

	# Every status-inflicting command calls `UseHeldStatusHealingItem` on the
	# Pokémon it just afflicted, so a berry answers at once rather than waiting
	# for the end of the turn.
	turn.battle.use_status_berry(turn.target, turn.events)


## Poisons the target the way [constant POISON_TARGET] does, and starts the
## counter that makes it Toxic rather than an ordinary poison: see
## [method Gen2Status.toxic_damage], which reads it back at the end of every
## turn from here on.
static func _toxic_target(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted() or Gen2Status.is_afflicted(defender.status):
		return

	defender.status |= Gen2Status.POISON
	defender.toxic_counter = 1
	turn.emit(Gen2Battle.STATUS_INFLICTED, {
		"target": turn.target, "status": defender.status, "name": &"toxic",
	})
	turn.battle.use_status_berry(turn.target, turn.events)


## Sets the target flinching, for [constant CHECK_STATUS] to catch on its turn.
## Only ever a secondary effect, so it obeys [member Gen2Turn.failed_chance] the
## same way a status target does; a fainted target cannot be made to flinch on
## a turn it will not take.
static func _flinch_target(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted():
		return

	defender.substatus |= Gen2Substatus.FLINCHED


## Sets the target confused and rolls its duration, or fails. An already-confused
## Pokémon is refused rather than having its counter restarted, the rule
## [Gen2Substatus.CONFUSED] enforces. Unlike a status, confusion sits alongside
## one: a poisoned Pokémon can still be confused.
static func _confuse_target(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted() or Gen2Substatus.has(defender.substatus, Gen2Substatus.CONFUSED):
		return

	defender.substatus |= Gen2Substatus.CONFUSED
	defender.confusion_turns = Gen2Substatus.roll_confusion(turn.rng())

	# Not [constant Gen2Battle.STATUS_INFLICTED]: that event's [code]status[/code]
	# field is the status byte, and confusion never touches it.
	turn.emit(Gen2Battle.CONFUSE_INFLICTED, {"target": turn.target})

	# `BattleCommand_Confuse` reaches `UseConfusionHealingItem` the moment the
	# confusion lands, the same way a status berry answers a status.
	turn.battle.use_confusion_berry(turn.target, turn.events)


## Heals the attacker for half of what the hit calculated, at least one.
##
## Half of [member Gen2Turn.damage], the calculated number, not half of
## [member Gen2Turn.dealt]. The cartridge's drain reads the same uncapped figure
## [constant APPLY_DAMAGE] read before clamping, so a move calculating fifty
## against a target with three HP left heals twenty-five.
static func _drain_target(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	@warning_ignore("integer_division")
	var healed: int = attacker.heal(maxi(turn.damage / 2, 1))
	turn.emit(Gen2Battle.DRAINED, {
		# "from" rather than "target": the healing lands on the attacker, whose
		# hp and max_hp these are, but the message names who it was sucked from.
		"from": turn.target, "amount": healed, "hp": attacker.hp, "max_hp": attacker.max_hp(),
	})


## Two to five hits for [constant Gen2MoveEffect.MULTI_HIT], or exactly two for
## [constant Gen2MoveEffect.DOUBLE_HIT] and [constant Gen2MoveEffect.TWINEEDLE].
##
## [constant CHECK_HIT] has already rolled the one accuracy check the whole move
## gets, before the repeat loop starts. The first hit reuses
## [constant DAMAGE_CALC]'s numbers; every later hit rerolls the critical and the
## spread, as the cartridge's loop does. A faint ends the move where it stands,
## which is why the "hit N times" summary is only sent when every planned hit
## landed.
static func _multi_hit(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()
	var hits: int = 2 if FIXED_TWO_HIT_EFFECTS.has(turn.effect()) else _roll_multi_hit_count(turn.rng())

	var focus_energy: bool = Gen2Substatus.has(attacker.substatus, Gen2Substatus.FOCUS_ENERGY)
	for hit: int in hits:
		if hit > 0:
			var result: Dictionary = Gen2Damage.calculate(
				attacker, defender, turn.move, turn.rng(), focus_energy,
				false, 1, turn.battle.weather
			)
			turn.damage = int(result["damage"])
			turn.critical = bool(result["critical"])
			turn.effectiveness = int(result["effectiveness"])

		turn.dealt = defender.take_damage(turn.damage)
		turn.battle.record_damage_taken(
			turn.target, turn.side, turn.move_number, turn.effect(), turn.damage
		)
		turn.emit(Gen2Battle.HIT, {
			"target": turn.target, "amount": turn.dealt, "critical": turn.critical,
			"effectiveness": turn.effectiveness, "hp": defender.hp, "max_hp": defender.max_hp(),
		})

		if defender.is_fainted():
			_check_faint(turn)
			turn.end()
			return

	turn.emit(Gen2Battle.HIT_TIMES, {"target": turn.target, "times": hits})


const FIXED_TWO_HIT_EFFECTS: Array = [Gen2MoveEffect.DOUBLE_HIT, Gen2MoveEffect.TWINEEDLE]


## How many times a generic multi-hit move connects, following the cartridge's
## own two-roll algorithm: a first roll out of four keeps 0 or 1 outright, or
## triggers a second roll out of four for 2 or 3, so 2 and 3 hits come up three
## times as often as 4 and 5 do (37.5%, 37.5%, 12.5%, 12.5%).
static func _roll_multi_hit_count(rng: RandomNumberGenerator) -> int:
	var first: int = rng.randi_range(0, 3)
	if first < 2:
		return first + 2
	return rng.randi_range(0, 3) + 2


## Overwrites [constant DAMAGE_CALC] with the number these four effects deal,
## none from the ordinary formula: [constant Gen2MoveEffect.LEVEL_DAMAGE] the
## user's level, [constant Gen2MoveEffect.PSYWAVE] a roll of it,
## [constant Gen2MoveEffect.SUPER_FANG] half the target's current HP, and
## [constant Gen2MoveEffect.STATIC_DAMAGE] the move's power field taken directly.
## None criticals or announces effectiveness, since the number was never
## multiplied by either; only the immunity from the spent
## [constant DAMAGE_CALC] roll is kept, and [constant CHECK_IMMUNE] has already
## acted on it.
static func _fixed_damage(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()

	match turn.effect():
		Gen2MoveEffect.LEVEL_DAMAGE:
			turn.damage = attacker.level
		Gen2MoveEffect.PSYWAVE:
			turn.damage = Gen2Damage.psywave_damage(attacker.level, turn.rng())
		Gen2MoveEffect.SUPER_FANG:
			@warning_ignore("integer_division")
			turn.damage = maxi(defender.hp / 2, 1)
		_: # STATIC_DAMAGE: Sonicboom and Dragon Rage deal exactly their own power.
			turn.damage = int(turn.move.get("power", 0))

	turn.critical = false
	turn.effectiveness = RomLayout.MATCHUP_EFFECTIVE


## How much an attacker's own level adds to an OHKO move's accuracy, doubled
## and added to the move's stored 30%-ish base once the defender's level is
## subtracted off.
const OHKO_LEVEL_BONUS: int = 2

## Guillotine, Horn Drill and Fissure: an instant faint with its own accuracy
## rule rather than the move's stored one read plainly.
##
## A higher-level defender is immune outright, with no roll. Otherwise the stored
## accuracy (a shade under 30%) rises by two per level the attacker leads by,
## capped as any accuracy is, and rolls through the ordinary stage machinery, so
## lowered evasion or raised accuracy helps a one-hit KO like any other move.
static func _ohko(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()

	if attacker.level < defender.level:
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		turn.end()
		return

	var accuracy: int = clampi(
		int(turn.move.get("accuracy", 0)) + (attacker.level - defender.level) * OHKO_LEVEL_BONUS,
		0, Gen2Accuracy.ALWAYS_HITS
	)
	var chance: int = Gen2Accuracy.chance(
		accuracy, attacker.stage("accuracy"), defender.stage("evasion")
	)
	if not Gen2Accuracy.rolls_hit(turn.rng(), chance):
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		turn.end()
		return

	turn.battle.record_damage_taken(
		turn.target, turn.side, turn.move_number, turn.effect(), 0xFFFF
	)
	var dealt: int = defender.take_damage(defender.hp)
	turn.emit(Gen2Battle.OHKO, {
		"target": turn.target, "amount": dealt, "hp": defender.hp, "max_hp": defender.max_hp(),
	})
	_check_faint(turn)


## Locks the user out of its next turn. The tail of Hyper Beam's own list,
## always reached: there is no roll behind it and nothing it can fail against.
static func _recharge(turn: Gen2Turn) -> void:
	turn.attacker().substatus |= Gen2Substatus.RECHARGING


## A two-turn move's charge, in the shape [code]docs/CONTRIBUTING.md[/code]
## already describes: a list that ends early the first time.
##
## Not charging yet: lock the user in, announce it and end the move before damage
## is worked out. Already charging, the release turn: clear the lock and fall
## through into an ordinary attack. [method Gen2Battle.move_for] guarantees the
## release turn uses the charged move whatever slot is asked for.
static func _charge_move(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if Gen2Substatus.has(mon.substatus, Gen2Substatus.CHARGING):
		mon.substatus &= ~Gen2Substatus.CHARGING
		mon.substatus &= ~(Gen2Substatus.FLYING | Gen2Substatus.UNDERGROUND)
		mon.charged_move = 0
		return

	if turn.skip_charge:
		return

	mon.substatus |= Gen2Substatus.CHARGING
	mon.charged_move = turn.move_number
	if turn.effect() == Gen2MoveEffect.FLY_OR_DIG:
		if turn.move_number == Gen2MoveEffect.FLY_MOVE:
			mon.substatus |= Gen2Substatus.FLYING
		elif turn.move_number == Gen2MoveEffect.DIG_MOVE:
			mon.substatus |= Gen2Substatus.UNDERGROUND
	turn.emit(Gen2Battle.CHARGING_UP)
	turn.end()


## A new Rollout starts a fresh count. A continuation leaves the count alone so
## [method _damage_calc] can apply the next power before this command advances
## it after a successful hit.
static func _rollout_check(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if not Gen2Substatus.has(mon.substatus, Gen2Substatus.ROLLOUT):
		mon.rollout_count = 0


## Rollout's power step runs after the hit check. A miss, including an immunity,
## ends the chain. A successful fifth hit also clears the continuation flag, but
## its count is retained until the next Rollout starts and resets it.
static func _rollout_power(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if turn.missed:
		mon.substatus &= ~Gen2Substatus.ROLLOUT
		return

	mon.rollout_count += 1
	if mon.rollout_count >= 5:
		mon.substatus &= ~Gen2Substatus.ROLLOUT
	else:
		mon.substatus |= Gen2Substatus.ROLLOUT


## Thrash, Petal Dance and Outrage share the rampage flag. The first turn rolls
## one or two future turns. Each forced continuation consumes one of those turns;
## when the last one is consumed, the user becomes confused after still getting
## this final attack.
static func _rampage(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if Gen2Substatus.has(mon.substatus, Gen2Substatus.RAMPAGING):
		mon.rampage_turns -= 1
		if mon.rampage_turns <= 0:
			mon.substatus &= ~Gen2Substatus.RAMPAGING
			mon.rampage_move = 0
			mon.confusion_turns = Gen2Substatus.roll_rampage_confusion(turn.rng())
			mon.substatus |= Gen2Substatus.CONFUSED
		return

	mon.substatus |= Gen2Substatus.RAMPAGING
	mon.rampage_move = turn.move_number
	mon.rampage_turns = Gen2Substatus.roll_rampage_turns(turn.rng())


## Defense Curl's flag is independent of whether its Defense stage changed. It
## remains until the Pokémon switches and doubles every later Rollout power.
static func _curl(turn: Gen2Turn) -> void:
	turn.attacker().substatus |= Gen2Substatus.CURLED


## Haze: every stage on both sides, back to nothing. Not [Gen2Substatus] and not
## the status byte, either side's: only what [method Gen2BattleMon.reset_stages]
## already resets on a switch is reset here on demand.
static func _haze(turn: Gen2Turn) -> void:
	turn.battle.mon(Gen2Battle.PLAYER).reset_stages()
	turn.battle.mon(Gen2Battle.ENEMY).reset_stages()
	turn.emit(Gen2Battle.STAGES_CLEARED)


## Belly Drum. Fails, and costs nothing, unless the user has more than half its
## maximum HP and Attack has somewhere left to go; otherwise it takes half the
## maximum off and sends Attack straight to the top, however far short of it
## the stage already was.
static func _belly_drum(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	var has_enough_hp: bool = mon.hp * 2 > mon.max_hp()
	var stage: int = mon.stage("attack")
	if not has_enough_hp or stage >= Gen2Stats.MAX_STAGE:
		turn.emit(Gen2Battle.STAT_CHANGE_FAILED, {"target": turn.side, "stat": "attack", "by": 6})
		return

	@warning_ignore("integer_division")
	mon.take_damage(mon.max_hp() / 2)
	mon.change_stage("attack", Gen2Stats.MAX_STAGE - stage)
	turn.emit(Gen2Battle.STAT_CHANGED, {"target": turn.side, "stat": "attack", "by": 6})


## Psych Up: the target's seven stages, copied onto the user in one go, or a
## failure if the target has nothing raised or lowered for there to be anything
## to copy.
static func _psych_up(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()
	var keys: Array = Gen2BattleMon.STAGED_STATS + Gen2BattleMon.STAGED_ODDS

	var defender_changed: bool = false
	for key: String in keys:
		if int(defender.stages.get(key, 0)) != 0:
			defender_changed = true
			break
	if not defender_changed:
		return

	for key: String in keys:
		attacker.stages[key] = int(defender.stages.get(key, 0))
	turn.emit(Gen2Battle.STAGES_COPIED)


## Locks whichever of the target's slots holds
## [member Gen2BattleMon.last_move_used], found by searching the target's move
## list as the cartridge does, since nothing the attacker did carries the slot.
##
## Fails silently if the target has not moved this battle, the move was Struggle,
## the target is already disabled, the move is no longer in its list (a mid-battle
## level up can replace a slot, which the cartridge never has to consider), or
## that slot is out of PP.
static func _disable(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	if defender.disabled_slot >= 0:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	var last_move: int = defender.last_move_used
	if last_move == 0 or last_move == Gen2Damage.STRUGGLE:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	var slot: int = defender.moves.find(last_move)
	if slot < 0 or defender.pp_left(slot) <= 0:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	defender.disabled_slot = slot
	defender.disable_turns = Gen2Substatus.roll_disable(turn.rng())
	turn.emit(Gen2Battle.DISABLE_INFLICTED, {
		"target": turn.target, "slot": slot, "move": last_move,
	})


## Locks the target into repeating [member Gen2BattleMon.last_move_used] for a
## few turns, found and refused as [method _disable] does, plus the two moves the
## cartridge names outright: see [constant ENCORE_EXCLUDED_MOVES].
##
## The forcing happens elsewhere: [method Gen2Battle.effective_slot] and
## [method Gen2Battle.move_for] read [member Gen2BattleMon.encored_slot] when a
## side acts, as a two-turn release reads
## [member Gen2BattleMon.charged_move].
static func _encore(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	if defender.encored_slot >= 0:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	var last_move: int = defender.last_move_used
	if last_move == 0 or last_move == Gen2Damage.STRUGGLE \
		or ENCORE_EXCLUDED_MOVES.has(last_move):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	var slot: int = defender.moves.find(last_move)
	if slot < 0 or defender.pp_left(slot) <= 0:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	defender.encored_slot = slot
	defender.encore_turns = Gen2Substatus.roll_encore(turn.rng())
	defender.substatus |= Gen2Substatus.ENCORED
	turn.emit(Gen2Battle.ENCORE_INFLICTED, {"target": turn.target, "slot": slot, "move": last_move})


## Puts the target in love, given opposite known genders (a genderless Pokémon or
## a matching pair refuses, as does one already in love).
## [constant Gen2EffectCommands.CHECK_STATUS] rolls each turn from here on
## whether that stops the target moving.
static func _attract(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()
	if Gen2Substatus.has(defender.substatus, Gen2Substatus.ATTRACTED):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	var user_gender: StringName = attacker.gender()
	var target_gender: StringName = defender.gender()
	if user_gender == Gen2BattleMon.GENDER_NONE or target_gender == Gen2BattleMon.GENDER_NONE \
		or user_gender == target_gender:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	defender.substatus |= Gen2Substatus.ATTRACTED
	turn.emit(Gen2Battle.ATTRACT_INFLICTED, {"target": turn.target})


## Shields the user from the opponent's own stat-lowering moves, until a
## switch: [method _stat_change] is what actually blocks a drop, reading this
## flag back off whichever side a drop is aimed at. Fails, without
## re-applying, on a second use, the same as [method _focus_energy].
static func _mist(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if Gen2Substatus.has(mon.substatus, Gen2Substatus.MIST):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	mon.substatus |= Gen2Substatus.MIST
	turn.emit(Gen2Battle.MIST_SET)


## Raises the user's own critical-hit rate for the rest of the battle, until a
## switch: [method _damage_calc] and [method _multi_hit] are what read this
## flag back, through [method Gen2Damage.calculate]'s own [code]focus_energy[/code]
## argument. Fails, without re-applying, on a second use.
static func _focus_energy(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if Gen2Substatus.has(mon.substatus, Gen2Substatus.FOCUS_ENERGY):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	mon.substatus |= Gen2Substatus.FOCUS_ENERGY
	turn.emit(Gen2Battle.FOCUS_ENERGY_SET)


## Binds the target for three to six turns, of which
## [method Gen2Battle._tick_wrap] spends the first without damage.
##
## `BattleCommand_TrapTarget`'s own three refusals, in its order: a missed move,
## a target that is already bound, and a target behind a Substitute. The first is
## structural here, since [method _check_hit] ends the move before this step is
## reached, and the third has nothing to read until Substitute exists. An
## already-bound target is silent rather than a [constant Gen2Battle.MOVE_FAILED],
## because the cartridge returns without printing anything.
static func _trap_target(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	if defender.trapped_turns > 0:
		return

	defender.trapped_turns = Gen2Substatus.roll_trap_turns(turn.rng())
	defender.trapping_move = turn.move_number
	turn.emit(Gen2Battle.TRAPPED, {
		"target": turn.target, "move": turn.move_number, "turns": defender.trapped_turns,
	})


## Stops the target running or being recalled for as long as the user stays out.
##
## `BattleCommand_ArenaTrap` fails against a target that is flying or
## underground (`CheckHiddenOpponent`) and against one already held, and the
## check for "already held" is the user's own flag rather than the target's: two
## Mean Looks from the same Pokémon is what fails, not a Mean Look on a target
## the opponent's previous Pokémon had already caught.
static func _arena_trap(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	if _is_hidden(turn.defender().substatus) \
		or Gen2Substatus.has(attacker.substatus, Gen2Substatus.CANT_RUN):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	attacker.substatus |= Gen2Substatus.CANT_RUN
	turn.emit(Gen2Battle.CANT_ESCAPE_SET, {"target": turn.target})


## Sets the weather for [constant Gen2Weather.TURNS], the turn it is used
## counting as the first.
##
## Only `BattleCommand_StartSandstorm` has a `.failed` branch, and it fails
## against its own weather alone: Sunny Day in sun and Rain Dance in rain both
## restart the count and print their line again, and either of them replaces a
## Sandstorm outright.
static func _start_weather(turn: Gen2Turn, weather: int) -> void:
	if weather == Gen2Weather.SANDSTORM and turn.battle.weather == Gen2Weather.SANDSTORM:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	turn.battle.weather = weather
	turn.battle.weather_turns = Gen2Weather.TURNS
	turn.emit(Gen2Battle.WEATHER_STARTED, {"weather": weather})


## Thunder's accuracy for this turn: `50 percent + 1` (128) in sun, and
## `100 percent` (255) in rain.
##
## Written on the turn rather than on the move, because the cartridge writes it
## into `wPlayerMoveStruct`, a per-turn copy, while [member Gen2Turn.move] is the
## cached row every future Thunder would read.
static func _thunder_accuracy(turn: Gen2Turn) -> void:
	match turn.battle.weather:
		Gen2Weather.SUN:
			turn.accuracy = THUNDER_SUN_ACCURACY
		Gen2Weather.RAIN:
			turn.accuracy = Gen2Accuracy.ALWAYS_HITS


## Solarbeam in sun, which is a one-turn move: the charge is skipped the way
## `checkcharge` skips it on a release turn. A release turn reaches
## [method _charge_move]'s own charging branch first, so this only ever answers
## for the turn a charge would have started.
static func _skip_sun_charge(turn: Gen2Turn) -> void:
	if turn.battle.weather == Gen2Weather.SUN:
		turn.skip_charge = true


## `BattleCommand_HeldFlinch`: a King's Rock on the attacker makes an ordinary
## attack flinch, out of the item's own parameter.
##
## The `wAttackMissed` guard is structural here, since [method _check_hit] ends
## the move on a miss and [method _check_faint] ends it on a KO, so this step is
## only ever reached by a hit that left the target standing. The Substitute check
## has nothing to read yet.
static func _kings_rock(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	if Gen2HeldItem.effect_of(turn.data(), attacker.item) != Gen2HeldItem.FLINCH:
		return
	if not Gen2HeldItem.rolls_under(
		turn.rng(), Gen2HeldItem.parameter_of(turn.data(), attacker.item)
	):
		return

	turn.defender().substatus |= Gen2Substatus.FLINCHED


## Moves one stat by one command's worth, and writes down who it happened to and
## whether it actually moved, for the message step behind it to read.
##
## A secondary effect's failed roll skips this as it skips a status: the damage in
## front has already landed.
##
## A drop against a target shielded by Mist never reaches
## [method Gen2BattleMon.change_stage]: every lowering entry targets the opponent
## (`entry[2]` false), which is exactly what Mist blocks. A rise always targets
## the user and is never checked, matching [code]CheckMist[/code] gating only the
## "down" and "down2" effect-byte ranges.
static func _stat_change(command: StringName, turn: Gen2Turn) -> void:
	var entry: Array = STAT_COMMANDS[command]
	var stat_key: String = String(entry[0])
	var amount: int = int(entry[1])
	var targets_user: bool = bool(entry[2])
	var side: int = turn.side if targets_user else turn.target

	turn.stat_key = stat_key
	turn.stat_by = amount
	turn.stat_target = side
	turn.stat_mist_blocked = false

	if turn.failed_chance:
		turn.stat_moved = false
		return

	if not targets_user and Gen2Substatus.has(turn.battle.mon(side).substatus, Gen2Substatus.MIST):
		turn.stat_moved = false
		turn.stat_mist_blocked = true
		return

	turn.stat_moved = turn.battle.mon(side).change_stage(stat_key, amount)


## Ancientpower's roll: the user's five real stats, all at once, reported as one
## event rather than five. Accuracy and evasion are not among them, because the
## cartridge's own command loops over the five a stage multiplies a real number
## for and not the two that only have a table of their own.
static func _all_stats_up(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return

	var mon: Gen2BattleMon = turn.attacker()
	var moved: bool = false
	for key: String in ALL_STATS_KEYS:
		if mon.change_stage(key, 1):
			moved = true

	if moved:
		turn.emit(Gen2Battle.STAT_CHANGED, {"target": turn.side, "stat": "all", "by": 1})


## Says a stat moved, or says nothing. A move whose sequence has no fail-text
## step behind this, which is every secondary effect, is silent either way when
## the stage was already at its limit.
static func _stat_message(turn: Gen2Turn) -> void:
	if not turn.stat_moved:
		return
	turn.emit(Gen2Battle.STAT_CHANGED, {
		"target": turn.stat_target, "stat": turn.stat_key, "by": turn.stat_by,
	})


## Says a stat could not move. Only reached from a status move's sequence, the
## only place [code]data/moves/effects.asm[/code] follows a message step with
## [code]statdownfailtext[/code]; an on-hit drop blocked by Mist fails silently,
## like any on-hit drop that misses its roll.
##
## Mist gets its own line, because
## [code]BattleCommand_StatDownFailText[/code] prints
## [code]ProtectedByMistText[/code] here rather than "won't go any lower".
static func _stat_fail_text(turn: Gen2Turn) -> void:
	if turn.stat_moved:
		return
	if turn.stat_mist_blocked:
		turn.emit(Gen2Battle.MIST_PROTECTED, {"target": turn.stat_target})
		return
	turn.emit(Gen2Battle.STAT_CHANGE_FAILED, {
		"target": turn.stat_target, "stat": turn.stat_key, "by": turn.stat_by,
	})
