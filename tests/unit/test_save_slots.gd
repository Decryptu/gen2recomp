extends GutTest

## Dynamic slot creation, naming, export and import. Shares the synthetic cache
## the other save tests use, so nothing here needs a cartridge.

const Fixture := preload("res://tests/unit/battle_fixture.gd")
const EXPORT_PATH: String = "user://slot-export-test.json"

var _directory: String = ""
var _data: GameData = null
var _save_directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"savetest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_save_directory = Gen2SaveStore.directory_for(_data.id, _data.sha1)
	_clear_saves()


func after_each() -> void:
	_clear_saves()
	DirAccess.remove_absolute(EXPORT_PATH)
	RomCache.clear(_directory)


func _clear_saves() -> void:
	for slot: int in Gen2SaveStore.MAX_SLOTS:
		var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, slot)
		for copy: String in [path, "%s.bak" % path, "%s.tmp" % path, "%s.bak.tmp" % path]:
			if FileAccess.file_exists(copy):
				DirAccess.remove_absolute(copy)
	if DirAccess.dir_exists_absolute(_save_directory):
		DirAccess.remove_absolute(_save_directory)


func _write_slot(slot: int, player_name: String = "RED") -> Gen2SaveData:
	var mon: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 20, [Fixture.TACKLE], Gen2BattleMon.PERFECT_DVS
	)
	var save: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, slot, Gen2Party.create([mon]), player_name
	)
	var result: Dictionary = Gen2SaveStore.save(save, _data)
	assert_true(result["ok"], result["message"])
	return save


func test_a_game_with_no_saves_lists_nothing() -> void:
	assert_eq(Gen2SaveStore.occupied_slots(_data.id, _data.sha1), [] as Array[int])
	assert_eq(Gen2SaveStore.slots_for(_data.id, _data.sha1, _data).size(), 0)


func test_occupied_slots_reports_written_slots_in_order() -> void:
	_write_slot(4)
	_write_slot(0)

	assert_eq(Gen2SaveStore.occupied_slots(_data.id, _data.sha1), [0, 4] as Array[int])


func test_a_slot_with_only_a_backup_copy_still_counts_as_occupied() -> void:
	_write_slot(2)
	DirAccess.remove_absolute(Gen2SaveStore.path_for(_data.id, _data.sha1, 2))

	assert_eq(Gen2SaveStore.occupied_slots(_data.id, _data.sha1), [2] as Array[int])


func test_next_free_slot_reuses_the_lowest_gap() -> void:
	_write_slot(0)
	_write_slot(1)
	_write_slot(3)

	assert_eq(Gen2SaveStore.next_free_slot(_data.id, _data.sha1), 2)


func test_next_free_slot_starts_at_zero_for_a_new_game() -> void:
	assert_eq(Gen2SaveStore.next_free_slot(_data.id, _data.sha1), 0)


func test_slot_rows_carry_the_label_and_player_name() -> void:
	_write_slot(0, "ASH")
	assert_true(Gen2SaveStore.rename_slot(_data.id, _data.sha1, 0, "Nuzlocke", _data)["ok"])

	var rows: Array = Gen2SaveStore.slots_for(_data.id, _data.sha1, _data)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["label"], "Nuzlocke")
	assert_eq(rows[0]["player_name"], "ASH")


func test_renaming_trims_and_survives_a_reload() -> void:
	_write_slot(0)
	assert_true(Gen2SaveStore.rename_slot(_data.id, _data.sha1, 0, "  Run two  ", _data)["ok"])

	var result: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(result["ok"], result["message"])
	assert_eq((result["save"] as Gen2SaveData).label, "Run two")


func test_an_overlong_label_is_refused_without_touching_the_save() -> void:
	_write_slot(0)
	var long_name: String = "x".repeat(Gen2SaveData.MAX_LABEL + 1)

	var result: Dictionary = Gen2SaveStore.rename_slot(_data.id, _data.sha1, 0, long_name, _data)
	assert_false(result["ok"])

	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_eq((loaded["save"] as Gen2SaveData).label, "")


func test_renaming_an_empty_slot_fails() -> void:
	assert_false(Gen2SaveStore.rename_slot(_data.id, _data.sha1, 0, "ghost", _data)["ok"])


func test_export_then_import_round_trips_into_a_free_slot() -> void:
	_write_slot(0, "ASH")
	assert_true(Gen2SaveStore.rename_slot(_data.id, _data.sha1, 0, "Nuzlocke", _data)["ok"])
	assert_true(Gen2SaveStore.export_slot(_data.id, _data.sha1, 0, EXPORT_PATH)["ok"])

	var imported: Dictionary = Gen2SaveStore.import_slot(EXPORT_PATH, _data)
	assert_true(imported["ok"], imported["message"])
	assert_eq(imported["slot"], 1, "the export lands in the next free slot")

	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 1, _data)
	assert_true(loaded["ok"], loaded["message"])
	var save: Gen2SaveData = loaded["save"]
	assert_eq(save.player_name, "ASH")
	assert_eq(save.label, "Nuzlocke", "the label travels inside the file")
	assert_eq(save.slot, 1, "the imported copy owns its new slot number")


func test_exporting_an_empty_slot_writes_nothing() -> void:
	assert_false(Gen2SaveStore.export_slot(_data.id, _data.sha1, 0, EXPORT_PATH)["ok"])
	assert_false(FileAccess.file_exists(EXPORT_PATH))


## Written without the container header, which `_unwrap` accepts unchecked as
## the pre-container path, so this reaches the identity guard rather than
## stopping at a checksum the test would otherwise have to recompute.
func test_importing_another_cartridges_save_is_refused() -> void:
	var raw: Dictionary = _write_slot(0).to_dict()
	raw["rom_sha1"] = "fedcba9876543210"
	var file: FileAccess = FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()

	var result: Dictionary = Gen2SaveStore.import_slot(EXPORT_PATH, _data)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "different cartridge")


func test_importing_a_damaged_file_is_refused() -> void:
	var file: FileAccess = FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	file.store_string("not a save at all")
	file.close()

	assert_false(Gen2SaveStore.import_slot(EXPORT_PATH, _data)["ok"])


func test_importing_a_file_whose_checksum_was_broken_is_refused() -> void:
	_write_slot(0)
	assert_true(Gen2SaveStore.export_slot(_data.id, _data.sha1, 0, EXPORT_PATH)["ok"])
	var reader: FileAccess = FileAccess.open(EXPORT_PATH, FileAccess.READ)
	var text: String = reader.get_as_text()
	reader.close()
	var writer: FileAccess = FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	writer.store_string(text.replace("\"player_name\": \"RED\"", "\"player_name\": \"BLU\""))
	writer.close()

	var result: Dictionary = Gen2SaveStore.import_slot(EXPORT_PATH, _data)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "checksum")


func test_a_version_two_save_migrates_by_gaining_an_empty_label() -> void:
	var raw: Dictionary = _write_slot(0).to_dict()
	raw["format_version"] = 2
	raw.erase("label")

	var migration: Dictionary = Gen2SaveData.migrate_dict(raw)
	assert_true(migration["ok"], migration.get("message", ""))
	assert_true(migration["migrated"])
	assert_eq(migration["data"]["format_version"], Gen2SaveData.FORMAT_VERSION)
	assert_eq(migration["data"]["label"], "")


func test_a_version_one_save_gains_both_boxes_and_a_label() -> void:
	var raw: Dictionary = _write_slot(0).to_dict()
	raw["format_version"] = 1
	raw.erase("boxes")
	raw.erase("label")

	var migration: Dictionary = Gen2SaveData.migrate_dict(raw)
	assert_true(migration["ok"], migration.get("message", ""))
	assert_eq((migration["data"]["boxes"] as Array).size(), Gen2SaveData.BOX_COUNT)
	assert_eq(migration["data"]["label"], "")


func test_a_save_from_a_later_format_is_refused_rather_than_guessed_at() -> void:
	var raw: Dictionary = _write_slot(0).to_dict()
	raw["format_version"] = Gen2SaveData.FORMAT_VERSION + 1

	assert_false(Gen2SaveData.migrate_dict(raw)["ok"])
