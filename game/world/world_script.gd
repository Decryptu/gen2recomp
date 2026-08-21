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
const GIVEMONEY: int = 0x22
const TAKEMONEY: int = 0x23
const CHECKMONEY: int = 0x24
const GIVECOINS: int = 0x25
const TAKECOINS: int = 0x26
const CHECKCOINS: int = 0x27
const ADDCELLNUM: int = 0x28
const DELCELLNUM: int = 0x29
const CHECKCELLNUM: int = 0x2A
const CHECKTIME: int = 0x2B
const CHECKPOKE: int = 0x2C
const GIVEPOKE: int = 0x2D
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

## Gold/Silver raw opcodes for the trainer intro sequence. Crystal inserted
## farjumptext at raw $52, so every Gold/Silver opcode at or above $52 shifts
## up by one in Crystal's raw byte stream; see raw_opcode().
const GOLD_LOADTEMPTRAINER: int = 0x5B
const GOLD_STARTBATTLE: int = 0x5E
const GOLD_RELOADMAPAFTERBATTLE: int = 0x5F
const GOLD_TRAINERFLAGACTION: int = 0x62
const GOLD_SCRIPTTALKAFTER: int = 0x64
const GOLD_ENCOUNTERMUSIC: int = 0x7F

const TEXT_START: int = 0x00
## World text uses the source text-command stream. $50 is a page control;
## $57 (done) ends the text box and $58 (prompt) pauses for a prompt.
## `<PARA>`, which waits for a press and clears the box. $50 is `@`, the
## terminator, and reading it as a page break walked `_OakText2` straight
## into the two texts after it.
const TEXT_PAGE: int = 0x51
const TEXT_TERMINATOR: int = 0x57
const TEXT_PROMPT: int = 0x58

## Long map-entry initialization callbacks can include the cartridge's full
## event-variable setup routine, which is larger than one hundred commands.
const MAX_COMMANDS: int = 512
const MAX_CALL_DEPTH: int = 8
const MAX_SCRIPT_BYTES: int = 512
const MAX_TEXT_BYTES: int = 1024

## constants/script_constants.asm's cmdqueue block. An entry is
## `dbw type, address` plus two filler bytes; four fit in wCmdQueue.
const CMDQUEUE_ENTRY_SIZE: int = 5
const CMDQUEUE_CAPACITY: int = 4
const CMDQUEUE_NULL: int = 0
const CMDQUEUE_STONETABLE: int = 2

## macros/scripts/maps.asm's `stonetable warp_id, object_id, script`, which is
## `db warp_id, object_id` then `dw script`, ending at a $ff warp id. Only two
## maps ship one, so the bound is generous rather than tight.
const STONETABLE_ROW_SIZE: int = 4
const STONETABLE_TERMINATOR: int = 0xFF
const MAX_STONETABLE_ROWS: int = 16


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
		GIVEMONEY:
			return &"givemoney"
		TAKEMONEY:
			return &"takemoney"
		CHECKMONEY:
			return &"checkmoney"
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
		GIVEPOKE:
			return &"givepoke"
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
		SETVAL, ADDVAL, RANDOM, READVAR, WRITEVAR, CHECKITEM, ADDCELLNUM, DELCELLNUM, CHECKCELLNUM, CHECKTIME, CHECKPOKE, GETNUM, GETCURLANDMARKNAME, REANCHORMAP, WRITEUNUSEDBYTE:
			return 2
		LOADVAR, GIVEITEM, TAKEITEM:
			return 3
		GIVECOINS, TAKECOINS, CHECKCOINS, CHECKFLAG, CLEARFLAG, SETFLAG, CLEAREVENT, SETEVENT, BLACKOUTMOD:
			return 3
		GIVEMONEY, TAKEMONEY, CHECKMONEY:
			return 5
		GETMONEY:
			return 3
		GETCOINS:
			return 3 if crystal_commands else 2
		GETMONNAME, GETITEMNAME:
			return 3
		GETTRAINERNAME, GETSTRING:
			return 4
		GIVEEGG:
			return 3
		GIVEPOKE:
			return 0
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
	if crystal_commands:
		var crystal_width: int = _crystal_only_command_width(opcode)
		if crystal_width > 0:
			return crystal_width
	return _later_command_width(source_opcode(opcode, crystal_commands))


## Widths for the commands Crystal has and pokegold does not, plus the one
## command whose operands differ between them. Everything else shares
## pokegold's table through source_opcode().
static func _crystal_only_command_width(opcode: int) -> int:
	match opcode:
		0x9F: return 3 # verbosegiveitemvar: item, var
		0xA0: return 4 # swarm: flag, map group, map number (pokegold omits the flag)
		0xA4: return 2 # battletowertext
		0xA5: return 3 # getlandmarkname
		0xA6: return 3 # gettrainerclassname
		0xA7: return 4 # getname
		0xA8: return 2 # wait
		0xA9: return 1 # checksave
	return 0


static func _later_command_width(opcode: int) -> int:
	## Gold/Silver command widths from pokegold's ScriptCommandTable. Crystal
	## inserts farjumptext at $52, so commands after $54 are shifted by one.
	match opcode:
		0x55:
			return 2
		0x56, 0x57, 0x58, 0x59, 0x5A, 0x5B, 0x5E, 0x5F, 0x64, 0x65, 0x66, 0x6A, 0x70, 0x7A, 0x7B, 0x7F, 0x81, 0x82, 0x85, 0x86, 0x87, 0x8D, 0x8F, 0x90, 0x92, 0x98, 0x9C, 0x9F, 0xA0:
			return 1
		0x5C, 0x5D, 0x69, 0x6B, 0x6C, 0x6F, 0x75, 0x76, 0x7C, 0x7E, 0x83, 0x84, 0x8C, 0x8E, 0x94, 0x97, 0x9B, 0x9D, 0x9E:
			return 3
		0x60, 0x61, 0x62, 0x67, 0x6D, 0x6E, 0x72, 0x73, 0x77, 0x78, 0x7D, 0x89, 0x8A, 0x8B, 0x91, 0x95, 0x96, 0x99, 0x9A:
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
	## $55 is the seam between the two tables: pokegold's `pokepic` and Crystal's
	## own `promptbutton`, which is one byte and has no species. The base table
	## already splits them, and answering `pokepic` here shadowed it, so every one
	## of Crystal's promptbuttons decoded under the wrong name and
	## `command_at` read the next command's first byte as a species.
	if crystal_commands and opcode == PROMPTBUTTON:
		return &""
	if crystal_commands:
		match opcode:
			0x9F: return &"verbosegiveitemvar"
			0xA4: return &"battletowertext"
			0xA5: return &"getlandmarkname"
			0xA6: return &"gettrainerclassname"
			0xA7: return &"getname"
			0xA8: return &"wait"
			0xA9: return &"checksave"
	match source_opcode(opcode, crystal_commands):
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


## Normalizes a raw command byte onto pokegold's numbering, which every width,
## name and handler table here is keyed with. Crystal's stream inserts two
## commands pokegold does not have: `farjumptext` at $52 and
## `verbosegiveitemvar` at $9f (macros/scripts/events.asm in both pins). So
## Crystal is one ahead from $53 and two ahead from $a0, and the commands
## Crystal added themselves have no source opcode: callers handle those from the
## raw byte before asking.
##
## The low boundary is $56 rather than $53 because every caller resolves
## farjumptext, jumptext, waitbutton and promptbutton from the raw opcode first.
static func source_opcode(opcode: int, crystal_commands: bool = true) -> int:
	if not crystal_commands or opcode < 0x56:
		return opcode
	return opcode - 2 if opcode >= 0xA0 else opcode - 1


## The inverse of [method source_opcode], for a caller holding a pokegold opcode
## that needs the raw byte this profile's stream uses.
static func raw_opcode(source_opcode_value: int, crystal_commands: bool = true) -> int:
	if not crystal_commands or source_opcode_value < 0x52:
		return source_opcode_value
	return source_opcode_value + 2 if source_opcode_value >= 0x9E else source_opcode_value + 1


## Converts a raw SPECIAL operand into the Crystal-canonical index the runner's
## handlers are numbered with. data/events/special_pointers.asm's
## SpecialsPointers agrees for the first 47 entries, then Crystal inserts
## BattleTowerFade at 47 and a mobile/Battle Tower block at 109, so Gold/Silver
## 47-107 sit one lower and its last three entries land after that block.
## Gold/Silver 110 is MrChrono, which Crystal has no entry for; -1 leaves it
## unhandled rather than aliasing it onto an unrelated routine.
static func special_index(raw_special: int, crystal_commands: bool = true) -> int:
	if crystal_commands or raw_special <= 46:
		return raw_special
	match raw_special:
		108: return 166
		109: return 167
		110: return -1
		111: return 168
	return raw_special + 1


static func is_endcallback(opcode: int, crystal_commands: bool = true) -> bool:
	return opcode == ENDCALLBACK if crystal_commands else opcode == GOLD_ENDCALLBACK


static func is_end(opcode: int, crystal_commands: bool = true) -> bool:
	return opcode == END if crystal_commands else opcode == GOLD_END


static func is_terminal(opcode: int, crystal_commands: bool = true) -> bool:
	return is_end(opcode, crystal_commands) or is_endcallback(opcode, crystal_commands)


## pokegold-numbered opcodes whose handler reaches ScriptJump, Script_end or
## Script_endall unconditionally, so the bytes after the command are never read
## as one. Two near misses are deliberately absent: `endifjustbattled`'s
## `jp Script_end` sits behind a `ret z`, and `reloadmapafterbattle` jumps only
## on LOSE and otherwise falls into `Script_reloadmap`, whose `StopScript`
## leaves the script pointer where it stands (Route30.asm resumes on the
## `loadmem` after it).
const NON_RETURNING_SOURCE_OPCODES: Array[int] = [
	0x03, 0x04, 0x05,  ## sjump, farsjump, memjump
	0x0C,  ## jumpstd
	0x51,  ## jumptextfaceplayer
	0x64,  ## scripttalkafter
	0x8E, 0x8F, 0x90, 0x91, 0x92,  ## stopandsjump, endcallback, end, reloadend, endall
	0x99, 0x9A,  ## describedecoration, fruittree
	0x9F, 0xA0,  ## halloffame, credits
]


## Whether the command at [param opcode] is followed by another command.
##
## A linear walk over a script stops here, not at [method is_terminal]: a script
## that ends in `jumptext` is followed by the text it named, and a `jumpstd`
## table by its pointers. Only the live runner, which dispatches one command at
## a time and is told where to go next, uses `is_terminal`.
static func continues_after(opcode: int, crystal_commands: bool = true) -> bool:
	if is_text_jump(opcode, crystal_commands):
		return false
	return source_opcode(opcode, crystal_commands) not in NON_RETURNING_SOURCE_OPCODES


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
	if opcode == GIVEPOKE:
		return _givepoke_command_at(data, offset)
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
	if opcode in [SCALL, MEMCALL, SJUMP, MEMJUMP, MEMCALLASM, WRITETEXT, JUMPTEXTFACEPLAYER,
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
			SPECIAL:
				command["value"] = read_u16(data, offset + 1)
			IFEQUAL, IFNOTEQUAL, IFGREATER, IFLESS:
				command["value"] = int(data[offset + 1])
				command["address"] = read_u16(data, offset + 2)
			LOADMEM:
				## `dw address` then `db value`, the reverse of the compare
				## commands that share its width.
				command["address"] = read_u16(data, offset + 1)
				command["value"] = int(data[offset + 3])
			CHECKMAPSCENE:
				command["map_group"] = int(data[offset + 1])
				command["map_number"] = int(data[offset + 2])
			SETMAPSCENE:
				command["map_group"] = int(data[offset + 1])
				command["map_number"] = int(data[offset + 2])
				command["scene"] = int(data[offset + 3])
			SETSCENE:
				command["scene"] = int(data[offset + 1])
			SETVAL, ADDVAL, RANDOM, READVAR, WRITEVAR, CHECKITEM, ADDCELLNUM, DELCELLNUM, CHECKCELLNUM, CHECKTIME, CHECKPOKE, GETNUM, GETCURLANDMARKNAME, REANCHORMAP, WRITEUNUSEDBYTE:
				command["value"] = int(data[offset + 1])
			LOADVAR, GIVEITEM, TAKEITEM, GIVEEGG:
				command["value"] = int(data[offset + 1])
				command["value_2"] = int(data[offset + 2])
			GIVEMONEY, TAKEMONEY, CHECKMONEY:
				command["account"] = int(data[offset + 1])
				command["amount_bytes"] = PackedByteArray([
					int(data[offset + 2]), int(data[offset + 3]), int(data[offset + 4])
				])
			GETMONEY:
				command["account"] = int(data[offset + 1])
				command["string_buffer"] = int(data[offset + 2])
			GETCOINS:
				command["string_buffer"] = int(data[offset + 1])
				if crystal_commands:
					command["string_buffer_2"] = int(data[offset + 2])
			GETMONNAME:
				command["pokemon"] = int(data[offset + 1])
				command["string_buffer"] = int(data[offset + 2])
			GETITEMNAME:
				command["item"] = int(data[offset + 1])
				command["string_buffer"] = int(data[offset + 2])
			GETTRAINERNAME:
				command["trainer_group"] = int(data[offset + 1])
				command["trainer_id"] = int(data[offset + 2])
				command["string_buffer"] = int(data[offset + 3])
			GETSTRING:
				command["address"] = read_u16(data, offset + 1)
				command["string_buffer"] = int(data[offset + 3])
			CLEAREVENT, SETEVENT, CHECKFLAG, CLEARFLAG, SETFLAG, CHECKEVENT:
				command["flag"] = read_u16(data, offset + 1)
			GIVECOINS, TAKECOINS, CHECKCOINS, BLACKOUTMOD:
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
		if crystal_commands:
			match opcode:
				0x9F: # verbosegiveitemvar
					command["item"] = int(data[offset + 1])
					command["variable"] = int(data[offset + 2])
					return command
				0xA0: # swarm, which carries a flag byte pokegold's does not
					command["flag"] = int(data[offset + 1])
					command["map_group"] = int(data[offset + 2])
					command["map_number"] = int(data[offset + 3])
					return command
				0xA8: # wait, in units of six frames
					command["value"] = int(data[offset + 1])
					return command
		var source: int = Gen2WorldScript.source_opcode(opcode, crystal_commands)
		match source:
			0x55:
				## Crystal's own $55 is `promptbutton`, one byte and no species;
				## only pokegold's $55 is `pokepic`. See `_later_command_name`.
				if command["name"] == &"pokepic":
					command["pokemon"] = int(data[offset + 1])
			0x5C:
				command["pokemon"] = int(data[offset + 1])
				command["level"] = int(data[offset + 2])
			0x5D:
				command["trainer_group"] = int(data[offset + 1])
				command["trainer_id"] = int(data[offset + 2])
			0x60, 0x61, 0x62:
				command["value"] = int(data[offset + 1])
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
			0x77:
				command["value"] = int(data[offset + 1])
			0x78, 0x88:
				command["bank"] = int(data[offset + 1])
				command["address"] = read_u16(data, offset + 2)
			0x79:
				command["x"] = int(data[offset + 1])
				command["y"] = int(data[offset + 2])
				command["block"] = int(data[offset + 3])
			0x7C, 0x7E, 0x8C, 0x8E, 0x94, 0x97, 0x9B:
				command["address"] = read_u16(data, offset + 1)
			0x7D, 0x89, 0x8A, 0x8B:
				command["value"] = int(data[offset + 1])
			0x80:
				command["value"] = read_u16(data, offset + 1)
				command["value_2"] = int(data[offset + 3])
			0x83, 0x84:
				command["value"] = read_u16(data, offset + 1)
			0x93:
				command["value"] = int(data[offset + 1])
				command["address"] = read_u16(data, offset + 2)
			0x95, 0x96, 0x99, 0x9A:
				command["value"] = int(data[offset + 1])
			0x9D:
				command["item"] = int(data[offset + 1])
				command["quantity"] = int(data[offset + 2])
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


static func _givepoke_command_at(data: PackedByteArray, offset: int) -> Dictionary:
	## givepoke is the one base command whose width depends on its trainer flag.
	## The macro emits four operands for an ordinary gift and two extra near
	## pointers when the gift carries trainer data.
	var base_width: int = 5
	if offset < 0 or offset + base_width > data.size():
		return {
			"ok": false, "reason": &"truncated_operands", "offset": offset,
			"opcode": GIVEPOKE, "name": &"givepoke", "width": base_width,
		}
	var trainer: int = int(data[offset + 4])
	var width: int = 9 if trainer != 0 else base_width
	if offset + width > data.size():
		return {
			"ok": false, "reason": &"truncated_operands", "offset": offset,
			"opcode": GIVEPOKE, "name": &"givepoke", "width": width,
		}
	var command: Dictionary = {
		"ok": true, "offset": offset, "opcode": GIVEPOKE, "name": &"givepoke",
		"width": width, "pokemon": int(data[offset + 1]),
		"level": int(data[offset + 2]), "item": int(data[offset + 3]),
		"trainer": trainer,
	}
	if trainer != 0:
		command["nickname_address"] = read_u16(data, offset + 5)
		command["ot_name_address"] = read_u16(data, offset + 7)
	return command


static func scan_references(
	data: PackedByteArray, bank: int, _address: int, crystal_commands: bool = true
) -> Dictionary:
	## Scans only commands understood by this slice. An unknown command stops the
	## scan because its operand width cannot be inferred safely.
	var scripts: Array = []
	var texts: Array = []
	var movements: Array = []
	var command_queues: Array = []
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
		var source: int = Gen2WorldScript.source_opcode(opcode, crystal_commands)
		match source:
			0x68, 0x69:
				movements.append({"bank": bank, "address": int(command["address"])})
			0x63:
				texts.append({"bank": bank, "address": int(command["win_address"])})
				texts.append({"bank": bank, "address": int(command["loss_address"])})
			0x8C, 0x8E:
				scripts.append({"bank": bank, "address": int(command["address"])})
			0x97:
				## phonecall passes a caller-name text pointer to PhoneCall. It is
				## not a script pointer and must be collected as text data.
				texts.append({"bank": bank, "address": int(command["address"])})
			0x7C:
				## writecmdqueue points at a cmdqueue entry, which is data rather
				## than script, so it is collected as its own kind.
				command_queues.append({"bank": bank, "address": int(command["address"])})
		at += int(command["width"])
		command_count += 1
		if not continues_after(opcode, crystal_commands):
			break
	return {
		"scripts": scripts, "texts": texts, "movements": movements,
		"command_queues": command_queues,
	}


## Decodes the bounded text-command slice collected by the importer. Map text
## begins with text_start and ends with the source done command $57. The generic
## Decodes one `cmdqueue` entry: `dbw type, address` and two filler bytes
## (macros/scripts/maps.asm). Answers the type and the data pointer only; what
## the pointer means is the type's business.
static func decode_command_queue_entry(data: PackedByteArray) -> Dictionary:
	if data.size() < CMDQUEUE_ENTRY_SIZE:
		return {"ok": false, "reason": &"short_command_queue_entry"}
	var type: int = data[0]
	if type == CMDQUEUE_NULL:
		return {"ok": false, "reason": &"null_command_queue"}
	return {
		"ok": true,
		"type": type,
		"address": data[1] | (data[2] << 8),
	}


## Decodes a `stonetable`, the only cmdqueue payload either game ships.
##
## Rows are `warp_id, object_id, script` until a $ff warp id, and the ids are
## the source's own: the warp is one-based, as `.check_on_warp` counts it, and
## the object is an `object_const_def` constant, which starts at 2, so it is two
## more than the map's own object index.
static func decode_stone_table(data: PackedByteArray) -> Dictionary:
	var rows: Array = []
	var at: int = 0
	while at < data.size() and rows.size() <= MAX_STONETABLE_ROWS:
		if data[at] == STONETABLE_TERMINATOR:
			return {"ok": true, "rows": rows, "bytes": at + 1}
		if at + STONETABLE_ROW_SIZE > data.size():
			break
		rows.append({
			"warp": data[at],
			"object": data[at + 1],
			"script": data[at + 2] | (data[at + 3] << 8),
		})
		at += STONETABLE_ROW_SIZE
	return {"ok": false, "reason": &"unterminated_stone_table", "rows": rows}


## A world text with nothing to substitute into it. Anything carrying a name,
## a string buffer or a `text_far` goes through [Gen2TextStream] with a
## context; this is the bare form a tool or a fixture reads.
static func decode_text(data: PackedByteArray) -> Dictionary:
	return Gen2TextStream.decode(data)
