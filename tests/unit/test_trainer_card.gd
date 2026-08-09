extends GutTest

## engine/menus/trainer_card.asm, as the page data and the page walk.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _world: Gen2WorldAPI = null
var _save: Gen2SaveData = null


func before_each() -> void:
	_data = Fixture.build()
	_world = Gen2WorldAPI.open(_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6))
	_save = Gen2SaveStore.create_development_save(_data, 0)
	_save.player_name = "GOLD"
	_save.player_id = 54321
	_save.game_time = Gen2GameTime.create(37, 8, 0, 0)


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func test_page_one_carries_the_fields_the_top_half_and_the_status_box_print() -> void:
	_world.state.apply_changes({}, {}, {"money": {0: 12345}})
	var page: Dictionary = Gen2TrainerCard.page(_save, _world, Gen2TrainerCard.PAGE_1)
	assert_eq(String(page["player_name"]), "GOLD")
	assert_eq(int(page["player_id"]), 54321)
	assert_eq(int(page["money"]), 12345)
	assert_eq(String(page["hours"]), "  37")
	assert_eq(String(page["minutes"]), "08")


## `TrainerCard_Page1_PrintDexCaught_GameTime` clears its own dex row when
## STATUSFLAGS_POKEDEX_F is clear, so the count is not printed at all.
func test_the_dex_count_is_the_caught_flags_and_only_with_the_pokedex() -> void:
	_world.state.apply_changes({}, {}, {"caught_species": {1: true, 4: true, 7: true}})
	var without: Dictionary = Gen2TrainerCard.page(_save, _world, Gen2TrainerCard.PAGE_1)
	assert_false(bool(without["pokedex"]))
	assert_eq(int(without["caught"]), 3)

	_world.state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEDEX)
	var with_dex: Dictionary = Gen2TrainerCard.page(_save, _world, Gen2TrainerCard.PAGE_1)
	assert_true(bool(with_dex["pokedex"]))
	assert_eq(int(with_dex["caught"]), 3)


func test_page_one_has_no_badges_and_the_two_badge_pages_split_johto_from_kanto() -> void:
	_world.state.set_engine_flag(Gen2WorldState.badge_flag(0, true))
	_world.state.set_engine_flag(Gen2WorldState.badge_flag(9, true))
	assert_eq(Gen2TrainerCard.page(_save, _world, Gen2TrainerCard.PAGE_1)["badges"], [])

	var johto: Array = Gen2TrainerCard.page(_save, _world, Gen2TrainerCard.PAGE_2)["badges"]
	assert_eq(johto.size(), Gen2TrainerCard.BADGES_PER_PAGE)
	assert_true(bool(johto[0]), "the Zephyr badge is the first Johto bit")
	assert_false(bool(johto[1]))

	var kanto: Array = Gen2TrainerCard.page(_save, _world, Gen2TrainerCard.PAGE_3)["badges"]
	assert_true(bool(kanto[1]), "badge 9 is the second Kanto bit")
	assert_false(bool(kanto[0]))


## Page 1 answers right and A with page 2; page 2 answers A with the exit and
## left with page 1. Both `.KantoBadgeCheck` branches are unreferenced, so
## nothing reaches page 3, and B leaves from anywhere.
func test_the_page_walk_is_the_source_jumptable() -> void:
	assert_eq(
		Gen2TrainerCard.next_page(Gen2TrainerCard.PAGE_1, Gen2Button.RIGHT),
		{"page": Gen2TrainerCard.PAGE_2}
	)
	assert_eq(
		Gen2TrainerCard.next_page(Gen2TrainerCard.PAGE_1, Gen2Button.A),
		{"page": Gen2TrainerCard.PAGE_2}
	)
	assert_eq(Gen2TrainerCard.next_page(Gen2TrainerCard.PAGE_1, Gen2Button.LEFT), {})

	assert_eq(
		Gen2TrainerCard.next_page(Gen2TrainerCard.PAGE_2, Gen2Button.LEFT),
		{"page": Gen2TrainerCard.PAGE_1}
	)
	assert_eq(
		Gen2TrainerCard.next_page(Gen2TrainerCard.PAGE_2, Gen2Button.A), {"exit": true}
	)
	assert_eq(
		Gen2TrainerCard.next_page(Gen2TrainerCard.PAGE_2, Gen2Button.RIGHT), {},
		"nothing on page 2 reaches page 3"
	)

	assert_eq(
		Gen2TrainerCard.next_page(Gen2TrainerCard.PAGE_3, Gen2Button.LEFT),
		{"page": Gen2TrainerCard.PAGE_2}
	)
	assert_eq(
		Gen2TrainerCard.next_page(Gen2TrainerCard.PAGE_3, Gen2Button.RIGHT),
		{"page": Gen2TrainerCard.PAGE_1}
	)
	for page: int in [Gen2TrainerCard.PAGE_1, Gen2TrainerCard.PAGE_2, Gen2TrainerCard.PAGE_3]:
		assert_eq(Gen2TrainerCard.next_page(page, Gen2Button.B), {"exit": true})


func test_no_save_answers_no_page() -> void:
	assert_eq(Gen2TrainerCard.page(null, _world, Gen2TrainerCard.PAGE_1), {})
