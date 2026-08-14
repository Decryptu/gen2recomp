class_name Gen2Substatus
extends RefCounted

## The volatile flags, for everything the one-at-a-time [Gen2Status] byte cannot
## hold. Pure arithmetic and no state, the same shape as [Gen2Status].
##
## The cartridge keeps these as `wPlayerSubStatus1` through `5`; they fold into
## one int here, since nothing needs to address a byte on its own. Counters that
## belong beside a flag (confusion turns, the charged move, the disabled slot)
## live on [Gen2BattleMon]. Every flag clears on a switch, in
## [method Gen2BattleMon.reset_volatile].

const CONFUSED: int = 1 << 0
const FLINCHED: int = 1 << 1
const RECHARGING: int = 1 << 2
const CHARGING: int = 1 << 3
## Bit 4 was a DISABLED flag. The cartridge has none: `wDisabledMove` and
## `wPlayerDisableCount` are the whole of it. Left unused rather than reassigned
## so a bit number keeps meaning what it did.
const ATTRACTED: int = 1 << 5
const ENCORED: int = 1 << 6
const MIST: int = 1 << 7
const FOCUS_ENERGY: int = 1 << 8
const FLYING: int = 1 << 9
const UNDERGROUND: int = 1 << 10
const CURLED: int = 1 << 11
const ROLLOUT: int = 1 << 12
const RAMPAGING: int = 1 << 13

## `SUBSTATUS_CANT_RUN`. On the Pokémon that used Mean Look, not the one that
## cannot leave: `BattleCommand_ArenaTrap` sets the user's own
## `BATTLE_VARS_SUBSTATUS5`.
const CANT_RUN: int = 1 << 14

## `SUBSTATUS_X_ACCURACY`. Every move its holder uses hits, checked in `CheckHit`
## ahead of the modifiers. Only a trainer's AI sets it; the player's pack has no
## X items yet.
const X_ACCURACY: int = 1 << 15

## `SUBSTATUS_PERISH`, with [member Gen2BattleMon.perish_count] beside it. A
## send-out zeroes the flag and leaves the count, but every read of the count is
## behind the flag, so clearing both is the same behaviour.
const PERISH: int = 1 << 16

## `SUBSTATUS_SUBSTITUTE`. The doll's hit points are
## [member Gen2BattleMon.substitute_hp].
const SUBSTITUTE: int = 1 << 17

## `SUBSTATUS_LEECH_SEED`. On the seeded Pokémon, which is why
## `BattleCommand_ClearHazards` reads the user's own flag.
const LEECH_SEED: int = 1 << 18

## `SUBSTATUS_NIGHTMARE` and `SUBSTATUS_CURSE`. Both cost a quarter at the end of
## the turn and both sit on the sufferer.
const NIGHTMARE: int = 1 << 19
const CURSE: int = 1 << 20

## `SUBSTATUS_PROTECT` and `SUBSTATUS_ENDURE`. Neither is spent by the hit it
## answers, so every hit of a multi-hit move is turned away or clamped;
## `EndOpponentProtectEndureDestinyBond` is what ends them.
const PROTECT: int = 1 << 21
const ENDURE: int = 1 << 22

## `SUBSTATUS_DESTINY_BOND`. On its user, read only by the opponent's
## `BattleCommand_CheckFaint`. `EndUserDestinyBond` clears it in front of its
## user's next action, so it covers exactly the opponent's next move.
const DESTINY_BOND: int = 1 << 23

## `SUBSTATUS_IDENTIFIED`. Foresight sets it on the target, not the user:
## `BattleCommand_Foresight` writes `BATTLE_VARS_SUBSTATUS1_OPP`.
const IDENTIFIED: int = 1 << 24

## `SUBSTATUS_LOCK_ON`. On the Pokémon aimed at, so `CheckHit`'s `.LockOn` reads
## `BATTLE_VARS_SUBSTATUS5_OPP` and consumes it. The cartridge's other readers
## are the 25% AI status-move failure, which this engine does not model.
const LOCK_ON: int = 1 << 25

## Both cleared by switching or by choosing another action; their counters live
## on [Gen2BattleMon].
const BIDE: int = 1 << 26
const RAGE: int = 1 << 27
const TRANSFORMED: int = 1 << 28

const NONE: int = 0

## Rolled the shape [constant Gen2Status.MIN_SLEEP] is: the cartridge rolls the
## low bits until it lands in range, inclusive of both ends.
const MIN_CONFUSION: int = 2
const MAX_CONFUSION: int = 5

## The low bit of a random byte, plus one.
const MIN_RAMPAGE_TURNS: int = 1
const MAX_RAMPAGE_TURNS: int = 2

## A separate roll from ordinary confusion, which can run to five turns.
const MIN_RAMPAGE_CONFUSION: int = 2
const MAX_RAMPAGE_CONFUSION: int = 3

## `BattleCommand_Disable`: three bits of a random byte, rerolled on zero, plus
## one. The cartridge packs the count with the disabled slot; the two are
## separate fields on [Gen2BattleMon] here.
const MIN_DISABLE: int = 2
const MAX_DISABLE: int = 8

## Two bits plus three, with no reroll on the low end.
const MIN_ENCORE: int = 3
const MAX_ENCORE: int = 6

## `BattleCommand_TrapTarget`: two bits incremented three times. The landing
## turn's `HandleWrap` spends one without damage, which is why the source
## comments the same roll as two to five.
const MIN_TRAP_TURNS: int = 3
const MAX_TRAP_TURNS: int = 6

## `GetSixteenthMaxHP`, `GetEighthMaxHP`, `GetQuarterMaxHP` and `GetHalfMaxHP`,
## each with its at-least-one floor.
const TRAP_DIVISOR: int = 16
const LEECH_SEED_DIVISOR: int = 8
const QUARTER_DIVISOR: int = 4
const HALF_DIVISOR: int = 2

## `HandlePerishSong` decrements before it prints, so the counts printed are 3,
## 2, 1 and 0 and the song's own line says three turns.
const PERISH_TURNS: int = 4

## Both out of 256, the cartridge's own coin flip, rolled fresh every turn the
## Pokémon tries to move rather than decided when the flag landed.
const ATTRACT_IMMOBILE_CHANCE: int = 128
const CONFUSION_HURTS_SELF_CHANCE: int = 128
const CHANCE_RANGE: int = 256


static func has(substatus: int, flag: int) -> bool:
	return (substatus & flag) != 0


static func roll_confusion(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_CONFUSION, MAX_CONFUSION)


static func roll_rampage_turns(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_RAMPAGE_TURNS, MAX_RAMPAGE_TURNS)


static func roll_rampage_confusion(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_RAMPAGE_CONFUSION, MAX_RAMPAGE_CONFUSION)


static func rolls_confusion_hit(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < CONFUSION_HURTS_SELF_CHANCE


## The reroll on zero is the cartridge's; the constant one added afterward is
## folded in here rather than left for a caller to remember.
static func roll_disable(rng: RandomNumberGenerator) -> int:
	var roll: int = 0
	while roll == 0:
		roll = rng.randi_range(0, 7)
	return roll + 1


static func roll_encore(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 3) + MIN_ENCORE


static func rolls_attract_immobile(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < ATTRACT_IMMOBILE_CHANCE


static func roll_trap_turns(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_TRAP_TURNS, MAX_TRAP_TURNS)


static func trap_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / TRAP_DIVISOR, 1)


static func leech_seed_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / LEECH_SEED_DIVISOR, 1)


static func quarter_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / QUARTER_DIVISOR, 1)


static func half_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / HALF_DIVISOR, 1)


## Not [method quarter_damage]: `BattleCommand_Substitute` shifts the maximum
## right twice by hand with no `GetQuarterMaxHP` and so no floor at one, which is
## why a maximum under four makes a doll with no hit points at all.
static func substitute_hp_for(max_hp: int) -> int:
	return (max_hp >> 2) & 0xFF
