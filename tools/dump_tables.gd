extends SceneTree

## Prints the decoded text tables out of the cache, headlessly.
##
##   Godot --headless --path . -s res://tools/dump_tables.gd -- <game> [table]
##
## The written counterpart of the contact sheet: a bad offset in a name table
## produces plausible words rather than an error, so the check is reading the
## output. <game> is a registry id; [table] is species, moves, items, types,
## matchups, trainers, learnsets, evolutions or all.

const TABLES: PackedStringArray = [
	"species", "moves", "items", "types", "matchups", "trainers", "learnsets",
	"evolutions", "growth",
]

## Which file a table is read out of, where it is not a file of its own.
## Evolutions, level-up moves and growth rate/base exp are all read off the
## species entry itself, so they are views of species.json rather than files
## of their own.
const SOURCES: Dictionary = {
	"learnsets": RomCache.SPECIES,
	"evolutions": RomCache.SPECIES,
	"growth": RomCache.SPECIES,
}

## The six growth curves, in the cartridge's own byte order (GROWTH_MEDIUM_FAST
## through GROWTH_SLOW). Only four are ever used by a real species in any of the
## three games; the other two are named for completeness, not because a species
## exercises them.
const GROWTH_NAMES: PackedStringArray = [
	"medium fast", "slightly fast", "slightly slow", "medium slow", "fast", "slow",
]

## How an evolution method is written out. The parameter that follows it means
## something different in each case, which is the point of naming them here.
const EVOLVE_NAMES: Dictionary = {
	RomLayout.EVOLVE_LEVEL: "level",
	RomLayout.EVOLVE_ITEM: "item",
	RomLayout.EVOLVE_TRADE: "trade",
	RomLayout.EVOLVE_HAPPINESS: "happiness",
	RomLayout.EVOLVE_STAT: "level",
}

const TRIGGER_NAMES: Dictionary = {
	RomLayout.TRIGGER_ANYTIME: "any time",
	RomLayout.TRIGGER_MORNDAY: "morning or day",
	RomLayout.TRIGGER_NITE: "night",
}

const CONDITION_NAMES: Dictionary = {
	RomLayout.ATTACK_OVER_DEFENSE: "attack over defense",
	RomLayout.ATTACK_UNDER_DEFENSE: "attack under defense",
	RomLayout.ATTACK_EQUALS_DEFENSE: "attack equals defense",
}

## Which of a move's scoring routines a class's AI move weight word turns on.
const AI_MOVE_FLAG_NAMES: Dictionary = {
	RomLayout.AI_BASIC: "basic",
	RomLayout.AI_SETUP: "setup",
	RomLayout.AI_TYPES: "types",
	RomLayout.AI_OFFENSIVE: "offensive",
	RomLayout.AI_SMART: "smart",
	RomLayout.AI_OPPORTUNIST: "opportunist",
	RomLayout.AI_AGGRESSIVE: "aggressive",
	RomLayout.AI_CAUTIOUS: "cautious",
	RomLayout.AI_STATUS: "status",
	RomLayout.AI_RISKY: "risky",
}

## How a class's item/switch word decides what its trainers do with a held item
## and when they switch out.
const AI_SWITCH_FLAG_NAMES: Dictionary = {
	RomLayout.SWITCH_OFTEN: "switch often",
	RomLayout.SWITCH_RARELY: "switch rarely",
	RomLayout.SWITCH_SOMETIMES: "switch sometimes",
	RomLayout.ALWAYS_USE: "always use item",
	RomLayout.UNKNOWN_USE: "unknown use",
	RomLayout.CONTEXT_USE: "context use",
}

## How a multiplier is drawn in the matchup grid. Symbols rather than numbers so
## that a column stays narrow enough for all seventeen types to fit on a line,
## and so that a wrong chart looks wrong at a glance instead of having to be read.
const MATCHUP_SYMBOLS: Dictionary = {
	RomLayout.MATCHUP_NO_EFFECT: "0",
	RomLayout.MATCHUP_NOT_VERY_EFFECTIVE: "-",
	RomLayout.MATCHUP_EFFECTIVE: ".",
	RomLayout.MATCHUP_SUPER_EFFECTIVE: "+",
}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("Usage: dump_tables.gd -- <%s> [%s|all]" % [
			"|".join(RomRegistry.ORDER), "|".join(TABLES),
		])
		quit(1)
		return

	var id: StringName = StringName(args[0])
	var wanted: String = args[1] if args.size() > 1 else "all"

	var directory: String = _cache_for(id)
	if directory.is_empty():
		push_error("No cache for %s. Run tools/import_rom.gd first." % id)
		quit(1)
		return

	print("%s  %s" % [id, ProjectSettings.globalize_path(directory)])
	for table: String in TABLES:
		if wanted == "all" or wanted == table:
			_dump(directory, table)
	quit(0)


## The cache directory is keyed by hash as well as game, so it is found by
## listing rather than built from an id.
func _cache_for(id: StringName) -> String:
	var dir: DirAccess = DirAccess.open(RomCache.ROOT)
	if dir == null:
		return ""
	for name: String in dir.get_directories():
		if name.begins_with("%s_" % id):
			return "%s/%s" % [RomCache.ROOT, name]
	return ""


func _dump(directory: String, table: String) -> void:
	var path: String = "%s/%s" % [directory, SOURCES.get(table, "%s.json" % table)]
	var rows: Variant = RomCache.read_json(path)
	if not rows is Array:
		print("\n%s: missing" % table)
		return

	match table:
		"matchups":
			print("\n%s (%d)" % [table, (rows as Array).size()])
			_dump_matchups(directory, rows)
		"trainers":
			_dump_trainers(directory, rows)
		"learnsets":
			_dump_learnsets(directory, rows)
		"evolutions":
			_dump_evolutions(directory, rows)
		"growth":
			_dump_growth(rows)
		_:
			print("\n%s (%d)" % [table, (rows as Array).size()])
			for row: Dictionary in rows:
				print("  %s" % _describe(table, row))


## Every species' level-up moves, in the cartridge's order rather than sorted.
##
## Reading them is the check the runtime one cannot be: the levels and move
## numbers are in range whatever a wrong offset does, but a learnset that reads
## Tackle at 1 and Growl at 4 for Bulbasaur is right and one that does not is not.
## The order is worth reading too, since it decides what a fresh Pokémon knows.
func _dump_learnsets(directory: String, rows: Array) -> void:
	var moves: Array = _names_in(RomCache.moves_path(directory))
	var total: int = 0

	print("\nlearnsets (%d species)" % rows.size())
	for row: Dictionary in rows:
		var learnset: Array = row.get("learnset", [])
		total += learnset.size()
		var parts: PackedStringArray = []
		for entry: Dictionary in learnset:
			parts.append("%d %s" % [int(entry["level"]), _name_at(moves, int(entry["move"]))])
		print("  %3d  %-11s %s" % [int(row["number"]), String(row["name"]), ", ".join(parts)])
	print("  %d level-up moves" % total)


## Every species' growth rate and base experience yield, the two fields
## [Gen2Experience] needs and nothing else reads. Neither has a self-checking
## shape (a growth rate byte 0-5 and a base exp byte are both plausible
## whatever the offset is), so what settles them is reading a name against a
## curve published independently: Bulbasaur medium slow, Caterpie medium fast,
## Chansey fast, Mewtwo slow.
func _dump_growth(rows: Array) -> void:
	print("\ngrowth (%d species)" % rows.size())
	for row: Dictionary in rows:
		var rate: int = int(row.get("growth_rate", -1))
		var rate_name: String = GROWTH_NAMES[rate] if rate >= 0 and rate < GROWTH_NAMES.size() else "?"
		print("  %3d  %-11s %-13s base exp %3d" % [
			int(row["number"]), String(row["name"]), rate_name, int(row.get("base_exp", 0)),
		])


## Only the species that evolve, which is under half of them. The rest would be
## 130 lines saying nothing, and what is worth reading here is the shape of an
## entry: what the parameter means changes with the method.
func _dump_evolutions(directory: String, rows: Array) -> void:
	var items: Array = _names_in(RomCache.items_path(directory))
	var species: Array = _names_in(RomCache.species_path(directory))
	var total: int = 0

	print("\nevolutions")
	for row: Dictionary in rows:
		var evolutions: Array = row.get("evolutions", [])
		if evolutions.is_empty():
			continue
		total += evolutions.size()
		var parts: PackedStringArray = []
		for evolution: Dictionary in evolutions:
			parts.append(_describe_evolution(evolution, items, species))
		print("  %3d  %-11s %s" % [int(row["number"]), String(row["name"]), "; ".join(parts)])
	print("  %d evolutions" % total)


## Every trainer class, and behind it every individual trainer's own party.
## Reading this is the check the runtime one cannot be: a level, a species and
## a move number are all in range whatever a wrong pointer does, but a group
## that reads Falkner's Pidgey and Pidgeotto, or that leaves the one empty
## class empty, is right and one that does not is not.
func _dump_trainers(directory: String, rows: Array) -> void:
	var species: Array = _names_in(RomCache.species_path(directory))
	var moves: Array = _names_in(RomCache.moves_path(directory))
	var items: Array = _names_in(RomCache.items_path(directory))
	var total: int = 0

	print("\ntrainers (%d classes)" % rows.size())
	for row: Dictionary in rows:
		print("  %s" % _describe("trainers", row))
		print("    %s" % _describe_ai(row.get("attributes", {}), items))
		print("    DVs: %s" % _describe_dvs(int(row.get("dvs", 0))))
		var trainers: Array = row.get("trainers", [])
		total += trainers.size()
		for trainer: Dictionary in trainers:
			var parts: PackedStringArray = []
			for mon: Dictionary in (trainer.get("party", []) as Array):
				parts.append(_describe_trainer_mon(mon, species, moves, items))
			print("    %-13s %s" % [String(trainer["name"]), "; ".join(parts)])

	print("  %d trainers" % total)


## A class's AI: which scoring routines run, how it treats a held item and when
## it switches, and the reward it pays out. Reading this against
## `data/trainers/attributes.asm` is the check the runtime one cannot be: the
## flag words are in range whatever a wrong offset does, but a line that reads
## Falkner as basic, setup, smart, aggressive, cautious, status, risky is right
## and one that does not is not.
func _describe_ai(attributes: Dictionary, items: Array) -> String:
	if attributes.is_empty():
		return "AI: none"

	var move_flags: String = _describe_flags(
		int(attributes.get("ai_move_weights", 0)), AI_MOVE_FLAG_NAMES
	)
	var switch_flags: String = _describe_flags(
		int(attributes.get("ai_item_switch", 0)), AI_SWITCH_FLAG_NAMES
	)
	var held: PackedStringArray = []
	for key: String in ["item1", "item2"]:
		var item: int = int(attributes.get(key, 0))
		if item != 0:
			held.append(_name_at(items, item))

	var line: String = "AI: %s | %s | reward %d" % [
		move_flags, switch_flags, int(attributes.get("base_reward", 0)),
	]
	if not held.is_empty():
		line += " | may use %s" % ", ".join(held)
	return line


## A class's own DVs, unpacked back into the four numbers pret's
## `TrainerClassDVs` lists them as, for reading against that table directly.
func _describe_dvs(dv_word: int) -> String:
	return "%d atk, %d def, %d spd, %d spc" % [
		Gen2Stats.attack_dv(dv_word), Gen2Stats.defense_dv(dv_word),
		Gen2Stats.speed_dv(dv_word), Gen2Stats.special_dv(dv_word),
	]


func _describe_flags(value: int, names: Dictionary) -> String:
	var parts: PackedStringArray = []
	for flag: int in names:
		if value & flag:
			parts.append(String(names[flag]))
	return ", ".join(parts) if not parts.is_empty() else "none"


func _describe_trainer_mon(mon: Dictionary, species: Array, moves: Array, items: Array) -> String:
	var out: String = "%d %s" % [int(mon["level"]), _name_at(species, int(mon["species"]))]

	var item: int = int(mon.get("item", 0))
	if item != 0:
		out += " @ %s" % _name_at(items, item)

	var move_names: PackedStringArray = []
	for move: Variant in (mon.get("moves", []) as Array):
		if int(move) != 0:
			move_names.append(_name_at(moves, int(move)))
	if not move_names.is_empty():
		out += " (%s)" % ", ".join(move_names)

	return out


func _describe_evolution(evolution: Dictionary, items: Array, species: Array) -> String:
	var method: int = int(evolution["method"])
	var parameter: int = int(evolution["parameter"])
	var target: String = _name_at(species, int(evolution["target"]))
	var how: String = String(EVOLVE_NAMES.get(method, "method %d" % method))

	match method:
		RomLayout.EVOLVE_ITEM:
			how += " %s" % _name_at(items, parameter)
		RomLayout.EVOLVE_TRADE:
			# $FF is the trades that need nothing held, which is most of them.
			how += " holding %s" % _name_at(items, parameter) if parameter != 0xFF else ""
		RomLayout.EVOLVE_HAPPINESS:
			how += " %s" % String(TRIGGER_NAMES.get(parameter, "trigger %d" % parameter))
		RomLayout.EVOLVE_STAT:
			how += " %d, %s" % [
				parameter,
				String(CONDITION_NAMES.get(
					int(evolution["condition"]), "condition %d" % int(evolution["condition"])
				)),
			]
		_:
			how += " %d" % parameter

	return "%s -> %s" % [how, target]


## The name column of a cached table, indexed by the number that names a row, so
## that a lookup is arithmetic rather than a search.
func _names_in(path: String) -> Array:
	var rows: Variant = RomCache.read_json(path)
	if not rows is Array:
		return []

	var out: Array = []
	for row: Dictionary in rows as Array:
		var number: int = int(row["number"])
		while out.size() <= number:
			out.append("")
		out[number] = String(row["name"])
	return out


func _name_at(names: Array, number: int) -> String:
	if number < 0 or number >= names.size() or String(names[number]).is_empty():
		return "#%d" % number
	return String(names[number])


## The chart as a grid, attacker down the side and defender across the top.
##
## Nobody checks a list of 110 rows; a grid gets checked, because the published
## table has the same shape and a wrong cell stands out. Only the seventeen real
## types are shown: the padding numbers between the two groups have names but no
## matchups.
func _dump_matchups(directory: String, rows: Array) -> void:
	var names: Array = _type_names(directory)
	var chart: Dictionary = {}
	for row: Dictionary in rows:
		# Every row is in the grid, the flagged ones included: they are matchups
		# that hold until Foresight cancels them, not extras it adds. Which two
		# they are is printed under the grid.
		chart[int(row["attacker"]) * RomLayout.TYPE_COUNT + int(row["defender"])] = \
			int(row["multiplier"])

	var types: Array = []
	for number: int in RomLayout.TYPE_COUNT:
		if RomLayout.is_matchup_type(number) and number < names.size():
			types.append(number)

	var header: String = " ".repeat(10)
	for number: int in types:
		header += "%-4s" % String(names[number]).substr(0, 3)
	print("  %s" % header)

	for attacker: int in types:
		var line: String = "%-10s" % String(names[attacker]).substr(0, 9)
		for defender: int in types:
			var multiplier: int = int(chart.get(
				attacker * RomLayout.TYPE_COUNT + defender, RomLayout.MATCHUP_EFFECTIVE
			))
			line += "%-4s" % String(MATCHUP_SYMBOLS.get(multiplier, "?"))
		print("  %s" % line)

	print("  0 immune, - resisted, . neutral, + super effective")
	for row: Dictionary in rows:
		if bool(row.get("negated_by_foresight", false)):
			print("  cancelled by Foresight: %s against %s" % [
				String(names[int(row["attacker"])]), String(names[int(row["defender"])]),
			])


## The type names out of the same cache, so the grid is labelled with what the
## cartridge calls them rather than with numbers.
func _type_names(directory: String) -> Array:
	var rows: Variant = RomCache.read_json(RomCache.types_path(directory))
	if not rows is Array:
		return []

	var out: Array = []
	for row: Dictionary in rows:
		out.append(String(row["name"]))
	return out


func _describe(table: String, row: Dictionary) -> String:
	var number: int = int(row["number"])
	var name: String = String(row["name"])
	match table:
		"moves":
			return "%3d  %-13s pow %3d  type %2d  acc %3d  pp %2d  effect %3d/%3d" % [
				number, name, int(row["power"]), int(row["type"]), int(row["accuracy"]),
				int(row["pp"]), int(row["effect"]), int(row["effect_chance"]),
			]
		"trainers":
			var palette: Array = row["palette"]
			return "%3d  %-13s $%04X $%04X" % [
				number, name, int(palette[0]), int(palette[1]),
			]
		"species":
			var stats: Dictionary = row["stats"]
			return "%3d  %-11s %3d/%3d/%3d/%3d/%3d/%3d  types %2d %2d" % [
				number, name, int(stats["hp"]), int(stats["attack"]), int(stats["defense"]),
				int(stats["speed"]), int(stats["sp_attack"]), int(stats["sp_defense"]),
				int(row["types"][0]), int(row["types"][1]),
			]
	return "%3d  %s" % [number, name]
