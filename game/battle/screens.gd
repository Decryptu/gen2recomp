class_name Gen2Screens
extends RefCounted

## `wPlayerScreens` and `wEnemyScreens`: the flags that belong to a side of the
## field rather than to whoever is standing on it.
##
## Nothing clears these on a switch, which is the whole difference between them
## and [Gen2Substatus]: a Reflect put up by one Pokémon still halves damage for
## the one sent out behind it. Only the counters ending them do, in
## [method Gen2Battle._tick_screens] and [method Gen2Battle._tick_safeguard].
##
## Pure arithmetic and no state, the same shape as [Gen2Weather]; the flags and
## the three counters live on [Gen2Battle], one of each per side.

## `constants/battle_constants.asm`'s bit numbers, kept rather than renumbered so
## a `bit SCREENS_REFLECT` in the source reads across. Bit 1 is skipped there and
## SCREENS_UNUSED is exactly what its name says.
const SPIKES: int = 1 << 0
const SAFEGUARD: int = 1 << 2
const LIGHT_SCREEN: int = 1 << 3
const REFLECT: int = 1 << 4

const NONE: int = 0

## What `BattleCommand_Screen` and `BattleCommand_Safeguard` all write. Each
## handler decrements before it looks, so this is four turns and a fifth that
## ends it, the setting turn counting as the first, exactly as
## [constant Gen2Weather.TURNS] does.
const TURNS: int = 5

## What a screen does to the defending stat: `sla c` / `rl b` on the sixteen-bit
## value, before the critical-hit check that may discard it.
const DEFENCE_MULTIPLIER: int = 2

## `SpikesDamage`'s own `GetEighthMaxHP`, paid by whoever walks onto the side the
## spikes are lying on.
const SPIKES_DIVISOR: int = 8


static func has(screens: int, flags: int) -> bool:
	return screens & flags != 0


## Which screen guards [param move_type], which is the whole of the split
## between the two: Reflect sits on the physical branch of `PlayerAttackDamage`
## and Light Screen on the special one. Answers [constant NONE] for neither.
static func guarding_flag(move_type: int) -> int:
	return REFLECT if Gen2Damage.is_physical(move_type) else LIGHT_SCREEN


## Whether a hit of [param move_type] against a side holding [param screens] has
## its defending stat doubled.
static func doubles_defence(screens: int, move_type: int) -> bool:
	return has(screens, guarding_flag(move_type))


static func spikes_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / SPIKES_DIVISOR, 1)


## Whether `SpikesDamage` skips the Pokémon walking in: a Flying-type in either
## slot, and nothing else.
static func spikes_spare(types: Array) -> bool:
	return types.has(RomLayout.TYPE_FLYING)
