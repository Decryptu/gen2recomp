extends GutTest

const Boot := preload("res://game/world/boot_cinema.gd")


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


func test_boot_keeps_intro_music_continuous_and_opens_title_after_28_scenes() -> void:
	var lengths: Array[int] = []
	for _scene: int in 28:
		lengths.append(1)
	lengths[0] = 2308
	var boot := Boot.new()
	boot.start(&"crystal", lengths)
	boot.drain_events()
	var movie_start: Array[Dictionary] = []
	for _frame: int in 10 + 100 + 32 + 64 + 128:
		movie_start.append_array(boot.advance_frame())
	assert_eq(boot.phase(), Boot.PHASE_INTRO_MOVIE)
	assert_true(movie_start.any(func(event: Dictionary) -> bool:
		return event["type"] == &"play_music" and event["music"] == &"gold_silver_opening"
	))

	var title: Array[Dictionary] = []
	for _frame: int in 2335:
		title.append_array(boot.advance_frame())
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


## A host names the phases it has art for, and the source's order is kept
## through what is left: the copyright screen runs and the two the project has
## no graphics for are skipped, rather than held on a blank screen for the
## frames they would have taken.
func test_a_host_without_the_movie_art_runs_only_the_phases_it_names() -> void:
	var boot := Boot.new()
	boot.start(&"crystal", [], [Boot.PHASE_COPYRIGHT])
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
	boot.start(&"gold", [], [Boot.PHASE_TITLE])
	assert_eq(boot.phase(), Boot.PHASE_TITLE)
	assert_true(boot.drain_events().any(func(event: Dictionary) -> bool:
		return event["type"] == &"open_title"
	))
