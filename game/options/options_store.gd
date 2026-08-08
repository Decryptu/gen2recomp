class_name Gen2OptionsStore
extends RefCounted

## Persistence for [Gen2Options].
##
## Deliberately not the save store's checksummed two-file container. Options
## carry no player progress and [method Gen2Options.parse] clamps every field,
## so the worst a damaged file costs is a return to defaults. A save cannot
## afford that, which is why it keeps the heavier scheme.

const PATH: String = "user://options.json"

static var _cached: Gen2Options = null


## The live options. Read once, then shared, so callers can hold the object and
## see later edits the way [Gen2SaveData] is shared through GameRuntime.
static func current() -> Gen2Options:
	if _cached == null:
		_cached = load_options()
	return _cached


static func load_options() -> Gen2Options:
	if not FileAccess.file_exists(PATH):
		return Gen2Options.new()
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return Gen2Options.new()
	var text: String = file.get_as_text()
	file.close()
	# JSON.parse_string pushes an engine error on malformed input; a damaged
	# options file is an expected outcome here, not something to report.
	var json := JSON.new()
	if json.parse(text) != OK:
		return Gen2Options.new()
	return Gen2Options.parse(json.data)


static func save(options: Gen2Options) -> bool:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(options.to_dict(), "\t"))
	file.close()
	_cached = options
	return true


## Drops the shared object so the next [method current] reads the file again.
## Tests need this; nothing in the game does.
static func forget_cached() -> void:
	_cached = null
