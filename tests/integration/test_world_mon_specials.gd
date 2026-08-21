extends GutTest

## Scene integration for the two specials that open `SelectMonFromParty`:
## `NameRater` and `MoveDeletion`. Each is its own line through the overworld,
## two `YesNoBox`es, the party list, and an ending text.
##
## Both maps are `opentext / special / waitbutton / closetext / end`, so the last
## text either special prints is dismissed by the script's own `waitbutton` and
## not by the special. That ordering is what this covers; [Gen2NameRater]'s and
## [Gen2MoveDeleter]'s own branches are unit tested beside the party host.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const PLAYER_CELL: Vector2i = Vector2i(2, 2)
const TALK_CELL: Vector2i = Vector2i(4, 5)

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	Fixture.build()
	_write_name_rater_script()
	_data = GameData.open_directory(Fixture.directory())
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())


func after_each() -> void:
	## The routine drops its party list and its naming screen with `queue_free`,
	## which the tree runs on the next frame and this test never spends: the
	## presses above are hardware frames, not process ones.
	await get_tree().process_frame
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


func _write_name_rater_script(
	special: int = Gen2WorldScriptRunner.SPECIAL_NAME_RATER
) -> void:
	var directory: String = Fixture.directory()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(directory))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, Fixture.TUTORIAL_SCRIPT)] = [
		Gen2WorldScript.SPECIAL, special, 0x00,
		Gen2WorldScript.WAITBUTTON,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(directory), scripts)


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
	world.set_player_id(save.player_id)
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame
	## The box reveals on hardware frames and this test counts presses, so the
	## frames it spends have to be the ones it asks for.
	_world_screen.set_process(false)
	var mon: Gen2SaveMon = save.party[0]
	mon.is_egg = false
	mon.nickname = "SPARKY"
	mon.original_trainer = save.player_name
	mon.ot_id = save.player_id


func _run_script() -> void:
	_world_screen._show_script_results(
		_world_screen._world.dispatch_script_events(TALK_CELL)
	)


func _host() -> Gen2NameRaterScreen:
	return _world_screen._name_rater_host


## Spends whatever the routine's box still owes, which is what a player waits
## through, plus the frame `advance_frame` reads it on: `PrintText` returning is
## what opens a `YesNoBox`, and no press can shorten the printing.
func _settle() -> void:
	var guard: int = 600
	while guard > 0:
		var host: Gen2NameRaterScreen = _host()
		if host == null or host._text_box == null or not host._text_box.is_revealing():
			break
		_world_screen.advance_frame()
		guard -= 1
	_world_screen.advance_frame()


func _press(button: int) -> void:
	_settle()
	_world_screen.press_button(button)


## Walks to the party list: hello, YES, which_mon, the press `prompt` waits for.
func _reach_party() -> void:
	_run_script()
	_press(Gen2Button.A)
	assert_eq(_host().phase(), Gen2NameRaterScreen.Phase.WHICH_MON)
	_press(Gen2Button.A)


func test_the_special_opens_the_routine_and_holds_the_world() -> void:
	await _open_world()
	_run_script()
	assert_not_null(_host())
	assert_false(_world_screen.move_player(Vector2i.RIGHT))
	assert_false(_world_screen.interact())
	_settle()
	assert_eq(_host().phase(), Gen2NameRaterScreen.Phase.HELLO_ASK)
	assert_eq(_host().question_cursor(), 0)


## `jp c, .cancel`: NO on the first question is `NameRaterComeAgainText`, and
## nothing after it runs.
func test_no_on_the_introduction_ends_on_come_again() -> void:
	await _open_world()
	_run_script()
	_settle()
	_world_screen.press_button(Gen2Button.DOWN)
	_world_screen.press_button(Gen2Button.A)
	assert_null(_host())
	assert_true(_world_screen._text_box.visible)
	assert_eq(
		" ".join(_world_screen._text_box.text_lines()),
		" ".join(_data.name_rater_text("come_again").split("\n"))
	)


## The ending text is the script's, not the special's: `special NameRater`
## returns with it standing and the map's own `waitbutton` is the press.
func test_the_ending_text_waits_on_the_scripts_own_waitbutton() -> void:
	await _open_world()
	_run_script()
	_settle()
	_world_screen.press_button(Gen2Button.B)
	assert_eq(
		StringName(_world_screen._world.pending_script_input().get("type", &"")), &"button"
	)


func test_the_party_list_is_select_mon_from_party() -> void:
	await _open_world()
	await _reach_party()
	var party: Gen2PartyScreen = _host().party_screen()
	assert_not_null(party)
	assert_eq(party._prompt(), Gen2PartyScreen.PROMPT_CHOOSE)
	## A on a member answers the caller rather than opening `MonSubmenu`.
	party.handle_button(Gen2Button.A)
	assert_null(_host().party_screen())
	assert_eq(_host().phase(), Gen2NameRaterScreen.Phase.BETTER_NAME)


## `PartyMenuSelect`'s carry: B over the list is the same `.cancel` a NO is.
func test_cancelling_the_party_list_ends_on_come_again() -> void:
	await _open_world()
	await _reach_party()
	_host().party_screen().handle_button(Gen2Button.B)
	assert_null(_host())
	assert_eq(
		" ".join(_world_screen._text_box.text_lines()),
		" ".join(_data.name_rater_text("come_again").split("\n"))
	)


## `.traded`: `CheckIfMonIsYourOT` is read before either question about the
## name, so a traded member never reaches the naming screen.
func test_a_traded_member_ends_on_perfect_name_with_its_nickname_filled() -> void:
	await _open_world()
	_world_screen.active_save().party[0].ot_id += 1
	await _reach_party()
	_host().party_screen().handle_button(Gen2Button.A)
	assert_null(_host())
	var shown: String = " ".join(_world_screen._text_box.text_lines())
	assert_true(shown.contains("SPARKY"), shown)
	assert_false(shown.contains(Gen2TextStream.RAM_MARKER), shown)


## `.egg`: the EGG test runs before `GetCurNickname`, so an egg is refused
## whoever caught it.
func test_an_egg_ends_on_the_egg_text() -> void:
	await _open_world()
	_world_screen.active_save().party[0].is_egg = true
	await _reach_party()
	_host().party_screen().handle_button(Gen2Button.A)
	assert_null(_host())
	assert_eq(
		" ".join(_world_screen._text_box.text_lines()),
		" ".join(_data.name_rater_text("egg").split("\n"))
	)


## The whole line through, ending in the `CopyBytes` into the party row.
func test_a_new_name_is_written_to_the_party_row() -> void:
	await _open_world()
	await _reach_party()
	_host().party_screen().handle_button(Gen2Button.A)
	_settle()
	assert_eq(_host().phase(), Gen2NameRaterScreen.Phase.BETTER_ASK)
	_world_screen.press_button(Gen2Button.A)
	assert_eq(_host().phase(), Gen2NameRaterScreen.Phase.WHAT_NAME)
	_press(Gen2Button.A)
	assert_eq(_host().phase(), Gen2NameRaterScreen.Phase.NAMING)

	var naming: Gen2NamingScreenScreen = _host().naming_screen()
	assert_not_null(naming)
	naming.closed.emit("BOLT")
	assert_eq(_host().phase(), Gen2NameRaterScreen.Phase.NAMED)
	_press(Gen2Button.A)
	assert_null(_host())
	assert_eq(_world_screen.active_save().party[0].nickname, "BOLT")
	assert_eq(
		" ".join(_world_screen._text_box.text_lines()),
		" ".join(_data.name_rater_text("finished").split("\n"))
	)


## `IsNewNameEmpty` reaching `.samename`: `NameRaterSameNameText` prints and the
## row keeps the name it had.
func test_an_empty_entry_leaves_the_row_alone() -> void:
	await _open_world()
	await _reach_party()
	_host().party_screen().handle_button(Gen2Button.A)
	_settle()
	_world_screen.press_button(Gen2Button.A)
	_press(Gen2Button.A)
	_host().naming_screen().closed.emit("")
	_press(Gen2Button.A)
	assert_null(_host())
	assert_eq(_world_screen.active_save().party[0].nickname, "SPARKY")
	assert_eq(
		" ".join(_world_screen._text_box.text_lines()),
		" ".join(_data.name_rater_text("same_name").split("\n"))
	)


## The move deleter from here down. Same harness, one special further on: the
## script is rewritten before the world is opened, so `_host()` below is the
## other routine's.
func _open_deleter_world() -> void:
	_write_name_rater_script(Gen2WorldScriptRunner.SPECIAL_MOVE_DELETION)
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	var mon: Gen2SaveMon = _world_screen.active_save().party[0]
	mon.moves = [1, 2, 0, 0]
	mon.pp = [10, 20, 0, 0]


func _deleter() -> Gen2MoveDeleterScreen:
	return _world_screen._move_deleter_host


func _settle_deleter() -> void:
	var guard: int = 600
	while guard > 0:
		var host: Gen2MoveDeleterScreen = _deleter()
		if host == null or host._text_box == null or not host._text_box.is_revealing():
			break
		_world_screen.advance_frame()
		guard -= 1
	_world_screen.advance_frame()


## Walks to the move list: intro, YES, which_mon, the party list, the member,
## which_move, the press `prompt` waits for.
func _reach_move_list() -> void:
	_run_script()
	_settle_deleter()
	_world_screen.press_button(Gen2Button.A)
	_settle_deleter()
	_world_screen.press_button(Gen2Button.A)
	_deleter().party_screen().handle_button(Gen2Button.A)
	_settle_deleter()
	_world_screen.press_button(Gen2Button.A)


func test_the_deleter_special_opens_its_own_routine() -> void:
	await _open_deleter_world()
	_run_script()
	assert_not_null(_deleter())
	assert_null(_world_screen._name_rater_host)
	_settle_deleter()
	assert_eq(_deleter().phase(), Gen2MoveDeleterScreen.Phase.INTRO_ASK)


## `.onlyonemove` is read off the second slot, before the move list is ever
## drawn.
func test_a_member_with_one_move_is_refused_before_the_list() -> void:
	await _open_deleter_world()
	_world_screen.active_save().party[0].moves = [1, 0, 0, 0]
	_run_script()
	_settle_deleter()
	_world_screen.press_button(Gen2Button.A)
	_settle_deleter()
	_world_screen.press_button(Gen2Button.A)
	_deleter().party_screen().handle_button(Gen2Button.A)
	assert_null(_deleter())
	assert_eq(
		" ".join(_world_screen._text_box.text_lines()),
		" ".join(_data.move_deleter_text("knows_one").split("\n"))
	)


## `DeleteMoveScreen2DMenuData` accepts up, down, A and B and nothing else, so
## the list neither cycles between members nor holds a move.
func test_the_move_list_neither_cycles_nor_swaps() -> void:
	await _open_deleter_world()
	await _reach_move_list()
	var moves: Gen2MoveScreen = _deleter().move_screen()
	assert_not_null(moves)
	assert_false(moves.handle_button(Gen2Button.RIGHT))
	assert_false(moves.handle_button(Gen2Button.LEFT))
	assert_eq(moves.snapshot()["held"], -1)


## The whole line through: the move and its PP leave together and the ending
## text is the script's.
func test_a_deleted_move_takes_its_pp_with_it() -> void:
	await _open_deleter_world()
	await _reach_move_list()
	_deleter().move_screen().handle_button(Gen2Button.DOWN)
	_deleter().move_screen().handle_button(Gen2Button.A)
	assert_eq(_deleter().phase(), Gen2MoveDeleterScreen.Phase.DELETE_ASK)
	_settle_deleter()
	_world_screen.press_button(Gen2Button.A)
	assert_null(_deleter())
	var mon: Gen2SaveMon = _world_screen.active_save().party[0]
	assert_eq(mon.moves, [1, 0, 0, 0])
	assert_eq(mon.pp, [10, 0, 0, 0])
	assert_eq(
		" ".join(_world_screen._text_box.text_lines()),
		" ".join(_data.move_deleter_text("forgot").split("\n"))
	)


## NO on the second question is `.declined`, and nothing is written.
func test_no_on_the_confirmation_leaves_the_moves_alone() -> void:
	await _open_deleter_world()
	await _reach_move_list()
	_deleter().move_screen().handle_button(Gen2Button.A)
	_settle_deleter()
	_world_screen.press_button(Gen2Button.B)
	assert_null(_deleter())
	assert_eq(_world_screen.active_save().party[0].moves, [1, 2, 0, 0])
	assert_eq(
		" ".join(_world_screen._text_box.text_lines()),
		" ".join(_data.move_deleter_text("come_again").split("\n"))
	)


## `engine/events/haircut.asm`'s four routines are the same `SelectMonFromParty`
## with no boxes of their own: every line the player reads belongs to the map
## script, so the special owes a party list and an answer and nothing else.
func _run_haircut(special: int) -> void:
	_write_name_rater_script(special)
	await _open_world()
	_run_script()


func _selection_list() -> Gen2PartyScreen:
	return _world_screen._party_host


func test_a_grooming_special_opens_the_party_list_with_no_box_of_its_own() -> void:
	await _run_haircut(Gen2WorldScriptRunner.SPECIAL_OLDER_HAIRCUT_BROTHER)
	assert_not_null(_selection_list())
	assert_eq(_selection_list()._prompt(), Gen2PartyScreen.PROMPT_CHOOSE)
	assert_false(_world_screen._text_box.visible, "the script owns every line")
	assert_false(_world_screen.move_player(Vector2i.RIGHT))


## `.nope`: the carry a B press or the CANCEL row answers with is `xor a`, which
## is the `ifequal $0` both haircut scripts refuse on.
func test_cancelling_the_list_answers_zero_and_changes_no_happiness() -> void:
	await _run_haircut(Gen2WorldScriptRunner.SPECIAL_YOUNGER_HAIRCUT_BROTHER)
	var before: int = _world_screen.active_save().party[0].happiness
	_selection_list().handle_button(Gen2Button.B)
	assert_null(_selection_list())
	assert_eq(_world_screen._world._active_script._script_value, 0)
	assert_eq(_world_screen.active_save().party[0].happiness, before)


## `.egg`: `cp EGG` is read before the name copy and before `Random`, so an egg
## answers 1 and no row is walked.
func test_an_egg_answers_one_and_is_not_groomed() -> void:
	await _run_haircut(Gen2WorldScriptRunner.SPECIAL_DAISYS_GROOMING)
	var mon: Gen2SaveMon = _world_screen.active_save().party[0]
	mon.is_egg = true
	var before: int = mon.happiness
	_selection_list().handle_button(Gen2Button.A)
	assert_eq(_world_screen._world._active_script._script_value, 1)
	assert_eq(mon.happiness, before)


## `call ChangeHappiness` on the row `Random` picked, and `wCurPartySpecies`
## left holding the chosen member, which is what a following
## `special PlayCurMonCry` reads rather than the row in wScriptVar.
func test_grooming_raises_happiness_and_leaves_the_chosen_species_standing() -> void:
	await _run_haircut(Gen2WorldScriptRunner.SPECIAL_DAISYS_GROOMING)
	var mon: Gen2SaveMon = _world_screen.active_save().party[0]
	mon.happiness = 100
	_selection_list().handle_button(Gen2Button.A)
	var runner: Gen2WorldScriptRunner = _world_screen._world._active_script
	assert_gt(mon.happiness, 100, "HAPPINESS_GROOMING is a rise at every threshold")
	assert_eq(runner._cur_party_species, mon.species)
	assert_ne(runner._script_value, mon.species,
		"wScriptVar carries the table row, which is why the cry reads the other byte")


## `BillsGrandfather` has no egg branch and no table: it answers the species
## itself, which is what `ifnotequal LICKITUNG` and its four siblings read.
func test_bills_grandfather_answers_the_chosen_species() -> void:
	await _run_haircut(Gen2WorldScriptRunner.SPECIAL_BILLS_GRANDFATHER)
	var mon: Gen2SaveMon = _world_screen.active_save().party[0]
	var before: int = mon.happiness
	_selection_list().handle_button(Gen2Button.A)
	assert_eq(_world_screen._world._active_script._script_value, mon.species)
	assert_eq(mon.happiness, before, "no row is walked here")


## The three balance windows write the tilemap and return, so the script runs
## straight on and the box stands over the map until `closetext` redraws it.
func test_a_balance_window_stands_over_the_map_until_closetext() -> void:
	var directory: String = Fixture.directory()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(directory))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, Fixture.TUTORIAL_SCRIPT)] = [
		Gen2WorldScript.SPECIAL,
		Gen2WorldScriptRunner.SPECIAL_PLACE_MONEY_TOP_RIGHT, 0x00,
		Gen2WorldScript.WAITBUTTON,
		Gen2WorldScript.CLOSETEXT,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(directory), scripts)
	await _open_world()
	_run_script()
	assert_true(_world_screen.money_window_open())
	_world_screen.press_button(Gen2Button.A)
	assert_false(_world_screen.money_window_open())
