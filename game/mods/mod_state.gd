class_name Gen2ModState
extends RefCounted

## Which installed mods the player has switched off.
##
## Disabled ids are stored rather than enabled ones, so a mod that was just
## installed runs without needing an entry written for it, and a file lost or
## damaged means every mod runs rather than none.
##
## A disabled mod is still discovered and still listed. Only [method
## Gen2ModHost.load_discovered] skips it, so the launcher can show it, say it
## is off, and switch it back on without reinstalling.

const PATH: String = "user://mods_disabled.json"

static var _disabled: Dictionary = {}
static var _loaded: bool = false


static func is_enabled(id: StringName) -> bool:
	_ensure_loaded()
	return not _disabled.has(id)


static func disabled_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for id: StringName in _disabled:
		out.append(id)
	out.sort()
	return out


## Returns false only when the change could not be written, in which case the
## in-memory set is rolled back so it never disagrees with the file.
static func set_enabled(id: StringName, enabled: bool) -> bool:
	_ensure_loaded()
	if String(id).is_empty():
		return false
	var was_disabled: bool = _disabled.has(id)
	if enabled:
		_disabled.erase(id)
	else:
		_disabled[id] = true
	if _write():
		return true
	if was_disabled:
		_disabled[id] = true
	else:
		_disabled.erase(id)
	return false


static func set_all_enabled(ids: Array, enabled: bool) -> bool:
	_ensure_loaded()
	var previous: Dictionary = _disabled.duplicate()
	for id: Variant in ids:
		if enabled:
			_disabled.erase(StringName(id))
		else:
			_disabled[StringName(id)] = true
	if _write():
		return true
	_disabled = previous
	return false


## Drops an id entirely, for a mod that no longer exists. A removed mod that
## stayed in the file would silently switch itself off if it were reinstalled.
static func forget(id: StringName) -> bool:
	_ensure_loaded()
	if not _disabled.has(id):
		return true
	_disabled.erase(id)
	return _write()


static func reload() -> void:
	_loaded = false
	_disabled = {}
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_disabled = {}
	if not FileAccess.file_exists(PATH):
		return
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	if json.data is not Dictionary:
		return
	var raw: Variant = (json.data as Dictionary).get("disabled", [])
	if raw is not Array:
		return
	for id: Variant in raw as Array:
		var name := StringName(String(id))
		if not String(name).is_empty():
			_disabled[name] = true


static func _write() -> bool:
	var ids: Array[String] = []
	for id: StringName in _disabled:
		ids.append(String(id))
	ids.sort()
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"disabled": ids}, "\t"))
	file.close()
	return true
