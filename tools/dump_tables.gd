extends SceneTree

## Prints the decoded text tables out of the cache, headlessly.
##
##   Godot --headless --path . -s res://tools/dump_tables.gd -- <game> [table]
##
## The written-down counterpart of the contact sheet: a bad offset in a name
## table produces plausible words rather than an error, so the check is to read
## the output. <game> is a registry id (gold, silver, crystal); [table] is one of
## species, moves, items, types, matchups, trainers, or all.

const TABLES: PackedStringArray = [
	"species", "moves", "items", "types", "matchups", "trainers",
]

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
	var path: String = "%s/%s.json" % [directory, table]
	var rows: Variant = RomCache.read_json(path)
	if not rows is Array:
		print("\n%s: missing" % table)
		return

	print("\n%s (%d)" % [table, (rows as Array).size()])
	if table == "matchups":
		_dump_matchups(directory, rows)
		return
	for row: Dictionary in rows:
		print("  %s" % _describe(table, row))


## The chart as a grid, attacker down the side and defender across the top.
##
## A list of 110 rows is not something anyone checks; a grid is, because the
## published table has the same shape and a single wrong cell stands out. Only
## the seventeen types that exist are shown: the padding numbers between the two
## groups have names but no matchups, so a column each would be seventeen columns
## of nothing.
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
