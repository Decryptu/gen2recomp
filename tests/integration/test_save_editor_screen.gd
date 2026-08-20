extends GutTest

## Drives the real editor scene. The rules are covered by test_save_editor.gd;
## this checks the screen shows what the editor holds and reports a refusal
## instead of quietly leaving a stale control on screen.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _screen: Control = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"savetest", "0123456789abcdef")
	_data = Fixture.build(_directory)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	Gen2SaveStore.delete_slot(_data.id, _data.sha1, 0)
	RomCache.clear(_directory)


func _save() -> Gen2SaveData:
	var pikachu: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 20, [Fixture.TACKLE], Gen2BattleMon.PERFECT_DVS
	)
	return Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, 0, Gen2Party.create([pikachu]), "RED"
	)


func _open(save: Gen2SaveData = null) -> void:
	var packed: PackedScene = load("res://game/save/save_editor_screen.tscn")
	_screen = packed.instantiate()
	add_child(_screen)
	await get_tree().process_frame
	_screen.set_editor(Gen2SaveEditor.open(save if save != null else _save(), _data))


func test_the_screen_opens_a_save_and_reports_it_valid() -> void:
	await _open()
	var snapshot: Dictionary = _screen.editor_snapshot()

	assert_true(snapshot["open"])
	assert_true(snapshot["valid"], snapshot["message"])
	assert_false(snapshot["dirty"])
	assert_eq(snapshot["player_name"], "RED")
	assert_eq((snapshot["party"] as Array).size(), 1)


func test_a_screen_with_no_save_reports_closed() -> void:
	var packed: PackedScene = load("res://game/save/save_editor_screen.tscn")
	_screen = packed.instantiate()
	add_child(_screen)
	await get_tree().process_frame

	assert_false(_screen.editor_snapshot()["open"])


func test_every_tab_can_be_selected_by_name() -> void:
	await _open()
	for tab: StringName in _screen.TABS:
		assert_true(_screen.select_tab(tab), String(tab))
		assert_eq(_screen.editor_snapshot()["tab"], tab)
	assert_false(_screen.select_tab(&"nowhere"))


func test_selecting_a_party_member_that_is_not_there_is_refused() -> void:
	await _open()
	assert_true(_screen.select_party_member(0))
	assert_eq(_screen.editor_snapshot()["selected_party"], 0)
	assert_false(_screen.select_party_member(3))


func test_saving_writes_the_slot_and_leaves_it_clean() -> void:
	await _open()
	assert_true(_screen.select_party_member(0))
	var editor: Gen2SaveEditor = Gen2SaveEditor.open(_save(), _data)
	_screen.set_editor(editor)
	assert_true(editor.set_player_name("ASH")["ok"])
	assert_true(_screen.editor_snapshot()["dirty"])

	assert_true(_screen.save_now())
	assert_false(_screen.editor_snapshot()["dirty"])

	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(loaded["ok"], loaded["message"])
	assert_eq((loaded["save"] as Gen2SaveData).player_name, "ASH")
	## A second editor rebuilds every row, and the rows it replaces are dropped
	## with `queue_free`: the game serves those at the end of its frame and a
	## test has to spend one to see it.
	await get_tree().process_frame


func test_reloading_drops_uncommitted_edits() -> void:
	var stored: Gen2SaveData = _save()
	assert_true(Gen2SaveStore.save(stored, _data)["ok"])
	await _open(stored)

	var editor: Gen2SaveEditor = Gen2SaveEditor.open(stored, _data)
	_screen.set_editor(editor)
	assert_true(editor.set_player_name("ASH")["ok"])

	assert_true(_screen.reload_now())
	assert_eq(_screen.editor_snapshot()["player_name"], "RED")
	assert_false(_screen.editor_snapshot()["dirty"])


## The fixture cache has no maps, so a world snapshot on it is exactly the case
## the map tab must refuse rather than write.
func test_a_save_without_world_state_still_opens() -> void:
	await _open()
	assert_false(_screen.editor_snapshot()["has_world"])
	assert_true(_screen.select_tab(&"items"))
	assert_true(_screen.editor_snapshot()["valid"])
