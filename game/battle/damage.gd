class_name Gen2Damage
extends RefCounted

## The damage formula, in the order and the arithmetic the hardware uses.
##
## Every step truncates and none of them commute, so this is a sequence rather
## than an expression: the matchup applies one type at a time with a truncation
## between, the critical multiplier lands before the cap and minimum, and the
## spread after everything.
##
## The cartridge's four commands are [method damage_stats], [method damage_calc],
## [method stab_damage] and [method apply_variation], run one at a time by
## [Gen2EffectCommands] because half a dozen effects write between two of them.
## [method calculate] and [method calculate_with] are the composition.

## The cap lands before the minimum is added, so the biggest hit is 999 and the
## smallest that connects at all is 2.
const DAMAGE_CAP: int = 997
const MIN_DAMAGE: int = 2

## The spread, out of 255: rerolled under 217, so 85% to 100%.
const MIN_VARIATION: int = 217
const MAX_VARIATION: int = 255

## A critical doubles the damage here rather than recomputing it at a higher
## level the way Generation 1 did.
const CRITICAL_MULTIPLIER: int = 2

## The chance at each critical level, out of 256; level 0 is every hit's.
const CRITICAL_CHANCES: Array = [17, 32, 64, 85, 128, 128, 128]

## Moves with a raised critical rate, worth two critical levels each.
const HIGH_CRITICAL_MOVES: Array = [0x02, 0x0D, 0x4B, 0x98, 0xA3, 0xB1, 0xEE]

## Focus Energy: a state the attacker is in, not a property of the move.
const FOCUS_ENERGY_LEVELS: int = 1

## Exempt from STAB and the type chart: `BattleCommand_Stab` returns first.
const STRUGGLE: int = 0xA5

## STAB is half again, truncated, not a multiply by 1.5.
const STAB_NUMERATOR: int = 3
const STAB_DENOMINATOR: int = 2

## A typeless physical hit against the Pokémon's own stats: no STAB, no matchup
## and never a critical.
const CONFUSION_POWER: int = 40

## `TruncateHL_BC` shifts the pair right by two until both fit in a byte,
## flooring at one: the ratio survives and the magnitude does not.
const STAT_BYTE_MAX: int = 0xFF
const TRUNCATE_SHIFT: int = 4


## A hit, rolled.
static func calculate(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	move: Dictionary,
	rng: RandomNumberGenerator,
	focus_energy: bool = false,
	defense_halved: bool = false,
	weather: int = Gen2Weather.NONE,
	defender_screens: int = Gen2Screens.NONE,
	foresight: bool = false
) -> Dictionary:
	var scope_lens: bool = attacker != null \
		and Gen2HeldItem.effect_of(attacker.data, attacker.item) == Gen2HeldItem.CRITICAL_UP
	return calculate_with(
		attacker, defender, move,
		roll_critical(move, rng, focus_energy, scope_lens),
		roll_variation(rng), defense_halved, weather, defender_screens, foresight
	)


## A hit with both rolls decided: deterministic, and the whole formula, for a
## caller (the AI, a test) that has no list to put the four steps in. Present,
## Triple Kick, Fury Cutter and Rollout each write between two of them, which is
## why the effect commands call the four rather than this.
##
## Returns { damage, critical, effectiveness, stab, immune }.
## [code]effectiveness[/code] is in tenths and is the announced number, not
## always the one damage used (see [method GameData.type_effectiveness]);
## [code]immune[/code] is a matchup of zero, which is a miss rather than a hit
## for nothing.
static func calculate_with(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	move: Dictionary,
	critical: bool,
	variation: int,
	defense_halved: bool = false,
	weather: int = Gen2Weather.NONE,
	defender_screens: int = Gen2Screens.NONE,
	foresight: bool = false
) -> Dictionary:
	var out: Dictionary = {
		"damage": 0, "critical": critical, "effectiveness": RomLayout.MATCHUP_EFFECTIVE,
		"stab": false, "immune": false,
	}
	if attacker == null or defender == null:
		return out

	var move_type: int = int(move.get("type", RomLayout.TYPE_NORMAL))
	var stats: Array = damage_stats(
		attacker, defender, move_type, critical, defender_screens
	)
	var damage: int = damage_calc(
		attacker, int(move.get("power", 0)), int(stats[0]), int(stats[1]),
		defense_halved, move_type, critical
	)

	var stabbed: Dictionary = stab_damage(
		attacker, defender, move, damage, weather, foresight
	)
	out["stab"] = stabbed["stab"]
	out["immune"] = stabbed["immune"]
	out["effectiveness"] = stabbed["effectiveness"]
	damage = int(stabbed["damage"])

	out["damage"] = apply_variation(damage, variation)
	return out


## `BattleCommand_DamageStats` (`PlayerAttackDamage`, `EnemyAttackDamage`): the
## stats, the items and the screen, handed to `TruncateHL_BC`. The pair comes
## back byte-sized, which is why Selfdestruct's halving in
## [method damage_calc] lands on the truncated value.
static func damage_stats(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	move_type: int,
	critical: bool,
	defender_screens: int = Gen2Screens.NONE
) -> Array:
	if attacker == null or defender == null:
		return [1, 1]
	return metal_powder_pair(defender, truncate_stats(
		_attack_stat(attacker, defender, move_type, critical),
		_defense_stat(attacker, defender, move_type, critical, defender_screens),
		Gen2WorldState.is_crystal_profile(attacker.data)
	))


## `BattleCommand_DamageCalc`: Selfdestruct's halved defense, the formula, the
## type-boosting item, the critical multiplier, the cap and the minimum.
##
## Its `ret z` on a power of zero is why a status move reaches
## [method stab_damage] with no damage rather than the minimum two.
## [param level] is -1 for the attacker's own; `BattleCommand_BeatUp` is the one
## caller that passes a party member's.
static func damage_calc(
	attacker: Gen2BattleMon,
	power: int,
	attack: int,
	defense: int,
	defense_halved: bool,
	move_type: int,
	critical: bool = false,
	level: int = -1
) -> int:
	if attacker == null or power <= 0:
		return 0
	var used_defense: int = defense
	if defense_halved:
		@warning_ignore("integer_division")
		used_defense = maxi(used_defense / 2, 1)

	var damage: int = base_damage(
		attacker.level if level < 0 else level, power, attack, used_defense
	)

	# Where `PlayerAttackDamage` applies them: after the divide by fifty and
	# before `.CriticalMultiplier`. Struggle reaches this too, that routine
	# having no check of its own.
	var boost: int = Gen2HeldItem.effect_of(attacker.data, attacker.item)
	if Gen2HeldItem.boosts_type(boost, move_type):
		damage = Gen2HeldItem.apply_type_boost(
			damage, Gen2HeldItem.parameter_of(attacker.data, attacker.item)
		)

	if critical:
		damage *= CRITICAL_MULTIPLIER
	return mini(damage, DAMAGE_CAP) + MIN_DAMAGE


## `BattleCommand_Stab`: weather, same-type bonus and matchup, in that order,
## over whatever [method damage_calc] left. It runs for a powerless move too, and
## has to: `DoPoison` and `DoParalyze` carry `stab` and no `damagecalc`, which is
## how Thunder Wave learns it does nothing to a Ground type.
##
## Returns { damage, stab, immune, effectiveness }. [param foresight] is
## `SUBSTATUS_IDENTIFIED`, which drops the rows past the chart's `-2` marker.
static func stab_damage(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	move: Dictionary,
	damage: int,
	weather: int = Gen2Weather.NONE,
	foresight: bool = false
) -> Dictionary:
	var out: Dictionary = {
		"damage": damage, "stab": false, "immune": false,
		"effectiveness": RomLayout.MATCHUP_EFFECTIVE,
	}
	if attacker == null or defender == null:
		return out
	if int(move.get("number", 0)) == STRUGGLE:
		return out

	var data: GameData = attacker.data
	var move_type: int = int(move.get("type", RomLayout.TYPE_NORMAL))
	var defending: Array = defender.types()
	out["effectiveness"] = data.type_effectiveness(move_type, defending, foresight)

	var worked: int = damage

	# `DoWeatherModifiers`, ahead of STAB and of the matchup.
	worked = Gen2Weather.apply_damage_modifier(worked, Gen2Weather.damage_modifier(
		weather, move_type, int(move.get("effect", -1))
	))
	if attacker.badge_type_boost_mask & (1 << move_type):
		@warning_ignore("integer_division")
		worked = mini(worked + maxi(worked / 8, 1), 0xFFFF)

	if attacker.types().has(move_type):
		out["stab"] = true
		@warning_ignore("integer_division")
		worked = worked * STAB_NUMERATOR / STAB_DENOMINATOR

	var applied: Array = []
	for defending_type: int in defending:
		if applied.has(defending_type):
			continue
		applied.append(defending_type)
		var multiplier: int = data.type_matchup(move_type, defending_type, foresight)
		if multiplier == RomLayout.MATCHUP_NO_EFFECT:
			out["immune"] = true
			out["damage"] = 0
			return out
		# One type at a time, never down to nothing: a hit that landed cannot be
		# rounded away, and a powerless move stays at nothing regardless.
		if worked > 0:
			@warning_ignore("integer_division")
			worked = maxi(worked * multiplier / RomLayout.MATCHUP_EFFECTIVE, 1)

	out["damage"] = worked
	return out


## Level, power and the two stats, before the critical multiplier, the cap and
## the minimum. The stats arrive truncated and the defense is floored at one, the
## way the cartridge floors it.
static func base_damage(level: int, power: int, attack: int, defense: int) -> int:
	@warning_ignore("integer_division")
	var out: int = level * 2 / 5 + 2
	out = out * power * attack
	@warning_ignore("integer_division")
	out = out / maxi(defense, 1) / 50
	return out


## `TruncateHL_BC`: both stats shifted right two bits at a time until each fits
## in a byte, flooring at one. Not cosmetic: `base_damage` multiplies by the
## attack before it divides by the defense, so shifting both changes the answer.
##
## [param crystal] is the single-player fix, `.finish` looping back while
## `wLinkMode` is not `LINK_COLOSSEUM`. pokegold has no such check, so one pass
## is all a value gets and anything still over a byte wraps, which is
## `docs/bugs_and_glitches.md`'s "Reflect and Light Screen can make (Special)
## Defense wrap around above 1024".
static func truncate_stats(attack: int, defense: int, crystal: bool = true) -> Array:
	var out_attack: int = attack
	var out_defense: int = defense
	while out_attack > STAT_BYTE_MAX or out_defense > STAT_BYTE_MAX:
		@warning_ignore("integer_division")
		out_defense = maxi(out_defense / TRUNCATE_SHIFT, 1)
		@warning_ignore("integer_division")
		out_attack = maxi(out_attack / TRUNCATE_SHIFT, 1)
		if not crystal:
			break
	return [out_attack & STAT_BYTE_MAX, out_defense & STAT_BYTE_MAX]


## The spread, applied last; a hit of one has nothing below it to reduce to.
static func apply_variation(damage: int, variation: int) -> int:
	if damage < MIN_DAMAGE:
		return damage
	@warning_ignore("integer_division")
	return damage * clampi(variation, MIN_VARIATION, MAX_VARIATION) / MAX_VARIATION


## `BattleCommand_Critical`'s roll, at the level below.
static func roll_critical(
	move: Dictionary, rng: RandomNumberGenerator, focus_energy: bool = false,
	scope_lens: bool = false
) -> bool:
	if int(move.get("power", 0)) <= 0:
		return false
	return rng.randi_range(0, 255) < CRITICAL_CHANCES[
		critical_level(int(move.get("number", 0)), focus_energy, scope_lens)
	]


## Two for a high-critical move, one for Focus Energy, one for the Scope Lens,
## in `BattleCommand_Critical`'s own order.
static func critical_level(
	move_number: int, focus_energy: bool = false, scope_lens: bool = false
) -> int:
	var level: int = 0
	if HIGH_CRITICAL_MOVES.has(move_number):
		level += 2
	if focus_energy:
		level += FOCUS_ENERGY_LEVELS
	if scope_lens:
		level += Gen2HeldItem.CRITICAL_LEVELS
	return mini(level, CRITICAL_CHANCES.size() - 1)


static func roll_variation(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_VARIATION, MAX_VARIATION)


## `HitSelfInConfusion`: the Pokémon's own Attack against its own Defense, stages
## and burn read as a physical hit would, and no STAB, matchup or critical.
##
## [param screens] is the confused Pokémon's own side's, doubled off exactly as
## `PlayerAttackDamage` doubles, so a Reflect halves what confusion takes.
static func confusion_damage(
	mon: Gen2BattleMon, rng: RandomNumberGenerator, screens: int = Gen2Screens.NONE
) -> int:
	var defense: int = mon.stat("defense")
	if Gen2Screens.has(screens, Gen2Screens.REFLECT):
		defense *= Gen2Screens.DEFENCE_MULTIPLIER
	var truncated: Array = truncate_stats(
		mon.stat("attack"), defense, Gen2WorldState.is_crystal_profile(mon.data)
	)
	var damage: int = base_damage(
		mon.level, CONFUSION_POWER, int(truncated[0]), int(truncated[1])
	)
	damage = mini(damage, DAMAGE_CAP) + MIN_DAMAGE
	return apply_variation(damage, roll_variation(rng))


## `MagnitudePower` (`data/moves/magnitude_power.asm`), as [threshold, power,
## magnitude]. The first row at or above the rolled byte wins, so the thresholds
## are cumulative; `percent` is `* $ff / 100` truncated, which is why 5 percent
## + 1 is 13.
const MAGNITUDE_POWER: Array = [
	[13, 10, 4], [38, 30, 5], [89, 50, 6], [166, 70, 7],
	[217, 90, 8], [242, 110, 9], [255, 150, 10],
]

## `PresentPower` (`data/moves/present_power.asm`), read the same way. Its `-1`
## terminator is the fourth outcome, a quarter of the target's health back, and
## is tested before the comparison, so every roll above the last row reaches it.
const PRESENT_POWER: Array = [[102, 40], [179, 80], [204, 120]]

## `FlailReversalPower` (`data/moves/flail_reversal_power.asm`), as [hp bar
## pixels, power]: the emptier the bar, the earlier the walk stops.
const FLAIL_REVERSAL_POWER: Array = [
	[1, 200], [4, 150], [9, 100], [16, 80], [32, 40], [48, 20],
]

## What Flail and Reversal measure in, rather than a percentage.
const HP_BAR_LENGTH_PX: int = 48

## Return and Frustration: `happiness * 10 / 25`, and the same over 255 minus it
## (`engine/battle/move_effects/return.asm`, `.../frustration.asm`). Both zero
## ends are the cartridge's own bug, kept: a power of zero, which `damagecalc`
## refuses outright.
const HAPPINESS_NUMERATOR: int = 10
const HAPPINESS_DENOMINATOR: int = 25
const HAPPINESS_MAX: int = 255


## The [constant MAGNITUDE_POWER] row a rolled byte lands on.
static func magnitude_row(roll: int) -> Array:
	for row: Array in MAGNITUDE_POWER:
		if int(row[0]) >= roll:
			return row
	return MAGNITUDE_POWER[MAGNITUDE_POWER.size() - 1]


## The power a rolled byte gives Present, or -1 for the row that heals instead.
static func present_power(roll: int) -> int:
	for row: Array in PRESENT_POWER:
		if int(row[0]) >= roll:
			return int(row[1])
	return -1


## `BattleCommand_HappinessPower` and `..._FrustrationPower`.
static func happiness_power(happiness: int, inverted: bool = false) -> int:
	var value: int = HAPPINESS_MAX - happiness if inverted else happiness
	@warning_ignore("integer_division")
	return value * HAPPINESS_NUMERATOR / HAPPINESS_DENOMINATOR


## `hp * 48 / max_hp`, except that `.reversal` shifts product and divisor right
## two bits each when the maximum is over a byte, its divisor being one byte
## wide. Both divisions truncate, which is the cartridge's own answer.
static func flail_reversal_power(hp: int, max_hp: int) -> int:
	if max_hp <= 0:
		return int(FLAIL_REVERSAL_POWER[0][1])
	var product: int = hp * HP_BAR_LENGTH_PX
	var divisor: int = max_hp
	if max_hp > STAT_BYTE_MAX:
		product >>= 2
		divisor >>= 2
	@warning_ignore("integer_division")
	var index: int = product / maxi(divisor, 1)
	for row: Array in FLAIL_REVERSAL_POWER:
		if int(row[0]) >= index:
			return int(row[1])
	return int(FLAIL_REVERSAL_POWER[FLAIL_REVERSAL_POWER.size() - 1][1])


## `HiddenPowerDamage`, as { type, power }: the top bit of each DV into a nibble
## times five, plus the Special DV's low two bits, halved and plus 31; the type
## is the Defense DV's low two bits under the Attack DV's, stepped over `BIRD`
## and the ten unused numbers between Steel and Fire.
static func hidden_power(dvs: int) -> Dictionary:
	var attack: int = Gen2Stats.attack_dv(dvs)
	var defense: int = Gen2Stats.defense_dv(dvs)
	var speed: int = Gen2Stats.speed_dv(dvs)
	var special: int = Gen2Stats.special_dv(dvs)

	var tops: int = (attack & 8) | ((defense & 8) >> 1) \
		| ((speed & 8) >> 2) | ((special & 8) >> 3)
	@warning_ignore("integer_division")
	var power: int = (tops * 5 + (special & 3)) / 2 + 31

	var move_type: int = (defense & 3) | ((attack & 3) << 2)
	move_type += 1
	if move_type >= RomLayout.TYPE_BIRD:
		move_type += 1
	if move_type >= RomLayout.TYPE_UNUSED_START:
		move_type += RomLayout.TYPE_UNUSED_END - RomLayout.TYPE_UNUSED_START
	return {"type": move_type, "power": power}


## Psywave: one up to but excluding one and a half times the level, the halving
## floored first. The cartridge rerolls rather than clamping, which is the same
## pick; level 1 has no range and would spin on hardware, so it reads as one.
static func psywave_damage(level: int, rng: RandomNumberGenerator) -> int:
	@warning_ignore("integer_division")
	var upper: int = level / 2 + level
	return rng.randi_range(1, maxi(upper - 1, 1))


## The split is by type, not by move: below Fire is physical and Fire up
## special, which is why Hyper Beam is special and Bite physical.
static func is_physical(move_type: int) -> bool:
	return move_type < RomLayout.SPECIAL_TYPES_START


## `ThickClubBoost` on the physical branch and `LightBallBoost` on the special
## one, both after the stat is chosen and before it is truncated.
static func _attack_stat(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move_type: int, critical: bool
) -> int:
	var physical: bool = is_physical(move_type)
	var key: String = "attack" if physical else "sp_attack"
	var out: int = attacker.unmodified_stat(key) \
		if _ignores_stages(attacker, defender, move_type, critical) else attacker.stat(key)
	if Gen2HeldItem.doubles_attack(attacker.species, attacker.item, physical):
		out *= 2
	return out


## The defending stat, doubled by the defender's screen. Metal Powder is not
## here: `DittoMetalPowder` runs past `TruncateHL_BC`, which is
## [method metal_powder_pair].
##
## `PlayerAttackDamage` doubles before `CheckDamageStatsCritical`, and a critical
## reaching `.thickclub`'s no-carry branch reloads the unmodified stat over it,
## so a critical that ignores the defender's stages ignores its screen too.
static func _defense_stat(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move_type: int, critical: bool,
	defender_screens: int = Gen2Screens.NONE
) -> int:
	var key: String = "defense" if is_physical(move_type) else "sp_defense"
	var ignores: bool = _ignores_stages(attacker, defender, move_type, critical)
	var out: int = defender.unmodified_stat(key) if ignores else defender.stat(key)
	if not ignores and Gen2Screens.doubles_defence(defender_screens, move_type):
		out *= Gen2Screens.DEFENCE_MULTIPLIER
	return out


## `DittoMetalPowder`, called at `.done` after `TruncateHL_BC`, so the half again
## lands on the byte rather than on the stat it was truncated from.
##
## Its overflow is reproduced, not corrected: `srl a / add c` carries for a byte
## over 170 and the recovery halves the *attack* and shifts the carry back into
## the defence, which is `docs/bugs_and_glitches.md`'s "Metal Powder can increase
## damage taken with boosted (Special) Defense".
static func metal_powder_pair(defender: Gen2BattleMon, pair: Array) -> Array:
	if defender == null or not Gen2HeldItem.boosts_defence(defender.species, defender.item):
		return pair
	var attack: int = int(pair[0])
	var boosted: int = Gen2HeldItem.metal_powder_defence(int(pair[1]))
	if boosted <= STAT_BYTE_MAX:
		return [attack, boosted]
	# `srl b`, floored at one the way the routine's own `inc b` floors it.
	attack = maxi(attack >> 1, 1)
	# `scf / rr c`: the carry comes back as the high bit of what is left.
	return [attack, ((boosted & STAT_BYTE_MAX) >> 1) | ((STAT_BYTE_MAX + 1) >> 1)]


## A critical ignores both sides' stages, but only when they work against the
## attacker: the cartridge keeps them while the defender's is lower, so a raised
## Attack survives and a raised Defense does not.
static func _ignores_stages(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move_type: int, critical: bool
) -> bool:
	if not critical:
		return false
	if is_physical(move_type):
		return defender.stage("defense") >= attacker.stage("attack")
	return defender.stage("sp_defense") >= attacker.stage("sp_attack")
