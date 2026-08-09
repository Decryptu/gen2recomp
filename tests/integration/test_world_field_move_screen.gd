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
		"rock_maps": [],
		"sets": [
			{"common": [], "rare": []},
			{
				"common": [{"percent": 100, "species": TREEMON_SPECIES, "level": 5}],
				"rare": [{"percent": 100, "species": TREEMON_SPECIES, "level": 5}],
			},
		],
		"asleep": {"morn": [], "day": [], "nite": []},
	}
	RomCache.write_json(RomCache.world_encounters_path(directory), encounters)

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
	var lines: PackedStringArray = PackedStringArray()
	for page: PackedStringArray in _world_screen._text_box.get("_pages"):
		lines.append_array(page)
	return " ".join(lines)


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
		world.advance_player_step(1.0)
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
	await get_tree().process_frame


func _open_headbutt_world(badge: bool = true) -> void:
	await _open_world(
		badge, Gen2WorldFieldMove.MOVE_HEADBUTT, Gen2WorldFieldMove.BADGE_HIVE,
		HEADBUTT_STAND_CELL
	)
