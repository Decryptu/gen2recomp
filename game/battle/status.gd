class_name Gen2Status
extends RefCounted

## The status byte, and the four things it does to a Pokémon.
##
## One byte, as the cartridge stores it: the low three bits are turns of sleep
## left and the four above are one flag each. That is also the rule, not just
## storage: one status at a time, a second refused rather than added, which falls
## out of checking the byte as a whole.
##
## What the four do is spread across the turn. Sleep, freeze and paralysis are
## checked before a move; burn and paralysis bend a stat where it is read; burn
## and poison take a slice at the end of the turn. This class is the arithmetic
## behind that and holds no state.

## The low three bits: turns of sleep left, from 1 to 7.
const SLEEP_MASK: int = 0b111

## One flag each, in the cartridge's own bit order.
const POISON: int = 1 << 3
const BURN: int = 1 << 4
const FREEZE: int = 1 << 5
const PARALYSIS: int = 1 << 6

const NONE: int = 0

## Everything the byte can say, which is what "does this Pokémon already have a
## status" asks about.
const ANY: int = SLEEP_MASK | POISON | BURN | FREEZE | PARALYSIS

## What sleep is rolled from. The cartridge rolls the low three bits until it
## gets something that is neither 0 nor 7 and then adds one, so the counter
## starts between 2 and 7 and the Pokémon loses between one and six turns.
const MIN_SLEEP: int = 2
const MAX_SLEEP: int = 7

## Burn halves the Attack and paralysis quarters the Speed, both to a minimum of
## one, and both are shifts rather than divisions on the hardware.
const BURN_ATTACK_SHIFT: int = 1
const PARALYSIS_SPEED_SHIFT: int = 2

## Being fully paralysed is a quarter of the time, out of 256.
const PARALYSIS_CHANCE: int = 64
const CHANCE_RANGE: int = 256

## Burn and poison cost an eighth of the maximum, never less than one.
const RESIDUAL_DIVISOR: int = 8

## Toxic ramps rather than costing a flat eighth: a sixteenth of the maximum for
## every turn it has been in effect, so the first turn costs the least of any
## status and the Pokémon that stays in against it pays more each turn after.
const TOXIC_RESIDUAL_DIVISOR: int = 16


static func has(status: int, flag: int) -> bool:
	return (status & flag) != 0


static func is_asleep(status: int) -> bool:
	return (status & SLEEP_MASK) != 0


static func sleep_turns(status: int) -> int:
	return status & SLEEP_MASK


## Whether there is anything at all on the byte. A Pokémon that has one status
## cannot be given another, which is why this is asked as one question.
static func is_afflicted(status: int) -> bool:
	return (status & ANY) != 0


## One turn of sleep counted off. A counter that reaches zero has taken sleep off
## the byte, and the Pokémon acts that same turn: the cartridge wakes it and
## carries on into the rest of its checks rather than ending its turn.
static func tick_sleep(status: int) -> int:
	if not is_asleep(status):
		return status
	return (status & ~SLEEP_MASK) | ((status & SLEEP_MASK) - 1)


## How long a Pokémon put to sleep stays asleep.
static func roll_sleep(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_SLEEP, MAX_SLEEP)


## Whether a paralysed Pokémon cannot move this turn.
static func rolls_full_paralysis(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < PARALYSIS_CHANCE


## The Attack a burned Pokémon attacks with, and the Speed a paralysed one moves
## at. Both are applied where the stat is read rather than to the stat itself,
## because a status is a lens on a stat exactly as a stage is, and a Pokémon
## cured of a burn has its Attack back without anything being recalculated.
static func apply_burn(attack: int) -> int:
	return maxi(attack >> BURN_ATTACK_SHIFT, 1)


static func apply_paralysis(speed: int) -> int:
	return maxi(speed >> PARALYSIS_SPEED_SHIFT, 1)


## What a burn or a poison takes at the end of a turn.
static func residual_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / RESIDUAL_DIVISOR, 1)


## What Toxic takes at the end of a turn, at [param counter] turns of it having
## been in effect. [param counter] starts at 1 the turn it is inflicted, so the
## first hit is a sixteenth and not nothing.
static func toxic_damage(max_hp: int, counter: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp * counter / TOXIC_RESIDUAL_DIVISOR, 1)


## What is on the byte, as a name a message can be built from, or an empty
## StringName for a Pokémon with nothing on it. Sleep first, because a byte that
## carries a sleep counter carries nothing else.
static func name_of(status: int) -> StringName:
	if is_asleep(status):
		return &"sleep"
	if has(status, FREEZE):
		return &"freeze"
	if has(status, PARALYSIS):
		return &"paralysis"
	if has(status, BURN):
		return &"burn"
	if has(status, POISON):
		return &"poison"
	return &""
