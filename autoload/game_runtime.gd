class_name Gen2GameRuntime
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

## The new game the intro is running for, before it exists on disk.
##
## `NewGame` reaches `InitializeWorld` only after `PlayerProfileSetup` and
## `OakSpeech` have both returned, so there is nothing to write until the intro
## finishes. The launcher stages the slot and the slot's own label here, the
## intro screen adds the trainer name and gender the cartridge asks for, and
## only then is a save built and written. Abandoning the intro leaves no file.
var pending_new_game_slot: int = -1
var pending_new_game_label: String = ""

## The autoload, cached after the first lookup.
static var _instance: Gen2GameRuntime = null


## The live runtime, or null outside a scene tree that has one.
##
## Named relative to the root rather than as `/root/GameRuntime`, and reached
## through this rather than through the `GameRuntime` global, for the reason
## [method Gen2InputRuntime.instance] gives: a script handed to `-s` compiles
## before the autoloads exist, so a screen naming the global by identifier fails
## to compile at all and takes every tool that loads it down with it.
static func instance() -> Gen2GameRuntime:
	if _instance == null:
		var loop: SceneTree = Engine.get_main_loop() as SceneTree
		if loop != null:
			_instance = loop.root.get_node_or_null(^"GameRuntime") as Gen2GameRuntime
	return _instance


## The selected cache, or the first imported one when nothing is selected, which
## is what a development screen opened outside the launcher wants.
static func data_or_any() -> GameData:
	var runtime: Gen2GameRuntime = instance()
	if runtime != null and runtime.has_selected_game():
		return runtime.selected_data()
	return GameData.open_any()


## The selected slot's save, or null when there is no runtime or no slot.
static func selected_save_or_null() -> Gen2SaveData:
	var runtime: Gen2GameRuntime = instance()
	if runtime == null or not runtime.has_selected_save_slot():
		return null
	return runtime.selected_save()


## Stages a new game for [method take_pending_new_game] to pick up.
func begin_new_game(game_id: StringName, slot: int, label: String) -> void:
	selected_game_id = game_id
	pending_new_game_slot = slot
	pending_new_game_label = label


## The staged slot and label, cleared as it is handed over so a second read
## cannot start the intro again.
func take_pending_new_game() -> Dictionary:
	var out: Dictionary = {"slot": pending_new_game_slot, "label": pending_new_game_label}
	pending_new_game_slot = -1
	pending_new_game_label = ""
	return out

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
##
## [param game_id] is the cartridge a mod's `games` declaration is checked
## against. Empty at boot, because the launcher lists what is installed before a
## cartridge is chosen and an unrestricted list is the honest answer there.
func load_mods(game_id: StringName = &"") -> Array:
	if not DirAccess.dir_exists_absolute(Gen2ModHost.ROOT):
		DirAccess.make_dir_recursive_absolute(Gen2ModHost.ROOT)
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(game_id)
	host.discover()
	if not mods_are_allowed():
		_loaded_mods = []
		if not host.manifests().is_empty():
			print("Mods: %d installed, none loaded. Pass --mods to run them." % [
				host.manifests().size()
			])
		return _loaded_mods
	_loaded_mods = host.load_discovered()
	# A mod registers its own controls inside its entry script, which is after the
	# options were applied, so the InputMap gets them now rather than never.
	var input: Gen2InputRuntime = Gen2InputRuntime.instance()
	if input != null:
		input.install_mod_actions()
	for failure: Dictionary in host.failures():
		push_warning("Mod %s was not loaded: %s (%s)" % [
			failure.get("directory", failure.get("id", "?")),
			failure.get("reason", "unknown"), failure.get("detail", ""),
		])
	return _loaded_mods


## Whether this process runs the mods it finds.
##
## A headless run or one driving a `-s` tool script is a check, a test tier or a
## screenshot, and a mod that swaps the renderer or shuffles a table changes what
## those measure without saying so anywhere in their output. Such a run discovers
## mods, so a list is still right, and loads none unless `--mods` is passed. A
## player's own launch is neither, so what they switched on in the launcher is
## what runs.
static func mods_are_allowed() -> bool:
	var args: PackedStringArray = OS.get_cmdline_args()
	if args.has("--mods") or OS.get_cmdline_user_args().has("--mods"):
		return true
	return not (
		DisplayServer.get_name() == "headless"
		or args.has("-s") or args.has("--script")
	)


func loaded_mods() -> Array:
	return _loaded_mods.duplicate()


func select_game(game_id: StringName) -> bool:
	if RomRegistry.sha1_for(game_id).is_empty():
		return false
	if selected_game_id != game_id:
		selected_save_slot = -1
		reload_selected_save()
	selected_game_id = game_id
	_retarget_mods(game_id)
	return true


## Reloads the mods a cartridge is entitled to, when the cartridge changes.
##
## Every mod's entry script runs again against a fresh host, because a `games`
## declaration decides what a mod may register at all and a registration made for
## the previous cartridge would outlive it. Reached only from
## [method select_game], which the launcher calls on Play and after an import,
## not while the player walks along the shelf.
func _retarget_mods(game_id: StringName) -> void:
	if Gen2ModHost.instance().target_game() == game_id:
		return
	reload_mods(game_id)


## The same reload for a list that changed rather than a cartridge that did: a
## mod switched on or off, or one deleted. One rule covers both, so a switch
## applies where it was thrown instead of at the next launch.
func reload_mods(game_id: StringName = selected_game_id) -> Array:
	Gen2ModHost.reset()
	return load_mods(game_id)


func has_selected_game() -> bool:
	return not selected_game_id.is_empty()


func selected_data() -> GameData:
	if not has_selected_game():
		return null
	return GameData.open(selected_game_id)


func select_save_slot(game_id: StringName, slot: int) -> bool:
	if slot < 0 or slot >= Gen2SaveStore.MAX_SLOTS:
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
