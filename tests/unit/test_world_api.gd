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
	# StringBufferPointers as Gold stores them, so a `text_ram` operand resolves
	# to the buffer a script filled. Order is data/text_buffers.asm's.
	RomCache.write_json(RomCache.text_buffers_path(_directory), [
		0xCF91, 0xCFA4, 0xCFB7, 0xCF7E, 0xCF6B, 0xCAF6, 0xCB01,
	])
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
		"collision": [0, 0, 0, 0, 0x29, 0x29, 0x29, 0x29],
	}])

	var blocks: Array = []
	for index: int in 48:
		blocks.append(index % 2)

	var collision: Array = []
	collision.resize(16 * 12)
	for index: int in collision.size():
		collision[index] = 0
	collision[6 * 16 + 9] = 0x07
	collision[7 * 16 + 8] = 0x29
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

	# Counter fixture, row 9: CheckFacingObject doubles the facing distance over
	# a counter, so an object on (13,10) is talked to from (13,8) across this
	# cell. (11,9) is left at LAND_TILE as the control for the same geometry.
	collision[9 * 16 + 13] = 0x90  # COLL_COUNTER

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

	# Forced-tile fixture, row 5, for DoPlayerMovement.CheckTile: a waterfall at
	# (1,5) pushing DOWN onto open land, a door at (12,5) whose cell below is a
	# wall, and a forced-right tile at (15,5) on the east edge, where the forced
	# step leaves the map through the connection.
	collision[5 * 16 + 1] = 0x33   # COLL_WATERFALL
	collision[5 * 16 + 12] = 0x71  # COLL_DOOR
	collision[6 * 16 + 12] = 0x07  # wall below the door
	collision[5 * 16 + 15] = 0x41  # COLL_WALK_RIGHT

	# CheckDirectionalWarp's carpet, for DoPlayerMovement.CheckWarp: a warp cell
	# that is stood on rather than warped onto, with the wall an interior door
	# always has behind it.
	collision[4 * 16 + 13] = 0x78  # COLL_WARP_CARPET_UP
	collision[3 * 16 + 13] = 0x07  # wall above the carpet

	# A lone COLL_UP_WALL at (2,10), matching real Route 42 cliff cells: it
	# blocks stepping off the edge (entering from above, moving DOWN) but not
	# climbing it (moving UP from below), since the enter rule only tests the
	# DOWN handler's opposite-face condition, which COLL_UP_WALL matches.
	collision[10 * 16 + 2] = 0xB2  # COLL_UP_WALL

	# CheckWarpCollision gates a warp on the tile's own code, so the fixture's
	# warp cells carry COLL_PIT: walkable, immediate and not a forced tile.
	collision[6 * 16 + 6] = 0x60   # COLL_PIT under the warp at (6,6)

	# A two-cell pond on row 11 for SPRITEMOVEDATA_SWIM_WANDER, which needs a
	# water cell to stand on and another to step to. Everything around it stays
	# at the default LAND_TILE, which is what a swimming object must refuse.
	collision[11 * 16 + 11] = 0x29  # COLL_WATER
	collision[11 * 16 + 12] = 0x29  # COLL_WATER

	# A tall-grass cell at (5,10) for SetTallGrassFlags and the rustle ShakeGrass
	# spawns on a step into it. LAND_TILE permission, so an ordinary step reaches
	# it and nothing else in the fixture changes.
	collision[10 * 16 + 5] = 0x18  # COLL_TALL_GRASS

	# An ice cell beside it, which CanEncounterWildMon refuses on every
	# environment including the cave branch that skips the grass test.
	collision[10 * 16 + 6] = 0x23  # COLL_ICE

	# An ice run on row 1 for DoPlayerMovement.CheckForced: (2,1) to (5,1) are
	# ice with a wall at (6,1), so a step east from (1,1) slides the whole run
	# and bumps the wall. Everything else on the row stays LAND_TILE.
	for column: int in range(2, 6):
		collision[1 * 16 + column] = 0x23  # COLL_ICE
	collision[1 * 16 + 6] = 0x07           # wall the slide ends against

	var source_events: Dictionary = {
		"bank": 48,
		"warps": [
			{"x": 6, "y": 6, "destination": 1, "map_group": 1, "map_number": 2},
			{"x": 13, "y": 4, "destination": 1, "map_group": 1, "map_number": 2},
		],
		"coord_events": [{"scene": 0, "x": 7, "y": 6, "script": 0x6000}],
		"bg_events": [{"x": 8, "y": 6, "type": 0, "script": 0x6015}],
		"objects": [{"sprite": 1, "x": 5, "y": 6, "script": 0x6030, "event_flag": 7}],
	}

	var target_collision: Array = []
	target_collision.resize(16 * 12)
	for index: int in target_collision.size():
		target_collision[index] = 0
	target_collision[2 * 16 + 2] = 0x60  # COLL_PIT under the warp at (2,2)

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
			"length": 6, "target_width_blocks": 8,
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
			"length": 6, "target_width_blocks": 8,
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
		"bug_contest": {
			"mons": [
				{"percent": 50, "species": 10, "min_level": 7, "max_level": 18},
				{"percent": 50, "species": 13, "min_level": 9, "max_level": 9},
				{"percent": 255, "species": 49, "min_level": 30, "max_level": 40},
			],
			"contestants": [
				{"trainer_class": 36, "trainer": 1, "placings": [
					{"species": 10, "score": 300}, {"species": 11, "score": 285},
					{"species": 12, "score": 226},
				]},
			],
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
		# BugContestResultsWarpScript's own index, so the contest can end the way
		# CheckTimeEvents ends it: through the std script, not a special case.
		"22": {"bank": 48, "address": 0x6020, "bytes": [0x4C, 0x00, 0x70, 0x91]},
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
		## `UnownWalls`' four, since the special that draws one names them by
		## index and a wrong index has to be told from a right one.
		"unown_walls": ["WALLA", "WALLB", "WALLC", "WALLD"],
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


## Spends the frames a script's own waits ask for and returns every result the
## run produced, the dispatched ones first. A script that moves anything stops
## at the movement it started, so a test that only wants the end of one drives
## it through here rather than reading the first result.
func _run_script(world: Gen2WorldAPI, dispatched: Array) -> Array:
	var results: Array = dispatched.duplicate()
	for _frame: int in 1024:
		if world.pending_script_wait().is_empty():
			break
		results.append_array(
			world.advance_script_presentation_frame()
		)
	return results


func _final_status(results: Array) -> StringName:
	if results.is_empty():
		return &""
	return StringName((results[results.size() - 1] as Dictionary).get("status", &""))


## Every event the whole run emitted. The runner hands each one to its caller
## once, on the result that follows it, so a script with waits in it spreads
## them over several results.
func _all_events(results: Array) -> Array:
	var events: Array = []
	for result: Dictionary in results:
		events.append_array(result.get("events", []))
	return events


func _event_types(results: Array) -> Array[StringName]:
	var types: Array[StringName] = []
	for event: Dictionary in _all_events(results):
		types.append(StringName(event.get("type", &"")))
	return types


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


## Spends [param frames] hardware frames of the two-ring sequence and returns
## whatever finishing it produced.
func _spend_phone_ring(world: Gen2WorldAPI, frames: int) -> Array:
	var results: Array = []
	for _frame: int in frames:
		var spent: Array = world.advance_phone_ring_frame()
		if not spent.is_empty():
			results = spent
	return results


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
	assert_true(
		_spend_phone_ring(world, Gen2WorldPhoneRing.TOTAL_FRAMES - 1).is_empty(),
		"the last of the two rings has not been spent yet"
	)
	var resumed: Array = _spend_phone_ring(world, 1)
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
	var resumed: Array = _spend_phone_ring(world, 4 * Gen2WorldPhoneRing.TOTAL_FRAMES)
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


func test_map_decoration_specials_stamp_the_selected_room_blocks() -> void:
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
	data.world_tileset(0).block_count = 0x26
	var map: Gen2WorldMap = data.world_map(1, 1)
	map.scripts["callbacks"] = [
		{"type": 5, "script": 0x6250},
		{"type": 1, "script": 0x6260},
	]
	var state := Gen2WorldState.new()
	state.set_maptile_decoration(&"bed", 0x02)
	state.set_maptile_decoration(&"poster", 0x10)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6), state)
	var result: Array = world.dispatch_map_entry()
	assert_eq(result.size(), 2, JSON.stringify(result))
	for callback_result: Dictionary in result:
		assert_eq(callback_result["status"], &"complete", JSON.stringify(result))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_CONSOLE))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_DOLL_1))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_DOLL_2))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_BIG_DOLL))
	assert_true(world.event_flag_active(Gen2WorldScriptRunner.EVENT_PLAYERS_ROOM_POSTER))
	assert_eq(world.block_at(0, 2), 0x1B)
	assert_eq(world.block_at(3, 0), 0x1F)
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


func test_crystal_verbosegiveitemvar_reads_kurts_quantity_without_staging_a_swarm() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6270"] = [0x9F, 1, 0x16, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6270,
		"kurt_apricorn_quantity": 3,
	})
	var result: Dictionary = runner.advance()
	## `ScriptCall GiveItemScript`'s received line, not the swarm request a
	## misread of this opcode would stage.
	assert_eq(result["status"], &"waiting", JSON.stringify(result))
	assert_eq(StringName(result["event"]["type"]), &"text", JSON.stringify(result))
	assert_string_contains(String(result["event"]["text"]), data.item_name(1))

	var finished: Dictionary = _drain_receipt(runner, runner.advance(true))
	assert_eq(finished["status"], &"complete", JSON.stringify(finished))
	assert_eq(state.item_quantity(1), 3)
	assert_eq(state.swarm_map(), Vector2i(-1, -1))


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
		## `text_buffer 0` is a text command, so the literal before it is closed
		## with `@` the way every `text_ram` in the pins is; without that
		## `PlaceString` reads $14 as a character.
		"48:7000": [
			Gen2WorldScript.TEXT_START, Gen2TextStream.TX_END,
			0x14, 0, Gen2TextStream.TX_END,
		],
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
	assert_eq(world.visible_origin_cell(), Vector2i(4, 2))
	assert_eq(world.visible_subcell_offset_cells(), Vector2i.ZERO)
	assert_eq(world.visible_screen_origin_cell(), Vector2i(4, 2))
	assert_eq(world.player_view_cell(), Vector2i(4, 4))
	assert_eq(world.player_pixel_position(), Vector2i(64, 64))

	var page: PackedInt32Array = world.visible_tile_indices()
	assert_eq(page.size(), 20 * 18)
	assert_eq(page[0], world.tile_index_at(8, 4))
	assert_eq(page[19], world.tile_index_at(27, 4))

	# GetMapScreenCoords clamps nothing, so the player stays centred at a corner
	# and the page runs off the map into border block.
	var top_left: Gen2WorldAPI = _world(Vector2i.ZERO)
	assert_eq(top_left.visible_origin_cell(), Vector2i(-4, -4))
	var bottom_right: Gen2WorldAPI = _world(Vector2i(15, 11))
	assert_eq(bottom_right.visible_origin_cell(), Vector2i(10, 6))
	assert_eq(bottom_right.visible_subcell_offset_cells(), Vector2i.ONE)
	assert_eq(bottom_right.visible_screen_origin_cell(), Vector2i(11, 7))


func test_movement_uses_raw_collision_codes_without_mutating_them() -> void:
	var world: Gen2WorldAPI = _world()
	assert_eq(world.collision_code_at(Vector2i(9, 6)), 0x07)
	assert_false(world.can_walk_to(Vector2i(9, 6)))
	assert_false(world.move(Vector2i.RIGHT))
	assert_eq(world.player_cell, Vector2i(8, 6))

	assert_eq(world.collision_code_at(Vector2i(8, 7)), 0x29)
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
	# STEP_PASSES_HOP frames, the same generic step system a one-cell walk
	# uses with a magnitude-2 direction.
	assert_true(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2(0, -2))
	_finish_player_step(world)
	assert_false(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2.ZERO)


## `UpdateJumpPosition`'s own `.y_offsets`, spent one entry per frame of the
## hop: the sprite rises to twelve pixels above its cell and is back on it two
## frames before the step ends. An ordinary walk has no arc at all.
func test_a_ledge_hop_lifts_the_sprite_and_an_ordinary_step_does_not() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(3, 2))
	assert_eq(world.player_jump_offset(), 0, "standing still is on the ground")
	assert_eq(world.move_result(Vector2i.DOWN)["kind"], &"ledge_hop")
	var arc: Array = []
	for _frame: int in Gen2WorldAPI.STEP_PASSES_HOP:
		arc.append(world.player_jump_offset())
		world.advance_player_step_pass()
	assert_eq(arc, Gen2WorldAPI.JUMP_OFFSETS)
	assert_eq(world.player_jump_offset(), 0, "and the arc ends with the step")

	## The mod-facing spelling of the same arc: world pixels, positive upward.
	var lifted: Gen2WorldAPI = _world(Vector2i(3, 2))
	assert_eq(lifted.player_height_offset_pixels(), 0.0, "at rest")
	assert_eq(lifted.move_result(Vector2i.DOWN)["kind"], &"ledge_hop")
	var cell: Vector2i = lifted.player_cell
	var highest: float = 0.0
	for _frame: int in Gen2WorldAPI.STEP_PASSES_HOP:
		highest = maxf(highest, lifted.player_height_offset_pixels())
		assert_eq(lifted.player_cell, cell, "the cell is the landing cell throughout")
		lifted.advance_player_step_pass()
	assert_eq(highest, 12.0, "the top of .y_offsets, above the ground")
	assert_eq(lifted.player_height_offset_pixels(), 0.0, "and back down on landing")

	var walker: Gen2WorldAPI = _world(Vector2i(5, 11))
	assert_true(bool(walker.move_result(Vector2i.UP).get("ok", false)))
	assert_eq(walker.player_jump_offset(), 0)

	## StepFunction_PlayerJump is the only step type that runs
	## UpdateJumpPosition, so the step after the hop is on the ground for the
	## whole of it however the hop left the flag.
	assert_true(bool(world.move_result(Vector2i.DOWN).get("ok", false)), "a walk off the ledge")
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		assert_eq(world.player_jump_offset(), 0, "the walk after a hop has no arc")
		world.advance_player_step_pass()


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


## Puts one SPRITEMOVEDATA_STRENGTH_BOULDER on [param at] and reloads, so the
## shared fixture's own object list is untouched by every other test here.
## ReadObjectEvents rebuilds from map data on a reload, which is what makes this
## the same path a real map load takes.
func _boulder_world(
	start: Vector2i, at: Vector2i, strength: bool = true, surfing: bool = false
) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = _world(start)
	if strength:
		world.state.set_engine_flag(Gen2WorldState.strength_active_flag(
			Gen2WorldState.is_crystal_profile(world.data)
		))
	world.current_map.events["objects"].append({
		"sprite": 1, "x": at.x, "y": at.y,
		"movement": Gen2WorldObject.MOVEMENT_STRENGTH_BOULDER, "event_flag": 0xFFFF,
	})
	if surfing:
		world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	world.reload_current_map()
	return world


func _boulder_at(world: Gen2WorldAPI, cell: Vector2i) -> Gen2WorldObject:
	return world.object_at(cell)


## Column x=11 is open land from y=0 to the map's south edge, so a push there
## meets nothing but the rule under test.
const BOULDER_STAND: Vector2i = Vector2i(11, 4)
const BOULDER_CELL: Vector2i = Vector2i(11, 5)
const BOULDER_LANDING: Vector2i = Vector2i(11, 6)


## .CheckNPC's own comment: a movable boulder is treated the same as an NPC in
## front, so both bump. The boulder advances a cell, the player does not, and the
## step still reports blocked.
func test_strength_push_moves_the_boulder_and_bumps_the_player() -> void:
	var world: Gen2WorldAPI = _boulder_world(BOULDER_STAND, BOULDER_CELL)
	var boulder: Gen2WorldObject = _boulder_at(world, BOULDER_CELL)
	assert_not_null(boulder)

	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_false(result["ok"], JSON.stringify(result))
	assert_eq(result["reason"], &"blocked")
	assert_eq(world.player_cell, BOULDER_STAND)
	assert_true(result.has("boulder_pushed"), JSON.stringify(result))
	assert_eq(result["boulder_pushed"]["from_cell"], BOULDER_CELL)
	assert_eq(result["boulder_pushed"]["to_cell"], BOULDER_LANDING)
	assert_eq(boulder.cell, BOULDER_LANDING)
	assert_null(_boulder_at(world, BOULDER_CELL))


## MovementFunction_Strength calls InitStep with `direction | 0`, the slow
## StepVectors row: 16 frames. The cell commits when the step starts, so only the
## drawn offset trails, and the boulder never rolls a wait afterwards because
## StepFunction_StrengthBoulder just stands it back up.
func test_strength_push_slides_the_boulder_over_the_slow_step_duration() -> void:
	var world: Gen2WorldAPI = _boulder_world(BOULDER_STAND, BOULDER_CELL)
	world.move_result(Vector2i.DOWN)
	var boulder: Gen2WorldObject = _boulder_at(world, BOULDER_LANDING)
	assert_not_null(boulder)
	assert_true(boulder.is_stepping())
	assert_eq(boulder.step_passes_total, Gen2WorldAPI.STEP_PASSES_BOULDER_PUSH)

	var random := RandomNumberGenerator.new()
	random.seed = 7
	for _frame: int in Gen2WorldAPI.STEP_PASSES_BOULDER_PUSH:
		world.advance_object_steps_pass(random)
	assert_false(boulder.is_stepping())
	assert_false(boulder.is_idle())
	assert_eq(boulder.cell, BOULDER_LANDING)


## The flag is the first thing .CheckStrengthBoulder tests, so without it the
## boulder is an ordinary blocking object.
func test_strength_push_refuses_without_the_active_flag() -> void:
	var world: Gen2WorldAPI = _boulder_world(BOULDER_STAND, BOULDER_CELL, false)
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"blocked")
	assert_false(result.has("boulder_pushed"))
	assert_eq(_boulder_at(world, BOULDER_CELL).cell, BOULDER_CELL)


## CanObjectMoveInDirection: WillObjectBumpIntoWater refuses a landing cell that
## is not LAND_TILE, and WillObjectBumpIntoSomeoneElse refuses an occupied one.
func test_strength_push_refuses_a_landing_cell_the_boulder_cannot_take() -> void:
	# (2,2) is a wall directly above the boulder at (2,3).
	var walled: Gen2WorldAPI = _boulder_world(Vector2i(2, 4), Vector2i(2, 3))
	var into_wall: Dictionary = walled.move_result(Vector2i.UP)
	assert_false(into_wall.has("boulder_pushed"), JSON.stringify(into_wall))
	assert_eq(_boulder_at(walled, Vector2i(2, 3)).cell, Vector2i(2, 3))

	# The shared fixture's own object stands at (5,6), so a boulder at (5,5)
	# pushed DOWN has nowhere to land.
	var occupied: Gen2WorldAPI = _boulder_world(Vector2i(5, 4), Vector2i(5, 5))
	assert_not_null(occupied.object_at(Vector2i(5, 6)))
	var into_object: Dictionary = occupied.move_result(Vector2i.DOWN)
	assert_false(into_object.has("boulder_pushed"), JSON.stringify(into_object))
	assert_eq(_boulder_at(occupied, Vector2i(5, 5)).cell, Vector2i(5, 5))


## .CheckLandPerms runs before .CheckNPC, so a boulder standing where the player
## could not walk anyway is never even considered: the leave rule on the player's
## own COLL_RIGHT_WALL cell refuses first.
func test_strength_push_refuses_when_the_step_itself_is_walled_off() -> void:
	var world: Gen2WorldAPI = _boulder_world(Vector2i(2, 8), Vector2i(3, 8))
	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_false(result["ok"])
	assert_false(result.has("boulder_pushed"), JSON.stringify(result))
	assert_eq(_boulder_at(world, Vector2i(3, 8)).cell, Vector2i(3, 8))


## MovementFunction_Strength .on_pit stops a boulder for good before it ever
## reads BOULDER_MOVING. Blackthorn Gym 2F is the only map that reaches it. The
## pit is LAND_TILE, so nothing else here would have refused.
func test_strength_push_refuses_a_boulder_standing_on_a_pit() -> void:
	var world: Gen2WorldAPI = _boulder_world(Vector2i(6, 5), Vector2i(6, 6))
	assert_true(Gen2WorldCollision.is_pit_tile(world.collision_code_at(Vector2i(6, 6))))
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_false(result.has("boulder_pushed"), JSON.stringify(result))
	assert_eq(_boulder_at(world, Vector2i(6, 6)).cell, Vector2i(6, 6))


## The fixture's warp at (6,6) is on COLL_PIT, which is exactly what a stone
## table needs: HandleStoneQueue wants a boulder standing on a pit that is also
## a warp event. Writes the queue the way a MAPCALLBACK_CMDQUEUE would, then
## pushes a boulder onto it from the north.
func _stone_table_world(rows: Array, boulder_at: Vector2i = Vector2i(6, 5)) -> Gen2WorldAPI:
	RomCache.write_json(RomCache.world_command_queues_path(_directory), {
		"48:6200": {
			"bank": 48, "address": 0x6200,
			"type": Gen2WorldScript.CMDQUEUE_STONETABLE,
			"data_address": 0x6205, "rows": rows,
		},
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6210": [Gen2WorldScript.SETEVENT, 24, 0, Gen2WorldScript.END],
	})
	var world: Gen2WorldAPI = _boulder_world(boulder_at + Vector2i.UP, boulder_at)
	world.apply_command_queue_write(48, 0x6200)
	return world


## The warp at (6,6) is the map's first, so HandleStoneQueue's one-based count
## makes it warp 1. The boulder appended by _boulder_world() is the second
## object, so its object_const_def id is 3.
const STONE_WARP: int = 1
const STONE_OBJECT: int = 3
const STONE_SCRIPT: int = 0x6210


## CmdQueue_StoneTable then HandleStoneQueue, all five tests passing at once: a
## Strength boulder, standing, on a pit, on a warp, named by a written row.
func test_a_boulder_pushed_onto_a_stone_table_warp_queues_its_fall_script() -> void:
	var world: Gen2WorldAPI = _stone_table_world([
		{"warp": STONE_WARP, "object": STONE_OBJECT, "script": STONE_SCRIPT},
	])
	var result: Dictionary = world.move_result(Vector2i.DOWN)

	assert_true(result.has("boulder_pushed"), JSON.stringify(result))
	assert_eq(result["boulder_pushed"]["to_cell"], Vector2i(6, 6))
	assert_eq(int(result["boulder_pushed"]["fall_script"]), STONE_SCRIPT)
	## The row's script is queued, not run behind the caller's back.
	var pumped: Array = world.run_event_queue(false)
	assert_eq(pumped.size(), 1)
	assert_eq(pumped[0]["status"], &"complete")
	assert_true(world.event_flag_active(24))


## The warp id is matched, not merely the fact of a warp: a row naming a
## different one leaves the push an ordinary push.
func test_a_stone_table_row_for_another_warp_does_not_fire() -> void:
	var world: Gen2WorldAPI = _stone_table_world([
		{"warp": STONE_WARP + 1, "object": STONE_OBJECT, "script": STONE_SCRIPT},
	])
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(result.has("boulder_pushed"))
	assert_false(result["boulder_pushed"].has("fall_script"), JSON.stringify(result))


## And so is the object id, which is an object_const_def constant and so two
## more than the map's own index.
func test_a_stone_table_row_for_another_boulder_does_not_fire() -> void:
	var world: Gen2WorldAPI = _stone_table_world([
		{"warp": STONE_WARP, "object": STONE_OBJECT + 1, "script": STONE_SCRIPT},
	])
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(result.has("boulder_pushed"))
	assert_false(result["boulder_pushed"].has("fall_script"), JSON.stringify(result))


## A boulder pushed onto ordinary floor is not on a warp at all, so the queue
## never answers however many rows it holds.
func test_a_boulder_pushed_onto_open_floor_fires_no_stone_table() -> void:
	var world: Gen2WorldAPI = _stone_table_world([
		{"warp": STONE_WARP, "object": STONE_OBJECT, "script": STONE_SCRIPT},
	], BOULDER_CELL)
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(result.has("boulder_pushed"))
	assert_false(result["boulder_pushed"].has("fall_script"), JSON.stringify(result))


## HandleStoneQueue reads the queue that was written, so a map whose callback
## never ran has none and nothing falls.
func test_no_stone_table_fires_without_a_written_queue() -> void:
	var world: Gen2WorldAPI = _boulder_world(Vector2i(6, 4), Vector2i(6, 5))
	assert_true(world.command_queues().is_empty())
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(result.has("boulder_pushed"))
	assert_false(result["boulder_pushed"].has("fall_script"))


## The one-based index .check_on_warp counts, and zero for a cell with no warp.
func test_warp_index_is_one_based_and_zero_off_a_warp() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(7, 6))
	assert_eq(world.warp_index_at(Vector2i(6, 6)), 1)
	assert_eq(world.warp_index_at(Vector2i(7, 6)), 0)


## A boulder already sliding is not STANDING, which is .CheckStrengthBoulder's
## second test, so a second press does not chain it another cell.
func test_strength_push_refuses_a_boulder_already_mid_push() -> void:
	var world: Gen2WorldAPI = _boulder_world(BOULDER_STAND, BOULDER_CELL)
	assert_true(world.move_result(Vector2i.DOWN).has("boulder_pushed"))
	var again: Dictionary = world.move_result(Vector2i.DOWN)
	assert_false(again.has("boulder_pushed"), JSON.stringify(again))
	assert_eq(_boulder_at(world, BOULDER_LANDING).cell, BOULDER_LANDING)


## .TrySurf calls the same .CheckNPC and .CheckStrengthBoulder checks no player
## state, so a surfing player stepping onto a land cell pushes the boulder on it.
func test_strength_push_works_while_surfing_onto_land() -> void:
	# (4,8) is COLL_RIGHT_BUOY, water permission, with land below at (4,9).
	var world: Gen2WorldAPI = _boulder_world(
		Vector2i(4, 8), Vector2i(4, 9), true, true
	)
	var result: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(result.has("boulder_pushed"), JSON.stringify(result))
	assert_eq(_boulder_at(world, Vector2i(4, 10)).cell, Vector2i(4, 10))


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


func test_gold_profile_specials_normalize_onto_the_crystal_handlers() -> void:
	# data/events/special_pointers.asm's SpecialsPointers shifts by one from
	# BattleTowerFade at Crystal 47, and Crystal's mobile block at 109 pushes the
	# DST entries to 166 and 167. Without the profile split these raw Gold bytes
	# reach RestartMapMusic, ToggleMaptileDecorations and PrintDiploma instead.
	var gold_directory: String = RomCache.directory_for(&"testworldgoldspecial", "9876543210fedcba")
	RomCache.clear(gold_directory)
	RomCache.prepare(gold_directory)
	var saved_directory: String = _directory
	_directory = gold_directory
	_write_cache("gold")

	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(gold_directory))
	scripts["48:6400"] = [
		Gen2WorldScript.SETVAL, 1,
		Gen2WorldScript.SPECIAL, 61, 0, # HealMachineAnim
		Gen2WorldScript.GOLD_END,
	]
	scripts["48:6410"] = [
		Gen2WorldScript.SPECIAL, 108, 0, # InitialSetDSTFlag
		Gen2WorldScript.YESORNO, Gen2WorldScript.GOLD_END,
	]
	scripts["48:6420"] = [
		Gen2WorldScript.SPECIAL, 73, 0, # ToggleDecorationsVisibility
		Gen2WorldScript.GOLD_ENDCALLBACK,
	]
	scripts["48:6430"] = [
		Gen2WorldScript.SPECIAL, 110, 0, # MrChrono, absent from Crystal
		Gen2WorldScript.GOLD_END,
	]
	RomCache.write_json(RomCache.world_scripts_path(gold_directory), scripts)
	_directory = saved_directory

	var data: GameData = GameData.open_directory(gold_directory)
	assert_eq(data.id, &"gold")

	var heal := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6400,
	})
	var heal_result: Dictionary = heal.advance()
	assert_eq(heal_result["status"], &"complete", JSON.stringify(heal_result))
	assert_eq(
		_event_value(heal_result["events"], &"presentation_special_applied", "kind"),
		&"heal_machine_anim",
		JSON.stringify(heal_result),
	)
	assert_eq(
		int(_event_value(heal_result["events"], &"presentation_special_applied", "machine_type")),
		1,
		JSON.stringify(heal_result),
	)

	var dst := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6410,
		"clock": {"day": 1, "hour": 10, "minute": 5},
	})
	assert_eq(dst.advance()["event"]["text"], "10:05 DST,\nis that OK?")
	assert_eq(dst.advance(true)["event"]["type"], &"choice")
	var dst_result: Dictionary = dst.advance(true, 0)
	assert_eq(dst_result["status"], &"complete", JSON.stringify(dst_result))
	assert_true(dst_result["dst_enabled"])

	var decoration_state := Gen2WorldState.new()
	var decoration := Gen2WorldScriptRunner.begin(data, decoration_state, {
		"kind": &"test", "bank": 48, "script": 0x6420,
	})
	var decoration_result: Dictionary = decoration.advance()
	assert_eq(decoration_result["status"], &"complete", JSON.stringify(decoration_result))
	assert_eq(
		_event_value(decoration_result["events"], &"decoration_callback_applied", "kind"),
		&"toggle_decorations_visibility",
		JSON.stringify(decoration_result),
	)
	for flag: int in [
		Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_CONSOLE,
		Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_DOLL_1,
		Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_DOLL_2,
		Gen2WorldScriptRunner.EVENT_PLAYERS_HOUSE_2F_BIG_DOLL,
	]:
		assert_true(decoration_state.is_event_flag_active(flag))

	var chrono := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6430,
	})
	var chrono_result: Dictionary = chrono.advance()
	assert_eq(chrono_result["status"], &"failed", JSON.stringify(chrono_result))
	assert_eq(chrono_result["reason"], &"unsupported_phone_special")

	RomCache.clear(gold_directory)


## Script_checkver answers GS_VERSION into wScriptVar, which
## constants/misc_constants.asm defines as 0 for Gold and 1 for Silver;
## pokecrystal defines it 0 unconditionally. RadioTower5FRocketBossScript is the
## one script on the walked route that reads it, and its `iftrue` is what
## chooses the Silver Wing over the Rainbow Wing, so the two profiles have to
## disagree here and Crystal has to answer with Gold. The opcode is $18 in both
## pins, below raw_opcode()'s $52 shift, so only `end` is profile split.
func test_checkver_answers_the_cartridges_own_gs_version() -> void:
	var address: int = 0xD1D8
	for row: Array in [
		["gold", 0, "0f1e2d3c4b5a6978"],
		["silver", 1, "69780f1e2d3c4b5a"],
		["", 0, ""],
	]:
		var game_id: String = String(row[0])
		var expected: int = int(row[1])
		var crystal: bool = game_id.is_empty()
		var directory: String = _directory
		var saved_directory: String = _directory
		if not crystal:
			directory = RomCache.directory_for(
				StringName("testworldver%s" % game_id), String(row[2])
			)
			RomCache.clear(directory)
			RomCache.prepare(directory)
			_directory = directory
			_write_cache(game_id)
			_directory = saved_directory

		var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(directory))
		scripts["48:6B00"] = [
			Gen2WorldScript.CHECKVER,
			Gen2WorldScript.WRITEMEM, address & 0xFF, address >> 8,
			Gen2WorldScript.END if crystal else Gen2WorldScript.GOLD_END,
		]
		RomCache.write_json(RomCache.world_scripts_path(directory), scripts)

		var data: GameData = GameData.open_directory(directory)
		var state := Gen2WorldState.new()
		var runner := Gen2WorldScriptRunner.begin(data, state, {
			"kind": &"test", "bank": 48, "script": 0x6B00,
		})
		var result: Dictionary = runner.advance()
		assert_eq(result["status"], &"complete", JSON.stringify(result))
		## Written rather than branched on, so the value itself is pinned: an
		## `iftrue` would pass for any non-zero answer.
		assert_eq(
			state.script_memory(address), expected,
			"checkver on %s" % (game_id if not crystal else "crystal"),
		)
		if not crystal:
			RomCache.clear(directory)


func test_fade_out_to_white_is_presentation_on_both_profiles() -> void:
	# Slowpoke Well's cleared script runs FadeOutToWhite before HealParty
	# (maps/SlowpokeWellB1F.asm, TrainerGruntM1). It is index 46 in both pins,
	# ahead of Crystal's inserted BattleTowerFade at 47, so the raw byte needs
	# no profile mapping.
	assert_eq(Gen2WorldScript.special_index(46, false), 46)
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6A00"] = [Gen2WorldScript.SPECIAL, 46, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6A00,
	})
	var result: Dictionary = runner.advance()
	## `ConvertTimePals*HL` spends `ld c, 2` on each of its four rows, so the
	## script holds for eight frames rather than running straight on.
	assert_eq(result["status"], &"waiting", JSON.stringify(result))
	assert_eq(int(result["event"]["frames"]), 8, JSON.stringify(result))
	assert_eq(
		int(_event_value(result["events"], &"presentation_special_applied", "special")),
		46,
		JSON.stringify(result),
	)
	assert_eq(
		_event_value(result["events"], &"presentation_special_applied", "orders"),
		Gen2WorldPalette.FADE_OUT_ORDERS,
		JSON.stringify(result),
	)


## `BattleTowerFade` is `FadeOutToWhite`'s four rows with `ld c, 7` instead of
## `ld c, 2`, and it is Crystal's own insertion at 47, which is why the four
## either side of it need no profile mapping.
func test_battle_tower_fade_walks_the_white_rows_at_seven_frames_each() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6A40"] = [
		Gen2WorldScript.SPECIAL,
		Gen2WorldScriptRunner.SPECIAL_BATTLE_TOWER_FADE, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6A40,
	})
	var result: Dictionary = runner.advance()
	assert_eq(result["status"], &"waiting", JSON.stringify(result))
	assert_eq(int(result["event"]["frames"]), 28, JSON.stringify(result))
	assert_eq(
		int(_event_value(result["events"], &"presentation_special_applied", "step_frames")),
		Gen2WorldPalette.BATTLE_TOWER_FADE_STEP_FRAMES,
		JSON.stringify(result),
	)


## `FadeOutToBlack` and `FadeInFromBlack` walk the other half of `.cgbfade`, and
## neither runs `FillWhiteBGColor`, so colour 0 stays the map's own.
func test_the_two_black_fades_walk_the_dark_rows_without_the_white_fill() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6A60"] = [
		Gen2WorldScript.SPECIAL,
		Gen2WorldScriptRunner.SPECIAL_FADE_OUT_TO_BLACK, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6A60,
	})
	var result: Dictionary = runner.advance()
	assert_eq(result["status"], &"waiting", JSON.stringify(result))
	assert_eq(
		_event_value(result["events"], &"presentation_special_applied", "orders"),
		Gen2WorldPalette.FADE_TO_BLACK_ORDERS,
		JSON.stringify(result),
	)
	assert_false(
		bool(_event_value(result["events"], &"presentation_special_applied", "white_fill")),
		JSON.stringify(result),
	)
	## `FadeOutToWhite` is the one that does, which is what says the flag is read
	## rather than always false.
	assert_true(
		Gen2WorldScriptRunner.SPECIAL_FADE_OUT_TO_WHITE
			in Gen2WorldScriptRunner.FADE_WHITE_FILL_SPECIALS
	)


## `CheckFirstMonIsEgg` reads slot zero alone and names it on both branches,
## since `GetPokemonName` runs before either `ld [wScriptVar]` is reached.
func test_check_first_mon_is_egg_reads_slot_zero_and_names_it() -> void:
	for is_egg: bool in [true, false]:
		var result: Array = _events_answering_special(
			90, 1 if is_egg else 0, 0x6A80,
			[172] as Array[int], [is_egg], [true], [70], [172], ["PICHU"]
		)
		assert_true(_flag_31_set(result), "egg %s" % is_egg)
		assert_eq(
			_event_value(result[0]["events"], &"text_buffer_changed", "value"),
			"PICHU", "GetPokemonName runs on both branches",
		)


## `GetFirstPokemonHappiness` walks past every EGG in the list rather than
## reading slot zero, which is the one step a reading of it drops.
func test_first_pokemon_happiness_skips_the_eggs_in_front_of_it() -> void:
	var result: Array = _events_answering_special(
		89, 200, 0x6AA0,
		[172, 25] as Array[int], [true, false], [true, true], [10, 200], [25],
		["PICHU", "PIKACHU"]
	)
	assert_true(_flag_31_set(result))
	## The box it fills names the member it answered for, not slot zero.
	assert_eq(
		_event_value(result[0]["events"], &"text_buffer_changed", "value"), "PIKACHU"
	)


## `CheckOwnMon` is three tests, not one: the species, the player's ID and the
## OT name. A traded mon of the right species owns nothing.
func test_mon_check_refuses_a_party_member_with_another_trainers_ot() -> void:
	for owned: Array in [[25], []]:
		var result: Array = _events_answering_special(
			151, 1 if not owned.is_empty() else 0, 0x6AC0,
			[25] as Array[int], [false], [not owned.is_empty()], [70], owned,
			["PIKACHU"], 25
		)
		assert_true(_flag_31_set(result), JSON.stringify(owned))


## `BeastsCheck` leaves the species it stopped on in wScriptVar, which is what
## `.notexist`'s own `xor a` does not do: the caller branches on which beast is
## missing rather than on a plain FALSE.
func test_beasts_check_answers_the_first_beast_the_player_does_not_own() -> void:
	var cases: Array = [[[], 243], [[243], 244], [[243, 244], 245], [[243, 244, 245], 1]]
	for case: Array in cases:
		var result: Array = _events_answering_special(
			150, int(case[1]), 0x6AE0,
			[25] as Array[int], [false], [true], [70], case[0], ["PIKACHU"]
		)
		assert_true(_flag_31_set(result), JSON.stringify(case))


## One script that runs [param special] with [param value] loaded and sets event
## 31 only when it answers [param expected], which is how a wScriptVar the API
## does not expose is read: the branch the cartridge's own caller takes.
func _events_answering_special(
	special: int, expected: int, address: int,
	species: Array[int], eggs: Array, own_ot: Array, happiness: Array,
	owned_species: Array, names: Array, value: int = -1
) -> Array:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	var refused: int = address + 0x10
	var body: Array = []
	if value >= 0:
		body.append_array([Gen2WorldScript.SETVAL, value])
	body.append_array([
		Gen2WorldScript.SPECIAL, special, 0,
		Gen2WorldScript.IFNOTEQUAL, expected, refused & 0xFF, (refused >> 8) & 0xFF,
		Gen2WorldScript.SETEVENT, 31, 0,
		Gen2WorldScript.END,
	])
	scripts["48:%04X" % address] = body
	scripts["48:%04X" % refused] = [Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var moves: Array = []
	for _slot: int in species.size():
		moves.append([])
	world.set_party_summary(
		species.size(), false, species, moves, names, eggs,
		{"own_ot": own_ot, "happiness": happiness, "owned_species": owned_species},
		[]
	)
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 7, "y": 6, "script": address,
	}]
	var result: Array = world.dispatch_script_events(Vector2i(7, 6))
	result.append(world)
	return result


## Whether the branch was taken, read off the world the helper appended.
func _flag_31_set(result: Array) -> bool:
	var world: Gen2WorldAPI = result.back() as Gen2WorldAPI
	return world != null and world.state.is_event_flag_active(31)


func test_fade_in_from_white_is_presentation_on_both_profiles() -> void:
	# maps/OlivineLighthouse6F.asm's OlivineLighthouseJasmine runs FadeOutToWhite
	# and then FadeInFromWhite either side of the Ampharos cry, and that script is
	# what clears EVENT_OLIVINE_GYM_JASMINE. FadeInFromWhite is 49 in Crystal and
	# 48 in Gold/Silver, one behind Crystal's inserted BattleTowerFade at 47.
	assert_eq(Gen2WorldScript.special_index(48, false), 49)
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6A20"] = [Gen2WorldScript.SPECIAL, 49, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6A20,
	})
	var result: Dictionary = runner.advance()
	## `ConvertTimePals*HL` spends `ld c, 2` on each of its four rows, so the
	## script holds for eight frames rather than running straight on.
	assert_eq(result["status"], &"waiting", JSON.stringify(result))
	assert_eq(int(result["event"]["frames"]), 8, JSON.stringify(result))
	assert_eq(
		int(_event_value(result["events"], &"presentation_special_applied", "special")),
		49,
		JSON.stringify(result),
	)
	assert_eq(
		_event_value(result["events"], &"presentation_special_applied", "orders"),
		Gen2WorldPalette.FADE_IN_ORDERS,
		JSON.stringify(result),
	)


## Ilex Forest's Farfetch'd herding is a ten-position state machine on
## wFarfetchdPosition, read and written with these three commands
## (maps/IlexForest.asm).
func test_script_memory_commands_read_write_and_commit_a_byte() -> void:
	var address: int = 0xD1D6
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6C00"] = [
		Gen2WorldScript.LOADMEM, address & 0xFF, address >> 8, 5,
		Gen2WorldScript.READMEM, address & 0xFF, address >> 8,
		Gen2WorldScript.IFEQUAL, 5, 0x10, 0x6C,
		Gen2WorldScript.END,
	]
	# Reached only when the readmem answered 5: writemem then stores wScriptVar.
	scripts["48:6C10"] = [
		Gen2WorldScript.SETVAL, 9,
		Gen2WorldScript.WRITEMEM, address & 0xFF, address >> 8,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6C00,
	})
	var result: Dictionary = runner.advance()
	assert_eq(result["status"], &"complete", JSON.stringify(result))
	assert_eq(state.script_memory(address), 9, "the ifequal branch ran and committed")


## Script_addval adds into wScriptVar, one byte, so it wraps in the variable
## itself. The Goldenrod switch room turns a switch off with `addval -1` on
## wUndergroundSwitchPositions and then branches on the result
## (maps/GoldenrodUndergroundSwitchRoomEntrances.asm).
func test_addval_wraps_in_the_script_variable_like_the_source_byte_add() -> void:
	var address: int = 0xD1D7
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# setval 1, addval -1, writemem, then branch on zero.
	scripts["48:6C20"] = [
		Gen2WorldScript.SETVAL, 1,
		Gen2WorldScript.ADDVAL, 0xFF,
		Gen2WorldScript.WRITEMEM, address & 0xFF, address >> 8,
		Gen2WorldScript.IFEQUAL, 0, 0x30, 0x6C,
		Gen2WorldScript.END,
	]
	scripts["48:6C30"] = [
		Gen2WorldScript.SETVAL, 42,
		Gen2WorldScript.WRITEMEM, address & 0xFF, address >> 8,
		Gen2WorldScript.END,
	]
	# The other edge: 0 - 1 is 255, not -1, so the wrapped value is what a
	# later ifequal and any writemem see.
	scripts["48:6C40"] = [
		Gen2WorldScript.SETVAL, 0,
		Gen2WorldScript.ADDVAL, 0xFF,
		Gen2WorldScript.WRITEMEM, address & 0xFF, address >> 8,
		Gen2WorldScript.IFEQUAL, 255, 0x50, 0x6C,
		Gen2WorldScript.END,
	]
	scripts["48:6C50"] = [
		Gen2WorldScript.SETVAL, 7,
		Gen2WorldScript.WRITEMEM, address & 0xFF, address >> 8,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	var down := Gen2WorldState.new()
	var to_zero := Gen2WorldScriptRunner.begin(data, down, {
		"kind": &"test", "bank": 48, "script": 0x6C20,
	})
	assert_eq(to_zero.advance()["status"], &"complete")
	assert_eq(down.script_memory(address), 42, "1 + -1 branched as 0")

	var under := Gen2WorldState.new()
	var to_255 := Gen2WorldScriptRunner.begin(data, under, {
		"kind": &"test", "bank": 48, "script": 0x6C40,
	})
	assert_eq(to_255.advance()["status"], &"complete")
	assert_eq(under.script_memory(address), 7, "0 + -1 branched as 255")


## Burned Tower's rival scene opens the hole under the player and then relies on
## warpcheck to drop them through it, so the command has to resolve the warp at
## the standing cell rather than one the script names.
func test_warpcheck_takes_the_warp_the_player_is_standing_on() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6D00"] = [0x8E, Gen2WorldScript.END] # warpcheck, raw
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var world: Gen2WorldAPI = _world(Vector2i(6, 6))
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 6, "y": 6, "script": 0x6D00,
	}]
	var before: Vector2i = world.map_id()

	var results: Array = world.dispatch_script_events(Vector2i(6, 6))
	assert_eq(results[0]["status"], &"complete", JSON.stringify(results))
	assert_true(results[0]["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"warp_check" and bool(event.get("taken", false))
	), JSON.stringify(results[0]["events"]))
	assert_ne(world.map_id(), before, "the standing warp was taken")


## CheckWarpCollision gates every warp on the tile's own code, so a warp_event
## on ordinary floor is inert. Burned Tower B1F's (10,8) is one, and the walk to
## the beasts crosses it.
func test_a_warp_event_on_ordinary_floor_never_fires() -> void:
	var world: Gen2WorldAPI = _world()
	var warp: Dictionary = world.warp_at(Vector2i(6, 6))
	assert_false(warp.is_empty(), "the fixture keeps its warp record")
	assert_eq(world.collision_code_at(Vector2i(6, 6)), 0x60)
	assert_true(bool(world.try_warp(Vector2i(6, 6)).get("ok", false)))

	var floor_world: Gen2WorldAPI = _world()
	floor_world.current_map.collision[6 * 16 + 6] = 0x00
	assert_false(floor_world.warp_at(Vector2i(6, 6)).is_empty())
	assert_true(
		floor_world.try_warp(Vector2i(6, 6)).is_empty(),
		"a warp record on floor answers nothing",
	)


## CheckDirectionalWarp clears carry on the four warp carpets, so CheckWarpTile
## refuses them and the step that lands on one takes nothing. Only
## DoPlayerMovement.CheckWarp takes a carpet, and only for the direction it names
## and only once the facing agrees: an interior door is stood on first and walked
## into afterwards.
func test_a_warp_carpet_is_walked_into_rather_than_landed_on() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(13, 5))
	assert_eq(world.collision_code_at(Vector2i(13, 4)), 0x78, "COLL_WARP_CARPET_UP")

	assert_true(bool(world.move_result(Vector2i.UP).get("ok", false)), "the carpet is walkable")
	assert_eq(world.player_cell, Vector2i(13, 4))
	assert_false(world.warp_pending(), "and landing on it warps nothing")

	_finish_player_step(world)
	assert_false(world.edge_warp_ready(Vector2i.LEFT), "only the direction the carpet names")
	assert_true(world.edge_warp_ready(Vector2i.UP), "which the step up is already facing")

	var taken: Dictionary = world.player_input_move(Vector2i.UP)
	assert_eq(StringName(taken.get("kind", &"")), &"edge_warp")
	assert_false(world.player_step_in_progress(), ".StandInPlace spends no step")
	assert_eq(world.player_cell, Vector2i(13, 4), "the warp itself is the host's")


## `ld a, [wPlayerDirection] / rrca / rrca` against wWalkingDirection: the press
## that arrives with the wrong facing turns, and the one after it warps.
func test_a_warp_carpet_facing_the_wrong_way_turns_first() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(13, 4))
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	assert_false(world.edge_warp_ready(Vector2i.UP), "facing down, so no warp yet")
	assert_eq(StringName(world.player_input_move(Vector2i.UP).get("kind", &"")), &"turn")
	_finish_player_step(world)
	assert_eq(
		StringName(world.player_input_move(Vector2i.UP).get("kind", &"")), &"edge_warp",
		"and the second press takes it",
	)


## Script_startbattle copies wBattleResult into wScriptVar, and WIN is zero
## there, so a script branching straight off the result reads a win as false.
func test_a_won_battle_leaves_the_source_win_result_in_the_script_value() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6D20"] = [
		0x5D, 16, 5, # loadwildmon, raw
		0x5F, # startbattle, raw
		Gen2WorldScript.IFEQUAL, Gen2WorldScriptRunner.BATTLE_RESULT_LOSE, 0x30, 0x6D,
		Gen2WorldScript.SETEVENT, 12, 0,
		Gen2WorldScript.END,
	]
	scripts["48:6D30"] = [Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 8, "y": 6, "script": 0x6D20,
	}]
	var waiting: Array = world.dispatch_script_events(Vector2i(8, 6))
	assert_eq(waiting[0]["status"], &"waiting", JSON.stringify(waiting))
	var completed: Array = world.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
	})
	assert_eq(completed[0]["status"], &"complete", JSON.stringify(completed))
	assert_true(
		world.state.is_event_flag_active(12),
		"ifequal LOSE must not match after a win",
	)


func test_init_roam_mons_reports_the_seeded_roaming_records() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6D10"] = [Gen2WorldScript.SPECIAL, 105, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 8, "y": 6, "script": 0x6D10,
	}]
	var results: Array = world.dispatch_script_events(Vector2i(8, 6))
	assert_eq(results[0]["status"], &"complete", JSON.stringify(results))
	var reported: Variant = _event_value(
		results[0]["events"], &"roaming_mons_initialized", "count"
	)
	assert_eq(int(reported), world.state.roaming_mons().size())
	assert_gt(int(reported), 0, "the records the special reports are already seeded")


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


## A world facing a boulder whose script is `jumpstd StrengthBoulderScript`, the
## shape every boulder object in every map has. No standard-script entry is
## written for index 14 on purpose: the intercept must answer before the table is
## ever consulted, because the real entry is `farsjump AskStrengthScript` and
## that script's first command is a `callasm` this runner cannot execute.
func _boulder_script_world(
	moves: Array, badge: bool = true, strength: bool = false
) -> Gen2WorldAPI:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6100"] = [Gen2WorldScript.JUMPSTD, 14, 0]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)

	var world: Gen2WorldAPI = _world(Vector2i(11, 4))
	var crystal: bool = Gen2WorldState.is_crystal_profile(world.data)
	if badge:
		world.state.set_engine_flag(
			Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_PLAIN, crystal)
		)
	if strength:
		world.state.set_engine_flag(Gen2WorldState.strength_active_flag(crystal))
	world.current_map.events["objects"].append({
		"sprite": 1, "x": 11, "y": 5,
		"movement": Gen2WorldObject.MOVEMENT_STRENGTH_BOULDER,
		"script": 0x6100, "event_flag": 0xFFFF,
	})
	world.reload_current_map()
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	world.set_party_summary(1, false, [25] as Array[int], moves, ["CHIKORITA"])
	return world


## TryStrengthOW answers 1 when CheckPartyMove finds nothing or the badge is
## missing, and AskStrengthScript's `.DontMeetRequirements` shows
## BouldersMayMoveText for it.
func test_boulder_script_reports_no_strength_without_the_move_or_the_badge() -> void:
	var no_move: Gen2WorldAPI = _boulder_script_world([[]])
	var without_move: Array = no_move.interact()
	assert_eq(without_move[0]["status"], &"waiting", JSON.stringify(without_move[0]))
	assert_eq(
		String(without_move[0]["event"]["text"]),
		Gen2WorldScriptRunner.STRENGTH_MAY_MOVE_TEXT
	)
	assert_eq(no_move.run_event_queue(true)[0]["status"], &"complete")
	assert_false(no_move.strength_active())

	var no_badge: Gen2WorldAPI = _boulder_script_world(
		[[Gen2WorldFieldMove.MOVE_STRENGTH]], false
	)
	var without_badge: Array = no_badge.interact()
	assert_eq(
		String(without_badge[0]["event"]["text"]),
		Gen2WorldScriptRunner.STRENGTH_MAY_MOVE_TEXT
	)
	assert_false(no_badge.strength_active())


## TryStrengthOW answers 2 once the flag is set, and `.AlreadyUsedStrength` shows
## BouldersMoveText without asking again.
func test_boulder_script_reports_boulders_already_movable() -> void:
	var world: Gen2WorldAPI = _boulder_script_world(
		[[Gen2WorldFieldMove.MOVE_STRENGTH]], true, true
	)
	var results: Array = world.interact()
	assert_eq(
		String(results[0]["event"]["text"]),
		Gen2WorldScriptRunner.STRENGTH_BOULDERS_MOVE_TEXT
	)
	assert_eq(world.run_event_queue(true)[0]["status"], &"complete")
	assert_true(world.strength_active())


## TryStrengthOW answers 0, so `.AskStrength` opens the yes/no. A yes runs
## Script_UsedStrength: SetStrengthFlag, then its two texts.
func test_boulder_script_asks_and_a_yes_sets_the_flag() -> void:
	var world: Gen2WorldAPI = _boulder_script_world([[Gen2WorldFieldMove.MOVE_STRENGTH]])
	var asked: Array = world.interact()
	assert_eq(
		String(asked[0]["event"]["text"]), Gen2WorldScriptRunner.STRENGTH_ASK_TEXT
	)
	assert_false(world.strength_active())

	var choice: Array = world.run_event_queue(true)
	assert_eq(StringName(choice[0]["event"]["type"]), &"choice")
	assert_eq(choice[0]["event"]["choices"], [&"yes", &"no"])

	var used: Array = world.run_event_queue(true, 0)
	assert_eq(String(used[0]["event"]["text"]), "CHIKORITA used\nSTRENGTH!")

	var boulders: Array = world.run_event_queue(true)
	assert_eq(String(boulders[0]["event"]["text"]), "CHIKORITA can\nmove boulders.")

	assert_eq(world.run_event_queue(true)[0]["status"], &"complete")
	assert_true(world.strength_active())


## A no falls through to closetext/end, so nothing is committed.
func test_boulder_script_leaves_the_flag_clear_on_a_no() -> void:
	var world: Gen2WorldAPI = _boulder_script_world([[Gen2WorldFieldMove.MOVE_STRENGTH]])
	world.interact()
	world.run_event_queue(true)
	var refused: Array = world.run_event_queue(true, 1)
	assert_eq(refused[0]["status"], &"complete", JSON.stringify(refused[0]))
	assert_false(world.strength_active())


## CheckPartyMove has nothing to read without the mirror, so the script fails
## rather than answering "nobody knows it", the way VAR_PARTYCOUNT does.
func test_boulder_script_fails_without_a_party_summary() -> void:
	var world: Gen2WorldAPI = _boulder_script_world([[Gen2WorldFieldMove.MOVE_STRENGTH]])
	world.clear_party_summary()
	var results: Array = world.interact()
	assert_eq(results[0]["status"], &"failed", JSON.stringify(results[0]))
	assert_eq(results[0]["reason"], &"missing_party_summary")


func test_interact_finds_no_tile_collision_script_for_an_untabled_code() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	assert_eq(world.collision_code_at(world.facing_cell()), 0)
	assert_eq(world.interact(), [])


## A world with a scripted object two cells ahead of [param stand], for
## CheckFacingObject's counter rule.
func _counter_world(stand: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = _world(stand)
	world.current_map.events["objects"].append({
		"sprite": 1, "x": stand.x, "y": stand.y + 2,
		"script": 0x6040, "event_flag": 0xFFFF,
	})
	world.reload_current_map()
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	return world


## CheckFacingObject doubles the facing distance when the faced tile is a
## counter, which is how a mart clerk or the Radio Tower's Radio Card woman is
## talked to from outside the desk they stand behind.
func test_interact_reaches_an_object_across_a_counter() -> void:
	var world: Gen2WorldAPI = _counter_world(Vector2i(13, 8))
	assert_eq(world.collision_code_at(world.facing_cell()), Gen2WorldCollision.COLL_COUNTER)
	assert_eq(world.object_facing_cell(), Vector2i(13, 10))
	var results: Array = world.interact()
	assert_false(results.is_empty())
	assert_eq(results[0]["status"], &"complete", JSON.stringify(results[0]))
	assert_eq(world.state.map_scene(1, 1), 3)


## The same geometry without a counter answers nothing: the doubling is the
## counter's, not a general two-cell reach.
func test_interact_does_not_reach_an_object_two_cells_away_without_a_counter() -> void:
	var world: Gen2WorldAPI = _counter_world(Vector2i(11, 8))
	assert_eq(world.collision_code_at(world.facing_cell()), 0)
	assert_eq(world.object_facing_cell(), Vector2i(11, 9))
	assert_eq(world.interact(), [])


## $98 ships in CheckCounterTile's pair but no map uses it. Both codes answer.
func test_counter_codes_are_the_pinned_pair() -> void:
	assert_true(Gen2WorldCollision.is_counter(Gen2WorldCollision.COLL_COUNTER))
	assert_true(Gen2WorldCollision.is_counter(Gen2WorldCollision.COLL_COUNTER_98))
	assert_eq(Gen2WorldCollision.COLL_COUNTER, 0x90)
	assert_eq(Gen2WorldCollision.COLL_COUNTER_98, 0x98)
	assert_false(Gen2WorldCollision.is_counter(Gen2WorldCollision.COLL_PC))


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
	assert_eq(world.player_pixel_position(), Gen2WorldAPI.PLAYER_VIEW_CELL * 16)


func test_the_camera_origin_follows_the_player_one_pass_behind() -> void:
	var world: Gen2WorldAPI = _world()
	# Standing still, the hardware page origin and the camera agree.
	assert_eq(world.player_position_cells(), Vector2(8.0, 6.0))
	assert_eq(world.visible_origin_cell(), Vector2i(4, 2))
	assert_eq(world.visible_origin_cells(), Vector2(4.0, 2.0))

	assert_true(world.move(Vector2i.LEFT))
	# Crossing an even-cell boundary moves the surrounding-page anchor by a whole
	# block at once. The fine scroll still frames the player's presentation cell.
	assert_eq(world.visible_origin_cell(), Vector2i(2, 2))
	assert_eq(world.player_position_cells(), Vector2(8.0, 6.0))
	assert_eq(world.visible_origin_cells(), Vector2(4.0, 2.0))

	# `ScrollScreen` runs after `NextOverworldFrame`, so the scroll a pass
	# computed is written two frames after the sprite moved: the camera stands
	# still on the pass the walk starts and the player is drawn two pixels ahead
	# of it, which is `sprite_x - scx` of 62 on the cartridge.
	assert_true(world.advance_player_step_pass())
	assert_eq(world.player_position_cells(), Vector2(7.875, 6.0))
	assert_eq(world.visible_origin_cells(), Vector2(4.0, 2.0))
	assert_eq(world.player_pixel_position(), Vector2i(62, 64))

	# The step lands on the committed cell with the camera still one pass behind,
	# and the pass after it, which moves nothing, is where the two agree again.
	_finish_player_step(world)
	assert_false(world.player_step_in_progress())
	assert_eq(world.player_position_cells(), Vector2(7.0, 6.0))
	assert_eq(world.visible_origin_cells(), Vector2(3.125, 2.0))
	assert_false(world.advance_player_step_pass())
	assert_eq(world.visible_origin_cells(), Vector2(world.visible_screen_origin_cell()))
	assert_eq(world.player_pixel_position(), Gen2WorldAPI.PLAYER_VIEW_CELL * 16)


func test_the_interpolated_camera_origin_runs_off_the_map_like_the_page_does() -> void:
	var corner: Gen2WorldAPI = _world(Vector2i(15, 11))
	assert_eq(corner.visible_origin_cell(), Vector2i(10, 6))
	assert_eq(corner.visible_origin_cells(), Vector2(11.0, 7.0))
	var top_left: Gen2WorldAPI = _world(Vector2i.ZERO)
	assert_eq(top_left.visible_origin_cells(), Vector2(-4.0, -4.0))


## One call, one hardware frame, whatever the host's frame rate is. The stall
## cap lives on the pump that feeds this
## (tests/integration/test_world_frame_pump.gd), not on the countdown.
func test_advance_player_step_spends_exactly_one_frame_per_call() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(world.move(Vector2i.LEFT))
	assert_eq(world.player_cell, Vector2i(7, 6))

	assert_true(world.advance_player_step_pass())
	assert_eq(world.player_step_offset_cells(), Vector2(0.875, 0.0))

	# STEP_PASSES_WALK is 8, one of which is spent above.
	for _frame: int in 4:
		assert_true(world.advance_player_step_pass())
	assert_eq(world.player_step_offset_cells(), Vector2(3.0 / 8.0, 0.0))
	assert_eq(world.player_cell, Vector2i(7, 6))

	for _frame: int in 3:
		assert_true(world.advance_player_step_pass())
	assert_false(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2.ZERO)
	assert_eq(world.player_cell, Vector2i(7, 6))
	assert_eq(world.player_walk_frame(), 0, "SetFacingStanding restores the resting cel")
	assert_false(world.advance_player_step_pass())


func test_player_step_does_not_affect_cell_collision_or_events() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(world.move(Vector2i.LEFT))
	assert_eq(world.player_cell, Vector2i(7, 6))
	assert_true(world.player_step_in_progress())
	var during_events: Array = world.dispatch_events()
	var during_permission: int = world.collision_permission_at(world.player_cell)
	var during_walkable: bool = world.can_walk_to(Vector2i(6, 6))

	_finish_player_step(world)
	assert_false(world.player_step_in_progress())

	# A presentation offset in flight never changes what resolves off the
	# already-committed cell.
	assert_eq(world.dispatch_events(), during_events)
	assert_eq(world.collision_permission_at(world.player_cell), during_permission)
	assert_eq(world.can_walk_to(Vector2i(6, 6)), during_walkable)
	assert_eq(world.player_cell, Vector2i(7, 6))


## CheckMovingOffEdgeOfMap only answers a step that has landed, so the crossing
## costs the frames any other step does: the map is swapped under a step that is
## still running, and the cell it is drawn walking out of is the connection
## strip the neighbour's edge was drawn in.
func test_connection_transition_spends_a_step() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(14, 6))
	assert_true(world.move(Vector2i.RIGHT))
	assert_eq(world.player_cell, Vector2i(15, 6))
	assert_true(world.player_step_in_progress())

	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_true(result["ok"])
	assert_eq(result["kind"], &"connection")
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_true(world.player_step_in_progress())
	assert_eq(world.player_step_offset_cells(), Vector2(-1, 0))
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_player_step_pass()
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

	_finish_player_step(world)
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
		world.advance_object_steps_pass(random)


## Spends the frames the player's step still owes. Bounded rather than a while
## loop so a step that never ends fails the assertion after it instead of
## hanging the suite.
func _finish_player_step(world: Gen2WorldAPI) -> void:
	for _frame: int in 64:
		if not world.player_step_in_progress():
			return
		world.advance_player_step_pass()


func test_wander_object_commits_its_cell_and_eases_over_the_slow_step() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 90210
	var start: Vector2i = object.cell

	# The first frame is the object's turn at the movement function.
	assert_true(world.advance_object_steps_pass(random))
	assert_true(object.is_stepping())
	# StepVectors' slow row is 16 frames, half the player's walking speed.
	assert_eq(object.step_passes_total, Gen2WorldAPI.STEP_PASSES_NPC_WALK)
	# The cell commits when the step starts, exactly as InitStep and the
	# player's own walk do; only the drawn offset trails behind it.
	assert_ne(object.cell, start)
	assert_eq(object.step_offset_cells(), Vector2(start - object.cell))

	# The deciding frame starts the step without spending one of its frames,
	# the way the source runs the movement function and the step function on
	# separate frames, so the full duration follows it.
	_advance_object_frames(world, Gen2WorldAPI.STEP_PASSES_NPC_WALK, random)
	assert_false(object.is_stepping())
	assert_eq(object.step_offset_cells(), Vector2.ZERO)
	assert_eq(abs(object.cell.x - start.x) + abs(object.cell.y - start.y), 1)


## CanObjectMoveInDirection's swimming branch: WillObjectBumpIntoLand refuses
## anything but WATER_TILE, where the not-swimming branch's
## WillObjectBumpIntoWater refuses anything but LAND_TILE.
func test_a_swimming_object_wants_water_where_every_other_object_wants_land() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var object: Gen2WorldObject = world.objects[0]
	object.cell = Vector2i(11, 11)
	object.initial_cell = object.cell
	assert_eq(world.collision_permission_at(Vector2i(12, 11)), Gen2WorldCollision.WATER_TILE)
	assert_eq(world.collision_permission_at(Vector2i(11, 10)), Gen2WorldCollision.LAND_TILE)

	assert_false(object.is_swimming())
	assert_true(world.can_object_walk_to(Vector2i(11, 10), object, Vector2i.UP))
	assert_false(world.can_object_walk_to(Vector2i(12, 11), object, Vector2i.RIGHT))

	object.movement = Gen2WorldObject.MOVEMENT_SWIM_WANDER
	assert_true(object.is_swimming())
	assert_true(world.can_object_walk_to(Vector2i(12, 11), object, Vector2i.RIGHT))
	assert_false(world.can_object_walk_to(Vector2i(11, 10), object, Vector2i.UP))


## WillObjectRemainOnWater's big-object branch checks the two cells newly
## occupied by the moving edge, rather than only the destination anchor.
func test_a_big_object_checks_both_cells_on_its_new_edge() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var object: Gen2WorldObject = world.objects[0]
	object.movement = Gen2WorldObject.MOVEMENT_BIGDOLL
	object.cell = Vector2i(10, 9)
	object.initial_cell = object.cell

	# Moving down adds (10,11) and (11,11). The fixture's latter cell is water;
	# the old one-cell check would incorrectly accept the anchor at (10,10).
	assert_false(world.can_object_walk_to(Vector2i(10, 10), object, Vector2i.DOWN))

	world.current_map.collision[11 * world.current_map.collision_width + 11] = 0
	assert_true(world.can_object_walk_to(Vector2i(10, 10), object, Vector2i.DOWN))


## SPRITEMOVEDATA_SWIM_WANDER was already listed as supported and advancing, so
## before the permission split it was asked to decide every frame and refused
## every frame. Its radius still holds: the source's own bug doc says swimming
## NPCs ignore it, but at these two pins both branches of
## CanObjectMoveInDirection reach the same HasObjectReachedMovementLimit.
func test_a_swim_wander_object_moves_across_its_pond_within_its_radius() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var object: Gen2WorldObject = world.objects[0]
	object.cell = Vector2i(11, 11)
	object.initial_cell = object.cell
	object.movement = Gen2WorldObject.MOVEMENT_SWIM_WANDER
	object.x_radius = 1
	object.y_radius = 1
	var random := RandomNumberGenerator.new()
	random.seed = 90210

	var visited: Dictionary = {object.cell: true}
	for _frame: int in 1024:
		world.advance_object_steps_pass(random)
		visited[object.cell] = true
	assert_eq(
		visited.keys().size(), 2,
		"a swimming object should reach both pond cells and neither bank: %s" % [visited.keys()]
	)
	assert_true(visited.has(Vector2i(11, 11)))
	assert_true(visited.has(Vector2i(12, 11)))


func test_wander_object_waits_its_rolled_idle_before_deciding_again() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 4242

	_advance_object_frames(world, 1 + Gen2WorldAPI.STEP_PASSES_NPC_WALK, random)
	assert_false(object.is_stepping())
	# The step's final frame rolls the next wait, exactly as
	# StepFunction_ContinueWalk jumps to RandomStepDuration_Slow. That mask is
	# $7F, so the wait never exceeds 127 frames.
	assert_true(object.is_idle())
	assert_true(object.idle_passes_remaining <= Gen2WorldAPI.IDLE_MASK_SLOW)

	var resting_cell: Vector2i = object.cell
	var idle_frames: int = object.idle_passes_remaining
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

	assert_false(world.advance_object_steps_pass(random))
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
		world.advance_object_steps_pass(random)
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
		assert_true(object.idle_passes_remaining <= mask)


func test_standing_objects_are_never_moved_by_the_driver() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(12, 10))
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 5
	var start: Vector2i = object.cell
	var facing: int = object.facing

	for _frame: int in 300:
		assert_false(world.advance_object_steps_pass(random))
	assert_eq(object.cell, start)
	assert_eq(object.facing, facing)


## One call, one frame. The stall cap is the pump's
## (tests/integration/test_world_frame_pump.gd), so this driver cannot be handed
## a hundred frames by a slow host either.
func test_object_driver_spends_exactly_one_frame_per_call() -> void:
	var world: Gen2WorldAPI = _wandering_world()
	var object: Gen2WorldObject = world.objects[0]
	var random := RandomNumberGenerator.new()
	random.seed = 90210

	# The deciding frame starts the step without spending one of its frames.
	assert_true(world.advance_object_steps_pass(random))
	assert_eq(object.step_passes_remaining, Gen2WorldAPI.STEP_PASSES_NPC_WALK)
	for _frame: int in 4:
		assert_true(world.advance_object_steps_pass(random))
	assert_eq(
		object.step_passes_remaining, Gen2WorldAPI.STEP_PASSES_NPC_WALK - 4
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
		world.advance_object_steps_pass(random)
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
	assert_false(world.advance_object_steps_pass(null))
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
		"48:6080": [0x70, 0, 2, 0x91],
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
	assert_eq(follower.step_passes_total, Gen2WorldAPI.STEP_PASSES_WALK)
	# The follower moved right, into the cell the player left, so it is drawn
	# one cell to the left of its committed cell as the step begins.
	assert_eq(follower.step_offset_cells(), Vector2(-1.0, 0.0))


func test_script_object_visibility_changes_rendering_and_occupancy() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var result: Array = world.dispatch_events(Vector2i(5, 6), true)
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete")
	assert_eq(result[0]["events"][0]["type"], &"object_visibility")
	assert_eq(world.visible_objects().size(), 0)
	assert_true(world.can_walk_to(Vector2i(5, 6)))


func test_event_flags_hide_objects_from_rendering_occupancy_and_dispatch() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	assert_eq(world.dispatch_events(Vector2i(5, 6)).size(), 1)
	assert_false(world.can_walk_to(Vector2i(5, 6)))

	## `LoadObjectMasks` reads the flag once a map load and nothing re-tests it
	## while the map is up, so writing it moves nothing on its own. That is why
	## `appear` and `disappear` exist and edit the struct themselves.
	world.set_event_flag(7)
	assert_eq(world.visible_objects().size(), 1)
	assert_not_null(world.object_at(Vector2i(5, 6)))
	assert_false(world.can_walk_to(Vector2i(5, 6)))

	var reloaded: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(world.data, world.snapshot())
	assert_eq(reloaded.visible_objects().size(), 0)
	assert_null(reloaded.object_at(Vector2i(5, 6)))
	assert_true(reloaded.can_walk_to(Vector2i(5, 6)))
	assert_eq(reloaded.dispatch_events(Vector2i(5, 6)).size(), 0)

	world.clear_event_flag(7)
	assert_eq(world.visible_objects().size(), 1)
	assert_eq(world.dispatch_events(Vector2i(5, 6)).size(), 1)


func test_a_map_entry_masks_on_the_flags_its_own_callbacks_wrote() -> void:
	## `MapSetupScript_Warp` runs `HandleNewMap`'s `MAPCALLBACK_NEWMAP` before
	## `LoadMapObjects` calls `LoadObjectMasks`, so a flag the entry callback set
	## hides its object on that entry rather than on the next map load. Reading
	## the flag while the record is built instead is what put the bedroom's four
	## decorations on screen for a new game.
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	assert_eq(world.visible_objects().size(), 1)

	world.set_event_flag(7)
	var _entry: Array = world.dispatch_map_entry()
	assert_eq(world.visible_objects().size(), 0)
	assert_true(world.can_walk_to(Vector2i(5, 6)))
	assert_eq(world.dispatch_events(Vector2i(5, 6)).size(), 0)

	world.clear_event_flag(7)
	var _reentry: Array = world.dispatch_map_entry()
	assert_eq(world.visible_objects().size(), 1)


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


## `MAPSETUP_ENTER` runs the scene script once, as part of the map load. A host
## that dispatches the same entry twice is dispatching twice, not entering
## twice: a replayed scene walks its `applymovement`s again, which is what put
## the Dragon Shrine's player through the north wall.
func test_a_second_dispatch_of_one_entry_does_not_run_the_scene_again() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# addval 1, so a second run would be visible in the flag it never sets.
	scripts["48:6190"] = [Gen2WorldScript.SETEVENT, 13, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var target_map: Gen2WorldMap = data.world_map(1, 2)
	target_map.scripts["callbacks"] = []
	target_map.scripts["scenes"] = [{"id": 0, "script": 0x6190}]
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 2, Vector2i(2, 2))

	var first: Array = world.dispatch_map_entry()
	assert_eq(first.size(), 1)
	assert_eq(first[0]["source"]["kind"], &"scene")

	var again: Array = world.dispatch_map_entry()
	assert_true(again.is_empty(), "the entry was already dispatched")

	# A warp is a new entry, so the destination's own scene is armed again: the
	# guard is per entry, not once per world.
	world.state.set_event_flag(13, false)
	assert_true(bool(world.try_warp(Vector2i(2, 2)).get("ok", false)), "onto map 1/1")
	world.dispatch_map_entry()
	assert_true(bool(world.try_warp(Vector2i(6, 6)).get("ok", false)), "and back")
	var kinds: Array[StringName] = []
	for result: Dictionary in world.dispatch_map_entry():
		kinds.append(StringName((result.get("source", {}) as Dictionary).get("kind", &"")))
	assert_true(kinds.has(&"scene"), "a warp is a new entry")
	assert_true(world.event_flag_active(13))


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


## Every gym does `setflag` on its badge, then `readvar VAR_BADGES`, then
## branches on the count in the same script (maps/MahoganyGym.asm's
## MahoganyGymActivateRockets). The cartridge has no staging, so the read sees
## the badge just awarded; counting committed flags answered one short and took
## the wrong branch, which left Mahogany's east exit shut for the whole game.
func test_readvar_badges_counts_a_badge_set_earlier_in_the_same_script() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:60A0"] = [
		Gen2WorldScript.SETFLAG, Gen2WorldState.ENGINE_ZEPHYRBADGE, 0,
		Gen2WorldScript.READVAR, 0x07,
		Gen2WorldScript.IFEQUAL, 2, 0xB0, 0x60,
		Gen2WorldScript.END,
	]
	scripts["48:60B0"] = [Gen2WorldScript.SETEVENT, 23, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	## One badge already committed, so the staged one has to make it two.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_HIVEBADGE)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6), state)
	world.current_map.events["coord_events"][0]["script"] = 0x60A0

	var result: Array = world.dispatch_script_events()

	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete")
	assert_true(world.event_flag_active(23), "the two-badge branch was taken")
	assert_eq(world.state.badge_count(), 2)


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
	## Still standing there: the flag hides it on the next map load, not on the
	## `setevent` that wrote it, which is what `restored` below is.
	assert_eq(world.visible_objects().size(), 1)

	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(data, world.snapshot())
	assert_not_null(restored)
	assert_true(restored.event_flag_active(7))
	assert_true(restored.state.hall_of_fame())
	assert_eq(restored.visible_objects().size(), 0)


## `Script_faceplayer` turns the object the talk is with, and the turn has to
## reach what is drawn on the frame it runs: the override alone leaves the
## object standing the way its event placed it until some later reload.
func test_faceplayer_turns_the_talked_object_toward_the_player() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6190"] = [Gen2WorldScript.FACEPLAYER, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(6, 6))
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	var object: Gen2WorldObject = world.objects[0]
	object.facing = Gen2WorldSprite.FACING_DOWN
	world.current_map.events["objects"][0]["script"] = 0x6190
	object.event_script = 0x6190

	world.interact()
	assert_eq(
		(world.objects[0] as Gen2WorldObject).facing, Gen2WorldSprite.FACING_RIGHT,
		"the object faces the player it was talked to by"
	)


## `Script_jumptextfaceplayer` jumps to JumpTextFacePlayerScript, whose first
## command is `faceplayer`; `jumptext` and `farjumptext` enter the same script
## one command later and turn nothing. Most NPCs in either pin are the first.
func test_jumptextfaceplayer_turns_the_object_and_jumptext_does_not() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:61A0"] = [Gen2WorldScript.JUMPTEXTFACEPLAYER, 0x00, 0x70]
	scripts["48:61B0"] = [Gen2WorldScript.JUMPTEXT, 0x00, 0x70]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	for row: Array in [[0x61A0, Gen2WorldSprite.FACING_RIGHT], [0x61B0, Gen2WorldSprite.FACING_DOWN]]:
		var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(6, 6))
		world.player_facing = Gen2WorldSprite.FACING_LEFT
		var object: Gen2WorldObject = world.objects[0]
		object.facing = Gen2WorldSprite.FACING_DOWN
		world.current_map.events["objects"][0]["script"] = int(row[0])
		object.event_script = int(row[0])

		var waiting: Array = world.interact()
		assert_eq(waiting[0]["event"]["text"], "AB")
		assert_eq((world.objects[0] as Gen2WorldObject).facing, int(row[1]))


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
	var conditional: Array = world.dispatch_events(Vector2i(8, 5), true)
	assert_eq(conditional.size(), 1)
	assert_true(world.event_flag_active(11))


## `NormalStep` calls `ShakeGrass` where it starts the step, and
## `MovementFunction_ShakingGrass` gives the temporary object one frame less
## than that step, so the rustle belongs to the step rather than to the cell.
func test_a_step_into_grass_takes_one_rustle_per_step() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(5, 11))
	assert_true(world.take_grass_rustles().is_empty(), "standing still shakes nothing")

	assert_true(bool(world.move_result(Vector2i.UP).get("ok", false)))
	var rustles: Array = world.take_grass_rustles()
	assert_eq(rustles.size(), 1)
	assert_eq(rustles[0]["object_index"], -1, "the player is index -1")
	assert_eq(rustles[0]["cell"], Vector2i(5, 10))
	assert_eq(rustles[0]["frames"], Gen2WorldAPI.STEP_PASSES_WALK - 1)
	assert_true(world.take_grass_rustles().is_empty(), "the flag is taken once")

	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_player_step_pass()
	assert_true(bool(world.move_result(Vector2i.UP).get("ok", false)))
	assert_true(world.take_grass_rustles().is_empty(), "the cell left behind is not grass")


## CheckTileEvent (engine/overworld/events.asm) runs warps, coord events, the
## step count and encounters. TryBGEvent is behind CheckAPressOW, so walking
## onto a background event's own cell runs nothing; only interact() reaches it.
func test_a_step_onto_a_background_event_runs_nothing() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6178"] = [Gen2WorldScript.SETEVENT, 13, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))
	world.current_map.events["bg_events"] = [
		{"x": 8, "y": 6, "type": Gen2WorldAPI.BGEVENT_READ, "script": 0x6178},
	]

	assert_true(world.dispatch_script_events(Vector2i(8, 6)).is_empty())
	assert_false(world.event_flag_active(13))

	# The same record still answers an A press and explicit execution.
	world.player_facing = Gen2WorldSprite.FACING_UP
	world.player_cell = Vector2i(8, 7)
	assert_eq(world.interact().size(), 1)
	assert_true(world.event_flag_active(13))


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


func test_describedecoration_runs_locally_and_opens_only_the_town_map_host() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6440"] = [Gen2WorldScript.raw_opcode(0x99), 0x00, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	state.set_maptile_decoration(&"poster", 0x10)
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6440,
	})

	var text_pause: Dictionary = runner.advance()
	assert_eq(text_pause["status"], &"waiting", JSON.stringify(text_pause))
	assert_eq(text_pause["event"]["type"], &"text", JSON.stringify(text_pause))
	assert_eq(text_pause["event"]["text"], "It's a town map.")
	var map_pause: Dictionary = runner.advance(true)
	assert_eq(map_pause["status"], &"waiting", JSON.stringify(map_pause))
	assert_eq(map_pause["event"]["type"], &"runtime_request", JSON.stringify(map_pause))
	assert_eq(map_pause["event"]["request"]["kind"], &"town_map_requested")
	assert_ne(map_pause["event"]["request"]["kind"], &"decoration_requested")
	var complete: Dictionary = runner.complete_runtime_request({"ok": true})
	assert_eq(complete["status"], &"complete", JSON.stringify(complete))


func test_other_describedecoration_variants_never_become_host_requests() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6450"] = [Gen2WorldScript.raw_opcode(0x99), 0x00, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	for decoration: int in [0x11, 0x12, 0x13]:
		var state := Gen2WorldState.new()
		state.set_maptile_decoration(&"poster", decoration)
		var runner := Gen2WorldScriptRunner.begin(data, state, {
			"kind": &"test", "bank": 48, "script": 0x6450,
		})
		var text_pause: Dictionary = runner.advance()
		assert_eq(text_pause["event"]["type"], &"text", JSON.stringify(text_pause))
		var result: Dictionary = runner.advance(true)
		assert_eq(result["status"], &"complete", JSON.stringify(result))


func test_every_describedecoration_target_is_resolved_without_a_host_request() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	var addresses: Array[int] = []
	for description: int in 5:
		var address: int = 0x6460 + description * 0x10
		addresses.append(address)
		scripts["48:%04X" % address] = [
			Gen2WorldScript.raw_opcode(0x99), description, Gen2WorldScript.END,
		]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	for description: int in 5:
		var state := Gen2WorldState.new()
		state.set_maptile_decoration(&"poster", 0x11)
		var runner := Gen2WorldScriptRunner.begin(data, state, {
			"kind": &"test", "bank": 48, "script": addresses[description],
		})
		assert_eq(runner.advance()["event"]["type"], &"text")
		var result: Dictionary = runner.advance(true)
		assert_eq(result["status"], &"complete", JSON.stringify(result))


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


## `DisplayUnownWords` draws the word a chamber wall spells and holds on
## `JoyWaitAorB`; the `setval` in front of it is which word. The script carries
## on into `closetext` once the box is acknowledged, and an index the table does
## not have refuses rather than drawing a blank box.
func test_the_unown_wall_special_says_the_word_its_setval_names() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:63B0"] = [
		Gen2WorldScript.SETVAL, 2,
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_DISPLAY_UNOWN_WORDS, 0x00,
		Gen2WorldScript.END,
	]
	scripts["48:63C0"] = [
		Gen2WorldScript.SETVAL, 9,
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_DISPLAY_UNOWN_WORDS, 0x00,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x63B0,
	})
	var word: Dictionary = runner.advance()
	assert_eq(word["status"], &"waiting", JSON.stringify(word))
	assert_eq(word["event"]["type"], &"text")
	assert_eq(word["event"]["text"], "WALLC")
	assert_eq(runner.advance(true)["status"], &"complete")

	var refused := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x63C0,
	})
	var failure: Dictionary = refused.advance()
	assert_eq(failure["status"], &"failed", JSON.stringify(failure))
	assert_eq(failure["reason"], &"unknown_unown_wall")


## `_GetVarAction.UnownCaught` counts `wUnownDex` up to its first empty slot.
## All three Ruins of Alph scientists and the Kabuto chamber's wall open with
## `readvar VAR_UNOWNCOUNT`, so an unsupported variable stops them talking.
func test_readvar_unowncount_counts_the_unown_dex() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6390"] = [
		Gen2WorldScript.READVAR, 0x0E,
		Gen2WorldScript.IFEQUAL, 2, 0xA0, 0x63,
		Gen2WorldScript.END,
	]
	scripts["48:63A0"] = [Gen2WorldScript.SETEVENT, 44, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.state.update_unown_dex(4)
	world.state.update_unown_dex(19)
	world.current_map.events["coord_events"][0]["script"] = 0x6390
	var result: Array = world.dispatch_script_events()
	assert_eq(result.size(), 1)
	assert_eq(result[0]["status"], &"complete", JSON.stringify(result))
	assert_true(world.event_flag_active(44))


func test_checkpoke_answers_the_party_summary_species_and_fails_without_one() -> void:
	# Route 39's TrainerPokefanmDerek and Route 43's PicnickerTiffany both ask
	# checkpoke before offering a phone number. Script_checkpoke searches
	# wPartySpecies (engine/overworld/scripting.asm).
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6350"] = [
		Gen2WorldScript.CHECKPOKE, 25, # PIKACHU
		Gen2WorldScript.IFTRUE, 0x60, 0x63,
		Gen2WorldScript.END,
	]
	scripts["48:6360"] = [Gen2WorldScript.SETEVENT, 42, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	var carrying: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	carrying.set_party_summary(2, false, [25, 1] as Array[int])
	carrying.current_map.events["coord_events"][0]["script"] = 0x6350
	var found: Array = carrying.dispatch_script_events()
	assert_eq(found[0]["status"], &"complete", JSON.stringify(found))
	assert_true(carrying.event_flag_active(42))

	var without: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	without.set_party_summary(2, false, [1, 4] as Array[int])
	without.current_map.events["coord_events"][0]["script"] = 0x6350
	var missing: Array = without.dispatch_script_events()
	assert_eq(missing[0]["status"], &"complete", JSON.stringify(missing))
	assert_false(without.event_flag_active(42))

	var unset: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	unset.current_map.events["coord_events"][0]["script"] = 0x6350
	var failed: Array = unset.dispatch_script_events()
	assert_eq(failed[0]["status"], &"failed")
	assert_eq(failed[0]["reason"], &"missing_party_summary")


func test_disappear_writes_the_object_flag_the_same_script_can_check() -> void:
	# TeamRocketBaseB2F's third Electrode disappears itself and then checks all
	# three electrode events before running the script that ends the hideout, so
	# the flag has to be readable inside the same script the way Script_disappear
	# writes it.
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6380"] = [
		Gen2WorldScript.raw_opcode(0x6D, true), 2, # disappear, first object
		Gen2WorldScript.CHECKEVENT, 0, 0,
		Gen2WorldScript.IFTRUE, 0x90, 0x63,
		Gen2WorldScript.END,
	]
	scripts["48:6390"] = [Gen2WorldScript.SETEVENT, 44, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var flag: int = (world.objects[0] as Gen2WorldObject).event_flag
	assert_gt(flag, 0, "the fixture's first object needs an event flag")
	scripts["48:6380"][3] = flag & 0xFF
	scripts["48:6380"][4] = flag >> 8
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)

	var reloaded: GameData = GameData.open_directory(_directory)
	var checked: Gen2WorldAPI = Gen2WorldAPI.open(reloaded, 1, 1, Vector2i(7, 6))
	checked.current_map.events["coord_events"][0]["script"] = 0x6380
	var result: Array = checked.dispatch_script_events()
	assert_eq(result[0]["status"], &"complete", JSON.stringify(result))
	assert_true(checked.event_flag_active(flag), JSON.stringify(result))
	assert_true(checked.event_flag_active(44), JSON.stringify(result))


func test_talking_to_a_beaten_trainer_clears_the_just_battled_flag_first() -> void:
	# LoadTrainer_continue clears wRunningTrainerBattleScript for every trainer
	# encounter (home/trainers.asm), so an after-battle script only stops at
	# endifjustbattled on the turn the battle happened. The Rocket hideout's two
	# password grunts put their setevent past that command
	# (maps/TeamRocketBaseB3F.asm, GruntF5Script and GruntM28Script).
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6370"] = [
		Gen2WorldScript.raw_opcode(0x65, true), # endifjustbattled
		Gen2WorldScript.SETEVENT, 43, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	var battled: Gen2WorldState = Gen2WorldState.from_dict({"just_battled": true})
	assert_true(battled.just_battled())
	var talked := Gen2WorldScriptRunner.begin(data, battled, {
		"kind": &"trainer", "bank": 48, "script": 0x6370, "trainer_phase": &"after",
	})
	var talked_result: Dictionary = talked.advance()
	assert_eq(talked_result["status"], &"complete", JSON.stringify(talked_result))
	assert_true(battled.is_event_flag_active(43), JSON.stringify(talked_result))

	# A script that is not a trainer encounter still sees the committed flag.
	var plain: Gen2WorldState = Gen2WorldState.from_dict({"just_battled": true})
	var ordinary := Gen2WorldScriptRunner.begin(data, plain, {
		"kind": &"test", "bank": 48, "script": 0x6370,
	})
	var ordinary_result: Dictionary = ordinary.advance()
	assert_eq(ordinary_result["status"], &"complete", JSON.stringify(ordinary_result))
	assert_false(plain.is_event_flag_active(43), JSON.stringify(ordinary_result))


func test_crystal_opcodes_past_verbosegiveitemvar_normalize_two_lower() -> void:
	# Crystal's stream inserts two commands pokegold does not have: farjumptext
	# at $52 and verbosegiveitemvar at $9f (macros/scripts/events.asm). So
	# Crystal is one ahead from $53 and two ahead from $a0.
	assert_eq(Gen2WorldScript.source_opcode(0x9E, true), 0x9D) # verbosegiveitem
	assert_eq(Gen2WorldScript.source_opcode(0xA0, true), 0x9E) # swarm
	assert_eq(Gen2WorldScript.source_opcode(0xA1, true), 0x9F) # halloffame
	assert_eq(Gen2WorldScript.source_opcode(0xA3, true), 0xA1) # warpfacing
	assert_eq(Gen2WorldScript.source_opcode(0xA1, false), 0xA1)
	assert_eq(Gen2WorldScript.raw_opcode(0x9D, true), 0x9E)
	assert_eq(Gen2WorldScript.raw_opcode(0x9E, true), 0xA0)
	assert_eq(Gen2WorldScript.raw_opcode(0x9F, true), 0xA1)
	assert_eq(Gen2WorldScript.raw_opcode(0x9F, false), 0x9F)
	# Crystal's swarm carries a flag byte pokegold's omits, so the widths differ
	# even though both name the same command.
	assert_eq(Gen2WorldScript.command_width(0xA0, true), 4)
	assert_eq(Gen2WorldScript.command_width(0x9E, false), 3)
	assert_eq(Gen2WorldScript.command_width(0x9F, true), 3) # verbosegiveitemvar
	assert_eq(Gen2WorldScript.command_width(0xA3, true), 6) # warpfacing
	assert_eq(Gen2WorldScript.command_name(0xA0, true), &"swarm")
	assert_eq(Gen2WorldScript.command_name(0xA1, true), &"halloffame")
	assert_eq(Gen2WorldScript.command_name(0x9F, true), &"verbosegiveitemvar")


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
	## `ld a, [wPartyCount] / and a / ret z`: with no party the routine returns
	## before it has loaded a tile, so it spends no frame and no sound.
	assert_eq(
		_event_value(result[0]["events"], &"presentation_special_applied", "sounds"), []
	)


## `.HallOfFame`'s sequence is the only one that differs: two effects around
## `.FlashPalettes8Times` where the other two start `MUSIC_HEAL` under it.
func test_heal_machine_sounds_follow_the_sequence_the_machine_type_selects() -> void:
	var centre: Array = Gen2WorldScriptRunner.heal_machine_sounds(0, 3)
	assert_eq(centre.size(), 4)
	for ball: int in 3:
		assert_eq(int(centre[ball]["frame"]), ball * 30)
		assert_eq(
			int(centre[ball]["index"]),
			Gen2WorldScriptRunner.SFX_SECOND_PART_OF_ITEMFINDER,
		)
	assert_eq(StringName(centre[3]["kind"]), &"music")
	assert_eq(int(centre[3]["frame"]), 90)

	var hall: Array = Gen2WorldScriptRunner.heal_machine_sounds(
		Gen2WorldScriptRunner.HEAL_MACHINE_HALL_OF_FAME, 1
	)
	assert_eq(
		[int(hall[1]["frame"]), int(hall[1]["index"])],
		[30, Gen2WorldScriptRunner.SFX_GAME_FREAK_LOGO_GS],
	)
	## `WaitSFX` between the two is not spent, like the world's other two.
	assert_eq(
		[int(hall[2]["frame"]), int(hall[2]["index"])],
		[110, Gen2WorldScriptRunner.SFX_BOOT_PC],
	)


## `ItemFinder.ItemfinderSound`: four passes of two `WaitPlaySFX`, so eight
## entries that wait on the channels rather than on a frame count. The other
## branch, `.Script_FoundNothing`, has no `callasm` at all.
func test_the_itemfinder_sounds_are_eight_waited_effects_in_pairs() -> void:
	var sounds: Array = Gen2WorldScriptRunner.itemfinder_sounds()
	assert_eq(sounds.size(), Gen2WorldScriptRunner.ITEMFINDER_SFX_PASSES * 2)
	for index: int in sounds.size():
		var entry: Dictionary = sounds[index]
		assert_true(bool(entry["wait"]), "every one of them is a `WaitPlaySFX`")
		assert_false(entry.has("frame"), "and none is due on a count")
		assert_eq(
			int(entry["index"]),
			Gen2WorldScriptRunner.SFX_TRANSACTION if index % 2 == 1 \
				else Gen2WorldScriptRunner.SFX_SECOND_PART_OF_ITEMFINDER,
		)


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
	assert_true(world.set_party_summary(
		3, true, [25, 1] as Array[int], [[0x46], []], ["PIKA", "BULBASAUR"], [false, true],
		{}, [false, true]
	)["ok"])
	var expected: Dictionary = {
		"count": 3, "pokerus": true, "species": [25, 1],
		"moves": [[0x46], []], "names": ["PIKA", "BULBASAUR"], "eggs": [false, true],
		## Per slot beside the rest: a fainted Pokemon in slot 2 is a fact the
		## lead's own flag cannot carry.
		"fainted": [false, true],
	}
	assert_eq(world.party_summary(), expected)
	assert_false(world.set_party_summary(-1, false)["ok"])
	assert_eq(world.party_summary(), expected)
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
	## `SetDayOfWeek` shows one weekday between two arrows, not a seven-row list:
	## seven rows at `_InitVerticalMenuCursor`'s two-row step do not fit a screen.
	assert_eq(menu["event"]["menu_kind"], &"spinner")
	## `.WeekdayStrings`' own padding, which is what centres the name in the
	## nine-wide box `hlcoord 10, 5` places it in.
	assert_eq(menu["event"]["options"], [
		" SUNDAY", " MONDAY", " TUESDAY", "WEDNESDAY", "THURSDAY", " FRIDAY", "SATURDAY",
	])

	var confirmation_text: Dictionary = runner.advance(true, 3)
	assert_eq(confirmation_text["event"]["type"], &"text")
	assert_eq(confirmation_text["event"]["text"], "WEDNESDAY, is it?")
	var confirmation: Dictionary = runner.advance(true)
	assert_eq(confirmation["event"]["type"], &"choice")
	assert_eq(confirmation["event"]["choices"], [&"yes", &"no"])

	var text: Dictionary = runner.advance(true, 0)
	assert_eq(text["event"]["type"], &"text")
	assert_eq(text["event"]["text"], "AB")
	var complete: Dictionary = runner.advance(true)
	assert_eq(complete["status"], &"complete")
	assert_eq(complete["clock"], {"day": 3, "hour": 8, "minute": 15})


## `Script_yesorno` is `YesNoBox` drawn over the box `writetext` left open, and
## `Script_verticalmenu` is `_2DMenu` over the same box, so the question a choice
## answers is the last text the script wrote. Without it a host has nothing but
## the command's own name, which is how "yesorno" reached the screen.
func test_a_choice_carries_the_text_the_open_box_is_still_showing() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6640"] = [
		Gen2WorldScript.WRITETEXT, 0x00, 0x70,
		Gen2WorldScript.YESORNO,
		Gen2WorldScript.END,
	]
	scripts["48:6650"] = [
		Gen2WorldScript.WRITETEXT, 0x00, 0x70,
		Gen2WorldScript.CLOSETEXT,
		Gen2WorldScript.YESORNO,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6640,
	})
	assert_eq(runner.advance()["event"]["text"], "AB")
	var choice: Dictionary = runner.advance(true)
	assert_eq(choice["event"]["type"], &"choice")
	assert_eq(choice["event"]["text"], "AB", JSON.stringify(choice))

	var closed := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6650,
	})
	assert_eq(closed.advance()["event"]["text"], "AB")
	assert_eq(closed.advance(true)["event"]["text"], "")


## `_GetVarAction.BoxFreeSpace` is `MONS_PER_BOX - [sBoxCount]`. Route 29's
## catching tutorial reads it before it hands a POKé BALL over, so an
## unsupported variable stops that NPC talking at all.
func test_readvar_boxspace_reads_the_party_summary_mirror() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6660"] = [
		Gen2WorldScript.READVAR, 0x10,
		Gen2WorldScript.IFEQUAL, 14, 0x70, 0x66,
		Gen2WorldScript.END,
	]
	scripts["48:6670"] = [Gen2WorldScript.SETEVENT, 41, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6660,
		"party": {"count": 1, "box_free_space": 14},
	})
	assert_eq(runner.advance()["status"], &"complete")
	assert_true(state.is_event_flag_active(41))

	var unmirrored := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6660,
	})
	var refused: Dictionary = unmirrored.advance()
	assert_eq(refused["status"], &"failed", JSON.stringify(refused))
	assert_eq(refused["reason"], &"missing_party_summary")


## An empty box is the whole box; a storage with no free slot anywhere answers 0,
## which is the refusal every reader of the var already branches on.
func test_box_free_space_answers_the_box_a_deposit_would_land_in() -> void:
	var save: Gen2SaveData = Gen2SaveData.new()
	assert_eq(save.box_free_space(), Gen2SaveBox.CAPACITY)
	for slot: int in Gen2SaveBox.CAPACITY:
		(save.boxes[0] as Gen2SaveBox).put(Gen2SaveMon.new())
	assert_eq(save.box_free_space(), Gen2SaveBox.CAPACITY)
	for box: Gen2SaveBox in save.boxes:
		for slot: int in Gen2SaveBox.CAPACITY:
			box.put(Gen2SaveMon.new())
	assert_eq(save.box_free_space(), 0)


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
	var result: Array = world.dispatch_events(Vector2i(8, 6), true)
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
	var results: Array = world.dispatch_events(Vector2i(8, 6), true)
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


func test_a_staircase_warp_faces_and_steps_the_player_out() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var target: Gen2WorldMap = data.world_map(1, 2)
	var landing := Vector2i(2, 2)
	target.collision[landing.y * target.collision_width + landing.x] = 0x7A
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(6, 6))
	world.player_facing = Gen2WorldSprite.FACING_UP

	assert_true(world.try_warp()["ok"])
	assert_eq(world.player_cell, landing)
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_DOWN)
	assert_eq(world.forced_movement()["direction"], Vector2i.DOWN)
	var step: Dictionary = world.advance_forced_movement()
	assert_true(step["ok"], JSON.stringify(step))
	assert_eq(world.player_cell, landing + Vector2i.DOWN)
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_DOWN)


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


func test_roaming_records_are_integers_rather_than_json_floats() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(6, 6))
	var mon: Dictionary = world.roaming_mons()[0]
	for field: String in ["species", "level", "map_group", "map_number"]:
		assert_eq(typeof(mon[field]), TYPE_INT, "%s must be an int" % field)


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


## The cartridge copies the connection strip into the same block buffer the
## current map lives in, so `.CheckLandPerms` reads the neighbour's real
## collision and refuses a wall across an edge exactly as it does inside one.
func test_connected_edge_step_refuses_a_wall_on_the_target_map() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var target: Gen2WorldMap = data.world_map(1, 2)
	target.collision[4 * target.collision_width + 0] = 0x07
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(15, 4))
	var result: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_false(result["ok"])
	assert_eq(result["kind"], &"connection")
	assert_eq(result["reason"], &"blocked_target_cell")
	assert_eq(world.map_id(), Vector2i(1, 1))
	assert_eq(world.player_cell, Vector2i(15, 4))


## A connection spans only part of its edge, so an edge cell the connected map
## does not reach resolves to nothing. connection_target() answers that without
## moving anyone, which is what a walk planner needs before it settles on a cell.
func test_connection_target_reports_the_span_without_moving_the_player() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var source: Gen2WorldMap = data.world_map(1, 1)
	(source.connections[0] as Dictionary)["y_offset"] = 6
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(15, 0))

	var inside: Dictionary = world.connection_target(Vector2i(15, 0), Vector2i.RIGHT)
	assert_true(inside["ok"])
	assert_eq(inside["map_group"], 1)
	assert_eq(inside["map_number"], 2)
	assert_eq(inside["cell"], Vector2i(0, 6))

	var outside: Dictionary = world.connection_target(Vector2i(15, 6), Vector2i.RIGHT)
	assert_false(outside["ok"])
	assert_eq(outside["reason"], &"invalid_target_cell")

	var inland: Dictionary = world.connection_target(Vector2i(8, 6), Vector2i.RIGHT)
	assert_false(inland["ok"])
	assert_eq(inland["reason"], &"not_at_edge")

	assert_true(world.connection_target(Vector2i(0, 6), Vector2i.LEFT).is_empty())

	assert_eq(world.map_id(), Vector2i(1, 1))
	assert_eq(world.player_cell, Vector2i(15, 0))
	# The step itself lands where the plan said it would.
	assert_true(world.move_result(Vector2i.RIGHT)["ok"])
	assert_eq(world.player_cell, Vector2i(0, 6))


func test_connection_requires_the_player_to_be_on_the_requested_edge() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	var result: Dictionary = world.try_connection(Vector2i.RIGHT)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"not_at_edge")
	assert_eq(world.map_id(), Vector2i(1, 1))
	assert_eq(world.player_cell, Vector2i(8, 6))


## `.CheckTurning` sits between `.CheckTile` and `.TryStep` in
## `DoPlayerMovement`, and its own comment is "This also lets the player change
## facing without moving by tapping a direction". It runs before any collision
## check, and `StepFunction_Turn` costs four frames and no cell.
func test_a_press_in_a_new_direction_turns_on_the_spot_before_it_walks() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(4, 4))
	var from: Vector2i = world.player_cell
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_DOWN)

	var turn: Dictionary = world.player_input_move(Vector2i.RIGHT)
	assert_true(turn["ok"])
	assert_eq(turn["kind"], &"turn")
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_RIGHT)
	assert_eq(world.player_cell, from, "a turn costs no cell")
	assert_true(world.player_step_in_progress(), "and it costs four frames")
	assert_eq(world.player_walk_frame(), 0, "StepFunction_Turn stays standing")

	while world.player_step_in_progress():
		world.advance_player_step_pass()
	assert_eq(world.player_walk_frame(), 0, "the completed turn stays standing")
	var walk: Dictionary = world.player_input_move(Vector2i.RIGHT)
	assert_true(walk["ok"])
	assert_ne(walk["kind"], &"turn", "the facing already agrees, so this one walks")
	assert_eq(world.player_cell, from + Vector2i.RIGHT)


## A scripted `applymovement` drives the object through
## `engine/overworld/movement.asm` and never reaches `DoPlayerMovement`, so it
## turns nothing: only the input path has the check.
func test_a_programmatic_step_does_not_turn_first() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(4, 4))
	var from: Vector2i = world.player_cell
	var moved: Dictionary = world.move_result(Vector2i.RIGHT)
	assert_true(moved["ok"])
	assert_eq(world.player_cell, from + Vector2i.RIGHT)


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
	var dispatched: Array = world.dispatch_script_events()
	assert_eq(dispatched.size(), 1)
	assert_eq(dispatched[0]["status"], &"waiting", "the first stream holds the script")
	assert_eq(dispatched[0]["event"]["wait"], Gen2WorldScriptRunner.WAIT_MOVEMENT)
	assert_eq(_final_status(_run_script(world, dispatched)), &"complete")
	assert_eq((world.objects[0] as Gen2WorldObject).cell, Vector2i(6, 6))
	assert_eq(world.player_cell, Vector2i(7, 5))


func test_script_movement_publishes_source_shake_effects() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x55, 16, 0x47],
		"48:6110": [0x56, 0x47],
		"48:6120": [0x57, 0, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [
			0x69, 0, 0x00, 0x61,
			0x69, 2, 0x10, 0x61,
			0x69, 2, 0x20, 0x61,
			0x91,
		],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var results: Array = _run_script(world, world.dispatch_script_events())
	assert_eq(_final_status(results), &"complete")
	var events: Array = _all_events(results)
	var types: Array[StringName] = _event_types(results)
	assert_true(types.has(&"screen_shake_requested"))
	assert_true(types.has(&"tree_shake_requested"))
	assert_true(types.has(&"rock_smash_effect_requested"))
	for event: Dictionary in events:
		if event.get("type", &"") == &"screen_shake_requested":
			assert_eq(event["strength"], 16)
	## `Movement_tree_shake` shakes the object, not the screen: 24 frames of
	## OBJECT_ACTION_WEIRD_TREE on the object the stream was applied to.
	for event: Dictionary in events:
		if event.get("type", &"") == &"tree_shake_requested":
			assert_eq(event["frames"], Gen2WorldAPI.TREE_SHAKE_FRAMES)


## Every step command reaches NormalStep (engine/overworld/movement.asm), which
## only calls InitStep and never reads a permission, so a scripted step walks
## through a wall. The S.S. Aqua's granddaughter scene is built on it.
func test_script_movement_steps_through_a_wall_the_way_normal_step_does() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x0F, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 0, 0x00, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))
	assert_false(world.can_walk_to(Vector2i(9, 6)), "the fixture wall moved")
	var results: Array = _run_script(world, world.dispatch_script_events(Vector2i(7, 6)))
	assert_eq(_final_status(results), &"complete")
	assert_eq(world.player_cell, Vector2i(9, 6))


## An applymovement applies its whole stream in one call, so every cell of the
## path commits at once and the drawing is what trails. Presentation only: the
## cells below are already the stream's last one while the offset is still two
## behind it.
## The four turning commands, which are not what their names suggest.
## `TurnStep` sets STEP_TYPE_TURN and never calls `InitStep`, so it only turns;
## `turn_away`, `turn_in` and `turn_waterfall` all reach `TurningStep`, which
## does call it, so each steps one cell in the direction it names and only the
## spin over the top tells them from a plain step. `turn_away` does not reverse
## anything. `engine/events/forced_movement.asm` is the case that shows it: a
## whirlpool spins the player, `turn_in` steps them back off the tile, and they
## would stand on it for good if it turned in place.
func test_the_turning_movement_commands_step_or_turn_as_their_source_does() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		# turn_step down, then turn_in up.
		"48:6110": [0x04, 0x25, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 0, 0x10, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var dispatched: Array = world.dispatch_script_events()
	assert_eq(dispatched[0]["status"], &"waiting", "the stream holds the script")

	# turn_step faced down and moved nothing; turn_in stepped one cell up and
	# left the player facing the way it named.
	assert_eq(world.player_cell, Vector2i(7, 5))
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_UP)
	# One cell of trail, at turn_in's own STEP_WALK duration.
	assert_eq(world.player_step_offset_cells(), Vector2(0.0, 1.0))
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_player_step_pass()
	assert_eq(world.player_step_offset_cells(), Vector2.ZERO)
	assert_eq(_final_status(_run_script(world, dispatched)), &"complete")


## `JumpStep` sets STEP_TYPE_NPC_JUMP, whose jumptable is `.Jump` then `.Land`
## with a `GetNextTile` between them, so one `jump_step` covers two cells over
## twice the duration and wears `UpdateJumpPosition`'s arc for the whole of it.
func test_a_scripted_jump_step_covers_two_cells_and_arcs_over_them() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x33, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 2, 0x00, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var object: Gen2WorldObject = world.objects[0]
	var start: Vector2i = object.cell
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")
	assert_eq(object.cell, start + Vector2i(2, 0), "two cells, committed at once")

	var highest: float = 0.0
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK * 2:
		assert_true(world.advance_scripted_steps_pass())
		highest = maxf(highest, object.height_offset_pixels())
	assert_eq(highest, 12.0, "the top of .y_offsets")
	assert_eq(object.step_offset_cells(), Vector2.ZERO, "and the whole hop is drawn")
	assert_eq(object.height_offset_pixels(), 0.0, "back on the ground where it lands")


func test_script_movement_leaves_a_trail_the_renderer_walks_a_step_at_a_time() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x0F, 0x0F, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 2, 0x00, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var object: Gen2WorldObject = world.objects[0]
	var start: Vector2i = object.cell
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")

	assert_eq(object.cell, start + Vector2i(2, 0), "both cells commit at once")
	assert_eq(object.step_offset_cells(), Vector2(-2.0, 0.0), "and the drawing is behind both")

	# Each of the two cells costs STEP_PASSES_WALK frames.
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		assert_true(world.advance_scripted_steps_pass())
	assert_eq(object.step_offset_cells(), Vector2(-1.0, 0.0), "one step drawn, one to go")
	assert_eq(object.cell, start + Vector2i(2, 0), "and no cell moved with it")

	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_scripted_steps_pass()
	assert_eq(object.step_offset_cells(), Vector2.ZERO)
	assert_false(world.advance_scripted_steps_pass())


## `NormalStep` writes OBJECT_FACING where it starts each step, so a stream whose
## legs turn is drawn turning with them. The whole path commits in one call here,
## which is why the facing has to travel with the trail rather than with the
## commit: applied with the cells it would walk the first two legs already facing
## the way the last one ends.
func test_a_turning_stream_is_drawn_facing_each_leg_in_turn() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		# step down, step down, step right.
		"48:6100": [0x0C, 0x0C, 0x0F, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 2, 0x00, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var object: Gen2WorldObject = world.objects[0]
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")

	assert_eq(object.facing, Gen2WorldSprite.FACING_DOWN, "the first leg")
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_scripted_steps_pass()
	assert_eq(object.facing, Gen2WorldSprite.FACING_DOWN, "still the second")
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_scripted_steps_pass()
	assert_eq(object.facing, Gen2WorldSprite.FACING_RIGHT, "and the last one turns")
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_scripted_steps_pass()
	assert_eq(object.step_offset_cells(), Vector2.ZERO)


## `Script_applymovement` sets SCRIPT_WAIT_MOVEMENT and StopScript, and
## `WaitScriptMovement` holds the script until the stream clears
## SCRIPTED_MOVEMENT_STATE_F, which `Movement_step_end` is what does. So the
## command after it does not run until the object has been drawn walking, which
## is what kept a text box off the top of Mom's walk.
func test_applymovement_holds_the_script_until_the_trail_has_been_drawn() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x0F, 0x0F, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		# applymovement, then the fixture text the wait must not reach.
		"48:6070": [0x69, 2, 0x00, 0x61, 0x4C, 0x00, 0x70, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var object: Gen2WorldObject = world.objects[0]

	var dispatched: Array = world.dispatch_script_events()
	assert_eq(dispatched[0]["status"], &"waiting")
	assert_eq(dispatched[0]["event"]["type"], &"wait")
	assert_eq(dispatched[0]["event"]["wait"], Gen2WorldScriptRunner.WAIT_MOVEMENT)
	assert_true(world.scripted_movement_in_progress())
	assert_true(world.pending_runtime_request().is_empty(), "no host answers a wait")

	# Two `step` commands, so the wait outlasts the first one's frames.
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		assert_true(
			world.advance_script_presentation_frame().is_empty()
		)
	assert_false(world.pending_script_wait().is_empty(), "one step still to draw")
	assert_eq(object.step_offset_cells(), Vector2(-1.0, 0.0))

	var resumed: Array = world.finish_script_waits()
	assert_false(object.scripted_steps)
	assert_eq(object.step_offset_cells(), Vector2.ZERO)
	assert_eq(StringName((resumed[0] as Dictionary).get("status", &"")), &"waiting")
	assert_eq((resumed[0] as Dictionary)["event"]["text"], "AB")


## `Movement_step_sleep_common` puts the object in STEP_TYPE_SLEEP for its own
## count before the stream reads on, so a sleep is part of what the wait waits
## for even though nothing moves.
func test_a_movement_sleep_holds_the_wait_without_moving_anything() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		# step_sleep 8, step_end.
		"48:6100": [0x45, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 2, 0x00, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var object: Gen2WorldObject = world.objects[0]
	var start: Vector2i = object.cell

	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")
	for _frame: int in 7:
		world.advance_script_presentation_frame()
	assert_false(world.pending_script_wait().is_empty(), "eight frames of sleep")
	assert_eq(object.cell, start)
	assert_eq(object.walk_frame(), 0, "STEP_TYPE_SLEEP stands still")

	assert_eq(_final_status(world.finish_script_waits()), &"complete")
	assert_eq(object.cell, start)


## `Script_pause` delays two frames per counted unit inside the command, and
## `Script_deactivatefacing` hands the same count to SCRIPT_WAIT, which
## `WaitScript` spends one a frame. Both write wScriptDelay only when their
## operand is nonzero, which is what makes `pause 0` reuse it.
func test_pause_and_deactivatefacing_spend_their_own_frame_counts() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# pause 3, deactivatefacing 0, end.
	scripts["48:6160"] = [0x8B, 3, 0x8C, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6160,
	})

	assert_eq(runner.advance()["status"], &"waiting")
	assert_eq(runner.pending_wait()["frames"], 6, "three units of two frames")

	assert_eq(runner.complete_wait()["status"], &"waiting")
	assert_eq(
		runner.pending_wait()["frames"], 3,
		"a zero operand reuses wScriptDelay, and WaitScript spends one a frame"
	)
	assert_eq(runner.complete_wait()["status"], &"complete")


## `Script_earthquake` is `ScriptCall` on `applymovement PLAYER,
## wEarthquakeMovementDataBuffer`, whose stream shakes and then sleeps the low
## six bits of the operand.
func test_earthquake_waits_out_the_sleep_its_own_movement_carries() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6170"] = [0x78, 84, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6170,
	})

	var result: Dictionary = runner.advance()

	assert_eq(result["status"], &"waiting")
	assert_eq(runner.pending_wait()["frames"], 84 & 0x3F)
	assert_true(result["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"earthquake_requested" \
			and int(event.get("strength", 0)) == 84
	), JSON.stringify(result["events"]))
	assert_eq(runner.complete_wait()["status"], &"complete")


## An event is handed to its caller once. The runner drains its list on every
## result, because the caller is what applies a movement and starts a screen
## shake: repeating the list on the next pause would do both twice.
func test_a_script_hands_each_event_to_its_caller_once() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# earthquake 4, pause 1, end.
	scripts["48:6180"] = [0x78, 4, 0x8B, 1, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.new(), {
		"kind": &"test", "bank": 48, "script": 0x6180,
	})

	var shaken: Dictionary = runner.advance()
	assert_eq(_types_of(shaken).count(&"earthquake_requested"), 1)

	var paused: Dictionary = runner.complete_wait()
	assert_eq(paused["status"], &"waiting")
	assert_eq(
		_types_of(paused).count(&"earthquake_requested"), 0,
		"the shake was already delivered"
	)


func _types_of(result: Dictionary) -> Array[StringName]:
	var types: Array[StringName] = []
	for event: Dictionary in result.get("events", []):
		types.append(StringName(event.get("type", &"")))
	return types


## The two drivers own different objects. advance_object_steps_pass() decides
## movement and a screen stops calling it while a script runs, which is exactly
## when a scripted trail has to keep being drawn, so draining it there as well
## would walk it at twice the speed.
func test_the_movement_driver_leaves_a_scripted_trail_to_its_own_driver() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x0F, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 2, 0x00, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var object: Gen2WorldObject = world.objects[0]
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")
	assert_true(object.scripted_steps)

	var random := RandomNumberGenerator.new()
	random.seed = 7
	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_object_steps_pass(random)
	assert_eq(object.step_offset_cells(), Vector2(-1.0, 0.0), "untouched by the other driver")

	@warning_ignore("integer_division")
	var half: int = Gen2WorldAPI.STEP_PASSES_WALK / 2
	for _frame: int in half:
		assert_true(world.advance_scripted_steps_pass())
	assert_eq(object.step_offset_cells(), Vector2(-0.5, 0.0))


## The player's half of the same thing, plus the walk frame that goes with it.
## OBJECT_STEP_FRAME advances once per hardware frame and its two high bits pick
## the drawing, so the frame changes every four.
func test_a_scripted_player_stream_trails_and_advances_the_walk_frame() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6110": [0x0D, 0x0D, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 0, 0x10, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	assert_eq(world.dispatch_script_events()[0]["status"], &"waiting")

	assert_eq(world.player_cell, Vector2i(7, 4), "both cells commit at once")
	assert_eq(world.player_step_offset_cells(), Vector2(0.0, 2.0))
	assert_eq(world.player_walk_frame(), 0)

	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		assert_true(world.advance_player_step_pass())
	assert_eq(world.player_step_offset_cells(), Vector2(0.0, 1.0), "one step drawn")
	# Eight frames in, the counter is on its third drawing: stand, walk, stand.
	assert_eq(world.player_walk_frame(), 2)

	for _frame: int in Gen2WorldAPI.STEP_PASSES_WALK:
		world.advance_player_step_pass()
	assert_eq(world.player_step_offset_cells(), Vector2.ZERO)
	assert_eq(world.player_cell, Vector2i(7, 4))
	assert_eq(world.player_walk_frame(), 0, "EndSpriteMovement leaves the player standing")


func test_script_movement_still_refuses_a_step_off_the_map() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x0F, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6070": [0x69, 0, 0x00, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6070
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(15, 6))
	var results: Array = _run_script(world, world.dispatch_script_events(Vector2i(7, 6)))
	assert_eq(_final_status(results), &"complete")
	assert_eq(world.player_cell, Vector2i(15, 6))
	assert_true(_event_types(results).has(&"movement_blocked"))


func test_follow_command_moves_the_follower_after_a_player_step() -> void:
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6080": [0x70, 0, 2, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6080
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))
	var results: Array = world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(results.size(), 1)
	assert_eq(results[0]["status"], &"complete")
	assert_true(world.move(Vector2i.LEFT))
	assert_eq((world.objects[0] as Gen2WorldObject).cell, Vector2i(6, 6))


## `follow NEWBARKTOWN_TEACHER, PLAYER`, which is what walks the player back out
## of the route and what a swapped pair of operands leaves standing still.
func test_follow_names_the_leader_first_so_the_player_can_be_the_follower() -> void:
	RomCache.write_json(RomCache.world_movements_path(_directory), {
		"48:6100": [0x0F, 0x0F, 0x47],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6080": [0x70, 2, 0, 0x69, 2, 0x00, 0x61, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6080
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(4, 6))
	var leader: Gen2WorldObject = world.objects[0]
	var from: Vector2i = leader.cell
	assert_eq(_final_status(_run_script(world, world.dispatch_script_events(Vector2i(7, 6)))),
		&"complete")
	assert_eq(leader.cell, from + Vector2i(2, 0), "the leader walked its own two steps")
	assert_eq(world.player_cell, from + Vector2i(1, 0), "the player followed into its trail")


## `Script_writetext` is `MapTextbox` and returns. A text ending in `<DONE>`
## owes no press of its own, so the `waitbutton` behind the command is what the
## script holds on; one ending in `<PROMPT>` owes its own.
func test_a_writetext_says_whether_its_text_owes_a_press() -> void:
	RomCache.write_json(RomCache.world_text_path(_directory), {
		"48:7000": [0x00, 0x80, 0x57],
		"48:7010": [0x00, 0x80, 0x58],
	})
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6060": [
			Gen2WorldScript.WRITETEXT, 0x00, 0x70, Gen2WorldScript.WAITBUTTON, 0x91,
		],
		"48:6070": [Gen2WorldScript.WRITETEXT, 0x10, 0x70, 0x91],
	})
	for expected: Dictionary in [
		{"script": 0x6060, "prompt": false}, {"script": 0x6070, "prompt": true},
	]:
		var data: GameData = GameData.open_directory(_directory)
		data.world_map(1, 1).events["coord_events"][0]["script"] = int(expected["script"])
		var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))
		assert_eq(world.dispatch_script_events(Vector2i(7, 6))[0]["status"], &"waiting")
		var pending: Dictionary = world.pending_script_input()
		assert_eq(StringName(pending.get("type", &"")), &"text")
		assert_eq(bool(pending.get("prompt", true)), bool(expected["prompt"]),
			"script %04X" % int(expected["script"]))


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


## Script_verticalmenu stores wMenuCursorY, which counts from one, so the
## Dragon Shrine's `ifequal 1, .RightAnswer` is asking for the first option.
## cancel_input() keeps the zero the source's carry branch writes.
func test_a_vertical_menu_answers_the_source_one_based_option() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6C60"] = [
		Gen2WorldScript.LOADMENU, 0x34, 0x12,
		0x59, # verticalmenu, raw Crystal
		Gen2WorldScript.IFEQUAL, 2, 0x70, 0x6C,
		Gen2WorldScript.END,
	]
	scripts["48:6C70"] = [
		Gen2WorldScript.SETVAL, 99,
		Gen2WorldScript.WRITEMEM, 0xD8, 0xD1,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	var chosen := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, chosen, {
		"kind": &"test", "bank": 48, "script": 0x6C60,
	})
	assert_eq(runner.advance()["event"]["type"], &"menu")
	# The second option, which the source numbers 2.
	assert_eq(runner.advance(true, 1)["status"], &"complete")
	assert_eq(chosen.script_memory(0xD1D8), 99, "option 1 answered the source's 2")

	var first := Gen2WorldState.new()
	var other := Gen2WorldScriptRunner.begin(data, first, {
		"kind": &"test", "bank": 48, "script": 0x6C60,
	})
	assert_eq(other.advance()["event"]["type"], &"menu")
	assert_eq(other.advance(true, 0)["status"], &"complete")
	assert_eq(first.script_memory(0xD1D8), 0, "option 0 answered the source's 1")

	var cancelled := Gen2WorldState.new()
	var backed_out := Gen2WorldScriptRunner.begin(data, cancelled, {
		"kind": &"test", "bank": 48, "script": 0x6C60,
	})
	assert_eq(backed_out.advance()["event"]["type"], &"menu")
	assert_eq(backed_out.cancel_input()["status"], &"complete")
	assert_eq(cancelled.script_memory(0xD1D8), 0, "cancelling still answers zero")


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
		# Crystal inserts verbosegiveitemvar at $9f; swarm moves to $a0 and
		# carries the event-flag byte before its two map indices.
		"48:60B0": [0xA0, 0, 1, 2, 0x91],
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
		# halloffame is Crystal $a1: pokegold's $9f plus farjumptext at $52 and
		# verbosegiveitemvar at $9f. Crystal $a0 is swarm.
		"48:60E0": [0xA1, 0x91],
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


## Script_credits farcalls RedCredits and falls into the same Script_endall tail
## as Script_halloffame (engine/overworld/scripting.asm's ReturnFromCredits), so
## it commits nothing. maps/SilverCaveRoom3.asm's Red is its one call site.
func test_credits_is_a_presentation_boundary_that_commits_no_flag() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# credits is Crystal $a2: pokegold's $a0 plus farjumptext at $52 and
	# verbosegiveitemvar at $9f.
	scripts["48:6100"] = [0xA2, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6100,
	})

	var result: Dictionary = runner.advance()

	assert_eq(result["status"], &"complete", JSON.stringify(result))
	assert_false(state.hall_of_fame())
	assert_eq(state.engine_flags().size(), 0)
	assert_eq(result["events"].filter(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"credits_requested"
	).size(), 1)


## ProfOaksPCBoot prints, counts the set bits in wPokedexSeen and wPokedexCaught
## and waits for a button (engine/events/prof_oaks_pc.asm). Oak's Kanto script
## reaches it on every branch, including the one that opens Mt. Silver.
func test_prof_oaks_pc_boot_is_presentation_and_writes_nothing() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6110"] = [Gen2WorldScript.SPECIAL, 101, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6110,
	})

	var result: Dictionary = runner.advance()

	assert_eq(result["status"], &"complete", JSON.stringify(result))
	assert_eq(state.event_flags().size(), 0)
	assert_eq(state.engine_flags().size(), 0)
	assert_true(result["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"presentation_special_applied" \
			and event.get("kind", &"") == &"prof_oaks_pc_boot"
	), JSON.stringify(result["events"]))


## `wait` is one of the commands Crystal added, so it has no pokegold opcode and
## has to be answered from the raw byte. Script_wait delays its operand times six
## frames and reads nothing; the two Magnet Train stations are its only call
## sites in either pin.
func test_wait_is_timing_only_and_reports_its_frame_count() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6140"] = [0xA8, 20, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6140,
	})

	var result: Dictionary = runner.advance()

	assert_eq(result["status"], &"waiting", JSON.stringify(result))
	assert_eq(runner.pending_wait()["wait"], Gen2WorldScriptRunner.WAIT_FRAMES)
	assert_eq(runner.pending_wait()["frames"], 120, "twenty units of six frames")
	assert_eq(state.event_flags().size(), 0)
	assert_true(result["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"script_timing_requested" \
			and event.get("kind", &"") == &"wait" \
			and int(event.get("frames", 0)) == 120
	), JSON.stringify(result["events"]))
	assert_eq(runner.advance(true)["status"], &"waiting", "a button does not end it")
	assert_eq(runner.complete_wait()["status"], &"complete")


## Script_newloadmap sets hMapEntryMethod and re-enters the map, then yields
## rather than ending: StopScript only clears SCRIPT_RUNNING in wScriptFlags, so
## the commands after it still run. FallIntoMapScript's pitfall animation is the
## proof (engine/overworld/events.asm).
func test_newloadmap_carries_its_entry_method_and_does_not_end_the_script() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# newloadmap is Crystal $8a: pokegold's $89 plus farjumptext at $52.
	scripts["48:6150"] = [
		0x8A, 0xF9, Gen2WorldScript.SETEVENT, 44, 0, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6150,
	})

	var result: Dictionary = runner.advance()

	assert_eq(result["status"], &"complete", JSON.stringify(result))
	assert_true(result["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"map_entry_method_requested" \
			and int(event.get("method", 0)) == 0xF9
	), JSON.stringify(result["events"]))
	assert_true(state.is_event_flag_active(44), "the command after newloadmap ran")


## MagnetTrain is scroll positions, graphics, music and a VBlank cutscene. It
## reads wScriptVar for the direction, which a preceding SETVAL loads, and
## writes nothing the overworld can observe.
func test_magnet_train_special_reports_its_direction_and_writes_nothing() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	for row: Array in [["48:6160", 1], ["48:6170", 0]]:
		scripts[row[0]] = [
			Gen2WorldScript.SETVAL, int(row[1]),
			Gen2WorldScript.SPECIAL, 35, 0, Gen2WorldScript.END,
		]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	for row: Array in [["48:6160", 0x6160, true], ["48:6170", 0x6170, false]]:
		var state := Gen2WorldState.new()
		var runner := Gen2WorldScriptRunner.begin(data, state, {
			"kind": &"test", "bank": 48, "script": int(row[1]),
		})

		var result: Dictionary = runner.advance()

		assert_eq(result["status"], &"complete", JSON.stringify(result))
		assert_eq(state.event_flags().size(), 0)
		assert_eq(state.engine_flags().size(), 0)
		assert_true(result["events"].any(func(event: Dictionary) -> bool:
			return event.get("type", &"") == &"presentation_special_applied" \
				and event.get("kind", &"") == &"magnet_train" \
				and bool(event.get("to_goldenrod", false)) == bool(row[2])
		), JSON.stringify(result["events"]))


## GetMonSprite's `.Variable` branch reads wVariableSprites and falls through to
## `.NoBreedmon` when the slot is still zero, which answers SPRITE_CHRIS rather
## than nothing (engine/overworld/overworld.asm). Copycat's House 2F is where it
## matters: SPRITE_COPYCAT is $fb and only her own script assigns it, so without
## the fallback she could not be reached to run it.
func test_an_unassigned_variable_sprite_still_occupies_and_is_talkable() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var objects: Array = world.current_map.events["objects"]
	objects[0]["sprite"] = Gen2WorldScriptRunner.VARIABLE_SPRITE_BASE + 0x0B
	objects[0]["x"] = 7
	objects[0]["y"] = 5
	world.reload_current_map()

	var standing: Gen2WorldObject = world.object_at(Vector2i(7, 5))

	assert_not_null(standing, "an unassigned variable sprite left the cell empty")
	assert_false(world.can_walk_to(Vector2i(7, 5)), "it did not occupy its cell")


## `ReadObjectEvents` builds wMapObjects from map data and `LoadSpriteGFX` fills
## VRAM afterwards, so an object exists before its graphics do and none of
## IsNPCAtCoord, CheckFacingObject or CanObjectMoveInDirection asks what loaded.
## A sprite this build cannot draw, a Pokemon sprite among them, therefore has to
## keep blocking and keep answering A: Vermilion's SPRITE_MACHOP and Celadon's
## SPRITE_POLIWAG were both walked straight through while that was not true.
func test_an_object_whose_sprite_is_missing_still_blocks_and_is_talkable() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var objects: Array = world.current_map.events["objects"]
	# Outside the complete SPRITE_POKEMON range and below SPRITE_VARS, so it
	# resolves to nothing at all rather than to an icon or variable fallback.
	objects[0]["sprite"] = 0xA3
	objects[0]["x"] = 7
	objects[0]["y"] = 5
	world.reload_current_map()

	var standing: Gen2WorldObject = world.object_at(Vector2i(7, 5))
	assert_not_null(standing, "a missing sprite emptied the cell")
	assert_null(standing.sprite, "and the fixture really cannot draw it")
	assert_false(world.can_walk_to(Vector2i(7, 5)), "it did not occupy its cell")

	# Drawing is the one thing that may ask for a sprite.
	assert_eq(world.visible_objects().size(), 0)
	assert_eq(world.active_objects().size(), 1)

	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_false(world.interact().is_empty(), "and it could not be talked to")


## constants/event_flags.asm, the flag Oak sets on the sixteen-badge branch.
const EVENT_OPENED_MT_SILVER: int = 1871


## maps/OaksLab.asm's Oak reads VAR_BADGES and opens Mt. Silver only on
## `ifequal NUM_BADGES`, which is NUM_JOHTO_BADGES + NUM_KANTO_BADGES = 16
## (constants/ram_constants.asm). Eight badges take `.Complain` instead, so the
## count has to span both badge bytes for the walk west to be earned.
func test_oaks_lab_opens_mt_silver_only_on_all_sixteen_badges() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6120"] = [
		Gen2WorldScript.READVAR, 0x07,
		Gen2WorldScript.IFEQUAL, 16, 0x30, 0x61,
		Gen2WorldScript.END,
	]
	scripts["48:6130"] = [
		Gen2WorldScript.SETEVENT, EVENT_OPENED_MT_SILVER & 0xFF,
		EVENT_OPENED_MT_SILVER >> 8, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)

	for badges: int in [8, 16]:
		var state := Gen2WorldState.new()
		for badge: int in range(badges):
			state.set_engine_flag(Gen2WorldState.badge_flag(badge))
		var runner := Gen2WorldScriptRunner.begin(data, state, {
			"kind": &"test", "bank": 48, "script": 0x6120,
		})

		var result: Dictionary = runner.advance()

		assert_eq(result["status"], &"complete", JSON.stringify(result))
		assert_eq(state.badge_count(), badges)
		assert_eq(
			state.is_event_flag_active(EVENT_OPENED_MT_SILVER), badges == 16,
			"%d badges" % badges
		)


## LancesRoomLanceScript ends on `warpfacing UP, HALL_OF_FAME, 4, 13`, and the
## Hall of Fame's own scene is what runs `halloffame`. A map scene queued by a
## warp is picked up by the same run_event_queue() loop that took the warp, so
## both happen inside one drain and the presentation event surfaces on the
## warping dispatch's results rather than on a later dispatch_map_entry().
##
## The facing is the other half: Script_warpfacing writes it before the warp and
## nothing in the map load clears it.
func test_a_warpfacing_runs_the_target_map_scene_in_the_same_event_queue() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# Raw Crystal bytes: warpfacing is source $a1, sdefer $8c, halloffame $9f.
	scripts["48:6300"] = [0xA3, Gen2WorldSprite.FACING_UP, 1, 2, 2, 2, Gen2WorldScript.END]
	scripts["48:6310"] = [0x8D, 0x20, 0x63, Gen2WorldScript.END]
	scripts["48:6320"] = [Gen2WorldScript.SETEVENT, 31, 0, 0xA1, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var target_map: Gen2WorldMap = data.world_map(1, 2)
	target_map.scripts["callbacks"] = []
	target_map.scripts["scenes"] = [{"id": 0, "script": 0x6310}]
	target_map.collision[2 * target_map.collision_width + 2] = 0x7A

	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.current_map.events["coord_events"][0]["script"] = 0x6300
	var results: Array = world.dispatch_script_events()

	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_eq(world.player_cell, Vector2i(2, 2))
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_UP)
	assert_true(world.event_flag_active(31))
	assert_true(world.state.hall_of_fame())
	assert_true(results.any(func(result: Dictionary) -> bool:
		return result.get("events", []).any(func(event: Dictionary) -> bool:
			return event.get("type", &"") == &"hall_of_fame_requested"
		)
	))


## The same handoff, but with the warp reached from a host request rather than a
## text pause: `OlivinePortSailorAtGangwayScript` plays a sound and then warps
## onto the S.S. Aqua, so the ship's entry scene resumes through
## complete_runtime_request() instead of run_event_queue(). Dropping the pending
## scene there left the player standing in the ship's doorway.
func test_a_warp_taken_while_resuming_a_host_request_still_runs_the_map_scene() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# playsound, then warp to map 1/2. Raw Crystal: playsound $85, warp $3c.
	scripts["48:6400"] = [0x85, 0x1C, 0x00, 0x3C, 1, 2, 2, 2, Gen2WorldScript.END]
	scripts["48:6410"] = [0x8D, 0x20, 0x64, Gen2WorldScript.END]
	scripts["48:6420"] = [Gen2WorldScript.SETEVENT, 41, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var target_map: Gen2WorldMap = data.world_map(1, 2)
	target_map.scripts["callbacks"] = []
	target_map.scripts["scenes"] = [{"id": 0, "script": 0x6410}]

	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	world.current_map.events["coord_events"][0]["script"] = 0x6400
	var results: Array = world.dispatch_script_events()
	assert_false(world.pending_runtime_request().is_empty(), "the sound should be pending")

	results = world.complete_runtime_request({"ok": true})
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_true(
		world.event_flag_active(41),
		"the destination's map scene did not run on the resume"
	)
	assert_false(results.is_empty())


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
	var schedule_random := RandomNumberGenerator.new()
	schedule_random.seed = 4046
	var schedule: Dictionary = restored.advance_schedule(schedule_random)
	assert_true(schedule["ok"])
	assert_eq(schedule["kind"], &"world_schedule_updated")


func test_schedule_refuses_active_roaming_without_a_random_stream() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var initial: Array = [{"species": 243, "level": 40, "map_group": 1, "map_number": 1}]
	state.ensure_roaming_mons(initial)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6), state)

	var result: Dictionary = world.advance_schedule()
	assert_false(result["ok"])
	assert_eq(result["kind"], &"world_schedule_failed")
	assert_eq(result["reason"], &"missing_schedule_random")
	assert_eq(result["roaming"], [])
	assert_eq(state.roaming_mons(), initial)


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
		world.advance_emotes_frame()
	assert_true(world.objects[0].emote_visible)
	assert_true(world.advance_emotes_frame())
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


## The approach is `applymovementlasttalked wMovementBuffer`, so every step
## reaches NormalStep (engine/overworld/movement.asm) and no permission stands
## between a seen trainer and the cell beside the player. Cerulean Gym is what
## needs it: its three swimmers stand on the pool.
func test_trainer_approach_crosses_water_a_wandering_object_could_not() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 5))
	var trainer: Gen2WorldObject = world.objects[0]
	trainer.cell = Vector2i(8, 8)
	trainer.object_type = Gen2WorldObject.OBJECTTYPE_TRAINER
	assert_eq(world.collision_permission_at(Vector2i(8, 7)), Gen2WorldCollision.WATER_TILE)
	assert_false(world.can_object_walk_to(Vector2i(8, 7), trainer, Vector2i.UP))

	var plan: Dictionary = world.trainer_approach_plan(0, Vector2i.UP, 3)
	assert_true(plan["ok"], JSON.stringify(plan))
	assert_eq(plan["target_cell"], Vector2i(8, 6))
	assert_eq(plan["path"], [Vector2i.UP, Vector2i.UP])

	var crossed: Dictionary = world.advance_trainer_approach_step(0, Vector2i.UP)
	assert_true(crossed["ok"], JSON.stringify(crossed))
	assert_eq(trainer.cell, Vector2i(8, 7))
	# TrainerWalkToPlayer passes 1 to ComputePathToWalkToPlayer, which selects
	# `step` rather than `slow_step`: StepVectors' normal row, 8 frames.
	assert_eq(trainer.step_passes_total, Gen2WorldAPI.STEP_PASSES_WALK)
	assert_true(world.advance_trainer_approach_step(0, Vector2i.UP)["ok"])
	assert_eq(trainer.cell, Vector2i(8, 6))


## Only GetNextTile's own bounds refuse, the same limit _apply_object_movement()
## keeps for a scripted step.
func test_trainer_approach_step_refuses_only_outside_the_map() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 5))
	var trainer: Gen2WorldObject = world.objects[0]
	trainer.cell = Vector2i(8, 0)
	trainer.object_type = Gen2WorldObject.OBJECTTYPE_TRAINER

	var refused: Dictionary = world.advance_trainer_approach_step(0, Vector2i.UP)
	assert_false(refused["ok"])
	assert_eq(refused["reason"], &"movement_blocked")
	assert_eq(refused["cell"], Vector2i(8, -1))
	assert_eq(trainer.cell, Vector2i(8, 0))


## StartBattleWithMapTrainerScript (engine/events/trainer_scripts.asm) falls
## through into AlreadyBeatenTrainerScript's scripttalkafter with
## wRunningTrainerBattleScript set, so the after-battle script runs at once and
## its own endifjustbattled is what usually ends it. Slowpoke Well's
## TrainerGruntM1 omits that command and clears the well from there.
func test_a_beaten_trainer_runs_its_after_script_before_any_second_interaction() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6B00"] = [
		Gen2WorldScript.SETEVENT, 0x11, 0x00, Gen2WorldScript.END,
	]
	scripts["48:6B10"] = [
		0x66, # endifjustbattled, raw
		Gen2WorldScript.SETEVENT, 0x12, 0x00, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)

	for probe: Array in [[0x6B00, 0x11, true], [0x6B10, 0x12, false]]:
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
			"after_script": int(probe[0]),
		}
		world.dispatch_sight_events()
		world.complete_runtime_request({"ok": true, "audio_played": false})
		var approach: Dictionary = (world.pending_runtime_request()["values"] as Dictionary)
		world.start_trainer_approach(
			int(approach["object_index"]), approach["direction"], int(approach["distance"])
		)
		world.advance_trainer_approach_step(0, Vector2i.UP)
		world.finish_trainer_approach(0)
		world.complete_runtime_request({
			"ok": true, "object_index": 0, "path": [Vector2i.UP],
		})
		world.run_event_queue(true)
		world.run_event_queue(true)
		var complete: Array = world.complete_runtime_request({
			"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
		})
		assert_eq(complete[0]["status"], &"complete", JSON.stringify(complete))
		assert_true(world.state.is_event_flag_active(42), "the beaten flag still commits")
		assert_eq(
			world.state.is_event_flag_active(int(probe[1])), bool(probe[2]),
			"after script at %s" % probe[0],
		)


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
	var disappeared: Array = world.dispatch_events(world.player_cell, true)
	assert_eq(disappeared[0]["status"], &"complete")
	assert_true(world.event_flag_active(7))
	assert_eq(world.visible_objects().size(), 0)

	world.clear_event_flag(7)
	var map: Gen2WorldMap = world.current_map
	map.events["bg_events"][0]["script"] = 0x6035
	var appeared: Array = world.dispatch_events(Vector2i(8, 6), true)
	assert_eq(appeared[0]["status"], &"complete")
	assert_false(world.event_flag_active(7))
	assert_eq(world.visible_objects().size(), 1)


func test_flagless_disappear_returns_when_the_map_rebuilds_objects() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6045"] = [Gen2WorldScript.raw_opcode(0x6D, true), 2, 0x91]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["objects"][0]["event_flag"] = 0
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6045
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))

	var disappeared: Array = world.dispatch_script_events()
	assert_eq(disappeared[0]["status"], &"complete", JSON.stringify(disappeared))
	assert_eq(world.visible_objects().size(), 0)
	assert_true(world.reload_current_map()["ok"])
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
	assert_eq(
		_final_status(_run_script(world, world.dispatch_script_events())), &"complete"
	)
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
	assert_eq(world.collision_code_at(Vector2i(0, 0)), 0x29)
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


## Script_showemote is `ScriptCall ShowEmoteScript`, whose middle command is
## `pause 0` over the delay this one just wrote into wScriptDelay. So the third
## operand holds the script rather than counting down on the object, and the
## emote comes back down from the same script's last command.
func test_scripted_emote_holds_the_script_for_its_own_pause() -> void:
	RomCache.write_json(RomCache.world_scripts_path(_directory), {
		"48:6150": [0x75, 1, 2, 2, 0x91],
	})
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 1).events["coord_events"][0]["script"] = 0x6150
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(7, 6))
	var dispatched: Array = world.dispatch_script_events()
	assert_eq(dispatched[0]["status"], &"waiting")
	assert_eq(dispatched[0]["event"]["frames"], 4, "two units of two frames")
	var object: Gen2WorldObject = world.objects[0]
	assert_true(object.emote_visible)
	assert_eq(object.emote_id, 1)

	for _frame: int in 3:
		assert_true(world.advance_script_wait_frame().is_empty())
	assert_true(object.emote_visible, "still up while the pause runs")
	assert_false(world.advance_emotes_frame(), "and not on a countdown of its own")

	var finished: Array = world.advance_script_wait_frame()
	assert_eq(_final_status(finished), &"complete")
	assert_false(object.emote_visible)


func test_surf_movement_accepts_water_and_exposes_an_encounter_request() -> void:
	var world := _world(Vector2i(8, 6))
	assert_true(world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)["ok"])
	var movement: Dictionary = world.move_result(Vector2i.DOWN)
	assert_true(movement["ok"])
	assert_eq(movement["kind"], &"water_move")
	assert_eq(world.collision_permission_at(world.player_cell), Gen2WorldCollision.WATER_TILE)
	## EnterMap's five-step cooldown: the map this world opened on set it, and
	## every request spends one step of it before the tile is even looked at.
	## The generator is seeded because the fixture's rate is 255 and one roll in
	## 256 is the one that refuses: unseeded, this case failed about that often.
	var random: RandomNumberGenerator = _seeded()
	for step: int in Gen2WorldState.WILD_ENCOUNTER_COOLDOWN_STEPS - 1:
		assert_true(world.encounter_request(random).is_empty(), "cooldown step %d" % step)
	var encounter: Dictionary = world.encounter_request(random)
	assert_eq(encounter["kind"], &"wild_encounter_requested")
	assert_eq(encounter["fish_group"], 1)
	assert_eq(encounter["values"]["kind"], &"wild")
	assert_eq(encounter["values"]["pokemon"], 16)
	assert_between(encounter["values"]["level"], 5, 9)
	assert_true(world.move(Vector2i.UP))


func test_stepping_onto_land_while_surfing_gets_out_of_the_water() -> void:
	# .TrySurf's .ExitWater: .GetOutOfWater restores PLAYER_NORMAL and the
	# walking sprite before .DoStep, so the mode is already back by the time the
	# result is reported.
	var world := _world(Vector2i(8, 7))
	assert_true(world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)["ok"])
	world.player_sprite_number = Gen2WorldSprite.SPRITE_SURF
	assert_eq(world.collision_permission_at(Vector2i(8, 7)), Gen2WorldCollision.WATER_TILE)

	var exited: Dictionary = world.move_result(Vector2i.UP)
	assert_true(exited["ok"], JSON.stringify(exited))
	assert_eq(exited["kind"], &"exit_water")
	assert_eq(world.player_cell, Vector2i(8, 6))
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_PLAYER)
	# Walking again, so the water cell is no longer a legal step.
	assert_false(world.move(Vector2i.DOWN))


func test_a_step_between_water_cells_stays_a_water_move() -> void:
	var world := _world(Vector2i(8, 6))
	assert_true(world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)["ok"])
	world.player_sprite_number = Gen2WorldSprite.SPRITE_SURF
	assert_eq(world.move_result(Vector2i.DOWN)["kind"], &"water_move")
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURF)


func test_surf_request_refuses_a_facing_object_on_crystal_only() -> void:
	# Crystal's .TrySurf ends with a CheckFacingObject that pokegold's omits,
	# under its own "You can Surf on top of NPCs" bug comment.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_FOG, true))
	var world := _world(Vector2i(8, 6), state)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	world.objects[0].cell = Vector2i(8, 7)
	assert_not_null(world.object_at(Vector2i(8, 7)))
	# CheckPartyMove runs before CheckFacingObject, so the party has to know Surf
	# for the object test to be the one that answers.
	world.set_party_summary(
		1, false, [1] as Array[int], [[Gen2WorldFieldMove.MOVE_SURF]], ["MON"], [false]
	)
	assert_eq(world.surf_request()["reason"], &"cannot_surf")

	var gold_directory: String = RomCache.directory_for(&"testworldsurfgold", "abcdef0123456789cd")
	RomCache.clear(gold_directory)
	RomCache.prepare(gold_directory)
	var saved_directory: String = _directory
	_directory = gold_directory
	_write_cache("gold")
	_directory = saved_directory

	var gold_data: GameData = GameData.open_directory(gold_directory)
	assert_false(Gen2WorldState.is_crystal_profile(gold_data))
	var gold_state := Gen2WorldState.new()
	gold_state.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_FOG, false))
	var gold_world: Gen2WorldAPI = Gen2WorldAPI.open(
		gold_data, 1, 1, Vector2i(8, 6), gold_state
	)
	gold_world.player_facing = Gen2WorldSprite.FACING_DOWN
	gold_world.objects[0].cell = Vector2i(8, 7)
	assert_not_null(gold_world.object_at(Vector2i(8, 7)))
	gold_world.set_party_summary(
		1, false, [1] as Array[int], [[Gen2WorldFieldMove.MOVE_SURF]], ["MON"], [false]
	)
	assert_true(bool(gold_world.surf_request().get("ok", false)))
	RomCache.clear(gold_directory)


func test_world_snapshot_round_trips_the_surfing_player_sprite() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 7))
	assert_true(world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)["ok"])
	world.player_sprite_number = Gen2WorldSprite.SPRITE_SURFING_PIKACHU
	var encoded: Dictionary = world.snapshot().to_dict()
	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(
		data, Gen2WorldSnapshot.from_dict(encoded)
	)
	assert_not_null(restored)
	assert_eq(restored.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(restored.player_sprite_number, Gen2WorldSprite.SPRITE_SURFING_PIKACHU)

	# A snapshot written before the sprite joined the format carries the movement
	# mode alone, which resolves every state but the Pikachu variant.
	encoded.erase("player_sprite_number")
	var legacy := Gen2WorldSnapshot.from_dict(encoded)
	assert_eq(legacy.player_sprite_number, Gen2WorldSprite.SPRITE_SURF)
	encoded["movement_mode"] = "walk"
	assert_eq(
		Gen2WorldSnapshot.from_dict(encoded).player_sprite_number,
		Gen2WorldSprite.SPRITE_PLAYER
	)


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


## `CanEncounterWildMon`: outdoors it is `CheckGrassCollision` on the standing
## tile alone, so open ground rolls nothing however high the map's rate is.
func test_an_unforced_encounter_needs_the_grass_the_source_checks_for() -> void:
	var world := _world(Vector2i(5, 10))
	world.state.set_wild_encounter_cooldown(0)
	assert_true(world.can_encounter_wild_mon(), "COLL_TALL_GRASS")
	assert_false(world.encounter_request(_seeded()).is_empty())

	world.player_cell = Vector2i(5, 9)
	assert_eq(world.collision_code_at(world.player_cell), 0, "plain land")
	assert_false(world.can_encounter_wild_mon())
	assert_true(world.encounter_request(_seeded()).is_empty())


## The `CAVE`/`DUNGEON` branch skips the grass test, and the ice test is the one
## thing both branches share.
func test_a_cave_rolls_on_any_tile_and_ice_refuses_on_every_environment() -> void:
	var world := _world(Vector2i(5, 9))
	world.state.set_wild_encounter_cooldown(0)
	world.current_map.environment = Gen2WorldAPI.ENVIRONMENT_CAVE
	assert_true(world.can_encounter_wild_mon(), "a cave floor is not grass")
	world.current_map.environment = Gen2WorldAPI.ENVIRONMENT_DUNGEON
	assert_true(world.can_encounter_wild_mon())

	world.player_cell = Vector2i(6, 10)
	assert_eq(world.collision_code_at(world.player_cell), Gen2WorldCollision.COLL_ICE)
	for environment: int in [
		Gen2WorldAPI.ENVIRONMENT_CAVE, Gen2WorldAPI.ENVIRONMENT_DUNGEON, 2,
	]:
		world.current_map.environment = environment
		assert_false(world.can_encounter_wild_mon(), "ice in environment %d" % environment)


## `wildoff` and `wildon`, the one thing that turns the whole roll off from a
## script.
func test_wildoff_stops_every_roll_until_wildon_puts_it_back() -> void:
	var world := _world(Vector2i(5, 10))
	world.state.set_wild_encounter_cooldown(0)
	world.state.set_wild_encounters_off(true)
	assert_false(world.can_encounter_wild_mon())
	assert_true(world.encounter_request(_seeded()).is_empty())
	world.state.set_wild_encounters_off(false)
	assert_false(world.encounter_request(_seeded()).is_empty())


## `CheckWildEncounterCooldown`: five steps are written on map entry and the
## fifth is the one that rolls, since the step taking the counter to zero is let
## through.
func test_a_map_entry_costs_four_steps_of_wild_encounters() -> void:
	var world := _world(Vector2i(5, 10))
	assert_eq(
		world.state.wild_encounter_cooldown(),
		Gen2WorldState.WILD_ENCOUNTER_COOLDOWN_STEPS
	)
	for step: int in Gen2WorldState.WILD_ENCOUNTER_COOLDOWN_STEPS - 1:
		assert_true(world.encounter_request(_seeded()).is_empty(), "step %d" % step)
	assert_false(world.encounter_request(_seeded()).is_empty())
	assert_eq(world.state.wild_encounter_cooldown(), 0)

	## `Script_reloadmap` re-enters the map, which is what a finished battle
	## does, so the counter is back up afterwards.
	assert_true(world.reload_current_map()["ok"])
	assert_eq(
		world.state.wild_encounter_cooldown(),
		Gen2WorldState.WILD_ENCOUNTER_COOLDOWN_STEPS
	)


## A generator whose first roll is under every fixture rate, so a request that
## reaches the roll resolves and one that does not is the gate's answer.
func _seeded() -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = 1
	return random


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


## engine/overworld/player_movement.asm's DoPlayerMovement.CheckTile, which runs
## before .CheckTurning and .TryStep and overwrites wWalkingDirection, so the
## standing tile decides the step and the pressed direction is discarded.
func test_a_waterfall_tile_pushes_the_player_down_whatever_is_pressed() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(1, 5))
	assert_eq(StringName(world.forced_movement()["kind"]), &"walk")
	assert_eq(world.forced_movement()["direction"], Vector2i.DOWN)

	var forced: Dictionary = world.move_result(Vector2i.UP)
	assert_true(bool(forced.get("ok", false)), JSON.stringify(forced))
	assert_eq(forced["kind"], &"forced_move")
	assert_eq(world.player_cell, Vector2i(1, 6))
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_DOWN)
	# Off the waterfall, ordinary movement resumes.
	assert_eq(StringName(world.forced_movement()["kind"]), &"none")
	assert_eq(world.move_result(Vector2i.UP)["kind"], &"move")


func test_a_forced_step_commits_into_a_cell_an_ordinary_step_refuses() -> void:
	# .continue_walk reaches .DoStep, which never consults permissions, so the
	# wall below a door does not stop the step off it.
	var world: Gen2WorldAPI = _world(Vector2i(12, 5))
	assert_false(world.can_walk_to(Vector2i(12, 6), Vector2i.DOWN))
	var forced: Dictionary = world.move_result(Vector2i.LEFT)
	assert_true(bool(forced.get("ok", false)), JSON.stringify(forced))
	assert_eq(forced["kind"], &"forced_move")
	assert_eq(world.player_cell, Vector2i(12, 6))


func test_a_forced_step_off_the_map_edge_takes_the_connection() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(15, 5))
	assert_eq(world.forced_movement()["direction"], Vector2i.RIGHT)
	var forced: Dictionary = world.move_result(Vector2i.LEFT)
	assert_true(bool(forced.get("ok", false)), JSON.stringify(forced))
	assert_eq(world.map_id(), Vector2i(1, 2))


func test_a_forced_step_spends_a_repel_step_like_an_ordinary_one() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(1, 5))
	world.state.set_repel_steps(5)
	assert_true(bool(world.move_result(Vector2i.DOWN).get("ok", false)))
	assert_eq(world.state.repel_steps(), 4)


## advance_forced_movement() is the no-input path, since the source polls
## .CheckTile every frame rather than only on a press.
func test_advance_forced_movement_moves_without_a_pressed_direction() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(1, 5))
	var forced: Dictionary = world.advance_forced_movement()
	assert_true(bool(forced.get("ok", false)), JSON.stringify(forced))
	assert_eq(world.player_cell, Vector2i(1, 6))
	assert_true(world.advance_forced_movement().is_empty())


## engine/overworld/player_movement.asm's DoPlayerMovement.CheckForced and
## CheckStandingOnIce. A step onto ice leaves wPlayerTurningDirection set, and
## the next poll ORs that direction back into wCurInput, so the walk carries on
## with nothing held.
func test_a_step_onto_ice_keeps_going_with_nothing_held() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(1, 1))
	world.player_facing = world.facing_for_direction(Vector2i.RIGHT)
	assert_true(bool(world.player_input_move(Vector2i.RIGHT).get("ok", false)))
	assert_eq(world.player_cell, Vector2i(2, 1))
	assert_true(world.standing_on_ice())
	assert_eq(world.effective_input_direction(Vector2i.ZERO), Vector2i.RIGHT)

	# The run to the wall, one poll a cell, all of it with nothing held.
	for expected: int in [3, 4, 5]:
		_finish_step(world)
		var forced: Vector2i = world.effective_input_direction(Vector2i.ZERO)
		assert_true(bool(world.player_input_move(forced).get("ok", false)))
		assert_eq(world.player_cell, Vector2i(expected, 1))

	# `.NotMoving` reaches `._WalkInPlace`, which clears the byte, so the wall
	# ends the slide rather than the player being stuck against it.
	_finish_step(world)
	assert_false(bool(world.player_input_move(Vector2i.RIGHT).get("ok", false)))
	assert_eq(world.player_cell, Vector2i(5, 1))
	assert_false(world.standing_on_ice())
	assert_eq(world.effective_input_direction(Vector2i.ZERO), Vector2i.ZERO)


## Standing on ice is not enough: CheckStandingOnIce tests the turning direction
## first, so a player who walked onto the ice and then stopped may press again.
func test_ice_forces_nothing_once_the_player_has_stood_still() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(1, 1))
	world.player_facing = world.facing_for_direction(Vector2i.RIGHT)
	assert_true(bool(world.player_input_move(Vector2i.RIGHT).get("ok", false)))
	_finish_step(world)
	world.note_standing_still()
	assert_false(world.standing_on_ice())
	assert_eq(world.effective_input_direction(Vector2i.ZERO), Vector2i.ZERO)
	assert_eq(world.effective_input_direction(Vector2i.LEFT), Vector2i.LEFT)


## `.CheckForced` ORs its bit into wCurInput rather than replacing it, so both
## directions are set and `.GetAction`'s own test order decides: down, up, left,
## right. A held DOWN therefore beats a slide running right, and a held UP does
## not beat a slide running down.
func test_a_held_direction_beats_the_slide_only_in_getactions_order() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(1, 1))
	world.player_facing = world.facing_for_direction(Vector2i.RIGHT)
	assert_true(bool(world.player_input_move(Vector2i.RIGHT).get("ok", false)))
	_finish_step(world)
	assert_eq(world.effective_input_direction(Vector2i.DOWN), Vector2i.DOWN)
	assert_eq(world.effective_input_direction(Vector2i.UP), Vector2i.UP)
	assert_eq(world.effective_input_direction(Vector2i.LEFT), Vector2i.LEFT)
	# Right against right is still right, and nothing held is the slide's own.
	assert_eq(world.effective_input_direction(Vector2i.RIGHT), Vector2i.RIGHT)
	assert_eq(world.effective_input_direction(Vector2i.ZERO), Vector2i.RIGHT)


## `.CheckTurning`'s first test is wPlayerTurningDirection, so the tap-to-turn
## only happens from a standstill. The poll right after a step still has the
## byte set, which is what keeps a walk around a corner from spending a turn.
func test_a_direction_pressed_straight_after_a_step_steps_rather_than_turns() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	assert_eq(world.player_input_move(Vector2i.LEFT)["kind"], &"turn")
	_finish_step(world)
	assert_eq(world.player_input_move(Vector2i.LEFT)["kind"], &"move")
	_finish_step(world)
	# Still walking: the byte is set, so UP is a step and not a turn.
	assert_eq(world.player_input_move(Vector2i.UP)["kind"], &"move")
	_finish_step(world)
	# A poll that commits nothing is `.StandInPlace`, and the tap turns again.
	world.note_standing_still()
	assert_eq(world.player_input_move(Vector2i.RIGHT)["kind"], &"turn")


## `RefreshPlayerSprite` clears the byte, and every warp and connection reaches
## it, so no walk carries its turning direction into the map it arrives on.
func test_a_warp_clears_the_turning_direction() -> void:
	var world: Gen2WorldAPI = _world(Vector2i(5, 6))
	world.player_facing = world.facing_for_direction(Vector2i.RIGHT)
	assert_true(bool(world.player_input_move(Vector2i.RIGHT).get("ok", false)))
	assert_eq(world.player_cell, Vector2i(6, 6))
	_finish_step(world)
	assert_true(bool(world.try_warp().get("ok", false)))
	# The byte is zero on the far side, so a tap turns rather than steps.
	assert_eq(world.player_input_move(Vector2i.LEFT)["kind"], &"turn")


func _finish_step(world: Gen2WorldAPI) -> void:
	for _pass: int in 64:
		if not world.player_step_in_progress():
			return
		world.advance_player_step_pass()


## ObjectEventTypeArray's `.itemball` copies `db item, quantity` into
## wItemBallData rather than running it, so the pointer must never reach the
## script runner as code.
func test_an_item_ball_is_dispatched_from_its_two_data_bytes() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# itemball ITEM3, 2. Byte $02 is `iffalse` and $91 `end`, so a runner that
	# parsed these as code would branch, not hand over an item.
	scripts["48:6030"] = [3, 2, 0x91]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)

	var world: Gen2WorldAPI = _world(Vector2i(5, 5))
	var ball: Gen2WorldObject = world.objects[0]
	ball.object_type = Gen2WorldObject.OBJECTTYPE_ITEMBALL
	world.player_facing = Gen2WorldSprite.FACING_DOWN

	var results: Array = world.interact()
	assert_eq(results.size(), 1, JSON.stringify(results))
	assert_eq(results[0]["source"]["kind"], &"item_ball")
	assert_eq(results[0]["source"]["item"], 3)
	assert_eq(results[0]["source"]["quantity"], 2)
	# FindItemInBallScript receives before it shows anything, and the text names
	# the item off the imported table, whose lookup is one-based like the source's.
	assert_eq(results[0]["status"], &"waiting", JSON.stringify(results[0]))
	assert_eq(results[0]["event"]["text"], "Found\n%s!" % _item_name(3))

	# `playsound SFX_ITEM` by name, not `specialsound`, and then `itemnotify`.
	var notified: Array = _receipt_sound(world, &"sound")
	assert_eq(
		int(notified[0]["event"]["request"]["values"]["address"]),
		Gen2WorldScriptRunner.SFX_ITEM
	)
	var finished: Array = _receipt_notify(world, 3)
	assert_eq(finished[0]["status"], &"complete", JSON.stringify(finished[0]))
	assert_eq(world.state.items().get(3, 0), 2)
	# `disappear LAST_TALKED` writes the ball's own event flag, so it stays gone.
	assert_true(world.event_flag_active(7))
	assert_false((world.objects[0] as Gen2WorldObject).active)


func test_an_item_ball_with_no_item_byte_fails_instead_of_running_data() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6030"] = [0, 0, 0x91]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)

	var world: Gen2WorldAPI = _world(Vector2i(5, 5))
	var ball: Gen2WorldObject = world.objects[0]
	ball.object_type = Gen2WorldObject.OBJECTTYPE_ITEMBALL
	world.player_facing = Gen2WorldSprite.FACING_DOWN

	# A zero item is not an item ball the cache can answer, so the typed request
	# is not built and the object falls back to its own pointer.
	var results: Array = world.interact()
	assert_eq(results.size(), 1, JSON.stringify(results))
	assert_ne(results[0]["source"]["kind"], &"item_ball")


func test_a_full_item_pocket_keeps_an_item_ball_and_its_flag() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6030"] = [3, 1, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var items: Array = RomCache.read_json(RomCache.items_path(_directory))
	for raw: Dictionary in items:
		var item: int = int(raw.get("number", 0))
		if item >= 3 and item <= 23:
			raw["pocket"] = Gen2WorldPack.TYPE_ITEM
	RomCache.write_json(RomCache.items_path(_directory), items)
	var data: GameData = GameData.open_directory(_directory)
	var owned: Dictionary = {}
	for item: int in range(4, 24):
		owned[item] = 1
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(5, 5), Gen2WorldState.new({}, {}, owned)
	)
	var ball: Gen2WorldObject = world.objects[0]
	ball.object_type = Gen2WorldObject.OBJECTTYPE_ITEMBALL
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	assert_eq(world.interact().size(), 1)
	var finished: Array = world.run_event_queue(true)
	assert_eq(finished[0]["status"], &"complete")
	assert_eq(world.state.item_quantity(3), 0)
	assert_false(world.event_flag_active(7))
	assert_true((world.objects[0] as Gen2WorldObject).active)


## `.itemifset` copies the `hiddenitem` macro's `dwb event, item` into
## wHiddenItemData rather than running it, so a BGEVENT_ITEM pointer must never
## reach the runner as code either. The flag comes first, little-endian.
func test_a_hidden_item_is_dispatched_from_its_three_data_bytes() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# hiddenitem ITEM3, EVENT 20. Byte $14 is a real opcode, so a runner that
	# parsed this as code would run it instead of handing over an item.
	scripts["48:61A0"] = [20, 0, 3, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 7))
	world.current_map.events["bg_events"] = [
		{"x": 8, "y": 6, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x61A0},
	]
	world.player_facing = Gen2WorldSprite.FACING_UP

	var results: Array = world.interact()
	assert_eq(results.size(), 1, JSON.stringify(results))
	assert_eq(results[0]["source"]["kind"], &"hidden_item")
	assert_eq(results[0]["source"]["item"], 3)
	assert_eq(results[0]["source"]["flag"], 20)
	assert_eq(results[0]["status"], &"waiting", JSON.stringify(results[0]))
	# _PlayerFoundItemText is _FoundItemText's wording, so both share one string.
	assert_eq(results[0]["event"]["text"], "Found\n%s!" % _item_name(3))

	# HiddenItemScript's own `specialsound` and `itemnotify`, which name the
	# pocket the item landed in.
	_receipt_sound(world, &"special_sound")
	var finished: Array = _receipt_notify(world, 3)
	assert_eq(finished[0]["status"], &"complete", JSON.stringify(finished[0]))
	assert_eq(world.state.items().get(3, 0), 1)
	# `callasm SetMemEvent` writes the record's own flag, not an object's.
	assert_true(world.event_flag_active(20))


func test_a_full_item_pocket_leaves_a_hidden_item_flag_clear() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:61A0"] = [20, 0, 3, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var items: Array = RomCache.read_json(RomCache.items_path(_directory))
	for raw: Dictionary in items:
		var item: int = int(raw.get("number", 0))
		if item >= 3 and item <= 23:
			raw["pocket"] = Gen2WorldPack.TYPE_ITEM
	RomCache.write_json(RomCache.items_path(_directory), items)
	var data: GameData = GameData.open_directory(_directory)
	var owned: Dictionary = {}
	for item: int in range(4, 24):
		owned[item] = 1
	var world := Gen2WorldAPI.open(
		data, 1, 1, Vector2i(8, 7), Gen2WorldState.new({}, {}, owned)
	)
	world.current_map.events["bg_events"] = [{
		"x": 8, "y": 6, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x61A0,
	}]
	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(world.interact().size(), 1)
	var finished: Array = world.run_event_queue(true)
	assert_eq(finished[0]["status"], &"complete")
	assert_eq(world.state.item_quantity(3), 0)
	assert_false(world.event_flag_active(20))


## CheckBGEventFlag then `jp nz, .dontread`: the record answers only while its
## flag is clear, which is what stops a hidden item being picked up twice.
func test_a_hidden_item_answers_only_while_its_flag_is_clear() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:61A8"] = [21, 0, 3, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 7))
	world.current_map.events["bg_events"] = [
		{"x": 8, "y": 6, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x61A8},
	]
	world.player_facing = Gen2WorldSprite.FACING_UP

	world.set_event_flag(21)
	assert_true(world.interact().is_empty())

	world.clear_event_flag(21)
	assert_eq(world.interact().size(), 1)
	_receipt_sound(world, &"special_sound")
	assert_eq(_receipt_notify(world, 3)[0]["status"], &"complete")
	assert_eq(world.state.items().get(3, 0), 1)
	# And the flag it just wrote closes it again, so a second A press is inert.
	assert_true(world.interact().is_empty())
	assert_eq(world.state.items().get(3, 0), 1)


func test_a_hidden_item_with_no_item_byte_fails_instead_of_running_data() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:61B0"] = [22, 0, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 7))
	world.current_map.events["bg_events"] = [
		{"x": 8, "y": 6, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x61B0},
	]
	world.player_facing = Gen2WorldSprite.FACING_UP

	# A zero item is not a record the cache can answer, so nothing is dispatched
	# rather than the three bytes being run as opcodes.
	assert_true(world.interact().is_empty())
	assert_false(world.event_flag_active(22))


## `CheckForHiddenItems`, the whole of the Itemfinder: the screen the player is
## in the middle of, which is four cells up and left and four down and five
## right, and only while the record's flag is clear.
func test_the_itemfinder_answers_for_a_hidden_item_inside_the_screen() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:61C0"] = [23, 0, 3, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 7))
	world.current_map.events["bg_events"] = [
		{"x": 8, "y": 6, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x61C0},
	]
	assert_true(world.hidden_item_nearby())

	# The window is asymmetric on x, because the bottom right corner is
	# `wXCoord + SCREEN_WIDTH / 4` and the difference is compared against half a
	# screen: the item may sit four cells left of the player and five right.
	world.player_cell = Vector2i(12, 6)
	assert_true(world.hidden_item_nearby(), "the item four cells left")
	world.player_cell = Vector2i(13, 6)
	assert_false(world.hidden_item_nearby())
	world.player_cell = Vector2i(3, 6)
	assert_true(world.hidden_item_nearby(), "the item five cells right")
	world.player_cell = Vector2i(2, 6)
	assert_false(world.hidden_item_nearby())
	world.player_cell = Vector2i(8, 10)
	assert_true(world.hidden_item_nearby(), "the item four cells up")
	world.player_cell = Vector2i(8, 11)
	assert_false(world.hidden_item_nearby())

	# A found item is not a nearby one, which is the same flag check the read is
	# gated on.
	world.player_cell = Vector2i(8, 7)
	world.set_event_flag(23)
	assert_false(world.hidden_item_nearby())


## The map gate every key-item effect opens with. Only `_Squirtbottle` answers
## anyway: it writes `wItemEffectSucceeded` before the script it queues decides
## anything, so the pack closes and the queued script says the line instead.
## Which script each of the three reaches on its own map is swept over all three
## cartridges by `tools/checks/pack.gd`, since no synthetic map can carry them.
func test_a_key_item_effect_refuses_off_its_own_map() -> void:
	var world := Gen2WorldAPI.open(GameData.open_directory(_directory), 1, 1, Vector2i(8, 7))
	assert_false(bool(world.card_key_request().get("ok", false)))
	assert_false(bool(world.basement_key_request().get("ok", false)))

	var nothing: Dictionary = world.squirtbottle_request()
	assert_true(bool(nothing.get("ok", false)))
	assert_eq(StringName(nothing.get("kind", &"")), &"squirtbottle_nothing")
	assert_true(world.queue_item_script(nothing).is_empty())


func _item_name(number: int) -> String:
	return GameData.open_directory(_directory).item_name(number)


## `GiveItemScript`'s tail, which every item receipt now ends on. Acknowledging
## the receipt's own line is what puts the sound out with the host.
func _receipt_sound(world: Gen2WorldAPI, kind: StringName) -> Array:
	var sound: Array = world.run_event_queue(true)
	assert_eq(
		StringName(sound[0]["event"]["request"]["values"]["kind"]), kind,
		JSON.stringify(sound)
	)
	return sound


## `itemnotify` behind the sound: one box naming the item and its pocket.
func _receipt_notify(world: Gen2WorldAPI, item: int) -> Array:
	var notified: Array = world.complete_runtime_request({"ok": true})
	assert_string_contains(String(notified[0]["event"]["text"]), _item_name(item))
	return world.run_event_queue(true)


## S2: `?RAM?CFA4?` was the text engine faithfully reporting an unresolved
## pointer. `_ReceivedItemText` is `text_ram wStringBuffer4`, and nothing mapped
## an address to the buffers the runner fills by number.
func test_verbosegiveitem_fills_the_buffer_its_text_reads_by_address() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# verbosegiveitem item 1 x1, then end. This cache carries Crystal's stream,
	# where verbosegiveitem is $9e rather than pokegold's $9d.
	scripts["48:6400"] = [
		Gen2WorldScript.raw_opcode(0x9D, true), 1, 1, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.from_dict({}), {
		"kind": &"script", "bank": 48, "script": 0x6400,
	})
	runner.advance()

	var context: Dictionary = runner.text_context()
	var ram: Dictionary = context["ram"]
	assert_true(
		ram.has(0xCFA4),
		"wStringBuffer4 is what _ReceivedItemText names: %s" % JSON.stringify(ram.keys())
	)
	assert_eq(String(ram[0xCFA4]), data.item_name(1))
	assert_eq(
		String(context["buffers"][RomLayout.STRING_BUFFER_4]), data.item_name(1),
		"the same value is still reachable by text_buffer number"
	)


## `GiveItemScript`, which every `verbosegiveitem` calls: the received line, the
## sound and `itemnotify`'s box, and on a full pack the same line followed by
## `pocketisfull` instead. The line is printed either way, because the source's
## `iffalse` sits behind its own `writetext`.
func test_a_verbose_give_prints_the_line_the_pocket_and_the_full_branch() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6420"] = [
		Gen2WorldScript.raw_opcode(0x9D, true), 1, 1, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	## One pocket for the given item and the twenty that fill it, so
	## `GetPocketName` has the same answer either way.
	var items: Array = RomCache.read_json(RomCache.items_path(_directory))
	for raw: Dictionary in items:
		if int(raw.get("number", 0)) <= Gen2WorldPack.MAX_ITEMS + 1:
			raw["pocket"] = Gen2WorldPack.TYPE_ITEM
	RomCache.write_json(RomCache.items_path(_directory), items)
	var data: GameData = GameData.open_directory(_directory)
	var request: Dictionary = {"kind": &"script", "bank": 48, "script": 0x6420}

	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.from_dict({}), request)
	assert_eq(runner.advance()["event"]["text"], "Received\n%s." % data.item_name(1))
	var sound: Dictionary = runner.advance(true)
	assert_eq(
		StringName(sound["event"]["request"]["values"]["kind"]), &"special_sound",
		JSON.stringify(sound)
	)
	var notified: Dictionary = runner.complete_runtime_request({"ok": true})
	## `cont`, so the box scrolls one line and the item name stays under it.
	assert_eq(
		notified["event"]["text"],
		"Put the\n%s in%sthe ITEM POCKET." % [
			data.item_name(1), Gen2TextStream.SCROLL_BREAK,
		]
	)
	assert_eq(runner.advance(true)["status"], &"complete")

	## A pack with no room for it: `ReceiveItem` returns false, the line is still
	## printed, and `pocketisfull` names the pocket that had no room.
	var owned: Dictionary = {}
	for number: int in range(2, 2 + Gen2WorldPack.MAX_ITEMS):
		owned[number] = 1
	var full := Gen2WorldState.new({}, {}, owned)
	var refused := Gen2WorldScriptRunner.begin(data, full, request)
	assert_eq(refused.advance()["event"]["text"], "Received\n%s." % data.item_name(1))
	var pocket: Dictionary = refused.advance(true)
	assert_eq(pocket["event"]["text"], "The ITEM POCKET\nis full…", JSON.stringify(pocket))
	assert_eq(refused.advance(true)["status"], &"complete")
	assert_eq(full.item_quantity(1), 0, "and nothing was received")


## The command on its own, which seventy-nine scripts across the three cartridges
## run after a plain `giveitem`. `CurItemName` reads wCurItem, so the box names
## whatever that give wrote and the script runs on behind it.
func test_itemnotify_names_the_item_the_give_before_it_wrote() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6430"] = [
		Gen2WorldScript.GIVEITEM, 1, 1,
		Gen2WorldScript.ITEMNOTIFY, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"script", "bank": 48, "script": 0x6430,
	})
	var notified: Dictionary = runner.advance()
	assert_string_contains(String(notified["event"]["text"]), data.item_name(1))
	assert_string_contains(String(notified["event"]["text"]), "POCKET")
	assert_eq(runner.advance(true)["status"], &"complete")
	assert_eq(state.item_quantity(1), 1)


func test_text_ram_resolves_through_the_cartridges_own_pointer_table() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	# getitemname into STRING_BUFFER_1, which the table puts at $CF6B on Gold.
	# The macro emits the item before the buffer (macros/scripts/events.asm:437).
	scripts["48:6410"] = [
		Gen2WorldScript.GETITEMNAME, 1, RomLayout.STRING_BUFFER_1, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.from_dict({}), {
		"kind": &"script", "bank": 48, "script": 0x6410,
	})
	runner.advance()

	var ram: Dictionary = runner.text_context()["ram"]
	assert_true(ram.has(0xCF6B), "buffer 4 is wStringBuffer1, not wStringBuffer4")
	assert_false(ram.has(0xCFA4))


## `Script_getstring` is `CopyName1`: a plain character run ending in `@`, not a
## text-command stream. `PokegearName` is `db "#GEAR@"`, and `#` is `$54`, which
## the command layer refuses as an unknown command; decoding it that way filled
## the buffer with nothing and printed "<PLAYER> received !" in Mom's own scene.
func test_getstring_reads_a_name_and_not_a_text_stream() -> void:
	var texts: Dictionary = RomCache.read_json(RomCache.world_text_path(_directory))
	# "#GEAR@": the word code for POKé, four letters, and the name terminator.
	texts["48:6500"] = [0x54, 0x86, 0x84, 0x80, 0x91, 0x50]
	RomCache.write_json(RomCache.world_text_path(_directory), texts)
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6430"] = [
		Gen2WorldScript.GETSTRING, 0x00, 0x65, RomLayout.STRING_BUFFER_4,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.from_dict({}), {
		"kind": &"script", "bank": 48, "script": 0x6430,
	})
	runner.advance()

	var context: Dictionary = runner.text_context()
	assert_eq(String(context["buffers"][RomLayout.STRING_BUFFER_4]), "POKéGEAR")
	assert_eq(
		String((context["ram"] as Dictionary)[0xCFA4]), "POKéGEAR",
		"_ReceivedItemText reads wStringBuffer4 by address, not by number"
	)


func test_an_unfilled_buffer_contributes_no_address() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var runner := Gen2WorldScriptRunner.begin(data, Gen2WorldState.from_dict({}), {
		"kind": &"script", "bank": 48, "script": 0x6400,
	})

	assert_eq(runner.text_context()["ram"], {})


## M2: LoadMetatiles substitutes wMapBorderBlock for a block byte of $00, and the
## padding ChangeMap puts around the map is that same block. Both are graphics
## only, so collision still reads the raw byte.
func test_the_page_draws_border_block_past_the_edge_of_the_map() -> void:
	var world: Gen2WorldAPI = _world(Vector2i.ZERO)
	world.current_map.border_block = 1

	assert_eq(world.drawn_block_at(-1, 0), 1, "west of the map is border block")
	assert_eq(world.drawn_block_at(0, -1), 1, "north of the map is border block")
	assert_eq(
		world.drawn_block_at(world.current_map.width_blocks, 0), 1,
		"east of the map is border block"
	)
	assert_eq(
		world.drawn_block_at(0, world.current_map.height_blocks), 1,
		"south of the map is border block"
	)


## FillMapConnections copies three real block rows or columns into the padded
## block buffer. The renderer must see those bytes before falling back to the
## current map's border block.
func test_the_page_draws_connected_map_strips_past_each_edge() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var source: Gen2WorldMap = data.world_map(1, 1)
	var target: Gen2WorldMap = data.world_map(1, 2)
	target.blocks.fill(0)
	var connection: Dictionary = source.connections[0]
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))

	connection["direction"] = "north"
	target.blocks[5 * target.width_blocks + 2] = 1
	assert_eq(world.drawn_block_at(2, -1), 1)
	assert_eq(world.drawn_block_at(2, -4), source.border_block, "north strip is three blocks")

	connection["direction"] = "south"
	target.blocks[2] = 1
	assert_eq(world.drawn_block_at(2, source.height_blocks), 1)
	assert_eq(
		world.drawn_block_at(2, source.height_blocks + 3), source.border_block,
		"south strip is three blocks",
	)

	connection["direction"] = "west"
	target.blocks[2 * target.width_blocks + 7] = 1
	assert_eq(world.drawn_block_at(-1, 2), 1)
	assert_eq(world.drawn_block_at(-4, 2), source.border_block, "west strip is three blocks")

	connection["direction"] = "east"
	target.blocks[2 * target.width_blocks] = 1
	assert_eq(world.drawn_block_at(source.width_blocks, 2), 1)
	assert_eq(
		world.drawn_block_at(source.width_blocks + 3, 2), source.border_block,
		"east strip is three blocks",
	)


func test_connection_strip_offsets_map_source_padding_to_target_blocks() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var source: Gen2WorldMap = data.world_map(1, 1)
	var target: Gen2WorldMap = data.world_map(1, 2)
	target.blocks.fill(0)
	target.blocks[2 * target.width_blocks] = 1
	var connection: Dictionary = source.connections[0]
	connection["direction"] = "east"
	connection["y_offset"] = 4
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(15, 0))

	assert_eq(world.drawn_block_at(source.width_blocks, 0), 1)
	assert_eq(
		world.drawn_block_at(source.width_blocks, target.height_blocks - 2),
		source.border_block,
		"the connection ends when its translated target coordinate leaves the map",
	)
	target.blocks[3 * target.width_blocks] = 1
	connection["length"] = 1
	assert_eq(
		world.drawn_block_at(source.width_blocks, 1), source.border_block,
		"the copied strip stops at the record's own length even inside the target map",
	)


func test_a_zero_block_in_a_connection_strip_uses_the_current_border() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var source: Gen2WorldMap = data.world_map(1, 1)
	var target: Gen2WorldMap = data.world_map(1, 2)
	source.border_block = 1
	target.blocks[2 * target.width_blocks] = 0
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(15, 4))

	assert_eq(world.drawn_block_at(source.width_blocks, 2), 1)


func test_a_zero_block_is_drawn_as_border_but_still_collides_as_zero() -> void:
	var world: Gen2WorldAPI = _world()
	world.current_map.border_block = 1
	world.change_block(0, 0, 0)

	assert_eq(world.drawn_block_at(0, 0), 1, "LoadMetatiles swaps $00 for the border")
	assert_eq(world.block_at(0, 0), 0, "GetCoordTileCollision still reads the raw byte")


func test_the_page_is_fully_drawn_even_when_the_map_is_smaller_than_it() -> void:
	# Every tile answered, none left at the -1 the old clamp produced.
	var world: Gen2WorldAPI = _world(Vector2i.ZERO)
	var page: PackedInt32Array = world.visible_tile_indices()

	assert_eq(page.size(), 20 * 18)
	assert_false(page.has(-1), "no tile of the page is left undrawn")


## FruitTreeScript (engine/events/fruit_trees.asm) runs inline the way an item
## ball's does: the tree's own line, then TryResetFruitTrees, CheckFruitTree and
## the give. FRUITTREE_AZALEA_TOWN is row 20 and bears WHT_APRICORN.
const FRUIT_TREE_AZALEA: int = 20
const FRUIT_TREE_ITEM: int = 0x61


func _write_fruit_tree_cache() -> void:
	var rows: Array = []
	for index: int in RomLayout.FRUIT_TREE_COUNT:
		rows.append(FRUIT_TREE_ITEM if index == FRUIT_TREE_AZALEA - 1 else 0xAD)
	RomCache.write_json(RomCache.world_fruit_trees_path(_directory), rows)
	var items: Array = RomCache.read_json(RomCache.items_path(_directory))
	while items.size() < FRUIT_TREE_ITEM:
		items.append({"number": items.size() + 1, "name": "ITEM%d" % (items.size() + 1), "pocket": 1})
	items[FRUIT_TREE_ITEM - 1] = {
		"number": FRUIT_TREE_ITEM, "name": "WHT APRICORN", "pocket": 1,
	}
	RomCache.write_json(RomCache.items_path(_directory), items)
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	## `fruittree` is $9a in pokegold's table and one byte higher in the raw
	## Crystal stream; this fixture is a Crystal-profile cache.
	scripts["48:6280"] = [
		Gen2WorldScript.raw_opcode(0x9A), FRUIT_TREE_AZALEA, Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)


func _pick_fruit_tree(data: GameData, state: Gen2WorldState) -> Dictionary:
	var runner := Gen2WorldScriptRunner.begin(data, state, {
		"kind": &"test", "bank": 48, "script": 0x6280,
	})
	var opened: Dictionary = runner.advance()
	if StringName(opened.get("status", &"")) != &"waiting":
		return opened
	var second: Dictionary = runner.advance(true)
	if StringName(second.get("status", &"")) != &"waiting":
		return second
	return _drain_receipt(runner, runner.advance(true))


## The `specialsound` and `itemnotify` behind a successful give, which a full
## pack or a bare tree never reaches: whatever the caller was already looking at
## is returned untouched in that case.
func _drain_receipt(runner: Gen2WorldScriptRunner, result: Dictionary) -> Dictionary:
	if StringName(result.get("status", &"")) != &"waiting":
		return result
	var event: Dictionary = result.get("event", {})
	if StringName(event.get("type", &"")) != &"runtime_request":
		return result
	var sounded: Dictionary = runner.complete_runtime_request({"ok": true})
	if StringName(sounded.get("status", &"")) != &"waiting":
		return sounded
	return runner.advance(true)


func test_a_fruit_tree_gives_its_fruit_once_and_is_bare_until_the_day_turns() -> void:
	_write_fruit_tree_cache()
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	var all_trees: int = Gen2WorldState.engine_flag(Gen2WorldState.ENGINE_ALL_FRUIT_TREES)

	var picked: Dictionary = _pick_fruit_tree(data, state)
	assert_eq(picked["status"], &"complete", JSON.stringify(picked))
	assert_eq(state.item_quantity(FRUIT_TREE_ITEM), 1)
	assert_true(state.fruit_tree_picked(FRUIT_TREE_AZALEA))
	## ResetFruitTrees sets ENGINE_ALL_FRUIT_TREES behind itself, so the refill
	## happens on the first tree touched after the day turned and not again.
	assert_true(state.is_engine_flag_active(all_trees))

	var again: Dictionary = _pick_fruit_tree(data, state)
	assert_eq(again["status"], &"complete", JSON.stringify(again))
	assert_eq(state.item_quantity(FRUIT_TREE_ITEM), 1)

	assert_true(state.reset_daily_flags())
	assert_false(state.is_engine_flag_active(all_trees))
	var tomorrow: Dictionary = _pick_fruit_tree(data, state)
	assert_eq(tomorrow["status"], &"complete", JSON.stringify(tomorrow))
	assert_eq(state.item_quantity(FRUIT_TREE_ITEM), 2)
	assert_true(state.fruit_tree_picked(FRUIT_TREE_AZALEA))


func test_a_full_stack_leaves_the_fruit_on_the_tree() -> void:
	_write_fruit_tree_cache()
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new({}, {}, {FRUIT_TREE_ITEM: Gen2WorldPack.MAX_ITEM_STACK})

	var refused: Dictionary = _pick_fruit_tree(data, state)
	assert_eq(refused["status"], &"complete", JSON.stringify(refused))
	assert_eq(state.item_quantity(FRUIT_TREE_ITEM), Gen2WorldPack.MAX_ITEM_STACK)
	## The source sets the tree's flag only past `giveitem`, so a full pack
	## leaves the fruit hanging.
	assert_false(state.fruit_tree_picked(FRUIT_TREE_AZALEA))


func test_the_picked_fruit_trees_survive_a_snapshot_round_trip() -> void:
	var state := Gen2WorldState.new()
	state.apply_changes({}, {}, {"fruit_trees": {FRUIT_TREE_AZALEA: true, 1: true}})
	var restored: Gen2WorldState = Gen2WorldState.from_dict(state.to_dict())
	assert_true(restored.fruit_tree_picked(FRUIT_TREE_AZALEA))
	assert_true(restored.fruit_tree_picked(1))
	assert_false(restored.fruit_tree_picked(2))
	## A tree id outside the source table is refused rather than stored.
	var bad: Dictionary = state.apply_changes({}, {}, {"fruit_trees": {0: true}})
	assert_false(bad["ok"])
	assert_eq(bad["reason"], &"invalid_fruit_trees")


## The Bug Catching Contest, from the officer's specials to the encounter and
## the timer (engine/events/bug_contest/, engine/overworld/events.asm).
func _contest_world(cell: Vector2i = Vector2i(5, 10)) -> Gen2WorldAPI:
	var world := _world(cell)
	world.state.set_wild_encounter_cooldown(0)
	## The officer's own `setflag ENGINE_BUG_CONTEST_TIMER`, resolved for the
	## profile the way every flag past ENGINE_MOBILE_SYSTEM has to be.
	world.state.set_engine_flag(Gen2WorldState.engine_flag(
		Gen2WorldState.ENGINE_BUG_CONTEST_TIMER,
		Gen2WorldState.is_crystal_profile(world.data)
	))
	return world


func test_a_contest_replaces_the_maps_own_tables_with_contest_mons() -> void:
	var world := _contest_world()
	assert_true(world.bug_contest_active())
	var encounter: Dictionary = world.encounter_request(_seeded(), true)
	assert_eq(encounter["source"], Gen2WorldBugContest.SOURCE_CONTEST)
	assert_eq(encounter["rate"], Gen2WorldBugContest.RATE_ELSEWHERE)
	assert_ne(int(encounter["pokemon"]), 16, "not the fixture map's own slot")
	assert_eq(int(encounter["battle_type"]), Gen2WorldBugContest.BATTLE_TYPE)

	## Its own rate rather than the map's 255, so a walk in the grass draws some
	## of the time instead of every step.
	var random: RandomNumberGenerator = _seeded()
	var drawn: int = 0
	for _step: int in 200:
		world.state.set_wild_encounter_cooldown(0)
		if not world.encounter_request(random).is_empty():
			drawn += 1
	assert_between(drawn, 1, 199, "the contest rate is neither never nor always")

	## `CanEncounterWildMon` still gates it: a contest rolls nothing off grass.
	world.player_cell = Vector2i(5, 9)
	world.state.set_wild_encounter_cooldown(0)
	assert_true(world.encounter_request(_seeded()).is_empty())


func test_giving_park_balls_starts_the_timer_and_the_count() -> void:
	var world := _contest_world()
	var started: Dictionary = world.start_bug_contest()
	assert_eq(int(started["park_balls"]), Gen2WorldBugContest.BALLS)
	assert_eq(world.bug_contest_minutes_remaining(), Gen2WorldBugContest.MINUTES)
	assert_eq(world.state.bug_contest_started()["hour"], world.world_hour)
	assert_true(world.check_bug_contest_timer().is_empty(), "twenty minutes left")

	## `CheckTimeEvents` ends it on the reading that runs out, and running out of
	## balls reaches the same warp.
	world.set_world_clock(
		world.world_day, world.world_hour, world.world_minute + Gen2WorldBugContest.MINUTES
	)
	assert_eq(world.bug_contest_minutes_remaining(), 0)
	assert_false(world.check_bug_contest_timer().is_empty())


func test_the_contest_ends_when_the_park_balls_run_out() -> void:
	var world := _contest_world()
	world.start_bug_contest()
	world.state.set_park_balls(0)
	assert_false(world.check_bug_contest_timer().is_empty())


func test_ending_the_contest_clears_the_flag_and_keeps_what_was_caught() -> void:
	var world := _contest_world()
	world.start_bug_contest()
	world.state.set_contest_mon({"species": 10, "level": 12, "max_hp": 30})
	assert_true(world.end_bug_contest()["ok"])
	assert_false(world.bug_contest_active())
	assert_eq(world.state.park_balls(), 0)
	assert_eq(int(world.state.contest_mon()["species"]), 10, "judging still needs it")


func test_the_judging_reads_the_contestants_that_turned_up() -> void:
	var world := _contest_world()
	for index: int in Gen2WorldBugContest.NUM_CONTESTANTS:
		world.state.set_event_flag(
			Gen2WorldState.EVENT_BUG_CATCHING_CONTESTANT_FIRST + index,
			index >= Gen2WorldBugContest.CONTESTANTS_WITHDRAWN
		)
	assert_eq(
		world.state.withdrawn_bug_contestants().size(),
		Gen2WorldBugContest.NUM_CONTESTANTS - Gen2WorldBugContest.CONTESTANTS_WITHDRAWN
	)
	world.state.set_contest_mon({
		"species": 10, "level": 12, "max_hp": 30, "hp": 30,
		"attack": 12, "defense": 13, "speed": 14,
		"special_attack": 15, "special_defense": 16, "dvs": 0, "item": 0,
	})
	var judged: Dictionary = world.judge_bug_contest(_seeded())
	assert_eq(int(judged["score"]), 193)
	assert_true(judged["placings"].size() > 0)


## The park balls and what was caught survive a save and come back, since a
## contest can be walked out of and resumed.
func test_contest_state_round_trips_through_the_state_dictionary() -> void:
	var world := _contest_world()
	world.start_bug_contest()
	world.state.set_contest_mon({"species": 13, "level": 9, "max_hp": 22})
	world.state.set_contest_second_party_species(155)
	var restored: Gen2WorldState = Gen2WorldState.from_dict(world.state.to_dict())
	assert_eq(restored.park_balls(), Gen2WorldBugContest.BALLS)
	assert_eq(int(restored.contest_mon()["species"]), 13)
	assert_eq(restored.contest_second_party_species(), 155)
	assert_eq(restored.bug_contest_started(), world.state.bug_contest_started())


## What a visible-encounter provider is handed instead of deriving it: the cells
## a wild may stand on, grouped by the method the terrain resolves to.
func test_visible_encounter_cells_group_by_terrain_and_refuse_ice() -> void:
	var world := _world()
	var cells: Dictionary = world.visible_encounter_cells()
	var grass: PackedVector2Array = cells[Gen2WorldEncounter.METHOD_GRASS]
	var surf: PackedVector2Array = cells[Gen2WorldEncounter.METHOD_SURF]
	assert_true(grass.has(Vector2(5, 10)), "the tall grass cell")
	assert_false(grass.has(Vector2(5, 9)), "plain land is not grass")
	assert_false(grass.has(Vector2(6, 10)), "ice")
	assert_true(surf.has(Vector2(11, 11)), "the pond")
	assert_true(surf.has(Vector2(12, 11)), "and its second cell")
	assert_false(surf.has(Vector2(5, 10)), "grass is not surfable")

	## The cave branch skips the grass test, so every walkable floor is eligible.
	world.current_map.environment = Gen2WorldAPI.ENVIRONMENT_CAVE
	var cave: PackedVector2Array = world.visible_encounter_cells()[
		Gen2WorldEncounter.METHOD_GRASS
	]
	assert_true(cave.has(Vector2(5, 9)), "plain land in a cave")
	assert_false(cave.has(Vector2(6, 10)), "ice in a cave")


## `wildoff` empties the sweep, so a mod cannot stand a Pokemon on a map a script
## has switched encounters off for.
func test_visible_encounter_cells_are_empty_while_wild_encounters_are_off() -> void:
	var world := _world()
	world.state.set_wild_encounters_off(true)
	var cells: Dictionary = world.visible_encounter_cells()
	assert_eq((cells[Gen2WorldEncounter.METHOD_GRASS] as PackedVector2Array).size(), 0)
	assert_eq((cells[Gen2WorldEncounter.METHOD_SURF] as PackedVector2Array).size(), 0)


## The active table is the one a roll would read: the day's slots, and the swarm's
## in place of them while one is on.
func test_active_encounter_tables_follow_the_clock_and_the_swarm() -> void:
	var world := _world()
	world.set_object_time(12, Gen2WorldPalette.TIME_DAY)
	var tables: Dictionary = world.active_encounter_tables()
	var grass: Dictionary = tables[Gen2WorldEncounter.METHOD_GRASS]
	assert_eq(StringName(grass["source"]), Gen2WorldEncounter.SOURCE_NORMAL)
	assert_eq(int((grass["slots"] as Array)[0]["species"]), 16)
	assert_eq(int((grass["slots"] as Array)[0]["min_level"]), 5)
	assert_eq(int((grass["slots"] as Array)[0]["max_level"]), 5)
	assert_eq(
		int((tables[Gen2WorldEncounter.METHOD_SURF]["slots"] as Array)[0]["species"]), 16
	)

	world.set_swarm_map(Vector2i(1, 1))
	var swarmed: Dictionary = world.active_encounter_tables()[
		Gen2WorldEncounter.METHOD_GRASS
	]
	assert_eq(StringName(swarmed["source"]), Gen2WorldEncounter.SOURCE_SWARM)
	assert_eq(int((swarmed["slots"] as Array)[0]["species"]), 19)


## The contest replaces the map's own grass table wholesale, and its rows are a
## level RANGE where a cartridge table's slot is one level.
func test_active_encounter_tables_take_the_contest_table_while_it_runs() -> void:
	var world := _contest_world()
	world.start_bug_contest()
	var grass: Dictionary = world.active_encounter_tables()[
		Gen2WorldEncounter.METHOD_GRASS
	]
	assert_eq(StringName(grass["source"]), Gen2WorldBugContest.SOURCE_CONTEST)
	assert_eq(int((grass["slots"] as Array)[0]["species"]), 10)
	assert_eq(int((grass["slots"] as Array)[0]["min_level"]), 7)
	assert_eq(int((grass["slots"] as Array)[0]["max_level"]), 18)


## `ANIM_SEND_OUT_MON` with the shiny param, anchored to the Pokemon rather than
## to a battler and with no field behind it: the host's whole pulse. A provider
## may ask on every frame; only the first of a window is played.
func test_a_shiny_pulse_runs_the_cartridge_animation_and_is_deduplicated() -> void:
	var world := _world()
	var driver := Gen2WorldEncounters.new()
	var provider: Object = _pulse_provider()
	driver.set_providers([provider])
	driver.set_world(world, _shiny_anim_data())
	driver.advance_frame()
	assert_eq(driver.entries().size(), 1)
	assert_true(bool(driver.entries()[0]["shiny"]))
	assert_eq(driver.pulse_anchor(), Vector2(5, 10) * float(Gen2WorldAPI.CELL_PIXELS))
	assert_false(driver.pulse_sprites().is_empty(), "the animation put objects in OAM")

	## The provider asks for a pulse on every frame of the window and gets one
	## sparkle: the host owns the cadence.
	for _frame: int in 8:
		driver.advance_frame()
	assert_null(driver.pulse_anchor(), "no second sparkle inside the window")

	## An ordinary Pokemon asking for one gets nothing, since the cartridge's
	## sparkle is the only animation this seam plays.
	provider.set("dvs", 0)
	var plain := Gen2WorldEncounters.new()
	plain.set_providers([provider])
	plain.set_world(world, _shiny_anim_data())
	plain.advance_frame()
	assert_false(bool(plain.entries()[0]["shiny"]))
	assert_true(plain.pulse_sprites().is_empty())
	assert_null(plain.pulse_anchor())


## An entry the map cannot produce is dropped rather than drawn, and so is one
## that asserts a shininess of its own.
func test_a_visible_encounter_entry_is_validated_against_the_snapshot() -> void:
	var world := _world()
	var driver := Gen2WorldEncounters.new()
	var provider: Object = _pulse_provider()
	driver.set_providers([provider])
	driver.set_world(world)
	for bad: Dictionary in [
		{"cell": Vector2i(5, 9)},          # not an eligible cell
		{"species": 200},                  # not in the active table
		{"level": 40},                     # off the slot's own level
		{"id": &""},                       # no stable id
		{"shiny": true},                   # the host's answer, not the mod's
	]:
		provider.set("overrides", bad)
		driver.advance_frame()
		assert_eq(driver.entries().size(), 0, str(bad))
	provider.set("overrides", {})
	driver.advance_frame()
	assert_eq(driver.entries().size(), 1)


func _pulse_provider() -> Object:
	var script := GDScript.new()
	script.source_code = """extends RefCounted

var dvs: int = 0
var overrides: Dictionary = {}

func set_context(_context) -> void:
	pass

func advance_frame() -> void:
	pass

func encounters() -> Array:
	var entry: Dictionary = {
		"id": &"one", "cell": Vector2i(5, 10), "species": 16, "level": 5,
		"dvs": dvs, "pulse": true,
	}
	entry.merge(overrides, true)
	return [entry]

func battle_finished(_id, _result) -> void:
	pass
"""
	script.reload()
	var out: Object = script.new()
	## `CheckShininess`: the attack mask and three tens.
	out.set("dvs", Gen2Stats.pack_dvs(2, 10, 10, 10))
	return out


## A hand-built animation region whose only script sits at the shiny index, so
## the pulse has something real to run without a cartridge in hand. One object
## spawned and held, which is all the pulse is asked to prove here.
func _shiny_anim_data() -> Gen2BattleAnimData:
	var base: int = 0x4000
	var table: int = (Gen2WorldEncounters.SHINY_ANIM + 1) * 2
	var body: int = base + table
	var bytes := PackedByteArray()
	bytes.resize(table)
	bytes[Gen2WorldEncounters.SHINY_ANIM * 2] = body & 0xFF
	bytes[Gen2WorldEncounters.SHINY_ANIM * 2 + 1] = body >> 8
	# `anim_obj` row 0 at (80, 64), a yield, and `anim_ret`.
	for value: int in [0xD0, 0x00, 0x50, 0x40, 0x00, 0x01, 0xFF]:
		bytes.append(value)
	var frameset: int = base + 2
	var oam: int = base + RomLayout.BATTLE_ANIM_OAM_SET_SIZE
	return Gen2BattleAnimData.create({
		&"scripts": {
			"bank": 0x32, "address": base,
			"count": Gen2WorldEncounters.SHINY_ANIM + 1, "data": bytes,
		},
		&"objects": {
			"bank": 0x33, "address": base, "count": 1,
			"data": PackedByteArray([0x00, 0x90, 0x00, 0x00, 0x02, 0x01]),
		},
		&"framesets": {
			"bank": 0x33, "address": base, "count": 1,
			"data": PackedByteArray([frameset & 0xFF, frameset >> 8,
				0x00, 0x0F, Gen2BattleAnimObject.OAM_END]),
		},
		&"oam_sets": {
			"bank": 0x33, "address": base, "count": 1,
			"data": PackedByteArray([0x00, 0x01, oam & 0xFF, oam >> 8,
				0xF8, 0xF8, 0x00, 0x00]),
		},
	}, [{"tiles": 0, "sheet": false}, {"tiles": 4, "sheet": true}])


## The catalog over a hand-built cache: what each shape decodes to, and that a
## patch reaches the request the SCRIPT makes rather than only the row.
func test_a_catalogued_site_hands_over_what_a_mod_patched() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	## `loadwildmon KOFFING, 21` then `startbattle`, which is what a static IS,
	## and a `verbosegiveitem` behind it.
	scripts["48:6E00"] = [
		0x5D, 109, 21,
		0x5F,
		0x9E, 0x2A, 1,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var overlay := Gen2ContentOverlay.new()
	var data: GameData = GameData.open_directory(_directory)
	data.set_content_overlay(overlay)
	var catalog: Gen2WorldCatalog = data.catalog()

	var statics: Array = catalog.rows(Gen2WorldCatalog.KIND_STATIC)
	assert_eq(statics.size(), 1, JSON.stringify(statics))
	assert_eq(int(statics[0]["species"]), 109)
	assert_eq(int(statics[0]["level"]), 21)
	## The id is the byte the command sits at, not its offset in a blob: the
	## `loadwildmon` is the first command of the script at $6E00.
	assert_eq(
		int(statics[0]["id"]),
		Gen2WorldCatalog.pack_id(Gen2WorldCatalog.KIND_STATIC, 48, 0x6E00)
	)
	var items: Array = catalog.rows(Gen2WorldCatalog.KIND_ITEM)
	var given: Array = items.filter(func(row: Dictionary) -> bool:
		return row.has("address") and int(row["address"]) == 0x6E04
	)
	assert_eq(given.size(), 1, "the verbosegiveitem behind the battle")
	assert_eq(int(given[0]["item"]), 0x2A)

	overlay.patch(Gen2ContentOverlay.KIND_CHECK, &"mod", int(statics[0]["id"]), {
		"species": 25, "level": 3,
	})
	overlay.patch(Gen2ContentOverlay.KIND_CHECK, &"mod", int(given[0]["id"]), {
		"item": 1, "quantity": 4,
	})

	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(8, 6),
		Gen2WorldState.new({}, {}, {Gen2WorldInventory.ITEM_OLD_ROD: 1})
	)
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 8, "y": 6, "script": 0x6E00,
	}]
	var waiting: Array = world.dispatch_script_events(Vector2i(8, 6))
	assert_eq(waiting[0]["status"], &"waiting", JSON.stringify(waiting))
	var request: Dictionary = waiting[0]["event"]["request"]
	assert_eq(int(request["values"]["pokemon"]), 25, "the script asked for the patch")
	assert_eq(int(request["values"]["level"]), 3)

	## The battle is answered and the give runs behind it, into its own
	## acknowledge text, which is where the script is left waiting.
	var after: Array = world.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
	})
	var changed: Dictionary = {}
	for event: Dictionary in after[0]["events"]:
		if StringName(event.get("type", &"")) == &"item_changed":
			changed = event
	assert_eq(int(changed.get("item", 0)), 1, "the patched item")
	assert_eq(int(changed.get("quantity", 0)), 4, "in the patched quantity")


## The site still runs the cartridge's own script: only the number it hands over
## is the mod's. An unpatched cache is the control.
func test_an_unpatched_catalogue_hands_over_the_cartridges_own_numbers() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6E00"] = [0x5D, 109, 21, 0x5F, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var world: Gen2WorldAPI = _world(Vector2i(8, 6))
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 8, "y": 6, "script": 0x6E00,
	}]
	var waiting: Array = world.dispatch_script_events(Vector2i(8, 6))
	var request: Dictionary = waiting[0]["event"]["request"]
	assert_eq(int(request["values"]["pokemon"]), 109)
	assert_eq(int(request["values"]["level"]), 21)


## A starter's species drives the BALL as well as the gift: patching the
## `givepoke` alone would show one Pokemon and hand over another.
func test_a_patched_starter_shows_and_gives_the_same_pokemon() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	## `pokepic CYNDAQUIL` then `givepoke CYNDAQUIL, 5, BERRY`, which is the one
	## shape Elm's three balls take.
	scripts["48:6F00"] = [
		0x56, 155,
		Gen2WorldScript.GIVEPOKE, 155, 5, 0, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var overlay := Gen2ContentOverlay.new()
	var data: GameData = GameData.open_directory(_directory)
	data.set_content_overlay(overlay)
	var catalog: Gen2WorldCatalog = data.catalog()
	var starters: Array = catalog.rows(Gen2WorldCatalog.KIND_STARTER)
	assert_eq(starters.size(), 1, JSON.stringify(starters))
	assert_eq(int(starters[0]["picture_address"]), 0x6F00, "the ball's own pokepic")

	overlay.patch(Gen2ContentOverlay.KIND_CHECK, &"mod", int(starters[0]["id"]), {
		"species": 25, "level": 9,
	})
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(8, 6),
		Gen2WorldState.new({}, {}, {Gen2WorldInventory.ITEM_OLD_ROD: 1})
	)
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 8, "y": 6, "script": 0x6F00,
	}]
	var results: Array = world.dispatch_script_events(Vector2i(8, 6))
	var pictured: int = -1
	for event: Dictionary in results[0]["events"]:
		if StringName(event.get("type", &"")) == &"pokemon_picture_requested":
			pictured = int(event["pokemon"])
	assert_eq(pictured, 25, "the ball shows the patch")
	var request: Dictionary = results[0]["event"]["request"]
	assert_eq(int(request["values"]["pokemon"]), 25, "and hands the same one over")
	assert_eq(int(request["values"]["level"]), 9)
	## What the ball carries is the cartridge's and is not a species patch.
	assert_eq(int(request["values"]["item"]), 0)


## A prize's price is its affordability branch and its deduction, one linked
## transaction. Patching the Pokemon alone would sell a Mewtwo for 100 coins.
func test_a_patched_prize_checks_and_charges_the_patched_price() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	## The Game Corner vendor's own shape: `checkcoins`, a branch on HAVE_LESS,
	## then the give and the charge.
	scripts["48:6F40"] = [
		Gen2WorldScript.CHECKCOINS, 100, 0,
		Gen2WorldScript.IFEQUAL, 0, 0x60, 0x6F,
		Gen2WorldScript.GIVEPOKE, 63, 5, 0, 0,
		Gen2WorldScript.TAKECOINS, 100, 0,
		Gen2WorldScript.END,
	]
	## `.NotEnoughCoins`: sets a flag and stops, so the refusal is observable.
	scripts["48:6F60"] = [Gen2WorldScript.SETEVENT, 12, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var overlay := Gen2ContentOverlay.new()
	var data: GameData = GameData.open_directory(_directory)
	data.set_content_overlay(overlay)
	var catalog: Gen2WorldCatalog = data.catalog()
	var prizes: Array = catalog.rows(Gen2WorldCatalog.KIND_PRIZE)
	assert_eq(prizes.size(), 1, JSON.stringify(prizes))
	assert_eq(int(prizes[0]["price"]), 100)
	assert_eq(int(prizes[0]["check_address"]), 0x6F40, "the affordability branch")
	assert_eq(int(prizes[0]["take_address"]), 0x6F4C, "and the deduction")

	overlay.patch(Gen2ContentOverlay.KIND_CHECK, &"mod", int(prizes[0]["id"]), {
		"species": 150, "price": 9000,
	})

	## One coin short of the PATCHED price takes the refusal branch, though the
	## cartridge's own 100 is long since covered.
	var short: Gen2WorldAPI = _coin_world(data, 8999)
	var short_results: Array = _run_script(short, short.dispatch_script_events(Vector2i(8, 6)))
	assert_eq(_final_status(short_results), &"complete", JSON.stringify(short_results))
	assert_true(short.state.is_event_flag_active(12), "refused below the patched price")
	assert_eq(short.state.coins(), 8999, "and nothing was charged")

	var rich: Gen2WorldAPI = _coin_world(data, 9000)
	var paid: Array = rich.dispatch_script_events(Vector2i(8, 6))
	var request: Dictionary = paid[0]["event"]["request"]
	assert_eq(int(request["values"]["pokemon"]), 150, "the patched prize")
	var after: Array = rich.complete_runtime_request({"ok": true, "accepted": true})
	assert_eq(_final_status(after), &"complete", JSON.stringify(after))
	assert_false(rich.state.is_event_flag_active(12))
	assert_eq(rich.state.coins(), 0, "and the patched price was charged")


func _coin_world(data: GameData, coins: int) -> Gen2WorldAPI:
	var state := Gen2WorldState.new(
		{}, {}, {Gen2WorldInventory.ITEM_OLD_ROD: 1}, {}, coins
	)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6), state)
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 8, "y": 6, "script": 0x6F40,
	}]
	return world


## A shop sells the shelf its own site names, at that site's prices. Two shops on
## one mart list can differ without either inventing a mart.
func test_a_patched_shop_sells_its_own_shelf_at_its_own_prices() -> void:
	_write_service_cache()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	## `pokemart MARTTYPE_STANDARD, 0`.
	scripts["48:6F80"] = [0x94, 0, 0, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var overlay := Gen2ContentOverlay.new()
	var data: GameData = GameData.open_directory(_directory)
	data.set_content_overlay(overlay)
	var shops: Array = data.catalog().rows(Gen2WorldCatalog.KIND_SHOP)
	assert_eq(shops.size(), 1, JSON.stringify(shops))
	assert_eq(shops[0]["items"], [{"item": 7, "price": 0}], "the mart's own shelf")

	overlay.patch(Gen2ContentOverlay.KIND_CHECK, &"mod", int(shops[0]["id"]), {
		"items": [{"item": 3, "price": 4242}],
	})
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(8, 6),
		Gen2WorldState.new({}, {}, {Gen2WorldInventory.ITEM_OLD_ROD: 1})
	)
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 8, "y": 6, "script": 0x6F80,
	}]
	var waiting: Array = world.dispatch_script_events(Vector2i(8, 6))
	var request: Dictionary = waiting[0]["event"]["request"]
	var resolved: Dictionary = Gen2WorldHost.resolve_runtime_request(world, request)
	assert_true(bool(resolved.get("ok", false)), JSON.stringify(resolved))
	var entries: Array = Gen2WorldMartHost.entries(
		data, resolved["data"]["mart"]
	)
	assert_eq(entries.size(), 1)
	assert_eq(int(entries[0]["item"]), 3, "the patched shelf")
	assert_eq(int(entries[0]["price"]), 4242, "at the patched price")


## Both halves of a trade take the patch, and the cartridge record they came from
## is left alone for whatever other site names it.
func test_a_patched_trade_uses_both_halves_without_moving_the_record() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	## `trade 0`.
	scripts["48:6FA0"] = [0x96, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	RomCache.write_json(RomCache.world_trades_path(_directory), [{
		"trade_id": 0, "dialog": 0, "requested_species": 16, "offered_species": 19,
		"nickname": "SWAPPY", "ot_name": "MIKE", "ot_id": 1234, "dvs": 0,
		"item": 0, "gender": RomLayout.TRADE_GENDER_EITHER,
	}])
	var overlay := Gen2ContentOverlay.new()
	var data: GameData = GameData.open_directory(_directory)
	data.set_content_overlay(overlay)
	var trades: Array = data.catalog().rows(Gen2WorldCatalog.KIND_TRADE)
	assert_eq(trades.size(), 1, JSON.stringify(trades))
	assert_eq(int(trades[0]["species"]), 19)
	assert_eq(int(trades[0]["requested_species"]), 16)

	overlay.patch(Gen2ContentOverlay.KIND_CHECK, &"mod", int(trades[0]["id"]), {
		"species": 25, "requested_species": 1,
	})
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(8, 6),
		Gen2WorldState.new({}, {}, {Gen2WorldInventory.ITEM_OLD_ROD: 1})
	)
	world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 8, "y": 6, "script": 0x6FA0,
	}]
	var waiting: Array = world.dispatch_script_events(Vector2i(8, 6))
	var values: Dictionary = waiting[0]["event"]["request"]["values"]
	assert_eq(int(values["offered_species"]), 25, "what the trade hands over")
	assert_eq(int(values["requested_species"]), 1, "and what it asks for")
	assert_eq(int(values["trade_id"]), 0, "still the cartridge's own record")
	## The record itself is untouched, so a second site naming it is unaffected.
	assert_eq(int(data.world_trade(0)["offered_species"]), 19)
	assert_eq(int(data.world_trade(0)["requested_species"]), 16)


## A world is a run, so opening one installs the rules it was opened with: the
## statics that read them ([Gen2Experience], [Gen2Damage], [Gen2BattleAI]) take no
## world object, and the battles inside the walk have to be fought under the same
## set the walk is.
func test_opening_a_world_carries_and_installs_its_rules() -> void:
	var rules := Gen2Rules.new()
	rules.set_flag(&"belly_drum_boosts_below_half_hp", true)
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, Vector2i(8, 6), Gen2WorldState.new(), rules
	)
	assert_same(world.rules, rules)
	assert_true(Gen2Rules.hardware(&"belly_drum_boosts_below_half_hp"))

	# A snapshot restore is the same run continuing, so it takes the rules the
	# same way rather than adopting whatever is installed.
	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(data, world.snapshot(), rules)
	assert_same(restored.rules, rules)

	Gen2Rules.install(null)
	var plain: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6), Gen2WorldState.new())
	assert_not_null(plain.rules, "a world opened without rules plays the installed set")
	assert_false(Gen2Rules.hardware(&"belly_drum_boosts_below_half_hp"))
	Gen2Rules.install(null)


## The public read a mod plans a pickup from: every BGEVENT_ITEM on the map,
## taken or not, and never the Itemfinder's one bool over its own window.
func test_hidden_items_lists_every_record_on_the_map_with_its_flag() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6200"] = [30, 0, 3, Gen2WorldScript.END]
	scripts["48:6208"] = [31, 0, 4, Gen2WorldScript.END]
	# A third whose item byte is zero: it decodes to nothing and is dropped
	# rather than offered with a zero item.
	scripts["48:6210"] = [32, 0, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 7))
	world.current_map.events["bg_events"] = [
		{"x": 8, "y": 6, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x6200},
		{"x": 2, "y": 2, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x6208},
		{"x": 3, "y": 3, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x6210},
		{"x": 4, "y": 4, "type": Gen2WorldAPI.BGEVENT_READ, "script": 0x6200},
	]
	world.set_event_flag(31)

	var listed: Array = world.hidden_items()
	assert_eq(listed.size(), 2, JSON.stringify(listed))
	assert_eq(listed[0]["cell"], Vector2i(8, 6))
	assert_eq(int(listed[0]["item"]), 3)
	assert_eq(int(listed[0]["flag"]), 30)
	assert_false(bool(listed[0]["taken"]))
	assert_eq(listed[1]["cell"], Vector2i(2, 2))
	assert_true(bool(listed[1]["taken"]), "A set flag is listed as taken, not dropped.")
	# The Itemfinder is the same walk narrowed to its window and the untaken.
	world.player_cell = Vector2i(8, 6)
	assert_true(world.hidden_item_nearby())
	world.set_event_flag(30)
	assert_false(world.hidden_item_nearby())


## The mod names a cell; the map's own script runs through the ordinary path, so
## the box, the flag, the bag and the pack-full branch are all the host's.
func test_take_hidden_item_runs_the_maps_own_script_from_a_named_cell() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6218"] = [33, 0, 3, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 7))
	world.current_map.events["bg_events"] = [
		{"x": 2, "y": 5, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x6218},
	]
	# Nowhere near the player and not the cell being faced: naming it is the
	# whole ask, which is what makes a follower's own cell reachable.
	assert_true(world.interact().is_empty())
	assert_true(world.take_hidden_item(Vector2i(4, 4)).is_empty(), "A cell with no record.")

	var results: Array = world.take_hidden_item(Vector2i(2, 5))
	assert_eq(results.size(), 1, JSON.stringify(results))
	assert_eq(results[0]["source"]["kind"], &"hidden_item")
	assert_eq(results[0]["event"]["text"], "Found\n%s!" % _item_name(3))
	_receipt_sound(world, &"special_sound")
	assert_eq(_receipt_notify(world, 3)[0]["status"], &"complete")
	assert_eq(world.state.items().get(3, 0), 1)
	assert_true(world.event_flag_active(33))
	# And the flag it wrote closes it, the way a second A press on one is inert.
	assert_true(world.take_hidden_item(Vector2i(2, 5)).is_empty())
	assert_eq(world.state.items().get(3, 0), 1)


## A request may not cut into a script that is already running.
func test_take_hidden_item_refuses_while_a_script_is_running() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(_directory))
	scripts["48:6220"] = [34, 0, 3, Gen2WorldScript.END]
	scripts["48:6228"] = [35, 0, 4, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(_directory), scripts)
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 7))
	world.current_map.events["bg_events"] = [
		{"x": 8, "y": 6, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x6220},
		{"x": 2, "y": 5, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x6228},
	]
	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(world.interact().size(), 1, "The faced record is waiting on its box.")
	assert_true(world.take_hidden_item(Vector2i(2, 5)).is_empty())
	assert_false(world.event_flag_active(35))


## SCREEN FILL: the connection graph places whole maps around this one, in the
## same block coordinates `FillMapConnections` writes its strip in.
func test_the_connection_graph_places_the_neighbour_at_its_own_edge() -> void:
	var world: Gen2WorldAPI = _world()
	var placements: Dictionary = world.map_placements()
	assert_eq(placements.size(), 1)
	assert_true(placements.has("1:2"))
	assert_eq(
		placements["1:2"]["origin"],
		Vector2i(world.current_map.width_blocks, 0),
		"an east connection starts where this map ends",
	)
	assert_eq((placements["1:2"]["map"] as Gen2WorldMap).number, 2)


## Inside `wOverworldMapBlocks` the expansion is the cartridge's own fold, so a
## 20x18 screen sees exactly what it always saw.
func test_expanded_blocks_are_the_hardware_buffer_inside_it() -> void:
	var world: Gen2WorldAPI = _world()
	var map: Gen2WorldMap = world.current_map
	for block_y: int in range(-Gen2WorldAPI.BUFFER_BLOCKS, map.height_blocks + Gen2WorldAPI.BUFFER_BLOCKS):
		for block_x: int in range(-Gen2WorldAPI.BUFFER_BLOCKS, map.width_blocks + Gen2WorldAPI.BUFFER_BLOCKS):
			assert_eq(
				world.expanded_block_at(block_x, block_y),
				world.drawn_block_at(block_x, block_y),
				"(%d,%d)" % [block_x, block_y],
			)


## Past it, the neighbour answers with its own blocks rather than the border
## block the cartridge's buffer holds there.
func test_expanded_blocks_read_the_placed_neighbour_past_the_buffer() -> void:
	var world: Gen2WorldAPI = _world()
	var map: Gen2WorldMap = world.current_map
	var neighbour: Gen2WorldMap = world.data.world_map(1, 2)
	var past: int = map.width_blocks + Gen2WorldAPI.BUFFER_BLOCKS
	assert_lt(past, map.width_blocks + neighbour.width_blocks, "the strip stops short of the map")
	for block_x: int in range(past, map.width_blocks + neighbour.width_blocks):
		assert_eq(
			world.expanded_block_at(block_x, 2),
			Gen2WorldAPI.drawn_block_for(world.data, neighbour, block_x - map.width_blocks, 2),
			"block %d" % block_x,
		)
	assert_eq(
		world.expanded_block_at(map.width_blocks + neighbour.width_blocks + 4, 2),
		map.border_block,
		"past every placed map the border block fills the void",
	)


## A wider view is the same screen with more around it: the player keeps the
## place PLAYER_VIEW_CELL puts him in and only the surround grows.
func test_a_wider_view_keeps_the_player_where_the_hardware_put_him() -> void:
	var world: Gen2WorldAPI = _world()
	var framed: Vector2 = world.view_origin_pixels()
	assert_eq(framed, world.visible_origin_cells() * float(Gen2WorldAPI.CELL_PIXELS))
	world.view_pixels = Gen2WorldAPI.VIEW_PIXELS + Vector2i(320, 64)
	assert_eq(world.view_origin_pixels(), framed - Vector2(160, 32))
	assert_eq(
		Vector2(world.player_position_cells()) * float(Gen2WorldAPI.CELL_PIXELS)
			- world.view_origin_pixels(),
		Vector2(world.player_pixel_position()) + Vector2(160, 32),
		"the player moved by exactly half the extra surround",
	)
	assert_eq(
		world.player_view_pixel(), world.player_pixel_position() + Vector2i(160, 32),
		"and the sprite is drawn there",
	)


## The people on a connected map are drawn and nothing else: they are not in the
## object table, so no collision, script or interaction can reach them.
func test_connected_map_objects_are_drawn_but_not_in_the_object_table() -> void:
	var data: GameData = GameData.open_directory(_directory)
	data.world_map(1, 2).events["objects"] = [{
		"sprite": Gen2WorldAPI.SPRITE_CHRIS, "x": 5, "y": 4, "movement": 0,
		"x_radius": 0, "y_radius": 0, "hour_1": -1, "hour_2": -1, "palette": 0,
		"object_type": 0, "sight_range": 0, "script": 0, "event_flag": 0,
	}]
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i(8, 6))
	var neighbours: Array = world.connected_map_objects()
	assert_eq(neighbours.size(), 1)
	var entry: Dictionary = neighbours[0]
	var object: Gen2WorldObject = entry["object"]
	assert_eq(
		entry["offset"],
		Vector2i(world.current_map.width_blocks * RomLayout.MAP_BLOCK_CELL_WIDTH, 0),
	)
	assert_false(world.objects.has(object), "not one of this map's own")
	assert_null(
		world.object_at(object.cell + (entry["offset"] as Vector2i)),
		"and standing on nothing this map can walk into",
	)
