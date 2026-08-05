extends GutTest

## World runtime tests use a synthetic cache so movement and expansion remain
## independent of a real cartridge while still going through GameData.

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testworld", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	RomCache.write_json(RomCache.species_path(_directory), [])
	RomCache.write_json(RomCache.moves_path(_directory), [])
	var items: Array = []
	for number: int in Gen2WorldInventory.ITEM_SUPER_ROD:
		items.append({
			"number": number,
			"name": "OLD ROD" if number == Gen2WorldInventory.ITEM_OLD_ROD
			else ("GOOD ROD" if number == Gen2WorldInventory.ITEM_GOOD_ROD
			else ("SUPER ROD" if number == Gen2WorldInventory.ITEM_SUPER_ROD else "ITEM%d" % number)),
			"pocket": 4 if number == 6 else 1,
		})
	RomCache.write_json(RomCache.items_path(_directory), items)
	RomCache.write_json(RomCache.types_path(_directory), [])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [])

	var meta: Array = []
	for block: int in 2:
		for tile: int in 16:
			meta.append(block * 16 + tile)

	RomCache.write_json(RomCache.world_tilesets_path(_directory), [{
		"number": 0,
		"block_count": 2,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [0, 0, 0, 0, 0x20, 0x20, 0x20, 0x20],
	}])

	var blocks: Array = []
	for index: int in 48:
		blocks.append(index % 2)

	var collision: Array = []
	collision.resize(16 * 12)
	for index: int in collision.size():
		collision[index] = 0
	collision[6 * 16 + 9] = 0x07
	collision[7 * 16 + 8] = 0x20
	collision[6 * 16 + 6] = 0x70

	var source_events: Dictionary = {
		"bank": 48,
		"warps": [{
			"x": 6, "y": 6, "destination": 1, "map_group": 1, "map_number": 2,
		}],
		"coord_events": [{"scene": 0, "x": 7, "y": 6, "script": 0x6000}],
		"bg_events": [{"x": 8, "y": 6, "type": 0, "script": 0x6015}],
		"objects": [{"sprite": 1, "x": 5, "y": 6, "script": 0x6030, "event_flag": 7}],
	}

	var target_collision: Array = []
	target_collision.resize(16 * 12)
	for index: int in target_collision.size():
		target_collision[index] = 0

	var source_map: Dictionary = {
		"group": 1,
		"number": 1,
		"tileset": 0,
		"fish_group": 1,
		"width_blocks": 8,
		"height_blocks": 6,
		"blocks": blocks,
		"collision": collision,
		"collision_width": 16,
		"collision_height": 12,
		"connection_flags": RomLayout.MAP_CONNECTION_FLAG_EAST,
		"connections": [{
			"direction": "east", "map_group": 1, "map_number": 2,
			"x_offset": 0, "y_offset": 0,
		}],
		"scripts": {
			"bank": 48,
			"address": 0x5000,
			"callbacks": [{"type": 3, "script": 0x6010}],
		},
		"events": source_events,
	}
	var target_map: Dictionary = {
		"group": 1,
		"number": 2,
		"tileset": 0,
		"fish_group": 1,
		"width_blocks": 8,
		"height_blocks": 6,
		"blocks": blocks,
		"collision": target_collision,
		"collision_width": 16,
		"collision_height": 12,
		"connection_flags": RomLayout.MAP_CONNECTION_FLAG_WEST,
		"connections": [{
			"direction": "west", "map_group": 1, "map_number": 1,
			"x_offset": 0, "y_offset": 0,
		}],
		"scripts": {
			"bank": 48,
			"callbacks": [{"type": 5, "script": 0x6040}],
		},
		"events": {"warps": [{
			"x": 2, "y": 2, "destination": 1, "map_group": 1, "map_number": 1,
		}]},
	}
	RomCache.write_json(RomCache.world_maps_path(_directory), [source_map, target_map])
	RomCache.write_json(RomCache.world_encounters_path(_directory), {
		"grass": {
			"1:1": {
				"map": "1:1", "rates": [255, 255, 255],
				"slots": [
					[{"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}],
					[{"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}],
					[{"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}, {"level": 5, "species": 16},
					 {"level": 5, "species": 16}],
				],
			},
		},
		"water": {
			"1:1": {
				"map": "1:1", "rate": 255,
				"slots": [{"level": 5, "species": 16}, {"level": 5, "species": 16},
					{"level": 5, "species": 16}],
			},
		},
		"swarm_grass": {
			"1:1": {
				"map": "1:1", "rates": [255, 255, 255],
				"slots": [
					[{"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}],
					[{"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}],
					[{"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}, {"level": 5, "species": 19}],
				],
			},
		},
		"swarm_water": {},
		"fishing": {
			"groups": [{
				"chance": 255,
				"rods": [[{"threshold": 255, "species": 16, "level": 5}], [], []],
			}],
			"time_groups": [],
		},
		"roaming": {
			"maps": [{"map_group": 1, "map_number": 1, "connections": []}],
			"mons": [{"species": 0xF3, "level": 40, "map_group": 1, "map_number": 2}],
		},
		"probabilities": {
			"grass": RomLayout.WILD_GRASS_PROBABILITIES,
			"water": RomLayout.WILD_WATER_PROBABILITIES,
		},
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6000": [0x33, 7, 0, 0x4C, 0x00, 0x70, 0x91],
		"48:6010": [0x14, 2, 0x91],
		"48:6015": [0x3C, 1, 2, 2, 2, 0x91],
		"48:6030": [0x6E, 2, 0x91],
		"48:6040": [0x14, 3, 0x91],
	})
	RomCache.write_json(RomCache.world_standard_scripts_path(_directory), {
		"0": {"bank": 48, "address": 0x6020, "bytes": [0x4C, 0x00, 0x70, 0x91]},
	})
	RomCache.write_json(RomCache.world_text_path(_directory), {
		"48:7000": [0x00, 0x80, 0x81, 0x50],
	})

	var pixels := PackedByteArray()
	pixels.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	for index: int in pixels.size():
		pixels[index] = index % 4
	RomCache.write_indices(RomCache.world_tile_path(_directory, 0), pixels)

	RomCache.write_json(RomCache.overworld_sprites_path(_directory), [{
		"number": 1, "address": 0x4000, "bank": 0x30, "bytes": 64,
		"tiles": 4, "type": Gen2WorldSprite.TYPE_STILL, "palette": 0,
	}])
	var sprite_palettes: Array = []
	for _group: int in RomLayout.OVERWORLD_SPRITE_PALETTE_GROUP_COUNT:
		sprite_palettes.append([0x7FFF, 0x421F, 0x2108, 0])
	RomCache.write_json(RomCache.overworld_sprite_palettes_path(_directory), sprite_palettes)
	var sprite_pixels := PackedByteArray()
	sprite_pixels.resize(4 * Gen2Tiles.TILE_PIXELS)
	for index: int in sprite_pixels.size():
		sprite_pixels[index] = index % 4
	RomCache.write_indices(RomCache.overworld_sprite_path(_directory, 1), sprite_pixels)

	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testworld",
		"sha1": "0123456789abcdef",
		"complete": true,
	})


func _world(
	start: Vector2i = Vector2i(8, 6), state: Gen2WorldState = null
) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var world_state: Gen2WorldState = state
	if world_state == null:
		world_state = Gen2WorldState.new(
			{}, {}, {Gen2WorldInventory.ITEM_OLD_ROD: 1}
		)
	return Gen2WorldAPI.open(data, 1, 1, start, world_state)


func _write_service_cache() -> void:
	RomCache.write_json(RomCache.world_marts_path(_directory), {
		"marts": [{"index": 0, "bank": 48, "address": 0x4000, "items": [7]}],
		"default": {"items": [7]}, "special": {},
	})
	RomCache.write_json(RomCache.world_phone_path(_directory), {
		"contacts": [{
			"index": 0, "caller_script": {"bank": 48, "address": 0x1234},
			"callee_script": {"bank": 48, "address": 0x5678},
		}],
		"special_calls": [{"index": 0, "script": {"bank": 48, "address": 0x7000}}],
	})
	var sfx: Array = []
	for index: int in 0x9C:
		sfx.append({"index": index, "bank": 48, "address": 0x4000, "bytes": [1, 2]})
	RomCache.write_json(RomCache.world_audio_path(_directory), {
		"music": [{"index": 0, "bank": 48, "address": 0x1234, "bytes": [1, 2]}],
		"sfx": sfx,
	})


func test_world_host_resolves_imported_mart_audio_and_phone_records() -> void:
	_write_service_cache()
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6100": [0x7F, 0x34, 0x12, 0x91],
		"48:6110": [0x94, 2, 0x00, 0x40, 0x91],
		"48:6120": [0x98, 0x34, 0x12, 0x91],
		"48:6130": [0x9C, 0x00, 0x00, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	var cases: Array = [
		{"script": 0x6100, "kind": &"audio_requested", "data_key": "audio", "row_key": "index"},
		{"script": 0x6110, "kind": &"mart_requested", "data_key": "mart", "row_key": "index"},
		{"script": 0x6120, "kind": &"phone_call_requested", "data_key": "contact", "row_key": "index"},
		{"script": 0x6130, "kind": &"special_phone_call_requested", "data_key": "special_call", "row_key": "index"},
	]
	for test_case: Dictionary in cases:
		data.world_map(1, 1).events["coord_events"][0]["script"] = test_case["script"]
		var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
		var waiting: Array = world.dispatch_script_events()
		assert_eq(waiting[0]["status"], &"waiting")
		assert_eq(world.pending_runtime_request()["kind"], test_case["kind"])
		var complete: Dictionary = Gen2WorldHost.complete_runtime_request(world, {})
		assert_true(complete["ok"])
		assert_true(complete["handled"])
		assert_eq(complete["data"][test_case["data_key"]][test_case["row_key"]], 0)
		assert_eq(complete["results"][0]["status"], &"complete")


func test_world_host_resolves_contextual_warp_and_item_sounds() -> void:
	_write_service_cache()
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6140": [0x87, 0x91],
		"48:6150": [0x1F, 7, 1, 0x88, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	var scripts: Array = [0x6140, 0x6150]
	var expected_sfx: Array = [0x23, 0x9B]
	for index: int in scripts.size():
		data.world_map(1, 1).events["coord_events"][0]["script"] = scripts[index]
		var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
		var waiting: Array = world.dispatch_script_events()
		assert_eq(waiting[0]["status"], &"waiting")
		var complete: Dictionary = Gen2WorldHost.complete_runtime_request(world, {})
		assert_true(complete["ok"])
		assert_eq(complete["data"]["audio"]["index"], expected_sfx[index])


func test_collision_codes_keep_the_cartridge_permission_categories() -> void:
	assert_eq(Gen2WorldCollision.permission_for(0x00), Gen2WorldCollision.LAND_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x70), Gen2WorldCollision.LAND_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x20), Gen2WorldCollision.WATER_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x07), Gen2WorldCollision.WALL_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x90), Gen2WorldCollision.WALL_TILE)
	assert_eq(Gen2WorldCollision.permission_for(-1), Gen2WorldCollision.WALL_TILE)


func test_api_resolves_map_and_clamps_start_cell() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(100, -2))
	assert_not_null(world)
	assert_eq(world.map_id(), Vector2i(1, 1))
	assert_eq(world.map_size_cells(), Vector2i(16, 12))
	assert_eq(world.player_cell, Vector2i(15, 0))


func test_expanded_tiles_follow_block_and_metatile_order() -> void:
	var world: Gen2WorldAPI = _world()
	assert_eq(world.tile_index_at(0, 0), 0)
	assert_eq(world.tile_index_at(3, 3), 15)
	assert_eq(world.tile_index_at(4, 0), 16)
	assert_eq(world.tile_index_at(7, 3), 31)
	assert_eq(world.tile_index_at(-1, 0), -1)
	assert_eq(world.tile_index_at(32, 0), -1)


func test_visible_page_is_twenty_by_eighteen_tiles_and_centers_player() -> void:
	var world: Gen2WorldAPI = _world()
	assert_eq(world.visible_origin_cell(), Vector2i(3, 2))
	assert_eq(world.player_view_cell(), Vector2i(5, 4))
	assert_eq(world.player_pixel_position(), Vector2i(80, 64))

	var page: PackedInt32Array = world.visible_tile_indices()
	assert_eq(page.size(), 20 * 18)
	assert_eq(page[0], world.tile_index_at(6, 4))
	assert_eq(page[19], world.tile_index_at(25, 4))

	var top_left: Gen2WorldAPI = _world(Vector2i.ZERO)
	assert_eq(top_left.visible_origin_cell(), Vector2i.ZERO)
	var bottom_right: Gen2WorldAPI = _world(Vector2i(15, 11))
	assert_eq(bottom_right.visible_origin_cell(), Vector2i(6, 3))


func test_movement_uses_raw_collision_codes_without_mutating_them() -> void:
	var world: Gen2WorldAPI = _world()
	assert_eq(world.collision_code_at(Vector2i(9, 6)), 0x07)
	assert_false(world.can_walk_to(Vector2i(9, 6)))
	assert_false(world.move(Vector2i.RIGHT))
	assert_eq(world.player_cell, Vector2i(8, 6))

	assert_eq(world.collision_code_at(Vector2i(8, 7)), 0x20)
	assert_false(world.can_walk_to(Vector2i(8, 7)))
	assert_false(world.move(Vector2i.DOWN))

	assert_true(world.move(Vector2i.LEFT))
	assert_eq(world.player_cell, Vector2i(7, 6))


func test_active_map_objects_occupy_walk_cells() -> void:
	var world: Gen2WorldAPI = _world()
	assert_eq(world.visible_objects().size(), 1)
	assert_eq(world.object_at(Vector2i(5, 6)).index, 0)
	assert_false(world.can_walk_to(Vector2i(5, 6)))


func test_trainer_sight_queues_the_first_facing_trainer_in_range() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(5, 4))
	var trainer: Gen2WorldObject = world.objects[0]
	trainer.object_type = Gen2WorldObject.OBJECTTYPE_TRAINER
	trainer.sight_range = 3
	trainer.facing = Gen2WorldSprite.FACING_UP

	var results: Array = world.dispatch_sight_events()
	assert_eq(results.size(), 1)
	assert_eq(results[0]["status"], &"complete")
	assert_eq(results[0]["source"]["kind"], &"sight")
	assert_eq(results[0]["source"]["distance"], 2)
	assert_eq(results[0]["source"]["direction"], Vector2i.UP)
	assert_eq(results[0]["events"][0]["type"], &"object_visibility")
	assert_false((world.objects[0] as Gen2WorldObject).active)

	var hidden_trainer: Gen2WorldObject = world.objects[0]
	hidden_trainer.active = true
	hidden_trainer.facing = Gen2WorldSprite.FACING_UP
	hidden_trainer.sight_range = 1
	assert_true(world.dispatch_sight_events().is_empty())


func test_script_object_visibility_changes_rendering_and_occupancy() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var result: Array = world.dispatch_script_events(Vector2i(5, 6))
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete")
	assert_eq(result[0]["events"][0]["type"], &"object_visibility")
	assert_eq(world.visible_objects().size(), 0)
	assert_true(world.can_walk_to(Vector2i(5, 6)))


func test_event_flags_hide_objects_from_rendering_occupancy_and_dispatch() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	assert_eq(world.dispatch_events(Vector2i(5, 6)).size(), 1)
	assert_false(world.can_walk_to(Vector2i(5, 6)))

	world.set_event_flag(7)
	assert_eq(world.visible_objects().size(), 0)
	assert_null(world.object_at(Vector2i(5, 6)))
	assert_true(world.can_walk_to(Vector2i(5, 6)))
	assert_eq(world.dispatch_events(Vector2i(5, 6)).size(), 0)

	world.clear_event_flag(7)
	assert_eq(world.visible_objects().size(), 1)
	assert_eq(world.dispatch_events(Vector2i(5, 6)).size(), 1)


func test_event_dispatch_reports_decoded_records_without_running_scripts() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(6, 6))
	var events: Array = world.dispatch_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["kind"], &"warps")
	assert_eq(events[0]["destination"], 1)

	var coord_events: Array = world.dispatch_events(Vector2i(7, 6))
	assert_eq(coord_events.size(), 1)
	assert_eq(coord_events[0]["kind"], &"coord_events")
	assert_eq(coord_events[0]["script"], 0x6000)

	var object_events: Array = world.dispatch_events(Vector2i(5, 6))
	assert_eq(object_events[0]["kind"], &"objects")


func test_script_dispatch_pauses_for_text_then_commits_flags_atomically() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(7, 6))
	var state: Gen2WorldState = world.state
	var waiting: Array = world.dispatch_script_events()
	assert_eq(waiting.size(), 1)
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(waiting[0]["event"]["type"], &"text")
	assert_eq(waiting[0]["event"]["text"], "AB")
	assert_false(state.is_event_flag_active(7))

	var completed: Array = world.run_event_queue(true)
	assert_eq(completed.size(), 1)
	assert_eq(completed[0]["status"], &"complete")
	assert_true(state.is_event_flag_active(7))


func test_standard_script_jump_and_call_use_the_imported_pointer_table() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var standard: Dictionary = data.world_standard_script(0)
	assert_eq(standard["bank"], 48)
	assert_eq(standard["address"], 0x6020)
	assert_eq(standard["data"], PackedByteArray([0x4C, 0x00, 0x70, 0x91]))

	for opcode: int in [Gen2WorldScript.JUMPSTD, Gen2WorldScript.CALLSTD]:
		var request: Dictionary = {"kind": &"test", "bank": 48, "script": 0x6025}
		var scripts: Dictionary = {
			"48:6025": [opcode, 0, 0, 0x91],
		}
		RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
		data = GameData.open_directory(_directory)
		var runner: Gen2WorldScriptRunner = Gen2WorldScriptRunner.begin(
			data, Gen2WorldState.new(), request
		)
		var waiting: Dictionary = runner.advance()
		assert_eq(waiting["status"], &"waiting")
		assert_eq(waiting["event"]["text"], "AB")
		var completed: Dictionary = runner.advance(true)
		assert_eq(completed["status"], &"complete")


func test_script_failure_does_not_commit_staged_state() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6008": [0x33, 8, 0, 0xFE],
	})
	# The current GameData was opened before the replacement, so use a fresh API.
	data = GameData.open_directory(_directory)
	var map: Gen2WorldMap = data.world_map(1, 1)
	map.events["coord_events"][0]["script"] = 0x6008
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var result: Array = world.dispatch_script_events()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"failed")
	assert_eq(result[0]["reason"], &"unsupported_command")
	assert_false(world.event_flag_active(8))


func test_callback_dispatch_updates_the_map_scene() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	assert_eq(world.state.map_scene(1, 1), 0)
	var result: Array = world.dispatch_callbacks(3)
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete")
	assert_eq(world.state.map_scene(1, 1), 2)


func test_script_warp_is_validated_before_transition() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var result: Array = world.dispatch_script_events(Vector2i(8, 6))
	assert_eq(result.size(), 2)
	assert_eq(result[0]["status"], &"complete")
	assert_eq(result[1]["source"]["kind"], &"callback")
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_eq(world.player_cell, Vector2i(2, 2))


func test_script_queue_keeps_event_source_order() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var coordinate: Dictionary = world.current_map.events["coord_events"][0]
	coordinate["x"] = 8
	coordinate["y"] = 6
	coordinate["script"] = 0x6010
	var results: Array = world.dispatch_script_events(Vector2i(8, 6))
	assert_eq(results.size(), 3)
	assert_eq(results[0]["source"]["kind"], &"coord_events")
	assert_eq(results[1]["source"]["kind"], &"bg_events")
	assert_eq(results[2]["source"]["kind"], &"callback")
	assert_eq(world.state.map_scene(1, 1), 2)
	assert_eq(world.map_id(), Vector2i(1, 2))


func test_warp_resolves_one_based_destination_and_reloads_the_target_map() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(6, 6))
	var result: Dictionary = world.try_warp()
	assert_true(result["ok"])
	assert_eq(result["from_map"], Vector2i(1, 1))
	assert_eq(result["from_cell"], Vector2i(6, 6))
	assert_eq(result["to_map"], Vector2i(1, 2))
	assert_eq(result["to_cell"], Vector2i(2, 2))
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_eq(world.player_cell, Vector2i(2, 2))


func test_map_transition_queues_target_callbacks_for_the_next_script_pump() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(6, 6))
	var transition: Dictionary = world.try_warp()
	assert_true(transition["ok"])
	var callbacks: Array = world.dispatch_callbacks(5)
	assert_eq(callbacks.size(), 1)
	assert_eq(callbacks[0]["status"], &"complete")
	assert_eq(world.state.map_scene(1, 2), 3)


func test_connected_edge_step_translates_the_player_and_reloads_the_target_map() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(15, 6))
	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_true(result["ok"])
	assert_eq(result["kind"], &"connection")
	assert_eq(result["from_map"], Vector2i(1, 1))
	assert_eq(result["from_cell"], Vector2i(15, 6))
	assert_eq(result["to_map"], Vector2i(1, 2))
	assert_eq(result["to_cell"], Vector2i(0, 6))
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_eq(world.player_cell, Vector2i(0, 6))

	var return_result: Dictionary = world.move_result(Vector2i.LEFT)
	assert_true(return_result["ok"])
	assert_eq(return_result["kind"], &"connection")
	assert_eq(world.map_id(), Vector2i(1, 1))
	assert_eq(world.player_cell, Vector2i(15, 6))


func test_connection_requires_the_player_to_be_on_the_requested_edge() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var result: Dictionary = world.try_connection(Vector2i.RIGHT)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"not_at_edge")
	assert_eq(world.map_id(), Vector2i(1, 1))
	assert_eq(world.player_cell, Vector2i(8, 6))


func test_invalid_directions_and_map_edges_do_not_move_player() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(0, 0))
	assert_false(world.move(Vector2i.ZERO))
	assert_false(world.move(Vector2i(1, 1)))
	assert_false(world.move(Vector2i.LEFT))
	assert_false(world.move(Vector2i.UP))
	assert_eq(world.player_cell, Vector2i.ZERO)

	world.player_cell = Vector2i(15, 11)
	assert_false(world.move(Vector2i.DOWN))


func test_script_applymovement_executes_imported_object_and_player_streams() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x0F, 0x47],
		"48:6110": [0x0D, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [
			0x69, 2, 0x00, 0x61,
			0x69, 0, 0x10, 0x61,
			0x91,
		],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var results: Array = world.dispatch_script_events()
	assert_eq(results.size(), 1)
	assert_eq(results[0]["status"], &"complete")
	assert_eq((world.objects[0] as Gen2WorldObject).cell, Vector2i(6, 6))
	assert_eq(world.player_cell, Vector2i(7, 5))


func test_follow_command_moves_the_follower_after_a_player_step() -> void:
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6080": [0x70, 2, 0, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6080
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))
	var results: Array = world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(results.size(), 1)
	assert_eq(results[0]["status"], &"complete")
	assert_true(world.move(Vector2i.LEFT))
	assert_eq((world.objects[0] as Gen2WorldObject).cell, Vector2i(6, 6))


func test_script_items_money_and_coins_commit_as_one_runtime_transaction() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6050": [
			0x1F, 3, 2,
			0x22, 0, 0, 0, 0x10,
			0x25, 10, 0,
			0x91,
		],
	})
	data = GameData.open_directory(_directory)
	var state := Gen2WorldState.new({}, {}, {3: 2}, {0: 100}, 20)
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6050,
	})
	var result: Dictionary = runner.advance()
	assert_eq(result["status"], &"complete")
	assert_eq(state.item_quantity(3), 4)
	assert_eq(state.money(), 110)
	assert_eq(state.coins(), 30)


func test_script_menu_and_battle_are_explicit_runtime_requests() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6060": [
			0x4F, 0x34, 0x12,
			0x59,
			0x5D, 25, 5,
			0x5F,
			0x91,
		],
	})
	data = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6060,
	})
	var menu: Dictionary = runner.advance()
	assert_eq(menu["status"], &"waiting")
	assert_eq(menu["event"]["type"], &"menu")
	assert_eq(menu["event"]["header"]["address"], 0x1234)

	var still_menu: Dictionary = runner.advance(true)
	assert_eq(still_menu["status"], &"waiting")
	var battle: Dictionary = runner.advance(true, 0)
	assert_eq(battle["status"], &"waiting")
	assert_eq(battle["event"]["type"], &"runtime_request")
	assert_eq(battle["event"]["request"]["kind"], &"battle_requested")
	assert_eq(battle["event"]["request"]["values"]["pokemon"], 25)

	var still_waiting: Dictionary = runner.advance(true)
	assert_eq(still_waiting["status"], &"waiting")

	var complete: Dictionary = runner.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
	})
	assert_eq(complete["status"], &"complete")
	assert_true(complete["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"battle_completed"
	))


func test_missing_audio_data_does_not_acknowledge_an_audio_request() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6098": [0x7F, 0x34, 0x12, 0x91],
	})
	data = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6098
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var waiting: Array = world.dispatch_script_events()
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(world.pending_runtime_request()["kind"], &"audio_requested")
	var unavailable: Dictionary = Gen2WorldHost.complete_runtime_request(world, {"ok": true})
	assert_false(unavailable["ok"])
	assert_eq(unavailable["reason"], &"audio_data_unavailable")
	assert_eq(world.pending_runtime_request()["kind"], &"audio_requested")


func test_swarm_runtime_request_commits_its_map_indices_as_one_transaction() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:60B0": [0x9F, 1, 2, 0x91],
	})
	data = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x60B0,
	})
	var waiting: Dictionary = runner.advance()
	assert_eq(waiting["status"], &"waiting")
	assert_eq(waiting["event"]["request"]["kind"], &"swarm_requested")
	assert_eq(state.swarm_map(), Vector2i(-1, -1))
	var complete: Dictionary = runner.complete_runtime_request({
		"ok": true, "active": true, "map_group": 1, "map_number": 2,
		"fishing_species": 0xD3,
	})
	assert_eq(complete["status"], &"complete")
	assert_eq(state.swarm_map(), Vector2i(1, 2))
	assert_eq(state.fishing_swarm_species(), 0xD3)


func test_world_snapshot_round_trips_map_player_and_mutable_state() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new({}, {"1:1": 3}, {4: 2}, {0: 100}, 7, {9: true}, 5, Vector2i(1, 1), 0xD3, [], true)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6), state)
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	assert_true(world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)["ok"])
	var snapshot: Gen2WorldSnapshot = world.snapshot()
	world.state.set_repel_steps(99)
	assert_eq(snapshot.world_state.repel_steps(), 5)
	var encoded: Dictionary = snapshot.to_dict()
	var decoded := Gen2WorldSnapshot.from_dict(encoded)
	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(data, decoded)
	assert_not_null(restored)
	assert_eq(restored.map_id(), Vector2i(1, 1))
	assert_eq(restored.player_cell, Vector2i(8, 6))
	assert_eq(restored.player_facing, Gen2WorldSprite.FACING_LEFT)
	assert_eq(restored.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(restored.state.map_scene(1, 1), 3)
	assert_eq(restored.state.repel_steps(), 5)
	assert_eq(restored.state.swarm_map(), Vector2i(1, 1))
	assert_true(restored.state.just_battled())
	var schedule: Dictionary = restored.advance_schedule()
	assert_true(schedule["ok"])
	assert_eq(schedule["kind"], &"world_schedule_updated")


func test_battle_request_keeps_trainer_source_and_result_text_pointers() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6090": [
			0x64, 0x00, 0x70, 0x00, 0x71,
			0x5E, 1, 0,
			0x5F,
			0x91,
		],
	})
	data = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"sight", "map_group": 1, "map_number": 1, "bank": 48,
		"script": 0x6090, "object_index": 2,
		"distance": 3, "direction": Vector2i.DOWN,
		"event": {"event_flag": 0x1234, "object_index": 2},
	})
	var waiting: Dictionary = runner.advance()
	assert_eq(waiting["status"], &"waiting")
	var values: Dictionary = waiting["event"]["request"]["values"]
	assert_eq(values["kind"], &"trainer")
	assert_eq(values["trainer_group"], 1)
	assert_eq(values["trainer_id"], 0)
	assert_eq(values["event"]["event_flag"], 0x1234)
	assert_eq(values["object_index"], 2)
	assert_eq(values["distance"], 3)
	assert_eq(values["win_text"]["bank"], 48)
	assert_eq(values["win_text"]["address"], 0x7000)
	assert_eq(values["loss_text"]["address"], 0x7100)


func test_reloadmapafterbattle_is_reported_after_a_confirmed_win() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:60A0": [0x5D, 25, 5, 0x5F, 0x60, 0x91],
	})
	data = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x60A0,
	})
	assert_eq(runner.advance()["status"], &"waiting")
	var complete: Dictionary = runner.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
	})
	assert_eq(complete["status"], &"complete")
	assert_true(complete["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"battle_map_reload_requested"
	))


func test_world_battle_completion_commits_just_battled_only_after_the_host_result() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6068": [0x5D, 25, 5, 0x5F, 0x91],
	})
	data = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6068
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))

	var waiting: Array = world.dispatch_script_events()
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(world.pending_runtime_request()["kind"], &"battle_requested")
	assert_false(world.state.just_battled())

	var acknowledged: Array = world.run_event_queue(true)
	assert_eq(acknowledged[0]["status"], &"waiting")
	assert_false(world.state.just_battled())

	var complete: Array = world.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
	})
	assert_eq(complete[0]["status"], &"complete")
	assert_true(world.state.just_battled())


func test_caught_world_battle_completes_without_marking_just_battled() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6088": [0x5D, 25, 5, 0x5F, 0x91],
	})
	data = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6088
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")

	var complete: Array = world.complete_runtime_request({
		"ok": true,
		"outcome": Gen2WorldBattleAdapter.OUTCOME_CAUGHT,
		"capture": {"species": 25, "ball": 0x01},
	})
	assert_eq(complete[0]["status"], &"complete")
	assert_true(complete[0]["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"battle_captured"
	))
	assert_false(world.state.just_battled())
	assert_true(world.pending_runtime_request().is_empty())


func test_world_battle_loss_fails_without_committing_world_state() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6078": [0x5D, 25, 5, 0x5F, 0x91],
	})
	data = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6078
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")

	var recovered: Array = world.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_LOST,
		"recovery": {"ok": true, "source": &"save", "slot": 0},
	})
	assert_eq(recovered[0]["status"], &"recovered")
	assert_true(recovered[0]["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"blackout"
	))
	assert_false(world.state.just_battled())
	assert_true(world.pending_runtime_request().is_empty())


func test_world_battle_loss_requires_host_recovery_before_ending() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6098": [0x5D, 25, 5, 0x5F, 0x91],
	})
	data = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6098
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")

	var failed: Array = world.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_LOST,
	})
	assert_eq(failed[0]["status"], &"failed")
	assert_eq(failed[0]["reason"], &"battle_recovery_failed")
	assert_false(world.state.just_battled())


func test_reloading_the_current_map_rebuilds_live_objects_without_moving_player() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(5, 6))
	var before: Vector2i = world.player_cell
	var reloaded: Dictionary = world.reload_current_map()
	assert_true(reloaded["ok"])
	assert_eq(reloaded["kind"], &"reload_map")
	assert_eq(world.player_cell, before)
	assert_eq(world.objects.size(), 1)


func test_world_battle_requires_an_explicit_outcome() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6088": [0x5D, 25, 5, 0x5F, 0x91],
	})
	data = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6088
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")

	var failed: Array = world.complete_runtime_request({"ok": true})
	assert_eq(failed[0]["status"], &"failed")
	assert_eq(failed[0]["reason"], &"invalid_battle_outcome")


func test_disappear_and_appear_update_the_object_event_flag() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6035"] = [0x6F, 2, 0x91]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var world := _world(Vector2i(5, 6))
	var disappeared: Array = world.dispatch_script_events()
	assert_eq(disappeared[0]["status"], &"complete")
	assert_true(world.event_flag_active(7))
	assert_eq(world.visible_objects().size(), 0)

	world.clear_event_flag(7)
	var map: Gen2WorldMap = world.current_map
	map.events["bg_events"][0]["script"] = 0x6035
	var appeared: Array = world.dispatch_script_events(Vector2i(8, 6))
	assert_eq(appeared[0]["status"], &"complete")
	assert_false(world.event_flag_active(7))
	assert_eq(world.visible_objects().size(), 1)


func test_movement_remove_object_is_live_until_the_next_map_reload() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6120": [0x49, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6130": [0x69, 2, 0x20, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6130
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(world.dispatch_script_events()[0]["status"], &"complete")
	assert_eq(world.visible_objects().size(), 0)

	world.reload_current_map()
	assert_eq(world.visible_objects().size(), 1)


func test_change_block_updates_tiles_and_collision_from_the_tileset_block() -> void:
	var world := _world()
	assert_eq(world.block_at(0, 0), 0)
	assert_eq(world.tile_index_at(0, 0), 0)
	assert_eq(world.change_block(0, 0, 1)["ok"], true)
	assert_eq(world.block_at(0, 0), 1)
	assert_eq(world.tile_index_at(0, 0), 16)
	assert_eq(world.collision_code_at(Vector2i(0, 0)), 0x20)
	assert_eq(world.change_block(0, 0, 0)["ok"], true)
	assert_eq(world.collision_code_at(Vector2i(0, 0)), 0)


func test_scripted_change_block_refresh_and_command_queue_state_are_explicit() -> void:
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6140": [0x7A, 0, 0, 1, 0x7C, 0x7D, 0x20, 0x60, 0x7E, 0, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6140
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var result: Array = world.dispatch_script_events()
	assert_eq(result[0]["status"], &"complete")
	assert_eq(world.block_at(0, 0), 1)
	assert_true(result[0]["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"map_refreshed"
	))
	assert_true(world.command_queues().is_empty())
	world.reload_current_map()
	assert_eq(world.block_at(0, 0), 0)


func test_scripted_emote_is_visible_for_its_bounded_duration() -> void:
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6150": [0x75, 1, 2, 2, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6150
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(world.dispatch_script_events()[0]["status"], &"complete")
	var object: Gen2WorldObject = world.objects[0]
	assert_true(object.emote_visible)
	assert_eq(object.emote_id, 1)
	assert_false(world.tick())
	assert_true(world.tick())
	assert_false(object.emote_visible)


func test_surf_movement_accepts_water_and_exposes_an_encounter_request() -> void:
	var world := _world(Vector2i(8, 6))
	assert_true(world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)["ok"])
	var movement: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(movement["ok"])
	assert_eq(movement["kind"], &"water_move")
	assert_eq(world.collision_permission_at(world.player_cell), Gen2WorldCollision.WATER_TILE)
	var encounter: Dictionary = world.encounter_request()
	assert_eq(encounter["kind"], &"wild_encounter_requested")
	assert_eq(encounter["fish_group"], 1)
	assert_eq(encounter["values"]["kind"], &"wild")
	assert_eq(encounter["values"]["pokemon"], 16)
	assert_between(encounter["values"]["level"], 5, 9)
	assert_true(world.move(Vector2i.UP))


func test_explicit_fishing_uses_the_current_map_fish_group() -> void:
	var world := _world(Vector2i(8, 6))
	var encounter: Dictionary = world.encounter_request(
		null, true, Gen2WorldEncounter.METHOD_OLD_ROD
	)
	assert_eq(encounter["source"], Gen2WorldEncounter.SOURCE_FISHING)
	assert_eq(encounter["method"], Gen2WorldEncounter.METHOD_OLD_ROD)
	assert_eq(encounter["fish_group"], 1)
	assert_eq(encounter["values"]["pokemon"], 16)
	assert_eq(encounter["facing_cell"], Vector2i(8, 7))


func test_fishing_requires_a_facing_water_tile_and_not_surfing() -> void:
	var world := _world(Vector2i(8, 6))
	var started: Dictionary = world.fishing_request(
		Gen2WorldEncounter.METHOD_OLD_ROD, null, true
	)
	assert_true(started["ok"])
	assert_eq(started["kind"], &"fishing_started")
	assert_eq(started["state"], Gen2WorldFishing.STATE_CASTING)
	assert_eq(world.fishing_state(), Gen2WorldFishing.STATE_CASTING)

	var bite: Dictionary = world.advance_fishing()
	assert_eq(bite["kind"], &"fishing_bite")
	assert_eq(bite["state"], Gen2WorldFishing.STATE_BITE)
	var battle: Dictionary = world.advance_fishing()
	assert_eq(battle["kind"], &"battle_requested")
	assert_eq(battle["values"]["pokemon"], 16)
	assert_eq(world.fishing_state(), Gen2WorldFishing.STATE_IDLE)

	world.player_facing = Gen2WorldSprite.FACING_LEFT
	var invalid: Dictionary = world.fishing_request(
		Gen2WorldEncounter.METHOD_OLD_ROD, null, true
	)
	assert_false(invalid["ok"])
	assert_eq(invalid["reason"], &"not_facing_water")

	world.player_facing = Gen2WorldSprite.FACING_DOWN
	assert_true(world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)["ok"])
	invalid = world.fishing_request(Gen2WorldEncounter.METHOD_OLD_ROD, null, true)
	assert_false(invalid["ok"])
	assert_eq(invalid["reason"], &"cannot_fish_while_surfing")


func test_fishing_requires_the_matching_inventory_item() -> void:
	var world := _world(Vector2i(8, 6), Gen2WorldState.new())
	var missing: Dictionary = world.fishing_request(
		Gen2WorldEncounter.METHOD_OLD_ROD, null, true
	)
	assert_false(missing["ok"])
	assert_eq(missing["reason"], &"rod_not_owned")
	var added: Dictionary = world.inventory.set_item_quantity(
		Gen2WorldInventory.ITEM_OLD_ROD, 1
	)
	assert_true(added["ok"])
	assert_true(world.available_fishing_rods().has(Gen2WorldEncounter.METHOD_OLD_ROD))
	assert_true(world.fishing_request(
		Gen2WorldEncounter.METHOD_OLD_ROD, null, true
	)["ok"])


func test_inventory_adapter_changes_items_and_currency_atomically() -> void:
	var world := _world(Vector2i(8, 6), Gen2WorldState.new())
	assert_true(world.inventory.set_item_quantity(1, 2)["ok"])
	assert_eq(world.state.item_quantity(1), 2)
	assert_true(world.inventory.change_item_quantity(1, -1)["ok"])
	assert_eq(world.state.item_quantity(1), 1)
	assert_true(world.inventory.set_money(0, 3000)["ok"])
	assert_true(world.inventory.change_money(0, -500)["ok"])
	assert_eq(world.state.money(), 2500)
	assert_true(world.inventory.set_coins(25)["ok"])
	assert_true(world.inventory.change_coins(5)["ok"])
	assert_eq(world.state.coins(), 30)


func test_fishing_cast_can_end_without_a_bite() -> void:
	var fishing := Gen2WorldFishing.new()
	var started: Dictionary = fishing.begin(
		Gen2WorldEncounter.METHOD_OLD_ROD,
		{"chance": 0, "rods": [[{"threshold": 255, "species": 16, "level": 5}], [], []]},
		1, 1, Gen2WorldPalette.TIME_MORNING, [], Vector2i(1, 1), Vector2i(8, 6),
		Gen2WorldSprite.FACING_DOWN, Vector2i(8, 7), Gen2WorldAPI.MOVEMENT_WALK,
	)
	assert_true(started["ok"])
	var result: Dictionary = fishing.advance()
	assert_eq(result["kind"], &"fishing_no_bite")
	assert_eq(fishing.state(), Gen2WorldFishing.STATE_IDLE)


func test_active_swarm_replaces_the_normal_map_record() -> void:
	var world := _world(Vector2i(8, 6))
	world.set_swarm_map(Vector2i(1, 1))
	var encounter: Dictionary = world.encounter_request(
		null, true, Gen2WorldEncounter.METHOD_GRASS
	)
	assert_eq(encounter["source"], Gen2WorldEncounter.SOURCE_SWARM)
	assert_eq(encounter["values"]["pokemon"], 19)


func test_repel_blocks_lower_level_candidates_and_counts_down_on_steps() -> void:
	var world := _world(Vector2i(8, 6))
	world.set_repel_steps(2)
	assert_eq(world.repel_steps(), 2)
	assert_true(world.move(Vector2i.LEFT))
	assert_eq(world.repel_steps(), 1)
	var blocked: Dictionary = world.encounter_request(
		null, true, &"auto", 6
	)
	assert_true(blocked.is_empty())
	var allowed: Dictionary = world.encounter_request(
		null, true, &"auto", 5
	)
	assert_false(allowed.is_empty())
