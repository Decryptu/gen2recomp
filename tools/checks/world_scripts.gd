extends RefCounted

## The one cached "text" that is not one. `96:4081` is bank 96, `0x180081` in a
## Gold or Silver dump, and the bytes there are a pointer table: `00 09 3a 42 03
## 94 40 31 2d ...`, the same `00 09 xx 42 31 xx` row repeating. The reference
## scanner reached it through bytes that are not commands, which is where the
## parse failures and the unwired `0415` marker below come from too.
const NOT_A_TEXT: Array[String] = ["96:4081"]

var _r: RefCounted = null

## Reports how far the cached overworld script and text resources can be read.
## This tool only reads the derived user cache. It never writes cartridge data
## into the project.
##
##   Godot --headless --path . -s res://tools/validate.gd -- world_scripts


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		if not _validate(game_id):
			_r.fail("%s: the cached scripts and text did not read back." % game_id)


func _validate(game_id: StringName) -> bool:
	var data: GameData = GameData.open(game_id)
	if data == null:
		print("FAIL %s: cache is not usable" % game_id)
		return false
	var scripts_value: Variant = RomCache.read_json(
		RomCache.world_scripts_path(data.directory)
	)
	var text_value: Variant = RomCache.read_json(
		RomCache.world_text_path(data.directory)
	)
	var movement_value: Variant = RomCache.read_json(
		RomCache.world_movements_path(data.directory)
	)
	if not scripts_value is Dictionary or not text_value is Dictionary:
		print("FAIL %s: script or text table is missing" % game_id)
		return false

	var crystal_commands: bool = game_id == &"crystal"
	var script_count: int = 0
	var command_count: int = 0
	var walk_end_count: int = 0
	var parse_failures: int = 0
	var failure_reasons: Dictionary = {}
	var failure_opcodes: Dictionary = {}
	var command_names: Dictionary = {}
	for raw_key: Variant in (scripts_value as Dictionary):
		# Read through GameData rather than off the JSON: the cache stores byte
		# runs as spans into a blob, and this checks the path the runtime uses.
		var bytes: PackedByteArray = _pointer_bytes(data, String(raw_key), false)
		if bytes.is_empty():
			parse_failures += 1
			failure_reasons["empty_script"] = int(failure_reasons.get("empty_script", 0)) + 1
			continue
		script_count += 1
		var offset: int = 0
		var steps: int = 0
		while offset < bytes.size() and steps < Gen2WorldScript.MAX_COMMANDS:
			var command: Dictionary = Gen2WorldScript.command_at(bytes, offset, crystal_commands)
			if not bool(command.get("ok", false)):
				parse_failures += 1
				var reason: String = String(command.get("reason", "unknown"))
				failure_reasons[reason] = int(failure_reasons.get(reason, 0)) + 1
				if command.has("opcode"):
					var opcode: String = "%02X" % int(command["opcode"])
					failure_opcodes[opcode] = int(failure_opcodes.get(opcode, 0)) + 1
				break
			var name: String = String(command.get("name", ""))
			command_names[name] = int(command_names.get(name, 0)) + 1
			command_count += 1
			steps += 1
			offset += int(command["width"])
			if not Gen2WorldScript.continues_after(int(command["opcode"]), crystal_commands):
				walk_end_count += 1
				break

	var invalid_text: int = 0
	var invalid_text_reasons: Dictionary = {}
	var invalid_text_samples: Array = []
	var ram_addresses: Dictionary = {}
	var number_markers: int = 0
	var raw_bytes: Dictionary = {}
	for raw_key: Variant in (text_value as Dictionary):
		var raw_text: PackedByteArray = _pointer_bytes(data, String(raw_key), true)
		var decoded: Dictionary = Gen2WorldScript.decode_text(raw_text)
		if not bool(decoded.get("ok", false)):
			invalid_text += 1
			var reason: String = String(decoded.get("reason", "unknown"))
			invalid_text_reasons[reason] = int(invalid_text_reasons.get(reason, 0)) + 1
			if invalid_text_samples.size() < 3:
				invalid_text_samples.append({"length": raw_text.size(), "head": _head(raw_text)})
		var text: String = String(decoded.get("text", ""))
		_tally_ram_markers(text, ram_addresses)
		number_markers += text.count(Gen2TextStream.NUMBER_MARKER)
		_tally_raw_bytes(text, String(raw_key), raw_bytes)

	print("%s: scripts=%d commands=%d walk_ends=%d parse_failures=%d texts=%d invalid_text=%d" % [
		game_id, script_count, command_count, walk_end_count, parse_failures,
		(text_value as Dictionary).size(), invalid_text,
	])
	print("  movements=%d" % (movement_value as Dictionary).size() \
		if movement_value is Dictionary else "  movements=missing")
	print("  failures=%s" % failure_reasons)
	print("  failure_opcodes=%s" % failure_opcodes)
	print("  invalid_text_reasons=%s" % invalid_text_reasons)
	print("  invalid_text_samples=%s" % JSON.stringify(invalid_text_samples))
	print("  commands=%s" % command_names)
	_print_ram_markers(data, ram_addresses, number_markers)
	print("  raw_byte_markers=%s" % raw_bytes)
	_print_standard_table(game_id)
	return raw_bytes.is_empty()


## Resolves one "bank:address" cache key through the runtime accessor.
func _pointer_bytes(data: GameData, key: String, text: bool) -> PackedByteArray:
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2:
		return PackedByteArray()
	var bank: int = int(parts[0])
	var address: int = ("0x%s" % parts[1]).hex_to_int()
	return data.world_text(bank, address) if text else data.world_script(bank, address)


## The `<xx>` [method Gen2Text.character] leaves for a byte it has no character
## for, which is a decoder gap rather than anything the cartridge draws: every
## byte `PlaceString` reaches is either a glyph or a `CheckDict` entry. `$14`
## reached the player as `?14?` mid-sentence in 243 Crystal texts before
## `<PLAY_G>` was wired, so this is a failure and not a census.
func _tally_raw_bytes(text: String, key: String, tally: Dictionary) -> void:
	var found: Array[RegExMatch] = RegEx.create_from_string("<([0-9A-F]{2})>").search_all(text)
	if found.is_empty():
		return
	if NOT_A_TEXT.has(key):
		return
	var bytes: PackedStringArray = PackedStringArray()
	for match_result: RegExMatch in found:
		bytes.append(match_result.get_string(1))
	tally[key] = bytes


## Counts the `<RAM_xxxx>` markers one decoded text left behind.
func _tally_ram_markers(text: String, tally: Dictionary) -> void:
	var at: int = text.find(Gen2TextStream.RAM_MARKER)
	while at >= 0:
		var address: int = ("0x%s" % text.substr(
			at + Gen2TextStream.RAM_MARKER.length(), 4
		)).hex_to_int()
		tally[address] = int(tally.get(address, 0)) + 1
		at = text.find(Gen2TextStream.RAM_MARKER, at + 1)


## Which `text_ram` targets the corpus names, split by whether the runner can
## answer one. Everything it can is a StringBufferPointers entry, which is what
## `Gen2WorldScriptRunner._text_buffer_ram` fills; an address outside that table
## names storage nothing here writes and reaches the player as `<RAM_xxxx>`.
##
## Gold and Silver each carry one unwired entry, `0415`, and it is not a text:
## the reference scanner reaches 94:4188 through bytes that are not commands,
## the same speculation the parse failures above come from.
func _print_ram_markers(data: GameData, tally: Dictionary, numbers: int) -> void:
	var buffers: Array[int] = data.string_buffer_addresses()
	var wired: int = 0
	var unwired: Dictionary = {}
	for address: Variant in tally:
		var count: int = int(tally[address])
		if buffers.has(int(address)):
			wired += count
		else:
			unwired["%04X" % int(address)] = count
	print("  ram_markers wired=%d unwired=%s number_markers=%d" % [wired, unwired, numbers])


func _head(bytes: PackedByteArray) -> String:
	var out: PackedStringArray = []
	for index: int in mini(12, bytes.size()):
		out.append("%02X" % int(bytes[index]))
	return " ".join(out)


func _print_standard_table(game_id: StringName) -> void:
	var rom: RomFile = RomFile.open_verified("res://roms/%s.gbc" % game_id)
	if rom == null:
		return
	var bank: int = 0x2F if game_id == &"crystal" else 0x40
	var entries: Array = []
	for index: int in 60:
		var offset: int = RomFile.linear(bank, 0x4000 + index * 3)
		var target_bank: int = rom.u8(offset)
		var target_address: int = rom.u16le(offset + 1)
		if target_bank <= 0 or target_address < RomFile.BANK_SIZE \
			or target_address >= RomFile.BANK_SIZE * 2:
			break
		entries.append("%d:%04X" % [target_bank, target_address])
	print("  standard_table bank=%02X entries=%d first=%s" % [
		bank, entries.size(), JSON.stringify(entries.slice(0, mini(5, entries.size()))),
	])
