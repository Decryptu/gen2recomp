extends SceneTree

## Prints the decoded text tables out of the cache, headlessly.
##
##   Godot --headless --path . -s res://tools/dump_tables.gd -- <game> [table]
##
## The written-down counterpart of the contact sheet: a bad offset in a name
## table produces plausible words rather than an error, so the check is to read
## the output. <game> is a registry id (gold, silver, crystal); [table] is one of
## species, moves, items, types, trainers, or all.

const TABLES: PackedStringArray = ["species", "moves", "items", "types", "trainers"]


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
	for row: Dictionary in rows:
		print("  %s" % _describe(table, row))


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
