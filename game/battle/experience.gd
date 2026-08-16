class_name Gen2Experience
extends RefCounted

## The six growth curves, what a defeated Pokémon is worth, and the stat
## experience it leaves. Static like [Gen2Stats] and [Gen2Damage]: hardware
## order, every division truncating. The curves are `CalcExpAtLevel`'s formula
## pinned against `data/growth_rates.asm` and swept over all 251 species on all
## three games; see `tools/dump_tables.gd`'s `growth` view.

## `wBaseGrowthRate` order. Only four are used by a real species.
const GROWTH_MEDIUM_FAST: int = 0
const GROWTH_SLIGHTLY_FAST: int = 1
const GROWTH_SLIGHTLY_SLOW: int = 2
const GROWTH_MEDIUM_SLOW: int = 3
const GROWTH_FAST: int = 4
const GROWTH_SLOW: int = 5

## `a, b, c, d, e` in `exp(n) = floor(a*n^3/b) + c*n^2 + d*n - e`. `c` carries its
## sign here; the cartridge keeps the sign in a separate bit.
const CURVES: Dictionary = {
	GROWTH_MEDIUM_FAST: [1, 1, 0, 0, 0],
	GROWTH_SLIGHTLY_FAST: [3, 4, 10, 0, 30],
	GROWTH_SLIGHTLY_SLOW: [3, 4, 20, 0, 70],
	GROWTH_MEDIUM_SLOW: [6, 5, -15, 100, 140],
	GROWTH_FAST: [4, 5, 0, 0, 0],
	GROWTH_SLOW: [5, 4, 0, 0, 0],
}

const MAX_LEVEL: int = 100

## Three bytes on the cartridge, which no curve reaches before level 100.
const MAX_EXP: int = 0xFFFFFF

## The cartridge copies base Sp. Attack into the fifth slot and never touches
## base Sp. Defense, which is why [Gen2BattleMon.stat_exp] keeps one `special`.
const STAT_EXP_KEYS: Array = ["hp", "attack", "defense", "speed", "special"]

## The cartridge skips the division rather than dividing by one, which matters
## because it truncates: a lone recipient keeps the whole byte.
const MIN_PARTICIPANTS_TO_SPLIT: int = 2

## Checked by item number rather than held effect, the way
## `IsAnyMonHoldingExpShare` checks it. It carries no `ITEMATTR_EFFECT` at all.
const EXP_SHARE_ITEM: int = 39

## `BoostExp` is `value + floor(value / 2)`, not multiply-then-divide, and the
## two disagree. The traded and Lucky Egg boosts have no OT ID to read.
const TRAINER_BONUS_NUMERATOR: int = 3
const TRAINER_BONUS_DENOMINATOR: int = 2


## Level 1 is hard-coded to zero: the medium slow curve underflows there, which
## `docs/bugs_and_glitches.md` calls a bug rather than a rule.
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


## Walked upward the way `CalcLevel` walks it: the forward formula truncates, so
## a directly solved inverse would not agree with it at every level.
static func level_for_exp(growth_rate: int, experience_points: int) -> int:
	var level: int = 1
	while level < MAX_LEVEL and total_exp_at(growth_rate, level + 1) <= experience_points:
		level += 1
	return level


## `floor(base_exp * level / 7)`, then a trainer battle's 1.5x.
## [param defeated_base_exp] is *already* divided by [method shared_block], since
## `wEnemyMonBaseExp` is in the block `.EvenlyDivideExpAmongParticipants` walks;
## dividing the award instead truncates in the wrong place.
static func award_for(defeated_level: int, defeated_base_exp: int, is_trainer_battle: bool) -> int:
	@warning_ignore("integer_division")
	var award: int = (defeated_base_exp * defeated_level) / 7
	if is_trainer_battle:
		award = _boost(award)
	return clampi(award, 0, MAX_EXP)


## Its own step because a second boost truncates its own half separately, which
## differs from multiplying by 2.25 in one go.
static func _boost(value: int) -> int:
	@warning_ignore("integer_division")
	return value + (value / 2)


## Keyed like [Gen2BattleMon.stat_exp]. The cartridge divides per stat, not once
## combined, so each share truncates on its own.
static func stat_exp_gain(defeated_stats: Dictionary, participants: int) -> Dictionary:
	return shared_block(defeated_stats, 0, false, participants)["stats"]


## The seven-byte block `wEnemyMonBaseStats` to `wEnemyMonEnd`, shared out. The
## five base stats and the base experience go through one loop, which is why this
## answers for both; the seventh byte is the catch rate, which nothing reads
## after a faint. [param halved] is `UpdateFaintedPlayerMon`'s Exp. Share pass,
## once before any division however many holders there are.
static func shared_block(
	defeated_stats: Dictionary, defeated_base_exp: int, halved: bool, recipients: int
) -> Dictionary:
	var stats: Dictionary = {}
	for key: String in STAT_EXP_KEYS:
		stats[key] = _shared_byte(int(defeated_stats.get(key, 0)), halved, recipients)
	return {
		"stats": stats,
		"base_exp": _shared_byte(defeated_base_exp, halved, recipients),
	}


static func _shared_byte(value: int, halved: bool, recipients: int) -> int:
	var byte: int = value
	if halved:
		@warning_ignore("integer_division")
		byte = byte / 2
	var count: int = maxi(recipients, 1)
	if count >= MIN_PARTICIPANTS_TO_SPLIT:
		@warning_ignore("integer_division")
		byte = byte / count
	return byte
