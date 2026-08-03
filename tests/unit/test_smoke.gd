extends GutTest

## GUT silently skips a test script that fails to parse, so a broken file shows
## up as a *smaller* run that still reports green. Loading every script
## explicitly turns that into a visible failure. Don't delete this test.

const ROOTS: Array[String] = ["res://game", "res://autoload", "res://tests", "res://tools"]


func _files(dir_path: String, extension: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			_files(full, extension, out)
		elif name.ends_with(extension):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func test_every_script_parses() -> void:
	var scripts: PackedStringArray = []
	for root: String in ROOTS:
		_files(root, ".gd", scripts)

	assert_gt(scripts.size(), 0, "found no scripts to check; is the walk broken?")
	for path: String in scripts:
		# A script that failed to parse is not null. It comes back as a real
		# GDScript with its source code attached, no methods on it and nothing
		# behind it, so the failure this test exists to catch is invisible to a
		# null check and shows up here instead. Asking the loader to bypass its
		# cache would also see it, and would re-parse scripts that are running at
		# the time, which corrupts them mid-call.
		var script: Variant = load(path)
		assert_not_null(script, "failed to load %s" % path)
		if script is GDScript:
			assert_true((script as GDScript).can_instantiate(), "failed to parse %s" % path)


func test_every_scene_loads_and_keeps_its_script() -> void:
	var scenes: PackedStringArray = []
	_files("res://game", ".tscn", scenes)

	assert_gt(scenes.size(), 0, "found no scenes to check; is the walk broken?")
	for path: String in scenes:
		var packed: PackedScene = load(path)
		assert_not_null(packed, "failed to load %s" % path)
		if packed == null:
			continue
		var instance: Node = packed.instantiate()
		# A .tscn root that lost its `script =` line still loads and resolves
		# every node; it just does nothing. Cheap to assert, expensive to debug.
		assert_not_null(instance.get_script(), "%s root lost its script" % path)
		instance.free()
