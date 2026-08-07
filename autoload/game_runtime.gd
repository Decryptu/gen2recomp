extends Node

## Runtime selection shared by the launcher and screens opened from it.
##
## Cartridge bytes and decoded data stay owned by their existing layers. The
## selected save is the exception: it is mutable, and every screen has to see the
## same instance. Re-reading the slot per call handed a battle result, a party
## transaction and a world snapshot three different saves, and only the last
## write survived. The slot is loaded once and kept until the selection changes
## or a caller asks for it from disk again.

var selected_game_id: StringName = &""
var selected_save_slot: int = -1

var _save: Gen2SaveData = null
var _save_key: String = ""
var _loaded_mods: Array = []


## Loads installed mods before any screen exists.
##
## A mod registers what it provides and returns, so this must happen before the
## first screen asks the host: a renderer registered after the overworld was
## built would not be offered until the next map. It also means a broken mod is
## reported while there is still a launcher to report it in.
func _ready() -> void:
	load_mods()


## Discovers and runs every mod under [constant Gen2ModHost.ROOT], returning the
## ids that loaded. The directory is created when it is absent so a player has
## somewhere to put one without being told the path.
func load_mods() -> Array:
	if not DirAccess.dir_exists_absolute(Gen2ModHost.ROOT):
		DirAccess.make_dir_recursive_absolute(Gen2ModHost.ROOT)
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.discover()
	_loaded_mods = host.load_discovered()
	for failure: Dictionary in host.failures():
		push_warning("Mod %s was not loaded: %s (%s)" % [
			failure.get("directory", failure.get("id", "?")),
			failure.get("reason", "unknown"), failure.get("detail", ""),
		])
	return _loaded_mods


func loaded_mods() -> Array:
	return _loaded_mods.duplicate()


func select_game(game_id: StringName) -> bool:
	if RomRegistry.sha1_for(game_id).is_empty():
		return false
	if selected_game_id != game_id:
		selected_save_slot = -1
		reload_selected_save()
	selected_game_id = game_id
	return true


func has_selected_game() -> bool:
	return not selected_game_id.is_empty()


func selected_data() -> GameData:
	if not has_selected_game():
		return null
	return GameData.open(selected_game_id)


func select_save_slot(game_id: StringName, slot: int) -> bool:
	if slot < 0 or slot >= Gen2SaveStore.SLOT_COUNT:
		return false
	if not select_game(game_id):
		return false
	if selected_save_slot != slot:
		reload_selected_save()
	selected_save_slot = slot
	return true


func has_selected_save_slot() -> bool:
	return has_selected_game() and selected_save_slot >= 0


## The selected slot, loaded once and shared. Callers may mutate it and write it
## back through [Gen2SaveStore]; they are all holding the same save.
func selected_save() -> Gen2SaveData:
	if not has_selected_save_slot():
		return null
	var key: String = "%s:%d" % [selected_game_id, selected_save_slot]
	if _save != null and _save_key == key:
		return _save
	var data: GameData = selected_data()
	if data == null:
		return null
	var result: Dictionary = Gen2SaveStore.load_result(
		data.id, data.sha1, selected_save_slot, data
	)
	if not result["ok"]:
		return null
	_save = result["save"]
	_save_key = key
	return _save


## Drops the loaded save so the next read comes from disk again. For a caller
## that has just rewritten the slot behind this one's back, such as an original
## cartridge import.
func reload_selected_save() -> void:
	_save = null
	_save_key = ""
