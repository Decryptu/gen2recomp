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


func _clear() -> void:
	var root: DirAccess = DirAccess.open(ROOT)
	if root == null:
		return
	for name: String in root.get_directories():
		var mod: DirAccess = DirAccess.open("%s/%s" % [ROOT, name])
		if mod != null:
			for file: String in mod.get_files():
				DirAccess.remove_absolute("%s/%s/%s" % [ROOT, name, file])
		DirAccess.remove_absolute("%s/%s" % [ROOT, name])
	DirAccess.remove_absolute(ROOT)


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _write_manifest(source: Dictionary) -> void:
	_write("%s/mod.json" % _directory, JSON.stringify(source))


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
