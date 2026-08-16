class_name Gen2Stats
extends RefCounted

## Base stats, DVs and stat experience into the numbers a battle is fought with.
##
## Integer arithmetic in the hardware's order: every division truncates, and a
## tidier rearrangement gives a different answer often enough to matter. A DV is
## four bits per stat, and HP's is assembled from the other four rather than
## stored, which is the same reading that decides shininess.

## The floors the formula ends on: a level 1 Pokémon still has 5 and 11.
const STAT_MIN_NORMAL: int = 5
const STAT_MIN_HP: int = 10

## Stats are stored in two bytes but capped well below what those hold.
const MAX_STAT_VALUE: int = 999

const MAX_DV: int = 15
const MAX_STAT_EXP: int = 65535

## `ld a, $ff / NUM_UNOWN + 1`, assembled rather than computed: 255 / 26 is 9.
const UNOWN_LETTER_DIVISOR: int = 10

## The table of squares stops here rather than at the true root, so stat
## experience above 255 squared is wasted and a full bar is worth 63.
const MAX_SQUARE_ROOT: int = 255

## The cartridge stores stages 7-centred so it can index the table with them;
## here they are signed and the table is offset instead.
const MIN_STAGE: int = -6
const MAX_STAGE: int = 6

## The cartridge's own numerator/denominator pairs, not a 2/(2+n) curve: the
## drops are rounded percentages, so -1 is 66/100 and differs on a stat of 150.
const STAGE_MULTIPLIERS: Array = [
	[25, 100], [28, 100], [33, 100], [40, 100], [50, 100], [66, 100],
	[1, 1],
	[15, 10], [2, 1], [25, 10], [3, 1], [35, 10], [4, 1],
]

## Which nibble of the packed DV word holds which stat. The word is two bytes:
## attack and defense in the first, speed and special in the second.
const DV_ATTACK_SHIFT: int = 12
const DV_DEFENSE_SHIFT: int = 8
const DV_SPEED_SHIFT: int = 4
const DV_SPECIAL_SHIFT: int = 0


## The cartridge's square root: the first entry of a table of squares not
## smaller than [param value]. A ceiling, not a floor, and the table starts at 1,
## so an untrained Pokémon answers 1 rather than 0.
static func square_root(value: int) -> int:
	for root: int in range(1, MAX_SQUARE_ROOT):
		if root * root >= value:
			return root
	return MAX_SQUARE_ROOT


## One stat, from base, DV, stat experience and level. [param is_hp] picks the
## other ending alone: HP adds the level and ten where the rest add five.
static func calculate(
	base: int, dv: int, stat_exp: int, level: int, is_hp: bool = false
) -> int:
	@warning_ignore("integer_division")
	var trained: int = square_root(clampi(stat_exp, 0, MAX_STAT_EXP)) / 4
	var value: int = (base + clampi(dv, 0, MAX_DV)) * 2 + trained
	@warning_ignore("integer_division")
	var out: int = value * level / 100
	out += (level + STAT_MIN_HP) if is_hp else STAT_MIN_NORMAL
	return mini(out, MAX_STAT_VALUE)


## HP's DV is not stored: it is the low bit of each of the other four, in the
## order attack, defense, speed, special, which is what shininess reads too.
static func hp_dv(dvs: int) -> int:
	return ((attack_dv(dvs) & 1) << 3) | ((defense_dv(dvs) & 1) << 2) \
		| ((speed_dv(dvs) & 1) << 1) | (special_dv(dvs) & 1)


static func attack_dv(dvs: int) -> int:
	return (dvs >> DV_ATTACK_SHIFT) & 0xF


static func defense_dv(dvs: int) -> int:
	return (dvs >> DV_DEFENSE_SHIFT) & 0xF


static func speed_dv(dvs: int) -> int:
	return (dvs >> DV_SPEED_SHIFT) & 0xF


## Special Attack and Special Defense share one DV: the split arrived for base
## stats and stat experience but not here.
static func special_dv(dvs: int) -> int:
	return (dvs >> DV_SPECIAL_SHIFT) & 0xF


## `GetUnownLetter` (engine/gfx/load_pics.asm), 1 being A: the middle two bits of
## each DV packed into a byte and divided by [constant UNOWN_LETTER_DIVISOR], so
## the highest, $FF, is Z. Nothing stores the letter on either side.
static func unown_letter(dvs: int) -> int:
	var packed: int = ((attack_dv(dvs) & 0x6) << 5) | ((defense_dv(dvs) & 0x6) << 3) \
		| ((speed_dv(dvs) & 0x6) << 1) | ((special_dv(dvs) & 0x6) >> 1)
	@warning_ignore("integer_division")
	var letter: int = packed / UNOWN_LETTER_DIVISOR
	return letter + 1


## Four DVs into the word the cartridge stores, for a caller building one by hand.
static func pack_dvs(attack: int, defense: int, speed: int, special: int) -> int:
	return (clampi(attack, 0, MAX_DV) << DV_ATTACK_SHIFT) \
		| (clampi(defense, 0, MAX_DV) << DV_DEFENSE_SHIFT) \
		| (clampi(speed, 0, MAX_DV) << DV_SPEED_SHIFT) \
		| clampi(special, 0, MAX_DV)


## A stat with a stage applied, capped at [constant MAX_STAT_VALUE] and never
## below 1. Applied to the unmodified stat every time rather than to the last
## answer, so six drops and six rises leave it where it started.
static func apply_stage(value: int, stage: int) -> int:
	var ratio: Array = STAGE_MULTIPLIERS[clampi(stage, MIN_STAGE, MAX_STAGE) - MIN_STAGE]
	@warning_ignore("integer_division")
	var out: int = value * int(ratio[0]) / int(ratio[1])
	return clampi(out, 1, MAX_STAT_VALUE)
