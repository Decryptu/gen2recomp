extends GutTest

## Scene integration for Cut: the party submenu, the field-move message and the
## block change, driven through the production world screen and party screen.
##
## The shared trainer fixture is patched here rather than extended, the same way
## test_world_start_menu_screen.gd patches its Potion in: the map moves onto
## TILESET_JOHTO so the real CutTreeBlockPointers rows apply, and block $5b's
## bottom-left quadrant becomes the cut tree.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")
const BattleFixture := preload("res://tests/unit/battle_fixture.gd")

const TILESET: int = Gen2WorldFieldMove.TILESET_JOHTO
const BLOCK_COUNT: int = 0x68
const BLOCK_TREE: int = 0x5B
const BLOCK_TREE_CUT: int = 0x3C
const TREE_BLOCK: Vector2i = Vector2i(1, 1)
const TREE_CELL: Vector2i = Vector2i(2, 3)
const PLAYER_CELL: Vector2i = Vector2i(2, 2)

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
		var collision: Array = raw["collision"]
		collision[TREE_CELL.y * Fixture.MAP_WIDTH_CELLS + TREE_CELL.x] = 0x12
	RomCache.write_json(RomCache.world_maps_path(directory), maps)

	var tiles: PackedByteArray = PackedByteArray()
	tiles.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	tiles.fill(1)
	RomCache.write_indices(RomCache.world_tile_path(directory, TILESET), tiles)


## A save whose first party member knows Cut and whose second does not, so one
## submenu offers the move and the other does not.
func _save_with_cut() -> Gen2SaveData:
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(_data, 0)
	(save.party[0] as Gen2SaveMon).moves = [Gen2WorldFieldMove.MOVE_CUT, 0, 0, 0]
	(save.party[0] as Gen2SaveMon).nickname = "TESTMON"
	if save.party.size() > 1:
		(save.party[1] as Gen2SaveMon).moves = [BattleFixture.TACKLE, 0, 0, 0]
	return save


func _open_world(badge: bool = true) -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = PLAYER_CELL
	var state := Gen2WorldState.new()
	if badge:
		state.set_engine_flag(Gen2WorldState.badge_flag(
			Gen2WorldFieldMove.BADGE_HIVE, Gen2WorldState.is_crystal_profile(_data)
		))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, PLAYER_CELL, state
	)
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var save: Gen2SaveData = _save_with_cut()
	save.world = world.snapshot()
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame
	_world_screen._world.player_cell = PLAYER_CELL
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_DOWN


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
	party.handle_key(KEY_SPACE)
	var first: Dictionary = party.submenu_snapshot()
	assert_true(bool(first["open"]))
	# GetMonSubmenuItems walks the move slots first, so a field move leads.
	assert_eq(_labels(first["items"]), ["CUT", "STATS", "SWITCH", "MOVE", "ITEM", "CANCEL"])

	party.handle_key(KEY_ESCAPE)
	party.handle_key(KEY_DOWN)
	party.handle_key(KEY_SPACE)
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
	party.handle_key(KEY_SPACE)
	party.handle_key(KEY_SPACE)
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
	party.handle_key(KEY_SPACE)
	party.handle_key(KEY_SPACE)
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
	party.handle_key(KEY_SPACE)
	party.handle_key(KEY_SPACE)
	await get_tree().process_frame

	assert_eq(_shown_text(), "There's nothing to CUT here.")
	_world_screen._acknowledge_field_move_text()
	assert_true(_world_screen._world.pending_cut().is_empty())
	assert_eq(_world_screen._world.block_at(TREE_BLOCK.x, TREE_BLOCK.y), BLOCK_TREE)


func test_cancel_closes_the_submenu_before_the_party_screen() -> void:
	await _open_world()
	var party: Gen2PartyScreen = await _open_party()
	party.handle_key(KEY_SPACE)
	assert_true(bool(party.submenu_snapshot()["open"]))
	party.handle_key(KEY_ESCAPE)
	assert_false(bool(party.submenu_snapshot()["open"]))
	assert_not_null(_world_screen._party_host)
	party.handle_key(KEY_ESCAPE)
	await get_tree().process_frame
	assert_null(_world_screen._party_host)
