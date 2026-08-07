extends GutTest

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _screen: Gen2SaveScreen = null
var _party_screen: Gen2PartyScreen = null
var _box_screen: Gen2BoxScreen = null
var _save_directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"screentest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_save_directory = "%s/testgame_01234567" % Gen2SaveStore.ROOT
	_clear_saves()


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	if is_instance_valid(_party_screen):
		_party_screen.free()
		_party_screen = null
	if is_instance_valid(_box_screen):
		_box_screen.free()
		_box_screen = null
	_clear_saves()
	RomCache.clear(_directory)


func _clear_saves() -> void:
	for slot: int in Gen2SaveStore.SLOT_COUNT:
		var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, slot)
		for copy: String in [path, "%s.bak" % path, "%s.tmp" % path, "%s.bak.tmp" % path]:
			if FileAccess.file_exists(copy):
				DirAccess.remove_absolute(copy)
	if DirAccess.dir_exists_absolute(_save_directory):
		DirAccess.remove_absolute(_save_directory)


func _save() -> Gen2SaveData:
	var mon: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 20, [Fixture.TACKLE, Fixture.THUNDERBOLT]
	)
	mon.status = Gen2Status.POISON
	var save: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, 1, Gen2Party.of(mon), "RED"
	)
	(save.party[0] as Gen2SaveMon).nickname = "SPARKY"
	return save


func _save_with_two() -> Gen2SaveData:
	var save: Gen2SaveData = _save()
	var second: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.GEODUDE, 18, [Fixture.GROWL]
	)
	save.party.append(Gen2SaveBattleAdapter.from_battle_mon(second))
	return save


func _open_save_screen() -> void:
	var packed: PackedScene = load("res://game/save/save_screen.tscn")
	_screen = packed.instantiate()
	_screen.set_data(_data)
	add_child(_screen)
	await get_tree().process_frame


func _open_party_screen(save: Gen2SaveData) -> void:
	var packed: PackedScene = load("res://game/save/party_screen.tscn")
	_party_screen = packed.instantiate()
	_party_screen.set_context(_data, save)
	add_child(_party_screen)
	await get_tree().process_frame


func _open_box_screen(save: Gen2SaveData) -> void:
	var packed: PackedScene = load("res://game/save/box_screen.tscn")
	_box_screen = packed.instantiate()
	_box_screen.set_context(_data, save)
	add_child(_box_screen)
	await get_tree().process_frame


func test_save_screen_shows_three_empty_slots() -> void:
	await _open_save_screen()
	var snapshot: Dictionary = _screen.save_screen_snapshot()
	assert_eq(snapshot["selected_slot"], 0)
	assert_eq((snapshot["slots"] as Array).size(), Gen2SaveStore.SLOT_COUNT)
	for row: Dictionary in snapshot["slots"]:
		assert_false(row["exists"])
		assert_false(row["valid"])


func test_save_screen_distinguishes_an_occupied_slot() -> void:
	var write: Dictionary = Gen2SaveStore.save(_save(), _data)
	assert_true(write["ok"], write["message"])
	await _open_save_screen()
	var snapshot: Dictionary = _screen.save_screen_snapshot()
	var second: Dictionary = snapshot["slots"][1]
	assert_true(second["exists"])
	assert_true(second["valid"])
	assert_true(_screen.select_slot(1))
	assert_eq(_screen.save_screen_snapshot()["selected_slot"], 1)


func test_save_screen_marks_an_invalid_existing_slot_incompatible() -> void:
	var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, 0)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"format_version": Gen2SaveData.FORMAT_VERSION,
		"game_id": String(_data.id),
		"rom_sha1": "different",
		"slot": 0,
		"player_name": "RED",
		"party": [],
	}))
	file.close()
	await _open_save_screen()
	var first: Dictionary = _screen.save_screen_snapshot()["slots"][0]
	assert_true(first["exists"])
	assert_false(first["valid"])
	assert_string_contains(first["message"], "different cartridge")


func test_save_screen_creates_a_valid_new_game() -> void:
	await _open_save_screen()
	assert_true(_screen.create_new_game("ASH", 155))
	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(loaded["ok"], loaded["message"])
	var save: Gen2SaveData = loaded["save"]
	assert_eq(save.player_name, "ASH")
	assert_eq(save.party.size(), 0)
	assert_string_contains(_screen.save_screen_snapshot()["detail"], "starter")


func test_save_screen_rejects_an_invalid_sram_without_creating_a_slot() -> void:
	await _open_save_screen()
	var path: String = "user://save-screen-invalid.sav"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([0x01, 0x02, 0x03]))
	file.close()
	assert_false(_screen.import_sav_path(path))
	assert_false(Gen2SaveStore.exists(_data.id, _data.sha1, 0))
	DirAccess.remove_absolute(path)


func test_party_screen_exposes_saved_hp_status_and_empty_positions() -> void:
	var save: Gen2SaveData = _save()
	await _open_party_screen(save)
	var snapshot: Dictionary = _party_screen.party_snapshot()
	assert_eq(snapshot["player_name"], "RED")
	assert_eq(snapshot["slot"], 1)
	var members: Array = snapshot["members"]
	assert_eq(members.size(), Gen2SaveData.MAX_PARTY)
	assert_eq((members[0] as Dictionary)["name"], "SPARKY")
	assert_eq((members[0] as Dictionary)["status"], "POISON")
	assert_false((members[0] as Dictionary)["empty"])
	assert_true((members[1] as Dictionary)["empty"])


func test_box_screen_exposes_all_fourteen_fixed_boxes_and_slots() -> void:
	var save: Gen2SaveData = _save()
	await _open_box_screen(save)
	var snapshot: Dictionary = _box_screen.box_snapshot()
	var boxes: Array = snapshot["boxes"]
	assert_eq(boxes.size(), Gen2SaveData.BOX_COUNT)
	assert_eq((boxes[0]["slots"] as Array).size(), Gen2SaveBox.CAPACITY)
	assert_true((boxes[0]["slots"][0] as Dictionary)["empty"])


func test_pc_storage_moves_party_to_box_and_back_through_atomic_save() -> void:
	var save: Gen2SaveData = _save_with_two()
	var initial_write: Dictionary = Gen2SaveStore.save(save, _data)
	assert_true(initial_write["ok"], initial_write["message"])
	await _open_box_screen(save)
	assert_true(_box_screen.select_party_member(0))
	assert_true(_box_screen.deposit_selected_party())
	assert_eq(save.party.size(), 1)
	assert_not_null(save.boxes[0].slots[0])
	assert_true(_box_screen.select_box_slot(0))
	assert_true(_box_screen.withdraw_selected_box())
	assert_eq(save.party.size(), 2)
	assert_null(save.boxes[0].slots[0])
	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, save.slot, _data)
	assert_true(loaded["ok"], loaded["message"])
	var restored: Gen2SaveData = loaded["save"]
	assert_eq(restored.party.size(), 2)
	assert_null(restored.boxes[0].slots[0])


func test_pc_storage_refuses_depositing_the_last_party_member() -> void:
	var save: Gen2SaveData = _save()
	var result: Dictionary = Gen2SaveStorage.deposit_party_to_box(save, _data, 0, 0)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"last_party_member")
	assert_eq(save.party.size(), 1)
	assert_null(save.boxes[0].slots[0])


func test_pc_storage_can_commit_in_memory_without_writing_slot() -> void:
	var save: Gen2SaveData = _save_with_two()
	var result: Dictionary = Gen2SaveStorage.deposit_party_to_box(save, _data, 0, 0, -1, false)
	assert_true(result["ok"])
	assert_false(result["persisted"])
	assert_eq(save.party.size(), 1)
	assert_not_null(save.boxes[0].slots[0])
	assert_false(Gen2SaveStore.exists(_data.id, _data.sha1, save.slot))
