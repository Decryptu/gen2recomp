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


func _write_cache(game_id: String = "testworld") -> void:
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

	# Ledge fixture, rows 2-4: a plain hop-down at (3,2) with a wall below it
	# and to its left, a hop-down-right at (5,2) with walls right and below,
	# and a hop-right at (14,2) whose landing cell would fall outside the
	# 16-wide grid. Every landing cell is left at its default LAND_TILE.
	collision[2 * 16 + 3] = 0xA3   # COLL_HOP_DOWN
	collision[3 * 16 + 3] = 0x07   # wall below the hop-down cell
	collision[2 * 16 + 2] = 0x07   # wall left of the hop-down cell
	collision[2 * 16 + 5] = 0xA4   # COLL_HOP_DOWN_RIGHT
	collision[2 * 16 + 6] = 0x07   # wall right of the diagonal hop cell
	collision[3 * 16 + 5] = 0x07   # wall below the diagonal hop cell
	collision[2 * 16 + 14] = 0xA0  # COLL_HOP_RIGHT, landing would be x=16
	collision[2 * 16 + 15] = 0x07  # wall right of the edge hop cell
	collision[2 * 16 + 10] = 0x93  # COLL_PC, faced (not stood on) for std scripts

	# Side-wall fixture, row 8: a COLL_RIGHT_WALL/COLL_LEFT_WALL pair at (2,8)
	# and (3,8), matching Celadon Mansion Roof's railing. Both stay LAND_TILE
	# permission; every surrounding cell is left at its default LAND_TILE.
	collision[8 * 16 + 2] = 0xB0  # COLL_RIGHT_WALL
	collision[8 * 16 + 3] = 0xB1  # COLL_LEFT_WALL
	# A COLL_RIGHT_BUOY/COLL_LEFT_BUOY pair at (4,8) and (5,8), both
	# WATER_TILE permission, to check the same rule while surfing.
	collision[8 * 16 + 4] = 0xC0  # COLL_RIGHT_BUOY
	collision[8 * 16 + 5] = 0xC1  # COLL_LEFT_BUOY
	# An isolated COLL_LEFT_WALL at (7,8), approached from open land at
	# (6,8): the enter rule alone, with no leave-rule wall on the standing
	# tile to also block it. This is what the Gold/Silver profile quirk
	# changes: crystal blocks entering from the west, gold does not.
	collision[8 * 16 + 7] = 0xB1  # COLL_LEFT_WALL

	# A lone COLL_UP_WALL at (2,10), matching real Route 42 cliff cells: it
	# blocks stepping off the edge (entering from above, moving DOWN) but not
	# climbing it (moving UP from below), since the enter rule only tests the
	# DOWN handler's opposite-face condition, which COLL_UP_WALL matches.
	collision[10 * 16 + 2] = 0xB2  # COLL_UP_WALL

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
		"48:6050": [0x5D, 16, 5, 0x61, 3, 0x91],
	})
	RomCache.write_json(RomCache.world_standard_scripts_path(_directory), {
		"0": {"bank": 48, "address": 0x6020, "bytes": [0x4C, 0x00, 0x70, 0x91]},
	})
	RomCache.write_json(RomCache.world_text_path(_directory), {
		"48:7000": [0x00, 0x80, 0x81, Gen2WorldScript.TEXT_TERMINATOR],
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
		"game_id": game_id,
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
			"index": 0, "caller_script": {"bank": 48, "address": 0x4234},
			"callee_script": {"bank": 48, "address": 0x5678},
			"callee_time": Gen2WorldPhoneHost.TIME_ANY,
			"caller_time": Gen2WorldPhoneHost.TIME_ANY,
		}],
		"special_calls": [{"index": 0, "condition_kind": "anywhere", "contact": 0,
			"script": {"bank": 48, "address": 0x7000}}],
	})
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:5678"] = [0x4C, 0x00, 0x70, 0x91]
	scripts["48:4234"] = [0x4C, 0x00, 0x70, 0x91]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
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
		"48:6110": [0x94, 0, 0x00, 0x40, 0x91],
		"48:6120": [0x98, 0x34, 0x42, 0x91],
		"48:6130": [0x9C, 0x01, 0x00, 0x91],
		"48:7000": [0x91],
	})
	RomCache.write_json(RomCache.world_text_path(_directory), {
		"48:4234": [Gen2WorldScript.TEXT_START, 0x81, 0x88, 0x8B, 0x8B, Gen2WorldScript.TEXT_TERMINATOR],
	})
	var data: GameData = GameData.open_directory(_directory)
	var cases: Array = [
		{"script": 0x6100, "kind": &"audio_requested", "data_key": "audio", "row_key": "index"},
		{"script": 0x6110, "kind": &"mart_requested", "data_key": "mart", "row_key": "index"},
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

	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6120
	var phone_world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var phone_waiting: Array = phone_world.dispatch_script_events()
	assert_eq(phone_waiting[0]["status"], &"waiting")
	assert_eq(phone_world.pending_runtime_request()["kind"], &"phone_call_requested")
	var phone_complete: Dictionary = Gen2WorldHost.complete_runtime_request(phone_world, {})
	assert_true(phone_complete["ok"])
	assert_eq(phone_complete["data"]["phone_call"]["caller_name"], "BILL")
	assert_eq(phone_complete["results"][0]["status"], &"complete")

	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6130
	var special_world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var special_results: Array = special_world.dispatch_script_events()
	assert_eq(special_results[0]["status"], &"complete")
	assert_eq(special_world.state.pending_special_phone_call(), 1)


func test_phone_ring_runs_before_the_imported_incoming_script() -> void:
	_write_service_cache()
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(7, 6), Gen2WorldState.new({}, {}, {}, {}, 0, {0: true})
	)
	var started: Array = world.request_incoming_phone_call(true, true, 0, true, 0)
	assert_eq(started[0]["status"], &"phone_ring")
	assert_true(world.phone_ring_active())
	assert_true(world.pending_runtime_request().is_empty())
	assert_eq(world.move_result(Vector2i.RIGHT)["reason"], &"phone_ring_active")
	assert_true(world.advance_phone_ring(1.0).is_empty())
	var resumed: Array = world.advance_phone_ring(2.0)
	assert_false(world.phone_ring_active())
	assert_eq(resumed[0]["status"], &"waiting", JSON.stringify(resumed))
	assert_eq(world.pending_script_input()["type"], &"text")


func test_phone_ring_runs_before_the_imported_outgoing_script() -> void:
	_write_service_cache()
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(7, 6), Gen2WorldState.new({}, {}, {}, {}, 0, {0: true})
	)
	var started: Array = world.request_outgoing_phone_call(0)
	assert_eq(started[0]["status"], &"phone_ring")
	assert_eq(started[0]["event"]["kind"], &"phone_outgoing")
	var resumed: Array = world.advance_phone_ring(3.0)
	assert_eq(resumed[0]["status"], &"waiting", JSON.stringify(resumed))
	assert_eq(world.pending_script_input()["type"], &"text")


func test_phone_number_commands_stage_add_check_and_delete_atomically() -> void:
	_write_service_cache()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6200"] = [
		Gen2WorldScript.ADDCELLNUM, 0,
		Gen2WorldScript.CHECKCELLNUM, 0,
		Gen2WorldScript.DELCELLNUM, 0,
		Gen2WorldScript.CHECKCELLNUM, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var map: Gen2WorldMap = data.world_map(1, 1)
	map.events["coord_events"][0]["script"] = 0x6200
	var state := Gen2WorldState.new()
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6), state)
	var results: Array = world.dispatch_script_events()
	assert_eq(results[0]["status"], &"complete", JSON.stringify(results[0]))
	assert_false(state.has_phone_contact(0))
	assert_true(results[0]["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"phone_contact_changed"
	))


func test_phone_number_prompt_uses_source_accept_refuse_and_full_results() -> void:
	_write_service_cache()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# Synthetic caches use the Crystal command table, where askforphonenumber
	# is shifted from the Gold/Silver opcode $96 to $97.
	scripts["48:6210"] = [0x97, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var map: Gen2WorldMap = data.world_map(1, 1)
	map.events["coord_events"][0]["script"] = 0x6210

	var refused_world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(refused_world.dispatch_script_events()[0]["status"], &"waiting")
	var refused: Array = refused_world.choose_script_input(1)
	assert_eq(refused[0]["status"], &"complete")
	assert_eq(_event_value(refused[0]["events"], &"phone_number_result", "result"), 2, JSON.stringify(refused))
	assert_false(refused_world.state.has_phone_contact(0))

	var accepted_world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(accepted_world.dispatch_script_events()[0]["status"], &"waiting")
	var accepted: Array = accepted_world.choose_script_input(0)
	assert_eq(accepted[0]["status"], &"complete")
	assert_eq(_event_value(accepted[0]["events"], &"phone_number_result", "result"), 0, JSON.stringify(accepted))
	assert_true(accepted_world.state.has_phone_contact(0), JSON.stringify(accepted))

	var full_contacts: Dictionary = {}
	for contact: int in Gen2WorldState.PHONE_CONTACT_CAPACITY:
		full_contacts[contact] = true
	var full_state := Gen2WorldState.new({}, {}, {}, {}, 0, full_contacts)
	var full_world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6), full_state)
	assert_eq(full_world.dispatch_script_events()[0]["status"], &"waiting")
	var full: Array = full_world.choose_script_input(0)
	assert_eq(full[0]["status"], &"complete")
	assert_eq(_event_value(full[0]["events"], &"phone_number_result", "result"), 1, JSON.stringify(full))
	assert_eq(full_world.state.phone_contact_count(), Gen2WorldState.PHONE_CONTACT_CAPACITY)


func test_phone_special_ids_match_the_source_phone_routines() -> void:
	_write_service_cache()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6230"] = [
		Gen2WorldScript.SETVAL, 0xD3,
		Gen2WorldScript.SPECIAL, 72, 0,
		Gen2WorldScript.SPECIAL, 91, 0,
		Gen2WorldScript.SPECIAL, 92, 0,
		Gen2WorldScript.SPECIAL, 93, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6230
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var result: Array = world.dispatch_script_events()
	assert_eq(result[0]["status"], &"complete", JSON.stringify(result))
	assert_eq(_event_value(result[0]["events"], &"phone_special_requested", "kind", 0), &"activate_fishing_swarm")
	assert_eq(_event_value(result[0]["events"], &"phone_special_requested", "kind", 1), &"random_unseen_wild_mon")
	assert_eq(_event_value(result[0]["events"], &"phone_special_requested", "kind", 2), &"random_phone_wild_mon")
	assert_eq(_event_value(result[0]["events"], &"phone_special_requested", "kind", 3), &"random_phone_mon")


func test_map_decoration_specials_apply_the_default_room_state() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6250"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_TOGGLE_DECORATIONS_VISIBILITY, 0,
		Gen2WorldScript.ENDCALLBACK,
	]
	scripts["48:6260"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_TOGGLE_MAPTILE_DECORATIONS, 0,
		Gen2WorldScript.ENDCALLBACK,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var map: Gen2WorldMap = data.world_map(1, 1)
	map.scripts["callbacks"] = [
		{"type": 5, "script": 0x6250},
		{"type": 1, "script": 0x6260},
	]
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var result: Array = world.dispatch_map_entry()
	assert_eq(result.size(), 2, JSON.stringify(result))
	for callback_result: Dictionary in result:
		assert_eq(callback_result["status"], &"complete", JSON.stringify(result))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_CONSOLE))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_DOLL_1))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_DOLL_2))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_BIG_DOLL))
	assert_false(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_ROOM_POSTER))
	assert_eq(
		_event_value(result[0]["events"], &"decoration_callback_applied", "kind"),
		&"toggle_decorations_visibility",
		JSON.stringify(result),
	)
	assert_eq(
		_event_value(result[1]["events"], &"decoration_callback_applied", "kind"),
		&"toggle_maptile_decorations",
		JSON.stringify(result),
	)


func test_random_unseen_wild_mon_uses_morning_rare_slots_and_seen_species() -> void:
	_write_service_cache()
	var species: Array = []
	for number: int in 27:
		species.append({"number": number + 1, "name": "MON%d" % (number + 1)})
	RomCache.write_json(RomCache.species_path(_directory), species)
	var phone: Dictionary = RomCache.read_json(RomCache.world_phone_path(_directory))
	phone["contacts"][0]["map_group"] = 1
	phone["contacts"][0]["map_number"] = 1
	RomCache.write_json(RomCache.world_phone_path(_directory), phone)
	var morning: Array = []
	for index: int in RomLayout.WILD_GRASS_SLOT_COUNT:
		morning.append({
			"level": 5,
			"species": 16 if index < 4 else 25 + index - 4,
		})
	var day: Array = morning.duplicate(true)
	var night: Array = morning.duplicate(true)
	RomCache.write_json(RomCache.world_encounters_path(_directory), {
		"grass": {"1:1": {
			"map": "1:1", "rates": [255, 255, 255],
			"slots": [morning, day, night],
		}},
		"water": {}, "fishing": {"groups": [], "time_groups": []},
	})
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6250"] = [Gen2WorldScript.SPECIAL, 91, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var unseen_runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.from_dict({}), {
		"kind": &"phone", "bank": 48, "script": 0x6250,
		"phone": {"caller_id": 0},
	})
	var unseen: Dictionary = unseen_runner.advance()
	assert_eq(unseen["status"], &"complete", JSON.stringify(unseen))
	assert_true(_event_value(
		unseen["events"], &"phone_special_requested", "internal_text"
	))
	assert_between(
		int(_event_value(unseen["events"], &"phone_special_requested", "species")),
		25, 27
	)

	var seen_runner := Gen2WorldScriptRunner.begin(
		data, Gen2WorldState.from_dict({"seen_species": {25: true, 26: true, 27: true}}), {
			"kind": &"phone", "bank": 48, "script": 0x6250,
			"phone": {"caller_id": 0},
		}
	)
	var seen: Dictionary = seen_runner.advance()
	assert_eq(seen["status"], &"complete", JSON.stringify(seen))
	assert_false(_event_value(
		seen["events"], &"phone_special_requested", "internal_text"
	))


func test_script_text_expands_a_source_string_buffer() -> void:
	_write_service_cache()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6240"] = [
		Gen2WorldScript.GETITEMNAME, 8, 0,
		Gen2WorldScript.WRITETEXT, 0, 0x70,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	RomCache.write_json(RomCache.world_text_path(_directory), {
		"48:7000": [Gen2WorldScript.TEXT_START, 0x14, 0, Gen2WorldScript.TEXT_TERMINATOR],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6240
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var waiting: Array = world.dispatch_script_events()
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(world.pending_script_input()["text"], "ITEM7")


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
	assert_eq(Gen2WorldCollision.PERMISSIONS.size(), 256)
	assert_eq(Gen2WorldCollision.permission_for(0x00), Gen2WorldCollision.LAND_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x70), Gen2WorldCollision.LAND_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x20), Gen2WorldCollision.WATER_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x07), Gen2WorldCollision.WALL_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x90), Gen2WorldCollision.WALL_TILE)
	assert_eq(Gen2WorldCollision.permission_for(-1), Gen2WorldCollision.WALL_TILE)
	assert_eq(Gen2WorldCollision.permission_for(0x100), Gen2WorldCollision.WALL_TILE)

	# The waterfall, current and buoy families. Every one of these was ordinary
	# ground before the table was carried whole, so a player walked out to sea
	# and surf refused to enter it.
	for code: int in range(0x30, 0x40):
		assert_eq(
			Gen2WorldCollision.permission_for(code), Gen2WorldCollision.WATER_TILE,
			"$%02X is water" % code
		)
	for code: int in range(0xC0, 0xD0):
		assert_eq(
			Gen2WorldCollision.permission_for(code), Gen2WorldCollision.WATER_TILE,
			"$%02X is water" % code
		)

	# Both headbutt trees and both cut trees block, and the source marks all four
	# as tiles the player can face and press A on.
	for code: int in [0x12, 0x15, 0x1A, 0x1D]:
		assert_eq(
			Gen2WorldCollision.permission_for(code), Gen2WorldCollision.WALL_TILE,
			"$%02X blocks" % code
		)
		assert_true(Gen2WorldCollision.talks(code), "$%02X talks" % code)
	assert_false(Gen2WorldCollision.talks(0x07))

	# Whirlpools and buoys float and talk at once, which is why the TALK bit is
	# masked off rather than compared as part of the permission.
	for code: int in [0x22, 0x24, 0x2A, 0x2C]:
		assert_eq(
			Gen2WorldCollision.permission_for(code), Gen2WorldCollision.WATER_TILE,
			"$%02X is water" % code
		)
		assert_true(Gen2WorldCollision.talks(code), "$%02X talks" % code)


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


func test_player_walks_onto_a_ledge_cell_as_ordinary_land() -> void:
	# Hop codes are LAND_TILE, so entering one is an ordinary step, not a hop.
	var world: Gen2WorldAPI = _world(Vector2i(3, 1))
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(result["ok"])
	assert_eq(result["kind"], &"move")
	assert_eq(world.player_cell, Vector2i(3, 2))


func test_ledge_hop_crosses_two_cells_after_an_ordinary_step_is_blocked() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(3, 2))
	world.set_repel_steps(2)
	assert_false(world.can_walk_to(Vector2i(3, 3)))
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(result["kind"], &"ledge_hop")
	assert_eq(result["from_cell"], Vector2i(3, 2))
	assert_eq(result["to_cell"], Vector2i(3, 4))
	assert_eq(world.player_cell, Vector2i(3, 4))
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_DOWN)
	assert_eq(world.repel_steps(), 1)

	# The presentation offset starts two cells behind and eases to zero over
	# STEP_FRAMES_HOP frames, the same generic step system a one-cell walk
	# uses with a magnitude-2 direction.
	assert_true(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2(0, -2))
	for _tick: int in 4:
		world.advance_player_step(1000.0)
	assert_false(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2.ZERO)


func test_ledge_hop_refuses_a_direction_the_code_does_not_allow() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(3, 2))
	assert_false(world.can_walk_to(Vector2i(2, 2)))
	var result: Dictionary = world.move_result(Vector2i.LEFT)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"blocked")
	assert_eq(world.player_cell, Vector2i(3, 2))


func test_diagonal_ledge_hop_allows_both_of_its_directions() -> void:
	var right_world: Gen2WorldAPI = _world(Vector2i(5, 2))
	var right_result: Dictionary = right_world.move_result(Vector2i.RIGHT)
	assert_true(right_result["ok"], JSON.stringify(right_result))
	assert_eq(right_result["kind"], &"ledge_hop")
	assert_eq(right_world.player_cell, Vector2i(7, 2))

	var down_world: Gen2WorldAPI = _world(Vector2i(5, 2))
	var down_result: Dictionary = down_world.move_result(Vector2i.DOWN)
	assert_true(down_result["ok"], JSON.stringify(down_result))
	assert_eq(down_result["kind"], &"ledge_hop")
	assert_eq(down_world.player_cell, Vector2i(5, 4))


func test_ledge_hop_refuses_a_landing_cell_outside_the_map() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(14, 2))
	assert_false(world.can_walk_to(Vector2i(15, 2)))
	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"blocked")
	assert_eq(world.player_cell, Vector2i(14, 2))


func test_ledge_hop_never_fires_while_surfing() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(3, 2))
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"blocked")
	assert_eq(world.player_cell, Vector2i(3, 2))


func test_side_wall_blocks_leaving_the_standing_tile_only_in_its_own_direction() -> void:
	# (2,8) is COLL_RIGHT_WALL, land permission on every side.
	var world: Gen2WorldAPI = _world(Vector2i(2, 8))
	var right: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_false(right["ok"], JSON.stringify(right))
	assert_eq(right["reason"], &"blocked")
	assert_eq(world.player_cell, Vector2i(2, 8))

	assert_true(world.move_result(Vector2i.UP)["ok"])
	assert_eq(world.player_cell, Vector2i(2, 7))


func test_side_wall_does_not_block_entering_from_the_far_side() -> void:
	# COLL_RIGHT_WALL only walls its own right edge; entering it from the
	# west is an ordinary step, matching the mansion-roof railing you can
	# walk up to but not cross.
	var world: Gen2WorldAPI = _world(Vector2i(1, 8))
	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(world.player_cell, Vector2i(2, 8))


func test_side_wall_pair_blocks_crossing_from_either_side() -> void:
	# COLL_RIGHT_WALL at (2,8) and COLL_LEFT_WALL at (3,8) form a fence
	# neither tile can cross into the other, though both are LAND_TILE.
	var from_right_wall: Gen2WorldAPI = _world(Vector2i(2, 8))
	var blocked_right: Dictionary = from_right_wall.move_result(Vector2i.RIGHT)
	assert_false(blocked_right["ok"])
	assert_eq(blocked_right["reason"], &"blocked")

	var from_left_wall: Gen2WorldAPI = _world(Vector2i(3, 8))
	var blocked_left: Dictionary = from_left_wall.move_result(Vector2i.LEFT)
	assert_false(blocked_left["ok"])
	assert_eq(blocked_left["reason"], &"blocked")


func test_side_wall_blocks_surfing_the_same_way_as_walking() -> void:
	# COLL_RIGHT_BUOY at (4,8) and COLL_LEFT_BUOY at (5,8) are WATER_TILE
	# permission, gated by the same wTilePermissions AND as land.
	var world: Gen2WorldAPI = _world(Vector2i(4, 8))
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.collision_permission_at(Vector2i(4, 8)), Gen2WorldCollision.WATER_TILE)
	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_false(result["ok"], JSON.stringify(result))
	assert_eq(result["reason"], &"blocked")
	assert_eq(world.player_cell, Vector2i(4, 8))


func test_can_walk_to_with_no_direction_ignores_side_walls() -> void:
	# The position-only form (Vector2i.ZERO) keeps answering the destination's
	# plain permission, matching every existing tool and test call site that
	# does not go through move_result().
	var world: Gen2WorldAPI = _world(Vector2i(2, 8))
	assert_true(world.can_walk_to(Vector2i(3, 8)))
	assert_true(world.can_walk_to(Vector2i(2, 8), Vector2i.ZERO))


func test_up_wall_blocks_stepping_off_the_edge_but_not_climbing_it() -> void:
	# (2,10) is COLL_UP_WALL: matches every real $b2 cell in the pinned
	# caches, which blocks entering from above (walking off a cliff) while
	# leaving the approach from below (climbing it) open, since the enter
	# rule for COLL_UP_WALL only feeds the DOWN handler.
	var from_above: Gen2WorldAPI = _world(Vector2i(2, 9))
	var stepped_off: Dictionary = from_above.move_result(Vector2i.DOWN)
	assert_false(stepped_off["ok"], JSON.stringify(stepped_off))
	assert_eq(stepped_off["reason"], &"blocked")

	var from_below: Gen2WorldAPI = _world(Vector2i(2, 11))
	var climbed: Dictionary = from_below.move_result(Vector2i.UP)
	assert_true(climbed["ok"], JSON.stringify(climbed))
	assert_eq(from_below.player_cell, Vector2i(2, 10))


func test_side_wall_enter_rule_blocks_crystal_from_the_isolated_wall() -> void:
	# (7,8) is a lone COLL_LEFT_WALL with open land to its west at (6,8), so
	# only the enter rule can be responsible for any block here.
	var world: Gen2WorldAPI = _world(Vector2i(6, 8))
	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_false(result["ok"], JSON.stringify(result))
	assert_eq(result["reason"], &"blocked")


func test_side_wall_gold_profile_enter_rule_only_blocks_down() -> void:
	# pokegold's .ok_right sets bit RIGHT, numerically FACE_DOWN rather than
	# FACE_RIGHT (wFacingDirection and wWalkingDirection use transposed bit
	# layouts), so the same isolated COLL_LEFT_WALL that blocks Crystal above
	# does not block Gold/Silver: the bit it sets is irrelevant to a RIGHT
	# move. No shipped Gold/Silver map has a code that reaches this branch;
	# this pins the source's own quirk for a mod-authored one.
	var gold_directory: String = RomCache.directory_for(&"testworldgold", "abcdef0123456789ab")
	RomCache.clear(gold_directory)
	RomCache.prepare(gold_directory)
	var saved_directory: String = _directory
	_directory = gold_directory
	_write_cache("gold")
	_directory = saved_directory

	var data: GameData = GameData.open_directory(gold_directory)
	assert_eq(data.id, &"gold")
	assert_false(Gen2WorldState.is_crystal_profile(data))
	var state: Gen2WorldState = Gen2WorldState.new({}, {}, {Gen2WorldInventory.ITEM_OLD_ROD: 1})
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(6, 8), state)

	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(world.player_cell, Vector2i(7, 8))

	RomCache.clear(gold_directory)


func test_interact_dispatches_a_tile_collision_std_script_when_nothing_else_answers() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6900"] = [Gen2WorldScript.SETSCENE, 90, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var standard_scripts: Dictionary = RomCache.read_json(
		RomCache.world_standard_scripts_path(_directory)
	)
	standard_scripts["49"] = {"bank": 48, "address": 0x6900, "bytes": [
		Gen2WorldScript.SETSCENE, 90, Gen2WorldScript.END,
	]}
	RomCache.write_json(RomCache.world_standard_scripts_path(_directory), standard_scripts)

	# Faces the COLL_PC cell at (10,2) from below; nothing else is registered
	# at that cell, so TryTileCollisionEvent is the only stage that can answer.
	var world: Gen2WorldAPI = _world(Vector2i(10, 3))
	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_true(world.state.map_scene(1, 1) != 90)
	var results: Array = world.interact()
	assert_false(results.is_empty())
	assert_eq(results[0]["status"], &"complete", JSON.stringify(results[0]))
	assert_eq(world.state.map_scene(1, 1), 90)


func test_interact_finds_no_tile_collision_script_for_an_untabled_code() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	assert_eq(world.collision_code_at(world.facing_cell()), 0)
	assert_eq(world.interact(), [])


func test_tile_collision_std_index_is_profile_split_for_pc_only() -> void:
	assert_eq(
		Gen2WorldCollision.tile_collision_std_index(Gen2WorldCollision.COLL_PC, true), 49
	)
	assert_eq(
		Gen2WorldCollision.tile_collision_std_index(Gen2WorldCollision.COLL_PC, false), 43
	)
	for code: int in [
		Gen2WorldCollision.COLL_BOOKSHELF, Gen2WorldCollision.COLL_RADIO,
		Gen2WorldCollision.COLL_TOWN_MAP, Gen2WorldCollision.COLL_MART_SHELF,
		Gen2WorldCollision.COLL_TV, Gen2WorldCollision.COLL_WINDOW,
		Gen2WorldCollision.COLL_INCENSE_BURNER,
	]:
		assert_eq(
			Gen2WorldCollision.tile_collision_std_index(code, true),
			Gen2WorldCollision.tile_collision_std_index(code, false),
			"$%02X is not profile-split" % code
		)
	assert_eq(Gen2WorldCollision.tile_collision_std_index(0x00, true), -1)


func test_interact_dispatches_the_gold_silver_pc_index_under_that_profile() -> void:
	# Gold/Silver's raw command stream is not Crystal's shifted by one: END is
	# $90 there, not Crystal's $91 (Gen2WorldScript.raw_opcode/GOLD_END).
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6910"] = [Gen2WorldScript.SETSCENE, 91, Gen2WorldScript.GOLD_END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var standard_scripts: Dictionary = RomCache.read_json(
		RomCache.world_standard_scripts_path(_directory)
	)
	standard_scripts["43"] = {"bank": 48, "address": 0x6910, "bytes": [
		Gen2WorldScript.SETSCENE, 91, Gen2WorldScript.GOLD_END,
	]}
	RomCache.write_json(RomCache.world_standard_scripts_path(_directory), standard_scripts)
	var manifest: Dictionary = RomCache.read_json(RomCache.manifest_path(_directory))
	manifest["game_id"] = "gold"
	RomCache.write_json(RomCache.manifest_path(_directory), manifest)

	var data: GameData = GameData.open_directory(_directory)
	assert_false(Gen2WorldState.is_crystal_profile(data))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(10, 3), Gen2WorldState.new()
	)
	world.player_facing = Gen2WorldSprite.FACING_UP
	var results: Array = world.interact()
	assert_false(results.is_empty())
	assert_eq(results[0]["status"], &"complete", JSON.stringify(results[0]))
	assert_eq(world.state.map_scene(1, 1), 91)


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


func test_trainer_approach_path_uses_the_source_longer_axis_first() -> void:
	assert_eq(
		Gen2WorldAPI.trainer_approach_path(Vector2i(1, 1), Vector2i(4, 3)),
		[Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.DOWN]
	)
	assert_eq(
		Gen2WorldAPI.trainer_approach_path(Vector2i(4, 4), Vector2i(2, 1)),
		[Vector2i.UP, Vector2i.UP, Vector2i.UP, Vector2i.LEFT, Vector2i.LEFT]
	)
	assert_eq(
		Gen2WorldAPI.trainer_approach_path(Vector2i(1, 1), Vector2i(3, 3)),
		[Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.DOWN]
	)


func test_player_walk_step_starts_a_cell_behind_and_never_moves_the_committed_cell() -> void:
	var world: Gen2WorldAPI = _world()
	assert_false(world.player_step_in_progress())
	assert_true(world.move(Vector2i.LEFT))
	# The logical cell already committed to the destination; the step only
	# paces a presentation offset that starts a full cell behind it.
	assert_eq(world.player_cell, Vector2i(7, 6))
	assert_true(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2(1.0, 0.0))
	assert_eq(
		world.player_pixel_position(),
		world.player_view_cell() * Gen2WorldAPI.CELL_PIXELS + Vector2i(16, 0)
	)


func test_the_interpolated_camera_origin_does_not_pan_a_step_early() -> void:
	var world: Gen2WorldAPI = _world()
	# Standing still, the hardware page origin and the camera agree.
	assert_eq(world.player_position_cells(), Vector2(8.0, 6.0))
	assert_eq(world.visible_origin_cell(), Vector2i(3, 2))
	assert_eq(world.visible_origin_cells(), Vector2(3.0, 2.0))

	assert_true(world.move(Vector2i.LEFT))
	# The page origin follows the committed cell, so it moves at once. The player
	# has not visibly left the old cell yet, and the camera stays with them.
	assert_eq(world.visible_origin_cell(), Vector2i(2, 2))
	assert_eq(world.player_position_cells(), Vector2(8.0, 6.0))
	assert_eq(world.visible_origin_cells(), Vector2(3.0, 2.0))

	assert_true(world.advance_player_step(Gen2WorldAnimation.FRAME_SECONDS))
	assert_eq(world.player_position_cells(), Vector2(7.875, 6.0))
	assert_eq(world.visible_origin_cells(), Vector2(2.875, 2.0))

	# The step lands on the committed cell, where the two agree again.
	assert_true(world.advance_player_step(1000.0))
	assert_true(world.advance_player_step(Gen2WorldAnimation.FRAME_SECONDS * 3.0))
	assert_false(world.player_step_in_progress())
	assert_eq(world.player_position_cells(), Vector2(7.0, 6.0))
	assert_eq(world.visible_origin_cells(), Vector2(world.visible_origin_cell()))


func test_the_interpolated_camera_origin_clamps_to_the_map_like_the_page_does() -> void:
	var corner: Gen2WorldAPI = _world(Vector2i(15, 11))
	assert_eq(corner.visible_origin_cell(), Vector2i(6, 3))
	assert_eq(corner.visible_origin_cells(), Vector2(6.0, 3.0))
	var top_left: Gen2WorldAPI = _world(Vector2i.ZERO)
	assert_eq(top_left.visible_origin_cells(), Vector2.ZERO)


func test_advance_player_step_consumes_hardware_frames_and_caps_catchup() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(world.move(Vector2i.LEFT))
	assert_eq(world.player_cell, Vector2i(7, 6))

	assert_true(world.advance_player_step(Gen2WorldAnimation.FRAME_SECONDS))
	assert_eq(world.player_step_offset_cells(), Vector2(0.875, 0.0))

	# A huge delta advances at most Gen2WorldAnimation.MAX_CATCHUP_FRAMES
	# hardware frames per call, the same stall cap the tile animation uses, so
	# a pause drops step frames instead of snapping the sprite to its
	# destination. STEP_FRAMES_WALK is 8: one frame already consumed above,
	# four more are capped here, leaving three of eight.
	assert_true(world.advance_player_step(1000.0))
	assert_eq(world.player_step_offset_cells(), Vector2(3.0 / 8.0, 0.0))
	assert_eq(world.player_cell, Vector2i(7, 6))

	assert_true(world.advance_player_step(Gen2WorldAnimation.FRAME_SECONDS * 3.0))
	assert_false(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2.ZERO)
	assert_eq(world.player_cell, Vector2i(7, 6))
	assert_false(world.advance_player_step(1.0))


func test_player_step_does_not_affect_cell_collision_or_events() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(world.move(Vector2i.LEFT))
	assert_eq(world.player_cell, Vector2i(7, 6))
	assert_true(world.player_step_in_progress())
	var during_events: Array = world.dispatch_events()
	var during_permission: int = world.collision_permission_at(world.player_cell)
	var during_walkable: bool = world.can_walk_to(Vector2i(6, 6))

	assert_true(world.advance_player_step(1000.0))
	assert_true(world.advance_player_step(1000.0))
	assert_false(world.player_step_in_progress())

	# A presentation offset in flight never changes what resolves off the
	# already-committed cell.
	assert_eq(world.dispatch_events(), during_events)
	assert_eq(world.collision_permission_at(world.player_cell), during_permission)
	assert_eq(world.can_walk_to(Vector2i(6, 6)), during_walkable)
	assert_eq(world.player_cell, Vector2i(7, 6))


func test_player_step_clears_on_connection_transition() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(14, 6))
	assert_true(world.move(Vector2i.RIGHT))
	assert_eq(world.player_cell, Vector2i(15, 6))
	assert_true(world.player_step_in_progress())

	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_true(result["ok"])
	assert_eq(result["kind"], &"connection")
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_false(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2.ZERO)


func test_player_step_clears_on_warp() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(7, 6))
	assert_true(world.move(Vector2i.LEFT))
	assert_eq(world.player_cell, Vector2i(6, 6))
	assert_true(world.player_step_in_progress())

	var result: Dictionary = world.try_warp()
	assert_true(result["ok"])
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_false(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2.ZERO)


func test_snapshot_ignores_transient_player_step() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(world.move(Vector2i.LEFT))
	assert_true(world.player_step_in_progress())
	var mid_step: Dictionary = world.snapshot().to_dict()

	assert_true(world.advance_player_step(1000.0))
	assert_true(world.advance_player_step(1000.0))
	assert_false(world.player_step_in_progress())
	var finished: Dictionary = world.snapshot().to_dict()

	# The snapshot is identical whether captured mid-step or after it
	# finishes: nothing about the transient offset reaches it.
	assert_eq(mid_step, finished)

	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(
		GameData.open_directory(_directory), world.snapshot()
	)
	assert_not_null(restored)
	assert_false(restored.player_step_in_progress())
	assert_eq(restored.player_cell, Vector2i(7, 6))


## The fixture's single object stands still. These tests hand it a wandering
## template so the data-driven driver has something to decide about.
func _wandering_world(
	movement: int = Gen2WorldObject.MOVEMENT_WANDER, x_radius: int = 2, y_radius: int = 2,
	start: Vector2i = Vector2i(12, 10)
) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = _world(start)
	var object: Gen2WorldObject = world.objects[0]
	object.movement = movement
	object.x_radius = x_radius
	object.y_radius = y_radius
	return world


func _advance_object_frames(
	world: Gen2WorldAPI, frames: int, random: RandomNumberGenerator
) -> void:
	for _frame: int in frames:
		world.advance_object_steps(Gen2WorldAnimation.FRAME_SECONDS, random)


func test_wander_object_commits_its_cell_and_eases_over_the_slow_step() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 90210
	var start: Vector2i = object.cell

	# The first frame is the object's turn at the movement function.
	assert_true(world.advance_object_steps(Gen2WorldAnimation.FRAME_SECONDS, random))
	assert_true(object.is_stepping())
	# StepVectors' slow row is 16 frames, half the player's walking speed.
	assert_eq(object.step_frames_total, Gen2WorldAPI.STEP_FRAMES_NPC_WALK)
	# The cell commits when the step starts, exactly as InitStep and the
	# player's own walk do; only the drawn offset trails behind it.
	assert_ne(object.cell, start)
	assert_eq(object.step_offset_cells(), Vector2(start - object.cell))

	# The deciding frame starts the step without spending one of its frames,
	# the way the source runs the movement function and the step function on
	# separate frames, so the full duration follows it.
	_advance_object_frames(world, Gen2WorldAPI.STEP_FRAMES_NPC_WALK, random)
	assert_false(object.is_stepping())
	assert_eq(object.step_offset_cells(), Vector2.ZERO)
	assert_eq(abs(object.cell.x - start.x) + abs(object.cell.y - start.y), 1)


func test_wander_object_waits_its_rolled_idle_before_deciding_again() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 4242

	_advance_object_frames(world, 1 + Gen2WorldAPI.STEP_FRAMES_NPC_WALK, random)
	assert_false(object.is_stepping())
	# The step's final frame rolls the next wait, exactly as
	# StepFunction_ContinueWalk jumps to RandomStepDuration_Slow. That mask is
	# $7F, so the wait never exceeds 127 frames.
	assert_true(object.is_idle())
	assert_true(object.idle_frames_remaining <= Gen2WorldAPI.IDLE_MASK_SLOW)

	var resting_cell: Vector2i = object.cell
	var idle_frames: int = object.idle_frames_remaining
	_advance_object_frames(world, idle_frames, random)
	assert_eq(object.cell, resting_cell)
	assert_false(object.is_idle())


func test_blocked_wander_object_keeps_its_cell_and_waits() -> void:
	# A radius of zero leaves every neighbouring cell outside the object's
	# bounds, which is the source's blocked branch.
	var world: Gen2WorldAPI = _wandering_world(Gen2WorldObject.MOVEMENT_WANDER, 0, 0)
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 77
	var start: Vector2i = object.cell

	assert_false(world.advance_object_steps(Gen2WorldAnimation.FRAME_SECONDS, random))
	assert_eq(object.cell, start)
	assert_false(object.is_stepping())
	# _RandomWalkContinue's .new_duration branch waits again rather than
	# retrying a direction on the very next frame.
	assert_true(object.is_idle())

	_advance_object_frames(world, 400, random)
	assert_eq(object.cell, start)


func test_wander_object_never_leaves_its_source_radius() -> void:
	var world: Gen2WorldAPI = _wandering_world(Gen2WorldObject.MOVEMENT_WANDER, 1, 1)
	var object: Gen2WorldObject = world.objects[0]
	var origin: Vector2i = object.initial_cell
	var random := RandomNumberGenerator.new()
	random.seed = 31337

	var strayed: Vector2i = Vector2i.MAX
	var visited: Dictionary = {}
	for _frame: int in 2000:
		world.advance_object_steps(Gen2WorldAnimation.FRAME_SECONDS, random)
		visited[object.cell] = true
		if abs(object.cell.x - origin.x) > 1 or abs(object.cell.y - origin.y) > 1:
			strayed = object.cell
			break
	assert_eq(strayed, Vector2i.MAX, "object left its radius")
	# The same run has to prove the object actually wandered, or a driver that
	# never moved anything would pass the bound above.
	assert_gt(visited.size(), 1, "object never moved")


func test_spin_templates_turn_without_starting_a_step() -> void:
	for movement: int in [
		Gen2WorldObject.MOVEMENT_SPINRANDOM_SLOW, Gen2WorldObject.MOVEMENT_SPINRANDOM_FAST,
	]:
		var world: Gen2WorldAPI = _wandering_world(movement)
		var object: Gen2WorldObject = world.objects[0]
		var random := RandomNumberGenerator.new()
		random.seed = 8
		var start: Vector2i = object.cell

		_advance_object_frames(world, 200, random)
		# MovementFunction_RandomSpinSlow and _Fast set a facing and wait; they
		# never call InitStep, so a spinning object has no step to interpolate.
		assert_eq(object.cell, start)
		assert_false(object.is_stepping())
		var mask: int = Gen2WorldAPI.IDLE_MASK_SLOW \
			if movement == Gen2WorldObject.MOVEMENT_SPINRANDOM_SLOW else Gen2WorldAPI.IDLE_MASK_FAST
		assert_true(object.idle_frames_remaining <= mask)


func test_standing_objects_are_never_moved_by_the_driver() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(12, 10))
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 5
	var start: Vector2i = object.cell
	var facing: int = object.facing

	for _frame: int in 300:
		assert_false(world.advance_object_steps(Gen2WorldAnimation.FRAME_SECONDS, random))
	assert_eq(object.cell, start)
	assert_eq(object.facing, facing)


func test_object_driver_caps_catchup_after_a_stall() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 90210

	assert_true(world.advance_object_steps(Gen2WorldAnimation.FRAME_SECONDS, random))
	assert_eq(object.step_frames_remaining, Gen2WorldAPI.STEP_FRAMES_NPC_WALK)
	# A huge delta spends at most MAX_CATCHUP_FRAMES frames, the same stall cap
	# the tile animation and the player's walk step use.
	assert_true(world.advance_object_steps(1000.0, random))
	assert_eq(
		object.step_frames_remaining,
		Gen2WorldAPI.STEP_FRAMES_NPC_WALK - Gen2WorldAnimation.MAX_CATCHUP_FRAMES
	)


func test_object_steps_do_not_survive_a_map_transition() -> void:
	var world: Gen2WorldAPI = _wandering_world(
		Gen2WorldObject.MOVEMENT_WANDER, 2, 2, Vector2i(6, 6)
	)
	var random := RandomNumberGenerator.new()
	random.seed = 90210
	var object: Gen2WorldObject = world.objects[0]
	# The player stands on the warp beside this object, so its first rolled
	# direction may be blocked. Run until a step is genuinely in flight.
	for _frame: int in 600:
		if object.is_stepping():
			break
		world.advance_object_steps(Gen2WorldAnimation.FRAME_SECONDS, random)
	assert_true(object.is_stepping())

	var result: Dictionary = world.try_warp()
	assert_true(result["ok"])
	assert_eq(world.map_id(), Vector2i(1, 2))
	for loaded: Gen2WorldObject in world.objects:
		assert_false(loaded.is_stepping())
		assert_eq(loaded.step_offset_cells(), Vector2.ZERO)


func test_object_movement_does_not_disturb_the_other_random_streams() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var script_random := RandomNumberGenerator.new()
	script_random.seed = 1000
	world.script_random = script_random
	var schedule_random := RandomNumberGenerator.new()
	schedule_random.seed = 2000
	world.schedule_random = schedule_random

	var object_random := RandomNumberGenerator.new()
	object_random.seed = 3000
	_advance_object_frames(world, 500, object_random)

	# Watching an NPC wander for hundreds of frames must not shift the next
	# encounter, phone or script roll by a single draw.
	var expected_script := RandomNumberGenerator.new()
	expected_script.seed = 1000
	assert_eq(script_random.randi(), expected_script.randi())
	var expected_schedule := RandomNumberGenerator.new()
	expected_schedule.seed = 2000
	assert_eq(schedule_random.randi(), expected_schedule.randi())


func test_object_driver_ignores_a_missing_generator() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var object: Gen2WorldObject = world.objects[0]
	var start: Vector2i = object.cell
	assert_false(world.advance_object_steps(Gen2WorldAnimation.FRAME_SECONDS, null))
	assert_eq(object.cell, start)
	assert_false(object.is_stepping())


func test_advance_objects_still_makes_one_decision_per_call() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 90210
	var start: Vector2i = object.cell

	# The existing per-call primitive keeps its contract: one decision, one
	# committed cell, with no frame pacing involved.
	assert_eq(world.advance_objects(random), 1)
	assert_eq(abs(object.cell.x - start.x) + abs(object.cell.y - start.y), 1)


func test_follower_carries_the_player_walk_step_offset() -> void:
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6080": [0x70, 2, 0, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6080
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))
	assert_eq(world.dispatch_script_events(Vector2i(7, 6))[0]["status"], &"complete")
	assert_true(world.move(Vector2i.LEFT))

	var follower: Gen2WorldObject = world.objects[0]
	assert_eq(follower.cell, Vector2i(6, 6))
	# A follower keeps the player's pace, not the slower wandering one.
	assert_true(follower.is_stepping())
	assert_eq(follower.step_frames_total, Gen2WorldAPI.STEP_FRAMES_WALK)
	# The follower moved right, into the cell the player left, so it is drawn
	# one cell to the left of its committed cell as the step begins.
	assert_eq(follower.step_offset_cells(), Vector2(-1.0, 0.0))


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


func test_map_entry_dispatch_runs_the_current_map_callbacks() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var result: Array = world.dispatch_map_entry()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["source"]["kind"], &"callback")
	assert_eq(world.state.map_scene(1, 1), 2)


func test_map_entry_runs_the_default_scene_and_coordinate_events_follow_scene_state() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6050"] = [Gen2WorldScript.SETEVENT, 13, 0, Gen2WorldScript.END]
	scripts["48:6060"] = [Gen2WorldScript.SETEVENT, 14, 0, Gen2WorldScript.END]
	scripts["48:6070"] = [Gen2WorldScript.SETEVENT, 15, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var target_map: Gen2WorldMap = data.world_map(1, 2)
	target_map.scripts["callbacks"] = []
	target_map.scripts["scenes"] = [{"id": 0, "script": 0x6050}]
	var target: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 2, Vector2i(2, 2))
	var entry: Array = target.dispatch_map_entry()
	assert_eq(entry.size(), 1)
	assert_eq(entry[0]["source"]["kind"], &"scene")
	assert_true(target.event_flag_active(13))
	assert_eq(target.state.map_scene(1, 2), 0)

	var source_map: Gen2WorldMap = data.world_map(1, 1)
	source_map.scripts["scenes"] = [
		{"id": 0, "script": 0x6060}, {"id": 1, "script": 0x6060},
	]
	source_map.events["coord_events"] = [
		{"scene": 1, "x": 7, "y": 6, "script": 0x6070},
	]
	var default_scene: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(default_scene.dispatch_script_events().size(), 0)
	var scene_one_state := Gen2WorldState.new({}, {"1:1": 1})
	var scene_one: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(7, 6), scene_one_state
	)
	var active: Array = scene_one.dispatch_script_events()
	assert_eq(active.size(), 1)
	assert_true(scene_one.event_flag_active(15))


func test_script_requests_supply_the_live_player_facing_to_readvar() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6080"] = [
		Gen2WorldScript.READVAR, 0x09,
		Gen2WorldScript.IFEQUAL, Gen2WorldSprite.FACING_RIGHT, 0x90, 0x60,
		Gen2WorldScript.END,
	]
	scripts["48:6090"] = [Gen2WorldScript.SETEVENT, 22, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.current_map.events["coord_events"][0]["script"] = 0x6080
	world.player_facing = Gen2WorldSprite.FACING_RIGHT
	var result: Array = world.dispatch_script_events()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete")
	assert_true(world.event_flag_active(22))


func test_facing_interaction_commits_map_and_engine_flags_after_text() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6160"] = [
		Gen2WorldScript.WRITETEXT, 0x00, 0x70,
		Gen2WorldScript.SETEVENT, 7, 0,
		Gen2WorldScript.SETFLAG, Gen2WorldState.ENGINE_HALL_OF_FAME, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(6, 6))
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	world.current_map.events["objects"][0]["script"] = 0x6160
	(world.objects[0] as Gen2WorldObject).event_script = 0x6160

	var waiting: Array = world.interact()
	assert_eq(waiting.size(), 1)
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(waiting[0]["event"]["text"], "AB")
	assert_false(world.event_flag_active(7))
	assert_false(world.state.hall_of_fame())

	var completed: Array = world.run_event_queue(true)
	assert_eq(completed.size(), 1)
	assert_eq(completed[0]["status"], &"complete")
	assert_true(world.event_flag_active(7))
	assert_true(world.state.hall_of_fame())
	assert_eq(world.visible_objects().size(), 0)

	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(data, world.snapshot())
	assert_not_null(restored)
	assert_true(restored.event_flag_active(7))
	assert_true(restored.state.hall_of_fame())
	assert_eq(restored.visible_objects().size(), 0)


func test_background_events_honor_source_direction_and_conditional_pointer_records() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6170"] = [Gen2WorldScript.SETEVENT, 11, 0, Gen2WorldScript.END]
	scripts["48:6180"] = [12, 0, 0x70, 0x61]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))
	world.current_map.events["bg_events"] = [
		{"x": 9, "y": 6, "type": Gen2WorldAPI.BGEVENT_RIGHT, "script": 0x6170},
		{"x": 8, "y": 5, "type": Gen2WorldAPI.BGEVENT_IFSET, "script": 0x6180},
	]

	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_true(world.interact().is_empty())
	world.player_facing = Gen2WorldSprite.FACING_RIGHT
	var direct: Array = world.interact()
	assert_eq(direct.size(), 1)
	assert_eq(direct[0]["status"], &"complete")
	assert_true(world.event_flag_active(11))

	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(world.dispatch_events(Vector2i(8, 5)).size(), 0)
	world.set_event_flag(12)
	assert_eq(world.dispatch_events(Vector2i(8, 5)).size(), 1)
	var conditional: Array = world.dispatch_script_events(Vector2i(8, 5))
	assert_eq(conditional.size(), 1)
	assert_true(world.event_flag_active(11))


func test_players_house_pc_special_is_a_host_request_and_returns_false_without_decoration_changes() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6190"] = [Gen2WorldScript.SPECIAL, 29, 0, Gen2WorldScript.IFTRUE, 0x99, 0x61, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.current_map.events["coord_events"][0]["script"] = 0x6190
	var waiting: Array = world.dispatch_script_events()
	assert_eq(waiting.size(), 1)
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(world.pending_runtime_request()["kind"], &"pc_requested")

	var resumed: Array = world.complete_runtime_request({"ok": true, "script_value": 0})
	assert_eq(resumed.size(), 1)
	assert_eq(resumed[0]["status"], &"complete")
	assert_true(world.pending_runtime_request().is_empty())


func test_pokemon_center_pc_special_stages_the_pokemon_center_mode() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6195"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_POKEMON_CENTER_PC, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.current_map.events["coord_events"][0]["script"] = 0x6195
	var waiting: Array = world.dispatch_script_events()
	assert_eq(waiting.size(), 1)
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(world.pending_runtime_request()["kind"], &"pc_requested")
	assert_eq(world.pending_runtime_request()["values"]["mode"], &"pokemon_center")

	var resumed: Array = world.complete_runtime_request({"ok": true, "script_value": 0})
	assert_eq(resumed.size(), 1)
	assert_eq(resumed[0]["status"], &"complete")


func test_readvar_badges_counts_active_engine_flags_across_both_bytes() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6300"] = [
		Gen2WorldScript.READVAR, 0x07,
		Gen2WorldScript.IFEQUAL, 1, 0x10, 0x63,
		Gen2WorldScript.END,
	]
	scripts["48:6310"] = [Gen2WorldScript.SETEVENT, 40, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.state.set_engine_flag(Gen2WorldState.ENGINE_ZEPHYRBADGE)
	world.current_map.events["coord_events"][0]["script"] = 0x6300
	var result: Array = world.dispatch_script_events()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete", JSON.stringify(result))
	assert_true(world.event_flag_active(40))


func test_readvar_partycount_reads_the_set_party_summary() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6320"] = [
		Gen2WorldScript.READVAR, 0x01,
		Gen2WorldScript.IFEQUAL, 2, 0x30, 0x63,
		Gen2WorldScript.END,
	]
	scripts["48:6330"] = [Gen2WorldScript.SETEVENT, 41, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.set_party_summary(2, false)
	world.current_map.events["coord_events"][0]["script"] = 0x6320
	var result: Array = world.dispatch_script_events()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete", JSON.stringify(result))
	assert_true(world.event_flag_active(41))


func test_readvar_partycount_fails_without_a_party_summary() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6340"] = [Gen2WorldScript.READVAR, 0x01, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.current_map.events["coord_events"][0]["script"] = 0x6340
	var result: Array = world.dispatch_script_events()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"failed")
	assert_eq(result[0]["reason"], &"missing_party_summary")


func test_heal_machine_anim_special_emits_presentation_event_without_state_change() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6350"] = [
		Gen2WorldScript.SETVAL, 0,
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_HEAL_MACHINE_ANIM, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.current_map.events["coord_events"][0]["script"] = 0x6350
	var result: Array = world.dispatch_script_events()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete", JSON.stringify(result))
	assert_eq(
		_event_value(result[0]["events"], &"presentation_special_applied", "kind"),
		&"heal_machine_anim",
		JSON.stringify(result),
	)
	assert_eq(
		int(_event_value(result[0]["events"], &"presentation_special_applied", "machine_type")),
		0,
		JSON.stringify(result),
	)
	assert_false(world.event_flag_active(0))


func test_check_pokerus_special_reads_the_low_nibble_across_the_party_summary() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6360"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_CHECK_POKERUS, 0,
		Gen2WorldScript.IFTRUE, 0x70, 0x63,
		Gen2WorldScript.END,
	]
	scripts["48:6370"] = [Gen2WorldScript.SETEVENT, 42, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var infected := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	infected.set_party_summary(1, true)
	infected.current_map.events["coord_events"][0]["script"] = 0x6360
	var infected_result: Array = infected.dispatch_script_events()
	assert_eq(infected_result[0]["status"], &"complete", JSON.stringify(infected_result))
	assert_true(infected.event_flag_active(42))

	var clean_data: GameData = GameData.open_directory(_directory)
	var clean := Gen2WorldAPI.open(clean_data, 1, 1, Vector2i(7, 6))
	clean.set_party_summary(1, false)
	clean.current_map.events["coord_events"][0]["script"] = 0x6360
	var clean_result: Array = clean.dispatch_script_events()
	assert_eq(clean_result[0]["status"], &"complete", JSON.stringify(clean_result))
	assert_false(clean.event_flag_active(42))


func test_check_pokerus_special_fails_without_a_party_summary() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6380"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_CHECK_POKERUS, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.current_map.events["coord_events"][0]["script"] = 0x6380
	var result: Array = world.dispatch_script_events()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"failed")
	assert_eq(result[0]["reason"], &"missing_party_summary")


func test_party_summary_round_trips_and_reaches_queued_script_requests() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(world.party_summary().is_empty())
	assert_true(world.set_party_summary(3, true)["ok"])
	assert_eq(world.party_summary(), {"count": 3, "pokerus": true})
	assert_false(world.set_party_summary(-1, false)["ok"])
	assert_eq(world.party_summary(), {"count": 3, "pokerus": true})
	world.clear_party_summary()
	assert_true(world.party_summary().is_empty())


func test_set_day_of_week_follows_the_source_selection_and_confirmation_flow() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:61A0"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_SET_DAY_OF_WEEK, 0,
		Gen2WorldScript.WRITETEXT, 0x30, 0x70,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	RomCache.write_json(RomCache.world_text_path(_directory), {
		"48:7030": [Gen2WorldScript.TEXT_START, 0x80, 0x81, Gen2WorldScript.TEXT_TERMINATOR],
	})
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x61A0,
		"clock": {"day": 2, "hour": 8, "minute": 15},
	})

	var menu: Dictionary = runner.advance()
	assert_eq(menu["status"], &"waiting")
	assert_eq(menu["event"]["type"], &"menu")
	assert_eq(menu["event"]["options"], [
		&"Sunday", &"Monday", &"Tuesday", &"Wednesday", &"Thursday", &"Friday", &"Saturday",
	])

	var confirmation_text: Dictionary = runner.advance(true, 3)
	assert_eq(confirmation_text["event"]["type"], &"text")
	assert_eq(confirmation_text["event"]["text"], "Wednesday,\nis it?")
	var confirmation: Dictionary = runner.advance(true)
	assert_eq(confirmation["event"]["type"], &"choice")
	assert_eq(confirmation["event"]["choices"], [&"yes", &"no"])

	var text: Dictionary = runner.advance(true, 0)
	assert_eq(text["event"]["type"], &"text")
	assert_eq(text["event"]["text"], "AB")
	var complete: Dictionary = runner.advance(true)
	assert_eq(complete["status"], &"complete")
	assert_eq(complete["clock"], {"day": 3, "hour": 8, "minute": 15})


func test_initial_dst_specials_publish_source_confirmation_text_and_commit_state() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:61B0"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_INITIAL_SET_DST_FLAG, 0,
		Gen2WorldScript.YESORNO, Gen2WorldScript.END,
	]
	scripts["48:61C0"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_INITIAL_CLEAR_DST_FLAG, 0,
		Gen2WorldScript.YESORNO, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	var enabled := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x61B0,
		"clock": {"day": 1, "hour": 10, "minute": 5},
	})
	var enabled_text: Dictionary = enabled.advance()
	assert_eq(enabled_text["event"]["text"], "10:05 DST,\nis that OK?")
	var enabled_choice: Dictionary = enabled.advance(true)
	assert_eq(enabled_choice["event"]["type"], &"choice")
	var enabled_result: Dictionary = enabled.advance(true, 0)
	assert_eq(enabled_result["status"], &"complete")
	assert_true(enabled_result["dst_enabled"])

	var disabled := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x61C0,
		"clock": {"day": 1, "hour": 10, "minute": 5},
	})
	var disabled_text: Dictionary = disabled.advance()
	assert_eq(disabled_text["event"]["text"], "10:05,\nis that OK?")
	var disabled_choice: Dictionary = disabled.advance(true)
	assert_eq(disabled_choice["event"]["type"], &"choice")
	var disabled_result: Dictionary = disabled.advance(true, 0)
	assert_eq(disabled_result["status"], &"complete")
	assert_false(disabled_result["dst_enabled"])


func test_restart_map_music_special_uses_the_audio_runtime_request() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:61D0"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_RESTART_MAP_MUSIC, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x61D0,
	})
	var waiting: Dictionary = runner.advance()
	assert_eq(waiting["event"]["type"], &"runtime_request")
	assert_eq(waiting["event"]["request"]["kind"], &"audio_requested")
	assert_eq(waiting["event"]["request"]["values"]["kind"], &"map_music")
	var complete: Dictionary = runner.complete_runtime_request({"ok": true})
	assert_eq(complete["status"], &"complete")


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


## home/map.asm's map load calls ReadObjectEvents, which clears the object
## structs and re-reads every object event from ROM, so the coordinates
## moveobject wrote into wMapObjects
## (engine/overworld/scripting.asm's Script_moveobject through
## CopyDECoordsToMapObject) do not outlive the loaded map. A MAPCALLBACK_OBJECTS
## callback re-applies them when its own condition still holds.
func test_scripted_object_position_does_not_survive_a_map_change() -> void:
	var world: Gen2WorldAPI = _object_script_world([0x72, 2, 3, 4, Gen2WorldScript.END])
	assert_eq(world.objects[0].cell, Vector2i(5, 6))
	var moved: Array = world.dispatch_script_events()
	assert_eq(moved[0]["status"], &"complete", JSON.stringify(moved[0]))
	assert_eq(world.objects[0].cell, Vector2i(3, 4))

	world.player_cell = Vector2i(6, 6)
	assert_true(world.try_warp()["ok"])
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_true(world.try_warp()["ok"])
	assert_eq(world.map_id(), Vector2i(1, 1))
	assert_eq(world.objects[0].cell, Vector2i(5, 6))


func test_scripted_object_facing_does_not_survive_a_map_change() -> void:
	var world: Gen2WorldAPI = _object_script_world([
		0x76, 2, Gen2WorldSprite.FACING_RIGHT, Gen2WorldScript.END,
	])
	assert_eq(world.dispatch_script_events()[0]["status"], &"complete")
	assert_eq(world.objects[0].facing, Gen2WorldSprite.FACING_RIGHT)

	world.player_cell = Vector2i(6, 6)
	assert_true(world.try_warp()["ok"])
	assert_true(world.try_warp()["ok"])
	assert_eq(world.objects[0].facing, Gen2WorldSprite.FACING_DOWN)


## reloadmapafterbattle reloads the live records without the map load that
## rebuilds them from the cache, so a trainer written to its post-approach cell
## still answers there.
func test_scripted_object_position_survives_a_reload_of_the_same_map() -> void:
	var world: Gen2WorldAPI = _object_script_world([0x72, 2, 3, 4, Gen2WorldScript.END])
	assert_eq(world.dispatch_script_events()[0]["status"], &"complete")
	assert_eq(world.objects[0].cell, Vector2i(3, 4))
	assert_true(world.reload_current_map()["ok"])
	assert_eq(world.objects[0].cell, Vector2i(3, 4))


## disappear writes an event flag rather than a map-object coordinate, and the
## cartridge does persist event flags, so visibility is not cleared with the
## position and facing overrides.
func test_object_visibility_override_survives_a_map_change() -> void:
	var world: Gen2WorldAPI = _object_script_world([0x6E, 2, Gen2WorldScript.END])
	assert_eq(world.dispatch_script_events()[0]["status"], &"complete")
	assert_false(world.objects[0].active)

	world.player_cell = Vector2i(6, 6)
	assert_true(world.try_warp()["ok"])
	assert_true(world.try_warp()["ok"])
	assert_false(world.objects[0].active)


## Opens map 1/1 standing on the coordinate event at (7, 6) with
## [param script_bytes] behind it, so a test can drive one object command.
func _object_script_world(script_bytes: Array) -> Gen2WorldAPI:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6220"] = script_bytes
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6220
	return Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6), Gen2WorldState.new())


func test_roaming_mons_move_on_map_setup_and_not_on_elapsed_time() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(6, 6))
	var random := RandomNumberGenerator.new()
	random.seed = 2
	world.schedule_random = random
	var before: Array = world.roaming_mons()
	assert_eq(before[0]["map_group"], 1)
	assert_eq(before[0]["map_number"], 2)

	# An hour of clock does not move a roamer: the cartridge advances them in
	# map setup, so standing still keeps them where they are.
	var clock := Gen2WorldClock.new(6, 0, 0)
	clock.advance(60.0 * 60.0, world)
	var after_clock: Array = world.roaming_mons()
	assert_eq(after_clock[0]["map_group"], 1)
	assert_eq(after_clock[0]["map_number"], 2)

	assert_true(world.try_warp()["ok"])
	var moved: Array = world.last_schedule().get("roaming", [])
	assert_eq(moved.size(), 1)
	assert_eq(world.roaming_mons()[0]["map_number"], 1)


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


func test_memcall_and_memjump_follow_far_pointers_supplied_by_runtime_memory() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6058": [Gen2WorldScript.MEMCALL, 0x00, 0xD0, Gen2WorldScript.END],
		"48:6068": [Gen2WorldScript.SETEVENT, 9, 0, Gen2WorldScript.END],
		"48:6078": [Gen2WorldScript.MEMJUMP, 0x10, 0xD0, Gen2WorldScript.END],
	})
	data = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6058,
		"memory_pointers": {
			"0xD000": {"bank": 48, "address": 0x6068},
		},
	})
	var completed: Dictionary = runner.advance()
	assert_eq(completed["status"], &"complete", JSON.stringify(completed))
	assert_true(state.is_event_flag_active(9))

	var jump_runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6078,
		"memory_pointers": {
			0xD010: {"bank": 48, "address": 0x6068},
		},
	})
	var jumped: Dictionary = jump_runner.advance()
	assert_eq(jumped["status"], &"complete", JSON.stringify(jumped))


func test_special_phone_call_check_reads_staged_id_before_commit() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6088": [0x9C, 2, 0, 0x9D, Gen2WorldScript.END],
	})
	data = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6088,
	})
	var completed: Dictionary = runner.advance()
	assert_eq(completed["status"], &"complete", JSON.stringify(completed))
	assert_eq(state.pending_special_phone_call(), 2, JSON.stringify(completed))


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


func test_crystal_engine_flags_and_hall_of_fame_commit_at_script_end() -> void:
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:60C0": [
			0x36, Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED, 0,
			0x34, Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED, 0,
			0x09, 0xD0, 0x60,
			0x91,
		],
		"48:60D0": [0x33, 7, 0, 0x91],
		"48:60E0": [0xA0, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var flag_runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x60C0,
	})
	var flag_result: Dictionary = flag_runner.advance()
	assert_eq(flag_result["status"], &"complete")
	assert_true(state.bargain_merchant_closed())
	assert_true(state.is_event_flag_active(7))

	var hall_runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x60E0,
	})
	var hall_result: Dictionary = hall_runner.advance()
	assert_eq(hall_result["status"], &"complete")
	assert_true(state.hall_of_fame())
	assert_true(hall_result["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"hall_of_fame_requested"
	))


func test_the_source_random_command_rolls_on_the_injected_generator() -> void:
	# RANDOM 4, then set one of four event flags by the value it rolled.
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6100": [
			0x17, 4,
			0x06, 0, 0x10, 0x61,
			0x06, 1, 0x20, 0x61,
			0x06, 2, 0x30, 0x61,
			0x33, 103, 0, 0x91,
		],
		"48:6110": [0x33, 100, 0, 0x91],
		"48:6120": [0x33, 101, 0, 0x91],
		"48:6130": [0x33, 102, 0, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)

	# A seeded generator has to reproduce the branch. Before this was injected the
	# command rolled on the engine's global generator, which no seed can reach, so
	# a script that branches on RANDOM could not be pinned by a test or replayed.
	var rolled: Array[int] = []
	for attempt: int in 2:
		var random := RandomNumberGenerator.new()
		random.seed = 20250806
		var state := Gen2WorldState.new()
		var runner := Gen2WorldScriptRunner.begin(
			data, state, {"kind": &"test", "bank": 48, "script": 0x6100},
			Callable(), random
		)
		assert_eq(runner.advance()["status"], &"complete")
		for flag: int in [100, 101, 102, 103]:
			if state.is_event_flag_active(flag):
				rolled.append(flag)
	assert_eq(rolled.size(), 2)
	assert_eq(rolled[0], rolled[1])

	# And the roll has to be a roll: over many seeds it must not always land in
	# the same branch.
	var seen: Dictionary = {}
	for attempt: int in 40:
		var random := RandomNumberGenerator.new()
		random.seed = attempt
		var state := Gen2WorldState.new()
		var runner := Gen2WorldScriptRunner.begin(
			data, state, {"kind": &"test", "bank": 48, "script": 0x6100},
			Callable(), random
		)
		runner.advance()
		for flag: int in [100, 101, 102, 103]:
			if state.is_event_flag_active(flag):
				seen[flag] = true
	assert_gt(seen.size(), 1, "RANDOM must reach more than one branch")


func test_world_snapshot_round_trips_map_player_and_mutable_state() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new({}, {"1:1": 3}, {4: 2}, {0: 100}, 7, {9: true}, 5, Vector2i(1, 1), 0xD3, [], true)
	state.set_hall_of_fame()
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6), state)
	world.set_world_clock(2, 7, 12)
	world.set_daylight_saving_time_enabled(true)
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
	assert_eq(restored.world_clock(), {"day": 2, "hour": 7, "minute": 12})
	assert_true(restored.daylight_saving_time_enabled())
	assert_eq(restored.state.map_scene(1, 1), 3)
	assert_eq(restored.state.repel_steps(), 5)
	assert_eq(restored.state.swarm_map(), Vector2i(1, 1))
	assert_true(restored.state.just_battled())
	assert_true(restored.state.hall_of_fame())
	var schedule: Dictionary = restored.advance_schedule()
	assert_true(schedule["ok"])
	assert_eq(schedule["kind"], &"world_schedule_updated")


func test_world_clock_day_change_clears_daily_engine_flags() -> void:
	var state := Gen2WorldState.new()
	state.set_hall_of_fame()
	state.set_engine_flag(Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED)
	var world: Gen2WorldAPI = _world(Vector2i(8, 6), state)
	world.set_world_clock(0, 23, 59)
	world.set_world_clock(1, 0, 0)
	assert_true(world.state.hall_of_fame())
	assert_false(world.state.bargain_merchant_closed())


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


func test_real_trainer_metadata_runs_seen_text_battle_and_beaten_flag() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(5, 4))
	var trainer: Gen2WorldObject = world.objects[0]
	trainer.object_type = Gen2WorldObject.OBJECTTYPE_TRAINER
	trainer.sight_range = 3
	trainer.facing = Gen2WorldSprite.FACING_UP
	trainer.trainer_data = {
		"event_flag": 42,
		"trainer_group": 1,
		"trainer_id": 1,
		"seen_text": {"bank": 48, "address": 0x7000},
		"win_text": {"bank": 48, "address": 0x7000},
		"loss_text": {"bank": 48, "address": 0x7000},
		"after_script": 0x6040,
	}
	var audio: Array = world.dispatch_sight_events()
	assert_eq(audio[0]["status"], &"waiting")
	assert_eq(audio[0]["event"]["type"], &"runtime_request")
	assert_eq(audio[0]["event"]["request"]["kind"], &"audio_requested")
	assert_eq(audio[0]["event"]["request"]["values"]["kind"], &"encounter_music")
	var approach: Array = world.complete_runtime_request({
		"ok": true, "audio_played": false,
	})
	assert_eq(approach[0]["status"], &"waiting")
	assert_eq(approach[0]["event"]["type"], &"runtime_request")
	assert_eq(approach[0]["event"]["request"]["kind"], &"trainer_approach_requested")
	var approach_values: Dictionary = approach[0]["event"]["request"]["values"]
	assert_eq(approach_values["object_index"], 0)
	assert_eq(approach_values["distance"], 2)
	assert_eq(approach_values["direction"], Vector2i.UP)
	var plan: Dictionary = world.start_trainer_approach(
		int(approach_values["object_index"]), approach_values["direction"],
		int(approach_values["distance"])
	)
	assert_true(plan["ok"])
	assert_eq(plan["path"], [Vector2i.UP])
	assert_eq(world.objects[0].emote_remaining, Gen2WorldAPI.TRAINER_SHOCK_FRAMES)
	for _frame: int in Gen2WorldAPI.TRAINER_SHOCK_FRAMES - 1:
		world.tick()
	assert_true(world.objects[0].emote_visible)
	assert_true(world.tick())
	assert_false(world.objects[0].emote_visible)
	var step: Dictionary = world.advance_trainer_approach_step(0, Vector2i.UP)
	assert_true(step["ok"])
	assert_eq(world.objects[0].cell, Vector2i(5, 5))
	var finished: Dictionary = world.finish_trainer_approach(0)
	assert_true(finished["ok"])
	assert_eq(finished["facing"], Gen2WorldSprite.FACING_UP)
	assert_eq(finished["player_facing"], Gen2WorldSprite.FACING_DOWN)
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_DOWN)
	var text: Array = world.complete_runtime_request({
		"ok": true, "object_index": 0, "path": plan["path"],
	})
	assert_eq(text[0]["status"], &"waiting")
	assert_eq(text[0]["event"]["type"], &"text")
	assert_eq(text[0]["event"]["text"], "AB")
	var button: Array = world.run_event_queue(true)
	assert_eq(button[0]["event"]["type"], &"button")
	var battle: Array = world.run_event_queue(true)
	assert_eq(battle[0]["event"]["type"], &"runtime_request")
	assert_eq(battle[0]["event"]["request"]["kind"], &"battle_requested")
	var values: Dictionary = battle[0]["event"]["request"]["values"]
	assert_eq(values["trainer_group"], 1)
	assert_eq(values["trainer_id"], 0)
	assert_eq(values["win_text"]["address"], 0x7000)
	var complete: Array = world.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
	})
	assert_eq(complete[0]["status"], &"complete")
	assert_true(world.state.is_event_flag_active(42))
	assert_true(complete[0]["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"battle_map_reload_requested"
	))
	assert_true(world.dispatch_sight_events().is_empty())
	assert_true((world.objects[0] as Gen2WorldObject).active)
	assert_false((world.objects[0] as Gen2WorldObject).event_flag_active(world.state))
	assert_true((world.objects[0] as Gen2WorldObject).trainer_flag_active(world.state))

	var after_battle: Array = world.interact()
	assert_eq(after_battle.size(), 1)
	assert_eq(after_battle[0]["status"], &"complete")
	assert_eq(after_battle[0]["source"]["trainer_phase"], &"after")
	assert_eq(after_battle[0]["source"]["script"], 0x6040)


func test_catch_tutorial_uses_wild_setup_without_persistent_capture_changes() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new({}, {}, {Gen2WorldPartyHost.ITEM_POKE_BALL: 3})
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"coord_events", "bank": 48, "script": 0x6050,
	})
	var waiting: Dictionary = runner.advance()
	assert_eq(waiting["status"], &"waiting")
	var request: Dictionary = waiting["event"]["request"]
	assert_eq(request["kind"], &"catch_tutorial_requested")
	assert_eq(request["values"]["kind"], &"wild")
	assert_eq(request["values"]["pokemon"], 16)
	assert_eq(request["values"]["level"], 5)
	assert_true(request["values"]["tutorial"])
	assert_eq(request["values"]["battle_type"], 3)
	var complete: Dictionary = runner.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_CAUGHT,
	})
	assert_eq(complete["status"], &"complete")
	assert_eq(state.item_quantity(Gen2WorldPartyHost.ITEM_POKE_BALL), 3)
	assert_false(state.just_battled())
	assert_true(complete["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"catch_tutorial_completed"
	))
	assert_true(complete["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"battle_map_reload_requested"
	))


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


func test_crystal_rival_battle_preserves_can_lose_and_continues_after_reloadmap() -> void:
	var data: GameData = GameData.open_directory(_directory)
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:60B8": [0x5E, 9, 3, 0x1E, 3, 1, 0x5F, 0x7B, 0x91],
	})
	data = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x60B8,
	})
	var waiting: Dictionary = runner.advance()
	assert_eq(waiting["status"], &"waiting")
	var values: Dictionary = waiting["event"]["request"]["values"]
	assert_eq(values["kind"], &"trainer")
	assert_eq(values["trainer_group"], 9)
	assert_eq(values["trainer_id"], 2)
	assert_eq(values["battle_type"], 1)
	assert_true(values["can_lose"])

	var lost: Dictionary = runner.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_LOST,
	})
	assert_eq(lost["status"], &"complete")
	assert_true(lost["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"battle_lost" and bool(event.get("can_lose", false))
	))
	assert_true(lost["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"map_reload_requested"
	))
	assert_false(lost["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"blackout"
	))


func test_crystal_post_starter_specials_and_checkitem_have_explicit_boundaries() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:60C8"] = [Gen2WorldScript.SPECIAL, 27, 0, Gen2WorldScript.END]
	scripts["48:60D8"] = [Gen2WorldScript.SPECIAL, 36, 0, Gen2WorldScript.END]
	scripts["48:60E8"] = [Gen2WorldScript.CHECKITEM, 7, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	var heal_runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x60C8,
	})
	var heal_waiting: Dictionary = heal_runner.advance()
	assert_eq(heal_waiting["status"], &"waiting")
	assert_eq(heal_waiting["event"]["request"]["kind"], &"party_heal_requested")
	var healed: Dictionary = heal_runner.complete_runtime_request({
		"ok": true, "script_value": 1,
	})
	assert_eq(healed["status"], &"complete")

	var rival_runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x60D8,
	})
	var rival_waiting: Dictionary = rival_runner.advance()
	assert_eq(rival_waiting["status"], &"waiting")
	assert_eq(rival_waiting["event"]["request"]["kind"], &"rival_name_requested")
	assert_eq(rival_waiting["event"]["request"]["values"]["default_name"], "SILVER")
	var named: Dictionary = rival_runner.complete_runtime_request({
		"ok": true, "name": "RIVAL",
	})
	assert_eq(named["status"], &"complete")
	assert_eq(named["events"].filter(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"rival_name_changed"
	)[0]["name"], "RIVAL")

	var item_runner := Gen2WorldScriptRunner.begin(
		data, Gen2WorldState.new({}, {}, {7: 1}), {
			"kind": &"test", "bank": 48, "script": 0x60E8,
		}
	)
	var item_result: Dictionary = item_runner.advance()
	assert_eq(item_result["status"], &"complete", JSON.stringify(item_result))


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
		"48:6140": [0x7A, 14, 2, 0, 0x7C, 0x7D, 0x20, 0x60, 0x7E, 0, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6140
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var result: Array = world.dispatch_script_events()
	assert_eq(result[0]["status"], &"complete")
	assert_eq(world.block_at(7, 1), 0)
	var block_event: Dictionary = {}
	for event: Dictionary in result[0]["events"]:
		if event.get("type", &"") == &"map_block_changed" and event.has("change"):
			block_event = event["change"]
	assert_eq(block_event["source_cell"], Vector2i(14, 2))
	assert_eq(block_event["cell"], Vector2i(7, 1))
	assert_true(result[0]["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"map_refreshed"
	))
	assert_true(world.command_queues().is_empty())
	world.reload_current_map()
	assert_eq(world.block_at(7, 1), 1)


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


func _event_value(
	events: Array, event_type: StringName, key: String, index: int = -1
) -> Variant:
	var matches: Array = []
	for event: Dictionary in events:
		if event.get("type", &"") == event_type:
			matches.append(event)
	if index >= 0:
		return (matches[index] as Dictionary).get(key, null) if index < matches.size() else null
	return (matches[0] as Dictionary).get(key, null) if not matches.is_empty() else null
