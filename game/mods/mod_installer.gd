class_name Gen2ModInstaller
extends RefCounted

## Installs a mod from a `.zip` into [constant Gen2ModHost.ROOT].
##
## This is the only way a mod gets onto disk, whichever way the player found it:
## a file they picked, a file they dropped on the window, or one downloaded from
## an index. A listing therefore buys a mod no trust that picking the same file
## by hand would not, and there is one place to harden rather than three.
##
## Nothing is written until the archive has been opened, its layout resolved and
## its manifest validated, so a refused archive leaves the mods directory
## exactly as it was. A copy that fails part way removes what it wrote.

## A single mod's uncompressed size. Well above the voxel example and far below
## anything that fills a phone, so a hostile or broken archive stops here rather
## than at the filesystem.
const MAX_UNCOMPRESSED_BYTES: int = 64 * 1024 * 1024
## Refuses an archive that would take longer to unpack than a player will wait.
const MAX_ENTRIES: int = 2048
## Local PK magic. An AppleDouble sidecar or a truncated download is not a zip,
## and saying so beats an opaque failure from the reader.
const ZIP_MAGIC: Array[int] = [0x50, 0x4B]


## Where a staged download is written before it is opened. [ZIPReader] only
## takes a path, so bytes from the network become a file first.
static func staging_path() -> String:
	return "user://mod_import_staging.zip"


## The prefix inside [param paths] that holds the manifest.
##
## Returns { ok, prefix } with an empty prefix when the manifest is at the
## archive root, or the single top-level directory that holds it. Anything else
## is refused: two mods in one archive have no obvious winner, and an archive
## with no manifest is not a mod. Pure, so the layout rule is testable without
## an archive on disk.
static func locate_root(paths: PackedStringArray) -> Dictionary:
	var top_directories: Array[String] = []
	var holds_manifest: Dictionary = {}
	for path: String in paths:
		if path == Gen2ModManifest.FILENAME:
			return {"ok": true, "prefix": ""}
		var separator: int = path.find("/")
		if separator <= 0:
			continue
		var top: String = path.substr(0, separator)
		var rest: String = path.substr(separator + 1)
		if not top_directories.has(top):
			top_directories.append(top)
		if rest == Gen2ModManifest.FILENAME:
			holds_manifest[top] = true
	if top_directories.size() == 1 and holds_manifest.has(top_directories[0]):
		return {"ok": true, "prefix": top_directories[0]}
	if top_directories.size() > 1:
		return {"ok": false, "reason": &"archive_holds_more_than_one_folder"}
	return {"ok": false, "reason": &"archive_has_no_manifest"}


## True when [param entry] stays inside the mod directory once [param prefix] is
## removed. A zip may name any path it likes, including one that climbs out with
## `..` or starts at the filesystem root, and extracting that would write
## wherever it pointed. The manifest's own entry check refuses the same shapes;
## this refuses them one layer earlier, before anything is read.
static func is_safe_entry(entry: String, prefix: String) -> bool:
	var relative: String = entry
	if not prefix.is_empty():
		if not entry.begins_with("%s/" % prefix):
			return false
		relative = entry.substr(prefix.length() + 1)
	if relative.is_empty():
		return false
	if relative.begins_with("/") or relative.contains("\\") or relative.contains(":"):
		return false
	for part: String in relative.split("/"):
		if part == ".." or part == ".":
			return false
	return true


## Installs the archive at [param path].
##
## [param replace] allows an already-installed id to be overwritten, which an
## update does and a first install does not. [param expect_id] refuses an
## archive whose manifest names a different mod, so a download resolved from an
## index cannot quietly deliver something else.
static func install_zip(
	path: String,
	replace: bool = false,
	expect_id: StringName = &"",
	root: String = Gen2ModHost.ROOT,
) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _refuse(&"archive_not_found", path)
	if not _looks_like_zip(path):
		return _refuse(&"not_a_zip", path)

	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return _refuse(&"archive_unreadable", path)
	var entries: PackedStringArray = reader.get_files()
	if entries.size() > MAX_ENTRIES:
		reader.close()
		return _refuse(&"archive_too_many_entries", str(entries.size()))

	var located: Dictionary = locate_root(entries)
	if not bool(located.get("ok", false)):
		reader.close()
		return _refuse(StringName(located.get("reason", &"archive_has_no_manifest")), path)
	var prefix: String = String(located["prefix"])

	var manifest_entry: String = Gen2ModManifest.FILENAME
	if not prefix.is_empty():
		manifest_entry = "%s/%s" % [prefix, Gen2ModManifest.FILENAME]
	var raw: String = reader.read_file(manifest_entry).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		reader.close()
		return _refuse(&"invalid_manifest", manifest_entry)

	var read: Dictionary = Gen2ModManifest.from_dictionary(parsed as Dictionary, root)
	if not bool(read.get("ok", false)):
		reader.close()
		return _refuse(
			StringName(read.get("reason", &"invalid_manifest")), String(read.get("detail", ""))
		)
	var manifest: Gen2ModManifest = read["manifest"]
	if not expect_id.is_empty() and manifest.id != expect_id:
		reader.close()
		return _refuse(&"unexpected_mod_id", "%s, expected %s" % [manifest.id, expect_id])

	var destination: String = "%s/%s" % [root, manifest.id]
	var existed: bool = DirAccess.dir_exists_absolute(destination)
	if existed and not replace:
		reader.close()
		return _refuse(&"already_installed", String(manifest.id))

	var planned: Array[String] = []
	var total: int = 0
	for entry: String in entries:
		if entry.ends_with("/"):
			continue
		if not is_safe_entry(entry, prefix):
			reader.close()
			return _refuse(&"unsafe_archive_entry", entry)
		total += reader.read_file(entry).size()
		if total > MAX_UNCOMPRESSED_BYTES:
			reader.close()
			return _refuse(&"archive_too_large", str(total))
		planned.append(entry)
	if planned.is_empty():
		reader.close()
		return _refuse(&"archive_is_empty", path)

	# Only now is anything written. An existing tree is removed first so a
	# replaced mod cannot keep a file the new version dropped.
	if existed:
		_remove_tree(destination)
	var written: Dictionary = _extract(reader, planned, prefix, destination)
	reader.close()
	if not bool(written.get("ok", false)):
		_remove_tree(destination)
		return written
	return {
		"ok": true,
		"id": manifest.id,
		"name": manifest.name,
		"version": manifest.version,
		"directory": destination,
		"replaced": existed,
		"files": planned.size(),
	}


## Installs [param bytes], staging them where [ZIPReader] can open them. The
## staging file is removed whatever the outcome, so a failed download leaves
## nothing behind.
static func install_bytes(
	bytes: PackedByteArray,
	replace: bool = false,
	expect_id: StringName = &"",
	root: String = Gen2ModHost.ROOT,
) -> Dictionary:
	var staged: String = staging_path()
	var file: FileAccess = FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return _refuse(&"could_not_stage_archive", staged)
	file.store_buffer(bytes)
	file.close()
	var result: Dictionary = install_zip(staged, replace, expect_id, root)
	DirAccess.remove_absolute(staged)
	return result


## Removes an installed mod. Returns ok even when it was already absent, so a
## caller cleaning up does not have to check first.
static func uninstall(id: StringName, root: String = Gen2ModHost.ROOT) -> Dictionary:
	if String(id).is_empty():
		return _refuse(&"invalid_id", String(id))
	var directory: String = "%s/%s" % [root, id]
	if not DirAccess.dir_exists_absolute(directory):
		return {"ok": true, "id": id, "removed": false}
	_remove_tree(directory)
	return {"ok": true, "id": id, "removed": true}


static func _extract(
	reader: ZIPReader, planned: Array[String], prefix: String, destination: String
) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return _refuse(&"could_not_create_mod_directory", destination)
	for entry: String in planned:
		var relative: String = entry
		if not prefix.is_empty():
			relative = entry.substr(prefix.length() + 1)
		var target: String = "%s/%s" % [destination, relative]
		var parent: String = target.get_base_dir()
		if parent != destination and DirAccess.make_dir_recursive_absolute(parent) != OK:
			return _refuse(&"could_not_create_mod_directory", parent)
		var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return _refuse(&"could_not_write_mod_file", target)
		file.store_buffer(reader.read_file(entry))
		file.close()
	return {"ok": true}


static func _remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name: String = directory.get_next()
	while name != "":
		var child: String = "%s/%s" % [path, name]
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


static func _looks_like_zip(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var head: PackedByteArray = file.get_buffer(ZIP_MAGIC.size())
	file.close()
	if head.size() != ZIP_MAGIC.size():
		return false
	for index: int in ZIP_MAGIC.size():
		if head[index] != ZIP_MAGIC[index]:
			return false
	return true


static func _refuse(reason: StringName, detail: String) -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail}
