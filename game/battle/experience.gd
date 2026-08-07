class_name Gen2Experience
extends RefCounted

## Experience: the six growth curves, how much a defeated Pokémon is worth, and
## how much of it a fainted Pokémon leaves behind in stat experience.
##
## [RefCounted] and static like [Gen2Stats] and [Gen2Damage]: integer arithmetic
## in the hardware's order, every division truncating, so a tidier rearrangement
## gives a different answer.
##
## The six curves are [code]CalcExpAtLevel[/code]'s formula, pinned against
## [code]data/growth_rates.asm[/code] and cross-checked against the real
## cartridges: all 251 species in all three games read the growth rate and base
## experience this module expects. See [code]tools/dump_tables.gd[/code]'s
## [code]growth[/code] view.

## The cartridge's byte order for [code]wBaseGrowthRate[/code]
## ([code]GROWTH_*[/code]). Only four are used by a real species in any of the
## three games (medium fast, medium slow, fast, slow); the other two are named
## for completeness.
const GROWTH_MEDIUM_FAST: int = 0
const GROWTH_SLIGHTLY_FAST: int = 1
const GROWTH_SLIGHTLY_SLOW: int = 2
const GROWTH_MEDIUM_SLOW: int = 3
const GROWTH_FAST: int = 4
const GROWTH_SLOW: int = 5

## Each curve as [code]a, b, c, d, e[/code] in
## [code]exp(n) = floor(a*n^3/b) + c*n^2 + d*n - e[/code], the cartridge's formula
## and coefficients. [code]c[/code] carries its sign here; the cartridge stores a
## magnitude with the sign in a separate bit, a storage detail not repeated.
const CURVES: Dictionary = {
	GROWTH_MEDIUM_FAST: [1, 1, 0, 0, 0],
	GROWTH_SLIGHTLY_FAST: [3, 4, 10, 0, 30],
	GROWTH_SLIGHTLY_SLOW: [3, 4, 20, 0, 70],
	GROWTH_MEDIUM_SLOW: [6, 5, -15, 100, 140],
	GROWTH_FAST: [4, 5, 0, 0, 0],
	GROWTH_SLOW: [5, 4, 0, 0, 0],
}

const MAX_LEVEL: int = 100

## Experience is stored in three bytes on the cartridge, so this is the most a
## Pokémon can ever be carrying. No curve reaches it before level 100, so the
## cap exists for the same reason [Gen2Stats.MAX_STAT_EXP] does: to have an
## answer ready rather than to ever actually be reached.
const MAX_EXP: int = 0xFFFFFF

## The five stats a fainted Pokémon leaves behind: HP, Attack, Defense, Speed and
## Special. The cartridge copies *base Sp. Attack* into the fifth slot and never
## touches base Sp. Defense, which is why [Gen2BattleMon.stat_exp] keeps one
## [code]"special"[/code] entry rather than two.
const STAT_EXP_KEYS: Array = ["hp", "attack", "defense", "speed", "special"]

## Awarding exp divides a base stat by the participant count, and the
## cartridge's own routine skips the division outright rather than dividing by
## one, which matters because the division truncates: a single participant
## keeps the whole base stat rather than losing a remainder to the floor.
const MIN_PARTICIPANTS_TO_SPLIT: int = 2

## A trainer battle multiplies the award by 1.5, truncating, computed as
## [code]value + floor(value / 2)[/code] rather than multiply-by-3-divide-by-2:
## the two disagree exactly where the extra truncation matters, and this is
## [code]BoostExp[/code]'s own shape. The traded and Lucky Egg boosts are not
## implemented, since nothing here has an original trainer ID or an item
## engine.
const TRAINER_BONUS_NUMERATOR: int = 3
const TRAINER_BONUS_DENOMINATOR: int = 2


## The total experience a Pokémon on [param growth_rate]'s curve has at exactly
## [param level].
##
## Level 1 is hard-coded to zero rather than run through the formula, which
## underflows there on the medium slow curve
## ([code]floor(6/5) - 15 + 100 - 140[/code] is negative in an unsigned
## three-byte total). [code]docs/bugs_and_glitches.md[/code] documents that as a
## bug, not a rule: a level 1 Pokémon has no experience on any curve.
static func total_exp_at(growth_rate: int, level: int) -> int:
	var n: int = clampi(level, 1, MAX_LEVEL)
	if n <= 1:
		return 0

	var curve: Array = CURVES.get(growth_rate, CURVES[GROWTH_MEDIUM_FAST])
	var a: int = int(curve[0])
	var b: int = int(curve[1])
	var c: int = int(curve[2])
	var d: int = int(curve[3])
	var e: int = int(curve[4])

	@warning_ignore("integer_division")
	var cubic: int = (a * n * n * n) / b
	var quadratic: int = c * n * n
	var linear: int = d * n
	return clampi(cubic + quadratic + linear - e, 0, MAX_EXP)


## The level [param exp] has reached on [param growth_rate]'s curve, found the
## way [code]CalcLevel[/code] finds it: by walking levels upward rather than
## solving the cubic backward, because the forward formula truncates and its
## inverse would not agree with it at every level if it were solved directly.
static func level_for_exp(growth_rate: int, experience_points: int) -> int:
	var level: int = 1
	while level < MAX_LEVEL and total_exp_at(growth_rate, level + 1) <= experience_points:
		level += 1
	return level


## What a Pokémon of [param defeated_level] and [param defeated_base_exp] is
## worth, before it is split among anyone: [code]floor(base_exp * level / 7)[/code],
## then a trainer battle's own 1.5x on top.
##
## Not divided by participant count: that is the stat experience's rule.
## [code]GiveExperiencePoints[/code] hands every participant this full figure and
## only divides the *base stats* feeding [method stat_exp_gain].
static func award_for(defeated_level: int, defeated_base_exp: int, is_trainer_battle: bool) -> int:
	@warning_ignore("integer_division")
	var award: int = (defeated_base_exp * defeated_level) / 7
	if is_trainer_battle:
		award = _boost(award)
	return clampi(award, 0, MAX_EXP)


## The 1.5x a trainer battle, a traded Pokémon or a held Lucky Egg each apply, as
## the cartridge computes it: half the value, truncated, added back. Its own step
## because a second boost truncates its own half separately and would differ from
## multiplying by 2.25 in one go.
static func _boost(value: int) -> int:
	@warning_ignore("integer_division")
	return value + (value / 2)


## How much of the five stats in [constant STAT_EXP_KEYS] a fainted Pokémon
## leaves behind, keyed like [Gen2BattleMon.stat_exp]. Split evenly across
## [param participants], each share truncated on its own rather than the total
## truncated once: the cartridge divides per stat, not once combined.
static func stat_exp_gain(defeated_stats: Dictionary, participants: int) -> Dictionary:
	var count: int = maxi(participants, 1)
	var out: Dictionary = {}
	for key: String in STAT_EXP_KEYS:
		var base: int = int(defeated_stats.get(key, 0))
		if count >= MIN_PARTICIPANTS_TO_SPLIT:
			@warning_ignore("integer_division")
			base = base / count
		out[key] = base
	return out
