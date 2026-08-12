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
