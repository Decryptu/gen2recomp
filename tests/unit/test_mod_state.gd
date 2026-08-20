extends GutTest

## Enable/disable state and the host's use of it. These write real files under
## user://, so each test clears both the state file and the mod root it uses.

const ROOT: String = "user://mod-state-test"
const MOD_ID: StringName = &"state_probe"
const OTHER_ID: StringName = &"state_probe_two"


func before_each() -> void:
	DirAccess.remove_absolute(Gen2ModState.PATH)
	Gen2ModState.reload()
	_clear_root()


func after_each() -> void:
	DirAccess.remove_absolute(Gen2ModState.PATH)
	Gen2ModState.reload()
	_clear_root()


func _clear_root() -> void:
	if not DirAccess.dir_exists_absolute(ROOT):
		return
	for id: String in DirAccess.get_directories_at(ROOT):
		var directory: String = "%s/%s" % [ROOT, id]
		for file_name: String in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute("%s/%s" % [directory, file_name])
		DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(ROOT)


## A minimal installed mod: a manifest plus an entry script whose register()
## records that it ran, so a skipped mod is observable rather than assumed.
func _install(id: StringName) -> void:
	var directory: String = "%s/%s" % [ROOT, id]
	DirAccess.make_dir_recursive_absolute(directory)
	var manifest: FileAccess = FileAccess.open(
		"%s/%s" % [directory, Gen2ModManifest.FILENAME], FileAccess.WRITE
	)
	manifest.store_string(JSON.stringify({
		"id": String(id), "name": "State probe", "version": "1.0.0", "entry": "mod.gd",
		"api_version": Gen2ModManifest.API_VERSION,
	}))
	manifest.close()
	var entry: FileAccess = FileAccess.open("%s/mod.gd" % directory, FileAccess.WRITE)
	entry.store_string("extends RefCounted\n\n\nfunc register(_host, _manifest) -> void:\n\tpass\n")
	entry.close()


func test_a_mod_is_enabled_until_it_is_switched_off() -> void:
	assert_true(Gen2ModState.is_enabled(MOD_ID))

	assert_true(Gen2ModState.set_enabled(MOD_ID, false))
	assert_false(Gen2ModState.is_enabled(MOD_ID))

	assert_true(Gen2ModState.set_enabled(MOD_ID, true))
	assert_true(Gen2ModState.is_enabled(MOD_ID))


func test_the_off_switch_survives_a_reload() -> void:
	assert_true(Gen2ModState.set_enabled(MOD_ID, false))
	Gen2ModState.reload()

	assert_false(Gen2ModState.is_enabled(MOD_ID))
	assert_eq(Gen2ModState.disabled_ids(), [MOD_ID] as Array[StringName])


func test_disabling_many_at_once_is_one_write() -> void:
	assert_true(Gen2ModState.set_all_enabled([MOD_ID, OTHER_ID], false))
	Gen2ModState.reload()

	assert_false(Gen2ModState.is_enabled(MOD_ID))
	assert_false(Gen2ModState.is_enabled(OTHER_ID))

	assert_true(Gen2ModState.set_all_enabled([MOD_ID, OTHER_ID], true))
	Gen2ModState.reload()
	assert_eq(Gen2ModState.disabled_ids().size(), 0)


func test_an_empty_id_is_refused() -> void:
	assert_false(Gen2ModState.set_enabled(&"", false))


func test_a_damaged_state_file_leaves_every_mod_enabled() -> void:
	var file: FileAccess = FileAccess.open(Gen2ModState.PATH, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	Gen2ModState.reload()

	assert_true(Gen2ModState.is_enabled(MOD_ID))
	assert_eq(Gen2ModState.disabled_ids().size(), 0)


func test_a_disabled_mod_is_discovered_but_not_loaded() -> void:
	_install(MOD_ID)
	var host := Gen2ModHost.new()

	assert_eq(host.discover(ROOT).size(), 1, "a disabled mod is still listed")
	assert_eq(host.load_discovered(), [MOD_ID] as Array)

	assert_true(Gen2ModState.set_enabled(MOD_ID, false))
	var second := Gen2ModHost.new()
	assert_eq(second.discover(ROOT).size(), 1)
	assert_eq(second.load_discovered().size(), 0, "it is skipped, not run")
	assert_eq(second.failures().size(), 0, "and being off is not a failure")


func test_uninstalling_forgets_the_off_switch() -> void:
	_install(MOD_ID)
	assert_true(Gen2ModState.set_enabled(MOD_ID, false))

	assert_true(Gen2ModInstaller.uninstall(MOD_ID, ROOT)["ok"])
	assert_eq(Gen2ModState.disabled_ids().size(), 0)
	assert_true(
		Gen2ModState.is_enabled(MOD_ID),
		"a reinstall must not find itself silently disabled",
	)


## The view is the installation's own choice and lives in the same file as the
## disabled list, so switching a mod off does not forget which view is on.
func test_the_selected_view_is_stored_beside_the_disabled_list() -> void:
	assert_eq(
		Gen2ModState.selected_view(), Gen2ModHost.BUILT_IN_RENDERER,
		"a fresh installation is on the built-in view"
	)
	assert_true(Gen2ModState.set_selected_view(&"voxel3d"))
	assert_true(Gen2ModState.set_enabled(MOD_ID, false))
	Gen2ModState.reload()
	assert_eq(Gen2ModState.selected_view(), &"voxel3d")
	assert_false(Gen2ModState.is_enabled(MOD_ID))


func test_an_empty_view_id_is_refused_rather_than_stored() -> void:
	assert_true(Gen2ModState.set_selected_view(&"voxel3d"))
	assert_false(Gen2ModState.set_selected_view(&""))
	assert_eq(Gen2ModState.selected_view(), &"voxel3d")
