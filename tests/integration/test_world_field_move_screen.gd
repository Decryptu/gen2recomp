extends GutTest

## Scene integration for Cut, Surf and Whirlpool: the party submenu, the
## field-move message and the change each commits, driven through the production
## world screen and party screen.
##
## The shared trainer fixture is patched here rather than extended, the same way
## test_world_start_menu_screen.gd patches its Potion in: the map moves onto
## TILESET_JOHTO so the real CutTreeBlockPointers and WhirlpoolBlockPointers rows
## apply, block $5b's bottom-left quadrant becomes the cut tree and block $07's
## the whirlpool. The fixture's own water cell at (8,7) is what Surf is driven
## against.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")
const BattleFixture := preload("res://tests/unit/battle_fixture.gd")

const TILESET: int = Gen2WorldFieldMove.TILESET_JOHTO
const BLOCK_COUNT: int = 0x68
const BLOCK_TREE: int = 0x5B
const BLOCK_TREE_CUT: int = 0x3C
const TREE_BLOCK: Vector2i = Vector2i(1, 1)
const TREE_CELL: Vector2i = Vector2i(2, 3)
const PLAYER_CELL: Vector2i = Vector2i(2, 2)
## The fixture's own water cell and the land directly above it.
const WATER_CELL: Vector2i = Vector2i(8, 7)
const SHORE_CELL: Vector2i = Vector2i(8, 6)
## WhirlpoolBlockPointers' only row, on the same TILESET_JOHTO the cut rows use.
const BLOCK_WHIRLPOOL: int = 0x07
const BLOCK_WHIRLPOOL_GONE: int = 0x36
const WHIRLPOOL_BLOCK: Vector2i = Vector2i(1, 3)
const WHIRLPOOL_CELL: Vector2i = Vector2i(2, 7)
const WHIRLPOOL_STAND_CELL: Vector2i = Vector2i(2, 6)
## A headbutt tree in block (3,1)'s bottom-left quadrant, with the standing cell
## directly above it. The set behind it is populated, so a commit can reach a
## battle; the score is fixed by the cell and the save's own wPlayerID.
const BLOCK_HEADBUTT_TREE: int = 0x40
const HEADBUTT_BLOCK: Vector2i = Vector2i(3, 1)
const HEADBUTT_CELL: Vector2i = Vector2i(6, 3)
const HEADBUTT_STAND_CELL: Vector2i = Vector2i(6, 2)
const TREEMON_SET: int = 1
const TREEMON_SPECIES: int = Fixture.TRAINER_SPECIES
## A smashable rock and the cell the player stands on to face it. The rock is a
## map object, not a tile, which is the whole difference from a headbutt tree:
## TryRockSmashFromMenu asks GetFacingObject rather than the collision byte.
## A two-cell waterfall column with water below it, so the climb has somewhere
## to start and CheckMapCanWaterfall has a facing to check.
const WATERFALL_STAND_CELL: Vector2i = Vector2i(4, 7)
const WATERFALL_CELL: Vector2i = Vector2i(4, 6)
const WATERFALL_TOP_CELL: Vector2i = Vector2i(4, 5)
const ROCK_CELL: Vector2i = Vector2i(9, 3)
const ROCK_STAND_CELL: Vector2i = Vector2i(9, 2)
const ROCK_OBJECT_INDEX: int = 1
## RockMonMaps names the same map, with the ROCK set at its Crystal number.
const ROCK_SET: int = 7
## The rock's own script, which every real rock has: `jumpstd SmashRockScript`.
const ROCK_SCRIPT: int = 0x6400
const STD_SMASH_ROCK: int = 15
## Any permanent flag: the fixture's rock carries -1 like the real ones, so a
## test that wants Mt. Moon Square's behavior gives it one.
const ROCK_EVENT_FLAG: int = 900

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	_data = Fixture.build()
	_write_cut_tree()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	Gen2ModHost.reset()
	RomCache.clear(Fixture.directory())


func _write_cut_tree() -> void:
	var directory: String = Fixture.directory()
	var moves: Array = RomCache.read_json(RomCache.moves_path(directory))
	for raw: Dictionary in moves:
		if int(raw.get("number", 0)) == Gen2WorldFieldMove.MOVE_CUT:
			raw["name"] = "CUT"
		elif int(raw.get("number", 0)) == Gen2WorldFieldMove.MOVE_SURF:
			raw["name"] = "SURF"
		elif int(raw.get("number", 0)) == Gen2WorldFieldMove.MOVE_STRENGTH:
			raw["name"] = "STRENGTH"
		elif int(raw.get("number", 0)) == Gen2WorldFieldMove.MOVE_WHIRLPOOL:
			raw["name"] = "WHIRLPOOL"
		elif int(raw.get("number", 0)) == Gen2WorldFieldMove.MOVE_HEADBUTT:
			raw["name"] = "HEADBUTT"
		elif int(raw.get("number", 0)) == Gen2WorldFieldMove.MOVE_ROCK_SMASH:
			raw["name"] = "ROCK SMASH"
	RomCache.write_json(RomCache.moves_path(directory), moves)

	var tilesets: Array = RomCache.read_json(RomCache.world_tilesets_path(directory))
	var tileset: Dictionary = tilesets[0]
	tileset["number"] = TILESET
	tileset["block_count"] = BLOCK_COUNT
	var meta: Array = []
	for block: int in BLOCK_COUNT:
		for tile: int in 16:
			meta.append((block + tile) & 0xFF)
	tileset["meta"] = meta
	var tile_collision: Array = []
	tile_collision.resize(BLOCK_COUNT * 4)
	tile_collision.fill(0)
	# Quadrant order is top-left, top-right, bottom-left, bottom-right.
	tile_collision[BLOCK_TREE * 4 + 2] = 0x12  # COLL_CUT_TREE
	tile_collision[BLOCK_WHIRLPOOL * 4 + 2] = 0x24  # COLL_WHIRLPOOL
	tile_collision[BLOCK_HEADBUTT_TREE * 4 + 2] = Gen2WorldCollision.COLL_HEADBUTT_TREE
	tileset["collision"] = tile_collision
	RomCache.write_json(RomCache.world_tilesets_path(directory), tilesets)

	var maps: Array = RomCache.read_json(RomCache.world_maps_path(directory))
	for raw: Dictionary in maps:
		raw["tileset"] = TILESET
		if int(raw.get("group", 0)) != Fixture.MAP_GROUP \
			or int(raw.get("number", 0)) != Fixture.MAP_NUMBER:
			continue
		var blocks: Array = raw["blocks"]
		blocks[TREE_BLOCK.y * Fixture.MAP_WIDTH_BLOCKS + TREE_BLOCK.x] = BLOCK_TREE
		blocks[WHIRLPOOL_BLOCK.y * Fixture.MAP_WIDTH_BLOCKS + WHIRLPOOL_BLOCK.x] = BLOCK_WHIRLPOOL
		blocks[HEADBUTT_BLOCK.y * Fixture.MAP_WIDTH_BLOCKS + HEADBUTT_BLOCK.x] = BLOCK_HEADBUTT_TREE
		var collision: Array = raw["collision"]
		collision[TREE_CELL.y * Fixture.MAP_WIDTH_CELLS + TREE_CELL.x] = 0x12
		collision[WHIRLPOOL_CELL.y * Fixture.MAP_WIDTH_CELLS + WHIRLPOOL_CELL.x] = 0x24
		collision[HEADBUTT_CELL.y * Fixture.MAP_WIDTH_CELLS + HEADBUTT_CELL.x] = \
			Gen2WorldCollision.COLL_HEADBUTT_TREE
		collision[WATERFALL_STAND_CELL.y * Fixture.MAP_WIDTH_CELLS + WATERFALL_STAND_CELL.x] = 0x29
		for waterfall_cell: Vector2i in [WATERFALL_CELL, WATERFALL_TOP_CELL]:
			collision[waterfall_cell.y * Fixture.MAP_WIDTH_CELLS + waterfall_cell.x] = \
				Gen2WorldCollision.COLL_WATERFALL
		# A second object beside the fixture's trainer, carrying the rock's own
		# movement byte and the fixture's only sprite. Its event flag is -1, the
		# way fifteen of the sixteen real rocks are, so smashing it lasts only
		# as long as the loaded map.
		(raw["events"]["objects"] as Array).append({
			"sprite": Fixture.TRAINER_SPRITE,
			"x": ROCK_CELL.x, "y": ROCK_CELL.y,
			"movement": Gen2WorldObject.MOVEMENT_SMASHABLE_ROCK,
			"x_radius": 0, "y_radius": 0, "hour_1": -1, "hour_2": -1, "palette": 0,
			"object_type": Gen2WorldObject.OBJECTTYPE_SCRIPT,
			"sight_range": 0, "script": ROCK_SCRIPT, "event_flag": 0xFFFF,
		})
	RomCache.write_json(RomCache.world_maps_path(directory), maps)

	# TreeMonMaps and one populated set, patched into the fixture's own
	# encounter cache rather than added to the shared fixture.
	var encounters: Dictionary = RomCache.read_json(
		RomCache.world_encounters_path(directory)
	)
	encounters["treemons"] = {
		"tree_maps": [{
			"map_group": Fixture.MAP_GROUP,
			"map_number": Fixture.MAP_NUMBER,
			"set": TREEMON_SET,
		}],
		"rock_maps": [{
			"map_group": Fixture.MAP_GROUP,
			"map_number": Fixture.MAP_NUMBER,
			"set": ROCK_SET,
		}],
		"sets": [
			{"common": [], "rare": []},
			{
				"common": [{"percent": 100, "species": TREEMON_SPECIES, "level": 5}],
				"rare": [{"percent": 100, "species": TREEMON_SPECIES, "level": 5}],
			},
			{"common": [], "rare": []},
			{"common": [], "rare": []},
			{"common": [], "rare": []},
			{"common": [], "rare": []},
			{"common": [], "rare": []},
			## TreeMonSet_Rock's own shape: a common table and no rare one.
			{"common": [{"percent": 100, "species": TREEMON_SPECIES, "level": 5}], "rare": []},
		],
		"asleep": {"morn": [], "day": [], "nite": []},
	}
	RomCache.write_json(RomCache.world_encounters_path(directory), encounters)

	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(directory))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, ROCK_SCRIPT)] = [
		Gen2WorldScript.JUMPSTD, STD_SMASH_ROCK, 0,
	]
	RomCache.write_json(RomCache.world_scripts_path(directory), scripts)

	var tiles: PackedByteArray = PackedByteArray()
	tiles.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	tiles.fill(1)
	RomCache.write_indices(RomCache.world_tile_path(directory, TILESET), tiles)


## A save whose first party member knows the field move and whose second does
## not, so one submenu offers it and the other does not.
func _save_with_move(move: int) -> Gen2SaveData:
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(_data, 0)
	(save.party[0] as Gen2SaveMon).moves = [move, 0, 0, 0]
	(save.party[0] as Gen2SaveMon).nickname = "TESTMON"
	if save.party.size() > 1:
		(save.party[1] as Gen2SaveMon).moves = [BattleFixture.TACKLE, 0, 0, 0]
	return save


func _open_world(
	badge: bool = true,
	move: int = Gen2WorldFieldMove.MOVE_CUT,
	badge_index: int = Gen2WorldFieldMove.BADGE_HIVE,
	cell: Vector2i = PLAYER_CELL,
) -> void:
	# A test that opens a second world frees the first here rather than leaking
	# it: after_each() only ever sees the last one.
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = cell
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			badge_index, Gen2WorldState.is_crystal_profile(_data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, cell, state
	)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var save: Gen2SaveData = _save_with_move(move)
	save.world = world.snapshot()
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame
	_world_screen._world.player_cell = cell
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_DOWN


func _open_surf_world(badge: bool = true, cell: Vector2i = SHORE_CELL) -> void:
	await _open_world(badge, Gen2WorldFieldMove.MOVE_SURF, Gen2WorldFieldMove.BADGE_FOG, cell)


func _open_whirlpool_world(
	badge: bool = true, cell: Vector2i = WHIRLPOOL_STAND_CELL
) -> void:
	await _open_world(
		badge, Gen2WorldFieldMove.MOVE_WHIRLPOOL, Gen2WorldFieldMove.BADGE_GLACIER, cell
	)


func _open_party() -> Gen2PartyScreen:
	_world_screen._open_embedded_party()
	await get_tree().process_frame
	return _world_screen._party_host


## The text box holds its message as wrapped lines, so the assertions below
## rejoin them rather than depending on where the wrap lands.
func _shown_text() -> String:
	return " ".join(_world_screen._text_box.text_lines())


func _labels(items: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in items:
		out.append(String(entry.get("label", "")))
	return out


func test_submenu_lists_cut_only_for_a_mon_that_knows_it() -> void:
	await _open_world()
	var party: Gen2PartyScreen = await _open_party()
	assert_not_null(party)
	party.handle_button(Gen2Button.A)
	var first: Dictionary = party.submenu_snapshot()
	assert_true(bool(first["open"]))
	# GetMonSubmenuItems walks the move slots first, so a field move leads.
	assert_eq(_labels(first["items"]), ["CUT", "STATS", "SWITCH", "MOVE", "ITEM", "CANCEL"])

	party.handle_button(Gen2Button.B)
	party.handle_button(Gen2Button.DOWN)
	party.handle_button(Gen2Button.A)
	assert_eq(
		_labels(party.submenu_snapshot()["items"]),
		["STATS", "SWITCH", "MOVE", "ITEM", "CANCEL"]
	)


func test_an_egg_submenu_carries_only_the_three_source_entries() -> void:
	await _open_world()
	var egg := Gen2SaveMon.new()
	egg.is_egg = true
	egg.moves = [Gen2WorldFieldMove.MOVE_CUT, 0, 0, 0]
	assert_eq(
		_labels(Gen2PartyScreen.submenu_items_for(_data, egg)),
		["STATS", "SWITCH", "CANCEL"]
	)


func test_choosing_cut_shows_the_message_and_defers_the_block_change() -> void:
	await _open_world()
	var world: Gen2WorldAPI = _world_screen._world
	assert_false(world.can_walk_to(TREE_CELL))
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_null(_world_screen._party_host)
	assert_true(_world_screen._field_move_text)
	assert_eq(_shown_text(), "TESTMON used CUT!")
	# Script_Cut writes the block only after UseCutText.
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)
	assert_false(world.can_walk_to(TREE_CELL))
	# The world is idle while the message is up.
	assert_false(_world_screen.move_player(Vector2i.RIGHT))
	assert_false(_world_screen.interact())
	assert_false(_world_screen._objects_may_move())

	_world_screen._acknowledge_field_move_text()
	assert_false(_world_screen._field_move_text)
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE_CUT)
	assert_true(world.can_walk_to(TREE_CELL))
	## `.CheckTurning` turns on the spot first when the pressed direction is not
	## the one faced, so the walk is the press after it.
	_world_screen.move_player(Vector2i.DOWN)
	while world.player_step_in_progress():
		world.advance_player_step_frame()
	if world.player_cell != TREE_CELL:
		assert_true(_world_screen.move_player(Vector2i.DOWN))
	assert_eq(world.player_cell, TREE_CELL)


func test_cut_without_the_badge_reports_the_badge_and_changes_nothing() -> void:
	await _open_world(false)
	var world: Gen2WorldAPI = _world_screen._world
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_true(_world_screen._field_move_text)
	assert_eq(_shown_text(), "Sorry! A new BADGE is required.")
	_world_screen._acknowledge_field_move_text()
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)
	assert_false(world.can_walk_to(TREE_CELL))


func test_cut_facing_nothing_reports_the_source_refusal() -> void:
	await _open_world()
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_UP
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(_shown_text(), "There's nothing to CUT here.")
	_world_screen._acknowledge_field_move_text()
	assert_true(_world_screen._world.pending_cut().is_empty())
	assert_eq(_world_screen._world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)


func test_submenu_lists_surf_for_a_mon_that_knows_it() -> void:
	await _open_surf_world()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	assert_eq(
		_labels(party.submenu_snapshot()["items"]),
		["SURF", "STATS", "SWITCH", "MOVE", "ITEM", "CANCEL"]
	)


func test_choosing_surf_shows_the_message_and_defers_entering_the_water() -> void:
	await _open_surf_world()
	var world: Gen2WorldAPI = _world_screen._world
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_null(_world_screen._party_host)
	assert_true(_world_screen._field_move_text)
	assert_eq(_shown_text(), "TESTMON used SURF!")
	# UsedSurfScript reaches writevar VAR_MOVEMENT only after its waitbutton.
	assert_eq(world.player_cell, SHORE_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_PLAYER)
	assert_false(_world_screen.move_player(Vector2i.RIGHT))

	_world_screen._acknowledge_field_move_text()
	assert_false(_world_screen._field_move_text)
	assert_eq(world.player_cell, WATER_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_SURF)
	assert_true(world.pending_surf().is_empty())


func test_stepping_back_onto_land_stops_surfing_through_the_screen() -> void:
	await _open_surf_world()
	var world: Gen2WorldAPI = _world_screen._world
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	_world_screen._acknowledge_field_move_text()
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)

	# The entry step is a slow_step, so the presentation offset has to run out
	# before the screen accepts input again.
	while world.player_step_in_progress():
		world.advance_player_step_frame()
	## `.CheckTurning` turns on the spot first when the pressed direction is not
	## the one faced, so the walk is the press after it.
	_world_screen.move_player(Vector2i.UP)
	while world.player_step_in_progress():
		world.advance_player_step_frame()
	if world.player_cell != SHORE_CELL:
		assert_true(_world_screen.move_player(Vector2i.UP))
	assert_eq(world.player_cell, SHORE_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)
	assert_eq(world.player_sprite_number, Gen2WorldSprite.SPRITE_PLAYER)


func test_surf_without_the_badge_reports_the_badge_and_changes_nothing() -> void:
	await _open_surf_world(false)
	var world: Gen2WorldAPI = _world_screen._world
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(_shown_text(), "Sorry! A new BADGE is required.")
	_world_screen._acknowledge_field_move_text()
	assert_eq(world.player_cell, SHORE_CELL)
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)


func test_surf_facing_land_reports_the_source_refusal() -> void:
	await _open_surf_world()
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_UP
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(_shown_text(), "You can't SURF here.")
	_world_screen._acknowledge_field_move_text()
	assert_true(_world_screen._world.pending_surf().is_empty())
	assert_eq(_world_screen._world.movement_mode, Gen2WorldAPI.MOVEMENT_WALK)


func test_surf_while_already_surfing_reports_the_source_refusal() -> void:
	await _open_surf_world(true, WATER_CELL)
	var world: Gen2WorldAPI = _world_screen._world
	assert_true(world.set_movement_mode(Gen2WorldAPI.MOVEMENT_SURF)["ok"])
	world.player_cell = WATER_CELL
	world.player_facing = Gen2WorldSprite.FACING_UP
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(_shown_text(), "You're already SURFING.")


func test_cancel_closes_the_submenu_before_the_party_screen() -> void:
	await _open_world()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	assert_true(bool(party.submenu_snapshot()["open"]))
	party.handle_button(Gen2Button.B)
	assert_false(bool(party.submenu_snapshot()["open"]))
	assert_not_null(_world_screen._party_host)
	party.handle_button(Gen2Button.B)
	await get_tree().process_frame
	assert_null(_world_screen._party_host)


func _open_strength_world(badge: bool = true) -> void:
	await _open_world(
		badge, Gen2WorldFieldMove.MOVE_STRENGTH, Gen2WorldFieldMove.BADGE_PLAIN
	)


func test_submenu_lists_strength_for_a_mon_that_knows_it() -> void:
	await _open_strength_world()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	assert_eq(
		_labels(party.submenu_snapshot()["items"]),
		["STRENGTH", "STATS", "SWITCH", "MOVE", "ITEM", "CANCEL"]
	)


## .TryStrength checks the badge and stops, so the entry resolves facing open
## floor with no boulder in sight, and the flag waits for the acknowledge the way
## Cut's block change does.
func test_choosing_strength_shows_the_message_and_defers_the_flag() -> void:
	await _open_strength_world()
	var world: Gen2WorldAPI = _world_screen._world
	world.player_facing = Gen2WorldSprite.FACING_UP
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_null(_world_screen._party_host)
	assert_true(_world_screen._field_move_text)
	assert_eq(_shown_text(), "TESTMON used STRENGTH!")
	assert_false(world.strength_active())

	_world_screen._acknowledge_field_move_text()
	assert_false(_world_screen._field_move_text)
	assert_true(world.strength_active())
	assert_true(world.pending_strength().is_empty())


func test_strength_without_the_badge_reports_the_badge_and_changes_nothing() -> void:
	await _open_strength_world(false)
	var world: Gen2WorldAPI = _world_screen._world
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(_shown_text(), "Sorry! A new BADGE is required.")
	_world_screen._acknowledge_field_move_text()
	assert_false(world.strength_active())


func test_submenu_lists_whirlpool_for_a_mon_that_knows_it() -> void:
	await _open_whirlpool_world()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	assert_eq(
		_labels(party.submenu_snapshot()["items"]),
		["WHIRLPOOL", "STATS", "SWITCH", "MOVE", "ITEM", "CANCEL"]
	)


func test_choosing_whirlpool_shows_the_message_and_defers_the_block_change() -> void:
	await _open_whirlpool_world()
	var world: Gen2WorldAPI = _world_screen._world
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_null(_world_screen._party_host)
	assert_true(_world_screen._field_move_text)
	assert_eq(_shown_text(), "TESTMON used WHIRLPOOL!")
	# Script_UsedWhirlpool reaches DisappearWhirlpool only after UseWhirlpoolText.
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL)
	assert_eq(world.collision_code_at(WHIRLPOOL_CELL), 0x24)

	_world_screen._acknowledge_field_move_text()
	assert_false(_world_screen._field_move_text)
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL_GONE)
	assert_ne(world.collision_code_at(WHIRLPOOL_CELL), 0x24)
	assert_true(world.pending_whirlpool().is_empty())


func test_whirlpool_without_the_badge_reports_the_badge_and_changes_nothing() -> void:
	await _open_whirlpool_world(false)
	var world: Gen2WorldAPI = _world_screen._world
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(_shown_text(), "Sorry! A new BADGE is required.")
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL)
	_world_screen._acknowledge_field_move_text()
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL)


## .FailWhirlpool calls FieldMoveFailed, so the tile refusal is _CantUseItemText
## rather than a whirlpool-specific line the way Cut's .FailCut has one.
func test_whirlpool_facing_nothing_reports_the_generic_refusal() -> void:
	await _open_whirlpool_world()
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_UP
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(_shown_text(), "Can't use that here.")


func test_submenu_lists_headbutt_for_a_mon_that_knows_it() -> void:
	await _open_headbutt_world()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(
		_labels(party.submenu_snapshot()["items"]),
		["HEADBUTT", "STATS", "SWITCH", "MOVE", "ITEM", "CANCEL"]
	)


## HeadbuttScript reaches TreeMonEncounter only after UseHeadbuttText, so the
## roll waits for the acknowledge exactly as Cut's block change does. The text
## is "did a HEADBUTT!", not the "used" the other five share.
func test_choosing_headbutt_shows_the_message_and_defers_the_roll() -> void:
	await _open_headbutt_world()
	var world: Gen2WorldAPI = _world_screen._world
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_true(_world_screen._field_move_text)
	assert_eq(_shown_text(), "TESTMON did a HEADBUTT!")
	assert_false(world.pending_headbutt().is_empty())
	assert_false(_world_screen.move_player(Vector2i.RIGHT))
	# The tree is not a block the move replaces, unlike Cut's and Whirlpool's.
	assert_eq(world.block_at(HEADBUTT_BLOCK.x, HEADBUTT_BLOCK.y), BLOCK_HEADBUTT_TREE)

	_world_screen._acknowledge_field_move_text()
	assert_true(world.pending_headbutt().is_empty())
	assert_eq(world.block_at(HEADBUTT_BLOCK.x, HEADBUTT_BLOCK.y), BLOCK_HEADBUTT_TREE)
	assert_false(world.can_walk_to(HEADBUTT_CELL), "the tree still blocks")


## Headbutt has no badge at all: TryHeadbuttOW is CheckPartyMove and nothing
## else. The same world with no badge flags set still reaches its message.
func test_headbutt_needs_no_badge() -> void:
	await _open_headbutt_world(false)
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(_shown_text(), "TESTMON did a HEADBUTT!")


func test_headbutt_facing_nothing_reports_the_generic_refusal() -> void:
	await _open_headbutt_world()
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_UP
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_eq(_shown_text(), "Can't use that here.")
	_world_screen._acknowledge_field_move_text()
	assert_true(_world_screen._world.pending_headbutt().is_empty())


## The commit is either .no_battle's HeadbuttNothingText or a wild battle, and
## which one is fixed once the score and the roll are: the faced cell (6,3) is
## wPlayerMapX/Y (10,7), so 7 * 11 + 10 = 87, 87 / 5 = 17 and 17 % 10 = 7. An
## ID scoring 7 is the equal case, which is RARE and passes on a roll under 8.
func test_a_rare_score_that_passes_its_roll_opens_the_tree_battle() -> void:
	await _open_headbutt_world()
	assert_eq(Gen2WorldTreemon.coord_score(HEADBUTT_CELL), 7)
	await _headbutt_with(7, 1)

	assert_not_null(_world_screen._battle_host, "a passed RARE roll reaches startbattle")
	var battle: Gen2Battle = _world_screen._battle_host._battle
	var enemy: Gen2BattleMon = battle.party(Gen2Battle.ENEMY).active_mon()
	assert_eq(enemy.species, TREEMON_SPECIES)
	assert_eq(battle.battle_type, Gen2Battle.BATTLETYPE_TREE)
	# The fixture's lists are empty, which is the Gold and Silver shape, so
	# nothing enters asleep here.
	assert_eq(enemy.status, Gen2Status.NONE)


## The same tree with an ID two below the coordinate score is BAD, whose whole
## threshold is a roll of zero, so the same seed falls to .no_battle.
func test_a_bad_score_that_fails_its_roll_prints_the_nothing_text() -> void:
	await _open_headbutt_world()
	await _headbutt_with(2, 1)

	assert_null(_world_screen._battle_host)
	assert_true(_world_screen._field_move_text)
	assert_eq(_shown_text(), "Nope. Nothing…")


## Chooses HEADBUTT from the submenu and acknowledges its text, with the score
## and the roll both pinned.
func _headbutt_with(player_id: int, seed_value: int) -> void:
	# On the save rather than on the world: _refresh_party_summary() mirrors the
	# save's own wPlayerID onto the world every time it runs, so a value written
	# straight to the world would be overwritten before the commit.
	_world_screen._injected_save.player_id = player_id
	_world_screen._refresh_party_summary()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	# Seeded here rather than before the submenu: the screen's own frames draw
	# from the same generator, and only the roll behind the acknowledge is
	# being pinned.
	_world_screen._encounter_random.seed = seed_value
	_world_screen._acknowledge_field_move_text()
	## HeadbuttScript spends ShakeHeadbuttTree's 32 frames between the text and
	## `callasm TreeMonEncounter`. The screen counts hardware frames off
	## wall-clock delta, so this takes its processing away and spends them.
	_world_screen.set_process(false)
	for _frame: int in Gen2WorldEffects.HEADBUTT_TREE_FRAMES + 1:
		_world_screen.advance_frame()
	await get_tree().process_frame


func _open_headbutt_world(badge: bool = true) -> void:
	await _open_world(
		badge, Gen2WorldFieldMove.MOVE_HEADBUTT, Gen2WorldFieldMove.BADGE_HIVE,
		HEADBUTT_STAND_CELL
	)


func test_submenu_lists_rock_smash_for_a_mon_that_knows_it() -> void:
	await _open_rock_smash_world()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(
		_labels(party.submenu_snapshot()["items"]),
		["ROCK SMASH", "STATS", "SWITCH", "MOVE", "ITEM", "CANCEL"]
	)


## RockSmashScript reaches `disappear LAST_TALKED` and RockMonEncounter only
## after UseRockSmashText, so the rock is still there while the message is up.
func test_choosing_rock_smash_shows_the_message_and_defers_the_rock() -> void:
	await _open_rock_smash_world()
	var world: Gen2WorldAPI = _world_screen._world
	assert_false(world.can_walk_to(ROCK_CELL), "an active object blocks its cell")
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame

	assert_true(_world_screen._field_move_text)
	assert_eq(_shown_text(), "TESTMON used ROCK SMASH!")
	assert_false(world.pending_rock_smash().is_empty())
	assert_not_null(world.object_at(ROCK_CELL), "the rock is still there")
	assert_false(world.can_walk_to(ROCK_CELL))

	_world_screen._encounter_random.seed = 4
	_world_screen._acknowledge_field_move_text()
	await get_tree().process_frame
	assert_true(world.pending_rock_smash().is_empty())
	assert_null(world.object_at(ROCK_CELL), "disappear LAST_TALKED deleted it")
	assert_true(world.can_walk_to(ROCK_CELL), "and its cell is walkable")


## Rock Smash asks no badge and no tile: the faced object's movement byte is the
## whole question, so facing away refuses even standing beside the rock.
func test_rock_smash_needs_no_badge_and_refuses_when_facing_no_rock() -> void:
	await _open_rock_smash_world(false)
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(_shown_text(), "TESTMON used ROCK SMASH!", "no badge is involved")
	_world_screen._acknowledge_field_move_text()

	await _open_rock_smash_world()
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_UP
	var facing_away: Gen2PartyScreen = await _open_party()
	facing_away.handle_button(Gen2Button.A)
	facing_away.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(_shown_text(), "Can't use that here.")
	_world_screen._acknowledge_field_move_text()
	assert_not_null(_world_screen._world.object_at(ROCK_CELL), "and the rock stays")


## RockMonEncounter is a flat 40 percent: seed 2's first RandomRange(10) is 0,
## which passes, and seed 4's is 7, which does not. The rock goes either way,
## because the disappear is before the roll.
func test_a_passed_rock_roll_opens_a_battle_and_a_failed_one_does_not() -> void:
	await _open_rock_smash_world()
	await _rock_smash_with(2)
	assert_not_null(_world_screen._battle_host, "a roll under 4 reaches startbattle")
	var battle: Gen2Battle = _world_screen._battle_host._battle
	assert_eq(battle.party(Gen2Battle.ENEMY).active_mon().species, TREEMON_SPECIES)
	# RockMonEncounter writes no wBattleType, unlike TreeMonEncounter.
	assert_eq(battle.battle_type, Gen2Battle.BATTLETYPE_NORMAL)
	assert_null(_world_screen._world.object_at(ROCK_CELL))

	await _open_rock_smash_world()
	await _rock_smash_with(4)
	assert_null(_world_screen._battle_host, "a roll of 4 or more is no encounter")
	assert_null(_world_screen._world.object_at(ROCK_CELL), "and the rock is gone anyway")


## Chooses ROCK SMASH from the submenu and acknowledges its text with the roll
## pinned, the way _headbutt_with() does.
func _rock_smash_with(seed_value: int) -> void:
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	_world_screen._encounter_random.seed = seed_value
	_world_screen._acknowledge_field_move_text()
	await get_tree().process_frame


func _open_rock_smash_world(badge: bool = true) -> void:
	await _open_world(
		badge, Gen2WorldFieldMove.MOVE_ROCK_SMASH, Gen2WorldFieldMove.BADGE_HIVE,
		ROCK_STAND_CELL
	)


## The other half of Rock Smash, and the half Headbutt does not have: talking to
## the rock. Every rock's script is `jumpstd SmashRockScript`, whose body is
## `farsjump AskRockSmashScript`, so the runner answers standard-script index 15
## with the synthesized ask the way it answers 14 with the boulder's.
func test_talking_to_a_rock_asks_and_then_smashes_it() -> void:
	await _open_rock_smash_world()
	var world: Gen2WorldAPI = _world_screen._world
	# RockMonEncounter rolls on the script's own generator. Seed 4's first
	# RandomRange(10) is 7, which is 4 or more, so this run takes `.done` and
	# the script ends instead of waiting on a battle.
	world.script_random = RandomNumberGenerator.new()
	world.script_random.seed = 4

	var opened: Array = world.interact()
	assert_eq(opened[0]["status"], &"waiting", JSON.stringify(opened))
	assert_string_contains(String(opened[0]["event"]["text"]), "This rock looks")

	# opentext, writetext, yesorno: the text is acknowledged, then the choice.
	var asked: Array = world.run_event_queue(true)
	assert_eq(asked[0]["event"]["type"], &"choice", JSON.stringify(asked))
	var used: Array = world.choose_script_input(0)
	assert_string_contains(String(used[0]["event"]["text"]), "used")
	assert_not_null(world.object_at(ROCK_CELL), "the rock is still there mid-script")

	# closetext, WaitSFX and playsound SFX_STRENGTH, which the host answers
	# before the earthquake, the disappear and the roll.
	var sound: Array = world.run_event_queue(true)
	assert_eq(
		sound[0]["event"]["request"]["kind"], &"audio_requested", JSON.stringify(sound)
	)
	# Answered on the world rather than through Gen2WorldHost, which would want
	# audio data this synthetic cache does not carry.
	var completed: Array = world.complete_runtime_request({"ok": true})
	assert_eq(completed[0]["status"], &"complete", JSON.stringify(completed))
	assert_true(
		_has_event(completed[0]["events"], &"screen_shake_requested"),
		"earthquake 84 is reported"
	)
	assert_null(world.object_at(ROCK_CELL), "disappear LAST_TALKED took the rock")
	assert_true(world.can_walk_to(ROCK_CELL))


## The same path with a roll that passes: `readmem wTempWildMonSpecies` is
## non-zero, so the script reaches randomwildmon and startbattle instead of
## ending, and the rock is gone either way.
func test_a_talked_rock_that_rolls_an_encounter_asks_for_a_battle() -> void:
	await _open_rock_smash_world()
	var world: Gen2WorldAPI = _world_screen._world
	# Seed 2's first RandomRange(10) is 0, which is under 4.
	world.script_random = RandomNumberGenerator.new()
	world.script_random.seed = 2

	world.interact()
	world.run_event_queue(true)
	world.choose_script_input(0)
	world.run_event_queue(true)
	var after_sound: Array = world.complete_runtime_request({"ok": true})
	assert_eq(after_sound[0]["status"], &"waiting", JSON.stringify(after_sound))
	var request: Dictionary = after_sound[0]["event"]["request"]
	assert_eq(request["kind"], &"battle_requested")
	assert_eq(int(request["values"]["pokemon"]), TREEMON_SPECIES)
	assert_eq(request["values"]["kind"], &"wild")


## `HasRockSmash` is CheckPartyMove and nothing else, so a party without the
## move is told _MaySmashText and never offered the choice.
func test_talking_to_a_rock_without_the_move_only_reports_it() -> void:
	await _open_world(
		true, Gen2WorldFieldMove.MOVE_CUT, Gen2WorldFieldMove.BADGE_HIVE, ROCK_STAND_CELL
	)
	var world: Gen2WorldAPI = _world_screen._world
	var opened: Array = world.interact()
	assert_string_contains(String(opened[0]["event"]["text"]), "Maybe a #MON")
	var after: Array = world.run_event_queue(true)
	assert_eq(after[0]["status"], &"complete", JSON.stringify(after))
	assert_not_null(world.object_at(ROCK_CELL), "and the rock is untouched")


## Whether a result's event list carries one type, for the presentation
## requests a script reports rather than performs.
func _has_event(events: Array, type: StringName) -> bool:
	for event: Variant in events:
		if event is Dictionary and StringName((event as Dictionary).get("type", &"")) == type:
			return true
	return false


## `disappear` is DeleteObjectStruct plus ApplyEventActionAppearDisappear, and
## the second half writes nothing when the object's event flag is `-1`. A map
## load runs ReadObjectEvents and rebuilds every object, so an unflagged rock
## comes back and only a flagged one stays smashed. Fifteen of the sixteen real
## rocks are unflagged; Mt. Moon Square's is the exception.
func test_an_unflagged_rock_comes_back_on_a_map_reload() -> void:
	await _open_rock_smash_world()
	var world: Gen2WorldAPI = _world_screen._world
	await _rock_smash_with(4)
	assert_null(world.object_at(ROCK_CELL))

	world.reload_current_map()
	assert_not_null(world.object_at(ROCK_CELL), "the rock is back")
	assert_false(world.can_walk_to(ROCK_CELL), "and it blocks again")


## The same rock given an event flag stays smashed, which is what gates
## Mt. Moon Square's Clefairy dance.
func test_a_flagged_rock_stays_smashed_across_a_reload() -> void:
	await _open_rock_smash_world()
	var world: Gen2WorldAPI = _world_screen._world
	var rock: Gen2WorldObject = world.objects[ROCK_OBJECT_INDEX]
	rock.event_flag = ROCK_EVENT_FLAG
	assert_true(bool(world.smash_object(ROCK_OBJECT_INDEX).get("ok", false)))
	assert_true(world.state.is_event_flag_active(ROCK_EVENT_FLAG))

	# The cache's own record still carries -1, so the map data needs the flag put
	# on it the way the cartridge's does, before the load that reads it:
	# `ReadObjectEvents` is the only thing that tests an object's event flag.
	world.current_map.events["objects"][ROCK_OBJECT_INDEX]["event_flag"] = ROCK_EVENT_FLAG
	world.reload_current_map()
	assert_null(world.object_at(ROCK_CELL), "a set event flag keeps it hidden")


## TryTileCollisionEvent's five field-move branches: facing a cut tree and
## pressing A asks before cutting, which is the way the cartridge teaches every
## one of these. The party submenu is the other way in and both end in the same
## staged request.
func test_facing_a_cut_tree_asks_before_cutting() -> void:
	await _open_world()
	var world: Gen2WorldAPI = _world_screen._world
	assert_false(world.can_walk_to(TREE_CELL))

	var opened: Array = world.interact()
	assert_eq(opened[0]["status"], &"waiting", JSON.stringify(opened))
	assert_string_contains(String(opened[0]["event"]["text"]), "This tree can be")
	assert_string_contains(String(opened[0]["event"]["text"]), "Want to use CUT?")

	var asked: Array = world.run_event_queue(true)
	assert_eq(asked[0]["event"]["type"], &"choice", JSON.stringify(asked))
	_world_screen._show_script_results(world.choose_script_input(0))
	assert_eq(_shown_text(), "TESTMON used CUT!")
	# Script_Cut still only writes the block after UseCutText.
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)
	_world_screen._acknowledge_field_move_text()
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE_CUT)
	assert_true(world.can_walk_to(TREE_CELL))


## `iffalse .declined` is closetext and end: no is no, and nothing is staged.
func test_declining_the_cut_prompt_leaves_the_tree_standing() -> void:
	await _open_world()
	var world: Gen2WorldAPI = _world_screen._world
	world.interact()
	world.run_event_queue(true)
	var declined: Array = world.choose_script_input(1)
	assert_eq(declined[0]["status"], &"complete", JSON.stringify(declined))
	assert_true(world.pending_cut().is_empty())
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)


## TryCutOW checks CheckPartyMove and then the badge, and a failure of either
## reaches CantCutScript, whose _CanCutText says the tree could be cut without
## offering to. There is no yes/no behind it.
func test_a_cut_tree_without_the_badge_only_reports_that_it_can_be_cut() -> void:
	await _open_world(false)
	var world: Gen2WorldAPI = _world_screen._world
	var opened: Array = world.interact()
	assert_eq(String(opened[0]["event"]["text"]), Gen2WorldScriptRunner.CUT_CAN_TEXT)
	var after: Array = world.run_event_queue(true)
	assert_eq(after[0]["status"], &"complete", JSON.stringify(after))
	assert_eq(world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)


## The same branch reached without the move at all, which is CheckPartyMove
## failing first.
func test_a_cut_tree_without_the_move_reports_the_same_text() -> void:
	await _open_world(true, Gen2WorldFieldMove.MOVE_SURF, Gen2WorldFieldMove.BADGE_HIVE)
	var opened: Array = _world_screen._world.interact()
	assert_eq(String(opened[0]["event"]["text"]), Gen2WorldScriptRunner.CUT_CAN_TEXT)


## `.headbutt` is CheckPartyMove and nothing else, and its failure is
## `.noevent`: no text, no choice, nothing at all.
func test_facing_a_headbutt_tree_asks_and_without_the_move_says_nothing() -> void:
	await _open_headbutt_world()
	var world: Gen2WorldAPI = _world_screen._world
	var opened: Array = world.interact()
	assert_string_contains(String(opened[0]["event"]["text"]), "Want to HEADBUTT")
	var asked: Array = world.run_event_queue(true)
	assert_eq(asked[0]["event"]["type"], &"choice")

	await _open_world(true, Gen2WorldFieldMove.MOVE_CUT, Gen2WorldFieldMove.BADGE_HIVE,
		HEADBUTT_STAND_CELL)
	var silent: Array = _world_screen._world.interact()
	assert_eq(silent[0]["status"], &"complete", JSON.stringify(silent))
	assert_eq(
		silent[0]["events"], [],
		"TryHeadbuttOW answers no carry, so the player event ends with nothing shown"
	)


## `.surf` is the fallback branch every other tile reaches, and it is silent on
## every failure: no badge, no move and no water each end the player event with
## nothing shown.
func test_facing_water_asks_to_surf_and_is_silent_without_the_badge() -> void:
	await _open_surf_world()
	var world: Gen2WorldAPI = _world_screen._world
	var opened: Array = world.interact()
	assert_eq(String(opened[0]["event"]["text"]), Gen2WorldScriptRunner.SURF_ASK_TEXT)
	_world_screen._show_script_results(world.run_event_queue(true))
	_world_screen._show_script_results(world.choose_script_input(0))
	assert_eq(_shown_text(), "TESTMON used SURF!")
	_world_screen._acknowledge_field_move_text()
	assert_eq(world.movement_mode, Gen2WorldAPI.MOVEMENT_SURF)

	await _open_surf_world(false)
	var quiet: Array = _world_screen._world.interact()
	assert_eq(quiet[0]["status"], &"complete", JSON.stringify(quiet))
	assert_eq(
		quiet[0]["events"], [],
		"TrySurfOW quits with no carry when the badge is missing"
	)


## A wall is not a surf prompt, and neither is anything else that is not water:
## `.surf` reads GetTilePermission before it reads anything else.
func test_facing_a_plain_wall_offers_no_prompt_at_all() -> void:
	await _open_world()
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(_world_screen._world.interact(), [])


## TryWhirlpoolOW checks the party, the badge and then TryWhirlpoolMenu, and any
## of the three failing reaches Script_MightyWhirlpool rather than an offer.
func test_facing_a_whirlpool_asks_before_dispelling_it() -> void:
	await _open_whirlpool_world()
	var world: Gen2WorldAPI = _world_screen._world
	var opened: Array = world.interact()
	assert_eq(String(opened[0]["event"]["text"]), Gen2WorldScriptRunner.WHIRLPOOL_ASK_TEXT)
	world.run_event_queue(true)
	_world_screen._show_script_results(world.choose_script_input(0))
	assert_eq(_shown_text(), "TESTMON used WHIRLPOOL!")
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL)
	_world_screen._acknowledge_field_move_text()
	assert_eq(world.block_at(WHIRLPOOL_BLOCK.x, WHIRLPOOL_BLOCK.y), BLOCK_WHIRLPOOL_GONE)


func test_a_whirlpool_without_the_badge_reports_that_a_mon_may_pass_it() -> void:
	await _open_whirlpool_world(false)
	var opened: Array = _world_screen._world.interact()
	assert_eq(
		String(opened[0]["event"]["text"]), Gen2WorldScriptRunner.WHIRLPOOL_MAY_PASS_TEXT
	)
	var after: Array = _world_screen._world.run_event_queue(true)
	assert_eq(after[0]["status"], &"complete", "no yes/no follows the refusal")


## CheckMapCanWaterfall is two tests and no more: the facing must be up and the
## tile above must be a waterfall. Facing it from the side is the refusal, not
## the offer, which is why the prompt carries the facing question and the badge
## does not answer it.
func test_facing_a_waterfall_asks_only_when_facing_up() -> void:
	await _open_waterfall_world()
	var world: Gen2WorldAPI = _world_screen._world
	var opened: Array = world.interact()
	assert_eq(String(opened[0]["event"]["text"]), Gen2WorldScriptRunner.WATERFALL_ASK_TEXT)
	world.run_event_queue(true)
	_world_screen._show_script_results(world.choose_script_input(0))
	assert_eq(_shown_text(), "TESTMON used WATERFALL!")
	_world_screen._acknowledge_field_move_text()
	# The climb runs the whole column and ends on the first cell above it that
	# is not a waterfall, which is one past the top of the two.
	assert_eq(world.player_cell, WATERFALL_TOP_CELL + Vector2i.UP)


func test_a_waterfall_without_the_badge_reports_a_huge_waterfall() -> void:
	await _open_waterfall_world(false)
	var opened: Array = _world_screen._world.interact()
	assert_eq(
		String(opened[0]["event"]["text"]), Gen2WorldScriptRunner.WATERFALL_HUGE_TEXT
	)


func _open_waterfall_world(badge: bool = true) -> void:
	await _open_world(
		badge, Gen2WorldFieldMove.MOVE_WATERFALL, Gen2WorldFieldMove.BADGE_RISING,
		WATERFALL_STAND_CELL
	)
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_UP
	_world_screen._world.movement_mode = Gen2WorldAPI.MOVEMENT_SURF


## `InitPartyMenuWithCancel`: the row after the last member answers A with the
## same carry a B press sets, so the menu closes from either.
func test_the_cancel_row_closes_the_menu_the_way_b_does() -> void:
	await _open_world()
	var party: Gen2PartyScreen = await _open_party()
	var members: int = _world_screen._embedded_party_save().party.size()
	for _step: int in members:
		party.handle_button(Gen2Button.DOWN)
	assert_true(bool(party.submenu_snapshot()["on_cancel"]), "the cursor is past the party")
	party.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_null(_world_screen._party_host)


## A refusal stands in the menu's own bottom box and `JoyWaitAorB` holds there:
## a direction does not answer it and the next A or B does nothing but clear it.
func test_a_refusal_holds_the_menu_until_a_or_b() -> void:
	await _open_world()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	## STATS, the first row this project does not act on.
	party.handle_button(Gen2Button.DOWN)
	party.handle_button(Gen2Button.A)
	var refused: Dictionary = party.submenu_snapshot()
	assert_ne(String(refused["message"]), "", "the refusal is in the box")

	assert_false(party.handle_button(Gen2Button.DOWN), "a direction is not one of the two")
	assert_eq(int(party.submenu_snapshot()["cursor"]), int(refused["cursor"]))
	assert_true(party.handle_button(Gen2Button.B))
	assert_eq(String(party.submenu_snapshot()["message"]), "")
	assert_true(bool(party.submenu_snapshot()["open"]), "and the submenu is still up")


## A mod's party-member rows land after every cartridge action and before CANCEL,
## which is the way out of the box. The label is asked per slot, so a mod can say
## something different about the one it already owns.
func test_a_mod_party_row_lands_after_the_cartridge_actions() -> void:
	await _open_world()
	var chosen: Array = []
	assert_true(bool(Gen2ModHost.instance().register_party_member_menu(&"follower", {
		"label": func(slot: int) -> String: return "FOLLOWING" if slot == 2 else "FOLLOW",
		"handler": func(slot: int) -> void: chosen.append(slot),
	}).get("ok", false)))
	## A second mod appends behind the first rather than replacing it.
	assert_true(bool(Gen2ModHost.instance().register_party_member_menu(&"pet", {
		"label": func(_slot: int) -> String: return "PET",
		"handler": func(_slot: int) -> void: pass,
	}).get("ok", false)))

	var party: Gen2PartyScreen = await _open_party()
	party.handle_button(Gen2Button.A)
	assert_eq(
		_labels(party.submenu_snapshot()["items"]),
		["CUT", "STATS", "SWITCH", "MOVE", "ITEM", "FOLLOW", "PET", "CANCEL"]
	)

	## Choosing it calls the mod's handler with the ONE-based slot and closes the
	## menu, the way a field move does.
	for _step: int in 5:
		party.handle_button(Gen2Button.DOWN)
	party.handle_button(Gen2Button.A)
	assert_eq(chosen, [1])
	await get_tree().process_frame
	assert_null(_world_screen._party_host)


## An egg has nothing to follow, and a battle's party list is a switch: neither
## is offered a mod row.
func test_an_egg_and_a_battle_list_are_offered_no_mod_row() -> void:
	await _open_world()
	assert_true(bool(Gen2ModHost.instance().register_party_member_menu(&"follower", {
		"label": func(_slot: int) -> String: return "FOLLOW",
		"handler": func(_slot: int) -> void: pass,
	}).get("ok", false)))
	var egg := Gen2SaveMon.new()
	egg.is_egg = true
	assert_eq(
		_labels(Gen2PartyScreen.submenu_items_for(_data, egg, 1)),
		["STATS", "SWITCH", "CANCEL"]
	)
	var mon: Gen2SaveMon = Gen2SaveStore.create_development_save(_data, 0).party[0]
	assert_false(
		_labels(Gen2PartyScreen.submenu_items_for(_data, mon, 1, true)).has("FOLLOW"),
		"a battle party list"
	)
	assert_true(_labels(Gen2PartyScreen.submenu_items_for(_data, mon, 1)).has("FOLLOW"))


## A row is registered by name with two Callables, and both are checked here
## rather than at the press.
func test_a_party_row_needs_both_callables_and_a_free_name() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var label: Callable = func(_slot: int) -> String: return "X"
	assert_eq(
		host.register_party_member_menu(&"a", {"label": label})["reason"],
		&"party_menu_entry_missing_callable"
	)
	assert_true(bool(host.register_party_member_menu(
		&"a", {"label": label, "handler": func(_slot: int) -> void: pass}
	).get("ok", false)))
	assert_eq(
		host.register_party_member_menu(
			&"a", {"label": label, "handler": func(_slot: int) -> void: pass}
		)["reason"],
		&"duplicate_party_menu_entry"
	)
