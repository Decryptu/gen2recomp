class_name Gen2ModOptions
extends RefCounted

## What the player chose for each mod's registered settings.
##
## The file under user:// is the installation's own values, beside
## [Gen2ModState]'s disabled list: it is what a NEW run is created from and what
## the launcher edits with no slot open. Per-mod *save* data is a separate thing
## and is not this.
##
## A run bound with [method bind_run] takes over while it is played, because a
## draw distance that changed under a loaded slot would make that slot's own
## recorded walk unreproducible ([member Gen2SaveData.run_options]). The bound
## Dictionary is the save's, so a setting changed mid-run is kept by the save that
## was played rather than by the installation alone.
##
## Only values are kept. What a setting is, what it may be and what it falls back
## to is the mod's own registration on [Gen2ModHost], so an uninstalled mod's
## leftover row costs nothing and a mod that changed its ladder between versions
## sees its stored value refused and its default used instead.

const PATH: String = "user://mod_options.json"

static var _values: Dictionary = {}
static var _loaded: bool = false
## The run's own values, or null when no slot is being played. See
## [method bind_run].
static var _run: Variant = null


## The stored value for [param key], or null when the player never chose one.
static func value(id: StringName, key: StringName) -> Variant:
	_ensure_loaded()
	if _run != null and (_run as Dictionary).has(id):
		return ((_run as Dictionary)[id] as Dictionary).get(key, null)
	return (_values.get(id, {}) as Dictionary).get(key, null)


## Every stored value for one mod, as `{key: value}`.
static func values_for(id: StringName) -> Dictionary:
	_ensure_loaded()
	if _run != null and (_run as Dictionary).has(id):
		return ((_run as Dictionary)[id] as Dictionary).duplicate()
	return (_values.get(id, {}) as Dictionary).duplicate()


## Plays a run out of [param values], which is the save's own Dictionary rather
## than a copy of it: a write during the run lands in the save that is being
## played and is kept with it.
##
## A mod with no row in it falls back to the installation's value, which is what a
## slot written before a mod was installed has to do.
static func bind_run(values: Dictionary) -> void:
	_ensure_loaded()
	_run = values


## Ends the run, so the launcher edits the installation again.
static func unbind_run() -> void:
	_run = null


static func run_bound() -> bool:
	return _run != null


## Every registered value of every mod, for a new save to record what it was
## created with. Only the ids named are read, since a mod that registered no
## option has nothing to snapshot.
static func snapshot(ids: Array) -> Dictionary:
	_ensure_loaded()
	var out: Dictionary = {}
	for raw_id: Variant in ids:
		var id: StringName = StringName(raw_id)
		var stored: Dictionary = values_for(id)
		if not stored.is_empty():
			out[id] = stored
	return out


## Returns false only when the change could not be written, in which case the
## in-memory value is rolled back so it never disagrees with the file.
##
## A bound run takes the write instead of the file: the value belongs to the slot
## being played, and writing it installation-wide would change every other slot
## with it. It reaches the disk when that save is written.
static func store(id: StringName, key: StringName, value_to_store: Variant) -> bool:
	_ensure_loaded()
	if String(id).is_empty() or String(key).is_empty():
		return false
	if _run != null:
		var run_mod: Dictionary = (_run as Dictionary).get(id, {})
		run_mod[key] = value_to_store
		(_run as Dictionary)[id] = run_mod
		return true
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
	if _run != null:
		(_run as Dictionary).erase(id)
	if not _values.has(id):
		return true
	var previous: Variant = _values[id]
	_values.erase(id)
	if _write():
		return true
	_values[id] = previous
	return false


## Rereads the file and ends any bound run, which is what starting over means.
static func reload() -> void:
	_loaded = false
	_values = {}
	_run = null
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
