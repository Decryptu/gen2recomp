extends GutTest

## One animation object: `battle_anim_struct`, `GetBattleAnimFrame` and
## `BattleAnimOAMUpdate` (engine/battle_anims/core.asm and helpers.asm).
##
## Everything is built by hand, so a coordinate or a flip is checked against the
## arithmetic rather than against whatever the cartridge happens to ship.

const BASE: int = 0x4000

## One `oamframe` naming OAM set 0 for six frames, then `oamdelete`.
const SIMPLE_FRAMESET: Array = [0x00, 0x06, Gen2BattleAnimObject.OAM_DELETE]

var _data: Gen2BattleAnimData = null


func before_each() -> void:
	_data = _build()


## A region: a two-byte pointer table over [param entries], then [param body]
## laid out at the addresses those pointers name.
func _region(pointers: Array, body: Array) -> Dictionary:
	var bytes := PackedByteArray()
	for pointer: int in pointers:
		bytes.append(pointer & 0xFF)
		bytes.append(pointer >> 8)
	for value: int in body:
		bytes.append(value & 0xFF)
	return {"bank": 0x33, "address": BASE, "count": pointers.size(), "data": bytes}


## A flat region with no pointer table of its own, which is what
## `BattleAnimObjects` is.
func _rows(count: int, body: Array) -> Dictionary:
	var bytes := PackedByteArray()
	for value: int in body:
		bytes.append(value & 0xFF)
	return {"bank": 0x33, "address": BASE, "count": count, "data": bytes}


## One frameset, one OAM set of two sprites and two object rows: one that never
## mirrors and one that does.
func _build(
	frameset: Array = SIMPLE_FRAMESET, sprites: Array = [], y_fix: int = 0x90
) -> Gen2BattleAnimData:
	var stream_at: int = BASE + 2
	# `dbsprite -1, -1, ...` and `dbsprite 0, -1, ...`, which emit y, x, tile,
	# attributes with the tile coordinates already multiplied out.
	var sprite_rows: Array = sprites if not sprites.is_empty() else [
		[0xF8, 0xF8, 0x00, 0x00],
		[0xF8, 0x00, 0x01, 0x00],
	]
	var sprite_at: int = BASE + RomLayout.BATTLE_ANIM_OAM_SET_SIZE
	var oam_body: Array = [0x00, sprite_rows.size(), sprite_at & 0xFF, sprite_at >> 8]
	for row: Array in sprite_rows:
		oam_body.append_array(row)

	return Gen2BattleAnimData.create({
		&"scripts": _region([BASE + 2], [0xFF]),
		&"objects": _rows(2, [
			# flags, y fix, frameset, function, palette, gfx
			0x00, 0x90, 0x00, 0x00, 0x02, 0x01,
			0x01, y_fix, 0x00, 0x00, 0x03, 0x01,
		]),
		&"framesets": _region([stream_at], frameset),
		&"oam_sets": {
			"bank": 0x33, "address": BASE, "count": 1,
			"data": _bytes(oam_body),
		},
	}, [
		{"tiles": 0, "sheet": false},
		{"tiles": 4, "sheet": true},
	])


func _bytes(values: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for value: int in values:
		out.append(value & 0xFF)
	return out


func _object(row: int = 0, x: int = 0x50, y: int = 0x40) -> Gen2BattleAnimObject:
	return Gen2BattleAnimObject.create(1, _data.object_row(row), 0, x, y, 0)


## `InitBattleAnimation` starts the frame at -1 because `GetBattleAnimFrame`
## increments before it reads, so the first draw is the frameset's first entry.
func test_a_new_object_starts_before_its_first_frame() -> void:
	var object: Gen2BattleAnimObject = _object()
	assert_eq(object.frame, 0xFF)
	assert_eq(object.duration, 0)
	assert_true(object.active())
	object.deinit()
	assert_false(object.active(), "zeroing the index is what frees the slot")


## An `oamframe`'s duration holds the same frame without advancing, and the
## frame is drawn on the step that set it as well as on the ones it counts.
func test_a_frames_duration_holds_it_without_advancing() -> void:
	var object: Gen2BattleAnimObject = _object()
	for step: int in 7:
		var update: Dictionary = object.oam_update(_data, false, 1)
		assert_eq((update["sprites"] as Array).size(), 2, "step %d draws" % step)
		assert_eq(object.frame, 0, "step %d is still the first frame" % step)
	# The seventh step spent the last of the duration, so the eighth reads on
	# into the `oamdelete`.
	var last: Dictionary = object.oam_update(_data, false, 1)
	assert_true(last["deleted"])
	assert_false(object.active())


## `.repeat_last` steps back two and loops, which redraws the last real frame for
## as long as the object lives.
func test_oamend_repeats_the_last_frame_forever() -> void:
	_data = _build([0x00, 0x01, Gen2BattleAnimObject.OAM_END])
	var object: Gen2BattleAnimObject = _object()
	for step: int in 6:
		var update: Dictionary = object.oam_update(_data, false, 1)
		assert_false(bool(update["deleted"]), "step %d does not end it" % step)
		assert_eq((update["sprites"] as Array).size(), 2)
	assert_true(object.active())


## `.restart` goes back to -1, so the frameset plays from the top again.
func test_oamrestart_plays_the_frameset_again() -> void:
	_data = _build([0x00, 0x01, 0x00, 0x01, Gen2BattleAnimObject.OAM_RESTART])
	var object: Gen2BattleAnimObject = _object()
	object.oam_update(_data, false, 1)
	assert_eq(object.frame, 0)
	object.oam_update(_data, false, 1)
	object.oam_update(_data, false, 1)
	assert_eq(object.frame, 1)
	object.oam_update(_data, false, 1)
	object.oam_update(_data, false, 1)
	assert_eq(object.frame, 0, "back to the first frame rather than off the end")


## An `oamwait` draws nothing without ending the object.
func test_oamwait_skips_a_frame_without_deleting() -> void:
	_data = _build([Gen2BattleAnimObject.OAM_WAIT, 0x02, 0x00, 0x01,
		Gen2BattleAnimObject.OAM_DELETE])
	var object: Gen2BattleAnimObject = _object()
	var update: Dictionary = object.oam_update(_data, false, 1)
	assert_eq(update["sprites"], [])
	assert_false(bool(update["deleted"]))
	assert_true(object.active())


## A sprite's place is its own offset within the set, moved to the object's
## coordinates and its running offset.
func test_a_sprite_sits_at_the_objects_coordinates() -> void:
	var object: Gen2BattleAnimObject = _object(0, 0x50, 0x40)
	object.x_offset = 0x04
	object.y_offset = 0x02
	var sprites: Array = object.oam_update(_data, false, 1)["sprites"]
	assert_eq(int(sprites[0]["y"]), (0xF8 + 0x40 + 0x02) & 0xFF)
	assert_eq(int(sprites[0]["x"]), (0xF8 + 0x50 + 0x04) & 0xFF)
	assert_eq(int(sprites[1]["x"]), (0x00 + 0x50 + 0x04) & 0xFF)


## A tile id is the animation window's base, plus where the object's sheet was
## loaded, plus the set's own offset, plus the sprite's.
func test_a_tile_id_counts_from_the_animation_window() -> void:
	var object: Gen2BattleAnimObject = Gen2BattleAnimObject.create(
		1, _data.object_row(0), 6, 0x50, 0x40, 0
	)
	var sprites: Array = object.oam_update(_data, false, 1)["sprites"]
	assert_eq(int(sprites[0]["tile"]), Gen2BattleAnimObject.BASE_TILE + 6 + 0)
	assert_eq(int(sprites[1]["tile"]), Gen2BattleAnimObject.BASE_TILE + 6 + 1)


## The object's CGB palette and bank go in, its DMG palette bit is the sprite's
## own, and the three shared bits are the sprite's combined with the frame's.
func test_attributes_take_the_objects_palette_and_the_frames_flips() -> void:
	var object: Gen2BattleAnimObject = _object(0)
	var sprites: Array = object.oam_update(_data, false, 1)["sprites"]
	assert_eq(int(sprites[0]["attributes"]) & Gen2BattleAnimObject.OAM_PALETTE, 2)

	# An `oamframe` whose second byte carries the x flip one bit high.
	_data = _build([0x00, 0x06 | (Gen2BattleAnimObject.OAM_XFLIP << 1),
		Gen2BattleAnimObject.OAM_DELETE])
	var flipped: Gen2BattleAnimObject = _object(0)
	var flipped_sprites: Array = flipped.oam_update(_data, false, 1)["sprites"]
	assert_true(
		(int(flipped_sprites[0]["attributes"]) & Gen2BattleAnimObject.OAM_XFLIP) != 0,
		"the frame's flip reaches the attribute byte"
	)
	assert_eq(
		flipped.duration, 6,
		"and does not leak into the duration, which is why the macro shifts it"
	)


## A flipped sprite is mirrored about its own eight pixels before it is moved,
## which is what keeps a flipped pair in the same place as an unflipped one.
func test_a_flip_mirrors_the_sprite_about_its_own_tile() -> void:
	_data = _build([0x00, 0x06 | (Gen2BattleAnimObject.OAM_XFLIP << 1),
		Gen2BattleAnimObject.OAM_DELETE])
	var object: Gen2BattleAnimObject = _object(0, 0x50, 0x40)
	var sprites: Array = object.oam_update(_data, false, 1)["sprites"]
	assert_eq(int(sprites[0]["x"]), (-(0xF8 + 8) + 0x50) & 0xFF)
	assert_eq(int(sprites[1]["x"]), (-(0x00 + 8) + 0x50) & 0xFF)


## On the enemy's turn an object whose row asks for it is mirrored onto the other
## side: `$b4 - x`, the y fix, and the x offset negated.
func test_the_enemy_side_mirrors_the_coordinates() -> void:
	var object: Gen2BattleAnimObject = _object(1, 0x50, 0x10)
	object.x_offset = 0x04
	var sprites: Array = object.oam_update(_data, true, 1)["sprites"]
	assert_eq(
		int(sprites[0]["x"]),
		(0xF8 + ((Gen2BattleAnimObject.ENEMY_X_MIRROR - 0x50) & 0xFF) - 0x04) & 0xFF
	)
	assert_eq(int(sprites[0]["y"]), (0xF8 + ((0x90 - 0x10) & 0xFF)) & 0xFF)


## A row that does not ask for the fix keeps its own coordinates on both sides;
## only the whole flags byte comes into play.
func test_a_row_without_the_fix_flag_is_not_mirrored() -> void:
	var object: Gen2BattleAnimObject = _object(0, 0x50, 0x40)
	var player_side: Array = object.oam_update(_data, false, 1)["sprites"]
	var enemy: Gen2BattleAnimObject = _object(0, 0x50, 0x40)
	var enemy_side: Array = enemy.oam_update(_data, true, 1)["sprites"]
	assert_eq(int(player_side[0]["x"]), int(enemy_side[0]["x"]))
	assert_eq(int(player_side[0]["y"]), int(enemy_side[0]["y"]))


## A y fix of `$ff` means "five tiles down" rather than "mirror".
func test_a_y_fix_of_ff_adds_five_tiles_instead_of_mirroring() -> void:
	_data = _build(SIMPLE_FRAMESET, [], Gen2BattleAnimObject.Y_FIX_ADD)
	var object: Gen2BattleAnimObject = _object(1, 0x50, 0x10)
	var sprites: Array = object.oam_update(_data, true, 1)["sprites"]
	assert_eq(
		int(sprites[0]["y"]),
		(0xF8 + Gen2BattleAnimObject.Y_FIX_ADD_PIXELS + 0x10) & 0xFF
	)


## Three moves are drawn a tile higher on the enemy side, and only as moves: the
## check reads `wFXAnimID`'s high byte first, so the non-move animations sharing
## those low bytes do not match.
func test_three_moves_sit_one_tile_higher_on_the_enemy_side() -> void:
	var kinesis: int = Gen2BattleAnimObject.Y_FIX_RAISED_MOVES[0]
	var raised: Gen2BattleAnimObject = _object(1, 0x50, 0x10)
	var plain: Gen2BattleAnimObject = _object(1, 0x50, 0x10)
	var raised_y: int = int(raised.oam_update(_data, true, kinesis)["sprites"][0]["y"])
	var plain_y: int = int(plain.oam_update(_data, true, 1)["sprites"][0]["y"])
	assert_eq(raised_y, (plain_y - Gen2BattleAnimObject.Y_FIX_RAISED_PIXELS) & 0xFF)

	var high: Gen2BattleAnimObject = _object(1, 0x50, 0x10)
	assert_eq(
		int(high.oam_update(_data, true, 0x100 + kinesis)["sprites"][0]["y"]), plain_y,
		"an animation past $ff is not a move and does not match"
	)
