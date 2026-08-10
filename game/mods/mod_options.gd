class_name Gen2ModOptions
extends RefCounted

## What the player chose for each mod's registered settings.
##
## Stored per mod id in one file under user://, beside [Gen2ModState]'s disabled
## list and for the same reason: a draw distance is a property of this
## installation, not of a save file, so it must not change when a slot is
## loaded. Per-mod *save* data is a separate thing and is not this.
##
## Only values are kept. What a setting is, what it may be and what it falls back
## to is the mod's own registration on [Gen2ModHost], so an uninstalled mod's
## leftover row costs nothing and a mod that changed its ladder between versions
## sees its stored value refused and its default used instead.

const PATH: String = "user://mod_options.json"

static var _values: Dictionary = {}
static var _loaded: bool = false


## The stored value for [param key], or null when the player never chose one.
static func value(id: StringName, key: StringName) -> Variant:
	_ensure_loaded()
	return (_values.get(id, {}) as Dictionary).get(key, null)


## Every stored value for one mod, as `{key: value}`.
static func values_for(id: StringName) -> Dictionary:
	_ensure_loaded()
	return (_values.get(id, {}) as Dictionary).duplicate()


## Returns false only when the change could not be written, in which case the
## in-memory value is rolled back so it never disagrees with the file.
static func store(id: StringName, key: StringName, value_to_store: Variant) -> bool:
	_ensure_loaded()
	if String(id).is_empty() or String(key).is_empty():
		return false
	var mod: Dictionary = _values.get(id, {})
	var had: bool = mod.has(key)
	var previous: Variant = mod.get(key, null)
	mod[key] = value_to_store
	_values[id] = mod
	if _write():
		return true
	if had:
		mod[key] = previous
	else:
		mod.erase(key)
	if mod.is_empty():
		_values.erase(id)
	return false


## Drops everything stored for a mod, for one being uninstalled. A leftover row
## would be read again if the same id were reinstalled later.
static func forget(id: StringName) -> bool:
	_ensure_loaded()
	if not _values.has(id):
		return true
	var previous: Variant = _values[id]
	_values.erase(id)
	if _write():
		return true
	_values[id] = previous
	return false


static func reload() -> void:
	_loaded = false
	_values = {}
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_values = {}
	if not FileAccess.file_exists(PATH):
		return
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or json.data is not Dictionary:
		return
	var raw: Variant = (json.data as Dictionary).get("options", {})
	if raw is not Dictionary:
		return
	for id: Variant in (raw as Dictionary):
		var mod: Variant = (raw as Dictionary)[id]
		if mod is not Dictionary:
			continue
		var stored: Dictionary = {}
		for key: Variant in (mod as Dictionary):
			stored[StringName(String(key))] = (mod as Dictionary)[key]
		if not stored.is_empty():
			_values[StringName(String(id))] = stored


static func _write() -> bool:
	var out: Dictionary = {}
	var ids: Array[String] = []
	for id: StringName in _values:
		ids.append(String(id))
	ids.sort()
	for id: String in ids:
		var mod: Dictionary = _values[StringName(id)]
		var keys: Array[String] = []
		for key: StringName in mod:
			keys.append(String(key))
		keys.sort()
		var written: Dictionary = {}
		for key: String in keys:
			written[key] = mod[StringName(key)]
		out[id] = written
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"options": out}, "\t"))
	file.close()
	return true
