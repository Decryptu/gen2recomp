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
	# Slot refreshes detach the old cards before queueing them so a pressed card
	# is never freed while its own signal is running. Flush that deletion queue
	# before GUT counts objects that no longer belong to the screen tree.
	await get_tree().process_frame
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
	for slot: int in Gen2SaveStore.MAX_SLOTS:
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


## Slots are created on demand, so a game with no saves lists none at all and
## has nothing selected. The old screen preallocated three empty ones.
func test_save_screen_shows_no_slots_before_any_save_exists() -> void:
	await _open_save_screen()
	var snapshot: Dictionary = _screen.save_screen_snapshot()
	assert_eq(snapshot["selected_slot"], -1)
	assert_eq((snapshot["slots"] as Array).size(), 0)
	assert_eq(snapshot["status"], "", "the old bottom slot prompt is gone")
	for node: Node in _screen.find_children("*", "Label", true, false):
		assert_ne((node as Label).text, "Select a save slot.")
		assert_ne((node as Label).text, "SLOTS", "the slots heading is fully removed")
	var save_title: Label = _screen.find_child("SaveScreenTitle", true, false)
	var game_title: Label = _screen.find_child("SaveScreenGameTitle", true, false)
	assert_not_null(save_title)
	assert_not_null(game_title)
	assert_same(save_title.get_parent(), game_title.get_parent(),
		"game name shares the Save data heading row")
	assert_eq(game_title.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	assert_eq(game_title.autowrap_mode, TextServer.AUTOWRAP_OFF)
	assert_eq(game_title.get_line_count(), 1,
		"the game name stays on one line beside the expanding spacer")


func test_save_screen_distinguishes_an_occupied_slot() -> void:
	var write: Dictionary = Gen2SaveStore.save(_save(), _data)
	assert_true(write["ok"], write["message"])
	await _open_save_screen()
	var snapshot: Dictionary = _screen.save_screen_snapshot()
	# Only occupied slots are listed, so the one save is the only row and its
	# slot number is no longer its index.
	assert_eq((snapshot["slots"] as Array).size(), 1)
	var second: Dictionary = snapshot["slots"][0]
	assert_eq(second["slot"], 1)
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


## The launcher no longer writes a save. `NewGame` reaches `InitializeWorld`
## only after the intro has run, so starting one stages the slot and the label
## and leaves the disk alone; [Gen2IntroScreen] writes it once the trainer has a
## name.
func test_starting_a_new_game_stages_the_slot_and_writes_nothing() -> void:
	await _open_save_screen()
	assert_true(_screen.create_new_game("Run one"))
	assert_false(
		Gen2SaveStore.exists(_data.id, _data.sha1, 0),
		"no slot on disk until the intro finishes"
	)
	assert_eq(GameRuntime.selected_game_id, _data.id)
	var pending: Dictionary = GameRuntime.take_pending_new_game()
	assert_eq(int(pending["slot"]), 0)
	assert_eq(String(pending["label"]), "Run one")


## The only name the launcher takes is the save's own. The field is the slot
## label's, not the trainer's, and it accepts the label's own length rather than
## the trainer name's ten.
func test_the_new_game_form_asks_for_a_save_name_not_a_trainer_name() -> void:
	await _open_save_screen()
	assert_true(_screen.open_new_slot())
	assert_true(_screen.save_screen_snapshot()["new_game_form"])
	assert_true(
		_screen.create_new_game("Second playthrough"),
		"a label past the trainer name's limit is still accepted"
	)
	GameRuntime.take_pending_new_game()


func test_a_save_name_past_its_own_limit_is_refused() -> void:
	await _open_save_screen()
	assert_false(_screen.create_new_game("x".repeat(Gen2SaveData.MAX_LABEL + 1)))
	assert_eq(GameRuntime.pending_new_game_slot, -1, "nothing was staged")


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


## `CopyBoxmonSpecies` ends every list with the row its `ld a, -1` terminator
## becomes, and `BillsPC_PressDown` stops the cursor on it.
func test_box_screen_lists_the_party_with_a_cancel_row() -> void:
	var save: Gen2SaveData = _save_with_two()
	await _open_box_screen(save)
	var rows: Array = _box_screen.rows()
	assert_eq(rows.size(), 3)
	assert_eq(String((rows[0] as Dictionary)["name"]), "SPARKY")
	assert_true(bool((rows[2] as Dictionary)["cancel"]))
	for _press: int in 5:
		_box_screen.handle_button(Gen2Button.DOWN)
	var snapshot: Dictionary = _box_screen.box_snapshot()
	assert_eq(int(snapshot["cursor"]) + int(snapshot["scroll"]), rows.size() - 1)


## `BillsPC_PressRight` walks the party and every box round, and the row the
## cursor stands on is what a transfer takes.
func test_box_screen_walks_boxes_and_deposits_the_row_under_the_cursor() -> void:
	var save: Gen2SaveData = _save_with_two()
	await _open_box_screen(save)
	_box_screen.handle_button(Gen2Button.DOWN)
	_box_screen.handle_button(Gen2Button.A)
	assert_eq(save.party.size(), 1)
	assert_not_null(save.boxes[0].slots[0])
	_box_screen.handle_button(Gen2Button.RIGHT)
	assert_eq(int(_box_screen.box_snapshot()["loaded"]), 1)
	assert_eq(String(_box_screen.rows()[0]["name"]), "GEODUDE")
	_box_screen.handle_button(Gen2Button.A)
	assert_eq(save.party.size(), 2)
	assert_null(save.boxes[0].slots[0])
	for _press: int in Gen2SaveData.BOX_COUNT:
		_box_screen.handle_button(Gen2Button.RIGHT)
	assert_eq(int(_box_screen.box_snapshot()["loaded"]), Gen2BoxScreen.LOADED_PARTY)


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


## Slot management. The store's own rules are covered by test_save_slots.gd;
## these check the screen reaches them and reports what happened.
func test_the_screen_opens_a_new_slot_at_the_lowest_free_number() -> void:
	var write: Dictionary = Gen2SaveStore.save(_save(), _data)
	assert_true(write["ok"], write["message"])
	await _open_save_screen()

	assert_true(_screen.open_new_slot())
	var snapshot: Dictionary = _screen.save_screen_snapshot()
	assert_eq(
		snapshot["selected_slot"], 0,
		"slot 1 is taken, so the new one is slot 0",
	)
	# The slot number alone is not the button working. A free slot has no row in
	# `slots_for`, and a details pane that refuses to draw one leaves the player
	# looking at an empty screen with no way to name a save.
	assert_true(snapshot["new_game"], "the form is asked for")
	assert_true(snapshot["new_game_form"], "and is actually on screen")


## A free slot is not a file, so the four things that act on the file are not
## offered on one. Cancelling back onto it leaves the slot described rather than
## blank.
func test_cancelling_a_new_slot_describes_it_instead_of_blanking_the_pane() -> void:
	assert_true(Gen2SaveStore.save(_save(), _data)["ok"])
	await _open_save_screen()

	assert_true(_screen.open_new_slot())
	_screen.cancel_new_game()
	var snapshot: Dictionary = _screen.save_screen_snapshot()

	assert_false(snapshot["new_game"])
	assert_false(snapshot["new_game_form"])
	assert_eq(snapshot["selected_slot"], 0, "still pointing at the free slot")


## The form opens on a game with no saves at all, which is the only way into a
## first playthrough from the launcher.
func test_a_game_with_no_saves_can_still_open_the_new_game_form() -> void:
	await _open_save_screen()
	assert_eq(_screen.save_screen_snapshot()["selected_slot"], -1, "nothing to select")

	assert_true(_screen.open_new_slot())
	var snapshot: Dictionary = _screen.save_screen_snapshot()

	assert_eq(snapshot["selected_slot"], 0)
	assert_true(snapshot["new_game_form"])
	assert_true(_screen.create_new_game())
	assert_eq(int(GameRuntime.take_pending_new_game()["slot"]), 0)


func test_creating_a_new_game_with_nothing_selected_takes_a_free_slot() -> void:
	await _open_save_screen()
	assert_eq(_screen.save_screen_snapshot()["selected_slot"], -1)

	assert_true(_screen.create_new_game())
	assert_eq(int(GameRuntime.take_pending_new_game()["slot"]), 0)


func test_renaming_from_the_screen_reaches_the_slot() -> void:
	assert_true(Gen2SaveStore.save(_save(), _data)["ok"])
	await _open_save_screen()
	assert_true(_screen.select_slot(1))

	assert_true(Gen2SaveStore.rename_slot(_data.id, _data.sha1, 1, "Run two", _data)["ok"])
	_screen.set_data(_data)

	var rows: Array = _screen.save_screen_snapshot()["slots"]
	assert_eq(rows[0]["label"], "Run two")


## The reported "the app exits after Create save": every details-pane button
## rebuilds the pane it sits in, so the node emitting `pressed` was one of the
## children `_refresh_details` freed outright, and the engine walked a destroyed
## object on the way back out of the signal. The API-driven cases above cannot
## see it, because nothing is emitting when they call.
func test_a_details_pane_button_survives_the_rebuild_it_triggers() -> void:
	assert_true(Gen2SaveStore.save(_save(), _data)["ok"])
	await _open_save_screen()
	assert_true(_screen.select_slot(1))
	_press_and_outlive("Rename")
	assert_eq(_screen.save_screen_snapshot()["status"], "Renamed slot 2.")

	assert_true(_screen.open_new_game(1))
	_press_and_outlive("Cancel")
	assert_false(_screen.save_screen_snapshot()["new_game_form"], "the form closed")

	assert_true(_screen.open_new_game(1))
	_press_and_outlive("Start game")
	assert_eq(int(GameRuntime.take_pending_new_game()["slot"]), 1, "the press did the work")


## Presses the pane button [param label] and asserts it is still a live object
## when its own `pressed` returns. Reading the pending new game after a frame
## would not: the press hands the tree a deferred scene change.
func _press_and_outlive(label: String) -> void:
	var button: Button = _find_button(_screen, label)
	assert_not_null(button, "%s is on the pane" % label)
	button.pressed.emit()
	assert_true(
		is_instance_valid(button),
		"%s is still alive when its own signal returns" % label,
	)


## First button under [param node] whose text is [param label], or null.
func _find_button(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text == label:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, label)
		if found != null:
			return found
	return null
