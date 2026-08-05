class_name Gen2WorldScript
extends RefCounted

## Shared Generation 2 overworld script command definitions.
##
## The cartridge stores one command byte followed by command-specific operands.
## This file describes the byte layout for the commands used by the bounded
## overworld runner. Unknown commands remain visible to the caller instead of
## being guessed or skipped.

const SCALL: int = 0x00
const FARSCALL: int = 0x01
const MEMCALL: int = 0x02
const SJUMP: int = 0x03
const FARSJUMP: int = 0x04
const MEMJUMP: int = 0x05
const IFEQUAL: int = 0x06
const IFNOTEQUAL: int = 0x07
const IFFALSE: int = 0x08
const IFTRUE: int = 0x09
const IFGREATER: int = 0x0A
const IFLESS: int = 0x0B
const JUMPSTD: int = 0x0C
const CALLSTD: int = 0x0D
const CALLASM: int = 0x0E
const SPECIAL: int = 0x0F
const MEMCALLASM: int = 0x10
const CHECKMAPSCENE: int = 0x11
const SETMAPSCENE: int = 0x12
const CHECKSCENE: int = 0x13
const SETSCENE: int = 0x14
const SETVAL: int = 0x15
const ADDVAL: int = 0x16
const RANDOM: int = 0x17
const CHECKVER: int = 0x18
const READMEM: int = 0x19
const WRITEMEM: int = 0x1A
const LOADMEM: int = 0x1B
const READVAR: int = 0x1C
const WRITEVAR: int = 0x1D
const LOADVAR: int = 0x1E
const GIVEITEM: int = 0x1F
const TAKEITEM: int = 0x20
const CHECKITEM: int = 0x21
const GIVECOINS: int = 0x25
const TAKECOINS: int = 0x26
const CHECKCOINS: int = 0x27
const ADDCELLNUM: int = 0x28
const DELCELLNUM: int = 0x29
const CHECKCELLNUM: int = 0x2A
const CHECKTIME: int = 0x2B
const CHECKPOKE: int = 0x2C
const GIVEEGG: int = 0x2E
const GIVEPOKEMAIL: int = 0x2F
const CHECKPOKEMAIL: int = 0x30
const CHECKEVENT: int = 0x31
const CLEAREVENT: int = 0x32
const SETEVENT: int = 0x33
const CHECKFLAG: int = 0x34
const CLEARFLAG: int = 0x35
const SETFLAG: int = 0x36
const WILDON: int = 0x37
const WILDOFF: int = 0x38
const XYCOMPARE: int = 0x39
const WARPMOD: int = 0x3A
const BLACKOUTMOD: int = 0x3B
const WARP: int = 0x3C
const GETMONEY: int = 0x3D
const GETCOINS: int = 0x3E
const GETNUM: int = 0x3F
const GETMONNAME: int = 0x40
const GETITEMNAME: int = 0x41
const GETCURLANDMARKNAME: int = 0x42
const GETTRAINERNAME: int = 0x43
const GETSTRING: int = 0x44
const ITEMNOTIFY: int = 0x45
const POCKETISFULL: int = 0x46
const OPENTEXT: int = 0x47
const REANCHORMAP: int = 0x48
const CLOSETEXT: int = 0x49
const WRITEUNUSEDBYTE: int = 0x4A
const FARWRITETEXT: int = 0x4B
const WRITETEXT: int = 0x4C
const REPEATTEXT: int = 0x4D
const YESORNO: int = 0x4E
const LOADMENU: int = 0x4F
const CLOSEWINDOW: int = 0x50
const JUMPTEXTFACEPLAYER: int = 0x51
const FARJUMPTEXT: int = 0x52
const JUMPTEXT: int = 0x53
const WAITBUTTON: int = 0x54
const PROMPTBUTTON: int = 0x55
const GOLD_FACEPLAYER: int = 0x6A
const FACEPLAYER: int = 0x6B
const GOLD_ENDCALLBACK: int = 0x8F
const GOLD_END: int = 0x90
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
	var later_name: StringName = _later_command_name(opcode, crystal_commands)
	if not later_name.is_empty():
		return later_name
	match opcode:
		SCALL:
			return &"scall"
		FARSCALL:
			return &"farscall"
		MEMCALL:
			return &"memcall"
		SJUMP:
			return &"sjump"
		FARSJUMP:
			return &"farsjump"
		MEMJUMP:
			return &"memjump"
		IFEQUAL:
			return &"ifequal"
		IFNOTEQUAL:
			return &"ifnotequal"
		IFFALSE:
			return &"iffalse"
		IFTRUE:
			return &"iftrue"
		IFGREATER:
			return &"ifgreater"
		IFLESS:
			return &"ifless"
		JUMPSTD:
			return &"jumpstd"
		CALLSTD:
			return &"callstd"
		CALLASM:
			return &"callasm"
		SPECIAL:
			return &"special"
		MEMCALLASM:
			return &"memcallasm"
		CHECKMAPSCENE:
			return &"checkmapscene"
		SETMAPSCENE:
			return &"setmapscene"
		CHECKSCENE:
			return &"checkscene"
		SETSCENE:
			return &"setscene"
		SETVAL:
			return &"setval"
		ADDVAL:
			return &"addval"
		RANDOM:
			return &"random"
		CHECKVER:
			return &"checkver"
		READMEM:
			return &"readmem"
		WRITEMEM:
			return &"writemem"
		LOADMEM:
			return &"loadmem"
		READVAR:
			return &"readvar"
		WRITEVAR:
			return &"writevar"
		LOADVAR:
			return &"loadvar"
		GIVEITEM:
			return &"giveitem"
		TAKEITEM:
			return &"takeitem"
		CHECKITEM:
			return &"checkitem"
		GIVECOINS:
			return &"givecoins"
		TAKECOINS:
			return &"takecoins"
		CHECKCOINS:
			return &"checkcoins"
		ADDCELLNUM:
			return &"addcellnum"
		DELCELLNUM:
			return &"delcellnum"
		CHECKCELLNUM:
			return &"checkcellnum"
		CHECKTIME:
			return &"checktime"
		CHECKPOKE:
			return &"checkpoke"
		GIVEEGG:
			return &"giveegg"
		GIVEPOKEMAIL:
			return &"givepokemail"
		CHECKPOKEMAIL:
			return &"checkpokemail"
		CHECKEVENT:
			return &"checkevent"
		CLEAREVENT:
			return &"clearevent"
		SETEVENT:
			return &"setevent"
		CHECKFLAG:
			return &"checkflag"
		CLEARFLAG:
			return &"clearflag"
		SETFLAG:
			return &"setflag"
		WILDON:
			return &"wildon"
		WILDOFF:
			return &"wildoff"
		XYCOMPARE:
			return &"xycompare"
		WARPMOD:
			return &"warpmod"
		BLACKOUTMOD:
			return &"blackoutmod"
		WARP:
			return &"warp"
		GETMONEY:
			return &"getmoney"
		GETCOINS:
			return &"getcoins"
		GETNUM:
			return &"getnum"
		GETMONNAME:
			return &"getmonname"
		GETITEMNAME:
			return &"getitemname"
		GETCURLANDMARKNAME:
			return &"getcurlandmarkname"
		GETTRAINERNAME:
			return &"gettrainername"
		GETSTRING:
			return &"getstring"
		ITEMNOTIFY:
			return &"itemnotify"
		POCKETISFULL:
			return &"pocketisfull"
		OPENTEXT:
			return &"opentext"
		REANCHORMAP:
			return &"reanchormap"
		CLOSETEXT:
			return &"closetext"
		WRITEUNUSEDBYTE:
			return &"writeunusedbyte"
		FARWRITETEXT:
			return &"farwritetext"
		WRITETEXT:
			return &"writetext"
		REPEATTEXT:
			return &"repeattext"
		YESORNO:
			return &"yesorno"
		LOADMENU:
			return &"loadmenu"
		CLOSEWINDOW:
			return &"closewindow"
		JUMPTEXTFACEPLAYER:
			return &"jumptextfaceplayer"
		FARJUMPTEXT:
			return &"farjumptext" if crystal_commands else &"jumptext"
		JUMPTEXT:
			return &"jumptext" if crystal_commands else &"waitbutton"
		WAITBUTTON:
			return &"waitbutton" if crystal_commands else &"promptbutton"
		PROMPTBUTTON:
			return &"promptbutton" if crystal_commands else &"pokepic"
		GOLD_FACEPLAYER:
			return &"faceplayer" if not crystal_commands else &""
		FACEPLAYER:
			return &"faceplayer"
		GOLD_ENDCALLBACK:
			return &"endcallback" if not crystal_commands else &""
		ENDCALLBACK:
			return &"endcallback" if crystal_commands else &"end"
		END:
			return &"end" if crystal_commands else &""
	return &""


static func command_width(opcode: int, crystal_commands: bool = true) -> int:
	match opcode:
		SCALL, MEMCALL, SJUMP, MEMJUMP, WRITETEXT, JUMPTEXTFACEPLAYER, IFFALSE, IFTRUE, JUMPSTD, CALLSTD, READMEM, WRITEMEM, XYCOMPARE, GIVEPOKEMAIL, CHECKPOKEMAIL, LOADMENU:
			return 3
		FARSCALL, FARSJUMP, CALLASM, FARWRITETEXT:
			return 4
		IFEQUAL, IFNOTEQUAL, IFGREATER, IFLESS, LOADMEM:
			return 4
		SPECIAL, MEMCALLASM, SETMAPSCENE, WARPMOD:
			return 3 if opcode == SPECIAL or opcode == MEMCALLASM else 4
		CHECKMAPSCENE:
			return 3
		CHECKSCENE, CHECKVER, WILDON, WILDOFF, ITEMNOTIFY, POCKETISFULL, OPENTEXT, CLOSETEXT, YESORNO, CLOSEWINDOW:
			return 1
		SETSCENE:
			return 2
		SETVAL, ADDVAL, RANDOM, READVAR, WRITEVAR, CHECKITEM, ADDCELLNUM, DELCELLNUM, CHECKCELLNUM, CHECKTIME, CHECKPOKE, GIVEEGG, GETMONEY, GETCOINS, GETNUM, GETCURLANDMARKNAME, REANCHORMAP, WRITEUNUSEDBYTE:
			return 2
		LOADVAR, GIVEITEM, TAKEITEM:
			return 3
		GIVECOINS, TAKECOINS, CHECKCOINS, CHECKFLAG, CLEARFLAG, SETFLAG, CLEAREVENT, SETEVENT, BLACKOUTMOD, GETMONNAME, GETITEMNAME:
			return 3
		CHECKEVENT:
			return 3
		WARP:
			return 5
		REPEATTEXT:
			return 3
		FARJUMPTEXT:
			return 4 if crystal_commands else 3
		JUMPTEXT:
			return 3 if crystal_commands else 1
		WAITBUTTON:
			return 1
		PROMPTBUTTON:
			return 1 if crystal_commands else 2
		GOLD_FACEPLAYER:
			return 1 if not crystal_commands else 0
		FACEPLAYER:
			return 1 if crystal_commands else 0
		GOLD_ENDCALLBACK:
			return 1 if not crystal_commands else 0
		ENDCALLBACK:
			return 1
		END:
			return 1 if crystal_commands else 0
	var source_opcode: int = opcode
	if crystal_commands and opcode >= 0x56:
		source_opcode -= 1
	return _later_command_width(source_opcode)


static func _later_command_width(opcode: int) -> int:
	## Gold/Silver command widths from pokegold's ScriptCommandTable. Crystal
	## inserts farjumptext at $52, so commands after $54 are shifted by one.
	match opcode:
		0x55:
			return 2
		0x56, 0x57, 0x58, 0x59, 0x5A, 0x5B, 0x5E, 0x5F, 0x64, 0x65, 0x66, 0x6A, 0x70, 0x7B, 0x7F, 0x81, 0x82, 0x85, 0x86, 0x87, 0x8D, 0x8F, 0x90, 0x92, 0x98, 0x9C, 0x9F, 0xA0:
			return 1
		0x5C, 0x5D, 0x69, 0x6B, 0x6C, 0x6F, 0x75, 0x76, 0x77, 0x7C, 0x7E, 0x83, 0x84, 0x8C, 0x8E, 0x94, 0x97, 0x9B, 0x9D, 0x9E:
			return 3
		0x60, 0x61, 0x62, 0x67, 0x6D, 0x6E, 0x72, 0x73, 0x78, 0x7D, 0x89, 0x8A, 0x8B, 0x91, 0x95, 0x96, 0x99, 0x9A:
			return 2
		0x68, 0x71, 0x74, 0x79, 0x80, 0x88, 0x93:
			return 4
		0x63:
			return 5
		0xA1:
			return 6
	return 0


static func _later_command_name(opcode: int, crystal_commands: bool) -> StringName:
	if opcode < 0x55:
		return &""
	var source_opcode: int = opcode - 1 if crystal_commands and opcode >= 0x56 else opcode
	match source_opcode:
		0x55: return &"pokepic"
		0x56: return &"closepokepic"
		0x57: return &"2dmenu"
		0x58: return &"verticalmenu"
		0x59: return &"loadpikachudata"
		0x5A: return &"randomwildmon"
		0x5B: return &"loadtemptrainer"
		0x5C: return &"loadwildmon"
		0x5D: return &"loadtrainer"
		0x5E: return &"startbattle"
		0x5F: return &"reloadmapafterbattle"
		0x60: return &"catchtutorial"
		0x61: return &"trainertext"
		0x62: return &"trainerflagaction"
		0x63: return &"winlosstext"
		0x64: return &"scripttalkafter"
		0x65: return &"endifjustbattled"
		0x66: return &"checkjustbattled"
		0x67: return &"setlasttalked"
		0x68: return &"applymovement"
		0x69: return &"applymovementlasttalked"
		0x6A: return &"faceplayer"
		0x6B: return &"faceobject"
		0x6C: return &"variablesprite"
		0x6D: return &"disappear"
		0x6E: return &"appear"
		0x6F: return &"follow"
		0x70: return &"stopfollow"
		0x71: return &"moveobject"
		0x72: return &"writeobjectxy"
		0x73: return &"loademote"
		0x74: return &"showemote"
		0x75: return &"turnobject"
		0x76: return &"follownotexact"
		0x77: return &"earthquake"
		0x78: return &"changemapblocks"
		0x79: return &"changeblock"
		0x7A: return &"reloadmap"
		0x7B: return &"refreshmap"
		0x7C: return &"writecmdqueue"
		0x7D: return &"delcmdqueue"
		0x7E: return &"playmusic"
		0x7F: return &"encountermusic"
		0x80: return &"musicfadeout"
		0x81: return &"playmapmusic"
		0x82: return &"dontrestartmapmusic"
		0x83: return &"cry"
		0x84: return &"playsound"
		0x85: return &"waitsfx"
		0x86: return &"warpsound"
		0x87: return &"specialsound"
		0x88: return &"autoinput"
		0x89: return &"newloadmap"
		0x8A: return &"pause"
		0x8B: return &"deactivatefacing"
		0x8C: return &"sdefer"
		0x8D: return &"warpcheck"
		0x8E: return &"stopandsjump"
		0x8F: return &"endcallback"
		0x90: return &"end"
		0x91: return &"reloadend"
		0x92: return &"endall"
		0x93: return &"pokemart"
		0x94: return &"elevator"
		0x95: return &"trade"
		0x96: return &"askforphonenumber"
		0x97: return &"phonecall"
		0x98: return &"hangup"
		0x99: return &"describedecoration"
		0x9A: return &"fruittree"
		0x9B: return &"specialphonecall"
		0x9C: return &"checkphonecall"
		0x9D: return &"verbosegiveitem"
		0x9E: return &"swarm"
		0x9F: return &"halloffame"
		0xA0: return &"credits"
		0xA1: return &"warpfacing"
	return &""


static func is_endcallback(opcode: int, crystal_commands: bool = true) -> bool:
	return opcode == ENDCALLBACK if crystal_commands else opcode == GOLD_ENDCALLBACK


static func is_end(opcode: int, crystal_commands: bool = true) -> bool:
	return opcode == END if crystal_commands else opcode == GOLD_END


static func is_terminal(opcode: int, crystal_commands: bool = true) -> bool:
	return is_end(opcode, crystal_commands) or is_endcallback(opcode, crystal_commands)


static func is_waitbutton(opcode: int, crystal_commands: bool = true) -> bool:
	return opcode == WAITBUTTON if crystal_commands else opcode == 0x53


static func is_promptbutton(opcode: int, crystal_commands: bool = true) -> bool:
	return opcode == PROMPTBUTTON if crystal_commands else opcode == 0x54


static func is_faceplayer(opcode: int, crystal_commands: bool = true) -> bool:
	return opcode == FACEPLAYER if crystal_commands else opcode == GOLD_FACEPLAYER


static func is_text_jump(opcode: int, crystal_commands: bool = true) -> bool:
	return opcode in [FARJUMPTEXT, JUMPTEXT] if crystal_commands else opcode in [0x51, 0x52]


static func is_text_pointer_command(opcode: int, crystal_commands: bool = true) -> bool:
	if opcode in [WRITETEXT, FARWRITETEXT, JUMPTEXTFACEPLAYER]:
		return true
	return is_text_jump(opcode, crystal_commands)


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
	if opcode in [SCALL, MEMCALL, SJUMP, MEMJUMP, WRITETEXT, JUMPTEXTFACEPLAYER,
		IFFALSE, IFTRUE, JUMPSTD, CALLSTD, READMEM, WRITEMEM, XYCOMPARE,
		GIVEPOKEMAIL, CHECKPOKEMAIL, LOADMENU] \
		or (crystal_commands and opcode == JUMPTEXT) \
		or (not crystal_commands and opcode == FARJUMPTEXT):
		command["address"] = read_u16(data, offset + 1)
	elif opcode in [FARSCALL, FARSJUMP, FARWRITETEXT, CALLASM] \
		or (crystal_commands and opcode == FARJUMPTEXT):
			command["bank"] = int(data[offset + 1])
			command["address"] = read_u16(data, offset + 2)
	else:
		match opcode:
			IFEQUAL, IFNOTEQUAL, IFGREATER, IFLESS:
				command["value"] = int(data[offset + 1])
				command["address"] = read_u16(data, offset + 2)
			CHECKMAPSCENE:
				command["map_group"] = int(data[offset + 1])
				command["map_number"] = int(data[offset + 2])
			SETMAPSCENE:
				command["map_group"] = int(data[offset + 1])
				command["map_number"] = int(data[offset + 2])
				command["scene"] = int(data[offset + 3])
			SETSCENE:
				command["scene"] = int(data[offset + 1])
			SETVAL, ADDVAL, RANDOM, READVAR, WRITEVAR, CHECKITEM, ADDCELLNUM, DELCELLNUM, CHECKCELLNUM, CHECKTIME, CHECKPOKE, GIVEEGG, GETMONEY, GETCOINS, GETNUM, GETCURLANDMARKNAME, REANCHORMAP, WRITEUNUSEDBYTE:
				command["value"] = int(data[offset + 1])
			LOADVAR, GIVEITEM, TAKEITEM:
				command["value"] = int(data[offset + 1])
				command["value_2"] = int(data[offset + 2])
			CLEAREVENT, SETEVENT, CHECKFLAG, CLEARFLAG, SETFLAG, CHECKEVENT:
				command["flag"] = read_u16(data, offset + 1)
			GIVECOINS, TAKECOINS, CHECKCOINS, BLACKOUTMOD, GETMONNAME, GETITEMNAME:
				command["value"] = read_u16(data, offset + 1)
			WARPMOD:
				command["warp_id"] = int(data[offset + 1])
				command["map_group"] = int(data[offset + 2])
				command["map_number"] = int(data[offset + 3])
			WARP:
				command["map_group"] = int(data[offset + 1])
				command["map_number"] = int(data[offset + 2])
				command["x"] = int(data[offset + 3])
				command["y"] = int(data[offset + 4])
			REPEATTEXT:
				command["value"] = int(data[offset + 1])
				command["value_2"] = int(data[offset + 2])
			0x55:
				if not crystal_commands:
					command["pokemon"] = int(data[offset + 1])
		var source_opcode: int = opcode - 1 if crystal_commands and opcode >= 0x56 else opcode
		match source_opcode:
			0x63:
				command["win_address"] = read_u16(data, offset + 1)
				command["loss_address"] = read_u16(data, offset + 3)
			0x67:
				command["object_id"] = int(data[offset + 1])
			0x68:
				command["object_id"] = int(data[offset + 1])
				command["address"] = read_u16(data, offset + 2)
			0x69:
				command["address"] = read_u16(data, offset + 1)
			0x6B:
				command["object_id"] = int(data[offset + 1])
				command["object_id_2"] = int(data[offset + 2])
			0x6C:
				command["value"] = int(data[offset + 1])
				command["value_2"] = int(data[offset + 2])
			0x6D, 0x6E, 0x72:
				command["object_id"] = int(data[offset + 1])
			0x6F, 0x76:
				command["object_id"] = int(data[offset + 1])
				command["object_id_2"] = int(data[offset + 2])
			0x71:
				command["object_id"] = int(data[offset + 1])
				command["x"] = int(data[offset + 2])
				command["y"] = int(data[offset + 3])
			0x74:
				command["value"] = int(data[offset + 1])
				command["object_id"] = int(data[offset + 2])
				command["value_2"] = int(data[offset + 3])
			0x75:
				command["object_id"] = int(data[offset + 1])
				command["facing"] = int(data[offset + 2])
			0x78, 0x88:
				command["bank"] = int(data[offset + 1])
				command["address"] = read_u16(data, offset + 2)
			0x79:
				command["x"] = int(data[offset + 1])
				command["y"] = int(data[offset + 2])
				command["block"] = int(data[offset + 3])
			0x7C, 0x7E, 0x8C, 0x8E, 0x94, 0x97, 0x9B:
				command["address"] = read_u16(data, offset + 1)
			0x80:
				command["value"] = read_u16(data, offset + 1)
				command["value_2"] = int(data[offset + 3])
			0x83, 0x84:
				command["value"] = read_u16(data, offset + 1)
			0x93:
				command["value"] = int(data[offset + 1])
				command["address"] = read_u16(data, offset + 2)
			0x95, 0x96, 0x99, 0x9A, 0x9D:
				command["value"] = int(data[offset + 1])
			0x9E:
				command["map_group"] = int(data[offset + 1])
				command["map_number"] = int(data[offset + 2])
			0xA1:
				command["facing"] = int(data[offset + 1])
				command["map_group"] = int(data[offset + 2])
				command["map_number"] = int(data[offset + 3])
				command["x"] = int(data[offset + 4])
				command["y"] = int(data[offset + 5])
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
			SCALL, MEMCALL, SJUMP, MEMJUMP:
				scripts.append({"bank": bank, "address": int(command["address"])})
			IFEQUAL, IFNOTEQUAL, IFFALSE, IFTRUE, IFGREATER, IFLESS:
				scripts.append({"bank": bank, "address": int(command["address"])})
			FARSCALL, FARSJUMP:
				scripts.append({"bank": int(command["bank"]), "address": int(command["address"])})
			WRITETEXT, JUMPTEXTFACEPLAYER:
				texts.append({"bank": bank, "address": int(command["address"])})
			GETSTRING:
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
		var source_opcode: int = opcode - 1 if crystal_commands and opcode >= 0x56 else opcode
		match source_opcode:
			0x63:
				texts.append({"bank": bank, "address": int(command["win_address"])})
				texts.append({"bank": bank, "address": int(command["loss_address"])})
			0x8C, 0x8E:
				scripts.append({"bank": bank, "address": int(command["address"])})
		at += int(command["width"])
		command_count += 1
		if is_terminal(opcode, crystal_commands):
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
