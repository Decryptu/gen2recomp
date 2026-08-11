extends GutTest

func test_semantic_versions_are_strict_three_part_numbers() -> void:
	for valid: String in ["0.0.0", "1.2.3", "12.0.45"]:
		assert_true(Gen2ModVersion.valid_version(valid), valid)
	for invalid: String in ["", "1", "1.2", "v1.2.3", "1.2.3-beta", "01.2.3"]:
		assert_false(Gen2ModVersion.valid_version(invalid), invalid)


func test_ranges_cover_exact_comparison_caret_tilde_and_wildcards() -> void:
	assert_true(Gen2ModVersion.matches("1.4.2", "1.4.2"))
	assert_true(Gen2ModVersion.matches("1.4.2", ">=1.0.0 <2.0.0"))
	assert_false(Gen2ModVersion.matches("2.0.0", ">=1.0.0 <2.0.0"))
	assert_true(Gen2ModVersion.matches("1.9.0", "^1.2.3"))
	assert_false(Gen2ModVersion.matches("2.0.0", "^1.2.3"))
	assert_true(Gen2ModVersion.matches("1.2.9", "~1.2.3"))
	assert_false(Gen2ModVersion.matches("1.3.0", "~1.2.3"))
	assert_true(Gen2ModVersion.matches("1.8.4", "1.x"))
	assert_true(Gen2ModVersion.matches("1.8.4", "1.8.*"))
	assert_false(Gen2ModVersion.matches("1.9.0", "1.8.*"))


func test_zero_major_caret_ranges_stop_at_the_next_nonzero_component() -> void:
	assert_true(Gen2ModVersion.matches("0.2.8", "^0.2.3"))
	assert_false(Gen2ModVersion.matches("0.3.0", "^0.2.3"))
	assert_true(Gen2ModVersion.matches("0.0.3", "^0.0.3"))
	assert_false(Gen2ModVersion.matches("0.0.4", "^0.0.3"))
	assert_false(Gen2ModVersion.matches("0.0.5", "^0.0.3"))


func test_malformed_ranges_are_refused_instead_of_partially_read() -> void:
	for invalid: String in [
		"latest", ">=1.0", "1.*.3", "01.x", ">=1.x", "^^1.0.0", "1.2.3 || 2.0.0"
	]:
		assert_false(Gen2ModVersion.valid_range(invalid), invalid)
