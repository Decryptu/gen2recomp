extends GutTest

## The motion callbacks `DoBattleAnimFrame` dispatches
## (engine/battle_anims/functions.asm) and the five helpers they are built from.
##
## Objects are built by hand rather than spawned by a script, because what is
## worth checking here is the arithmetic: which byte a state writes, where it
## wraps, and which of the source's own dead branches stays dead.
## `tools/checks/battle_anims.gd` is the counterpart that runs all eighty
## against real cartridge data.

const BASE: int = 0x4000
const RET: int = 0xFF

var _player: Gen2BattleAnimPlayer = null


func before_each() -> void:
	_player = _make_player()


## A player with the real sine table behind it and nothing else: no object is
## spawned, so the pool stays empty and the callbacks are called directly.
func _make_player(enemy_turn: bool = false) -> Gen2BattleAnimPlayer:
	var sine := PackedByteArray()
	for value: int in RomLayout.BATTLE_ANIM_SINE_WAVE:
		sine.append(value)
	var data: Gen2BattleAnimData = Gen2BattleAnimData.create({
		&"scripts": {
			"bank": 0x32, "address": BASE, "count": 1,
			"data": PackedByteArray([(BASE + 2) & 0xFF, (BASE + 2) >> 8, RET]),
		},
		&"objects": {"bank": 0x33, "address": BASE, "count": 0, "data": PackedByteArray()},
		&"framesets": {"bank": 0x33, "address": BASE, "count": 0, "data": PackedByteArray()},
		&"oam_sets": {"bank": 0x33, "address": BASE, "count": 0, "data": PackedByteArray()},
	}, [], sine)
	return Gen2BattleAnimPlayer.create(data, 0, enemy_turn)


## One object with a chosen callback, at a chosen place, with a chosen parameter.
func _object(function: int, x: int = 0x40, y: int = 0x40, param: int = 0) -> Gen2BattleAnimObject:
	return Gen2BattleAnimObject.create(
		1, {&"flags": 0x00, &"y_fix": 0x90, &"frameset": 0x10, &"function": function,
			&"palette": 0x02, &"gfx": 0x01},
		0, x, y, param
	)


func _run(object: Gen2BattleAnimObject) -> void:
	assert_true(Gen2BattleAnimFunctions.run(_player, object))


# ---------------------------------------------------------------- helpers ----

## `BattleAnim_Sine` at the quarter turn is the whole amplitude, because
## `BattleAnimSineWave`'s sixteenth entry is $0100 and not $00ff. An eight-bit
## re-derivation of the table is short by one here and everywhere it is scaled.
func test_the_quarter_turn_is_the_whole_amplitude() -> void:
	var object: Gen2BattleAnimObject = _object(0x03, 0x40, 0x40, 0x50)
	object.jumptable_index = 1
	object.var1 = 0x10
	_run(object)
	assert_eq(object.y_offset, 0x50, "sin(pi/2) * $50 is $50, not $4f")


## The second half of the turn is the first half negated, which is what makes an
## offset a signed byte.
func test_the_second_half_of_the_turn_is_negative() -> void:
	var rising: Gen2BattleAnimObject = _object(0x03, 0x40, 0x40, 0x40)
	rising.jumptable_index = 1
	rising.var1 = 0x08
	_run(rising)

	var falling: Gen2BattleAnimObject = _object(0x03, 0x40, 0x40, 0x40)
	falling.jumptable_index = 1
	falling.var1 = 0x28
	_run(falling)
	assert_eq(falling.y_offset, (-rising.y_offset) & 0xFF)


## `BattleAnim_Cosine` is the sine a quarter turn on, so a cosine at zero is the
## amplitude and the two offsets are a quarter apart.
func test_the_cosine_leads_the_sine_by_a_quarter_turn() -> void:
	var object: Gen2BattleAnimObject = _object(0x03, 0x40, 0x40, 0x30)
	object.jumptable_index = 1
	object.var1 = 0x00
	_run(object)
	assert_eq(object.y_offset, 0x00)
	assert_eq(object.x_offset, 0x30)


## `BattleAnim_StepToTarget`'s vertical half is a `dec`/`jr nz` loop, so a low
## nybble under two runs it 256 times and the object does not rise at all.
func test_a_step_of_one_moves_sideways_and_not_up() -> void:
	var object: Gen2BattleAnimObject = _object(0x02, 0x40, 0x40, 0x01)
	_run(object)
	assert_eq(object.x, 0x41)
	assert_eq(object.y, 0x40, "256 decrements are no decrement at all")

	var stepped: Gen2BattleAnimObject = _object(0x02, 0x40, 0x40, 0x04)
	_run(stepped)
	assert_eq(stepped.x, 0x44)
	assert_eq(stepped.y, 0x3E)


## Coordinates are single cartridge bytes, and several animations walk an object
## off one side and rely on the wrap.
func test_a_coordinate_wraps_rather_than_clamping() -> void:
	var object: Gen2BattleAnimObject = _object(0x3B, 0xF8, 0x40, 0x10)  # Agility
	_run(object)
	assert_eq(object.x, 0x08)


# -------------------------------------------------------------- callbacks ----

## `BattleAnimFunc_Null` is not a no-op: its second state deletes the object,
## which is how `anim_incobj` retires the sixty-two rows that use it.
func test_the_null_callback_deletes_on_its_second_state() -> void:
	var object: Gen2BattleAnimObject = _object(0x00)
	_run(object)
	assert_true(object.active())
	object.jumptable_index = 1
	_run(object)
	assert_false(object.active())


## Bit 7 of `BattleAnimFunc_MoveInCircle`'s parameter starts the object on the
## far side of the circle and is then cleared, since the rest is the radius.
func test_move_in_circle_reads_bit_seven_as_a_starting_position() -> void:
	var near: Gen2BattleAnimObject = _object(0x03, 0x40, 0x40, 0x20)
	_run(near)
	assert_eq(near.var1, 0x01, "started at zero and stepped one")
	assert_eq(near.param, 0x20)

	var far: Gen2BattleAnimObject = _object(0x03, 0x40, 0x40, 0xA0)
	_run(far)
	assert_eq(far.var1, 0x21, "started half a turn round")
	assert_eq(far.param, 0x20, "the radius is what is left of the byte")


## `BattleAnimFunc_Drop`'s parameter is how much height each bounce loses, and
## the object goes when it has none left.
func test_drop_loses_height_each_bounce_and_then_goes() -> void:
	var object: Gen2BattleAnimObject = _object(0x07, 0x40, 0x40, 0x40)
	_run(object)
	assert_eq(object.var1, 0x31)
	assert_eq(object.var2, 0x48)

	object.var1 = 0x3F
	_run(object)
	assert_eq(object.var1, 0x20, "the bounce restarts")
	assert_eq(object.var2, 0x08, "and is $40 shorter")

	object.var1 = 0x3F
	_run(object)
	assert_false(object.active(), "a bounce it cannot afford ends the object")


## `BattleAnimFunc_PokeBall`'s settling writes the masked value back, so a var1
## of $20 lands on zero rather than keeping its high bit.
func test_the_ball_settles_by_zeroing_its_own_counter() -> void:
	var object: Gen2BattleAnimObject = _object(0x12)
	object.jumptable_index = 4
	object.var1 = 0x21
	object.var2 = 0x10
	_run(object)
	assert_eq(object.var1, 0x00)
	assert_eq(object.var2, 0x0C)


## `GetBallAnimPal` colours a thrown ball off `wCurItem`, and an item that is not
## a ball falls out on `BallColors`' own `-1` row.
func test_the_thrown_ball_takes_its_own_colour() -> void:
	_player.cur_item = 0x02  # ULTRA_BALL
	var ultra: Gen2BattleAnimObject = _object(0x12)
	_run(ultra)
	assert_eq(ultra.palette, 3, "PAL_BATTLE_OB_YELLOW")

	_player.cur_item = 0x14  # a potion, which is in no row
	var other: Gen2BattleAnimObject = _object(0x12)
	_run(other)
	assert_eq(other.palette, 2, "the terminator's PAL_BATTLE_OB_GRAY")


## `BattleAnimFunc_Sound` mirrors its angle on the enemy's turn, which is one of
## only two places a callback reads `hBattleTurn`.
func test_a_sound_wave_is_mirrored_on_the_enemys_turn() -> void:
	var player: Gen2BattleAnimObject = _object(0x21, 0x40, 0x40, 0x02)
	_run(player)
	assert_eq(player.param, 0x02)

	_player = _make_player(true)
	var enemy: Gen2BattleAnimObject = _object(0x21, 0x40, 0x40, 0x02)
	_run(enemy)
	assert_eq(enemy.param, 0x00, "$ff - param + 3")


## `BattleAnimFunc_Surf` is the one callback that reaches the raster: it opens a
## scanline window over `rSCY` and hands it back when the wave has crossed.
func test_surf_opens_and_closes_its_scanline_window() -> void:
	var object: Gen2BattleAnimObject = _object(0x0D, 0x40, 0x60, 0x30)
	_run(object)
	assert_eq(_player.background().lcdc_pointer, Gen2BattleAnimFunctions.LCDC_POINTER_SCY)
	assert_eq(_player.background().ly_override_start, 0x58)
	assert_eq(_player.background().ly_override_end, 0x5E)

	object.jumptable_index = 3
	object.y = 0x70
	_run(object)
	assert_eq(_player.background().lcdc_pointer, 0)
	assert_eq(_player.background().ly_override_end, 0)
	assert_false(object.active())


## `BattleAnimFunc_SkyAttack` flashes `wOBP0`, which the Color hardware never
## draws from. The write is kept because it is the whole of that state.
func test_sky_attack_cycles_the_dmg_object_palette() -> void:
	var object: Gen2BattleAnimObject = _object(0x32)
	_run(object)
	assert_eq(object.var1, 0xF0, "the player's side")
	_run(object)
	assert_eq(_player.background().obp0, 0xF0)
	_run(object)
	assert_eq(_player.background().obp0, 0xF0)
	_run(object)
	assert_eq(_player.background().obp0, 0xA0, "$aa masked by the side's own byte")


## `BattleAnimFunc_RockSmash` writes the frameset straight into the struct rather
## than through `ReinitBattleAnimFrameset`, so the frame it is on is not reset.
func test_rock_smash_swaps_its_frameset_without_restarting_it() -> void:
	var object: Gen2BattleAnimObject = _object(0x4E, 0x40, 0x40, 0x40)
	object.frame = 0x03
	object.duration = 0x05
	_run(object)
	assert_eq(object.frameset, Gen2BattleAnimFunctions.FRAMESET_BIG_ROCK + 1)
	assert_eq(object.frame, 0x03)
	assert_eq(object.duration, 0x05)


## `BattleAnimFunc_PresentSmokescreen` masks with $1f and then compares against
## $20, which can never match, so the halving under it is unreachable and the
## bounce keeps its height. The cartridge's own dead branch.
func test_the_present_bounce_never_loses_its_height() -> void:
	var object: Gen2BattleAnimObject = _object(0x35, 0x40, 0x40)
	_run(object)
	assert_eq(object.var1, 0x30)
	assert_eq(object.var2, 0x10)
	for _frame: int in 16:
		_run(object)
	assert_eq(object.var2, 0x10, "the srl below the cp is never reached")


## `BattleAnim_ScatterHorizontal` steps a leaf sideways by one of three amounts,
## and bit 7 of the parameter is which way.
func test_a_leaf_scatters_the_way_its_parameter_says() -> void:
	var right: Gen2BattleAnimObject = _object(0x0B, 0x40, 0x40, 0x10)
	right.jumptable_index = 1
	right.var1 = 0x40
	_run(right)
	assert_eq(right.x, 0x42, "$200 over a byte and a half is two pixels")

	var left: Gen2BattleAnimObject = _object(0x0B, 0x40, 0x40, 0x90)
	left.jumptable_index = 1
	left.var1 = 0x40
	_run(left)
	assert_eq(left.x, 0x3E)


## The importer refuses an object row naming a callback past the jumptable, so
## only a hand-built object reaches this, and it is reported rather than run.
func test_a_callback_past_the_jumptable_is_refused() -> void:
	var object: Gen2BattleAnimObject = _object(Gen2BattleAnimImporter.FUNCTION_COUNT)
	assert_false(Gen2BattleAnimFunctions.run(_player, object))
	assert_true(object.active())
