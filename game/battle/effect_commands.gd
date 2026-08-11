class_name Gen2EffectCommands
extends RefCounted

## The steps a move is made of.
##
## A move is a short program, not a switch case: the cartridge keeps a command
## list per effect and runs it in order. An ordinary attack announces the move,
## spends the PP, works out damage, rolls the hit, applies it and checks for a
## faint; every other move is that list with steps added, removed or replaced, so
## a burn is an appended command and a move that cannot miss is a list without
## the roll. None of it reaches [Gen2Battle], which only knows how to run a list.
##
## The names are the cartridge's, so a sequence reads against
## [code]data/moves/effects.asm[/code] line for line. [Gen2MoveEffect] holds the
## lists.

## Announces the move. First, because a move that fails still says it was used.
const USED_MOVE_TEXT: StringName = &"usedmovetext"

## Spends the PP.
const DO_TURN: StringName = &"doturn"

## The five steps a hit is worked out in, which are five commands on the
## cartridge and not one: an effect that reaches inside the formula does so
## between two of them. Present sets the power between [constant DAMAGE_STATS]
## and [constant DAMAGE_CALC], Triple Kick multiplies between
## [constant DAMAGE_CALC] and [constant STAB], and Fury Cutter and Rollout
## between [constant STAB] and [constant DAMAGE_VARIATION]. Nothing is applied
## by any of them, and nothing has been rolled for whether the move connects.
const CRITICAL: StringName = &"critical"
const DAMAGE_STATS: StringName = &"damagestats"
const DAMAGE_CALC: StringName = &"damagecalc"
const STAB: StringName = &"stab"
const DAMAGE_VARIATION: StringName = &"damagevariation"

## `doubleflyingdamage`, `doubleundergrounddamage` and `doubleminimizedamage`,
## which are one routine under three gates and sit behind the spread: Gust and
## Twister reach a target that is out of sight above, Earthquake and Magnitude
## one below, and Stomp one that has made itself small.
const DOUBLE_DAMAGE: StringName = &"doubledamage"

## The four steps that write a power over the move's own, all of them between
## [constant DAMAGE_STATS] and [constant DAMAGE_CALC] where the cartridge writes
## into `wPlayerMoveStruct`. [constant HIDDEN_POWER] writes a type as well and
## runs `damagestats` itself, which is why its list carries no `damagestats` of
## its own.
const HAPPINESS_POWER: StringName = &"happinesspower"
const FRUSTRATION_POWER: StringName = &"frustrationpower"
const GET_MAGNITUDE: StringName = &"getmagnitude"
const HIDDEN_POWER: StringName = &"hiddenpower"

## Present, which is a power table with a fourth row that heals the target
## instead of hitting it.
const PRESENT: StringName = &"present"

## The two that multiply the finished damage: Fury Cutter between
## [constant STAB] and [constant DAMAGE_VARIATION], Triple Kick between
## [constant DAMAGE_CALC] and [constant STAB]. [constant KICK_COUNTER] is what
## walks Triple Kick from one kick to the next.
const FURY_CUTTER: StringName = &"furycutter"
const TRIPLE_KICK: StringName = &"triplekick"
const KICK_COUNTER: StringName = &"kickcounter"

## False Swipe, which leaves the target on one hit point rather than none.
const FALSE_SWIPE: StringName = &"falseswipe"

## `resettypematchup`: the constant-damage moves' own immunity check, and the
## reason their lists carry no `stab`. Announces nothing about effectiveness,
## since a fixed number was never multiplied by a matchup.
const RESET_TYPE_MATCHUP: StringName = &"resettypematchup"

## Heal Bell, which clears the status of every Pokémon in the user's party.
const HEAL_BELL: StringName = &"healbell"

## Snore, which fails unless its user is asleep.
const SNORE: StringName = &"snore"

## Tri Attack's one-in-three pick between paralysis, freeze and burn.
const TRI_STATUS_CHANCE: StringName = &"tristatuschance"

## `defrost`: Flame Wheel and Sacred Fire thawing their own user. Not
## `defrostopponent`, which is effect byte 96 and carried by no move either game
## ships.
const DEFROST: StringName = &"defrost"

## Splash, which is the one move whose whole implementation is saying that
## nothing happened.
const SPLASH: StringName = &"splash"

## Commands for the called-, copied- and type-changing move families. The three
## called moves ask [Gen2Battle] to restart the effect interpreter through
## [member Gen2Turn.called_move_number].
const MIRROR_MOVE: StringName = &"mirrormove"
const MIMIC: StringName = &"mimic"
const METRONOME: StringName = &"metronome"
const SKETCH: StringName = &"sketch"
const SLEEP_TALK: StringName = &"sleeptalk"
const CONVERSION: StringName = &"conversion"
const CONVERSION_2: StringName = &"conversion2"

const STORE_ENERGY: StringName = &"storeenergy"
const UNLEASH_ENERGY: StringName = &"unleashenergy"
const RAGE: StringName = &"rage"
const RAGE_DAMAGE: StringName = &"ragedamage"
const BUILD_OPPONENT_RAGE: StringName = &"buildopponentrage"
const CHECK_FUTURE_SIGHT: StringName = &"checkfuturesight"
const FUTURE_SIGHT: StringName = &"futuresight"
const PAY_DAY: StringName = &"payday"
const TRANSFORM: StringName = &"transform"

const CURSE_TYPE: int = 0x13
## Conversion2's accepted random type bytes: the physical run including BIRD,
## then the special run. The padding from $0a through $13 and everything at or
## beyond $1c is rejected by the source loop.
const CONVERSION_2_TYPES: Array[int] = [
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
	0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B,
]

## `MetronomeExcepts`, move numbers rather than effects. The caller's own move
## set is checked separately, exactly as `CheckUserMove` does after this table.
const METRONOME_EXCEPTS: Array[int] = [
	0, Gen2MoveEffect.METRONOME_MOVE, Gen2Damage.STRUGGLE,
	Gen2MoveEffect.SKETCH_MOVE, Gen2MoveEffect.MIMIC_MOVE, 68, 243,
	182, 197, 203, 194, Gen2MoveEffect.SLEEP_TALK_MOVE, 168,
]

## `.check_two_turn_move`, the six effect bytes Sleep Talk resamples. Bide is
## included even before its own effect body is implemented because the source
## refuses it by effect, not by capability.
const SLEEP_TALK_EXCLUDED_EFFECTS: Array[int] = [
	Gen2MoveEffect.SKULL_BASH, Gen2MoveEffect.RAZOR_WIND,
	Gen2MoveEffect.SKY_ATTACK, Gen2MoveEffect.SOLARBEAM,
	Gen2MoveEffect.FLY_OR_DIG, 26,
]

## `BattleCommand_SwitchTurn`: swaps who is acting and who is being acted on for
## the commands between two of them. Swagger is the only list that uses it, to
## raise the *target's* Attack with the ordinary `attackup2`.
const SWITCH_TURN: StringName = &"switchturn"

## Ends the move if the defender cannot be touched by it at all. Separate from
## the roll, because an immunity is not a miss and does not read as one.
const CHECK_IMMUNE: StringName = &"checkimmune"

## Rolls whether the move connects, and ends it if it does not.
const CHECK_HIT: StringName = &"checkhit"

## The effects whose list still has work to do after a miss, and so are not
## ended by [constant CHECK_HIT].
##
## `BattleCommand_CheckHit` never ends anything on the cartridge: it writes
## `wAttackMissed` and the list runs on until `failuretext`, which is where a
## miss is announced and the move stops. This engine has no `failuretext`, so
## the hit check ends the move instead and these three are the lists with a
## command between the two: Selfdestruct faints its user whether or not it
## connected, Rollout's `rolloutpower` breaks the chain on a miss, and Fury
## Cutter's `furycutter` puts its count back to nothing.
const CONTINUES_AFTER_MISS: Array[int] = [
	Gen2MoveEffect.SELFDESTRUCT, Gen2MoveEffect.ROLLOUT, Gen2MoveEffect.FURY_CUTTER,
]

## The two effects `BattleCommand_CheckHit`'s `.DrainSub` turns into a miss when
## the target is behind a Substitute, and the whole of what that branch names.
const DRAINING_EFFECTS: Array[int] = [
	Gen2MoveEffect.LEECH_HIT, Gen2MoveEffect.DREAM_EATER,
]

## The three moves `BattleCommand_CheckHit`'s `.LockOn` names by number: a
## locked-on target that is flying is still out of reach of the three that only
## strike downwards.
##
## Fissure is named and unreachable, here and on the cartridge: `OHKOHit` carries
## no `checkhit`, so no `EFFECT_OHKO` move ever reads the flag.
const LOCK_ON_GROUND_MOVES: Array[int] = [
	Gen2MoveEffect.EARTHQUAKE_MOVE, Gen2MoveEffect.FISSURE_MOVE,
	Gen2MoveEffect.MAGNITUDE_MOVE,
]

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

## `BattleCommand_Screen`, which is Light Screen and Reflect both: one command
## that reads the move's own effect byte to decide which bit it is setting.
## Fails, without restarting the count, on a second use of the same one.
const SCREEN: StringName = &"screen"

## `BattleCommand_Safeguard`, the same shape a side at a time: sets the flag for
## [constant Gen2Screens.TURNS] and fails on a second use.
const SAFEGUARD: StringName = &"safeguard"

## `BattleCommand_PerishSong`: the song both sides hear, whoever sang it. Fails
## only when both are already counting down.
const PERISH_SONG: StringName = &"perishsong"

## A doll in front of the user, the three residuals `ResidualDamage` charges, the
## hazard `SpikesDamage` charges, and the one command that clears any of them.
## Each handler below owns its own rules.
const SUBSTITUTE: StringName = &"substitute"
const LEECH_SEED: StringName = &"leechseed"
const NIGHTMARE: StringName = &"nightmare"
const CURSE: StringName = &"curse"
const SPIKES: StringName = &"spikes"
const CLEAR_HAZARDS: StringName = &"clearhazards"

## Protect, Endure and Destiny Bond. The first two are one routine and one
## counter, told apart only by the flag they set: `BattleCommand_Endure` is
## `call ProtectChance / ret c` and nothing else.
const PROTECT: StringName = &"protect"
const ENDURE: StringName = &"endure"
const DESTINY_BOND: StringName = &"destinybond"

## Whirlwind and Roar, which switch the side opposite whoever used them.
const FORCE_SWITCH: StringName = &"forceswitch"

## Baton Pass, which switches the side that used it and hands everything over.
const BATON_PASS: StringName = &"batonpass"

## Teleport, which takes its own user out of a wild battle and ends it as a draw.
const TELEPORT: StringName = &"teleport"

## Foresight and Lock On, the two flags one side leaves on the other for the
## accuracy step to read. Neither is spent by the move that set it: Foresight's
## lasts until a switch and Lock On's is spent by the next hit check against it.
const FORESIGHT: StringName = &"foresight"
const LOCK_ON: StringName = &"lockon"

## Spite, which takes two to five PP off the slot holding the target's last move.
const SPITE: StringName = &"spite"

## Pain Split, which writes the average of the two Pokémon's health into both.
const PAIN_SPLIT: StringName = &"painsplit"

## Thief, which moves the target's held item onto a thief carrying none.
const THIEF: StringName = &"thief"

## Pursuit, which doubles the finished figure against a side that is leaving.
const PURSUIT: StringName = &"pursuit"

## Beat Up, whose own body is the `startloop`/`endloop` pair around one hit per
## party member, as [constant MULTI_HIT]'s is around one hit per roll.
const BEAT_UP: StringName = &"beatup"

## `BattleCommand_CheckSafeguard`, the loud half of Safeguard. The four status
## moves that carry it end on `SafeguardProtectText`; the six secondary effects
## that reach `SafeCheckSafeguard` instead are refused with nothing said, which
## is why that is a check inside each of them rather than a step of its own.
const CHECK_SAFEGUARD: StringName = &"checksafeguard"

## Recover, Softboiled, Milk Drink and Rest, and separately the three heals that
## read the clock. Both refuse at full HP, and both spend the turn doing it.
const HEAL: StringName = &"heal"
const TIMED_HEAL: StringName = &"timedheal"

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

## The move's own animation, and the damage flash `BattleAnimRunScript` chains
## off `wBattleAfterAnim` behind it.
##
## `BattleCommand_MoveAnim` is `lowersub`, `moveanimnosub`, `raisesub`. Both subs
## only drop and restore the doll's picture, which this project does not draw, so
## the two names are one command here.
const MOVE_ANIM: StringName = &"moveanim"
const MOVE_ANIM_NO_SUB: StringName = &"moveanimnosub"

## The animation a stat move plays, between the change and its message.
## `BattleCommand_StatUpAnim` uses one animation for both sides;
## `..._StatDownAnim` picks `ANIM_ENEMY_STAT_DOWN` on the player's turn and
## `ANIM_WOBBLE` on the enemy's. Neither is skipped by a change that failed:
## `RaiseStat` sets `wFailedMessage`, not `wAttackMissed`, so a stat already at
## its ceiling animates and then says it will not go higher.
const STAT_UP_ANIM: StringName = &"statupanim"
const STAT_DOWN_ANIM: StringName = &"statdownanim"

## The five effects `BattleCommand_MoveAnimNoSub` alternates `wBattleAnimParam`
## for instead of clearing it. Conversion and Triple Kick are named for the
## record and are not written, so no move reaches those two.
const ALTERNATING_ANIM_EFFECTS: Array[int] = [
	Gen2MoveEffect.MULTI_HIT, Gen2MoveEffect.DOUBLE_HIT, Gen2MoveEffect.TWINEEDLE,
]

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

## `.Multipliers`, the four fractions a time-based heal indexes, in its own
## order. The fourth row is the whole bar and is [method _heal_fraction]'s
## fallthrough, so it needs no name of its own.
const HEAL_EIGHTH: int = 0
const HEAL_QUARTER: int = 1
const HEAL_HALF: int = 2

## The time of day each of the three asks for: `MORN_F`, `DAY_F` and `NITE_F`,
## the three labels `BattleCommand_TimeBasedHealContinue` is entered at.
const HEAL_TIMES: Dictionary = {
	Gen2MoveEffect.MORNING_SUN: Gen2WorldPalette.TIME_MORNING,
	Gen2MoveEffect.SYNTHESIS: Gen2WorldPalette.TIME_DAY,
	Gen2MoveEffect.MOONLIGHT: Gen2WorldPalette.TIME_NIGHT,
}

## The two moves a frozen Pokémon can use, which thaw it in the using. Flame
## Wheel and Sacred Fire, by move number.
const THAWING_MOVES: Array = [172, 221]

## The moves a sleeping Pokémon can use, `.fast_asleep`'s own two by number:
## Snore and Sleep Talk. Sleep Talk has no effect list yet, and is named here
## anyway because the bypass is the sleep check's rule rather than the move's.
const SLEEPING_MOVES: Array = [173, 214]

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
		CRITICAL:
			_critical(turn)
		DAMAGE_STATS:
			_damage_stats(turn)
		DAMAGE_CALC:
			_damage_calc(turn)
		STAB:
			_stab(turn)
		DAMAGE_VARIATION:
			_damage_variation(turn)
		DOUBLE_DAMAGE:
			_double_damage(turn)
		HAPPINESS_POWER:
			_happiness_power(turn, false)
		FRUSTRATION_POWER:
			_happiness_power(turn, true)
		GET_MAGNITUDE:
			_get_magnitude(turn)
		HIDDEN_POWER:
			_hidden_power(turn)
		PRESENT:
			_present(turn)
		FURY_CUTTER:
			_fury_cutter(turn)
		TRIPLE_KICK:
			_triple_kick(turn)
		KICK_COUNTER:
			_kick_counter(turn)
		FALSE_SWIPE:
			_false_swipe(turn)
		RESET_TYPE_MATCHUP:
			_reset_type_matchup(turn)
		HEAL_BELL:
			_heal_bell(turn)
		SNORE:
			_snore(turn)
		TRI_STATUS_CHANCE:
			_tri_status_chance(turn)
		DEFROST:
			_defrost_user(turn)
		SPLASH:
			_splash(turn)
		MIRROR_MOVE:
			_mirror_move(turn)
		MIMIC:
			_mimic(turn)
		METRONOME:
			_metronome(turn)
		SKETCH:
			_sketch(turn)
		SLEEP_TALK:
			_sleep_talk(turn)
		CONVERSION:
			_conversion(turn)
		CONVERSION_2:
			_conversion_2(turn)
		STORE_ENERGY:
			_store_energy(turn)
		UNLEASH_ENERGY:
			_unleash_energy(turn)
		RAGE:
			_rage(turn)
		RAGE_DAMAGE:
			_rage_damage(turn)
		BUILD_OPPONENT_RAGE:
			_build_opponent_rage(turn)
		CHECK_FUTURE_SIGHT:
			_check_future_sight(turn)
		FUTURE_SIGHT:
			_future_sight(turn)
		PAY_DAY:
			_pay_day(turn)
		TRANSFORM:
			_transform(turn)
		SWITCH_TURN:
			_switch_turn(turn)
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
		SCREEN:
			_screen(turn)
		SAFEGUARD:
			_safeguard(turn)
		PERISH_SONG:
			_perish_song(turn)
		SUBSTITUTE:
			_substitute(turn)
		LEECH_SEED:
			_leech_seed(turn)
		NIGHTMARE:
			_nightmare(turn)
		CURSE:
			_curse(turn)
		SPIKES:
			_spikes(turn)
		CLEAR_HAZARDS:
			_clear_hazards(turn)
		PROTECT:
			_protect(turn)
		ENDURE:
			_endure(turn)
		DESTINY_BOND:
			_destiny_bond(turn)
		FORCE_SWITCH:
			_force_switch(turn)
		BATON_PASS:
			_baton_pass(turn)
		TELEPORT:
			_teleport(turn)
		FORESIGHT:
			_foresight(turn)
		LOCK_ON:
			_lock_on(turn)
		SPITE:
			_spite(turn)
		PAIN_SPLIT:
			_pain_split(turn)
		THIEF:
			_thief(turn)
		PURSUIT:
			_pursuit(turn)
		BEAT_UP:
			_beat_up(turn)
		CHECK_SAFEGUARD:
			_check_safeguard(turn)
		HEAL:
			_heal(turn)
		TIMED_HEAL:
			_timed_heal(turn)
		THUNDER_ACCURACY:
			_thunder_accuracy(turn)
		SKIP_SUN_CHARGE:
			_skip_sun_charge(turn)
		MOVE_ANIM, MOVE_ANIM_NO_SUB:
			_move_anim(turn)
		STAT_UP_ANIM:
			_stat_change_anim(turn, Gen2BattleAnimPlayer.AFTER_ANIM_NONE)
		STAT_DOWN_ANIM:
			_stat_change_anim(
				turn,
				Gen2BattleAnimPlayer.AFTER_ANIM_ENEMY_STAT_DOWN if turn.side == Gen2Battle.PLAYER
					else Gen2BattleAnimPlayer.AFTER_ANIM_WOBBLE
			)
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
	if turn.bide_release:
		return
	# `ResetTurn` raises the temporary charging byte before entering the called
	# list. `UsedMoveText` still prints that move, but its `CheckUserIsCharging`
	# branch leaves both last-move bytes clear.
	if not turn.called:
		turn.attacker().last_move_used = turn.move_number
		turn.attacker().last_counter_move = turn.move_number
	turn.emit(Gen2Battle.USED_MOVE, {"move": turn.move_number})


## Struggle is what a Pokémon does when there is nothing left to spend, so it
## spends nothing, and it is the one move that arrives without a slot. Neither
## does the release turn of a two-turn move: the PP for it went on the charge
## turn, which is what [member Gen2Turn.locked] means here.
static func _do_turn(turn: Gen2Turn) -> void:
	if turn.locked or turn.called:
		return

	# "If we've gotten this far, this counts as a turn", ahead of the Struggle
	# check, so Struggle counts even though it spends nothing.
	turn.attacker().turns_taken += 1

	if turn.slot >= 0 and turn.move_number != Gen2Damage.STRUGGLE:
		turn.attacker().spend_pp(turn.slot)


## `engine/battle/move_effects/bide.asm`: an active Bide decrements its shared
## counter before acting. Non-final turns only say it is storing; the final one
## doubles the saturating damage word and jumps into the release half.
static func _store_energy(turn: Gen2Turn) -> void:
	var user: Gen2BattleMon = turn.attacker()
	if not Gen2Substatus.has(user.substatus, Gen2Substatus.BIDE):
		return
	user.bide_turns -= 1
	if user.bide_turns > 0:
		turn.emit(Gen2Battle.BIDE_STORING)
		turn.end()
		return
	user.substatus &= ~Gen2Substatus.BIDE
	turn.bide_release = true
	turn.damage = mini(user.bide_damage * 2, 0xFFFF)
	user.bide_damage = 0
	turn.emit(Gen2Battle.BIDE_UNLEASHED)
	if turn.damage == 0:
		turn.emit(Gen2Battle.MOVE_FAILED)
		turn.end()


## Starts Bide for two or three turns, using the same low-bit roll as the
## cartridge. The release path has already been prepared by StoreEnergy.
static func _unleash_energy(turn: Gen2Turn) -> void:
	if turn.bide_release:
		return
	var user: Gen2BattleMon = turn.attacker()
	user.substatus |= Gen2Substatus.BIDE
	user.bide_damage = 0
	user.bide_turns = turn.rng().randi_range(0, 1) + 2
	user.bide_move = turn.move_number
	turn.end()


static func _rage(turn: Gen2Turn) -> void:
	turn.attacker().substatus |= Gen2Substatus.RAGE


## `BattleCommand_RageDamage`: repeat-add the original damage once per counter,
## saturating on overflow. Zero is the ordinary one-times hit.
static func _rage_damage(turn: Gen2Turn) -> void:
	var base: int = turn.damage
	turn.damage = mini(base * (turn.attacker().rage_count + 1), 0xFFFF)


## Ordinary damage builds Rage in `_apply_damage`, where every damaging effect
## passes. This command remains in source-shaped lists as that shared seam.
static func _build_opponent_rage(_turn: Gen2Turn) -> void:
	pass


static func _check_future_sight(turn: Gen2Turn) -> void:
	if turn.battle.future_sight_pending(turn.side):
		turn.emit(Gen2Battle.MOVE_FAILED)
		turn.end()


## Stores damage after DamageCalc and before DamageVariation, exactly where the
## source copies `wCurDamage` into the side's delayed word.
static func _future_sight(turn: Gen2Turn) -> void:
	if not turn.battle.schedule_future_sight(turn.side, turn.damage):
		turn.emit(Gen2Battle.MOVE_FAILED)
	else:
		turn.emit(Gen2Battle.FUTURE_SIGHT_SET, {"target": turn.target})
	turn.end()


static func _pay_day(turn: Gen2Turn) -> void:
	turn.battle.pay_day_money = mini(
		turn.battle.pay_day_money + turn.attacker().level * 2, 0xFFFFFF
	)
	turn.emit(Gen2Battle.COINS_SCATTERED, {"amount": turn.attacker().level * 2})


## Copies the active opponent's species, moves, DVs, five combat stats, stages
## and types. HP, level, status, item and experience remain the user's.
static func _transform(turn: Gen2Turn) -> void:
	turn.attacker().last_move_used = 0 # ClearLastMove opens the source routine.
	turn.attacker().last_counter_move = 0
	if not turn.attacker().transform_into(turn.defender()):
		turn.emit(Gen2Battle.MOVE_FAILED)
		turn.end()
		return
	turn.emit(Gen2Battle.TRANSFORMED, {
		"species": turn.attacker().species, "target": turn.target,
	})


## `BattleCommand_Critical`: whether this hit is a critical, at the level the
## move, Focus Energy and a Scope Lens add up to. A move with no power never
## rolls, which is the routine's own `and a / ret z` on the power byte.
static func _critical(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	turn.critical = Gen2Damage.roll_critical(
		turn.effective_move(), turn.rng(),
		Gen2Substatus.has(attacker.substatus, Gen2Substatus.FOCUS_ENERGY),
		Gen2HeldItem.effect_of(turn.data(), attacker.item) == Gen2HeldItem.CRITICAL_UP
	)


## `BattleCommand_DamageStats`: the two stats, truncated, left on the turn for
## [method _damage_calc] to divide with.
static func _damage_stats(turn: Gen2Turn) -> void:
	var stats: Array = Gen2Damage.damage_stats(
		turn.attacker(), turn.defender(),
		int(turn.effective_move().get("type", RomLayout.TYPE_NORMAL)),
		turn.critical, turn.battle.screens[turn.target]
	)
	turn.attack_stat = int(stats[0])
	turn.defense_stat = int(stats[1])


## `BattleCommand_DamageCalc`: the formula over those two stats, the item, the
## critical multiplier, the cap and the minimum.
static func _damage_calc(turn: Gen2Turn) -> void:
	var effective: Dictionary = turn.effective_move()
	turn.damage = Gen2Damage.damage_calc(
		turn.attacker(), int(effective.get("power", 0)),
		turn.attack_stat, turn.defense_stat,
		turn.effect() == Gen2MoveEffect.SELFDESTRUCT,
		int(effective.get("type", RomLayout.TYPE_NORMAL)), turn.critical,
		turn.level_override
	)


## `BattleCommand_Stab`: the weather, the same-type bonus and the matchup. The
## step that answers whether the target is immune, which is why a status move
## with no `damagecalc` in its list still carries this one.
static func _stab(turn: Gen2Turn) -> void:
	var result: Dictionary = Gen2Damage.stab_damage(
		turn.attacker(), turn.defender(), turn.effective_move(), turn.damage,
		turn.battle.weather,
		Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.IDENTIFIED)
	)
	turn.damage = int(result["damage"])
	turn.effectiveness = int(result["effectiveness"])
	turn.immune = bool(result["immune"])


## `BattleCommand_DamageVariation`: the 85% to 100% spread, last.
##
## Nothing below two is touched and, because the routine returns before
## `BattleRandom`, nothing below two draws either, so a move that worked out to
## nothing moves no generator.
static func _damage_variation(turn: Gen2Turn) -> void:
	if turn.damage < Gen2Damage.MIN_DAMAGE:
		return
	turn.damage = Gen2Damage.apply_variation(
		turn.damage, Gen2Damage.roll_variation(turn.rng())
	)


## `BattleCommand_DoubleFlyingDamage`, `..._DoubleUndergroundDamage` and
## `..._DoubleMinimizeDamage`, which are one `DoubleDamage` under three gates and
## sit after the spread rather than before it.
static func _double_damage(turn: Gen2Turn) -> void:
	if _doubles_flying_damage(turn) or _doubles_underground_damage(turn) \
		or _doubles_minimize_damage(turn):
		turn.damage = mini(turn.damage * 2, 0xFFFF)


## `BattleCommand_HappinessPower` and `..._FrustrationPower`, one handler because
## the two routines differ only in reading the happiness or 255 minus it.
static func _happiness_power(turn: Gen2Turn, inverted: bool) -> void:
	turn.power_override = Gen2Damage.happiness_power(
		turn.attacker().happiness, inverted
	)


## `BattleCommand_GetMagnitude`: one roll picks the power and the number said out
## loud, and the line is printed before the hit rather than after it.
static func _get_magnitude(turn: Gen2Turn) -> void:
	var row: Array = Gen2Damage.magnitude_row(turn.rng().randi_range(0, 255))
	turn.power_override = int(row[1])
	turn.emit(Gen2Battle.MAGNITUDE, {"magnitude": int(row[2])})


## `BattleCommand_HiddenPower`, which is `HiddenPowerDamage`: the user's DVs give
## the move both its type and its power, and the routine runs `damagestats` off
## the new type itself, which is why Hidden Power's list carries none.
static func _hidden_power(turn: Gen2Turn) -> void:
	if turn.missed:
		return
	var resolved: Dictionary = Gen2Damage.hidden_power(turn.attacker().dvs)
	turn.type_override = int(resolved["type"])
	turn.power_override = int(resolved["power"])
	_damage_stats(turn)


## `BattleCommand_Present`: three power rows and a fourth that heals the target a
## quarter of its own maximum instead of hitting it.
##
## The failure checks come first and are the matchup and the accuracy roll, both
## of which the command asks itself because `present` sits where `damagecalc`
## would and its list carries no `failuretext` before `applydamage`. The heal is
## the target's, not the user's: the source switches turn, measures the target's
## maximum, switches back and calls `RestoreHP`, which reads the side opposite
## whoever is acting, so the two switches land it on the target either way round.
static func _present(turn: Gen2Turn) -> void:
	var matchup: Dictionary = Gen2Damage.stab_damage(
		turn.attacker(), turn.defender(), turn.effective_move(), 0
	)
	if bool(matchup["immune"]) or turn.missed:
		turn.immune = bool(matchup["immune"])
		turn.emit(Gen2Battle.MOVE_FAILED)
		turn.end()
		return

	var power: int = Gen2Damage.present_power(turn.rng().randi_range(0, 255))
	if power >= 0:
		turn.power_override = power
		return

	_animate_current_move(turn)
	var target: Gen2BattleMon = turn.defender()
	if target.hp >= target.max_hp():
		turn.emit(Gen2Battle.PRESENT_REFUSED, {"target": turn.target})
		turn.end()
		return

	# Switched around the heal the way the source is, so `RegainedHealthText`'s
	# `<USER>` is the Pokémon that got the present rather than the one that gave
	# it.
	_switch_turn(turn)
	@warning_ignore("integer_division")
	var restored: int = target.heal(maxi(target.max_hp() / 4, 1))
	turn.emit(Gen2Battle.HP_RESTORED, {
		"amount": restored, "hp": target.hp, "max_hp": target.max_hp(),
	})
	_switch_turn(turn)
	turn.end()


## `BattleCommand_FuryCutter`: the damage doubled once per consecutive hit,
## capped at five turns' worth, and the count reset by a miss.
##
## Sits between `stab` and `damagevariation`, so the doubling lands on the
## matched-up damage and the spread is taken from the doubled figure.
static func _fury_cutter(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if turn.missed:
		mon.fury_cutter_count = 0
		return

	mon.fury_cutter_count += 1
	for _step: int in mini(mon.fury_cutter_count, FURY_CUTTER_MAX_COUNT) - 1:
		turn.damage = mini(turn.damage * 2, 0xFFFF)


## The cap `cp 6 / ld b, 5` puts on the doubling, which is sixteen times the
## first kick's damage and no more.
const FURY_CUTTER_MAX_COUNT: int = 5


## `BattleCommand_TripleKick`: the second kick is worth twice the first and the
## third three times it, by adding the first kick's damage back on rather than by
## multiplying, which is why the count is the animation parameter's.
static func _triple_kick(turn: Gen2Turn) -> void:
	var base: int = turn.damage
	for _step: int in turn.battle.battle_anim_param:
		turn.damage = mini(turn.damage + base, 0xFFFF)


## `BattleCommand_KickCounter`, the other half: one more kick counted.
static func _kick_counter(turn: Gen2Turn) -> void:
	turn.battle.battle_anim_param += 1


## `BattleCommand_FalseSwipe`: the hit is cut down to one less than what the
## target has left, so it always survives.
##
## The source's other half, clearing `wCriticalHit` when it holds 2, is
## unreachable: only `BattleCommand_OHKO` ever writes that value and False Swipe
## is not an OHKO move.
static func _false_swipe(turn: Gen2Turn) -> void:
	var target: Gen2BattleMon = turn.defender()
	if turn.damage < target.hp:
		return
	turn.damage = maxi(target.hp - 1, 0)


## `BattleCommand_ResetTypeMatchup`: the constant-damage moves' own immunity
## check, and the reason their lists carry no `stab`.
##
## An immune target reads as a miss here rather than as its own kind of failure,
## which is `ResetDamage` plus `wAttackMissed`. Otherwise the matchup is flattened
## to neutral, since a fixed number was never multiplied by one and announcing an
## effectiveness for it would be a lie.
static func _reset_type_matchup(turn: Gen2Turn) -> void:
	var matchup: Dictionary = Gen2Damage.stab_damage(
		turn.attacker(), turn.defender(), turn.effective_move(), 0
	)
	if bool(matchup["immune"]):
		turn.damage = 0
		turn.missed = true
		turn.immune = true
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		turn.end()
		return
	turn.effectiveness = RomLayout.MATCHUP_EFFECTIVE


## `BattleCommand_HealBell`: every Pokémon in the user's party loses its status,
## the one on the field included.
##
## The source writes a zero over all six party status bytes whether or not there
## is a Pokémon in the slot, so a shorter party here is the same thing. Its
## trailing `CalcPlayerStats`/`CalcEnemyStats` has no counterpart, because a burn
## and a paralysis are applied when a stat is read ([method Gen2BattleMon.stat])
## rather than baked into a copy that would need rebuilding. Its
## `res SUBSTATUS_NIGHTMARE` has none either, since no move here gives one.
static func _heal_bell(turn: Gen2Turn) -> void:
	for mon: Gen2BattleMon in turn.battle.party(turn.side).mons:
		if mon == null:
			continue
		mon.status = Gen2Status.NONE
		mon.toxic_counter = 0
	_animate_current_move(turn)
	turn.emit(Gen2Battle.BELL_CHIMED)


## `BattleCommand_Snore`: the move fails outright unless its user is asleep,
## which is the only way it is ever used.
static func _snore(turn: Gen2Turn) -> void:
	if Gen2Status.is_asleep(turn.attacker().status):
		return
	turn.damage = 0
	turn.missed = true
	turn.emit(Gen2Battle.MOVE_FAILED)
	turn.end()


## `BattleCommand_TriStatusChance`: one of paralysis, freeze and burn, each a
## third of the time.
##
## The pick is the high nibble of a rolled byte masked to two bits, rerolled
## while it is zero, so three of the four values are used and the fourth costs
## another roll rather than biasing the three.
static func _tri_status_chance(turn: Gen2Turn) -> void:
	if turn.failed_chance:
		return
	var pick: int = 0
	while pick == 0:
		pick = (turn.rng().randi_range(0, 255) >> 4) & 0b11
	match pick:
		1:
			_status_target(turn, Gen2Status.PARALYSIS)
		2:
			_status_target(turn, Gen2Status.FREEZE)
		_:
			_status_target(turn, Gen2Status.BURN)


## `BattleCommand_Defrost`: Flame Wheel and Sacred Fire thaw whoever used them.
##
## The user, not the target, which is what tells this apart from the `Defrost`
## subroutine [method _defrost] is. It clears the freeze bit rather than the
## whole status byte, which comes to the same thing while a freeze is the only
## status a Pokémon can be under.
static func _defrost_user(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if not Gen2Status.has(mon.status, Gen2Status.FREEZE):
		return
	mon.status &= ~Gen2Status.FREEZE
	turn.emit(Gen2Battle.THAWED)


## `BattleCommand_Splash`, which is `AnimateCurrentMove` and
## `PrintNothingHappened`.
static func _splash(turn: Gen2Turn) -> void:
	_animate_current_move(turn)
	turn.emit(Gen2Battle.NOTHING_HAPPENED)


## `ClearLastMove`, shared by the called- and copied-move commands. The source
## clears both of the user's last-move bytes before it decides whether the call
## can succeed, so a failed call clears the remembered move too.
static func _clear_last_move_for_call(turn: Gen2Turn) -> void:
	turn.attacker().last_move_used = 0
	turn.attacker().last_counter_move = 0


static func _fail_called_move(turn: Gen2Turn) -> void:
	turn.emit(Gen2Battle.MOVE_FAILED)
	turn.end()


## `BattleCommand_MirrorMove`: copy the opponent's last counter move, unless it
## is empty or already appears in the user's own set. The latter is the source's
## perhaps-surprising `CheckUserMove / jr nz, .use` branch.
static func _mirror_move(turn: Gen2Turn) -> void:
	_clear_last_move_for_call(turn)
	var copied: int = turn.defender().last_counter_move
	if copied == 0 or turn.attacker().moves.has(copied) \
		or turn.data().move(copied).is_empty():
		_fail_called_move(turn)
		return
	turn.called_move_number = copied


## `BattleCommand_Mimic`: replace the Mimic slot in the active battle struct,
## give the copy five PP, and leave the party move untouched. A switch restores
## the original through [method Gen2BattleMon.reset_volatile].
static func _mimic(turn: Gen2Turn) -> void:
	_clear_last_move_for_call(turn)
	var copied: int = turn.defender().last_counter_move
	var slot: int = turn.attacker().moves.find(Gen2MoveEffect.MIMIC_MOVE)
	if copied == 0 or copied == Gen2Damage.STRUGGLE or slot < 0 \
		or turn.attacker().moves.has(copied) or turn.data().move(copied).is_empty():
		_fail_called_move(turn)
		return
	if not turn.attacker().mimic_move(slot, copied):
		_fail_called_move(turn)
		return
	_animate_current_move(turn)
	turn.emit(Gen2Battle.MIMIC_LEARNED, {"move": copied, "slot": slot})


## `BattleCommand_Metronome`: byte rejection over the cartridge's 251 moves,
## then the exact exception table and the user's own set. The real table always
## leaves candidates; the guard only keeps a malformed modded cache from
## spinning forever.
static func _metronome(turn: Gen2Turn) -> void:
	_clear_last_move_for_call(turn)
	_animate_current_move(turn)
	for _attempt: int in 4096:
		var picked: int = turn.rng().randi_range(0, 255)
		if picked <= 0 or picked > RomLayout.MOVE_COUNT:
			continue
		if METRONOME_EXCEPTS.has(picked) or turn.attacker().moves.has(picked):
			continue
		if turn.data().move(picked).is_empty():
			continue
		turn.called_move_number = picked
		return
	_fail_called_move(turn)


## `BattleCommand_SleepTalk`: while still asleep, sample one of the four move
## slots by the low two bits of a random byte. Empty slots, Sleep Talk itself,
## the disabled move and the six two-turn effects are resampled. PP is not read:
## the cartridge can call a move whose own PP is empty.
static func _sleep_talk(turn: Gen2Turn) -> void:
	_clear_last_move_for_call(turn)
	var attacker: Gen2BattleMon = turn.attacker()
	if not Gen2Status.is_asleep(attacker.status):
		_fail_called_move(turn)
		return

	var disabled_move: int = 0
	if attacker.disabled_slot >= 0 and attacker.disabled_slot < attacker.moves.size():
		disabled_move = int(attacker.moves[attacker.disabled_slot])
	var candidates: Array[int] = []
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if slot >= attacker.moves.size():
			break
		var number: int = int(attacker.moves[slot])
		if number == 0:
			break
		var move: Dictionary = turn.data().move(number)
		if number == turn.move_number or number == disabled_move or move.is_empty():
			continue
		if SLEEP_TALK_EXCLUDED_EFFECTS.has(int(move.get("effect", -1))):
			continue
		candidates.append(number)
	if candidates.is_empty():
		_fail_called_move(turn)
		return

	_animate_current_move(turn)
	for _attempt: int in 4096:
		var slot: int = turn.rng().randi_range(0, 255) & 0b11
		if slot >= attacker.moves.size():
			continue
		var picked: int = int(attacker.moves[slot])
		if candidates.has(picked):
			turn.called_move_number = picked
			return
	_fail_called_move(turn)


## `BattleCommand_Sketch`: the same last-move validation as Mimic, plus the
## target's Substitute refusal, then a permanent replacement carrying the
## copied move's base PP. Link battles and Transform have no runtime model yet;
## neither can reach this command in the current engine.
static func _sketch(turn: Gen2Turn) -> void:
	_clear_last_move_for_call(turn)
	var copied: int = turn.defender().last_counter_move
	var slot: int = turn.attacker().moves.find(Gen2MoveEffect.SKETCH_MOVE)
	if _substitute_refuses(turn) or copied == 0 or copied == Gen2Damage.STRUGGLE \
		or slot < 0 or turn.attacker().moves.has(copied) \
		or turn.data().move(copied).is_empty():
		_fail_called_move(turn)
		return
	if not turn.attacker().replace_move(slot, copied):
		_fail_called_move(turn)
		return
	_animate_current_move(turn)
	turn.emit(Gen2Battle.SKETCHED_MOVE, {"move": copied, "slot": slot})


## `BattleCommand_Conversion`: collect the type byte of each move the user
## knows, then sample a slot until it differs from both current types and is not
## CURSE_TYPE. Duplicate move types remain duplicate entries, preserving the
## source's slot-weighted roll.
static func _conversion(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var current: Array = attacker.types()
	var move_types: Array[int] = []
	for slot: int in Gen2BattleMon.MAX_MOVES:
		if slot >= attacker.moves.size() or int(attacker.moves[slot]) == 0:
			break
		var move: Dictionary = turn.data().move(int(attacker.moves[slot]))
		if move.is_empty():
			break
		move_types.append(int(move.get("type", RomLayout.TYPE_NORMAL)))
	var has_candidate: bool = false
	for move_type: int in move_types:
		if move_type != CURSE_TYPE and not current.has(move_type):
			has_candidate = true
			break
	if not has_candidate:
		_fail_called_move(turn)
		return
	for _attempt: int in 4096:
		var slot: int = turn.rng().randi_range(0, 255) & 0b11
		if slot >= move_types.size():
			continue
		var picked: int = move_types[slot]
		if picked == CURSE_TYPE or current.has(picked):
			continue
		attacker.set_battle_type(picked)
		_animate_current_move(turn)
		turn.emit(Gen2Battle.TYPE_CHANGED, {"type_number": picked})
		return
	_fail_called_move(turn)


## `BattleCommand_Conversion2`: read the opponent's last move type, then sample
## the cartridge's disjoint type-number runs until one resists or ignores it.
## Both active type bytes become the answer.
static func _conversion_2(turn: Gen2Turn) -> void:
	var last_move: int = turn.defender().last_counter_move
	var move: Dictionary = turn.data().move(last_move)
	if last_move == 0 or move.is_empty():
		_fail_called_move(turn)
		return
	var attacking_type: int = int(move.get("type", CURSE_TYPE))
	if attacking_type == CURSE_TYPE:
		_fail_called_move(turn)
		return
	_animate_current_move(turn)
	for _attempt: int in 4096:
		var picked: int = turn.rng().randi_range(0, 255) & 0x1F
		if not CONVERSION_2_TYPES.has(picked):
			continue
		if turn.data().type_effectiveness(attacking_type, [picked, picked]) \
			>= RomLayout.MATCHUP_EFFECTIVE:
			continue
		turn.attacker().set_battle_type(picked)
		turn.emit(Gen2Battle.TYPE_CHANGED, {"type_number": picked})
		return
	_fail_called_move(turn)


## `BattleCommand_SwitchTurn`: the commands between two of these act with the
## sides the other way round.
static func _switch_turn(turn: Gen2Turn) -> void:
	var was: int = turn.side
	turn.side = turn.target
	turn.target = was


## `CheckSubstituteOpp`: whether the Pokémon opposite whoever is acting is
## standing behind a doll. Eighteen commands ask it and every one of them refuses
## on a yes.
static func _substitute_refuses(turn: Gen2Turn) -> bool:
	return Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.SUBSTITUTE)


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
		if not CONTINUES_AFTER_MISS.has(turn.effect()):
			turn.end()
		return

	# `.DreamEater`, first.
	if turn.effect() == Gen2MoveEffect.DREAM_EATER \
		and not Gen2Status.is_asleep(turn.defender().status):
		turn.missed = true
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		if not CONTINUES_AFTER_MISS.has(turn.effect()):
			turn.end()
		return

	# `.Protect`, second, and ahead of everything but the Dream Eater question.
	# One gate for the whole game: 47 of the lists here carry `checkhit`, so a
	# Protect turns away a damaging move, a status move and a stat drop alike
	# without any of them knowing about it. Ahead of `.LockOn`, so a Protect
	# turns a locked-on move away *and* leaves the flag standing for the next one.
	if Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.PROTECT):
		turn.missed = true
		turn.emit(Gen2Battle.PROTECTING_ITSELF, {"target": turn.target})
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		_jump_kick_crash(turn)
		if not CONTINUES_AFTER_MISS.has(turn.effect()):
			turn.end()
		return

	# `.DrainSub`, third: nothing can be drained out of a doll, so the two effects
	# that heal off what they deal read as a miss rather than as a hit that heals
	# nothing. Every other move goes through the doll normally.
	if _substitute_refuses(turn) and turn.effect() in DRAINING_EFFECTS:
		turn.missed = true
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		if not CONTINUES_AFTER_MISS.has(turn.effect()):
			turn.end()
		return

	# `.LockOn`, fourth. The flag is spent on every hit check whether it was set or
	# not, which is `res SUBSTATUS_LOCK_ON, [hl]` sitting in front of `ret z`, and
	# it is the target's flag rather than the aimer's.
	#
	# A locked-on target that is flying is still missed by the three moves that
	# only reach a target underground. `CheckHiddenOpponent` has no such list,
	# which is `docs/bugs_and_glitches.md`'s "Lock-On and Mind Reader don't always
	# bypass Fly and Dig": mirrored, not fixed.
	var aimed_at: Gen2BattleMon = turn.defender()
	var locked_on: bool = Gen2Substatus.has(aimed_at.substatus, Gen2Substatus.LOCK_ON)
	aimed_at.substatus &= ~Gen2Substatus.LOCK_ON
	if locked_on and not (
		Gen2Substatus.has(aimed_at.substatus, Gen2Substatus.FLYING)
		and LOCK_ON_GROUND_MOVES.has(turn.move_number)
	):
		return

	# `.FlyDigMoves`, fifth, and behind the lock-on question for that reason.
	if _is_hidden(turn.defender().substatus) \
		and not _can_hit_hidden(turn.move_number, turn.defender().substatus):
		turn.missed = true
		turn.emit(Gen2Battle.MISSED, {"target": turn.target})
		_jump_kick_crash(turn)
		if not CONTINUES_AFTER_MISS.has(turn.effect()):
			turn.end()
		return

	# `.ThunderRain`, ahead of the stat modifiers and the roll: Thunder never
	# misses in rain, whatever either side's accuracy and evasion say.
	if turn.effect() == Gen2MoveEffect.THUNDER \
		and turn.battle.weather == Gen2Weather.RAIN:
		return

	# `.XAccuracy`, immediately after it: an X Accuracy makes everything the
	# holder throws land, for the rest of the time it is out.
	if Gen2Substatus.has(turn.attacker().substatus, Gen2Substatus.X_ACCURACY):
		return

	# The perfect-accuracy check, last before the stat modifiers. Swift, Faint
	# Attack and Vital Throw all carry `NormalHit`'s ordinary list and a stored
	# accuracy of 100; this one comparison is the whole of what makes them never
	# miss, so it is here rather than in a list of their own.
	if turn.effect() == Gen2MoveEffect.ALWAYS_HIT:
		return

	# `.StatModifiers`, whose Foresight branch returns before it multiplies
	# anything: an identified target whose evasion is at least the attacker's
	# accuracy has the whole stage block skipped, and the stored byte stands.
	var chance: int = Gen2Accuracy.chance(
		turn.accuracy if turn.accuracy >= 0 \
			else int(turn.move.get("accuracy", Gen2Accuracy.ALWAYS_HITS)),
		turn.attacker().stage("accuracy"), turn.defender().stage("evasion"),
		Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.IDENTIFIED)
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
	# `.Miss` keeps the worked-out damage for Jump Kick alone, where every other
	# miss clears it, because `BattleCommand_FailureText` is about to take an
	# eighth of it off the user.
	turn.missed = true
	turn.emit(Gen2Battle.MISSED, {"target": turn.target})
	_jump_kick_crash(turn)
	if not CONTINUES_AFTER_MISS.has(turn.effect()):
		turn.end()


## The tail of `BattleCommand_FailureText`: a missed Jump Kick or Hi Jump Kick
## costs its user an eighth of the damage it would have dealt, never less than
## one.
##
## Nothing is taken when the target was immune, since the routine returns on a
## type modifier of zero, and Jump Kick's own effect byte is what gates the whole
## block: it points at `NormalHit` like any other move and this is the only place
## the two are told apart.
static func _jump_kick_crash(turn: Gen2Turn) -> void:
	if turn.effect() != Gen2MoveEffect.JUMP_KICK or turn.immune:
		return
	var attacker: Gen2BattleMon = turn.attacker()
	var crash: int = maxi(turn.damage >> 3, 1)
	var taken: int = attacker.take_damage(crash)
	turn.emit(Gen2Battle.CRASHED, {
		"amount": taken, "hp": attacker.hp, "max_hp": attacker.max_hp(),
	})


## Takes the damage off, and reports what was actually taken.
##
## `BattleCommand_ApplyDamage` rolls the defender's Focus Band before it does,
## and a band that fires calls `BattleCommand_FalseSwipe`, which is what leaves
## the Pokémon on one hit point. The roll happens whether or not the hit would
## have been lethal, and only the survival shows.
##
## The band sits in front of the substitute routing, which is the source's order
## and not a tidying opportunity: `FalseSwipe` clamps against the *real* health
## whatever is standing in front of it, so a band can fire, cut the figure down,
## and have the doll spend the cut figure with "hung on" printed anyway.
## `.update_damage_taken` then returns early against a doll, which is what stops
## Counter and Mirror Coat answering a hit it took.
static func _apply_damage(turn: Gen2Turn) -> void:
	if turn.missed or turn.damage <= 0:
		return
	var defender: Gen2BattleMon = turn.defender()

	# Ahead of `.damage`, so everything behind reads the cut figure: what Counter
	# remembers, what a drain heals off and what a recoil costs are all
	# `wCurDamage` after this.
	#
	# Endure is the front branch and the band is its `else`, which is the source's
	# `jr z, .focus_band` and not a tidying opportunity: an enduring target never
	# reaches the band's roll, so it draws no randomness there. Endure is read
	# rather than spent, so every hit of a multi-hit move is clamped.
	var enduring: bool = Gen2Substatus.has(defender.substatus, Gen2Substatus.ENDURE)
	var band: bool = not enduring \
		and Gen2HeldItem.effect_of(turn.data(), defender.item) == Gen2HeldItem.FOCUS_BAND \
		and Gen2HeldItem.rolls_under(
			turn.rng(), Gen2HeldItem.parameter_of(turn.data(), defender.item)
		)
	# `BattleCommand_FalseSwipe` reports whether it clamped, which is what decides
	# between the two lines; the test itself is the same for both.
	var clamped: bool = (enduring or band) and turn.damage >= defender.hp
	if clamped:
		turn.damage = maxi(defender.hp - 1, 0)
	var endured: bool = clamped and not enduring
	var braced: bool = clamped and enduring

	var behind_sub: bool = _substitute_refuses(turn)
	if not behind_sub:
		turn.battle.record_damage_taken(
			turn.target, turn.side, turn.move_number, turn.effect(), turn.damage
		)

	if behind_sub:
		_substitute_damage(turn)
		if braced:
			turn.emit(Gen2Battle.ENDURED_HIT, {"target": turn.target})
		if endured:
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
	if not defender.is_fainted() \
			and Gen2Substatus.has(defender.substatus, Gen2Substatus.RAGE) \
			and defender.rage_count < 0xFF:
		defender.rage_count += 1
		turn.emit(Gen2Battle.RAGE_BUILDING, {"target": turn.target})
	if braced:
		turn.emit(Gen2Battle.ENDURED_HIT, {"target": turn.target})
	if endured:
		turn.emit(Gen2Battle.ENDURED, {"target": turn.target, "item": defender.item})


## `DoSubstituteDamage`: the doll spends the hit and the Pokémon's own health is
## never touched.
##
## The damage is a sixteen-bit word against a one-byte counter, so anything from
## 256 up breaks the doll without arithmetic, and the subtraction breaks it on a
## result of exactly zero as well as on a borrow. `xor a / ld [hl], a` over the
## move's own effect byte then makes the rest of the list read as an ordinary
## attack; five effects are exempted. `ResetDamage` closes both branches, so
## nothing behind this applies the hit again.
static func _substitute_damage(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	turn.emit(Gen2Battle.SUBSTITUTE_TOOK_DAMAGE, {"target": turn.target})

	var broke: bool = turn.damage > 0xFF
	if not broke:
		# Written back before it is tested, and as the byte the cartridge leaves.
		broke = defender.substitute_hp - turn.damage <= 0
		defender.substitute_hp = (defender.substitute_hp - turn.damage) & 0xFF

	if broke:
		defender.substatus &= ~Gen2Substatus.SUBSTITUTE
		turn.emit(Gen2Battle.SUBSTITUTE_FADED, {"target": turn.target})
		if not SUBSTITUTE_KEEPS_EFFECT.has(turn.effect()):
			turn.effect_override = Gen2MoveEffect.NORMAL_HIT_EFFECT

	turn.dealt = 0
	turn.damage = 0


## The five whose own command reads the effect byte back to decide how many hits
## it is partway through. Beat Up is among them and is not written here.
const SUBSTITUTE_KEEPS_EFFECT: Array[int] = [
	Gen2MoveEffect.MULTI_HIT, Gen2MoveEffect.DOUBLE_HIT, Gen2MoveEffect.TWINEEDLE,
	Gen2MoveEffect.TRIPLE_KICK, Gen2MoveEffect.BEAT_UP,
]


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
##
## Two flags go with it, and they are on opposite sides: the user loses its own
## Leech Seed, which nothing can read off a Pokémon at zero, and the *target*
## loses its Destiny Bond (`BATTLE_VARS_SUBSTATUS5_OPP`), which is what stops an
## explosion being answered by one.
static func _selfdestruct(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	attacker.status = Gen2Status.NONE
	attacker.substatus &= ~(Gen2Substatus.CHARGING | Gen2Substatus.FLYING | Gen2Substatus.UNDERGROUND)
	attacker.substatus &= ~Gen2Substatus.LEECH_SEED
	turn.defender().substatus &= ~Gen2Substatus.DESTINY_BOND
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


## The three gates in front of `DoubleDamage`, each reading one thing about the
## target and nothing about the move: which moves ask is the list's business, and
## only Gust and Twister carry `doubleflyingdamage`, only Earthquake and
## Magnitude `doubleundergrounddamage`, only Stomp `doubleminimizedamage`.
static func _doubles_flying_damage(turn: Gen2Turn) -> bool:
	return Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.FLYING)


static func _doubles_underground_damage(turn: Gen2Turn) -> bool:
	return Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.UNDERGROUND)


static func _doubles_minimize_damage(turn: Gen2Turn) -> bool:
	return turn.defender().minimized


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
	_destiny_bond_takes_user(turn)
	for side: int in [turn.target, turn.side]:
		if turn.battle.mon(side).is_fainted():
			turn.events.append({"type": Gen2Battle.FAINTED, "side": side})
	if turn.battle.mon(turn.target).is_fainted():
		turn.end()


## The Destiny Bond half of `BattleCommand_CheckFaint`, which is the one reader
## of the flag and reads the *target's*, not the user's.
##
## The health is emptied outright rather than damaged: the source zeroes both
## bytes of `wBattleMonHP` by hand, so no held item, no Endure and no Focus Band
## stands between the bond and the attacker. Sitting in front of the loop below
## is what reports the target's faint before the attacker's, which is the order
## the source's own two `HandleMonFaint` calls take them in.
##
## A user already down asks nothing extra and is not exempted, because the source
## exempts it nowhere: `recoil` runs in front of `checkfaint` in `RecoilHit`, so a
## user that killed itself on the same hit still prints the line.
static func _destiny_bond_takes_user(turn: Gen2Turn) -> void:
	var target: Gen2BattleMon = turn.battle.mon(turn.target)
	if not target.is_fainted():
		return
	if not Gen2Substatus.has(target.substatus, Gen2Substatus.DESTINY_BOND):
		return
	turn.emit(Gen2Battle.TOOK_DOWN_WITH_IT, {"target": turn.target})
	var user: Gen2BattleMon = turn.attacker()
	user.take_damage(user.hp)


## CantMove on the cartridge cancels Bide, a pending two-turn move, Rollout or
## rampage. For Fly and Dig that also makes the user visible again, so a sleep,
## flinch or paralysis on the release turn cannot leave a Pokémon permanently
## untouchable.
static func _cancel_charge(mon: Gen2BattleMon) -> void:
	mon.substatus &= ~(Gen2Substatus.CHARGING | Gen2Substatus.FLYING | Gen2Substatus.UNDERGROUND)
	mon.charged_move = 0
	mon.substatus &= ~(Gen2Substatus.ROLLOUT | Gen2Substatus.RAMPAGING)
	mon.rampage_move = 0
	mon.rampage_turns = 0
	mon.substatus &= ~Gen2Substatus.BIDE
	mon.bide_turns = 0
	mon.bide_damage = 0
	mon.bide_move = 0


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
			# `.fast_asleep` prints its line and only then looks at the move:
			# Snore and Sleep Talk are used through a sleep, so the text stands
			# and `CantMove` is what they skip.
			if not SLEEPING_MOVES.has(turn.move_number):
				turn.end()
				return
		else:
			turn.emit(Gen2Battle.WOKE_UP)

	if Gen2Status.has(mon.status, Gen2Status.FREEZE):
		# Flame Wheel and Sacred Fire are used through a freeze; nothing else in
		# the game is. `CheckPlayerTurn` only lets the move happen and clears no
		# bit, so the thaw itself is the `defrost` step in their own list, behind
		# `applydamage`: a Flame Wheel that misses leaves its user frozen.
		if not THAWING_MOVES.has(turn.move_number):
			_cancel_charge(mon)
			turn.emit(Gen2Battle.CANNOT_MOVE, {"reason": &"freeze"})
			turn.end()
			return

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
				var dealt: int = mon.take_damage(Gen2Damage.confusion_damage(
					mon, turn.rng(), turn.battle.screens[turn.side]
				))
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
	# `xor a / ld [wEffectFailed], a` opens the routine, so a second
	# `effectchance` clears what the first decided. Only `DefenseDownHit` has two.
	turn.failed_chance = false

	# `CheckSubstituteOpp` next, jumping straight to `.failed`, so a secondary
	# effect aimed at a doll draws no roll at all.
	if _substitute_refuses(turn):
		turn.failed_chance = true
		return

	var chance: int = int(turn.move.get("effect_chance", 0))
	if turn.rng().randi_range(0, Gen2Status.CHANCE_RANGE - 1) >= chance:
		turn.failed_chance = true


## Puts a status on the defender, or fails.
##
## One status at a time: a Pokémon that already has something on its byte is
## refused rather than added to, and so is one whose type makes it immune. A
## sleep is rolled for how long it lasts; the rest are a flag.
##
## The checks are in the four `*Target` commands' own order, which every one of
## them shares: the target's existing status, the weather, its type, and only
## then `wEffectFailed`. Ordering `wEffectFailed` last is not cosmetic, because
## the first step is the one that does something besides refuse: a burn whose
## roll failed still reaches `Defrost`.
static func _status_target(turn: Gen2Turn, flag: int) -> void:
	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted():
		return

	# The four secondary `*Target` commands open on `CheckSubstituteOpp`, ahead of
	# the status check, so a doll stops even the thaw a burn would have given. The
	# three primary commands ask after theirs. Everything between the two
	# positions is a refusal that says nothing here, so `Defrost` is the only
	# place the split shows.
	var primary: bool = _status_move_animates(turn, flag)
	if not primary and _substitute_refuses(turn):
		return

	if Gen2Status.is_afflicted(defender.status):
		# `BattleCommand_BurnTarget` is the one that does not simply return here:
		# its `jp nz, Defrost` thaws a frozen target instead.
		if flag == Gen2Status.BURN:
			_defrost(turn, defender)
		return

	# `BattleCommand_FreezeTarget` refuses outright in sun. It is the only one of
	# the five statuses the weather has anything to say about.
	if flag == Gen2Status.FREEZE and turn.battle.weather == Gen2Weather.SUN:
		return

	if _status_type_refuses(turn, flag):
		return

	if primary and _substitute_refuses(turn):
		return

	if turn.failed_chance:
		return

	# `SafeCheckSafeguard`, last of the four `*Target` commands' checks and behind
	# `wEffectFailed`. Nothing is said: a Safeguard stops a secondary status the
	# way a held item does, and only `BattleCommand_CheckSafeguard` speaks.
	if _safeguard_refuses(turn, turn.target):
		return

	if _status_move_animates(turn, flag):
		_animate_current_move(turn)

	if flag == Gen2Status.SLEEP_MASK:
		defender.status = Gen2Status.roll_sleep(turn.rng())
	else:
		defender.status |= flag

	# The status is on before the animation plays, which is the order all four
	# `*Target` commands use: the status bit, `UpdateOpponentInParty` and any
	# `Apply*Effect` call, then `PlayOpponentBattleAnim`, then `RefreshBattleHuds`
	# and the text.
	var opponent_anim: int = _status_target_anim(turn, flag)
	if opponent_anim >= 0:
		_play_opponent_battle_anim(turn, opponent_anim)

	turn.emit(Gen2Battle.STATUS_INFLICTED, {
		"target": turn.target,
		"status": defender.status,
		"name": Gen2Status.name_of(defender.status),
	})

	# Every status-inflicting command calls `UseHeldStatusHealingItem` on the
	# Pokémon it just afflicted, so a berry answers at once rather than waiting
	# for the end of the turn.
	turn.battle.use_status_berry(turn.target, turn.events)

	# `BattleCommand_FreezeTarget`'s own tail, and behind the berry the way the
	# source puts it behind `UseHeldStatusHealingItem`'s `ret nz`: a freeze a
	# berry has already cured never sets the flag, so it does not stop a thaw
	# that is no longer needed.
	if flag == Gen2Status.FREEZE \
		and Gen2Status.has(defender.status, Gen2Status.FREEZE):
		turn.battle.mark_just_got_frozen(turn.target)


## Whether the target's own type refuses this status, which two of the five ask
## and three do not.
##
## Poison asks `CheckIfTargetIsPoisonType`, which compares the target's two types
## against POISON itself rather than against the move's: a Poison-type is refused
## whatever poisons it. Burn and freeze ask `CheckMoveTypeMatchesTarget`, which
## compares the *move's* type against the target's two, so a Fire-type shrugs off
## a Fire-type burn and an Ice-type an Ice-type freeze. Its `.normal` branch
## returns non-zero without comparing anything, so a Normal-type move matches
## nobody and Tri Attack can burn and freeze anything.
##
## Sleep and paralysis ask neither, which is why a Ground-type is paralysed by
## Body Slam and an Electric-type by Thunder Wave: the type immunities those two
## statuses have are a later generation's.
static func _status_type_refuses(turn: Gen2Turn, flag: int) -> bool:
	var types: Array = turn.defender().types()
	if flag == Gen2Status.POISON:
		return types.has(RomLayout.TYPE_POISON)
	if flag != Gen2Status.BURN and flag != Gen2Status.FREEZE:
		return false

	var move_type: int = int(turn.move.get("type", RomLayout.TYPE_NORMAL))
	if move_type == RomLayout.TYPE_NORMAL:
		return false
	return types.has(move_type)


## `Defrost`, which `BattleCommand_BurnTarget` jumps to instead of returning when
## the target already carries a status. Only a freeze is cleared; any other
## status reaches its own `ret z` and stays.
##
## So a Fire-type move with a burn behind it thaws whoever it hits, and it does
## so before `wEffectFailed` is read, which means the burn's own roll failing
## does not stop the thaw.
static func _defrost(turn: Gen2Turn, defender: Gen2BattleMon) -> void:
	if not Gen2Status.has(defender.status, Gen2Status.FREEZE):
		return
	defender.status = Gen2Status.NONE
	turn.emit(Gen2Battle.THAWED, {"side": turn.target})


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

	# Toxic is `BattleCommand_Poison` with a different branch at the end, so it
	# passes that command's own `CheckIfTargetIsPoisonType` on the way in: a
	# Poison-type is no more badly poisoned than ordinarily poisoned.
	if _status_type_refuses(turn, Gen2Status.POISON):
		return

	# `.dont_sample_failure`, which is where that command asks about the doll:
	# behind the type and status checks rather than in front of them.
	if _substitute_refuses(turn):
		return

	# `BattleCommand_Poison`'s `.toxic` branch reaches the same `.apply_poison`,
	# so Toxic animates from inside the command and never reaches
	# `PlayOpponentBattleAnim`: no `ANIM_PSN` follows it.
	_animate_current_move(turn)
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

	# `BattleCommand_FlinchTarget` opens on `CheckSubstituteOpp`: there is nobody
	# to startle behind a doll.
	if _substitute_refuses(turn):
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

	# `BattleCommand_ConfuseTarget`'s own `SafeCheckSafeguard`, ahead of the
	# substitute and already-confused checks and silent like the four statuses'.
	if _safeguard_refuses(turn, turn.target):
		return

	# Where `..._ConfuseTarget` asks it. `..._Confuse` asks one step later, after
	# the already-confused check, and both refusals are silent, so the two orders
	# cannot be told apart here.
	if _substitute_refuses(turn):
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.is_fainted() or Gen2Substatus.has(defender.substatus, Gen2Substatus.CONFUSED):
		return

	defender.substatus |= Gen2Substatus.CONFUSED
	defender.confusion_turns = Gen2Substatus.roll_confusion(turn.rng())

	# `BattleCommand_FinishConfusingTarget`'s `.got_effect` skips the move's own
	# animation for the three effects that already played one. Only
	# `EFFECT_CONFUSE_HIT` is checked, because `EFFECT_SNORE` and
	# `EFFECT_SWAGGER` are unwritten and no move here carries either.
	if turn.effect() != Gen2MoveEffect.CONFUSE_HIT:
		_animate_current_move(turn)

	# Unconditional, and past `.got_effect`: a confusion animates on its target
	# whichever way the move reached here.
	_play_opponent_battle_anim(turn, Gen2BattleAnimPlayer.ANIM_CONFUSED)

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
				attacker, defender, turn.effective_move(), turn.rng(), focus_energy,
				false, turn.battle.weather, turn.battle.screens[turn.target],
				Gen2Substatus.has(defender.substatus, Gen2Substatus.IDENTIFIED)
			)
			turn.damage = int(result["damage"])
			turn.critical = bool(result["critical"])
			turn.effectiveness = int(result["effectiveness"])

		# `moveanimnosub` sits inside the source loop, after `clearmissdamage`
		# and before `applydamage`, so every hit animates and only the last one
		# carries the damage flash.
		_multi_hit_anim(turn, hit == hits - 1)

		# `applydamage` is inside the loop too, so each hit goes through the whole
		# of it, Focus Band and Substitute included. That is why
		# `DoSubstituteDamage` exempts this effect from stamping
		# `EFFECT_NORMAL_HIT`: the loop reads the byte back on the next pass.
		_apply_damage(turn)

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


## `BattleCommand_ConstantDamage`: the whole hit, worked out without the ordinary
## formula. [constant Gen2MoveEffect.LEVEL_DAMAGE] is the user's level,
## [constant Gen2MoveEffect.PSYWAVE] a roll of it,
## [constant Gen2MoveEffect.SUPER_FANG] half the target's current HP, and
## [constant Gen2MoveEffect.STATIC_DAMAGE] the move's power field taken directly.
## None of the four criticals or announces an effectiveness, since the number was
## never multiplied by either, and [constant RESET_TYPE_MATCHUP] behind them is
## what says so and what answers an immunity.
##
## [constant Gen2MoveEffect.REVERSAL] shares the command and not that shape: it
## sets a power and runs the formula, and its own list carries `stab` rather than
## `resettypematchup`, so Flail against a Ghost really is super effective.
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
		Gen2MoveEffect.REVERSAL:
			# `.reversal` is the one branch that does not hand back a number: it
			# picks a power off how much health is left and then runs
			# `PlayerAttackDamage` and `BattleCommand_DamageCalc` itself, so the
			# hit goes through the ordinary formula. Its list carries no
			# `critical`, so the hit is never one.
			turn.power_override = Gen2Damage.flail_reversal_power(
				attacker.hp, attacker.max_hp()
			)
			_damage_stats(turn)
			_damage_calc(turn)
		_: # STATIC_DAMAGE: Sonicboom and Dragon Rage deal exactly their own power.
			turn.damage = int(turn.move.get("power", 0))


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

	# `OHKOHit` is `ohko, moveanim, failuretext, applydamage`: this command owns
	# the roll and the damage both, so the animation sits between them here.
	_move_anim(turn)
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
	## `.UsedText` picks its line by move number rather than by effect, so the
	## move travels with the event and the screen owns the wording.
	turn.emit(Gen2Battle.CHARGING_UP, {"move": turn.move_number})
	turn.end()


## A new Rollout starts a fresh count. A continuation leaves the count alone so
## [method _damage_calc] can apply the next power before this command advances
## it after a successful hit.
static func _rollout_check(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	if not Gen2Substatus.has(mon.substatus, Gen2Substatus.ROLLOUT):
		mon.rollout_count = 0


## `BattleCommand_RolloutPower`, which is both halves of Rollout: the count and
## the doubling.
##
## It runs after `stab` and the hit check and before `damagevariation`, so the
## doubling lands on the matched-up damage and the spread is taken from the
## doubled figure. A miss, including an immunity, ends the chain. A successful
## fifth hit also clears the continuation flag, but its count is retained until
## the next Rollout starts and resets it.
##
## The count is raised before the doubling and one doubling is spent doing
## nothing, which is `inc [hl]` then `dec b / jr z`: the first hit is worth its
## own power and the fifth sixteen times it. Defense Curl adds one more.
static func _rollout_power(turn: Gen2Turn) -> void:
	var mon: Gen2BattleMon = turn.attacker()
	# Sleep Talk can call Rollout while the user remains asleep. The cartridge's
	# opening SLP_MASK check leaves both the counter and damage untouched.
	if Gen2Status.is_asleep(mon.status):
		return
	if turn.missed:
		mon.substatus &= ~Gen2Substatus.ROLLOUT
		return

	mon.rollout_count += 1
	if mon.rollout_count >= ROLLOUT_MAX_COUNT:
		mon.substatus &= ~Gen2Substatus.ROLLOUT
	else:
		mon.substatus |= Gen2Substatus.ROLLOUT

	var doublings: int = mon.rollout_count - 1
	if Gen2Substatus.has(mon.substatus, Gen2Substatus.CURLED):
		doublings += 1
	for _step: int in doublings:
		turn.damage = mini(turn.damage * 2, 0xFFFF)


## `MAX_ROLLOUT_COUNT`.
const ROLLOUT_MAX_COUNT: int = 5


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
			# `BattleCommand_Rampage` switches turn around its own
			# `SafeCheckSafeguard` and back, so the Safeguard that matters is the
			# rampaging Pokémon's own: it is the one about to be confused.
			if not _safeguard_refuses(turn, turn.side):
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
	_animate_current_move(turn)
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

	_animate_current_move(turn)
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
	_animate_current_move(turn)
	turn.emit(Gen2Battle.STAGES_COPIED)


## Locks whichever of the target's slots holds
## [member Gen2BattleMon.last_counter_move], found by searching the target's move
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

	var last_move: int = defender.last_counter_move
	if last_move == 0 or last_move == Gen2Damage.STRUGGLE:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	var slot: int = defender.moves.find(last_move)
	if slot < 0 or defender.pp_left(slot) <= 0:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	defender.disabled_slot = slot
	defender.disable_turns = Gen2Substatus.roll_disable(turn.rng())
	_animate_current_move(turn)
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
	_animate_current_move(turn)
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
	_animate_current_move(turn)
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
	_animate_current_move(turn)
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
	_animate_current_move(turn)
	turn.emit(Gen2Battle.FOCUS_ENERGY_SET)


## Binds the target for three to six turns, of which
## [method Gen2Battle._tick_wrap] spends the first without damage.
##
## `BattleCommand_TrapTarget`'s own three refusals, in its order: a missed move,
## a target that is already bound, and a target behind a Substitute. The first is
## structural here, since [method _check_hit] ends the move before this step is
## reached. All three are silent rather than a
## [constant Gen2Battle.MOVE_FAILED], because the cartridge returns without
## printing anything. The doll check sits in front of `BattleRandom`, so a bind
## aimed at one draws no roll.
static func _trap_target(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	if defender.trapped_turns > 0:
		return

	if _substitute_refuses(turn):
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
	_animate_current_move(turn)
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
	_animate_current_move(turn)
	turn.emit(Gen2Battle.WEATHER_STARTED, {"weather": weather})


## `BattleCommand_Screen`: Light Screen and Reflect, one command told apart by
## the move's own effect byte.
##
## The flag goes on the user's side, which is the side being defended, and
## survives every switch that side makes. A second use fails outright rather than
## restarting the count, the way Sandstorm does and Rain Dance does not.
static func _screen(turn: Gen2Turn) -> void:
	var flag: int = Gen2Screens.LIGHT_SCREEN \
		if turn.effect() == Gen2MoveEffect.LIGHT_SCREEN else Gen2Screens.REFLECT
	var counts: Dictionary = turn.battle.light_screen_turns \
		if flag == Gen2Screens.LIGHT_SCREEN else turn.battle.reflect_turns
	_raise_screen(turn, flag, counts)


## `BattleCommand_Safeguard`, which is [method _screen] with one bit and one
## count of its own.
static func _safeguard(turn: Gen2Turn) -> void:
	_raise_screen(turn, Gen2Screens.SAFEGUARD, turn.battle.safeguard_turns)


## The half all three share: refuse if it is already up, otherwise set the bit,
## load the count and say so.
static func _raise_screen(turn: Gen2Turn, flag: int, counts: Dictionary) -> void:
	if Gen2Screens.has(turn.battle.screens[turn.side], flag):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	turn.battle.screens[turn.side] |= flag
	counts[turn.side] = Gen2Screens.TURNS
	_animate_current_move(turn)
	turn.emit(Gen2Battle.SCREEN_SET, {"screen": flag})


## `BattleCommand_PerishSong`: four turns on the clock for both Pokémon on the
## field, whichever of them sang.
##
## The one command that names `wPlayerSubStatus1` and `wEnemySubStatus1` outright
## instead of the user and the target, so it reads the same either way round. A
## side already counting down is left with the count it has rather than given a
## fresh four, and the move fails only when that is true of both.
static func _perish_song(turn: Gen2Turn) -> void:
	var battle: Gen2Battle = turn.battle
	var already: Dictionary = {}
	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		already[side] = Gen2Substatus.has(
			battle.mon(side).substatus, Gen2Substatus.PERISH
		)
	if bool(already[Gen2Battle.PLAYER]) and bool(already[Gen2Battle.ENEMY]):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		if bool(already[side]):
			continue
		var hearer: Gen2BattleMon = battle.mon(side)
		hearer.substatus |= Gen2Substatus.PERISH
		hearer.perish_count = Gen2Substatus.PERISH_TURNS

	_animate_current_move(turn)
	turn.emit(Gen2Battle.PERISH_SONG_STARTED)


## `BattleCommand_Substitute`. Paying is exact rather than clamped, so the test is
## a borrow *or* a result of zero: a user sitting on exactly a quarter fails
## rather than making a doll and fainting. Success zeroes the user's own wrap
## counter and nothing on the other side of the field.
static func _substitute(turn: Gen2Turn) -> void:
	var user: Gen2BattleMon = turn.attacker()
	if Gen2Substatus.has(user.substatus, Gen2Substatus.SUBSTITUTE):
		turn.emit(Gen2Battle.SUBSTITUTE_ALREADY)
		return

	# Written before the affordability test, as the source writes it: a refused
	# Substitute leaves the byte set and the flag clear.
	var cost: int = Gen2Substatus.substitute_hp_for(user.max_hp())
	user.substitute_hp = cost
	if user.hp <= cost:
		turn.emit(Gen2Battle.SUBSTITUTE_TOO_WEAK)
		return

	user.hp -= cost
	user.substatus |= Gen2Substatus.SUBSTITUTE
	user.trapped_turns = 0
	user.trapping_move = 0

	# `xor a / ld [wBattleAnimParam], a` before `LoadAnim`: param 0 is the doll
	# going up, where `lowersub` and `raisesub` pass 1 and 2.
	turn.battle.battle_anim_param = 0
	_animate_current_move(turn)
	turn.emit(Gen2Battle.SUBSTITUTE_MADE, {
		"amount": cost, "hp": user.hp, "max_hp": user.max_hp(),
		"substitute_hp": user.substitute_hp,
	})


## The seed [method Gen2Battle._residual_leech_seed] reads back every turn.
##
## Refusals in the source's order: a Substitute and an already-seeded target both
## say `EvadedText`, a Grass-type says `DoesntAffectText`. The missed branch in
## front of them is structural here, since [method _check_hit] ends the move.
## Every refusal reaches `AnimateFailedMove`, which is a forty-frame wait between
## two doll calls and plays no animation, so only a seed that lands is drawn.
static func _leech_seed(turn: Gen2Turn) -> void:
	if _substitute_refuses(turn):
		turn.emit(Gen2Battle.EVADED, {"target": turn.target})
		return

	var defender: Gen2BattleMon = turn.defender()
	if defender.types().has(RomLayout.TYPE_GRASS):
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		return

	if Gen2Substatus.has(defender.substatus, Gen2Substatus.LEECH_SEED):
		turn.emit(Gen2Battle.EVADED, {"target": turn.target})
		return

	defender.substatus |= Gen2Substatus.LEECH_SEED
	_animate_current_move(turn)
	turn.emit(Gen2Battle.WAS_SEEDED, {"target": turn.target})


## Four refusals, all `PrintButItFailed`: a target out of sight, one behind a
## doll, one that is not asleep, and one already having a nightmare.
static func _nightmare(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	if _is_hidden(defender.substatus) or _substitute_refuses(turn) \
		or not Gen2Status.is_asleep(defender.status) \
		or Gen2Substatus.has(defender.substatus, Gen2Substatus.NIGHTMARE):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	defender.substatus |= Gen2Substatus.NIGHTMARE
	_animate_current_move(turn)
	turn.emit(Gen2Battle.NIGHTMARE_STARTED, {"target": turn.target})


## Two moves sharing a byte and telling themselves apart by the *user's* own
## types: a Ghost curses the target for half its own maximum, everybody else
## trades a stage of Speed for one of Attack and one of Defense.
##
## Those three are `LowerStat` and `BattleCommand_AttackUp`/`..._DefenseUp`, which
## act on the user's own stages with no Mist, Substitute or `wEffectFailed` check
## between them, so they are stage moves here rather than [method _stat_change]
## calls. `ResetMiss` between them is what stops a Speed that could not fall from
## swallowing the two raises.
static func _curse(turn: Gen2Turn) -> void:
	var user: Gen2BattleMon = turn.attacker()
	if user.types().has(RomLayout.TYPE_GHOST):
		_curse_ghost(turn, user)
		return

	# `.cantraise` names `GetStatName`'s eighth entry rather than either stat it
	# just looked at: `ld b, ABILITY + 1` is what `StatNames`' "ABILITY" row exists
	# for, and the line reads "<USER>'s ABILITY won't rise anymore!".
	if not user.can_change_stage("attack", 1) and not user.can_change_stage("defense", 1):
		turn.emit(Gen2Battle.STAT_CHANGE_FAILED, {
			"target": turn.side, "stat": CURSE_FAILED_STAT, "by": 1,
		})
		return

	# `ld a, $1 / ld [wBattleAnimParam], a` ahead of `AnimateCurrentMove`.
	turn.battle.battle_anim_param = 1
	_animate_current_move(turn)
	_curse_stage(turn, user, "speed", -1)
	_curse_stage(turn, user, "attack", 1)
	_curse_stage(turn, user, "defense", 1)


static func _curse_stage(turn: Gen2Turn, user: Gen2BattleMon, key: String, by: int) -> void:
	turn.stat_key = key
	turn.stat_by = by
	turn.stat_target = turn.side
	turn.stat_mist_blocked = false
	turn.stat_moved = user.change_stage(key, by)
	_stat_message(turn)


## `.ghost`: `GetHalfMaxHP` and `SubtractHPFromUser` with nothing between them, so
## a user on less than half its maximum goes down to its own move.
static func _curse_ghost(turn: Gen2Turn, user: Gen2BattleMon) -> void:
	var defender: Gen2BattleMon = turn.defender()
	if _is_hidden(defender.substatus) or _substitute_refuses(turn) \
		or Gen2Substatus.has(defender.substatus, Gen2Substatus.CURSE):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	defender.substatus |= Gen2Substatus.CURSE
	_animate_current_move(turn)
	var taken: int = user.take_damage(Gen2Substatus.half_damage(user.max_hp()))
	turn.emit(Gen2Battle.CURSE_SET, {
		"target": turn.target, "amount": taken, "hp": user.hp, "max_hp": user.max_hp(),
	})

	# `Curse:` carries no `checkfaint`: the cartridge's turn loop asks
	# `HasPlayerFainted` behind every move, and this engine has no such step, so
	# whoever took the health reports it, as `_residual_damage` already does.
	if user.is_fainted():
		turn.emit(Gen2Battle.FAINTED)


## Field state [method Gen2Battle._spikes_damage] charges to whoever walks onto
## it. Nothing stops it but spikes already there, and that is `FailMove` rather
## than a quiet return.
static func _spikes(turn: Gen2Turn) -> void:
	if Gen2Screens.has(turn.battle.screens[turn.target], Gen2Screens.SPIKES):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	turn.battle.screens[turn.target] |= Gen2Screens.SPIKES
	_animate_current_move(turn)
	turn.emit(Gen2Battle.SPIKES_SET, {"target": turn.target})


## All three are the user's own state, never the target's, and the wrap half
## zeroes the counter without clearing [member Gen2BattleMon.trapping_move],
## which is what the source leaves alone.
static func _clear_hazards(turn: Gen2Turn) -> void:
	var user: Gen2BattleMon = turn.attacker()
	if Gen2Substatus.has(user.substatus, Gen2Substatus.LEECH_SEED):
		user.substatus &= ~Gen2Substatus.LEECH_SEED
		turn.emit(Gen2Battle.SHED_LEECH_SEED)

	if Gen2Screens.has(turn.battle.screens[turn.side], Gen2Screens.SPIKES):
		turn.battle.screens[turn.side] &= ~Gen2Screens.SPIKES
		turn.emit(Gen2Battle.BLEW_SPIKES)

	if user.trapped_turns > 0:
		user.trapped_turns = 0
		turn.emit(Gen2Battle.RELEASED_BY, {"target": turn.target})


## `ProtectChance`, which Protect, Detect and Endure all are: three gates, then a
## roll whose odds halve once per consecutive use. Answers whether the flag goes
## up, and has already reported the failure when it says no.
##
## The two gates in front of the ladder are easy to get backwards. Going second
## fails outright, which is what makes two Protects in one turn a question of
## speed. And the Substitute it refuses is the *user's own*
## (`BATTLE_VARS_SUBSTATUS4`, not `_OPP`), so a Pokémon behind its own doll cannot
## protect; nothing about the target is asked.
static func _protect_chance(turn: Gen2Turn) -> bool:
	var user: Gen2BattleMon = turn.attacker()
	if turn.battle.opponent_went_first(turn.side):
		return _protect_failed(turn, user)
	if Gen2Substatus.has(user.substatus, Gen2Substatus.SUBSTITUTE):
		return _protect_failed(turn, user)

	# `ld b, $ff` shifted right once per count, failing outright the moment it
	# reaches zero: 255, 127, 63, 31, 15, 7, 3, 1, then nothing at eight.
	var ceiling: int = 0xFF
	for _step: int in user.protect_count:
		ceiling >>= 1
		if ceiling == 0:
			return _protect_failed(turn, user)

	# `.rand` rerolls a zero, so the draw is 1..255 rather than 0..255, and the
	# comparison is on `roll - 1`. That is why a count of zero, with the ceiling
	# still at 255, cannot fail: every one of the 255 values it can draw passes.
	var roll: int = turn.rng().randi_range(1, PROTECT_ROLL_RANGE)
	if roll - 1 >= ceiling:
		return _protect_failed(turn, user)

	user.protect_count += 1
	return true


## What the ladder draws against, `BattleRandom` with its zero rerolled away.
const PROTECT_ROLL_RANGE: int = 0xFF


## `.failed`: the count goes back to nothing and the move says so. The animation
## the source plays here is `AnimateFailedMove`, which this engine spends no
## frames on anywhere.
static func _protect_failed(turn: Gen2Turn, user: Gen2BattleMon) -> bool:
	user.protect_count = 0
	turn.emit(Gen2Battle.MOVE_FAILED)
	return false


static func _protect(turn: Gen2Turn) -> void:
	if not _protect_chance(turn):
		return
	turn.attacker().substatus |= Gen2Substatus.PROTECT
	_animate_current_move(turn)
	turn.emit(Gen2Battle.PROTECTED_ITSELF)


static func _endure(turn: Gen2Turn) -> void:
	if not _protect_chance(turn):
		return
	turn.attacker().substatus |= Gen2Substatus.ENDURE
	_animate_current_move(turn)
	turn.emit(Gen2Battle.BRACED_ITSELF)


## `BattleCommand_DestinyBond`: the flag and the line, with nothing in front of
## them. It rolls nothing, refuses nothing and cannot fail, which is why a second
## use in a row is not a failure the way a second Protect can be.
static func _destiny_bond(turn: Gen2Turn) -> void:
	turn.attacker().substatus |= Gen2Substatus.DESTINY_BOND
	_animate_current_move(turn)
	turn.emit(Gen2Battle.DESTINY_BOND_SET)


## `BattleCommand_ForceSwitch`: Whirlwind and Roar, which have two endings and
## share almost nothing between them.
##
## Against a trainer the target's side switches to a random standing party
## member. Against a wild the battle *ends*, in either direction: the wild is
## blown out of it or the player's own Pokémon is, and `SetBattleDraw` makes both
## a draw with nobody beaten.
##
## The two halves of the source, `.trainer` and `.vs_trainer`, are one routine
## here because every difference between them is which side is read. Written out,
## both say: the user's level against the target's, the user having moved second,
## and a random member of the target's party.
static func _force_switch(turn: Gen2Turn) -> void:
	if FORCE_SWITCH_REFUSED_TYPES.has(turn.battle.battle_type) or turn.missed:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	if turn.battle.is_trainer_battle:
		_force_switch_trainer(turn)
		return
	_force_switch_wild(turn)


## The four `wBattleType` values that refuse outright, before anything else is
## asked. All four are scripted encounters the story needs to keep on the field.
const FORCE_SWITCH_REFUSED_TYPES: Array[int] = [
	Gen2Battle.BATTLETYPE_FORCESHINY, Gen2Battle.BATTLETYPE_TRAP,
	Gen2Battle.BATTLETYPE_CELEBI, Gen2Battle.BATTLETYPE_SUICUNE,
]


## `.trainer` and `.vs_trainer`: drag a random standing party member out.
##
## The went-first gate is the non-obvious half. Both branches refuse unless the
## *opponent* moved first, which is `wEnemyGoesFirst` read from each side's own
## point of view, so a Whirlwind that somehow moved first does nothing. Priority
## 0 makes that rare rather than impossible: a slower opponent using Counter,
## Mirror Coat or a force switch of its own shares the same priority.
static func _force_switch_trainer(turn: Gen2Turn) -> void:
	var party: Gen2Party = turn.battle.party(turn.target)
	if _standing_others(party).is_empty():
		turn.emit(Gen2Battle.MOVE_FAILED)
		return
	if not turn.battle.opponent_went_first(turn.side):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	turn.battle.battle_anim_param = FORCE_SWITCH_ANIM_PARAM
	_animate_current_move(turn)
	var picked: int = _roll_dragged_index(turn, party)
	turn.events.append_array(turn.battle.send_out(turn.target, picked, turn.side))


## `ld a, $1 / ld [wBattleAnimParam], a`, which both endings set in front of
## their own `AnimateCurrentMove`.
const FORCE_SWITCH_ANIM_PARAM: int = 1


## `.random_loop_trainer`, which is a rejection sample rather than a range: three
## bits of a random byte, rerolled while the value is past the party's end, is the
## member already out, or is one that has fainted. `CheckAnyOtherAlivePartyMons`
## has already answered that one of the six will do, so it terminates.
static func _roll_dragged_index(turn: Gen2Turn, party: Gen2Party) -> int:
	var standing: Array[int] = _standing_others(party)
	var picked: int = party.active
	while not standing.has(picked):
		picked = turn.rng().randi_range(0, FORCE_SWITCH_ROLL_MASK)
	return picked


## `and $7`: the roll is masked to three bits, so a party is only ever reached
## through the eight values that mask leaves.
const FORCE_SWITCH_ROLL_MASK: int = 7


## Every member of [param party] that is standing and is not the one out, which
## is `CheckAnyOtherAlivePartyMons` and `FindAliveEnemyMons` both.
static func _standing_others(party: Gen2Party) -> Array[int]:
	var out: Array[int] = []
	for index: int in party.size():
		if index != party.active and not party.at(index).is_fainted():
			out.append(index)
	return out


## `.wild_force_flee` and `.wild_succeed_playeristarget`, which are the same
## comparison written twice: the user's level against the target's.
##
## A user at or above the target's level always succeeds. Below it, the roll is
## drawn out of the two levels summed and one more, and it succeeds unless it
## lands under a quarter of the target's level, so a much weaker user usually
## fails. `srl b` twice is that quarter, and it truncates.
static func _force_switch_wild(turn: Gen2Turn) -> void:
	var user_level: int = turn.attacker().level
	var target_level: int = turn.defender().level

	if user_level < target_level:
		var span: int = user_level + target_level + 1
		var roll: int = turn.rng().randi_range(0, span - 1)
		if roll < target_level >> 2:
			turn.emit(Gen2Battle.MOVE_FAILED)
			return

	turn.battle.force_out(turn.target)
	turn.battle.battle_anim_param = FORCE_SWITCH_ANIM_PARAM
	_animate_current_move(turn)
	# `.succeed` reads the move's animation byte back and compares it against
	# ROAR, and every move here animates as itself.
	var line: StringName = Gen2Battle.FLED_IN_FEAR if turn.move_number == Gen2MoveEffect.ROAR_MOVE \
		else Gen2Battle.BLOWN_AWAY
	turn.emit(line, {"target": turn.target})


## `BattleCommand_BatonPass`: switch, and hand the new arrival everything the
## position was carrying.
##
## The two halves differ in one thing only, and it is the reason this is the
## first effect that cannot be resolved in one go. The enemy's target is picked
## for it, by the same routine that picks an ordinary AI switch. The player's is
## `ForcePickSwitchMonInBattle`, a menu opened inside the move and impossible to
## back out of, so the turn stops here and [method Gen2Battle.pass_to] is what
## finishes it. Committing a target before the turn would be the easy way and the
## wrong one: a Baton Pass that moves second is picked once the opponent's move
## has already landed, so the player chooses knowing something an earlier
## commitment could not.
##
## `AnimateCurrentMove` is in front of both, which is why it runs before the
## question rather than after the answer.
static func _baton_pass(turn: Gen2Turn) -> void:
	var battle: Gen2Battle = turn.battle
	var side: int = turn.side

	# `.Enemy`'s own first line: a wild Pokémon has no party behind it.
	if side == Gen2Battle.ENEMY and not battle.is_trainer_battle:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return
	# `CheckAnyOtherAlivePartyMons`, the same question `.trainer` asks of the
	# other side before dragging anybody out.
	if _standing_others(battle.party(side)).is_empty():
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	_animate_current_move(turn)

	if side == Gen2Battle.PLAYER:
		battle.request_baton_pass(side)
		return
	turn.events.append_array(
		battle.baton_pass_send_out(side, battle.baton_pass_target(side))
	)


## `BattleCommand_Teleport`: the user takes itself out of a wild battle, which
## ends it as a draw with nobody beaten. `wForcedSwitch` and `SetBattleDraw` are
## [method Gen2Battle.force_out], the same pair Whirlwind and Roar reach, except
## that the side leaving is the user's rather than the target's.
##
## Four refusals in the source's order: the four scripted `wBattleType` values,
## the opponent holding the user with Mean Look or Spider Web, a trainer battle,
## and the level comparison. The comparison is `BattleCommand_ForceSwitch`'s: a
## user at or above the other's level always gets away, and below it the roll is
## drawn out of the two levels summed and one more and fails only under a quarter
## of the other's level.
##
## The enemy's half draws that roll and then throws it away: `cp b / jr nc,
## .run_away` falls straight into `.run_away`, so a wild Pokémon always
## teleports. That is `docs/bugs_and_glitches.md`'s "Wild Pokémon can always
## Teleport regardless of level difference", mirrored rather than fixed, and the
## roll is still drawn so the generator moves the same way.
static func _teleport(turn: Gen2Turn) -> void:
	if FORCE_SWITCH_REFUSED_TYPES.has(turn.battle.battle_type) \
		or Gen2Substatus.has(turn.defender().substatus, Gen2Substatus.CANT_RUN) \
		or turn.battle.is_trainer_battle:
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	var user_level: int = turn.attacker().level
	var other_level: int = turn.defender().level
	if user_level < other_level:
		var span: int = user_level + other_level + 1
		var roll: int = turn.rng().randi_range(0, span - 1)
		if turn.side == Gen2Battle.PLAYER and roll < other_level >> 2:
			turn.emit(Gen2Battle.MOVE_FAILED)
			return

	turn.battle.force_out(turn.side)
	turn.battle.battle_anim_param = FORCE_SWITCH_ANIM_PARAM
	_animate_current_move(turn)
	turn.emit(Gen2Battle.FLED_FROM_BATTLE)


## `BattleCommand_Foresight`: the flag that drops the target's evasion out of the
## accuracy sum and opens the two Ghost immunities the matchup table keeps past
## its own `-2` marker. It sits on the target and nothing but a switch clears it.
##
## Two refusals: a target that is flying or underground, and one already
## identified. Only the second is reached through the cartridge's own list, on the
## cartridge as well as here, since `checkhit` in front of the command has already
## turned a hidden target away. The first is kept for a registered list that
## carries no `checkhit`.
static func _foresight(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	if _is_hidden(defender.substatus) \
		or Gen2Substatus.has(defender.substatus, Gen2Substatus.IDENTIFIED):
		turn.emit(Gen2Battle.MOVE_FAILED)
		return

	defender.substatus |= Gen2Substatus.IDENTIFIED
	_animate_current_move(turn)
	turn.emit(Gen2Battle.IDENTIFIED_SET, {"target": turn.target})


## `BattleCommand_LockOn`: Lock On and Mind Reader, one command. The flag goes on
## the target, and [method _check_hit] spends it on the next hit check made
## against that Pokémon, whoever makes it.
##
## The one refusal is a target behind a doll, and it prints
## `PrintDidntAffect` rather than "But it failed!".
static func _lock_on(turn: Gen2Turn) -> void:
	if _substitute_refuses(turn):
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		return

	turn.defender().substatus |= Gen2Substatus.LOCK_ON
	_animate_current_move(turn)
	turn.emit(Gen2Battle.TOOK_AIM)


## `BattleCommand_Spite`: two to five PP off the slot holding the target's last
## move, or as much as that slot has left.
##
## The slot is found by searching the target's own move list, the way
## [method _disable] finds Disable's, and the guard for a move no longer in that
## list is this project's rather than the cartridge's: `.loop` there has no bound
## and would run off the end of the list. It is reachable only through a
## mid-battle level up replacing a slot.
##
## Four refusals, all `PrintDidntAffect2`: a target that has not moved, a last
## move of Struggle, a slot already empty of PP, and the missing slot above.
static func _spite(turn: Gen2Turn) -> void:
	var defender: Gen2BattleMon = turn.defender()
	var last_move: int = defender.last_counter_move
	if last_move == 0 or last_move == Gen2Damage.STRUGGLE:
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		return

	var slot: int = defender.moves.find(last_move)
	if slot < 0 or defender.pp_left(slot) <= 0:
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		return

	var amount: int = mini(_roll_spite_pp(turn.rng()), defender.pp_left(slot))
	defender.pp[slot] = int(defender.pp[slot]) - amount
	_animate_current_move(turn)
	turn.emit(Gen2Battle.PP_REDUCED, {
		"target": turn.target, "slot": slot, "move": last_move, "amount": amount,
	})


## `call BattleRandom / and %11 / inc a / inc a`: two bits of a random byte and
## two added, so two through five.
static func _roll_spite_pp(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 3) + SPITE_MIN_PP


const SPITE_MIN_PP: int = 2


## `BattleCommand_PainSplit`: both Pokémon end on the average of the two current
## totals, floored, and neither goes above its own maximum.
##
## The health words are written by hand, so nothing stands between this and
## either Pokémon: no doll takes it, no Focus Band fires and no Endure clamps it.
## Both are standing when this runs, so the average is at least one and the move
## cannot faint anybody.
##
## Two refusals, both `PrintDidntAffect2`: a miss, which `checkhit` has already
## turned into an ended move, and a target behind a doll.
static func _pain_split(turn: Gen2Turn) -> void:
	if _substitute_refuses(turn):
		turn.emit(Gen2Battle.NO_EFFECT, {"target": turn.target})
		return

	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()
	@warning_ignore("integer_division")
	var shared: int = (attacker.hp + defender.hp) / 2
	_animate_current_move(turn)
	attacker.hp = mini(shared, attacker.max_hp())
	defender.hp = mini(shared, defender.max_hp())
	turn.emit(Gen2Battle.SHARED_PAIN, {
		"target": turn.target,
		"hp": attacker.hp, "max_hp": attacker.max_hp(),
		"target_hp": defender.hp, "target_max_hp": defender.max_hp(),
	})


## `BattleCommand_Thief`: the target's held item, onto a thief carrying none.
##
## The cartridge writes both the battle struct and the party struct, because they
## are two copies of one Pokémon; here [method Gen2Battle.mon] hands back the
## party member itself, so one write is both and a stolen item is gone for good
## on either side without anything extra.
##
## Four refusals in the source's order, every one of them silent: the thief
## already holds something, the target holds nothing, the item is mail, and the
## move's own chance came up short. The chance is read last, which costs nothing
## since `effectchance` drew its roll earlier in the list.
static func _thief(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	var defender: Gen2BattleMon = turn.defender()
	if attacker.item != 0 or defender.item == 0:
		return
	if Gen2HeldItem.is_mail(defender.item) or turn.failed_chance:
		return

	var stolen: int = defender.item
	defender.item = 0
	attacker.item = stolen
	turn.emit(Gen2Battle.STOLE_ITEM, {"target": turn.target, "item": stolen})


## `BattleCommand_Pursuit`: twice the finished figure against a side that is
## leaving, saturating at a word rather than wrapping.
##
## The doubling is all this command is. What makes Pursuit hit the Pokémon on its
## way out is `PursuitSwitch`, which runs the whole move in front of the switch;
## see [method Gen2Battle.take_actions].
static func _pursuit(turn: Gen2Turn) -> void:
	if not turn.battle.is_switching(turn.target):
		return
	turn.damage = mini(turn.damage * 2, 0xFFFF)


## `BattleCommand_BeatUp` with `startloop` and `endloop` around it: one hit per
## member of the user's own party, in party order, each worked out from that
## member's species base Attack and its own level.
##
## The loop is inside this command as [method _multi_hit]'s is inside that one,
## because `endloop` jumps back to `critical` rather than to the top of the list:
## `checkhit` is outside it and rolls once for the whole move.
##
## `damagecalc` is handed base stats rather than real ones and never sees
## `damagestats`, so no item, no screen, no stage and no truncation touches
## either figure. There is no `stab` either, so no same-type bonus, no weather
## and no matchup: `CheckTurn` leaves the type modifier at `EFFECTIVE` for the
## whole turn and `supereffectivetext` says nothing.
##
## `.beatup_fail` skips a member with no health or with any status at all and
## lets the loop carry on, which is `SkipToBattleCommand buildopponentrage`, and
## `endloop` prints no "hit N times" line for this effect (`.beat_up_2`).
static func _beat_up(turn: Gen2Turn) -> void:
	var battle: Gen2Battle = turn.battle
	var party: Gen2Party = battle.party(turn.side)
	var defender: Gen2BattleMon = turn.defender()

	# `.wild`, which has no party to walk: `EnemyAttackDamage` gives the wild
	# Pokémon one ordinary hit off its own real stats, and `endloop`'s
	# `.check_ot_beat_up` then falls into `.only_one_beatup`. Nothing on that path
	# ever set `wBeatUpHitAtLeastOnce`, so the hit lands and "But it failed!" is
	# printed behind it anyway.
	if turn.side == Gen2Battle.ENEMY and not battle.is_trainer_battle:
		turn.emit(Gen2Battle.BEAT_UP_ATTACK, {"index": -1, "species": turn.attacker().species})
		_damage_stats(turn)
		_beat_up_hit(turn)
		if defender.is_fainted():
			_check_faint(turn)
		else:
			turn.emit(Gen2Battle.MOVE_FAILED)
		turn.end()
		return

	var struck: bool = false
	for index: int in party.size():
		var member: Gen2BattleMon = party.at(index)
		if not member.is_fainted() and member.status == Gen2Status.NONE:
			struck = true
			turn.emit(Gen2Battle.BEAT_UP_ATTACK, {
				"index": index, "species": member.species,
			})
			turn.attack_stat = _base_stat(turn, member.species, "attack")
			turn.defense_stat = _base_stat(turn, defender.species, "defense")
			turn.level_override = member.level
			turn.power_override = int(turn.move.get("power", 0))
			_beat_up_hit(turn)
			if defender.is_fainted():
				_check_faint(turn)
				turn.end()
				return

		# `.only_one_beatup`, which the whole party reaches on `cp 1`: the loop
		# flag is cleared and the move ends outright, so `kingsrock` behind it
		# never runs. `docs/bugs_and_glitches.md`'s "Beat Up works incorrectly
		# with only one Pokémon in the party", mirrored rather than fixed.
		if party.size() == 1:
			if not struck:
				turn.emit(Gen2Battle.MOVE_FAILED)
			turn.end()
			return

	# `beatupfailtext`, which says nothing when any member landed a hit.
	if not struck:
		turn.emit(Gen2Battle.MOVE_FAILED)


## One pass of the loop: `critical`, `beatup`'s own numbers, `damagecalc`,
## `damagevariation`, `moveanimnosub` and `applydamage`.
##
## `clearmissdamage` is structural, since the one `checkhit` sits outside the loop
## and has already ended the move on a miss.
static func _beat_up_hit(turn: Gen2Turn) -> void:
	_critical(turn)
	_damage_calc(turn)
	_damage_variation(turn)
	_move_anim(turn)
	_apply_damage(turn)


## A species' own base Attack or base Defense, which is what `GetBaseData` leaves
## in `wBaseAttack` and `wBaseDefense` for `BattleCommand_BeatUp` to load.
static func _base_stat(turn: Gen2Turn, species: int, key: String) -> int:
	return int(turn.data().species(species).get("stats", {}).get(key, 0))


## `BattleCommand_CheckSafeguard`: the target's own Safeguard refusing a status
## move outright, with `SafeguardProtectText` and the move ended.
##
## `wAttackMissed` is set before the text, so everything behind this in the list
## is skipped and the move counts as a miss for whatever reads that back.
static func _check_safeguard(turn: Gen2Turn) -> void:
	if not Gen2Screens.has(turn.battle.screens[turn.target], Gen2Screens.SAFEGUARD):
		return
	turn.missed = true
	turn.emit(Gen2Battle.SAFEGUARD_PROTECTED, {"target": turn.target})
	turn.end()


## `SafeCheckSafeguard`: the quiet half, which every secondary status effect asks
## before it writes anything. Reads the side opposite whoever is acting, so a
## rampage confusing its own user has to ask about the user's side and the
## caller switches turn around it the way `BattleCommand_Rampage` does.
static func _safeguard_refuses(turn: Gen2Turn, side: int) -> bool:
	return Gen2Screens.has(turn.battle.screens[side], Gen2Screens.SAFEGUARD)


## `BattleCommand_Heal`: Recover, Softboiled and Milk Drink take back half the
## maximum; Rest takes back all of it and pays for that with two turns asleep.
##
## The full-HP refusal is checked before anything else, so Rest at full health
## fails and stays awake even when there is a status sitting on it that sleeping
## would have cleared. Rest writes `REST_SLEEP_TURNS + 1` over the whole status
## byte rather than into the sleep bits, which is why it is the one move that
## cures a burn or a paralysis, and it clears Toxic's ramp with it.
static func _heal(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	if attacker.hp >= attacker.max_hp():
		turn.emit(Gen2Battle.HP_ALREADY_FULL)
		return

	var is_rest: bool = turn.move_number == Gen2MoveEffect.REST_MOVE
	if is_rest:
		var had_status: bool = Gen2Status.is_afflicted(attacker.status)
		attacker.toxic_counter = 0
		attacker.status = Gen2Status.REST_SLEEP_TURNS + 1
		turn.emit(Gen2Battle.RESTED if had_status else Gen2Battle.WENT_TO_SLEEP)

	@warning_ignore("integer_division")
	var amount: int = attacker.max_hp() if is_rest else maxi(attacker.max_hp() / 2, 1)
	_animate_current_move(turn)
	attacker.heal(amount)
	turn.emit(Gen2Battle.HP_RESTORED, {
		"hp": attacker.hp, "max_hp": attacker.max_hp(),
	})


## `BattleCommand_TimeBasedHealContinue`: Morning Sun, Synthesis and Moonlight.
##
## Half the maximum by default. One step down the table outside the move's own
## time of day, which is the cartridge's real rule: matching the clock buys
## nothing, missing it costs. Then one step up in sun, or one step down in any
## other weather, so the worst case is an eighth and the best is the whole bar.
## Link battles skip the time step; there are none here.
static func _timed_heal(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	if attacker.hp >= attacker.max_hp():
		turn.emit(Gen2Battle.HP_ALREADY_FULL)
		return

	var index: int = HEAL_HALF
	if turn.battle.time_of_day != HEAL_TIMES.get(turn.effect(), Gen2WorldPalette.TIME_DAY):
		index -= 1
	if Gen2Weather.is_active(turn.battle.weather):
		index += 1 if turn.battle.weather == Gen2Weather.SUN else -1

	_animate_current_move(turn)
	attacker.heal(_heal_fraction(attacker.max_hp(), index))
	turn.emit(Gen2Battle.HP_RESTORED, {
		"hp": attacker.hp, "max_hp": attacker.max_hp(),
	})


## One row of `.Multipliers`. `GetEighthMaxHP` halves `GetQuarterMaxHP`'s answer
## rather than dividing the maximum by eight, so its own floor of one is applied
## twice and a two-HP Pokémon is healed for one either way.
static func _heal_fraction(max_hp: int, index: int) -> int:
	match index:
		HEAL_EIGHTH:
			@warning_ignore("integer_division")
			return maxi(maxi(max_hp / 4, 1) / 2, 1)
		HEAL_QUARTER:
			@warning_ignore("integer_division")
			return maxi(max_hp / 4, 1)
		HEAL_HALF:
			@warning_ignore("integer_division")
			return maxi(max_hp / 2, 1)
		_:
			return max_hp


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


## `PlayFXAnimID`. Nothing is drawn here: the animation is written down as an
## event at its own place in the turn and the screen is what spends frames on it.
##
## [param on_opponent] is `PlayOpponentBattleAnim`'s pair of
## `BattleCommand_SwitchTurn` calls: the same event with `hBattleTurn` inverted
## for the length of the animation, so it plays on the target rather than on
## whoever is acting.
static func _play_fx_anim(
	turn: Gen2Turn, index: int, after_anim: int, restore_user_pic: bool = false,
	on_opponent: bool = false
) -> void:
	var enemy_turn: bool = turn.side == Gen2Battle.ENEMY
	turn.emit(Gen2Battle.ANIMATION, {
		"index": index,
		"param": turn.battle.battle_anim_param,
		"after_anim": after_anim,
		"enemy_turn": enemy_turn != on_opponent,
		"effectiveness": turn.effectiveness,
		"restore_user_pic": restore_user_pic,
	})


## `PlayOpponentBattleAnim`, the fifth route an animation reaches the screen by
## and the only one that is not the move's own: `wFXAnimID` set from `de`,
## `wBattleAfterAnim` cleared, and `PlayBattleAnim` run between two
## `BattleCommand_SwitchTurn` calls.
##
## `wBattleAnimParam` is not written, so whatever the move's own animation left
## stands, the way it does across [method _animate_current_move].
##
## Five commands call it, all secondary-effect ones, and all five ids are past
## `wFXAnimID`'s low byte: `BattleAnimRunScript` therefore takes `.not_move`,
## which skips `CheckBattleScene`, both hud calls and the after-anim. A status
## animation plays with the battle-scene option turned off.
static func _play_opponent_battle_anim(turn: Gen2Turn, index: int) -> void:
	_play_fx_anim(turn, index, Gen2BattleAnimPlayer.AFTER_ANIM_NONE, false, true)


## `BattleCommand_MoveAnimNoSub`: the damage flash aimed at whoever was hit, the
## animation param cleared or alternated, and then the move's own animation.
##
## A miss falls to `BattleCommand_MoveDelay` and plays nothing. That branch is
## structural here rather than reached: [method _check_hit] ends the move, so no
## list gets this far after one.
static func _move_anim(turn: Gen2Turn) -> void:
	if turn.missed:
		return
	turn.battle.battle_anim_param = 0
	_play_fx_anim(
		turn, turn.move_number, _damage_after_anim(turn),
		turn.move_number in [Gen2MoveEffect.FLY_MOVE, Gen2MoveEffect.DIG_MOVE]
	)


## `.alternate_anim`, the branch the five multi-hit effects take instead of
## clearing the param: the low bit is flipped, and the damage flash is kept only
## for the hit `wPlayerRolloutCount`/`wEnemyRolloutCount` says is the last one,
## so a multi-hit flashes once rather than per hit.
static func _multi_hit_anim(turn: Gen2Turn, last_hit: bool) -> void:
	turn.battle.battle_anim_param = (turn.battle.battle_anim_param & 1) ^ 1
	_play_fx_anim(
		turn, turn.move_number,
		_damage_after_anim(turn) if last_hit else Gen2BattleAnimPlayer.AFTER_ANIM_NONE
	)


## `ANIM_ENEMY_DAMAGE` on the player's turn, `ANIM_PLAYER_DAMAGE` on the
## enemy's, both as offsets from `BATTLE_AFTERANIMS`.
static func _damage_after_anim(turn: Gen2Turn) -> int:
	return Gen2BattleAnimPlayer.AFTER_ANIM_ENEMY_DAMAGE if turn.side == Gen2Battle.PLAYER \
		else Gen2BattleAnimPlayer.AFTER_ANIM_PLAYER_DAMAGE


## `BattleCommand_StatUpDownAnim`, which both stat anim commands fall into: the
## after-anim its caller chose, the param cleared, and the move's animation.
static func _stat_change_anim(turn: Gen2Turn, after_anim: int) -> void:
	if turn.missed:
		return
	turn.battle.battle_anim_param = 0
	_play_fx_anim(turn, turn.move_number, after_anim)


## Which of the five status commands carries an `AnimateCurrentMove` of its own.
##
## `BattleCommand_SleepTarget`, `..._Poison` and `..._Paralyze` are the status
## moves' own commands and do; `..._PoisonTarget`, `..._ParalyzeTarget`,
## `..._BurnTarget` and `..._FreezeTarget` are the secondary-effect commands and
## do not, since the move that carried them has already played its `moveanim`.
## One command serves both here, so the effect byte is what tells them apart.
static func _status_move_animates(turn: Gen2Turn, flag: int) -> bool:
	match flag:
		Gen2Status.SLEEP_MASK:
			return true
		Gen2Status.POISON:
			return turn.effect() == Gen2MoveEffect.POISON
		Gen2Status.PARALYSIS:
			return turn.effect() == Gen2MoveEffect.PARALYZE
	return false


## Which status animation `PlayOpponentBattleAnim` plays on the target, or -1.
##
## The four secondary-effect commands each play one, and the primary status
## moves' own commands play none: `BattleCommand_SleepTarget` ends at
## `AnimateCurrentMove`, `BattleCommand_Poison`'s `.apply_poison` is
## `AnimateCurrentMove`, `PoisonOpponent`, `RefreshBattleHuds`, and
## `BattleCommand_Paralyze` the same. Toxic reaches that same `.apply_poison`, so
## [method _toxic_target] plays none either.
##
## That makes this the exact inverse of [method _status_move_animates] rather
## than a second rule: burn and freeze have no status move of their own to be the
## primary shape of, and sleep is the one status whose primary command is the
## only shape there is.
static func _status_target_anim(turn: Gen2Turn, flag: int) -> int:
	if _status_move_animates(turn, flag):
		return -1
	match flag:
		Gen2Status.POISON:
			return Gen2BattleAnimPlayer.ANIM_PSN
		Gen2Status.BURN:
			return Gen2BattleAnimPlayer.ANIM_BRN
		Gen2Status.FREEZE:
			return Gen2BattleAnimPlayer.ANIM_FRZ
		Gen2Status.PARALYSIS:
			return Gen2BattleAnimPlayer.ANIM_PAR
	return -1


## `AnimateCurrentMove`, which is `LoadMoveAnim` between a `lowersub` and a
## `raisesub`: the move's own animation with `wBattleAfterAnim` cleared, so no
## damage flash follows it.
##
## Not a list command. Fifteen commands call it from inside their own bodies,
## and it is the whole animation of every move whose effect list carries no
## animation command at all. `wBattleAnimParam` is pushed across the sub calls
## rather than cleared, so whatever the last animation left stands.
static func _animate_current_move(turn: Gen2Turn) -> void:
	_play_fx_anim(turn, turn.move_number, Gen2BattleAnimPlayer.AFTER_ANIM_NONE)


## `BattleCommand_HeldFlinch`: a King's Rock on the attacker makes an ordinary
## attack flinch, out of the item's own parameter.
##
## The `wAttackMissed` guard is structural here, since [method _check_hit] ends
## the move on a miss and [method _check_faint] ends it on a KO, so this step is
## only ever reached by a hit that left the target standing. The Substitute check
## sits between the item and the roll, exactly where `BattleCommand_HeldFlinch`
## puts it, so a King's Rock aimed at a doll draws no roll.
static func _kings_rock(turn: Gen2Turn) -> void:
	var attacker: Gen2BattleMon = turn.attacker()
	if Gen2HeldItem.effect_of(turn.data(), attacker.item) != Gen2HeldItem.FLINCH:
		return

	if _substitute_refuses(turn):
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
##
## The order is `BattleCommand_StatDown`'s: `CheckMist`, then the stage that
## cannot move, then `.DidntMiss`'s `CheckSubstituteOpp` and `wEffectFailed`. Each
## sets a different `wFailedMessage`, so a drop that failed its secondary roll
## against a Misted or already-floored target still says the specific line.
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
	turn.stat_moved = false

	if not targets_user and Gen2Substatus.has(turn.battle.mon(side).substatus, Gen2Substatus.MIST):
		turn.stat_mist_blocked = true
		return

	if not turn.battle.mon(side).can_change_stage(stat_key, amount):
		return

	if not targets_user and _substitute_refuses(turn):
		return

	if turn.failed_chance:
		return

	turn.stat_moved = turn.battle.mon(side).change_stage(stat_key, amount)

	# `MinimizeDropSub`, the tail of `BattleCommand_StatUp` and reached only when
	# the raise took: the flag is set off the move being animated rather than off
	# an effect byte, since Minimize carries the ordinary `EFFECT_EVASION_UP` and
	# nothing else tells it from Double Team.
	if targets_user and turn.stat_moved and turn.move_number == MINIMIZE_MOVE:
		turn.battle.mon(side).minimized = true


## Minimize's move number, which is the whole of what `MinimizeDropSub` compares
## against and what makes a Stomp hurt twice as much.
const MINIMIZE_MOVE: int = 107

## `StatNames`' eighth row, which exists only so `BattleCommand_Curse` has
## something to name when neither of the two stats it raises can move.
const CURSE_FAILED_STAT: String = "ability"


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
