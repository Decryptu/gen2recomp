class_name Gen2HeldItem
extends RefCounted

## What a Pokémon is carrying, and what the battle does about it.
##
## An item's held effect and its parameter are already on every row the importer
## writes ([code]effect[/code] and [code]parameter[/code]), which is
## `ITEMATTR_EFFECT` and `ITEMATTR_PARAM`. This class is the reading of them:
## pure arithmetic and tables, the same shape [Gen2Status], [Gen2Substatus] and
## [Gen2Weather] have.
##
## Only the effects a real item carries are named. `constants/item_data_constants.asm`
## defines twenty more, and no item in any of the three games has one:
## `HandleStatBoostingHeldItems` says so itself ("The effects handled here are
## not used in-game"), and the same is true of every `HELD_PREVENT_*`.
##
## Two of the items here have no held effect at all. Thick Club and Light Ball
## are checked by item number, through `SpeciesItemBoost`, because what they do
## depends on who is holding them.

const NONE: int = 0

## Berry and Gold Berry restore [code]parameter[/code] HP once the holder drops
## below half; Berry Juice is the same effect with a larger number.
const BERRY: int = 1

## A sixteenth of maximum HP every turn. Its own parameter is 10 and nothing
## reads it.
const LEFTOVERS: int = 3

## Mysteryberry, which refills the first move that ran out.
const RESTORE_PP: int = 6

## Cleanse Tag, which is an overworld encounter-rate item and not a battle one.
const CLEANSE_TAG: int = 8

## The status berries, one effect per status plus Miracleberry for all of them
## and Bitter Berry for confusion, which is not a status at all.
const HEAL_POISON: int = 10
const HEAL_FREEZE: int = 11
const HEAL_BURN: int = 12
const HEAL_SLEEP: int = 13
const HEAL_PARALYZE: int = 14
const HEAL_STATUS: int = 15
const HEAL_CONFUSION: int = 16

## Metal Powder, which is only worth anything on a Ditto.
const METAL_POWDER: int = 42

## The seventeen type-boosting items, one per type, running from
## `HELD_NORMAL_BOOST` in the type chart's own order. Each carries a parameter of
## 10, which is the percentage it adds.
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

## Amulet Coin, which doubles prize money and so is not a battle-engine effect
## here: no money changes hands inside [Gen2Battle].
const AMULET_COIN: int = 76

## BrightPowder: its parameter comes straight off the attacker's accuracy.
const BRIGHTPOWDER: int = 77

## Focus Band: a chance to survive on one hit point.
const FOCUS_BAND: int = 79

## `TypeBoostItems` (data/types/type_boost_items.asm), which is the whole of the
## `HELD_*_BOOST` run in the type chart's own order. Dragon Scale rather than
## Dragon Fang boosts Dragon, which `docs/bugs_and_glitches.md` records as a bug
## the games ship rather than a choice; nothing here has to do anything about
## that, since the effect byte is on the item the cartridge put it on.
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

## The two items `SpeciesItemBoost` checks by number, with the species each one
## answers for. Thick Club is reached on the physical branch and Light Ball on
## the special one, so each doubles the stat its own branch had already chosen.
const THICK_CLUB: int = 118
const LIGHT_BALL: int = 163
const CUBONE: int = 104
const MAROWAK: int = 105
const PIKACHU: int = 25

## Metal Powder is checked by number too, and only against a Ditto.
const METAL_POWDER_ITEM: int = 35
const DITTO: int = 132

## `MailItems` (data/items/mail_items.asm), which `ItemIsMail` walks. Pinned here
## rather than imported: the table has no locator, the way `RadioChannels` in
## `game/world/world_radio.gd` has none. `BattleCommand_Thief` is its only reader,
## and no mail model exists.
const MAIL_ITEMS: Array[int] = [158, 181, 182, 183, 184, 185, 186, 187, 188, 189]

## What Metal Powder does to the defence it is read against: half again, floored
## the way the cartridge's `srl a; add c` floors it.
const METAL_POWDER_NUMERATOR: int = 3
const METAL_POWDER_DENOMINATOR: int = 2

## What a type-boosting item multiplies by, as a percentage added to 100.
const BOOST_DIVISOR: int = 100

## One more critical level, the same shape [constant Gen2Damage.FOCUS_ENERGY_LEVELS]
## already has.
const CRITICAL_LEVELS: int = 1

## The range every held-item roll is out of: `BattleRandom` against the item's
## own parameter byte, so a parameter of 30 is 30 in 256.
const CHANCE_RANGE: int = 256

## What Leftovers gives back each turn, `GetSixteenthMaxHP`'s at-least-one
## sixteenth. Its own parameter is not read.
const LEFTOVERS_DIVISOR: int = 16

## What Mysteryberry puts back into the first move that ran out, and the one move
## it puts back less into. Sketch is by number, and the cartridge's own comment
## calls it a lousy hack.
const RESTORED_PP: int = 5
const SKETCH_RESTORED_PP: int = 1
const SKETCH: int = 166

## `HeldStatusHealingEffects` (data/battle/held_heal_status.asm): which status
## each berry answers for. Miracleberry's row is every status at once, and Bitter
## Berry is not here at all because confusion is not a status.
const STATUS_HEALS: Dictionary = {
	HEAL_POISON: Gen2Status.POISON,
	HEAL_FREEZE: Gen2Status.FREEZE,
	HEAL_BURN: Gen2Status.BURN,
	HEAL_SLEEP: Gen2Status.SLEEP_MASK,
	HEAL_PARALYZE: Gen2Status.PARALYSIS,
	HEAL_STATUS: Gen2Status.ANY,
}


## Whether an effect is a berry that answers for [param status].
##
## `UseHeldStatusHealingItem` clears the whole status byte rather than the masked
## bit, which is the same thing while one status is all a Pokémon can carry.
static func heals_status(effect: int, status: int) -> bool:
	return (int(STATUS_HEALS.get(effect, 0)) & status) != 0


## Whether an effect is one of the two berries that answer for confusion:
## `UseConfusionHealingItem` takes Bitter Berry and Miracleberry alike.
static func heals_confusion(effect: int) -> bool:
	return effect == HEAL_CONFUSION or effect == HEAL_STATUS


## `HandleHPHealingItem`'s own condition, which is strictly under half rather
## than at or under it: the cartridge doubles the current HP and returns unless
## it comes in below the maximum.
static func wants_hp_berry(hp: int, max_hp: int) -> bool:
	return hp * 2 < max_hp


## What Leftovers restores.
static func leftovers_healing(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / LEFTOVERS_DIVISOR, 1)


## How much PP Mysteryberry puts back into [param move_number].
static func restored_pp(move_number: int) -> int:
	return SKETCH_RESTORED_PP if move_number == SKETCH else RESTORED_PP


## The held effect of [param item], or [constant NONE]. The item's own
## [code]effect[/code] field is `ITEMATTR_EFFECT`.
static func effect_of(data: GameData, item: int) -> int:
	if data == null or item <= 0:
		return NONE
	return int(data.item(item).get("effect", NONE))


## The item's `ITEMATTR_PARAM`, which is what every held-item roll is against and
## what the HP and percentage effects carry their number in. Absent parameters
## are stored as -1 by the importer and answer zero here, since nothing that
## reads one is reached by an item that has none.
static func parameter_of(data: GameData, item: int) -> int:
	if data == null or item <= 0:
		return 0
	return maxi(int(data.item(item).get("parameter", 0)), 0)


## Whether a held effect boosts [param move_type], which is `TypeBoostItems`'
## own walk: the row has to match both the effect and the type.
static func boosts_type(effect: int, move_type: int) -> bool:
	return TYPE_BOOSTS.get(effect, -1) == move_type


## One hit through a type-boosting item, `* (100 + parameter) / 100`.
static func apply_type_boost(damage: int, percent: int) -> int:
	@warning_ignore("integer_division")
	return damage * (BOOST_DIVISOR + percent) / BOOST_DIVISOR


## Whether `ThickClubBoost` or `LightBallBoost` doubles the stat this hit is
## worked out from: Thick Club on Cubone or Marowak for a physical move, Light
## Ball on Pikachu for a special one.
static func doubles_attack(species: int, item: int, physical: bool) -> bool:
	if physical:
		return item == THICK_CLUB and (species == CUBONE or species == MAROWAK)
	return item == LIGHT_BALL and species == PIKACHU


## Whether `DittoMetalPowder` applies: the Pokémon being hit is a Ditto and it is
## holding Metal Powder.
static func boosts_defence(species: int, item: int) -> bool:
	return species == DITTO and item == METAL_POWDER_ITEM


## Half again on the defence, which is what `srl a; add c` leaves.
static func metal_powder_defence(defence: int) -> int:
	@warning_ignore("integer_division")
	return defence * METAL_POWDER_NUMERATOR / METAL_POWDER_DENOMINATOR


## `ItemIsMail`: whether Thief has to leave this item where it is.
static func is_mail(item: int) -> bool:
	return MAIL_ITEMS.has(item)


## Whether a roll out of 256 came in under an item's own parameter, which is
## every held-item chance in the game: `BattleRandom; cp c; jr nc` keeps the
## effect only while the roll is below it.
static func rolls_under(rng: RandomNumberGenerator, parameter: int) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < parameter
