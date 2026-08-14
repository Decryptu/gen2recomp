extends GutTest

const Boot := preload("res://game/world/boot_cinema.gd")

## Longer than the movie, whose own total tests/unit/test_intro_movie.gd pins.
const FRAME_CAP: int = 20000


func test_boot_starts_with_source_ordered_copyright_events() -> void:
	var boot := Boot.new()
	boot.start(&"gold")
	var initial: Array[Dictionary] = boot.drain_events()
	assert_eq(initial[0]["type"], &"play_music")
	assert_eq(initial[1]["type"], &"hide_image")

	var copyright: Array[Dictionary] = []
	for _frame: int in 10:
		copyright.append_array(boot.advance_frame())
	assert_true(copyright.any(func(event: Dictionary) -> bool:
		return event["type"] == &"show_image" and event["id"] == &"copyright"
	))

	var presents: Array[Dictionary] = []
	for _frame: int in 100:
		presents.append_array(boot.advance_frame())
	assert_eq(boot.phase(), Boot.PHASE_PRESENTS)
	assert_true(presents.any(func(event: Dictionary) -> bool:
		return event["type"] == &"show_image" and event["id"] == &"game_freak_presents"
	))


## The movie phase spends what `CrystalIntro` spends rather than a budget of the
## coordinator's, so it is driven until its own jumptable sets the exit bit.
## `IntroScene13` is what starts the music, part way in and not at the top;
## tests/unit/test_intro_movie.gd pins the scene budgets themselves.
func test_boot_runs_the_whole_movie_and_opens_the_title_behind_it() -> void:
	var boot := Boot.new()
	boot.start(&"crystal", null, [
		Boot.PHASE_COPYRIGHT, Boot.PHASE_PRESENTS, Boot.PHASE_INTRO_MOVIE,
		Boot.PHASE_TITLE,
	])
	boot.drain_events()
	# The GameFreak animation spends what `GameFreakPresentsScene` spends rather
	# than a budget of the coordinator's, so the movie is reached by driving to
	# it. tests/unit/test_game_freak_presents.gd pins the count itself.
	for _frame: int in 10 + 100 + 500:
		boot.advance_frame()
		if boot.phase() == Boot.PHASE_INTRO_MOVIE:
			break
	assert_eq(boot.phase(), Boot.PHASE_INTRO_MOVIE)

	var title: Array[Dictionary] = []
	var music: Array[Dictionary] = []
	var frames: int = 0
	while boot.phase() == Boot.PHASE_INTRO_MOVIE and frames < FRAME_CAP:
		var events: Array[Dictionary] = boot.advance_frame()
		frames += 1
		title.append_array(events)
		music.append_array(events.filter(func(event: Dictionary) -> bool:
			return event["type"] == &"play_music" \
				and event["phase"] == Boot.PHASE_INTRO_MOVIE
		))
	assert_eq(music.size(), 1, "one `PlayMusic`, which is `IntroScene13`'s")
	assert_eq(int(music[0]["music"]), Gen2IntroMovie.MUSIC_CRYSTAL_OPENING)
	assert_eq(boot.phase(), Boot.PHASE_TITLE)
	assert_true(title.any(func(event: Dictionary) -> bool:
		return event["type"] == &"open_title"
	))
	assert_true(boot.select_title(&"new_game"))
	var new_game: Array[Dictionary] = boot.drain_events()
	assert_eq(boot.phase(), Boot.PHASE_NEW_GAME)
	assert_true(new_game.any(func(event: Dictionary) -> bool:
		return event["type"] == &"open_new_game" and event["profile"] == &"crystal"
	))


func test_boot_sound_wait_is_explicit_and_does_not_consume_frames() -> void:
	var boot := Boot.new()
	boot.start()
	boot.drain_events()
	boot.wait_sound(&"intro_sfx")
	var before: int = boot.frame()
	boot.advance_frame()
	assert_eq(boot.frame(), before)
	assert_false(boot.complete_sound(&"other"))
	assert_true(boot.complete_sound(&"intro_sfx"))
	assert_eq(boot.waiting_sound(), &"")


## `PlaySFX` is inside the GameFreak animation, so the coordinator has to carry
## its requests out to whatever owns a device. The sequence's own frame numbers
## do not cross over: the coordinator's are the ones a caller reads.
func test_the_gamefreak_sounds_reach_the_host() -> void:
	var boot := Boot.new()
	boot.start(&"crystal", null, [Boot.PHASE_COPYRIGHT, Boot.PHASE_PRESENTS])
	boot.drain_events()
	var sounds: Array[int] = []
	var frames: Array[int] = []
	for _frame: int in Boot.COPYRIGHT_PRELUDE_FRAMES + Boot.COPYRIGHT_HOLD_FRAMES + 100:
		for event: Dictionary in boot.advance_frame():
			if event["type"] != &"play_sfx":
				continue
			sounds.append(int(event["sfx"]))
			frames.append(int(event["frame"]))
	assert_eq(sounds, [
		Gen2GameFreakPresents.SFX_DITTO_BOUNCE,
		Gen2GameFreakPresents.SFX_DITTO_BOUNCE,
		Gen2GameFreakPresents.SFX_DITTO_POP_UP,
		Gen2GameFreakPresents.SFX_DITTO_TRANSFORM,
	])
	var offset: int = Boot.COPYRIGHT_PRELUDE_FRAMES + Boot.COPYRIGHT_HOLD_FRAMES
	assert_eq(frames, [offset + 18, offset + 50, offset + 51, offset + 84])


## A host names the phases it has art for, and the source's order is kept
## through what is left: the copyright screen runs and the two the project has
## no graphics for are skipped, rather than held on a blank screen for the
## frames they would have taken.
func test_a_host_without_the_movie_art_runs_only_the_phases_it_names() -> void:
	var boot := Boot.new()
	boot.start(&"crystal", null, [Boot.PHASE_COPYRIGHT])
	boot.drain_events()
	assert_true(boot.is_available(Boot.PHASE_COPYRIGHT))
	assert_false(boot.is_available(Boot.PHASE_PRESENTS))

	var events: Array[Dictionary] = []
	for _frame: int in Boot.COPYRIGHT_PRELUDE_FRAMES + Boot.COPYRIGHT_HOLD_FRAMES:
		events.append_array(boot.advance_frame())

	assert_eq(boot.phase(), Boot.PHASE_FINISHED)
	assert_true(events.any(func(event: Dictionary) -> bool:
		return event["type"] == &"hide_image" and event["id"] == &"copyright"
	))
	assert_true(events.any(func(event: Dictionary) -> bool:
		return event["type"] == &"finish_intro"
	))
	assert_false(events.any(func(event: Dictionary) -> bool:
		return event["type"] == &"show_image" and event["id"] == &"game_freak_presents"
	), "the phase with no art did not run")
	assert_true(boot.advance_frame().is_empty(), "and nothing runs after it")


## Skipping applies to the first phase too: a host that cannot draw the
## copyright screen starts on the next phase it can, with that phase's own
## opening events, rather than spending its hundred and ten frames blank.
func test_a_skipped_copyright_starts_on_the_next_phase_the_host_names() -> void:
	var boot := Boot.new()
	boot.start(&"gold", null, [Boot.PHASE_TITLE])
	assert_eq(boot.phase(), Boot.PHASE_TITLE)
	assert_true(boot.drain_events().any(func(event: Dictionary) -> bool:
		return event["type"] == &"open_title"
	))


## `RunTitleScreen` runs the screen rather than holding the phase: a held START
## answers it, and the answer is what reaches the host.
func test_the_title_phase_runs_its_own_screen_and_answers_the_host() -> void:
	var boot := Boot.new()
	boot.start(&"gold", null, [Boot.PHASE_TITLE])
	assert_eq(boot.phase(), Boot.PHASE_TITLE)
	assert_not_null(boot.title())

	boot.drain_events()
	for _frame: int in 20:
		boot.advance_frame()
	assert_eq(boot.phase(), Boot.PHASE_TITLE, "and it waits for a button")

	var answered: Array[Dictionary] = boot.advance_frame([Gen2Button.START])
	assert_true(answered.any(func(event: Dictionary) -> bool:
		return event["type"] == &"title_menu"
	))
	assert_true(boot.select_title(&"new_game"))
	assert_eq(boot.phase(), Boot.PHASE_NEW_GAME)


## `TitleScreenEnd` jumps back to `IntroSequence`, so a screen nobody pressed
## starts the whole opening again rather than standing still.
func test_a_title_screen_nobody_presses_restarts_the_opening() -> void:
	var boot := Boot.new()
	boot.start(&"gold", null, [Boot.PHASE_TITLE])
	var restarted: bool = false
	for _frame: int in Gen2TitleScene.TIMER_GOLD + 4:
		for event: Dictionary in boot.advance_frame():
			if event["type"] == &"restart_opening":
				restarted = true
		if restarted:
			break
	assert_true(restarted)
	## The order starts again from the top, which with only this phase drawable
	## is this phase, on a screen that has not been answered.
	assert_eq(boot.phase(), Boot.PHASE_TITLE)
	assert_false(boot.title().finished())


## The two chords answer without leaving the screen, because what they open is
## the host's business and `Init` comes back to the title afterwards.
func test_a_chord_is_reported_and_the_screen_stays_up() -> void:
	var boot := Boot.new()
	boot.start(&"gold", null, [Boot.PHASE_TITLE])
	boot.drain_events()
	for _frame: int in 4:
		boot.advance_frame()
	var chord: Array[Dictionary] = boot.advance_frame([
		Gen2Button.UP, Gen2Button.B, Gen2Button.SELECT,
	])
	var reported: Array = chord.filter(func(event: Dictionary) -> bool:
		return event["type"] == &"title_chord"
	)
	assert_eq(reported.size(), 1)
	assert_eq(reported[0]["kind"], &"delete_save_data")
	assert_eq(boot.phase(), Boot.PHASE_TITLE)
	assert_false(boot.title().finished())
	boot.advance_frame()
	assert_eq(boot.title().timer(), Gen2TitleScene.TIMER_GOLD, "on a fresh timer")
