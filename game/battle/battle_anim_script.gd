class_name Gen2BattleAnimScript
extends RefCounted

## The battle animation command interpreter
## (engine/battle_anims/anim_commands.asm).
##
## Scene-free like the rest of the battle layer: the screen ticks this once per
## hardware frame and reads back the commands that ran, the way it ticks the
## bars and the intro. Nothing here draws, plays a sound or touches a palette;
## the commands are reported and whoever is drawing decides what they look like.
##
## A script is a byte stream in one bank. Anything below
## [constant FIRST_COMMAND] is not a command at all: `RunBattleAnimCommand`
## stores it in `wBattleAnimDelay` and `.CheckTimer` then decrements it once a
## frame and runs nothing while it is non-zero, so `anim_wait N` is exactly N
## frames of pause. Everything from [constant FIRST_COMMAND] up dispatches
## through `BattleAnimCommands`, which is what [constant COMMANDS] is.
##
## The control-flow state is the cartridge's, which means one level of nesting
## and no more: `anim_call` saves the return address in the single
## `wBattleAnimParent` word and `anim_loop` counts in the single
## `wBattleAnimLoops` byte, so a call inside a call or a loop inside a loop
## loses the outer one. Both are reproduced rather than generalised.
##
## `wBattleAnimParam` is an input the battle engine writes before playing
## (engine/battle/effect_commands.asm), and `wBattleAnimVar` is animation-local:
## `ClearBattleAnims` zeroes `wLYOverrides` through `wBattleAnimEnd`, which
## covers the var and not the param.

## `FIRST_BATTLE_ANIM_CMD` (macros/scripts/battle_anims.asm). Every byte under it
## is a delay.
const FIRST_COMMAND: int = 0xD0

## `BattleAnimCommands` in order, from [constant FIRST_COMMAND].
##
## The names are the jumptable's, not the macros': `$d9` assembles from
## `anim_battlergfx_2row` but dispatches to `BattleAnimCmd_BattlerGFX_1Row`, and
## `$da` the other way round. The routines are what run, so they are what the
## commands are called here; the two are genuinely crosswise in both pins.
##
## `operands` is how many bytes follow the command byte. `target` is where the
## low byte of a jump address sits inside them, or -1 for a command that never
## branches.
const COMMANDS: Array[Dictionary] = [
	{"name": &"obj", "operands": 4, "target": -1},
	{"name": &"gfx_1", "operands": 1, "target": -1},
	{"name": &"gfx_2", "operands": 2, "target": -1},
	{"name": &"gfx_3", "operands": 3, "target": -1},
	{"name": &"gfx_4", "operands": 4, "target": -1},
	{"name": &"gfx_5", "operands": 5, "target": -1},
	{"name": &"inc_obj", "operands": 1, "target": -1},
	{"name": &"set_obj", "operands": 2, "target": -1},
	{"name": &"inc_bg_effect", "operands": 1, "target": -1},
	{"name": &"battler_gfx_1row", "operands": 0, "target": -1},
	{"name": &"battler_gfx_2row", "operands": 0, "target": -1},
	{"name": &"check_pokeball", "operands": 0, "target": -1},
	{"name": &"transform", "operands": 0, "target": -1},
	{"name": &"raise_sub", "operands": 0, "target": -1},
	{"name": &"drop_sub", "operands": 0, "target": -1},
	{"name": &"reset_obp0", "operands": 0, "target": -1},
	{"name": &"sound", "operands": 2, "target": -1},
	{"name": &"cry", "operands": 1, "target": -1},
	{"name": &"minimize_opp", "operands": 0, "target": -1},
	{"name": &"oam_on", "operands": 0, "target": -1},
	{"name": &"oam_off", "operands": 0, "target": -1},
	{"name": &"clear_objs", "operands": 0, "target": -1},
	{"name": &"beat_up", "operands": 0, "target": -1},
	{"name": &"e7", "operands": 0, "target": -1},
	{"name": &"update_actor_pic", "operands": 0, "target": -1},
	{"name": &"minimize", "operands": 0, "target": -1},
	{"name": &"ea", "operands": 0, "target": -1},
	{"name": &"eb", "operands": 0, "target": -1},
	{"name": &"ec", "operands": 0, "target": -1},
	{"name": &"ed", "operands": 0, "target": -1},
	{"name": &"if_param_and", "operands": 3, "target": 1},
	{"name": &"jump_until", "operands": 2, "target": 0},
	{"name": &"bg_effect", "operands": 4, "target": -1},
	{"name": &"bgp", "operands": 1, "target": -1},
	{"name": &"obp0", "operands": 1, "target": -1},
	{"name": &"obp1", "operands": 1, "target": -1},
	{"name": &"keep_sprites", "operands": 0, "target": -1},
	{"name": &"f5", "operands": 0, "target": -1},
	{"name": &"f6", "operands": 0, "target": -1},
	{"name": &"f7", "operands": 0, "target": -1},
	{"name": &"if_param_equal", "operands": 3, "target": 1},
	{"name": &"set_var", "operands": 1, "target": -1},
	{"name": &"inc_var", "operands": 0, "target": -1},
	{"name": &"if_var_equal", "operands": 3, "target": 1},
	{"name": &"jump", "operands": 2, "target": 0},
	{"name": &"loop", "operands": 3, "target": 1},
	{"name": &"call", "operands": 2, "target": 0},
	{"name": &"ret", "operands": 0, "target": -1},
]

## The name a delay byte is reported under. Not a `BattleAnimCommands` entry:
## `.RunScript` never reaches the jumptable for one.
const WAIT: StringName = &"wait"

const OBJ: StringName = &"obj"
const SOUND: StringName = &"sound"
## The two that write a battler's own picture rather than an animation object:
## `GetSubstitutePic` puts the doll over it and `DropPlayerSub` puts it back.
const RAISE_SUB: StringName = &"raise_sub"
const DROP_SUB: StringName = &"drop_sub"
const CRY: StringName = &"cry"
const JUMP: StringName = &"jump"
const LOOP: StringName = &"loop"
const CALL: StringName = &"call"
const RET: StringName = &"ret"
const JUMP_UNTIL: StringName = &"jump_until"
const IF_PARAM_AND: StringName = &"if_param_and"
const IF_PARAM_EQUAL: StringName = &"if_param_equal"
const IF_VAR_EQUAL: StringName = &"if_var_equal"
const SET_VAR: StringName = &"set_var"
const INC_VAR: StringName = &"inc_var"

## How many commands one frame may run before the script is abandoned.
##
## The cartridge has no such limit: `.RunScript` loops until a delay byte or a
## top-level `anim_ret`, and a script that does neither hangs the hardware. This
## is ours, so a malformed cached region or a mod's own script costs a refused
## animation rather than a frozen game. The worst shipped frame across all three
## dumps runs seventeen commands.
const MAX_COMMANDS_PER_FRAME: int = 256

## Where the cached region starts, as the cartridge addresses it, and the bytes
## themselves. Every pointer inside a script is bank-local and every byte is read
## through `BANK(BattleAnimations)` (home/battle.asm, `GetBattleAnimByte`), so an
## address resolves by subtraction and nothing has to model banking.
var _region: PackedByteArray = PackedByteArray()
var _base_address: int = 0

var _address: int = 0
var _parent: int = 0
var _in_subroutine: bool = false
var _in_loop: bool = false
var _loops: int = 0
var _delay: int = 0
var _var: int = 0
var _param: int = 0
var _stopped: bool = false
var _failed: bool = false


## An interpreter positioned at [param address] inside [param region], which
## starts at [param base_address].
##
## [param param] is `wBattleAnimParam`, which the caller sets before playing;
## `wBattleAnimVar` starts at zero because `ClearBattleAnims` clears it.
static func create(
	region: PackedByteArray, base_address: int, start_address: int, param: int = 0
) -> Gen2BattleAnimScript:
	var script := Gen2BattleAnimScript.new()
	script._region = region
	script._base_address = base_address
	script._address = start_address
	script._param = param & 0xFF
	script._stopped = not script._holds(start_address)
	script._failed = script._stopped
	return script


## Decodes one command at [param start_address]. Returns
## [code]{ ok, name, byte, operands, size, target }[/code]; `target` is the
## start_address a branch would take, or -1. A delay byte answers [constant WAIT] with
## its own value as its single operand.
##
## Shared with [Gen2BattleAnimImporter], which walks every body with it, so the
## vocabulary is stated once.
static func decode_command(
	region: PackedByteArray, base_address: int, at_address: int
) -> Dictionary:
	var at: int = at_address - base_address
	if at < 0 or at >= region.size():
		return {"ok": false}
	var byte: int = region[at]
	if byte < FIRST_COMMAND:
		return {
			"ok": true, "name": WAIT, "byte": byte, "operands": [byte],
			"size": 1, "target": -1,
		}
	var command: Dictionary = COMMANDS[byte - FIRST_COMMAND]
	var count: int = int(command["operands"])
	if at + 1 + count > region.size():
		return {"ok": false}
	var operands: Array[int] = []
	for index: int in count:
		operands.append(region[at + 1 + index])
	var target: int = -1
	var target_at: int = int(command["target"])
	if target_at >= 0:
		target = operands[target_at] | (operands[target_at + 1] << 8)
	return {
		"ok": true, "name": command["name"], "byte": byte, "operands": operands,
		"size": 1 + count, "target": target,
	}


func finished() -> bool:
	return _stopped


## True when the script ran off the region or past
## [constant MAX_COMMANDS_PER_FRAME]. A failed script is also finished.
func failed() -> bool:
	return _failed


## Frames still owed before the next command runs: `wBattleAnimDelay`.
func delay() -> int:
	return _delay


## Where the next byte will be read from, as the cartridge addresses it.
func address() -> int:
	return _address


## `wBattleAnimVar`.
func variable() -> int:
	return _var


## One hardware frame of `RunBattleAnimCommand`, as an Array of the commands it
## ran, each [code]{ name, byte, operands }[/code].
##
## Empty while a delay is counting down, which is most frames, and empty once
## the script has stopped. A frame that runs commands ends either on the delay
## byte that set the next pause or on the `anim_ret` that ended the script, and
## that terminating command is in the Array: `.RunScript` executed it.
func advance_frame() -> Array:
	if _stopped:
		return []
	if _delay > 0:
		_delay -= 1
		return []

	var ran: Array = []
	for _step: int in MAX_COMMANDS_PER_FRAME:
		var command: Dictionary = decode_command(_region, _base_address, _address)
		if not bool(command.get("ok", false)):
			_fail()
			return ran
		_address += int(command["size"])
		ran.append({
			"name": command["name"], "byte": command["byte"], "operands": command["operands"],
		})
		if _execute(command):
			return ran
	_fail()
	return ran


## Runs one decoded command. Answers whether the frame ends here, which is what
## a delay byte and a top-level `anim_ret` do.
func _execute(command: Dictionary) -> bool:
	var name: StringName = command["name"]
	var operands: Array = command["operands"]
	match name:
		WAIT:
			_delay = int(operands[0])
			return true
		RET:
			# `.RunScript` reaches `BattleAnimCmd_Ret` only inside a subroutine;
			# at the top level it sets BATTLEANIM_STOP_F without dispatching.
			if _in_subroutine:
				_in_subroutine = false
				_address = _parent
				return false
			_stopped = true
			return true
		CALL:
			_parent = _address
			_in_subroutine = true
			_address = int(command["target"])
		JUMP:
			_address = int(command["target"])
		LOOP:
			_run_loop(int(operands[0]), int(command["target"]))
		JUMP_UNTIL:
			# Spends `wBattleAnimParam` rather than keeping a counter of its own,
			# so the caller decides how many times this goes round.
			if _param > 0:
				_param -= 1
				_address = int(command["target"])
		IF_PARAM_AND:
			if (_param & int(operands[0])) != 0:
				_address = int(command["target"])
		IF_PARAM_EQUAL:
			if int(operands[0]) == _param:
				_address = int(command["target"])
		IF_VAR_EQUAL:
			if int(operands[0]) == _var:
				_address = int(command["target"])
		SET_VAR:
			_var = int(operands[0])
		INC_VAR:
			_var = (_var + 1) & 0xFF
	return false


## `BattleAnimCmd_Loop`. A count of zero loops forever without ever claiming the
## loop flag, so it re-reads its own zero every time round; any other count is
## stored one lower, which is why `anim_loop 1` falls straight through.
func _run_loop(count: int, target: int) -> void:
	if not _in_loop:
		if count == 0:
			_address = target
			return
		_loops = count - 1
		_in_loop = true
	if _loops > 0:
		_loops -= 1
		_address = target
		return
	_in_loop = false


func _holds(at_address: int) -> bool:
	var at: int = at_address - _base_address
	return at >= 0 and at < _region.size()


func _fail() -> void:
	_failed = true
	_stopped = true
