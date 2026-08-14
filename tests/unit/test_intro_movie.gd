extends GutTest

## `CrystalIntro`'s jumptable, driven without a cache.
##
## Every frame count here is the source's own: the scenes count in
## `wIntroSceneFrameCounter` and spend `DelayFrames`, neither of which depends on
## the art being imported, so the whole movie runs and lands on the same frame
## with no [GameData] at all. tools/validate_intro_movie.gd is what checks the
## art it draws with.

## Longer than the movie, whose own total is asserted below.
const FRAME_CAP: int = 20000

## `IntroScene28` sets `JUMPTABLE_EXIT_F` on this frame.
const MOVIE_FRAMES: int = 1784
## The frame each of the twenty-eight scenes starts on.
const SCENE_STARTS: Array[int] = [
	0, 1, 132, 133, 264, 265, 396, 397, 494, 495, 694, 695, 890, 891, 1022, 1023,
	1154, 1155, 1254, 1255, 1410, 1411, 1423, 1424, 1457, 1521, 1522, 1655,
]


func _movie() -> Gen2IntroMovie:
	return Gen2IntroMovie.create(null, null)


## The budget the boot cinema spends, and the scene it spends each frame in.
func test_the_movie_runs_every_scene_and_sets_its_own_exit_bit() -> void:
	var movie: Gen2IntroMovie = _movie()
	var starts: Array[int] = [0]
	var scene: int = 0
	while not movie.finished() and movie.frame() < FRAME_CAP:
		movie.advance_frame()
		if movie.scene() != scene:
			scene = movie.scene()
			starts.append(movie.frame())
	assert_true(movie.finished())
	assert_eq(movie.frame(), MOVIE_FRAMES)
	assert_eq(starts, SCENE_STARTS)
	assert_eq(starts.size(), RomLayout.INTRO_SCENES)


## `IntroScene13` is the only `PlayMusic` in the movie, so the GameFreak logo's
## silence runs a third of the way in before the opening theme starts.
func test_the_music_starts_part_way_in_and_only_once() -> void:
	var movie: Gen2IntroMovie = _movie()
	var music: Array[Dictionary] = []
	while not movie.finished() and movie.frame() < FRAME_CAP:
		for event: Dictionary in movie.advance_frame():
			if event["type"] == &"play_music":
				music.append(event)
	assert_eq(music.size(), 1)
	assert_eq(int(music[0]["music"]), Gen2IntroMovie.MUSIC_CRYSTAL_OPENING)
	assert_eq(int(music[0]["frame"]), SCENE_STARTS[12] + 1)


## The eight `.UnownSounds` rows plus the nine the scenes play directly, in the
## order the movie asks for them.
func test_every_scene_asks_for_its_own_sounds() -> void:
	var movie: Gen2IntroMovie = _movie()
	var sfx: Array[int] = []
	while not movie.finished() and movie.frame() < FRAME_CAP:
		for event: Dictionary in movie.advance_frame():
			if event["type"] == &"play_sfx":
				sfx.append(int(event["sfx"]))
	assert_eq(sfx, [
		Gen2IntroMovie.SFX_INTRO_UNOWN_1,
		Gen2IntroMovie.SFX_INTRO_UNOWN_2, Gen2IntroMovie.SFX_INTRO_UNOWN_1,
		Gen2IntroMovie.SFX_INTRO_SUICUNE_3, Gen2IntroMovie.SFX_INTRO_SUICUNE_2,
		Gen2IntroMovie.SFX_INTRO_PICHU, Gen2IntroMovie.SFX_INTRO_PICHU,
		Gen2IntroMovie.SFX_INTRO_UNOWN_3, Gen2IntroMovie.SFX_INTRO_UNOWN_2,
		Gen2IntroMovie.SFX_INTRO_UNOWN_1, Gen2IntroMovie.SFX_INTRO_UNOWN_2,
		Gen2IntroMovie.SFX_INTRO_UNOWN_3, Gen2IntroMovie.SFX_INTRO_UNOWN_2,
		Gen2IntroMovie.SFX_INTRO_UNOWN_1, Gen2IntroMovie.SFX_INTRO_UNOWN_2,
		Gen2IntroMovie.SFX_INTRO_SUICUNE_4, Gen2IntroMovie.SFX_INTRO_WHOOSH,
	])


## `CrystalIntro_InitUnownAnim` spawns four structs at one point, each on its own
## frameset, and `Frameset_IntroUnown1` ends on `oamdelete`, so the burst takes
## itself away rather than standing there.
func test_the_unown_burst_is_four_structs_that_delete_themselves() -> void:
	var movie: Gen2IntroMovie = _movie()
	var most: int = 0
	while movie.scene() < 2 and movie.frame() < FRAME_CAP:
		movie.advance_frame()
		most = maxi(most, movie.sprites().size())
	assert_eq(most, Gen2IntroMovie.UNOWN_BURST.size())
	assert_eq(movie.sprites().size(), 0, "and none of them survives the scene")


## `SpriteAnimFunc_IntroSuicuneAway` moves its struct sixteen pixels a frame on a
## coordinate that is a byte, so it wraps rather than clamping and comes back
## round the top of the screen.
func test_a_sprite_coordinate_wraps_rather_than_clamping() -> void:
	var movie: Gen2IntroMovie = _movie()
	while movie.scene() < 19 and movie.frame() < FRAME_CAP:
		movie.advance_frame()
	var seen: Array[int] = []
	for _frame: int in 20:
		movie.advance_frame()
		for sprite: Dictionary in movie.sprites():
			seen.append((sprite["at"] as Vector2i).y)
	assert_true(seen.size() > 0, "the scene has a sprite in it")
	for y: int in seen:
		assert_between(y, 0, 0xFF)
	assert_true(seen.min() < seen[0], "and it has come back round the top")


## `.ShutOffMusic`: a button ends the whole movie and stops the music with it.
func test_a_button_ends_the_movie_and_the_music() -> void:
	var movie: Gen2IntroMovie = _movie()
	for _frame: int in 40:
		movie.advance_frame()
	movie.drain_events()
	assert_true(movie.cancel())
	var events: Array[Dictionary] = movie.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"play_music")
	assert_eq(int(events[0]["music"]), 0)
	assert_true(movie.finished())
	assert_false(movie.cancel(), "and it only ends once")


## A cache without the art is what Gold and Silver are: the movie is not offered
## rather than run blank.
func test_a_cache_without_the_art_does_not_offer_the_movie() -> void:
	assert_false(Gen2IntroMovie.available(null))
	assert_null(Gen2IntroMoviePage.from_data(null))
