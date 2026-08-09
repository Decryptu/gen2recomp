class_name Gen2BattleAnimFunctions
extends RefCounted

## The eighty motion callbacks `DoBattleAnimFrame` dispatches
## (engine/battle_anims/functions.asm), plus the five helpers they are built
## from.
##
## An object row names one of these and the `anim_obj` that spawned it supplies
## the parameter it reads. Nearly every one is a `BattleAnim_AnonJumptable` over
## two to four states, which is a match on the object's own `jumptable_index`,
## and the arithmetic is on that object's coordinates, offsets and two spare
## bytes. Every value here is a cartridge byte and wraps like one.
##
## Scene-free: a callback moves an object and nothing else. The three that reach
## past the object, the ball palette, the Sky Attack `wOBP0` cycle and Surf's
## scanline window, write player state a renderer reads rather than drawing.

## `BattleAnimSineWave` has 32 samples over half a turn, so the full turn is 64
## and `BattleAnim_Sine` masks its argument with $3f.
const SINE_HALF: int = 0x20
const SINE_MASK: int = 0x3F

## `BattleAnim_Cosine` is `add %010000` and then the sine, a quarter turn on.
const COSINE_OFFSET: int = 0x10

## `BallColors` (data/battle_anims/ball_colors.asm), as item number to
## `PAL_BATTLE_OB_*`. The `-1` row is the terminator `GetBallAnimPal` falls out
## on, so an item that is not a ball is drawn grey.
const BALL_COLORS: Array = [
	[0x01, 5], [0x02, 3], [0x04, 6], [0x05, 4], [0x9D, 2], [0x9F, 7],
	[0xA0, 6], [0xA1, 6], [0xA4, 3], [0xA5, 2], [0xA6, 4],
]
const BALL_COLOR_DEFAULT: int = 2

## `BattleAnimFunc_Gust.GustOffsets`, the circle width it wobbles through.
const GUST_OFFSETS: Array[int] = [8, 6, 5, 4, 5, 6, 8, 12, 16]

## `BattleAnimFunc_Amnesia.AmnesiaOffsets`, one y offset per parameter.
const AMNESIA_OFFSETS: Array[int] = [0xEC, 0xF8, 0x00]

## `BattleAnimFunc_SkyAttack.GBCPals`. The `.SGBPals` beside it is unreachable
## here: `hSGB` is zero on the Color hardware this project draws for, which is
## the same branch every `_CGB_*` layout takes.
const SKY_ATTACK_PALS: Array[int] = [0xFF, 0xAA, 0x55, 0xAA]

## Framesets a callback names by number rather than by an object row
## (constants/battle_anim_constants.asm).
const FRAMESET_POKE_BALL_1: int = 0x09
const FRAMESET_POKE_BALL_2: int = 0x0A
const FRAMESET_POKE_BALL_3: int = 0x0B
const FRAMESET_POKE_BALL_4: int = 0x0C
const FRAMESET_POKE_BALL_5: int = 0x0D
const FRAMESET_FLAMETHROWER: int = 0x0F
const FRAMESET_EMBER: int = 0x10
const FRAMESET_BURNED: int = 0x11
const FRAMESET_RAZOR_LEAF_1: int = 0x16
const FRAMESET_RAZOR_LEAF_2: int = 0x17
const FRAMESET_BIG_ROCK: int = 0x19
const FRAMESET_SLUDGE_BUBBLE_BURST: int = 0x20
const FRAMESET_PULSING_BUBBLE: int = 0x22
const FRAMESET_MUSIC_NOTE_1: int = 0x24
const FRAMESET_WATER_GUN_2: int = 0x28
const FRAMESET_WATER_GUN_3: int = 0x29
const FRAMESET_BITE_1: int = 0x3C
const FRAMESET_BITE_2: int = 0x3D
const FRAMESET_EGG_WOBBLE: int = 0x4E
const FRAMESET_EGG_CRACKED_TOP: int = 0x4F
const FRAMESET_EGG_CRACKED_BOTTOM: int = 0x50
const FRAMESET_LEECH_SEED_2: int = 0x57
const FRAMESET_LEECH_SEED_3: int = 0x58
const FRAMESET_SOUND_1: int = 0x59
const FRAMESET_CONFUSE_RAY_1: int = 0x5D
const FRAMESET_AMNESIA_1: int = 0x63
const FRAMESET_STRING_SHOT_1: int = 0x6A
const FRAMESET_PARALYZED_FLIPPED: int = 0x6E
const FRAMESET_SPEED_LINE_1: int = 0x81
const FRAMESET_THUNDER_WAVE_EXTRA: int = 0x35

## `LOW(rSCY)`: Surf's scanline window scrolls the background vertically.
const LCDC_POINTER_SCY: int = Gen2BattleAnimBackground.LCDC_SCY


## `DoBattleAnimFrame`. Answers false when [param object]'s callback is outside
## the jumptable, which the importer's own range check makes unreachable with
## cartridge data and which a hand-built object can still ask for.
static func run(
	player: Gen2BattleAnimPlayer, object: Gen2BattleAnimObject
) -> bool:
	var data: Gen2BattleAnimData = player.data()
	match object.function:
		0x00: _null(object)
		0x01: _user_to_target(object)
		0x02: _user_to_target_disappear(object)
		0x03: _move_in_circle(data, object)
		0x04: _wave_to_target(data, object)
		0x05: _throw_to_target(data, object)
		0x06: _throw_to_target_disappear(data, object)
		0x07: _drop(data, object)
		0x08: _user_to_target_spin(data, object)
		0x09: _shake(object)
		0x0A: _fire_blast(data, object)
		0x0B: _razor_leaf(data, object)
		0x0C: _bubble(object)
		0x0D: _surf(player, data, object)
		0x0E: _sing(data, object)
		0x0F: _water_gun(data, object)
		0x10: _ember(object)
		0x11: _powder(object)
		0x12: _poke_ball(player, data, object)
		0x13: _poke_ball_blocked(player, data, object)
		0x14: _recover(data, object)
		0x15: _thunder_wave(object)
		0x16: _clamp_encore(data, object)
		0x17: _bite(data, object)
		0x18: _solar_beam(data, object)
		0x19: _gust(data, object)
		0x1A: _razor_wind(data, object)
		0x1B: _kick(data, object)
		0x1C: _absorb(object)
		0x1D: _egg(data, object)
		0x1E: _move_up(object)
		0x1F: _wrap(object)
		0x20: _leech_seed(data, object)
		0x21: _sound(player, data, object)
		0x22: _confuse_ray(data, object)
		0x23: _dizzy(data, object)
		0x24: _amnesia(object)
		0x25: _float_up(data, object)
		0x26: _dig(data, object)
		0x27: _string(object)
		0x28: _paralyzed(object)
		0x29: _spiral_descent(data, object)
		0x2A: _poison_gas(data, object)
		0x2B: _horn(data, object)
		0x2C: _needle(data, object)
		0x2D: _petal_dance(data, object)
		0x2E: _thief_payday(data, object)
		0x2F: _absorb_circle(data, object)
		0x30: _bonemerang(data, object)
		0x31: _shiny(data, object)
		0x32: _sky_attack(player, object)
		0x33: _growth_swords_dance(data, object)
		0x34: _smoke_flame_wheel(data, object)
		0x35: _present_smokescreen(data, object)
		0x36: _strength_seismic_toss(object)
		0x37: _speed_line(object)
		0x38: _sludge(object)
		0x39: _metronome_hand(data, object)
		0x3A: _metronome_sparkle_sketch(data, object)
		0x3B: _agility(object)
		0x3C: _sacred_fire(data, object)
		0x3D: _safeguard_protect(data, object)
		0x3E: _lock_on_mind_reader(data, object)
		0x3F: _spikes(data, object)
		0x40: _heal_bell_notes(data, object)
		0x41: _baton_pass(data, object)
		0x42: _conversion(data, object)
		0x43: _encore_belly_drum(data, object)
		0x44: _swagger_morning_sun(data, object)
		0x45: _hidden_power(data, object)
		0x46: _curse(object)
		0x47: _perish_song(data, object)
		0x48: _rapid_spin(object)
		0x49: _beta_pursuit(object)
		0x4A: _rain_sandstorm(object)
		0x4B: _anim_obj_b0(object)
		0x4C: _psych_up(data, object)
		0x4D: _ancient_power(data, object)
		0x4E: _rock_smash(data, object)
		0x4F: _cotton(data, object)
		_: return false
	return true


# ---------------------------------------------------------------- helpers ----

## `BattleAnim_IncAnonJumptableIndex`.
static func _inc(object: Gen2BattleAnimObject) -> void:
	object.jumptable_index = (object.jumptable_index + 1) & 0xFF


## `ReinitBattleAnimFrameset` (engine/battle_anims/helpers.asm): the frameset is
## restarted rather than continued, which is why the frame goes back to -1.
static func _reinit(object: Gen2BattleAnimObject, frameset: int) -> void:
	object.frameset = frameset & 0xFF
	object.duration = 0
	object.frame = 0xFF


## `sra`, which keeps the sign bit rather than shifting a zero in.
static func _sra(value: int) -> int:
	return ((value >> 1) | (value & 0x80)) & 0xFF


## `BattleAnim_Sine_e` and `..._Cosine_e`, the far-callable pair
## `BattleBGEffects_Sine` reaches, so a bg effect scales with the same table.
static func sine_of(data: Gen2BattleAnimData, a: int, d: int) -> int:
	return _sine(data, a, d)


static func cosine_of(data: Gen2BattleAnimData, a: int, d: int) -> int:
	return _cosine(data, a, d)


## `BattleAnim_Sine`: [code]a = d * sin(a * pi/32)[/code], as the high byte of
## the sixteen-bit product and negated over the second half of the turn.
static func _sine(data: Gen2BattleAnimData, a: int, d: int) -> int:
	var index: int = a & SINE_MASK
	if index < SINE_HALF:
		return _amplitude(data, index, d)
	return (-_amplitude(data, index & (SINE_HALF - 1), d)) & 0xFF


static func _amplitude(data: Gen2BattleAnimData, index: int, d: int) -> int:
	return (((d & 0xFF) * data.sine_word(index)) >> 8) & 0xFF


## `BattleAnim_Cosine`, which is the sine a quarter turn on. The quarter is added
## as a byte before the mask, so a parameter near $ff wraps into the first turn.
static func _cosine(data: Gen2BattleAnimData, a: int, d: int) -> int:
	return _sine(data, (a + COSINE_OFFSET) & 0xFF, d)


## `BattleAnim_StepToTarget`: the low nybble of [param a] rightwards and half of
## it upwards.
##
## The vertical half is a `dec`/`jr nz` loop, so a nybble under two runs it 256
## times rather than none and the object does not move up at all.
static func _step_to_target(object: Gen2BattleAnimObject, a: int) -> void:
	var step: int = a & 0xF
	object.x = (object.x + step) & 0xFF
	var count: int = step >> 1
	object.y = (object.y - (count if count != 0 else 0x100)) & 0xFF


## `BattleAnim_StepCircle`: a circle whose height is a quarter of its width.
static func _step_circle(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject, a: int, d: int
) -> void:
	object.y_offset = _sra(_sra(_sine(data, a, d)))
	object.x_offset = _cosine(data, a, d)


## `BattleAnim_StepThrownToTarget`: a parabola towards the other side, whose two
## halves are the parameter's two nybbles. Entered with [param a] holding var2's
## value from before its own decrement, the way both callers leave it.
static func _step_thrown_to_target(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject, a: int
) -> void:
	object.var2 = (object.var2 - 1) & 0xFF
	object.y_offset = _sine(data, a, 0x20)
	object.y_fix = (object.y_fix + 2) & 0xFF

	var de: int = (object.x << 8) | object.var1
	var hl: int = (((object.param & 0xF0) >> 4) << 8) | ((object.param & 0xF) << 4)
	hl = (hl + de) & 0xFFFF
	object.var1 = hl & 0xFF
	object.x = hl >> 8

	if (object.var2 & 1) != 0:
		return
	object.y = (object.y - 1) & 0xFF


## `GetBallAnimPal`: the thrown ball's own colour, off `wCurItem`.
static func _ball_palette(player: Gen2BattleAnimPlayer, object: Gen2BattleAnimObject) -> void:
	for row: Variant in BALL_COLORS:
		if int((row as Array)[0]) == player.cur_item:
			object.palette = int((row as Array)[1])
			return
	object.palette = BALL_COLOR_DEFAULT


# -------------------------------------------------------------- callbacks ----

## `BattleAnimFunc_Null`, which is not a no-op: its second state deletes the
## object, and that is how `anim_incobj` retires the sixty-two rows that use it.
static func _null(object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 1:
		object.deinit()


static func _user_to_target(object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index != 0:
		object.deinit()
		return
	if object.x >= 0x84:
		return
	_step_to_target(object, object.param)


static func _user_to_target_disappear(object: Gen2BattleAnimObject) -> void:
	if object.x >= 0x84:
		object.deinit()
		return
	_step_to_target(object, object.param)


## Bit 7 of the parameter starts the object on the other side of the circle and
## is then cleared, since the rest of the byte is the radius.
static func _move_in_circle(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var1 = 0x00 if (object.param & 0x80) == 0 else 0x20
		object.param &= 0x7F
	object.y_offset = _sine(data, object.var1, object.param)
	object.x_offset = _cosine(data, object.var1, object.param)
	object.var1 = (object.var1 + 1) & 0xFF


static func _wave_to_target(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.x >= 0x88:
		object.deinit()
		return
	object.x = (object.x + 2) & 0xFF
	object.y = (object.y - 1) & 0xFF
	var a: int = object.var1
	object.var1 = (object.var1 + 4) & 0xFF
	object.y_offset = _sine(data, a, 0x10)
	object.x_offset = _sra(_sra(_sra(_sra(_cosine(data, a, 0x10)))))


## `BattleAnimFunc_ThrowFromUserToTarget`, whose carry flag is its answer: false
## once the object has reached the far side, which is what the disappearing
## variant and the Poke Ball both branch on.
static func _throw_to_target(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> bool:
	if object.x >= 0x88:
		return false
	object.x = (object.x + 2) & 0xFF
	object.y = (object.y - 1) & 0xFF
	var a: int = object.var1
	object.var1 = (object.var1 - 1) & 0xFF
	object.y_offset = _sine(data, a, object.param)
	return true


static func _throw_to_target_disappear(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	if _throw_to_target(data, object):
		return
	object.deinit()


static func _drop(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var1 = 0x30
		object.var2 = 0x48
	object.y_offset = _sine(data, object.var1, object.var2)
	object.var1 = (object.var1 + 1) & 0xFF
	if (object.var1 & 0x3F) != 0:
		return
	object.var1 = 0x20
	var left: int = object.var2 - object.param
	if left <= 0:
		object.deinit()
		return
	object.var2 = left


static func _user_to_target_spin(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	if object.jumptable_index == 0:
		if object.x < 0x80:
			# `.SetCoords` is `BattleAnim_StepToTarget` written out again, the
			# 256-step vertical loop included.
			_step_to_target(object, object.param)
			return
		_inc(object)
	if object.jumptable_index == 1:
		_inc(object)
		object.var1 = 0x00
	if object.jumptable_index == 2:
		if object.var1 < 0x40:
			object.y_offset = _sra((_cosine(data, object.var1, 0x18) - 0x18) & 0xFF)
			object.x_offset = _sine(data, object.var1, 0x18)
			object.var1 = (object.var1 + (object.param & 0xF)) & 0xFF
			return
		# One more lap while the parameter's high nybble has laps left in it.
		var laps: int = object.param & 0xF0
		if laps != 0:
			object.param = (object.param & 0xF) | (laps - 0x10)
			object.jumptable_index = (object.jumptable_index - 1) & 0xFF
			return
		_inc(object)
	if object.x >= 0xB0:
		object.deinit()
		return
	_step_to_target(object, object.param)


static func _shake(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.var1 = 0x00
			object.x_offset = object.param & 0xF
			_shake_step(object)
		1:
			_shake_step(object)
		2:
			object.deinit()


static func _shake_step(object: Gen2BattleAnimObject) -> void:
	if object.var1 != 0:
		object.var1 = (object.var1 - 1) & 0xFF
		return
	object.var1 = (object.param >> 4) & 0xF
	object.x_offset = (-object.x_offset) & 0xFF


## The parameter is the state to start in, so one object row draws nine
## different flames.
static func _fire_blast(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		object.jumptable_index = object.param
		if object.jumptable_index != 7:
			_reinit(object, FRAMESET_BURNED)
			return
	match object.jumptable_index:
		1:
			object.y_offset = (object.y_offset - 1) & 0xFF
		2:
			object.x_offset = (object.x_offset - 1) & 0xFF
		3:
			object.x_offset = (object.x_offset + 1) & 0xFF
		4:
			object.y_offset = (object.y_offset + 1) & 0xFF
			object.x_offset = (object.x_offset - 1) & 0xFF
		5:
			object.y_offset = (object.y_offset + 1) & 0xFF
			object.x_offset = (object.x_offset + 1) & 0xFF
		6:
			pass
		7:
			if object.x >= 0x88:
				_inc(object)
				_reinit(object, FRAMESET_EMBER)
				_fire_blast_circle(data, object)
				return
			object.x = (object.x + 2) & 0xFF
			object.y = (object.y - 1) & 0xFF
		8:
			_fire_blast_circle(data, object)
		9:
			object.deinit()


static func _fire_blast_circle(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	object.y_offset = _sine(data, object.var1, 0x10)
	object.x_offset = _cosine(data, object.var1, 0x10)
	object.var1 = (object.var1 + 1) & 0xFF


static func _razor_leaf(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.var1 = 0x40
			_razor_leaf_fall(data, object)
		1:
			_razor_leaf_fall(data, object)
		2:
			if object.y_offset == 0x20:
				object.deinit()
				return
			object.x_offset = _sine(data, object.var1, 0x10)
			if (object.param & 0x40) != 0:
				object.var1 = (object.var1 - 1) & 0xFF
			else:
				object.var1 = (object.var1 + 1) & 0xFF
			var hl: int = (((object.y_offset << 8) | object.var2) + 0x80) & 0xFFFF
			object.y_offset = hl >> 8
			object.var2 = hl & 0xFF
		3:
			_reinit(object, FRAMESET_RAZOR_LEAF_1)
			object.oam_flags &= ~Gen2BattleAnimObject.OAM_XFLIP & 0xFF
			_inc(object)
		4, 5, 6, 7:
			_inc(object)
		8:
			if object.x >= 0xC0:
				return
			_step_to_target(object, 0x8)


## The first state of both leaf callbacks: the arc down, and the switch to the
## second frameset once it has fallen far enough.
static func _razor_leaf_fall(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.var1 < 0x30:
		_inc(object)
		object.var1 = 0x00
		object.var2 = 0x00
		_reinit(object, FRAMESET_RAZOR_LEAF_2)
		if (object.param & 0x40) == 0:
			return
		object.frame = 0x5
		return
	_arc_horizontal(data, object)


## The half `BattleAnimFunc_RazorLeaf` and `..._RockSmash` share: a sine on the
## y offset and a sixteen-bit horizontal step whose low byte lives in var2.
static func _arc_horizontal(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var a: int = object.var1
	object.var1 = (object.var1 - 1) & 0xFF
	object.y_offset = _sine(data, a, object.param & 0x3F)
	var hl: int = (((object.x << 8) | object.var2) + _scatter_horizontal(object.param)) & 0xFFFF
	object.x = hl >> 8
	object.var2 = hl & 0xFF


## `BattleAnim_ScatterHorizontal`: how far sideways one frame of that arc is,
## with bit 7 of the parameter deciding which way.
static func _scatter_horizontal(param: int) -> int:
	if (param & 0x80) != 0:
		var negative: int = param & 0x3F
		if negative >= 0x20:
			return -0x100
		if negative >= 0x18:
			return -0x180
		return -0x200
	if param >= 0x20:
		return 0x100
	if param >= 0x18:
		return 0x180
	return 0x200


static func _bubble(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.var1 = 0xC
			_bubble_approach(object)
		1:
			_bubble_approach(object)
		2:
			_bubble_rise(object)


static func _bubble_approach(object: Gen2BattleAnimObject) -> void:
	if object.var1 != 0:
		object.var1 = (object.var1 - 1) & 0xFF
		_step_to_target(object, object.param)
		return
	_inc(object)
	object.var1 = 0x00
	_reinit(object, FRAMESET_PULSING_BUBBLE)
	_bubble_rise(object)


static func _bubble_rise(object: Gen2BattleAnimObject) -> void:
	if object.x < 0x98:
		var horizontal: int = (((object.x << 8) | object.var1) + 0x60) & 0xFFFF
		object.var1 = horizontal & 0xFF
		object.x = horizontal >> 8
	if object.y < 0x20:
		return
	var vertical: int = (((object.y << 8) | object.var2) + 0xFF00 + (object.param & 0xF0)) & 0xFFFF
	object.var2 = vertical & 0xFF
	object.y = vertical >> 8


## The one callback that owns a scanline window: `hLYOverrideStart` follows the
## wave down the screen and is handed back when it reaches the bottom.
static func _surf(
	player: Gen2BattleAnimPlayer, data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	var background: Gen2BattleAnimBackground = player.background()
	match object.jumptable_index:
		0:
			_inc(object)
			background.lcdc_pointer = LCDC_POINTER_SCY
			background.ly_override_start = 0x58
			background.ly_override_end = 0x5E
		1:
			if object.y < object.param:
				_inc(object)
				background.ly_override_start = 0
				return
			object.y = (object.y - 1) & 0xFF
			var wave: int = _sine(data, object.var1, 0x10)
			object.y_offset = wave
			var line: int = ((wave + object.y) & 0xFF) - 0x10
			if line < 0:
				return
			background.ly_override_start = line
			object.x_offset = (object.x_offset + 1) & 0x7
			object.var1 = (object.var1 + 2) & 0xFF
		2:
			pass
		3:
			if object.y < 0x70:
				object.y = (object.y + 2) & 0xFF
				var below: int = object.y - 0x10
				if below < 0:
					return
				background.ly_override_start = below
				return
			background.lcdc_pointer = 0
			background.ly_override_start = 0
			background.ly_override_end = 0
			object.deinit()
		4:
			object.deinit()


static func _sing(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		_reinit(object, FRAMESET_MUSIC_NOTE_1 + object.param)
	if object.x >= 0xB8:
		object.deinit()
		return
	_step_to_target(object, 0x2)
	var a: int = object.var1
	object.var1 = (object.var1 - 1) & 0xFF
	object.y_offset = _sine(data, a, 0x8)


static func _water_gun(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
	match object.jumptable_index:
		1:
			if object.y >= 0x30:
				_step_to_target(object, 0x2)
				var a: int = object.var1
				object.var1 = (object.var1 - 1) & 0xFF
				object.y_offset = _sine(data, a, 0x8)
				return
			_inc(object)
			_reinit(object, FRAMESET_WATER_GUN_2)
			object.y_offset = 0x00
			object.y = 0x30
			object.oam_flags &= Gen2BattleAnimObject.OAM_FLAGS_FIX_COORDS
			_water_gun_splash(object)
		2:
			_water_gun_splash(object)
		3:
			pass


static func _water_gun_splash(object: Gen2BattleAnimObject) -> void:
	if object.y_offset < 0x18:
		object.y_offset = (object.y_offset + 1) & 0xFF
		return
	_inc(object)
	_reinit(object, FRAMESET_WATER_GUN_3)


static func _ember(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			object.jumptable_index = (object.param >> 4) & 0xF
		1:
			if object.x >= 0x88:
				return
			_step_to_target(object, object.param)
		2:
			object.deinit()
		3:
			_inc(object)
			_reinit(object, FRAMESET_FLAMETHROWER)
		4:
			pass


static func _powder(object: Gen2BattleAnimObject) -> void:
	if object.y_offset >= 0x38:
		object.deinit()
		return
	var fall: int = (((object.y_offset << 8) | object.var1) + 0x80) & 0xFFFF
	object.var1 = fall & 0xFF
	object.y_offset = fall >> 8
	object.x_offset ^= 0x10


static func _poke_ball(
	player: Gen2BattleAnimPlayer, data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	match object.jumptable_index:
		0:
			_ball_palette(player, object)
			_inc(object)
		1:
			if _throw_to_target(data, object):
				return
			object.y = (object.y + object.y_offset) & 0xFF
			_reinit(object, FRAMESET_POKE_BALL_3)
			_inc(object)
		2, 5, 9:
			pass
		3:
			_inc(object)
			_reinit(object, FRAMESET_POKE_BALL_1)
			object.var1 = 0x00
			object.var2 = 0x10
			_poke_ball_bounce(data, object)
		4:
			_poke_ball_bounce(data, object)
		6:
			_reinit(object, FRAMESET_POKE_BALL_5)
			object.jumptable_index = (object.jumptable_index - 1) & 0xFF
		7:
			_ball_palette(player, object)
			_reinit(object, FRAMESET_POKE_BALL_2)
			_inc(object)
			object.var2 = 0x20
			_poke_ball_wobble(data, object)
		8, 10:
			_poke_ball_wobble(data, object)
		11:
			object.deinit()


## The ball settling: a shrinking bounce whose amplitude drops four at a time.
static func _poke_ball_bounce(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	object.y_offset = _sine(data, object.var1, object.var2)
	object.var1 = (object.var1 - 1) & 0xFF
	# The masked value is written back, so a var1 of $20 or $40 lands on zero
	# rather than keeping its high bits.
	if (object.var1 & 0x1F) != 0:
		return
	object.var1 = 0x00
	object.var2 = (object.var2 - 4) & 0xFF
	if object.var2 != 0:
		return
	_reinit(object, FRAMESET_POKE_BALL_4)
	_inc(object)


## The three wobbles, each ending on the state after it.
static func _poke_ball_wobble(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	object.y_offset = _sine(data, object.var1, object.var2)
	object.var1 = (object.var1 - 1) & 0xFF
	if (object.var1 & 0x1F) == 0:
		object.deinit()
		return
	if (object.var1 & 0xF) != 0:
		return
	_inc(object)


static func _poke_ball_blocked(
	player: Gen2BattleAnimPlayer, data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	match object.jumptable_index:
		0:
			_ball_palette(player, object)
			_inc(object)
		1:
			if object.x < 0x70:
				_throw_to_target(data, object)
				return
			_inc(object)
			_poke_ball_fall(object)
		2:
			_poke_ball_fall(object)


static func _poke_ball_fall(object: Gen2BattleAnimObject) -> void:
	if object.y >= 0x80:
		object.deinit()
		return
	object.y = (object.y + 4) & 0xFF
	object.x = (object.x - 2) & 0xFF


## The parameter is both the starting angle and the radius, and the radius is
## what runs out: the object is deleted once the circle has closed.
static func _recover(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var2 = object.param & 0xF0
		object.var1 = ((object.param & 0xF) << 3) & 0xFF
		object.param = 0x1
	if object.var2 == 0:
		object.deinit()
		return
	var a: int = object.var1
	object.var1 = (object.var1 + 1) & 0xFF
	object.y_offset = _sine(data, a, object.var2)
	object.x_offset = _cosine(data, a, object.var2)
	object.param ^= 0x1
	if object.param == 0:
		return
	object.var2 = (object.var2 - 1) & 0xFF


static func _thunder_wave(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		1:
			_inc(object)
			_reinit(object, FRAMESET_THUNDER_WAVE_EXTRA)
		3:
			object.deinit()


## Two hands clapped together twice. The parameter is the distance from the
## centre, and its bit 7 picks the mirrored frameset of the pair.
static func _clamp_encore(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var2 = object.frameset
		object.var1 = 0x30 if (object.param & 0x80) != 0 else 0x10
		object.param &= 0x7F
	match object.jumptable_index:
		1:
			var step: int = _sine(data, object.var1, object.param)
			object.x_offset = step
			_reinit(object, object.var2 if (step & 0x80) != 0 else object.var2 + 1)
			object.var1 = (object.var1 + 1) & 0xFF
			if (object.var1 & 0x1F) != 0:
				return
			_inc(object)
		2, 3, 4, 5:
			_inc(object)
		6:
			object.jumptable_index = 0x1


static func _bite(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var1 = 0x30 if (object.param & 0x80) != 0 else 0x10
		object.param &= 0x7F
	match object.jumptable_index:
		1:
			var step: int = _sine(data, object.var1, object.param)
			object.y_offset = step
			_reinit(object, FRAMESET_BITE_1 if (step & 0x80) != 0 else FRAMESET_BITE_2)
			object.var1 = (object.var1 + 2) & 0xFF
			if (object.var1 & 0x1F) != 0:
				return
			_inc(object)
		2, 3, 4, 5:
			_inc(object)
		6:
			object.jumptable_index = 0x1


static func _solar_beam(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var1 = 0x28
		object.var2 = 0x00
	object.y_offset = _sine(data, object.param, object.var1)
	object.x_offset = _cosine(data, object.param, object.var1)
	if object.var1 == 0:
		object.deinit()
		return
	var shrink: int = (((object.var1 << 8) | object.var2) - 0x80) & 0xFFFF
	object.var2 = shrink & 0xFF
	object.var1 = shrink >> 8


static func _gust(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.param = 0
			_gust_wobble(data, object)
		1, 3:
			_gust_wobble(data, object)
		2:
			if object.x < 0x88:
				_gust_move(data, object)
				return
			_inc(object)
		4:
			if object.x < 0xB8:
				_gust_move(data, object)
				return
			object.deinit()


static func _gust_move(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	_gust_wobble(data, object)
	object.x = (object.x + 1) & 0xFF
	if (object.x & 0x1) != 0:
		return
	object.y = (object.y - 1) & 0xFF


## A circle whose width comes from a nine-entry list and whose height is a
## sixteenth of it. The list is never indexed past its end: var2 only climbs
## while the parameter counts down from $ff to $c2, which is seven steps.
static func _gust_wobble(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var radius: int = GUST_OFFSETS[object.var2] if object.var2 < GUST_OFFSETS.size() else 0
	var a: int = object.var1
	object.y_offset = (_sra(_sra(_sra(_sra(_sine(data, a, radius))))) + object.param) & 0xFF
	object.x_offset = _cosine(data, a, radius)
	object.var1 = (object.var1 - 0x8) & 0xFF

	if object.param != 0 and object.param < 0xC2:
		object.var2 = 0
		object.param = 0
		object.x_offset = 0
		object.y_offset = 0
		return
	object.param = (object.param - 1) & 0xFF
	if (object.param & 0x7) != 0:
		return
	object.var2 = (object.var2 + 1) & 0xFF


static func _razor_wind(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	_move_in_circle(data, object)
	object.var1 = (object.var1 + 0xF) & 0xFF


static func _kick(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			pass
		1:
			if object.y < 0x30:
				object.y = (object.y + 4) & 0xFF
				return
			object.jumptable_index = 0x0
		2:
			if object.x >= 0x98:
				return
			object.x = (object.x + 2) & 0xFF
			object.oam_flags |= Gen2BattleAnimObject.OAM_FLAGS_FIX_COORDS
			object.y_fix = 0x90
			object.frame = 0x0
			object.duration = 0x2
			object.y = (object.y - 1) & 0xFF
		3:
			_inc(object)
			object.var1 = 0x2C
			object.frame = 0x0
			object.duration = 0x80
			_rolling_kick(data, object)
		4:
			_rolling_kick(data, object)


static func _rolling_kick(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.x >= 0x98:
		return
	object.x = (object.x + 2) & 0xFF
	var a: int = object.var1
	object.var1 = (object.var1 + 1) & 0xFF
	object.y_offset = _sine(data, a, 0x8)


## The mirror of [method _user_to_target_disappear]: back towards the user, with
## the same 256-step vertical loop when the nybble is under two.
static func _absorb(object: Gen2BattleAnimObject) -> void:
	if object.x < 0x30:
		object.deinit()
		return
	var step: int = object.param & 0xF
	object.x = (object.x - step) & 0xFF
	var count: int = step >> 1
	object.y = (object.y + (count if count != 0 else 0x100)) & 0xFF


## Egg Bomb and Softboiled share fourteen states; the parameter picks which one
## the object starts on.
static func _egg(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			object.var1 = 0x28
			object.var2 = 0x10
			object.jumptable_index = object.param
		1:
			if object.x < 0x40:
				object.x = (object.x + 1) & 0xFF
			_egg_wave(data, object)
		2:
			if object.x >= 0x88:
				object.jumptable_index = (object.jumptable_index + 2) & 0xFF
				return
			if (object.x & 0xF) != 0:
				_egg_step(object)
				return
			object.var2 = 0x10
			_inc(object)
		3:
			if object.var2 != 0:
				object.var2 = (object.var2 - 1) & 0xFF
				return
			object.jumptable_index = (object.jumptable_index - 1) & 0xFF
			_egg_step(object)
		4, 10, 13:
			pass
		5:
			object.deinit()
		6:
			if object.x < 0x4B:
				object.x = (object.x + 1) & 0xFF
			_egg_wave(data, object)
		7:
			_reinit(object, FRAMESET_EGG_WOBBLE)
			_inc(object)
		8:
			var a: int = object.var1
			object.var1 = (object.var1 + 2) & 0xFF
			object.x_offset = _sine(data, a, 0x2)
		9:
			_reinit(object, FRAMESET_EGG_CRACKED_BOTTOM)
			object.y_offset = 0x4
			_inc(object)
		11:
			_reinit(object, FRAMESET_EGG_CRACKED_TOP)
			_inc(object)
			object.var1 = 0x40
		12:
			object.y_offset = _sine(data, object.var1, 0x20)
			if object.var1 < 0x30:
				_inc(object)
				return
			object.var1 = (object.var1 - 1) & 0xFF


static func _egg_step(object: Gen2BattleAnimObject) -> void:
	object.x = (object.x + 1) & 0xFF
	var rise: int = (((object.y << 8) | object.var1) - 0x80) & 0xFFFF
	object.y = rise >> 8
	object.var1 = rise & 0xFF


## `.EggVerticalWaveMotion`, whose amplitude drops eight at a time and whose
## running out is what moves the object on to the next state.
static func _egg_wave(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	object.y_offset = _sine(data, object.var1, object.var2)
	object.var1 = (object.var1 + 1) & 0xFF
	if (object.var1 & 0x3F) != 0:
		return
	object.var1 = 0x20
	object.var2 = (object.var2 - 0x8) & 0xFF
	if object.var2 != 0:
		return
	object.var1 = 0x00
	object.var2 = 0x00
	_inc(object)


static func _move_up(object: Gen2BattleAnimObject) -> void:
	if object.y_offset != 0 and object.y_offset < 0xD8:
		object.deinit()
		return
	object.y_offset = (object.y_offset - object.param) & 0xFF


static func _wrap(object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index != 1:
		return
	_reinit(object, object.frameset + 1)
	_inc(object)
	object.var1 = 0x8


static func _leech_seed(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.var2 = 0x40
		1:
			if object.var2 >= 0x20:
				_step_thrown_to_target(data, object, object.var2)
				return
			object.var2 = 0x40
			_reinit(object, FRAMESET_LEECH_SEED_2)
			_inc(object)
		2:
			if object.var2 != 0:
				object.var2 = (object.var2 - 1) & 0xFF
				return
			_inc(object)
			_reinit(object, FRAMESET_LEECH_SEED_3)


## Growl, Snore and Kinesis. The angle is mirrored on the enemy's turn, which is
## the one callback that reads `hBattleTurn` for anything but a palette.
static func _sound(
	player: Gen2BattleAnimPlayer, data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	if object.jumptable_index == 0:
		if player.enemy_turn():
			object.param = (~object.param + 3) & 0xFF
		_inc(object)
		object.var1 = 0x8
		_reinit(object, FRAMESET_SOUND_1 + object.param)
		return
	if object.var1 == 0:
		object.deinit()
		return
	object.var1 = (object.var1 - 1) & 0xFF

	var a: int = object.var2
	object.var2 = (object.var2 + 2) & 0xFF
	var step: int = _sine(data, a, 0x10)
	object.x_offset = step
	if object.param == 0:
		object.y_offset = (-step) & 0xFF
		return
	if object.param == 1:
		return
	object.y_offset = step


static func _confuse_ray(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var2 = object.param & 0x3F
		object.param = 1 if (object.param & 0x80) != 0 else 0
		_reinit(object, FRAMESET_CONFUSE_RAY_1 + object.param)
		return

	var radius: int = ((object.param << 4) | (object.param >> 4)) & 0xFF
	var a: int = object.var2
	object.var2 = (object.var2 + 1) & 0xFF
	object.y_offset = _sine(data, a, radius)
	object.x_offset = _cosine(data, a, radius)
	if object.x >= 0x80:
		return
	var phase: int = object.var2 & 0x3
	if phase == 0:
		object.y = (object.y - 1) & 0xFF
	if (phase & 0x1) != 0:
		return
	object.x = (object.x + 1) & 0xFF


static func _dizzy(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var1 = object.frameset
		_reinit(object, object.var1 + (1 if (object.param & 0x80) != 0 else 0))
		object.param &= 0x7F

	object.y_offset = _sra(_sra(_sine(data, object.param, 0x10)))
	object.x_offset = _cosine(data, object.param, 0x10)
	var phase: int = object.param & 0x3F
	object.param = (object.param + 1) & 0xFF
	if phase == 0:
		_reinit(object, object.var1)
		return
	if (phase & 0x1F) != 0:
		return
	_reinit(object, object.var1 + 1)


static func _amnesia(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			_reinit(object, FRAMESET_AMNESIA_1 + object.param)
			object.y_offset = AMNESIA_OFFSETS[object.param] \
				if object.param < AMNESIA_OFFSETS.size() else 0
		2:
			object.deinit()


static func _float_up(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var a: int = object.var1
	object.var1 = (object.var1 + 2) & 0xFF
	object.x_offset = _sine(data, a, 0x4)
	var rise: int = (((object.y_offset << 8) | object.var2) + 0xFFA0) & 0xFFFF
	object.y_offset = rise >> 8
	object.var2 = rise & 0xFF


static func _dig(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var a: int = object.var1
	object.var1 = (object.var1 - 2) & 0xFF
	object.y_offset = _sine(data, a, 0x10)
	object.x = (object.x + 1) & 0xFF


static func _string(object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index != 0:
		return
	_inc(object)
	if object.param == 0:
		object.oam_flags |= Gen2BattleAnimObject.OAM_YFLIP
	_reinit(object, FRAMESET_STRING_SHOT_1 + object.param)


## Bit 7 of the parameter picks the mirrored frameset and is then gone: the two
## nybbles left are how long between switches and how far each way.
static func _paralyzed(object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var1 = 0x00
		var param: int = object.param
		object.param = (param & 0x70) >> 4
		if (param & 0x80) != 0:
			object.x_offset = (-(param & 0xF)) & 0xFF
			_reinit(object, FRAMESET_PARALYZED_FLIPPED)
		else:
			object.x_offset = param & 0xF
		return
	if object.var1 != 0:
		object.var1 = (object.var1 - 1) & 0xFF
		return
	object.var1 = object.param
	object.x_offset = (-object.x_offset) & 0xFF


static func _spiral_descent(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	_descend(data, object, 0x7)


static func _petal_dance(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	_descend(data, object, 0x3)


## The spiral `BattleAnimFunc_SpiralDescent` and `..._PetalDance` share: they
## differ only in how often the object sinks a pixel.
static func _descend(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject, mask: int
) -> void:
	var a: int = object.var1
	object.y_offset = (_sra(_sra(_sra(_sine(data, a, 0x18)))) + object.var2) & 0xFF
	object.x_offset = _cosine(data, a, 0x18)
	object.var1 = (object.var1 + 1) & 0xFF
	if (object.var1 & mask) != 0:
		return
	if object.var2 >= 0x28:
		object.deinit()
		return
	object.var2 = (object.var2 + 1) & 0xFF


static func _poison_gas(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index != 0:
		_spiral_descent(data, object)
		return
	if object.x >= 0x84:
		_inc(object)
		return
	object.x = (object.x + 1) & 0xFF
	var a: int = object.var1
	object.var1 = (object.var1 + 1) & 0xFF
	object.x_offset = _cosine(data, a, 0x18)
	if (object.x & 0x1) != 0:
		return
	object.y = (object.y - 1) & 0xFF


static func _horn(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			object.jumptable_index = object.param
			object.var1 = object.y
		1:
			if object.x >= 0x58:
				return
			_step_to_target(object, 0x2)
		2:
			if object.var2 >= 0x20:
				object.deinit()
				return
			_horn_sweep(data, object)
		3:
			_horn_sweep(data, object)


static func _horn_sweep(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var step: int = _sine(data, object.var2, 0x8)
	object.x_offset = step
	object.y = (((-_sra(step)) & 0xFF) + object.var1) & 0xFF
	object.var2 = (object.var2 + 0x8) & 0xFF


## The parameter's high nybble picks the state and its low nybble the speed, so
## one row is both the straight needle and the arcing one.
static func _needle(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			object.jumptable_index = (object.param & 0xF0) >> 4
		2:
			var arc: int = _sine(data, object.var1, 0x10)
			# Only the negative half of the sine is stored, so the arc is one
			# hump rather than a wave.
			if (arc & 0x80) != 0:
				object.y_offset = arc
			object.var1 = (object.var1 - 4) & 0xFF
			_needle_advance(object)
		1:
			_needle_advance(object)


static func _needle_advance(object: Gen2BattleAnimObject) -> void:
	if object.x >= 0x84:
		object.deinit()
		return
	_step_to_target(object, object.param)


static func _thief_payday(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var1 = 0x28
		object.var2 = (object.y - 0x28) & 0xFF
	object.y_offset = _sine(data, object.var1, object.var2)
	if (object.var1 & object.param) == 0:
		object.x = (object.x - 1) & 0xFF
	object.var1 = (object.var1 + 1) & 0xFF
	if (object.var1 & 0x3F) != 0:
		return
	object.var1 = 0x20
	object.var2 >>= 1


## A ring that widens on the way in and closes on the way out, the object going
## when its radius reaches zero.
static func _absorb_circle(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	object.y_offset = _sine(data, object.param, object.var1)
	object.x_offset = _cosine(data, object.param, object.var1)
	object.param = (object.param + 1) & 0xFF
	if (object.param & 0x1) == 0:
		object.x = (object.x - 1) & 0xFF
	if (object.param & 0x3) == 0:
		object.y = (object.y + 1) & 0xFF
	if object.x >= 0x5A:
		object.var1 = (object.var1 + 1) & 0xFF
		return
	if object.var1 == 0:
		object.deinit()
		return
	object.var1 = (object.var1 - 1) & 0xFF


static func _bonemerang(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var2 = object.y
	object.y = (_sine(data, object.param, 0x30) + object.var2) & 0xFF
	object.x_offset = _cosine(data, (object.param + 0x8) & 0xFF, 0x30)
	object.param = (object.param + 1) & 0xFF


static func _shiny(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index != 0:
		return
	_inc(object)
	object.y_offset = _sine(data, object.param, 0x10)
	object.x_offset = _cosine(data, object.param, 0x10)
	object.var2 = 0xF


static func _sky_attack(player: Gen2BattleAnimPlayer, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.var1 = 0xCC if player.enemy_turn() else 0xF0
		1:
			_sky_attack_palette(player, object)
		2:
			_sky_attack_palette(player, object)
			if object.x >= 0x84:
				return
			_step_to_target(object, 0x4)
		3:
			_sky_attack_palette(player, object)
			if object.x >= 0xD0:
				object.deinit()
				return
			_step_to_target(object, 0x4)


## `.SkyAttack_CyclePalette`, which flashes `wOBP0`. `BattleAnimRequestPals`
## watches that byte, so on the Color hardware the write becomes a remap of the
## two object palettes from `PAL_BATTLE_OB_GRAY` on.
static func _sky_attack_palette(
	player: Gen2BattleAnimPlayer, object: Gen2BattleAnimObject
) -> void:
	var phase: int = object.var2 & 0x7
	object.var2 = (object.var2 + 1) & 0xFF
	player.background().obp0 = SKY_ATTACK_PALS[phase >> 1] & object.var1


static func _growth_swords_dance(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	object.y_offset = (_sra(_sra(_sra(_sine(data, object.param, 0x18)))) + object.var2) & 0xFF
	object.x_offset = _cosine(data, object.param, 0x18)
	object.param = (object.param + 1) & 0xFF
	object.var2 = (object.var2 - 2) & 0xFF


static func _smoke_flame_wheel(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	_rise_in_circle(data, object, 0x7, 0xE8, 1)


static func _sacred_fire(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	_rise_in_circle(data, object, 0x3, 0xD0, 2)


## The spiral `BattleAnimFunc_SmokeFlameWheel` and `..._SacredFire` share: they
## differ in how often the object rises, how far, and where it stops.
static func _rise_in_circle(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject,
	mask: int, limit: int, step: int
) -> void:
	object.y_offset = (_sra(_sra(_sra(_sine(data, object.param, 0x18)))) + object.var2) & 0xFF
	object.x_offset = _cosine(data, object.param, 0x18)
	object.param = (object.param + 2) & 0xFF
	if (object.param & mask) != 0:
		return
	if object.var2 == limit:
		object.deinit()
		return
	object.var2 = (object.var2 - step) & 0xFF


static func _present_smokescreen(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.var1 = 0x34
			object.var2 = 0x10
			_present_bounce(data, object)
		1:
			_present_bounce(data, object)
		2:
			object.deinit()


static func _present_bounce(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.x >= 0x6C:
		return
	_step_to_target(object, 0x2)
	var height: int = _sine(data, object.var1, object.var2)
	if (height & 0x80) == 0:
		height = (-height) & 0xFF
	object.y_offset = height
	object.var1 = (object.var1 - 0x4) & 0xFF
	# `and $1f` then `cp $20` can never match, so the halving below it is
	# unreachable and the bounce never loses height. The cartridge's own.


static func _strength_seismic_toss(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			if object.y_offset == 0xE0:
				_inc(object)
				object.var1 = 0x2
				return
			var rise: int = (((object.y_offset << 8) | object.var1) - 0x80) & 0xFFFF
			object.y_offset = rise >> 8
			object.var1 = rise & 0xFF
		1:
			if object.var2 != 0:
				object.var2 = (object.var2 - 1) & 0xFF
				return
			object.var2 = 0x4
			object.var1 = (-object.var1) & 0xFF
			object.y_offset = (object.var1 + object.y_offset) & 0xFF
		2:
			if object.x >= 0x84:
				object.deinit()
				return
			_step_to_target(object, 0x4)


static func _speed_line(object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		_reinit(object, FRAMESET_SPEED_LINE_1 + (object.param & 0x7F))
	if (object.param & 0x80) != 0:
		object.x_offset = (object.x_offset - 1) & 0xFF
		return
	object.x_offset = (object.x_offset + 1) & 0xFF


static func _sludge(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.var1 = 0xC
		1:
			if object.var1 != 0:
				object.var1 = (object.var1 - 1) & 0xFF
				return
			_inc(object)
			_reinit(object, FRAMESET_SLUDGE_BUBBLE_BURST)
			object.y_offset = (object.y_offset - 1) & 0xFF
		2:
			object.y_offset = (object.y_offset - 1) & 0xFF


static func _metronome_hand(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var a: int = object.var1
	object.var1 = (object.var1 + 2) & 0xFF
	object.y_offset = _sine(data, a, 0x2)
	object.x_offset = _cosine(data, a, 0x8)


static func _metronome_sparkle_sketch(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	if object.y_offset >= 0x20:
		object.deinit()
		return
	object.x_offset = _cosine(data, object.param, 0x8)
	object.param = (object.param + 2) & 0xFF
	if (object.param & 0x7) != 0:
		return
	object.y_offset = (object.y_offset + 1) & 0xFF


static func _agility(object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index != 0:
		object.deinit()
		return
	object.x = (object.x + object.param) & 0xFF


static func _safeguard_protect(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	object.y_offset = _sine(data, object.param, 0x18)
	object.x_offset = _sra(_cosine(data, object.param, 0x18))
	object.param = (object.param + 1) & 0xFF


## Four objects converging on one point, then a wait, then gone. The parameter's
## low nybble picks which of the four framesets this one is.
static func _lock_on_mind_reader(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		object.var1 = 0x28
		_reinit(object, (object.param & 0xF) + object.frameset)
		object.param = (object.param & 0xF0) | 0x8
	match object.jumptable_index:
		1:
			if object.var1 != 0:
				var radius: int = object.var1
				object.var1 = (object.var1 - 1) & 0xFF
				object.y_offset = _sine(data, object.param, (radius + 0x8) & 0xFF)
				object.x_offset = _cosine(data, object.param, (radius + 0x8) & 0xFF)
				return
			object.var1 = 0x10
			_inc(object)
			_lock_on_wait(object)
		2:
			_lock_on_wait(object)


static func _lock_on_wait(object: Gen2BattleAnimObject) -> void:
	var left: int = object.var1
	object.var1 = (object.var1 - 1) & 0xFF
	if left != 0:
		return
	object.deinit()


static func _spikes(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			_inc(object)
			object.var2 = 0x40
		1:
			if object.var2 >= 0x20:
				_step_thrown_to_target(data, object, object.var2)
				return
			_inc(object)


static func _heal_bell_notes(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		_inc(object)
		_reinit(object, FRAMESET_MUSIC_NOTE_1 + object.param)
	if object.y_offset >= 0x38:
		object.deinit()
		return
	object.y_offset = (object.y_offset + 1) & 0xFF
	var a: int = object.var1
	object.var1 = (object.var1 + 1) & 0xFF
	object.x_offset = _cosine(data, a, 0x18)
	if (object.y & 0x1) != 0:
		return
	object.x = (object.x - 1) & 0xFF


static func _baton_pass(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.param == 0:
		return
	var a: int = object.var1
	object.var1 = (object.var1 + 1) & 0xFF
	var height: int = _sine(data, a, object.param)
	if (height & 0x80) == 0:
		height = (-height) & 0xFF
	object.y_offset = height
	if (object.var1 & 0x1F) != 0:
		return
	object.param >>= 1


static func _conversion(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var a: int = object.param
	object.param = (object.param + 1) & 0xFF
	object.y_offset = _sine(data, a, object.var1)
	object.x_offset = _cosine(data, a, object.var1)
	var age: int = object.var2
	object.var2 = (object.var2 + 1) & 0xFF
	if age < 0x40:
		object.var1 = (object.var1 + 1) & 0xFF
		return
	var radius: int = object.var1
	object.var1 = (object.var1 - 1) & 0xFF
	if radius != 0:
		return
	object.deinit()


static func _encore_belly_drum(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.var1 >= 0x10:
		object.deinit()
		return
	var radius: int = object.var1
	object.var1 = (object.var1 + 2) & 0xFF
	object.y_offset = _sine(data, object.param, radius)
	object.x_offset = _cosine(data, object.param, radius)


## The parameter's top two bits are the speed and the rest is the angle, and the
## radius is whatever var1 has grown to.
static func _swagger_morning_sun(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	var radius: int = object.var1
	object.var1 = (radius + ((object.param & 0xC0) >> 6)) & 0xFF
	var angle: int = object.param & 0x3F
	object.y_offset = _sine(data, angle, radius)
	object.x_offset = _cosine(data, angle, radius)


static func _hidden_power(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			var a: int = object.param
			object.param = (object.param + 1) & 0xFF
			_step_circle(data, object, a, 0x18)
		1:
			_inc(object)
			object.var1 = 0x18
			_hidden_power_expand(data, object)
		2:
			_hidden_power_expand(data, object)


static func _hidden_power_expand(
	data: Gen2BattleAnimData, object: Gen2BattleAnimObject
) -> void:
	if object.var1 >= 0x80:
		object.deinit()
		return
	var radius: int = object.var1
	object.var1 = (object.var1 + 0x8) & 0xFF
	_step_circle(data, object, object.param, radius)


static func _curse(object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		return
	if object.x < 0x30:
		object.deinit()
		return
	object.x = (object.x - 2) & 0xFF
	object.y = (object.y + 2) & 0xFF


static func _perish_song(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var a: int = object.param
	object.param = (object.param + 2) & 0xFF
	object.y_offset = (_sra(_sra(_sine(data, a, 0x50))) + object.var1) & 0xFF
	object.var1 = (object.var1 + 1) & 0xFF
	object.x_offset = _cosine(data, a, 0x50)


static func _rapid_spin(object: Gen2BattleAnimObject) -> void:
	if object.y_offset == 0xD0:
		object.deinit()
		return
	object.y_offset = (object.y_offset - 4) & 0xFF


static func _beta_pursuit(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			if object.param != 0:
				object.jumptable_index = (object.jumptable_index + 2) & 0xFF
				_beta_pursuit_up(object)
				return
			_inc(object)
			object.y_offset = 0xEC
			_beta_pursuit_down(object)
		1:
			_beta_pursuit_down(object)
		2:
			_beta_pursuit_up(object)
		3:
			object.deinit()


static func _beta_pursuit_down(object: Gen2BattleAnimObject) -> void:
	if object.y_offset == 0x4:
		object.deinit()
		return
	object.y_offset = (object.y_offset + 4) & 0xFF


static func _beta_pursuit_up(object: Gen2BattleAnimObject) -> void:
	if object.y_offset == 0xD8:
		return
	object.y_offset = (object.y_offset - 4) & 0xFF


static func _rain_sandstorm(object: Gen2BattleAnimObject) -> void:
	match object.jumptable_index:
		0:
			object.jumptable_index = object.param
			_inc(object)
		1:
			_rain_step(object, 2)
		2:
			_rain_step(object, 8)
		3:
			_rain_step(object, 4)


static func _rain_step(object: Gen2BattleAnimObject, sideways: int) -> void:
	var fall: int = (object.y_offset + 0x4) & 0xFF
	object.y_offset = fall if fall < 0x70 else 0x00
	object.x_offset = (object.x_offset + sideways) & 0xFF


## `BattleAnimFunc_AnimObjB0`, which no shipped animation reaches: object $b0 is
## in no `anim_obj`. Ported because the jumptable dispatches to it.
static func _anim_obj_b0(object: Gen2BattleAnimObject) -> void:
	var de: int = (object.x << 8) | object.var1
	var high: int = (object.param & 0xF0) | ((object.param & 0xF0) >> 4)
	var hl: int = ((high << 8) | ((object.param & 0xF) << 4)) & 0xFFFF
	hl = (hl + de) & 0xFFFF
	object.x = hl >> 8
	object.var1 = hl & 0xFF


static func _psych_up(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var a: int = object.param
	object.param = (object.param + 1) & 0xFF
	_step_circle(data, object, a, 0x18)


static func _ancient_power(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.var1 >= 0x20:
		object.deinit()
		return
	var a: int = object.var1
	object.var1 = (object.var1 + 1) & 0xFF
	object.y_offset = (-_sine(data, a, object.param)) & 0xFF


static func _rock_smash(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	if object.jumptable_index == 0:
		# Written straight into the struct rather than through
		# `ReinitBattleAnimFrameset`, so the frame and duration are not reset.
		object.frameset = (FRAMESET_BIG_ROCK + ((object.param & 0x40) >> 6)) & 0xFF
		_inc(object)
		object.var1 = 0x40
	if object.var1 < 0x30:
		object.deinit()
		return
	_arc_horizontal(data, object)


static func _cotton(data: Gen2BattleAnimData, object: Gen2BattleAnimObject) -> void:
	var a: int = object.var2
	object.var2 = (object.var2 + 1) & 0xFF
	_step_circle(data, object, ((a >> 1) + object.param) & 0xFF, 0x18)
