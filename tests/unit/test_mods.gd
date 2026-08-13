extends GutTest

## Mod tests write a real mod directory under user:// and load it the way the
## launcher will, because the point of the boundary is that mod code the project
## has never seen can reach it.

const ROOT: String = "user://mod_tests"

var _directory: String = ""


func before_each() -> void:
	_directory = "%s/voxel" % ROOT
	_clear()
	DirAccess.make_dir_recursive_absolute(_directory)
	Gen2ModHost.reset()


func after_each() -> void:
	_clear()
	Gen2ModHost.reset()


## Recursive, because an installed mod can carry nested directories and a
## non-empty one refuses to be removed.
func _clear(path: String = ROOT) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for name: String in directory.get_directories():
		_clear("%s/%s" % [path, name])
	for file: String in directory.get_files():
		DirAccess.remove_absolute("%s/%s" % [path, file])
	DirAccess.remove_absolute(path)


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _write_manifest(source: Dictionary) -> void:
	_write("%s/mod.json" % _directory, JSON.stringify(source))


func _write_dependency_mod(
	directory: String, id: String, version: String, dependencies: Dictionary = {}
) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	_write("%s/mod.json" % directory, JSON.stringify({
		"id": id, "name": id.capitalize(), "version": version,
		"api_version": Gen2ModManifest.API_VERSION, "entry": "mod.gd",
		"dependencies": dependencies,
	}))
	_write("%s/mod.gd" % directory, """extends RefCounted
func register(host, manifest) -> void:
	host.register_menu_entry(host.MENU_START, manifest.id, {\"label\": manifest.name})
""")


func _valid_manifest() -> Dictionary:
	return {
		"id": "voxel",
		"name": "Voxel World",
		"version": "1.0.0",
		"api_version": Gen2ModManifest.API_VERSION,
		"entry": "mod.gd",
	}


func test_a_valid_manifest_is_read_without_running_the_mod() -> void:
	_write_manifest(_valid_manifest())
	var result: Dictionary = Gen2ModManifest.read(_directory)
	assert_true(result["ok"])
	var manifest: Gen2ModManifest = result["manifest"]
	assert_eq(manifest.id, &"voxel")
	assert_eq(manifest.name, "Voxel World")
	assert_eq(manifest.entry_path(), "%s/mod.gd" % _directory)


func test_a_manifest_built_for_another_host_is_refused() -> void:
	var source: Dictionary = _valid_manifest()
	source["api_version"] = Gen2ModManifest.API_VERSION + 1
	_write_manifest(source)
	assert_eq(Gen2ModManifest.read(_directory)["reason"], &"unsupported_api_version")


func test_manifest_versions_and_dependency_ranges_are_validated_before_code_runs() -> void:
	var source: Dictionary = _valid_manifest()
	source["version"] = "one"
	assert_eq(
		Gen2ModManifest.from_dictionary(source, _directory)["reason"],
		&"invalid_mod_version"
	)
	source["version"] = "1.0.0"
	source["dependencies"] = {"core": ">=1.0 <2.0"}
	assert_eq(
		Gen2ModManifest.from_dictionary(source, _directory)["reason"],
		&"invalid_dependency_range"
	)


## `games` is cartridge ids and nothing else. An unknown id is not refused when
## the manifest is read, because a mod naming a cartridge a later launcher will
## ship has to install today.
func test_the_games_declaration_is_validated_by_shape_and_not_by_registry() -> void:
	var source: Dictionary = _valid_manifest()
	source["games"] = "crystal"
	assert_eq(Gen2ModManifest.from_dictionary(source, _directory)["reason"], &"invalid_games")
	source["games"] = ["Crystal"]
	assert_eq(Gen2ModManifest.from_dictionary(source, _directory)["reason"], &"invalid_game")
	source["games"] = ["gold", "silver", "crystal", "red"]
	var read: Dictionary = Gen2ModManifest.from_dictionary(source, _directory)
	assert_true(read["ok"], "an id this host does not know is still a legal declaration")
	var manifest: Gen2ModManifest = read["manifest"]
	assert_eq(manifest.games, [&"gold", &"silver", &"crystal", &"red"] as Array[StringName])
	assert_eq(manifest.game_titles(), ["Gold", "Silver", "Crystal", "red"] as Array[String])


## An absent declaration is every cartridge, and so is an unchosen one: the
## launcher lists what is installed before Play is pressed.
func test_a_mod_declaring_no_games_is_for_every_cartridge() -> void:
	var read: Dictionary = Gen2ModManifest.from_dictionary(_valid_manifest(), _directory)
	var manifest: Gen2ModManifest = read["manifest"]
	assert_true(manifest.games.is_empty())
	assert_true(manifest.supports_game(RomRegistry.GOLD))
	assert_true(manifest.supports_game(&""))
	assert_true(manifest.game_titles().is_empty())


func test_a_mod_for_another_cartridge_is_refused_by_name_and_not_run() -> void:
	_write_dependency_mod("%s/crystal_only" % ROOT, "crystalonly", "1.0.0")
	_write("%s/crystal_only/mod.json" % ROOT, JSON.stringify({
		"id": "crystalonly", "name": "Crystal Only", "version": "1.0.0",
		"api_version": Gen2ModManifest.API_VERSION, "entry": "mod.gd",
		"games": ["crystal"],
	}))
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(RomRegistry.GOLD)
	host.discover(ROOT)
	assert_eq(host.load_discovered(), [])
	assert_eq(StringName(host.failures()[-1]["reason"]), &"incompatible_game")
	assert_eq(
		Gen2ModRefusal.text(host.failures()[-1]), "That mod is not for Gold.",
		"the launcher has a line for it"
	)

	Gen2ModHost.reset()
	host = Gen2ModHost.instance()
	host.set_target_game(RomRegistry.CRYSTAL)
	host.discover(ROOT)
	assert_eq(host.load_discovered(), [&"crystalonly"])
	for failure: Dictionary in host.failures():
		assert_ne(StringName(failure["reason"]), &"incompatible_game")


func test_dependencies_load_before_the_mod_that_requires_them() -> void:
	_write_dependency_mod("%s/dep_core" % ROOT, "core", "1.5.0")
	_write_dependency_mod("%s/addon" % ROOT, "addon", "2.0.0", {"core": "^1.2.0"})
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.discover(ROOT)
	assert_eq(host.load_discovered(), [&"core", &"addon"])
	assert_eq(host.menu_entries(Gen2ModHost.MENU_START).size(), 2)


func test_missing_and_incompatible_dependencies_are_named_and_not_loaded() -> void:
	_write_dependency_mod("%s/missing_addon" % ROOT, "addon", "1.0.0", {"missing": "*"})
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.discover(ROOT)
	assert_eq(host.load_discovered(), [])
	assert_eq(StringName(host.failures()[-1]["reason"]), &"missing_dependency")

	Gen2ModHost.reset()
	_clear()
	_write_dependency_mod("%s/old_core" % ROOT, "core", "1.0.0")
	_write_dependency_mod("%s/addon" % ROOT, "addon", "1.0.0", {"core": ">=2.0.0"})
	host = Gen2ModHost.instance()
	host.discover(ROOT)
	assert_eq(host.load_discovered(), [&"core"])
	assert_eq(StringName(host.failures()[-1]["reason"]), &"incompatible_dependency")


func test_dependency_cycles_refuse_every_member_without_running_either() -> void:
	_write_dependency_mod("%s/one" % ROOT, "one", "1.0.0", {"two": "*"})
	_write_dependency_mod("%s/two" % ROOT, "two", "1.0.0", {"one": "*"})
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.discover(ROOT)
	assert_eq(host.load_discovered(), [])
	var reasons: Array = host.failures().map(func(row: Dictionary) -> StringName:
		return StringName(row.get("reason", &""))
	)
	assert_eq(reasons.count(&"dependency_cycle"), 2)


func test_a_manifest_is_the_capability_for_only_its_own_save_namespace() -> void:
	_write_dependency_mod("%s/save_owner" % ROOT, "save_owner", "1.0.0")
	var host: Gen2ModHost = Gen2ModHost.instance()
	var found: Array = host.discover(ROOT)
	var manifest: Gen2ModManifest = null
	for candidate: Gen2ModManifest in found:
		if candidate.id == &"save_owner":
			manifest = candidate
	assert_not_null(manifest)
	var save := Gen2SaveData.new()
	assert_true(host.write_save_data(manifest, save, {"chapter": 3})["ok"])
	assert_eq(host.read_save_data(manifest, save), {"chapter": 3})

	var impostor := Gen2ModManifest.new()
	impostor.id = &"save_owner"
	assert_eq(
		host.write_save_data(impostor, save, {"chapter": 9})["reason"],
		&"unknown_mod_save_owner"
	)
	assert_eq(save.mod_data(&"save_owner"), {"chapter": 3})


func test_an_entry_that_leaves_the_mod_directory_is_refused() -> void:
	for entry: String in ["../escape.gd", "/etc/passwd.gd", "res://game/main/main.gd"]:
		var source: Dictionary = _valid_manifest()
		source["entry"] = entry
		_write_manifest(source)
		var result: Dictionary = Gen2ModManifest.read(_directory)
		assert_false(result["ok"], "entry %s must be refused" % entry)


func test_a_native_entry_is_refused_because_ios_forbids_runtime_native_code() -> void:
	var source: Dictionary = _valid_manifest()
	source["entry"] = "mod.dll"
	_write_manifest(source)
	assert_eq(Gen2ModManifest.read(_directory)["reason"], &"entry_not_gdscript")


func test_the_built_in_renderer_is_registered_before_any_mod_loads() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(host.world_renderer_ids().has(Gen2ModHost.BUILT_IN_RENDERER))
	assert_eq(host.selected_world_renderer(), Gen2ModHost.BUILT_IN_RENDERER)
	var renderer: Node = host.create_world_renderer()
	assert_true(renderer is Gen2WorldRenderer)
	renderer.free()


func test_the_built_in_battle_renderer_is_registered_before_any_mod_loads() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(host.battle_renderer_ids().has(Gen2ModHost.BUILT_IN_RENDERER))
	assert_eq(host.selected_battle_renderer(), Gen2ModHost.BUILT_IN_RENDERER)
	var renderer: Node = host.create_battle_renderer()
	assert_true(renderer is Gen2BattleRenderer)
	renderer.free()


func test_a_battle_renderer_missing_a_contract_method_is_refused_at_registration() -> void:
	var script := GDScript.new()
	# Has set_battle_data and refresh, but not set_view.
	script.source_code = "extends Control\nfunc set_battle_data(_d) -> bool:\n\treturn true\nfunc refresh() -> void:\n\tpass\n"
	script.reload()
	var result: Dictionary = Gen2ModHost.instance().register_battle_renderer(&"broken", script)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"renderer_missing_methods")
	assert_string_contains(String(result["detail"]), "set_view")


func test_a_discovered_mod_registers_a_battle_renderer_the_screen_then_draws_with() -> void:
	# A directory and mod id distinct from the world-renderer mod test above:
	# res:// scripts load through Godot's resource cache keyed by path, so two
	# tests writing different content to the same user:// script path in the
	# same process can read back a stale cached script.
	var directory: String = "%s/voxel_battle" % ROOT
	DirAccess.make_dir_recursive_absolute(directory)
	var manifest: Dictionary = _valid_manifest()
	manifest["id"] = "voxel_battle"
	_write("%s/mod.json" % directory, JSON.stringify(manifest))
	_write("%s/battle_renderer.gd" % directory, """extends Control

func set_battle_data(_data) -> bool:
	return true

func set_view(_view: Dictionary) -> void:
	pass

func refresh() -> void:
	pass

func is_voxel_battle_renderer() -> bool:
	return true
""")
	_write("%s/mod.gd" % directory, """extends RefCounted

func register(host, manifest) -> void:
	host.register_battle_renderer(
		manifest.id, load("%s/battle_renderer.gd"), "Voxel"
	)
""" % directory)

	var host: Gen2ModHost = Gen2ModHost.instance()
	var found: Array = host.discover(ROOT)
	assert_eq(found.size(), 1)
	assert_eq(host.load_discovered(), [&"voxel_battle"])
	assert_true(host.battle_renderer_ids().has(&"voxel_battle"))

	assert_true(host.select_battle_renderer(&"voxel_battle")["ok"])
	var renderer: Node = host.create_battle_renderer()
	assert_true(renderer.has_method("is_voxel_battle_renderer"))
	renderer.free()

	assert_true(host.select_battle_renderer(Gen2ModHost.BUILT_IN_RENDERER)["ok"])
	var built_in: Node = host.create_battle_renderer()
	assert_true(built_in is Gen2BattleRenderer)
	built_in.free()


func test_a_battle_renderer_choosing_the_native_layer_is_not_confined_to_hardware_pixels() -> void:
	var hardware := Gen2BattleRenderer.new()
	assert_true(Gen2ModHost.renderer_uses_hardware_viewport(hardware))
	hardware.free()

	var script := GDScript.new()
	script.source_code = """extends Control

func set_battle_data(_data) -> bool:
	return true

func set_view(_view: Dictionary) -> void:
	pass

func refresh() -> void:
	pass

func uses_hardware_viewport() -> bool:
	return false
"""
	script.reload()
	assert_true(Gen2ModHost.instance().register_battle_renderer(&"native", script)["ok"])
	var native: Node = script.new()
	assert_false(Gen2ModHost.renderer_uses_hardware_viewport(native))
	native.free()


func test_a_renderer_missing_a_contract_method_is_refused_at_registration() -> void:
	var script := GDScript.new()
	# Has set_world and refresh, but not the rest of the contract.
	script.source_code = "extends Node2D\nfunc set_world(_w, _a = null) -> void:\n\tpass\nfunc refresh() -> void:\n\tpass\n"
	script.reload()
	var result: Dictionary = Gen2ModHost.instance().register_world_renderer(&"broken", script)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"renderer_missing_methods")
	assert_string_contains(String(result["detail"]), "set_time_of_day")


func test_a_discovered_mod_registers_a_renderer_the_world_then_draws_with() -> void:
	_write_manifest(_valid_manifest())
	_write("%s/renderer.gd" % _directory, """extends Node2D

func set_world(_world, _animation = null) -> void:
	pass

func set_time_of_day(_time_of_day: int) -> void:
	pass

func refresh() -> void:
	pass

func refresh_animation() -> void:
	pass

func is_voxel_renderer() -> bool:
	return true
""")
	_write("%s/mod.gd" % _directory, """extends RefCounted

func register(host, manifest) -> void:
	host.register_world_renderer(
		manifest.id, load("%s/renderer.gd"), "Voxel"
	)
""" % _directory)

	var host: Gen2ModHost = Gen2ModHost.instance()
	var found: Array = host.discover(ROOT)
	assert_eq(found.size(), 1)
	assert_eq(host.load_discovered(), [&"voxel"])
	assert_true(host.world_renderer_ids().has(&"voxel"))

	# Selecting is what a keybind does, and it must change what a new world is
	# handed without the screen knowing which renderer it asked for.
	assert_true(host.select_world_renderer(&"voxel")["ok"])
	var renderer: Node = host.create_world_renderer()
	assert_true(renderer.has_method("is_voxel_renderer"))
	renderer.free()

	assert_true(host.select_world_renderer(Gen2ModHost.BUILT_IN_RENDERER)["ok"])
	var built_in: Node = host.create_world_renderer()
	assert_true(built_in is Gen2WorldRenderer)
	built_in.free()


func test_a_renderer_choosing_the_native_layer_is_not_confined_to_hardware_pixels() -> void:
	# A 3D or HD view cannot be drawn in a 160x144 buffer and magnified, so the
	# screen has to be told which of its two layers a renderer belongs on.
	var hardware := Gen2WorldRenderer.new()
	assert_true(Gen2ModHost.renderer_uses_hardware_viewport(hardware))
	hardware.free()

	var script := GDScript.new()
	script.source_code = """extends Node2D

func set_world(_world, _animation = null) -> void:
	pass

func set_time_of_day(_time_of_day: int) -> void:
	pass

func refresh() -> void:
	pass

func refresh_animation() -> void:
	pass

func uses_hardware_viewport() -> bool:
	return false
"""
	script.reload()
	assert_true(Gen2ModHost.instance().register_world_renderer(&"native", script)["ok"])
	var native: Node = script.new()
	assert_false(Gen2ModHost.renderer_uses_hardware_viewport(native))
	native.free()


func test_a_renderer_can_take_the_input_the_screen_left_it() -> void:
	# Camera pitch, first person and free-roam are all input a renderer has to
	# receive, and answering false has to leave the event where it was.
	var script := GDScript.new()
	script.source_code = """extends Node2D

var seen: Array = []

func set_world(_world, _animation = null) -> void:
	pass

func set_time_of_day(_time_of_day: int) -> void:
	pass

func refresh() -> void:
	pass

func refresh_animation() -> void:
	pass

func handle_world_input(event) -> bool:
	seen.append(event.keycode)
	return event.keycode == KEY_Q
"""
	script.reload()
	assert_true(Gen2ModHost.instance().register_world_renderer(&"camera", script)["ok"])
	var renderer: Node = script.new()
	var claimed := InputEventKey.new()
	claimed.keycode = KEY_Q
	var declined := InputEventKey.new()
	declined.keycode = KEY_E
	assert_true(Gen2ModHost.renderer_handles_input(renderer, claimed))
	assert_false(Gen2ModHost.renderer_handles_input(renderer, declined))
	assert_eq(renderer.get("seen"), [KEY_Q, KEY_E])
	renderer.free()

	# The hook is optional: a renderer written before it existed, or one with no
	# use for input, is never asked and consumes nothing.
	var built_in := Gen2WorldRenderer.new()
	assert_false(Gen2ModHost.renderer_handles_input(built_in, claimed))
	built_in.free()
	assert_false(Gen2ModHost.renderer_handles_input(null, claimed))


func test_manifests_survive_reading_the_failures_recorded_after_discovery() -> void:
	_write_manifest(_valid_manifest())
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.discover(ROOT)
	host.load_discovered()
	# The entry script was never written, so loading failed. Listing what is
	# installed must not discover again and drop that.
	assert_eq(host.manifests().size(), 1)
	assert_eq(host.failures().size(), 1)
	assert_eq(host.manifests().size(), 1)


func test_a_broken_mod_is_reported_and_does_not_stop_the_others() -> void:
	_write_manifest(_valid_manifest())
	# Declared entry never written, so this mod cannot load.
	DirAccess.make_dir_recursive_absolute("%s/other" % ROOT)
	_write("%s/other/mod.json" % ROOT, JSON.stringify({
		"id": "other", "name": "Other", "version": "1.0.0",
		"api_version": Gen2ModManifest.API_VERSION, "entry": "mod.gd",
	}))
	_write("%s/other/mod.gd" % ROOT, "extends RefCounted\n\nfunc register(_host, _manifest) -> void:\n\tpass\n")

	var host: Gen2ModHost = Gen2ModHost.instance()
	host.discover(ROOT)
	assert_eq(host.load_discovered(), [&"other"])
	var failures: Array = host.failures()
	assert_eq(failures.size(), 1)
	assert_eq(failures[0]["reason"], &"missing_entry_script")
	# The reason alone cannot be reported: the launcher and the startup warning
	# name the mod from the failure itself.
	assert_eq(failures[0]["id"], _valid_manifest()["id"])
	assert_true(String(failures[0]["directory"]).ends_with(_valid_manifest()["id"]))


## Builds a zip at [param path] from { entry path: text } so an installer test
## can describe an archive's layout in one literal.
func _write_zip(path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	assert_eq(packer.open(path), OK, "could not open %s for writing" % path)
	for entry: String in entries:
		packer.start_file(entry)
		packer.write_file(String(entries[entry]).to_utf8_buffer())
		packer.close_file()
	packer.close()


## A distinct id from _valid_manifest(): before_each() already creates
## ROOT/voxel, and an installer test needs a destination that does not exist.
func _packaged_manifest() -> Dictionary:
	var source: Dictionary = _valid_manifest()
	source["id"] = "packaged"
	source["name"] = "Packaged Mod"
	return source


func _mod_zip_entries(prefix: String = "") -> Dictionary:
	var at: String = prefix if prefix.is_empty() else "%s/" % prefix
	return {
		"%smod.json" % at: JSON.stringify(_packaged_manifest()),
		"%smod.gd" % at: "extends RefCounted\n\nfunc register(_h, _m) -> void:\n\tpass\n",
		"%sextra/notes.txt" % at: "kept",
	}


func test_locate_root_accepts_a_manifest_at_the_archive_root_or_one_folder_down() -> void:
	assert_eq(Gen2ModInstaller.locate_root(
		PackedStringArray(["mod.json", "mod.gd"])
	)["prefix"], "")
	assert_eq(Gen2ModInstaller.locate_root(
		PackedStringArray(["voxel/mod.json", "voxel/mod.gd"])
	)["prefix"], "voxel")


func test_locate_root_refuses_an_archive_without_exactly_one_mod() -> void:
	# Two mods in one archive have no obvious winner.
	var two: Dictionary = Gen2ModInstaller.locate_root(
		PackedStringArray(["a/mod.json", "b/mod.json"])
	)
	assert_false(two["ok"])
	assert_eq(two["reason"], &"archive_holds_more_than_one_folder")

	var none: Dictionary = Gen2ModInstaller.locate_root(
		PackedStringArray(["voxel/renderer.gd"])
	)
	assert_false(none["ok"])
	assert_eq(none["reason"], &"archive_has_no_manifest")


func test_is_safe_entry_refuses_paths_that_leave_the_mod_directory() -> void:
	assert_true(Gen2ModInstaller.is_safe_entry("voxel/mod.gd", "voxel"))
	assert_true(Gen2ModInstaller.is_safe_entry("extra/deep/file.txt", ""))
	# A zip may name any path it likes; these would write outside the mod.
	assert_false(Gen2ModInstaller.is_safe_entry("voxel/../../evil.gd", "voxel"))
	assert_false(Gen2ModInstaller.is_safe_entry("../evil.gd", ""))
	assert_false(Gen2ModInstaller.is_safe_entry("/etc/passwd", ""))
	assert_false(Gen2ModInstaller.is_safe_entry("user://evil.gd", ""))
	assert_false(Gen2ModInstaller.is_safe_entry("other/mod.gd", "voxel"))


func test_installing_a_zip_writes_the_mod_and_the_host_then_loads_it() -> void:
	var archive: String = "%s/import.zip" % ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	_write_zip(archive, _mod_zip_entries("packaged"))

	var result: Dictionary = Gen2ModInstaller.install_zip(archive, false, &"", ROOT)
	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(result["id"], &"packaged")
	assert_eq(int(result["files"]), 3)
	assert_false(result["replaced"])
	# The nested path survives the copy rather than being flattened.
	assert_true(FileAccess.file_exists("%s/packaged/extra/notes.txt" % ROOT))

	var host: Gen2ModHost = Gen2ModHost.instance()
	host.discover(ROOT)
	assert_eq(host.load_discovered(), [&"packaged"])


func test_installing_over_an_existing_mod_needs_replace() -> void:
	var archive: String = "%s/import.zip" % ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	_write_zip(archive, _mod_zip_entries("packaged"))
	assert_true(Gen2ModInstaller.install_zip(archive, false, &"", ROOT)["ok"])

	var again: Dictionary = Gen2ModInstaller.install_zip(archive, false, &"", ROOT)
	assert_false(again["ok"])
	assert_eq(again["reason"], &"already_installed")

	var replaced: Dictionary = Gen2ModInstaller.install_zip(archive, true, &"", ROOT)
	assert_true(replaced["ok"], JSON.stringify(replaced))
	assert_true(replaced["replaced"])


func test_replacing_a_mod_does_not_keep_a_file_the_new_version_dropped() -> void:
	var archive: String = "%s/import.zip" % ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	_write_zip(archive, _mod_zip_entries("packaged"))
	assert_true(Gen2ModInstaller.install_zip(archive, false, &"", ROOT)["ok"])
	assert_true(FileAccess.file_exists("%s/packaged/extra/notes.txt" % ROOT))

	var slimmer: Dictionary = _mod_zip_entries("packaged")
	slimmer.erase("packaged/extra/notes.txt")
	_write_zip(archive, slimmer)
	assert_true(Gen2ModInstaller.install_zip(archive, true, &"", ROOT)["ok"])
	assert_false(FileAccess.file_exists("%s/packaged/extra/notes.txt" % ROOT))


func test_an_expected_id_refuses_an_archive_for_a_different_mod() -> void:
	var archive: String = "%s/import.zip" % ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	_write_zip(archive, _mod_zip_entries("packaged"))
	var result: Dictionary = Gen2ModInstaller.install_zip(archive, false, &"something_else", ROOT)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"unexpected_mod_id")
	assert_false(DirAccess.dir_exists_absolute("%s/packaged" % ROOT))


func test_a_refused_archive_writes_nothing() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var not_a_zip: String = "%s/plain.zip" % ROOT
	_write(not_a_zip, "this is not an archive")
	var refused: Dictionary = Gen2ModInstaller.install_zip(not_a_zip, false, &"", ROOT)
	assert_false(refused["ok"])
	assert_eq(refused["reason"], &"not_a_zip")

	var bad_manifest: String = "%s/bad.zip" % ROOT
	_write_zip(bad_manifest, {
		"packaged/mod.json": JSON.stringify({
			"id": "packaged", "name": "Packaged", "version": "1.0.0",
			"api_version": Gen2ModManifest.API_VERSION + 1, "entry": "mod.gd",
		}),
		"packaged/mod.gd": "extends RefCounted\n",
	})
	var version: Dictionary = Gen2ModInstaller.install_zip(bad_manifest, false, &"", ROOT)
	assert_false(version["ok"])
	assert_eq(version["reason"], &"unsupported_api_version")
	assert_false(DirAccess.dir_exists_absolute("%s/packaged" % ROOT))


func test_installing_from_bytes_removes_its_staging_file() -> void:
	var archive: String = "%s/import.zip" % ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	_write_zip(archive, _mod_zip_entries("packaged"))
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(archive)

	var result: Dictionary = Gen2ModInstaller.install_bytes(bytes, false, &"", ROOT)
	assert_true(result["ok"], JSON.stringify(result))
	assert_false(FileAccess.file_exists(Gen2ModInstaller.staging_path()))


func test_uninstall_removes_the_tree_and_is_quiet_when_it_is_already_gone() -> void:
	var archive: String = "%s/import.zip" % ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	_write_zip(archive, _mod_zip_entries("packaged"))
	assert_true(Gen2ModInstaller.install_zip(archive, false, &"", ROOT)["ok"])

	var removed: Dictionary = Gen2ModInstaller.uninstall(&"packaged", ROOT)
	assert_true(removed["ok"])
	assert_true(removed["removed"])
	assert_false(DirAccess.dir_exists_absolute("%s/packaged" % ROOT))

	var again: Dictionary = Gen2ModInstaller.uninstall(&"packaged", ROOT)
	assert_true(again["ok"])
	assert_false(again["removed"])


func test_index_source_resolves_the_shapes_a_player_might_paste() -> void:
	var expected: String = "https://someone.github.io/mods/index.json"
	for input: String in [
		"someone/mods",
		"https://github.com/someone/mods",
		"https://github.com/someone/mods.git",
	]:
		var resolved: Dictionary = Gen2ModIndex.resolve_source(input)
		assert_true(resolved["ok"], input)
		assert_eq(resolved["feed"], expected, input)
		assert_eq(resolved["label"], "someone/mods", input)

	# A site root gains the feed name; a feed file is taken as given.
	assert_eq(
		Gen2ModIndex.resolve_source("https://mods.example.com/")["feed"],
		"https://mods.example.com/index.json",
	)
	assert_eq(
		Gen2ModIndex.resolve_source("https://mods.example.com/feed.json")["feed"],
		"https://mods.example.com/feed.json",
	)


func test_index_source_refuses_plain_http_and_nothing() -> void:
	# http would let anyone on the path rewrite the downloads the feed hands out.
	var insecure: Dictionary = Gen2ModIndex.resolve_source("http://mods.example.com/")
	assert_false(insecure["ok"])
	assert_eq(insecure["reason"], &"index_url_not_https")
	assert_eq(Gen2ModIndex.resolve_source("   ")["reason"], &"empty_index_url")


func _feed(mods: Array, schema: int = Gen2ModIndex.SCHEMA_VERSION) -> String:
	return JSON.stringify({"schema_version": schema, "name": "Example", "mods": mods})


func test_index_feed_parses_entries_and_keeps_the_listing_order() -> void:
	var parsed: Dictionary = Gen2ModIndex.parse_feed(_feed([
		{"id": "voxel", "name": "Voxel", "version": "2.0.0",
		 "download": "https://example.com/voxel.zip", "description": "A view"},
		{"id": "second", "download": "https://example.com/second.zip"},
	]))
	assert_true(parsed["ok"], JSON.stringify(parsed))
	assert_eq(parsed["name"], "Example")
	var entries: Array = parsed["entries"]
	assert_eq(entries.size(), 2)
	assert_eq(entries[0]["id"], &"voxel")
	assert_eq(entries[0]["version"], "2.0.0")
	# A row with no name falls back to its id rather than listing as blank.
	assert_eq(entries[1]["name"], "second")


func test_index_feed_of_an_unknown_schema_is_refused_outright() -> void:
	# A later format may reuse a field name, so this is a gate and not a hint.
	var parsed: Dictionary = Gen2ModIndex.parse_feed(
		_feed([], Gen2ModIndex.SCHEMA_VERSION + 1)
	)
	assert_false(parsed["ok"])
	assert_eq(parsed["reason"], &"unsupported_index_schema")
	assert_eq(Gen2ModIndex.parse_feed("not json")["reason"], &"index_not_json")


func test_index_feed_drops_unusable_rows_without_losing_the_rest() -> void:
	var parsed: Dictionary = Gen2ModIndex.parse_feed(_feed([
		{"name": "No id at all", "download": "https://example.com/a.zip"},
		{"id": "insecure", "download": "http://example.com/b.zip"},
		{"id": "no download"},
		{"id": "Bad Id", "download": "https://example.com/c.zip"},
		{"id": "voxel", "download": "https://example.com/voxel.zip"},
		{"id": "voxel", "download": "https://example.com/duplicate.zip"},
	]))
	assert_true(parsed["ok"])
	var entries: Array = parsed["entries"]
	assert_eq(entries.size(), 1, JSON.stringify(entries))
	assert_eq(entries[0]["id"], &"voxel")
	assert_eq(entries[0]["download"], "https://example.com/voxel.zip")


func test_following_an_index_persists_it_and_never_duplicates_a_feed() -> void:
	var store: String = "%s/indexes.json" % ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	# Ships following nobody: an index is the player trusting a publisher.
	assert_eq(Gen2ModIndex.followed(store).size(), 0)

	var added: Dictionary = Gen2ModIndex.follow("someone/mods", store)
	assert_true(added["ok"])
	assert_true(added["added"])
	assert_eq(Gen2ModIndex.followed(store).size(), 1)
	assert_eq(Gen2ModIndex.followed(store)[0]["label"], "someone/mods")

	# The same feed reached by another URL shape is still the same feed.
	var again: Dictionary = Gen2ModIndex.follow("https://github.com/someone/mods", store)
	assert_true(again["ok"])
	assert_false(again["added"])
	assert_eq(Gen2ModIndex.followed(store).size(), 1)

	Gen2ModIndex.unfollow(added["feed"], store)
	assert_eq(Gen2ModIndex.followed(store).size(), 0)


func test_following_a_refused_url_stores_nothing() -> void:
	var store: String = "%s/indexes.json" % ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	assert_false(Gen2ModIndex.follow("http://mods.example.com/", store)["ok"])
	assert_eq(Gen2ModIndex.followed(store).size(), 0)


func test_menu_entries_are_registered_per_menu_and_kept_in_order() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_eq(host.menu_entries(Gen2ModHost.MENU_START), [])
	assert_true(bool(host.register_menu_entry(
		Gen2ModHost.MENU_START, &"first", {"label": "First"}
	).get("ok", false)))
	assert_true(bool(host.register_menu_entry(
		Gen2ModHost.MENU_START, &"second", {"label": "Second"}
	).get("ok", false)))
	assert_true(bool(host.register_menu_entry(
		Gen2ModHost.MENU_PACK_POCKET, &"relics",
		{"label": "Relics", "pocket": Gen2ModHost.FIRST_MOD_POCKET}
	).get("ok", false)))
	var start: Array = host.menu_entries(Gen2ModHost.MENU_START)
	assert_eq(start.size(), 2)
	assert_eq(StringName(start[0]["kind"]), &"first")
	assert_eq(StringName(start[1]["kind"]), &"second")
	assert_eq(host.menu_entries(Gen2ModHost.MENU_PACK_POCKET).size(), 1)


func test_a_menu_entry_is_refused_rather_than_silently_dropped() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_eq(
		StringName(host.register_menu_entry(&"nowhere", &"x", {"label": "X"})["reason"]),
		&"unknown_menu"
	)
	assert_eq(
		StringName(host.register_menu_entry(Gen2ModHost.MENU_START, &"", {"label": "X"})["reason"]),
		&"invalid_menu_entry"
	)
	assert_eq(
		StringName(host.register_menu_entry(Gen2ModHost.MENU_START, &"x", {})["reason"]),
		&"menu_entry_missing_label"
	)
	# Pocket numbers 1 to 4 are the cartridge's own, so a mod cannot claim one.
	for pocket: int in [0, Gen2WorldPack.TYPE_ITEM, Gen2WorldPack.TYPE_TM_HM]:
		assert_eq(
			StringName(host.register_menu_entry(
				Gen2ModHost.MENU_PACK_POCKET, &"p", {"label": "P", "pocket": pocket}
			)["reason"]),
			&"reserved_pocket", "pocket %d" % pocket
		)
	assert_true(bool(host.register_menu_entry(
		Gen2ModHost.MENU_START, &"x", {"label": "X"}
	).get("ok", false)))
	# Two mods claiming the same id is the conflict a player would want named.
	assert_eq(
		StringName(host.register_menu_entry(
			Gen2ModHost.MENU_START, &"x", {"label": "Other"}
		)["reason"]),
		&"duplicate_menu_entry"
	)
