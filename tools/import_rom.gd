extends SceneTree

## Imports a cartridge into the user:// cache, headlessly.
##
##   Godot --headless --path . -s res://tools/import_rom.gd -- [file-or-dir ...]
##
## Defaults to res://roms. Exits 0 only if every candidate imported. Add
## --verify to stop after the layout check without writing a cache.

const DEFAULT_DIR: String = "res://roms"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var verify_only: bool = args.has("--verify")

	var inputs: PackedStringArray = []
	for arg: String in args:
		if not arg.begins_with("--"):
			inputs.append(arg)
	if inputs.is_empty():
		inputs = PackedStringArray([DEFAULT_DIR])

	var paths: PackedStringArray = []
	for raw: String in inputs:
		var path: String = raw if raw.contains("://") or raw.begins_with("/") else "res://" + raw
		if DirAccess.dir_exists_absolute(path):
			paths.append_array(_roms_in(path))
		else:
			paths.append(path)

	if paths.is_empty():
		push_error("No candidate files found.")
		quit(1)
		return

	var failures: int = 0
	for path: String in paths:
		if not _handle(path, verify_only):
			failures += 1

	print("\n%d/%d %s." % [
		paths.size() - failures, paths.size(), "verified" if verify_only else "imported",
	])
	quit(1 if failures > 0 else 0)


func _handle(path: String, verify_only: bool) -> bool:
	var identity: Dictionary = RomVerifier.identify(path)
	if identity["status"] != RomVerifier.Status.OK:
		print("FAIL  %s\n    %s" % [path.get_file(), identity["message"]])
		return false

	var rom: RomFile = RomFile.open_verified(path)
	if rom == null:
		print("FAIL  %s\n    Could not read the file." % path.get_file())
		return false

	var header: RomHeader = RomHeader.parse(rom)
	print("\n%s  %s" % [path.get_file(), identity["message"]])
	print("    %s" % header.describe())
	print("    header checksum %s" % (
		"ok" if header.header_checksum == RomHeader.compute_header_checksum(rom) else "MISMATCH"
	))

	var check: Dictionary = RomImporter.verify_layout(rom)
	print("    layout: %s" % check["message"])
	if not check["ok"]:
		return false
	if verify_only:
		return true

	var importer := RomImporter.new()
	var result: Dictionary = importer.import_rom(rom, _report)
	print("    %s" % result["message"])
	if result["ok"]:
		print("    cache: %s" % ProjectSettings.globalize_path(result["directory"]))
	return result["ok"]


func _report(stage: String, done: int, total: int) -> void:
	if done == total:
		print("    %s: %d/%d" % [stage, done, total])


func _roms_in(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension().to_lower() in ["gb", "gbc"]:
			out.append("%s/%s" % [dir_path, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
