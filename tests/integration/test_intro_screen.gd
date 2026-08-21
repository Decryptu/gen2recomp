extends GutTest

## `NewGame`: the gender question, clock set, then Oak's speech with the naming screen in
## it, then one write. Nothing reaches disk until the run is over, which is what
## lets [Gen2SaveValidator]'s rule that a save has a trainer stand unchanged.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const SLOT: int = 0
const LABEL: String = "Run one"

var _data: GameData = null
var _screen: Gen2IntroScreen = null
var _finished: Array = []
var _failed: Array = []


func before_each() -> void:
	_data = Fixture.build()
	_clear_saves()
	_finished = []
	_failed = []
	_screen = Gen2IntroScreen.new()
	add_child_autofree(_screen)
	_screen.finished.connect(func(save: Gen2SaveData) -> void: _finished.append(save))
	_screen.failed.connect(func(message: String) -> void: _failed.append(message))


func after_each() -> void:
	_clear_saves()
	RomCache.clear(Fixture.directory())
	# `Gen2Screen.drop` queues the sub-screen it replaced, and a test that never
	# reaches a frame would leave every one of them standing as an orphan.
	await get_tree().process_frame


func _clear_saves() -> void:
	for slot: int in Gen2SaveStore.MAX_SLOTS:
		var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, slot)
		for copy: String in [path, "%s.bak" % path, "%s.tmp" % path, "%s.bak.tmp" % path]:
			if FileAccess.file_exists(copy):
				DirAccess.remove_absolute(copy)


## `SplashScreen` runs in front of `PlayerProfileSetup`, so a run that wants the
## gender question spends the copyright screen's own frames first. No button
## skips it: `DelayFrames` reads no joypad.
func _begin() -> void:
	_screen.begin(_data, SLOT, LABEL, false)
	_settle_splash()


## The copyright half is a fixed budget and the GameFreak half a sequence, so
## the splash is driven until it hands over rather than for a count.
func _settle_splash(limit: int = 800) -> void:
	var splash: Gen2SplashScreen = _screen.current() as Gen2SplashScreen
	if splash == null:
		return
	for _frame: int in limit:
		if _screen.current() != splash:
			return
		splash.advance_frames(1)


## Spends whatever `DelayFrames` the intro is standing in: its own fade between
## two sub-screens, or the queue the screen under it is holding. The intro's
## fades, pic moves and `DelayFrames` are real frame counts, so a test drives
## them rather than skipping them; there is no clock in a GUT run.
func _settle(limit: int = 40) -> void:
	for _pass: int in limit:
		var owed: int = _screen.animation_frames_left()
		if owed == 0:
			return
		_screen.advance_frames(owed)


## `InitClock` from the gender choice to Oak's speech: the fade in front of it,
## Oak's woke-up text, both dials and both YES/NO boxes, and his answer.
func _accept_clock() -> void:
	_settle()
	assert_true(_screen.current() is Gen2ClockSetScreen)
	for _step: int in 12:
		_settle()
		if not (_screen.current() is Gen2ClockSetScreen):
			return
		_screen.handle_button(Gen2Button.A)
	_settle()


## Presses A until [param stop] answers, so a test never has to know how many
## pages a text wrapped to.
func _press_a_until(stop: Callable, limit: int = 200) -> void:
	for _step: int in limit:
		_settle()
		if stop.call():
			return
		_screen.handle_button(Gen2Button.A)


func _at_naming() -> bool:
	var speech: Gen2OakSpeechScreen = _screen.current() as Gen2OakSpeechScreen
	return speech != null and speech.naming()


func _done() -> bool:
	return not _finished.is_empty()


## Runs the whole intro, typing one letter for a name. Returns that name.
func _run_intro(female: bool = false) -> String:
	_begin()
	if female:
		_screen.handle_button(Gen2Button.DOWN)
	_screen.handle_button(Gen2Button.A)
	_accept_clock()
	_press_a_until(_at_naming)
	_screen.handle_button(Gen2Button.A)
	_screen.handle_button(Gen2Button.START)
	_screen.handle_button(Gen2Button.A)
	_settle()
	var speech: Gen2OakSpeechScreen = _screen.current() as Gen2OakSpeechScreen
	var typed: String = speech.player_name()
	_press_a_until(_done)
	return typed


## `SplashScreen` is what `Init` reaches before `NewGame`, so the copyright
## screen and the GameFreak animation behind it are the first things a new game
## shows and the gender question waits for both.
func test_the_copyright_screen_comes_before_the_gender_question() -> void:
	_screen.begin(_data, SLOT, LABEL, false)
	assert_true(_screen.current() is Gen2SplashScreen)
	var splash: Gen2SplashScreen = _screen.current() as Gen2SplashScreen
	splash.advance_frames(splash.frames_left() - 1)
	assert_eq(splash.visible_image(), &"copyright", "and it is not cut short")
	splash.advance_frames(1)
	assert_eq(splash.visible_image(), &"game_freak_presents")
	assert_true(_screen.current() is Gen2SplashScreen)
	_settle_splash()
	assert_true(_screen.current() is Gen2GenderScreen)


## `PlayerProfileSetup` runs before `OakSpeech`, so the gender question is the
## first thing a new game shows once the splash has run.
func test_the_gender_question_comes_first() -> void:
	_begin()
	assert_true(_screen.current() is Gen2GenderScreen)
	_screen.handle_button(Gen2Button.A)
	assert_true(_screen.current() is Gen2GenderScreen,
		"still standing under `RotateFourPalettesLeft`")
	_settle()
	assert_true(_screen.current() is Gen2ClockSetScreen, "then InitClock")
	_accept_clock()
	assert_true(_screen.current() is Gen2OakSpeechScreen, "then the speech")


## `InitClock` is hour and minutes: it ends on `OakText_ResponseToSetTime` after
## `.MinutesAreSet`. The weekday is `SetDayOfWeek`, which only Mom's errand in
## `PlayersHouse1F.asm` calls, so a new game leaves the RTC's own SUNDAY alone.
func test_clock_set_wraps_each_source_dial_and_reaches_the_speech() -> void:
	_begin()
	_screen.handle_button(Gen2Button.A)
	_settle()
	var clock: Gen2ClockSetScreen = _screen.current() as Gen2ClockSetScreen
	assert_not_null(clock)
	# `PrintText OakTimeWokeUpText`: three pages before the first dial is drawn.
	for _page: int in 3:
		_settle()
		assert_true(_screen.current() is Gen2ClockSetScreen, "still in the text")
		clock.handle_button(Gen2Button.A)
	_settle()
	clock.handle_button(Gen2Button.DOWN)
	clock.handle_button(Gen2Button.A)
	_settle()
	# `YesNoBox` defaults to YES, and `InterpretTwoOptionMenu` holds `ld c, $f`
	# before the answer is acted on.
	clock.handle_button(Gen2Button.A)
	assert_eq(clock.value()["minute"], 0, "the minutes dial has not been reached")
	_settle()
	clock.handle_button(Gen2Button.DOWN)
	assert_eq(clock.value(), {"day": 0, "hour": 9, "minute": 59})
	clock.handle_button(Gen2Button.A)
	_settle()
	clock.handle_button(Gen2Button.A)
	_settle()
	# `.MinutesAreSet`'s `OakText_ResponseToSetTime`, which waits with
	# `WaitPressAorB_BlinkCursor` before the routine returns.
	assert_true(_screen.current() is Gen2ClockSetScreen, "Oak answers the time")
	clock.handle_button(Gen2Button.A)
	assert_true(_screen.current() is Gen2OakSpeechScreen)


## `.loop` and `.HourIsSet` end on `ld c, 10 / call DelayFrames`, and
## `InterpretTwoOptionMenu` on `ld c, $f`, so neither a dial nor a YES/NO reads
## a button on the frame it is drawn.
func test_a_dial_reads_no_button_until_its_delay_frames_have_gone() -> void:
	_begin()
	_screen.handle_button(Gen2Button.A)
	_settle()
	var clock: Gen2ClockSetScreen = _screen.current() as Gen2ClockSetScreen
	for _page: int in 3:
		_settle()
		clock.handle_button(Gen2Button.A)
	assert_eq(clock.animation_frames_left(), Gen2ClockSetScreen.DIAL_DELAY_FRAMES)
	clock.handle_button(Gen2Button.DOWN)
	assert_eq(clock.value()["hour"], 10, "the dial is still held")
	_settle()
	clock.handle_button(Gen2Button.DOWN)
	assert_eq(clock.value()["hour"], 9)


## `NewGame` reaches `InitializeWorld` only after both have returned, so nothing
## is on disk while the intro is running.
func test_nothing_is_written_while_the_intro_runs() -> void:
	_begin()
	assert_false(Gen2SaveStore.exists(_data.id, _data.sha1, SLOT))
	_screen.handle_button(Gen2Button.A)
	_accept_clock()
	_press_a_until(_at_naming)
	assert_false(
		Gen2SaveStore.exists(_data.id, _data.sha1, SLOT),
		"still nothing on disk at the naming screen"
	)


## Backing out of the intro leaves no half-written slot, because there is
## nothing half-written to leave.
func test_abandoning_the_intro_leaves_no_slot() -> void:
	_begin()
	_screen.handle_button(Gen2Button.A)
	_accept_clock()
	_press_a_until(_at_naming)
	_screen.free()
	_screen = null
	assert_false(Gen2SaveStore.exists(_data.id, _data.sha1, SLOT))


func test_the_saved_name_is_the_one_typed_on_the_naming_screen() -> void:
	var typed: String = _run_intro()
	assert_eq(_finished.size(), 1, "the intro finished once")
	assert_eq(typed.length(), 1, "one letter was typed")

	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, SLOT, _data)
	assert_true(loaded["ok"], String(loaded.get("message", "")))
	var save: Gen2SaveData = loaded["save"]
	assert_eq(save.player_name, typed)


## The launcher's field is the save file's own name, and it survives the intro
## rather than being overwritten by the trainer's.
func test_the_slot_label_round_trips_through_the_intro() -> void:
	_run_intro()
	var save: Gen2SaveData = Gen2SaveStore.load_result(_data.id, _data.sha1, SLOT, _data)["save"]
	assert_eq(save.label, LABEL)
	assert_ne(save.label, save.player_name)


func test_the_chosen_gender_reaches_the_save() -> void:
	_run_intro()
	var male: Gen2SaveData = Gen2SaveStore.load_result(_data.id, _data.sha1, SLOT, _data)["save"]
	assert_eq(male.gender, Gen2SaveData.GENDER_MALE)

	_clear_saves()
	_screen.free()
	_screen = Gen2IntroScreen.new()
	add_child_autofree(_screen)
	_screen.finished.connect(func(save: Gen2SaveData) -> void: _finished.append(save))
	_finished = []
	_run_intro(true)
	var female: Gen2SaveData = Gen2SaveStore.load_result(_data.id, _data.sha1, SLOT, _data)["save"]
	assert_eq(female.gender, Gen2SaveData.GENDER_FEMALE)


## The written save is the one the world then loads, so the intro hands over a
## slot rather than a screen.
func test_the_written_save_carries_the_new_game_spawn() -> void:
	_run_intro()
	var save: Gen2SaveData = _finished[0]
	assert_not_null(save.world, "the new-game snapshot came with it")
	assert_eq(save.slot, SLOT)
	assert_eq(save.game_id, _data.id)
	assert_eq(save.world.world_clock(), {"day": 0, "hour": 10, "minute": 0})


## A cartridge with no gender screen starts on the speech instead, and its save
## keeps GENDER_MALE, which is what pokegold's absent wPlayerGender means.
func test_a_cartridge_without_a_gender_screen_starts_on_the_speech() -> void:
	var text: Dictionary = RomCache.read_json(RomCache.intro_text_path(Fixture.directory()))
	text.erase("gender")
	RomCache.write_json(RomCache.intro_text_path(Fixture.directory()), text)
	_data = GameData.open_directory(Fixture.directory())

	_begin()
	assert_true(_screen.current() is Gen2ClockSetScreen)
	_accept_clock()
	assert_true(_screen.current() is Gen2OakSpeechScreen)
	assert_eq(_screen.gender(), Gen2SaveData.GENDER_MALE)


## A cache with no intro text at all fails loudly and writes nothing, rather
## than making a world with a nameless trainer in it.
func test_a_cache_without_intro_text_fails_without_writing() -> void:
	RomCache.write_json(RomCache.intro_text_path(Fixture.directory()), {})
	_data = GameData.open_directory(Fixture.directory())
	_begin()
	_accept_clock()
	assert_eq(_failed.size(), 1)
	assert_false(Gen2SaveStore.exists(_data.id, _data.sha1, SLOT))
