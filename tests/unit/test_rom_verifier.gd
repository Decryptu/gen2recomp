extends GutTest

## These tests never touch a real cartridge; the repo has none and must never
## gain one. Synthetic files cover the rejection paths, and the accept path is
## covered by asserting the registry's own hashes round-trip. Hashing a genuine
## ROM is a manual check: `tools/verify_rom.gd` (see README.md).

const SCRATCH_DIR: String = "user://test_roms"

var _made: PackedStringArray = []


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	_made = []


func after_each() -> void:
	for path: String in _made:
		DirAccess.remove_absolute(path)


func _write_file(name: String, size: int, fill: int = 0) -> String:
	var path: String = "%s/%s" % [SCRATCH_DIR, name]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var buffer: PackedByteArray = []
	buffer.resize(size)
	buffer.fill(fill)
	file.store_buffer(buffer)
	file.close()
	_made.append(path)
	return path


func test_missing_file_reports_not_found() -> void:
	var result: Dictionary = RomVerifier.identify("user://definitely_absent.gbc")
	assert_eq(result["status"], RomVerifier.Status.NOT_FOUND)


func test_wrong_size_is_rejected_before_hashing() -> void:
	var path: String = _write_file("small.gbc", 1024)
	var result: Dictionary = RomVerifier.identify(path)
	assert_eq(result["status"], RomVerifier.Status.WRONG_SIZE)
	# Rejected on size alone, so we never paid for the hash.
	assert_eq(result["sha1"], "")


func test_right_size_but_unknown_contents_is_rejected() -> void:
	var path: String = _write_file("blank.gbc", RomRegistry.EXPECTED_SIZE)
	var result: Dictionary = RomVerifier.identify(path)
	assert_eq(result["status"], RomVerifier.Status.UNKNOWN_ROM)
	assert_eq(result["sha1"].length(), 40, "sha1 should be 40 hex chars")


func test_sha1_matches_a_known_vector() -> void:
	# sha1("abc"), so a broken hashing path fails here rather than silently
	# rejecting every real cartridge as unknown.
	var path: String = "%s/abc.bin" % SCRATCH_DIR
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("abc")
	file.close()
	_made.append(path)
	assert_eq(
		RomVerifier.sha1_of_file(path),
		"a9993e364706816aba3e25717850c26c9cd0d89d"
	)


func test_sha1_of_unreadable_file_is_empty() -> void:
	assert_eq(RomVerifier.sha1_of_file("user://nope.bin"), "")


func test_registry_holds_exactly_the_three_gen2_games() -> void:
	assert_eq(RomRegistry.BY_SHA1.size(), 3)
	assert_eq(RomRegistry.ORDER.size(), 3)


func test_every_registry_id_round_trips() -> void:
	for id: StringName in RomRegistry.ORDER:
		var sha1: String = RomRegistry.sha1_for(id)
		assert_eq(sha1.length(), 40, "%s should have a 40-char sha1" % id)
		assert_true(RomRegistry.is_known(sha1), "%s should be known" % id)
		assert_eq(RomRegistry.lookup(sha1)["id"], id)
		assert_false(RomRegistry.title_for(id).is_empty())


func test_lookup_is_case_insensitive() -> void:
	var sha1: String = RomRegistry.sha1_for(RomRegistry.CRYSTAL)
	assert_true(RomRegistry.is_known(sha1.to_upper()))


func test_hashes_are_lowercase_hex() -> void:
	# lookup() lowercases its argument, so an uppercase key in the table would
	# be permanently unreachable.
	var hex := RegEx.create_from_string("^[0-9a-f]{40}$")
	for sha1: String in RomRegistry.BY_SHA1:
		assert_not_null(hex.search(sha1), "%s is not lowercase hex" % sha1)


func test_unknown_id_yields_no_hash() -> void:
	assert_eq(RomRegistry.sha1_for(&"emerald"), "")
	assert_eq(RomRegistry.title_for(&"emerald"), "")
