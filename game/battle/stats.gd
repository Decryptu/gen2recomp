class_name Gen2Stats
extends RefCounted

## The stat arithmetic: base stats, DVs and stat experience into the numbers a
## battle is fought with.
##
## Integer arithmetic throughout, in the order the hardware does it. That is not
## nostalgia: every division here truncates, and a formula rearranged to be
## tidier gives a different answer often enough to matter. A Pokémon that
## survives on one hit point does so because of a truncation somewhere in here.
##
## Generation 2 has DVs and stat experience, not the effort values later games
## use. A DV is four bits per stat, and HP's is assembled from the low bit of the
## other four rather than stored, which is why a shiny Pokémon has the stats it
## does: shininess is a pattern in the same nibbles.

## The two constants the formula ends on. A stat is never below its floor, so a
## level 1 Pokémon with nothing going for it still has 5 of everything and 11 hit
## points.
const STAT_MIN_NORMAL: int = 5
const STAT_MIN_HP: int = 10

## Stats are stored in two bytes but capped well below what those hold.
const MAX_STAT_VALUE: int = 999

const MAX_DV: int = 15
const MAX_STAT_EXP: int = 65535

## The cartridge finds a square root by walking a table of squares, so it stops
## at the last entry rather than at the true root. Stat experience above 255
## squared is therefore wasted, and the most a full stat exp bar is worth is 63.
const MAX_SQUARE_ROOT: int = 255

## Stat stages run from -6 to +6. The cartridge stores them 7-centred, from 1 to
## 13, because it indexes the multiplier table with them directly; here they are
## the numbers a player would recognise and the table is offset instead.
const MIN_STAGE: int = -6
const MAX_STAGE: int = 6

## What each stage multiplies a stat by, as the numerator and denominator pair the
## cartridge stores. They are not a clean 2/(2+n) curve: the drops are rounded
## percentages, so -1 is 66/100 and not 2/3, and the two disagree by a point on a
## stat of 150.
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


## The square root as the cartridge computes it: the smallest whole number whose
## square is at least [param value], never below 1 and never above
## [constant MAX_SQUARE_ROOT].
##
## This is a ceiling, not a floor, which is easy to get wrong and shows up as a
## stat being one out on a Pokémon that has been trained at all. The cartridge
## scans a table of squares for the first entry that is not smaller than the
## stat experience, and the first entry is 1, so a Pokémon with no stat
## experience answers 1 rather than 0.
static func square_root(value: int) -> int:
	for root: int in range(1, MAX_SQUARE_ROOT):
		if root * root >= value:
			return root
	return MAX_SQUARE_ROOT


## One stat, from its base value, its DV, its stat experience and a level.
##
## [param is_hp] picks the other ending: HP adds the level and ten where every
## other stat adds five. Everything before that is shared, which is why they are
## one function rather than two.
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


## HP's DV, which is not stored: it is the low bit of each of the other four,
## in the order attack, defense, speed, special.
##
## The same four nibbles decide whether a Pokémon is shiny, so its colour and its
## hit points are two readings of one number rather than two facts about it.
static func hp_dv(dvs: int) -> int:
	return ((attack_dv(dvs) & 1) << 3) | ((defense_dv(dvs) & 1) << 2) \
		| ((speed_dv(dvs) & 1) << 1) | (special_dv(dvs) & 1)


static func attack_dv(dvs: int) -> int:
	return (dvs >> DV_ATTACK_SHIFT) & 0xF


static func defense_dv(dvs: int) -> int:
	return (dvs >> DV_DEFENSE_SHIFT) & 0xF


static func speed_dv(dvs: int) -> int:
	return (dvs >> DV_SPEED_SHIFT) & 0xF


## Special Attack and Special Defense share one DV in these games. The split
## arrived in Generation 2 for base stats and stat experience but not for DVs.
static func special_dv(dvs: int) -> int:
	return (dvs >> DV_SPECIAL_SHIFT) & 0xF


## Packs four DVs into the word the cartridge stores, which is what a caller
## building a Pokémon by hand wants.
static func pack_dvs(attack: int, defense: int, speed: int, special: int) -> int:
	return (clampi(attack, 0, MAX_DV) << DV_ATTACK_SHIFT) \
		| (clampi(defense, 0, MAX_DV) << DV_DEFENSE_SHIFT) \
		| (clampi(speed, 0, MAX_DV) << DV_SPEED_SHIFT) \
		| clampi(special, 0, MAX_DV)


## A stat with a stage applied, capped at [constant MAX_STAT_VALUE] and never
## below 1.
##
## The stage is applied to the unmodified stat every time rather than to the last
## answer, so six drops and six rises leave the stat where it started instead of
## grinding it down through twelve truncations.
static func apply_stage(value: int, stage: int) -> int:
	var ratio: Array = STAGE_MULTIPLIERS[clampi(stage, MIN_STAGE, MAX_STAGE) - MIN_STAGE]
	@warning_ignore("integer_division")
	var out: int = value * int(ratio[0]) / int(ratio[1])
	return clampi(out, 1, MAX_STAT_VALUE)
