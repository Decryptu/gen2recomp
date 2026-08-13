extends GutTest

## `OakSpeech`: its beats in source order, the naming screen where `NamePlayer`
## sits, `InitName`'s default for a blank entry and the `<PLAYER>` it prints
## afterwards.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _screen: Gen2OakSpeechScreen = null
var _finished: Array = []


func before_each() -> void:
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	_finished = []
	_screen = Gen2OakSpeechScreen.new()
	add_child_autofree(_screen)
	_screen.open(_data, Gen2SaveData.GENDER_MALE)
	_screen.finished.connect(func(value: String) -> void: _finished.append(value))


func after_each() -> void:
	RomCache.clear(Fixture.directory())


## Spends whatever `DelayFrames` the speech is standing in. The fades between
## beats and the two pic moves are real frame counts, so a test drives them
## rather than skipping them; there is no clock in a GUT run.
func _settle(limit: int = 40) -> void:
	for _pass: int in limit:
		if _screen.animation_frames_left() == 0:
			return
		_screen.advance_frames(_screen.animation_frames_left())


## Presses A until the speech either reaches the naming screen or ends, so a
## test never has to know how many pages a text wrapped to.
func _press_a_until(stop: Callable, limit: int = 200) -> void:
	for _step: int in limit:
		_settle()
		if stop.call():
			return
		_screen.handle_button(Gen2Button.A)


func _at_naming() -> bool:
	return _screen.naming()


func _at_name_choices() -> bool:
	return _screen.choosing_name()


func _done() -> bool:
	return not _finished.is_empty()


# --- the model ----------------------------------------------------------------

## `_OakText3` is a bare promptbutton and carries no words, so it is not a beat;
## `_OakText2` and `_OakText4` are two PrintText calls over one pic, so they are.
func test_the_beats_are_the_six_texts_in_source_order() -> void:
	var beats: Array = Gen2OakSpeech.beats(_data)
	assert_eq(beats.size(), 6)
	var keys: Array = []
	for beat: Dictionary in beats:
		keys.append(String(beat["key"]))
	assert_eq(keys, ["oak_1", "oak_2", "oak_4", "oak_5", "oak_6", "oak_7"])


func test_the_pics_follow_the_routines_own_order() -> void:
	var beats: Array = Gen2OakSpeech.beats(_data)
	assert_eq(int(beats[0]["pic"]), Gen2OakSpeech.Pic.OAK)
	assert_eq(int(beats[1]["pic"]), Gen2OakSpeech.Pic.MON)
	assert_eq(int(beats[2]["pic"]), Gen2OakSpeech.Pic.MON)
	assert_eq(int(beats[3]["pic"]), Gen2OakSpeech.Pic.OAK)
	assert_eq(int(beats[4]["pic"]), Gen2OakSpeech.Pic.PLAYER)
	assert_eq(int(beats[5]["pic"]), Gen2OakSpeech.Pic.PLAYER)


func test_a_cache_without_the_texts_has_no_speech() -> void:
	RomCache.write_json(RomCache.intro_text_path(Fixture.directory()), {})
	assert_eq(Gen2OakSpeech.beats(GameData.open_directory(Fixture.directory())), [])
	assert_eq(Gen2OakSpeech.beats(null), [])


## `home/string.asm`'s InitName, which is why the naming screen's END is
## reachable with nothing typed at all.
func test_a_blank_entry_becomes_the_gendered_default() -> void:
	assert_eq(Gen2OakSpeech.resolve_name("", Gen2SaveData.GENDER_MALE), "CHRIS")
	assert_eq(Gen2OakSpeech.resolve_name("", Gen2SaveData.GENDER_FEMALE), "KRIS")
	assert_eq(Gen2OakSpeech.resolve_name("   ", Gen2SaveData.GENDER_FEMALE), "KRIS")
	assert_eq(Gen2OakSpeech.resolve_name("ASH", Gen2SaveData.GENDER_MALE), "ASH")


func test_the_player_marker_is_replaced_by_the_name() -> void:
	assert_eq(Gen2OakSpeech.with_player_name("<PLAYER>, hello", "ASH"), "ASH, hello")
	assert_eq(Gen2OakSpeech.with_player_name("no marker", "ASH"), "no marker")


func test_each_profile_uses_its_own_source_name_table() -> void:
	assert_eq(Gen2PlayerNameChoices.options(_data, Gen2SaveData.GENDER_MALE),
		["NEW NAME", "CHRIS", "MAT", "ALLAN", "JON"])
	assert_eq(Gen2PlayerNameChoices.options(_data, Gen2SaveData.GENDER_FEMALE),
		["NEW NAME", "KRIS", "AMANDA", "JUANA", "JODI"])
	var gold: GameData = Fixture.build(&"gold")
	var silver: GameData = Fixture.build(&"silver")
	assert_eq(Gen2PlayerNameChoices.options(gold, Gen2SaveData.GENDER_MALE),
		["NEW NAME", "GOLD", "HIRO", "TAYLOR", "KARL"])
	assert_eq(Gen2PlayerNameChoices.options(silver, Gen2SaveData.GENDER_MALE),
		["NEW NAME", "SILVER", "KAMON", "OSCAR", "MAX"])
	RomCache.clear(Fixture.directory(&"gold"))
	RomCache.clear(Fixture.directory(&"silver"))


# --- the screen ---------------------------------------------------------------

func test_it_opens_on_the_first_beat() -> void:
	assert_eq(_screen.beat_index(), 0)
	assert_eq(_screen.beat_count(), 6)
	assert_false(_screen.naming())


## `OakSpeech` opens on `RotateFourPalettesLeft`, `RotateFourPalettesRight` and
## `RotateThreePalettesRight` before the first pic is loaded, and the first beat
## then comes in on `Intro_RotatePalettesLeftFrontpic`. No button does anything
## while any of that is running.
func test_the_speech_opens_on_the_source_fades_before_the_first_pic() -> void:
	assert_eq(_screen.animation_frames_left(), 32, "RotateFourPalettesLeft")
	assert_true(_screen.handle_button(Gen2Button.A), "a press inside DelayFrames is swallowed")
	_screen.advance_frames(32)
	assert_eq(_screen.animation_frames_left(), 32 + 24, "then in from black and out to white")
	_screen.advance_frames(56)
	assert_eq(_screen.animation_frames_left(), 60, "and the first pic fades in")
	assert_eq(_screen.beat_index(), 0)


## Every beat that loads a new picture ends on `RotateThreePalettesRight`; the
## two that keep the picture before them run straight on.
func test_only_the_beats_that_load_a_picture_fade_out() -> void:
	var beats: Array = Gen2OakSpeech.beats(_data)
	var clears: Array = []
	var enters: Array = []
	for beat: Dictionary in beats:
		clears.append(bool(beat["clears_after"]))
		enters.append(int(beat["enter"]))
	assert_eq(clears, [true, false, true, true, false, false])
	assert_eq(enters, [
		Gen2OakSpeech.Enter.FRONTPIC, Gen2OakSpeech.Enter.WIPE,
		Gen2OakSpeech.Enter.NONE, Gen2OakSpeech.Enter.FRONTPIC,
		Gen2OakSpeech.Enter.FRONTPIC, Gen2OakSpeech.Enter.NONE,
	])


## `NamePlayer` opens with `MovePlayerPicRight`, which has to finish before
## `ShowPlayerNamingChoices` is on screen.
func test_the_pic_walks_right_before_the_name_menu_opens() -> void:
	# No other run in the routine is forty frames, so the queue identifies it.
	for _step: int in 200:
		if _screen.animation_frames_left() == Gen2IntroPresentation.MOVE_STEPS \
				* Gen2IntroPresentation.MOVE_STEP_FRAMES:
			break
		_settle()
		_screen.handle_button(Gen2Button.A)
	assert_eq(_screen.animation_frames_left(), 40, "MovePlayerPicRight was queued")
	assert_false(_screen.choosing_name(), "the menu is not up while the pic is walking")
	_screen.advance_frames(39)
	assert_false(_screen.choosing_name())
	_screen.advance_frames(1)
	assert_true(_screen.choosing_name())


## `NamePlayer` sits after `_OakText6`, so pressing through the speech reaches
## the keyboard rather than the end.
func test_pressing_through_reaches_the_naming_screen_after_oak_six() -> void:
	_press_a_until(_at_naming)
	assert_true(_screen.naming(), "the naming screen opened")
	assert_eq(_screen.beat_index(), 4, "on the beat _OakText6 is")
	assert_eq(_finished.size(), 0)


func test_oak_six_opens_the_source_choices_before_the_keyboard() -> void:
	_press_a_until(_at_name_choices)
	assert_true(_screen.choosing_name())
	assert_false(_screen.naming())
	assert_eq(_screen.beat_index(), 4)
	assert_false(_screen.handle_button(Gen2Button.B), "STATICMENU_DISABLE_B")


func test_a_preset_name_skips_the_keyboard_and_resumes_the_speech() -> void:
	_press_a_until(_at_name_choices)
	_screen.handle_button(Gen2Button.DOWN)
	_screen.handle_button(Gen2Button.A)
	# `MovePlayerPicLeft` walks the pic back before `_OakText7` is printed.
	assert_eq(_screen.animation_frames_left(), 40)
	_settle()
	assert_false(_screen.choosing_name())
	assert_false(_screen.naming())
	assert_eq(_screen.player_name(), "CHRIS")
	assert_eq(_screen.beat_index(), 5)
	_press_a_until(_done)
	assert_eq(_finished, ["CHRIS"])


## While the keyboard is up it owns every button, so A types rather than
## advancing the speech.
func test_the_naming_screen_takes_the_buttons_while_it_is_open() -> void:
	_press_a_until(_at_naming)
	var beat: int = _screen.beat_index()
	_screen.handle_button(Gen2Button.A)
	assert_true(_screen.naming(), "still naming")
	assert_eq(_screen.beat_index(), beat, "the speech did not move on")


func test_the_speech_resumes_and_ends_with_the_name_that_was_typed() -> void:
	_press_a_until(_at_naming)
	# One letter, then START to reach END and A to store it.
	_screen.handle_button(Gen2Button.A)
	_screen.handle_button(Gen2Button.START)
	_screen.handle_button(Gen2Button.A)
	_settle()
	assert_false(_screen.naming(), "the keyboard closed")
	assert_eq(_screen.player_name().length(), 1)
	_press_a_until(_done)
	assert_eq(_finished, [_screen.player_name()])


## Ending the keyboard with nothing typed reaches InitName's default rather than
## an empty name, which is what keeps the save validator's rule satisfiable.
func test_ending_the_keyboard_empty_takes_the_default() -> void:
	_press_a_until(_at_naming)
	_screen.handle_button(Gen2Button.START)
	_screen.handle_button(Gen2Button.A)
	_settle()
	assert_eq(_screen.player_name(), Gen2OakSpeech.DEFAULT_MALE)
	_press_a_until(_done)
	assert_eq(_finished, [Gen2OakSpeech.DEFAULT_MALE])


func test_a_female_intro_takes_the_female_default() -> void:
	var female := Gen2OakSpeechScreen.new()
	add_child_autofree(female)
	female.open(_data, Gen2SaveData.GENDER_FEMALE)
	for _step: int in 200:
		for _pass: int in 40:
			if female.animation_frames_left() == 0:
				break
			female.advance_frames(female.animation_frames_left())
		if female.naming():
			break
		female.handle_button(Gen2Button.A)
	female.handle_button(Gen2Button.START)
	female.handle_button(Gen2Button.A)
	for _pass: int in 40:
		female.advance_frames(female.animation_frames_left())
	assert_eq(female.player_name(), Gen2OakSpeech.DEFAULT_FEMALE)


## `InitializeWorld` calls `ShrinkPlayer` the moment `OakSpeech` returns, so the
## run does not end on `_OakText7`: its five `DelayFrames` and the closing
## `RotateThreePalettesRight` are 101 more frames, and the name only arrives at
## the end of them.
func test_the_speech_ends_on_the_shrink_rather_than_on_the_last_text() -> void:
	_press_a_until(func() -> bool: return _screen.beat_index() == _screen.beat_count() - 1)
	# The last beat's own pages, pressed without settling past the shrink the
	# last of them starts.
	for _step: int in 40:
		if _screen.beat_index() >= _screen.beat_count():
			break
		_screen.handle_button(Gen2Button.A)
	assert_eq(_finished.size(), 0, "the speech has not handed a name over yet")
	assert_eq(_screen.animation_frames_left(), 8, "ShrinkPlayer's first DelayFrames")

	var waits: int = 0
	for wait: int in Gen2OakSpeech.SHRINK_WAITS:
		waits += wait
	_screen.advance_frames(waits + 3 * Gen2IntroPresentation.FADE_STEP_FRAMES)
	assert_eq(_finished, [_screen.player_name()], "the name arrives when the shrink is over")


## Nothing but A moves the speech, the way every PrintText in the routine waits
## for one.
func test_other_buttons_do_not_advance_the_speech() -> void:
	_settle()
	assert_false(_screen.handle_button(Gen2Button.B))
	assert_false(_screen.handle_button(Gen2Button.START))
	assert_eq(_screen.beat_index(), 0)
