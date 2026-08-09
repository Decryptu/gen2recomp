class_name Gen2WorldTreemon
extends RefCounted

## The headbutt-tree and rock-smash encounter rolls
## (engine/events/treemons.asm), which share their tables.
##
## TreeMonEncounter is four questions in order: does this map have a treemon
## set, does that set exist under this profile's limit, does GetTreeMon's score
## and roll produce an encounter, and which row does SelectTreeMon land on.
## Only the last two are random; the first two are table lookups the caller
## resolves through [GameData]. RockMonEncounter is the same two lookups over
## RockMonMaps and then one flat roll, see [method rock_encounter].
##
## The generator is required rather than defaulted, so nothing here can roll on
## an uninjected generator the way advance_roaming() still can.

## GetTreeScore's three answers (constants/pokemon_data_constants.asm).
const SCORE_BAD: int = 0
const SCORE_GOOD: int = 1
const SCORE_RARE: int = 2

## GetTreeMons' `cp NUM_TREEMON_SETS`. pokegold reads `cp NUM_TREEMON_SETS - 2`
## instead, with its own assert that the last two sets are UNUSED and CITY, so
## Gold and Silver refuse both: the five maps TreeMonMaps gives
## TREEMON_SET_CITY yield no headbutt encounter at all despite having data.
const SET_LIMIT_CRYSTAL: int = 8
const SET_LIMIT_GOLD_SILVER: int = 4

## TREEMON_SET_NONE, which GetTreeMons refuses before the limit check.
const SET_NONE: int = 0

## GetTreeMon's three RandomRange(10) thresholds: an encounter needs a roll
## under the threshold for the score it drew.
const ENCOUNTER_THRESHOLDS: Dictionary = {
	SCORE_BAD: 1,
	SCORE_GOOD: 5,
	SCORE_RARE: 8,
}

## RockMonEncounter's own threshold, commented "40% chance of an encounter" in
## both pins. It is a flat chance rather than one of three, because nothing
## scores a rock.
const ROCK_ENCOUNTER_THRESHOLD: int = 4

## CheckSleepingTreeMon's status turns for a tree encounter that starts asleep
## (constants/battle_constants.asm's TREEMON_SLEEP_TURNS).
const SLEEP_TURNS: int = 7

## The four-cell border every map is drawn inside, which is what separates a
## walk cell from wPlayerMapX/wPlayerMapY.
const MAP_BORDER: int = 4


## The set limit for a profile, which is the only line
## engine/events/treemons.asm differs on between the pins.
static func set_limit(is_crystal: bool) -> int:
	return SET_LIMIT_CRYSTAL if is_crystal else SET_LIMIT_GOLD_SILVER


## GetTreeMons: whether a set number resolves to a readable table at all.
static func set_is_usable(set_number: int, is_crystal: bool) -> bool:
	return set_number != SET_NONE and set_number < set_limit(is_crystal)


## GetTreeScore's .CoordScore, over the coordinates GetFacingTileCoord returns.
##
## Those are wPlayerMapX/wPlayerMapY, which carry the source's four-cell border
## offset: CheckCurrentMapCoordEvents subtracts 4 from each to compare against a
## map's own coord events (home/map.asm). [param cell] is a walk cell, so the
## offset is applied here and nowhere else.
##
## The arithmetic is `hl = y * (x + 1) + x`, then `/ 5`, then `% 10`, all
## through the source's 16-bit Divide.
static func coord_score(cell: Vector2i) -> int:
	var x: int = cell.x + MAP_BORDER
	var y: int = cell.y + MAP_BORDER
	var value: int = (y * (x + 1) + x) & 0xFFFF
	@warning_ignore("integer_division")
	return (value / 5) % 10


## GetTreeScore's .OTIDScore: the player's own trainer ID, mod ten.
static func otid_score(player_id: int) -> int:
	return (player_id & 0xFFFF) % 10


## GetTreeScore: the two scores compared. Equal is RARE; a difference under
## five once wrapped into 0..9 is GOOD; anything else is BAD. The source
## answers RARE on the difference itself before wrapping, so only a true equal
## reaches it.
static func score(cell: Vector2i, player_id: int) -> int:
	var difference: int = coord_score(cell) - otid_score(player_id)
	if difference == 0:
		return SCORE_RARE
	if difference < 0:
		difference += 10
	return SCORE_GOOD if difference < 5 else SCORE_BAD


## GetTreeMon: the score, then RandomRange(10) against its threshold, then
## SelectTreeMon over the table that score chose. Only RARE walks past the
## common table's terminator to the rare one.
##
## Returns an empty Dictionary for every no-encounter answer, which is
## TreeMonEncounter's own `wScriptVar = 0`.
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


## RockMonEncounter, which is the same tables and a much shorter question:
## GetTreeMonSet over RockMonMaps, GetTreeMons, then a flat 40 percent
## `RandomRange(10)` under 4 and `SelectTreeMon` on the common table. It calls
## SelectTreeMon directly rather than GetTreeMon, so there is no score, no
## trainer ID and no rare table, which is why TreeMonSet_Rock can ship without
## one. It also writes no wBattleType, so a smashed rock is an ordinary wild
## battle and CheckSleepingTreeMon never looks at it.
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


## RockMonEncounter's `cp 4` against its RandomRange(10), kept apart from the
## roll the way the tree thresholds are.
static func rock_encounter_allowed(roll: int) -> bool:
	return roll < ROCK_ENCOUNTER_THRESHOLD


## GetTreeMon's per-tier comparison against its RandomRange(10) result, kept
## apart from the roll so both sides of each threshold are assertable.
static func encounter_allowed(tier: int, roll: int) -> bool:
	return roll < int(ENCOUNTER_THRESHOLDS.get(tier, 0))


## SelectTreeMon with its RandomRange(100) result already drawn: subtract each
## row's percentage until the subtraction borrows. Running off the end of the
## table is the source's `$ff` row, which is NoTreeMon.
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


## CheckSleepingTreeMon: whether a tree encounter with this species starts
## asleep. Gold and Silver import no lists, so this is false there, which is
## what pokegold shipping neither the routine nor the data means.
static func starts_asleep(species: int, asleep_species: Array) -> bool:
	return asleep_species.has(species)
