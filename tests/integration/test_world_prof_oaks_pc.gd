extends GutTest

## Scene integration for Prof Oak's PC: the three pages `ProfOaksPCBoot` shows,
## the input they hold, and the script text they stand in front of.
##
## `OaksLab`'s own script is `special ProfOaksPCBoot`, `writetext` and
## `waitbutton`, and the special blocks on the cartridge while it does not here,
## so the ordering between the two is what this covers.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const PLAYER_CELL: Vector2i = Vector2i(2, 2)
const TUTORIAL_CELL: Vector2i = Vector2i(4, 5)
const GOODBYE_TEXT: int = 0x6400
## Each page takes two presses: one completes the reveal, the next advances.
const PRESSES_PER_PAGE: int = 2

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	Fixture.build()
	_write_oak_script()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


## `maps/OaksLab.asm`'s `.CheckPokedex` tail, on the fixture's coord event.
func _write_oak_script() -> void:
	var directory: String = Fixture.directory()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(directory))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, Fixture.TUTORIAL_SCRIPT)] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_PROF_OAKS_PC_BOOT, 0x00,
		Gen2WorldScript.WRITETEXT, GOODBYE_TEXT & 0xFF, GOODBYE_TEXT >> 8,
		Gen2WorldScript.WAITBUTTON,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(directory), scripts)
	var text: Dictionary = RomCache.read_json(RomCache.world_text_path(directory))
	text[Gen2WorldScript.pointer_key(Fixture.BANK, GOODBYE_TEXT)] = [0x00, 0x81, 0xE8, 0x57]
	RomCache.write_json(RomCache.world_text_path(directory), text)


func _open_world() -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = PLAYER_CELL
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, PLAYER_CELL, Gen2WorldState.new()
	)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(_data, 0)
	save.world = world.snapshot()
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame


func _run_script() -> void:
	_world_screen._show_script_results(
		_world_screen._world.dispatch_script_events(TUTORIAL_CELL)
	)


func test_the_special_opens_its_three_pages_in_front_of_the_script_text() -> void:
	await _open_world()
	_run_script()
	assert_eq(_world_screen._oak_pc_pages.size(), 3)
	## The script has already run on to its `waitbutton`, but its text waits
	## behind the pages rather than being drawn over them.
	assert_eq(
		StringName(_world_screen._world.pending_script_input().get("type", &"")), &"text"
	)
	assert_true(_world_screen._text_box.visible)


func test_a_or_b_walks_the_pages_and_hands_the_box_back_to_the_script() -> void:
	await _open_world()
	_run_script()
	for _press: int in PRESSES_PER_PAGE * 2:
		_world_screen.press_button(Gen2Button.B)
	assert_eq(_world_screen._oak_pc_pages.size(), 1, "the rating is up")

	for _press: int in PRESSES_PER_PAGE:
		_world_screen.press_button(Gen2Button.A)
	assert_eq(_world_screen._oak_pc_pages.size(), 0)
	assert_true(_world_screen._text_box.visible, "the script's own text now")
	assert_eq(_world_screen._script_prompt, "A: advance text")


## `.loop`'s own joypad read swallows everything else, so the map underneath
## stays where it was.
func test_the_pages_hold_the_world() -> void:
	await _open_world()
	_run_script()
	assert_false(_world_screen.move_player(Vector2i.RIGHT))
	assert_false(_world_screen.interact())
