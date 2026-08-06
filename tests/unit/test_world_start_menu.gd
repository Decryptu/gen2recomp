extends GutTest

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

## engine/menus/start_menu.asm's StartMenu.SetUpMenuItems gating, reproduced
## as data: Pokedex behind wStatusFlags/STATUSFLAGS_POKEDEX_F, Pokemon behind
## a non-zero party count, Pokegear behind wPokegearFlags/POKEGEAR_OBTAINED_F,
## everything else always present. Pokedex, Player and Options are always
## built but marked unavailable since this project has none of the three yet.


func _kinds(menu: Gen2WorldStartMenu) -> Array:
	var out: Array = []
	for entry: Dictionary in menu.items():
		out.append(entry.get("kind"))
	return out


func test_default_list_omits_pokedex_pokemon_and_pokegear() -> void:
	var menu: Gen2WorldStartMenu = Gen2WorldStartMenu.build(0, false, false)
	assert_eq(_kinds(menu), [
		Gen2WorldStartMenu.ITEM_PACK, Gen2WorldStartMenu.ITEM_PLAYER,
		Gen2WorldStartMenu.ITEM_SAVE, Gen2WorldStartMenu.ITEM_OPTION,
		Gen2WorldStartMenu.ITEM_EXIT,
	])


func test_pokemon_appears_only_with_a_non_empty_party() -> void:
	var empty: Gen2WorldStartMenu = Gen2WorldStartMenu.build(0, false, false)
	assert_false(_kinds(empty).has(Gen2WorldStartMenu.ITEM_POKEMON))
	var with_party: Gen2WorldStartMenu = Gen2WorldStartMenu.build(1, false, false)
	assert_true(_kinds(with_party).has(Gen2WorldStartMenu.ITEM_POKEMON))


func test_pokegear_appears_only_with_the_source_engine_flag() -> void:
	var without: Gen2WorldStartMenu = Gen2WorldStartMenu.build(0, false, false)
	assert_false(_kinds(without).has(Gen2WorldStartMenu.ITEM_POKEGEAR))
	var with_flag: Gen2WorldStartMenu = Gen2WorldStartMenu.build(0, false, true)
	assert_true(_kinds(with_flag).has(Gen2WorldStartMenu.ITEM_POKEGEAR))


func test_pokedex_appears_only_with_the_source_engine_flag_and_stays_unavailable() -> void:
	var without: Gen2WorldStartMenu = Gen2WorldStartMenu.build(0, false, false)
	assert_false(_kinds(without).has(Gen2WorldStartMenu.ITEM_POKEDEX))
	var with_flag: Gen2WorldStartMenu = Gen2WorldStartMenu.build(0, true, false)
	assert_true(_kinds(with_flag).has(Gen2WorldStartMenu.ITEM_POKEDEX))
	for entry: Dictionary in with_flag.items():
		if entry.get("kind") == Gen2WorldStartMenu.ITEM_POKEDEX:
			assert_false(entry.get("available"))


func test_full_list_matches_the_source_item_order_when_every_gate_is_open() -> void:
	var menu: Gen2WorldStartMenu = Gen2WorldStartMenu.build(1, true, true)
	assert_eq(_kinds(menu), [
		Gen2WorldStartMenu.ITEM_POKEDEX, Gen2WorldStartMenu.ITEM_POKEMON,
		Gen2WorldStartMenu.ITEM_PACK, Gen2WorldStartMenu.ITEM_POKEGEAR,
		Gen2WorldStartMenu.ITEM_PLAYER, Gen2WorldStartMenu.ITEM_SAVE,
		Gen2WorldStartMenu.ITEM_OPTION, Gen2WorldStartMenu.ITEM_EXIT,
	])


func test_pack_pokemon_pokegear_save_and_exit_are_available_player_and_option_are_not() -> void:
	var menu: Gen2WorldStartMenu = Gen2WorldStartMenu.build(1, true, true)
	var available_by_kind: Dictionary = {}
	for entry: Dictionary in menu.items():
		available_by_kind[entry.get("kind")] = entry.get("available")
	assert_true(available_by_kind[Gen2WorldStartMenu.ITEM_PACK])
	assert_true(available_by_kind[Gen2WorldStartMenu.ITEM_POKEMON])
	assert_true(available_by_kind[Gen2WorldStartMenu.ITEM_POKEGEAR])
	assert_true(available_by_kind[Gen2WorldStartMenu.ITEM_SAVE])
	assert_true(available_by_kind[Gen2WorldStartMenu.ITEM_EXIT])
	assert_false(available_by_kind[Gen2WorldStartMenu.ITEM_POKEDEX])
	assert_false(available_by_kind[Gen2WorldStartMenu.ITEM_PLAYER])
	assert_false(available_by_kind[Gen2WorldStartMenu.ITEM_OPTION])


func test_quit_never_appears_because_this_project_has_no_bug_contest() -> void:
	var menu: Gen2WorldStartMenu = Gen2WorldStartMenu.build(1, true, true)
	assert_false(_kinds(menu).has(&"quit"))


## STATICMENU_WRAP is on the source .MenuData flags, so the cursor wraps at
## both ends instead of stopping.
func test_cursor_wraps_at_both_ends() -> void:
	var menu: Gen2WorldStartMenu = Gen2WorldStartMenu.build(0, false, false)
	assert_eq(menu.size(), 5)
	assert_true(menu.move(-1))
	assert_eq(menu.cursor, 4)
	assert_true(menu.move(1))
	assert_eq(menu.cursor, 0)


## wBattleMenuCursorPosition survives a reopen; rebuilding with the previous
## cursor should keep the same selection rather than resetting to the top.
func test_cursor_persists_across_a_rebuild_and_clamps_to_a_shrunk_list() -> void:
	var menu: Gen2WorldStartMenu = Gen2WorldStartMenu.build(1, false, true)
	menu.move(2)
	var reopened: Gen2WorldStartMenu = Gen2WorldStartMenu.build(1, false, true, menu.cursor)
	assert_eq(reopened.cursor, menu.cursor)

	var shrunk: Gen2WorldStartMenu = Gen2WorldStartMenu.build(0, false, false, menu.cursor)
	assert_lt(shrunk.cursor, shrunk.size())


func test_moving_an_empty_menu_does_nothing() -> void:
	var menu := Gen2WorldStartMenu.new()
	assert_false(menu.move(1))
	assert_eq(menu.selected_item(), {})
	assert_eq(menu.selected_kind(), &"")
	assert_false(menu.selected_available())


func test_from_world_reads_party_count_and_engine_flags_off_the_live_world() -> void:
	var data: GameData = Fixture.build()
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6)
	)
	var empty_menu: Gen2WorldStartMenu = Gen2WorldStartMenu.from_world(world)
	assert_false(_kinds(empty_menu).has(Gen2WorldStartMenu.ITEM_POKEMON))
	assert_false(_kinds(empty_menu).has(Gen2WorldStartMenu.ITEM_POKEGEAR))

	world.set_party_summary(1, false)
	world.state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEGEAR)
	var populated_menu: Gen2WorldStartMenu = Gen2WorldStartMenu.from_world(world)
	assert_true(_kinds(populated_menu).has(Gen2WorldStartMenu.ITEM_POKEMON))
	assert_true(_kinds(populated_menu).has(Gen2WorldStartMenu.ITEM_POKEGEAR))

	assert_eq(_kinds(Gen2WorldStartMenu.from_world(null)), _kinds(Gen2WorldStartMenu.build(0, false, false)))
	RomCache.clear(Fixture.directory())
