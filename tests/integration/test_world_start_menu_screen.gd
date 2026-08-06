extends GutTest

## Scene integration for the overworld start menu. The fixture is synthetic,
## but the world screen, script runner and UI scenes are the production paths.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	_data = Fixture.build()
	_write_pack_item()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


func _write_pack_item() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		if int(raw.get("number", 0)) == 7:
			raw["name"] = "POTION"
			raw["pocket"] = Gen2WorldPack.TYPE_ITEM
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)


func _open_world() -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	var state := Gen2WorldState.new({}, {}, {7: 1}, {0: 500})
	var world := Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6), state
	)
	var save := Gen2SaveStore.create_development_save(_data, 0)
	save.world = world.snapshot()
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame


func test_start_menu_opens_and_blocks_movement() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	assert_not_null(_world_screen._start_menu_host)
	assert_false(_world_screen.move_player(Vector2i.RIGHT))
	assert_false(_world_screen._objects_may_move())


func test_exit_closes_the_menu_and_restores_movement() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	## EXIT is the source's guaranteed last entry.
	while host.cursor() < host.get("_menu").size() - 1:
		host.handle_key(KEY_DOWN)
	assert_eq(host.get("_menu").selected_kind(), Gen2WorldStartMenu.ITEM_EXIT)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	assert_true(_world_screen._objects_may_move())


func test_cancel_closes_the_menu_the_same_as_exit() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	host.handle_key(KEY_ESCAPE)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	assert_true(_world_screen._objects_may_move())


func test_pokemon_opens_the_embedded_party_screen_and_returns() -> void:
	await _open_world()
	_world_screen._world.set_party_summary(1, false)
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	assert_true(_kinds(host).has(Gen2WorldStartMenu.ITEM_POKEMON))
	_select(host, Gen2WorldStartMenu.ITEM_POKEMON)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	var party: Gen2PartyScreen = _world_screen._party_host
	assert_not_null(party)

	party.close_embedded()
	await get_tree().process_frame
	assert_null(_world_screen._party_host)
	assert_true(_world_screen._objects_may_move())


func test_pack_lists_a_granted_item() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_PACK)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	var items_pocket: Dictionary = host.get("_pack_pockets")[0]
	assert_eq(items_pocket["pocket"], Gen2WorldPack.TYPE_ITEM)
	var items: Array = items_pocket["items"]
	assert_eq(items.size(), 1)
	assert_eq(items[0]["item"], 7)
	assert_eq(items[0]["quantity"], 1)

	host.handle_key(KEY_ESCAPE)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.LIST)


func test_pokegear_reaches_the_existing_phone_list() -> void:
	await _open_world()
	_world_screen._world.state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEGEAR)
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	assert_true(_kinds(host).has(Gen2WorldStartMenu.ITEM_POKEGEAR))
	_select(host, Gen2WorldStartMenu.ITEM_POKEGEAR)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	assert_not_null(_world_screen._service_host)


func test_save_writes_a_snapshot_to_the_injected_save_without_touching_disk() -> void:
	await _open_world()
	var save: Gen2SaveData = _world_screen._injected_save
	## Set an event flag in place instead of moving, since a real move can
	## roll this fixture's own wild grass encounter and open a battle; the
	## screen's own _process() re-derives the clock from Gen2WorldClock every
	## frame, so the clock is not a stable field to change for this check.
	const MARKER_FLAG: int = 50
	assert_false(save.world.world_state.is_event_flag_active(MARKER_FLAG))
	_world_screen._world.state.set_event_flag(MARKER_FLAG)
	var expected: Gen2WorldSnapshot = _world_screen._world.snapshot()

	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_SAVE)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.SAVE_CONFIRM)
	## Yes is the confirm menu's default cursor position.
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(save.world.map_id, expected.map_id)
	assert_eq(save.world.player_cell, expected.player_cell)
	assert_true(save.world.world_state.is_event_flag_active(MARKER_FLAG))
	## Continue returns to the list without reopening a fresh menu instance.
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.LIST)


## Covers three of _open_start_menu()'s busy-state guards directly; the fourth
## (phone_ring_active()) is the identical one-line pattern and is exercised
## for the rest of the screen by test_world_service_screen.gd's phone cases.
func test_start_menu_does_not_open_while_battling_fishing_or_scripted() -> void:
	await _open_world()

	_world_screen._battle_host = Gen2BattleScreen.new()
	_world_screen._open_start_menu()
	assert_null(_world_screen._start_menu_host)
	_world_screen._battle_host.free()
	_world_screen._battle_host = null

	_world_screen._world._fishing._state = Gen2WorldFishing.STATE_CASTING
	_world_screen._open_start_menu()
	assert_null(_world_screen._start_menu_host)
	_world_screen._world._fishing._state = Gen2WorldFishing.STATE_IDLE

	## The script cache is lazy-loaded from disk on first use, so writing the
	## file now still reaches the already-open Gen2WorldAPI instance; the map's
	## coord_events were already parsed into memory, so that part is set
	## directly rather than by rewriting the maps cache too late to matter.
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6320)] = [
		Gen2WorldScript.SPECIAL, 27, 0, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_world_screen._world.current_map.events["coord_events"] = [
		{"x": 7, "y": 6, "script": 0x6320}
	]
	var waiting: Array = _world_screen._world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(waiting[0]["status"], &"waiting")
	assert_true(_world_screen._world.script_busy())
	_world_screen._open_start_menu()
	assert_null(_world_screen._start_menu_host)


func _kinds(host: Gen2StartMenuScreen) -> Array:
	var out: Array = []
	for entry: Dictionary in (host.get("_menu") as Gen2WorldStartMenu).items():
		out.append(entry.get("kind"))
	return out


func _select(host: Gen2StartMenuScreen, kind: StringName) -> void:
	var menu: Gen2WorldStartMenu = host.get("_menu")
	var guard: int = menu.size() + 1
	while menu.selected_kind() != kind and guard > 0:
		host.handle_key(KEY_DOWN)
		guard -= 1
	assert_eq(menu.selected_kind(), kind)
