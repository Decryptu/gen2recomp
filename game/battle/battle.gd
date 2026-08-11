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
## A freeze cleared, from any of the three places one is. `side` is whoever
## thawed, not whoever acted: the user through a Flame Wheel or Sacred Fire, the
## target through `BattleCommand_BurnTarget`'s `Defrost`, or either through
## `HandleDefrost`'s end-of-turn roll.
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
## The five stats in [constant Gen2Experience.STAT_EXP_KEYS], out of the same
## divided block [constant EXP_GAINED]'s award came from: see
## [method Gen2Experience.shared_block]. Divided by the same count, but a base
## stat rather than a figure the level formula has been through.
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
const BIDE_STORING: StringName = &"bide_storing"
const BIDE_UNLEASHED: StringName = &"bide_unleashed"
const RAGE_BUILDING: StringName = &"rage_building"
const FUTURE_SIGHT_SET: StringName = &"future_sight_set"
const FUTURE_SIGHT_HIT: StringName = &"future_sight_hit"
const COINS_SCATTERED: StringName = &"coins_scattered"
const TRANSFORMED: StringName = &"transformed"
## Mimic and Sketch both replace their own slot with the opponent's last move,
## but only Sketch persists after battle. Separate events keep their two source
## lines distinct in the battle screen.
const MIMIC_LEARNED: StringName = &"mimic_learned"
const SKETCHED_MOVE: StringName = &"sketched_move"
## Conversion and Conversion2 both print `TransformedTypeText` after replacing
## both of the user's active type bytes.
const TYPE_CHANGED: StringName = &"type_changed"

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
## names the item rather than the effect. This is `HungOnText`; Endure's own line
## is [constant ENDURED_HIT], and the two are separate texts for separate
## reasons, so neither stands in for the other.
const ENDURED: StringName = &"endured"

## Protect and Detect: `ProtectedItselfText` when the flag goes up, and
## `ProtectingItselfText` on every move it then turns away, which is printed
## ahead of that move's own [constant MISSED].
const PROTECTED_ITSELF: StringName = &"protected_itself"
const PROTECTING_ITSELF: StringName = &"protecting_itself"

## Endure: `BracedItselfText` when the flag goes up and `EnduredText` on each hit
## it survives. A hit can be clamped more than once a turn, since nothing spends
## the flag.
const BRACED_ITSELF: StringName = &"braced_itself"
const ENDURED_HIT: StringName = &"endured_hit"

## Destiny Bond: `DestinyBondEffectText` when it is used, and `TookDownWithItText`
## when it collects. [code]target[/code] on the second is the Pokémon that went
## down holding it; [code]side[/code] is the attacker it takes with it, and the
## two [constant FAINTED] events follow in that order.
const DESTINY_BOND_SET: StringName = &"destiny_bond_set"
const TOOK_DOWN_WITH_IT: StringName = &"took_down_with_it"

## Whirlwind and Roar against a trainer: `DraggedOutText`, printed after the
## replacement is out and before it walks into any spikes.
##
## The cartridge's line is `<USER>`, which is the Pokémon that *used* the move
## rather than the one dragged out, in both directions. That is mirrored rather
## than corrected, so [code]side[/code] here is the user and the Pokémon dragged
## out is the one on [code]target[/code].
const DRAGGED_OUT: StringName = &"dragged_out"

## The same pair against a wild, where the battle ends instead:
## `FledInFearText` for Roar and `BlownAwayText` for Whirlwind, told apart by the
## move number. [code]target[/code] is whoever left, which is the wild when the
## player used it and the player's own Pokémon when the wild did.
const FLED_IN_FEAR: StringName = &"fled_in_fear"
const BLOWN_AWAY: StringName = &"blown_away"

## `FledFromBattleText`: Teleport, which takes its own user out rather than the
## other side. Named for `<USER>`, so [code]side[/code] is who left.
const FLED_FROM_BATTLE: StringName = &"fled_from_battle"

## Foresight and Lock On, whose flags sit on [code]target[/code] rather than on
## the Pokémon that used the move. `TookAimText` names only the aimer, which is
## why [constant TOOK_AIM] carries nothing beyond the side.
const IDENTIFIED_SET: StringName = &"identified_set"
const TOOK_AIM: StringName = &"took_aim"

## Spite, carrying the [code]slot[/code] drained, the [code]move[/code] in it and
## the [code]amount[/code] taken, which is the number `SpiteEffectText` prints.
const PP_REDUCED: StringName = &"pp_reduced"

## Pain Split, which names neither Pokémon. Both sides' health is on the event
## because both moved: [code]hp[/code] is the user's and [code]target_hp[/code] the
## other's.
const SHARED_PAIN: StringName = &"shared_pain"

## Thief, carrying the [code]item[/code] that moved. `StoleText` names the thief
## and the item and calls the loser "its foe", so nothing else is needed.
const STOLE_ITEM: StringName = &"stole_item"

## `BeatUpAttackText`, once per party member Beat Up sends in. [code]index[/code]
## is that member's party slot, or -1 for a wild Pokémon, which has no party and
## swings once as itself.
const BEAT_UP_ATTACK: StringName = &"beat_up_attack"

## Rain Dance, Sunny Day and Sandstorm. [code]weather[/code] on all four is the
## [Gen2Weather] value, so a screen names it without being told twice.
## [constant WEATHER_CONTINUES] is the line printed on every turn the weather
## survives, which is the same turn a Sandstorm's damage lands on.
const WEATHER_STARTED: StringName = &"weather_started"
const WEATHER_CONTINUES: StringName = &"weather_continues"
const WEATHER_ENDED: StringName = &"weather_ended"
const HURT_BY_SANDSTORM: StringName = &"hurt_by_sandstorm"

## Reflect, Light Screen and Safeguard going up and running out.
## [code]screen[/code] on all three is the [Gen2Screens] flag, so one pair of
## events covers the three moves. [constant SCREEN_SET] carries the side that put
## it up, which is also the side it protects; [constant SCREEN_FADED] the side it
## is leaving. [constant SAFEGUARD_PROTECTED] is `BattleCommand_CheckSafeguard`'s
## own line, the one a status move gets when it is refused outright rather than
## quietly, and it carries the `target` it failed against.
const SCREEN_SET: StringName = &"screen_set"
const SCREEN_FADED: StringName = &"screen_faded"
const SAFEGUARD_PROTECTED: StringName = &"safeguard_protected"

## Perish Song. [constant PERISH_SONG_STARTED] is `StartPerishText`, which names
## both Pokémon rather than either side, so its [code]side[/code] is only whoever
## sang. [constant PERISH_COUNT] carries the [code]side[/code] it is counting down
## and the [code]count[/code] just reached, including the zero that kills, since
## `HandlePerishSong` prints on every tick.
const PERISH_SONG_STARTED: StringName = &"perish_song_started"
const PERISH_COUNT: StringName = &"perish_count"

## A trainer spent one of its two items on whoever it has out. [code]item[/code]
## is what was spent and [code]effect[/code] is [method Gen2AIItems.apply]'s own
## answer, so a screen can follow the bar or the stage without asking the battle
## again. The cartridge prints one line for all thirteen ("<TRAINER> used ITEM on
## <MON>"), which is why there is one event rather than thirteen.
const TRAINER_USED_ITEM: StringName = &"trainer_used_item"

## The heal family. [constant HP_RESTORED] carries the user's `hp` and `max_hp`
## so a screen moves the bar without reading the battle back;
## [constant HP_ALREADY_FULL] is `BattleCommand_Heal`'s own refusal, which costs
## the turn. Rest's two lines are separate events rather than one with a flag,
## because the cartridge chooses between them on whether there was a status to
## clear and a screen should not have to know that rule.
const HP_RESTORED: StringName = &"hp_restored"
const HP_ALREADY_FULL: StringName = &"hp_already_full"
const WENT_TO_SLEEP: StringName = &"went_to_sleep"
const RESTED: StringName = &"rested"

## Heal Bell, whose text names nobody: `BellChimedText` is one line about a bell
## and the party it cleared is the acting side's.
const BELL_CHIMED: StringName = &"bell_chimed"

## Splash, and the one line it exists to print.
const NOTHING_HAPPENED: StringName = &"nothing_happened"

## Magnitude, which says which of the seven it rolled before it lands.
## [code]magnitude[/code] is the number in the line, 4 to 10, not the power.
const MAGNITUDE: StringName = &"magnitude"

## Present's fourth row against a target that is already at full health.
## [code]target[/code] is who refused, since `PresentFailedText` names them.
const PRESENT_REFUSED: StringName = &"present_refused"

## A missed Jump Kick or Hi Jump Kick, which costs its user an eighth of the
## damage it would have dealt. Carries the user's own `hp` and `max_hp`, the way
## [constant RECOIL] does, so a screen moves the bar without asking again.
const CRASHED: StringName = &"crashed"

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

## Substitute. The two refusals are separate events because the cartridge chooses
## between `HasSubstituteText` and `TooWeakSubText` on which precondition failed.
## The last two name the Pokémon behind the doll and carry no amount, since
## `SubTookDamageText` reports no number and the real health never moved.
const SUBSTITUTE_MADE: StringName = &"substitute_made"
const SUBSTITUTE_ALREADY: StringName = &"substitute_already"
const SUBSTITUTE_TOO_WEAK: StringName = &"substitute_too_weak"
const SUBSTITUTE_TOOK_DAMAGE: StringName = &"substitute_took_damage"
const SUBSTITUTE_FADED: StringName = &"substitute_faded"

## Leech Seed, on the Pokémon that was seeded rather than the one that seeded it.
## [constant LEECH_SEED_SAPPED] carries the healed side under `to`, `to_amount`,
## `to_hp` and `to_max_hp`, since one event moves health across the field.
const WAS_SEEDED: StringName = &"was_seeded"
const LEECH_SEED_SAPPED: StringName = &"leech_seed_sapped"

## Nightmare and Curse, both quarters and both on the sufferer.
## [constant CURSE_SET] carries the user's own `hp` after the half it cut.
const NIGHTMARE_STARTED: StringName = &"nightmare_started"
const HURT_BY_NIGHTMARE: StringName = &"hurt_by_nightmare"
const CURSE_SET: StringName = &"curse_set"
const HURT_BY_CURSE: StringName = &"hurt_by_curse"

## Spikes, which are field state on the side they were scattered onto.
const SPIKES_SET: StringName = &"spikes_set"
const HURT_BY_SPIKES: StringName = &"hurt_by_spikes"

## `BattleCommand_ClearHazards`' own three lines, all about the user's own side.
## [constant RELEASED_BY] is not [constant RELEASED_FROM_TRAP]: `HandleWrap`'s
## release names the move that let go and this one names the Pokémon that spun
## out of it, so the two texts are two events.
const SHED_LEECH_SEED: StringName = &"shed_leech_seed"
const BLEW_SPIKES: StringName = &"blew_spikes"
const RELEASED_BY: StringName = &"released_by"

## `EvadedText`, which only `BattleCommand_LeechSeed` prints. Not
## [constant MISSED], which is `GetFailureResultText`'s own line.
const EVADED: StringName = &"evaded"

## A stat drop blocked by the target's own Mist. Not [constant STAT_CHANGE_FAILED]:
## the cartridge prints a line of its own ("It's protected by mist!") rather
## than the generic "won't go any lower" a drop already at its floor gets, and a
## screen that read this as the generic failure would say the wrong thing.
const MIST_PROTECTED: StringName = &"mist_protected"

## `PlayFXAnimID`: one animation for the screen to spend frames on.
##
## The engine has resolved by the time the screen draws, so this sits at its own
## index in the returned list and the ordering stays the cartridge's rather than
## the screen's, the same shape [Gen2HpBarAnimation] already has.
##
## Carries `index` (`wFXAnimID`), `param` (`wBattleAnimParam`), `after_anim`
## (`wBattleAfterAnim`, zero for none), `enemy_turn` (`hBattleTurn`),
## `effectiveness` (`wTypeModifier`, which `PlayHitSound` reads) and
## `restore_user_pic`, the `AppearUserLowerSub` that follows Fly and Dig.
const ANIMATION: StringName = &"animation"

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
## A trainer reaching into its bag, which is `AI_TryItem`'s own action. It costs
## the turn and is settled ahead of it: `AI_SwitchOrTryItem` sets
## `wEnemyGoesFirst`, so the item lands before the player's move whatever the
## speeds say. Only the enemy ever uses one; the player's pack is the overworld's.
const ACTION_ITEM: StringName = &"item"

## `wBattleType`. Only the values `TryToRunAwayFromBattle` branches on are named;
## everything else reaches the ordinary speed check.
const BATTLETYPE_NORMAL: int = 0
const BATTLETYPE_DEBUG: int = 2
const BATTLETYPE_CONTEST: int = 6
const BATTLETYPE_FORCESHINY: int = 7
## What TreeMonEncounter writes before a headbutt battle. CheckSleepingTreeMon
## is the only thing that reads it.
const BATTLETYPE_TREE: int = 8
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
	Gen2MoveEffect.PROTECT: 3,
	Gen2MoveEffect.ENDURE: 3,
	0x67: 2,  # Quick Attack, Extreme Speed, Mach Punch
	Gen2MoveEffect.FORCE_SWITCH: 0,
	Gen2MoveEffect.COUNTER: 0,
	Gen2MoveEffect.MIRROR_COAT: 0,
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

## `wPlayerScreens`/`wEnemyScreens` and the three counters beside each, keyed by
## side. Field state, not Pokémon state: nothing clears these on a switch, so a
## Reflect outlives whoever put it up and only its own count ends it.
var screens: Dictionary = {PLAYER: Gen2Screens.NONE, ENEMY: Gen2Screens.NONE}
var light_screen_turns: Dictionary = {PLAYER: 0, ENEMY: 0}
var reflect_turns: Dictionary = {PLAYER: 0, ENEMY: 0}
var safeguard_turns: Dictionary = {PLAYER: 0, ENEMY: 0}

## `wTimeOfDay`, which only the three time-based heals read. It holds
## `MORN_F`/`DAY_F`/`NITE_F` (engine/rtc/rtc.asm, `GetTimeOfDay`), the bit
## indices 0/1/2 rather than the shifted flags, and those are the same three
## numbers [Gen2WorldPalette] already uses, so the overworld's value is written
## here unmapped. A battle nobody told stands at midday.
var time_of_day: int = Gen2WorldPalette.TIME_DAY

## `wEnemyTrainerItem1` and `wEnemyTrainerItem2`: the two items this trainer
## class may spend, one copy for the whole battle. Each is removed as it is
## spent, which is the cartridge's own `xor a; ld [de], a`. Empty for a wild
## battle and for any class carrying `NO_ITEM` twice.
var enemy_items: Array[int] = []

## `wPlayerUsedMoves`: the distinct moves the Pokémon the player currently has
## out has thrown, oldest first, which is the only thing the switch AI has to go
## on about what it is facing. `NewBattleMonStatus` clears it on every player
## send-out, so it describes the Pokémon rather than the battle, and
## `UpdateUsedMoves` keeps at most four, dropping the oldest.
var player_used_moves: Array[int] = []

## `wBattleAnimParam`, the animation's own input byte. Battle state rather than
## turn state, because it sits outside the run `ClearBattleAnims` zeroes: almost
## every animation command clears it, and the five multi-hit effects alternate
## its low bit from whatever the last hit left.
var battle_anim_param: int = 0

## `wPlayerJustGotFrozen` and `wEnemyJustGotFrozen`, keyed by side: whether this
## side was frozen during the turn now ending. `HandleDefrost` refuses to thaw
## one that was, so a freeze always costs its target at least the turn it landed
## on. Cleared at the top of every turn, the way `BattleTurn.loop` clears both
## bytes before either side chooses.
var _just_got_frozen: Dictionary = {PLAYER: false, ENEMY: false}

## `wEnemyGoesFirst`, written once per turn by `DetermineMoveOrder` and read by
## `CheckOpponentWentFirst`. It is exactly what [method order] already decides, so
## this is that answer kept rather than a second decision:
## [method opponent_went_first] is the `wEnemyGoesFirst XOR hBattleTurn` the three
## commands that ask are given.
var enemy_goes_first: bool = false

## Set once the player has run. The battle is over with no winner, which is the
## DRAW `wBattleResult` the cartridge writes.
var _fled: bool = false

## `wForcedSwitch`, the other way a battle ends in that same DRAW: Whirlwind or
## Roar in a wild battle blows one side out of it rather than switching anybody.
## `BattleTurn`'s `ld a, [wForcedSwitch] / jr nz, .quit` is what ends it, and
## `SetBattleDraw` beside it is why [method winner] answers nobody.
var _forced_out: bool = false
## Which side was blown out, for a screen that has to say who left.
var _forced_out_side: int = -1

## The half-run turn a Baton Pass stopped, as
## [code]{"acting": Array, "actions": Dictionary, "index": int}[/code], or empty
## when no turn is part way through. [method _run_turn] reads it and
## [method pass_to] is what lets it finish.
var _pending_turn: Dictionary = {}

## The side owing a Baton Pass target, or -1. `ForcePickSwitchMonInBattle` is a
## menu the player cannot back out of, so this is answered rather than optional
## and everything else is refused until it is.
var _pending_baton_pass: int = -1

## The side whose Pursuit already ran, in front of the switch it answered, or -1.
## `PursuitSwitch` writes `CANNOT_MOVE` over that side's move once it has, and
## `CheckTurn` reads the byte back and ends the turn, so the action it would have
## taken later this turn is spent.
var _pursuit_spent: int = -1

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

## `wPlayerFutureSightCount/Damage` and the enemy pair. Keyed by the side that
## foresaw the attack, so switching either active Pokémon leaves it intact and
## the eventual target is whoever is opposite when the count reaches one.
var _future_sight: Dictionary = {
	PLAYER: {"count": 0, "damage": 0},
	ENEMY: {"count": 0, "damage": 0},
}

## `wPayDayMoney`, capped to its three-byte storage. Awarding it belongs to the
## world completion boundary; the move command only scatters the coins.
var pay_day_money: int = 0

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


static func use_item(item: int) -> Dictionary:
	return {"type": ACTION_ITEM, "item": item}


## Fills [member enemy_items] from a trainer class's own attributes, the way
## `LoadEnemyMon`'s caller copies `TRNATTR_ITEM1` and `TRNATTR_ITEM2` into the
## two working slots. `NO_ITEM` is zero and is not carried.
func load_trainer_items(trainer_class: int) -> void:
	enemy_items = []
	if data == null or trainer_class <= 0:
		return
	var attributes: Dictionary = data.trainer_attributes(trainer_class)
	for key: String in ["item1", "item2"]:
		var item: int = int(attributes.get(key, 0))
		if item != 0:
			enemy_items.append(item)


func party(side: int) -> Gen2Party:
	return parties[side]


func mon(side: int) -> Gen2BattleMon:
	return party(side).active_mon()


func opponent_of(side: int) -> int:
	return ENEMY if side == PLAYER else PLAYER


## `BattleCommand_FreezeTarget`'s own tail, which writes the flag on the side it
## just froze so [method _tick_defrost] leaves that one alone this turn.
func mark_just_got_frozen(side: int) -> void:
	_just_got_frozen[side] = true


## Clears the damage that Counter and Mirror Coat are allowed to remember.
## Residual damage is deliberately not recorded: the cartridge's counter move
## reads the damage produced by the opponent's move, not end-of-turn status loss.
func reset_damage_taken() -> void:
	_last_damage_taken = {PLAYER: {}, ENEMY: {}}


## Adds the uncapped damage figure to the current action pair's saturating word.
## `BattleCommand_ApplyDamage.update_damage_taken` is an add-with-carry capped
## at $ffff, not an assignment. Bide accumulates the same raw word across its
## storage window.
func record_damage_taken(target: int, source: int, move_number: int, effect: int, amount: int) -> void:
	if amount <= 0 or target not in [PLAYER, ENEMY] or source not in [PLAYER, ENEMY]:
		return
	var previous: Dictionary = _last_damage_taken.get(target, {})
	var total: int = mini(int(previous.get("damage", 0)) + amount, 0xFFFF)
	_last_damage_taken[target] = {
		"damage": total,
		"source": source,
		"move": move_number,
		"effect": effect,
	}
	var target_mon: Gen2BattleMon = mon(target)
	if Gen2Substatus.has(target_mon.substatus, Gen2Substatus.BIDE):
		target_mon.bide_damage = mini(target_mon.bide_damage + amount, 0xFFFF)


func last_damage_taken(side: int) -> Dictionary:
	return _last_damage_taken.get(side, {})


func future_sight_pending(side: int) -> bool:
	return int((_future_sight.get(side, {}) as Dictionary).get("count", 0)) > 0


func schedule_future_sight(side: int, damage: int) -> bool:
	if side not in [PLAYER, ENEMY] or future_sight_pending(side):
		return false
	_future_sight[side] = {"count": 4, "damage": clampi(damage, 0, 0xFFFF)}
	return true


## A battle is lost when a whole party is down, not when the Pokémon that is out
## has fainted. One of those is a defeat and the other is a Pokémon to replace.
func is_over() -> bool:
	return _fled or _forced_out or party(PLAYER).is_wiped() or party(ENEMY).is_wiped()


## `wForcedSwitch` and `SetBattleDraw` together: Whirlwind or Roar blowing
## [param side] out of a wild battle, which ends it with nobody beaten.
##
## Nothing is switched and nobody faints, so both parties are left exactly as
## they stand; [method winner] answers null the way it does for a run.
func force_out(side: int) -> void:
	if is_over():
		return
	_forced_out = true
	_forced_out_side = side


## Which side Whirlwind or Roar blew out, or -1 if neither did.
func forced_out_side() -> int:
	return _forced_out_side


## Whether Whirlwind or Roar ended this battle by blowing a side out of it.
## Separate from [method has_fled] because the two print different lines and only
## one of them was the player's own decision, though both are the same DRAW.
func was_forced_out() -> bool:
	return _forced_out


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
	# `SetBattleDraw` makes Whirlwind and Roar the same answer for the same reason.
	if _fled or _forced_out:
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


## Which side owes a Baton Pass target, or -1. The turn is standing still until
## [method pass_to] answers, the same refusal-until-answered shape
## [method must_replace] uses, except that this one stops a turn part way rather
## than between two.
func awaiting_baton_pass() -> int:
	return _pending_baton_pass


## Answers a pending Baton Pass by sending [param index] out, then finishes the
## turn that was waiting on it and returns everything that happened after.
##
## Refuses an index the party would refuse anyway, leaving the question standing,
## because `ForcePickSwitchMonInBattle` redisplays its list rather than accepting
## a Pokémon that cannot come in.
func pass_to(index: int) -> Array:
	var side: int = _pending_baton_pass
	if side < 0 or not party(side).can_send_out(index):
		return []

	var events: Array = []
	_pending_baton_pass = -1
	events.append_array(baton_pass_send_out(side, index))
	_close_turn_bracket(side, (_pending_turn["actions"] as Dictionary)[side])
	_pending_turn["index"] = int(_pending_turn["index"]) + 1
	return _run_turn(events)


## Stops the turn and asks [param side] for a Baton Pass target.
## [method Gen2EffectCommands._baton_pass] is the only caller.
func request_baton_pass(side: int) -> void:
	_pending_baton_pass = side


## `FindMonInOTPartyToSwitchIntoBattle`, which `EnemySwitch_SetMode` reaches
## because Baton Pass zeroes `wEnemySwitchMonIndex` rather than naming anybody:
## the AI's own type-matchup pick, asked without asking whether it wants to
## switch at all, since the move has already decided that.
func baton_pass_target(side: int) -> int:
	if side == ENEMY:
		return Gen2AISwitch.pick_target(self)
	return party(side).first_healthy()


## `PassedBattleMonEntrance` and the enemy's `EnemySwitch_SetMode`: an entrance
## that keeps what it is handed.
##
## Neither calls `NewBattleMonStatus` or resets the stat levels, which is the
## only difference from [method send_out] and the only reason Baton Pass exists.
## The state is captured before the switch and put back after it, so the Pokémon
## walking back to its ball still loses everything, exactly as it would on the
## cartridge where none of it was ever its own.
func baton_pass_send_out(side: int, index: int) -> Array:
	var passed: Dictionary = mon(side).capture_passed_state()
	var events: Array = send_out(side, index, -1, true)
	if events.is_empty():
		return events
	mon(side).apply_passed_state(passed)
	_reset_baton_pass_status(side)
	return events


## `ResetBatonPassStatus`: the five things a pass does not carry.
##
## Nightmare is the odd one and is easy to get backwards. The check runs after
## the entrance, so the sleep it reads is the *arriving* Pokémon's, not the one
## that left: a Nightmare survives a pass only into somebody already asleep.
##
## Attraction and the wrap counters are cleared on *both* sides, since the
## Pokémon that was loved or bound is not on the field any more either.
func _reset_baton_pass_status(side: int) -> void:
	var arriving: Gen2BattleMon = mon(side)
	if not Gen2Status.is_asleep(arriving.status):
		arriving.substatus &= ~Gen2Substatus.NIGHTMARE

	arriving.disabled_slot = -1
	arriving.disable_turns = 0

	mon(PLAYER).substatus &= ~Gen2Substatus.ATTRACTED
	mon(ENEMY).substatus &= ~Gen2Substatus.ATTRACTED

	# `SUBSTATUS_TRANSFORMED` goes with these two and has nothing to clear yet.
	arriving.substatus &= ~Gen2Substatus.ENCORED
	arriving.encored_slot = -1
	arriving.encore_turns = 0

	arriving.last_move_used = 0

	for each: int in [PLAYER, ENEMY]:
		mon(each).trapped_turns = 0
		mon(each).trapping_move = 0


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
##
## [param dragged_by] is the side that used Whirlwind or Roar, or -1 for an
## ordinary switch. It exists because `DraggedOutText` is printed between
## `ForceEnemySwitch` and `SpikesDamage`, so the line has to land inside this
## method rather than around it.
func send_out(
	side: int, index: int, dragged_by: int = -1, preserve_counter_moves: bool = false
) -> Array:
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
	if not preserve_counter_moves:
		# NewBattleMonStatus/NewEnemyMonStatus clear both counter-move words.
		mon(PLAYER).last_counter_move = 0
		mon(ENEMY).last_counter_move = 0
	# `BreakAttraction`, which every entrance calls and which clears the flag on
	# *both* sides rather than only the incoming Pokémon's: whoever the Pokémon
	# that left was in love with is not on the field any more either.
	mon(PLAYER).substatus &= ~Gen2Substatus.ATTRACTED
	mon(ENEMY).substatus &= ~Gen2Substatus.ATTRACTED
	# `NewBattleMonStatus`, which clears the used-move list beside the rest of
	# the incoming Pokémon's volatile state. The enemy's send-out leaves it
	# alone: the list describes what the player has shown, not what it is facing.
	if side == PLAYER:
		player_used_moves = []

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
	if dragged_by >= 0:
		events.append({"type": DRAGGED_OUT, "side": dragged_by, "target": side})
	_spikes_damage(side, events)
	return events


## `SpikesDamage`, which every entrance runs behind its own `SetPlayerTurn` or
## `SetEnemyTurn`: the spikes read are the ones lying on the side walking in.
##
## Every reachable call site is an entrance this method already is
## (`DetermineMoveOrder`, `PlayerPartyMonEntrance`, `EnemyPartyMonEntrance`,
## `EnemyMonEntrance`, `ForcePlayerMonChoice`). `DoBattle`'s two run before the
## move can have been used, and `BattleCommand_ForceSwitch`'s two belong to an
## effect this engine does not have yet.
func _spikes_damage(side: int, events: Array) -> void:
	if not Gen2Screens.has(screens[side], Gen2Screens.SPIKES):
		return

	var entering: Gen2BattleMon = mon(side)
	if entering.is_fainted() or Gen2Screens.spikes_spare(entering.types()):
		return

	var taken: int = entering.take_damage(Gen2Screens.spikes_damage(entering.max_hp()))
	events.append({
		"type": HURT_BY_SPIKES, "side": side, "amount": taken,
		"hp": entering.hp, "max_hp": entering.max_hp(),
	})
	if entering.is_fainted():
		events.append({"type": FAINTED, "side": side})


## `UpdateUsedMoves`: a move the player throws is remembered once, and the list
## holds four. A fifth distinct move drops the oldest rather than being ignored,
## which is why this is a queue rather than a set with a cap.
func _record_used_move(move_number: int) -> void:
	if move_number == 0 or player_used_moves.has(move_number):
		return
	player_used_moves.append(move_number)
	if player_used_moves.size() > Gen2BattleMon.MAX_MOVES:
		player_used_moves.remove_at(0)


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
	# A turn already part way through cannot be started again: the one standing
	# is finished by [method pass_to] and by nothing else.
	if _pending_baton_pass >= 0:
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
	_just_got_frozen = {PLAYER: false, ENEMY: false}

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
	enemy_goes_first = int(acting[0]) == ENEMY
	_pursuit_spent = -1
	_pending_turn = {"acting": acting, "actions": actions, "index": 0}
	return _run_turn(events)


## The per-side loop and the end-of-turn tail, run from wherever the turn last
## stopped. Ordinarily that is the beginning and it runs to the end in one call.
##
## Baton Pass is the one thing that stops it part way: the cartridge opens a
## switch menu inside `DoPlayerTurn` and waits, so the turn is left standing with
## its remaining half in [member _pending_turn] until [method pass_to] answers.
func _run_turn(events: Array) -> Array:
	var acting: Array = _pending_turn["acting"]
	var actions: Dictionary = _pending_turn["actions"]

	while int(_pending_turn["index"]) < acting.size():
		var side: int = int(acting[int(_pending_turn["index"])])
		var action: Dictionary = actions[side]
		var action_event_start: int = events.size()
		var moving: bool = not (_is_run(action) or _is_switch(action) or _is_item(action))
		# The faint check is the source's own `HasPlayerFainted`/`HasEnemyFainted`
		# between the two halves of the turn, and it gates the whole of the second
		# half rather than only its move. It is asked before the bracket below
		# opens for that reason. A switching or item-using side is always
		# [method order]'s first, so this is only ever asked of a move.
		if moving and (mon(side).is_fainted() or mon(opponent_of(side)).is_fainted()):
			break
		_open_turn_bracket(side, action)
		if not moving:
			# `.reset_rage` for a switch and `.reset_bide` for an item or a failed
			# run, both of which fall into `.locked_in`'s unconditional zeroing.
			# `AI_TryItem` does the same on the enemy's side. -1 is no move's
			# effect, so both counters go.
			_reset_action_counters(side, -1)
		if _is_switch(action):
			_pursuit_before_switch(side, actions, events)
			events.append_array(send_out(side, int(action.get("index", -1))))
		elif _is_item(action):
			_use_trainer_item(side, int(action.get("item", 0)), events)
		elif moving and side != _pursuit_spent:
			var slot: int = effective_slot(side, int(action.get("slot", 0)))
			_act(side, slot, move_for(side, slot), events)
			_report_unannounced_action_faints(events, action_event_start)
		# The move asked for a Baton Pass target and nothing behind it can happen
		# until there is one, the bracket around it included.
		if _pending_baton_pass >= 0:
			return events
		_close_turn_bracket(side, action)
		# `ld a, [wForcedSwitch] / and a / ret nz`, which `Battle_PlayerFirst` and
		# `Battle_EnemyFirst` each ask twice, behind each side's own wrapper. A
		# Pokémon blown or teleported out of a wild battle ends the turn where it
		# stands: no second move, and none of the end-of-turn tail below.
		if was_forced_out():
			_pending_turn = {}
			events.append({"type": OVER, "winner": winner()})
			return events
		_pending_turn["index"] = int(_pending_turn["index"]) + 1

	_pending_turn = {}
	_residual_damage(acting, events)
	_tick_future_sight(events)
	_tick_weather(events)
	_tick_wrap(events)
	_tick_perish(events)
	_tick_held_items(events)
	_tick_encore(acting, events)
	_award_experience(events)

	if is_over():
		events.append({"type": OVER, "winner": winner()})
	return events


## Core checks both battlers after every action, independently of whether that
## effect list carried `checkfaint`. Keep effect-owned ordering where an event
## already exists; fill only the missing report.
func _report_unannounced_action_faints(events: Array, since: int) -> void:
	for side: int in [PLAYER, ENEMY]:
		if not mon(side).is_fainted():
			continue
		var reported: bool = false
		for index: int in range(since, events.size()):
			var event: Dictionary = events[index]
			if StringName(event.get("type", &"")) == FAINTED and int(event.get("side", -1)) == side:
				reported = true
				break
		if not reported:
			events.append({"type": FAINTED, "side": side})


## `HandleFutureSight`, player then enemy outside link battles. The count is
## decremented before testing one, and the stored base damage receives its
## spread only on impact. The ordinary hit and apply commands retain Protect,
## Substitute, Focus Band, faint and Rage interactions.
func _tick_future_sight(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		var pending: Dictionary = _future_sight[side]
		var count: int = int(pending.get("count", 0))
		if count <= 0:
			continue
		count -= 1
		pending["count"] = count
		if count != 1:
			continue
		pending["count"] = 0
		if mon(side).is_fainted() or mon(opponent_of(side)).is_fainted():
			continue
		events.append({"type": FUTURE_SIGHT_HIT, "side": side, "target": opponent_of(side)})
		var move: Dictionary = data.move(Gen2MoveEffect.FUTURE_SIGHT_MOVE)
		var turn: Gen2Turn = Gen2Turn.create(
			self, side, -1, Gen2MoveEffect.FUTURE_SIGHT_MOVE, move, events
		)
		turn.damage = int(pending.get("damage", 0))
		for command: StringName in [
			Gen2EffectCommands.DAMAGE_VARIATION, Gen2EffectCommands.CHECK_HIT,
			Gen2EffectCommands.MOVE_ANIM_NO_SUB, Gen2EffectCommands.APPLY_DAMAGE,
			Gen2EffectCommands.CHECK_FAINT,
		]:
			if turn.ended:
				break
			Gen2EffectCommands.run(command, turn)


## `wPlayerIsSwitching` and `wEnemyIsSwitching`: whether [param side] is recalling
## a Pokémon this turn. Both are zeroed at the top of `BattleTurn`, which is what
## rebuilding [member _pending_turn] every turn already does.
##
## An enemy item is not a switch here even though [method order] treats it as one
## for ordering: `AI_TryItem` sets no flag, only `AI_Switch` does, and
## [method Gen2EffectCommands._pursuit] is the reader.
func is_switching(side: int) -> bool:
	if _pending_turn.is_empty():
		return false
	var actions: Dictionary = _pending_turn["actions"]
	return _is_switch(actions.get(side, {}))


## `PursuitSwitch`, which the cartridge calls from `BattleMonEntrance` and from
## `AI_Switch`, both in front of the recall: a side that chose Pursuit takes its
## whole turn now, against the Pokémon on its way out, and then has nothing left
## to spend later in the turn.
##
## No speed or priority test. The switch is settled first whatever the speeds, so
## the pursuer always gets the early hit; `EFFECT_PURSUIT` carries no priority
## entry and does not need one.
##
## The effect byte is read here rather than inside a command because the trigger
## belongs to the byte rather than to the list, the same way
## [constant EFFECT_PRIORITIES] reads bytes from outside every list.
##
## Called from a chosen switch only. The cartridge's two call sites are the two
## entrances a switch action reaches; `PassedBattleMonEntrance`,
## `PlayerPartyMonEntrance` and `ForcePlayerMonChoice` call neither, so a Baton
## Pass and a post-faint replacement are not pursued.
func _pursuit_before_switch(side: int, actions: Dictionary, events: Array) -> void:
	var other: int = opponent_of(side)
	var action: Dictionary = actions.get(other, {})
	if _is_switch(action) or _is_run(action) or _is_item(action):
		return
	var slot: int = effective_slot(other, int(action.get("slot", 0)))
	var move_number: int = move_for(other, slot)
	if int(data.move(move_number).get("effect", -1)) != Gen2MoveEffect.PURSUIT:
		return

	_act(other, slot, move_number, events)
	_pursuit_spent = other


## `CheckOpponentWentFirst`, which is `wEnemyGoesFirst XOR hBattleTurn`: whether
## the Pokémon opposite [param side] has already moved this turn.
##
## Protect and Endure both fail outright on a yes, which is what makes two
## Protects in one turn a question of speed and what makes a Protect behind a
## switch fail: a switching side is `.player_first` or `wEnemyGoesFirst`, so the
## other side is always second.
func opponent_went_first(side: int) -> bool:
	return (side == PLAYER) == enemy_goes_first


## `EndUserDestinyBond`, the front half of the wrapper each side's action runs
## inside (`PlayerTurn_EndOpponentProtectEndureDestinyBond`,
## engine/battle/core.asm). It is in front of `DoPlayerTurn`, so a Pokémon that
## cannot move still loses the bond it put up.
func _open_turn_bracket(side: int, action: Dictionary) -> void:
	if not _brackets_turn(side, action):
		return
	mon(side).substatus &= ~Gen2Substatus.DESTINY_BOND


## `EndOpponentProtectEndureDestinyBond`, the back half: the three flags that only
## an opposing action ends. A Protect therefore covers exactly one opposing
## action, and outlives the turn it was used on when it was used going second.
func _close_turn_bracket(side: int, action: Dictionary) -> void:
	if not _brackets_turn(side, action):
		return
	var other: Gen2BattleMon = mon(opponent_of(side))
	other.substatus &= ~(
		Gen2Substatus.PROTECT | Gen2Substatus.ENDURE | Gen2Substatus.DESTINY_BOND
	)


## Whether an action runs inside that wrapper, and the two sides do not agree.
##
## The player's runs on everything it spends the turn on: `Battle_PlayerFirst` and
## `Battle_EnemyFirst` both call `PlayerTurn_End...` unconditionally, and
## `DoPlayerTurn`'s own `ret nz` for a switch, an item or a failed run skips only
## the move, not the two clears around it. The enemy's is skipped outright when
## `AI_SwitchOrTryItem` answers, which is the `.switch_item` and
## `.switched_or_used_item` jump past `EnemyTurn_End...`.
##
## So a Protect the player put up survives an enemy switch and blocks the move
## after it, where an enemy's does not survive a player switch.
func _brackets_turn(side: int, action: Dictionary) -> bool:
	return side == PLAYER or not (_is_switch(action) or _is_item(action))


## `ParsePlayerAction` and `ParseEnemyAction`: the two counters a chain keeps only
## while the chain is the move being used. Both are zeroed unless this move is the
## one that feeds them, and Protect and Endure share a counter, so alternating the
## two does not reset it.
##
## The source has a second, unconditional reset behind `CheckPlayerLockedIn` and
## `CheckEnemyLockedIn`, for a Pokémon locked into a recharge, a charge, a rampage
## or a Rollout. It is not modelled separately because it can never disagree: none
## of Fury Cutter, Protect and Endure sets any of those four flags, so a locked-in
## Pokémon's forced move always fails the effect test below anyway.
##
## [param effect] is the move's own byte rather than [method Gen2Turn.effect],
## which a broken Substitute can overwrite part way through a move that has
## already been counted.
func _reset_action_counters(side: int, effect: int) -> void:
	var actor: Gen2BattleMon = mon(side)
	if effect != Gen2MoveEffect.FURY_CUTTER:
		actor.fury_cutter_count = 0
	if effect != Gen2MoveEffect.PROTECT and effect != Gen2MoveEffect.ENDURE:
		actor.protect_count = 0
	if effect != Gen2MoveEffect.BIDE:
		actor.substatus &= ~Gen2Substatus.BIDE
		actor.bide_turns = 0
		actor.bide_damage = 0
		actor.bide_move = 0
	if effect != Gen2MoveEffect.RAGE:
		actor.substatus &= ~Gen2Substatus.RAGE
		actor.rage_count = 0


## Both sides use a move slot, which is the common case and the whole of a battle
## that has one Pokémon a side.
func take_turn(player_slot: int, enemy_slot: int) -> Array:
	return take_actions(use_move(player_slot), use_move(enemy_slot))


## `ResidualDamage`: what a burn, a poison, a Leech Seed, a Nightmare and a Curse
## take from each side at the end of the turn, in that order and in the order the
## sides acted.
##
## After both moves rather than after each, skipping whoever is already down, so
## a Pokémon that faints to its burn does so here rather than mid-move.
##
## The four steps are four routines' worth of `HasUserFainted` between them: a
## Pokémon that goes down to its poison pays neither the seed nor the nightmare.
func _residual_damage(acting: Array, events: Array) -> void:
	for side: int in acting:
		if mon(side).is_fainted():
			continue
		_residual_status(side, events)
		if mon(side).is_fainted():
			continue
		_residual_leech_seed(side, events)
		if mon(side).is_fainted():
			continue
		_residual_nightmare(side, events)
		if mon(side).is_fainted():
			continue
		_residual_curse(side, events)


## A running [member Gen2BattleMon.toxic_counter] means Toxic, which ramps
## instead of taking the flat eighth. The counter rises here, once a turn, so the
## turn it was inflicted counts as the first.
func _residual_status(side: int, events: Array) -> void:
	var current: Gen2BattleMon = mon(side)
	if not Gen2Status.has(current.status, Gen2Status.BURN | Gen2Status.POISON):
		return

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


## An eighth off the seeded Pokémon and onto the one across from it, capped by
## `RestoreHP`. What is healed is what `SubtractHP` left in `bc`: the eighth
## normally, and the seeded Pokémon's whole remaining health when the eighth
## would have taken it below zero, so
## [method Gen2BattleMon.take_damage]'s own answer is the figure to hand on.
##
## A fainted receiver cannot happen on the cartridge, where `ResidualDamage` runs
## behind a faint check inside each side's own move; it can here, because this
## runs once after both. Nothing is moved in that case.
func _residual_leech_seed(side: int, events: Array) -> void:
	var current: Gen2BattleMon = mon(side)
	if not Gen2Substatus.has(current.substatus, Gen2Substatus.LEECH_SEED):
		return

	var sapper: Gen2BattleMon = mon(opponent_of(side))
	var taken: int = current.take_damage(Gen2Substatus.leech_seed_damage(current.max_hp()))
	var healed: int = 0 if sapper.is_fainted() else sapper.heal(taken)
	events.append({
		"type": LEECH_SEED_SAPPED,
		"side": side,
		"amount": taken,
		"hp": current.hp,
		"max_hp": current.max_hp(),
		"to": opponent_of(side),
		"to_amount": healed,
		"to_hp": sapper.hp,
		"to_max_hp": sapper.max_hp(),
	})
	if current.is_fainted():
		events.append({"type": FAINTED, "side": side})


## Nothing here asks whether the sufferer is still asleep, because waking is what
## clears the flag.
func _residual_nightmare(side: int, events: Array) -> void:
	var current: Gen2BattleMon = mon(side)
	if not Gen2Substatus.has(current.substatus, Gen2Substatus.NIGHTMARE):
		return

	var taken: int = current.take_damage(Gen2Substatus.quarter_damage(current.max_hp()))
	events.append({
		"type": HURT_BY_NIGHTMARE, "side": side, "amount": taken,
		"hp": current.hp, "max_hp": current.max_hp(),
	})
	if current.is_fainted():
		events.append({"type": FAINTED, "side": side})


func _residual_curse(side: int, events: Array) -> void:
	var current: Gen2BattleMon = mon(side)
	if not Gen2Substatus.has(current.substatus, Gen2Substatus.CURSE):
		return

	var taken: int = current.take_damage(Gen2Substatus.quarter_damage(current.max_hp()))
	events.append({
		"type": HURT_BY_CURSE, "side": side, "amount": taken,
		"hp": current.hp, "max_hp": current.max_hp(),
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


## `HandlePerishSong`: one off each side's count, said out loud, and whoever
## reaches zero is finished where it stands.
##
## Behind [method _tick_wrap] and ahead of the leftovers block, which is where
## `HandleBetweenTurnEffects` calls it, and player first for the same reason
## every other handler here is: the order that reverses them is the link one.
##
## The line prints on every tick including the last, since `HandlePerishSong`
## decrements, prints, and only then looks at whether the count came out zero.
## The kill is `xor a` straight into the HP word rather than damage, so nothing
## about it is a sixteenth of anything and no held item can answer it.
func _tick_perish(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		var current: Gen2BattleMon = mon(side)
		if current.is_fainted():
			continue
		if not Gen2Substatus.has(current.substatus, Gen2Substatus.PERISH):
			continue

		current.perish_count -= 1
		events.append({"type": PERISH_COUNT, "side": side, "count": current.perish_count})
		if current.perish_count > 0:
			continue

		current.substatus &= ~Gen2Substatus.PERISH
		current.hp = 0
		events.append({"type": FAINTED, "side": side})


## The leftovers block of `HandleBetweenTurnEffects`: `HandleLeftovers`,
## `HandleMysteryberry` and then `HandleHealingItems`, after the wrap tick and
## before Encore.
##
## The three do not agree on an order. The first two are `SetPlayerTurn` then
## `SetEnemyTurn` reading `GetUserItem`, so the player is handled first; the
## third is the same two calls reading `GetOpponentItem`, so the enemy is.
## `HandleDefrost` runs between the second and the third and is not an item
## effect at all; `HandleSafeguard` and `HandleScreens` sit behind it in that
## order, and are not item effects either.
func _tick_held_items(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		_use_leftovers(side, events)
	for side: int in [PLAYER, ENEMY]:
		_use_pp_berry(side, events)
	_tick_defrost(events)
	_tick_safeguard(events)
	_tick_screens(events)
	for side: int in [ENEMY, PLAYER]:
		use_hp_berry(side, events)
		use_status_berry(side, events)
		use_confusion_berry(side, events)


## `HandleDefrost`: each frozen side thaws on its own roll at the end of a turn,
## which is the only thing that makes a Generation 2 freeze temporary. Without
## it a freeze lasts until a Flame Wheel, a Sacred Fire or an item, which is
## Generation 1's rule.
##
## Player first, then enemy: the branch that reverses them is the
## `USING_EXTERNAL_CLOCK` one, and this project has no link play. Nothing is
## rolled for a side that is not frozen, since `bit FRZ` comes before
## `BattleRandom`, so a battle with no freeze in it draws no randomness here.
func _tick_defrost(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		var current: Gen2BattleMon = mon(side)
		if not Gen2Status.has(current.status, Gen2Status.FREEZE):
			continue
		if bool(_just_got_frozen[side]):
			continue
		if not Gen2Status.rolls_thaw(rng):
			continue
		# `xor a / ld [wBattleMonStatus], a` clears the whole byte rather than
		# the bit, which is the same thing: a freeze is never on it with anything
		# else.
		current.status = Gen2Status.NONE
		events.append({"type": THAWED, "side": side})


## `HandleSafeguard`: one turn off each side's count, and the line when it runs
## out. Player first, then enemy, the same order [method _tick_defrost] uses and
## for the same reason: the branch that reverses them is the link one.
##
## The count is read only while the flag is up, so a side without a Safeguard
## rolls nothing and prints nothing.
func _tick_safeguard(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		if not Gen2Screens.has(screens[side], Gen2Screens.SAFEGUARD):
			continue
		safeguard_turns[side] = int(safeguard_turns[side]) - 1
		if int(safeguard_turns[side]) > 0:
			continue
		screens[side] &= ~Gen2Screens.SAFEGUARD
		safeguard_turns[side] = 0
		events.append({
			"type": SCREEN_FADED, "side": side, "screen": Gen2Screens.SAFEGUARD,
		})


## `HandleScreens`: Light Screen before Reflect on each side, which is the order
## `.TickScreens` tests the two bits in, and the player's side before the
## enemy's.
##
## Unlike Safeguard there is no shared count: `wPlayerLightScreenCount` and the
## Reflect count beside it are separate bytes, so a side can hold both at once
## and lose them on different turns.
func _tick_screens(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		for row: Array in [
			[Gen2Screens.LIGHT_SCREEN, light_screen_turns],
			[Gen2Screens.REFLECT, reflect_turns],
		]:
			var flag: int = int(row[0])
			var counts: Dictionary = row[1]
			if not Gen2Screens.has(screens[side], flag):
				continue
			counts[side] = int(counts[side]) - 1
			if int(counts[side]) > 0:
				continue
			screens[side] &= ~flag
			counts[side] = 0
			events.append({"type": SCREEN_FADED, "side": side, "screen": flag})


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


## Splits what [param defeated] is worth between everyone owed a share, then
## resets the participant set to whoever is left standing: the next enemy
## Pokémon, if the trainer has one, starts its own participant count fresh.
##
## `UpdateFaintedPlayerMon` awards in two passes when anything alive is holding
## an Exp. Share. The block is halved once, then that same halved block is split
## among the participants, and split again among the holders, so each group
## divides half of it. A Pokémon that both fought and holds one is in both
## passes and is awarded twice.
func _give_experience_for(defeated: Gen2BattleMon, events: Array) -> void:
	var participants: Array = (_participants[PLAYER] as Dictionary).keys()
	var holders: Array = _exp_share_holders()
	var halved: bool = not holders.is_empty()

	_award_share(defeated, participants, halved, false, events)
	_award_share(defeated, holders, halved, true, events)

	_participants[PLAYER] = {party(PLAYER).active: true}


## One of the two passes: the block divided among [param recipients], then handed
## to each of them that is still standing.
func _award_share(
	defeated: Gen2BattleMon, recipients: Array, halved: bool, by_exp_share: bool, events: Array
) -> void:
	if recipients.is_empty():
		return
	var block: Dictionary = Gen2Experience.shared_block(
		defeated.base_stat_exp_shape(), defeated.base_exp(), halved, recipients.size()
	)
	var award: int = Gen2Experience.award_for(
		defeated.level, int(block["base_exp"]), is_trainer_battle
	)
	var stat_gains: Dictionary = block["stats"]
	for index: int in recipients:
		var learner: Gen2BattleMon = party(PLAYER).at(int(index))
		if learner != null and not learner.is_fainted():
			_give_experience_to(learner, int(index), award, stat_gains, by_exp_share, events)


## Spends one of the trainer's two items, which costs the turn.
##
## The item is gone whether or not it changed anything: `AI_TryItem` clears the
## slot the moment a check said yes, and the checks are what decide that, not
## the effect. Bide, Fury Cutter, Protect, Rage and `wLastEnemyCounterMove` are
## cleared alongside it on the cartridge. The two counters are cleared by
## [method _reset_action_counters], which the caller runs for every action that is
## not a move; the counter move was already cleared by
## [method reset_damage_taken] at the top of this action pair; and Bide and Rage
## do not exist here yet.
func _use_trainer_item(side: int, item: int, events: Array) -> void:
	if item == 0:
		return
	enemy_items.erase(item)
	var user: Gen2BattleMon = mon(side)
	var effect: Dictionary = Gen2AIItems.apply(user, item)
	events.append({
		"type": TRAINER_USED_ITEM, "side": side, "item": item,
		"species": user.species, "effect": effect,
		"hp": user.hp, "max_hp": user.max_hp(),
	})


## `IsAnyMonHoldingExpShare`: every living party index carrying one, in party
## order. A fainted holder is skipped and does not count towards the split, the
## same test the routine makes before it looks at the item at all.
func _exp_share_holders() -> Array:
	var out: Array = []
	var party_side: Gen2Party = party(PLAYER)
	for index: int in party_side.size():
		var member: Gen2BattleMon = party_side.at(index)
		if member != null and not member.is_fainted() \
				and member.item == Gen2Experience.EXP_SHARE_ITEM:
			out.append(index)
	return out


func _give_experience_to(
	learner: Gen2BattleMon, index: int, award: int, stat_gains: Dictionary,
	by_exp_share: bool, events: Array
) -> void:
	learner.gain_exp(award)
	events.append({
		"type": EXP_GAINED, "side": PLAYER, "index": index,
		"species": learner.species, "amount": award, "exp": learner.exp,
		# Which of the two passes this came from. The cartridge prints the same
		# line either way; this is here so a Pokémon that is in both passes can
		# be told apart from one awarded twice for any other reason.
		"exp_share": by_exp_share,
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


static func _is_item(action: Dictionary) -> bool:
	return StringName(action.get("type", ACTION_MOVE)) == ACTION_ITEM


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
	if _is_switch(action) or _is_run(action) or _is_item(action):
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
	if Gen2Substatus.has(attacker.substatus, Gen2Substatus.BIDE) and attacker.bide_move != 0:
		return attacker.bide_move
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
	# An enemy item is `wEnemyGoesFirst` for the same reason an enemy switch is,
	# and both lose to a player switch, which was settled at menu time.
	var enemy_switching: bool = _is_switch(actions.get(ENEMY, {})) \
		or _is_item(actions.get(ENEMY, {}))
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

	_reset_action_counters(side, int(move.get("effect", -1)))

	var turn: Gen2Turn = Gen2Turn.create(self, side, slot, move_number, move, events)
	# The release turn of a two-turn move, or any Rollout/rampage continuation:
	# the PP was already spent on the first turn, and
	# [method Gen2EffectCommands._do_turn] reads this so it is not spent again.
	var active_substatus: int = mon(side).substatus
	turn.locked = (
		mon(side).charged_move == move_number
		or Gen2Substatus.has(active_substatus, Gen2Substatus.ROLLOUT)
		or Gen2Substatus.has(active_substatus, Gen2Substatus.RAMPAGING)
		or Gen2Substatus.has(active_substatus, Gen2Substatus.BIDE)
	) and move_number != 0

	if side == PLAYER:
		_record_used_move(move_number)

	# Whether the Pokémon can move at all is asked before the effect is looked up,
	# which is the cartridge's arrangement: every move goes through it, so no
	# sequence has to remember to include it.
	Gen2EffectCommands.run(Gen2EffectCommands.CHECK_STATUS, turn)
	_run_move_effect(turn)


## `ResetTurn`, used by Metronome, Mirror Move and Sleep Talk. A called command
## replaces the working move and starts its command list from the beginning,
## without running the once-per-action status gate again. A fresh [Gen2Turn]
## gives the called move a clean move-struct copy while retaining the acting
## side and the one shared event stream.
func _run_move_effect(turn: Gen2Turn, depth: int = 0) -> void:
	for command: StringName in Gen2MoveEffect.sequence_for(turn.effect()):
		if turn.ended:
			return
		Gen2EffectCommands.run(command, turn)
		if turn.called_move_number == 0:
			continue
		if depth >= 16:
			turn.emit(MOVE_FAILED)
			turn.end()
			return
		var number: int = turn.called_move_number
		var called_move: Dictionary = data.move(number)
		if called_move.is_empty():
			turn.emit(MOVE_FAILED)
			turn.end()
			return
		if turn.side == PLAYER:
			_record_used_move(number)
		var called_turn: Gen2Turn = Gen2Turn.create(
			self, turn.side, -1, number, called_move, turn.events
		)
		called_turn.called = true
		_run_move_effect(called_turn, depth + 1)
		return
