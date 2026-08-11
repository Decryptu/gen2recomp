class_name Gen2MoveEffect
extends RefCounted

## What each move's effect byte makes it do, as a list of commands.
##
## The table the cartridge keeps in [code]data/moves/effects.asm[/code], to be
## read against it. A move number picks an effect byte and an effect byte picks a
## list.
##
## Almost every list is [constant NORMAL_HIT] with something inserted, which is
## the reason for keeping the shape: burn, paralysis, stat changes and the
## multi-hit moves are commands added to a list rather than branches added to the
## turn loop. The effect bytes are the cartridge's own.

## The effect bytes with a list of their own, numbered as the cartridge's move
## table numbers them.
##
## Recoil is here because Struggle needs it: without it two empty Pokémon never
## finish their battle. The rest are the status conditions in their two shapes, a
## move whose whole purpose is the status and a move that damages and leaves
## something behind on a roll.
const SLEEP: int = 1
const POISON_HIT: int = 2
## Absorb, Mega Drain, Giga Drain and Leech Life: half the calculated hit healed
## onto the attacker. Named for the disassembly's "LeechHit" label rather than a
## bare "drain", so this reads against `data/moves/effects_pointers.asm` line for
## line.
const LEECH_HIT: int = 3
const BURN_HIT: int = 4
const FREEZE_HIT: int = 5
const PARALYZE_HIT: int = 6
## Dream Eater: [constant LEECH_HIT]'s drain gated on the target being asleep.
## The gate lives inside [method Gen2EffectCommands._check_hit] rather than its
## own command, because that is where the cartridge's shared accuracy check puts
## it: against an awake target it reads as a miss, not a separate failure.
const DREAM_EATER: int = 8
const TOXIC: int = 33
const RECOIL_HIT: int = 48
const POISON: int = 66
const PARALYZE: int = 67

## The three effects that replace the move being executed and restart the
## effect interpreter. Mirror Move takes the opponent's last move, Metronome
## samples the full move table with its source exclusions, and Sleep Talk
## samples the user's own set while asleep. Their command implementations share
## [member Gen2Turn.called_move_number] and the restart loop in [Gen2Battle].
const MIRROR_MOVE: int = 9
const CONVERSION: int = 30
const MIMIC: int = 82
const METRONOME: int = 83
const CONVERSION_2: int = 93
const SKETCH: int = 95
const SLEEP_TALK: int = 97
const BIDE: int = 26
const RAGE: int = 81
const BIDE_MOVE: int = 117
const RAGE_MOVE: int = 99
const FUTURE_SIGHT: int = 148
const FUTURE_SIGHT_MOVE: int = 248
const PAY_DAY: int = 34
const TRANSFORM: int = 57
const PAY_DAY_MOVE: int = 6
const TRANSFORM_MOVE: int = 144

## Real move numbers read by the called-move commands.
const METRONOME_MOVE: int = 118
const MIRROR_MOVE_MOVE: int = 119
const CONVERSION_MOVE: int = 160
const MIMIC_MOVE: int = 102
const SKETCH_MOVE: int = 166
const CONVERSION_2_MOVE: int = 176
const SLEEP_TALK_MOVE: int = 214

## Two to five hits, the cartridge's own weighted roll
## ([method Gen2EffectCommands._roll_multi_hit_count]); and exactly two, always,
## for [constant DOUBLE_HIT]. Both point at the one command,
## [constant Gen2EffectCommands.MULTI_HIT], which tells the two apart by
## reading the effect byte back off the turn the same way the cartridge's own
## loop does, rather than needing two commands that differ only in a number.
const MULTI_HIT: int = 29
const DOUBLE_HIT: int = 44
## Twineedle: the same two hits as [constant DOUBLE_HIT], with a chance of
## poison rolled once before either lands and applied once after both do,
## never per hit.
const TWINEEDLE: int = 77

## Guillotine, Horn Drill and Fissure: an instant faint if it connects at all,
## which is its own accuracy rule rather than the move's stored one. See
## [method Gen2EffectCommands._ohko].
const OHKO: int = 38

## The four effects behind [constant Gen2EffectCommands.FIXED_DAMAGE], sharing
## one command the way the cartridge shares one, `BattleCommand_ConstantDamage`,
## reading the effect byte back to decide which number it is.
## Super Fang: half the target's current HP, floored, never less than one.
const SUPER_FANG: int = 40
## Sonicboom and Dragon Rage: the move's own power field, taken directly as the
## whole of the hit rather than as an input to the formula.
const STATIC_DAMAGE: int = 41
## Seismic Toss and Night Shade: the user's own level, exactly.
const LEVEL_DAMAGE: int = 87
## Psywave: a roll of the user's own, [method Gen2Damage.psywave_damage].
const PSYWAVE: int = 88

## The substatuses: flinching and confusion in both shapes, plus Hyper Beam, the
## only move that recharges. Numbers read off the real move table with
## [code]tools/dump_tables.gd[/code]: Rolling Kick, Headbutt, Bite, Bone Club and
## Hyper Fang carry 31; Confusion and Psybeam 76; Supersonic and Confuse Ray 49;
## Hyper Beam 80.
const FLINCH_HIT: int = 31
const CONFUSE_HIT: int = 76
const CONFUSE: int = 49
const RECHARGE_HIT: int = 80

## The two-turn moves: charge on the first turn, hit on the second. Razor Wind,
## Solarbeam, Fly and Dig share the plain shape; Sky Attack and Skull Bash each
## add one thing behind the hit, which is why they keep their own effect byte
## rather than folding into the plain one. Fly and Dig share 155 with each
## other and nothing else, since both leave the field for their charge turn on
## the cartridge. Their shared charge command now carries the two distinct
## semi-invulnerability flags and the incoming hit check reads them.
const RAZOR_WIND: int = 39
const SKY_ATTACK: int = 75
const SKULL_BASH: int = 145
const SOLARBEAM: int = 151
const FLY_OR_DIG: int = 155
const RAMPAGE: int = 27
const ROLLOUT: int = 117
const DEFENSE_CURL: int = 156
const SELFDESTRUCT: int = 7
const COUNTER: int = 0x59
const MIRROR_COAT: int = 0x90

## Real move numbers used by the shared two-turn and semi-invulnerability
## commands. These are kept here because the cartridge stores Fly and Dig under
## one effect byte, while the charge command still has to tell them apart.
const FLY_MOVE: int = 19
const DIG_MOVE: int = 91
## The other four moves `BattleCommand_Charge.UsedText` names by number, kept
## beside Fly and Dig for the same reason: the charge text is chosen by move
## rather than by effect, and Fly and Dig already share an effect byte.
const RAZOR_WIND_MOVE: int = 13
const SKY_ATTACK_MOVE: int = 143
const SKULL_BASH_MOVE: int = 130
const SOLARBEAM_MOVE: int = 76
const GUST_MOVE: int = 16
const WHIRLWIND_MOVE: int = 18
const THUNDER_MOVE: int = 87
const TWISTER_MOVE: int = 239
const EARTHQUAKE_MOVE: int = 89
const FISSURE_MOVE: int = 90
const MAGNITUDE_MOVE: int = 222
const THRASH_MOVE: int = 37
const PETAL_DANCE_MOVE: int = 80
const OUTRAGE_MOVE: int = 200
const ROLLOUT_MOVE: int = 205
const DEFENSE_CURL_MOVE: int = 111
## Rest, kept here for the same reason Fly and Dig are: four moves share
## [constant HEAL] and `BattleCommand_Heal` tells this one apart by number.
const REST_MOVE: int = 156

## None of the three needs any state this file has not already grown for
## something else: [Gen2BattleMon.reset_stages] for Haze,
## [method Gen2BattleMon.change_stage] and [method Gen2BattleMon.take_damage]
## for Belly Drum, and reading one side's stages to write the other's for
## Psych Up.
const HAZE: int = 25
const BELLY_DRUM: int = 142
const PSYCH_UP: int = 143

## Disable, Mist, Focus Energy, Attract and Encore, numbered off the real
## cartridge with [code]tools/dump_tables.gd -- gold moves[/code], since Gen II
## does not share Generation 1's numbering. Mist and Focus Energy need nothing
## new; Disable, Attract and Encore are what
## [member Gen2BattleMon.disabled_slot], [member Gen2BattleMon.encored_slot] and
## [method Gen2BattleMon.gender] exist for.
const DISABLE: int = 86
const MIST: int = 46
const FOCUS_ENERGY: int = 47
const ATTRACT: int = 120
const ENCORE: int = 90

## The two trapping effects, numbered the same way. Bind, Wrap, Fire Spin, Clamp
## and Whirlpool carry the first; Mean Look and Spider Web the second.
const TRAP_TARGET: int = 42
const MEAN_LOOK: int = 106

## The heal family. [constant HEAL] is Recover, Softboiled, Milk Drink and Rest
## sharing `BattleCommand_Heal`; the other three are one command,
## `BattleCommand_TimeBasedHealContinue`, entered at three different labels that
## differ only in the time of day they ask for.
const HEAL: int = 32
const MORNING_SUN: int = 132
const SYNTHESIS: int = 133
const MOONLIGHT: int = 134

## The three weather moves and the two moves that read the weather back.
## [constant SOLARBEAM] is already above, since it was a two-turn move before it
## was a weather one.
const SANDSTORM: int = 115
const RAIN_DANCE: int = 136
const SUNNY_DAY: int = 137
const THUNDER: int = 152

## The three side-of-the-field screens. Light Screen and Reflect share
## `BattleCommand_Screen`, which tells them apart by this byte, so the two are
## one command and two lists that read the same.
const LIGHT_SCREEN: int = 35
const REFLECT: int = 65
const SAFEGUARD: int = 124

## Perish Song, which is neither a screen nor a status: a count on each Pokémon
## on the field that a switch escapes.
const PERISH_SONG: int = 114

## Substitute: a quarter of the user's own health standing in front of it, with
## hit points of its own on [member Gen2BattleMon.substitute_hp]. Eighteen
## commands ask whether one is up and every one of them refuses on a yes.
const SUBSTITUTE: int = 79

## The three residuals `ResidualDamage` charges behind burn and poison, and
## Spikes, which is field state on [member Gen2Battle.screens] instead. Rapid Spin
## is the only move that undoes any of them.
const LEECH_SEED: int = 84
const NIGHTMARE: int = 107
const CURSE: int = 109
const SPIKES: int = 112
const RAPID_SPIN: int = 129

## Protect and Detect are one effect byte under two move numbers, and Endure is
## the byte beside it: `BattleCommand_Endure` is `ProtectChance` and a different
## flag. Both carry priority 3 in `MoveEffectPriorities`, which is why
## [constant Gen2Battle.EFFECT_PRIORITIES] named them before either was written.
const PROTECT: int = 111
const ENDURE: int = 116

## Destiny Bond, which rolls nothing and never fails: the flag goes up and the
## opponent's own `BattleCommand_CheckFaint` reads it.
const DESTINY_BOND: int = 98

## Whirlwind and Roar, which are one effect byte and two endings: against a
## trainer they drag a random party member out, and against a wild they end the
## battle outright. Priority 0, so the user almost always moves second, which the
## command then requires of itself.
const FORCE_SWITCH: int = 28

## Roar's own move number. `.succeed` picks between the two lines by comparing
## the move's animation byte against `ROAR`, and every move here animates as
## itself, so the number is what tells the pair apart.
const ROAR_MOVE: int = 46

## Baton Pass, the one effect whose player half cannot be resolved inside the
## turn that started it.
const BATON_PASS: int = 127

## `EFFECT_NORMAL_HIT` as a byte rather than [constant NORMAL_HIT]'s list:
## `DoSubstituteDamage` stamps it over the move's own once a doll has broken.
const NORMAL_HIT_EFFECT: int = 0

## Beat Up: one hit per standing, healthy member of the user's own party, each
## worked out from that member's base Attack and level rather than the field
## Pokémon's. The one list with no `stab`, so no same-type bonus, no weather and
## no matchup.
const BEAT_UP: int = 154

## Pain Split, which averages the two Pokémon's health rather than moving damage
## across the field.
const PAIN_SPLIT: int = 91

## Lock On and Mind Reader, one byte: a flag on the *target* that makes the
## aimer's next move connect, read and spent by
## [method Gen2EffectCommands._check_hit].
const LOCK_ON: int = 94

## Spite, which takes two to five PP off the slot holding the target's last move.
const SPITE: int = 100

## Thief, which takes the target's held item when the thief has none of its own.
const THIEF: int = 105

## Foresight, whose flag drops the target's evasion out of the accuracy sum and
## opens the two Ghost immunities the matchup table keeps past its own marker.
const FORESIGHT: int = 113

## Pursuit, which doubles against a side that is leaving. Two halves: the command
## reads the switching flag, and [method Gen2Battle.take_actions] is what runs
## this move early, in front of the switch it answers.
const PURSUIT: int = 128

## Teleport, which ends a wild battle as a draw with the user out of it. Refused
## outright in a trainer battle, since there is nowhere to teleport away from.
const TELEPORT: int = 153

## Swift, Faint Attack and Vital Throw, which point at `NormalHit` like any other
## attack: their whole difference is one comparison inside
## [method Gen2EffectCommands._check_hit], so this byte has no list.
const ALWAYS_HIT: int = 17

## Jump Kick and Hi Jump Kick, the same shape: `NormalHit` plus the eighth of the
## damage a miss costs the user, which is the tail of
## `BattleCommand_FailureText`.
const JUMP_KICK: int = 45

## The four that write a power over the move's own. Return and Frustration read
## the user's happiness from either end, Magnitude rolls one of seven, and Hidden
## Power reads a power and a type out of the user's DVs.
const RETURN: int = 121
const FRUSTRATION: int = 123
const MAGNITUDE: int = 126
const HIDDEN_POWER: int = 135

## Present, which is a fourth power row that heals the target instead.
const PRESENT: int = 122

## Flail and Reversal, which share [constant Gen2EffectCommands.FIXED_DAMAGE]
## with the four constant-damage effects and are the only branch of it that runs
## the ordinary formula: the power comes off how much health the user has left.
const REVERSAL: int = 99

## Fury Cutter and Triple Kick, the two that multiply a finished figure rather
## than replace it.
const FURY_CUTTER: int = 119
const TRIPLE_KICK: int = 104

## False Swipe, which leaves what it hits standing on one hit point.
const FALSE_SWIPE: int = 101

## Heal Bell, which is the only move that reaches the party behind the Pokémon on
## the field.
const HEAL_BELL: int = 102

## Snore, Tri Attack and Splash. Snore fails unless its user is asleep, Tri
## Attack picks one of three statuses, and Splash does nothing and says so.
const SNORE: int = 92
const TRI_ATTACK: int = 36
const SPLASH: int = 85

## Flame Wheel and Sacred Fire, one list: a burn chance with the user's own thaw
## in front of the faint check.
const FLAME_WHEEL: int = 108
const SACRED_FIRE: int = 125

## Steel Wing: the raise-on-hit run's missing seventh, since
## [constant ATTACK_UP_HIT] and [constant ALL_STATS_UP_HIT] were the only two
## built.
const DEFENSE_UP_HIT: int = 138

## The four that double against a target the ordinary hit would have missed or
## barely grazed. Twister and Stomp carry a flinch chance with it; Gust and
## Earthquake carry nothing, and are the two lists that leave `kingsrock` out.
const TWISTER: int = 146
const STOMP: int = 150
const GUST: int = 149
const EARTHQUAKE: int = 147

## Swagger, the one list that raises a stat on the side it is not acting from.
const SWAGGER: int = 118

## An ordinary attack: say it, spend it, work it out, roll it, apply it, and see
## who is standing. Everything else is this with steps moved.
const NORMAL_HIT: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Bide's first command either ends a storage turn or prepares the stored
## double-damage release. Its initial pass reaches UnleashEnergy and starts the
## two-or-three-turn lock.
const BIDE_SEQUENCE: Array = [
	Gen2EffectCommands.STORE_ENERGY,
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.UNLEASH_ENERGY,
	Gen2EffectCommands.RESET_TYPE_MATCHUP,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.BUILD_OPPONENT_RAGE,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

const RAGE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.RAGE_DAMAGE,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.RAGE,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.BUILD_OPPONENT_RAGE,
	Gen2EffectCommands.END_MOVE,
]

const FUTURE_SIGHT_SEQUENCE: Array = [
	Gen2EffectCommands.CHECK_FUTURE_SIGHT,
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.FUTURE_SIGHT,
	Gen2EffectCommands.END_MOVE,
]

const PAY_DAY_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.PAY_DAY,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.BUILD_OPPONENT_RAGE,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

const TRANSFORM_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.TRANSFORM,
	Gen2EffectCommands.END_MOVE,
]

## Counter and Mirror Coat validate the damage the opponent dealt earlier in
## this action pair, then apply twice that uncapped figure. Their command owns
## the failure path, so neither one uses the ordinary accuracy or damage steps.
const COUNTER_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.COUNTER,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

const MIRROR_COAT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.MIRROR_COAT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## The cartridge runs Selfdestruct after the shared hit check and before its
## failure text and damage application. Keeping that order means the user faints
## even when the target is immune or the accuracy roll misses.
const SELFDESTRUCT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.SELFDESTRUCT,
	Gen2EffectCommands.MOVE_ANIM_NO_SUB,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## The same list with the recoil taken between the hit and the faint, so that an
## attacker that goes down to its own recoil is reported alongside the defender
## rather than after it.
const RECOIL_HIT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.RECOIL,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## A move that is nothing but a status: no damage, and the status is the whole of
## what it does. Sleep is the odd one of the three, because nothing is immune to
## it: there is no matchup step in its list, where the other two have one.
const SLEEP_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.CHECK_SAFEGUARD,
	Gen2EffectCommands.SLEEP_TARGET,
	Gen2EffectCommands.END_MOVE,
]

const POISON_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_SAFEGUARD,
	Gen2EffectCommands.POISON_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## Toxic: the same shape as [constant POISON_SEQUENCE], with the command that
## starts the ramping counter in place of the one that leaves a flat poison.
const TOXIC_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_SAFEGUARD,
	Gen2EffectCommands.TOXIC_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## The matchup before the roll rather than after it, which is the order the
## cartridge lists them in and the reason Thunder Wave against a Ground type says
## it had no effect rather than that it missed.
const PARALYZE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.CHECK_SAFEGUARD,
	Gen2EffectCommands.PARALYZE_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## Supersonic and Confuse Ray: no power, so no matchup step either, the same
## shape as [constant SLEEP_SEQUENCE].
const CONFUSE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.CHECK_SAFEGUARD,
	Gen2EffectCommands.CONFUSE_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## Hyper Beam: an ordinary attack with the recharge locked in behind the hit,
## which is why it sits after [constant Gen2EffectCommands.CHECK_HIT] rather
## than before it. A miss ends the move at [constant Gen2EffectCommands.CHECK_HIT]
## the way any other miss does, so a missed Hyper Beam costs nothing extra.
const RECHARGE_HIT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.RECHARGE,
	Gen2EffectCommands.END_MOVE,
]

## Razor Wind, Solarbeam, Fly and Dig: a normal attack with the charge in front
## of it. The first time this runs, [constant Gen2EffectCommands.CHARGE_MOVE]
## ends the move before [constant Gen2EffectCommands.DAMAGE_CALC] is reached;
## the second time, it clears the lock and everything after it is
## [constant NORMAL_HIT] again.
const CHARGE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHARGE_MOVE,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Thrash, Petal Dance and Outrage use one shared rampage state. The first turn
## starts the state; later turns are forced through [method Gen2Battle.move_for]
## and this command counts them down. The cartridge does not clear the state on
## a miss, so the hit check is allowed to finish before the next turn's choice.
const RAMPAGE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.RAMPAGE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Rollout increases its power after the hit has been checked and before the
## damage variation is applied. This command also ends the chain on a miss and
## counts successful hits so the next call can select the right multiplier.
const ROLLOUT_SEQUENCE: Array = [
	Gen2EffectCommands.ROLLOUT_CHECK,
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.ROLLOUT_POWER,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Defense Curl raises Defense and leaves the Curl flag even when Defense is
## already at its maximum. Rollout reads the flag from the attacker later.
const DEFENSE_CURL_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.DEFENSE_UP,
	Gen2EffectCommands.CURL,
	Gen2EffectCommands.STAT_UP_ANIM,
	Gen2EffectCommands.STAT_UP_MESSAGE,
	Gen2EffectCommands.STAT_UP_FAIL_TEXT,
	Gen2EffectCommands.END_MOVE,
]

## Sky Attack: the same charge, with a flinch chance behind the hit exactly the
## way [constant FLINCH_HIT] carries one. The real cartridge's own move table
## gives it a chance of zero, which is never, so this is written the way the
## disassembly has it rather than left out: a flinch that cannot come up reads
## the same as no flinch at all, and nothing here should assume that stays true
## forever.
const SKY_ATTACK_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHARGE_MOVE,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.EFFECT_CHANCE,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.FLINCH_TARGET,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Skull Bash: the same charge, with the user's own Defense raised by one stage
## behind the hit landing, which is the one thing that sets it apart from
## [constant CHARGE_SEQUENCE].
const SKULL_BASH_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHARGE_MOVE,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.DEFENSE_UP,
	Gen2EffectCommands.STAT_UP_MESSAGE,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

const HAZE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.HAZE,
	Gen2EffectCommands.END_MOVE,
]

const BELLY_DRUM_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.BELLY_DRUM,
	Gen2EffectCommands.END_MOVE,
]

const PSYCH_UP_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.PSYCH_UP,
	Gen2EffectCommands.END_MOVE,
]

## Mist and Focus Energy: no roll at all, the same shape as [constant HAZE_SEQUENCE]
## and [constant BELLY_DRUM_SEQUENCE] above, since both fail on their own
## precondition (already active) rather than ever missing.
const MIST_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.MIST,
	Gen2EffectCommands.END_MOVE,
]

const FOCUS_ENERGY_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.FOCUS_ENERGY,
	Gen2EffectCommands.END_MOVE,
]

## Disable, Attract and Encore all roll to connect before they do anything:
## the cartridge's own sequences for all three are
## [code]usedmovetext, doturn, checkhit, <effect>, endmove[/code], read off
## [code]data/moves/effects.asm[/code] directly rather than assumed from the
## shape of the other three above.
const DISABLE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.DISABLE,
	Gen2EffectCommands.END_MOVE,
]

const ATTRACT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.ATTRACT,
	Gen2EffectCommands.END_MOVE,
]

const ENCORE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.ENCORE,
	Gen2EffectCommands.END_MOVE,
]

## An ordinary attack that binds what it hits: `TrapTarget` is `NormalHit` with
## `traptarget` in `kingsrock`'s place, behind the faint check, so a knocked out
## target is never bound.
const TRAP_TARGET_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.TRAP_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## The heal family, the same four-step shape as the weather moves: announce,
## spend, heal. Neither list rolls accuracy, so the 100% every one of the seven
## carries is never read. The cartridge's own lists open with `checkobedience`,
## which this engine does not model and no other list here carries either.
const HEAL_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.HEAL,
	Gen2EffectCommands.END_MOVE,
]

## Morning Sun, Synthesis and Moonlight share one list as they share one command:
## the time of day each wants is read back off the effect byte, the way
## [constant Gen2EffectCommands.FIXED_DAMAGE] reads which of its four figures it
## is.
const TIME_HEAL_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.TIMED_HEAL,
	Gen2EffectCommands.END_MOVE,
]

## The three weather moves, which are the shortest lists in the game: announce,
## spend, change the sky. None of them rolls accuracy, so the 90% Rain Dance and
## Sunny Day carry and Sandstorm's 100% are all never read.
const START_RAIN_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.START_RAIN,
	Gen2EffectCommands.END_MOVE,
]

const START_SUN_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.START_SUN,
	Gen2EffectCommands.END_MOVE,
]

const START_SANDSTORM_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.START_SANDSTORM,
	Gen2EffectCommands.END_MOVE,
]

## The three screens, which are the weather moves' shape with a different
## command. `LightScreen:` and `Reflect:` are one label with two entries in
## `data/moves/effects.asm`, so both point here; none of the three rolls
## accuracy.
const SCREEN_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.SCREEN,
	Gen2EffectCommands.END_MOVE,
]

const SAFEGUARD_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.SAFEGUARD,
	Gen2EffectCommands.END_MOVE,
]

## Perish Song, the same four steps again. Its own accuracy byte is 100 and no
## list step rolls against it, so the song never misses.
const PERISH_SONG_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.PERISH_SONG,
	Gen2EffectCommands.END_MOVE,
]

## Substitute, Nightmare, Curse and Spikes: the same four steps
## [constant PERISH_SONG_SEQUENCE] has. None of them rolls accuracy, so the 100%
## all four carry in the move table is never read.
const SUBSTITUTE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.SUBSTITUTE,
	Gen2EffectCommands.END_MOVE,
]

const NIGHTMARE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.NIGHTMARE,
	Gen2EffectCommands.END_MOVE,
]

const CURSE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CURSE,
	Gen2EffectCommands.END_MOVE,
]

const SPIKES_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.SPIKES,
	Gen2EffectCommands.END_MOVE,
]

## The same list with a roll in front: `LeechSeed` is the one of the five that
## carries `checkhit`, and its 90% is the only accuracy byte among them read.
const LEECH_SEED_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.LEECH_SEED,
	Gen2EffectCommands.END_MOVE,
]

## [constant NORMAL_HIT] with `clearhazards` between the damage and the faint
## check, which is where the source puts it: a spin that knocks its target out
## still sheds the seed, the spikes and the bind on its own side.
const RAPID_SPIN_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CLEAR_HAZARDS,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Protect, Detect, Endure and Destiny Bond: four moves whose whole list is one
## command, the shape `HEAL_SEQUENCE` above already has. None of the three rolls
## accuracy, so the 100% each stores is never read.
const PROTECT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.PROTECT,
	Gen2EffectCommands.END_MOVE,
]

const ENDURE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.ENDURE,
	Gen2EffectCommands.END_MOVE,
]

const DESTINY_BOND_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.DESTINY_BOND,
	Gen2EffectCommands.END_MOVE,
]

## Baton Pass: the command is the whole move, and `endmove` behind it does
## nothing, which is what lets the turn stop inside it and pick up later.
const BATON_PASS_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.BATON_PASS,
	Gen2EffectCommands.END_MOVE,
]

## Whirlwind and Roar. `checkhit` is the one thing in front of the command.
##
## The list carries no `failuretext`, so on the cartridge a missed Whirlwind
## reaches `forceswitch`, takes `.missed` and says "But it failed!" with no miss
## line at all. Here `checkhit` ends the move and announces the miss, which is
## the standing `failuretext` divergence and not a second one: nothing switches
## either way, only the line differs. Every other list without a `failuretext`,
## `DoParalyze` among them, already reads this way.
const FORCE_SWITCH_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.FORCE_SWITCH,
	Gen2EffectCommands.END_MOVE,
]

## Pain Split, Lock On, Mind Reader, Spite and Foresight: four lists that are the
## same five steps with one command swapped, which is why they are written as one
## helper rather than four constants.
static func _status_command_sequence(command: StringName) -> Array:
	return [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.CHECK_HIT,
		command,
		Gen2EffectCommands.END_MOVE,
	]


## Teleport, the one of the five with no `checkhit` at all: the move spends its PP
## and then decides for itself, out of the two levels, whether the user gets away.
const TELEPORT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.TELEPORT,
	Gen2EffectCommands.END_MOVE,
]

## Thief: [constant NORMAL_HIT] with the move's own chance behind the roll and the
## steal between the damage and the faint check, where `thief` sits.
const THIEF_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.EFFECT_CHANCE,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.THIEF,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Pursuit: [constant NORMAL_HIT] with the doubling between the spread and the
## roll, which is the one place the finished figure can still be multiplied.
const PURSUIT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.PURSUIT,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Beat Up. The `startloop`/`endloop` pair is inside
## [constant Gen2EffectCommands.BEAT_UP], as [constant Gen2EffectCommands.MULTI_HIT]
## already holds its own, and `endloop` jumps back to `critical` rather than to
## the top, so `checkhit` is outside the loop and rolls once for the whole move.
##
## No `damagestats` and no `stab`: the command loads the formula's two stats
## itself, from base stats rather than from either Pokémon's real ones, and
## nothing multiplies the result by a matchup. `CheckTurn` leaves `wTypeModifier`
## at `EFFECTIVE` for the whole turn, so `supereffectivetext` says nothing.
const BEAT_UP_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.BEAT_UP,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Thunder: a paralysis chance behind the hit, with its own accuracy step ahead
## of the roll. Without that step Thunder would be an ordinary attack, which is
## what it was here before the weather existed to read.
const THUNDER_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.THUNDER_ACCURACY,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.EFFECT_CHANCE,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.PARALYZE_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## Solarbeam: [constant CHARGE_SEQUENCE] with the sun's own way out in front of
## the charge, exactly where `skipsuncharge` sits in front of `charge`.
const SOLARBEAM_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.SKIP_SUN_CHARGE,
	Gen2EffectCommands.CHARGE_MOVE,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Mean Look and Spider Web, which are four commands and no accuracy roll:
## `MeanLook` has no `checkhit`, so the 100% both moves carry in the move table
## is never consulted and neither one can miss.
const MEAN_LOOK_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.ARENA_TRAP,
	Gen2EffectCommands.END_MOVE,
]

## [constant MULTI_HIT] and [constant DOUBLE_HIT]: the accuracy roll happens
## once, the way the cartridge's own script checks it before the loop that
## repeats the hit even starts, and everything from the critical roll onward
## is [constant Gen2EffectCommands.MULTI_HIT]'s own job, hit by hit.
const MULTI_HIT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MULTI_HIT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Twineedle: the same two hits, with the poison roll taken once right after
## the accuracy check, in the same slot [method Gen2MoveEffect._secondary]
## already puts a secondary effect's roll, and applied once at the very end,
## after both hits, rather than after either one on its own.
const TWINEEDLE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.EFFECT_CHANCE,
	Gen2EffectCommands.MULTI_HIT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.POISON_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## [constant LEECH_HIT] and [constant DREAM_EATER]: the same list, since
## Dream Eater's own "must be asleep" rule lives inside
## [constant Gen2EffectCommands.CHECK_HIT] rather than in a step of its own,
## the same place the real cartridge's shared accuracy check puts it.
const DRAIN_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.DRAIN_TARGET,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Dream Eater is the same list without the King's Rock step, which is the one
## thing `DreamEater` and `LeechHit` do not share. The two shared a sequence here
## until the item existed to tell them apart.
const DREAM_EATER_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.DRAIN_TARGET,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.END_MOVE,
]

## [constant SUPER_FANG], [constant STATIC_DAMAGE], [constant LEVEL_DAMAGE] and
## [constant PSYWAVE]: one shared list, the way the cartridge shares one script
## (`StaticDamage:`) across all four labels.
##
## The shortest damaging list in the game: no critical, no stats, no formula, no
## matchup and no spread, because the number is
## [constant Gen2EffectCommands.FIXED_DAMAGE]'s to decide outright.
## [constant Gen2EffectCommands.RESET_TYPE_MATCHUP] behind the hit check is what
## answers an immunity and flattens the effectiveness none of the four earned.
const FIXED_DAMAGE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.FIXED_DAMAGE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.RESET_TYPE_MATCHUP,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Guillotine, Horn Drill and Fissure. [constant Gen2EffectCommands.OHKO] does
## its own accuracy roll and its own damage, so nothing after
## [constant CHECK_IMMUNE] is shared with an ordinary attack.
const OHKO_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.OHKO,
	Gen2EffectCommands.END_MOVE,
]


## Return and Frustration, which are [constant NORMAL_HIT] with the power step
## the cartridge writes into `wPlayerMoveStruct` between `damagestats` and
## `damagecalc`. Two lists rather than one, because the two power steps are two
## routines and reading the effect byte back would be the same table twice.
const RETURN_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.HAPPINESS_POWER,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

const FRUSTRATION_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.FRUSTRATION_POWER,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Magnitude: the same shape again, with the doubling against a target that is
## underground behind the spread rather than the flinch a secondary effect would
## have there.
const MAGNITUDE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.GET_MAGNITUDE,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.DOUBLE_DAMAGE,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Hidden Power, which carries no `damagestats` of its own: the command runs it
## once it has decided what type the move is, since the two stats depend on
## whether that type is physical or special.
const HIDDEN_POWER_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.HIDDEN_POWER,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Present, whose command owns the matchup and the failure itself, which is why
## the list has no `moveanim`: three of the four rows are a hit and the fourth is
## a heal, and each animates from inside the command.
const PRESENT_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.PRESENT,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Flail and Reversal: `constantdamage` picks the power and runs the formula, and
## `stab` behind it is what keeps the matchup a fixed-damage move throws away.
const REVERSAL_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.FIXED_DAMAGE,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Fury Cutter, whose doubling sits between the matchup and the spread, so the
## spread is taken from the doubled figure and a run of hits is not smoothed by
## it.
const FURY_CUTTER_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.FURY_CUTTER,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Triple Kick, which is a loop like the multi-hit moves and unlike them in
## rolling its own accuracy per kick and multiplying each kick by which one it
## is. [constant Gen2EffectCommands.TRIPLE_KICK] does the multiply and
## [constant Gen2EffectCommands.KICK_COUNTER] walks the count on.
const TRIPLE_KICK_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.TRIPLE_KICK,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.MOVE_ANIM_NO_SUB,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KICK_COUNTER,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## False Swipe, whose clamp sits between the spread and the accuracy roll, so the
## number it cuts down is the finished one.
const FALSE_SWIPE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.FALSE_SWIPE,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Heal Bell and Splash, both four steps, and both moves whose whole effect is
## one command.
const HEAL_BELL_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.HEAL_BELL,
	Gen2EffectCommands.END_MOVE,
]

const SPLASH_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.SPLASH,
	Gen2EffectCommands.END_MOVE,
]

## Each is the source's four-step wrapper. The last command is normally never
## reached on success because the called-move command restarts the interpreter;
## it remains in the list for the same reason it does in `effects.asm`, to end a
## failed call normally.
const MIRROR_MOVE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.MIRROR_MOVE,
	Gen2EffectCommands.END_MOVE,
]

const MIMIC_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MIMIC,
	Gen2EffectCommands.END_MOVE,
]

const METRONOME_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.METRONOME,
	Gen2EffectCommands.END_MOVE,
]

const SLEEP_TALK_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.SLEEP_TALK,
	Gen2EffectCommands.END_MOVE,
]

const SKETCH_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.SKETCH,
	Gen2EffectCommands.END_MOVE,
]

const CONVERSION_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CONVERSION,
	Gen2EffectCommands.END_MOVE,
]

const CONVERSION_2_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.CONVERSION_2,
	Gen2EffectCommands.END_MOVE,
]

## Snore: a flinch chance whose own command sits between the roll and the
## animation, so a Snore used awake fails before anything is drawn.
const SNORE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.EFFECT_CHANCE,
	Gen2EffectCommands.SNORE,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.FLINCH_TARGET,
	Gen2EffectCommands.KINGS_ROCK,
	Gen2EffectCommands.END_MOVE,
]

## Tri Attack, which is [constant NORMAL_HIT] with the three-way status roll in
## `kingsrock`'s place and no `effectchance` step of its own: the command calls
## it itself, which is `BattleCommand_TriStatusChance`'s own first instruction.
const TRI_ATTACK_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.EFFECT_CHANCE,
	Gen2EffectCommands.TRI_STATUS_CHANCE,
	Gen2EffectCommands.END_MOVE,
]

## Flame Wheel and Sacred Fire: a burn chance with the user's own thaw in front
## of the faint check, which is the one place a list puts `defrost`.
const FLAME_WHEEL_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.EFFECT_CHANCE,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.DEFROST,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.BURN_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## Gust and Earthquake: [constant NORMAL_HIT] with the doubling behind the spread
## and no King's Rock, which the two lists really do leave out.
const DOUBLE_DAMAGE_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.DOUBLE_DAMAGE,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.END_MOVE,
]

## Twister and Stomp: the same list with the flinch chance both carry.
const DOUBLE_DAMAGE_FLINCH_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CRITICAL,
	Gen2EffectCommands.DAMAGE_STATS,
	Gen2EffectCommands.DAMAGE_CALC,
	Gen2EffectCommands.STAB,
	Gen2EffectCommands.DAMAGE_VARIATION,
	Gen2EffectCommands.DOUBLE_DAMAGE,
	Gen2EffectCommands.CHECK_IMMUNE,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.EFFECT_CHANCE,
	Gen2EffectCommands.MOVE_ANIM,
	Gen2EffectCommands.APPLY_DAMAGE,
	Gen2EffectCommands.CHECK_FAINT,
	Gen2EffectCommands.FLINCH_TARGET,
	Gen2EffectCommands.END_MOVE,
]

## Swagger, the one list that acts from the other side of the field for part of
## its run: the two-stage Attack raise is the ordinary `attackup2` with the turn
## switched around it, so the target is raised and then confused.
const SWAGGER_SEQUENCE: Array = [
	Gen2EffectCommands.USED_MOVE_TEXT,
	Gen2EffectCommands.DO_TURN,
	Gen2EffectCommands.CHECK_HIT,
	Gen2EffectCommands.SWITCH_TURN,
	Gen2EffectCommands.ATTACK_UP_2,
	Gen2EffectCommands.SWITCH_TURN,
	Gen2EffectCommands.STAT_UP_ANIM,
	Gen2EffectCommands.SWITCH_TURN,
	Gen2EffectCommands.STAT_UP_MESSAGE,
	Gen2EffectCommands.SWITCH_TURN,
	Gen2EffectCommands.CONFUSE_TARGET,
	Gen2EffectCommands.END_MOVE,
]


## An attack that leaves something behind if its roll comes up. The damage is
## done either way: the roll sits between the hit and the status, so a failed one
## costs [param trailing] and nothing else. Most callers leave one command
## behind; a stat change leaves two, the change and its message, because a
## secondary effect never carries the fail-text step a status move's own
## sequence has.
static func _secondary(trailing: Array) -> Array:
	return [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.CRITICAL,
		Gen2EffectCommands.DAMAGE_STATS,
		Gen2EffectCommands.DAMAGE_CALC,
		Gen2EffectCommands.STAB,
		Gen2EffectCommands.DAMAGE_VARIATION,
		Gen2EffectCommands.CHECK_IMMUNE,
		Gen2EffectCommands.CHECK_HIT,
		Gen2EffectCommands.EFFECT_CHANCE,
		Gen2EffectCommands.MOVE_ANIM,
		Gen2EffectCommands.APPLY_DAMAGE,
		Gen2EffectCommands.CHECK_FAINT,
	] + trailing + [Gen2EffectCommands.END_MOVE]


## Where each run of seven starts, in the cartridge's own numbering. The seven
## across a run are [constant Gen2BattleMon.STAGED_STATS] followed by
## [constant Gen2BattleMon.STAGED_ODDS], which is also the order
## [Gen2EffectCommands] keeps its per-stat command lists in, so a run and an
## index into those lists are the same number.
const STAT_UP_BASE: int = 10
const STAT_DOWN_BASE: int = 18
const STAT_UP_2_BASE: int = 50
const STAT_DOWN_2_BASE: int = 58
const STAT_DOWN_HIT_BASE: int = 68
const STAT_RUN_LENGTH: int = 7

## The second of that run, `EFFECT_DEFENSE_DOWN_HIT`, which is the only one whose
## list differs from its six neighbours.
const DEFENSE_DOWN_HIT: int = STAT_DOWN_HIT_BASE + 1

## The two effect bytes a run does not reach. Metal Claw raises the user's
## Attack on a roll and Ancientpower raises all five of them, and neither sits
## in a run of its own: 139 falls where an eighth "down by one, on a hit" stat
## would if there were one, and 140 is the byte after it.
const ATTACK_UP_HIT: int = 139
const ALL_STATS_UP_HIT: int = 140

const STAT_UP_COMMANDS: Array = [
	Gen2EffectCommands.ATTACK_UP, Gen2EffectCommands.DEFENSE_UP,
	Gen2EffectCommands.SPEED_UP, Gen2EffectCommands.SP_ATTACK_UP,
	Gen2EffectCommands.SP_DEFENSE_UP, Gen2EffectCommands.ACCURACY_UP,
	Gen2EffectCommands.EVASION_UP,
]
const STAT_UP_2_COMMANDS: Array = [
	Gen2EffectCommands.ATTACK_UP_2, Gen2EffectCommands.DEFENSE_UP_2,
	Gen2EffectCommands.SPEED_UP_2, Gen2EffectCommands.SP_ATTACK_UP_2,
	Gen2EffectCommands.SP_DEFENSE_UP_2, Gen2EffectCommands.ACCURACY_UP_2,
	Gen2EffectCommands.EVASION_UP_2,
]
const STAT_DOWN_COMMANDS: Array = [
	Gen2EffectCommands.ATTACK_DOWN, Gen2EffectCommands.DEFENSE_DOWN,
	Gen2EffectCommands.SPEED_DOWN, Gen2EffectCommands.SP_ATTACK_DOWN,
	Gen2EffectCommands.SP_DEFENSE_DOWN, Gen2EffectCommands.ACCURACY_DOWN,
	Gen2EffectCommands.EVASION_DOWN,
]
const STAT_DOWN_2_COMMANDS: Array = [
	Gen2EffectCommands.ATTACK_DOWN_2, Gen2EffectCommands.DEFENSE_DOWN_2,
	Gen2EffectCommands.SPEED_DOWN_2, Gen2EffectCommands.SP_ATTACK_DOWN_2,
	Gen2EffectCommands.SP_DEFENSE_DOWN_2, Gen2EffectCommands.ACCURACY_DOWN_2,
	Gen2EffectCommands.EVASION_DOWN_2,
]

## A status move that only raises a stat: it cannot miss, so there is no roll in
## its list, only the change, its message, and the text for when it was already
## at the top.
static func _stat_up_sequence(command: StringName) -> Array:
	return [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		command,
		Gen2EffectCommands.STAT_UP_ANIM,
		Gen2EffectCommands.STAT_UP_MESSAGE,
		Gen2EffectCommands.STAT_UP_FAIL_TEXT,
		Gen2EffectCommands.END_MOVE,
	]


## A status move that lowers the foe's stat: it can miss, which is the one
## difference from the list above and the reason Screech has a roll where Swords
## Dance does not.
static func _stat_down_sequence(command: StringName) -> Array:
	return [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.CHECK_HIT,
		command,
		Gen2EffectCommands.STAT_DOWN_ANIM,
		Gen2EffectCommands.STAT_DOWN_MESSAGE,
		Gen2EffectCommands.STAT_DOWN_FAIL_TEXT,
		Gen2EffectCommands.END_MOVE,
	]


## The seven-wide runs, walked once into a dictionary rather than written out by
## hand. A wrong entry here would be a wrong number in a table that self-checks
## nothing, which is why [code]tools/dump_tables.gd[/code] and the published
## effect list are what settled the five bases in the first place, not this
## function.
static func _stat_sequences() -> Dictionary:
	var out: Dictionary = {}
	for offset: int in STAT_RUN_LENGTH:
		out[STAT_UP_BASE + offset] = _stat_up_sequence(STAT_UP_COMMANDS[offset])
		out[STAT_UP_2_BASE + offset] = _stat_up_sequence(STAT_UP_2_COMMANDS[offset])
		out[STAT_DOWN_BASE + offset] = _stat_down_sequence(STAT_DOWN_COMMANDS[offset])
		out[STAT_DOWN_2_BASE + offset] = _stat_down_sequence(STAT_DOWN_2_COMMANDS[offset])
		# `DefenseDownHit` is the one row of the seven that rolls twice, with the
		# second roll behind `applydamage`. Nothing reads `wEffectFailed` between
		# them, so only the second decides, and by then a doll the hit broke is
		# gone: `docs/bugs_and_glitches.md`'s "Moves that lower Defense can do so
		# after breaking a Substitute", kept rather than fixed.
		var trailing: Array = [
			STAT_DOWN_COMMANDS[offset], Gen2EffectCommands.STAT_DOWN_MESSAGE,
		]
		if STAT_DOWN_HIT_BASE + offset == DEFENSE_DOWN_HIT:
			trailing.push_front(Gen2EffectCommands.EFFECT_CHANCE)
		out[STAT_DOWN_HIT_BASE + offset] = _secondary(trailing)
	out[ATTACK_UP_HIT] = _secondary([
		STAT_UP_COMMANDS[0], Gen2EffectCommands.STAT_UP_MESSAGE,
	])
	out[DEFENSE_UP_HIT] = _secondary([
		STAT_UP_COMMANDS[1], Gen2EffectCommands.STAT_UP_MESSAGE,
	])
	out[ALL_STATS_UP_HIT] = _secondary([Gen2EffectCommands.ALL_STATS_UP])
	return out


## The cartridge's own table, built once. It is a constant answer to a constant
## question, and [method sequence_for] is asked it on every move of every turn,
## so rebuilding forty-odd lists and the five stat runs per attack was work
## nobody read.
static var _cached_sequences: Dictionary = {}
## Effect bytes a mod added, kept apart from the cartridge's so
## [method reset_registry] can drop them without rebuilding the table.
static var _registered_sequences: Dictionary = {}
## Command name to handler, for a step the engine does not have.
static var _registered_commands: Dictionary = {}
## What claimed each effect byte and command name, so a conflict names both mods.
static var _registry_owners: Dictionary = {}


## Effect bytes that do something other than [constant NORMAL_HIT]. An effect
## that is not in here is an ordinary attack, which is what most of the table is
## and what an effect nobody has written yet falls back to.
static func _sequences() -> Dictionary:
	var out: Dictionary = {
		SLEEP: SLEEP_SEQUENCE,
		POISON: POISON_SEQUENCE,
		TOXIC: TOXIC_SEQUENCE,
		PARALYZE: PARALYZE_SEQUENCE,
		POISON_HIT: _secondary([Gen2EffectCommands.POISON_TARGET]),
		BURN_HIT: _secondary([Gen2EffectCommands.BURN_TARGET]),
		FREEZE_HIT: _secondary([Gen2EffectCommands.FREEZE_TARGET]),
		PARALYZE_HIT: _secondary([Gen2EffectCommands.PARALYZE_TARGET]),
		RECOIL_HIT: RECOIL_HIT_SEQUENCE,
		COUNTER: COUNTER_SEQUENCE,
		MIRROR_COAT: MIRROR_COAT_SEQUENCE,
		SELFDESTRUCT: SELFDESTRUCT_SEQUENCE,
		FLINCH_HIT: _secondary([Gen2EffectCommands.FLINCH_TARGET]),
		CONFUSE_HIT: _secondary([Gen2EffectCommands.CONFUSE_TARGET]),
		CONFUSE: CONFUSE_SEQUENCE,
		RECHARGE_HIT: RECHARGE_HIT_SEQUENCE,
		RAZOR_WIND: CHARGE_SEQUENCE,
		SOLARBEAM: SOLARBEAM_SEQUENCE,
		FLY_OR_DIG: CHARGE_SEQUENCE,
		SKY_ATTACK: SKY_ATTACK_SEQUENCE,
		SKULL_BASH: SKULL_BASH_SEQUENCE,
		RAMPAGE: RAMPAGE_SEQUENCE,
		ROLLOUT: ROLLOUT_SEQUENCE,
		DEFENSE_CURL: DEFENSE_CURL_SEQUENCE,
		HAZE: HAZE_SEQUENCE,
		BELLY_DRUM: BELLY_DRUM_SEQUENCE,
		PSYCH_UP: PSYCH_UP_SEQUENCE,
		MIST: MIST_SEQUENCE,
		FOCUS_ENERGY: FOCUS_ENERGY_SEQUENCE,
		DISABLE: DISABLE_SEQUENCE,
		ATTRACT: ATTRACT_SEQUENCE,
		ENCORE: ENCORE_SEQUENCE,
		TRAP_TARGET: TRAP_TARGET_SEQUENCE,
		MEAN_LOOK: MEAN_LOOK_SEQUENCE,
		HEAL: HEAL_SEQUENCE,
		MORNING_SUN: TIME_HEAL_SEQUENCE,
		SYNTHESIS: TIME_HEAL_SEQUENCE,
		MOONLIGHT: TIME_HEAL_SEQUENCE,
		RAIN_DANCE: START_RAIN_SEQUENCE,
		SUNNY_DAY: START_SUN_SEQUENCE,
		SANDSTORM: START_SANDSTORM_SEQUENCE,
		LIGHT_SCREEN: SCREEN_SEQUENCE,
		REFLECT: SCREEN_SEQUENCE,
		SAFEGUARD: SAFEGUARD_SEQUENCE,
		PERISH_SONG: PERISH_SONG_SEQUENCE,
		SUBSTITUTE: SUBSTITUTE_SEQUENCE,
		LEECH_SEED: LEECH_SEED_SEQUENCE,
		NIGHTMARE: NIGHTMARE_SEQUENCE,
		CURSE: CURSE_SEQUENCE,
		SPIKES: SPIKES_SEQUENCE,
		RAPID_SPIN: RAPID_SPIN_SEQUENCE,
		PROTECT: PROTECT_SEQUENCE,
		ENDURE: ENDURE_SEQUENCE,
		DESTINY_BOND: DESTINY_BOND_SEQUENCE,
		FORCE_SWITCH: FORCE_SWITCH_SEQUENCE,
		BATON_PASS: BATON_PASS_SEQUENCE,
		PAIN_SPLIT: _status_command_sequence(Gen2EffectCommands.PAIN_SPLIT),
		LOCK_ON: _status_command_sequence(Gen2EffectCommands.LOCK_ON),
		SPITE: _status_command_sequence(Gen2EffectCommands.SPITE),
		FORESIGHT: _status_command_sequence(Gen2EffectCommands.FORESIGHT),
		TELEPORT: TELEPORT_SEQUENCE,
		THIEF: THIEF_SEQUENCE,
		PURSUIT: PURSUIT_SEQUENCE,
		BEAT_UP: BEAT_UP_SEQUENCE,
		THUNDER: THUNDER_SEQUENCE,
		LEECH_HIT: DRAIN_SEQUENCE,
		DREAM_EATER: DREAM_EATER_SEQUENCE,
		MULTI_HIT: MULTI_HIT_SEQUENCE,
		DOUBLE_HIT: MULTI_HIT_SEQUENCE,
		TWINEEDLE: TWINEEDLE_SEQUENCE,
		OHKO: OHKO_SEQUENCE,
		SUPER_FANG: FIXED_DAMAGE_SEQUENCE,
		STATIC_DAMAGE: FIXED_DAMAGE_SEQUENCE,
		LEVEL_DAMAGE: FIXED_DAMAGE_SEQUENCE,
		PSYWAVE: FIXED_DAMAGE_SEQUENCE,
		# Both of these really are `NormalHit` in `effects_pointers.asm`: what
		# makes Swift never miss and a Jump Kick hurt to miss lives inside
		# [method Gen2EffectCommands._check_hit] rather than in a list. They are
		# named here so [method is_written] can tell a modelled effect from one
		# still standing in as an ordinary attack.
		ALWAYS_HIT: NORMAL_HIT,
		JUMP_KICK: NORMAL_HIT,
		RETURN: RETURN_SEQUENCE,
		FRUSTRATION: FRUSTRATION_SEQUENCE,
		MAGNITUDE: MAGNITUDE_SEQUENCE,
		HIDDEN_POWER: HIDDEN_POWER_SEQUENCE,
		PRESENT: PRESENT_SEQUENCE,
		REVERSAL: REVERSAL_SEQUENCE,
		FURY_CUTTER: FURY_CUTTER_SEQUENCE,
		TRIPLE_KICK: TRIPLE_KICK_SEQUENCE,
		FALSE_SWIPE: FALSE_SWIPE_SEQUENCE,
		HEAL_BELL: HEAL_BELL_SEQUENCE,
		SPLASH: SPLASH_SEQUENCE,
		MIRROR_MOVE: MIRROR_MOVE_SEQUENCE,
		CONVERSION: CONVERSION_SEQUENCE,
		MIMIC: MIMIC_SEQUENCE,
		METRONOME: METRONOME_SEQUENCE,
		CONVERSION_2: CONVERSION_2_SEQUENCE,
		SKETCH: SKETCH_SEQUENCE,
		SLEEP_TALK: SLEEP_TALK_SEQUENCE,
		BIDE: BIDE_SEQUENCE,
		RAGE: RAGE_SEQUENCE,
		FUTURE_SIGHT: FUTURE_SIGHT_SEQUENCE,
		PAY_DAY: PAY_DAY_SEQUENCE,
		TRANSFORM: TRANSFORM_SEQUENCE,
		SNORE: SNORE_SEQUENCE,
		TRI_ATTACK: TRI_ATTACK_SEQUENCE,
		FLAME_WHEEL: FLAME_WHEEL_SEQUENCE,
		SACRED_FIRE: FLAME_WHEEL_SEQUENCE,
		GUST: DOUBLE_DAMAGE_SEQUENCE,
		EARTHQUAKE: DOUBLE_DAMAGE_SEQUENCE,
		TWISTER: DOUBLE_DAMAGE_FLINCH_SEQUENCE,
		STOMP: DOUBLE_DAMAGE_FLINCH_SEQUENCE,
		SWAGGER: SWAGGER_SEQUENCE,
	}
	out.merge(_stat_sequences())
	return out


## The cartridge's table, built on the first ask and kept.
static func _table() -> Dictionary:
	if _cached_sequences.is_empty():
		_cached_sequences = _sequences()
	return _cached_sequences


## The commands a move with this effect byte is made of.
##
## A registered effect wins over the cartridge's, which is what lets a mod
## rewrite one as well as add one. [method register_effect] is where that is
## refused for the effects the engine relies on reading back off a turn.
static func sequence_for(effect: int) -> Array:
	if _registered_sequences.has(effect):
		return _registered_sequences[effect]
	return _table().get(effect, NORMAL_HIT)


## Whether an effect has a list of its own yet, which is what separates a move
## that is fully implemented from one that is standing in as an ordinary attack.
static func is_written(effect: int) -> bool:
	return _registered_sequences.has(effect) or _table().has(effect)


## Effect bytes whose command reads the byte back off the turn to decide what it
## is: the multi-hit count, the four fixed-damage figures, Rollout's multiplier,
## Selfdestruct's halved Defense and the three time-based heals' time of day all
## work that way. Rewriting one would make its own command answer for a list it
## is no longer in, so these are refused rather than left to fail at the point of
## use.
const RESERVED_EFFECTS: Array[int] = [
	MULTI_HIT, DOUBLE_HIT, TWINEEDLE, SUPER_FANG, STATIC_DAMAGE, LEVEL_DAMAGE,
	PSYWAVE, ROLLOUT, SELFDESTRUCT, MORNING_SUN, SYNTHESIS, MOONLIGHT,
	LIGHT_SCREEN, REFLECT, REVERSAL, ALWAYS_HIT, JUMP_KICK,
]


## Registers the command list a move carrying [param effect] runs.
##
## Every step named has to be one the engine knows or one already registered
## through [method register_command], so a list that would push an error mid-turn
## is refused here, where the mod's id is still in hand.
static func register_effect(id: StringName, effect: int, commands: Array) -> Dictionary:
	if effect < 0 or effect > 0xFF:
		return {"ok": false, "reason": &"invalid_effect", "detail": str(effect)}
	if RESERVED_EFFECTS.has(effect):
		return {"ok": false, "reason": &"reserved_effect", "detail": str(effect)}
	if commands.is_empty():
		return {"ok": false, "reason": &"empty_effect", "detail": str(effect)}
	var unknown: Array[String] = []
	for command: Variant in commands:
		if not _command_exists(StringName(command)):
			unknown.append(String(command))
	if not unknown.is_empty():
		return {
			"ok": false, "reason": &"unknown_effect_command",
			"detail": "%d: %s" % [effect, ", ".join(unknown)],
		}
	var claim: Dictionary = _claim(&"effect", id, effect)
	if not bool(claim.get("ok", false)):
		return claim
	var sequence: Array = []
	for command: Variant in commands:
		sequence.append(StringName(command))
	_registered_sequences[effect] = sequence
	return {"ok": true, "effect": effect}


## Registers a step a command list may name, run with the [Gen2Turn] the way
## every built-in step is.
##
## The engine's own commands are tried first, so a registration cannot shadow
## [constant Gen2EffectCommands.APPLY_DAMAGE] and quietly change what every move
## in the game does.
static func register_command(
	id: StringName, command: StringName, handler: Callable
) -> Dictionary:
	if String(command).is_empty():
		return {"ok": false, "reason": &"invalid_effect_command"}
	if not handler.is_valid():
		return {"ok": false, "reason": &"invalid_effect_handler", "detail": String(command)}
	if Gen2EffectCommands.is_engine_command(command):
		return {"ok": false, "reason": &"reserved_effect_command", "detail": String(command)}
	var claim: Dictionary = _claim(&"command", id, command)
	if not bool(claim.get("ok", false)):
		return claim
	_registered_commands[command] = handler
	return {"ok": true, "command": command}


## Runs a registered command, answering whether there was one.
## [method Gen2EffectCommands.run] reaches this only after its own match has
## refused the name.
static func run_registered_command(command: StringName, turn: Gen2Turn) -> bool:
	var handler: Variant = _registered_commands.get(command, null)
	if not handler is Callable:
		return false
	(handler as Callable).call(turn)
	return true


## Drops every registered effect and command. [method Gen2ModHost.reset] calls
## this; the cartridge's own table is untouched, since nothing can change it.
static func reset_registry() -> void:
	_registered_sequences = {}
	_registered_commands = {}
	_registry_owners = {}


## Whether [param command] is a step something can run: one the engine has, or
## one a mod registered before naming it in a list.
static func _command_exists(command: StringName) -> bool:
	return Gen2EffectCommands.is_engine_command(command) \
		or _registered_commands.has(command)


## One effect byte or command name, one mod, for the same reason
## [method Gen2ContentOverlay._claim] holds: load order must not decide which of
## two mods a move belongs to.
static func _claim(kind: StringName, id: StringName, key: Variant) -> Dictionary:
	var owners: Dictionary = _registry_owners.get(kind, {})
	var owner: StringName = StringName(owners.get(key, &""))
	if owner != &"" and owner != id:
		return {
			"ok": false, "reason": &"duplicate_move_effect",
			"detail": "%s %s: %s and %s" % [kind, key, owner, id],
		}
	owners[key] = id
	_registry_owners[kind] = owners
	return {"ok": true}
