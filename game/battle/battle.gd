class_name Gen2Battle
extends RefCounted

## A battle: two parties, a turn at a time. Scene-free with randomness injected,
## so a whole battle can be fought in a test with no display.
##
## A turn answers with events carrying their own numbers, never a string:
## sentences, animation and draining bars are the screen's job. A side is a party
## and a wild encounter a party of one. A turn ending with somebody down says so
## through [method must_replace] and stands still until [method replace_fallen],
## the only entry point besides [method take_actions] that moves a battle on.

## Plain numbers rather than an enum: they are dictionary keys and event payloads
## throughout, and everything reading one compares it against these two.
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
## A multi-hit move's summary, once every planned hit has landed. A target that
## faints partway gets none, the loop ending the move first.
const HIT_TIMES: StringName = &"hit_times"
## A draining move healed the attacker off what it dealt.
const DRAINED: StringName = &"drained"
## A one-hit KO landed. Its own event rather than a flag on [constant HIT]: the
## cartridge shows neither a critical nor an effectiveness line, the damage
## having been multiplied by neither.
const OHKO: StringName = &"ohko"
## A status stopped a Pokémon moving, [code]reason[/code] being which:
## [code]&"sleep"[/code], [code]&"freeze"[/code], [code]&"paralysis"[/code],
## [code]&"flinch"[/code], [code]&"recharge"[/code].
const CANNOT_MOVE: StringName = &"cannot_move"
const WOKE_UP: StringName = &"woke_up"
## A freeze cleared, `side` being whoever thawed rather than whoever acted: a
## Flame Wheel, `BurnTarget`'s `Defrost`, or `HandleDefrost`'s roll.
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
## `SendOutMonText`'s four lines, chosen off the opponent's remaining HP: the
## `line` field of a player [constant SENT_OUT].
const SEND_OUT_GO: int = 0
const SEND_OUT_DO_IT: int = 1
const SEND_OUT_GO_FOR_IT: int = 2
const SEND_OUT_FOES_WEAK: int = 3
## `PlayStereoCry` behind an entrance: the cry `CheckFaintedFrzSlp` allows, on
## the entering side's own tracks. Silent on its own, so nothing is printed for
## it.
const CRY: StringName = &"cry"
## The player got away, `how` naming the branch: [code]&"battle_type"[/code] for
## the two that always escape, [code]&"item"[/code] for the Smoke Ball,
## [code]&"speed"[/code], [code]&"odds"[/code] and [code]&"roll"[/code].
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
## Never for [constant ENEMY]: `GiveExperiencePoints` reads the player's party
## alone, so a trainer's Pokémon are the reason and never the recipient.
const EXP_GAINED: StringName = &"exp_gained"
## The five stats in [constant Gen2Experience.STAT_EXP_KEYS], out of the block
## [constant EXP_GAINED] came from ([method Gen2Experience.shared_block]) and
## divided by the same count, but a base stat rather than a level figure.
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

## Disable, Attract, Encore, Mist and Focus Energy refuse for their own reasons
## rather than missing a roll ([constant MISSED]) or losing to a type
## ([constant NO_EFFECT]): the "but it failed!" the cartridge shares.
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

## Disable locked a slot and later let it go, [code]slot[/code] and
## [code]move[/code] being the target's. A Pokémon locked into the disabled move
## is refused through [constant CANNOT_MOVE]'s [code]&"disabled"[/code].
const DISABLE_INFLICTED: StringName = &"disable_inflicted"
const DISABLE_ENDED: StringName = &"disable_ended"

## Falling in love, [constant Gen2Substatus.ATTRACTED] until a switch. A turn it
## costs is [constant CANNOT_MOVE]'s [code]&"attract"[/code], the shape flinch
## and confusion use.
const ATTRACT_INFLICTED: StringName = &"attract_inflicted"

## Encore locked a slot, and later let it go, the same pair
## [constant DISABLE_INFLICTED] and [constant DISABLE_ENDED] are for Disable.
const ENCORE_INFLICTED: StringName = &"encore_inflicted"
const ENCORE_ENDED: StringName = &"encore_ended"

## What a held item gave back between turns. Leftovers has its own line
## ("recovered with"); [constant RECOVERED_USING_ITEM] covers the HP berry and the
## status berries, which share `UseOpponentItem`. [code]item[/code] is what did it,
## and on the consumable three what is no longer held.
const RECOVERED_WITH_ITEM: StringName = &"recovered_with_item"
const RECOVERED_USING_ITEM: StringName = &"recovered_using_item"
const RESTORED_PP: StringName = &"restored_pp"
const ITEM_HEALED_CONFUSION: StringName = &"item_healed_confusion"

## `HungOnText`: a Focus Band held the Pokémon on one hit point. The line names
## the item, which is why [code]item[/code] is on it. Endure's own line is
## [constant ENDURED_HIT] and neither text stands in for the other.
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

## `DestinyBondEffectText` when it is used and `TookDownWithItText` when it
## collects, where [code]target[/code] is the Pokémon that went down holding it
## and [code]side[/code] the attacker it takes with it, in that order.
const DESTINY_BOND_SET: StringName = &"destiny_bond_set"
const TOOK_DOWN_WITH_IT: StringName = &"took_down_with_it"

## Whirlwind and Roar against a trainer: `DraggedOutText`, after the replacement
## is out and before any spikes. The line is `<USER>` in both directions, mirrored
## rather than corrected, so [code]side[/code] is the user.
const DRAGGED_OUT: StringName = &"dragged_out"

## The same pair against a wild, where the battle ends: `FledInFearText` for
## Roar and `BlownAwayText` for Whirlwind, told apart by the move number.
## [code]target[/code] is whoever left, either way round.
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

## Rain Dance, Sunny Day and Sandstorm, [code]weather[/code] being the
## [Gen2Weather] value. [constant WEATHER_CONTINUES] is printed on every turn the
## weather survives, which is the turn a Sandstorm's damage lands on.
const WEATHER_STARTED: StringName = &"weather_started"
const WEATHER_CONTINUES: StringName = &"weather_continues"
const WEATHER_ENDED: StringName = &"weather_ended"
const HURT_BY_SANDSTORM: StringName = &"hurt_by_sandstorm"

## Reflect, Light Screen and Safeguard going up and running out, one pair for the
## three: [code]screen[/code] is the [Gen2Screens] flag and the side the one it
## protects. [constant SAFEGUARD_PROTECTED] is
## `BattleCommand_CheckSafeguard`'s line, with the `target` it failed against.
const SCREEN_SET: StringName = &"screen_set"
const SCREEN_FADED: StringName = &"screen_faded"
const SAFEGUARD_PROTECTED: StringName = &"safeguard_protected"

## `StartPerishText` names both Pokémon, so its [code]side[/code] is only whoever
## sang. [constant PERISH_COUNT] carries the side counting down and the
## [code]count[/code] reached, the killing zero included.
const PERISH_SONG_STARTED: StringName = &"perish_song_started"
const PERISH_COUNT: StringName = &"perish_count"

## A trainer spent one of its two items, [code]effect[/code] being
## [method Gen2AIItems.apply]'s answer so a screen follows the bar without asking
## again. One event rather than thirteen: the cartridge prints one line.
const TRAINER_USED_ITEM: StringName = &"trainer_used_item"

## [constant HP_RESTORED] carries `hp` and `max_hp` so a screen moves the bar
## without reading the battle back; [constant HP_ALREADY_FULL] is
## `BattleCommand_Heal`'s refusal, which costs the turn. Rest's two lines are two
## events, the cartridge picking on whether a status was cleared.
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

## Bind, Wrap, Fire Spin, Clamp and Whirlpool: bound, taking a sixteenth, or let
## go. [code]move[/code] is what the texts name through `wStringBuffer1`; the
## release carries no damage, the turn the counter empties costing nothing.
const TRAPPED: StringName = &"trapped"
const HURT_BY_TRAP: StringName = &"hurt_by_trap"
const RELEASED_FROM_TRAP: StringName = &"released_from_trap"

## Mean Look and Spider Web landed. Set on the user, cleared by any send-out;
## a second one from the same user is [constant MOVE_FAILED].
const CANT_ESCAPE_SET: StringName = &"cant_escape_set"

## A switch `TryPlayerSwitch` refused: `BattleText_MonCantBeRecalled`, then back
## to `BattleMenuPKMN_Loop`, so no turn is spent. As [constant RUN_BLOCKED] is.
const SWITCH_BLOCKED: StringName = &"switch_blocked"

## `OfferSwitch`'s question, which only SHIFT reaches: the trainer is about to
## send [code]index[/code] out and the player may change too, until
## [method answer_switch_offer]. Raised from both places `EnemySwitch` is.
const SWITCH_OFFERED: StringName = &"switch_offered"

## Mist and Focus Energy, set on the user. Both fail with [constant MOVE_FAILED]
## on a second use rather than silently re-applying.
const MIST_SET: StringName = &"mist_set"
const FOCUS_ENERGY_SET: StringName = &"focus_energy_set"

## Substitute. Two refusals, because the cartridge picks between
## `HasSubstituteText` and `TooWeakSubText` on which precondition failed. The last
## two carry no amount: `SubTookDamageText` reports none and the health never
## moved.
const SUBSTITUTE_MADE: StringName = &"substitute_made"
const SUBSTITUTE_ALREADY: StringName = &"substitute_already"
const SUBSTITUTE_TOO_WEAK: StringName = &"substitute_too_weak"
const SUBSTITUTE_TOOK_DAMAGE: StringName = &"substitute_took_damage"
const SUBSTITUTE_FADED: StringName = &"substitute_faded"

## `BattleCommand_RaiseSubNoAnim` and `..._LowerSubNoAnim`: once `WaitBGMap` is
## discounted, the doll drawn over a picture or taken off it, no frames and no
## battle state. An animated drop is the animation's own `anim_dropsub`.
const SUBSTITUTE_PIC: StringName = &"substitute_pic"

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

## `BattleCommand_ClearHazards`' three lines, all about the user's own side. Not
## [constant RELEASED_FROM_TRAP]: `HandleWrap`'s release names the move, this one
## the Pokémon that spun out of it.
const SHED_LEECH_SEED: StringName = &"shed_leech_seed"
const BLEW_SPIKES: StringName = &"blew_spikes"
const RELEASED_BY: StringName = &"released_by"

## `EvadedText`, which only `BattleCommand_LeechSeed` prints. Not
## [constant MISSED], which is `GetFailureResultText`'s own line.
const EVADED: StringName = &"evaded"

## A drop blocked by Mist. Not [constant STAT_CHANGE_FAILED]: the cartridge's own
## "It's protected by mist!" rather than the "won't go any lower" a drop at its
## floor gets.
const MIST_PROTECTED: StringName = &"mist_protected"

## `ANIM_SEND_OUT_MON` (constants/move_constants.asm) and the two
## `wBattleAnimParam` values every entrance plays it with: `BattleAnim_SendOutMon`
## branches on the parameter, `$0` being the ball and `$1` the shiny sparkle.
##
## The constant is `$101`, not 101: the comments in that file are hexadecimal,
## and the animations past the moves start at `const_next $ff`. Read as a
## decimal it is NIGHT SHADE, which decodes, runs and draws, so nothing falls
## over: the ball is a night shade with the wrong palette and four times the
## frames. `tools/checks/battle_anims.gd` pins the body each parameter reaches.
const ANIM_SEND_OUT_MON: int = 0x101
const SEND_OUT_ANIM_NORMAL: int = 0
const SEND_OUT_ANIM_SHINY: int = 1

## `PlayFXAnimID`: one animation to spend frames on, at its own index in the
## returned list so the ordering stays the cartridge's, as [Gen2HpBarAnimation]
## does. Carries `index` (`wFXAnimID`), `param` (`wBattleAnimParam`), `after_anim`
## (`wBattleAfterAnim`), `enemy_turn` (`hBattleTurn`), `effectiveness`
## (`wTypeModifier`, which `PlayHitSound` reads) and `restore_user_pic`, the
## `AppearUserLowerSub` after Fly and Dig.
const ANIMATION: StringName = &"animation"

## What a side does with its turn. Switching is settled before priority is looked
## at, which is why it is an action rather than a very fast move.
const ACTION_MOVE: StringName = &"move"
const ACTION_SWITCH: StringName = &"switch"
## `BattleMenu_Run` runs at menu time, so running is settled before the turn: a
## success ends the battle before either side moves and a refusal spends none.
const ACTION_RUN: StringName = &"run"
## `AI_TryItem`'s action. It costs the turn and lands before the player's move
## whatever the speeds say, `AI_SwitchOrTryItem` setting `wEnemyGoesFirst`. Only
## the enemy uses one; the player's pack is the overworld's.
const ACTION_ITEM: StringName = &"item"

## The half of `ItemEffects` the cache does not carry: the two revives, the four
## PP restorers and the doll. Everything else comes off the item's own
## `status_mask` and `heal_amount`.
const ITEM_POKE_DOLL: int = 0x25
const ITEM_REVIVE: int = 0x27
const ITEM_MAX_REVIVE: int = 0x28
const ITEM_ETHER: int = 0x3F
const ITEM_MAX_ETHER: int = 0x40
const ITEM_ELIXER: int = 0x41
const ITEM_MAX_ELIXER: int = 0x15
const ITEM_MYSTERYBERRY: int = 0x96
const REVIVE_ITEMS: Array[int] = [ITEM_REVIVE, ITEM_MAX_REVIVE]
const PP_ITEMS: Array[int] = [
	ITEM_ETHER, ITEM_MAX_ETHER, ITEM_ELIXER, ITEM_MAX_ELIXER, ITEM_MYSTERYBERRY,
]
## The three of them that fill one slot, which is what `.loop` asks about; the
## two Elixers fill every slot and ask nothing.
const SLOT_PP_ITEMS: Array[int] = [ITEM_ETHER, ITEM_MAX_ETHER, ITEM_MYSTERYBERRY]
## `RestorePPEffect`'s own amounts: the Max pair fill the slot, and the other
## three add five (`MYSTERYBERRY` and `ETHER` share it).
const PP_ITEM_AMOUNTS: Dictionary = {
	ITEM_ETHER: 10, ITEM_ELIXER: 10, ITEM_MYSTERYBERRY: 5,
	ITEM_MAX_ETHER: 0, ITEM_MAX_ELIXER: 0,
}

## `wBattleType`. Only the values `TryToRunAwayFromBattle` branches on are named;
## everything else reaches the ordinary speed check.
const BATTLETYPE_NORMAL: int = 0
const BATTLETYPE_DEBUG: int = 2
const BATTLETYPE_CONTEST: int = 6
const BATTLETYPE_FORCESHINY: int = 7
## Named by `PlayBattleMusic` alone: nothing else here branches on it.
const BATTLETYPE_ROAMING: int = 5
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

## `TryToRunAwayFromBattle`: `player_speed * 32 / ((enemy_speed / 4) & $ff)`, plus
## 30 per attempt after the first, and over a byte gets away without a roll.
const FLEE_SPEED_MULTIPLIER: int = 32
const FLEE_ENEMY_SPEED_SHIFT: int = 2
const FLEE_ATTEMPT_BONUS: int = 30
const FLEE_ODDS_RANGE: int = 256

## Priority runs 0 to 3 with most moves at 1, so a move can go below the ordinary
## as well as above it. Keyed by effect byte, which the cache carries.
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
## The run's own divergences and difficulty. Set by [method create_parties], which
## also installs it, so the statics in the formula read the same set.
var rules: Gen2Rules = null

## Whether beating this opponent is worth [Gen2Experience]'s trainer 1.5x. A wild
## encounter, which is the default, never sets it.
var is_trainer_battle: bool = false

## `wBattleType`, read by running alone so far and set on the world path by a
## `loadvar VAR_BATTLETYPE` before `startbattle`.
var battle_type: int = BATTLETYPE_NORMAL

## Earned player badges as source-order bits. Zero is the battle-safe default
## for wild fixtures and development matchups without a world save.
var player_badge_mask: int = 0

## `wNumFleeAttempts`. Every failed run raises the odds behind the next one, and
## choosing FIGHT clears it again, which is `BattleMenu_Fight`'s own `xor a`.
var flee_attempts: int = 0

## `wBattleWeather` and `wWeatherCount`: one of each for the battle rather than
## per side, and neither survives it.
var weather: int = Gen2Weather.NONE
var weather_turns: int = 0

## `wPlayerScreens`/`wEnemyScreens` and their counters. Field state, not Pokémon
## state: a switch clears none of it, so a Reflect outlives whoever put it up.
var screens: Dictionary = {PLAYER: Gen2Screens.NONE, ENEMY: Gen2Screens.NONE}
var light_screen_turns: Dictionary = {PLAYER: 0, ENEMY: 0}
var reflect_turns: Dictionary = {PLAYER: 0, ENEMY: 0}
var safeguard_turns: Dictionary = {PLAYER: 0, ENEMY: 0}

## `wTimeOfDay`, read by the three time-based heals alone: `MORN_F`/`DAY_F`/
## `NITE_F` as bit indices rather than shifted flags, which is what
## [Gen2WorldPalette] holds too, so the overworld's value is written here
## unmapped. A battle nobody told stands at midday.
var time_of_day: int = Gen2WorldPalette.TIME_DAY

## `GetWorldMapLocation`'s answer for the map this is being fought on, which
## `LevelUpHappinessMod` compares a Pokémon's caught location against. A battle
## nobody told is nowhere, and no Pokémon was caught there.
var landmark: int = LANDMARK_NONE

## `wEnemyTrainerItem1` and `wEnemyTrainerItem2`, one copy for the whole battle
## and each removed as it is spent (`xor a; ld [de], a`). Empty for a wild battle
## and for a class carrying `NO_ITEM` twice.
var enemy_items: Array[int] = []

## `wPlayerUsedMoves`, oldest first: all the switch AI has to go on about what it
## is facing. `NewBattleMonStatus` clears it on every send-out, so it describes
## the Pokémon rather than the battle, and `UpdateUsedMoves` keeps four.
var player_used_moves: Array[int] = []

## `wBattleAnimParam`, the animation's input byte. Battle state rather than turn
## state: it sits outside the run `ClearBattleAnims` zeroes, and the five
## multi-hit effects alternate its low bit from whatever the last hit left.
var battle_anim_param: int = 0

## `wPlayerJustGotFrozen` and `wEnemyJustGotFrozen`: frozen during the turn now
## ending, which `HandleDefrost` refuses to thaw, so a freeze costs the turn it
## landed on. Cleared at the top of every turn, as `BattleTurn.loop` clears it.
var _just_got_frozen: Dictionary = {PLAYER: false, ENEMY: false}

## `wEnemyGoesFirst`, written once a turn by `DetermineMoveOrder`: [method order]'s
## answer kept rather than decided twice, and [method opponent_went_first] is the
## `wEnemyGoesFirst XOR hBattleTurn` the three commands asking are given.
var enemy_goes_first: bool = false

## Set once the player has run. The battle is over with no winner, which is the
## DRAW `wBattleResult` the cartridge writes.
var _fled: bool = false

## `wForcedSwitch`: Whirlwind or Roar in a wild battle blows a side out rather
## than switching anybody. `BattleTurn`'s `jr nz, .quit` ends it and the
## `SetBattleDraw` beside it is why [method winner] answers nobody.
var _forced_out: bool = false
## Which side was blown out, for a screen that has to say who left.
var _forced_out_side: int = -1

## The half-run turn a Baton Pass stopped, as
## [code]{"acting": Array, "actions": Dictionary, "index": int}[/code], which
## [method pass_to] lets finish.
var _pending_turn: Dictionary = {}

## The side owing a Baton Pass target, or -1. `ForcePickSwitchMonInBattle` cannot
## be backed out of, so everything else is refused until it is answered.
var _pending_baton_pass: int = -1
## `OfferSwitch`'s pending question, the slot the enemy is about to send out or
## -1. SHIFT alone sets it, and the turn stands still until
## [method answer_switch_offer] closes it.
var _pending_switch_offer: int = -1
## `wOptions`' BATTLE_SHIFT bit, as the caller's own setting rather than a read
## of the options file: the engine is scene-free and takes its rules injected.
var battle_style_set: bool = false

## Whether `AskUseNextPokemon` was answered for the faint standing. Asked once,
## a NO whose run fails falling through to `ForcePlayerMonChoice`.
var _use_next_answered: bool = false

## The side whose Pursuit already ran in front of the switch it answered, or -1.
## `PursuitSwitch` writes `CANNOT_MOVE` over that side's move and `CheckTurn`
## ends the turn on it, so the action it would have taken is spent.
var _pursuit_spent: int = -1

## The two sides, keyed by [constant PLAYER] and [constant ENEMY].
var parties: Dictionary = {}

## Which party indices have fought since the current opponent came in, a
## Dictionary used for its keys: seeded at [method create_parties], added to on
## every [method send_out], reset once experience is awarded.
var _participants: Dictionary = {PLAYER: {}, ENEMY: {}}

## Which of the player's Pokemon have already been charged
## `UpdateFaintedPlayerMon`'s happiness, keyed by instance id. The cartridge runs
## that routine once per faint, off its own turn loop; this engine reports a
## faint from a dozen places and would otherwise charge one Pokemon several
## times for going down once. A revive clears the entry, since a revived
## Pokemon can faint again in the same fight.
var _faint_charged: Dictionary = {}

## The last direct damage each side took this action pair, which Counter and
## Mirror Coat read after the faster side has acted. Cleared each pair: the
## cartridge's `wCurDamage` is move-local, not a history.
var _last_damage_taken: Dictionary = {PLAYER: {}, ENEMY: {}}

## `DoMove`'s own artefact: every effect command executed, in the order the read
## cycle reached it, skips and loop passes included. Collected only while
## `trace_commands` is on, which `tools/trace_battle_commands.gd` turns on so a
## fought turn can be diffed against `.claude/oracle/battle/trace_move_commands.py`'s
## reading of the same one.
static var trace_commands: bool = false
var command_trace: Array[StringName] = []

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

## `wEvolvableFlags`, cleared by `FindFirstAliveMonAndStartBattle` and set per
## party member that gained a level. `ExitBattle` hands it to `EvolveAfterBattle`
## on the overworld, so it is read at the completion boundary the way
## [member pay_day_money] is.
var _evolvable: Array[int] = []

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
	trainer_battle: bool = false,
	player_badges: int = 0,
	battle_rules: Gen2Rules = null
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
	# The rules the fight is fought under, installed for its duration: the damage
	# formula and the experience curves are statics with no battle in hand.
	out.rules = battle_rules if battle_rules != null else Gen2Rules.active()
	Gen2Rules.install(out.rules)
	out.player_badge_mask = player_badges & 0xFFFF
	out._participants = {PLAYER: {player_party.active: true}, ENEMY: {enemy_party.active: true}}
	out._apply_player_badges()
	return out


## One Pokémon a side, which is what a wild encounter is.
static func create(
	game_data: GameData,
	player_mon: Gen2BattleMon,
	enemy_mon: Gen2BattleMon,
	generator: RandomNumberGenerator,
	battle_rules: Gen2Rules = null
) -> Gen2Battle:
	if player_mon == null or enemy_mon == null:
		return null
	return create_parties(
		game_data, Gen2Party.of(player_mon), Gen2Party.of(enemy_mon), generator,
		false, 0, battle_rules
	)


## What a side asks for with its turn.
static func use_move(slot: int) -> Dictionary:
	return {"type": ACTION_MOVE, "slot": slot}


func set_player_badges(mask: int) -> void:
	player_badge_mask = mask & 0xFFFF
	_apply_player_badges()


func _apply_player_badges() -> void:
	if parties.is_empty():
		return
	var current: Gen2BattleMon = mon(PLAYER)
	if current != null:
		current.set_badge_boosts(player_badge_mask)


static func switch_to(index: int) -> Dictionary:
	return {"type": ACTION_SWITCH, "index": index}


static func run_away() -> Dictionary:
	return {"type": ACTION_RUN}


static func use_item(item: int) -> Dictionary:
	return {"type": ACTION_ITEM, "item": item}


## `InitEnemyTrainer`: the class's own `TRNATTR_ITEM1` and `TRNATTR_ITEM2` into
## the two working slots, and then `IsGymLeader`'s own party walk. `NO_ITEM` is
## zero and is not carried.
func init_enemy_trainer(trainer_class: int) -> void:
	enemy_items = []
	if data == null or trainer_class <= 0:
		return
	var attributes: Dictionary = data.trainer_attributes(trainer_class)
	for key: String in ["item1", "item2"]:
		var item: int = int(attributes.get(key, 0))
		if item != 0:
			enemy_items.append(item)
	_gain_gym_battle_happiness(trainer_class)


## `InitEnemyTrainer`'s `.partyloop`, which runs on the frame the trainer's pic
## is placed rather than on the win: standing in front of a gym leader is what
## pays, and a fainted member is skipped by `ld a, [hli] / or [hl] / jr z`.
func _gain_gym_battle_happiness(trainer_class: int) -> void:
	if not (KANTO_GYM_LEADERS.has(trainer_class) or JOHTO_GYM_LEADERS.has(trainer_class)):
		return
	for member: Gen2BattleMon in party(PLAYER).mons:
		if member == null or member.is_fainted():
			continue
		member.happiness = Gen2WorldPartyHost.change_happiness(
			data, member.happiness, HAPPINESS_GYMBATTLE
		)


## Reports one faint. Every site that knows a battler has gone down goes through
## here rather than appending the event itself, because `UpdateFaintedPlayerMon`
## hangs off the same moment and the cartridge reaches it once.
func note_faint(side: int, events: Array, extra: Dictionary = {}) -> void:
	var event: Dictionary = {"type": FAINTED, "side": side}
	event.merge(extra, true)
	events.append(event)
	_charge_faint_happiness(side)


## `UpdateFaintedPlayerMon`'s happiness half: HAPPINESS_BEATENBYSTRONGFOE when
## the enemy stands at the fallen Pokemon's level plus thirty or above, and
## HAPPINESS_FAINTED under it. The enemy's own faints reach no table.
func _charge_faint_happiness(side: int) -> void:
	if side != PLAYER:
		return
	var fallen: Gen2BattleMon = mon(PLAYER)
	if fallen == null or not fallen.is_fainted():
		return
	var key: int = fallen.get_instance_id()
	if _faint_charged.has(key):
		return
	_faint_charged[key] = true
	var foe: Gen2BattleMon = mon(ENEMY)
	var kind: int = HAPPINESS_FAINTED
	if foe != null and foe.level >= fallen.level + 30:
		kind = HAPPINESS_BEATENBYSTRONGFOE
	fallen.happiness = Gen2WorldPartyHost.change_happiness(data, fallen.happiness, kind)


func party(side: int) -> Gen2Party:
	return parties[side]


func mon(side: int) -> Gen2BattleMon:
	return party(side).active_mon()


func opponent_of(side: int) -> int:
	return ENEMY if side == PLAYER else PLAYER


## Which Unown letter a Pokémon is, 1 being A, zero for anything else.
## `_GetFrontpic` reads `UnownPicPointers` by `wUnownLetter`, which
## `GetUnownLetter` fills from the same DVs the stats came from: a display value
## like the level in an event, so it travels with the send-out.
static func unown_form_of(battler: Gen2BattleMon) -> int:
	if battler == null or battler.species != RomLayout.UNOWN_SPECIES:
		return 0
	return Gen2Stats.unown_letter(battler.persistent_dvs())


## `BattleCommand_FreezeTarget`'s own tail, which writes the flag on the side it
## just froze so [method _tick_defrost] leaves that one alone this turn.
func mark_just_got_frozen(side: int) -> void:
	_just_got_frozen[side] = true


## Clears the damage that Counter and Mirror Coat are allowed to remember.
## Residual damage is deliberately not recorded: the cartridge's counter move
## reads the damage produced by the opponent's move, not end-of-turn status loss.
func reset_damage_taken() -> void:
	_last_damage_taken = {PLAYER: {}, ENEMY: {}}


## `BattleCommand_ApplyDamage.update_damage_taken`, an add-with-carry capped at
## $ffff rather than an assignment. Bide accumulates the same raw word.
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


## `BattleCommand_CheckFutureSight`'s own read: the count still standing, and on
## the turn it is one, the stored word taken and the count cleared.
func future_sight_count(side: int) -> int:
	return int((_future_sight.get(side, {}) as Dictionary).get("count", 0))


func take_future_sight_damage(side: int) -> int:
	var pending: Dictionary = _future_sight[side]
	pending["count"] = 0
	return int(pending.get("damage", 0))


## A battle is lost when a whole party is down, not when the Pokémon that is out
## has fainted. One of those is a defeat and the other is a Pokémon to replace.
func is_over() -> bool:
	return _fled or _forced_out or party(PLAYER).is_wiped() or party(ENEMY).is_wiped()


## `wForcedSwitch` and `SetBattleDraw`: Whirlwind or Roar blowing [param side] out
## of a wild battle. Nothing is switched and nobody faints, so both parties stand
## as they are and [method winner] answers null, the way a run leaves it.
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


## `TryToRunAwayFromBattle`, resolved without spending anything. Answers
## `outcome`: [code]&"fled"[/code], [code]&"failed"[/code] for the short roll,
## which costs the turn, or [code]&"blocked"[/code] for a refusal that costs
## nothing, with `how` or `reason` naming the branch. Both trapping checks are
## refusals rather than failed rolls: `.cant_escape` returns without writing
## `BATTLEPLAYERACTION_USEITEM`, so only `.cant_escape_2` spends the turn.
##
## [param runner_speed] is the Speed the caller hands the routine, which is not
## always the Pokémon out: `BattleMenu_Run` passes `wBattleMonSpeed` and
## `AskUseNextPokemon` `wPartyMon1Speed`, and below zero takes the former. The
## source's `hl` covers the Speed word alone, so the rest is the battle copy's.
func run_odds(runner_speed: int = -1) -> Dictionary:
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
	var speed: int = runner.stat("speed") if runner_speed < 0 else runner_speed
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


## `wEvolvableFlags` read back: the party indices that gained a level in this
## battle, in party order. Battle-party indices, so a save carrying an egg maps
## them through [method Gen2SaveBattleAdapter.save_party_index].
func evolvable_indices() -> Array[int]:
	return _evolvable.duplicate()


## Whether a side is waiting for somebody to be sent out: the Pokémon that was
## out has fainted and there is still a party behind it. Nothing else can happen
## on either side until it is answered, which is the cartridge's order too.
func must_replace(side: int) -> bool:
	var current: Gen2Party = party(side)
	return current.active_mon().is_fainted() and not current.is_wiped()


func awaiting_replacement() -> bool:
	return must_replace(PLAYER) or must_replace(ENEMY)


## `TryToRunAwayFromBattle` spent rather than only weighed: the odds rolled,
## `wNumFleeAttempts` moved and the event appended. Answers the outcome, since
## every caller has a different tail behind it.
func _attempt_run(events: Array, runner_speed: int = -1) -> StringName:
	var attempt: Dictionary = run_odds(runner_speed)
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
	match outcome:
		&"fled":
			_fled = true
			events.append(_run_event(FLED, attempt))
		&"blocked":
			events.append(_run_event(RUN_BLOCKED, attempt))
		_:
			events.append(_run_event(RUN_FAILED, attempt))
	return outcome


## Whether `AskUseNextPokemon` has a question: the player owes a replacement and
## this is a wild battle. A trainer battle returns at once ("that decision is
## made for us"), and the question is asked once per faint.
func asking_use_next() -> bool:
	return must_replace(PLAYER) and not is_trainer_battle and not _use_next_answered


## `AskUseNextPokemon`'s yes/no. YES leaves `ForcePlayerMonChoice` standing; NO is
## `TryToRunAwayFromBattle`, which ends the battle or falls into that same forced
## choice. The Speed handed to the run is `wPartyMon1Speed`, the first slot's:
## the source reads the party here because the battle copy is a corpse.
func answer_use_next(use_next: bool) -> Array:
	if not asking_use_next():
		return []
	_use_next_answered = true
	if use_next:
		return []
	var events: Array = []
	if _attempt_run(events, _first_party_speed()) == &"fled":
		events.append({"type": OVER, "winner": winner(), "fled": true})
	return events


## `wPartyMon1Speed`: the stored stat, with neither a badge boost nor a stage on
## it, since neither is ever written back into the party structure.
func _first_party_speed() -> int:
	var first: Gen2BattleMon = party(PLAYER).at(0)
	return 0 if first == null else int(first.stats.get("speed", 0))


## Who [param side] sends out to replace a faint: the enemy's is
## `FindMonInOTPartyToSwitchIntoBattle`'s type-matchup pick, and the player's is
## asked rather than answered, so this is the fallback for a caller with none.
func replacement_target(side: int) -> int:
	if side == ENEMY:
		return Gen2AISwitch.pick_target(self)
	return party(side).first_healthy()


## `HandlePlayerMonFaint` and `HandleEnemyMonFaint`'s replacement tail, and the
## one thing besides [method take_actions] that moves a battle on. [param index]
## is the player's row out of `ForcePlayerMonChoice`, refused the way the party
## menu refuses so the question stays standing; the enemy's is never asked for.
## The order is `DoubleSwitch`'s: with both down the player enters first, so the
## AI's pick is scored against whoever that turned out to be, and the enemy
## arrives through `EnemySwitch_SetMode`. Only a trainer replacing on its own
## reaches `EnemySwitch` and its SHIFT offer.
func replace_fallen(index: int = -1) -> Array:
	var events: Array = []
	if is_over() or _pending_switch_offer >= 0 or _pending_baton_pass >= 0:
		return events

	if must_replace(PLAYER):
		if not party(PLAYER).can_send_out(index):
			return events
		var doubled: bool = must_replace(ENEMY)
		events.append_array(send_out(PLAYER, index))
		if doubled:
			_enemy_entrance(events, false)
		return events

	if must_replace(ENEMY):
		_enemy_entrance(events, should_offer_switch())
	return events


## `EnemyPartyMonEntrance`: `EnemySwitch_SetMode` when the replacement walks in,
## `EnemySwitch` when SHIFT makes it an offer, closed by
## [method answer_switch_offer] like a mid-turn switch's.
func _enemy_entrance(events: Array, offer: bool) -> void:
	var target: int = replacement_target(ENEMY)
	if target < 0:
		return
	if not offer:
		events.append_array(send_out(ENEMY, target))
		return
	_pending_switch_offer = target
	events.append({
		"type": SWITCH_OFFERED, "side": PLAYER, "index": target,
		"species": party(ENEMY).at(target).species,
	})


## `CheckWhetherToAskSwitch`: in SHIFT mode a trainer's switch offers the player
## one, given a started battle, somebody else to send, SET off and the player's
## own Pokémon standing. A wild has no trainer to switch.
func should_offer_switch() -> bool:
	return is_trainer_battle and not battle_style_set \
		and party(PLAYER).healthy_count() > 1 and not mon(PLAYER).is_fainted()


## The party slot the enemy is about to send out while the player is being asked
## whether to switch as well, or -1. `OfferSwitch` asks before that Pokémon
## appears, which is why the answer arrives with the enemy still on its way in.
func awaiting_switch_offer() -> int:
	return _pending_switch_offer


## `OfferSwitch`'s yes/no. [param index] below zero is the source's carry, ending
## the turn's first half; anything else is the player switching too, which
## `EnemySwitch` reaches by falling into `PlayerSwitch`. A slot the party would
## refuse leaves the question standing.
func answer_switch_offer(index: int = -1) -> Array:
	if _pending_switch_offer < 0:
		return []
	if index >= 0 and not party(PLAYER).can_send_out(index):
		return []
	var enemy_index: int = _pending_switch_offer
	_pending_switch_offer = -1
	var events: Array = []
	events.append_array(send_out(ENEMY, enemy_index))
	if index >= 0:
		events.append_array(send_out(PLAYER, index))
	# An offer raised by [method replace_fallen] has no turn behind it:
	# `HandleEnemyMonFaint` returns as soon as both entrances are done.
	if _pending_turn.is_empty():
		return events
	var actions: Dictionary = _pending_turn.get("actions", {})
	_close_turn_bracket(ENEMY, actions.get(ENEMY, {}))
	_pending_turn["index"] = int(_pending_turn["index"]) + 1
	return _run_turn(events)


## Which side owes a Baton Pass target, or -1: [method must_replace]'s shape,
## except that this one stops a turn part way rather than between two.
func awaiting_baton_pass() -> int:
	return _pending_baton_pass


## Answers a pending Baton Pass by sending [param index] out and finishing the
## turn behind it. An index the party would refuse leaves the question standing,
## as `ForcePickSwitchMonInBattle` redisplays its list.
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


## `FindMonInOTPartyToSwitchIntoBattle`, reached because Baton Pass zeroes
## `wEnemySwitchMonIndex` rather than naming anybody:
## [method replacement_target]'s pick, without the question of whether to switch,
## which the move has already answered.
func baton_pass_target(side: int) -> int:
	return replacement_target(side)


## `PassedBattleMonEntrance` and the enemy's `EnemySwitch_SetMode`: an entrance
## that keeps what it is handed, neither calling `NewBattleMonStatus` nor
## resetting the stages, which is the whole difference from [method send_out].
## The Pokémon walking back to its ball still loses everything.
func baton_pass_send_out(side: int, index: int) -> Array:
	var passed: Dictionary = mon(side).capture_passed_state()
	var events: Array = send_out(side, index, -1, true)
	if events.is_empty():
		return events
	mon(side).apply_passed_state(passed)
	_reset_baton_pass_status(side)
	return events


## `ResetBatonPassStatus`: the five things a pass does not carry. Nightmare is
## easy to get backwards, the check running after the entrance, so the sleep it
## reads is the *arriving* Pokémon's. Attraction and the wrap counters clear on
## both sides, whoever was loved or bound having left the field.
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


## A move waiting on [method learn_move] or [method decline_move]: every slot was
## full when a level taught a new one, [method must_replace]'s shape again.
func must_learn_move(side: int) -> bool:
	return not (_move_learn_queue.get(side, []) as Array).is_empty()


func awaiting_move_learn() -> bool:
	return must_learn_move(PLAYER) or must_learn_move(ENEMY)


## The offer waiting on [param side], or empty. [code]species[/code],
## [code]index[/code], [code]move[/code] and [code]level[/code] say "your FOO
## wants to learn BAR" without reading the Pokémon back.
func pending_learn(side: int) -> Dictionary:
	var queue: Array = _move_learn_queue.get(side, [])
	return queue[0] if not queue.is_empty() else {}


## Answers a pending offer by giving up [param forget_slot]. An HM slot is refused
## as `ForgetMove`'s `.hmmove` branch refuses it, and either refusal leaves the
## offer standing.
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

	# LearnMove clears a Disable naming the move that went, in battle only. The
	# cartridge compares numbers against wDisabledMove; Disable is a slot here and
	# the new move takes the forgotten one's, so slot equality is that test.
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


## Sends a side's [param index] out, as a replacement or between turns, with one
## event or none: an impossible switch is refused. [param dragged_by] is the side
## that used Whirlwind or Roar, -1 otherwise, because `DraggedOutText` is printed
## between `ForceEnemySwitch` and `SpikesDamage`.
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
	if side == PLAYER and current.active_mon() != null:
		current.active_mon().clear_badge_boosts()
	if not current.send_out(index):
		return events
	if side == PLAYER:
		_apply_player_badges()
	_clear_trapping()
	if not preserve_counter_moves:
		# NewBattleMonStatus/NewEnemyMonStatus clear both counter-move words.
		mon(PLAYER).last_counter_move = 0
		mon(ENEMY).last_counter_move = 0
	# `BreakAttraction`, which every entrance calls, clears both sides: whoever
	# the Pokémon that left loved is not on the field either.
	mon(PLAYER).substatus &= ~Gen2Substatus.ATTRACTED
	mon(ENEMY).substatus &= ~Gen2Substatus.ATTRACTED
	# `NewBattleMonStatus` clears the used-move list with the rest of the volatile
	# state. The enemy's send-out leaves it alone: it lists what the player showed.
	if side == PLAYER:
		player_used_moves = []
		# The next faint is a fresh `AskUseNextPokemon`.
		_use_next_answered = false

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
		"unown_form": unown_form_of(current.active_mon()),
		"line": send_out_line(side),
	})
	(_participants[side] as Dictionary)[index] = true
	# `SendOutPlayerMon` and `ShowSetEnemyMonAndSendOutAnimation` both run their
	# animation after the line that announced them, and `ForceEnemySwitch` runs
	# it before `DraggedOutText`.
	events.append_array(entrance_events(side))
	if dragged_by >= 0:
		events.append({"type": DRAGGED_OUT, "side": dragged_by, "target": side})
	_spikes_damage(side, events)
	return events


## `SendOutPlayerMon` and `ShowSetEnemyMonAndSendOutAnimation`, which every
## entrance in the source runs and which are the same three steps on both sides:
## `ANIM_SEND_OUT_MON`, a second pass of it for a shiny, and the cry Crystal's
## own `CheckFaintedFrzSlp` allows. Public because a battle's opening entrance is not
## a [method send_out]: both sides are already standing there when the pics
## finish sliding, and the screen plays the same list for them.
##
## [param ball] is false for `BattleStartMessage`'s wild branch, which is the one
## entrance with no ball in it: the Pokemon is already standing there when the
## pics stop sliding, so only the shiny pass and the cry are left of the list.
func entrance_events(side: int, ball: bool = true) -> Array:
	var entering: Gen2BattleMon = mon(side)
	if entering == null:
		return []
	var enemy_turn: bool = side == ENEMY
	var out: Array = []
	if ball:
		out.append(_send_out_animation(enemy_turn, SEND_OUT_ANIM_NORMAL))
	# `BattleCheckPlayerShininess`/`BattleCheckEnemyShininess`, which read the
	# live DVs: a Transform has already copied the target's over them.
	if Gen2Stats.is_shiny(entering.dvs):
		out.append(_send_out_animation(enemy_turn, SEND_OUT_ANIM_SHINY))
	# `CheckFaintedFrzSlp`: no cry from a fainted, frozen or sleeping Pokemon.
	# Crystal's alone: pokegold's `SendOutPlayerMon` and
	# `ShowSetEnemyMonAndSendOutAnimation` both reach `PlayStereoCry` with no
	# test in front of it, the same place their own pic animation is missing.
	if Gen2WorldState.is_crystal_profile(data) and (entering.is_fainted() \
			or (entering.status & (Gen2Status.FREEZE | Gen2Status.SLEEP_MASK)) != 0):
		return out
	out.append({"type": CRY, "side": side, "species": entering.species})
	return out


## `Call_PlayBattleAnim` rather than `PlayFXAnimID`: `WaitBGMap` in place of the
## three-frame delay, which is what `called` says.
func _send_out_animation(enemy_turn: bool, param: int) -> Dictionary:
	return {
		"type": ANIMATION,
		"index": ANIM_SEND_OUT_MON,
		"param": param,
		"after_anim": 0,
		"enemy_turn": enemy_turn,
		# `SendOutPlayerMon` clears `wTypeModifier` on its way past; nothing in a
		# send-out reads it, since only a damage after-anim has a hit sound.
		"effectiveness": 0,
		"restore_user_pic": false,
		"called": true,
	}


## `SendOutMonText`, which picks one of four lines off how much of the opponent
## is left. Only the player is ever announced this way; the enemy has one line.
##
## The arithmetic is the source's own: the remaining HP times 25 over the top
## quarter of the maximum, both read as the cartridge reads them, so the answer
## is a percentage that has been through an eight-bit divisor. A maximum below
## four leaves that divisor zero, which is `docs/bugs_and_glitches.md`'s freeze;
## nothing here can freeze, so it answers the first line.
func send_out_line(side: int) -> int:
	if side != PLAYER:
		return SEND_OUT_GO
	var foe: Gen2BattleMon = mon(opponent_of(side))
	if foe == null or foe.hp <= 0:
		return SEND_OUT_GO
	var divisor: int = (foe.max_hp() >> 2) & 0xFF
	if divisor == 0:
		return SEND_OUT_GO
	var percent: int = ((foe.hp * 25) / divisor) & 0xFF
	if percent >= 70:
		return SEND_OUT_GO
	if percent >= 40:
		return SEND_OUT_DO_IT
	if percent >= 10:
		return SEND_OUT_GO_FOR_IT
	return SEND_OUT_FOES_WEAK


## `SpikesDamage`, behind each entrance's own `SetPlayerTurn`/`SetEnemyTurn`, so
## the spikes read are the ones on the side walking in.
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
		note_faint(side, events)


## `UpdateUsedMoves`: remembered once, four kept, and a fifth drops the oldest
## rather than being ignored, which is why it is a queue and not a capped set.
func _record_used_move(move_number: int) -> void:
	if move_number == 0 or player_used_moves.has(move_number):
		return
	player_used_moves.append(move_number)
	if player_used_moves.size() > Gen2BattleMon.MAX_MOVES:
		player_used_moves.remove_at(0)


## Ends the trapping relationship on both sides, as `NewBattleMonStatus` does.
## [method Gen2BattleMon.reset_volatile] cannot: half the state is on the Pokémon
## staying.
func _clear_trapping() -> void:
	for side: int in [PLAYER, ENEMY]:
		var battler: Gen2BattleMon = mon(side)
		battler.trapped_turns = 0
		battler.trapping_move = 0
		battler.substatus &= ~Gen2Substatus.CANT_RUN


## Whether `TryPlayerSwitch` would refuse the recall: bound, or held by Mean Look
## or Spider Web. Player-only, `AI_Switch` making no such check.
func switch_blocked() -> bool:
	return mon(PLAYER).trapped_turns > 0 \
		or Gen2Substatus.has(mon(ENEMY).substatus, Gen2Substatus.CANT_RUN)


## Both sides act and the turn plays out, answering the events in order. An action
## is [method use_move] or [method switch_to]; nothing happens while either side
## owes a replacement, and a faint ends the turn where it is. [method order] reads
## each side's credited move once before either acts, which is when the cartridge
## decides order, and what runs is recomputed just before [method _act]: Encore
## can land on a side that has not gone.
func take_actions(player_action: Dictionary, enemy_action: Dictionary) -> Array:
	var events: Array = []
	if is_over() or awaiting_replacement() or awaiting_move_learn():
		return events
	# A turn already part way through cannot be started again: the one standing
	# is finished by [method pass_to] and by nothing else.
	if _pending_baton_pass >= 0 or _pending_switch_offer >= 0:
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
		var outcome: StringName = _attempt_run(events)
		if outcome == &"fled":
			events.append({"type": OVER, "winner": winner(), "fled": true})
			return events
		if outcome == &"blocked":
			# BattleMenu_Run's `jp BattleMenu`: nothing was spent, so no residual
			# damage and no enemy move either.
			return events

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


## The per-side loop and the end-of-turn tail, from wherever the turn last
## stopped. Baton Pass is the one thing that stops it part way: `DoPlayerTurn`
## opens a switch menu and waits, so the rest sits in [member _pending_turn].
func _run_turn(events: Array) -> Array:
	var acting: Array = _pending_turn["acting"]
	var actions: Dictionary = _pending_turn["actions"]

	while int(_pending_turn["index"]) < acting.size():
		var side: int = int(acting[int(_pending_turn["index"])])
		var action: Dictionary = actions[side]
		var action_event_start: int = events.size()
		var moving: bool = not (_is_run(action) or _is_switch(action) or _is_item(action))
		# `HasPlayerFainted`/`HasEnemyFainted` between the halves of the turn,
		# gating the whole second half rather than its move, which is why it is
		# asked before the bracket opens. A switching or item-using side is always
		# [method order]'s first, so this is only ever asked of a move.
		if moving and (mon(side).is_fainted() or mon(opponent_of(side)).is_fainted()):
			break
		_open_turn_bracket(side, action)
		if not moving:
			# `.reset_rage` for a switch and `.reset_bide` for an item or a failed
			# run, both falling into `.locked_in`'s zeroing, and `AI_TryItem` the
			# same on the enemy's side. -1 is no effect, so both counters go.
			_reset_action_counters(side, -1)
		if _is_switch(action):
			_pursuit_before_switch(side, actions, events)
			# `EnemySwitch`: on SHIFT the player is told who is coming and asked
			# whether to change, before that Pokémon is out. The turn stops here.
			if side == ENEMY and should_offer_switch():
				_pending_switch_offer = int(action.get("index", -1))
				events.append({
					"type": SWITCH_OFFERED, "side": PLAYER,
					"index": _pending_switch_offer,
					"species": party(ENEMY).at(_pending_switch_offer).species,
				})
				return events
			events.append_array(send_out(side, int(action.get("index", -1))))
		elif _is_item(action):
			## `BattleMenu_Pack` spends the player's item before the turn
			## resolves; only the enemy reaches into its bag inside one.
			if side == ENEMY:
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
		# `ld a, [wForcedSwitch] / and a / ret nz`, asked twice by each of
		# `Battle_PlayerFirst` and `Battle_EnemyFirst`. Blown or teleported out of
		# a wild battle ends the turn where it stands, tail included.
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


## Core checks both battlers after every action, whether or not the effect list
## carried `checkfaint`: this fills only the report an effect did not make.
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
			note_faint(side, events)


## `HandleFutureSight`, player then enemy: the count is decremented before it is
## tested, and the move is then run through `DoMove` like any other, so the
## stored word takes its spread, its hit roll and its faint check inside the
## effect list rather than beside it. `checkfuturesight` is what loads it.
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
		if mon(side).is_fainted() or mon(opponent_of(side)).is_fainted():
			pending["count"] = 0
			continue
		events.append({"type": FUTURE_SIGHT_HIT, "side": side, "target": opponent_of(side)})
		var number: int = Gen2MoveEffect.FUTURE_SIGHT_MOVE
		var turn: Gen2Turn = Gen2Turn.create(self, side, -1, number, data.move(number), events)
		run_move_effect(turn)


## `wPlayerIsSwitching` and `wEnemyIsSwitching`, zeroed each turn the way
## rebuilding [member _pending_turn] is. An enemy item is not a switch here though
## [method order] orders it as one: `AI_TryItem` sets no flag, and
## [method Gen2EffectCommands._pursuit] is the reader.
func is_switching(side: int) -> bool:
	if _pending_turn.is_empty():
		return false
	var actions: Dictionary = _pending_turn["actions"]
	return _is_switch(actions.get(side, {}))


## `PursuitSwitch`, called from `BattleMonEntrance` and `AI_Switch` in front of
## the recall: the pursuer spends its whole turn now, against the Pokémon on its
## way out. No speed or priority test, the switch being settled first whatever
## the speeds, which is why `EFFECT_PURSUIT` carries no priority entry; the effect
## byte is read here rather than in a command because the trigger belongs to the
## byte, as [constant EFFECT_PRIORITIES] does. A chosen switch only, so a Baton
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


## `CheckOpponentWentFirst`, `wEnemyGoesFirst XOR hBattleTurn`. Protect and Endure
## fail outright on a yes, which is what makes two Protects a question of speed
## and a Protect behind a switch fail, a switching side always going first.
func opponent_went_first(side: int) -> bool:
	return (side == PLAYER) == enemy_goes_first


## `EndUserDestinyBond`, the front half of the wrapper each action runs inside.
## Ahead of `DoPlayerTurn`, so a Pokémon that cannot move still loses its bond.
func _open_turn_bracket(side: int, action: Dictionary) -> void:
	if not _brackets_turn(side, action):
		return
	mon(side).substatus &= ~Gen2Substatus.DESTINY_BOND


## `EndOpponentProtectEndureDestinyBond`, the back half: three flags only an
## opposing action ends, so a Protect covers one action and outlives its own turn
## when it was used going second.
func _close_turn_bracket(side: int, action: Dictionary) -> void:
	if not _brackets_turn(side, action):
		return
	var other: Gen2BattleMon = mon(opponent_of(side))
	other.substatus &= ~(
		Gen2Substatus.PROTECT | Gen2Substatus.ENDURE | Gen2Substatus.DESTINY_BOND
	)


## Whether an action runs inside that wrapper, which the two sides disagree on:
## the player's runs on everything, both orderings calling `PlayerTurn_End...`
## unconditionally, and the enemy's is jumped past whenever `AI_SwitchOrTryItem`
## answers. So a player's Protect survives an enemy switch and an enemy's does not
## survive a player switch.
func _brackets_turn(side: int, action: Dictionary) -> bool:
	return side == PLAYER or not (_is_switch(action) or _is_item(action))


## `ParsePlayerAction` and `ParseEnemyAction`: the two counters a chain keeps only
## while it is the move being used, Protect and Endure sharing one. The source's
## second reset behind `CheckPlayerLockedIn` cannot disagree, none of the three
## setting a recharge, charge, rampage or Rollout flag. [param effect] is the
## move's own byte, not [method Gen2Turn.effect], which a broken Substitute
## overwrites part way.
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


## `ResidualDamage`: burn, poison, Leech Seed, Nightmare and Curse, in that order
## and in the order the sides acted, after both moves and skipping whoever is
## down. `HasUserFainted` sits between the steps, so one that goes down to its
## poison pays neither the seed nor the nightmare.
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


## A running [member Gen2BattleMon.toxic_counter] means Toxic, which ramps rather
## than taking the flat eighth. It rises here, so the turn it landed is the
## first.
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
		note_faint(side, events)


## An eighth off the seeded Pokémon and onto the one opposite, capped by
## `RestoreHP`: what is healed is what `SubtractHP` left in `bc`, which is
## [method Gen2BattleMon.take_damage]'s answer. A fainted receiver cannot happen
## on the cartridge and can here, this running after both moves; nothing moves.
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
		note_faint(side, events)


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
		note_faint(side, events)


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
		note_faint(side, events)


## `HandleWeather`: a turn off the count, its line, and a Sandstorm's eighth off
## whoever it reaches, ahead of [method _tick_wrap]. The countdown is before the
## message, so the turn it empties prints the ending line and deals no damage.
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
			note_faint(side, events)


## `HandleWrap`: a turn off each bound Pokémon's counter and a sixteenth of its
## health, between [method _residual_damage] and [method _tick_encore] where
## `HandleBetweenTurnEffects` runs it, always the player first where
## `ResidualDamage` follows the turn order. The turn the counter empties is the
## release and costs nothing, which is why three to six rolled turns are two to
## five turns of damage.
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
			note_faint(side, events)


## `HandlePerishSong`: one off each count, said out loud, and whoever reaches zero
## is finished where it stands. Behind [method _tick_wrap] and ahead of the
## leftovers block, player first as every handler here is. The line prints on
## every tick including the last, and the kill is `xor a` into the HP word rather
## than damage, so no held item can answer it.
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
		note_faint(side, events)


## `HandleBetweenTurnEffects`' leftovers block: `HandleLeftovers`,
## `HandleMysteryberry`, then `HandleHealingItems`, after the wrap tick and before
## Encore. The first two read `GetUserItem` so the player is first, the third
## `GetOpponentItem` so the enemy is. `HandleDefrost`, `HandleSafeguard` and
## `HandleScreens` sit among them and are not item effects.
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


## `HandleDefrost`: each frozen side thaws on its own roll, the only thing making
## a Generation 2 freeze temporary. Player first, and `bit FRZ` comes before
## `BattleRandom`, so a battle with no freeze draws no randomness here.
func _tick_defrost(events: Array) -> void:
	for side: int in [PLAYER, ENEMY]:
		var current: Gen2BattleMon = mon(side)
		if not Gen2Status.has(current.status, Gen2Status.FREEZE):
			continue
		if bool(_just_got_frozen[side]):
			continue
		if not Gen2Status.rolls_thaw(rng):
			continue
		# `xor a / ld [wBattleMonStatus], a` clears the byte rather than the bit,
		# which is the same thing: a freeze is never on it with anything else.
		current.status = Gen2Status.NONE
		events.append({"type": THAWED, "side": side})


## `HandleSafeguard`: a turn off each side's count and the line when it runs out.
## The count is read only while the flag is up, so a side without one is quiet.
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


## `HandleScreens`: Light Screen before Reflect, `.TickScreens`' own order, and
## the player first. The counts are separate bytes, so a side holds both.
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


## `HandleMysteryberry`: five points into the first move that ran out, one for
## Sketch. Consumed by its own code, which is why it is not on
## `ConsumableEffects`.
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


## `UseHeldStatusHealingItem`, reached here and the moment a status lands: the
## berry answers at once rather than at the end of the turn.
func use_status_berry(side: int, events: Array) -> bool:
	var holder: Gen2BattleMon = mon(side)
	if holder.status == Gen2Status.NONE:
		return false
	if not Gen2HeldItem.heals_status(_held_effect(holder), holder.status):
		return false

	# The status byte alone: `UseHeldStatusHealingItem` never touches
	# `SUBSTATUS_TOXIC`, so a cured Pokémon keeps the flag that ramps its next
	# poison, and [member Gen2BattleMon.toxic_counter] is that flag.
	holder.status = Gen2Status.NONE
	var used: int = holder.item
	holder.item = 0
	events.append({"type": RECOVERED_USING_ITEM, "side": side, "item": used})
	return true


## `UseConfusionHealingItem`. A Miracleberry answers here and for the status byte,
## spent by whichever came first, which is why the calls are separate.
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


## Encore's countdown, once a turn rather than once a move. It ends the moment
## the encored slot runs out of PP, checked every tick rather than at expiry.
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


## Experience for every enemy Pokémon that fainted this turn, to a move or to
## status damage. [constant FAINTED] clears the member out of
## [member _participants] on either side; only [method _give_experience_for] is
## asymmetric.
func _award_experience(events: Array) -> void:
	for event: Dictionary in events.duplicate():
		if StringName(event.get("type", "")) != FAINTED:
			continue
		var side: int = int(event["side"])
		(_participants[side] as Dictionary).erase(party(side).active)
		if side == ENEMY:
			_give_experience_for(mon(ENEMY), events)


## Splits what [param defeated] is worth, then resets the participant set to
## whoever is standing, so the trainer's next Pokémon starts its own count.
## `UpdateFaintedPlayerMon` awards in two passes when anything alive holds an
## Exp. Share: the block is halved, then split among the participants and again
## among the holders. A Pokémon in both passes is awarded twice.
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


## What a won battle owes when nothing simulated the turns that won it: every
## enemy Pokémon fainted in party order through [method _give_experience_for], so
## the split, the Exp. Share pass, the level ups, the evolutions and the moves
## learned are the engine's own and only the fighting is missing. The
## participant set never grows past whoever is out, so the award is the floor a
## real fight could have paid rather than a guess at who took part.
func award_win_experience() -> Array:
	var events: Array = []
	if data == null or parties.is_empty():
		return events
	var beaten: Gen2Party = party(ENEMY)
	for index: int in beaten.size():
		var defeated: Gen2BattleMon = beaten.at(index)
		if defeated == null or defeated.is_fainted():
			continue
		defeated.hp = 0
		_give_experience_for(defeated, events)
	return events


## Spends one of the trainer's two items, which costs the turn. The item is gone
## whether or not it changed anything, `AI_TryItem` clearing the slot the moment a
## check said yes. What the cartridge clears beside it is
## [method _reset_action_counters]'s work and
## [method reset_damage_taken]'s; Bide and Rage do not exist here yet.
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


## `DoItemEffect` with `wBattleMode` set, the pack's own USE inside a battle:
## applied here rather than in the turn loop, as the cartridge applies it in the
## menu and then spends the turn as `BATTLEPLAYERACTION_USEITEM`.
## [param target_index] is `UseItem_SelectMon`'s pick and [param move_slot]
## `RestorePPEffect`'s question; a refusal is any branch leaving
## `wItemEffectSucceeded` clear, and none spends the item or the turn.
func use_bag_item(item: int, target_index: int = -1, move_slot: int = -1) -> Dictionary:
	if data == null or is_over():
		return _item_failure(&"battle_not_running")
	var definition: Dictionary = data.item(item)
	if definition.is_empty():
		return _item_failure(&"unknown_item")
	if item == ITEM_POKE_DOLL:
		## `PokeDollEffect`: `wForcedSwitch` and a DRAW, which is
		## [method force_out] with nobody blown out by a move.
		if is_trainer_battle:
			return _item_failure(&"item_has_no_effect")
		force_out(PLAYER)
		return {"ok": true, "kind": &"fled", "item": item}
	if Gen2AIItems.X_STATS.has(item) or Gen2AIItems.X_SUBSTATUSES.has(item):
		var applied: Dictionary = _apply_active_item(mon(PLAYER), item)
		if not bool(applied.get("ok", false)):
			return _item_failure(StringName(applied.get("reason", &"item_has_no_effect")))
		return {"ok": true, "kind": &"active_item", "item": item, "effect": applied}
	var target: Gen2BattleMon = party(PLAYER).at(target_index)
	if target == null:
		return _item_failure(&"party_member_required")
	var result: Dictionary = _apply_party_item(
		target, item, definition, move_slot, target_index == party(PLAYER).active
	)
	if not bool(result.get("ok", false)):
		return _item_failure(StringName(result.get("reason", &"item_has_no_effect")))
	## `RevivePokemon`'s own `wBattleParticipantsNotFainted` write: a revived
	## Pokemon that had already taken part shares the experience again.
	if bool(result.get("revived", false)):
		(_participants[PLAYER] as Dictionary)[target_index] = true
	return {
		"ok": true, "kind": &"party_item", "item": item,
		"target": target_index, "effect": result,
	}


## `XItemEffect`, `GuardSpecEffect` and `DireHitEffect`, on whoever is out rather
## than a party member, each refusing a capped stage or a set flag with
## `WontHaveAnyEffect_NotUsedMessage`.
func _apply_active_item(user: Gen2BattleMon, item: int) -> Dictionary:
	if user == null or user.is_fainted():
		return {"ok": false, "reason": &"item_has_no_effect"}
	if Gen2AIItems.X_SUBSTATUSES.has(item):
		var flag: int = int(Gen2AIItems.X_SUBSTATUSES[item])
		if Gen2Substatus.has(user.substatus, flag):
			return {"ok": false, "reason": &"item_has_no_effect"}
		user.substatus |= flag
		return {"ok": true, "substatus": flag}
	var stat: String = String(Gen2AIItems.X_STATS[item])
	if user.stage(stat) >= Gen2Stats.MAX_STAGE:
		return {"ok": false, "reason": &"item_has_no_effect"}
	user.change_stage(stat, 1)
	return {"ok": true, "stat": stat, "stages": 1}


## The ITEMMENU_PARTY half, whose target `UseItem_SelectMon` has chosen, in the
## source's own refusal order: a fainted target takes only a revive, a revive only
## a fainted one, and anything else that would change nothing is
## `WontHaveAnyEffect_NotUsedMessage`. [param active] decides the two a benched
## member cannot have, `IsItemUsedOnConfusedMon`'s cure and Full Restore's.
func _apply_party_item(
	target: Gen2BattleMon, item: int, definition: Dictionary,
	move_slot: int, active: bool
) -> Dictionary:
	if item in REVIVE_ITEMS:
		if not target.is_fainted():
			return {"ok": false, "reason": &"item_has_no_effect"}
		target.hp = target.max_hp() if item == ITEM_MAX_REVIVE else maxi(target.max_hp() / 2, 1)
		_faint_charged.erase(target.get_instance_id())
		return {"ok": true, "revived": true, "healed": target.hp}
	if target.is_fainted():
		return {"ok": false, "reason": &"item_has_no_effect"}
	if item in PP_ITEMS:
		return _restore_pp(target, item, move_slot)
	var healed: int = 0
	var heal_amount: int = int(definition.get("heal_amount", 0))
	if heal_amount > 0:
		healed = target.heal(
			target.max_hp() if heal_amount >= Gen2Stats.MAX_STAT_VALUE else heal_amount
		)
	## `UseStatusHealer`: the mask decides, and only a `%11111111` one reaches
	## `IsItemUsedOnConfusedMon`, which needs the target to be the one out.
	var mask: int = int(definition.get("status_mask", 0))
	var cured: int = target.status & mask
	if cured != 0:
		target.status = Gen2Status.NONE
		target.toxic_counter = 0
	var unconfused: bool = mask == 0xFF and active \
		and Gen2Substatus.has(target.substatus, Gen2Substatus.CONFUSED)
	if unconfused:
		target.substatus &= ~Gen2Substatus.CONFUSED
		target.confusion_turns = 0
	if healed <= 0 and cured == 0 and not unconfused:
		return {"ok": false, "reason": &"item_has_no_effect"}
	return {
		"ok": true, "healed": healed, "status_cleared": cured, "unconfused": unconfused,
	}


## `RestorePPEffect`: the Elixers fill every slot and the Ethers one, which is
## the slot `.loop` asks for. Nothing is spent on a moveset already full.
func _restore_pp(target: Gen2BattleMon, item: int, move_slot: int) -> Dictionary:
	var amount: int = PP_ITEM_AMOUNTS.get(item, 0)
	var slots: Array[int] = []
	if item in [ITEM_ELIXER, ITEM_MAX_ELIXER]:
		for slot: int in target.moves.size():
			slots.append(slot)
	elif move_slot >= 0 and move_slot < target.moves.size():
		slots.append(move_slot)
	var restored: int = 0
	for slot: int in slots:
		if int(target.moves[slot]) <= 0:
			continue
		var full: int = int(data.move(int(target.moves[slot])).get("pp", 0))
		var target_pp: int = full if amount <= 0 else mini(full, target.pp_left(slot) + amount)
		restored += maxi(0, target_pp - target.pp_left(slot))
		target.pp[slot] = target_pp
	if restored <= 0:
		return {"ok": false, "reason": &"item_has_no_effect"}
	return {"ok": true, "pp_restored": restored}


static func _item_failure(reason: StringName) -> Dictionary:
	return {"ok": false, "kind": &"item_failed", "reason": reason}


## `IsAnyMonHoldingExpShare`: every living party index carrying one, in order. A
## fainted holder is skipped before the item is looked at, so it splits nothing.
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
		# Which pass this came from. The cartridge prints one line either way; this
		# tells a Pokémon in both passes from one awarded twice otherwise.
		"exp_share": by_exp_share,
	})

	learner.gain_stat_exp(stat_gains)
	events.append({
		"type": STAT_EXP_GAINED, "side": PLAYER, "index": index, "gains": stat_gains,
	})

	var target_level: int = learner.level_for_exp()
	var grew: bool = learner.level < target_level
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

	## `LevelUpHappinessMod` sits after `.level_loop`, outside it: an award that
	## crossed four levels raises happiness once, not four times.
	if grew:
		_gain_level_happiness(learner)
		## The `SmallFarFlagAction SET_FLAG` at the end of the same block, which
		## is what `EvolveAfterBattle` walks the party against once the battle is
		## over and won. Nothing evolves in here: `ExitBattle` runs the pass on
		## the overworld, so a Pokemon that levels up and then loses the fight
		## does not evolve at all.
		if not _evolvable.has(index):
			_evolvable.append(index)


## `LevelUpHappinessMod`: HAPPINESS_GAINLEVELATHOME when the Pokémon is standing
## on the landmark it was caught on and HAPPINESS_GAINLEVEL anywhere else. The
## compare is Crystal's alone; Gold and Silver inline HAPPINESS_GAINLEVEL with no
## row to reach for, which is also why their table is one row shorter.
func _gain_level_happiness(learner: Gen2BattleMon) -> void:
	var kind: int = HAPPINESS_GAINLEVEL
	if Gen2WorldState.is_crystal_profile(data) and landmark != LANDMARK_NONE \
			and learner.caught_location == landmark:
		kind = HAPPINESS_GAINLEVELATHOME
	learner.happiness = Gen2WorldPartyHost.change_happiness(data, learner.happiness, kind)


## What [param learner] is taught at exactly [param level]: into an empty slot
## unasked, or queued for [method learn_move] when every slot is full.
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


## The move an action commits a side to, Struggle standing in for a switch so
## the order needs no special case. A switching side never uses it.
func _move_for_action(side: int, action: Dictionary) -> int:
	if _is_switch(action) or _is_run(action) or _is_item(action):
		return Gen2Damage.STRUGGLE
	return move_for(side, int(action.get("slot", 0)))


## The slot PP is spent from, not always the one asked for: Encore forces the
## slot it locked in, as a release forces its move number, and only while that
## slot is still usable.
func effective_slot(side: int, requested_slot: int) -> int:
	var attacker: Gen2BattleMon = mon(side)
	if attacker.encored_slot >= 0 and attacker.can_use(attacker.encored_slot):
		return attacker.encored_slot
	return requested_slot


## Which move a side will actually use. A release turn answers with the charged
## move whatever slot was asked for, the cartridge choosing nothing that turn, and
## Rollout and rampage continuations force the move that started the chain;
## failing those, Encore answers with [method effective_slot]. An unusable slot
## answers Struggle, the cartridge's answer for a Pokémon with no PP anywhere,
## used here for an empty, spent or disabled slot too.
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


## Who goes first, as the two sides in the order they act. A switch is settled
## first at any speed or priority, the incoming Pokémon taking the other side's
## move, and two switches go to the player as outside a link battle. Otherwise
## priority decides, then a Quick Claw, then speed with stages applied, then a
## coin flip.
func order(chosen: Dictionary, actions: Dictionary = {}) -> Array:
	# A failed run is settled before the enemy moves, as a switch is: the turn is
	# spent as BATTLEPLAYERACTION_USEITEM, which resolves at once.
	var player_switching: bool = _is_switch(actions.get(PLAYER, {})) \
		or _is_run(actions.get(PLAYER, {})) \
		or _is_item(actions.get(PLAYER, {}))
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


## `DetermineMoveOrder`'s `.equal_priority` block: true for the player first,
## false for the enemy, null for a claw that said nothing, which falls through to
## speed. The player's claw is rolled first and the enemy's only when the player
## has none, except that with one on each side the enemy's roll is taken first.
func _quick_claw() -> Variant:
	var player_claw: bool = _held_effect(mon(PLAYER)) == Gen2HeldItem.QUICK_CLAW
	var enemy_claw: bool = _held_effect(mon(ENEMY)) == Gen2HeldItem.QUICK_CLAW
	if not player_claw and not enemy_claw:
		return null

	if player_claw and not enemy_claw:
		if _claw_fires(mon(PLAYER)):
			return true
		return null
	if enemy_claw and not player_claw:
		if _claw_fires(mon(ENEMY)):
			return false
		return null

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


## One side's move, as the list of commands its effect is made of: the effect byte
## picks a sequence out of [Gen2MoveEffect] and its commands run against a
## [Gen2Turn] until one ends the move. Announcing, spending, rolling, applying and
## fainting are all commands, which is why no move lives here.
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
	run_move_effect(turn)


## The command interpreter: `DoMove`'s own read cycle over the list an effect
## byte picks, with `SkipToBattleCommand` and `endloop`'s rewind to `critical`.
##
## `ResetTurn`, used by Metronome, Mirror Move and Sleep Talk: the called move
## replaces the working one and starts its list from the beginning, without the
## once-per-action status gate. A fresh [Gen2Turn] is that clean move-struct copy,
## keeping the acting side and the one event stream.
func run_move_effect(turn: Gen2Turn, depth: int = 0) -> void:
	var sequence: Array = Gen2MoveEffect.sequence_for(turn.effect())
	var counter: int = 0
	while counter < sequence.size():
		if turn.ended:
			return
		var command: StringName = sequence[counter]
		counter += 1
		# `SkipToBattleCommand` walks the pointer past the byte it matched, so
		# the command it was sent to find is not run either.
		if turn.skip_to != &"":
			if command == turn.skip_to:
				turn.skip_to = &""
			continue
		if trace_commands:
			command_trace.append(command)
		Gen2EffectCommands.run(command, turn)
		if turn.ended:
			return
		if turn.loop_back:
			# `.loop_back_to_critical` scans down for `critical` and resumes on
			# it, not behind it.
			turn.loop_back = false
			var back: int = sequence.rfind(Gen2EffectCommands.CRITICAL, counter - 1)
			if back < 0:
				push_error("a looping effect has no critical to return to")
				return
			counter = back
			continue
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
		run_move_effect(called_turn, depth + 1)
		return


## `PlayBattleMusic` (engine/battle/start_battle.asm) and the two routines it
## calls, `RegionCheck` and `IsGymLeader`. Kept here rather than on the screen
## because every input is battle state: `wBattleType`, `wOtherTrainerClass`,
## `wOtherTrainerID`, `wTimeOfDay` and the map's landmark.
##
## `MUSIC_SUICUNE_BATTLE` exists on Crystal alone; the two `BATTLETYPE_` rows in
## front of the trainer check are the only place either game reaches it, and
## Gold and Silver never write those types.
const MUSIC_NONE: int = 0x00
const MUSIC_KANTO_GYM_LEADER_BATTLE: int = 0x06
const MUSIC_KANTO_TRAINER_BATTLE: int = 0x07
const MUSIC_KANTO_WILD_BATTLE: int = 0x08
const MUSIC_JOHTO_WILD_BATTLE: int = 0x29
const MUSIC_JOHTO_TRAINER_BATTLE: int = 0x2A
const MUSIC_JOHTO_GYM_LEADER_BATTLE: int = 0x2E
const MUSIC_CHAMPION_BATTLE: int = 0x2F
const MUSIC_RIVAL_BATTLE: int = 0x30
const MUSIC_ROCKET_BATTLE: int = 0x31
const MUSIC_JOHTO_WILD_BATTLE_NIGHT: int = 0x4A
const MUSIC_SUICUNE_BATTLE: int = 0x64

## constants/trainer_constants.asm. The `trainerclass` indexes agree byte for
## byte between the two pins, so there is no profile conversion here.
const TRAINER_CLASS_RIVAL1: int = 0x09
const TRAINER_CLASS_CHAMPION: int = 0x10
const TRAINER_CLASS_GRUNTM: int = 0x1F
const TRAINER_CLASS_RIVAL2: int = 0x2A
const TRAINER_CLASS_RED: int = 0x3F
const TRAINER_CLASS_GRUNTF: int = 0x42
## `RIVAL2_2_CHIKORITA`. `trainerclass` restarts the id count at 1, so the
## Indigo Plateau rematch is the fourth id of the class and `jr c, .done` keeps
## the three below it on `MUSIC_RIVAL_BATTLE`.
const TRAINER_ID_RIVAL2_2_CHIKORITA: int = 4

## `data/trainers/leaders.asm`. `GymLeaders` falls through into
## `KantoGymLeaders`, so `IsGymLeader` matches both rows and `IsKantoGymLeader`
## only the second. CHAMPION and RED sit in the first list and are unreachable
## from the music check, which the file's own comment says.
const KANTO_GYM_LEADERS: Array[int] = [
	0x11, 0x12, 0x13, 0x15, 0x1A, 0x23, 0x2E, 0x40,
]
const JOHTO_GYM_LEADERS: Array[int] = [
	0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
	0x0B, 0x0D, 0x0E, 0x0F, TRAINER_CLASS_CHAMPION, TRAINER_CLASS_RED,
]

## A landmark no map has, so an untold battle matches nobody's caught location.
const LANDMARK_NONE: int = -1

## `constants/pokemon_data_constants.asm`, one-based the way `ChangeHappiness`
## takes it. Gold and Silver ship neither the second row nor the compare in
## front of it: their `.skip_active_mon_update` passes HAPPINESS_GAINLEVEL flat.
const HAPPINESS_GAINLEVEL: int = 0x01
const HAPPINESS_USEDITEM: int = 0x02
const HAPPINESS_GYMBATTLE: int = 0x04
const HAPPINESS_FAINTED: int = 0x06
const HAPPINESS_POISONFAINT: int = 0x07
const HAPPINESS_BEATENBYSTRONGFOE: int = 0x08
const HAPPINESS_OLDERCUT1: int = 0x09
const HAPPINESS_OLDERCUT2: int = 0x0A
const HAPPINESS_OLDERCUT3: int = 0x0B
const HAPPINESS_YOUNGCUT1: int = 0x0C
const HAPPINESS_YOUNGCUT2: int = 0x0D
const HAPPINESS_YOUNGCUT3: int = 0x0E
const HAPPINESS_BITTERPOWDER: int = 0x0F
const HAPPINESS_ENERGYROOT: int = 0x10
const HAPPINESS_REVIVALHERB: int = 0x11
const HAPPINESS_GROOMING: int = 0x12
const HAPPINESS_GAINLEVELATHOME: int = 0x13


## constants/landmark_constants.asm, Crystal-canonical like
## [constant Gen2WorldRadio.KANTO_LANDMARK], which is where the Gold and Silver
## conversion lives.
const LANDMARK_VICTORY_ROAD: int = 0x58


## `RegionCheck`, which is not `IsInJohto`: the Fast Ship counts as Johto, so
## does everything below `KANTO_LANDMARK`, and so does Victory Road and every
## landmark above it, because `cp LANDMARK_VICTORY_ROAD / jr c, .kanto` only
## takes the Kanto branch below that row.
##
## The `LANDMARK_SPECIAL` backup lookup in front of it is the six Cable Club
## rooms and is deliberately not modelled; see [method Gen2WorldAPI.landmark].
static func region_is_kanto(landmark_id: int, crystal: bool = true) -> bool:
	if landmark_id == Gen2WorldRadio.fast_ship_landmark(crystal):
		return false
	if landmark_id < Gen2WorldRadio.kanto_landmark(crystal):
		return false
	return landmark_id < Gen2WorldRadio.profile_landmark(LANDMARK_VICTORY_ROAD, crystal)


## `PlayBattleMusic`'s answer: the track a battle opens on.
##
## [param landmark_id] is `GetWorldMapLocation`'s, [param trainer_class] and
## [param trainer_id] are `wOtherTrainerClass` and `wOtherTrainerID` (class 0
## being a wild fight), and [param time_of_day] is `wTimeOfDay`.
static func battle_music(
	battle_kind: int,
	trainer_class: int,
	trainer_id: int,
	landmark_id: int,
	day_period: int,
	crystal: bool = true,
) -> int:
	# `ld de, MUSIC_SUICUNE_BATTLE` sits in front of both compares, so the
	# roaming branch reaches `.done` with the same track still in `de`.
	if battle_kind == BATTLETYPE_SUICUNE or battle_kind == BATTLETYPE_ROAMING:
		return MUSIC_SUICUNE_BATTLE
	var kanto: bool = region_is_kanto(landmark_id, crystal)
	if trainer_class <= 0:
		if kanto:
			return MUSIC_KANTO_WILD_BATTLE
		return MUSIC_JOHTO_WILD_BATTLE_NIGHT \
			if day_period == Gen2WorldPalette.TIME_NIGHT else MUSIC_JOHTO_WILD_BATTLE
	if trainer_class == TRAINER_CLASS_CHAMPION or trainer_class == TRAINER_CLASS_RED:
		return MUSIC_CHAMPION_BATTLE
	# `docs/bugs_and_glitches.md`: only the two grunt classes reach the Rocket
	# track, so an Executive or a Scientist falls through to the trainer rows.
	if trainer_class == TRAINER_CLASS_GRUNTM or trainer_class == TRAINER_CLASS_GRUNTF:
		return MUSIC_ROCKET_BATTLE
	if KANTO_GYM_LEADERS.has(trainer_class):
		return MUSIC_KANTO_GYM_LEADER_BATTLE
	if JOHTO_GYM_LEADERS.has(trainer_class):
		return MUSIC_JOHTO_GYM_LEADER_BATTLE
	if trainer_class == TRAINER_CLASS_RIVAL1:
		return MUSIC_RIVAL_BATTLE
	if trainer_class == TRAINER_CLASS_RIVAL2:
		return MUSIC_CHAMPION_BATTLE \
			if trainer_id >= TRAINER_ID_RIVAL2_2_CHIKORITA else MUSIC_RIVAL_BATTLE
	return MUSIC_KANTO_TRAINER_BATTLE if kanto else MUSIC_JOHTO_TRAINER_BATTLE
