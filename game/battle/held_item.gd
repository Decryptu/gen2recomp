class_name Gen2HeldItem
extends RefCounted

## `ITEMATTR_EFFECT` and `ITEMATTR_PARAM` read: tables and arithmetic, the shape
## [Gen2Status], [Gen2Substatus] and [Gen2Weather] have.
##
## Only the effects a real item carries are named; the twenty more
## `constants/item_data_constants.asm` defines reach no item, which
## `HandleStatBoostingHeldItems`' own comment says. Thick Club and Light Ball
## carry no held effect at all and are checked by number through
## `SpeciesItemBoost`.

const NONE: int = 0

## Berry, Gold Berry and Berry Juice: [code]parameter[/code] HP under half.
const BERRY: int = 1

## A sixteenth of maximum HP a turn; its parameter of 10 is read by nothing.
const LEFTOVERS: int = 3

## Mysteryberry, which refills the first move that ran out.
const RESTORE_PP: int = 6

## Cleanse Tag, which is an overworld encounter-rate item and not a battle one.
const CLEANSE_TAG: int = 8

## One effect per status, plus Miracleberry for all of them and Bitter Berry for
## confusion, which is not a status.
const HEAL_POISON: int = 10
const HEAL_FREEZE: int = 11
const HEAL_BURN: int = 12
const HEAL_SLEEP: int = 13
const HEAL_PARALYZE: int = 14
const HEAL_STATUS: int = 15
const HEAL_CONFUSION: int = 16

## Metal Powder, which is only worth anything on a Ditto.
const METAL_POWDER: int = 42

## The seventeen type boosts, `HELD_NORMAL_BOOST` up in type-chart order, each
## with a parameter of 10 percent.
const NORMAL_BOOST: int = 50
const STEEL_BOOST: int = 66

## The Smoke Ball, which [method Gen2Battle.run_odds] already reads.
const ESCAPE: int = 72

## Scope Lens: one more critical level.
const CRITICAL_UP: int = 73

## Quick Claw: a chance to go first whatever the speeds say.
const QUICK_CLAW: int = 74

## King's Rock: a chance to make an ordinary attack flinch.
const FLINCH: int = 75

## Amulet Coin: prize money, which [Gen2Battle] does not pay.
const AMULET_COIN: int = 76

## BrightPowder: its parameter comes straight off the attacker's accuracy.
const BRIGHTPOWDER: int = 77

## Focus Band: a chance to survive on one hit point.
const FOCUS_BAND: int = 79

## `TypeBoostItems` (data/types/type_boost_items.asm). Dragon Scale rather than
## Dragon Fang boosts Dragon, a shipped bug (`docs/bugs_and_glitches.md`) that
## costs nothing: the effect byte sits where the cartridge put it.
const TYPE_BOOSTS: Dictionary = {
	NORMAL_BOOST: RomLayout.TYPE_NORMAL,
	51: RomLayout.TYPE_FIGHTING,
	52: RomLayout.TYPE_FLYING,
	53: RomLayout.TYPE_POISON,
	54: RomLayout.TYPE_GROUND,
	55: RomLayout.TYPE_ROCK,
	56: RomLayout.TYPE_BUG,
	57: RomLayout.TYPE_GHOST,
	58: RomLayout.TYPE_FIRE,
	59: RomLayout.TYPE_WATER,
	60: RomLayout.TYPE_GRASS,
	61: RomLayout.TYPE_ELECTRIC,
	62: RomLayout.TYPE_PSYCHIC,
	63: RomLayout.TYPE_ICE,
	64: RomLayout.TYPE_DRAGON,
	65: RomLayout.TYPE_DARK,
	STEEL_BOOST: RomLayout.TYPE_STEEL,
}

## `SpeciesItemBoost`'s two by-number items: Thick Club on the physical branch,
## Light Ball on the special one.
const THICK_CLUB: int = 118
const LIGHT_BALL: int = 163
const CUBONE: int = 104
const MAROWAK: int = 105
const PIKACHU: int = 25

## Metal Powder is checked by number too, and only against a Ditto.
const METAL_POWDER_ITEM: int = 35
const DITTO: int = 132

## `MailItems` (data/items/mail_items.asm), pinned rather than imported for want
## of a locator. `BattleCommand_Thief` is the only reader.
const MAIL_ITEMS: Array[int] = [158, 181, 182, 183, 184, 185, 186, 187, 188, 189]

## Metal Powder's half again, floored the way `srl a; add c` floors it.
const METAL_POWDER_NUMERATOR: int = 3
const METAL_POWDER_DENOMINATOR: int = 2

## What a type-boosting item multiplies by, as a percentage added to 100.
const BOOST_DIVISOR: int = 100

## One more critical level, as [constant Gen2Damage.FOCUS_ENERGY_LEVELS] is.
const CRITICAL_LEVELS: int = 1

## `BattleRandom` against the parameter byte: a parameter of 30 is 30 in 256.
const CHANCE_RANGE: int = 256

## `GetSixteenthMaxHP`'s at-least-one sixteenth.
const LEFTOVERS_DIVISOR: int = 16

## Mysteryberry's refill, and Sketch's smaller one, which the cartridge's own
## comment calls a lousy hack.
const RESTORED_PP: int = 5
const SKETCH_RESTORED_PP: int = 1
const SKETCH: int = 166

## `HeldStatusHealingEffects` (data/battle/held_heal_status.asm): Miracleberry's
## row is every status, and Bitter Berry is absent, confusion being none.
const STATUS_HEALS: Dictionary = {
	HEAL_POISON: Gen2Status.POISON,
	HEAL_FREEZE: Gen2Status.FREEZE,
	HEAL_BURN: Gen2Status.BURN,
	HEAL_SLEEP: Gen2Status.SLEEP_MASK,
	HEAL_PARALYZE: Gen2Status.PARALYSIS,
	HEAL_STATUS: Gen2Status.ANY,
}


## `UseHeldStatusHealingItem` clears the whole status byte rather than the masked
## bit, which is the same thing while one status is all a Pokémon can carry.
static func heals_status(effect: int, status: int) -> bool:
	return (int(STATUS_HEALS.get(effect, 0)) & status) != 0


## `UseConfusionHealingItem` takes Bitter Berry and Miracleberry alike.
static func heals_confusion(effect: int) -> bool:
	return effect == HEAL_CONFUSION or effect == HEAL_STATUS


## `HandleHPHealingItem`'s condition: strictly under half, since the cartridge
## doubles the current HP and returns unless it lands below the maximum.
static func wants_hp_berry(hp: int, max_hp: int) -> bool:
	return hp * 2 < max_hp


## What Leftovers restores.
static func leftovers_healing(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / LEFTOVERS_DIVISOR, 1)


## How much PP Mysteryberry puts back into [param move_number].
static func restored_pp(move_number: int) -> int:
	return SKETCH_RESTORED_PP if move_number == SKETCH else RESTORED_PP


## `ITEMATTR_EFFECT`, or [constant NONE].
static func effect_of(data: GameData, item: int) -> int:
	if data == null or item <= 0:
		return NONE
	return int(data.item(item).get("effect", NONE))


## `ITEMATTR_PARAM`; an absent one is -1 in the cache and zero here.
static func parameter_of(data: GameData, item: int) -> int:
	if data == null or item <= 0:
		return 0
	return maxi(int(data.item(item).get("parameter", 0)), 0)


## `TypeBoostItems`' own walk: the row matches both the effect and the type.
static func boosts_type(effect: int, move_type: int) -> bool:
	return TYPE_BOOSTS.get(effect, -1) == move_type


## One hit through a type-boosting item, `* (100 + parameter) / 100`.
static func apply_type_boost(damage: int, percent: int) -> int:
	@warning_ignore("integer_division")
	return damage * (BOOST_DIVISOR + percent) / BOOST_DIVISOR


## `ThickClubBoost` on Cubone or Marowak for a physical move, `LightBallBoost`
## on Pikachu for a special one.
static func doubles_attack(species: int, item: int, physical: bool) -> bool:
	if physical:
		return item == THICK_CLUB and (species == CUBONE or species == MAROWAK)
	return item == LIGHT_BALL and species == PIKACHU


## `DittoMetalPowder`: a Ditto holding Metal Powder.
static func boosts_defence(species: int, item: int) -> bool:
	return species == DITTO and item == METAL_POWDER_ITEM


## Half again on the defence, which is what `srl a; add c` leaves.
static func metal_powder_defence(defence: int) -> int:
	@warning_ignore("integer_division")
	return defence * METAL_POWDER_NUMERATOR / METAL_POWDER_DENOMINATOR


## `ItemIsMail`: whether Thief has to leave this item where it is.
static func is_mail(item: int) -> bool:
	return MAIL_ITEMS.has(item)


## Every held-item chance: `BattleRandom; cp c; jr nc` keeps the effect only
## while the roll is under the parameter.
static func rolls_under(rng: RandomNumberGenerator, parameter: int) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < parameter
