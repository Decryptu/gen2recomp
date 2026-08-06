extends GutTest

## Scene-level integration for the overworld trainer vertical slice. The cache
## is synthetic, but the scene, world API, script runner, battle adapter and
## battle overlay are the production paths.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")
const BattleFixture := preload("res://tests/unit/battle_fixture.gd")

const STORY_CALLBACK: int = 0x6200
const STORY_OBJECT: int = 0x6210
const STORY_TEXT: int = 0x7200
const STORY_EVENT_FLAG: int = 8

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	_data = Fixture.build()
	_add_capture_metadata()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


func _open_world(with_save: bool = false) -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(4, 5)
	_world_screen.set_data(_data)
	if with_save:
		var player: Gen2BattleMon = Gen2BattleMon.create(
			_data, Fixture.TRAINER_SPECIES, 5, [BattleFixture.TACKLE]
		)
		var save: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
			_data.id, _data.sha1, 0, Gen2Party.of(player), "TEST"
		)
		var snapshot := Gen2WorldSnapshot.new()
		snapshot.map_id = Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER)
		snapshot.player_cell = Vector2i(4, 5)
		snapshot.world_state = Gen2WorldState.new()
		save.world = snapshot
		_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame


func _trigger_trainer() -> void:
	assert_true(_world_screen.move_player(Vector2i.RIGHT))
	await get_tree().process_frame
	await get_tree().process_frame


func _battle_host() -> Gen2BattleScreen:
	for child: Node in _world_screen.get_children():
		if child is Gen2BattleScreen:
			return child as Gen2BattleScreen
	return null


func test_trainer_sight_reaches_the_real_battle_overlay() -> void:
	await _open_world()
	var before: Dictionary = _world_screen.world_snapshot()
	await _trigger_trainer()

	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	assert_eq(before["map"], Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER))
	assert_eq(before["player_cell"], Vector2i(4, 5))
	assert_eq(_world_screen.world_snapshot()["player_cell"], Vector2i(5, 5))
	assert_true(host.is_ready())
	var snapshot: Dictionary = host.battle_snapshot()
	assert_eq(snapshot["enemy"], Fixture.TRAINER_SPECIES)
	assert_eq(snapshot["message"], "LEADER RIVAL wants to fight!")
	assert_eq(snapshot["world_battle_active"], true)


func test_victory_displays_imported_text_reloads_objects_and_keeps_player_cell() -> void:
	await _open_world()
	await _trigger_trainer()
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)

	for _hit: int in 12:
		host.hurt_enemy()
	host.finish()
	host.advance()
	var result_text: Dictionary = host.battle_snapshot()
	assert_eq(result_text["message"], "YOU WON.")

	host.finish()
	host.advance()
	await get_tree().process_frame
	var world: Dictionary = _world_screen.world_snapshot()
	assert_eq(world["map"], Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER))
	assert_eq(world["player_cell"], Vector2i(5, 5))
	assert_eq(world["visible_objects"], 0)
	assert_true(world["just_battled"])


func test_defeat_displays_imported_loss_text_and_uses_save_recovery() -> void:
	await _open_world(true)
	await _trigger_trainer()
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)

	for _hit: int in 12:
		host.hurt_player()
	for member: Gen2BattleMon in host._battle.party(Gen2Battle.PLAYER).mons:
		member.hp = 0
	host.finish()
	host.advance()
	assert_eq(host.battle_snapshot()["message"], "YOU LOST.")

	host.finish()
	host.advance()
	assert_eq(host.battle_snapshot()["message"], "Blackout! Party restored.")

	host.finish()
	host.advance()
	await get_tree().process_frame
	var world: Dictionary = _world_screen.world_snapshot()
	assert_eq(world["player_cell"], Vector2i(5, 5))
	assert_eq(world["visible_objects"], 1)
	assert_false(world["just_battled"])


func test_emote_preview_reaches_the_production_world_renderer() -> void:
	await _open_world()
	_world_screen.preview_emote()
	await get_tree().process_frame

	assert_eq(_world_screen.world_snapshot()["script_prompt"], "Debug emote preview")
	assert_true((_world_screen._world.objects[0] as Gen2WorldObject).emote_visible)


func test_production_world_entry_and_facing_object_story_persist_separate_flags() -> void:
	_install_story_slice()
	await _open_world()
	assert_eq(_world_screen._world.state.map_scene(Fixture.MAP_GROUP, Fixture.MAP_NUMBER), 2)

	_world_screen._world.player_cell = Vector2i(4, 3)
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_RIGHT
	assert_true(_world_screen.interact())
	assert_eq(_world_screen._world.pending_script_input()["type"], &"text")
	assert_false(_world_screen._world.event_flag_active(STORY_EVENT_FLAG))
	assert_false(_world_screen._world.state.hall_of_fame())

	_world_screen._advance_script_input()
	assert_true(_world_screen._world.event_flag_active(STORY_EVENT_FLAG))
	assert_true(_world_screen._world.state.hall_of_fame())
	assert_eq(_world_screen.world_snapshot()["visible_objects"], 0)

	var snapshot: Gen2WorldSnapshot = _world_screen.world_save_snapshot()
	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(_data, snapshot)
	assert_not_null(restored)
	assert_eq(restored.state.map_scene(Fixture.MAP_GROUP, Fixture.MAP_NUMBER), 2)
	assert_true(restored.event_flag_active(STORY_EVENT_FLAG))
	assert_true(restored.state.hall_of_fame())
	assert_eq(restored.visible_objects().size(), 0)


func test_resolved_wild_encounter_reaches_the_real_battle_overlay() -> void:
	await _open_world()
	_world_screen.preview_wild_encounter()
	await get_tree().process_frame
	await get_tree().process_frame

	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	assert_true(host.is_ready())
	assert_eq(host.battle_snapshot()["enemy"], Fixture.TRAINER_SPECIES)
	assert_eq(host.battle_snapshot()["message"], "Wild FILLER appeared!")


func test_fishing_reaches_the_real_battle_overlay() -> void:
	await _open_world()
	_world_screen.start_cell = Vector2i(8, 6)
	_world_screen._world.player_cell = Vector2i(8, 6)
	var started: Dictionary = _world_screen.start_fishing(true)
	assert_true(started["ok"])
	assert_eq(_world_screen._world.advance_fishing()["kind"], &"fishing_bite")
	var battle: Dictionary = _world_screen._world.advance_fishing()
	assert_eq(battle["kind"], &"battle_requested")
	_world_screen._handle_fishing_result(battle)
	await get_tree().process_frame
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	assert_eq(host.battle_snapshot()["enemy"], Fixture.TRAINER_SPECIES)


func test_master_ball_capture_runs_through_the_real_battle_overlay() -> void:
	await _open_world()
	var added: Dictionary = _world_screen._world.state.apply_changes(
		{}, {}, {"items": {Gen2WorldPartyHost.ITEM_MASTER_BALL: 1}}
	)
	assert_true(added["ok"])
	assert_eq(_world_screen._world.state.items(), {
		Gen2WorldInventory.ITEM_OLD_ROD: 1,
		Gen2WorldPartyHost.ITEM_POKE_BALL: 1,
		Gen2WorldPartyHost.ITEM_MASTER_BALL: 1,
	})
	_world_screen.preview_wild_encounter()
	await get_tree().process_frame
	await get_tree().process_frame

	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	assert_eq(host.battle_snapshot()["capture_balls"], [
		Gen2WorldPartyHost.ITEM_POKE_BALL, Gen2WorldPartyHost.ITEM_MASTER_BALL,
	])
	assert_true(host.begin_capture()["ok"])
	assert_true(host.select_capture_ball(1)["ok"])
	assert_true(host.throw_capture_ball()["ok"])
	assert_eq(
		host.battle_snapshot()["message"],
		"You threw a %s!" % _data.item_name(Gen2WorldPartyHost.ITEM_MASTER_BALL)
	)

	for _message: int in 4:
		host.finish()
		host.advance()

	assert_eq(host.battle_snapshot()["message"], "Gotcha! FILLER was caught!")
	host.finish()
	host.advance()
	await get_tree().process_frame
	assert_null(_battle_host())
	assert_eq(_world_screen._world.state.item_quantity(Gen2WorldPartyHost.ITEM_MASTER_BALL), 0)
	assert_eq(_world_screen.world_snapshot()["script_prompt"], "Caught FILLER")


func test_failed_capture_shows_break_free_and_returns_to_battle() -> void:
	await _open_world()
	_data.species(Fixture.TRAINER_SPECIES)["catch_rate"] = 1
	_world_screen._encounter_random.seed = 1
	_world_screen.preview_wild_encounter()
	await get_tree().process_frame
	await get_tree().process_frame

	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	assert_true(host.begin_capture()["ok"])
	assert_true(host.throw_capture_ball()["ok"])
	assert_eq(
		host.battle_snapshot()["message"],
		"You threw a %s!" % _data.item_name(Gen2WorldPartyHost.ITEM_POKE_BALL)
	)

	var saw_break_free: bool = false
	for _message: int in 5:
		host.finish()
		host.advance()
		if host.battle_snapshot()["message"] == "FILLER broke free!":
			saw_break_free = true

	assert_true(saw_break_free)
	assert_not_null(_battle_host())
	assert_eq(_world_screen._world.state.item_quantity(Gen2WorldPartyHost.ITEM_POKE_BALL), 0)
	assert_false(host.battle_snapshot()["capture_waiting"])


func test_project_save_can_carry_the_world_snapshot_without_guessing_a_spawn() -> void:
	await _open_world()
	var player: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.TRAINER_SPECIES, 5, [BattleFixture.TACKLE]
	)
	var save: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, 0, Gen2Party.of(player), "TEST"
	)
	save.world = _world_screen.world_save_snapshot()
	var validation: Dictionary = Gen2SaveValidator.validate(save, _data)
	assert_true(validation["ok"], validation["message"])
	var round_trip: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	assert_not_null(round_trip.world)
	assert_eq(round_trip.world.map_id, Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER))
	assert_eq(round_trip.world.player_cell, Vector2i(4, 5))


func test_party_heal_special_restores_save_hp_status_and_move_pp() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	var heal_script: int = 0x6300
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, heal_script)] = [
		Gen2WorldScript.SPECIAL, 27, 0, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_data = GameData.open_directory(Fixture.directory())
	await _open_world(true)

	var save: Gen2SaveData = _world_screen._injected_save
	var mon: Gen2SaveMon = save.party[0]
	var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, mon)
	mon.hp = 1
	mon.status = Gen2Status.POISON
	mon.pp[0] = 0
	_world_screen._world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 4, "y": 5, "script": heal_script,
	}]

	var waiting: Array = _world_screen._world.dispatch_script_events(Vector2i(4, 5))
	assert_eq(waiting[0]["status"], &"waiting", JSON.stringify(waiting))
	assert_eq(_world_screen._world.pending_runtime_request()["kind"], &"party_heal_requested")
	var complete: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world_screen._world, {}, save, false
	)
	assert_true(complete["ok"], JSON.stringify(complete))
	var healed_mon: Gen2SaveMon = save.party[0]
	assert_eq(healed_mon.hp, battle_mon.max_hp())
	assert_eq(healed_mon.status, Gen2Status.NONE)
	assert_eq(healed_mon.pp[0], int(_data.move(BattleFixture.TACKLE).get("pp", 0)))


func test_new_game_uses_the_verified_home_spawn_and_source_start_money() -> void:
	var save: Gen2SaveData = Gen2SaveStore.create_new_game(_data, 0, "TEST", 155)
	assert_not_null(save)
	assert_not_null(save.world)
	assert_eq(save.world.map_id, Vector2i(Gen2WorldSpawn.NEW_BARK_GROUP, Gen2WorldSpawn.PLAYERS_HOUSE_2F))
	assert_eq(save.world.player_cell, Gen2WorldSpawn.HOME_CELL)
	assert_eq(save.world.world_state.money(), Gen2WorldSpawn.START_MONEY)
	var validation: Dictionary = Gen2SaveValidator.validate(save, _data)
	assert_true(validation["ok"], validation["message"])


func _add_capture_metadata() -> void:
	var species: Array = RomCache.read_json(RomCache.species_path(Fixture.directory()))
	for raw: Dictionary in species:
		if int(raw["number"]) == Fixture.TRAINER_SPECIES:
			raw["catch_rate"] = 190
	RomCache.write_json(RomCache.species_path(Fixture.directory()), species)
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		if int(raw["number"]) in Gen2WorldPartyHost.capture_ball_items():
			raw["pocket"] = RomLayout.ITEM_POCKET_BALL
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)


func _install_story_slice() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, STORY_CALLBACK)] = [
		Gen2WorldScript.SETSCENE, 2, Gen2WorldScript.END,
	]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, STORY_OBJECT)] = [
		Gen2WorldScript.WRITETEXT, STORY_TEXT & 0xFF, STORY_TEXT >> 8,
		Gen2WorldScript.SETEVENT, STORY_EVENT_FLAG, 0,
		Gen2WorldScript.SETFLAG, Gen2WorldState.ENGINE_HALL_OF_FAME, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	RomCache.write_json(RomCache.world_text_path(Fixture.directory()), {
		Gen2WorldScript.pointer_key(Fixture.BANK, STORY_TEXT): [
			Gen2WorldScript.TEXT_START, 0x41, 0x42, Gen2WorldScript.TEXT_TERMINATOR,
		],
	})
	_data = GameData.open_directory(Fixture.directory())
	var map: Gen2WorldMap = _data.world_map(Fixture.MAP_GROUP, Fixture.MAP_NUMBER)
	map.scripts["callbacks"] = [{"type": 3, "script": STORY_CALLBACK}]
	var object: Dictionary = map.events["objects"][0]
	object["object_type"] = Gen2WorldObject.OBJECTTYPE_SCRIPT
	object["script"] = STORY_OBJECT
	object["event_flag"] = STORY_EVENT_FLAG
