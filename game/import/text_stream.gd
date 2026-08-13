class_name Gen2TextStream
extends RefCounted

## `home/text.asm`'s printer: the layer above [Gen2Text].
##
## A cartridge text is two languages, not one. `DoTextUntilTerminator` reads
## *text commands*, `$00` to `$16`, each with its own operand width; `TX_START`
## hands the bytes after it to `PlaceString`, which reads *characters* and runs
## `CheckDict` over the ones that are not glyphs. The same byte means different
## things in the two: `$16` is `TX_FAR` to the command loop and `<CR>` to
## `CheckDict`, `$50` ends a literal for one and the whole text for the other.
##
## Reading a text with the character table alone prints the command bytes. That
## is where `?06?` (`TX_PROMPT_BUTTON`), `?00?` (`TX_START`) and a whole
## `text_ram` pointer drawn as `?01?e?CF?` came from, and why `$50` looked like a
## page break: it is `@`, and `_OakText2` ends on one, so a reader that treated
## it as a break walked straight into `_OakText3` and `_OakText4`.
##
## Names are substituted here rather than left as markers, because this is the
## layer that knows them: `PrintPlayerName` and its siblings are `CheckDict`
## entries, not something a later pass can spot in a string.

## `macros/scripts/text.asm`, the `TextCommands` indices.
const TX_START: int = 0x00
const TX_RAM: int = 0x01
const TX_BCD: int = 0x02
const TX_MOVE: int = 0x03
const TX_BOX: int = 0x04
const TX_LOW: int = 0x05
const TX_PROMPT_BUTTON: int = 0x06
const TX_SCROLL: int = 0x07
const TX_START_ASM: int = 0x08
const TX_DECIMAL: int = 0x09
const TX_PAUSE: int = 0x0A
const TX_DOTS: int = 0x0C
const TX_WAIT_BUTTON: int = 0x0D
const TX_STRINGBUFFER: int = 0x14
const TX_DAY: int = 0x15
const TX_FAR: int = 0x16
const TX_END: int = 0x50

## What an unfilled slot in a decoded text opens with. A caller that knows the
## value puts it in through [method fill_marker]; one that does not can at least
## see that something belongs there.
const RAM_MARKER: String = "<RAM_"
const NUMBER_MARKER: String = "<NUM_"

## `TextSFX`: the seven command bytes that play an effect and `WaitSFX`.
const TX_SOUND: Array[int] = [0x0B, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13]

## `CheckDict` entries that are not characters.
const CHAR_NULL: int = 0x00
const CHAR_BSP: int = 0x1F
const CHAR_LF: int = 0x22
const CHAR_WBR: int = 0x25
const CHAR_CONT_RAW: int = 0x4B
const CHAR_SCROLL: int = 0x4C
const CHAR_NEXT: int = 0x4E
const CHAR_LINE: int = 0x4F
const CHAR_PARA: int = 0x51
const CHAR_CONT: int = 0x55
const CHAR_DONE: int = 0x57
const CHAR_PROMPT: int = 0x58
const CHAR_DEXEND: int = 0x5F

## What the two waits become in the laid-out string.
##
## `Paragraph` clears the box and starts again at the top line; `_ContText`
## scrolls by one line and starts at the bottom, so the line above stays on
## screen. They are different breaks, and a layout that cannot tell them apart
## drops a line every time a paragraph runs past two lines.
##
## Private-use code points rather than control characters: a cache is JSON,
## and Godot writes U+000B as `\v`, which JSON has no escape for. Nothing in
## [method Gen2Text.character] can produce either of these.
const PAGE_BREAK: String = "\ue000"
const SCROLL_BREAK: String = "\ue001"

## `GetWeekday`'s `.Days`, which `TextCommand_DAY` follows with "DAY".
const WEEKDAYS: Array[String] = [
	"SUN", "MON", "TUES", "WEDNES", "THURS", "FRI", "SATUR",
]


## Runs a text from [param offset] to its terminator.
##
## [param context] carries what the print-time codes read: `player`, `rival`,
## `mom`, `red`, `green`, `enemy`, `target` and `user` names, a `buffers`
## dictionary for `TX_STRINGBUFFER`, a `ram` dictionary keyed by address for
## `TX_RAM`, a `weekday` index for `TX_DAY`, and a `far` [Callable] taking
## (bank, address) and answering the bytes, for `TX_FAR`.
static func decode(
	data: PackedByteArray, offset: int = 0, context: Dictionary = {}
) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "reason": &"missing_text"}
	return _run(data, offset, context, 0)


static func _run(
	data: PackedByteArray, offset: int, context: Dictionary, depth: int
) -> Dictionary:
	var out: String = ""
	var at: int = offset
	var prompt: bool = false
	while at < data.size():
		var command: int = int(data[at])
		at += 1
		if command == TX_END:
			return {"ok": true, "text": out, "bytes": at, "prompt": prompt}
		if command == TX_START:
			var placed: Dictionary = _place(data, at, context)
			out += String(placed["text"])
			at = int(placed["at"])
			if bool(placed.get("truncated", false)):
				return _truncated(out, &"missing_text_terminator")
			if bool(placed.get("ended", false)):
				return {
					"ok": true, "text": out, "bytes": at,
					"prompt": bool(placed.get("prompt", false)),
				}
			continue
		if command in TX_SOUND:
			# The effect plays and `WaitSFX` holds the printer; nothing is drawn.
			continue
		match command:
			TX_RAM:
				if not _has(data, at, 2):
					return _truncated(out, &"truncated_text_ram")
				var address: int = data[at] | (data[at + 1] << 8)
				at += 2
				out += _ram_string(context, address)
			TX_STRINGBUFFER:
				if not _has(data, at, 1):
					return _truncated(out, &"truncated_text_buffer")
				out += _buffer_string(context, int(data[at]))
				at += 1
			TX_FAR:
				if not _has(data, at, 3):
					return _truncated(out, &"truncated_text_far")
				var far_address: int = data[at] | (data[at + 1] << 8)
				var far_bank: int = int(data[at + 2])
				at += 3
				var far: Dictionary = _far(context, far_bank, far_address, depth)
				out += String(far.get("text", ""))
				if not bool(far.get("ok", false)):
					return {"ok": false, "reason": far.get("reason", &"invalid_far_text"), "text": out}
				return {
					"ok": true, "text": out, "bytes": at,
					"prompt": bool(far.get("prompt", false)),
				}
			TX_DOTS:
				if not _has(data, at, 1):
					return _truncated(out, &"truncated_text_dots")
				out += "…".repeat(maxi(int(data[at]), 0))
				at += 1
			TX_DAY:
				out += _weekday(context) + "DAY"
			TX_LOW:
				out += "\n"
			TX_SCROLL:
				out += SCROLL_BREAK
			TX_PROMPT_BUTTON, TX_WAIT_BUTTON:
				# Both wait for a press; only the first shows the arrow, which is
				# the box's business rather than the string's.
				out += PAGE_BREAK
				prompt = true
			TX_PAUSE:
				pass
			TX_DECIMAL:
				# `text_decimal address, bytes, digits`: a number printed out of
				# live RAM. Marked rather than skipped, the way TX_RAM is, so a
				# caller that does know the value can put it in and one that does
				# not can see that a number belongs there.
				if not _has(data, at, 3):
					return _truncated(out, &"truncated_text_command")
				out += _decimal_string(context, data[at] | (data[at + 1] << 8))
				at += 3
			TX_BCD, TX_MOVE:
				# Three bytes of operand each, and each prints from live RAM this
				# project does not model. Skipped rather than drawn wrong.
				if not _has(data, at, 3):
					return _truncated(out, &"truncated_text_command")
				at += 3
			TX_BOX:
				if not _has(data, at, 4):
					return _truncated(out, &"truncated_text_command")
				at += 4
			TX_START_ASM:
				# `jp hl` into code. Nothing after it can be read as text.
				return {"ok": true, "text": out, "bytes": at, "prompt": prompt}
			_:
				return {
					"ok": false, "reason": &"unknown_text_command",
					"text": out, "command": command,
				}
	return {"ok": false, "reason": &"missing_text_terminator", "text": out}


## `PlaceString`/`CheckDict`: characters until the `@` that ends the literal.
static func _place(data: PackedByteArray, offset: int, context: Dictionary) -> Dictionary:
	var out: String = ""
	var at: int = offset
	while at < data.size():
		var byte: int = int(data[at])
		at += 1
		match byte:
			TX_END:
				return {"text": out, "at": at, "ended": false}
			CHAR_DONE:
				return {"text": out, "at": at, "ended": true, "prompt": false}
			CHAR_PROMPT:
				# `PromptText` waits for a press and falls through to `DoneText`.
				return {"text": out, "at": at, "ended": true, "prompt": true}
			CHAR_NULL:
				# `NullChar` prints a debugging error string. Treated as an end
				# rather than reproduced.
				return {"text": out, "at": at, "ended": true, "prompt": false}
			CHAR_LINE, CHAR_NEXT, CHAR_LF:
				out += "\n"
			CHAR_PARA:
				out += PAGE_BREAK
			CHAR_CONT, CHAR_CONT_RAW, CHAR_SCROLL:
				out += SCROLL_BREAK
			CHAR_WBR:
				pass
			CHAR_BSP:
				out += " "
			CHAR_DEXEND:
				out += "."
			_:
				out += _dict(byte, context)
	# Off the end of the data with no `@`, `<DONE>` or `<PROMPT>`: the text
	# is truncated, which is a wrong offset rather than a finished string.
	return {"text": out, "at": at, "truncated": true}


## The `print_name` half of `CheckDict`. Everything else is a glyph.
static func _dict(byte: int, context: Dictionary) -> String:
	match byte:
		0x52:
			return _name(context, "player", "<PLAYER>")
		0x53:
			return _name(context, "rival", "<RIVAL>")
		0x49:
			return _name(context, "mom", "<MOM>")
		0x38:
			return _name(context, "red", "<RED>")
		0x39:
			return _name(context, "green", "<GREEN>")
		0x3F:
			return _name(context, "enemy", "<ENEMY>")
		0x59:
			return _name(context, "target", "<TARGET>")
		0x5A:
			return _name(context, "user", "<USER>")
	return Gen2Text.character(byte)


static func _name(context: Dictionary, key: String, fallback: String) -> String:
	var value: String = String(context.get(key, ""))
	return value if not value.is_empty() else fallback


## Replaces the first marker of [param prefix] in [param text] with
## [param value]. The address inside a marker is the profile's own WRAM, so a
## screen substitutes by position rather than by naming one.
static func fill_marker(text: String, prefix: String, value: String) -> String:
	var at: int = text.find(prefix)
	if at < 0:
		return text
	var end: int = text.find(">", at)
	if end < 0:
		return text
	return text.substr(0, at) + value + text.substr(end + 1)


static func _ram_string(context: Dictionary, address: int) -> String:
	var ram: Variant = context.get("ram", {})
	if ram is Dictionary and (ram as Dictionary).has(address):
		return String((ram as Dictionary)[address])
	return "%s%04X>" % [RAM_MARKER, address]


static func _decimal_string(context: Dictionary, address: int) -> String:
	var decimals: Variant = context.get("decimals", {})
	if decimals is Dictionary and (decimals as Dictionary).has(address):
		return String((decimals as Dictionary)[address])
	return "%s%04X>" % [NUMBER_MARKER, address]


static func _buffer_string(context: Dictionary, buffer: int) -> String:
	var buffers: Variant = context.get("buffers", {})
	if buffers is Dictionary and (buffers as Dictionary).has(buffer):
		return String((buffers as Dictionary)[buffer])
	return "<BUFFER_%d>" % buffer


static func _weekday(context: Dictionary) -> String:
	var day: int = int(context.get("weekday", 0))
	return WEEKDAYS[posmod(day, WEEKDAYS.size())]


## `TextCommand_FAR` banks in and runs the target as a whole text of its own.
## Bounded: a text that pointed at itself would otherwise never return.
static func _far(context: Dictionary, bank: int, address: int, depth: int) -> Dictionary:
	if depth >= 4:
		return {"ok": false, "reason": &"text_far_too_deep"}
	var resolver: Variant = context.get("far", null)
	if not resolver is Callable or not (resolver as Callable).is_valid():
		return {"ok": false, "reason": &"text_far_unresolved"}
	var bytes: Variant = (resolver as Callable).call(bank, address)
	if not bytes is PackedByteArray or (bytes as PackedByteArray).is_empty():
		return {"ok": false, "reason": &"text_far_unresolved"}
	return _run(bytes as PackedByteArray, 0, context, depth + 1)


static func _truncated(text: String, reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason, "text": text}


static func _has(data: PackedByteArray, at: int, count: int) -> bool:
	return at >= 0 and at + count <= data.size()
