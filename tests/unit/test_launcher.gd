extends GutTest

## Launcher tests use the real scene and synthetic rejected files. They never
## import a cartridge or create cartridge-derived data.

var _launcher: Control = null
var _scratch_path: String = "user://launcher-test-small.gbc"


func after_each() -> void:
	if is_instance_valid(_launcher):
		_launcher.free()
	_launcher = null
	DirAccess.remove_absolute(_scratch_path)


func _open_launcher() -> void:
	var packed: PackedScene = load("res://game/main/main.tscn")
	_launcher = packed.instantiate()
	add_child(_launcher)
	await get_tree().process_frame


func test_launcher_lists_every_supported_game() -> void:
	await _open_launcher()
	var snapshot: Dictionary = _launcher.launcher_snapshot()
	var games: Dictionary = snapshot["games"]

	assert_eq(games.size(), RomRegistry.ORDER.size())
	for game_id: StringName in RomRegistry.ORDER:
		var row: Dictionary = games[String(game_id)]
		assert_eq(row["title"], RomRegistry.title_for(game_id))
		assert_true(row["imported"] is bool)
		assert_false(row["selected"])


func test_launcher_reports_a_rejected_rom_without_importing() -> void:
	await _open_launcher()
	var file: FileAccess = FileAccess.open(_scratch_path, FileAccess.WRITE)
	var bytes := PackedByteArray()
	bytes.resize(1024)
	file.store_buffer(bytes)
	file.close()

	_launcher.import_rom_path(_scratch_path)
	var snapshot: Dictionary = _launcher.launcher_snapshot()

	assert_eq(snapshot["status"], "Import stopped.")
	assert_string_contains(snapshot["detail"], "bytes")
	assert_false(snapshot["importing"])


func test_runtime_selection_accepts_registry_games_and_rejects_unknown_ids() -> void:
	var previous: StringName = GameRuntime.selected_game_id
	var previous_slot: int = GameRuntime.selected_save_slot

	assert_true(GameRuntime.select_game(RomRegistry.CRYSTAL))
	assert_eq(GameRuntime.selected_game_id, RomRegistry.CRYSTAL)
	assert_true(GameRuntime.select_save_slot(RomRegistry.CRYSTAL, 1))
	assert_true(GameRuntime.has_selected_save_slot())
	assert_eq(GameRuntime.selected_save_slot, 1)
	assert_false(GameRuntime.select_game(&"not_a_game"))
	assert_eq(GameRuntime.selected_game_id, RomRegistry.CRYSTAL)
	assert_false(GameRuntime.select_save_slot(RomRegistry.CRYSTAL, Gen2SaveStore.SLOT_COUNT))
	assert_eq(GameRuntime.selected_save_slot, 1)

	GameRuntime.selected_game_id = previous
	GameRuntime.selected_save_slot = previous_slot
	GameRuntime.reload_selected_save()


func test_the_selected_save_is_one_shared_instance_until_the_selection_changes() -> void:
	var previous: StringName = GameRuntime.selected_game_id
	var previous_slot: int = GameRuntime.selected_save_slot
	var data: GameData = GameData.open_any()
	if data == null:
		pass_test("No imported cache on this machine.")
		return

	assert_true(GameRuntime.select_save_slot(data.id, 0))
	var save: Gen2SaveData = GameRuntime.selected_save()
	if save == null:
		pass_test("Slot 0 of the imported cache is empty.")
	else:
		# Two readers must see one save, or a party change made by a battle is
		# invisible to whoever writes the world snapshot.
		assert_same(save, GameRuntime.selected_save())
		GameRuntime.reload_selected_save()
		assert_not_same(save, GameRuntime.selected_save())

	GameRuntime.selected_game_id = previous
	GameRuntime.selected_save_slot = previous_slot
	GameRuntime.reload_selected_save()
