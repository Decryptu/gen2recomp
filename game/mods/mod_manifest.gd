class_name Gen2ModManifest
extends RefCounted

## One mod's declared identity, read from its `mod.json`.
##
## Parsing is separate from loading, so the launcher can list what is installed
## and say why something was refused without running a line of mod code.
##
## [code]api_version[/code] is [Gen2ModHost]'s contract, not the mod's own
## version. A mod built against an older host is refused rather than allowed to
## fail somewhere less obvious.

const FILENAME: String = "mod.json"
## Bumped when the host contract changes in a way an existing mod would notice.
const API_VERSION: int = 1
## Ids address directories and registry keys, so they stay to a plain lowercase
## alphabet. A mod cannot name itself something that escapes its own folder.
const ID_PATTERN: String = "^[a-z0-9][a-z0-9_-]*$"

var id: StringName = &""
var name: String = ""
var version: String = ""
var api_version: int = 0
var entry: String = ""
var description: String = ""
## Absolute path of the directory the manifest was read from.
var directory: String = ""


## Reads and validates the manifest in [param directory].
## Returns { ok, manifest } or { ok: false, reason, detail }.
static func read(directory: String) -> Dictionary:
	var path: String = "%s/%s" % [directory, FILENAME]
	if not FileAccess.file_exists(path):
		return _refuse(&"missing_manifest", path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _refuse(&"unreadable_manifest", path)
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _refuse(&"invalid_manifest", path)
	return from_dictionary(parsed as Dictionary, directory)


## Validates an already-parsed manifest. Split out so a test, and a future pack
## reader, do not need a file on disk.
static func from_dictionary(source: Dictionary, directory: String) -> Dictionary:
	var manifest := Gen2ModManifest.new()
	manifest.directory = directory
	manifest.id = StringName(String(source.get("id", "")))
	manifest.name = String(source.get("name", String(manifest.id)))
	manifest.version = String(source.get("version", ""))
	manifest.api_version = int(source.get("api_version", 0))
	manifest.entry = String(source.get("entry", ""))
	manifest.description = String(source.get("description", ""))

	var regex := RegEx.new()
	regex.compile(ID_PATTERN)
	if regex.search(String(manifest.id)) == null:
		return _refuse(&"invalid_id", String(manifest.id))
	if manifest.api_version != API_VERSION:
		return _refuse(
			&"unsupported_api_version",
			"mod declares %d, host provides %d" % [manifest.api_version, API_VERSION]
		)
	if manifest.entry.is_empty():
		return _refuse(&"missing_entry", String(manifest.id))
	# An entry is a path inside the mod's own directory. Anything that climbs
	# out of it, or reaches for an absolute location, is refused.
	if manifest.entry.begins_with("/") or manifest.entry.contains("..") \
		or manifest.entry.contains(":"):
		return _refuse(&"entry_escapes_mod", manifest.entry)
	if not manifest.entry.ends_with(".gd"):
		# iOS forbids JIT and loading native code at runtime, so a mod is
		# interpreted GDScript or it is nothing.
		return _refuse(&"entry_not_gdscript", manifest.entry)
	return {"ok": true, "manifest": manifest}


func entry_path() -> String:
	return "%s/%s" % [directory, entry]


func summary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"version": version,
		"description": description,
		"directory": directory,
	}


static func _refuse(reason: StringName, detail: String) -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail}
