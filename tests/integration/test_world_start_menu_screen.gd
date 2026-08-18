extends GutTest

## Scene integration for the overworld start menu. The fixture is synthetic,
## but the world screen, script runner and UI scenes are the production paths.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

## `ITEM_REPEL`, whose effect `UseItem` keys on the item number for.
const REPEL: int = 0x14
## ITEMMENU_CLOSE rows at their real numbers: two `.Field` runs here and one it
## does not, which is what says the pack quits on the effect rather than on the
## menu nibble.
const ITEMFINDER: int = 0x37
const CARD_KEY: int = 0x7F
const OLD_ROD: int = Gen2WorldInventory.ITEM_OLD_ROD

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	_data = Fixture.build()
	_write_pack_item()
	_data = GameData.open_directory(Fixture.directory())
	## The OPTION menu writes through Gen2OptionsStore, so the file and the
	## shared instance both start clean.
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())


## Item 7 carries POTION's real ItemAttributes row, so the pack builds the
## source's own USE/GIVE/TOSS/QUIT submenu for it and USE reaches .Party. Item
## $14 is REPEL's, which is the number `UseItem`'s own effect keys on: it carries
## no permission bit at all, so it is the row that reaches SEL.
func _write_pack_item() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		match int(raw.get("number", 0)):
			7:
				raw["name"] = "POTION"
				raw["pocket"] = Gen2WorldPack.TYPE_ITEM
				raw["permissions"] = Gen2WorldPack.CANT_SELECT
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_PARTY
				raw["heal_amount"] = 20
			REPEL:
				raw["name"] = "REPEL"
				raw["pocket"] = Gen2WorldPack.TYPE_ITEM
				raw["permissions"] = 0
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_CURRENT
			ITEMFINDER:
				raw["name"] = "ITEMFINDER"
				raw["pocket"] = Gen2WorldPack.TYPE_KEY_ITEM
				raw["permissions"] = Gen2WorldPack.CANT_TOSS
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_CLOSE
			OLD_ROD:
				raw["name"] = "OLD ROD"
				raw["pocket"] = Gen2WorldPack.TYPE_KEY_ITEM
				raw["permissions"] = Gen2WorldPack.CANT_TOSS
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_CLOSE
			CARD_KEY:
				raw["name"] = "CARD KEY"
				raw["pocket"] = Gen2WorldPack.TYPE_KEY_ITEM
				raw["permissions"] = Gen2WorldPack.CANT_TOSS
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_CLOSE
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
		host.handle_button(Gen2Button.DOWN)
	assert_eq(host.get("_menu").selected_kind(), Gen2WorldStartMenu.ITEM_EXIT)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	assert_true(_world_screen._objects_may_move())


func test_cancel_closes_the_menu_the_same_as_exit() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	host.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	assert_true(_world_screen._objects_may_move())


func test_mod_settings_use_the_hardware_option_screen() -> void:
	var host_api: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host_api.register_option(&"display", {
		"key": &"distance", "label": "Distance", "values": [1, 2],
		"labels": ["Near", "Far"],
	})["ok"]))
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_MODS)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.MODS)
	assert_true((host.get("_view") as TextureRect).visible)
	assert_false((host.get("_center") as Control).visible)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.MOD_OPTIONS)
	assert_true((host.get("_view") as TextureRect).visible)
	assert_false((host.get("_center") as Control).visible)

	Gen2ModHost.reset()


func test_long_mod_list_scrolls_the_hardware_option_screen() -> void:
	var host_api: Gen2ModHost = Gen2ModHost.instance()
	for index: int in 10:
		assert_true(bool(host_api.register_option(StringName("mod_%02d" % index), {
			"key": &"enabled", "label": "ENABLED", "values": [0, 1],
		})["ok"]))
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_MODS)
	host.handle_button(Gen2Button.A)
	for _step: int in 8:
		host.handle_button(Gen2Button.DOWN)
	assert_eq(host.get("_mod_cursor"), 8)
	var rows: Array = []
	for id: StringName in host.get("_mod_ids") as Array[StringName]:
		rows.append({"label": String(id), "value": ""})
	var window: Dictionary = host.call("_option_window", rows, 8)
	assert_eq((window["rows"] as Array).size(), Gen2StartMenuPage.OPTIONS_VISIBLE_ROWS)
	assert_eq((window["rows"] as Array)[7]["label"], "mod_08")
	assert_eq(window["cursor"], 7)
	assert_true((host.get("_view") as TextureRect).visible)

	Gen2ModHost.reset()


func test_long_mod_settings_scroll_and_adjust_the_global_row() -> void:
	var host_api: Gen2ModHost = Gen2ModHost.instance()
	for index: int in 14:
		assert_true(bool(host_api.register_option(&"randomizer", {
			"key": StringName("setting_%02d" % index),
			"label": "SETTING %02d" % index,
			"values": [0, 1], "labels": ["OFF", "ON"],
		})["ok"]))
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_MODS)
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.A)
	for _step: int in 8:
		host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.RIGHT)
	assert_eq(host.get("_mod_option_cursor"), 8)
	assert_eq(host_api.option(&"randomizer", &"setting_08"), 1)
	assert_eq(host_api.option(&"randomizer", &"setting_07"), 0)
	var window: Dictionary = host.call(
		"_option_window", host.call("_mod_options"), 8,
		Gen2StartMenuPage.OPTIONS_VISIBLE_VALUE_ROWS
	)
	assert_eq((window["rows"] as Array).size(), Gen2StartMenuPage.OPTIONS_VISIBLE_VALUE_ROWS)
	assert_eq((window["rows"] as Array)[6]["key"], &"setting_08")
	assert_eq(window["cursor"], 6)
	assert_true((host.get("_view") as TextureRect).visible)

	Gen2ModHost.reset()


func test_pokemon_opens_the_embedded_party_screen_and_reopens_the_menu() -> void:
	await _open_world()
	_world_screen._world.set_party_summary(1, false)
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	assert_true(_kinds(host).has(Gen2WorldStartMenu.ITEM_POKEMON))
	_select(host, Gen2WorldStartMenu.ITEM_POKEMON)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	var party: Gen2PartyScreen = _world_screen._party_host
	assert_not_null(party)

	party.close_embedded()
	await get_tree().process_frame
	assert_null(_world_screen._party_host)
	# `StartMenu_Pokemon`'s `.return` reaches `CloseSubmenu` and returns 0, which
	# `.MenuReturns` sends to `.Reopen`.
	assert_not_null(_world_screen._start_menu_host, "the menu is drawn again")
	_world_screen._start_menu_host.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_true(_world_screen._objects_may_move())


func test_pack_lists_a_granted_item() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_PACK)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	assert_true((host.get("_view") as TextureRect).visible)
	assert_false((host.get("_center") as Control).visible)
	assert_false((host.get("_pack_view") as TextureRect).visible)
	var items_pocket: Dictionary = host.get("_pack_pockets")[0]
	assert_eq(items_pocket["pocket"], Gen2WorldPack.TYPE_ITEM)
	var items: Array = items_pocket["items"]
	assert_eq(items.size(), 1)
	assert_eq(items[0]["item"], 7)
	assert_eq(items[0]["quantity"], 1)

	host.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.LIST)


## MENU ACCOUNT is `.IsMenuAccountOn`, and what it gates is `.MenuDesc`: the
## highlighted entry's own line under the list. It is read on every cursor move,
## so turning it off in OPTION takes the box away without reopening the menu.
func test_menu_account_draws_the_entry_description_and_off_takes_it_away() -> void:
	await _open_world()
	var options: Gen2Options = Gen2OptionsStore.current()
	options.menu_account = true
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	var menu: Gen2WorldStartMenu = host.get("_menu")
	assert_eq(host.get("_status").text, menu.selected_description())
	assert_ne(host.get("_status").text, "")

	host.handle_button(Gen2Button.DOWN)
	assert_eq(host.get("_status").text, menu.selected_description())

	options.menu_account = false
	host.handle_button(Gen2Button.DOWN)
	assert_eq(host.get("_status").text, "", "the box is gone")


## The pack's wording is the cartridge's, read out of the cache rather than
## written here. `Pack_GetItemName` fills the name slot and the dial owns the
## number, so both markers are gone by the time a box is drawn.
func test_the_toss_boxes_read_the_cartridges_own_words() -> void:
	await _open_world()
	_world_screen._world.state.apply_changes({}, {}, {"items": {7: 5}})
	var host: Gen2StartMenuScreen = await _open_pack()
	_choose_action(host, Gen2WorldPack.ACTION_TOSS)
	assert_eq(host.get("_status").text, "Throw away how many?")

	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_summary").text, "Throw away 5 POTION(S)?")

	host.handle_button(Gen2Button.A)
	assert_eq(String(host.get("_pack_result")), "Threw away POTION(S).")
	for marker: String in [Gen2TextStream.RAM_MARKER, Gen2TextStream.NUMBER_MARKER]:
		assert_eq(String(host.get("_pack_result")).find(marker), -1, marker)


## `TossMenu`: the ask, `SelectQuantityToToss`'s dial, a yes/no and `TossItem`.
## The item submenu is already closed by the time it runs, so every way out of it
## lands back on the pocket list.
func test_toss_takes_the_chosen_quantity_and_reports_it() -> void:
	await _open_world()
	_world_screen._world.state.apply_changes({}, {}, {"items": {7: 5}})
	var host: Gen2StartMenuScreen = await _open_pack()
	_choose_action(host, Gen2WorldPack.ACTION_TOSS)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TOSS_QUANTITY)

	## The dial opens on 1 and pages by ten, which cannot pass the stack.
	host.handle_button(Gen2Button.RIGHT)
	assert_eq((host.get("_toss_prompt") as Gen2WorldQuantityPrompt).value, 5)
	host.handle_button(Gen2Button.DOWN)
	assert_eq((host.get("_toss_prompt") as Gen2WorldQuantityPrompt).value, 4)

	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TOSS_CONFIRM)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq(_world_screen._world.state.item_quantity(7), 1)

	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)


## `SelectQuantityToToss`'s `cp -1 / scf` and `YesNoBox`'s no are the same carry
## `TossMenu` finishes on, and neither takes anything.
func test_backing_out_of_either_toss_prompt_takes_nothing() -> void:
	await _open_world()
	_world_screen._world.state.apply_changes({}, {}, {"items": {7: 5}})
	var host: Gen2StartMenuScreen = await _open_pack()

	_choose_action(host, Gen2WorldPack.ACTION_TOSS)
	host.handle_button(Gen2Button.B)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	assert_eq(_world_screen._world.state.item_quantity(7), 5)

	_choose_action(host, Gen2WorldPack.ACTION_TOSS)
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	assert_eq(_world_screen._world.state.item_quantity(7), 5, "NO takes nothing")


## Tossing the last of a stack takes it off the pocket list, which is what the
## pack redraws on the way back.
func test_tossing_the_last_of_a_stack_empties_the_pocket() -> void:
	await _open_world()
	var host: Gen2StartMenuScreen = await _open_pack()
	_choose_action(host, Gen2WorldPack.ACTION_TOSS)
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	assert_eq((host.get("_pack_pockets")[0] as Dictionary)["items"], [])


## `.Field`: `DoItemEffect` runs in the overworld and `PACKSTATE_QUITRUNSCRIPT`
## closes the pack behind it, so the Itemfinder's answer is in the world's own
## text box rather than in the pack's result line. A key item is not consumed.
func test_a_field_item_closes_the_pack_and_answers_in_the_world() -> void:
	await _open_world()
	_world_screen._world.state.apply_changes({}, {}, {"items": {ITEMFINDER: 1}})
	var scripts: Dictionary = RomCache.read_json(
		RomCache.world_scripts_path(Fixture.directory())
	)
	scripts["48:61C0"] = [30, 0, 7, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_world_screen._world.current_map.events["bg_events"] = [
		{"x": 7, "y": 5, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x61C0},
	]
	var host: Gen2StartMenuScreen = await _open_pack(Gen2WorldPack.TYPE_KEY_ITEM)

	_choose_action(host, Gen2WorldPack.ACTION_USE)
	await get_tree().process_frame

	assert_null(_world_screen._start_menu_host, "the pack quit")
	assert_true(_world_screen.get("_field_move_text"))
	assert_eq(_world_screen._world.state.item_quantity(ITEMFINDER), 1)


## `UseRod`: the rod the pack chose is the one `FishFunction` casts, and a cast
## it would refuse is `.FailFish`, which is `.Oak` with the pack still open.
func test_a_rod_casts_from_the_pack_and_is_refused_away_from_water() -> void:
	await _open_world()
	_world_screen._world.state.apply_changes({}, {}, {"items": {OLD_ROD: 1}})

	var away: Gen2StartMenuScreen = await _open_pack(Gen2WorldPack.TYPE_KEY_ITEM)
	_choose_action(away, Gen2WorldPack.ACTION_USE)
	await get_tree().process_frame
	assert_not_null(_world_screen._start_menu_host, "no water in front of the player")
	assert_eq(away.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	away.handle_button(Gen2Button.B)
	await get_tree().process_frame
	_world_screen._start_menu_host.handle_button(Gen2Button.B)
	await get_tree().process_frame

	_world_screen._position_for_fishing_preview()
	var host: Gen2StartMenuScreen = await _open_pack(Gen2WorldPack.TYPE_KEY_ITEM)
	_choose_action(host, Gen2WorldPack.ACTION_USE)
	await get_tree().process_frame

	assert_null(_world_screen._start_menu_host, "the pack quit")
	assert_true(_world_screen._world.fishing_busy())
	assert_eq(
		_world_screen.get("_selected_rod"), Gen2WorldEncounter.METHOD_OLD_ROD
	)


## An ITEMMENU_CLOSE row whose effect this project has no overworld for leaves
## `wItemEffectSucceeded` clear, which is `.Oak` with every other refusal and a
## pack still open behind it.
func test_a_field_item_with_no_effect_stays_in_the_pack_on_oaks_refusal() -> void:
	await _open_world()
	_world_screen._world.state.apply_changes({}, {}, {"items": {CARD_KEY: 1}})
	var host: Gen2StartMenuScreen = await _open_pack(Gen2WorldPack.TYPE_KEY_ITEM)

	_choose_action(host, Gen2WorldPack.ACTION_USE)
	await get_tree().process_frame

	assert_not_null(_world_screen._start_menu_host)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq(
		String(host.get("_pack_result")), host._pack_text(Gen2StartMenuScreen.TEXT_OAK)
	)


## Opens the pack on [param pocket], cursor on its first row, which for the
## default items pocket is the granted POTION.
func _open_pack(pocket: int = Gen2WorldPack.TYPE_ITEM) -> Gen2StartMenuScreen:
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_PACK)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	var guard: int = host.get("_pack_pockets").size()
	while int(host.get("_pack_pockets")[host.get("_pack_pocket_index")]["pocket"]) != pocket \
		and guard > 0:
		host.handle_button(Gen2Button.RIGHT)
		guard -= 1
	return host


## Opens the item submenu and puts the cursor on [param action] before pressing A.
func _choose_action(host: Gen2StartMenuScreen, action: StringName) -> void:
	host.handle_button(Gen2Button.A)
	var actions: Array = host.get("_item_actions")
	for index: int in actions.size():
		if StringName((actions[index] as Dictionary).get("action", &"")) == action:
			host.set("_item_cursor", index)
			break
	host.handle_button(Gen2Button.A)


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
	host.handle_button(Gen2Button.A)
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

	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_ITEM)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TEACH)
	assert_eq(
		String(host.get("_teach_prompt")["text"]),
		"Booted up an HM. It contained STRENGTH. Teach STRENGTH to a #MON?"
	)

	## Yes is the prompt's default cursor position, matching YesNoBox.
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TARGET)

	host.handle_button(Gen2Button.A)
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

	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TEACH)

	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
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

	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	host.handle_button(Gen2Button.A)
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
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	host.handle_button(Gen2Button.A)
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
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_FORGET)
	assert_eq((host.get("_forget_moves") as Array).size(), 4)

	## Slot 2, past the HM, is an ordinary move.
	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
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
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame

	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
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

	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_STOP_LEARNING)
	assert_true(
		String(host.get("_summary").text).begins_with("Stop learning"),
		String(host.get("_summary").text)
	)

	host.handle_button(Gen2Button.A)
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

	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_STOP_LEARNING)

	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
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
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_FORGET)

	host.handle_button(Gen2Button.B)
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
	host.handle_button(Gen2Button.A)
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
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.SAVE_ASK)
	## Yes is YesNoMenuHeader's own default cursor position. The second question
	## is AskOverwriteSaveFile's, which every save here reaches: the slot the
	## world is played from always exists and always carries this player's ID.
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.SAVE_OVERWRITE)
	## `_ContText`'s wait before the text's third line, then its yes.
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.SAVE_SAVING)
	## SavingDontTurnOffThePower's sixteen frames and SavedTheGame's thirty-two
	## are both spent before the words that follow them.
	host.advance_save_frames(
		Gen2StartMenuScreen.SAVE_SAVING_FRAMES
		+ Gen2StartMenuScreen.SAVE_WRITE_FRAMES - 1
	)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.SAVE_SAVING)
	host.advance_save_frames(1)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.SAVE_SAVED)
	assert_eq(save.world.map_id, expected.map_id)
	assert_eq(save.world.player_cell, expected.player_cell)
	assert_true(save.world.world_state.is_event_flag_active(MARKER_FLAG))
	## `StartMenu_Save`'s `ld a, 1`: a save that succeeded leaves the menu.
	var closed: Array = []
	host.closed.connect(func() -> void: closed.append(true))
	host.advance_save_frames(Gen2StartMenuScreen.SAVE_DONE_FRAMES)
	assert_eq(closed.size(), 1)


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
	var before_scripted_move: Vector2i = _world_screen._world.player_cell
	assert_false(_world_screen.move_player(Vector2i.RIGHT))
	assert_eq(_world_screen._world.player_cell, before_scripted_move)


func _kinds(host: Gen2StartMenuScreen) -> Array:
	var out: Array = []
	for entry: Dictionary in (host.get("_menu") as Gen2WorldStartMenu).items():
		out.append(entry.get("kind"))
	return out


func _select(host: Gen2StartMenuScreen, kind: StringName) -> void:
	var menu: Gen2WorldStartMenu = host.get("_menu")
	var guard: int = menu.size() + 1
	while menu.selected_kind() != kind and guard > 0:
		host.handle_button(Gen2Button.DOWN)
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
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	return host


func test_choosing_an_item_opens_the_source_submenu() -> void:
	var host: Gen2StartMenuScreen = await _open_pack_with_a_hurt_party()
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_ITEM)
	var labels: Array = []
	for entry: Dictionary in host.get("_item_actions"):
		labels.append(String(entry.get("label", "")))
	assert_eq(labels, ["USE", "GIVE", "TOSS", "QUIT"])

	# QUIT returns to the pocket list, keeping the cursor the source restores.
	while StringName((host.get("_item_actions")[host.get("_item_cursor")] as Dictionary)
		.get("action", &"")) != Gen2WorldPack.ACTION_QUIT:
		host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)


func test_use_on_a_party_item_asks_which_mon_then_heals_and_spends_it() -> void:
	var host: Gen2StartMenuScreen = await _open_pack_with_a_hurt_party()
	var save: Gen2SaveData = _world_screen.get("_injected_save")
	var before: int = (save.party[0] as Gen2SaveMon).hp
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TARGET)
	# Nothing has changed until the target is chosen.
	assert_eq((save.party[0] as Gen2SaveMon).hp, before)
	assert_eq(_world_screen._world.state.item_quantity(7), 1)

	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq((save.party[0] as Gen2SaveMon).hp, before + 15)
	assert_eq(_world_screen._world.state.item_quantity(7), 0)
	assert_eq(String(host.get("_pack_result")), "POTION restored 15 HP.")

	# The spent item leaves the pocket on the way back.
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	assert_eq(((host.get("_pack_pockets")[0] as Dictionary)["items"] as Array).size(), 0)


func test_using_an_item_with_nothing_to_do_reports_it_and_spends_nothing() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_PACK)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.A)
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
	host.handle_button(Gen2Button.A)
	# CANT_TOSS with CANT_SELECT clear is MenuHeader_UnusableKeyItem: USE stays.
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq(String(host.get("_pack_result")), host._pack_text(
		Gen2StartMenuScreen.TEXT_OAK
	))
	assert_string_contains(String(host.get("_pack_result")), "isn't the")
	assert_eq(_world_screen._world.state.item_quantity(7), 1)


## StartMenu_Option's farcall Option, as a mode on this screen.
func _open_options_menu() -> Gen2StartMenuScreen:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_OPTION)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.OPTIONS)
	return host


func test_option_is_available_and_opens_the_option_menu() -> void:
	var host: Gen2StartMenuScreen = await _open_options_menu()
	var menu: Gen2WorldOptionsMenu = host.get("_options_menu")
	assert_eq(menu.size(), Gen2WorldOptionsMenu.NUM_OPTIONS)
	assert_eq(menu.cursor, Gen2WorldOptionsMenu.OPT_TEXT_SPEED)


func test_a_change_reaches_the_shared_options_and_the_file() -> void:
	var host: Gen2StartMenuScreen = await _open_options_menu()
	var menu: Gen2WorldOptionsMenu = host.get("_options_menu")
	menu.cursor = Gen2WorldOptionsMenu.OPT_BATTLE_STYLE
	assert_false(Gen2OptionsStore.current().battle_style_set)
	host.handle_button(Gen2Button.RIGHT)
	assert_true(Gen2OptionsStore.current().battle_style_set)

	Gen2OptionsStore.use_test_path()
	assert_true(Gen2OptionsStore.current().battle_style_set)


## Every other handler reads left and right alone, so A on a value row does
## nothing and the menu stays open.
func test_a_on_a_value_row_changes_nothing_and_cancel_returns_to_the_list() -> void:
	var host: Gen2StartMenuScreen = await _open_options_menu()
	var menu: Gen2WorldOptionsMenu = host.get("_options_menu")
	menu.cursor = Gen2WorldOptionsMenu.OPT_SOUND
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.OPTIONS)
	assert_false(Gen2OptionsStore.current().stereo)

	menu.cursor = Gen2WorldOptionsMenu.OPT_CANCEL
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.LIST)


## _Option.joypad_loop exits on PAD_B from any row.
func test_b_returns_to_the_list_from_a_value_row() -> void:
	var host: Gen2StartMenuScreen = await _open_options_menu()
	(host.get("_options_menu") as Gen2WorldOptionsMenu).cursor = Gen2WorldOptionsMenu.OPT_FRAME
	host.handle_button(Gen2Button.B)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.LIST)
	assert_not_null(_world_screen._start_menu_host)


## `StartMenu_Status`'s `farcall TrainerCard`, as an overlay the world screen
## owns the way it owns the party screen.
func test_player_opens_the_trainer_card_and_b_reopens_the_start_menu() -> void:
	await _open_world()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_PLAYER)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	var card: Gen2TrainerCardScreen = _world_screen._trainer_card_host
	assert_not_null(card)
	assert_eq(card.current_page(), Gen2TrainerCard.PAGE_1)
	assert_false(_world_screen.move_player(Vector2i.RIGHT), "the card blocks the overworld")

	## Right reaches the badge page, and B leaves from there.
	card.handle_button(Gen2Button.RIGHT)
	assert_eq(card.current_page(), Gen2TrainerCard.PAGE_2)
	card.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_null(_world_screen._trainer_card_host)
	# `StartMenu_Status` returns 0, which `.MenuReturns` sends to `.Reopen`.
	assert_not_null(_world_screen._start_menu_host, "the menu is drawn again")
	_world_screen._start_menu_host.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_true(_world_screen._objects_may_move(), "and its own B is the way out")


## The play timer is the save's, and it counts hardware frames of the world
## running rather than host seconds.
func test_the_play_timer_counts_while_the_world_runs() -> void:
	await _open_world()
	## The fixture drives an injected save, which is the one the timer counts on
	## too: the pump prefers it exactly as the card does.
	var save: Gen2SaveData = _world_screen._injected_save
	assert_not_null(save)
	save.game_time = Gen2GameTime.new()
	_world_screen.advance_frames(3)
	assert_eq(save.game_time.frames, 3)


## `StartMenu_Pokedex`'s `farcall Pokedex`, as an overlay the world screen owns
## the way it owns the trainer card.
func test_pokedex_opens_from_the_start_menu_and_b_reopens_the_start_menu() -> void:
	await _open_world()
	_world_screen._world.state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEDEX)
	_world_screen._world.state.set_species_seen(Fixture.TRAINER_SPECIES)
	_world_screen._open_start_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	_select(host, Gen2WorldStartMenu.ITEM_POKEDEX)
	host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)
	var dex: Gen2PokedexScreen = _world_screen._pokedex_host
	assert_not_null(dex)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.LIST)
	assert_false(_world_screen.move_player(Vector2i.RIGHT), "the dex blocks the overworld")

	## SELECT reaches the OPTION screen, and B comes back to the listing.
	dex.handle_button(Gen2Button.SELECT)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.OPTION)
	dex.handle_button(Gen2Button.B)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.LIST)

	dex.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_null(_world_screen._pokedex_host)
	# `StartMenu_Pokedex` returns 0 too.
	assert_not_null(_world_screen._start_menu_host, "the menu is drawn again")
	_world_screen._start_menu_host.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_true(_world_screen._objects_may_move())


## The entry screen's AREA, which is `Pokedex_GetArea` rather than a panel: it
## opens the cartridge's own region map over the dex and A or B hands the entry
## back. The world screen carries the release the map's SELECT reads.
func test_the_dex_entry_screens_area_button_opens_the_region_map() -> void:
	await _open_world()
	var state: Gen2WorldState = _world_screen._world.state
	state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEDEX)
	state.set_species_seen(Fixture.TRAINER_SPECIES)
	_world_screen._open_pokedex()
	var dex: Gen2PokedexScreen = _world_screen._pokedex_host
	## Only a seen species opens an entry, and the fixture has one.
	for _row: int in RomLayout.SPECIES_COUNT:
		if dex.get("_dex").selected_species() == Fixture.TRAINER_SPECIES:
			break
		dex.handle_button(Gen2Button.DOWN)
	dex.handle_button(Gen2Button.A)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.ENTRY)

	## `DexEntryScreen_ArrowCursorData`'s second position.
	dex.handle_button(Gen2Button.RIGHT)
	dex.handle_button(Gen2Button.A)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.AREA)
	var area: Gen2TownMapScreen = dex.get("_area")
	assert_eq(area.current_nests(), [Fixture.MAP_LANDMARK], "the fixture's one grass map")

	_world_screen.press_button(Gen2Button.SELECT)
	assert_eq(area.shadow_oam(), Gen2TownMapScreen.OAM_PLAYER)
	## The release is not a redraw: `.BlinkNestIcons` writes shadow OAM on every
	## sixteenth frame and the player icon stands until it does.
	dex.release_button(Gen2Button.SELECT)
	for _frame: int in Gen2TownMapScreen.NEST_BLINK_FRAMES:
		if area.shadow_oam() != Gen2TownMapScreen.OAM_PLAYER:
			break
		area.advance_frame()
	assert_ne(area.shadow_oam(), Gen2TownMapScreen.OAM_PLAYER)

	_world_screen.press_button(Gen2Button.B)
	await get_tree().process_frame
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.ENTRY)
	assert_not_null(_world_screen._pokedex_host, "the dex is still up behind it")


## A mode chosen on the OPTION screen is written back to wLastDexMode, which is
## saved player data, so the next opening starts there.
func test_the_chosen_dex_mode_survives_closing_the_dex() -> void:
	await _open_world()
	var state: Gen2WorldState = _world_screen._world.state
	state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEDEX)
	_world_screen._open_pokedex()
	var dex: Gen2PokedexScreen = _world_screen._pokedex_host
	assert_not_null(dex)
	dex.handle_button(Gen2Button.SELECT)
	dex.handle_button(Gen2Button.DOWN)
	dex.handle_button(Gen2Button.A)
	assert_eq(state.last_dex_mode(), RomLayout.DEXMODE_OLD)
	dex.handle_button(Gen2Button.B)
	await get_tree().process_frame

	_world_screen._open_pokedex()
	var reopened: Gen2PokedexScreen = _world_screen._pokedex_host
	assert_eq(reopened.get("_dex").mode, RomLayout.DEXMODE_OLD)


## The Unown dex: `Pokedex_CheckUnlockedUnownMode` puts a fourth row on the
## OPTION screen once the Ruins of Alph research centre has set the flag, and
## `.MenuAction_UnownMode` answers back to OPTION rather than to the listing,
## with the listing's own mode untouched.
func test_unown_mode_is_offered_once_its_flag_is_set_and_returns_to_the_option_screen() -> void:
	await _open_world()
	var state: Gen2WorldState = _world_screen._world.state
	state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEDEX)
	_world_screen._open_pokedex()
	var dex: Gen2PokedexScreen = _world_screen._pokedex_host
	dex.handle_button(Gen2Button.SELECT)
	assert_eq(dex.get("_mode_rows").size(), 3, "three modes until the dex is upgraded")

	state.set_engine_flag(Gen2WorldState.ENGINE_UNOWN_DEX)
	state.update_unown_dex(3)
	state.update_unown_dex(20)
	dex.handle_button(Gen2Button.B)
	dex.handle_button(Gen2Button.SELECT)
	assert_eq(dex.get("_mode_rows").size(), 4)
	for _row: int in 3:
		dex.handle_button(Gen2Button.DOWN)
	dex.handle_button(Gen2Button.A)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.UNOWN)
	assert_eq(dex.get("_dex").unown_word(), "CWORD")
	dex.handle_button(Gen2Button.RIGHT)
	assert_eq(dex.get("_dex").unown_word(), "TWORD")

	dex.handle_button(Gen2Button.A)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.OPTION)
	assert_eq(
		state.last_dex_mode(), RomLayout.DEXMODE_NEW,
		"the listing keeps the mode it had"
	)


## `Pokedex_UpdateMainScreen`'s START reaches the search screen, and its CANCEL
## row comes back to the listing.
func test_the_dex_search_screen_opens_from_the_listing_and_cancels_back() -> void:
	await _open_world()
	var state: Gen2WorldState = _world_screen._world.state
	state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEDEX)
	_world_screen._open_pokedex()
	var dex: Gen2PokedexScreen = _world_screen._pokedex_host
	assert_not_null(dex)

	dex.handle_button(Gen2Button.START)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.SEARCH)

	## Down twice reaches BEGIN SEARCH and once more CANCEL, which leaves.
	dex.handle_button(Gen2Button.DOWN)
	dex.handle_button(Gen2Button.DOWN)
	dex.handle_button(Gen2Button.DOWN)
	dex.handle_button(Gen2Button.A)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.LIST)
	assert_eq(dex.get("_dex").listing_height, Gen2Pokedex.LISTING_HEIGHT)


## A search with a caught species behind it reaches the results screen, and B
## returns through the search screen with the main listing put back.
func test_a_dex_search_reaches_its_results_and_back() -> void:
	await _open_world()
	var state: Gen2WorldState = _world_screen._world.state
	state.set_engine_flag(Gen2WorldStartMenu.ENGINE_POKEDEX)
	state.set_species_caught(Fixture.TRAINER_SPECIES)
	_world_screen._open_pokedex()
	var dex: Gen2PokedexScreen = _world_screen._pokedex_host
	var model: Gen2Pokedex = dex.get("_dex")

	dex.handle_button(Gen2Button.START)
	## The fixture's species are all NORMAL, which is the row the screen opens on.
	dex.handle_button(Gen2Button.DOWN)
	dex.handle_button(Gen2Button.DOWN)
	dex.handle_button(Gen2Button.A)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.SEARCH_RESULTS)
	assert_eq(model.search_result_count, 1)
	assert_eq(model.listing_height, Gen2Pokedex.SEARCH_RESULTS_HEIGHT)
	assert_eq(model.selected_species(), Fixture.TRAINER_SPECIES)

	dex.handle_button(Gen2Button.B)
	assert_eq(dex.current_mode(), Gen2PokedexScreen.Mode.SEARCH)
	assert_eq(model.search_type_1, 1, "the search screen re-initialises its rows")


## `GiveItem`: the party list, then `TryGiveItemToPartymon`'s
## `.give_item_to_mon`. The item leaves the bag on the same press.
func test_give_hands_the_item_to_the_chosen_party_member() -> void:
	await _open_world()
	var host: Gen2StartMenuScreen = await _open_pack()
	_choose_action(host, Gen2WorldPack.ACTION_GIVE)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_TARGET)
	assert_eq(host.get("_title").text, "GIVE TO")

	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	var save: Gen2SaveData = _world_screen._injected_save
	assert_eq((save.party[0] as Gen2SaveMon).item, 7)
	assert_eq(_world_screen._world.state.item_quantity(7), 0)
	assert_eq(
		String(host.get("_pack_result")),
		Gen2WorldPack.hold_text(_first_member_name(save), "POTION")
	)


## `PokemonAskSwapItemText` and its yes/no. `.abort` is the no, and it leaves
## both items where they were.
func test_a_full_hand_asks_before_the_swap_and_no_takes_nothing() -> void:
	await _open_world()
	_world_screen._world.state.apply_changes({}, {}, {"items": {7: 1, REPEL: 1}})
	var save: Gen2SaveData = _world_screen._injected_save
	(save.party[0] as Gen2SaveMon).item = REPEL
	var host: Gen2StartMenuScreen = await _open_pack()
	_choose_action(host, Gen2WorldPack.ACTION_GIVE)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_GIVE_SWAP)
	assert_eq(
		host.get("_summary").text,
		Gen2WorldPack.ask_swap_text(_first_member_name(save), "REPEL")
	)

	host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK)
	assert_eq((save.party[0] as Gen2SaveMon).item, REPEL)
	assert_eq(_world_screen._world.state.item_quantity(7), 1)

	_choose_action(host, Gen2WorldPack.ACTION_GIVE)
	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.A)
	assert_eq((save.party[0] as Gen2SaveMon).item, 7)
	assert_eq(_world_screen._world.state.item_quantity(REPEL), 2, "the old one came back")


## The party submenu's ITEM: `GiveTakeItemMenuData`'s two rows, TAKE running
## `TakePartyItem` against the live world and saying so in the map's own box.
func test_the_party_submenu_takes_a_held_item_back() -> void:
	await _open_world()
	var save: Gen2SaveData = _world_screen._injected_save
	(save.party[0] as Gen2SaveMon).item = 7
	_world_screen._open_embedded_party()
	await get_tree().process_frame
	var party: Gen2PartyScreen = _world_screen._party_host
	party.handle_button(Gen2Button.A)
	var items: Array = (party.submenu_snapshot()["items"] as Array)
	for index: int in items.size():
		if StringName((items[index] as Dictionary).get("option", &"")) \
			== Gen2PartyScreen.OPTION_ITEM:
			party.set("_submenu_cursor", index)
			break
	party.handle_button(Gen2Button.A)
	assert_true(bool(party.submenu_snapshot()["item_menu"]))

	party.handle_button(Gen2Button.DOWN)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_null(_world_screen._party_host)
	assert_eq((save.party[0] as Gen2SaveMon).item, 0)
	assert_eq(_world_screen._world.state.item_quantity(7), 2)


## `SwitchPartyMons`: the row is held, the list comes back with `▷` on it and no
## CANCEL, and `_SwitchPartyMons` trades the two members whole.
func test_the_party_submenu_switch_row_moves_a_member() -> void:
	await _open_world()
	var save: Gen2SaveData = _world_screen._injected_save
	var first: Gen2SaveMon = save.party[0]
	var second: Gen2SaveMon = save.party[1]
	var played: Array[int] = []
	_world_screen._open_embedded_party()
	await get_tree().process_frame
	var party: Gen2PartyScreen = _world_screen._party_host
	party.sfx_requested.connect(func(index: int) -> void: played.append(index))
	_choose_submenu(party, Gen2PartyScreen.OPTION_SWITCH)

	var snapshot: Dictionary = party.submenu_snapshot()
	assert_eq(int(snapshot["switch_from"]), 0, "the first row is being moved")
	assert_false(bool(snapshot["open"]), "and the submenu is gone")
	assert_eq(party._prompt(), Gen2PartyScreen.PROMPT_MOVE_TO_WHERE)
	assert_eq(party._row_count(), 2, "InitPartyMenuNoCancel has no CANCEL row")

	party.handle_button(Gen2Button.DOWN)
	party.handle_button(Gen2Button.A)
	assert_same(save.party[0], second, "the two traded places")
	assert_same(save.party[1], first)
	assert_eq(played, [Gen2PartyScreen.SFX_SWITCH_POKEMON])
	assert_eq(int(party.submenu_snapshot()["switch_from"]), -1)
	assert_eq(party._row_count(), 3, "and CANCEL is back")


## `.DontSwitch`, both ways into it: a party of one never leaves the submenu, and
## B over the list is `CancelPokemonAction`.
func test_switch_refuses_a_party_of_one_and_b_gives_the_move_up() -> void:
	await _open_world()
	var save: Gen2SaveData = _world_screen._injected_save
	var first: Gen2SaveMon = save.party[0]
	var second: Gen2SaveMon = save.party[1]
	_world_screen._open_embedded_party()
	await get_tree().process_frame
	var party: Gen2PartyScreen = _world_screen._party_host

	_choose_submenu(party, Gen2PartyScreen.OPTION_SWITCH)
	party.handle_button(Gen2Button.DOWN)
	party.handle_button(Gen2Button.B)
	assert_eq(int(party.submenu_snapshot()["switch_from"]), -1)
	assert_false(bool(party.submenu_snapshot()["open"]), "CancelPokemonAction")
	assert_same(save.party[0], first, "and nothing moved")
	assert_same(save.party[1], second)

	save.party.remove_at(1)
	party.set_context(_data, save, true)
	_choose_submenu(party, Gen2PartyScreen.OPTION_SWITCH)
	assert_eq(int(party.submenu_snapshot()["switch_from"]), -1, "cp 2 refused it")
	assert_false(bool(party.submenu_snapshot()["open"]))


## Opens the mon's submenu and puts the cursor on one of its option rows.
func _choose_submenu(party: Gen2PartyScreen, option: StringName) -> void:
	party.handle_button(Gen2Button.A)
	var items: Array = (party.submenu_snapshot()["items"] as Array)
	for index: int in items.size():
		if StringName((items[index] as Dictionary).get("option", &"")) == option:
			party.set("_submenu_cursor", index)
			break
	party.handle_button(Gen2Button.A)


## `SelectMenu`: `CheckRegisteredItem` answers first, and `MayRegisterItemText`
## is the whole of what an unregistered SELECT does.
func test_select_says_an_item_may_be_registered_when_none_is() -> void:
	await _open_world()
	_world_screen.open_select_menu()
	await get_tree().process_frame
	var host: Gen2StartMenuScreen = _world_screen._start_menu_host
	assert_eq(host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq(String(host.get("_pack_result")), Gen2WorldPack.may_register_text())


## `RegisterItem` and `UseRegisteredItem`'s `.Current`, which is the whole
## journey a registered REPEL makes from the pack to the SELECT button.
func test_a_registered_item_is_used_by_the_select_button() -> void:
	await _open_world()
	_world_screen._world.state.apply_changes({}, {}, {"items": {REPEL: 1}})
	var host: Gen2StartMenuScreen = await _open_pack()
	host.set("_pack_cursor", 1)
	_choose_action(host, Gen2WorldPack.ACTION_SELECT)
	assert_eq(String(host.get("_pack_result")), Gen2WorldPack.registered_text("REPEL"))
	assert_eq(_world_screen._world.state.registered_item(), REPEL)

	host.handle_button(Gen2Button.A)
	host.handle_button(Gen2Button.B)
	host.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_null(_world_screen._start_menu_host)

	assert_true(_world_screen.press_button(Gen2Button.SELECT))
	await get_tree().process_frame
	var select_host: Gen2StartMenuScreen = _world_screen._start_menu_host
	assert_eq(select_host.get("_mode"), Gen2StartMenuScreen.Mode.PACK_RESULT)
	assert_eq(_world_screen._world.state.repel_steps(), 100)
	assert_eq(_world_screen._world.state.item_quantity(REPEL), 0)
	assert_eq(
		_world_screen._world.state.registered_item(), REPEL,
		"the registration is only cleared where the check looks"
	)


## What the party list shows for the first member: `GetCurNickname`, which falls
## back to the species name the fixture gave it.
func _first_member_name(save: Gen2SaveData) -> String:
	var mon: Gen2SaveMon = save.party[0]
	if not mon.nickname.is_empty():
		return mon.nickname
	return String(_data.species(mon.species).get("name", ""))
