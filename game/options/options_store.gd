class_name Gen2OptionsStore
extends RefCounted

## Persistence for [Gen2Options].
##
## Deliberately not the save store's checksummed two-file container. Options
## carry no player progress and [method Gen2Options.parse] clamps every field,
## so the worst a damaged file costs is a return to defaults. A save cannot
## afford that, which is why it keeps the heavier scheme.

const PATH: String = "user://options.json"
## Where a test writes instead. The suite shares `user://` with the game, so
## without this a headless GUT run would reset the developer's own settings and
## key bindings; [method use_test_path] is what a test calls to redirect it.
const TEST_PATH: String = "user://options_test.json"

static var _cached: Gen2Options = null
static var _path: String = PATH


## The file in use. Tests redirect it; nothing in the game does.
static func path() -> String:
	return _path


## Points the store at [constant TEST_PATH] and drops the shared object, so a
## test neither reads nor overwrites the real options file. It stays pointed
## there for the rest of the run on purpose: a later test that forgets to call
## this then reads the test file rather than the developer's own.
static func use_test_path() -> void:
	_path = TEST_PATH
	_cached = null


## The live options. Read once, then shared, so callers can hold the object and
## see later edits the way [Gen2SaveData] is shared through GameRuntime.
static func current() -> Gen2Options:
	if _cached == null:
		_cached = load_options()
	return _cached


static func load_options() -> Gen2Options:
	if not FileAccess.file_exists(_path):
		return Gen2Options.new()
	var file: FileAccess = FileAccess.open(_path, FileAccess.READ)
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
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(options.to_dict(), "\t"))
	file.close()
	_cached = options
	return true
