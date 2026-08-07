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


## Item 7 carries POTION's real ItemAttributes row, so the pack builds the
## source's own USE/GIVE/TOSS/QUIT submenu for it and USE reaches .Party.
func _write_pack_item() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		if int(raw.get("number", 0)) == 7:
			raw["name"] = "POTION"
			raw["pocket"] = Gen2WorldPack.TYPE_ITEM
			raw["permissions"] = Gen2WorldPack.CANT_SELECT
			raw["field_menu"] = Gen2WorldPack.ITEMMENU_PARTY
			raw["heal_amount"] = 20
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


## HM04 with its real item number, plus the TM/HM table and the flag bit that
## lets the development save's first party member learn it.
const HM_ITEM: int = 0xF6
const HM_MOVE: int = 0x46


func _write_tmhm_item(learnable: bool = true) -> void:
	var table: Array = []
	for index: int in RomLayout.TMHM_TM_COUNT + RomLayout.TMHM_HM_COUNT:
		table.append(0x60 + index)
	table[RomLayout.TMHM_TM_COUNT + 3] = HM_MOVE
	RomCache.write_json(RomCache.tmhm_moves_path(Fixture.directory()), table)

	var moves: Array = RomCache.read_json(RomCache.moves_path(Fixture.directory()))
	for raw: Dictionary in moves:
		if int(raw.get("number", 0)) == HM_MOVE:
			raw["name"] = "STRENGTH"
			raw["pp"] = 15
	RomCache.write_json(RomCache.moves_path(Fixture.directory()), moves)

	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	while items.size() < HM_ITEM:
		items.append({
			"number": items.size() + 1, "name": "HM%02d" % items.size(),
			"permissions": 0, "pocket": Gen2WorldPack.TYPE_TM_HM,
			"field_menu": 0, "battle_menu": 0, "status_mask": 0, "heal_amount": 0,
		})
	(items[HM_ITEM - 1] as Dictionary)["name"] = "HM04"
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)

	var species: Array = RomCache.read_json(RomCache.species_path(Fixture.directory()))
	for raw: Dictionary in species:
		var flags: Array = []
		flags.resize(RomLayout.TMHM_BYTES)
		for index: int in flags.size():
			flags[index] = 0
		if learnable:
			# TMNUM 54, so bit 53: byte 6, bit 5 from the low end.
			flags[6] = 0x20
		raw["tmhm"] = flags
	RomCache.write_json(RomCache.species_path(Fixture.directory()), species)
	_data = GameData.open_directory(Fixture.directory())


## Opens the pack on the TM/HM pocket with HM04 in the bag and the cursor on it.
## _write_tmhm_item() has to have run before the world screen was built, since
## the screen keeps the GameData it was handed.
func _open_tmhm_pack() -> Gen2StartMenuScreen:
	_world_screen._world.state.apply_changes({}, {}, {"items": {HM_ITEM: 1}})
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_PACK)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	var pockets: Array = host.get("_pack_pockets")
	for index: int in pockets.size():
		if int((pockets[index] as Dictionary)["pocket"]) == Gen2WorldPack.TYPE_TM_HM:
			host.set("_pack_pocket_index", index)
			break
	host.set("_pack_cursor", 0)
	return host


## engine/items/pack.asm gives the TM/HM pocket its own USE, which runs
## AskTeachTMHM rather than reaching UseItem's jumptable.
func test_tmhm_use_asks_before_teaching_and_a_yes_teaches_the_move() -> void:
	_write_tmhm_item()
	await _open_world()
	var host: Gen2StartMenuScreen = await _open_tmhm_pack()
	var save: Gen2SaveData = _world_screen._injected_save
	assert_false(save.party[0].moves.has(HM_MOVE))

	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_ITEM)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame

	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TEACH)
	assert_eq(
		String(host.get("_teach_prompt")["text"]),
		"Booted up an HM. It contained STRENGTH. Teach STRENGTH to a #MON?"
	)

	## Yes is the prompt's default cursor position, matching YesNoBox.
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TARGET)

	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_true(bool(host.get("_pack_result_ok")), String(host.get("_pack_result")))
	assert_true(save.party[0].moves.has(HM_MOVE))
	## IsHM returns before ConsumeTM, so the HM stays in the bag.
	assert_eq(_world_screen._world.state.item_quantity(HM_ITEM), 1)


## The yes/no is a real refusal, not decoration: no leaves the party alone.
func test_tmhm_use_declined_teaches_nothing() -> void:
	_write_tmhm_item()
	await _open_world()
	var host: Gen2StartMenuScreen = await _open_tmhm_pack()
	var save: Gen2SaveData = _world_screen._injected_save

	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TEACH)

	host.handle_key(KEY_DOWN)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	assert_false(save.party[0].moves.has(HM_MOVE))


## CanLearnTMHMMove is the first thing TeachTMHM asks, and its refusal is
## TMHMNotCompatibleText rather than a silent no-op.
func test_tmhm_use_reports_an_incompatible_species() -> void:
	_write_tmhm_item(false)
	await _open_world()
	var host: Gen2StartMenuScreen = await _open_tmhm_pack()
	var save: Gen2SaveData = _world_screen._injected_save

	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame

	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_false(bool(host.get("_pack_result_ok")))
	assert_true(
		String(host.get("_pack_result")).contains("not compatible"),
		String(host.get("_pack_result"))
	)
	assert_false(save.party[0].moves.has(HM_MOVE))


## Fills the first party member's four move slots so LearnMove's scan finds no
## zero and reaches ForgetMove. Slot 1 is SURF, HM03, the row .hmmove refuses.
func _fill_moveset(with_hm: bool = true) -> Gen2SaveMon:
	var mon: Gen2SaveMon = _world_screen._injected_save.party[0]
	mon.moves = [1, 0x39 if with_hm else 2, 3, 4]
	mon.pp = [10, 10, 10, 10]
	return mon


## Walks the pack to the TEACH prompt and answers yes, which reaches the party
## list and then LearnMove.
func _reach_forget_ask() -> Gen2StartMenuScreen:
	var host: Gen2StartMenuScreen = await _open_tmhm_pack()
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	return host


## LearnMove reaches ForgetMove, whose ask comes before the list.
func test_a_full_moveset_opens_forget_move_and_a_choice_replaces_that_slot() -> void:
	_write_tmhm_item()
	await _open_world()
	var mon: Gen2SaveMon = _fill_moveset()
	var host: Gen2StartMenuScreen = await _reach_forget_ask()

	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_FORGET_ASK)
	assert_true(
		String(host.get("_summary").text).contains("can't learn more than four moves"),
		String(host.get("_summary").text)
	)

	## Yes is YesNoBox's default, which opens the list.
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_FORGET)
	assert_eq((host.get("_forget_moves") as Array).size(), 4)

	## Slot 2, past the HM, is an ordinary move.
	host.handle_key(KEY_DOWN)
	host.handle_key(KEY_DOWN)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_true(bool(host.get("_pack_result_ok")), String(host.get("_pack_result")))
	assert_eq(_world_screen._injected_save.party[0].moves, [1, 0x39, HM_MOVE, 4])
	assert_true(String(host.get("_pack_result")).contains("forgot"), String(host.get("_pack_result")))


## .hmmove prints MoveCantForgetHMText and is `jr .loop`, so the list stays open
## and nothing is written.
func test_choosing_an_hm_row_refuses_and_keeps_the_list_open() -> void:
	_write_tmhm_item()
	await _open_world()
	_fill_moveset()
	var host: Gen2StartMenuScreen = await _reach_forget_ask()
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame

	host.handle_key(KEY_DOWN)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame

	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_FORGET, "the list stays open")
	assert_eq(String(host.get("_status").text), "HM moves can't be forgotten now.")
	assert_eq(_world_screen._injected_save.party[0].moves, [1, 0x39, 3, 4])


## No at the ask is YesNoBox's carry, which is LearnMove.cancel: the
## stop-learning yes/no, and yes there ends with DidNotLearnMoveText.
func test_refusing_to_forget_reaches_stop_learning_and_teaches_nothing() -> void:
	_write_tmhm_item()
	await _open_world()
	_fill_moveset()
	var host: Gen2StartMenuScreen = await _reach_forget_ask()

	host.handle_key(KEY_DOWN)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_STOP_LEARNING)
	assert_true(
		String(host.get("_summary").text).begins_with("Stop learning"),
		String(host.get("_summary").text)
	)

	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_false(bool(host.get("_pack_result_ok")))
	assert_true(
		String(host.get("_pack_result")).contains("did not learn"),
		String(host.get("_pack_result"))
	)
	assert_eq(_world_screen._injected_save.party[0].moves, [1, 0x39, 3, 4])
	## An HM is never consumed, refused or not.
	assert_eq(_world_screen._world.state.item_quantity(HM_ITEM), 1)


## No to "Stop learning?" is `jp .loop`, which reaches ForgetMove's ask again
## rather than ending the offer.
func test_declining_to_stop_returns_to_the_forget_ask() -> void:
	_write_tmhm_item()
	await _open_world()
	_fill_moveset()
	var host: Gen2StartMenuScreen = await _reach_forget_ask()

	host.handle_key(KEY_DOWN)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_STOP_LEARNING)

	host.handle_key(KEY_DOWN)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_FORGET_ASK)
	## YesNoBox opens on YES every time it is opened.
	assert_eq(host.get("_forget_confirm_cursor"), 0)


## B in the list is ForgetMove's own .cancel, the same carry the ask's no sets.
func test_backing_out_of_the_move_list_reaches_stop_learning() -> void:
	_write_tmhm_item()
	await _open_world()
	_fill_moveset()
	var host: Gen2StartMenuScreen = await _reach_forget_ask()
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_FORGET)

	host.handle_key(KEY_ESCAPE)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_STOP_LEARNING)


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


## Opens the pack with the cursor on the granted Potion, having damaged the
## first party member so the item has something to do.
func _open_pack_with_a_hurt_party() -> Gen2StartMenuScreen:
	await _open_world()
	var save: Gen2SaveData = _world_screen.get("_injected_save")
	var mon: Gen2SaveMon = save.party[0]
	mon.hp = maxi(mon.hp - 15, 1)
	mon.nickname = "TESTMON"
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_PACK)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	return host


func test_choosing_an_item_opens_the_source_submenu() -> void:
	var host: Gen2StartMenuScreen = await _open_pack_with_a_hurt_party()
	host.handle_key(KEY_ENTER)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_ITEM)
	var labels: Array = []
	for entry: Dictionary in host.get("_item_actions"):
		labels.append(String(entry.get("label", "")))
	assert_eq(labels, ["USE", "GIVE", "TOSS", "QUIT"])

	# QUIT returns to the pocket list, keeping the cursor the source restores.
	while StringName((host.get("_item_actions")[host.get("_item_cursor")] as Dictionary)
		.get("action", &"")) != Gen2WorldPack.ACTION_QUIT:
		host.handle_key(KEY_DOWN)
	host.handle_key(KEY_ENTER)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)


func test_use_on_a_party_item_asks_which_mon_then_heals_and_spends_it() -> void:
	var host: Gen2StartMenuScreen = await _open_pack_with_a_hurt_party()
	var save: Gen2SaveData = _world_screen.get("_injected_save")
	var before: int = (save.party[0] as Gen2SaveMon).hp
	host.handle_key(KEY_ENTER)
	host.handle_key(KEY_ENTER)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TARGET)
	# Nothing has changed until the target is chosen.
	assert_eq((save.party[0] as Gen2SaveMon).hp, before)
	assert_eq(_world_screen._world.state.item_quantity(7), 1)

	host.handle_key(KEY_ENTER)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq((save.party[0] as Gen2SaveMon).hp, before + 15)
	assert_eq(_world_screen._world.state.item_quantity(7), 0)
	assert_eq(String(host.get("_pack_result")), "POTION restored 15 HP.")

	# The spent item leaves the pocket on the way back.
	host.handle_key(KEY_ENTER)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	assert_eq(((host.get("_pack_pockets")[0] as Dictionary)["items"] as Array).size(), 0)


func test_using_an_item_with_nothing_to_do_reports_it_and_spends_nothing() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_PACK)
	host.handle_key(KEY_ENTER)
	await get_tree().process_frame
	host.handle_key(KEY_ENTER)
	host.handle_key(KEY_ENTER)
	host.handle_key(KEY_ENTER)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq(String(host.get("_pack_result")), "It won't have any effect.")
	assert_eq(_world_screen._world.state.item_quantity(7), 1)


## UseItem's .Oak branch: an item whose field menu is ITEMMENU_NOUSE never
## reaches an effect at all.
func test_an_item_with_no_field_menu_reports_oaks_refusal() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		if int(raw.get("number", 0)) == 7:
			raw["field_menu"] = Gen2WorldPack.ITEMMENU_NOUSE
			raw["permissions"] = Gen2WorldPack.CANT_TOSS
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)
	_data = GameData.open_directory(Fixture.directory())

	var host: Gen2StartMenuScreen = await _open_pack_with_a_hurt_party()
	host.handle_key(KEY_ENTER)
	# CANT_TOSS with CANT_SELECT clear is MenuHeader_UnusableKeyItem: USE stays.
	host.handle_key(KEY_ENTER)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq(String(host.get("_pack_result")), Gen2StartMenuScreen.OAK_TEXT)
	assert_eq(_world_screen._world.state.item_quantity(7), 1)
