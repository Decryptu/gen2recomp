class_name Gen2Substatus
extends RefCounted

## The second byte of battle state, for everything the status byte cannot hold.
##
## [Gen2Status] is deliberately one status at a time, which is the cartridge's
## own rule: a Pokémon that is already poisoned cannot also be confused by
## refusing a second flag on the same byte. Confusion, flinching, being locked
## into a recharge turn or a two-turn move's charge, Disable and Attract are all
## independent of that and of each other, so they live on a byte of their own.
##
## Unlike [Gen2Status] this one is not the whole of its state: a few of these
## flags need a counter alongside them (how many turns of confusion are left,
## which move was charged), which is why [Gen2BattleMon] keeps those as separate
## fields next to [member Gen2BattleMon.substatus] rather than packing them into
## the byte. This class stays pure arithmetic and holds no state of its own,
## the same shape as [Gen2Status].
##
## Every flag here clears on a switch, which is what makes it volatile rather
## than a status: [method Gen2BattleMon.reset_volatile] is the single place that
## happens, called from [method Gen2Party.send_out] alongside
## [method Gen2BattleMon.reset_stages].

const CONFUSED: int = 1 << 0
const FLINCHED: int = 1 << 1
const RECHARGING: int = 1 << 2
const CHARGING: int = 1 << 3
## Not yet written by any command; declared now so the byte's layout is decided
## once rather than grown flag by flag as Disable and Attract are added.
const DISABLED: int = 1 << 4
const ATTRACTED: int = 1 << 5

const NONE: int = 0

## How many turns a confused Pokémon stays that way, rolled the same shape as
## [constant Gen2Status.MIN_SLEEP] and [constant Gen2Status.MAX_SLEEP]: the
## cartridge rolls the low bits until it gets something in range and the
## counter starts inclusive of both ends.
const MIN_CONFUSION: int = 2
const MAX_CONFUSION: int = 5

## Whether a confused Pokémon hurts itself instead of moving, out of 256: the
## cartridge's own 128 in 256, a coin flip.
const CONFUSION_HURTS_SELF_CHANCE: int = 128
const CHANCE_RANGE: int = 256


static func has(substatus: int, flag: int) -> bool:
	return (substatus & flag) != 0


## How long a newly confused Pokémon stays that way.
static func roll_confusion(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_CONFUSION, MAX_CONFUSION)


## Whether a confused Pokémon hurts itself this turn instead of moving.
static func rolls_confusion_hit(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < CONFUSION_HURTS_SELF_CHANCE
