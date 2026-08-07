class_name Gen2Accuracy
extends RefCounted

## Whether a move connects.
##
## Accuracy is a byte out of 255, not a percentage: "100%" stores 255 and "90%"
## stores 229. Kept as the byte, because the roll is against it and a stored 255
## is a special case that never misses.
##
## Accuracy and evasion use their own multiplier table, a different shape from
## the other stats', so -1 accuracy and -1 Attack are different fractions.

## The move accuracy that cannot miss. Anything the stages leave below this rolls.
const ALWAYS_HITS: int = 255

## What each stage from -6 to +6 multiplies accuracy by, as the numerator and
## denominator pair the cartridge stores.
const STAGE_MULTIPLIERS: Array = [
	[33, 100], [36, 100], [43, 100], [50, 100], [60, 100], [75, 100],
	[1, 1],
	[133, 100], [166, 100], [2, 1], [233, 100], [133, 50], [3, 1],
]


## The chance a move connects, out of 255.
##
## Evasion reads the same table from the other end rather than a second table:
## +2 evasion is the multiplier accuracy uses at -2.
##
## [param foresight] drops both sides' stages, not only evasion, and only when
## the evasion stage is at least the accuracy stage, so it cannot undo an
## accuracy the attacker raised.
static func chance(
	move_accuracy: int,
	accuracy_stage: int = 0,
	evasion_stage: int = 0,
	foresight: bool = false
) -> int:
	var out: int = clampi(move_accuracy, 0, ALWAYS_HITS)
	if foresight and evasion_stage >= accuracy_stage:
		return out

	out = apply_stage(out, accuracy_stage)
	out = apply_stage(out, -evasion_stage)
	return mini(out, ALWAYS_HITS)


## One multiplication, floored at 1 and deliberately not capped: the cap is
## applied once at the end, so an accuracy raised past 255 and then halved by
## evasion lands where the arithmetic puts it rather than at 127.
static func apply_stage(value: int, stage: int) -> int:
	var ratio: Array = STAGE_MULTIPLIERS[
		clampi(stage, Gen2Stats.MIN_STAGE, Gen2Stats.MAX_STAGE) - Gen2Stats.MIN_STAGE
	]
	@warning_ignore("integer_division")
	var out: int = value * int(ratio[0]) / int(ratio[1])
	return maxi(out, 1)


## Rolls a hit against a chance out of 255.
##
## A chance of exactly 255 connects without rolling. Rolling would miss one time
## in 256, and the cartridge goes out of its way not to.
static func rolls_hit(rng: RandomNumberGenerator, hit_chance: int) -> bool:
	if hit_chance >= ALWAYS_HITS:
		return true
	return rng.randi_range(0, 255) < hit_chance
