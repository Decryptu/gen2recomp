extends GutTest

## `Rate` and `ProfOaksPCBoot` (engine/events/prof_oaks_pc.asm).

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null


func before_each() -> void:
	_data = Fixture.build()


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _state(caught: int) -> Gen2WorldState:
	var state := Gen2WorldState.new()
	for species: int in range(1, caught + 1):
		state.set_species_caught(species)
	return state


## `FindOakRating` takes the first row whose threshold the count does not exceed,
## so both ends of a band answer the same row and the one past it does not.
func test_every_band_answers_its_own_row() -> void:
	var previous: int = -1
	for index: int in Fixture.OAK_THRESHOLDS.size():
		var threshold: int = Fixture.OAK_THRESHOLDS[index]
		for caught: int in [previous + 1, threshold]:
			assert_eq(
				int(Gen2ProfOaksPC.rating_for(_data, caught).get("threshold", -1)),
				threshold,
				"caught %d" % caught
			)
		previous = threshold


func test_the_last_row_answers_a_full_dex() -> void:
	var rating: Dictionary = Gen2ProfOaksPC.rating_for(_data, 251)
	assert_eq(int(rating["threshold"]), RomLayout.OAK_RATING_LAST_THRESHOLD)
	assert_eq(String(rating["text"]), "RATING19")


## `ProfOaksPCBoot` prints the level line, then `Rate`'s counts, then the rating,
## and plays the sound that row carries.
func test_the_boot_is_three_pages_and_the_row_s_own_sound() -> void:
	var boot: Dictionary = Gen2ProfOaksPC.boot(_data, _state(20))
	assert_eq(boot["seen"], 20)
	assert_eq(boot["caught"], 20)
	assert_eq(boot["sfx"], Fixture.OAK_FIRST_SFX + 2, "the 20..34 row")
	var pages: Array = boot["pages"]
	assert_eq(pages.size(), 3)
	assert_eq(String(pages[0]), "LEVEL:")
	assert_eq(String(pages[2]), "RATING03")


## `.UpdateRatingBuffers` fills `wStringBuffer3` with the seen count and
## `wStringBuffer4` with the owned one, in that order, and `PrintNum`'s left
## alignment writes the significant digits and nothing else.
func test_the_counts_page_fills_both_ram_slots_in_order() -> void:
	assert_eq(Gen2ProfOaksPC.counts_text(_data, 7, 3), "7 SEEN\n3 OWNED")
	assert_eq(Gen2ProfOaksPC.counts_text(_data, 251, 0), "251 SEEN\n0 OWNED")


func test_a_cache_without_the_table_answers_nothing() -> void:
	assert_true(Gen2ProfOaksPC.boot(null, _state(0)).is_empty())
