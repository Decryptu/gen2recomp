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

## The status moves, in the two shapes they come in. Thunder Wave and Sleep
## Powder are the status and nothing else; Ember Burns and Flame Wheel are
## attacks with something behind a roll, one of which never rolls and one of
## which always does, so a test can have either without a seed.
const THUNDER_WAVE: int = 86
const SLEEP_POWDER: int = 79
const POISON_POWDER: int = 77
const EMBER_BURNS: int = 92
const NEVER_BURNS: int = 93
const FLAME_WHEEL: int = 172

## The stat-changing moves, in the shapes the effect bytes come in: a pure raise,
## a pure drop, a raise on hit, and a drop on hit that always rolls or never
## does, the same trick [constant EMBER_BURNS] and [constant NEVER_BURNS] already
## use.
const SWORDS_DANCE: int = 14
const SCREECH: int = 103
const METAL_CLAW: int = 232
const ANCIENTPOWER: int = 246
const PSYCHIC_LOWERS: int = 210
const PSYCHIC_NEVER: int = 211

## The substatus moves. Flinch and confusion each in the two shapes they come
## in, the same [code]_ALWAYS[/code]/nothing pairing [constant EMBER_BURNS] and
## [constant NEVER_BURNS] use so a test can have one without a seed; Hyper Beam
## for recharge, since nothing else in this table needs it.
const ROLLING_KICK_ALWAYS: int = 247
const ROLLING_KICK_NEVER: int = 248
const CONFUSION_ALWAYS: int = 249
const CONFUSION_NEVER: int = 250
const SUPERSONIC: int = 251
const HYPER_BEAM: int = 252

## The three move families this fixture keeps at their real Generation 2 move
## numbers, so the command layer can exercise the cartridge's number-based
## exceptions as well as the effect-byte table.
const COUNTER: int = 68
const DIG: int = 91
const SELFDESTRUCT: int = 120
const EXPLOSION: int = 153
const FLY: int = 19
const MIRROR_COAT: int = 243
const GUST: int = 16
const THUNDER: int = 9
const TWISTER: int = 239
const EARTHQUAKE: int = 89
const FISSURE: int = 90
const MAGNITUDE: int = 222

## Rollout, its Defense Curl partner and the three rampage moves keep their real
## move numbers so the state can be forced through the same number-based path as
## the cartridge.
const THRASH: int = 37
const DEFENSE_CURL: int = 111
const PETAL_DANCE: int = 80
const OUTRAGE: int = 200
const ROLLOUT: int = 205

## Solarbeam for the plain two-turn shape, Skull Bash for the one that raises a
## stat behind the hit.
const SOLARBEAM: int = 253
const SKULL_BASH: int = 254
const TOXIC: int = 255
const HAZE: int = 256
const BELLY_DRUM: int = 257
const PSYCH_UP: int = 258

## Multi-hit, in the two counting shapes: a random 2-5 and a fixed 2, plus the
## fixed 2 with a poison chance behind both hits, the way Twineedle does it.
const MULTI_HIT_MOVE: int = 259
const DOUBLE_HIT_MOVE: int = 260
const TWINEEDLE_MOVE: int = 261

## Drain, in the two shapes: an ordinary attack that heals, and one gated on
## the target being asleep.
const DRAIN_MOVE: int = 262
const DREAM_EATER_MOVE: int = 263

## The four fixed-damage effects sharing one command.
const LEVEL_DAMAGE_MOVE: int = 264
const STATIC_DAMAGE_MOVE: int = 265
const SUPER_FANG_MOVE: int = 266
const PSYWAVE_MOVE: int = 267

const OHKO_MOVE: int = 268

## Disable, Attract, Encore, Mist and Focus Energy, with the real accuracy
## bytes (Disable's own shade under 55%; the other four always hit) and the
## real effect bytes, both read off the real cartridges with
## [code]tools/dump_tables.gd -- gold moves[/code].
const DISABLE_MOVE: int = 269
const ENCORE_MOVE: int = 270
const ATTRACT_MOVE: int = 271
const MIST_MOVE: int = 272
const FOCUS_ENERGY_MOVE: int = 273

## The highest move number this table fills. Grown as new moves are added.
const MAX_MOVE: int = FOCUS_ENERGY_MOVE
const BERRY_ITEM: int = 0xAD

## Gender ratios, the published bytes: `x percent = floor(x * 255 / 100)`, so a
## species' own ratio here can be checked against pret's own base stats rather
## than against this file. Bulbasaur and Charmander are really 12.5% female;
## Pikachu, Geodude and Magcargo are really an even 50/50.
const GENDER_F12_5: int = 31
const GENDER_F50: int = 127
const GENDER_UNKNOWN: int = 255

const NORMAL: int = 0x00
const FIGHTING: int = 0x01
const GROUND: int = 0x04
const ROCK: int = 0x05
const GHOST: int = 0x08
const STEEL: int = 0x09
const FIRE: int = 0x14
const WATER: int = 0x15
const GRASS: int = 0x16
const ELECTRIC: int = 0x17
const PSYCHIC_TYPE: int = 0x18
const POISON: int = 0x03
const FLYING: int = 0x02
const DRAGON: int = 0x1A
const DARK: int = 0x1B

## Only the matchups the battle tests use, not the whole chart. The chart itself
## is the importer's business and is tested there; what matters here is that the
## engine asks for one and applies what it is given.
const MATCHUPS: Array = [
	[ELECTRIC, GROUND, 0], [ELECTRIC, WATER, 20], [ELECTRIC, FLYING, 20],
	[ELECTRIC, GRASS, 5], [ELECTRIC, ELECTRIC, 5],
	[FIRE, GRASS, 20], [FIRE, WATER, 5], [FIRE, FIRE, 5], [FIRE, ROCK, 5],
	[GRASS, ROCK, 20], [GRASS, GROUND, 20], [GRASS, POISON, 5], [GRASS, GRASS, 5],
	[NORMAL, ROCK, 5], [NORMAL, STEEL, 5],
	[FIGHTING, GHOST, 0], [PSYCHIC_TYPE, DARK, 0],
]

## The two the cartridge keeps past the Foresight marker.
const FORESIGHT_MATCHUPS: Array = [[NORMAL, GHOST, 0]]


## Writes a cache at [param directory] and opens it.
static func build(directory: String) -> GameData:
	RomCache.clear(directory)
	RomCache.prepare(directory)

	RomCache.write_json(RomCache.species_path(directory), _species())
	RomCache.write_json(RomCache.moves_path(directory), _moves())
	RomCache.write_json(RomCache.items_path(directory), _items())
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
	# Growth rate and base exp, appended after the type pair, are the published
	# ones too: Pikachu and Magcargo are medium fast, Bulbasaur, Charmander and
	# Geodude medium slow, which is why [constant Gen2Experience.GROWTH_MEDIUM_FAST]
	# and [constant Gen2Experience.GROWTH_MEDIUM_SLOW] are the two
	# [test_experience.gd] and [test_battle.gd] ever need a fixture for.
	# The two learnsets exist only for [test_battle.gd]'s own experience tests:
	# Charmander's single entry is the plain "an empty slot needs no question"
	# case, and Geodude's two are a level-up jump that crosses both a free slot
	# and, once that slot is gone, [Gen2Battle.must_learn_move]'s own offer.
	var known: Dictionary = {
		BULBASAUR: [
			"BULBASAUR", [45, 49, 49, 45, 65, 65], [GRASS, POISON],
			Gen2Experience.GROWTH_MEDIUM_SLOW, 64, [], GENDER_F12_5,
		],
		CHARMANDER: [
			"CHARMANDER", [39, 52, 43, 65, 60, 50], [FIRE, FIRE],
			Gen2Experience.GROWTH_MEDIUM_SLOW, 65, [{"level": 6, "move": EMBER}],
			GENDER_F12_5,
		],
		PIKACHU: [
			"PIKACHU", [35, 55, 30, 90, 50, 40], [ELECTRIC, ELECTRIC],
			Gen2Experience.GROWTH_MEDIUM_FAST, 82, [], GENDER_F50,
		],
		GEODUDE: [
			"GEODUDE", [40, 80, 100, 20, 30, 30], [ROCK, GROUND],
			Gen2Experience.GROWTH_MEDIUM_SLOW, 86,
			[{"level": 6, "move": GROWL}, {"level": 11, "move": SLASH}], GENDER_F50,
		],
		MAGCARGO: [
			"MAGCARGO", [50, 50, 120, 30, 80, 80], [FIRE, ROCK],
			Gen2Experience.GROWTH_MEDIUM_FAST, 154, [], GENDER_F50,
		],
	}

	var out: Array = []
	for number: int in range(1, MAGCARGO + 1):
		var entry: Array = known.get(number, [
			"FILLER", [10, 10, 10, 10, 10, 10], [NORMAL, NORMAL],
			Gen2Experience.GROWTH_MEDIUM_FAST, 64, [], GENDER_UNKNOWN,
		])
		var stats: Array = entry[1]
		out.append({
			"number": number,
			"name": entry[0],
			"stats": {
				"hp": stats[0], "attack": stats[1], "defense": stats[2],
				"speed": stats[3], "sp_attack": stats[4], "sp_defense": stats[5],
			},
			"learnset": entry[5],
			"types": entry[2],
			"growth_rate": entry[3],
			"base_exp": entry[4],
			"gender_ratio": entry[6],
			"front_tiles": [7, 7],
			"palette": {"normal": [0x1234, 0x5678], "shiny": [0x0C63, 0x1084]},
		})
	return out


static func _moves() -> Array:
	# Name, power, type, accuracy, PP, effect. The effect byte is the cartridge's
	# own, because the turn loop reads priority and recoil out of it.
	# Name, power, type, accuracy, PP, effect, and the secondary effect's chance
	# out of 256. Ember and Thunderbolt keep a chance of zero, which is never, so
	# that the tests written before there were status conditions still see the
	# plain attacks they were written against.
	var known: Dictionary = {
		TACKLE: ["TACKLE", 35, NORMAL, 255, 35, 0, 0],
		GROWL: ["GROWL", 0, NORMAL, 255, 40, Gen2MoveEffect.STAT_DOWN_BASE, 0],
		EMBER: ["EMBER", 40, FIRE, 255, 25, Gen2MoveEffect.BURN_HIT, 0],
		THUNDERBOLT: ["THUNDERBOLT", 95, ELECTRIC, 255, 15, Gen2MoveEffect.PARALYZE_HIT, 0],
		SLASH: ["SLASH", 70, NORMAL, 255, 20, 0, 0],
		STRUGGLE: ["STRUGGLE", 50, NORMAL, 255, 10, Gen2MoveEffect.RECOIL_HIT, 0],
		THUNDER_WAVE: ["THUNDERWAVE", 0, ELECTRIC, 255, 20, Gen2MoveEffect.PARALYZE, 0],
		SLEEP_POWDER: ["SLEEP POWDER", 0, GRASS, 255, 15, Gen2MoveEffect.SLEEP, 0],
		POISON_POWDER: ["POISONPOWDER", 0, POISON, 255, 35, Gen2MoveEffect.POISON, 0],
		# A chance of 256 is one the roll cannot fail, which is how a test gets a
		# burn without a seed. Its opposite is a chance of zero.
		EMBER_BURNS: ["EMBER", 40, FIRE, 255, 25, Gen2MoveEffect.BURN_HIT, 256],
		NEVER_BURNS: ["EMBER", 40, FIRE, 255, 25, Gen2MoveEffect.BURN_HIT, 0],
		FLAME_WHEEL: ["FLAME WHEEL", 60, FIRE, 255, 25, Gen2MoveEffect.BURN_HIT, 0],
		# Attack up by two, on the user, with no roll to miss.
		SWORDS_DANCE: ["SWORDS DANCE", 0, NORMAL, 255, 30, Gen2MoveEffect.STAT_UP_2_BASE, 0],
		# Defense down by two, on the foe, which can still miss.
		SCREECH: ["SCREECH", 0, NORMAL, 216, 40, Gen2MoveEffect.STAT_DOWN_2_BASE + 1, 0],
		# Attack up on the user, behind a roll, the way Metal Claw does it.
		METAL_CLAW: ["METAL CLAW", 50, STEEL, 255, 35, Gen2MoveEffect.ATTACK_UP_HIT, 256],
		# All five real stats up on the user, behind a roll, the way Ancientpower
		# does it.
		ANCIENTPOWER: ["ANCIENTPOWER", 60, ROCK, 255, 5, Gen2MoveEffect.ALL_STATS_UP_HIT, 256],
		# Sp.Defense down on the foe, behind a roll, the way Psychic does it. One
		# chance never fails and the other never does, the same trick
		# [constant EMBER_BURNS] and [constant NEVER_BURNS] use for a status.
		PSYCHIC_LOWERS: ["PSYCHIC", 90, PSYCHIC_TYPE, 255, 10, Gen2MoveEffect.STAT_DOWN_HIT_BASE + 4, 256],
		PSYCHIC_NEVER: ["PSYCHIC", 90, PSYCHIC_TYPE, 255, 10, Gen2MoveEffect.STAT_DOWN_HIT_BASE + 4, 0],
		# A flinch behind a roll, the way Rolling Kick does it.
		ROLLING_KICK_ALWAYS: ["ROLLING KICK", 60, NORMAL, 255, 15, Gen2MoveEffect.FLINCH_HIT, 256],
		ROLLING_KICK_NEVER: ["ROLLING KICK", 60, NORMAL, 255, 15, Gen2MoveEffect.FLINCH_HIT, 0],
		# A confusion behind a roll, the way Confusion itself does it.
		CONFUSION_ALWAYS: ["CONFUSION", 50, PSYCHIC_TYPE, 255, 25, Gen2MoveEffect.CONFUSE_HIT, 256],
		CONFUSION_NEVER: ["CONFUSION", 50, PSYCHIC_TYPE, 255, 25, Gen2MoveEffect.CONFUSE_HIT, 0],
		# Confusion as the whole of the move, the way Supersonic does it.
		SUPERSONIC: ["SUPERSONIC", 0, NORMAL, 255, 20, Gen2MoveEffect.CONFUSE, 0],
		HYPER_BEAM: ["HYPER BEAM", 150, NORMAL, 255, 5, Gen2MoveEffect.RECHARGE_HIT, 0],
		FLY: ["FLY", 70, FLYING, 242, 15, Gen2MoveEffect.FLY_OR_DIG, 0],
		DIG: ["DIG", 100, GROUND, 255, 10, Gen2MoveEffect.FLY_OR_DIG, 0],
		GUST: ["GUST", 40, FLYING, 255, 35, 0, 0],
		THUNDER: ["THUNDER", 120, ELECTRIC, 179, 10, Gen2MoveEffect.PARALYZE_HIT, 0],
		TWISTER: ["TWISTER", 40, DRAGON, 255, 20, Gen2MoveEffect.FLINCH_HIT, 0],
		EARTHQUAKE: ["EARTHQUAKE", 100, GROUND, 255, 10, 0, 0],
		FISSURE: ["FISSURE", 0, GROUND, 76, 5, Gen2MoveEffect.OHKO, 0],
		MAGNITUDE: ["MAGNITUDE", 100, GROUND, 255, 30, 0, 0],
		THRASH: ["THRASH", 90, NORMAL, 255, 20, Gen2MoveEffect.RAMPAGE, 0],
		PETAL_DANCE: ["PETAL DANCE", 70, GRASS, 255, 20, Gen2MoveEffect.RAMPAGE, 0],
		OUTRAGE: ["OUTRAGE", 90, DRAGON, 255, 15, Gen2MoveEffect.RAMPAGE, 0],
		ROLLOUT: ["ROLLOUT", 30, ROCK, 229, 20, Gen2MoveEffect.ROLLOUT, 0],
		DEFENSE_CURL: ["DEFENSE CURL", 0, NORMAL, 255, 40, Gen2MoveEffect.DEFENSE_CURL, 0],
		COUNTER: ["COUNTER", 0, FIGHTING, 255, 20, Gen2MoveEffect.COUNTER, 0],
		SELFDESTRUCT: ["SELF-DESTRUCT", 200, NORMAL, 255, 5, Gen2MoveEffect.SELFDESTRUCT, 0],
		EXPLOSION: ["EXPLOSION", 250, NORMAL, 255, 5, Gen2MoveEffect.SELFDESTRUCT, 0],
		MIRROR_COAT: ["MIRROR COAT", 0, PSYCHIC_TYPE, 255, 20, Gen2MoveEffect.MIRROR_COAT, 0],
		SOLARBEAM: ["SOLARBEAM", 120, NORMAL, 255, 10, Gen2MoveEffect.SOLARBEAM, 0],
		SKULL_BASH: ["SKULL BASH", 100, NORMAL, 255, 15, Gen2MoveEffect.SKULL_BASH, 0],
		TOXIC: ["TOXIC", 0, POISON, 255, 10, Gen2MoveEffect.TOXIC, 0],
		HAZE: ["HAZE", 0, NORMAL, 255, 30, Gen2MoveEffect.HAZE, 0],
		BELLY_DRUM: ["BELLY DRUM", 0, NORMAL, 255, 10, Gen2MoveEffect.BELLY_DRUM, 0],
		PSYCH_UP: ["PSYCH UP", 0, NORMAL, 255, 10, Gen2MoveEffect.PSYCH_UP, 0],
		MULTI_HIT_MOVE: ["COMET PUNCH", 18, NORMAL, 255, 15, Gen2MoveEffect.MULTI_HIT, 0],
		DOUBLE_HIT_MOVE: ["DOUBLE KICK", 30, NORMAL, 255, 30, Gen2MoveEffect.DOUBLE_HIT, 0],
		# A chance of 256 never fails, which is how a test gets Twineedle's poison
		# without a seed, the same trick EMBER_BURNS uses for a status.
		TWINEEDLE_MOVE: ["TWINEEDLE", 25, POISON, 255, 20, Gen2MoveEffect.TWINEEDLE, 256],
		DRAIN_MOVE: ["ABSORB", 20, GRASS, 255, 20, Gen2MoveEffect.LEECH_HIT, 0],
		DREAM_EATER_MOVE: ["DREAM EATER", 100, PSYCHIC_TYPE, 255, 15, Gen2MoveEffect.DREAM_EATER, 0],
		LEVEL_DAMAGE_MOVE: ["SEISMIC TOSS", 1, NORMAL, 255, 20, Gen2MoveEffect.LEVEL_DAMAGE, 0],
		STATIC_DAMAGE_MOVE: ["SONICBOOM", 20, NORMAL, 255, 20, Gen2MoveEffect.STATIC_DAMAGE, 0],
		SUPER_FANG_MOVE: ["SUPER FANG", 1, NORMAL, 255, 10, Gen2MoveEffect.SUPER_FANG, 0],
		PSYWAVE_MOVE: ["PSYWAVE", 1, PSYCHIC_TYPE, 255, 15, Gen2MoveEffect.PSYWAVE, 0],
		OHKO_MOVE: ["GUILLOTINE", 0, NORMAL, 76, 5, Gen2MoveEffect.OHKO, 0],
		DISABLE_MOVE: ["DISABLE", 0, NORMAL, 140, 20, Gen2MoveEffect.DISABLE, 0],
		ENCORE_MOVE: ["ENCORE", 0, NORMAL, 255, 5, Gen2MoveEffect.ENCORE, 0],
		ATTRACT_MOVE: ["ATTRACT", 0, NORMAL, 255, 15, Gen2MoveEffect.ATTRACT, 0],
		MIST_MOVE: ["MIST", 0, NORMAL, 255, 30, Gen2MoveEffect.MIST, 0],
		FOCUS_ENERGY_MOVE: ["FOCUS ENERGY", 0, NORMAL, 255, 30, Gen2MoveEffect.FOCUS_ENERGY, 0],
	}

	var out: Array = []
	for number: int in range(1, MAX_MOVE + 1):
		var entry: Array = known.get(number, ["FILLER", 40, NORMAL, 255, 20, 0, 0])
		out.append({
			"number": number,
			"name": entry[0],
			"effect": entry[5],
			"power": entry[1],
			"type": entry[2],
			"accuracy": entry[3],
			"pp": entry[4],
			"effect_chance": entry[6],
		})
	return out


static func _types() -> Array:
	var out: Array = []
	for number: int in RomLayout.TYPE_COUNT:
		out.append({"number": number, "name": "TYPE%d" % number})
	return out


static func _items() -> Array:
	var out: Array = []
	for number: int in range(1, BERRY_ITEM + 1):
		out.append({
			"number": number,
			"name": "BERRY" if number == BERRY_ITEM else "ITEM%d" % number,
		})
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
