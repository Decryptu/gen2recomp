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
	RomCache.clear(Fixture.directory(&"gold"))


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


## One cell, however many presses the cartridge needs for it. The player spawns
## facing down, so a press in any other direction is `.CheckTurning`'s turn on the
## spot first and the walk is the press after it; a press in the direction already
## faced walks straight away.
func _walk_one(direction: Vector2i) -> void:
	var before: Vector2i = _world_screen._world.player_cell
	assert_true(_world_screen.move_player(direction))
	for _frame: int in 16:
		if not _world_screen._world.player_step_in_progress():
			break
		_world_screen.advance_frame()
	await get_tree().process_frame
	if _world_screen._world.player_cell == before:
		assert_true(_world_screen.move_player(direction))


## Spends the world's own frames rather than the host's, so the shock emote and
## the approach cost what `SeenByTrainerScript` says they cost however fast this
## machine runs the suite.
func _trigger_trainer() -> void:
	await _walk_one(Vector2i.RIGHT)
	for _frame: int in 400:
		_world_screen.advance_frame()
		if _battle_child() != null:
			break
		var pending: Dictionary = _world_screen._world.pending_script_input()
		if StringName(pending.get("type", &"")) in [&"text", &"button"]:
			_world_screen._advance_script_input()
	await get_tree().process_frame
	assert_not_null(_battle_host())


func _battle_child() -> Gen2BattleScreen:
	for child: Node in _world_screen.get_children():
		if child is Gen2BattleScreen:
			return child as Gen2BattleScreen
	return null


## The battle overlay, with its opening slide walked to the end.
##
## `BattleIntroSlidingPics` runs before `BattleStartMessage`, so a battle says
## nothing until the pics are in place. In play the screen's own frames spend
## that; a test that read the box without it would read an empty one.
func _battle_host() -> Gen2BattleScreen:
	var host: Gen2BattleScreen = _battle_child()
	if host == null:
		return null
	var guard: int = 4000
	while host.frames_running() and guard > 0:
		host.advance_frame()
		guard -= 1
	return host


## The wild this fixture ships, named out of the cache rather than spelled out.
## Which species number `TRAINER_SPECIES` lands on, and so whether that row
## carries a name of its own or the filler one, is the world fixture's business
## and not something these four messages should pin.
func _wild_name() -> String:
	return String(_data.species(Fixture.TRAINER_SPECIES).get("name", ""))


func test_trainer_sight_reaches_the_real_battle_overlay() -> void:
	await _open_world()
	var before: Dictionary = _world_screen.world_snapshot()
	await _trigger_trainer()

	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	assert_eq(before["map"], Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER))
	assert_eq(before["player_cell"], Vector2i(4, 5))
	assert_eq(_world_screen.world_snapshot()["player_cell"], Vector2i(5, 5))
	assert_eq((_world_screen._world.objects[0] as Gen2WorldObject).cell, Vector2i(5, 4))
	assert_eq(
		(_world_screen._world.objects[0] as Gen2WorldObject).facing,
		Gen2WorldSprite.FACING_DOWN
	)
	assert_eq(_world_screen._world.player_facing, Gen2WorldSprite.FACING_UP)
	assert_true(host.is_ready())
	var snapshot: Dictionary = host.battle_snapshot()
	assert_eq(snapshot["enemy"], Fixture.TRAINER_SPECIES)
	assert_eq(snapshot["message"], "LEADER RIVAL wants to fight!")
	assert_eq(snapshot["world_battle_active"], true)


## While the trainer object is mid-step, its presentation offset eases toward
## zero instead of snapping.
func test_trainer_approach_step_interpolates_the_objects_position() -> void:
	await _open_world()
	await _walk_one(Vector2i.RIGHT)

	var object := _world_screen._world.objects[0] as Gen2WorldObject
	var saw_step: bool = false
	var was_stepping: bool = false
	var previous_magnitude: int = -1
	var lowest_magnitude: int = Gen2WorldAPI.CELL_PIXELS
	for _frame: int in 400:
		_world_screen.advance_frame()
		if _battle_child() != null:
			break
		if object.is_stepping():
			var offset: Vector2i = object.step_offset(Gen2WorldAPI.CELL_PIXELS)
			var magnitude: int = abs(offset.x) + abs(offset.y)
			if not saw_step:
				# The source's single-step Route 30 fixture path starts at a
				# full cell of offset; a longer path would restart here too.
				assert_eq(magnitude, Gen2WorldAPI.CELL_PIXELS)
			elif was_stepping:
				assert_true(
					magnitude <= previous_magnitude,
					"step offset must ease toward zero within one step, not grow"
				)
			saw_step = true
			was_stepping = true
			previous_magnitude = magnitude
			lowest_magnitude = mini(lowest_magnitude, magnitude)
		else:
			was_stepping = false
		var pending: Dictionary = _world_screen._world.pending_script_input()
		if StringName(pending.get("type", &"")) in [&"text", &"button"]:
			_world_screen._advance_script_input()
	await get_tree().process_frame
	assert_not_null(_battle_host())
	assert_true(saw_step)
	# tick_step() spends one hardware frame, the same one the emote and
	# movement-delay counters are spent by; the offset eases down to one
	# STEP_FRAMES_WALK-th of a cell on the frame before the step formally ends.
	assert_eq(lowest_magnitude, Gen2WorldAPI.CELL_PIXELS / Gen2WorldAPI.STEP_FRAMES_WALK)


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


## Gold/Silver share one command profile (Gen2WorldScriptRunner._crystal_commands()
## returns false for both), so covering the "gold" game id also covers Silver's
## opcode layout for this flow.
func test_gold_profile_trainer_sight_reaches_the_real_battle_overlay() -> void:
	_data = Fixture.build(&"gold")
	await _open_world()
	var before: Dictionary = _world_screen.world_snapshot()
	await _trigger_trainer()

	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	assert_eq(before["player_cell"], Vector2i(4, 5))
	assert_eq(_world_screen.world_snapshot()["player_cell"], Vector2i(5, 5))
	assert_eq((_world_screen._world.objects[0] as Gen2WorldObject).cell, Vector2i(5, 4))
	assert_eq(
		(_world_screen._world.objects[0] as Gen2WorldObject).facing,
		Gen2WorldSprite.FACING_DOWN
	)
	assert_eq(_world_screen._world.player_facing, Gen2WorldSprite.FACING_UP)
	assert_true(host.is_ready())
	var snapshot: Dictionary = host.battle_snapshot()
	assert_eq(snapshot["enemy"], Fixture.TRAINER_SPECIES)
	assert_eq(snapshot["message"], "LEADER RIVAL wants to fight!")
	assert_eq(snapshot["world_battle_active"], true)


func test_gold_profile_victory_commits_beaten_flag_and_reloads_objects() -> void:
	_data = Fixture.build(&"gold")
	await _open_world()
	await _trigger_trainer()
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)

	for _hit: int in 12:
		host.hurt_enemy()
	host.finish()
	host.advance()
	assert_eq(host.battle_snapshot()["message"], "YOU WON.")

	host.finish()
	host.advance()
	await get_tree().process_frame
	var world: Dictionary = _world_screen.world_snapshot()
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


func test_effect_sprite_preview_reaches_the_production_world_renderer() -> void:
	await _open_world()
	_world_screen.preview_effect_sprites()
	await get_tree().process_frame

	assert_eq(_world_screen.world_snapshot()["script_prompt"], "Debug effect sprite preview")
	assert_true((_world_screen._world.objects[0] as Gen2WorldObject).emote_visible)
	assert_eq(_world_screen._effects.sprites().size(), 3,
		"the dust, the rustle and the tree are all staged")


func test_production_world_entry_and_facing_object_story_persist_separate_flags() -> void:
	_install_story_slice()
	await _open_world()
	assert_eq(_world_screen._world.state.map_scene(Fixture.MAP_GROUP, Fixture.MAP_NUMBER), 2)

	_world_screen._world.player_cell = Vector2i(4, 3)
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_RIGHT
	assert_true(_world_screen.interact())
	## The `waitbutton` behind the `writetext`, which is what a text ending in
	## `<DONE>` leaves the script holding on.
	assert_eq(
		StringName(_world_screen._world.pending_script_input().get("type", &"")), &"button"
	)
	assert_false(_world_screen._world.event_flag_active(STORY_EVENT_FLAG))
	assert_false(_world_screen._world.state.hall_of_fame())

	## Two presses, not one: the box reveals at the OPTION menu's TEXT SPEED now,
	## and the first press completes the page the way holding A does in
	## `PrintLetterDelay`. The second is the one that acknowledges it.
	_world_screen._advance_script_input()
	_world_screen._advance_script_input()
	assert_true(_world_screen._world.event_flag_active(STORY_EVENT_FLAG))
	assert_true(_world_screen._world.state.hall_of_fame())
	## Still on screen: `ReadObjectEvents` tested the flag when the map loaded
	## and nothing re-tests it while the map is up, so the `setevent` this script
	## just ran hides the object on the next load, which is `restored` below.
	assert_eq(_world_screen.world_snapshot()["visible_objects"], 1)

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
	assert_eq(host.battle_snapshot()["message"], "Wild %s appeared!" % _wild_name())


func test_catch_tutorial_uses_the_real_battle_overlay_without_persistent_capture() -> void:
	await _open_world()
	var balls_before: int = _world_screen._world.state.item_quantity(
		Gen2WorldPartyHost.ITEM_POKE_BALL
	)
	var results: Array = _world_screen._world.dispatch_script_events(Vector2i(4, 5))
	assert_eq(results[0]["status"], &"waiting")
	assert_eq(results[0]["event"]["request"]["kind"], &"catch_tutorial_requested")
	_world_screen._show_script_results(results)
	assert_not_null(_battle_host())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_null(_battle_host())
	assert_eq(
		_world_screen._world.state.item_quantity(Gen2WorldPartyHost.ITEM_POKE_BALL),
		balls_before
	)
	assert_false(_world_screen._world.state.just_battled())


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

	assert_eq(host.battle_snapshot()["message"], "Gotcha! %s was caught!" % _wild_name())
	host.finish()
	host.advance()
	await get_tree().process_frame
	assert_null(_battle_host())
	assert_eq(_world_screen._world.state.item_quantity(Gen2WorldPartyHost.ITEM_MASTER_BALL), 0)
	assert_eq(_world_screen.world_snapshot()["script_prompt"], "Caught %s" % _wild_name())


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
		if host.battle_snapshot()["message"] == "%s broke free!" % _wild_name():
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


## A trimmed PokecenterNurseScript: yesorno, HealParty, then HealMachineAnim,
## matching the source's std script call order in
## engine/events/std_scripts.asm.
func test_nurse_script_heals_the_party_after_accepting_and_shows_the_heal_machine() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	var nurse_script: int = 0x6310
	var done_script: int = 0x6320
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, nurse_script)] = [
		Gen2WorldScript.YESORNO,
		Gen2WorldScript.IFFALSE, done_script & 0xFF, (done_script >> 8) & 0xFF,
		Gen2WorldScript.SPECIAL, 27, 0,
		Gen2WorldScript.SETVAL, 0,
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_HEAL_MACHINE_ANIM, 0,
		Gen2WorldScript.END,
	]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, done_script)] = [Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_data = GameData.open_directory(Fixture.directory())
	await _open_world(true)

	var save: Gen2SaveData = _world_screen._injected_save
	var mon: Gen2SaveMon = save.party[0]
	var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, mon)
	mon.hp = 1
	_world_screen._world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 4, "y": 5, "script": nurse_script,
	}]

	var waiting: Array = _world_screen._world.dispatch_script_events(Vector2i(4, 5))
	assert_eq(waiting[0]["status"], &"waiting", JSON.stringify(waiting))
	assert_eq(waiting[0]["event"]["type"], &"choice")

	var after_choice: Array = _world_screen._world.choose_script_input(0)
	assert_eq(after_choice[0]["status"], &"waiting", JSON.stringify(after_choice))
	assert_eq(_world_screen._world.pending_runtime_request()["kind"], &"party_heal_requested")

	var complete: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world_screen._world, {}, save, false
	)
	assert_true(complete["ok"], JSON.stringify(complete))
	var results: Array = complete.get("results", [])
	assert_eq(results[results.size() - 1]["status"], &"complete", JSON.stringify(results))
	assert_eq(
		_event_value(results[results.size() - 1].get("events", []), &"presentation_special_applied", "kind"),
		&"heal_machine_anim",
		JSON.stringify(results),
	)
	var healed_mon: Gen2SaveMon = save.party[0]
	assert_eq(healed_mon.hp, battle_mon.max_hp())


func test_nurse_script_leaves_the_party_unhealed_on_refusal() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	var nurse_script: int = 0x6330
	var done_script: int = 0x6340
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, nurse_script)] = [
		Gen2WorldScript.YESORNO,
		Gen2WorldScript.IFFALSE, done_script & 0xFF, (done_script >> 8) & 0xFF,
		Gen2WorldScript.SPECIAL, 27, 0,
		Gen2WorldScript.END,
	]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, done_script)] = [Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_data = GameData.open_directory(Fixture.directory())
	await _open_world(true)

	var save: Gen2SaveData = _world_screen._injected_save
	var mon: Gen2SaveMon = save.party[0]
	mon.hp = 1
	_world_screen._world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 4, "y": 5, "script": nurse_script,
	}]

	var waiting: Array = _world_screen._world.dispatch_script_events(Vector2i(4, 5))
	assert_eq(waiting[0]["status"], &"waiting", JSON.stringify(waiting))

	var after_choice: Array = _world_screen._world.choose_script_input(1)
	assert_eq(after_choice[0]["status"], &"complete", JSON.stringify(after_choice))
	assert_true(_world_screen._world.pending_runtime_request().is_empty())
	assert_eq(save.party[0].hp, 1)


func test_zephyr_badge_survives_a_snapshot_save_and_reload() -> void:
	await _open_world(true)
	_world_screen._world.state.set_engine_flag(Gen2WorldState.ENGINE_ZEPHYRBADGE)
	assert_eq(_world_screen._world.state.badge_count(), 1)

	var save: Gen2SaveData = _world_screen._injected_save
	save.world = _world_screen._world.snapshot()
	var validation: Dictionary = Gen2SaveValidator.validate(save, _data)
	assert_true(validation["ok"], validation["message"])

	var round_trip: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	assert_not_null(round_trip.world)
	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(_data, round_trip.world)
	assert_not_null(restored)
	assert_eq(restored.state.badge_count(), 1)
	assert_true(restored.state.is_engine_flag_active(Gen2WorldState.ENGINE_ZEPHYRBADGE))


## The Togepi egg joins the party before Route 32 opens, so every trainer after
## it fights with an egg in a party slot.
func test_a_trainer_battle_fights_and_writes_back_with_an_egg_in_the_party() -> void:
	await _open_world(true)
	var save: Gen2SaveData = _world_screen._injected_save
	# Built the way Gen2WorldPartyHost's GIVEEGG builds one, so the save
	# validator sees a consistent level and experience.
	var egg: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(
		Gen2BattleMon.create(_data, Fixture.TRAINER_SPECIES, 5, [BattleFixture.TACKLE])
	)
	egg.is_egg = true
	egg.hp = 0
	egg.nickname = "EGG"
	save.party.append(egg)

	await _trigger_trainer()
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host, "an egg in the party must not refuse the battle")
	assert_eq(host.battle_snapshot()["world_battle_active"], true)

	for _hit: int in 12:
		host.hurt_enemy()
	host.finish()
	host.advance()
	assert_eq(host.battle_snapshot()["message"], "YOU WON.")
	host.finish()
	host.advance()
	await get_tree().process_frame
	assert_true(_world_screen.world_snapshot()["just_battled"])

	var written: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, save.slot,
		Gen2SaveBattleAdapter.to_battle_party(_data, save), "", save
	)
	assert_not_null(written)
	assert_eq(written.party.size(), 2)
	assert_false((written.party[0] as Gen2SaveMon).is_egg)
	assert_true((written.party[1] as Gen2SaveMon).is_egg)
	assert_eq((written.party[1] as Gen2SaveMon).nickname, "EGG")


func _event_value(events: Array, event_type: StringName, key: String) -> Variant:
	for event: Dictionary in events:
		if event.get("type", &"") == event_type:
			return event.get(key, null)
	return null


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
		## The `waitbutton` every talked-to script carries behind its text:
		## `writetext` itself prints and returns.
		Gen2WorldScript.WAITBUTTON,
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


## Running from a real wild encounter, through the production overlay: the
## battle ends with nobody having won, the party is untouched, and the world
## comes back rather than blacking out.
##
## The player's Pokémon is faster than the fixture's wild one, so
## `TryToRunAwayFromBattle`'s speed comparison answers and no roll happens.
func test_running_from_a_wild_encounter_returns_to_the_world_without_a_loss() -> void:
	await _open_world()
	_world_screen.preview_wild_encounter()
	await get_tree().process_frame
	await get_tree().process_frame
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	var party_before: int = host._battle.party(Gen2Battle.PLAYER).at(0).hp

	host.run_from_battle()

	assert_true(host._battle.has_fled())
	assert_null(host._battle.winner())
	assert_eq(host.battle_snapshot()["message"], "Got away safely!")
	assert_eq(host._battle.party(Gen2Battle.PLAYER).at(0).hp, party_before)

	host.finish()
	host.advance()
	host.finish()
	host.advance()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_null(_battle_host(), "the overlay stayed open after the run")
	var world: Dictionary = _world_screen.world_snapshot()
	assert_eq(world["map"], Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER))


## A trainer battle answers the same request with its own refusal, and the
## overlay stays open with both sides where they were: `BattleMenu_Run` reopens
## the menu rather than spending the turn.
func test_a_trainer_battle_refuses_the_run_and_the_overlay_stays_open() -> void:
	await _open_world()
	await _trigger_trainer()
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	var enemy_before: int = host._battle.mon(Gen2Battle.ENEMY).hp
	var player_before: int = host._battle.mon(Gen2Battle.PLAYER).hp

	host.run_from_battle()

	assert_false(host._battle.has_fled())
	assert_false(host._battle.is_over())
	assert_eq(
		host.battle_snapshot()["message"],
		"No! There's no running from a trainer battle!"
	)
	assert_eq(host._battle.mon(Gen2Battle.ENEMY).hp, enemy_before)
	assert_eq(host._battle.mon(Gen2Battle.PLAYER).hp, player_before, "the turn was spent")
	assert_not_null(_battle_host())
