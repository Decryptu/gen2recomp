class_name RomVerifier
extends RefCounted

## Identifies a user-supplied ROM file by SHA-1 against [RomRegistry].
##
## Pure and node-free so the whole import gate is testable headlessly. Nothing
## here reads game content; it only answers "is this a cartridge we know?".
## The importer that follows is entitled to assume a verified hash.

enum Status {
	OK,
	NOT_FOUND,
	WRONG_SIZE,
	UNKNOWN_ROM,
}

## Read in chunks so a 2 MiB file never lands in memory twice, and so the same
## code path survives if a future platform hands us something larger.
const CHUNK_SIZE: int = 65536


## SHA-1 of a file on disk as lowercase hex, or "" if it could not be read.
static func sha1_of_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""

	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA1) != OK:
		return ""

	var remaining: int = file.get_length()
	while remaining > 0:
		var chunk: PackedByteArray = file.get_buffer(mini(CHUNK_SIZE, remaining))
		if chunk.is_empty():
			break
		context.update(chunk)
		remaining -= chunk.size()

	return context.finish().hex_encode()


## Identifies a candidate ROM.
##
## Returns { status, sha1, id, title, revision, message }. Callers should look
## at [code]status[/code]; [code]message[/code] is a ready-to-show string.
static func identify(path: String) -> Dictionary:
	var result: Dictionary = {
		"status": Status.NOT_FOUND,
		"sha1": "",
		"id": &"",
		"title": "",
		"revision": "",
		"message": "",
	}

	if not FileAccess.file_exists(path):
		result["message"] = "No file at %s" % path
		return result

	# Cheap rejection before hashing: every Gen 2 cartridge is exactly 2 MiB, so
	# a mismatch is a wrong file (or a headered/trimmed dump) and hashing it
	# would only waste the read.
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["message"] = "Could not open %s" % path
		return result
	var size: int = file.get_length()
	file.close()

	if size != RomRegistry.EXPECTED_SIZE:
		result["status"] = Status.WRONG_SIZE
		result["message"] = (
			"That file is %d bytes; a Gen 2 cartridge is %d."
			% [size, RomRegistry.EXPECTED_SIZE]
		)
		return result

	var sha1: String = sha1_of_file(path)
	result["sha1"] = sha1

	var row: Dictionary = RomRegistry.lookup(sha1)
	if row.is_empty():
		result["status"] = Status.UNKNOWN_ROM
		result["message"] = (
			"Unrecognised ROM (sha1 %s). pokerecomp supports Gold, Silver and Crystal."
			% sha1
		)
		return result

	result["status"] = Status.OK
	result["id"] = row["id"]
	result["title"] = row["title"]
	result["revision"] = row["revision"]
	result["message"] = "%s (%s)" % [row["title"], row["revision"]]
	return result


static func is_valid(path: String) -> bool:
	return identify(path)["status"] == Status.OK
