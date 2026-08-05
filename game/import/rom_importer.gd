class_name RomImporter
extends RefCounted

## Decodes a verified cartridge into the cache under [code]user://[/code].
##
## The ROM is an asset database, read once and released. Nothing downstream of
## the cache holds a reference to it, and nothing in the engine reads cartridge
## bytes at play time.
##
## Order of business, and it matters: verify the hash, then verify the layout,
## then decode. [method verify_layout] exists because an offset table is a claim
## that can rot: a wrong constant produces plausible-looking garbage rather
## than an error, and garbage that reaches the cache is indistinguishable from
## real data later on. Checking a handful of values whose correct answers are
## known independently turns that class of mistake into an immediate failure.

## Atlas cells are the largest pic of their kind so a renderer can index them
## arithmetically; smaller pics sit in the top-left of their cell and record
## their real size.
const ATLAS_COLUMNS: int = 16

## Falkner is trainer class 1 in all three games, and the class in the middle is
## a walk check on a table whose entries are terminated rather than padded. The
## class that ends the table differs between games and lives in [RomLayout].
const TRAINER_FIRST_CLASS: String = "LEADER"
const TRAINER_MIDDLE_CLASS: int = 22
const TRAINER_MIDDLE_CLASS_NAME: String = "YOUNGSTER"

## What the evolution and learnset table is known to say, independently of the
## cartridge. The first species evolves at sixteen into the second and opens with
## Tackle at level one; the last has no evolution at all. One at each end of the
## pointer table, so a start that is right and a stride that is not fails too.
const FIRST_EVOLUTION_LEVEL: int = 16
const FIRST_LEARNSET_MOVE: int = 33

## Tyrogue, the only species that evolves on a stat comparison, and the number of
## ways it can go. It is worth checking on its own: [constant RomLayout.EVOLVE_STAT]
## is the one entry that is four bytes rather than three, so a decoder that has
## the size wrong stays in step everywhere except here and comes out the far side
## of Tyrogue reading rubbish.
const STAT_EVOLUTION_SPECIES: int = 236
const STAT_EVOLUTION_COUNT: int = 3

## What the trainer *party* table is known to say, independently of the
## cartridge, which is a different table from [constant TRAINER_FIRST_CLASS]:
## that one is the class every gym leader shares ("LEADER"), and this one is the
## individual trainer stored inside class 1's own entry. Falkner's level 7
## Pidgey and level 9 Pidgeotto are the same in all three games.
const TRAINER_PARTY_FIRST_NAME: String = "FALKNER"
const TRAINER_PARTY_FIRST_LEVEL_1: int = 7
const TRAINER_PARTY_FIRST_SPECIES_1: int = 16
const TRAINER_PARTY_FIRST_LEVEL_2: int = 9
const TRAINER_PARTY_FIRST_SPECIES_2: int = 17

## Falkner's own entry in the trainer attributes table, known independently of
## the cartridge from pret's `TrainerClassAttributes`: no items, a reward of 25,
## and the AI flag word every gym leader shares.
const TRAINER_ATTR_FIRST_REWARD: int = 25
const TRAINER_ATTR_FIRST_AI_MOVE_WEIGHTS: int = RomLayout.AI_BASIC | RomLayout.AI_SETUP \
	| RomLayout.AI_SMART | RomLayout.AI_AGGRESSIVE | RomLayout.AI_CAUTIOUS \
	| RomLayout.AI_STATUS | RomLayout.AI_RISKY
const TRAINER_ATTR_FIRST_AI_ITEM_SWITCH: int = RomLayout.CONTEXT_USE | RomLayout.SWITCH_SOMETIMES

## Falkner's own DVs, known independently of the cartridge from pret's
## `TrainerClassDVs`: attack 9, defense 10, speed 7, special 7, packed the way
## [method Gen2Stats.pack_dvs] packs a DV word.
const TRAINER_DVS_FIRST: int = 0x9A77

var _lz: Gen2Lz = Gen2Lz.new()


## Sanity-checks [RomLayout] against the cartridge before anything is decoded.
## Returns { ok, message }.
static func verify_layout(rom: RomFile) -> Dictionary:
	var layout: Dictionary = RomLayout.for_id(rom.id)
	if layout.is_empty():
		return {"ok": false, "message": "No layout for %s." % rom.id}

	var data: PackedByteArray = rom.bytes()

	# The first and last species, decoded through the text codec. Wrong offset,
	# wrong table or wrong character map all fail here.
	var first: String = Gen2Text.decode(
		data, RomLayout.species_name_offset(layout, 1), RomLayout.NAME_LENGTH
	)
	if first != "BULBASAUR":
		return {"ok": false, "message": "Species name table: expected BULBASAUR, read %s." % first}

	var last: String = Gen2Text.decode(
		data, RomLayout.species_name_offset(layout, RomLayout.SPECIES_COUNT),
		RomLayout.NAME_LENGTH
	)
	if last != "CELEBI":
		return {"ok": false, "message": "Species name table: expected CELEBI, read %s." % last}

	# Every base stats entry opens with its own Pokédex number, so the whole
	# table self-checks in one pass, and a stride that is off by any amount
	# stops matching immediately.
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var stored: int = rom.u8(RomLayout.base_stats_offset(layout, species))
		if stored != species:
			return {
				"ok": false,
				"message": "Base stats entry %d claims to be %d." % [species, stored],
			}

	# Palettes have no self-identifying field, so they are checked structurally:
	# a colour is 15 bits, and no species is drawn in two blacks. An offset that
	# lands on the wrong table, or a stride that runs past the end of the right
	# one, breaks one of those. This check exists because a palette table that
	# was one whole table too far along still decoded into sprites that were the
	# correct shapes in the wrong colours, which nothing else would catch.
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var entry: int = RomLayout.palette_offset(layout, species)
		var packed: Array = []
		for i: int in int(float(Gen2Palette.ENTRY_BYTES) / float(Gen2Palette.COLOR_BYTES)):
			packed.append(rom.u16le(entry + i * Gen2Palette.COLOR_BYTES))
		for color: int in packed:
			if color & 0x8000:
				return {
					"ok": false,
					"message": "Palette %d has bit 15 set ($%04X); not colour data." % [
						species, color,
					],
				}
		if packed.count(0) == packed.size():
			return {"ok": false, "message": "Palette %d is blank." % species}

	# Move and item names are variable-length, so one wrong byte at the start
	# slides every entry after it and still reads as words. Checking the last
	# entry of each table catches that; checking only the first would not.
	var moves: PackedStringArray = Gen2Text.decode_sequence(
		data, int(layout["move_names"]), RomLayout.MOVE_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	if moves.size() != RomLayout.MOVE_COUNT:
		return {"ok": false, "message": "Move name table ran out after %d." % moves.size()}
	if moves[0] != "POUND":
		return {"ok": false, "message": "Move name table: expected POUND, read %s." % moves[0]}
	if moves[RomLayout.MOVE_COUNT - 1] != "BEAT UP":
		return {
			"ok": false,
			"message": "Move name table: expected BEAT UP, read %s." % moves[
				RomLayout.MOVE_COUNT - 1
			],
		}

	# Every move entry opens with its animation, which is the move's own number,
	# so the whole table self-checks the way the base stats do. The type byte is
	# range-checked in the same pass because it indexes the type name table.
	for move: int in range(1, RomLayout.MOVE_COUNT + 1):
		var entry: int = RomLayout.move_data_offset(layout, move)
		var animation: int = rom.u8(entry + RomLayout.MOVE_ANIMATION)
		if animation != move:
			return {"ok": false, "message": "Move entry %d claims to be %d." % [move, animation]}
		var type_number: int = rom.u8(entry + RomLayout.MOVE_TYPE)
		if type_number >= RomLayout.TYPE_COUNT:
			return {
				"ok": false,
				"message": "Move %d has type $%02X, past the end of the type table." % [
					move, type_number,
				],
			}

	var items: PackedStringArray = Gen2Text.decode_sequence(
		data, int(layout["item_names"]), RomLayout.ITEM_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	if items.size() != RomLayout.ITEM_COUNT:
		return {"ok": false, "message": "Item name table ran out after %d." % items.size()}
	if items[0] != "MASTER BALL":
		return {"ok": false, "message": "Item name table: expected MASTER BALL, read %s." % items[0]}
	# Four entries in, so a start that is right but a walk that is not still
	# fails here.
	if items[3] != "GREAT BALL":
		return {"ok": false, "message": "Item 4: expected GREAT BALL, read %s." % items[3]}

	var item_metadata: Dictionary = verify_item_metadata(rom, layout)
	if not bool(item_metadata.get("ok", false)):
		return item_metadata

	var trades: Dictionary = verify_world_trades(rom, layout)
	if not bool(trades.get("ok", false)):
		return trades

	# The first and last type, either side of the padding run in the middle.
	var first_type: String = type_name(rom, layout, 0)
	if first_type != "NORMAL":
		return {"ok": false, "message": "Type table: expected NORMAL, read %s." % first_type}
	var last_type: String = type_name(rom, layout, RomLayout.TYPE_COUNT - 1)
	if last_type != "DARK":
		return {"ok": false, "message": "Type table: expected DARK, read %s." % last_type}

	var matchups: Dictionary = verify_matchups(rom, layout)
	if not matchups["ok"]:
		return matchups

	var evos_attacks: Dictionary = verify_evos_attacks(rom, layout)
	if not evos_attacks["ok"]:
		return evos_attacks

	var font: Dictionary = verify_font(rom, layout)
	if not font["ok"]:
		return font

	var frames: Dictionary = verify_frames(rom, layout)
	if not frames["ok"]:
		return frames

	var battle: Dictionary = verify_battle_graphics(rom, layout)
	if not battle["ok"]:
		return battle

	var trainers: Dictionary = verify_trainers(rom, layout)
	if not trainers["ok"]:
		return trainers

	var trainer_parties: Dictionary = verify_trainer_parties(rom, layout)
	if not trainer_parties["ok"]:
		return trainer_parties

	var trainer_attributes: Dictionary = verify_trainer_attributes(rom, layout)
	if not trainer_attributes["ok"]:
		return trainer_attributes

	var trainer_dvs: Dictionary = verify_trainer_dvs(rom, layout)
	if not trainer_dvs["ok"]:
		return trainer_dvs

	var world: Dictionary = Gen2WorldImporter.verify_layout(rom)
	if not world["ok"]:
		return world

	var encounters: Dictionary = Gen2WorldEncounterImporter.verify_layout(rom)
	if not encounters["ok"]:
		return encounters

	var services: Dictionary = Gen2WorldServicesImporter.verify_layout(rom)
	if not services["ok"]:
		return services

	return {"ok": true, "message": "Layout verified."}


## Walks the type matchup chart from its offset to the terminator.
##
## Returns an Array of { attacker, defender, multiplier, negated_by_foresight },
## or an empty Array if the walk ran away without finding an end. The rows after
## the $FE marker carry the flag: they are the matchups that stop applying once
## Foresight has identified the defender, which is how the cartridge gets a Ghost
## to be hittable by Normal without a second table.
static func read_matchups(rom: RomFile, layout: Dictionary) -> Array:
	var at: int = int(layout["type_matchups"])
	var out: Array = []
	var after_foresight: bool = false

	for _step: int in RomLayout.MAX_MATCHUPS:
		if not rom.in_bounds(at, RomLayout.MATCHUP_ENTRY_SIZE):
			return []

		var attacker: int = rom.u8(at + RomLayout.MATCHUP_ATTACKER)
		if attacker == RomLayout.MATCHUP_END:
			return out
		if attacker == RomLayout.MATCHUP_END_FORESIGHT:
			# The first marker is one byte, not an entry: the rows it separates
			# follow immediately after it.
			after_foresight = true
			at += 1
			continue

		out.append({
			"attacker": attacker,
			"defender": rom.u8(at + RomLayout.MATCHUP_DEFENDER),
			"multiplier": rom.u8(at + RomLayout.MATCHUP_MULTIPLIER),
			"negated_by_foresight": after_foresight,
		})
		at += RomLayout.MATCHUP_ENTRY_SIZE

	return []


## The matchup chart, checked by the shape a chart of exceptions has to have.
##
## It carries no name and no number, but it is unusually hard to land on by
## accident: every row is two sparse type numbers and a multiplier drawn from a
## set of three, the whole run has to walk to a $FE and then a $FF at exactly the
## right distance, and both ends are known content. A wrong offset fails on the
## very first row, because the padding run between the two groups of type numbers
## is most of the byte range.
static func verify_matchups(rom: RomFile, layout: Dictionary) -> Dictionary:
	var rows: Array = read_matchups(rom, layout)
	if rows.is_empty():
		return {"ok": false, "message": "Type matchups: no terminator within reach."}

	for index: int in rows.size():
		var row: Dictionary = rows[index]
		for side: String in ["attacker", "defender"]:
			var type_number: int = int(row[side])
			if not RomLayout.is_matchup_type(type_number):
				return {
					"ok": false,
					"message": "Type matchup %d: %s is $%02X, not a type." % [
						index, side, type_number,
					],
				}
		# A neutral matchup is an absent row, so a byte of ten here would mean the
		# walk is reading something that is not the chart.
		if not RomLayout.MATCHUP_MULTIPLIERS.has(int(row["multiplier"])):
			return {
				"ok": false,
				"message": "Type matchup %d has multiplier %d, which the chart never stores." % [
					index, int(row["multiplier"]),
				],
			}

	var negated: Array = rows.filter(func(row: Dictionary) -> bool:
		return bool(row["negated_by_foresight"])
	)
	if rows.size() != RomLayout.MATCHUP_COUNT + RomLayout.FORESIGHT_MATCHUP_COUNT:
		return {
			"ok": false,
			"message": "Type matchups: read %d rows, expected %d." % [
				rows.size(), RomLayout.MATCHUP_COUNT + RomLayout.FORESIGHT_MATCHUP_COUNT,
			],
		}
	if negated.size() != RomLayout.FORESIGHT_MATCHUP_COUNT:
		return {
			"ok": false,
			"message": "Type matchups: %d rows past the Foresight marker, expected %d." % [
				negated.size(), RomLayout.FORESIGHT_MATCHUP_COUNT,
			],
		}

	# Both ends, as content whose answer is known independently. The chart opens
	# with Normal against Rock and closes with Steel against itself, and the two
	# rows Foresight cancels are the Ghost immunities.
	var checks: Array = [
		[rows[0], RomLayout.TYPE_NORMAL, RomLayout.TYPE_ROCK,
			RomLayout.MATCHUP_NOT_VERY_EFFECTIVE, "the first row"],
		[rows[RomLayout.MATCHUP_COUNT - 1], RomLayout.TYPE_STEEL, RomLayout.TYPE_STEEL,
			RomLayout.MATCHUP_NOT_VERY_EFFECTIVE, "the last row"],
		[negated[0], RomLayout.TYPE_NORMAL, RomLayout.TYPE_GHOST,
			RomLayout.MATCHUP_NO_EFFECT, "the first Foresight row"],
		[negated[1], RomLayout.TYPE_FIGHTING, RomLayout.TYPE_GHOST,
			RomLayout.MATCHUP_NO_EFFECT, "the second Foresight row"],
	]
	for check: Array in checks:
		var row: Dictionary = check[0]
		if int(row["attacker"]) != int(check[1]) or int(row["defender"]) != int(check[2]) \
			or int(row["multiplier"]) != int(check[3]):
			return {
				"ok": false,
				"message": "Type matchups: %s is $%02X against $%02X at x%d/10." % [
					check[4], int(row["attacker"]), int(row["defender"]), int(row["multiplier"]),
				],
			}

	return {"ok": true, "message": ""}


## Walks one species' entry in the combined evolution and level-up move table.
##
## Returns { evolutions, learnset }, or an empty Dictionary if the walk did not
## find both terminators where a well-formed entry has them. An evolution is
## { method, parameter, condition, target } and a level-up move is
## { level, move }; [code]condition[/code] is zero for every method except
## [constant RomLayout.EVOLVE_STAT], which is the only one that asks two
## questions.
##
## Level-up moves are kept in the cartridge's order rather than sorted. The order
## is what decides which move a fresh Pokémon ends up with when more than four are
## on offer, and one species is genuinely out of order; see
## [constant RomLayout.UNSORTED_LEARNSET_SPECIES].
static func read_evos_attacks(rom: RomFile, layout: Dictionary, species: int) -> Dictionary:
	var table: int = RomLayout.evos_attacks_pointer_offset(layout, species)
	if not rom.in_bounds(table, RomLayout.EVOS_ATTACKS_POINTER_SIZE):
		return {}

	# The pointer is an address with no bank, so it has to be one the switchable
	# window can hold: the entry is in the pointer table's own bank.
	var address: int = rom.u16le(table)
	if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return {}
	var at: int = RomFile.linear(RomLayout.bank_of(table), address)

	var evolutions: Array = []
	while rom.in_bounds(at) and rom.u8(at) != RomLayout.EVOS_ATTACKS_END:
		if evolutions.size() >= RomLayout.MAX_EVOLUTIONS:
			return {}
		var method: int = rom.u8(at)
		if not RomLayout.EVOLVE_METHODS.has(method):
			return {}
		var size: int = RomLayout.evolution_size(method)
		if not rom.in_bounds(at, size):
			return {}
		# The target is always last, which is what makes the four-byte method fit
		# the same shape as the three-byte ones.
		evolutions.append({
			"method": method,
			"parameter": rom.u8(at + 1),
			"condition": rom.u8(at + 2) if method == RomLayout.EVOLVE_STAT else 0,
			"target": rom.u8(at + size - 1),
		})
		at += size

	if not rom.in_bounds(at):
		return {}
	at += 1

	var learnset: Array = []
	while rom.in_bounds(at) and rom.u8(at) != RomLayout.EVOS_ATTACKS_END:
		if learnset.size() >= RomLayout.MAX_LEVEL_UP_MOVES or not rom.in_bounds(at, 2):
			return {}
		learnset.append({"level": rom.u8(at), "move": rom.u8(at + 1)})
		at += 2

	if not rom.in_bounds(at):
		return {}
	return {"evolutions": evolutions, "learnset": learnset}


## The evolution and learnset table, checked species by species.
##
## Nothing in it says which species an entry belongs to, so what is checked is
## the shape: 251 pointers into the banked window, each naming a run of
## evolutions whose methods come from a set of five and whose targets are real
## species, then a run of level-up moves at real levels teaching real moves. A
## wrong pointer fails on the first byte it reads, because most byte values are
## not an evolution method and not a terminator.
##
## On top of that, the levels ascend in all but one species, the totals are known,
## and both ends of the table are content whose answer is known independently.
static func verify_evos_attacks(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entries: Array = []
	var evolutions: int = 0

	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var entry: Dictionary = read_evos_attacks(rom, layout, species)
		if entry.is_empty():
			return {
				"ok": false,
				"message": "Species %d has no readable evolution and learnset entry." % species,
			}

		for evolution: Dictionary in entry["evolutions"]:
			var check: Dictionary = _evolution_check(species, evolution)
			if not check["ok"]:
				return check
		evolutions += (entry["evolutions"] as Array).size()

		var learnset: Array = entry["learnset"]
		# Every species learns something by levelling, even the ones that learn it
		# all at level one, so an empty run means the walk is not on the table.
		if learnset.is_empty():
			return {"ok": false, "message": "Species %d learns no moves at all." % species}

		var previous: int = 0
		for move: Dictionary in learnset:
			var level: int = int(move["level"])
			var number: int = int(move["move"])
			if level < 1 or level > RomLayout.MAX_LEVEL:
				return {
					"ok": false,
					"message": "Species %d learns a move at level %d." % [species, level],
				}
			if number < 1 or number > RomLayout.MOVE_COUNT:
				return {
					"ok": false,
					"message": "Species %d learns move %d, which does not exist." % [
						species, number,
					],
				}
			if level < previous and species != RomLayout.UNSORTED_LEARNSET_SPECIES:
				return {
					"ok": false,
					"message": "Species %d learns at level %d after level %d." % [
						species, level, previous,
					],
				}
			previous = level

		entries.append(entry)

	if evolutions != RomLayout.EVOLUTION_COUNT:
		return {
			"ok": false,
			"message": "Read %d evolutions, expected %d." % [
				evolutions, RomLayout.EVOLUTION_COUNT,
			],
		}

	return _verify_known_evos_attacks(entries)


## One evolution entry, checked against what its method is allowed to say.
static func _evolution_check(species: int, evolution: Dictionary) -> Dictionary:
	var method: int = int(evolution["method"])
	var parameter: int = int(evolution["parameter"])
	var target: int = int(evolution["target"])

	if target < 1 or target > RomLayout.SPECIES_COUNT:
		return {
			"ok": false,
			"message": "Species %d evolves into %d, which does not exist." % [species, target],
		}

	match method:
		RomLayout.EVOLVE_LEVEL, RomLayout.EVOLVE_STAT:
			if parameter < 1 or parameter > RomLayout.MAX_LEVEL:
				return {
					"ok": false,
					"message": "Species %d evolves at level %d." % [species, parameter],
				}
		RomLayout.EVOLVE_HAPPINESS:
			if parameter < RomLayout.TRIGGER_ANYTIME or parameter > RomLayout.TRIGGER_NITE:
				return {
					"ok": false,
					"message": "Species %d evolves on happiness trigger %d." % [species, parameter],
				}

	if method == RomLayout.EVOLVE_STAT:
		var condition: int = int(evolution["condition"])
		if condition < RomLayout.ATTACK_OVER_DEFENSE \
			or condition > RomLayout.ATTACK_EQUALS_DEFENSE:
			return {
				"ok": false,
				"message": "Species %d evolves on stat comparison %d." % [species, condition],
			}

	return {"ok": true, "message": ""}


## The three entries whose contents are known independently of the cartridge.
static func _verify_known_evos_attacks(entries: Array) -> Dictionary:
	var first: Dictionary = entries[0]
	var first_evolutions: Array = first["evolutions"]
	if first_evolutions.size() != 1 \
		or int(first_evolutions[0]["method"]) != RomLayout.EVOLVE_LEVEL \
		or int(first_evolutions[0]["parameter"]) != FIRST_EVOLUTION_LEVEL \
		or int(first_evolutions[0]["target"]) != 2:
		return {
			"ok": false,
			"message": "Species 1 should evolve into species 2 at level %d." % FIRST_EVOLUTION_LEVEL,
		}

	var first_learnset: Array = first["learnset"]
	if int(first_learnset[0]["level"]) != 1 \
		or int(first_learnset[0]["move"]) != FIRST_LEARNSET_MOVE:
		return {
			"ok": false,
			"message": "Species 1 should open with move %d at level 1, not move %d at level %d." % [
				FIRST_LEARNSET_MOVE, int(first_learnset[0]["move"]),
				int(first_learnset[0]["level"]),
			],
		}

	# The last species is the far end of the pointer table, and it is one of the
	# ones that never evolves.
	var last_evolutions: Array = entries[RomLayout.SPECIES_COUNT - 1]["evolutions"]
	if not last_evolutions.is_empty():
		return {
			"ok": false,
			"message": "Species %d should not evolve, and has %d evolutions." % [
				RomLayout.SPECIES_COUNT, last_evolutions.size(),
			],
		}

	var stat_evolutions: Array = entries[STAT_EVOLUTION_SPECIES - 1]["evolutions"]
	if stat_evolutions.size() != STAT_EVOLUTION_COUNT:
		return {
			"ok": false,
			"message": "Species %d should have %d evolutions, and has %d." % [
				STAT_EVOLUTION_SPECIES, STAT_EVOLUTION_COUNT, stat_evolutions.size(),
			],
		}
	for evolution: Dictionary in stat_evolutions:
		if int(evolution["method"]) != RomLayout.EVOLVE_STAT:
			return {
				"ok": false,
				"message": "Species %d should evolve on a stat comparison, and uses method %d." % [
					STAT_EVOLUTION_SPECIES, int(evolution["method"]),
				],
			}

	return {"ok": true, "message": ""}


## The font carries no name and no number, so it is checked against the one
## thing that is known about it independently: the charmap.
##
## The font is indexed by character code, so the letters and digits [Gen2Text]
## claims are there must have ink, and the runs of codes it has no character for
## must be blank. Those runs sit between the alphabets, so an offset out by a
## single tile drags a blank onto "z" and a glyph onto a code that has none, and
## the check fails in both directions at once.
static func verify_font(rom: RomFile, layout: Dictionary) -> Dictionary:
	var offset: int = RomLayout.font_offset(layout)
	var length: int = RomLayout.FONT_TILES * Gen2Tiles.TILE_1BPP_BYTES
	if not rom.in_bounds(offset, length):
		return {"ok": false, "message": "Font runs past the end of the dump."}

	for run: Array in RomLayout.FONT_INK_RUNS:
		for code: int in range(run[0], run[1] + 1):
			if _glyph_ink(rom, offset, code) == 0:
				return {
					"ok": false,
					"message": "Font: code $%02X (%s) has no glyph." % [
						code, Gen2Text.character(code),
					],
				}

	for run: Array in RomLayout.FONT_BLANK_RUNS:
		for code: int in range(run[0], run[1] + 1):
			if _glyph_ink(rom, offset, code) != 0:
				return {
					"ok": false,
					"message": "Font: code $%02X has a glyph but no character." % code,
				}

	# No glyph fills a row of eight: every character leaves the spacing column
	# clear, and most leave more. A run of $FF is graphics, not a font.
	for i: int in length:
		if rom.u8(offset + i) == 0xFF:
			return {"ok": false, "message": "Font: solid row at byte %d; not font data." % i}

	return {"ok": true, "message": ""}


## Ink in the tile for one character code, in pixels.
static func _glyph_ink(rom: RomFile, offset: int, code: int) -> int:
	var at: int = offset + (code - RomLayout.FONT_FIRST_CODE) * Gen2Tiles.TILE_1BPP_BYTES
	var ink: int = 0
	for row: int in Gen2Tiles.TILE_1BPP_BYTES:
		var byte: int = rom.u8(at + row)
		for bit: int in 8:
			ink += (byte >> bit) & 1
	return ink


## Frames are checked by the shape a border has to have rather than by content,
## because all eight are decoration and none of them says which it is.
static func verify_frames(rom: RomFile, layout: Dictionary) -> Dictionary:
	var seen: Array = []

	for frame: int in RomLayout.FRAME_COUNT:
		var offset: int = RomLayout.frame_offset(layout, frame)
		var tiles: PackedByteArray = rom.slice(
			offset, RomLayout.FRAME_TILES * Gen2Tiles.TILE_1BPP_BYTES
		)
		if tiles.is_empty():
			return {"ok": false, "message": "Frame %d runs past the end of the dump." % frame}

		# A border is inset from the top of its tile row, so the top-left, top and
		# top-right tiles all open with blank scanlines.
		for tile: int in [
			RomLayout.FRAME_TOP_LEFT, RomLayout.FRAME_HORIZONTAL, RomLayout.FRAME_TOP_RIGHT
		]:
			for row: int in 2:
				if tiles[tile * Gen2Tiles.TILE_1BPP_BYTES + row] != 0:
					return {
						"ok": false,
						"message": "Frame %d tile %d has ink on row %d of its top edge." % [
							frame, tile, row,
						],
					}

		# The two bottom corners continue the vertical edge they hang from, so
		# their first row is one the vertical tile also draws.
		var left: int = tiles[RomLayout.FRAME_BOTTOM_LEFT * Gen2Tiles.TILE_1BPP_BYTES]
		var right: int = tiles[RomLayout.FRAME_BOTTOM_RIGHT * Gen2Tiles.TILE_1BPP_BYTES]
		if left == 0 or left != right:
			return {
				"ok": false,
				"message": "Frame %d corners do not meet its sides ($%02X, $%02X)." % [
					frame, left, right,
				],
			}
		var vertical: PackedByteArray = tiles.slice(
			RomLayout.FRAME_VERTICAL * Gen2Tiles.TILE_1BPP_BYTES,
			(RomLayout.FRAME_VERTICAL + 1) * Gen2Tiles.TILE_1BPP_BYTES
		)
		if not vertical.has(left):
			return {
				"ok": false,
				"message": "Frame %d side never draws $%02X, which its corners do." % [frame, left],
			}

		# Eight identical frames would mean the table is not where it is claimed
		# to be, or is not a table at all.
		if seen.has(tiles):
			return {"ok": false, "message": "Frame %d repeats an earlier frame." % frame}
		seen.append(tiles)

	return {"ok": true, "message": ""}


## The battle HUD's graphics, checked by the one thing they do that nothing else
## in the section does: they count.
##
## A bar's fill levels are consecutive tiles, each lighting one more column than
## the last, so the ink in that run climbs by exactly two pixels a step. Neither
## bar has a name or a number in the cartridge, but a run that counts up like
## that is not something a wrong offset lands on. The two HUD borders have
## neither content nor a progression, so they are checked the way the text box
## frames are: every tile has ink, and no two tiles are the same.
static func verify_battle_graphics(rom: RomFile, layout: Dictionary) -> Dictionary:
	var data: PackedByteArray = rom.bytes()

	# The bar palettes are known values rather than a shape, so they are checked
	# as the species names are: against what they have to say.
	for index: int in RomLayout.BAR_PALETTE_NAMES.size():
		var entry: int = RomLayout.bar_palette_offset(layout, index)
		var wanted: Array = RomLayout.BAR_PALETTES[index]
		for colour: int in wanted.size():
			var read: int = rom.u16le(entry + colour * Gen2Palette.COLOR_BYTES)
			if read != int(wanted[colour]):
				return {
					"ok": false,
					"message": "Bar palette %s colour %d: expected $%04X, read $%04X." % [
						RomLayout.BAR_PALETTE_NAMES[index], colour, wanted[colour], read,
					],
				}

	var battle_font: PackedByteArray = Gen2Tiles.decode_2bpp_strip(
		data, int(layout["battle_font"]), RomLayout.BATTLE_FONT_TILES
	)
	var hp_bar: Dictionary = _verify_bar(
		battle_font, RomLayout.BATTLE_FONT_TILES, RomLayout.HP_BAR_FIRST_TILE,
		RomLayout.HP_BAR_LEVELS, "HP bar"
	)
	if not hp_bar["ok"]:
		return hp_bar

	var exp_bar: PackedByteArray = Gen2Tiles.decode_2bpp_strip(
		data, int(layout["exp_bar"]), RomLayout.EXP_BAR_TILES
	)
	var levels: Dictionary = _verify_bar(
		exp_bar, RomLayout.EXP_BAR_TILES, 0, RomLayout.EXP_BAR_LEVELS, "exp bar"
	)
	if not levels["ok"]:
		return levels

	for name: String in ["enemy_hud", "player_hud"]:
		var tiles: int = RomLayout.ENEMY_HUD_TILES if name == "enemy_hud" \
			else RomLayout.PLAYER_HUD_TILES
		var strip: PackedByteArray = Gen2Tiles.decode_1bpp_strip(
			data, int(layout[name]), tiles
		)
		var seen: Array = []
		for tile: int in tiles:
			var pixels: PackedByteArray = _strip_tile(strip, tiles, tile)
			if _ink(pixels) == 0:
				return {"ok": false, "message": "%s tile %d is blank." % [name, tile]}
			if seen.has(pixels):
				return {"ok": false, "message": "%s tile %d repeats an earlier one." % [name, tile]}
			seen.append(pixels)

	return {"ok": true, "message": ""}


## One bar's fill levels: consecutive tiles whose ink climbs by a fixed step.
static func _verify_bar(
	strip: PackedByteArray, tiles: int, first: int, levels: int, what: String
) -> Dictionary:
	if strip.size() != tiles * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT:
		return {"ok": false, "message": "%s: strip decoded short." % what}

	var previous: int = _ink(_strip_tile(strip, tiles, first))
	if previous == 0:
		return {"ok": false, "message": "%s: the empty level has no ink." % what}

	for level: int in range(1, levels):
		var ink: int = _ink(_strip_tile(strip, tiles, first + level))
		if ink != previous + RomLayout.BAR_STEP_PIXELS:
			return {
				"ok": false,
				"message": "%s: level %d has %d pixels, expected %d." % [
					what, level, ink, previous + RomLayout.BAR_STEP_PIXELS,
				],
			}
		previous = ink

	return {"ok": true, "message": ""}


## One tile out of a strip, as its own buffer.
static func _strip_tile(strip: PackedByteArray, tiles: int, tile: int) -> PackedByteArray:
	var width: int = tiles * Gen2Tiles.TILE_WIDTH
	var out: PackedByteArray = PackedByteArray()
	out.resize(Gen2Tiles.TILE_PIXELS)
	for row: int in Gen2Tiles.TILE_HEIGHT:
		for column: int in Gen2Tiles.TILE_WIDTH:
			out[row * Gen2Tiles.TILE_WIDTH + column] = strip[
				row * width + tile * Gen2Tiles.TILE_WIDTH + column
			]
	return out


## Lit pixels in a decoded tile, whatever colour they are.
static func _ink(pixels: PackedByteArray) -> int:
	var out: int = 0
	for index: int in pixels:
		if index != 0:
			out += 1
	return out


## The three trainer tables, each checked by what is known about it independently.
##
## They are checked together because they are three views of one numbering, and
## a mistake in any of them shows up as the three disagreeing: the names say what
## a class is, the palette table has one entry more than the pic table because
## the player owns the first one, and the pic table's entries have to decompress
## into pics of the one size every trainer is drawn at.
static func verify_trainers(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.trainer_class_count(layout)
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["trainer_class_names"]), count, RomLayout.MAX_NAME_LENGTH
	)
	if names.size() != count:
		return {"ok": false, "message": "Trainer class names ran out after %d." % names.size()}
	# Falkner opens the table, and the classes are terminated rather than padded,
	# so the far end is checked as well as the near one. The class in the middle
	# catches a start that is right and a walk that is not.
	if names[0] != TRAINER_FIRST_CLASS:
		return {
			"ok": false,
			"message": "Trainer class 1: expected %s, read %s." % [TRAINER_FIRST_CLASS, names[0]],
		}
	if names[TRAINER_MIDDLE_CLASS - 1] != TRAINER_MIDDLE_CLASS_NAME:
		return {
			"ok": false,
			"message": "Trainer class %d: expected %s, read %s." % [
				TRAINER_MIDDLE_CLASS, TRAINER_MIDDLE_CLASS_NAME, names[TRAINER_MIDDLE_CLASS - 1],
			],
		}
	var last_class: String = String(layout["trainer_last_class"])
	if names[count - 1] != last_class:
		return {
			"ok": false,
			"message": "Trainer class %d: expected %s, read %s." % [
				count, last_class, names[count - 1],
			],
		}

	# Palettes are checked structurally, as the species ones are, and then at one
	# entry past the end: the table is the player plus every class, so whatever
	# follows it must not read as a palette. Without that, an offset that slid by
	# a whole entry would pass every check above it.
	for trainer_class: int in range(0, count + 1):
		var check: Dictionary = _trainer_palette_check(rom, layout, trainer_class)
		if not check["ok"]:
			return check
	if _trainer_palette_check(rom, layout, count + 1)["ok"]:
		return {
			"ok": false,
			"message": "Trainer palette table has a %dth entry; it should end at %d." % [
				count + 2, count + 1,
			],
		}

	# Every pointer has to address the switchable window of a bank that exists.
	# The two ends are decompressed as well, which is what proves the bank repair
	# is the same one the Pokémon pics need.
	var lz := Gen2Lz.new()
	var wanted: int = RomLayout.TRAINER_PIC_TILES * RomLayout.TRAINER_PIC_TILES \
		* Gen2Tiles.TILE_BYTES
	for trainer_class: int in range(1, count + 1):
		var offset: int = RomLayout.trainer_pic_pointer_offset(layout, trainer_class)
		var pointer: Dictionary = rom.far_pointer(offset)
		var address: int = int(pointer["address"])
		if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
			return {
				"ok": false,
				"message": "Trainer pic %d points at $%04X, outside the banked window." % [
					trainer_class, address,
				],
			}
		var start: int = RomFile.linear(
			RomLayout.fix_pic_bank(layout, int(pointer["bank"])), address
		)
		if not rom.in_bounds(start):
			return {"ok": false, "message": "Trainer pic %d points past the dump." % trainer_class}
		if trainer_class != 1 and trainer_class != count:
			continue
		var raw: PackedByteArray = lz.decompress(rom.bytes(), start)
		if lz.failed or raw.size() < wanted:
			return {
				"ok": false,
				"message": "Trainer pic %d decompressed to %d bytes, wanted %d." % [
					trainer_class, raw.size(), wanted,
				],
			}

	return {"ok": true, "message": ""}


## One trainer palette entry, checked the way a species' is: fifteen-bit colours,
## and never two blacks.
static func _trainer_palette_check(
	rom: RomFile, layout: Dictionary, trainer_class: int
) -> Dictionary:
	var entry: int = RomLayout.trainer_palette_offset(layout, trainer_class)
	if not rom.in_bounds(entry, Gen2Palette.PAIR_BYTES):
		return {"ok": false, "message": "Trainer palette %d is past the end." % trainer_class}

	var first: int = rom.u16le(entry)
	var second: int = rom.u16le(entry + Gen2Palette.COLOR_BYTES)
	if (first | second) & 0x8000:
		return {
			"ok": false,
			"message": "Trainer palette %d has bit 15 set ($%04X, $%04X)." % [
				trainer_class, first, second,
			],
		}
	if first == 0 and second == 0:
		return {"ok": false, "message": "Trainer palette %d is blank." % trainer_class}
	return {"ok": true, "message": ""}


## Reads the whole trainer party table in one pass: every class's individual
## trainers, each a name, a type and a party.
##
## This is not [method verify_trainers]'s table. That one is the class every
## gym leader shares ("LEADER") and this one is the trainer inside it
## ("FALKNER"), and the two are read through entirely different pointers, one
## per class in both.
##
## Nothing inside a class's own bytes says where its group ends, so a class's
## span is bounded by the *next* class's pointer rather than by anything it
## carries itself, and the last class is walked until a byte that cannot open a
## name is met instead. One class in every game shares its pointer with the
## next, which is the one class the games never send into a battle: its honest
## span is empty, not a copy of the class after it. See
## [constant RomLayout.EMPTY_TRAINER_CLASS].
##
## Returns { ok, message, classes, total }, where [code]classes[/code] is one
## Array of trainers per class, in order.
static func read_trainer_parties(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.trainer_class_count(layout)
	var table: int = int(layout["trainer_parties"])
	var bank: int = RomLayout.bank_of(table)

	var pointers: Array = []
	for trainer_class: int in range(1, count + 1):
		var offset: int = RomLayout.trainer_party_pointer_offset(layout, trainer_class)
		if not rom.in_bounds(offset, RomLayout.TRAINER_PARTY_POINTER_SIZE):
			return {
				"ok": false,
				"message": "Trainer party pointer %d is past the end." % trainer_class,
			}
		pointers.append(rom.u16le(offset))

	var classes: Array = []
	var total: int = 0
	for trainer_class: int in range(1, count + 1):
		var address: int = pointers[trainer_class - 1]
		if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
			return {
				"ok": false,
				"message": "Trainer class %d's party points at $%04X, outside the banked window." % [
					trainer_class, address,
				],
			}
		var at: int = RomFile.linear(bank, address)

		# The pointers are non-decreasing in class order in every game but one,
		# so the class after this one is what bounds it; the walk itself proves
		# the offset, because a span that has slid cannot tile the region.
		var end: int = -1
		if trainer_class < count:
			var next_address: int = pointers[trainer_class]
			if next_address < address:
				return {
					"ok": false,
					"message": "Trainer class %d's party pointer goes backwards." % trainer_class,
				}
			end = RomFile.linear(bank, next_address)

		var group: Dictionary = _read_trainer_group(rom, at, end)
		if not group["ok"]:
			return {
				"ok": false,
				"message": "Trainer class %d: %s" % [trainer_class, group["message"]],
			}

		classes.append(group["trainers"])
		total += (group["trainers"] as Array).size()

	return {"ok": true, "message": "", "classes": classes, "total": total}


## One class's span of trainers: read from [param start] to exactly
## [param end], or, when [param end] is negative because this is the last
## class, until a byte that cannot open a name (the padding past the real
## table) is met. A span that overshoots [param end] is caught here rather than
## left for the next class to notice, because there may not be a next class.
static func _read_trainer_group(rom: RomFile, start: int, end: int) -> Dictionary:
	var trainers: Array = []
	var at: int = start

	while true:
		if end >= 0:
			if at == end:
				break
			if at > end:
				return {"ok": false, "message": "a trainer's own party walked past the next class."}
		elif not rom.in_bounds(at) or rom.u8(at) == 0:
			break

		if trainers.size() >= RomLayout.MAX_TRAINERS_PER_CLASS:
			return {"ok": false, "message": "more trainers than any real class carries."}

		var trainer: Dictionary = _read_one_trainer(rom, at)
		if trainer.is_empty():
			return {"ok": false, "message": "a trainer at $%X did not parse." % at}

		trainers.append(trainer)
		at = int(trainer["_next"])

	return {"ok": true, "message": "", "trainers": trainers}


## One trainer: a $50-terminated name, a type byte, its Pokémon and $FF. Returns
## an empty Dictionary for anything that does not parse as that shape, which is
## most byte values, since a level, a species and a move number are all
## range-checked as they are read.
static func _read_one_trainer(rom: RomFile, at: int) -> Dictionary:
	var start: int = at
	var end: int = at
	while rom.in_bounds(end) and rom.u8(end) != Gen2Text.TERMINATOR:
		end += 1
		if end - start > RomLayout.MAX_NAME_LENGTH:
			return {}
	if not rom.in_bounds(end):
		return {}
	var name: String = Gen2Text.decode(rom.bytes(), start, end - start)

	var pos: int = end + 1
	if not rom.in_bounds(pos):
		return {}
	var mon_type: int = rom.u8(pos)
	if not RomLayout.TRAINER_MON_TYPES.has(mon_type):
		return {}
	pos += 1

	var party: Array = []
	while rom.in_bounds(pos) and rom.u8(pos) != RomLayout.TRAINER_PARTY_END:
		if party.size() >= RomLayout.MAX_TRAINER_PARTY_SIZE:
			return {}
		if not rom.in_bounds(pos, 2):
			return {}
		var level: int = rom.u8(pos)
		var species: int = rom.u8(pos + 1)
		if level < 1 or level > RomLayout.MAX_LEVEL:
			return {}
		if species < 1 or species > RomLayout.SPECIES_COUNT:
			return {}
		pos += 2

		var extra: int = RomLayout.trainer_mon_extra_size(mon_type)
		if not rom.in_bounds(pos, extra):
			return {}
		var item: int = 0
		var moves: Array = []
		if mon_type == RomLayout.TRAINER_MON_ITEM or mon_type == RomLayout.TRAINER_MON_ITEM_MOVES:
			item = rom.u8(pos)
			pos += 1
		if mon_type == RomLayout.TRAINER_MON_MOVES or mon_type == RomLayout.TRAINER_MON_ITEM_MOVES:
			for slot: int in RomLayout.TRAINER_MON_MOVE_COUNT:
				var move: int = rom.u8(pos + slot)
				if move > RomLayout.MOVE_COUNT:
					return {}
				moves.append(move)
			pos += RomLayout.TRAINER_MON_MOVE_COUNT

		party.append({"level": level, "species": species, "item": item, "moves": moves})

	if not rom.in_bounds(pos) or party.is_empty():
		return {}
	pos += 1

	return {"name": name, "type": mon_type, "party": party, "_next": pos}


## The trainer party table, checked by everything known about it independently:
## the walk itself (see [method _read_trainer_group]), the one class with no
## party of its own, the total trainer count, and Falkner's team at one end and
## the last class's first trainer's name at the other.
static func verify_trainer_parties(rom: RomFile, layout: Dictionary) -> Dictionary:
	var result: Dictionary = read_trainer_parties(rom, layout)
	if not result["ok"]:
		return result

	var classes: Array = result["classes"]
	if int(result["total"]) != int(layout["trainer_party_total"]):
		return {
			"ok": false,
			"message": "Read %d trainers, expected %d." % [
				result["total"], layout["trainer_party_total"],
			],
		}

	for trainer_class: int in range(1, classes.size() + 1):
		var group: Array = classes[trainer_class - 1]
		var should_be_empty: bool = trainer_class == RomLayout.EMPTY_TRAINER_CLASS
		if should_be_empty != group.is_empty():
			return {
				"ok": false,
				"message": "Trainer class %d has %d trainers; expected %s." % [
					trainer_class, group.size(), "none" if should_be_empty else "at least one",
				],
			}

	var falkner: Dictionary = classes[0][0]
	if String(falkner["name"]) != TRAINER_PARTY_FIRST_NAME:
		return {
			"ok": false,
			"message": "Trainer class 1's first trainer: expected %s, read %s." % [
				TRAINER_PARTY_FIRST_NAME, falkner["name"],
			],
		}
	var falkner_party: Array = falkner["party"]
	if falkner_party.size() != 2 \
		or int(falkner_party[0]["level"]) != TRAINER_PARTY_FIRST_LEVEL_1 \
		or int(falkner_party[0]["species"]) != TRAINER_PARTY_FIRST_SPECIES_1 \
		or int(falkner_party[1]["level"]) != TRAINER_PARTY_FIRST_LEVEL_2 \
		or int(falkner_party[1]["species"]) != TRAINER_PARTY_FIRST_SPECIES_2:
		return {"ok": false, "message": "Falkner's party does not match what is known of it."}

	var last_group: Array = classes[classes.size() - 1]
	var last_trainer: Dictionary = last_group[0]
	var wanted_last: String = String(layout["trainer_party_last_trainer"])
	if String(last_trainer["name"]) != wanted_last:
		return {
			"ok": false,
			"message": "Last trainer class's first trainer: expected %s, read %s." % [
				wanted_last, last_trainer["name"],
			],
		}

	return {"ok": true, "message": ""}


## One trainer class's own entry in the attributes table: two item numbers,
## a base money reward, and the two flag words the AI reads. A fixed stride,
## not a pointer, so unlike the party table nothing here is walked.
static func read_trainer_attributes(rom: RomFile, layout: Dictionary, trainer_class: int) -> Dictionary:
	var offset: int = RomLayout.trainer_attributes_offset(layout, trainer_class)
	return {
		"item1": rom.u8(offset + RomLayout.ATTR_ITEM1),
		"item2": rom.u8(offset + RomLayout.ATTR_ITEM2),
		"base_reward": rom.u8(offset + RomLayout.ATTR_BASE_REWARD),
		"ai_move_weights": rom.u16le(offset + RomLayout.ATTR_AI_MOVE_WEIGHTS),
		"ai_item_switch": rom.u16le(offset + RomLayout.ATTR_AI_ITEM_SWITCH),
	}


## The trainer attributes table, checked entry by entry: neither flag word may
## carry a bit past what [constant RomLayout.AI_MOVE_WEIGHTS_MASK] and
## [constant RomLayout.AI_ITEM_SWITCH_MASK] define, which a wrong offset fails
## almost immediately and has to pass 66 or 67 times running to slip through by
## chance. Falkner's own entry is content whose answer is known independently,
## the same anchor [constant TRAINER_FIRST_CLASS] gives the class name table.
static func verify_trainer_attributes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.trainer_class_count(layout)

	for trainer_class: int in range(1, count + 1):
		var offset: int = RomLayout.trainer_attributes_offset(layout, trainer_class)
		if not rom.in_bounds(offset, RomLayout.TRAINER_ATTRIBUTES_SIZE):
			return {
				"ok": false,
				"message": "Trainer attributes %d is past the end." % trainer_class,
			}

		var entry: Dictionary = read_trainer_attributes(rom, layout, trainer_class)
		var weights: int = int(entry["ai_move_weights"])
		if weights & ~RomLayout.AI_MOVE_WEIGHTS_MASK:
			return {
				"ok": false,
				"message": "Trainer attributes %d: AI move weights $%04X use undefined bits." % [
					trainer_class, weights,
				],
			}
		var switch_flags: int = int(entry["ai_item_switch"])
		if switch_flags & ~RomLayout.AI_ITEM_SWITCH_MASK:
			return {
				"ok": false,
				"message": "Trainer attributes %d: item/switch flags $%04X use undefined bits." % [
					trainer_class, switch_flags,
				],
			}

	var falkner: Dictionary = read_trainer_attributes(rom, layout, 1)
	if int(falkner["item1"]) != 0 or int(falkner["item2"]) != 0 \
		or int(falkner["base_reward"]) != TRAINER_ATTR_FIRST_REWARD \
		or int(falkner["ai_move_weights"]) != TRAINER_ATTR_FIRST_AI_MOVE_WEIGHTS \
		or int(falkner["ai_item_switch"]) != TRAINER_ATTR_FIRST_AI_ITEM_SWITCH:
		return {"ok": false, "message": "Trainer class 1's attributes do not match what is known of it."}

	return {"ok": true, "message": ""}


## One trainer class's own entry in the DVs table, packed into the same DV word
## shape [method Gen2BattleMon.create] takes as [code]dv_word[/code]: the two
## raw bytes read as one big-endian integer are already attack, defense, speed
## and special in [method Gen2Stats.pack_dvs]'s own nibble order, so nothing
## here has to unpack and repack them.
static func read_trainer_dvs(rom: RomFile, layout: Dictionary, trainer_class: int) -> int:
	var offset: int = RomLayout.trainer_dvs_offset(layout, trainer_class)
	return (rom.u8(offset) << 8) | rom.u8(offset + 1)


## The trainer DVs table has no structural shape to check: every nibble is a
## legal DV, so a wrong offset produces a plausible-looking table exactly the
## way it always would. What settles it is content whose answer is known
## independently at both ends, the same way the move and item name tables are
## checked: Falkner opens the table with his own known DVs, and the class that
## closes it (a different one per game, since Crystal alone carries
## MYSTICALMAN) carries its own, stored in the layout as [code]trainer_dvs_last[/code].
static func verify_trainer_dvs(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.trainer_class_count(layout)
	var last_offset: int = RomLayout.trainer_dvs_offset(layout, count)
	if not rom.in_bounds(last_offset, RomLayout.TRAINER_DVS_SIZE):
		return {"ok": false, "message": "Trainer DVs table is past the end."}

	var falkner: int = read_trainer_dvs(rom, layout, 1)
	if falkner != TRAINER_DVS_FIRST:
		return {
			"ok": false,
			"message": "Trainer class 1's DVs: expected $%04X, read $%04X." % [
				TRAINER_DVS_FIRST, falkner,
			],
		}

	var last: int = read_trainer_dvs(rom, layout, count)
	var expected_last: int = int(layout["trainer_dvs_last"])
	if last != expected_last:
		return {
			"ok": false,
			"message": "Trainer class %d's DVs: expected $%04X, read $%04X." % [
				count, expected_last, last,
			],
		}

	return {"ok": true, "message": ""}


## Resolves one entry of the type name pointer table.
static func type_name(rom: RomFile, layout: Dictionary, type_number: int) -> String:
	var table: int = RomLayout.type_name_pointer_offset(layout, type_number)
	var address: int = rom.u16le(table)
	var offset: int = RomFile.linear(RomLayout.bank_of(table), address)
	return Gen2Text.decode(rom.bytes(), offset, RomLayout.MAX_NAME_LENGTH)


## Imports [param rom] into its cache directory, replacing whatever was there.
##
## [param on_progress] is called as [code](stage, done, total)[/code] if given.
## Returns { ok, message, directory, species, elapsed_ms }.
func import_rom(rom: RomFile, on_progress: Callable = Callable()) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var result: Dictionary = {
		"ok": false,
		"message": "",
		"directory": directory,
		"species": 0,
		"moves": 0,
		"items": 0,
		"types": 0,
		"matchups": 0,
		"trainers": 0,
		"trainer_party_count": 0,
		"evolutions": 0,
		"learnset_moves": 0,
		"maps": 0,
		"tilesets": 0,
		"overworld_sprites": 0,
		"menus": 0,
		"marts": 0,
		"phone_contacts": 0,
		"special_phone_calls": 0,
		"phone_scripts": 0,
		"music": 0,
		"sfx": 0,
		"elapsed_ms": 0,
	}

	var layout: Dictionary = RomLayout.for_id(rom.id)
	var check: Dictionary = verify_layout(rom)
	if not check["ok"]:
		result["message"] = check["message"]
		return result

	# A half-written cache from an interrupted run must not be mistaken for a
	# good one, so the old directory goes before the new one is built and the
	# manifest is only marked complete at the very end.
	RomCache.clear(directory)
	if not RomCache.prepare(directory):
		result["message"] = "Could not create %s." % directory
		return result

	var species: Array = _import_species(rom, layout, on_progress)
	if species.is_empty():
		result["message"] = "Decoded no species."
		return result

	var pics: Dictionary = _import_pics(rom, layout, species, on_progress)
	if pics.is_empty():
		result["message"] = "Could not decode pics."
		return result

	var tiles: Dictionary = _import_tiles(rom, layout, on_progress)
	if tiles.is_empty():
		result["message"] = "Could not write the font."
		return result

	var moves: Array = _import_moves(rom, layout, on_progress)
	var items: Array = _import_items(rom, layout, on_progress)
	var trades: Array = _import_world_trades(rom, layout)
	var types: Array = _import_types(rom, layout, on_progress)
	var matchups: Array = read_matchups(rom, layout)
	var trainers: Array = _import_trainers(rom, layout, on_progress)
	var world: Dictionary = Gen2WorldImporter.import_to_cache(rom, layout, directory, on_progress)
	if not bool(world.get("ok", false)):
		result["message"] = String(world.get("message", "Could not import overworld data."))
		return result
	var encounters: Dictionary = Gen2WorldEncounterImporter.import_to_cache(rom, layout, directory)
	if not bool(encounters.get("ok", false)):
		result["message"] = String(encounters.get("message", "Could not import wild encounter data."))
		return result
	var services: Dictionary = Gen2WorldServicesImporter.import_to_cache(
		rom, layout, directory,
		world.get("scripts", {}), world.get("standard_scripts", {}),
		world.get("text", {}), world.get("movements", {})
	)
	if not bool(services.get("ok", false)):
		result["message"] = String(services.get("message", "Could not import world service data."))
		return result

	if not RomCache.write_json(RomCache.species_path(directory), species):
		result["message"] = "Could not write species data."
		return result
	if not RomCache.write_json(RomCache.moves_path(directory), moves):
		result["message"] = "Could not write move data."
		return result
	if not RomCache.write_json(RomCache.items_path(directory), items):
		result["message"] = "Could not write item data."
		return result
	if not RomCache.write_json(RomCache.world_trades_path(directory), trades):
		result["message"] = "Could not write world trade data."
		return result
	if not RomCache.write_json(RomCache.types_path(directory), types):
		result["message"] = "Could not write type data."
		return result
	if not RomCache.write_json(RomCache.matchups_path(directory), matchups):
		result["message"] = "Could not write the type matchup chart."
		return result
	if not RomCache.write_json(RomCache.trainers_path(directory), trainers):
		result["message"] = "Could not write trainer data."
		return result

	var evolutions: int = _count_in(species, "evolutions")
	var learnset_moves: int = _count_in(species, "learnset")
	var trainer_party_count: int = _count_in(trainers, "trainers")

	var manifest: Dictionary = {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": String(rom.id),
		"sha1": rom.sha1,
		"species_count": species.size(),
		"evolution_count": evolutions,
		"learnset_move_count": learnset_moves,
		"move_count": moves.size(),
		"item_count": items.size(),
		"world_trade_count": trades.size(),
		"type_count": types.size(),
		"matchup_count": matchups.size(),
		"trainer_count": trainers.size(),
		"trainer_party_count": trainer_party_count,
		"world_map_count": int(world["maps"]),
		"world_tileset_count": int(world["tilesets"]),
		"world_grass_encounter_count": int(encounters["grass"]),
		"world_water_encounter_count": int(encounters["water"]),
		"world_swarm_grass_encounter_count": int(encounters["swarm_grass"]),
		"world_swarm_water_encounter_count": int(encounters["swarm_water"]),
		"world_fishing_group_count": int(encounters["fish_groups"]),
		"world_roam_map_count": int(encounters["roam_maps"]),
		"overworld_sprite_count": int(world["overworld_sprites"]),
		"world_menu_count": int(services["menus"]),
		"world_mart_count": int(services["marts"]),
		"world_phone_contact_count": int(services["phone_contacts"]),
		"world_special_phone_call_count": int(services["special_phone_calls"]),
		"world_phone_script_count": int(services["phone_scripts"]),
		"world_music_count": int(services["music"]),
		"world_sfx_count": int(services["sfx"]),
		"bar_palettes": _import_bar_palettes(rom, layout),
		"atlases": pics,
		"tiles": tiles,
		"complete": true,
	}
	if not RomCache.write_json(RomCache.manifest_path(directory), manifest):
		result["message"] = "Could not write manifest."
		return result

	result["ok"] = true
	result["species"] = species.size()
	result["moves"] = moves.size()
	result["items"] = items.size()
	result["types"] = types.size()
	result["matchups"] = matchups.size()
	result["trainers"] = trainers.size()
	result["trainer_party_count"] = trainer_party_count
	result["maps"] = int(world["maps"])
	result["tilesets"] = int(world["tilesets"])
	result["grass_encounters"] = int(encounters["grass"])
	result["water_encounters"] = int(encounters["water"])
	result["swarm_grass_encounters"] = int(encounters["swarm_grass"])
	result["swarm_water_encounters"] = int(encounters["swarm_water"])
	result["fishing_groups"] = int(encounters["fish_groups"])
	result["roam_maps"] = int(encounters["roam_maps"])
	result["overworld_sprites"] = int(world["overworld_sprites"])
	result["menus"] = int(services["menus"])
	result["marts"] = int(services["marts"])
	result["phone_contacts"] = int(services["phone_contacts"])
	result["special_phone_calls"] = int(services["special_phone_calls"])
	result["phone_scripts"] = int(services["phone_scripts"])
	result["music"] = int(services["music"])
	result["sfx"] = int(services["sfx"])
	result["evolutions"] = evolutions
	result["learnset_moves"] = learnset_moves
	result["elapsed_ms"] = Time.get_ticks_msec() - started
	result["message"] = ("Imported %d species, %d moves, %d items, %d type matchups, "
		+ "%d trainer classes carrying %d trainers, %d maps, %d tilesets, %d grass encounter maps, "
		+ "%d water encounter maps, %d swarm grass maps, %d swarm water maps, "
		+ "%d fishing groups, %d roaming maps and %d overworld sprites, "
		+ "%d menus, %d marts, %d phone contacts, %d phone script resources, "
		+ "%d music tracks and %d sound effects, "
		+ "%d evolutions and %d level-up moves in %d ms.") % [
		species.size(), moves.size(), items.size(), matchups.size(), trainers.size(),
		trainer_party_count, int(world["maps"]), int(world["tilesets"]),
		int(encounters["grass"]), int(encounters["water"]),
		int(encounters["swarm_grass"]), int(encounters["swarm_water"]),
		int(encounters["fish_groups"]), int(encounters["roam_maps"]),
		int(world["overworld_sprites"]),
		int(services["menus"]), int(services["marts"]), int(services["phone_contacts"]),
		int(services["phone_scripts"]),
		int(services["music"]), int(services["sfx"]),
		evolutions, learnset_moves, result["elapsed_ms"],
	]
	return result


## Rows of one list across every species, for the manifest's counts.
static func _count_in(species: Array, key: String) -> int:
	var out: int = 0
	for entry: Dictionary in species:
		out += (entry[key] as Array).size()
	return out


func _import_species(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var data: PackedByteArray = rom.bytes()
	var out: Array = []

	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var stats: int = RomLayout.base_stats_offset(layout, species)
		var dimensions: int = rom.u8(stats + RomLayout.OFFSET_PIC_SIZE)
		var egg_groups: int = rom.u8(stats + RomLayout.OFFSET_EGG_GROUPS)
		var palette: int = RomLayout.palette_offset(layout, species)
		var evos_attacks: Dictionary = read_evos_attacks(rom, layout, species)

		out.append({
			"number": species,
			"name": Gen2Text.decode(
				data, RomLayout.species_name_offset(layout, species), RomLayout.NAME_LENGTH
			),
			"stats": {
				"hp": rom.u8(stats + RomLayout.STAT_HP),
				"attack": rom.u8(stats + RomLayout.STAT_ATTACK),
				"defense": rom.u8(stats + RomLayout.STAT_DEFENSE),
				"speed": rom.u8(stats + RomLayout.STAT_SPEED),
				"sp_attack": rom.u8(stats + RomLayout.STAT_SP_ATTACK),
				"sp_defense": rom.u8(stats + RomLayout.STAT_SP_DEFENSE),
			},
			"types": [
				rom.u8(stats + RomLayout.OFFSET_TYPE1),
				rom.u8(stats + RomLayout.OFFSET_TYPE2),
			],
			"catch_rate": rom.u8(stats + RomLayout.OFFSET_CATCH_RATE),
			"base_exp": rom.u8(stats + RomLayout.OFFSET_BASE_EXP),
			"held_items": [
				rom.u8(stats + RomLayout.OFFSET_ITEM1),
				rom.u8(stats + RomLayout.OFFSET_ITEM2),
			],
			"gender_ratio": rom.u8(stats + RomLayout.OFFSET_GENDER_RATIO),
			"hatch_cycles": rom.u8(stats + RomLayout.OFFSET_HATCH_CYCLES),
			"growth_rate": rom.u8(stats + RomLayout.OFFSET_GROWTH_RATE),
			"egg_groups": [egg_groups >> 4, egg_groups & 0x0F],
			"tmhm": Array(rom.slice(stats + RomLayout.OFFSET_TMHM, RomLayout.TMHM_BYTES)),
			# Both halves of one table, which is why they arrive together and are
			# stored on the species rather than in tables of their own.
			"evolutions": evos_attacks.get("evolutions", []),
			"learnset": evos_attacks.get("learnset", []),
			"front_tiles": [dimensions & 0x0F, dimensions >> 4],
			"palette": {
				"normal": [rom.u16le(palette), rom.u16le(palette + 2)],
				"shiny": [rom.u16le(palette + 4), rom.u16le(palette + 6)],
			},
		})

		if on_progress.is_valid():
			on_progress.call("species", species, RomLayout.SPECIES_COUNT)

	return out


func _import_moves(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["move_names"]), RomLayout.MOVE_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	var out: Array = []

	for move: int in range(1, RomLayout.MOVE_COUNT + 1):
		var entry: int = RomLayout.move_data_offset(layout, move)
		# The animation byte is dropped: it is the move's own number, and it is
		# already spent proving the table is where the layout says it is.
		out.append({
			"number": move,
			"name": names[move - 1],
			"effect": rom.u8(entry + RomLayout.MOVE_EFFECT),
			"power": rom.u8(entry + RomLayout.MOVE_POWER),
			"type": rom.u8(entry + RomLayout.MOVE_TYPE),
			"accuracy": rom.u8(entry + RomLayout.MOVE_ACCURACY),
			"pp": rom.u8(entry + RomLayout.MOVE_PP),
			"effect_chance": rom.u8(entry + RomLayout.MOVE_EFFECT_CHANCE),
		})

		if on_progress.is_valid():
			on_progress.call("moves", move, RomLayout.MOVE_COUNT)

	return out


func _import_items(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["item_names"]), RomLayout.ITEM_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	var out: Array = []
	var status_masks: Dictionary = _read_item_status_masks(rom, layout)
	var healing_amounts: Dictionary = _read_item_healing_amounts(rom, layout)

	for item: int in range(1, RomLayout.ITEM_COUNT + 1):
		var at: int = int(layout["item_attributes"]) + (item - 1) * RomLayout.ITEM_ATTRIBUTE_SIZE
		var packed_menu: int = rom.u8(at + RomLayout.ITEM_ATTRIBUTE_HELP)
		var parameter: int = rom.u8(at + RomLayout.ITEM_ATTRIBUTE_PARAM)
		if parameter == 0xFF:
			parameter = -1
		var entry: Dictionary = {
			"number": item,
			"name": names[item - 1],
			"price": rom.u16le(at),
			"effect": rom.u8(at + 2),
			"parameter": parameter,
			"permissions": rom.u8(at + RomLayout.ITEM_ATTRIBUTE_PERMISSIONS),
			"pocket": rom.u8(at + RomLayout.ITEM_ATTRIBUTE_POCKET),
			"field_menu": packed_menu >> 4,
			"battle_menu": packed_menu & 0x0F,
		}
		if status_masks.has(item):
			entry["status_mask"] = int(status_masks[item])
		if healing_amounts.has(item):
			entry["heal_amount"] = int(healing_amounts[item])
		out.append(entry)
		if on_progress.is_valid():
			on_progress.call("items", item, RomLayout.ITEM_COUNT)

	return out


static func verify_item_metadata(rom: RomFile, layout: Dictionary) -> Dictionary:
	var attributes: int = int(layout.get("item_attributes", -1))
	if not rom.in_bounds(attributes, RomLayout.ITEM_COUNT * RomLayout.ITEM_ATTRIBUTE_SIZE):
		return {"ok": false, "message": "Item attribute table is outside the ROM."}
	if rom.u8(attributes + RomLayout.ITEM_ATTRIBUTE_POCKET) != RomLayout.ITEM_POCKET_BALL:
		return {"ok": false, "message": "Master Ball is not in the cartridge ball pocket."}
	var poke_ball: int = attributes + 4 * RomLayout.ITEM_ATTRIBUTE_SIZE
	if rom.u8(poke_ball + RomLayout.ITEM_ATTRIBUTE_POCKET) != RomLayout.ITEM_POCKET_BALL:
		return {"ok": false, "message": "Poke Ball is not in the cartridge ball pocket."}
	var status_at: int = int(layout.get("item_status_actions", -1))
	var status_found: bool = false
	for index: int in 32:
		if rom.u8(status_at + index * 3) == 0xFF:
			status_found = true
			break
	if not status_found:
		return {"ok": false, "message": "Status-healing item table has no terminator."}
	var healing_at: int = int(layout.get("item_healing_hp", -1))
	var healing_found: bool = false
	for index: int in 32:
		if rom.u8(healing_at + index * 3) == 0xFF:
			healing_found = true
			break
	if not healing_found:
		return {"ok": false, "message": "HP-healing item table has no terminator."}
	return {"ok": true, "message": ""}


static func verify_world_trades(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = int(layout.get("world_trade_count", 0))
	var at: int = int(layout.get("world_trades", -1))
	if count <= 0 or not rom.in_bounds(at, count * RomLayout.TRADE_RECORD_SIZE):
		return {"ok": false, "message": "NPC trade table is outside the ROM."}
	for index: int in count:
		var row: int = at + index * RomLayout.TRADE_RECORD_SIZE
		if rom.u8(row + 1) <= 0 or rom.u8(row + 1) > RomLayout.SPECIES_COUNT \
			or rom.u8(row + 2) <= 0 or rom.u8(row + 2) > RomLayout.SPECIES_COUNT:
			return {"ok": false, "message": "NPC trade %d has an invalid species." % index}
		if rom.u8(row + 30) > RomLayout.TRADE_GENDER_FEMALE or rom.u8(row + 31) != 0:
			return {"ok": false, "message": "NPC trade %d has an invalid record tail." % index}
	return {"ok": true, "message": ""}


static func _read_item_status_masks(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var at: int = int(layout["item_status_actions"])
	for index: int in 32:
		var item: int = rom.u8(at)
		if item == 0xFF:
			break
		if item <= 0 or item > RomLayout.ITEM_COUNT:
			break
		out[item] = rom.u8(at + 2)
		at += 3
	return out


static func _read_item_healing_amounts(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var at: int = int(layout["item_healing_hp"])
	for index: int in 32:
		var item: int = rom.u8(at)
		if item == 0xFF:
			break
		if item <= 0 or item > RomLayout.ITEM_COUNT:
			break
		out[item] = rom.u16le(at + 1)
		at += 3
	return out


static func _import_world_trades(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	var count: int = int(layout["world_trade_count"])
	var at: int = int(layout["world_trades"])
	for index: int in count:
		var row: int = at + index * RomLayout.TRADE_RECORD_SIZE
		out.append({
			"trade_id": index,
			"dialog": rom.u8(row),
			"requested_species": rom.u8(row + 1),
			"offered_species": rom.u8(row + 2),
			"nickname": Gen2Text.decode_fixed(
				rom.bytes(), row + 3, RomLayout.TRADE_NAME_LENGTH
			),
			"dvs": (rom.u8(row + 14) << 8) | rom.u8(row + 15),
			"item": rom.u8(row + 16),
			"ot_id": rom.u16le(row + 17),
			"ot_name": Gen2Text.decode_fixed(
				rom.bytes(), row + 19, RomLayout.TRADE_NAME_LENGTH
			),
			"gender": rom.u8(row + 30),
		})
	return out


func _import_types(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var out: Array = []

	for type_number: int in RomLayout.TYPE_COUNT:
		out.append({"number": type_number, "name": type_name(rom, layout, type_number)})
		if on_progress.is_valid():
			on_progress.call("types", type_number + 1, RomLayout.TYPE_COUNT)

	return out


## Decodes the trainer classes: a name and the two colours the class is drawn in.
##
## A class has one palette and no shiny counterpart, so the pair is stored flat
## rather than under a key, and the pic is found by class number in the trainer
## atlas the way a species' is in the front one.
## Decodes the trainer classes and, behind them, the trainer party table (who
## carries what), the trainer attributes table (how the class's AI plays it)
## and the trainer DVs table (how good its Pokémon's stats are). The four are
## kept on the one entry rather than split into cache files of their own, the
## way a species' evolutions and learnset are, because a class name, its
## trainers, its own AI behaviour and its own DVs are four tables one class
## number addresses, not four separate questions.
func _import_trainers(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var count: int = RomLayout.trainer_class_count(layout)
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["trainer_class_names"]), count, RomLayout.MAX_NAME_LENGTH
	)
	var parties: Dictionary = RomImporter.read_trainer_parties(rom, layout)
	var classes: Array = parties["classes"] if parties["ok"] else []
	var out: Array = []

	for trainer_class: int in range(1, count + 1):
		var palette: int = RomLayout.trainer_palette_offset(layout, trainer_class)
		out.append({
			"number": trainer_class,
			"name": names[trainer_class - 1],
			"palette": [rom.u16le(palette), rom.u16le(palette + Gen2Palette.COLOR_BYTES)],
			"trainers": classes[trainer_class - 1] if trainer_class - 1 < classes.size() else [],
			"attributes": RomImporter.read_trainer_attributes(rom, layout, trainer_class),
			"dvs": RomImporter.read_trainer_dvs(rom, layout, trainer_class),
		})

		if on_progress.is_valid():
			on_progress.call("trainers", trainer_class, count)

	return out


## The four colours a battle draws its bars in. Small enough to live in the
## manifest beside the atlas metadata rather than in a file of its own.
func _import_bar_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for index: int in RomLayout.BAR_PALETTE_NAMES.size():
		var entry: int = RomLayout.bar_palette_offset(layout, index)
		out[RomLayout.BAR_PALETTE_NAMES[index]] = [
			rom.u16le(entry), rom.u16le(entry + Gen2Palette.COLOR_BYTES),
		]
	return out


## Decodes the fixed tile sheets: the font, the eight text box borders and the
## battle HUD's graphics, each as one strip of tiles.
##
## None of them is compressed and none is per-species, so unlike a pic there is
## nothing to look up: each is a fixed run of tiles at a known place. They are
## kept as strips because each is addressed by a number, whether a character code
## or a tile in a bar, and a strip turns that number into a horizontal offset and
## nothing else.
##
## [code]first_code[/code] is the character code a sheet's first tile draws, and
## is zero for the sheets that are graphics rather than characters. [code]bits[/code]
## is how the cartridge stores them: the font and the borders are 1bpp, the
## battle graphics 2bpp.
func _import_tiles(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Dictionary:
	var data: PackedByteArray = rom.bytes()
	var sheets: Dictionary = {
		"font": {
			"offset": RomLayout.font_offset(layout),
			"tiles": RomLayout.FONT_TILES,
			"first_code": RomLayout.FONT_FIRST_CODE,
			"bits": 1,
		},
		"frames": {
			"offset": RomLayout.frame_offset(layout, 0),
			"tiles": RomLayout.FRAME_COUNT * RomLayout.FRAME_TILES,
			"first_code": RomLayout.FRAME_FIRST_CODE,
			"bits": 1,
		},
		"battle_font": {
			"offset": int(layout["battle_font"]),
			"tiles": RomLayout.BATTLE_FONT_TILES,
			"first_code": 0,
			"bits": 2,
		},
		"enemy_hud": {
			"offset": int(layout["enemy_hud"]),
			"tiles": RomLayout.ENEMY_HUD_TILES,
			"first_code": 0,
			"bits": 1,
		},
		"player_hud": {
			"offset": int(layout["player_hud"]),
			"tiles": RomLayout.PLAYER_HUD_TILES,
			"first_code": 0,
			"bits": 1,
		},
		"exp_bar": {
			"offset": int(layout["exp_bar"]),
			"tiles": RomLayout.EXP_BAR_TILES,
			"first_code": 0,
			"bits": 2,
		},
	}

	var written: Dictionary = {}
	var done: int = 0
	for name: String in sheets:
		var sheet: Dictionary = sheets[name]
		var count: int = sheet["tiles"]
		var indices: PackedByteArray = _decode_strip(data, sheet)
		var directory: String = RomCache.directory_for(rom.id, rom.sha1)
		if not RomCache.write_indices(RomCache.tile_path(directory, name), indices):
			return {}
		written[name] = {
			"width": count * Gen2Tiles.TILE_WIDTH,
			"height": Gen2Tiles.TILE_HEIGHT,
			"tiles": count,
			"first_code": sheet["first_code"],
			"bits": sheet["bits"],
		}

		done += 1
		if on_progress.is_valid():
			on_progress.call("tiles", done, sheets.size())

	return written


static func _decode_strip(data: PackedByteArray, sheet: Dictionary) -> PackedByteArray:
	if int(sheet["bits"]) == 1:
		return Gen2Tiles.decode_1bpp_strip(data, int(sheet["offset"]), int(sheet["tiles"]))
	return Gen2Tiles.decode_2bpp_strip(data, int(sheet["offset"]), int(sheet["tiles"]))


func _import_pics(
	rom: RomFile, layout: Dictionary, species: Array, on_progress: Callable
) -> Dictionary:
	var front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.SPECIES_COUNT)
	var back: Dictionary = _new_atlas(RomLayout.BACKPIC_TILES, RomLayout.SPECIES_COUNT)
	var unown_front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.UNOWN_FORMS)
	var unown_back: Dictionary = _new_atlas(RomLayout.BACKPIC_TILES, RomLayout.UNOWN_FORMS)
	var trainer_classes: int = RomLayout.trainer_class_count(layout)
	var trainers: Dictionary = _new_atlas(RomLayout.TRAINER_PIC_TILES, trainer_classes)

	for entry: Dictionary in species:
		var number: int = entry["number"]
		var tiles: Array = entry["front_tiles"]
		var slot: int = number - 1

		# Unown's main-table entry is a placeholder. Its forms are decoded into
		# their own atlas, and the species slot gets form A so a caller that
		# does not know about forms still gets a sprite rather than a hole.
		var source: int = number
		if number == RomLayout.UNOWN_SPECIES:
			for form: int in RomLayout.UNOWN_FORMS:
				_decode_into(
					rom, layout, RomLayout.unown_pic_pointer_offset(layout, form, false),
					tiles[0], tiles[1], unown_front, form
				)
				_decode_into(
					rom, layout, RomLayout.unown_pic_pointer_offset(layout, form, true),
					RomLayout.BACKPIC_TILES, RomLayout.BACKPIC_TILES, unown_back, form
				)
			_decode_into(
				rom, layout, RomLayout.unown_pic_pointer_offset(layout, 0, false),
				tiles[0], tiles[1], front, slot
			)
			_decode_into(
				rom, layout, RomLayout.unown_pic_pointer_offset(layout, 0, true),
				RomLayout.BACKPIC_TILES, RomLayout.BACKPIC_TILES, back, slot
			)
		else:
			_decode_into(
				rom, layout, RomLayout.pic_pointer_offset(layout, source, false),
				tiles[0], tiles[1], front, slot
			)
			_decode_into(
				rom, layout, RomLayout.pic_pointer_offset(layout, source, true),
				RomLayout.BACKPIC_TILES, RomLayout.BACKPIC_TILES, back, slot
			)

		if on_progress.is_valid():
			on_progress.call("pics", number, RomLayout.SPECIES_COUNT)

	# Trainer pics share the pointer form and the bank repair, and differ in that
	# every one of them is the same square and none of them has a back half.
	for trainer_class: int in range(1, trainer_classes + 1):
		_decode_into(
			rom, layout, RomLayout.trainer_pic_pointer_offset(layout, trainer_class),
			RomLayout.TRAINER_PIC_TILES, RomLayout.TRAINER_PIC_TILES, trainers, trainer_class - 1
		)

		if on_progress.is_valid():
			on_progress.call("trainer pics", trainer_class, trainer_classes)

	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var atlases: Dictionary = {
		"front": front, "back": back, "unown_front": unown_front, "unown_back": unown_back,
		"trainers": trainers,
	}
	var written: Dictionary = {}
	for name: String in atlases:
		var atlas: Dictionary = atlases[name]
		if not RomCache.write_indices(RomCache.pic_path(directory, name), atlas["pixels"]):
			return {}
		written[name] = {
			"width": atlas["width"],
			"height": atlas["height"],
			"cell": atlas["cell"],
			"columns": ATLAS_COLUMNS,
			"decoded": atlas["decoded"],
		}
	return written


func _new_atlas(cell_tiles: int, cells: int) -> Dictionary:
	var cell: int = cell_tiles * Gen2Tiles.TILE_WIDTH
	var rows: int = ceili(float(cells) / ATLAS_COLUMNS)
	var width: int = ATLAS_COLUMNS * cell
	var height: int = rows * cell
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(width * height)
	return {
		"pixels": pixels, "width": width, "height": height, "cell": cell, "decoded": 0,
	}


func _decode_into(
	rom: RomFile,
	layout: Dictionary,
	pointer_offset: int,
	columns: int,
	rows: int,
	atlas: Dictionary,
	slot: int
) -> bool:
	if columns <= 0 or rows <= 0:
		return false

	var pointer: Dictionary = rom.far_pointer(pointer_offset)
	var bank: int = RomLayout.fix_pic_bank(layout, pointer["bank"])
	var start: int = RomFile.linear(bank, pointer["address"])
	if not rom.in_bounds(start):
		return false

	var raw: PackedByteArray = _lz.decompress(rom.bytes(), start)
	if _lz.failed or raw.size() < columns * rows * Gen2Tiles.TILE_BYTES:
		return false

	var pixels: PackedByteArray = Gen2Tiles.decode_pic(raw, columns, rows)
	var cell: int = atlas["cell"]
	Gen2Tiles.blit(
		pixels, columns * Gen2Tiles.TILE_WIDTH,
		atlas["pixels"], atlas["width"],
		(slot % ATLAS_COLUMNS) * cell, floori(float(slot) / float(ATLAS_COLUMNS)) * cell
	)
	atlas["decoded"] = int(atlas["decoded"]) + 1
	return true
