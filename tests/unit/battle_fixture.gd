extends RefCounted

## A cache the battle tests are fought inside.
##
## Not a cartridge and not a fake of one: it is a real cache directory with a
## handful of real species and moves in it, written the way the importer writes
## one. The battle engine reads cartridge content through [GameData] and nothing
## else, so a cache with four Pokémon in it exercises the same path a cache with
## 251 does, and the suite still runs on a machine that has no ROM.
##
## The numbers here are the published ones, so a stat or a damage figure in a
## test can be checked against a calculator rather than against this file.

const PIKACHU: int = 25
const GEODUDE: int = 74
const CHARMANDER: int = 4
const BULBASAUR: int = 1
const MAGCARGO: int = 219

const TACKLE: int = 33
const EMBER: int = 52
const THUNDERBOLT: int = 85
const SLASH: int = 163
const STRUGGLE: int = 165
const GROWL: int = 45

const NORMAL: int = 0x00
const GROUND: int = 0x04
const ROCK: int = 0x05
const GHOST: int = 0x08
const STEEL: int = 0x09
const FIRE: int = 0x14
const WATER: int = 0x15
const GRASS: int = 0x16
const ELECTRIC: int = 0x17
const POISON: int = 0x03
const FLYING: int = 0x02

## Only the matchups the battle tests use, not the whole chart. The chart itself
## is the importer's business and is tested there; what matters here is that the
## engine asks for one and applies what it is given.
const MATCHUPS: Array = [
	[ELECTRIC, GROUND, 0], [ELECTRIC, WATER, 20], [ELECTRIC, FLYING, 20],
	[ELECTRIC, GRASS, 5], [ELECTRIC, ELECTRIC, 5],
	[FIRE, GRASS, 20], [FIRE, WATER, 5], [FIRE, FIRE, 5], [FIRE, ROCK, 5],
	[GRASS, ROCK, 20], [GRASS, GROUND, 20], [GRASS, POISON, 5], [GRASS, GRASS, 5],
	[NORMAL, ROCK, 5], [NORMAL, STEEL, 5],
]

## The two the cartridge keeps past the Foresight marker.
const FORESIGHT_MATCHUPS: Array = [[NORMAL, GHOST, 0]]


## Writes a cache at [param directory] and opens it.
static func build(directory: String) -> GameData:
	RomCache.clear(directory)
	RomCache.prepare(directory)

	RomCache.write_json(RomCache.species_path(directory), _species())
	RomCache.write_json(RomCache.moves_path(directory), _moves())
	RomCache.write_json(RomCache.items_path(directory), [])
	RomCache.write_json(RomCache.types_path(directory), _types())
	RomCache.write_json(RomCache.matchups_path(directory), _matchups())
	RomCache.write_json(RomCache.trainers_path(directory), [])
	RomCache.write_json(RomCache.manifest_path(directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testgame",
		"sha1": "0123456789abcdef",
		"complete": true,
	})
	return GameData.open_directory(directory)


## The species table, indexed by number like the real one, with the gaps filled
## by entries that exist only so a number indexes its own row.
static func _species() -> Array:
	var known: Dictionary = {
		BULBASAUR: ["BULBASAUR", [45, 49, 49, 45, 65, 65], [GRASS, POISON]],
		CHARMANDER: ["CHARMANDER", [39, 52, 43, 65, 60, 50], [FIRE, FIRE]],
		PIKACHU: ["PIKACHU", [35, 55, 30, 90, 50, 40], [ELECTRIC, ELECTRIC]],
		GEODUDE: ["GEODUDE", [40, 80, 100, 20, 30, 30], [ROCK, GROUND]],
		MAGCARGO: ["MAGCARGO", [50, 50, 120, 30, 80, 80], [FIRE, ROCK]],
	}

	var out: Array = []
	for number: int in range(1, MAGCARGO + 1):
		var entry: Array = known.get(number, ["FILLER", [10, 10, 10, 10, 10, 10], [NORMAL, NORMAL]])
		var stats: Array = entry[1]
		out.append({
			"number": number,
			"name": entry[0],
			"stats": {
				"hp": stats[0], "attack": stats[1], "defense": stats[2],
				"speed": stats[3], "sp_attack": stats[4], "sp_defense": stats[5],
			},
			"types": entry[2],
			"front_tiles": [7, 7],
			"palette": {"normal": [0x1234, 0x5678], "shiny": [0x0C63, 0x1084]},
		})
	return out


static func _moves() -> Array:
	var known: Dictionary = {
		TACKLE: ["TACKLE", 35, NORMAL, 255, 35],
		GROWL: ["GROWL", 0, NORMAL, 255, 40],
		EMBER: ["EMBER", 40, FIRE, 255, 25],
		THUNDERBOLT: ["THUNDERBOLT", 95, ELECTRIC, 255, 15],
		SLASH: ["SLASH", 70, NORMAL, 255, 20],
		STRUGGLE: ["STRUGGLE", 50, NORMAL, 255, 10],
	}

	var out: Array = []
	for number: int in range(1, STRUGGLE + 1):
		var entry: Array = known.get(number, ["FILLER", 40, NORMAL, 255, 20])
		out.append({
			"number": number,
			"name": entry[0],
			"effect": 0,
			"power": entry[1],
			"type": entry[2],
			"accuracy": entry[3],
			"pp": entry[4],
			"effect_chance": 0,
		})
	return out


static func _types() -> Array:
	var out: Array = []
	for number: int in RomLayout.TYPE_COUNT:
		out.append({"number": number, "name": "TYPE%d" % number})
	return out


static func _matchups() -> Array:
	var out: Array = []
	for row: Array in MATCHUPS:
		out.append(_matchup(row, false))
	for row: Array in FORESIGHT_MATCHUPS:
		out.append(_matchup(row, true))
	return out


static func _matchup(row: Array, foresight: bool) -> Dictionary:
	return {
		"attacker": row[0],
		"defender": row[1],
		"multiplier": row[2],
		"negated_by_foresight": foresight,
	}
