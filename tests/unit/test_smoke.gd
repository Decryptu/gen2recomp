extends GutTest

## GUT silently skips a test script that fails to parse, so a broken file shows
## up as a *smaller* run that still reports green. Loading every script
## explicitly turns that into a visible failure. Don't delete this test.

const ROOTS: Array[String] = ["res://game", "res://autoload", "res://tests", "res://tools"]


func _gd_files(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			_gd_files(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func test_every_script_parses() -> void:
	var scripts: PackedStringArray = []
	for root: String in ROOTS:
		_gd_files(root, scripts)

	assert_gt(scripts.size(), 0, "found no scripts to check; is the walk broken?")
	for path: String in scripts:
		assert_not_null(load(path), "failed to load %s" % path)


func test_main_scene_loads_and_keeps_its_script() -> void:
	var packed: PackedScene = load("res://game/main/main.tscn")
	assert_not_null(packed)
	var instance: Node = packed.instantiate()
	# A .tscn root that lost its `script =` line still loads and resolves every
	# node; it just does nothing. Cheap to assert, expensive to debug.
	assert_not_null(instance.get_script(), "main.tscn root lost its script")
	instance.free()
