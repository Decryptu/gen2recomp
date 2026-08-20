class_name Gen2PicAnimation
extends RefCounted

## `AnimateFrontpic` (engine/gfx/pic_animation.asm), the wobble a front pic does
## when it is sent out, looked at in a menu, traded, evolved or hatched.
##
## The cartridge's shape is a per-frame interpreter over two nested state
## machines, and so is this one: `SetUpPokeAnim` spends one scene command a
## frame, and `PokeAnim_DoAnimScript` spends one script command over as many
## frames as its own duration. Neither is flattened into a list of frames
## computed once, because a `dorepeat` counter and a `SetWait` are read while
## the animation runs.
##
## What it produces is a 7x7 box of tile numbers, which is exactly what
## `PokeAnim_PlaceGraphic` writes into `wTilemap` and what
## [method Gen2BattleScreenMap.stamp] already writes for the enemy's square. The
## caller stamps that box into its own map; nothing here draws.
##
## Crystal only. pokegold ships no `pic_animation.asm`, no `anim.asm`, no
## bitmasks and no frames, and both of its send-outs reach `PlayStereoCry`
## directly, so a record this has none of animates nothing and the caller plays
## the cry on its own.

## The `ANIM_MON_*` constants, in `PokeAnims`' own order.
enum {
	ANIM_MON_SLOW,
	ANIM_MON_NORMAL,
	ANIM_MON_MENU,
	ANIM_MON_TRADE,
	ANIM_MON_EVOLVE,
	ANIM_MON_HATCH,
	ANIM_MON_HOF,
}

## `PokeAnim_SetupCommands`, indexed by the `pokeanim` macro's own byte.
enum {
	SETUP_FINISH,
	SETUP_BASE_PIC,
	SETUP_SET_WAIT,
	SETUP_WAIT,
	SETUP_SETUP,
	SETUP_SETUP2,
	SETUP_IDLE,
	SETUP_PLAY,
	SETUP_PLAY2,
	SETUP_CRY,
	SETUP_CRY_NO_WAIT,
	SETUP_STEREO_CRY,
}

## The `pokeanim` lists in `PokeAnims`, each ending in `PokeAnim_Finish`.
const SCENES: Dictionary = {
	ANIM_MON_SLOW: [SETUP_STEREO_CRY, SETUP_SETUP2, SETUP_PLAY, SETUP_FINISH],
	ANIM_MON_NORMAL: [SETUP_STEREO_CRY, SETUP_SETUP, SETUP_PLAY, SETUP_FINISH],
	ANIM_MON_MENU: [
		SETUP_CRY_NO_WAIT, SETUP_SETUP, SETUP_PLAY, SETUP_SET_WAIT, SETUP_WAIT,
		SETUP_IDLE, SETUP_PLAY, SETUP_FINISH,
	],
	ANIM_MON_TRADE: [
		SETUP_IDLE, SETUP_PLAY2, SETUP_IDLE, SETUP_PLAY, SETUP_SET_WAIT, SETUP_WAIT,
		SETUP_CRY, SETUP_SETUP, SETUP_PLAY, SETUP_FINISH,
	],
	ANIM_MON_EVOLVE: [
		SETUP_IDLE, SETUP_PLAY, SETUP_SET_WAIT, SETUP_WAIT, SETUP_CRY_NO_WAIT,
		SETUP_SETUP, SETUP_PLAY, SETUP_FINISH,
	],
	ANIM_MON_HATCH: [
		SETUP_IDLE, SETUP_PLAY, SETUP_CRY_NO_WAIT, SETUP_SETUP, SETUP_PLAY,
		SETUP_SET_WAIT, SETUP_WAIT, SETUP_IDLE, SETUP_PLAY, SETUP_FINISH,
	],
	ANIM_MON_HOF: [
		SETUP_CRY_NO_WAIT, SETUP_SETUP, SETUP_PLAY, SETUP_SET_WAIT, SETUP_WAIT,
		SETUP_IDLE, SETUP_PLAY, SETUP_FINISH,
	],
}

## `PokeAnim_Setup2`'s `ld b, 4`, which `PokeAnim_GetDuration` divides by 16.
const SLOW_SPEED: int = 4
## `PokeAnim_SetWait`'s own `ld a, 18`.
const WAIT_FRAMES: int = 18

## `AnimateFrontpic`'s loop has no `DelayFrame` of its own: the frame comes from
## `HDMATransferTilemapToWRAMBank3`, whose `WaitDMATransfer` is a `DelayFrame`
## loop. So a scene command that transfers again costs that again.
## `PokeAnim_SetVBank1` ends `Setup`, `Setup2` and `Idle` with one attrmap
## transfer; `PokeAnim_DeinitFrames` is a tilemap and an attrmap transfer, which
## is what `BasePic` and `Finish` are made of.
const EXTRA_TRANSFERS: Dictionary = {
	SETUP_SETUP: 1, SETUP_SETUP2: 1, SETUP_IDLE: 1,
	SETUP_BASE_PIC: 2, SETUP_FINISH: 2,
}

const ENDANIM: int = 0xFF
const SETREPEAT: int = 0xFE
const DOREPEAT: int = 0xFD

## `PokeAnim_PlaceGraphic`'s box, which is `PadFrontpic`'s.
const BOX: int = Gen2PicImage.FRONTPIC_TILES

## Which cry the scene command just reached asks for, or an empty StringName.
## `PokeAnim_StereoCry` is `PlayStereoCry2`, the one that does not wait;
## `PokeAnim_Cry` is `_PlayMonCry` and `PokeAnim_CryNoWait` is `PlayMonCry2`.
const CRY_STEREO: StringName = &"stereo"
const CRY_WAIT: StringName = &"wait"
const CRY_NO_WAIT: StringName = &"no_wait"

var _record: Dictionary = {}
var _height: int = 0
var _scene: Array = []
var _scene_index: int = 0
var _finished: bool = true

var _script: PackedByteArray = PackedByteArray()
var _speed: int = 0
var _frame: int = 0
var _repeat: int = 0
var _wait: int = 0
var _waiting: bool = false
var _script_done: bool = true
var _wait_counter: int = 0
var _extra: int = 0
var _finish_pending: bool = false

## The 7x7 box as `PokeAnim_PlaceGraphic` and `.ApplyFrame` last left it, as
## tile numbers counted from the pic's own first.
var box: PackedByteArray = PackedByteArray()

## `wBoxAlignment`, which `.GetCoord` walks its columns backwards for.
var mirrored: bool = false


## [param record] is [method GameData.pic_animation]'s answer. A record without
## a script animates nothing and [member finished] is true from the start, which
## is the answer a caller with no cache or a Gold and Silver cartridge gets.
func _init(record: Dictionary, kind: int = ANIM_MON_NORMAL, box_mirrored: bool = false) -> void:
	mirrored = box_mirrored
	_record = record
	_height = int(record.get("height", 0))
	if _height <= 0 or not SCENES.has(kind) \
			or (record.get("script", PackedByteArray()) as PackedByteArray).is_empty():
		return
	_scene = SCENES[kind]
	_scene_index = 0
	_finished = false
	_place_graphic()


## True once `PokeAnim_Finish` has run, which is what `AnimateFrontpic`'s
## `jr nc, .loop` stops on.
func finished() -> bool:
	return _finished


## One turn of `AnimateFrontpic`'s loop, which is one `SetUpPokeAnim` and so one
## hardware frame. Answers which cry this frame asked for, if any: the cry is
## the scene's own command rather than something around the animation.
func advance() -> StringName:
	if _finished:
		return &""
	# A command still paying for its own transfers has not moved on yet.
	if _extra > 0:
		_extra -= 1
		if _extra == 0 and _finish_pending:
			_finished = true
		return &""
	var command: int = int(_scene[mini(_scene_index, _scene.size() - 1)])
	_extra = int(EXTRA_TRANSFERS.get(command, 0))
	match command:
		SETUP_FINISH:
			_place_graphic()
			if _extra > 0:
				_finish_pending = true
			else:
				_finished = true
		SETUP_BASE_PIC:
			_place_graphic()
			_scene_index += 1
		SETUP_SET_WAIT:
			_wait_counter = WAIT_FRAMES
			_scene_index += 1
			# `PokeAnim_SetWait` falls through into `PokeAnim_Wait`, so the
			# frame it is reached on already spends one of the eighteen.
			_tick_wait()
		SETUP_WAIT:
			_tick_wait()
		SETUP_SETUP:
			_init_anim(false, 0)
		SETUP_SETUP2:
			_init_anim(false, SLOW_SPEED)
		SETUP_IDLE:
			_init_anim(true, 0)
		SETUP_PLAY:
			_do_anim_script()
			if _script_done:
				_place_graphic()
				_scene_index += 1
		SETUP_PLAY2:
			# The one difference from `PokeAnim_Play`: no `PlaceGraphic` at the
			# end, so the last frame of the script stays on the screen.
			_do_anim_script()
			if _script_done:
				_scene_index += 1
		SETUP_CRY:
			_scene_index += 1
			return CRY_WAIT
		SETUP_CRY_NO_WAIT:
			_scene_index += 1
			return CRY_NO_WAIT
		SETUP_STEREO_CRY:
			_scene_index += 1
			return CRY_STEREO
	return &""


func _tick_wait() -> void:
	_wait_counter -= 1
	if _wait_counter <= 0:
		_scene_index += 1


## `PokeAnim_InitAnim`: the script, its speed and whether it is the idle one.
func _init_anim(idle: bool, speed: int) -> void:
	_script = _record.get("idle" if idle else "script", PackedByteArray())
	_speed = speed
	_frame = 0
	_repeat = 0
	_waiting = false
	_script_done = _script.is_empty()
	_scene_index += 1


## `PokeAnim_DoAnimScript`, which is one command or one frame of a command's own
## duration. `.RunAnim` loops through `setrepeat` and `dorepeat` without
## spending a frame on either, which is what the `jr .loop` does.
func _do_anim_script() -> void:
	if _script_done:
		return
	if _waiting:
		_wait -= 1
		if _wait <= 0:
			_waiting = false
		return
	for _step: int in _script.size():
		var at: int = _frame * 2
		if at + 1 >= _script.size():
			_script_done = true
			return
		var command: int = int(_script[at])
		var parameter: int = int(_script[at + 1])
		_frame += 1
		match command:
			ENDANIM:
				_script_done = true
				return
			SETREPEAT:
				_repeat = parameter
				continue
			DOREPEAT:
				# `.DoRepeat` returns on a counter that is already zero and on
				# the one it takes to zero, so a `setrepeat n` runs the body n
				# times rather than n + 1.
				if _repeat == 0:
					return
				_repeat -= 1
				if _repeat == 0:
					return
				_frame = parameter
				continue
			_:
				_apply_frame(command)
				_wait = _duration(parameter)
				_waiting = true
				# `PokeAnim_StartWaitAnim` moves to `.WaitAnim`, which spends
				# this same frame decrementing the counter it was just given.
				_wait -= 1
				if _wait <= 0:
					_waiting = false
				return
	_script_done = true


## `PokeAnim_GetDuration`: `a * (1 + [wPokeAnimSpeed] / 16)`, built as an 8.8
## fixed-point multiply, so the fraction is truncated rather than rounded.
func _duration(base: int) -> int:
	@warning_ignore("integer_division")
	return base + (base * _speed) / 16


## `PokeAnim_GetFrame`: the base pic first, then this frame's own tiles over it.
## Command zero is the base pic on its own, which is what `and a / ret z` is.
func _apply_frame(command: int) -> void:
	_place_graphic()
	if command == 0:
		return
	var frames: Array = _record.get("frames", []) as Array
	if command - 1 >= frames.size():
		return
	var frame: PackedByteArray = frames[command - 1]
	var mask_bytes: int = RomLayout.pic_anim_bitmask_bytes(_height)
	if frame.size() < mask_bytes:
		return

	# `PokeAnim_ConvertAndApplyBitmask` walks the pic's own square column by
	# column, one bit of the bitmask per cell, and takes the next tile number
	# from the frame for every set bit.
	#
	# `.GetStartCoord` is `PadFrontpic`'s alignment a third time: a pic shorter
	# than the box starts one column in and its own difference down.
	var pad_column: int = 0 if _height >= BOX else 1
	var pad_row: int = BOX - _height
	var next: int = mask_bytes
	for column: int in _height:
		for row: int in _height:
			var bit: int = column * _height + row
			@warning_ignore("integer_division")
			var byte: int = int(frame[bit / 8])
			if (byte >> (bit % 8)) & 1 == 0:
				continue
			if next >= frame.size():
				return
			var tile: int = int(frame[next])
			next += 1
			# `.subtract`: the mirrored walk starts at the box's other end and
			# runs its columns back, which is `PlaceGraphic`'s own `.flipped`.
			var x: int = BOX - 1 - pad_column - column if mirrored \
				else pad_column + column
			box[x * BOX + pad_row + row] = \
				RomLayout.pic_anim_box_tile(tile, _height) & 0xFF


## `PokeAnim_PlaceGraphic`: the whole 7x7 box filled column by column, which is
## the base pic as `PadFrontpic` laid it out. `.flipped` runs the columns the
## other way, and the box is indexed here rather than the tilemap, so the caller
## stamps it wherever the picture stands.
func _place_graphic() -> void:
	box.resize(BOX * BOX)
	for column: int in BOX:
		for row: int in BOX:
			var x: int = BOX - 1 - column if mirrored else column
			box[x * BOX + row] = column * BOX + row
