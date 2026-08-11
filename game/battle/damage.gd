class_name Gen2Damage
extends RefCounted

## The damage formula, in the order and the arithmetic the hardware uses.
##
## Every step truncates and the steps are not commutative, so this is a sequence,
## not an expression: rearranging it changes the answer. Type matchups apply one
## type at a time with a truncation between, the critical multiplier lands before
## the cap and minimum, and the random spread after everything.
##
## The cartridge spends four commands on it, and this file is those four:
## [method damage_stats], [method damage_calc], [method stab_damage] and
## [method apply_variation]. [Gen2EffectCommands] runs them one at a time,
## because half a dozen effects write something between two of them.
## [method calculate] and [method calculate_with] are the composition, for a
## caller that wants a whole hit and has no list to put steps in.
## [constant MAX_VARIATION] with no critical is the highest a hit can go, the
## number a damage calculator quotes.

## Where the formula's constants come from. The cap is applied before the
## minimum is added, so a hit that would flatten the counter lands at 999 and
## the smallest hit that connects at all is 2.
const DAMAGE_CAP: int = 997
const MIN_DAMAGE: int = 2

## The random spread, out of 255. The cartridge rejects anything below 217 and
## then divides, so a hit lands between 85% and 100% of its full value.
const MIN_VARIATION: int = 217
const MAX_VARIATION: int = 255

## What a critical hit multiplies by. Generation 2 doubles the damage rather than
## recomputing it at a higher level, which is what Generation 1 did.
const CRITICAL_MULTIPLIER: int = 2

## The chance of a critical at each critical level, out of 256. Level 0 is the
## one in fifteen every hit has; the levels above it are what a high-critical
## move and Focus Energy add.
const CRITICAL_CHANCES: Array = [17, 32, 64, 85, 128, 128, 128]

## Moves with a raised critical rate, worth two critical levels each.
const HIGH_CRITICAL_MOVES: Array = [0x02, 0x0D, 0x4B, 0x98, 0xA3, 0xB1, 0xEE]

## Focus Energy is worth one. It is here rather than in the move list because it
## is a state the attacker is in, not a property of the move being used.
const FOCUS_ENERGY_LEVELS: int = 1

## Struggle is exempt from STAB and from the type chart alike: the cartridge
## returns out of that step before either is looked at.
const STRUGGLE: int = 0xA5

## STAB is half again, truncated, not a multiply by 1.5.
const STAB_NUMERATOR: int = 3
const STAB_DENOMINATOR: int = 2

## What a confused Pokémon hits itself for: a 40-power typeless physical hit
## against its own Attack and Defense. Neither side's type comes into it, so
## there is no STAB and no matchup, and it is never a critical.
const CONFUSION_POWER: int = 40

## `TruncateHL_BC` holds the attack in `hl` and the defense in `bc` and shifts
## both right by two until each fits in a byte, flooring each at one. The pair is
## shifted together, so the ratio survives and the magnitude does not, which is
## what the formula's own multiply by the attack then reads.
const STAT_BYTE_MAX: int = 0xFF
const TRUNCATE_SHIFT: int = 4


## A hit, rolled. Returns what [method calculate_with] returns.
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


## A hit with both rolls decided. Deterministic, and the whole of the formula.
##
## The cartridge spends four commands on what this composes in one, and every
## effect that reaches inside the formula does so between two of them: Present
## sets the power between [method damage_stats] and [method damage_calc], Triple
## Kick multiplies between [method damage_calc] and [method stab_damage], Fury
## Cutter and Rollout between [method stab_damage] and [method apply_variation].
## So the four are what the effect commands call and this is the composition,
## kept because a caller wanting a whole hit at once (the AI, a test) should not
## have to know the order.
##
## Returns { damage, critical, effectiveness, stab, immune }.
## [code]effectiveness[/code] is in tenths and is the announced number, not always
## the one damage used: see [method GameData.type_effectiveness].
## [code]immune[/code] is a matchup of zero, which the cartridge treats as a miss
## rather than a hit for nothing.
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


## `BattleCommand_DamageStats`, whose two halves are `PlayerAttackDamage` and
## `EnemyAttackDamage`: pick the attacking and defending stats, apply the items
## and the defender's screen, and hand the pair to `TruncateHL_BC`.
##
## Returns [attack, defense], already byte-sized, which is why Selfdestruct's
## halving in [method damage_calc] lands on the truncated value rather than the
## raw one.
static func damage_stats(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	move_type: int,
	critical: bool,
	defender_screens: int = Gen2Screens.NONE
) -> Array:
	if attacker == null or defender == null:
		return [1, 1]
	return truncate_stats(
		_attack_stat(attacker, defender, move_type, critical),
		_defense_stat(attacker, defender, move_type, critical, defender_screens),
		Gen2WorldState.is_crystal_profile(attacker.data)
	)


## `BattleCommand_DamageCalc`: Selfdestruct's halved defense, the formula, the
## type-boosting item, the critical multiplier, the cap and the minimum.
##
## A power of zero returns without writing anything, which is the routine's own
## `ret z`, so a status move reaches [method stab_damage] with no damage rather
## than with the minimum two. `EFFECT_MULTI_HIT` and `EFFECT_CONVERSION` are the
## two the source lets past that check, because both can carry a power of zero
## and have it filled in by the time this runs.
##
## [param level] is the level the formula multiplies, or -1 for the attacker's
## own. `BattleCommand_BeatUp` is the one caller that needs the parameter: it
## loads `e` with a party member's level rather than the level of whoever is on
## the field.
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

	# The type-boosting items land here, on the finished base damage and ahead of
	# the critical multiplier, which is where `PlayerAttackDamage` applies them:
	# after the divide by fifty and before `.CriticalMultiplier`. Struggle reaches
	# this too, because that routine has no Struggle check of its own.
	var boost: int = Gen2HeldItem.effect_of(attacker.data, attacker.item)
	if Gen2HeldItem.boosts_type(boost, move_type):
		damage = Gen2HeldItem.apply_type_boost(
			damage, Gen2HeldItem.parameter_of(attacker.data, attacker.item)
		)

	if critical:
		damage *= CRITICAL_MULTIPLIER
	return mini(damage, DAMAGE_CAP) + MIN_DAMAGE


## `BattleCommand_Stab`: the weather, the same-type bonus and the type matchup,
## in that order, over whatever damage [method damage_calc] left.
##
## Runs for a move with no power too, and has to: `DoPoison` and `DoParalyze`
## both carry `stab` and no `damagecalc`, which is how Thunder Wave learns it has
## no effect on a Ground type. Struggle returns before any of it, since
## `cp STRUGGLE / ret z` is the routine's first two instructions.
##
## Returns { damage, stab, immune, effectiveness }.
##
## [param foresight] is the defender's own `SUBSTATUS_IDENTIFIED`, which drops the
## matchup rows the cartridge keeps past its `-2` marker: Normal and Fighting
## against a Ghost stop being immunities.
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

	# `DoWeatherModifiers` runs at the top of the command, ahead of STAB and of
	# the matchup.
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
		# One type at a time, truncating between them, and never down to nothing:
		# a hit that has landed cannot be rounded away. A move with no power
		# stays at nothing, since every step here is a multiply.
		if worked > 0:
			@warning_ignore("integer_division")
			worked = maxi(worked * multiplier / RomLayout.MATCHUP_EFFECTIVE, 1)

	out["damage"] = worked
	return out


## The formula's core: level, power and the two stats, before the critical
## multiplier, the cap and the minimum.
##
## A defense of zero would divide by zero on the hardware too, so the cartridge
## floors it at one and so does this.
##
## [param attack] and [param defense] arrive already truncated by
## [method truncate_stats]; nothing here shifts them again.
static func base_damage(level: int, power: int, attack: int, defense: int) -> int:
	@warning_ignore("integer_division")
	var out: int = level * 2 / 5 + 2
	out = out * power * attack
	@warning_ignore("integer_division")
	out = out / maxi(defense, 1) / 50
	return out


## `TruncateHL_BC`: the attack and the defense shifted right together, two bits
## at a time, until both fit in a byte, each flooring at one rather than at zero.
##
## Not cosmetic, and not a ratio: `base_damage` multiplies by the attack before
## it divides by the defense, so shifting both changes the answer. A Reflect
## doubling a 200 Defense to 400 is the common way past a byte, which is why this
## and the screens landed together, but a +6 stage, a Thick Club or a Light Ball
## reach it without one.
##
## [param crystal] is the single-player fix. `.finish` re-checks and loops back
## only when `wLinkMode` is not `LINK_COLOSSEUM`; pokegold has no such check at
## all, so on Gold and Silver one pass is all a value gets and anything still
## over a byte wraps, which is `docs/bugs_and_glitches.md`'s "Reflect and Light
## Screen can make (Special) Defense wrap around above 1024".
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


## The random spread, applied last. A hit of one is left alone: there is nothing
## below it to reduce to.
static func apply_variation(damage: int, variation: int) -> int:
	if damage < MIN_DAMAGE:
		return damage
	@warning_ignore("integer_division")
	return damage * clampi(variation, MIN_VARIATION, MAX_VARIATION) / MAX_VARIATION


## Whether this hit is a critical, at the critical level the move and the
## attacker's state add up to.
static func roll_critical(
	move: Dictionary, rng: RandomNumberGenerator, focus_energy: bool = false,
	scope_lens: bool = false
) -> bool:
	if int(move.get("power", 0)) <= 0:
		return false
	return rng.randi_range(0, 255) < CRITICAL_CHANCES[
		critical_level(int(move.get("number", 0)), focus_energy, scope_lens)
	]


## The critical level a hit is rolled at: two for a high-critical move, one for
## Focus Energy, one for the Scope Lens, in the order `BattleCommand_Critical`
## adds them.
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


## What a confused Pokémon does to itself instead of moving: its own Attack
## against its own Defense, with the stages and any burn applied exactly as an
## ordinary physical hit would read them, but no STAB, no type matchup and no
## critical, because the hit is not really an attack at all.
##
## [param screens] is the confused Pokémon's own side's, which is the side being
## hit: `HitSelfInConfusion` picks `wPlayerScreens` for the player's turn and
## doubles the Defense off it exactly as `PlayerAttackDamage` does, so a Reflect
## halves what confusion takes out of the Pokémon that put it up.
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
## magnitude number]. One byte is rolled and the first row whose threshold is at
## or above it wins, so the thresholds are cumulative rather than per-row odds.
## `percent` is `* $ff / 100` and truncates, which is why 5 percent + 1 is 13 and
## not 14.
const MAGNITUDE_POWER: Array = [
	[13, 10, 4], [38, 30, 5], [89, 50, 6], [166, 70, 7],
	[217, 90, 8], [242, 110, 9], [255, 150, 10],
]

## `PresentPower` (`data/moves/present_power.asm`), read the same way, with the
## `-1` terminator standing for the fourth outcome: no hit at all, and a quarter
## of the target's health back instead. The terminator is tested before the
## comparison, so every roll above the last threshold reaches it.
const PRESENT_POWER: Array = [[102, 40], [179, 80], [204, 120]]

## `FlailReversalPower` (`data/moves/flail_reversal_power.asm`), as
## [hp bar pixels, power] with `HP_BAR_LENGTH_PX` at 48. The index is how many
## of those 48 pixels of health are left, so the emptier the bar the earlier the
## walk stops and the harder the hit.
const FLAIL_REVERSAL_POWER: Array = [
	[1, 200], [4, 150], [9, 100], [16, 80], [32, 40], [48, 20],
]

## `HP_BAR_LENGTH_PX`, which Flail and Reversal measure in rather than in a
## percentage.
const HP_BAR_LENGTH_PX: int = 48

## Return and Frustration: `happiness * 10 / 25`, and the same over 255 minus the
## happiness (`engine/battle/move_effects/return.asm`, `.../frustration.asm`).
##
## The two zero ends are the cartridge's own bug and are kept: a Return from a
## Pokémon that hates its trainer and a Frustration from one that loves it both
## work out to a power of zero, which `damagecalc` then refuses outright.
const HAPPINESS_NUMERATOR: int = 10
const HAPPINESS_DENOMINATOR: int = 25
const HAPPINESS_MAX: int = 255


## The row of [constant MAGNITUDE_POWER] a rolled byte lands on.
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


## Flail and Reversal's power, from how much of the health bar is left.
##
## The index is `hp * 48 / max_hp`, except that a maximum over a byte is divided
## down first: `.reversal` shifts the product and the divisor right two bits each
## before the divide, because the routine's divisor is one byte wide. Both are
## integer divisions and the second loses the low bits of each, which is the
## cartridge's answer rather than an approximation of it.
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


## `HiddenPowerDamage`: the move's type and power, both out of the user's DVs.
##
## Returns { type, power }. The power takes the top bit of each of the four DVs
## into a nibble, multiplies by five, adds the Special DV's low two bits, halves
## and adds 31. The type is the Defense DV's low two bits under the Attack DV's,
## stepped over `BIRD` and over the ten unused numbers between Steel and Fire.
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


## Psywave: a random amount from one up to but excluding one and a half times the
## user's level, the halving floored first. The cartridge rerolls a byte until it
## lands in range rather than clamping, which is the same uniform pick. Level 1
## has no such range and would spin forever on hardware, so it reads as a minimum
## of one here.
static func psywave_damage(level: int, rng: RandomNumberGenerator) -> int:
	@warning_ignore("integer_division")
	var upper: int = level / 2 + level
	return rng.randi_range(1, maxi(upper - 1, 1))


## Whether a move is worked out from Attack or from Special Attack.
##
## Generation 2 splits by type, not by move: every type below Fire is physical
## and every type from Fire up special, which is why Hyper Beam is special and
## Bite physical.
static func is_physical(move_type: int) -> bool:
	return move_type < RomLayout.SPECIAL_TYPES_START


## The attacking stat, doubled if the attacker is one of the two species holding
## the item that answers for it: `ThickClubBoost` sits on the physical branch and
## `LightBallBoost` on the special one, both after the stat has been chosen and
## before it is truncated.
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


## The defending stat, doubled by the defender's own screen and half again if
## `DittoMetalPowder` answers: the Pokémon being hit is a Ditto holding Metal
## Powder.
##
## The screen is applied to the boosted stat and only there. `PlayerAttackDamage`
## doubles the pair before `CheckDamageStatsCritical`, and a critical that
## reaches `.thickclub`'s no-carry branch reloads the unmodified stat over it, so
## the same critical that ignores the defender's stages ignores its screen with
## them.
static func _defense_stat(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move_type: int, critical: bool,
	defender_screens: int = Gen2Screens.NONE
) -> int:
	var key: String = "defense" if is_physical(move_type) else "sp_defense"
	var ignores: bool = _ignores_stages(attacker, defender, move_type, critical)
	var out: int = defender.unmodified_stat(key) if ignores else defender.stat(key)
	if not ignores and Gen2Screens.doubles_defence(defender_screens, move_type):
		out *= Gen2Screens.DEFENCE_MULTIPLIER
	if Gen2HeldItem.boosts_defence(defender.species, defender.item):
		out = Gen2HeldItem.metal_powder_defence(out)
	return out


## A critical hit ignores both sides' stages, but only when they are working
## against the attacker.
##
## Narrower than usually described: the cartridge compares the two stages and
## keeps them when the defender's is lower, so a critical from an attacker who
## raised its Attack keeps the boost and one against a raised Defense ignores it.
## The attacker's advantage either way.
static func _ignores_stages(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move_type: int, critical: bool
) -> bool:
	if not critical:
		return false
	if is_physical(move_type):
		return defender.stage("defense") >= attacker.stage("attack")
	return defender.stage("sp_defense") >= attacker.stage("sp_attack")
