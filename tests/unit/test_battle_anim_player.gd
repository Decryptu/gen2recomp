extends GutTest

## `RunBattleAnimScript`'s frame loop over the object pool and the tile window
## (engine/battle_anims/anim_commands.asm, core.asm).
##
## Built by hand like the object's own tests, so the pool's limits and the
## cartridge's own `BattleAnimCmd_ClearObjs` bug are checked against the counts
## rather than against whatever an animation happens to spawn.

const BASE: int = 0x4000
## Where a hand-written script body starts, just past a one-entry pointer table.
const BODY: int = BASE + 2

## `anim_obj` naming object row 0 at (80, 64) with parameter 0.
const SPAWN: Array = [0xD0, 0x00, 0x50, 0x40, 0x00]
const RET: Array = [0xFF]


func _bytes(values: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for value: int in values:
		out.append(value & 0xFF)
	return out


## A data set whose object rows all use frameset 0, callback 0 and graphics 1,
## and whose one frameset draws OAM set 0 forever.
func _data(body: Array, rows: int = 2, function: int = 0) -> Gen2BattleAnimData:
	var object_body: Array = []
	for row: int in rows:
		object_body.append_array([0x00, 0x90, 0x00, function, 0x02, 0x01])

	var frameset_at: int = BASE + 2
	var sprite_at: int = BASE + RomLayout.BATTLE_ANIM_OAM_SET_SIZE
	return Gen2BattleAnimData.create({
		&"scripts": {
			"bank": 0x32, "address": BASE, "count": 1,
			"data": _bytes([BODY & 0xFF, BODY >> 8] + body),
		},
		&"objects": {
			"bank": 0x33, "address": BASE, "count": rows, "data": _bytes(object_body),
		},
		&"framesets": {
			"bank": 0x33, "address": BASE, "count": 1,
			"data": _bytes([frameset_at & 0xFF, frameset_at >> 8,
				0x00, 0x0F, Gen2BattleAnimObject.OAM_END]),
		},
		&"oam_sets": {
			"bank": 0x33, "address": BASE, "count": 1,
			"data": _bytes([0x00, 0x01, sprite_at & 0xFF, sprite_at >> 8,
				0xF8, 0xF8, 0x00, 0x00]),
		},
	}, [
		{"tiles": 0, "sheet": false},
		{"tiles": 4, "sheet": true},
		{"tiles": 3, "sheet": true},
	])


func _player(body: Array, rows: int = 2, function: int = 0) -> Gen2BattleAnimPlayer:
	return Gen2BattleAnimPlayer.create(_data(body, rows, function), 0)


## `BattleAnimCmd_BattlerGFX_2Row` ($da) puts two rows of each battler's own
## picture into the top of the window, so an effect can lift a battler off the
## tilemap and move it as objects. Three effects do, `BattleBGEffect_Tackle`
## among them, and until the command existed they drew whatever sheet happened
## to sit at window tile zero.
func test_battler_graphics_put_both_pictures_at_the_top_of_the_window() -> void:
	var player: Gen2BattleAnimPlayer = _player([0xDA] + RET)
	player.advance_frame()
	var window: Array = player.tiles()

	# `($80 - 6 * 2 - 7 * 2) - BATTLEANIM_BASE_TILE` and `($80 - 6 * 2) - ...`.
	var enemy_at: int = 53
	var player_at: int = 67
	# The enemy's bottom two rows, a column at a time, stepping the source by the
	# picture's own height.
	assert_eq(window[enemy_at], {"battler_tile": 0x05})
	assert_eq(window[enemy_at + 1], {"battler_tile": 0x06})
	assert_eq(window[enemy_at + 2], {"battler_tile": 0x0C})
	assert_eq(window[enemy_at + 13], {"battler_tile": 0x30})
	# The player's top two, from its own base tile.
	assert_eq(window[player_at], {"battler_tile": 0x31})
	assert_eq(window[player_at + 1], {"battler_tile": 0x32})
	assert_eq(window[player_at + 11], {"battler_tile": 0x50})
	# It fills the window exactly to the top and no further.
	assert_eq(window.size(), Gen2BattleAnimPlayer.MAX_TILES)


## The one-row variant copies the enemy's last row and the player's first, and
## sits seven tiles further up the window.
func test_the_one_row_variant_copies_a_row_of_each() -> void:
	var player: Gen2BattleAnimPlayer = _player([0xD9] + RET)
	player.advance_frame()
	var window: Array = player.tiles()
	assert_eq(window[66], {"battler_tile": 0x06})
	assert_eq(window[72], {"battler_tile": 0x30})
	assert_eq(window[73], {"battler_tile": 0x31})
	assert_eq(window[78], {"battler_tile": 0x4F})


## `anim_1gfx` claims the front of the tile dict, so a battler-graphics command
## behind it takes the next two slots rather than overwriting it.
func test_battler_graphics_take_the_first_free_dict_slot() -> void:
	var player: Gen2BattleAnimPlayer = _player([0xD1, 0x01, 0xDA] + RET)
	player.advance_frame()
	var window: Array = player.tiles()
	assert_eq(window[0], {"gfx": 1, "tile": 0})
	assert_eq(window[53], {"battler_tile": 0x05})


## Ten spawns fill the pool and an eleventh finds no slot, which is
## `QueueBattleAnimation` returning carry and the command doing nothing with it.
func test_the_pool_holds_ten_objects_and_refuses_an_eleventh() -> void:
	var body: Array = []
	for spawn: int in 11:
		body.append_array(SPAWN)
	body.append_array([0x01])  # anim_wait 1, so the spawns share one frame
	body.append_array(RET)

	var player: Gen2BattleAnimPlayer = _player(body)
	player.advance_frame()
	assert_eq(player.objects().size(), Gen2BattleAnimPlayer.MAX_OBJECTS)


## Every object carries a different index, which is what `anim_incobj` and
## `anim_setobj` name it by. The counter is never reset, so it counts on through
## the animation.
func test_each_object_gets_the_next_index() -> void:
	var player: Gen2BattleAnimPlayer = _player(SPAWN + SPAWN + [0x01] + RET)
	player.advance_frame()
	var objects: Array = player.objects()
	assert_eq(objects.size(), 2)
	assert_eq((objects[0] as Gen2BattleAnimObject).index, 1)
	assert_eq((objects[1] as Gen2BattleAnimObject).index, 2)


## `BattleAnimCmd_ClearObjs` counts `$a0` bytes over structs that are `$18` each,
## so it stops inside the seventh and the last three objects survive. The
## cartridge's own bug, reproduced.
func test_clearing_the_objects_leaves_the_last_three_standing() -> void:
	var body: Array = []
	for spawn: int in Gen2BattleAnimPlayer.MAX_OBJECTS:
		body.append_array(SPAWN)
	body.append_array([0x01])
	body.append_array([0xE5])  # anim_clearobjs
	body.append_array([0x01])
	body.append_array(RET)

	var player: Gen2BattleAnimPlayer = _player(body)
	player.advance_frame()
	assert_eq(player.objects().size(), Gen2BattleAnimPlayer.MAX_OBJECTS)
	# The wait costs its own frame before the clear runs on the one after it.
	player.advance_frame()
	player.advance_frame()
	assert_eq(player.objects().size(), 3, "the seventh struct is only part cleared")


## `anim_incobj` finds an object by its index and bumps its jumptable index,
## which for a null callback is what deletes it.
func test_incobj_retires_an_object_with_the_null_callback() -> void:
	var player: Gen2BattleAnimPlayer = _player(
		SPAWN + [0x01] + [0xD6, 0x01] + [0x01] + RET
	)
	player.advance_frame()
	assert_eq(player.objects().size(), 1)
	player.advance_frame()
	player.advance_frame()
	assert_eq(
		player.objects().size(), 0,
		"BattleAnimFunc_Null's second state calls DeinitBattleAnimation"
	)


## `BattleAnim_UpdateOAM_All` tests the slot's index once, at the top of its
## loop, so the object whose own callback has just deinitialised itself still
## reaches `BattleAnimOAMUpdate` and is drawn one last time. Measured on a real
## cartridge: TACKLE's `anim_incobj 1` frees the target's two rows on the frame
## it runs and OAM still holds their sprites for that frame.
func test_an_object_that_deletes_itself_is_drawn_one_last_time() -> void:
	var player: Gen2BattleAnimPlayer = _player(
		SPAWN + [0x01] + [0xD6, 0x01] + [0x01] + RET
	)
	player.advance_frame()
	player.advance_frame()
	var before: int = player.sprites().size()
	player.advance_frame()
	assert_eq(player.objects().size(), 0, "the null callback deinitialised it")
	assert_eq(
		player.sprites().size(), before,
		"the freed slot is still drawn on the frame it was freed"
	)
	player.advance_frame()
	assert_eq(player.sprites().size(), 0, "and on no frame after it")


## `anim_setobj` writes the index rather than stepping it, and an index no object
## carries finds nothing rather than writing over slot zero.
func test_setobj_writes_the_index_and_an_unknown_one_finds_nothing() -> void:
	var player: Gen2BattleAnimPlayer = _player(
		SPAWN + [0x01] + [0xD7, 0x09, 0x05] + [0x01] + RET
	)
	player.advance_frame()
	var object: Gen2BattleAnimObject = player.objects()[0]
	player.advance_frame()
	player.advance_frame()
	assert_eq(object.jumptable_index, 0, "no object carries index 9")
	assert_true(object.active())


## `anim_2gfx` records both sheets in the tile dict in turn, so the second one's
## tiles start after the first one's.
func test_graphics_are_loaded_into_the_window_in_turn() -> void:
	# anim_2gfx 1, 2 then spawn, whose row asks for sheet 1.
	var player: Gen2BattleAnimPlayer = _player([0xD2, 0x01, 0x02] + SPAWN + [0x01] + RET)
	player.advance_frame()
	var tiles: Array = player.tiles()
	assert_eq(tiles.size(), 7, "four tiles of sheet 1 and three of sheet 2")
	assert_eq(int((tiles[0] as Dictionary)["gfx"]), 1)
	assert_eq(int((tiles[4] as Dictionary)["gfx"]), 2)
	assert_eq(int((tiles[4] as Dictionary)["tile"]), 0)

	var object: Gen2BattleAnimObject = player.objects()[0]
	assert_eq(object.tile_id, 0, "sheet 1 was loaded first, so its offset is zero")


## A sheet the animation never loaded answers offset zero rather than nothing,
## which draws whatever is at the start of the window.
func test_an_unloaded_sheet_reads_as_the_start_of_the_window() -> void:
	var player: Gen2BattleAnimPlayer = _player([0xD1, 0x02] + SPAWN + [0x01] + RET)
	player.advance_frame()
	assert_eq((player.objects()[0] as Gen2BattleAnimObject).tile_id, 0)


## The shadow buffer holds forty sprites and no more; the objects queued after it
## are simply not drawn that frame.
func test_the_shadow_buffer_stops_at_forty_sprites() -> void:
	var body: Array = []
	for spawn: int in Gen2BattleAnimPlayer.MAX_OBJECTS:
		body.append_array(SPAWN)
	body.append_array([0x01])
	body.append_array(RET)

	var player: Gen2BattleAnimPlayer = _player(body)
	player.advance_frame()
	assert_eq(player.objects().size(), Gen2BattleAnimPlayer.MAX_OBJECTS)
	assert_lte(player.sprites().size(), Gen2BattleAnimPlayer.MAX_SPRITES)
	assert_eq(player.sprites().size(), Gen2BattleAnimPlayer.MAX_OBJECTS)


## `BattleAnim_ClearOAM` normally wipes the buffer; after `anim_keepsprites` it
## leaves the sprites and moves every one onto `PAL_BATTLE_OB_ENEMY` instead.
func test_keepsprites_keeps_the_sprites_and_takes_their_colour() -> void:
	var plain: Gen2BattleAnimPlayer = _player(SPAWN + [0x01] + RET)
	while plain.advance_frame():
		pass
	assert_eq(plain.sprites(), [], "the buffer is wiped at the end")

	var kept: Gen2BattleAnimPlayer = _player(SPAWN + [0xF4] + [0x01] + RET)
	while kept.advance_frame():
		pass
	assert_eq(kept.sprites().size(), 1)
	assert_eq(
		int((kept.sprites()[0] as Dictionary)["attributes"])
			& (Gen2BattleAnimObject.OAM_PALETTE | Gen2BattleAnimObject.OAM_BANK1),
		0,
		"PAL_BATTLE_OB_ENEMY is zero, which is what the source asserts"
	)


## A callback or an effect past the end of its own table is reported rather than
## passed over. The importer refuses such an object row and no cartridge script
## names such an effect, so only hand-built data reaches either.
func test_a_callback_or_effect_past_its_table_is_reported() -> void:
	var unknown: int = Gen2BattleAnimBgEffects.EFFECTS_CRYSTAL.size()
	var player: Gen2BattleAnimPlayer = _player(
		SPAWN + [0xF0, unknown, 0x00, 0x00, 0x00] + [0x01] + RET,
		2, Gen2BattleAnimImporter.FUNCTION_COUNT
	)
	player.advance_frame()
	var missing: Dictionary = player.unimplemented()
	assert_eq(missing["functions"], [Gen2BattleAnimImporter.FUNCTION_COUNT])
	assert_eq(missing["bg_effects"], [unknown])

	# Callback 9 is `BattleAnimFunc_Shake` and effect $22 `BattleBGEffect_BounceDown`,
	# both built.
	var whole: Gen2BattleAnimPlayer = _player(
		SPAWN + [0xF0, 0x22, 0x00, 0x00, 0x00] + [0x01] + RET, 2, 0x09
	)
	whole.advance_frame()
	assert_eq(whole.unimplemented(), {"bg_effects": [], "functions": []})


## An animation the cache does not carry answers null rather than an empty
## player, so "not imported" and "imported and empty" stay apart.
func test_an_animation_the_cache_does_not_have_answers_null() -> void:
	assert_null(Gen2BattleAnimPlayer.create(_data(RET), 1))
	assert_null(Gen2BattleAnimPlayer.create(null, 0))
