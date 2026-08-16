class_name Gen2Substatus
extends RefCounted

## The volatile flags, for what the one-at-a-time [Gen2Status] byte cannot hold.
## `wPlayerSubStatus1` through `5` folded into one int, since nothing addresses a
## byte alone; counters that belong beside a flag live on [Gen2BattleMon], and
## every flag clears in [method Gen2BattleMon.reset_volatile].

const CONFUSED: int = 1 << 0
const FLINCHED: int = 1 << 1
const RECHARGING: int = 1 << 2
const CHARGING: int = 1 << 3
## Bit 4 was a DISABLED flag; the cartridge has none, `wDisabledMove` and
## `wPlayerDisableCount` being the whole of it. Left unused, not reassigned.
const ATTRACTED: int = 1 << 5
const ENCORED: int = 1 << 6
const MIST: int = 1 << 7
const FOCUS_ENERGY: int = 1 << 8
const FLYING: int = 1 << 9
const UNDERGROUND: int = 1 << 10
const CURLED: int = 1 << 11
const ROLLOUT: int = 1 << 12
const RAMPAGING: int = 1 << 13

## On the Pokémon that used Mean Look, not the one that cannot leave:
## `BattleCommand_ArenaTrap` sets the user's own `BATTLE_VARS_SUBSTATUS5`.
const CANT_RUN: int = 1 << 14

## Every move its holder uses hits, checked in `CheckHit` ahead of the modifiers.
## Only a trainer's AI sets it; the player's pack has no X items yet.
const X_ACCURACY: int = 1 << 15

## With [member Gen2BattleMon.perish_count] beside it. A send-out zeroes the flag
## and leaves the count, but every read of the count is behind the flag.
const PERISH: int = 1 << 16

## The doll's hit points are [member Gen2BattleMon.substitute_hp].
const SUBSTITUTE: int = 1 << 17

## On the seeded Pokémon, which is why `BattleCommand_ClearHazards` reads the
## user's own flag.
const LEECH_SEED: int = 1 << 18

## Both cost a quarter at the end of the turn and sit on the sufferer.
const NIGHTMARE: int = 1 << 19
const CURSE: int = 1 << 20

## Neither is spent by the hit it answers, so every hit of a multi-hit move is
## turned away; `EndOpponentProtectEndureDestinyBond` ends them.
const PROTECT: int = 1 << 21
const ENDURE: int = 1 << 22

## On its user, read only by the opponent's `BattleCommand_CheckFaint`.
## `EndUserDestinyBond` clears it before its user's next action, so it covers
## exactly the opponent's next move.
const DESTINY_BOND: int = 1 << 23

## Foresight sets it on the target: `BATTLE_VARS_SUBSTATUS1_OPP`.
const IDENTIFIED: int = 1 << 24

## On the Pokémon aimed at, so `CheckHit`'s `.LockOn` reads
## `BATTLE_VARS_SUBSTATUS5_OPP` and consumes it. Its only other reader is the 25%
## AI status-move failure, which this engine does not model.
const LOCK_ON: int = 1 << 25

## Both cleared by switching or by choosing another action; their counters live
## on [Gen2BattleMon].
const BIDE: int = 1 << 26
const RAGE: int = 1 << 27
const TRANSFORMED: int = 1 << 28

const NONE: int = 0

## Rolled the shape [constant Gen2Status.MIN_SLEEP] is, both ends inclusive.
const MIN_CONFUSION: int = 2
const MAX_CONFUSION: int = 5

## The low bit of a random byte, plus one.
const MIN_RAMPAGE_TURNS: int = 1
const MAX_RAMPAGE_TURNS: int = 2

## A separate roll from ordinary confusion, which can run to five turns.
const MIN_RAMPAGE_CONFUSION: int = 2
const MAX_RAMPAGE_CONFUSION: int = 3

## `BattleCommand_Disable`: three bits rerolled on zero, plus one. The cartridge
## packs the count with the slot; they are two fields on [Gen2BattleMon] here.
const MIN_DISABLE: int = 2
const MAX_DISABLE: int = 8

## Two bits plus three, with no reroll on the low end.
const MIN_ENCORE: int = 3
const MAX_ENCORE: int = 6

## `BattleCommand_TrapTarget`: two bits incremented three times. The landing
## turn's `HandleWrap` spends one without damage, hence the source's "two to five".
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

## Both out of 256, rolled fresh every turn rather than when the flag landed.
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


## Not [method quarter_damage]: `BattleCommand_Substitute` shifts right twice by
## hand with no floor at one, so a maximum under four makes a doll with no HP.
static func substitute_hp_for(max_hp: int) -> int:
	return (max_hp >> 2) & 0xFF
