class_name Gen2Substatus
extends RefCounted

## The volatile flags of battle state, for everything the status byte cannot
## hold.
##
## [Gen2Status] is deliberately one status at a time, which is the cartridge's
## own rule: a Pokémon that is already poisoned cannot also be confused by
## refusing a second flag on the same byte. Confusion, flinching, being locked
## into a recharge turn or a two-turn move's charge, Disable, Attract, Encore,
## Mist, Focus Energy, flying and underground are all independent of that and
## of each other, so they live apart from it.
##
## The cartridge itself keeps these as five separate bytes
## (`wPlayerSubStatus1` through `wPlayerSubStatus5`), not one: this project
## folds them into a single int because nothing here needs to address one of
## the five in isolation the way the cartridge's own bit-numbering does, and a
## flag is a flag regardless of which byte it started on.
##
## Unlike [Gen2Status] this one is not the whole of its state: a few of these
## flags need a counter alongside them (how many turns of confusion are left,
## which move was charged, which slot is disabled and for how long, or how many
## turns Rollout or a rampage has left), which is why [Gen2BattleMon] keeps
## those as separate fields next to
## [member Gen2BattleMon.substatus] rather than packing them into the byte.
## This class stays pure arithmetic and holds no state of its own, the same
## shape as [Gen2Status].
##
## Every flag here clears on a switch, which is what makes it volatile rather
## than a status: [method Gen2BattleMon.reset_volatile] is the single place that
## happens, called from [method Gen2Party.send_out] alongside
## [method Gen2BattleMon.reset_stages].

const CONFUSED: int = 1 << 0
const FLINCHED: int = 1 << 1
const RECHARGING: int = 1 << 2
const CHARGING: int = 1 << 3
const DISABLED: int = 1 << 4
const ATTRACTED: int = 1 << 5
const ENCORED: int = 1 << 6
const MIST: int = 1 << 7
const FOCUS_ENERGY: int = 1 << 8
const FLYING: int = 1 << 9
const UNDERGROUND: int = 1 << 10
const CURLED: int = 1 << 11
const ROLLOUT: int = 1 << 12
const RAMPAGING: int = 1 << 13

const NONE: int = 0

## How many turns a confused Pokémon stays that way, rolled the same shape as
## [constant Gen2Status.MIN_SLEEP] and [constant Gen2Status.MAX_SLEEP]: the
## cartridge rolls the low bits until it gets something in range and the
## counter starts inclusive of both ends.
const MIN_CONFUSION: int = 2
const MAX_CONFUSION: int = 5

## A rampage lasts one or two more turns after the move that starts it. The
## cartridge uses the low bit of a random byte and adds one.
const MIN_RAMPAGE_TURNS: int = 1
const MAX_RAMPAGE_TURNS: int = 2

## When a rampage ends, confusion lasts two or three turns. This is a separate
## roll from ordinary confusion, which can last through five turns.
const MIN_RAMPAGE_CONFUSION: int = 2
const MAX_RAMPAGE_CONFUSION: int = 3

## How many turns Disable lasts, from `BattleCommand_Disable`'s own roll: three
## bits of a random byte, rerolled on zero, plus one. The result is packed
## alongside the disabled slot on the cartridge's own single counter byte; here
## the two live as separate fields on [Gen2BattleMon] instead, since nothing
## else needs the packed form.
const MIN_DISABLE: int = 2
const MAX_DISABLE: int = 8

## How many turns Encore lasts. Unlike Disable's roll, this one does not
## reroll on the low end: two bits of a random byte, plus three.
const MIN_ENCORE: int = 3
const MAX_ENCORE: int = 6

## Whether an attracted Pokémon is too smitten to move, out of 256: the
## cartridge's own 128 in 256, a coin flip, rolled fresh every turn it tries to
## move rather than decided once when Attract lands.
const ATTRACT_IMMOBILE_CHANCE: int = 128

## Whether a confused Pokémon hurts itself instead of moving, out of 256: the
## cartridge's own 128 in 256, a coin flip.
const CONFUSION_HURTS_SELF_CHANCE: int = 128
const CHANCE_RANGE: int = 256


static func has(substatus: int, flag: int) -> bool:
	return (substatus & flag) != 0


## How long a newly confused Pokémon stays that way.
static func roll_confusion(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_CONFUSION, MAX_CONFUSION)


## How many more turns a newly started rampage lasts.
static func roll_rampage_turns(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_RAMPAGE_TURNS, MAX_RAMPAGE_TURNS)


## How long confusion lasts when a rampage ends.
static func roll_rampage_confusion(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_RAMPAGE_CONFUSION, MAX_RAMPAGE_CONFUSION)


## Whether a confused Pokémon hurts itself this turn instead of moving.
static func rolls_confusion_hit(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < CONFUSION_HURTS_SELF_CHANCE


## How long a newly disabled move stays that way. The cartridge rolls three
## bits of a random byte and rerolls a zero, so the roll itself only ever
## produces 1 through 7; the constant one added afterward is folded in here
## rather than left for a caller to remember.
static func roll_disable(rng: RandomNumberGenerator) -> int:
	var roll: int = 0
	while roll == 0:
		roll = rng.randi_range(0, 7)
	return roll + 1


## How long a newly encored move stays that way.
static func roll_encore(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 3) + MIN_ENCORE


## Whether an attracted Pokémon is too smitten to move this turn.
static func rolls_attract_immobile(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < ATTRACT_IMMOBILE_CHANCE
