class_name Gen2Damage
extends RefCounted

## The damage formula, in the order and the arithmetic the hardware uses.
##
## Every step truncates, and the steps are not commutative, so this is written as
## a sequence rather than as an expression. Rearranging it into one line changes
## the answer: the type matchups are applied to the damage one type at a time
## with a truncation between them, the critical multiplier lands before the cap
## and the minimum, and the random spread lands after everything.
##
## Randomness is injected. [method calculate] rolls the two things a hit rolls,
## the critical and the spread, and hands both to [method calculate_with], which
## is deterministic and is what a test should be pointed at. Asking for
## [constant MAX_VARIATION] and no critical is the highest a hit can go, which is
## the number a damage calculator quotes.

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


## A hit, rolled. Returns what [method calculate_with] returns.
static func calculate(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	move: Dictionary,
	rng: RandomNumberGenerator,
	focus_energy: bool = false
) -> Dictionary:
	return calculate_with(
		attacker, defender, move,
		roll_critical(move, rng, focus_energy), roll_variation(rng)
	)


## A hit with both rolls decided. Deterministic, and the whole of the formula.
##
## Returns { damage, critical, effectiveness, stab, immune }. [code]effectiveness[/code]
## is in tenths and is the number the battle announces, which is not always the
## number the damage was worked out with: see [method GameData.type_effectiveness].
## [code]immune[/code] is the cartridge's own answer to a matchup of zero, which
## it treats as a miss rather than as a hit for nothing.
static func calculate_with(
	attacker: Gen2BattleMon,
	defender: Gen2BattleMon,
	move: Dictionary,
	critical: bool,
	variation: int
) -> Dictionary:
	var out: Dictionary = {
		"damage": 0, "critical": critical, "effectiveness": RomLayout.MATCHUP_EFFECTIVE,
		"stab": false, "immune": false,
	}
	var power: int = int(move.get("power", 0))
	var move_type: int = int(move.get("type", RomLayout.TYPE_NORMAL))
	var number: int = int(move.get("number", 0))
	if attacker == null or defender == null:
		return out

	var data: GameData = attacker.data
	var defending: Array = defender.types()
	if number != STRUGGLE:
		out["effectiveness"] = data.type_effectiveness(move_type, defending)

	if power <= 0:
		# A move with no power is not a failed attack, it is a move that does
		# something else. The matchup is still worked out, because the battle
		# announces it either way, and because a status move is stopped by an
		# immunity exactly as an attack is: Thunder Wave does nothing to a Ground
		# type and Poison Powder nothing to a Steel one.
		for defending_type: int in defending:
			if data.type_matchup(move_type, defending_type) == RomLayout.MATCHUP_NO_EFFECT:
				out["immune"] = true
				break
		return out

	var damage: int = base_damage(
		attacker.level, power, _attack_stat(attacker, defender, move_type, critical),
		_defense_stat(attacker, defender, move_type, critical)
	)
	if critical:
		damage *= CRITICAL_MULTIPLIER
	damage = mini(damage, DAMAGE_CAP) + MIN_DAMAGE

	# Struggle returns before both of these, so it is neither boosted by the
	# attacker's type nor stopped by the defender's.
	if number != STRUGGLE:
		if attacker.types().has(move_type):
			out["stab"] = true
			@warning_ignore("integer_division")
			damage = damage * STAB_NUMERATOR / STAB_DENOMINATOR

		var applied: Array = []
		for defending_type: int in defending:
			if applied.has(defending_type):
				continue
			applied.append(defending_type)
			var multiplier: int = data.type_matchup(move_type, defending_type)
			if multiplier == RomLayout.MATCHUP_NO_EFFECT:
				out["immune"] = true
				out["damage"] = 0
				return out
			# One type at a time, truncating between them, and never down to
			# nothing: a hit that has landed cannot be rounded away.
			@warning_ignore("integer_division")
			damage = maxi(damage * multiplier / RomLayout.MATCHUP_EFFECTIVE, 1)

	out["damage"] = apply_variation(damage, variation)
	return out


## The formula's core: level, power and the two stats, before the critical
## multiplier, the cap and the minimum.
##
## A defense of zero would divide by zero on the hardware too, so the cartridge
## floors it at one and so does this.
static func base_damage(level: int, power: int, attack: int, defense: int) -> int:
	@warning_ignore("integer_division")
	var out: int = level * 2 / 5 + 2
	out = out * power * attack
	@warning_ignore("integer_division")
	out = out / maxi(defense, 1) / 50
	return out


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
	move: Dictionary, rng: RandomNumberGenerator, focus_energy: bool = false
) -> bool:
	if int(move.get("power", 0)) <= 0:
		return false
	return rng.randi_range(0, 255) < CRITICAL_CHANCES[
		critical_level(int(move.get("number", 0)), focus_energy)
	]


static func critical_level(move_number: int, focus_energy: bool = false) -> int:
	var level: int = 0
	if HIGH_CRITICAL_MOVES.has(move_number):
		level += 2
	if focus_energy:
		level += FOCUS_ENERGY_LEVELS
	return mini(level, CRITICAL_CHANCES.size() - 1)


static func roll_variation(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_VARIATION, MAX_VARIATION)


## What a confused Pokémon does to itself instead of moving: its own Attack
## against its own Defense, with the stages and any burn applied exactly as an
## ordinary physical hit would read them, but no STAB, no type matchup and no
## critical, because the hit is not really an attack at all.
static func confusion_damage(mon: Gen2BattleMon, rng: RandomNumberGenerator) -> int:
	var damage: int = base_damage(mon.level, CONFUSION_POWER, mon.stat("attack"), mon.stat("defense"))
	damage = mini(damage, DAMAGE_CAP) + MIN_DAMAGE
	return apply_variation(damage, roll_variation(rng))


## Psywave: a random amount from one up to, but not including, one and a half
## times the user's own level, the halving floored first. The cartridge draws
## this by rerolling a byte until it lands inside that range rather than
## clamping into it, which is a uniform pick over the same range and not a
## detail worth reproducing bit for bit; a level of 1 has no such range at all
## on the real hardware and would spin forever, which this reads as a minimum
## of one rather than replicate.
static func psywave_damage(level: int, rng: RandomNumberGenerator) -> int:
	@warning_ignore("integer_division")
	var upper: int = level / 2 + level
	return rng.randi_range(1, maxi(upper - 1, 1))


## Whether a move is worked out from Attack or from Special Attack.
##
## Generation 2 splits by the move's type and not by the move: every type below
## Fire is physical and every type from Fire up is special, which is why Hyper
## Beam is special and Bite is physical.
static func is_physical(move_type: int) -> bool:
	return move_type < RomLayout.SPECIAL_TYPES_START


static func _attack_stat(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move_type: int, critical: bool
) -> int:
	var key: String = "attack" if is_physical(move_type) else "sp_attack"
	if _ignores_stages(attacker, defender, move_type, critical):
		return attacker.unmodified_stat(key)
	return attacker.stat(key)


static func _defense_stat(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move_type: int, critical: bool
) -> int:
	var key: String = "defense" if is_physical(move_type) else "sp_defense"
	if _ignores_stages(attacker, defender, move_type, critical):
		return defender.unmodified_stat(key)
	return defender.stat(key)


## A critical hit ignores both sides' stages, but only when they are working
## against the attacker.
##
## This is narrower than it is usually described. The cartridge compares the two
## stages and keeps them if the defender's is the lower one, so a critical hit
## from an attacker who has raised its own Attack still gets the boost, and one
## against a defender who has raised its Defense does not have to fight through
## it. It is the attacker's advantage either way.
static func _ignores_stages(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move_type: int, critical: bool
) -> bool:
	if not critical:
		return false
	if is_physical(move_type):
		return defender.stage("defense") >= attacker.stage("attack")
	return defender.stage("sp_defense") >= attacker.stage("sp_attack")
