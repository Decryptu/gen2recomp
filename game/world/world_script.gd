class_name Gen2WorldScript
extends RefCounted

## Shared Generation 2 overworld script command definitions.
##
## The cartridge stores one command byte followed by command-specific operands.
## This file deliberately describes only the first runtime slice. Unknown
## commands remain visible to the caller instead of being guessed or skipped.

const SCALL: int = 0x00
const FARSCALL: int = 0x01
const SJUMP: int = 0x03
const FARSJUMP: int = 0x04
const SETSCENE: int = 0x14
const CLEAREVENT: int = 0x32
const SETEVENT: int = 0x33
const WARP: int = 0x3C
const OPENTEXT: int = 0x47
const CLOSETEXT: int = 0x49
const FARWRITETEXT: int = 0x4B
const WRITETEXT: int = 0x4C
const REPEATTEXT: int = 0x4D
const JUMPTEXTFACEPLAYER: int = 0x51
const FARJUMPTEXT: int = 0x52
const JUMPTEXT: int = 0x53
const WAITBUTTON: int = 0x54
const PROMPTBUTTON: int = 0x55
const GOLD_JUMPTEXT: int = 0x52
const GOLD_WAITBUTTON: int = 0x53
const GOLD_PROMPTBUTTON: int = 0x54
const FACEPLAYER: int = 0x6B
const ENDCALLBACK: int = 0x90
const END: int = 0x91

const TEXT_START: int = 0x00
const TEXT_TERMINATOR: int = Gen2Text.TERMINATOR

const MAX_COMMANDS: int = 128
const MAX_CALL_DEPTH: int = 8
const MAX_SCRIPT_BYTES: int = 512
const MAX_TEXT_BYTES: int = 1024


static func pointer_key(bank: int, address: int) -> String:
	return "%d:%04X" % [bank, address]


static func command_name(opcode: int, crystal_commands: bool = true) -> StringName:
	match opcode:
		SCALL:
			return &"scall"
		FARSCALL:
			return &"farscall"
		SJUMP:
			return &"sjump"
		FARSJUMP:
			return &"farsjump"
		SETSCENE:
			return &"setscene"
		CLEAREVENT:
			return &"clearevent"
		SETEVENT:
			return &"setevent"
		WARP:
			return &"warp"
		OPENTEXT:
			return &"opentext"
		CLOSETEXT:
			return &"closetext"
		FARWRITETEXT:
			return &"farwritetext"
		WRITETEXT:
			return &"writetext"
		REPEATTEXT:
			return &"repeattext"
		JUMPTEXTFACEPLAYER:
			return &"jumptextfaceplayer"
		FARJUMPTEXT:
			return &"farjumptext" if crystal_commands else &"jumptext"
		JUMPTEXT:
			return &"jumptext" if crystal_commands else &"waitbutton"
		WAITBUTTON:
			return &"waitbutton" if crystal_commands else &"promptbutton"
		PROMPTBUTTON:
			return &"promptbutton" if crystal_commands else &"unsupported"
		FACEPLAYER:
			return &"faceplayer"
		ENDCALLBACK:
			return &"endcallback"
		END:
			return &"end"
	return &""


static func command_width(opcode: int, crystal_commands: bool = true) -> int:
	if crystal_commands:
		match opcode:
			FARJUMPTEXT:
				return 4
			JUMPTEXT:
				return 3
			WAITBUTTON, PROMPTBUTTON:
				return 1
	else:
		match opcode:
			GOLD_JUMPTEXT:
				return 3
			GOLD_WAITBUTTON, GOLD_PROMPTBUTTON:
				return 1
	match opcode:
		SCALL, SJUMP, WRITETEXT, JUMPTEXTFACEPLAYER:
			return 3
		FARSCALL, FARSJUMP, FARWRITETEXT:
			return 4
		SETSCENE:
			return 2
		CLEAREVENT, SETEVENT:
			return 3
		WARP:
			return 5
		REPEATTEXT:
			return 3
		OPENTEXT, CLOSETEXT, FACEPLAYER, ENDCALLBACK, END:
			return 1
	return 0


static func is_terminal(opcode: int) -> bool:
	return opcode == END or opcode == ENDCALLBACK


static func read_u16(data: PackedByteArray, offset: int) -> int:
	return int(data[offset]) | (int(data[offset + 1]) << 8)


static func command_at(
	data: PackedByteArray, offset: int, crystal_commands: bool = true
) -> Dictionary:
	if offset < 0 or offset >= data.size():
		return {"ok": false, "reason": &"truncated_opcode", "offset": offset}
	var opcode: int = int(data[offset])
	var width: int = command_width(opcode, crystal_commands)
	if width <= 0:
		return {
			"ok": false,
			"reason": &"unsupported_command",
			"offset": offset,
			"opcode": opcode,
			"name": command_name(opcode, crystal_commands),
		}
	if offset + width > data.size():
		return {
			"ok": false,
			"reason": &"truncated_operands",
			"offset": offset,
			"opcode": opcode,
			"name": command_name(opcode, crystal_commands),
			"width": width,
		}
	var command: Dictionary = {
		"ok": true,
		"offset": offset,
		"opcode": opcode,
		"name": command_name(opcode, crystal_commands),
		"width": width,
	}
	if opcode in [SCALL, SJUMP, WRITETEXT, JUMPTEXTFACEPLAYER] \
		or (crystal_commands and opcode == JUMPTEXT) \
		or (not crystal_commands and opcode == GOLD_JUMPTEXT):
			command["address"] = read_u16(data, offset + 1)
	elif opcode in [FARSCALL, FARSJUMP, FARWRITETEXT] \
		or (crystal_commands and opcode == FARJUMPTEXT):
			command["bank"] = int(data[offset + 1])
			command["address"] = read_u16(data, offset + 2)
	else:
		match opcode:
			SETSCENE:
				command["scene"] = int(data[offset + 1])
			CLEAREVENT, SETEVENT:
				command["flag"] = read_u16(data, offset + 1)
			WARP:
				command["map_group"] = int(data[offset + 1])
				command["map_number"] = int(data[offset + 2])
				command["x"] = int(data[offset + 3])
				command["y"] = int(data[offset + 4])
			REPEATTEXT:
				command["text_address"] = read_u16(data, offset + 1)
	return command


static func scan_references(
	data: PackedByteArray, bank: int, address: int, crystal_commands: bool = true
) -> Dictionary:
	## Scans only commands understood by this slice. An unknown command stops the
	## scan because its operand width cannot be inferred safely.
	var scripts: Array = []
	var texts: Array = []
	var at: int = 0
	var command_count: int = 0
	while at < data.size() and command_count < MAX_COMMANDS:
		var command: Dictionary = command_at(data, at, crystal_commands)
		if not bool(command.get("ok", false)):
			break
		var opcode: int = int(command["opcode"])
		match opcode:
			SCALL, SJUMP:
				scripts.append({"bank": bank, "address": int(command["address"])})
			FARSCALL, FARSJUMP:
				scripts.append({"bank": int(command["bank"]), "address": int(command["address"])})
			WRITETEXT, JUMPTEXTFACEPLAYER:
				texts.append({"bank": bank, "address": int(command["address"])})
			JUMPTEXT:
				if crystal_commands:
					texts.append({"bank": bank, "address": int(command["address"])})
			FARWRITETEXT:
				texts.append({"bank": int(command["bank"]), "address": int(command["address"])})
			FARJUMPTEXT:
				if crystal_commands:
					texts.append({"bank": int(command["bank"]), "address": int(command["address"])})
				else:
					texts.append({"bank": bank, "address": int(command["address"])})
			REPEATTEXT:
				var text_address: int = int(command["text_address"])
				if text_address != 0xFFFF:
					texts.append({"bank": bank, "address": text_address})
		at += int(command["width"])
		command_count += 1
		if is_terminal(opcode):
			break
	return {"scripts": scripts, "texts": texts}


## Decodes the bounded text slice collected by the importer. Text resources in
## the cartridge begin with TX_START and end with the same $50 terminator used
## by the existing Gen2Text codec. Bytes that are not part of its known glyph
## table remain visible as bracketed markers instead of being discarded.
static func decode_text(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "reason": &"missing_text"}
	var at: int = 1 if data[0] == TEXT_START else 0
	var out: String = ""
	while at < data.size():
		var byte: int = int(data[at])
		if byte == TEXT_TERMINATOR:
			return {"ok": true, "text": out, "bytes": at + 1}
		out += Gen2Text.character(byte)
		at += 1
	return {"ok": false, "reason": &"missing_text_terminator", "text": out}
