class_name Gen2WorldMovement
extends RefCounted

## Decoder for the bounded movement streams referenced by applymovement.
## Movement data is byte-coded and ends at step_end ($47). The decoder keeps
## parameter bytes attached to their command so execution cannot accidentally
## interpret a parameter as a second movement command.

const MAX_BYTES: int = 128
const MAX_COMMANDS: int = 128
const STEP_END: int = 0x47

static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "reason": &"missing_movement"}
	var commands: Array = []
	var at: int = 0
	while at < data.size() and commands.size() < MAX_COMMANDS:
		var opcode: int = int(data[at])
		if opcode == STEP_END:
			return {"ok": true, "commands": commands, "bytes": at + 1}
		var width: int = 1
		var command: Dictionary = {"opcode": opcode, "offset": at, "width": width}
		if opcode < 0x38:
			var group: int = opcode & 0xFC
			command["kind"] = _direction_kind(group)
			command["direction"] = opcode & 0x03
		elif opcode >= 0x3E and opcode <= 0x45:
			command["kind"] = &"step_sleep"
			command["length"] = opcode - 0x3D
		elif opcode == 0x46:
			if at + 1 >= data.size():
				return _truncated(at, opcode, 2)
			width = 2
			command["kind"] = &"step_sleep"
			command["length"] = int(data[at + 1])
		elif opcode in [0x48, 0x4F, 0x55, 0x57, 0x58]:
			if at + 1 >= data.size():
				return _truncated(at, opcode, 2)
			width = 2
			command["value"] = int(data[at + 1])
			command["kind"] = {
				0x48: &"step_wait_end", 0x4F: &"step_dig",
				0x55: &"step_shake", 0x57: &"rock_smash", 0x58: &"return_dig",
			}[opcode]
		elif opcode in range(0x38, 0x46) or opcode in range(0x49, 0x55) \
			or opcode in [0x56, 0x59]:
			command["kind"] = _control_kind(opcode)
		else:
			return {
				"ok": false, "reason": &"unsupported_movement_command",
				"offset": at, "opcode": opcode,
			}
		commands.append(command)
		at += width
	return {
		"ok": false,
		"reason": &"movement_terminator_missing" if commands.size() < MAX_COMMANDS else &"movement_command_limit",
		"commands": commands,
	}


static func _direction_kind(group: int) -> StringName:
	return {
		0x00: &"turn_head", 0x04: &"turn_step", 0x08: &"slow_step",
		0x0C: &"step", 0x10: &"big_step", 0x14: &"slow_slide_step",
		0x18: &"slide_step", 0x1C: &"fast_slide_step", 0x20: &"turn_away",
		0x24: &"turn_in", 0x28: &"turn_waterfall", 0x2C: &"slow_jump_step",
		0x30: &"jump_step", 0x34: &"fast_jump_step",
	}.get(group, &"direction_command")


static func _control_kind(opcode: int) -> StringName:
	return {
		0x38: &"remove_sliding", 0x39: &"set_sliding",
		0x3A: &"remove_fixed_facing", 0x3B: &"fix_facing",
		0x3C: &"show_object", 0x3D: &"hide_object",
		0x49: &"remove_object", 0x4A: &"step_loop", 0x4B: &"step_stop",
		0x4C: &"teleport_from", 0x4D: &"teleport_to", 0x4E: &"skyfall",
		0x50: &"step_bump", 0x51: &"fish_got_bite", 0x52: &"fish_cast_rod",
		0x53: &"hide_emote", 0x54: &"show_emote", 0x56: &"tree_shake",
		0x59: &"skyfall_top",
	}.get(opcode, &"control_command")


static func _truncated(offset: int, opcode: int, width: int) -> Dictionary:
	return {
		"ok": false, "reason": &"truncated_movement_operands",
		"offset": offset, "opcode": opcode, "width": width,
	}
