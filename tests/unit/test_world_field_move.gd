extends GutTest

## Field-move tables and the Cut, Surf and Whirlpool boundaries, against a
## synthetic cache built for this file so the shared world fixture stays
## untouched.
##
## The cache uses tileset number 1 (TILESET_JOHTO) so the real CutTreeBlockPointers
## rows apply: block $5b is a tree replaced by $3c, block $03 is grass replaced
## by $02. WhirlpoolBlockPointers names the same tileset, where block $07 is
## replaced by $36. Tileset 5 is TILESET_PLAYERS_HOUSE, which neither source
## table has an entry for.

const TILESET_CUTTABLE: int = Gen2WorldFieldMove.TILESET_JOHTO
const TILESET_NO_ENTRY: int = 5
## The escape moves' own three maps. The cache is not tagged `gold` or `silver`,
## so `TILESET_POKECENTER` is Crystal's number.
const TILESET_POKECENTER: int = Gen2WorldAPI.TILESET_POKECENTER
const ESCAPE_TOWN: int = 4
const ESCAPE_CAVE: int = 5
const ESCAPE_POKECENTER: int = 6
const ENVIRONMENT_INDOOR: int = Gen2WorldAPI.ENVIRONMENT_INDOOR
const ENVIRONMENT_CAVE: int = Gen2WorldAPI.ENVIRONMENT_CAVE
## Where the town's own spawn puts the player down, which is not its warp tile.
const SPAWN_CELL: Vector2i = Vector2i(1, 1)
## The town's two doors and the one every indoor map here has back out.
const ESCAPE_CAVE_DOOR: Vector2i = Vector2i(3, 1)
const ESCAPE_CENTRE_DOOR: Vector2i = Vector2i(5, 1)
const ESCAPE_INSIDE_DOOR: Vector2i = Vector2i(2, 2)
const BLOCK_TREE: int = 0x5B
const BLOCK_TREE_CUT: int = 0x3C
const BLOCK_GRASS: int = 0x03
const BLOCK_GRASS_CUT: int = 0x02
const BLOCK_FLOOR: int = 0x01
## Two blocks CutTreeBlockPointers has no row for, so the surf fixture cannot
## disturb any Cut case.
const BLOCK_WATER: int = 0x20
const BLOCK_WALLED_SHORE: int = 0x21
## WhirlpoolBlockPointers' only row, which CutTreeBlockPointers has no entry for.
const BLOCK_WHIRLPOOL: int = 0x07
const BLOCK_WHIRLPOOL_GONE: int = 0x36
const BLOCK_COUNT: int = 0x68

## The cut tree stands at block (1,1)'s bottom-left quadrant and the grass at
## block (2,1)'s, mirroring Ilex Forest's own block $0f layout.
const TREE_CELL: Vector2i = Vector2i(2, 3)
const TREE_BLOCK: Vector2i = Vector2i(1, 1)
const GRASS_CELL: Vector2i = Vector2i(4, 3)
const GRASS_BLOCK: Vector2i = Vector2i(2, 1)

## A shore in block (3,1): land above COLL_WATER, the New Bark Town shape the
## real-cache validator drives. The second shore in block (0,3) stands on
## COLL_DOWN_WALL, whose own edge mask is what CheckDirection reads.
const WATER_CELL: Vector2i = Vector2i(6, 3)
const SHORE_CELL: Vector2i = Vector2i(6, 2)
const WALLED_WATER_CELL: Vector2i = Vector2i(0, 7)
const WALLED_SHORE_CELL: Vector2i = Vector2i(0, 6)
## CheckWarpCollision only fires a warp from a warp tile, so the fixture's
## warp sources carry COLL_PIT. The second map needs a land one because no
## warp code is a WATER_TILE, which is why the cartridge never warps out of
## open water.
const TRANSITION_PIT_CELL: Vector2i = Vector2i(1, 1)
const COLL_WATER: int = 0x29
const COLL_PIT: int = 0x60
const COLL_DOWN_WALL: int = 0xB3

## A whirlpool in block (3,3)'s bottom-left quadrant, with the water it sits in
## directly above it, so a surfing player can reach and face it.
const WHIRLPOOL_CELL: Vector2i = Vector2i(6, 7)
const WHIRLPOOL_BLOCK: Vector2i = Vector2i(3, 3)
const WHIRLPOOL_STAND_CELL: Vector2i = Vector2i(6, 6)
const COLL_WHIRLPOOL: int = 0x24

## A two-cell waterfall column in x=2, with the water a surfing player climbs
## from below it and floor above it, so the climb ends ashore and
## CheckUpdatePlayerSprite has something to restore walking on.
const WATERFALL_STAND_CELL: Vector2i = Vector2i(2, 7)
const WATERFALL_CELLS: Array[Vector2i] = [Vector2i(2, 6), Vector2i(2, 5)]
const WATERFALL_LANDING_CELL: Vector2i = Vector2i(2, 4)

## A headbutt tree in block (0,1)'s bottom-left quadrant. COLL_HEADBUTT_TREE is
## WALL_TILE | TALK like the cut tree, so it blocks and is faced.
const BLOCK_HEADBUTT_TREE: int = 0x40
const HEADBUTT_CELL: Vector2i = Vector2i(0, 3)
const HEADBUTT_STAND_CELL: Vector2i = Vector2i(0, 2)

## constants/map_data_constants.asm: ROUTE and TOWN are the two
## `ResetFlashIfOutOfCave` treats as outdoors; DUNGEON is not one of them.
const ENVIRONMENT_TOWN: int = 1
const ENVIRONMENT_DUNGEON: int = 7

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testfieldmove", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	RomCache.write_json(RomCache.species_path(_directory), [])
	RomCache.write_json(RomCache.moves_path(_directory), [])
	RomCache.write_json(RomCache.items_path(_directory), [])
	RomCache.write_json(RomCache.types_path(_directory), [])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [])

	RomCache.write_json(RomCache.world_tilesets_path(_directory), [
		_tileset(TILESET_CUTTABLE), _tileset(TILESET_NO_ENTRY),
		_tileset(TILESET_POKECENTER),
	])
	RomCache.write_json(RomCache.world_maps_path(_directory), [
		_map(1, TILESET_CUTTABLE), _map(2, TILESET_NO_ENTRY),
		# A third map that is a dark cave, for Flash: PALETTE_DARK with the
		# DUNGEON environment, which is what keeps the light on when the player
		# walks from it into another cave room.
		_map(3, TILESET_CUTTABLE, Gen2WorldPalette.PALETTE_DARK, ENVIRONMENT_DUNGEON),
		# The three the escape moves need: an outdoor town, the cave it leads
		# into and a Pokemon Center, each warping back to the town. `.SaveDigWarp`
		# and `.SetSpawn` only fire on the way from an outdoor map into an indoor
		# one, so the town is where both walks start.
		_map(ESCAPE_TOWN, TILESET_CUTTABLE, 0, ENVIRONMENT_TOWN),
		_map(ESCAPE_CAVE, TILESET_NO_ENTRY, 0, ENVIRONMENT_CAVE),
		_map(ESCAPE_POKECENTER, TILESET_POKECENTER, 0, ENVIRONMENT_INDOOR),
	])
	# `SpawnPoints`, with the town as the one spawn this cache carries.
	RomCache.write_json(RomCache.world_spawns_path(_directory), {
		"spawns": [{
			"map_group": 1, "map_number": ESCAPE_TOWN,
			"x": SPAWN_CELL.x, "y": SPAWN_CELL.y,
		}],
		"flypoints": [],
	})

	var pixels := PackedByteArray()
	pixels.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	for index: int in pixels.size():
		pixels[index] = index % 4
	for number: int in [TILESET_CUTTABLE, TILESET_NO_ENTRY, TILESET_POKECENTER]:
		RomCache.write_indices(RomCache.world_tile_path(_directory, number), pixels)

	RomCache.write_json(RomCache.world_encounters_path(_directory), {
		# One grass table, on map 1 alone, so SWEET SCENT has somewhere with a
		# wild in it and somewhere without.
		"grass": {"1:1": {"rates": [255, 255, 255], "slots": _grass_slots()}}, "water": {}, "swarm_grass": {}, "swarm_water": {},
		"fishing": {"groups": [], "time_groups": []},
		"roaming": {"maps": [], "mons": []},
		"treemons": {
			"tree_maps": [
				{"map_group": 1, "map_number": 1, "set": TREEMON_SET},
				{"map_group": 1, "map_number": 3, "set": TREEMON_SET_CITY},
			],
			"rock_maps": [],
			"sets": _treemon_sets(),
			"asleep": {"morn": [ASLEEP_SPECIES], "day": [ASLEEP_SPECIES], "nite": []},
		},
	})
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testfieldmove",
		"sha1": "0123456789abcdef",
		"complete": true,
	})


## The fixture's only populated set, at a Crystal-legal number. Set 5 is
## TREEMON_SET_CITY on Gold and Silver, which their own GetTreeMons refuses;
## the cache here is not profile-tagged, so the refusal is checked through
## Gen2WorldTreemon directly in test_world_treemon.gd.
const TREEMON_SET: int = 1
const TREEMON_SET_CITY: int = 5
const TREEMON_SPECIES: int = 21
const TREEMON_RARE_SPECIES: int = 214
## One of the fixture's asleep species, so a tree encounter can be asserted
## both ways without depending on which row the roll lands on.
const ASLEEP_SPECIES: int = 21


## One grass table for map 1: three times of day of the source's seven slots,
## all the same species, so a roll cannot pick a different answer.
func _grass_slots() -> Array:
	var out: Array = []
	for time_of_day: int in 3:
		var slots: Array = []
		for slot: int in 7:
			slots.append({"level": 5, "species": TREEMON_SPECIES})
		out.append(slots)
	return out


func _treemon_sets() -> Array:
	var empty: Dictionary = {"common": [], "rare": []}
	var populated: Dictionary = {
		"common": [{"percent": 100, "species": TREEMON_SPECIES, "level": 10}],
		"rare": [{"percent": 100, "species": TREEMON_RARE_SPECIES, "level": 10}],
	}
	return [empty, populated, empty, empty, empty, populated]


func _tileset(number: int) -> Dictionary:
	var meta: Array = []
	for block: int in BLOCK_COUNT:
		for tile: int in 16:
			meta.append((block + tile) & 0xFF)
	var collision: Array = []
	collision.resize(BLOCK_COUNT * 4)
	for index: int in collision.size():
		collision[index] = 0
	# Quadrant order is top-left, top-right, bottom-left, bottom-right, so the
	# bottom-left cell is index 2. Only the uncut blocks carry a cuttable code.
	collision[BLOCK_TREE * 4 + 2] = 0x12   # COLL_CUT_TREE
	collision[BLOCK_GRASS * 4 + 2] = 0x18  # COLL_TALL_GRASS
	collision[BLOCK_WATER * 4 + 2] = COLL_WATER
	collision[BLOCK_WALLED_SHORE * 4 + 0] = COLL_DOWN_WALL
	collision[BLOCK_WALLED_SHORE * 4 + 2] = COLL_WATER
	# Both whirlpool blocks are water apart from the whirlpool quadrant itself, so
	# the cell the player surfs from stays water after the block is replaced.
	for quadrant: int in 4:
		collision[BLOCK_WHIRLPOOL * 4 + quadrant] = COLL_WATER
		collision[BLOCK_WHIRLPOOL_GONE * 4 + quadrant] = COLL_WATER
	collision[BLOCK_WHIRLPOOL * 4 + 2] = COLL_WHIRLPOOL
	collision[BLOCK_HEADBUTT_TREE * 4 + 2] = Gen2WorldCollision.COLL_HEADBUTT_TREE
	return {
		"number": number,
		"block_count": BLOCK_COUNT,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": collision,
	}


func _map(number: int, tileset: int, palette: int = 0, environment: int = 0) -> Dictionary:
	var blocks: Array = []
	for index: int in 16:
		blocks.append(BLOCK_FLOOR)
	blocks[TREE_BLOCK.y * 4 + TREE_BLOCK.x] = BLOCK_TREE
	blocks[GRASS_BLOCK.y * 4 + GRASS_BLOCK.x] = BLOCK_GRASS
	blocks[1 * 4 + 3] = BLOCK_WATER
	blocks[3 * 4 + 0] = BLOCK_WALLED_SHORE
	blocks[WHIRLPOOL_BLOCK.y * 4 + WHIRLPOOL_BLOCK.x] = BLOCK_WHIRLPOOL
	blocks[1 * 4 + 0] = BLOCK_HEADBUTT_TREE
	var collision: Array = []
	collision.resize(64)
	for index: int in collision.size():
		collision[index] = 0
	collision[TREE_CELL.y * 8 + TREE_CELL.x] = 0x12
	collision[GRASS_CELL.y * 8 + GRASS_CELL.x] = 0x18
	collision[WATER_CELL.y * 8 + WATER_CELL.x] = COLL_WATER
	collision[WALLED_SHORE_CELL.y * 8 + WALLED_SHORE_CELL.x] = COLL_DOWN_WALL
	collision[WALLED_WATER_CELL.y * 8 + WALLED_WATER_CELL.x] = COLL_WATER
	collision[WHIRLPOOL_CELL.y * 8 + WHIRLPOOL_CELL.x] = COLL_WHIRLPOOL
	collision[WHIRLPOOL_STAND_CELL.y * 8 + WHIRLPOOL_STAND_CELL.x] = COLL_WATER
	collision[HEADBUTT_CELL.y * 8 + HEADBUTT_CELL.x] = Gen2WorldCollision.COLL_HEADBUTT_TREE
	collision[WATERFALL_STAND_CELL.y * 8 + WATERFALL_STAND_CELL.x] = COLL_WATER
	for waterfall_cell: Vector2i in WATERFALL_CELLS:
		collision[waterfall_cell.y * 8 + waterfall_cell.x] = Gen2WorldCollision.COLL_WATERFALL
	# A warp pair between the shore and the water cell of the other map, so a map
	# transition can land the player on either kind of tile. Destinations are
	# one-based, so both point at the other map's only warp.
	var warp_cell: Vector2i = SHORE_CELL if number == 1 else WATER_CELL
	collision[warp_cell.y * 8 + warp_cell.x] = COLL_PIT if number == 1 else COLL_WATER
	collision[TRANSITION_PIT_CELL.y * 8 + TRANSITION_PIT_CELL.x] = COLL_PIT
	var warps: Array = [{
		"x": warp_cell.x, "y": warp_cell.y, "destination": 1,
		"map_group": 1, "map_number": 2 if number == 1 else 1,
	}]
	if number == 2:
		warps.append({
			"x": TRANSITION_PIT_CELL.x, "y": TRANSITION_PIT_CELL.y,
			"destination": 1, "map_group": 1, "map_number": 1,
		})
	# The town's two doors and the one door back out of each of them, so a walk
	# in records the warp it came through and a Dig walks back out of it.
	if number == ESCAPE_TOWN:
		collision[ESCAPE_CAVE_DOOR.y * 8 + ESCAPE_CAVE_DOOR.x] = COLL_PIT
		collision[ESCAPE_CENTRE_DOOR.y * 8 + ESCAPE_CENTRE_DOOR.x] = COLL_PIT
		warps = [
			{
				"x": ESCAPE_CAVE_DOOR.x, "y": ESCAPE_CAVE_DOOR.y, "destination": 1,
				"map_group": 1, "map_number": ESCAPE_CAVE,
			},
			{
				"x": ESCAPE_CENTRE_DOOR.x, "y": ESCAPE_CENTRE_DOOR.y, "destination": 1,
				"map_group": 1, "map_number": ESCAPE_POKECENTER,
			},
		]
	elif number in [ESCAPE_CAVE, ESCAPE_POKECENTER]:
		collision[ESCAPE_INSIDE_DOOR.y * 8 + ESCAPE_INSIDE_DOOR.x] = COLL_PIT
		warps = [{
			"x": ESCAPE_INSIDE_DOOR.x, "y": ESCAPE_INSIDE_DOOR.y,
			"destination": 1 if number == ESCAPE_CAVE else 2,
			"map_group": 1, "map_number": ESCAPE_TOWN,
		}]
	return {
		"group": 1,
		"number": number,
		"tileset": tileset,
		"palette": palette,
		"environment": environment,
		"width_blocks": 4,
		"height_blocks": 4,
		"blocks": blocks,
		"collision": collision,
		"collision_width": 8,
		"collision_height": 8,
		"events": {"warps": warps},
	}


func _gold_profile() -> void:
	var manifest: Dictionary = RomCache.read_json(RomCache.manifest_path(_directory))
	manifest["game_id"] = "gold"
	RomCache.write_json(RomCache.manifest_path(_directory), manifest)


## The one thing every field move is gated on besides its badge: a party member
## that knows it (`CheckPartyMove`). One non-egg slot carrying [param move] is
## what the party submenu guarantees on the real path, so the fixtures set it,
## and each move's own case drives the empty party for the refusal.
func _knowing_party(world: Gen2WorldAPI, move: int) -> void:
	world.set_party_summary(
		1, false, [1] as Array[int], [[move]], ["MON"], [false]
	)


## A world standing above the cut tree and facing it, with the Hive Badge set on
## whichever engine flag table the opened cache selects.
func _world(map_number: int = 1, badge: bool = true, knows: bool = true) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_HIVE, Gen2WorldState.is_crystal_profile(data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, map_number, TREE_CELL + Vector2i.UP, state
	)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	if knows:
		_knowing_party(world, Gen2WorldFieldMove.MOVE_CUT)
	return world


## A world standing on the shore facing the water, with the Fog Badge set on
## whichever engine flag table the opened cache selects.
func _surf_world(
	badge: bool = true, stand: Vector2i = SHORE_CELL, knows: bool = true
) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_FOG, Gen2WorldState.is_crystal_profile(data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, stand, state)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	if knows:
		_knowing_party(world, Gen2WorldFieldMove.MOVE_SURF)
	return world


## A world on the shore with the Plain Badge on whichever engine flag table the
## opened cache selects. Strength needs nothing in front of the player, so the
## start cell only has to be somewhere ordinary.
func _strength_world(badge: bool = true) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_PLAIN, Gen2WorldState.is_crystal_profile(data)
		))
	return Gen2WorldAPI.open(data, 1, 1, SHORE_CELL, state)


## A world beside the whirlpool and facing it, surfing, with the Glacier Badge on
## whichever engine flag table the opened cache selects.
func _whirlpool_world(badge: bool = true, knows: bool = true) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_GLACIER, Gen2WorldState.is_crystal_profile(data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, WHIRLPOOL_STAND_CELL, state)
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	if knows:
		_knowing_party(world, Gen2WorldFieldMove.MOVE_WHIRLPOOL)
	return world


func test_the_eight_resolved_moves_are_the_field_moves_the_submenu_offers() -> void:
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_CUT))
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_SURF))
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_STRENGTH))
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_WHIRLPOOL))
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_WATERFALL))
	assert_eq(Gen2WorldFieldMove.MOVE_CUT, 0x0F)
	assert_eq(Gen2WorldFieldMove.MOVE_SURF, 0x39)
	assert_eq(Gen2WorldFieldMove.MOVE_STRENGTH, 0x46)
	assert_eq(Gen2WorldFieldMove.MOVE_WHIRLPOOL, 0xFA)
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_FLASH))
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_HEADBUTT))
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_ROCK_SMASH))
	assert_eq(Gen2WorldFieldMove.MOVE_WATERFALL, 0x7F)
	assert_eq(Gen2WorldFieldMove.MOVE_FLASH, 0x94)
	assert_eq(Gen2WorldFieldMove.MOVE_HEADBUTT, 0x1D)
	assert_eq(Gen2WorldFieldMove.MOVE_ROCK_SMASH, 0xF9)
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_DIG))
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_TELEPORT))
	assert_eq(Gen2WorldFieldMove.MOVE_DIG, 0x5B)
	assert_eq(Gen2WorldFieldMove.MOVE_TELEPORT, 0x64)
	assert_true(Gen2WorldFieldMove.is_field_move(Gen2WorldFieldMove.MOVE_SWEET_SCENT))
	assert_eq(Gen2WorldFieldMove.MOVE_SWEET_SCENT, 0xE6)
	# MonMenuOptions rows this project does not act on yet must stay out, or the
	# submenu would offer an entry nothing answers: FLY, SOFTBOILED and
	# MILK_DRINK.
	for move: int in [0x13, 0x87, 0xD0]:
		assert_false(Gen2WorldFieldMove.is_field_move(move), "move $%02x" % move)


## .TryStrength is CheckBadge ENGINE_PLAINBADGE and nothing else, so a request
## made facing open floor with no boulder anywhere resolves. That is the whole
## difference from Cut, Surf and Whirlpool.
func test_strength_request_checks_the_plain_badge_and_nothing_else() -> void:
	var world: Gen2WorldAPI = _strength_world()
	world.player_cell = Vector2i(1, 1)
	world.player_facing = Gen2WorldSprite.FACING_UP
	var request: Dictionary = world.strength_request(25)
	assert_true(request["ok"], JSON.stringify(request))
	assert_eq(StringName(request["kind"]), &"strength_requested")
	assert_eq(int(request["move"]), Gen2WorldFieldMove.MOVE_STRENGTH)
	assert_eq(int(request["species"]), 25)
	assert_eq(world.pending_strength(), request)


func test_strength_request_refuses_without_the_plain_badge() -> void:
	var world: Gen2WorldAPI = _strength_world(false)
	var request: Dictionary = world.strength_request()
	assert_false(request["ok"])
	assert_eq(StringName(request["kind"]), &"strength_failed")
	assert_eq(StringName(request["reason"]), &"badge_required")
	assert_true(world.pending_strength().is_empty())


## The badge flag is profile split, so a Crystal-numbered write must not satisfy
## a Gold/Silver .TryStrength, the way the Cut and Surf cases check theirs.
func test_strength_request_refuses_the_other_profiles_badge_flag() -> void:
	_gold_profile()
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_PLAIN, true))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, Vector2i(1, 1), state)
	assert_eq(StringName(world.strength_request()["reason"]), &"badge_required")


## SetStrengthFlag is the only writer of BIKEFLAGS_STRENGTH_ACTIVE_F in the
## pinned sources, and Script_UsedStrength reaches it only after its text, so
## nothing is set until the commit.
func test_complete_strength_sets_the_flag_only_after_the_request() -> void:
	var world: Gen2WorldAPI = _strength_world()
	var crystal: bool = Gen2WorldState.is_crystal_profile(world.data)
	assert_false(world.strength_active())

	assert_eq(StringName(world.complete_strength()["reason"]), &"no_pending_strength")
	assert_false(world.strength_active())

	assert_true(world.strength_request(25)["ok"])
	assert_false(world.strength_active())

	var applied: Dictionary = world.complete_strength()
	assert_true(applied["ok"], JSON.stringify(applied))
	assert_eq(StringName(applied["kind"]), &"strength_applied")
	assert_eq(int(applied["species"]), 25)
	assert_true(world.strength_active())
	assert_true(world.state.is_engine_flag_active(
		Gen2WorldState.strength_active_flag(crystal)
	))
	assert_true(world.pending_strength().is_empty())


## Nothing clears the flag, so it has to outlive the map reload and the warp that
## drop every staged field-move request.
func test_strength_stays_active_across_a_map_reload_and_a_warp() -> void:
	var world: Gen2WorldAPI = _strength_world()
	assert_true(world.strength_request()["ok"])
	assert_true(world.complete_strength()["ok"])

	world.reload_current_map()
	assert_true(world.strength_active())

	world.player_cell = SHORE_CELL
	assert_true(world.try_warp()["ok"])
	assert_eq(world.map_id(), Vector2i(1, 2))
	assert_true(world.strength_active())


## A staged request dies with the loaded map beside the other three, because
## Script_StrengthFromMenu runs the moment it is queued.
func test_pending_strength_is_dropped_by_a_map_reload() -> void:
	var world: Gen2WorldAPI = _strength_world()
	assert_true(world.strength_request()["ok"])
	world.reload_current_map()
	assert_true(world.pending_strength().is_empty())
	assert_false(world.strength_active())


func test_surf_sprite_follows_get_surf_type() -> void:
	assert_eq(
		Gen2WorldFieldMove.surf_sprite(Gen2WorldFieldMove.SPECIES_PIKACHU),
		Gen2WorldSprite.SPRITE_SURFING_PIKACHU
	)
	assert_eq(Gen2WorldFieldMove.SPECIES_PIKACHU, 25)
	assert_eq(Gen2WorldSprite.SPRITE_SURF, 83)
	assert_eq(Gen2WorldSprite.SPRITE_SURFING_PIKACHU, 52)
	for species: int in [0, 1, 24, 26, 251]:
		assert_eq(Gen2WorldFieldMove.surf_sprite(species), Gen2WorldSprite.SPRITE_SURF)


func test_surf_request_checks_the_badge_before_the_state_and_the_tile() -> void:
	# .TrySurf calls CheckBadge first, so a player without the Fog Badge is told
	# about the badge whether or not the tile in front of them is surfable.
	var world: Gen2WorldAPI = _surf_world(false)
	var refused: Dictionary = world.surf_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"badge_required")
	assert_true(world.pending_surf().is_empty())

	# Facing land, and already surfing, still answer the badge first.
	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(world.surf_request()["reason"], &"badge_required")
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.surf_request()["reason"], &"badge_required")


func test_surf_request_reads_the_gold_silver_badge_flag() -> void:
	_gold_profile()
	var data: GameData = GameData.open_directory(_directory)
	assert_false(Gen2WorldState.is_crystal_profile(data))
	# Crystal's ENGINE_FOGBADGE (30) must not answer on a Gold cache, whose
	# shorter engine flag table puts the same badge at 29.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_FOGBADGE)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, SHORE_CELL, state)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	_knowing_party(world, Gen2WorldFieldMove.MOVE_SURF)
	assert_eq(world.surf_request()["reason"], &"badge_required")

	state.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_FOG, false))
	assert_true(bool(world.surf_request().get("ok", false)))


func test_surf_request_refuses_a_tile_that_is_not_water() -> void:
	var world: Gen2WorldAPI = _surf_world()
	world.player_facing = Gen2WorldSprite.FACING_UP
	var refused: Dictionary = world.surf_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"cannot_surf")


func test_surf_request_refuses_when_the_standing_tile_walls_the_direction() -> void:
	# CheckDirection ANDs wTilePermissions against the facing bit, so a
	# COLL_DOWN_WALL shore refuses even with water directly below it.
	var world: Gen2WorldAPI = _surf_world(true, WALLED_SHORE_CELL)
	assert_eq(
		world.collision_permission_at(WALLED_WATER_CELL), Gen2WorldCollision.WATER_TILE
	)
	assert_eq(
		world.tile_permissions_at(WALLED_SHORE_CELL) & Gen2WorldCollision.FACE_DOWN,
		Gen2WorldCollision.FACE_DOWN
	)
	assert_eq(world.surf_request()["reason"], &"cannot_surf")


func test_surf_request_stages_without_moving_the_player() -> void:
	var world: Gen2WorldAPI = _surf_world()
	var staged: Dictionary = world.surf_request()
	assert_true(bool(staged.get("ok", false)), JSON.stringify(staged))
	assert_eq(staged["kind"], &"surf_requested")
	assert_eq(staged["cell"], WATER_CELL)
	assert_eq(staged["direction"], Vector2i.DOWN)
	assert_eq(int(staged["sprite"]), Gen2WorldSprite.SPRITE_SURF)
	# UsedSurfScript shows its text before writevar VAR_MOVEMENT, so nothing has
	# changed yet.
	assert_eq(world.player_cell, SHORE_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_PLAYER)
	assert_eq(world.pending_surf()["cell"], WATER_CELL)


func test_complete_surf_enters_the_water_without_spending_a_step() -> void:
	var world: Gen2WorldAPI = _surf_world()
	world.state.set_repel_steps(20)
	assert_true(bool(world.surf_request().get("ok", false)))
	var applied: Dictionary = world.complete_surf()
	assert_true(bool(applied.get("ok", false)), JSON.stringify(applied))
	assert_eq(applied["kind"], &"surf_applied")
	assert_eq(world.player_cell, WATER_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURF)
	# SurfStartStep is an applymovement, not player input: no repel step is
	# consumed and no encounter is rolled.
	assert_eq(world.state.repel_steps(), 20)
	assert_true(world.player_step_in_progress())
	assert_true(world.pending_surf().is_empty())


func test_complete_surf_carries_the_pikachu_variant() -> void:
	var world: Gen2WorldAPI = _surf_world()
	assert_true(bool(
		world.surf_request(Gen2WorldFieldMove.SPECIES_PIKACHU).get("ok", false)
	))
	assert_eq(
		int(world.complete_surf()["sprite"]), Gen2WorldSprite.SPRITE_SURFING_PIKACHU
	)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURFING_PIKACHU)


func test_surf_request_refuses_while_staged_or_already_surfing() -> void:
	var world: Gen2WorldAPI = _surf_world()
	assert_true(bool(world.surf_request().get("ok", false)))
	assert_eq(world.surf_request()["reason"], &"surf_in_progress")
	assert_true(bool(world.complete_surf().get("ok", false)))
	assert_eq(world.surf_request()["reason"], &"already_surfing")


func test_complete_surf_without_a_request_fails() -> void:
	var world: Gen2WorldAPI = _surf_world()
	var applied: Dictionary = world.complete_surf()
	assert_false(bool(applied.get("ok", false)))
	assert_eq(applied["reason"], &"no_pending_surf")
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)


func test_a_map_transition_rederives_the_player_state_from_the_landing_cell() -> void:
	# CheckUpdatePlayerSprite runs on every warp and connection: .CheckSurfing
	# starts surfing on water, .ResetSurfingOrBikingState restores walking
	# anywhere else. Without it a warp taken from water strands the player on
	# land in a mode where only water is a legal step.
	var world: Gen2WorldAPI = _surf_world()
	var onto_water: Dictionary = world.try_warp()
	assert_true(bool(onto_water.get("ok", false)), JSON.stringify(onto_water))
	assert_eq(world.player_cell, WATER_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURF)

	world.player_cell = TRANSITION_PIT_CELL
	var onto_land: Dictionary = world.try_warp()
	assert_true(bool(onto_land.get("ok", false)), JSON.stringify(onto_land))
	assert_eq(world.player_cell, SHORE_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_PLAYER)


func test_a_map_transition_keeps_the_pikachu_surf_variant() -> void:
	# .CheckSurfing keeps an existing surf state rather than overwriting it, so
	# the Pikachu sprite survives a warp between two water cells.
	var world: Gen2WorldAPI = _surf_world()
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	world.player_sprite_number = Gen2WorldSprite.SPRITE_SURFING_PIKACHU
	assert_true(bool(world.try_warp().get("ok", false)))
	assert_eq(world.player_cell, WATER_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURFING_PIKACHU)


func test_a_map_reload_drops_a_staged_surf() -> void:
	var world: Gen2WorldAPI = _surf_world()
	assert_true(bool(world.surf_request().get("ok", false)))
	assert_true(bool(world.reload_current_map().get("ok", false)))
	assert_true(world.pending_surf().is_empty())


func test_cuttable_carries_the_six_check_cut_collision_codes() -> void:
	for code: int in [0x12, 0x1A, 0x10, 0x18, 0x14, 0x1C]:
		assert_true(Gen2WorldFieldMove.cuttable(code), "code $%02x" % code)
	# Neighbours of the cuttable runs, and the codes the other field moves own.
	for code: int in [0x00, 0x11, 0x13, 0x15, 0x19, 0x1B, 0x1D, 0x24, 0x33, 0x07]:
		assert_false(Gen2WorldFieldMove.cuttable(code), "code $%02x" % code)


func test_cut_tree_block_table_matches_the_pinned_rows() -> void:
	var rows: Array = [
		# tileset, facing block, replacement, animation
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x03, 0x02, 1],
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x5B, 0x3C, 0],
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x5F, 0x3D, 0],
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x63, 0x3F, 0],
		[Gen2WorldFieldMove.TILESET_JOHTO, 0x67, 0x3E, 0],
		[Gen2WorldFieldMove.TILESET_JOHTO_MODERN, 0x03, 0x02, 1],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x0B, 0x0A, 1],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x32, 0x6D, 0],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x33, 0x6C, 0],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x34, 0x6F, 0],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x35, 0x4C, 0],
		[Gen2WorldFieldMove.TILESET_KANTO, 0x60, 0x6E, 0],
	]
	for row: Array in rows:
		for crystal: bool in [true, false]:
			var result: Dictionary = Gen2WorldFieldMove.cut_replacement(row[0], row[1], crystal)
			assert_true(bool(result.get("ok", false)), "tileset %d block $%02x" % [row[0], row[1]])
			assert_eq(int(result["block"]), int(row[2]))
			assert_eq(int(result["animation"]), int(row[3]))


func test_park_and_forest_tileset_numbers_are_profile_split() -> void:
	var park: Array = [[0x13, 0x03, 1], [0x03, 0x04, 1]]
	var forest: Array = [[0x0F, 0x17, 0]]
	var cases: Array = [
		[Gen2WorldFieldMove.TILESET_PARK_CRYSTAL, true, park],
		[Gen2WorldFieldMove.TILESET_PARK_GOLD_SILVER, false, park],
		[Gen2WorldFieldMove.TILESET_FOREST_CRYSTAL, true, forest],
		[Gen2WorldFieldMove.TILESET_FOREST_GOLD_SILVER, false, forest],
	]
	for case: Array in cases:
		for row: Array in case[2] as Array:
			var hit: Dictionary = Gen2WorldFieldMove.cut_replacement(case[0], row[0], case[1])
			assert_true(bool(hit.get("ok", false)), "tileset %d block $%02x" % [case[0], row[0]])
			assert_eq(int(hit["block"]), int(row[1]))
			assert_eq(int(hit["animation"]), int(row[2]))
			# The other profile numbers the same tileset differently, so its
			# number must not resolve there.
			var miss: Dictionary = Gen2WorldFieldMove.cut_replacement(
				case[0], row[0], not bool(case[1])
			)
			assert_false(bool(miss.get("ok", false)), "tileset %d on the other profile" % case[0])


func test_cut_replacement_refuses_an_absent_tileset_or_block() -> void:
	assert_false(bool(Gen2WorldFieldMove.cut_replacement(
		TILESET_NO_ENTRY, BLOCK_TREE, true
	).get("ok", false)))
	assert_false(bool(Gen2WorldFieldMove.cut_replacement(
		Gen2WorldFieldMove.TILESET_JOHTO, 0x00, true
	).get("ok", false)))


func test_cut_request_checks_the_badge_before_the_tile() -> void:
	# .CheckAble calls CheckBadge first, so a player facing a real tree without
	# the Hive Badge is told about the badge, not about the tree.
	var world: Gen2WorldAPI = _world(1, false)
	var refused: Dictionary = world.cut_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"badge_required")
	assert_true(world.pending_cut().is_empty())


func test_cut_request_reads_the_gold_silver_badge_flag() -> void:
	_gold_profile()
	var data: GameData = GameData.open_directory(_directory)
	assert_false(Gen2WorldState.is_crystal_profile(data))
	# Crystal's ENGINE_HIVEBADGE (28) must not answer on a Gold cache, whose
	# shorter engine flag table puts the same badge at 27.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_HIVEBADGE)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, 1, TREE_CELL + Vector2i.UP, state
	)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	_knowing_party(world, Gen2WorldFieldMove.MOVE_CUT)
	assert_eq(world.cut_request()["reason"], &"badge_required")

	state.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_HIVE, false))
	assert_true(bool(world.cut_request().get("ok", false)))


## CheckPartyMove, which every one of the four gates on. TryCutOW,
## TryWhirlpoolOW and TryWaterfallOW ask it before their badge; TrySurfOW asks it
## after. An empty party answers the same way a party without the move does,
## because neither can reach the move on any source path.
func test_each_field_move_refuses_a_party_that_does_not_know_it() -> void:
	assert_eq(_world(1, true, false).cut_request()["reason"], &"move_not_known")
	assert_eq(
		_surf_world(true, SHORE_CELL, false).surf_request()["reason"], &"move_not_known"
	)
	assert_eq(_whirlpool_world(true, false).whirlpool_request()["reason"], &"move_not_known")
	assert_eq(_waterfall_world(true, false).waterfall_request()["reason"], &"move_not_known")


## The refusal order the overworld prompts use: Cut, Whirlpool and Waterfall
## report the missing move even when the badge is missing too, and Surf reports
## the missing badge first.
func test_the_party_move_check_runs_before_the_badge_except_for_surf() -> void:
	assert_eq(_world(1, false, false).cut_request()["reason"], &"move_not_known")
	assert_eq(_whirlpool_world(false, false).whirlpool_request()["reason"], &"move_not_known")
	assert_eq(_waterfall_world(false, false).waterfall_request()["reason"], &"move_not_known")
	assert_eq(
		_surf_world(false, SHORE_CELL, false).surf_request()["reason"], &"badge_required"
	)


## An egg carries the moves it will hatch with, and CheckPartyMove skips it.
func test_an_egg_that_would_hatch_with_the_move_does_not_answer_for_it() -> void:
	var world: Gen2WorldAPI = _world(1, true, false)
	world.set_party_summary(
		1, false, [1] as Array[int], [[Gen2WorldFieldMove.MOVE_CUT]], ["EGG"], [true]
	)
	assert_eq(world.cut_request()["reason"], &"move_not_known")
	assert_eq(world.party_slot_with_move(Gen2WorldFieldMove.MOVE_CUT), -1)

	world.set_party_summary(
		2, false, [1, 2] as Array[int],
		[[Gen2WorldFieldMove.MOVE_CUT], [Gen2WorldFieldMove.MOVE_CUT]],
		["EGG", "MON"], [true, false]
	)
	assert_eq(world.party_slot_with_move(Gen2WorldFieldMove.MOVE_CUT), 1)
	assert_true(bool(world.cut_request().get("ok", false)))


func test_cut_request_refuses_a_tile_that_is_not_cuttable() -> void:
	var world: Gen2WorldAPI = _world()
	world.player_cell = Vector2i(6, 6)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var refused: Dictionary = world.cut_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"nothing_to_cut")


func test_cut_request_refuses_a_tileset_without_a_block_list() -> void:
	# Map 2 carries the identical tree cell on TILESET_PLAYERS_HOUSE, which
	# CutTreeBlockPointers has no entry for.
	var world: Gen2WorldAPI = _world(2)
	assert_true(Gen2WorldFieldMove.cuttable(world.collision_code_at(TREE_CELL)))
	assert_eq(world.cut_request()["reason"], &"nothing_to_cut")


func test_cut_request_stages_without_changing_the_map() -> void:
	var world: Gen2WorldAPI = _world()
	assert_false(world.can_walk_to(TREE_CELL))
	var staged: Dictionary = world.cut_request()
	assert_true(bool(staged.get("ok", false)), JSON.stringify(staged))
	assert_eq(staged["block_cell"], TREE_BLOCK)
	assert_eq(int(staged["block"]), BLOCK_TREE_CUT)
	assert_eq(int(staged["animation"]), Gen2WorldFieldMove.ANIMATION_TREE)
	# Script_Cut writes the block only after its text, so nothing has moved yet.
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)
	assert_false(world.can_walk_to(TREE_CELL))
	assert_eq(world.pending_cut()["block"], BLOCK_TREE_CUT)


func test_complete_cut_replaces_the_block_and_opens_the_cell() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(bool(world.cut_request().get("ok", false)))
	var applied: Dictionary = world.complete_cut()
	assert_true(bool(applied.get("ok", false)), JSON.stringify(applied))
	assert_eq(applied["kind"], &"cut_applied")
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE_CUT)
	assert_eq(world.collision_code_at(TREE_CELL), 0x00)
	assert_true(world.can_walk_to(TREE_CELL))
	assert_true(world.pending_cut().is_empty())


func test_cutting_grass_keeps_the_cell_walkable_and_swaps_the_block() -> void:
	var world: Gen2WorldAPI = _world()
	world.player_cell = GRASS_CELL + Vector2i.UP
	# The four grass codes are LAND_TILE, so this cell was always walkable; only
	# the block changes.
	assert_true(world.can_walk_to(GRASS_CELL))
	var staged: Dictionary = world.cut_request()
	assert_true(bool(staged.get("ok", false)), JSON.stringify(staged))
	assert_eq(int(staged["animation"]), Gen2WorldFieldMove.ANIMATION_GRASS)
	assert_true(bool(world.complete_cut().get("ok", false)))
	assert_eq(world.block_at(GRASS_BLOCK.x, GRASS_BLOCK.y), BLOCK_GRASS_CUT)
	assert_true(world.can_walk_to(GRASS_CELL))


func test_a_second_request_refuses_while_one_is_staged() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(bool(world.cut_request().get("ok", false)))
	assert_eq(world.cut_request()["reason"], &"cut_in_progress")


func test_complete_cut_without_a_request_fails() -> void:
	var world: Gen2WorldAPI = _world()
	var applied: Dictionary = world.complete_cut()
	assert_false(bool(applied.get("ok", false)))
	assert_eq(applied["reason"], &"no_pending_cut")


func test_a_map_reload_regrows_the_tree_and_drops_a_staged_cut() -> void:
	var world: Gen2WorldAPI = _world()
	assert_true(bool(world.cut_request().get("ok", false)))
	assert_true(bool(world.complete_cut().get("ok", false)))
	assert_true(world.can_walk_to(TREE_CELL))
	# CutDownTreeOrGrass only writes wOverworldMapBlocks, and a map load re-reads
	# the block data from ROM, so the tree is back on the next visit.
	assert_true(bool(world.reload_current_map().get("ok", false)))
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)
	assert_false(world.can_walk_to(TREE_CELL))

	assert_true(bool(world.cut_request().get("ok", false)))
	world.reload_current_map()
	assert_true(world.pending_cut().is_empty())


func test_whirlpool_tile_carries_both_check_whirlpool_tile_codes() -> void:
	for code: int in [0x24, 0x2C]:
		assert_true(Gen2WorldFieldMove.whirlpool_tile(code), "code $%02x" % code)
	# Neighbours of both codes, and the codes Cut and the waterfall own.
	for code: int in [0x00, 0x20, 0x23, 0x25, 0x2B, 0x2D, 0x12, 0x33]:
		assert_false(Gen2WorldFieldMove.whirlpool_tile(code), "code $%02x" % code)


func test_whirlpool_block_table_matches_the_pinned_row() -> void:
	var hit: Dictionary = Gen2WorldFieldMove.whirlpool_replacement(
		Gen2WorldFieldMove.TILESET_JOHTO, BLOCK_WHIRLPOOL
	)
	assert_true(bool(hit.get("ok", false)))
	assert_eq(int(hit["block"]), BLOCK_WHIRLPOOL_GONE)
	assert_eq(int(hit["animation"]), Gen2WorldFieldMove.ANIMATION_TREE)
	# WhirlpoolBlockPointers names TILESET_JOHTO alone, and nothing else in it.
	assert_false(bool(Gen2WorldFieldMove.whirlpool_replacement(
		Gen2WorldFieldMove.TILESET_JOHTO, 0x03
	).get("ok", false)))
	for tileset: int in [
		Gen2WorldFieldMove.TILESET_JOHTO_MODERN, Gen2WorldFieldMove.TILESET_KANTO,
		Gen2WorldFieldMove.TILESET_FOREST_CRYSTAL, TILESET_NO_ENTRY,
	]:
		assert_false(bool(Gen2WorldFieldMove.whirlpool_replacement(
			tileset, BLOCK_WHIRLPOOL
		).get("ok", false)), "tileset %d" % tileset)


func test_whirlpool_request_checks_the_badge_before_the_tile() -> void:
	# .TryWhirlpool calls CheckBadge first, the same order .CheckAble has.
	var world: Gen2WorldAPI = _whirlpool_world(false)
	var refused: Dictionary = world.whirlpool_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"badge_required")
	assert_true(world.pending_whirlpool().is_empty())

	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(world.whirlpool_request()["reason"], &"badge_required")


func test_whirlpool_request_reads_the_gold_silver_badge_flag() -> void:
	_gold_profile()
	var data: GameData = GameData.open_directory(_directory)
	assert_false(Gen2WorldState.is_crystal_profile(data))
	# Crystal's ENGINE_GLACIERBADGE (33) must not answer on a Gold cache, whose
	# shorter engine flag table puts the same badge at 32.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_GLACIERBADGE)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, WHIRLPOOL_STAND_CELL, state)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	_knowing_party(world, Gen2WorldFieldMove.MOVE_WHIRLPOOL)
	assert_eq(world.whirlpool_request()["reason"], &"badge_required")

	state.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_GLACIER, false))
	assert_true(bool(world.whirlpool_request().get("ok", false)))


func test_whirlpool_request_refuses_a_tile_that_is_not_a_whirlpool() -> void:
	var world: Gen2WorldAPI = _whirlpool_world()
	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(world.whirlpool_request()["reason"], &"nothing_to_whirlpool")


func test_whirlpool_request_refuses_a_tileset_without_a_block_list() -> void:
	# Map 2 carries the identical whirlpool cell on TILESET_PLAYERS_HOUSE, which
	# WhirlpoolBlockPointers has no entry for.
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.badge_flag(
		Gen2WorldFieldMove.BADGE_GLACIER, Gen2WorldState.is_crystal_profile(data)
	))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 2, WHIRLPOOL_STAND_CELL, state)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	_knowing_party(world, Gen2WorldFieldMove.MOVE_WHIRLPOOL)
	assert_true(Gen2WorldFieldMove.whirlpool_tile(world.collision_code_at(WHIRLPOOL_CELL)))
	assert_eq(world.whirlpool_request()["reason"], &"nothing_to_whirlpool")


func test_whirlpool_request_resolves_from_land_too() -> void:
	# .TryWhirlpool checks no player state at all, so walking is not a refusal.
	var world: Gen2WorldAPI = _whirlpool_world()
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_WALK)
	assert_true(bool(world.whirlpool_request().get("ok", false)))


func test_whirlpool_request_stages_without_changing_the_map() -> void:
	var world: Gen2WorldAPI = _whirlpool_world()
	var staged: Dictionary = world.whirlpool_request()
	assert_true(bool(staged.get("ok", false)), JSON.stringify(staged))
	assert_eq(staged["kind"], &"whirlpool_requested")
	assert_eq(staged["cell"], WHIRLPOOL_CELL)
	assert_eq(staged["block_cell"], WHIRLPOOL_BLOCK)
	assert_eq(int(staged["block"]), BLOCK_WHIRLPOOL_GONE)
	# Script_UsedWhirlpool reaches DisappearWhirlpool only after UseWhirlpoolText.
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL)
	assert_eq(world.collision_code_at(WHIRLPOOL_CELL), COLL_WHIRLPOOL)
	assert_eq(world.pending_whirlpool()["block"], BLOCK_WHIRLPOOL_GONE)


func test_complete_whirlpool_replaces_the_block_and_clears_the_code() -> void:
	var world: Gen2WorldAPI = _whirlpool_world()
	assert_true(bool(world.whirlpool_request().get("ok", false)))
	var applied: Dictionary = world.complete_whirlpool()
	assert_true(bool(applied.get("ok", false)), JSON.stringify(applied))
	assert_eq(applied["kind"], &"whirlpool_applied")
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL_GONE)
	assert_ne(world.collision_code_at(WHIRLPOOL_CELL), COLL_WHIRLPOOL)
	assert_true(world.pending_whirlpool().is_empty())


func test_a_second_whirlpool_request_refuses_while_one_is_staged() -> void:
	var world: Gen2WorldAPI = _whirlpool_world()
	assert_true(bool(world.whirlpool_request().get("ok", false)))
	assert_eq(world.whirlpool_request()["reason"], &"whirlpool_in_progress")


func test_complete_whirlpool_without_a_request_fails() -> void:
	var world: Gen2WorldAPI = _whirlpool_world()
	var applied: Dictionary = world.complete_whirlpool()
	assert_false(bool(applied.get("ok", false)))
	assert_eq(applied["reason"], &"no_pending_whirlpool")


func test_a_map_reload_restores_the_whirlpool_and_drops_a_staged_request() -> void:
	var world: Gen2WorldAPI = _whirlpool_world()
	assert_true(bool(world.whirlpool_request().get("ok", false)))
	assert_true(bool(world.complete_whirlpool().get("ok", false)))
	assert_true(bool(world.reload_current_map().get("ok", false)))
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL)
	assert_eq(world.collision_code_at(WHIRLPOOL_CELL), COLL_WHIRLPOOL)

	assert_true(bool(world.whirlpool_request().get("ok", false)))
	world.reload_current_map()
	assert_true(world.pending_whirlpool().is_empty())


func test_the_whirlpool_traps_a_player_until_it_is_removed() -> void:
	# .CheckTile answers before .TrySurf, so the cell is enterable but not
	# leavable: Script_ForcedMovement only spins the player around.
	var world: Gen2WorldAPI = _whirlpool_world()
	assert_true(bool(world.move_result(Vector2i.DOWN).get("ok", false)))
	assert_eq(world.player_cell, WHIRLPOOL_CELL)

	var spun: Dictionary = world.move_result(Vector2i.DOWN)
	assert_eq(spun["kind"], &"forced_turn")
	assert_eq(world.player_cell, WHIRLPOOL_CELL)
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_UP)
	assert_eq(world.move_result(Vector2i.UP)["kind"], &"forced_turn")
	assert_eq(world.player_facing, Gen2WorldSprite.FACING_DOWN)
	assert_eq(world.player_cell, WHIRLPOOL_CELL)

	# Removing it from the neighbouring cell frees it.
	world.player_cell = WHIRLPOOL_STAND_CELL
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	assert_true(bool(world.whirlpool_request().get("ok", false)))
	assert_true(bool(world.complete_whirlpool().get("ok", false)))
	assert_true(bool(world.move_result(Vector2i.DOWN).get("ok", false)))
	assert_eq(world.player_cell, WHIRLPOOL_CELL)
	assert_eq(world.forced_movement()["kind"], &"none")


## A world in the water below the waterfall column, facing up, with the Rising
## Badge on whichever engine flag table the opened cache selects.
func _waterfall_world(badge: bool = true, knows: bool = true) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_RISING, Gen2WorldState.is_crystal_profile(data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, WATERFALL_STAND_CELL, state)
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	world.player_facing = Gen2WorldSprite.FACING_UP
	if knows:
		_knowing_party(world, Gen2WorldFieldMove.MOVE_WATERFALL)
	return world


func test_waterfall_tile_carries_both_check_waterfall_tile_codes() -> void:
	for code: int in [Gen2WorldCollision.COLL_WATERFALL, Gen2WorldCollision.COLL_CURRENT_DOWN]:
		assert_true(Gen2WorldFieldMove.waterfall_tile(code), "code $%02x" % code)
	for code: int in [0x00, COLL_WATER, COLL_WHIRLPOOL, 0x32]:
		assert_false(Gen2WorldFieldMove.waterfall_tile(code), "code $%02x" % code)


func test_waterfall_request_checks_the_badge_before_the_tile() -> void:
	var world: Gen2WorldAPI = _waterfall_world(false)
	var refused: Dictionary = world.waterfall_request()
	assert_false(bool(refused.get("ok", true)))
	assert_eq(refused["reason"], &"badge_required")
	assert_true(world.pending_waterfall().is_empty())


func test_waterfall_request_reads_the_gold_silver_badge_flag() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	var state := Gen2WorldState.new()
	# The other profile's number is not this profile's badge.
	state.set_engine_flag(Gen2WorldState.badge_flag(
		Gen2WorldFieldMove.BADGE_RISING, not crystal
	))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 1, WATERFALL_STAND_CELL, state)
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)
	world.player_facing = Gen2WorldSprite.FACING_UP
	_knowing_party(world, Gen2WorldFieldMove.MOVE_WATERFALL)
	assert_eq(world.waterfall_request()["reason"], &"badge_required")


## CheckMapCanWaterfall tests the facing before the tile, and only FACE_UP passes.
func test_waterfall_request_refuses_every_facing_but_up() -> void:
	for facing: int in [
		Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_LEFT,
		Gen2WorldSprite.FACING_RIGHT,
	]:
		var world: Gen2WorldAPI = _waterfall_world()
		world.player_facing = facing
		assert_eq(world.waterfall_request()["reason"], &"wrong_facing", "facing %d" % facing)


func test_waterfall_request_refuses_a_tile_that_is_not_a_waterfall() -> void:
	var world: Gen2WorldAPI = _waterfall_world()
	world.player_cell = WHIRLPOOL_STAND_CELL
	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(world.waterfall_request()["reason"], &"nothing_to_climb")


## .TryWaterfall reads no player state, so walking is not a refusal, the same
## way .TryWhirlpool has it.
func test_waterfall_request_resolves_from_land_too() -> void:
	var world: Gen2WorldAPI = _waterfall_world()
	world.set_movement_mode(Gen2WorldAPI.MOVEMENT_WALK)
	assert_true(bool(world.waterfall_request().get("ok", false)))


func test_waterfall_request_stages_without_moving_the_player() -> void:
	var world: Gen2WorldAPI = _waterfall_world()
	var staged: Dictionary = world.waterfall_request()
	assert_true(bool(staged.get("ok", false)), JSON.stringify(staged))
	assert_eq(staged["kind"], &"waterfall_requested")
	assert_eq(staged["cell"], WATERFALL_CELLS[0])
	# Script_UsedWaterfall steps only after _UseWaterfallText's waitbutton.
	assert_eq(world.player_cell, WATERFALL_STAND_CELL)
	assert_eq(world.pending_waterfall()["cell"], WATERFALL_CELLS[0])


## .CheckContinueWaterfall repeats the step while the cell stood on is still a
## waterfall, so a two-cell column is one command and three steps.
func test_complete_waterfall_climbs_the_whole_column_in_one_command() -> void:
	var world: Gen2WorldAPI = _waterfall_world()
	assert_true(bool(world.waterfall_request().get("ok", false)))
	var applied: Dictionary = world.complete_waterfall()
	assert_true(bool(applied.get("ok", false)), JSON.stringify(applied))
	assert_eq(applied["kind"], &"waterfall_applied")
	assert_eq(applied["cell"], WATERFALL_LANDING_CELL)
	assert_eq(int(applied["steps"]), WATERFALL_CELLS.size() + 1)
	assert_eq(world.player_cell, WATERFALL_LANDING_CELL)
	assert_true(world.pending_waterfall().is_empty())


## The landing re-derives the player state the way a warp does, so a climb that
## ends on land puts the surfer back on foot.
func test_complete_waterfall_restores_walking_when_it_lands_ashore() -> void:
	var world: Gen2WorldAPI = _waterfall_world()
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_true(bool(world.waterfall_request().get("ok", false)))
	var applied: Dictionary = world.complete_waterfall()
	assert_eq(applied["movement_mode"], Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_PLAYER)


func test_complete_waterfall_without_a_request_refuses() -> void:
	var world: Gen2WorldAPI = _waterfall_world()
	var refused: Dictionary = world.complete_waterfall()
	assert_false(bool(refused.get("ok", true)))
	assert_eq(refused["reason"], &"no_pending_waterfall")


## The request names a cell on the loaded map, so a map change drops it the way
## the other four are dropped.
func test_a_map_change_clears_a_pending_waterfall() -> void:
	var world: Gen2WorldAPI = _waterfall_world()
	assert_true(bool(world.waterfall_request().get("ok", false)))
	# Map 1's only warp is the shore pit; TRANSITION_PIT_CELL belongs to map 2.
	world.player_cell = SHORE_CELL
	assert_true(bool(world.try_warp().get("ok", false)))
	assert_true(world.pending_waterfall().is_empty())


## Flash. `.CheckUseFlash` checks the badge and then the map's own palette byte,
## and nothing else: it is the one field move that never looks at a tile.
func _flash_world(with_badge: bool = true, map_number: int = 3) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var state := Gen2WorldState.new()
	if with_badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_ZEPHYR, Gen2WorldState.is_crystal_profile(data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, map_number, Vector2i(1, 1), state)
	_knowing_party(world, Gen2WorldFieldMove.MOVE_FLASH)
	return world


func test_flash_request_needs_the_zephyr_badge_before_it_looks_at_the_map() -> void:
	var world: Gen2WorldAPI = _flash_world(false)

	var refused: Dictionary = world.flash_request()

	assert_false(bool(refused.get("ok", true)))
	assert_eq(refused["reason"], &"badge_required", "the badge, even standing in the dark")
	assert_true(world.pending_flash().is_empty())


func test_flash_request_reads_the_gold_silver_badge_flag() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.badge_flag(
		Gen2WorldFieldMove.BADGE_ZEPHYR, not crystal
	))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 1, 3, Vector2i(1, 1), state)
	_knowing_party(world, Gen2WorldFieldMove.MOVE_FLASH)

	assert_eq(world.flash_request()["reason"], &"badge_required")


## A map that is not PALETTE_DARK reaches FieldMoveFailed, whatever is under the
## player: map 1 is an ordinary outdoor map.
func test_flash_refuses_on_a_map_that_is_not_dark() -> void:
	var world: Gen2WorldAPI = _flash_world(true, 1)

	assert_eq(world.flash_request()["reason"], &"not_dark")


func test_flash_lights_the_cave_and_only_on_the_acknowledge() -> void:
	var world: Gen2WorldAPI = _flash_world()

	assert_eq(world.map_time_of_day(), Gen2WorldPalette.TIME_DARK)
	var staged: Dictionary = world.flash_request()
	assert_true(bool(staged["ok"]))
	assert_false(world.state.used_flash(), "nothing changes until the text is answered")
	assert_eq(world.map_time_of_day(), Gen2WorldPalette.TIME_DARK)

	var applied: Dictionary = world.complete_flash()

	assert_true(bool(applied["ok"]))
	assert_true(world.state.used_flash())
	# A lit cave is drawn as night, not as day: the cartridge swaps DARKNESS_PALSET
	# for a night palset rather than for the clock's own.
	assert_eq(world.map_time_of_day(), Gen2WorldPalette.TIME_NIGHT)
	assert_true(world.pending_flash().is_empty())


func test_flash_refuses_a_second_time_in_the_same_cave() -> void:
	var world: Gen2WorldAPI = _flash_world()
	world.flash_request()
	world.complete_flash()

	assert_eq(world.flash_request()["reason"], &"already_lit")


## `ResetFlashIfOutOfCave`: only a route or a town puts the light out, so walking
## between two cave rooms keeps it.
func test_the_light_survives_a_cave_door_and_dies_outdoors() -> void:
	var state := Gen2WorldState.new()

	state.set_used_flash(true)
	state.clear_flash_if_outdoors(ENVIRONMENT_DUNGEON)
	assert_true(state.used_flash(), "a dungeon is not outdoors")

	state.clear_flash_if_outdoors(ENVIRONMENT_TOWN)
	assert_false(state.used_flash())


## `ReplaceTimeOfDayPals`' brightness table: only PALETTE_AUTO lets the clock
## decide, and PALETTE_DARK ignores it in both states.
func test_the_map_palette_byte_decides_how_much_the_clock_matters() -> void:
	for clock: int in [
		Gen2WorldPalette.TIME_MORNING, Gen2WorldPalette.TIME_DAY, Gen2WorldPalette.TIME_NIGHT,
	]:
		assert_eq(
			Gen2WorldPalette.map_time_of_day(Gen2WorldPalette.PALETTE_AUTO, clock), clock,
			"AUTO is the clock, unchanged"
		)
		assert_eq(
			Gen2WorldPalette.map_time_of_day(Gen2WorldPalette.PALETTE_NITE, clock),
			Gen2WorldPalette.TIME_NIGHT, "a NITE map is night at noon"
		)
		assert_eq(
			Gen2WorldPalette.map_time_of_day(Gen2WorldPalette.PALETTE_DARK, clock),
			Gen2WorldPalette.TIME_DARK
		)
		assert_eq(
			Gen2WorldPalette.map_time_of_day(Gen2WorldPalette.PALETTE_DARK, clock, true),
			Gen2WorldPalette.TIME_NIGHT
		)


## TryHeadbuttOW is CheckPartyMove and nothing else, and TryHeadbuttFromMenu is
## the faced tile and nothing else. No badge is involved anywhere, which is what
## separates Headbutt from the other six.
func test_headbutt_needs_the_move_and_a_tree_and_no_badge_at_all() -> void:
	var world: Gen2WorldAPI = _headbutt_world()
	var request: Dictionary = world.headbutt_request()
	assert_true(bool(request.get("ok", false)), String(request.get("reason", "")))
	assert_eq(request["kind"], &"headbutt_requested")
	assert_eq(request["cell"], HEADBUTT_CELL)
	assert_eq(int(request["move"]), Gen2WorldFieldMove.MOVE_HEADBUTT)


func test_headbutt_refuses_without_the_move_or_a_tree() -> void:
	var unknowing: Gen2WorldAPI = _headbutt_world(false)
	var refused: Dictionary = unknowing.headbutt_request()
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"move_not_known")

	var world: Gen2WorldAPI = _headbutt_world()
	world.player_facing = Gen2WorldSprite.FACING_UP
	var no_tree: Dictionary = world.headbutt_request()
	assert_false(bool(no_tree.get("ok", false)))
	assert_eq(no_tree["reason"], &"nothing_to_headbutt")


## The roll belongs to the commit, because HeadbuttScript reaches
## TreeMonEncounter only after UseHeadbuttText.
func test_the_headbutt_request_rolls_nothing_and_changes_no_block() -> void:
	var world: Gen2WorldAPI = _headbutt_world()
	var before: int = world.block_at(0, 1)
	assert_true(bool(world.headbutt_request().get("ok", false)))
	assert_eq(world.block_at(0, 1), before, "the tree is not replaced")
	assert_false(world.pending_headbutt().is_empty())
	var second: Dictionary = world.headbutt_request()
	assert_eq(second["reason"], &"headbutt_in_progress")


## A map TreeMonMaps does not name has no set, which GetTreeMonSet answers with
## no carry: the commit still applies, as HeadbuttScript's .no_battle branch.
func test_a_map_without_a_treemon_set_headbutts_to_nothing() -> void:
	var world: Gen2WorldAPI = _headbutt_world(true, 2)
	assert_true(bool(world.headbutt_request().get("ok", false)))
	var applied: Dictionary = world.complete_headbutt(_random())
	assert_true(bool(applied.get("ok", false)))
	assert_eq(applied["kind"], &"headbutt_applied")
	assert_true((applied["encounter"] as Dictionary).is_empty())


## A populated set resolves to the wild-battle shape the other encounter paths
## return, carrying BATTLETYPE_TREE and the sleep answer with it.
func test_a_populated_set_headbutts_into_a_tree_battle() -> void:
	var world: Gen2WorldAPI = _headbutt_world()
	# The fixture's cell scores against a chosen ID so the tier is fixed: the
	# faced cell (0,3) is wPlayerMapX/Y (4,7), and 7 * 5 + 4 = 39, 39 / 5 = 7.
	assert_eq(Gen2WorldTreemon.coord_score(HEADBUTT_CELL), 7)
	world.set_player_id(7)
	var encounter: Dictionary = {}
	for seed_value: int in 20:
		var world_attempt: Gen2WorldAPI = _headbutt_world()
		world_attempt.set_player_id(7)
		assert_true(bool(world_attempt.headbutt_request().get("ok", false)))
		var applied: Dictionary = world_attempt.complete_headbutt(_random(seed_value))
		encounter = applied["encounter"]
		if not encounter.is_empty():
			break
	assert_false(encounter.is_empty(), "a RARE score meets its 80 percent threshold")
	assert_eq(int(encounter["pokemon"]), TREEMON_RARE_SPECIES, "an equal score reads the rare table")
	assert_eq(int(encounter["score"]), Gen2WorldTreemon.SCORE_RARE)
	assert_eq(encounter["method"], Gen2WorldEncounter.METHOD_HEADBUTT)
	assert_eq(encounter["source"], Gen2WorldEncounter.SOURCE_TREE)
	assert_eq(int(encounter["values"]["battle_type"]), Gen2Battle.BATTLETYPE_TREE)


## GetTreeScore reads wPlayerID, so a world no save has answered for refuses
## rather than scoring against an invented zero.
func test_completing_a_headbutt_refuses_without_a_player_id_or_a_generator() -> void:
	var world: Gen2WorldAPI = _headbutt_world()
	world.clear_player_id()
	assert_true(bool(world.headbutt_request().get("ok", false)))
	var refused: Dictionary = world.complete_headbutt(_random())
	assert_false(bool(refused.get("ok", false)))
	assert_eq(refused["reason"], &"missing_player_id")

	var second: Gen2WorldAPI = _headbutt_world()
	assert_true(bool(second.headbutt_request().get("ok", false)))
	assert_eq(second.complete_headbutt(null)["reason"], &"missing_generator")


func test_completing_a_headbutt_that_was_never_requested_is_refused() -> void:
	assert_eq(
		_headbutt_world().complete_headbutt(_random())["reason"], &"no_pending_headbutt"
	)


## CheckSleepingTreeMon is answered off the map's own time of day, and the
## fixture's morning list carries the common species but not the rare one.
func test_the_sleep_answer_follows_the_time_of_day_list() -> void:
	var world: Gen2WorldAPI = _headbutt_world()
	world.object_time_of_day = Gen2WorldPalette.TIME_MORNING
	assert_true(Gen2WorldTreemon.starts_asleep(
		ASLEEP_SPECIES, world.data.asleep_treemons(Gen2WorldPalette.TIME_MORNING)
	))
	assert_false(Gen2WorldTreemon.starts_asleep(
		TREEMON_RARE_SPECIES, world.data.asleep_treemons(Gen2WorldPalette.TIME_MORNING)
	))
	# The fixture's night list is empty, which is the Gold and Silver shape.
	assert_false(Gen2WorldTreemon.starts_asleep(
		ASLEEP_SPECIES, world.data.asleep_treemons(Gen2WorldPalette.TIME_NIGHT)
	))


func _random(seed_value: int = 3) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator


## A world standing above the headbutt tree and facing it. No badge is set on
## any table, which is the point: Headbutt has no badge gate.
func _headbutt_world(knows: bool = true, map_number: int = 1) -> Gen2WorldAPI:
	var data: GameData = GameData.open_directory(_directory)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, 1, map_number, HEADBUTT_STAND_CELL, Gen2WorldState.new()
	)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	world.set_player_id(0)
	if knows:
		_knowing_party(world, Gen2WorldFieldMove.MOVE_HEADBUTT)
	return world


## `.SaveDigWarp` and `.SetSpawn`, and the two moves that read what they wrote.

func _escape_world(map_number: int = ESCAPE_TOWN, cell: Vector2i = SPAWN_CELL) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		GameData.open_directory(_directory), 1, map_number, cell, Gen2WorldState.new()
	)
	world.set_party_summary(
		1, false, [1] as Array[int],
		[[Gen2WorldFieldMove.MOVE_DIG, Gen2WorldFieldMove.MOVE_TELEPORT]],
		["MON"], [false]
	)
	return world


func test_walking_into_a_cave_records_the_warp_and_nothing_else_does() -> void:
	var world: Gen2WorldAPI = _escape_world()
	assert_true(world.dig_warp.is_empty())
	assert_eq(world.last_spawn_map, Vector2i(-1, -1))

	world.player_cell = ESCAPE_CAVE_DOOR
	assert_true(bool(world.try_warp().get("ok", false)))
	assert_eq(world.map_id(), Vector2i(1, ESCAPE_CAVE))
	# One-based, as the town's own warp list counts it.
	assert_eq(world.dig_warp, {"warp": 1, "map_group": 1, "map_number": ESCAPE_TOWN})
	assert_eq(world.last_spawn_map, Vector2i(-1, -1), "a cave is no respawn")

	# Out again: the way back is not a walk from an outdoor map, so neither
	# record moves.
	world.player_cell = ESCAPE_INSIDE_DOOR
	assert_true(bool(world.try_warp().get("ok", false)))
	assert_eq(world.map_id(), Vector2i(1, ESCAPE_TOWN))
	assert_eq(world.dig_warp, {"warp": 1, "map_group": 1, "map_number": ESCAPE_TOWN})


func test_walking_into_a_pokemon_centre_records_the_spawn() -> void:
	var world: Gen2WorldAPI = _escape_world()
	world.player_cell = ESCAPE_CENTRE_DOOR
	assert_true(bool(world.try_warp().get("ok", false)))
	assert_eq(world.map_id(), Vector2i(1, ESCAPE_POKECENTER))
	assert_eq(world.last_spawn_map, Vector2i(1, ESCAPE_TOWN))
	# `.SetSpawn` records the map, and `IsSpawnPoint` is what turns it into the
	# spawn a blackout and a Teleport share.
	assert_eq(world.spawn_index_of(world.last_spawn_map), 0)
	assert_eq(world.whiteout_spawn(), 0)
	# `.SaveDigWarp` fires on any outdoor to indoor walk, a Pokemon Center's
	# included, so both records move on this one: the door is the town's second.
	assert_eq(world.dig_warp, {"warp": 2, "map_group": 1, "map_number": ESCAPE_TOWN})


func test_a_blackout_with_no_pokemon_centre_behind_it_falls_back_to_home() -> void:
	# `GetWhiteoutSpawn`'s own `xor a`: a game that has entered none goes home.
	assert_eq(_escape_world().whiteout_spawn(), RomLayout.SPAWN_HOME)


func test_dig_takes_the_warp_the_cave_was_entered_by() -> void:
	var world: Gen2WorldAPI = _escape_world()
	world.player_cell = ESCAPE_CAVE_DOOR
	world.try_warp()
	world.player_cell = Vector2i(4, 4)

	var dug: Dictionary = world.dig_request()
	assert_true(bool(dug.get("ok", false)), String(dug.get("reason", "")))
	assert_eq(world.map_id(), Vector2i(1, ESCAPE_TOWN))
	assert_eq(world.player_cell, ESCAPE_CAVE_DOOR)


func test_dig_is_refused_outside_a_cave_and_with_no_warp_recorded() -> void:
	var outdoors: Gen2WorldAPI = _escape_world()
	assert_eq(StringName(outdoors.dig_request()["reason"]), &"not_in_a_cave")

	var in_a_cave: Gen2WorldAPI = _escape_world(ESCAPE_CAVE, Vector2i(4, 4))
	assert_eq(StringName(in_a_cave.dig_request()["reason"]), &"no_dig_warp")

	var unknowing: Gen2WorldAPI = _escape_world(ESCAPE_CAVE, Vector2i(4, 4))
	unknowing.set_party_summary(1, false, [1] as Array[int], [[]], ["MON"], [false])
	assert_eq(StringName(unknowing.dig_request()["reason"]), &"move_not_known")


func test_teleport_returns_to_the_last_pokemon_centre_from_outdoors() -> void:
	var world: Gen2WorldAPI = _escape_world()
	world.player_cell = ESCAPE_CENTRE_DOOR
	world.try_warp()
	# Out of the centre and away, so the return is somewhere to go.
	world.player_cell = ESCAPE_INSIDE_DOOR
	world.try_warp()
	world.player_cell = Vector2i(6, 6)

	var teleported: Dictionary = world.teleport_request()
	assert_true(bool(teleported.get("ok", false)), String(teleported.get("reason", "")))
	assert_eq(world.map_id(), Vector2i(1, ESCAPE_TOWN))
	assert_eq(world.player_cell, SPAWN_CELL)


func test_teleport_is_refused_indoors_and_with_no_pokemon_centre_behind_it() -> void:
	var fresh: Gen2WorldAPI = _escape_world()
	assert_eq(StringName(fresh.teleport_request()["reason"]), &"no_spawn_point")

	var indoors: Gen2WorldAPI = _escape_world(ESCAPE_POKECENTER, Vector2i(4, 4))
	indoors.last_spawn_map = Vector2i(1, ESCAPE_TOWN)
	assert_eq(StringName(indoors.teleport_request()["reason"]), &"not_outdoors")


func test_a_snapshot_carries_both_escape_points_and_a_reopened_world_keeps_them() -> void:
	var world: Gen2WorldAPI = _escape_world()
	world.player_cell = ESCAPE_CAVE_DOOR
	world.try_warp()
	var snapshot: Gen2WorldSnapshot = Gen2WorldSnapshot.from_world(world)
	snapshot.last_spawn_map = Vector2i(1, ESCAPE_TOWN)

	var reopened: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(
		GameData.open_directory(_directory),
		Gen2WorldSnapshot.from_dict(snapshot.to_dict())
	)
	assert_eq(reopened.dig_warp, {"warp": 1, "map_group": 1, "map_number": ESCAPE_TOWN})
	assert_eq(reopened.last_spawn_map, Vector2i(1, ESCAPE_TOWN))
	# A snapshot written before either existed reads as a game that has entered
	# neither, which is what their defaults say.
	var old: Dictionary = snapshot.to_dict()
	old.erase("dig_warp")
	old.erase("last_spawn_map")
	var older: Gen2WorldSnapshot = Gen2WorldSnapshot.from_dict(old)
	assert_true(older.dig_warp.is_empty())
	assert_eq(older.last_spawn_map, Vector2i(-1, -1))


## `SweetScentEncounter`: a wild where one could have been stepped into.

func _scent_world(cell: Vector2i = GRASS_CELL, map_number: int = 1) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		GameData.open_directory(_directory), 1, map_number, cell, Gen2WorldState.new()
	)
	_knowing_party(world, Gen2WorldFieldMove.MOVE_SWEET_SCENT)
	return world


func test_sweet_scent_finds_a_wild_in_the_grass_without_rolling_the_rate() -> void:
	var world: Gen2WorldAPI = _scent_world()
	# The five-step cooldown a map entry sets is a step's gate, not this one.
	assert_true(world.state.wild_encounter_cooldown() > 0)
	var random := RandomNumberGenerator.new()
	random.seed = 7
	var scent: Dictionary = world.sweet_scent_request(random)
	assert_true(bool(scent.get("ok", false)), String(scent.get("reason", "")))
	assert_eq(int((scent["encounter"] as Dictionary)["pokemon"]), TREEMON_SPECIES)


func test_sweet_scent_says_nothing_is_here_off_the_grass_and_on_a_bare_map() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 7
	# `CanEncounterWildMon`: ordinary floor is where the source refuses first.
	var on_floor: Gen2WorldAPI = _scent_world(Vector2i(1, 1))
	assert_eq(StringName(on_floor.sweet_scent_request(random)["reason"]), &"no_encounter")

	# And a map with no table of its own answers the same, which is
	# `ChooseWildEncounter` refusing rather than the tile.
	var bare: Gen2WorldAPI = _scent_world(GRASS_CELL, 2)
	assert_eq(StringName(bare.sweet_scent_request(random)["reason"]), &"no_encounter")


func test_sweet_scent_needs_a_party_member_that_knows_it() -> void:
	var world: Gen2WorldAPI = _scent_world()
	world.set_party_summary(1, false, [1] as Array[int], [[]], ["MON"], [false])
	assert_eq(StringName(world.sweet_scent_request()["reason"]), &"move_not_known")
