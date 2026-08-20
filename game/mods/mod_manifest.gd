class_name Gen2ModManifest
extends RefCounted

## One mod's declared identity, read from its `mod.json`.
##
## Parsing is separate from loading, so the launcher can list what is installed
## and say why something was refused without running a line of mod code.
##
## [code]api_version[/code] is [Gen2ModHost]'s contract, not the mod's own
## version. A mod built against a NEWER host is refused rather than allowed to
## fail somewhere less obvious; one built against an older one still runs, since
## every version so far has only added to the contract.

const FILENAME: String = "mod.json"
## Bumped when the host contract changes in a way an existing mod would notice.
## 2 added [method Gen2ModHost.register_visible_encounters].
## 3 added mart rows and named action axes.
## 4 added types, type matchups and mod-supplied art as content, and
## [method Gen2ModHost.register_event_mutator].
## 5 added [member Gen2WorldAPI.rules], the run's own divergence flags.
const API_VERSION: int = 5
## The oldest contract this host still answers. See [constant API_VERSION].
const MIN_API_VERSION: int = 1
## Ids address directories and registry keys, so they stay to a plain lowercase
## alphabet. A mod cannot name itself something that escapes its own folder.
const ID_PATTERN: String = "^[a-z0-9][a-z0-9_-]*$"

var id: StringName = &""
var name: String = ""
var version: String = ""
var api_version: int = 0
var entry: String = ""
## An optional resource pack beside the manifest, `.pck` or `.zip`, holding the
## mod's own scripts and resources. Its files mount at [method mount_root], so
## [member entry] is a path inside that root rather than inside the directory.
var pack: String = ""
var description: String = ""
## Required mod ids to accepted semantic-version ranges.
var dependencies: Dictionary = {}
## Which cartridges the mod is for, as [RomRegistry] ids. Empty means every game
## the host knows, which is what a manifest written before this existed says.
##
## Cartridge ids rather than a generation number, because ids are what the
## registry has: a generation is not a fact the host holds about a dump, and a
## manifest may not declare something nothing can check. A list also stays right
## when the launcher gains another generation, since a mod naming the three
## Generation II cartridges refuses on a fourth without being edited.
var games: Array[StringName] = []
## Absolute path of the directory the manifest was read from.
var directory: String = ""


## Reads and validates the manifest in [param directory].
## Returns { ok, manifest } or { ok: false, reason, detail }.
static func read(folder: String) -> Dictionary:
	var path: String = "%s/%s" % [folder, FILENAME]
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
	return from_dictionary(parsed as Dictionary, folder)


## Validates an already-parsed manifest. Split out so a test, and a future pack
## reader, do not need a file on disk.
static func from_dictionary(source: Dictionary, folder: String) -> Dictionary:
	var manifest := Gen2ModManifest.new()
	manifest.directory = folder
	manifest.id = StringName(String(source.get("id", "")))
	manifest.name = String(source.get("name", String(manifest.id)))
	manifest.version = String(source.get("version", ""))
	manifest.api_version = int(source.get("api_version", 0))
	manifest.entry = String(source.get("entry", ""))
	manifest.pack = String(source.get("pack", ""))
	manifest.description = String(source.get("description", ""))
	var raw_dependencies: Variant = source.get("dependencies", {})
	if not raw_dependencies is Dictionary:
		return _refuse(&"invalid_dependencies", String(manifest.id))
	manifest.dependencies = (raw_dependencies as Dictionary).duplicate()

	var regex := RegEx.new()
	regex.compile(ID_PATTERN)
	var raw_games: Variant = source.get("games", [])
	if not raw_games is Array:
		return _refuse(&"invalid_games", String(manifest.id))
	for raw_game: Variant in raw_games as Array:
		var game: String = String(raw_game)
		# Shape only. An id this host has never heard of is not refused here: a
		# mod that also names a cartridge a later launcher will ship has to
		# install today and simply not run on the ones it does not name.
		if regex.search(game) == null:
			return _refuse(&"invalid_game", game)
		if not manifest.games.has(StringName(game)):
			manifest.games.append(StringName(game))
	if regex.search(String(manifest.id)) == null:
		return _refuse(&"invalid_id", String(manifest.id))
	if manifest.api_version < MIN_API_VERSION or manifest.api_version > API_VERSION:
		return _refuse(
			&"unsupported_api_version",
			"mod declares %d, host provides %d" % [manifest.api_version, API_VERSION]
		)
	if not Gen2ModVersion.valid_version(manifest.version):
		return _refuse(&"invalid_mod_version", manifest.version)
	for raw_id: Variant in manifest.dependencies:
		var dependency_id: String = String(raw_id)
		var wanted: String = String(manifest.dependencies[raw_id])
		if regex.search(dependency_id) == null or dependency_id == String(manifest.id):
			return _refuse(&"invalid_dependency", dependency_id)
		if not Gen2ModVersion.valid_range(wanted):
			return _refuse(&"invalid_dependency_range", "%s %s" % [dependency_id, wanted])
	if manifest.entry.is_empty():
		return _refuse(&"missing_entry", String(manifest.id))
	# An entry is a path inside the mod's own folder. Anything that climbs
	# out of it, or reaches for an absolute location, is refused.
	if manifest.entry.begins_with("/") or manifest.entry.contains("..") \
		or manifest.entry.contains(":"):
		return _refuse(&"entry_escapes_mod", manifest.entry)
	if not manifest.entry.ends_with(".gd"):
		# iOS forbids JIT and loading native code at runtime, so a mod is
		# interpreted GDScript or it is nothing.
		return _refuse(&"entry_not_gdscript", manifest.entry)
	if not manifest.pack.is_empty():
		if manifest.pack.begins_with("/") or manifest.pack.contains("..") \
			or manifest.pack.contains(":") or manifest.pack.contains("/"):
			# A pack is a file beside the manifest, not a path: it is mounted
			# rather than read, so there is nothing to gain by letting it point
			# anywhere else.
			return _refuse(&"pack_escapes_mod", manifest.pack)
		if not (manifest.pack.ends_with(".pck") or manifest.pack.ends_with(".zip")):
			return _refuse(&"pack_not_a_resource_pack", manifest.pack)
	return {"ok": true, "manifest": manifest}


## Whether this mod ships its files as a resource pack rather than loose.
func packed() -> bool:
	return not pack.is_empty()


## Where a pack's files are expected to land. `ProjectSettings.load_resource_pack`
## mounts each file at the `res://` path it was packed with, so a mod exports
## from this root and the host resolves the entry against it. One root per id,
## which is also what keeps two packs from landing on each other.
func mount_root() -> String:
	return "res://mods/%s" % id


func pack_path() -> String:
	return "%s/%s" % [directory, pack]


func entry_path() -> String:
	return "%s/%s" % [mount_root() if packed() else directory, entry]


## Whether this mod declares [param game_id]. An empty declaration is every game,
## and an empty [param game_id] is "no cartridge chosen yet", which restricts
## nothing: the launcher lists what is installed before Play is pressed.
func supports_game(game_id: StringName) -> bool:
	return games.is_empty() or String(game_id).is_empty() or games.has(game_id)


## What the mod is for, as titles the launcher can print. Empty for a mod that
## declares nothing, which the card reads as every cartridge; a declared id the
## registry does not know keeps its own name, so a mod for a later generation
## says so rather than disappearing from its own card.
func game_titles() -> Array[String]:
	var out: Array[String] = []
	for game: StringName in games:
		var title: String = RomRegistry.title_for(game)
		out.append(title if not title.is_empty() else String(game))
	return out


func summary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"version": version,
		"description": description,
		"directory": directory,
		"pack": pack,
		"dependencies": dependencies.duplicate(),
		"games": games.duplicate(),
	}


static func _refuse(reason: StringName, detail: String) -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail}
