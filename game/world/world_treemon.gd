class_name Gen2WorldTreemon
extends RefCounted

## The headbutt-tree and rock-smash encounter rolls
## (engine/events/treemons.asm), which share their tables.
##
## TreeMonEncounter is four questions: has this map a set, is the set under this
## profile's limit, does GetTreeMon's score and roll make an encounter, and which
## row does SelectTreeMon land on. Only the last two are random; the caller
## resolves the lookups through [GameData]. The generator is required rather than
## defaulted, so nothing here can roll on an uninjected one.

## GetTreeScore's three answers (constants/pokemon_data_constants.asm).
const SCORE_BAD: int = 0
const SCORE_GOOD: int = 1
const SCORE_RARE: int = 2

## GetTreeMons' `cp NUM_TREEMON_SETS`; pokegold reads `- 2` and asserts the last
## two sets are UNUSED and CITY, so its five TREEMON_SET_CITY maps yield no
## headbutt encounter despite having data.
const SET_LIMIT_CRYSTAL: int = 8
const SET_LIMIT_GOLD_SILVER: int = 4

## TREEMON_SET_NONE, which GetTreeMons refuses before the limit check.
const SET_NONE: int = 0

## GetTreeMon's three RandomRange(10) thresholds.
const ENCOUNTER_THRESHOLDS: Dictionary = {
	SCORE_BAD: 1,
	SCORE_GOOD: 5,
	SCORE_RARE: 8,
}

## RockMonEncounter's flat threshold, "40% chance of an encounter" in both pins:
## nothing scores a rock.
const ROCK_ENCOUNTER_THRESHOLD: int = 4

## CheckSleepingTreeMon's status turns for a tree encounter that starts asleep
## (constants/battle_constants.asm's TREEMON_SLEEP_TURNS).
const SLEEP_TURNS: int = 7

## What separates a walk cell from wPlayerMapX/wPlayerMapY.
const MAP_BORDER: int = 4


## The only line engine/events/treemons.asm differs on between the pins.
static func set_limit(is_crystal: bool) -> int:
	return SET_LIMIT_CRYSTAL if is_crystal else SET_LIMIT_GOLD_SILVER


## GetTreeMons: whether a set number resolves to a readable table at all.
static func set_is_usable(set_number: int, is_crystal: bool) -> bool:
	return set_number != SET_NONE and set_number < set_limit(is_crystal)


## GetTreeScore's .CoordScore: `hl = y * (x + 1) + x`, then `/ 5`, then `% 10`,
## through the source's 16-bit Divide. GetFacingTileCoord answers in
## wPlayerMapX/wPlayerMapY, which carry the four-cell border, so [param cell]
## being a walk cell is why the offset is added here and nowhere else.
static func coord_score(cell: Vector2i) -> int:
	var x: int = cell.x + MAP_BORDER
	var y: int = cell.y + MAP_BORDER
	var value: int = (y * (x + 1) + x) & 0xFFFF
	@warning_ignore("integer_division")
	return (value / 5) % 10


## GetTreeScore's .OTIDScore: the player's own trainer ID, mod ten.
static func otid_score(player_id: int) -> int:
	return (player_id & 0xFFFF) % 10


## GetTreeScore: equal is RARE, a difference under five once wrapped into 0..9
## GOOD, anything else BAD. The source tests before wrapping, so only a true
## equal is RARE.
static func score(cell: Vector2i, player_id: int) -> int:
	var difference: int = coord_score(cell) - otid_score(player_id)
	if difference == 0:
		return SCORE_RARE
	if difference < 0:
		difference += 10
	return SCORE_GOOD if difference < 5 else SCORE_BAD


## GetTreeMon: the score, RandomRange(10) against its threshold, then
## SelectTreeMon over the table that score chose, only RARE reaching the rare
## one. Empty is TreeMonEncounter's own `wScriptVar = 0`.
static func resolve(
	set_record: Dictionary, cell: Vector2i, player_id: int,
	random: RandomNumberGenerator
) -> Dictionary:
	if set_record.is_empty() or random == null:
		return {}
	var tier: int = score(cell, player_id)
	var encounter_roll: int = random.randi_range(0, 9)
	if not encounter_allowed(tier, encounter_roll):
		return {}
	var key: String = "rare" if tier == SCORE_RARE else "common"
	var table: Variant = set_record.get(key, [])
	if not table is Array or (table as Array).is_empty():
		return {}
	var selected: Dictionary = select_at(table as Array, random.randi_range(0, 99))
	if selected.is_empty():
		return {}
	selected["score"] = tier
	selected["encounter_roll"] = encounter_roll
	return selected


## RockMonEncounter: the same tables over RockMonMaps, a flat `RandomRange(10)`
## under 4, and `SelectTreeMon` called directly rather than through GetTreeMon,
## so there is no score, no trainer ID and no rare table, which is why
## TreeMonSet_Rock ships without one. It writes no wBattleType either, so a
## smashed rock is an ordinary wild battle.
static func rock_encounter(
	set_record: Dictionary, random: RandomNumberGenerator
) -> Dictionary:
	if set_record.is_empty() or random == null:
		return {}
	var encounter_roll: int = random.randi_range(0, 9)
	if not rock_encounter_allowed(encounter_roll):
		return {}
	var table: Variant = set_record.get("common", [])
	if not table is Array or (table as Array).is_empty():
		return {}
	var selected: Dictionary = select_at(table as Array, random.randi_range(0, 99))
	if selected.is_empty():
		return {}
	selected["encounter_roll"] = encounter_roll
	return selected


## RockMonEncounter's `cp 4`, kept apart from the roll as the tree ones are.
static func rock_encounter_allowed(roll: int) -> bool:
	return roll < ROCK_ENCOUNTER_THRESHOLD


## GetTreeMon's per-tier comparison, apart from the roll so both sides of each
## threshold are assertable.
static func encounter_allowed(tier: int, roll: int) -> bool:
	return roll < int(ENCOUNTER_THRESHOLDS.get(tier, 0))


## SelectTreeMon with its RandomRange(100) drawn: subtract each row's percentage
## until it borrows. Off the end is the `$ff` row, NoTreeMon.
static func select_at(table: Array, roll: int) -> Dictionary:
	var remainder: int = roll
	for row: Variant in table:
		if not row is Dictionary:
			return {}
		var percent: int = int((row as Dictionary).get("percent", 0))
		if remainder < percent:
			return {
				"species": int((row as Dictionary).get("species", 0)),
				"level": int((row as Dictionary).get("level", 0)),
				"slot_roll": roll,
			}
		remainder -= percent
	return {}


## CheckSleepingTreeMon's list selection: below DAY_F is the morning list, DAY_F
## itself the day list, anything above the night one.
static func asleep_list_key(time_of_day: int) -> String:
	if time_of_day < Gen2WorldPalette.TIME_DAY:
		return "morn"
	return "day" if time_of_day == Gen2WorldPalette.TIME_DAY else "nite"


## CheckSleepingTreeMon. Gold and Silver import no lists, pokegold shipping
## neither the routine nor the data, so this is false there.
static func starts_asleep(species: int, asleep_species: Array) -> bool:
	return asleep_species.has(species)
