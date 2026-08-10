extends RefCounted

## A cache the battle tests are fought inside.
##
## Not a fake cartridge: a real cache directory with a handful of real species
## and moves, written the way the importer writes one. The battle engine reads
## cartridge content only through [GameData], so four Pokémon exercise the same
## path 251 do and the suite runs on a machine with no ROM.
##
## The numbers are the published ones, so a stat or damage figure in a test can
## be checked against a calculator rather than against this file.

const PIKACHU: int = 25
const GEODUDE: int = 74
const CHARMANDER: int = 4
const BULBASAUR: int = 1
const MAGCARGO: int = 219

## The three species a held item singles out by number: Cubone and Marowak for
## Thick Club, Ditto for Metal Powder. Pikachu is already above and is Light
## Ball's. Real numbers and real base stats, since the point of each of them is
## that the number is what the cartridge checks.
const CUBONE: int = 104
const MAROWAK: int = 105
const DITTO: int = 132

## The two species whose *type* is the whole point of them. `BattleCommand_Curse`
## picks its branch off the user being a Ghost-type and `SpikesDamage` spares a
## Flying-type, so neither rule can be reached with the eight above. Real numbers
## and real base stats, like every other row here. Hoothoot's 163 is a species
## number and shares nothing but its value with [constant SLASH]'s move number and
## [constant LIGHT_BALL]'s item number.
const GASTLY: int = 92
const HOOTHOOT: int = 163

## The highest species number this table fills.
const MAX_SPECIES: int = MAGCARGO

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

## The other three secondary statuses, each on a real row with a chance the roll
## cannot fail, so all four `*Target` commands can be reached without a seed.
## Burn already has [constant EMBER_BURNS]; sleep has no secondary shape, since
## `EFFECT_SLEEP` is the whole of every move that carries it. Invented numbers
## and `_ALWAYS` names, the way [constant THUNDER_ALWAYS_PARALYZES] is one: the
## chance is the only byte that is not the cartridge's.
const SLUDGE_BOMB_ALWAYS_POISONS: int = 275
const ICE_BEAM_ALWAYS_FREEZES: int = 276
const BODY_SLAM_ALWAYS_PARALYZES: int = 277

## The stat-changing moves, in the shapes the effect bytes come in: a pure raise,
## a pure drop, a raise on hit, and a drop on hit that always rolls or never
## does, the same trick [constant EMBER_BURNS] and [constant NEVER_BURNS] already
## use.
const SWORDS_DANCE: int = 14
const SCREECH: int = 103
const METAL_CLAW: int = 232
const ANCIENTPOWER: int = 246
## Parked above the cartridge's own numbering rather than on 210 and 211, which
## are Fury Cutter's and Steel Wing's and are now filled with those rows.
const PSYCHIC_LOWERS: int = 278
const PSYCHIC_NEVER: int = 279

## The substatus moves. Flinch and confusion each in the two shapes they come
## in, the same [code]_ALWAYS[/code]/nothing pairing [constant EMBER_BURNS] and
## [constant NEVER_BURNS] use so a test can have one without a seed; Hyper Beam
## for recharge, since nothing else in this table needs it.
const ROLLING_KICK_ALWAYS: int = 247
const ROLLING_KICK_NEVER: int = 248
const CONFUSION_ALWAYS: int = 249
const CONFUSION_NEVER: int = 250
## Parked past every other row rather than on 251, which is Beat Up's own number
## and is now filled with that row. Supersonic really is move 48, and this entry
## is not it: its accuracy is forced to 255 so a confusion test needs no seed.
const SUPERSONIC: int = 280
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
const THUNDER: int = 87
const TWISTER: int = 239
const EARTHQUAKE: int = 89
const FISSURE: int = 90
const MAGNITUDE: int = 222

## The two trapping effects, at their real move numbers because the landing text
## is chosen by number rather than by effect. Wrap and Bind are one effect apart
## from each other only in that text, which is what makes the pair enough to see
## that an already-bound target keeps the move that bound it.
const WRAP: int = 35
const BIND: int = 20
const MEAN_LOOK: int = 212

## The three weather moves, at their real numbers with the real bytes. Solarbeam
## needs no entry of its own: [constant SOLARBEAM] above already carries the
## effect, and nothing about the sun reads a move number.
const RAIN_DANCE: int = 240
const SUNNY_DAY: int = 241
const SANDSTORM: int = 201
const THUNDER_ALWAYS_PARALYZES: int = 274

## The three screens, real numbers off `data/moves/moves.asm`. All three are
## powerless status moves whose accuracy is never rolled, the same shape the
## weather rows above have.
const LIGHT_SCREEN: int = 113
const REFLECT: int = 115
const SAFEGUARD: int = 219

## Perish Song, the same shape again: a real move number, no power, and an
## accuracy its own sequence never rolls.
const PERISH_SONG: int = 195

## Substitute and the three residuals, at their real move numbers with their real
## rows. Curse has to be real twice over: `BattleCommand_Curse` reads the user's
## own type, and the move is the only carrier of `CURSE_TYPE`. Leech Seed is the
## one of the five that rolls accuracy, so its 90% is a real byte rather than the
## 255 the others carry.
const SUBSTITUTE: int = 164
const LEECH_SEED: int = 73
const NIGHTMARE: int = 171
const CURSE: int = 174
const SPIKES: int = 191

## Rapid Spin, the only move that undoes any of the three.
const RAPID_SPIN: int = 229

## Protect, Detect, Endure and Destiny Bond, at their real move numbers. Protect
## and Detect have to be two numbers over one effect byte, since one shared
## [member Gen2BattleMon.protect_count] is the whole point of the pair; the other
## two are real for company, and all four fit under [constant MAX_MOVE].
const PROTECT: int = 182
const DESTINY_BOND: int = 194
const DETECT: int = 197
const ENDURE: int = 203

## Whirlwind and Roar, which have to be real numbers twice over: they share one
## effect byte, and `.succeed` picks between "fled in fear" and "was blown away"
## by comparing the move against ROAR.
const WHIRLWIND: int = 18
const ROAR: int = 46

## Baton Pass, at its real number for company: nothing about it reads the number.
const BATON_PASS: int = 226

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

## The heal family at its real move numbers. Rest has to be real, because
## `BattleCommand_Heal` tells it from the other three by number; the rest are
## real for company, and all seven fit under [constant MAX_MOVE] already.
const RECOVER: int = 105
const SOFTBOILED: int = 135
const REST: int = 156
const MILK_DRINK: int = 208
const MORNING_SUN: int = 234
const SYNTHESIS: int = 235
const MOONLIGHT: int = 236

## The effects whose whole point is a number the move table does not hold, all at
## their real move numbers with their real rows: the power comes from the user's
## happiness, its remaining health, its DVs, or a roll, so a synthetic row would
## test nothing. Present is here too, since one of its four rows is not a hit at
## all.
const SWIFT: int = 129
const JUMP_KICK: int = 26
const FLAIL: int = 175
const REVERSAL: int = 179
const RETURN: int = 216
const PRESENT: int = 217
const FRUSTRATION: int = 218
const HIDDEN_POWER: int = 237
const FURY_CUTTER: int = 210
const TRIPLE_KICK: int = 167
const FALSE_SWIPE: int = 206
const HEAL_BELL: int = 215
const SNORE: int = 173
const TRI_ATTACK: int = 161
const STEEL_WING: int = 211
const SACRED_FIRE: int = 221
const STOMP: int = 23
const MINIMIZE: int = 107
const SPLASH: int = 150
const SWAGGER: int = 207

## The last row of the effects table, all nine at their real move numbers with
## their real bytes. Lock On and Mind Reader have to be two numbers over one
## effect byte the way Protect and Detect do, and Beat Up's power of 10 is the
## whole of what its own command hands the formula.
const TELEPORT: int = 100
const THIEF: int = 168
const MIND_READER: int = 170
const SPITE: int = 180
const FORESIGHT: int = 193
const LOCK_ON: int = 199
const PAIN_SPLIT: int = 220
const PURSUIT: int = 228
const BEAT_UP: int = 251

## The highest move number this table fills. Grown as new moves are added.
const MAX_MOVE: int = SUPERSONIC
const BERRY_ITEM: int = 0xAD

## The highest item number this table fills.
const MAX_ITEM: int = 174
## The Smoke Ball and its held effect, both the cartridge's own numbers
## (constants/item_constants.asm, constants/item_data_constants.asm). It is the
## one item running reads.
const SMOKE_BALL: int = 0x6A
const HELD_ESCAPE: int = 72

## The held items the battle reads, at their real numbers with the real held
## effect and parameter bytes off the cartridge. Thick Club and Light Ball carry
## no held effect at all: `SpeciesItemBoost` checks them by number.
const MAGNET: int = 108
const THICK_CLUB: int = 118
const LIGHT_BALL: int = 163
const METAL_POWDER: int = 35
const SCOPE_LENS: int = 140
const QUICK_CLAW: int = 73
const KINGS_ROCK: int = 82
const BRIGHTPOWDER: int = 3
const FOCUS_BAND: int = 119
const LEFTOVERS: int = 146
const GOLD_BERRY: int = 174
const MYSTERYBERRY: int = 150
const PSNCUREBERRY: int = 74
const MIRACLEBERRY: int = 109
const BITTER_BERRY: int = 83

## `MailItems`' first entry, at its real number. The one item Thief has to leave
## where it is, and it carries no held effect: `ItemIsMail` checks the number.
const FLOWER_MAIL: int = 158

## Exp. Share, at its real number. It carries no held effect at all: the routine
## that finds it checks the item number, so the default row is the whole of what
## the fixture needs.
const EXP_SHARE: int = 39

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
const BUG: int = 0x07
const GHOST: int = 0x08
const STEEL: int = 0x09
const FIRE: int = 0x14
const WATER: int = 0x15
const GRASS: int = 0x16
const ELECTRIC: int = 0x17
const PSYCHIC_TYPE: int = 0x18
const ICE: int = 0x19
const POISON: int = 0x03
const FLYING: int = 0x02
const DRAGON: int = 0x1A
const DARK: int = 0x1B
## `constants/type_constants.asm`'s own `CURSE_TYPE`, which sits in the unused
## run at 19 and belongs to exactly one move.
const CURSE_TYPE: int = 0x13

## Only the matchups the battle tests use, not the whole chart. The chart itself
## is the importer's business and is tested there; what matters here is that the
## engine asks for one and applies what it is given.
const MATCHUPS: Array = [
	[ELECTRIC, GROUND, 0], [ELECTRIC, WATER, 20], [ELECTRIC, FLYING, 20],
	[ELECTRIC, GRASS, 5], [ELECTRIC, ELECTRIC, 5],
	[FIRE, GRASS, 20], [FIRE, WATER, 5], [FIRE, FIRE, 5], [FIRE, ROCK, 5],
	[GRASS, ROCK, 20], [GRASS, GROUND, 20], [GRASS, POISON, 5], [GRASS, GRASS, 5],
	[NORMAL, ROCK, 5], [NORMAL, STEEL, 5],
	[PSYCHIC_TYPE, DARK, 0],
]

## The two the cartridge keeps past the Foresight marker, and the only place
## either appears: `data/types/type_matchups.asm` lists Normal and Fighting
## against Ghost after `db -2` and nowhere before it.
const FORESIGHT_MATCHUPS: Array = [[NORMAL, GHOST, 0], [FIGHTING, GHOST, 0]]


## Writes a cache at [param directory] and opens it.
static func build(directory: String) -> GameData:
	RomCache.clear(directory)
	RomCache.prepare(directory)

	RomCache.write_json(RomCache.species_path(directory), _species())
	RomCache.write_json(RomCache.dex_orders_path(directory), _dex_orders())
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
	# Growth rate and base exp after the type pair are published values too:
	# Pikachu and Magcargo medium fast, Bulbasaur, Charmander and Geodude medium
	# slow, which is why those are the only two curves the tests fixture.
	# The two learnsets serve test_battle.gd's experience tests: Charmander's
	# single entry is the "empty slot needs no question" case, Geodude's two are
	# a level-up jump crossing a free slot and then must_learn_move's offer.
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
		CUBONE: [
			"CUBONE", [50, 50, 95, 35, 40, 50], [GROUND, GROUND],
			Gen2Experience.GROWTH_MEDIUM_FAST, 87, [], GENDER_F50,
		],
		MAROWAK: [
			"MAROWAK", [60, 80, 110, 45, 50, 80], [GROUND, GROUND],
			Gen2Experience.GROWTH_MEDIUM_FAST, 124, [], GENDER_F50,
		],
		DITTO: [
			"DITTO", [48, 48, 48, 48, 48, 48], [NORMAL, NORMAL],
			Gen2Experience.GROWTH_MEDIUM_FAST, 61, [], GENDER_UNKNOWN,
		],
		GASTLY: [
			"GASTLY", [30, 35, 30, 80, 100, 35], [GHOST, POISON],
			Gen2Experience.GROWTH_MEDIUM_SLOW, 95, [], GENDER_F50,
		],
		HOOTHOOT: [
			"HOOTHOOT", [60, 30, 30, 50, 36, 56], [NORMAL, FLYING],
			Gen2Experience.GROWTH_MEDIUM_FAST, 58, [], GENDER_F50,
		],
	}

	var out: Array = []
	for number: int in range(1, MAX_SPECIES + 1):
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
			"dex": {
				"category": "%s MON" % entry[0],
				"height": 204,
				"weight": 150,
				"pages": ["page one", "page two"],
			},
			"palette": {"normal": [0x1234, 0x5678], "shiny": [0x0C63, 0x1084]},
		})
	return out


## Both dex order tables, which every real cache carries and the Pokedex refuses
## to open without. The species range stands in for NewPokedexOrder, since
## nothing here checks a listing against the cartridge's own order.
static func _dex_orders() -> Dictionary:
	var forward: Array = []
	var backward: Array = []
	for number: int in range(1, RomLayout.SPECIES_COUNT + 1):
		forward.append(number)
		backward.append(RomLayout.SPECIES_COUNT + 1 - number)
	return {"new": forward, "alpha": backward}


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
		FLAME_WHEEL: ["FLAME WHEEL", 60, FIRE, 255, 25, Gen2MoveEffect.FLAME_WHEEL, 25],
		# The other three secondary statuses, power, type and PP as the cartridge
		# has them and only the chance forced past failing.
		SLUDGE_BOMB_ALWAYS_POISONS: [
			"SLUDGE BOMB", 90, POISON, 255, 10, Gen2MoveEffect.POISON_HIT, 256,
		],
		ICE_BEAM_ALWAYS_FREEZES: [
			"ICE BEAM", 95, ICE, 255, 10, Gen2MoveEffect.FREEZE_HIT, 256,
		],
		BODY_SLAM_ALWAYS_PARALYZES: [
			"BODY SLAM", 85, NORMAL, 255, 15, Gen2MoveEffect.PARALYZE_HIT, 256,
		],
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
		GUST: ["GUST", 40, FLYING, 255, 35, Gen2MoveEffect.GUST, 0],
		THUNDER: ["THUNDER", 120, ELECTRIC, 178, 10, Gen2MoveEffect.THUNDER, 76],
		TWISTER: ["TWISTER", 40, DRAGON, 255, 20, Gen2MoveEffect.TWISTER, 51],
		EARTHQUAKE: ["EARTHQUAKE", 100, GROUND, 255, 10, Gen2MoveEffect.EARTHQUAKE, 0],
		FISSURE: ["FISSURE", 0, GROUND, 76, 5, Gen2MoveEffect.OHKO, 0],
		MAGNITUDE: ["MAGNITUDE", 1, GROUND, 255, 30, Gen2MoveEffect.MAGNITUDE, 0],
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
		RAIN_DANCE: ["RAIN DANCE", 0, WATER, 229, 5, Gen2MoveEffect.RAIN_DANCE, 0],
		SUNNY_DAY: ["SUNNY DAY", 0, FIRE, 229, 5, Gen2MoveEffect.SUNNY_DAY, 0],
		SANDSTORM: ["SANDSTORM", 0, ROCK, 255, 10, Gen2MoveEffect.SANDSTORM, 0],
		LIGHT_SCREEN: ["LIGHT SCREEN", 0, PSYCHIC_TYPE, 255, 30, Gen2MoveEffect.LIGHT_SCREEN, 0],
		REFLECT: ["REFLECT", 0, PSYCHIC_TYPE, 255, 20, Gen2MoveEffect.REFLECT, 0],
		SAFEGUARD: ["SAFEGUARD", 0, NORMAL, 255, 25, Gen2MoveEffect.SAFEGUARD, 0],
		PERISH_SONG: ["PERISH SONG", 0, NORMAL, 255, 5, Gen2MoveEffect.PERISH_SONG, 0],
		# Leech Seed's 229 is its real 90% as a byte (`x percent` is `x * 255 / 100`);
		# the other four never roll theirs.
		SUBSTITUTE: ["SUBSTITUTE", 0, NORMAL, 255, 10, Gen2MoveEffect.SUBSTITUTE, 0],
		LEECH_SEED: ["LEECH SEED", 0, GRASS, 229, 10, Gen2MoveEffect.LEECH_SEED, 0],
		NIGHTMARE: ["NIGHTMARE", 0, GHOST, 255, 15, Gen2MoveEffect.NIGHTMARE, 0],
		CURSE: ["CURSE", 0, CURSE_TYPE, 255, 10, Gen2MoveEffect.CURSE, 0],
		SPIKES: ["SPIKES", 0, GROUND, 255, 20, Gen2MoveEffect.SPIKES, 0],
		RAPID_SPIN: ["RAPID SPIN", 20, NORMAL, 255, 40, Gen2MoveEffect.RAPID_SPIN, 0],
		# Real rows. All four store 100% as the 255 that skips a roll, and none of
		# their lists rolls accuracy anyway.
		PROTECT: ["PROTECT", 0, NORMAL, 255, 10, Gen2MoveEffect.PROTECT, 0],
		DETECT: ["DETECT", 0, FIGHTING, 255, 5, Gen2MoveEffect.PROTECT, 0],
		ENDURE: ["ENDURE", 0, NORMAL, 255, 10, Gen2MoveEffect.ENDURE, 0],
		DESTINY_BOND: [
			"DESTINY BOND", 0, GHOST, 255, 5, Gen2MoveEffect.DESTINY_BOND, 0,
		],
		WHIRLWIND: ["WHIRLWIND", 0, NORMAL, 255, 20, Gen2MoveEffect.FORCE_SWITCH, 0],
		ROAR: ["ROAR", 0, NORMAL, 255, 20, Gen2MoveEffect.FORCE_SWITCH, 0],
		BATON_PASS: ["BATON PASS", 0, NORMAL, 255, 40, Gen2MoveEffect.BATON_PASS, 0],
		# Thunder with a paralysis chance the roll cannot fail, so the secondary
		# behind its own effect can be seen without a seed. The accuracy byte is
		# still the real 178, since that is what the weather rewrites.
		THUNDER_ALWAYS_PARALYZES: [
			"THUNDER", 120, ELECTRIC, 178, 10, Gen2MoveEffect.THUNDER, 256,
		],
		# Real rows, accuracy bytes included: Wrap and Bind can miss, so a test
		# that needs one to land raises the attacker's accuracy stage rather than
		# pretending either move always hits. Mean Look really is 255, and its
		# sequence never rolls it anyway.
		WRAP: ["WRAP", 15, NORMAL, 216, 20, Gen2MoveEffect.TRAP_TARGET, 0],
		BIND: ["BIND", 15, NORMAL, 191, 20, Gen2MoveEffect.TRAP_TARGET, 0],
		MEAN_LOOK: ["MEAN LOOK", 0, NORMAL, 255, 5, Gen2MoveEffect.MEAN_LOOK, 0],
		# The heal family, real rows: no power, 100% accuracy, and Rest the only
		# one of the seven that is not Normal or Grass. None of the four lists
		# rolls accuracy, so the byte is never read.
		RECOVER: ["RECOVER", 0, NORMAL, 255, 20, Gen2MoveEffect.HEAL, 0],
		SOFTBOILED: ["SOFTBOILED", 0, NORMAL, 255, 10, Gen2MoveEffect.HEAL, 0],
		REST: ["REST", 0, PSYCHIC_TYPE, 255, 10, Gen2MoveEffect.HEAL, 0],
		MILK_DRINK: ["MILK DRINK", 0, NORMAL, 255, 10, Gen2MoveEffect.HEAL, 0],
		MORNING_SUN: ["MORNING SUN", 0, NORMAL, 255, 5, Gen2MoveEffect.MORNING_SUN, 0],
		SYNTHESIS: ["SYNTHESIS", 0, GRASS, 255, 5, Gen2MoveEffect.SYNTHESIS, 0],
		MOONLIGHT: ["MOONLIGHT", 0, NORMAL, 255, 5, Gen2MoveEffect.MOONLIGHT, 0],
		# Real rows throughout, accuracy bytes included: `percent` is
		# `* $ff / 100` and truncates, so 90% is 229, 95% is 242 and 100% is 255.
		# The seven powers of 1 are the cartridge's own and are the point: a
		# command overwrites each of them before `damagecalc` reads it, so a row
		# that carried a plausible number would hide the step that fills it in.
		SWIFT: ["SWIFT", 60, NORMAL, 255, 20, Gen2MoveEffect.ALWAYS_HIT, 0],
		JUMP_KICK: ["JUMP KICK", 70, FIGHTING, 242, 25, Gen2MoveEffect.JUMP_KICK, 0],
		FLAIL: ["FLAIL", 1, NORMAL, 255, 15, Gen2MoveEffect.REVERSAL, 0],
		REVERSAL: ["REVERSAL", 1, FIGHTING, 255, 15, Gen2MoveEffect.REVERSAL, 0],
		RETURN: ["RETURN", 1, NORMAL, 255, 20, Gen2MoveEffect.RETURN, 0],
		PRESENT: ["PRESENT", 1, NORMAL, 229, 15, Gen2MoveEffect.PRESENT, 0],
		FRUSTRATION: [
			"FRUSTRATION", 1, NORMAL, 255, 20, Gen2MoveEffect.FRUSTRATION, 0,
		],
		HIDDEN_POWER: [
			"HIDDEN POWER", 1, NORMAL, 255, 15, Gen2MoveEffect.HIDDEN_POWER, 0,
		],
		FURY_CUTTER: ["FURY CUTTER", 10, BUG, 242, 20, Gen2MoveEffect.FURY_CUTTER, 0],
		TRIPLE_KICK: [
			"TRIPLE KICK", 10, FIGHTING, 229, 10, Gen2MoveEffect.TRIPLE_KICK, 0,
		],
		FALSE_SWIPE: [
			"FALSE SWIPE", 40, NORMAL, 255, 40, Gen2MoveEffect.FALSE_SWIPE, 0,
		],
		HEAL_BELL: ["HEAL BELL", 0, NORMAL, 255, 5, Gen2MoveEffect.HEAL_BELL, 0],
		SNORE: ["SNORE", 40, NORMAL, 255, 15, Gen2MoveEffect.SNORE, 76],
		TRI_ATTACK: ["TRI ATTACK", 80, NORMAL, 255, 10, Gen2MoveEffect.TRI_ATTACK, 51],
		STEEL_WING: [
			"STEEL WING", 70, STEEL, 229, 25, Gen2MoveEffect.DEFENSE_UP_HIT, 25,
		],
		SACRED_FIRE: [
			"SACRED FIRE", 100, FIRE, 242, 5, Gen2MoveEffect.SACRED_FIRE, 127,
		],
		STOMP: ["STOMP", 65, NORMAL, 255, 20, Gen2MoveEffect.STOMP, 76],
		# Minimize is the ordinary evasion-up effect, which is the whole reason
		# `MinimizeDropSub` has to compare the move number: nothing about the
		# effect byte tells it from Double Team.
		MINIMIZE: ["MINIMIZE", 0, NORMAL, 255, 20, Gen2MoveEffect.STAT_UP_BASE + 6, 0],
		SPLASH: ["SPLASH", 0, NORMAL, 255, 40, Gen2MoveEffect.SPLASH, 0],
		SWAGGER: ["SWAGGER", 0, NORMAL, 229, 15, Gen2MoveEffect.SWAGGER, 255],
		# The last row of the effects table. All nine store an accuracy of 255, so
		# `checkhit` never rolls one, and Thief's `100 percent` chance is a roll
		# `effectchance` cannot fail.
		TELEPORT: ["TELEPORT", 0, PSYCHIC_TYPE, 255, 20, Gen2MoveEffect.TELEPORT, 0],
		THIEF: ["THIEF", 40, DARK, 255, 10, Gen2MoveEffect.THIEF, 256],
		MIND_READER: [
			"MIND READER", 0, NORMAL, 255, 5, Gen2MoveEffect.LOCK_ON, 0,
		],
		SPITE: ["SPITE", 0, GHOST, 255, 10, Gen2MoveEffect.SPITE, 0],
		FORESIGHT: ["FORESIGHT", 0, NORMAL, 255, 40, Gen2MoveEffect.FORESIGHT, 0],
		LOCK_ON: ["LOCK-ON", 0, NORMAL, 255, 5, Gen2MoveEffect.LOCK_ON, 0],
		PAIN_SPLIT: [
			"PAIN SPLIT", 0, NORMAL, 255, 20, Gen2MoveEffect.PAIN_SPLIT, 0,
		],
		PURSUIT: ["PURSUIT", 40, DARK, 255, 20, Gen2MoveEffect.PURSUIT, 0],
		BEAT_UP: ["BEAT UP", 10, DARK, 255, 10, Gen2MoveEffect.BEAT_UP, 0],
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


## `ITEMATTR_EFFECT` and `ITEMATTR_PARAM` for the items a battle reads, keyed by
## item number with the real bytes: name, held effect, parameter.
const HELD_ITEMS: Dictionary = {
	SMOKE_BALL: ["SMOKE BALL", HELD_ESCAPE, 0],
	# 61 is HELD_ELECTRIC_BOOST, twelfth in the run that starts at
	# HELD_NORMAL_BOOST. Every one of the seventeen carries a parameter of 10.
	MAGNET: ["MAGNET", 61, 10],
	THICK_CLUB: ["THICK CLUB", 0, 0],
	LIGHT_BALL: ["LIGHT BALL", 0, 0],
	METAL_POWDER: ["METAL POWDER", Gen2HeldItem.METAL_POWDER, 10],
	SCOPE_LENS: ["SCOPE LENS", Gen2HeldItem.CRITICAL_UP, 0],
	QUICK_CLAW: ["QUICK CLAW", Gen2HeldItem.QUICK_CLAW, 60],
	KINGS_ROCK: ["KING'S ROCK", Gen2HeldItem.FLINCH, 30],
	BRIGHTPOWDER: ["BRIGHTPOWDER", Gen2HeldItem.BRIGHTPOWDER, 20],
	FOCUS_BAND: ["FOCUS BAND", Gen2HeldItem.FOCUS_BAND, 30],
	# The berries, with the HP each of the two restoring ones puts back. The
	# plain BERRY at [constant BERRY_ITEM] is the ten-point one.
	LEFTOVERS: ["LEFTOVERS", Gen2HeldItem.LEFTOVERS, 10],
	BERRY_ITEM: ["BERRY", Gen2HeldItem.BERRY, 10],
	GOLD_BERRY: ["GOLD BERRY", Gen2HeldItem.BERRY, 30],
	MYSTERYBERRY: ["MYSTERYBERRY", Gen2HeldItem.RESTORE_PP, 0],
	PSNCUREBERRY: ["PSNCUREBERRY", Gen2HeldItem.HEAL_POISON, 0],
	MIRACLEBERRY: ["MIRACLEBERRY", Gen2HeldItem.HEAL_STATUS, 0],
	BITTER_BERRY: ["BITTER BERRY", Gen2HeldItem.HEAL_CONFUSION, 0],
}


static func _items() -> Array:
	var out: Array = []
	for number: int in range(1, MAX_ITEM + 1):
		var held: Array = HELD_ITEMS.get(number, [])
		out.append({
			"number": number,
			"name": String(held[0]) if not held.is_empty() else "ITEM%d" % number,
			"effect": int(held[1]) if not held.is_empty() else 0,
			"parameter": int(held[2]) if not held.is_empty() else 0,
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
