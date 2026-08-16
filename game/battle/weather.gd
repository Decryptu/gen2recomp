class_name Gen2Weather
extends RefCounted

## `wBattleWeather` and `wWeatherCount` are one value each for the whole battle,
## so the state lives on [Gen2Battle] and this class is pure arithmetic, the
## shape [Gen2Status] and [Gen2Substatus] have. Five readers: the damage formula
## ([method Gen2Damage.calculate_with]), Thunder's accuracy, Solarbeam's charge
## turn, Freeze, and [method Gen2Battle._tick_weather]'s countdown.

const NONE: int = 0
const RAIN: int = 1
const SUN: int = 2
const SANDSTORM: int = 3

## What `BattleCommand_StartRain`, `StartSun` and `StartSandstorm` all write.
## `HandleWeather` decrements before it looks, so this is four turns of weather
## and a fifth that ends it, the setting turn counting as the first.
const TURNS: int = 5

## `DoWeatherModifiers`' multipliers in tenths, which are the type chart's own
## `MORE_EFFECTIVE` and `NOT_VERY_EFFECTIVE` (constants/battle_constants.asm).
const BOOSTED: int = 15
const WEAKENED: int = 5
const UNCHANGED: int = 10

## `DoWeatherModifiers` floors a zero result at one and answers `$FFFF` on a
## two-byte overflow.
const MODIFIER_DIVISOR: int = 10
const MAX_DAMAGE: int = 0xFFFF

## `WeatherTypeModifiers`: what the weather does to a move of a given type.
const TYPE_MODIFIERS: Dictionary = {
	RAIN: {RomLayout.TYPE_WATER: BOOSTED, RomLayout.TYPE_FIRE: WEAKENED},
	SUN: {RomLayout.TYPE_FIRE: BOOSTED, RomLayout.TYPE_WATER: WEAKENED},
}

## `WeatherMoveModifiers`: the one row that is keyed by effect rather than type,
## read only when no type row matched.
const EFFECT_MODIFIERS: Dictionary = {
	RAIN: {Gen2MoveEffect.SOLARBEAM: WEAKENED},
}

## What a Sandstorm takes each turn, `GetEighthMaxHP`'s at-least-one eighth.
const SANDSTORM_DIVISOR: int = 8

## `.SandstormDamage` checks these and `SUBSTATUS_UNDERGROUND` and nothing else,
## so Flying and a Pokémon in mid-Fly are both hit.
const SANDSTORM_EXEMPT_TYPES: Array[int] = [
	RomLayout.TYPE_ROCK, RomLayout.TYPE_GROUND, RomLayout.TYPE_STEEL,
]


## The check every reader makes before anything else.
static func is_active(weather: int) -> bool:
	return weather != NONE


## `DoWeatherModifiers` in tenths: the type table first, the effect table only
## when no type row matched, which is how Solarbeam's own row is reached.
static func damage_modifier(weather: int, move_type: int, move_effect: int) -> int:
	var by_type: Dictionary = TYPE_MODIFIERS.get(weather, {})
	if by_type.has(move_type):
		return int(by_type[move_type])

	var by_effect: Dictionary = EFFECT_MODIFIERS.get(weather, {})
	return int(by_effect.get(move_effect, UNCHANGED))


## One hit through [method damage_modifier]'s answer, in the cartridge's range.
static func apply_damage_modifier(damage: int, tenths: int) -> int:
	if tenths == UNCHANGED:
		return damage
	@warning_ignore("integer_division")
	return clampi(damage * tenths / MODIFIER_DIVISOR, 1, MAX_DAMAGE)


## What one turn of Sandstorm costs whoever is not exempt from it.
static func sandstorm_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / SANDSTORM_DIVISOR, 1)


## Whether a Sandstorm reaches this Pokémon.
static func hits_in_sandstorm(types: Array, substatus: int) -> bool:
	if Gen2Substatus.has(substatus, Gen2Substatus.UNDERGROUND):
		return false
	for defending_type: int in types:
		if SANDSTORM_EXEMPT_TYPES.has(int(defending_type)):
			return false
	return true
