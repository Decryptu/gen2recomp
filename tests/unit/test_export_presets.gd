extends GutTest

## Development-only trees must never reach a distributable pack. This audits
## every preset, so adding a platform cannot quietly restore example mods.

func test_every_export_preset_excludes_tests_tools_and_repository_mods() -> void:
	var text: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	var preset_count: int = 0
	var current: String = ""
	for line: String in text.split("\n"):
		if line.begins_with("[preset.") and not line.contains(".options]"):
			current = line
			preset_count += 1
			continue
		if not line.begins_with("exclude_filter="):
			continue
		assert_ne(current, "", "an exclusion belongs to a preset")
		for excluded: String in ["tests/*", "tools/*", "addons/gut/*", "mods/*"]:
			assert_string_contains(line, excluded, "preset %s excludes %s" % [current, excluded])
	assert_eq(preset_count, 5)
