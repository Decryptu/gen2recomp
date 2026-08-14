extends GutTest

## The battle animation command interpreter
## (engine/battle_anims/anim_commands.asm), against hand-built regions.
##
## The real cartridges are `tools/checks/battle_anims.gd`'s job; what is here
## is the vocabulary and the control flow, including the shapes no shipped
## animation uses.

## Where a built region starts, so nothing passes by accident on a zero base.
const BASE: int = 0x5000


## Assembles a region from a flat byte list. Addresses inside it are
## [constant BASE] plus the position.
func _region(bytes: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(bytes.size())
	for index: int in bytes.size():
		out[index] = int(bytes[index]) & 0xFF
	return out


func _script(bytes: Array, param: int = 0, at: int = BASE) -> Gen2BattleAnimScript:
	return Gen2BattleAnimScript.create(_region(bytes), BASE, at, param)


## Every command a frame ran, as [code][name, operands][/code] pairs.
func _names(ran: Array) -> Array:
	return ran.map(func(command: Dictionary) -> Array:
		return [command["name"], Array(command["operands"])])


## Runs to a stop, collecting each frame's commands separately.
func _frames(script: Gen2BattleAnimScript, limit: int = 512) -> Array:
	var out: Array = []
	var frames: int = 0
	while not script.finished() and frames < limit:
		frames += 1
		out.append(_names(script.advance_frame()))
	return out


## `BattleAnim_Pound`, the same eighteen bytes in all three cartridges, decoded
## command by command. `anim_sound 0, 1, SFX_POUND` packs its duration and track
## mask into one byte, `(0 << 2) | 1`, which is why the operand is $01 and not
## a pair.
func test_pound_decodes_to_its_seven_commands() -> void:
	var script: Gen2BattleAnimScript = _script(Gen2BattleAnimImporter.POUND_BYTES)
	var frames: Array = _frames(script)
	assert_true(script.finished())
	assert_false(script.failed())

	var ran: Array = []
	for frame: Array in frames:
		ran.append_array(frame)
	assert_eq(ran, [
		[&"gfx_1", [0x01]],
		[&"sound", [0x01, 0x31]],
		[&"obj", [0x08, 136, 56, 0x00]],
		[&"wait", [6]],
		[&"obj", [0x01, 136, 56, 0x00]],
		[&"wait", [16]],
		[&"ret", []],
	])


## `RunBattleAnimCommand.CheckTimer` decrements the delay and runs nothing while
## it is non-zero, so `anim_wait N` costs exactly N frames and the command that
## set it is on the frame before them.
func test_a_wait_costs_its_own_number_of_frames() -> void:
	var script: Gen2BattleAnimScript = _script([0xE9, 0x03, 0xFF])
	assert_eq(_names(script.advance_frame()), [[&"minimize", []], [&"wait", [3]]])
	assert_eq(script.delay(), 3)
	for frame: int in 3:
		assert_eq(script.advance_frame(), [], "frame %d of the wait runs nothing" % frame)
	assert_eq(_names(script.advance_frame()), [[&"ret", []]])
	assert_true(script.finished())


## `.RunScript` loops until a delay byte or a top-level `anim_ret`, so a run of
## commands with no wait between them all happens on one frame.
func test_commands_without_a_wait_share_one_frame() -> void:
	var frames: Array = _frames(_script([0xFA, 0xFA, 0xFA, 0xFF]))
	assert_eq(frames.size(), 1)
	assert_eq(frames[0], [[&"inc_var", []], [&"inc_var", []], [&"inc_var", []], [&"ret", []]])


## A byte below $d0 is not a command at all: `.not_done_with_anim` stores it and
## returns before the jumptable is reached.
func test_the_command_table_starts_at_d0() -> void:
	assert_eq(Gen2BattleAnimScript.FIRST_COMMAND, 0xD0)
	assert_eq(Gen2BattleAnimScript.COMMANDS.size(), 0x100 - 0xD0)
	var script: Gen2BattleAnimScript = _script([0xCF, 0xFF])
	assert_eq(_names(script.advance_frame()), [[&"wait", [0xCF]]])


## `$d9` assembles from `anim_battlergfx_2row` and dispatches to
## `BattleAnimCmd_BattlerGFX_1Row`; `$da` is the other way round. The routine is
## what runs, so the routine is what the command is called.
func test_the_two_battler_graphics_commands_are_named_for_their_routines() -> void:
	var frames: Array = _frames(_script([0xD9, 0xDA, 0xFF]))
	assert_eq(frames[0], [
		[&"battler_gfx_1row", []], [&"battler_gfx_2row", []], [&"ret", []],
	])


## `BattleAnimCmd_Ret` returns to the single `wBattleAnimParent` word inside a
## subroutine and sets BATTLEANIM_STOP_F at the top level.
func test_a_call_returns_and_the_top_level_ret_stops() -> void:
	# call $5005, inc_var, ret | (at $5005) inc_var, ret
	var script: Gen2BattleAnimScript = _script([0xFE, 0x05, 0x50, 0xFA, 0xFF, 0xFA, 0xFF])
	var frames: Array = _frames(script)
	assert_eq(frames.size(), 1)
	assert_eq(frames[0], [
		[&"call", [0x05, 0x50]],
		[&"inc_var", []],
		[&"ret", []],
		[&"inc_var", []],
		[&"ret", []],
	], "the subroutine's ret continues the frame, the outer one ends it")
	assert_eq(script.variable(), 2)
	assert_true(script.finished())


## There is no stack: `wBattleAnimParent` is one word, so a call inside a call
## loses the outer return address and the second ret walks on into whatever
## follows. Reproduced rather than generalised.
func test_a_nested_call_loses_the_outer_return() -> void:
	var script: Gen2BattleAnimScript = _script([
		0xFE, 0x06, 0x50,  # $5000 call $5006
		0xFF,              # $5003 ret       (never reached)
		0xFA, 0xFF,        # $5004 inc_var, ret
		0xFE, 0x04, 0x50,  # $5006 call $5004
		0xFF,              # $5009 ret
	])
	_frames(script)
	# The inner call overwrote the parent with $5009, so the first ret lands
	# there and the second is the one that stops.
	assert_true(script.finished())
	assert_false(script.failed())
	assert_eq(script.variable(), 1)


## `BattleAnimCmd_Loop`: the count is stored one lower, so `anim_loop 1` never
## jumps and `anim_loop 3` jumps twice. `.return_from_loop` clears the flag and
## skips the address rather than reading it.
func test_a_loop_runs_its_count_and_then_falls_through() -> void:
	# inc_var, loop 3 -> $5000, ret
	var script: Gen2BattleAnimScript = _script([0xFA, 0xFD, 0x03, 0x00, 0x50, 0xFF])
	_frames(script)
	assert_eq(script.variable(), 3, "three passes over the body")
	assert_true(script.finished())

	var once: Gen2BattleAnimScript = _script([0xFA, 0xFD, 0x01, 0x00, 0x50, 0xFF])
	_frames(once)
	assert_eq(once.variable(), 1, "a count of one falls straight through")


## A count of zero never claims the loop flag, so it re-reads its own zero and
## jumps forever. The cartridge hangs here; [constant MAX_COMMANDS_PER_FRAME] is
## ours and turns it into a refused animation.
func test_a_perpetual_loop_fails_rather_than_hanging() -> void:
	var script: Gen2BattleAnimScript = _script([0xFD, 0x00, 0x00, 0x50, 0xFF])
	var ran: Array = script.advance_frame()
	assert_eq(ran.size(), Gen2BattleAnimScript.MAX_COMMANDS_PER_FRAME)
	assert_true(script.failed())
	assert_true(script.finished(), "a failed script is finished")


## `BattleAnimCmd_JumpUntil` spends `wBattleAnimParam` down rather than keeping
## a counter of its own, so the caller's own value decides how many times it
## goes round. That is what the multi-hit animations are.
func test_jump_until_spends_the_param() -> void:
	# inc_var, jumpuntil $5000, ret
	var bytes: Array = [0xFA, 0xEF, 0x00, 0x50, 0xFF]
	var twice: Gen2BattleAnimScript = _script(bytes, 2)
	_frames(twice)
	assert_eq(twice.variable(), 3, "the body runs once more than the param")

	var none: Gen2BattleAnimScript = _script(bytes, 0)
	_frames(none)
	assert_eq(none.variable(), 1)


## The three conditional jumps, each of which skips its own two address bytes
## when it does not take the branch.
func test_the_conditional_jumps_read_the_param_and_the_var() -> void:
	# if_param_and $06 -> $5006, inc_var, ret | ($5006) set_var $09, ret
	var bytes: Array = [0xEE, 0x06, 0x06, 0x50, 0xFA, 0xFF, 0xF9, 0x09, 0xFF]
	var hit: Gen2BattleAnimScript = _script(bytes, 0x04)
	_frames(hit)
	assert_eq(hit.variable(), 0x09, "a shared bit takes the branch")

	var missed: Gen2BattleAnimScript = _script(bytes, 0x01)
	_frames(missed)
	assert_eq(missed.variable(), 1, "no shared bit falls through")

	# if_param_equal $02 -> $5006 over the same tail.
	var equal: Gen2BattleAnimScript = _script(
		[0xF8, 0x02, 0x06, 0x50, 0xFA, 0xFF, 0xF9, 0x09, 0xFF], 0x02
	)
	_frames(equal)
	assert_eq(equal.variable(), 0x09)

	# set_var $07, if_var_equal $07 -> $5008, inc_var, ret | ($5008) set_var $01, ret
	var by_var: Gen2BattleAnimScript = _script(
		[0xF9, 0x07, 0xFB, 0x07, 0x08, 0x50, 0xFA, 0xFF, 0xF9, 0x01, 0xFF]
	)
	_frames(by_var)
	assert_eq(by_var.variable(), 0x01)


## `wBattleAnimVar` starts at zero because `ClearBattleAnims` zeroes
## `wLYOverrides` through `wBattleAnimEnd`; `wBattleAnimParam` sits outside that
## run and is the caller's input.
func test_the_var_starts_at_zero_and_the_param_is_given() -> void:
	var script: Gen2BattleAnimScript = _script([0xFF], 0x1F)
	assert_eq(script.variable(), 0)
	assert_eq(script.address(), BASE)


## An address outside the region, and a command whose operands run past its end.
## Both are refused rather than read out of whatever is next in memory.
func test_a_script_outside_its_region_fails_at_once() -> void:
	var outside: Gen2BattleAnimScript = _script([0xFF], 0, BASE + 8)
	assert_true(outside.failed())
	assert_true(outside.finished())
	assert_eq(outside.advance_frame(), [])

	var truncated: Gen2BattleAnimScript = _script([0xD0, 0x08, 0x88])
	assert_eq(truncated.advance_frame(), [], "anim_obj wants four operands and has three")
	assert_true(truncated.failed())


## The shared decoder, which the importer walks every body with. A branch
## command reports where it would go; everything else reports -1.
func test_decode_command_reports_operands_and_branch_targets() -> void:
	var region: PackedByteArray = _region([0xFC, 0x34, 0x12, 0xE0, 0x01, 0x31])
	var jump: Dictionary = Gen2BattleAnimScript.decode_command(region, BASE, BASE)
	assert_eq(jump["name"], &"jump")
	assert_eq(jump["size"], 3)
	assert_eq(jump["target"], 0x1234)

	var sound: Dictionary = Gen2BattleAnimScript.decode_command(region, BASE, BASE + 3)
	assert_eq(sound["name"], &"sound")
	assert_eq(Array(sound["operands"]), [0x01, 0x31])
	assert_eq(sound["target"], -1)

	assert_false(
		bool(Gen2BattleAnimScript.decode_command(region, BASE, BASE - 1).get("ok", false))
	)
