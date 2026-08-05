extends SceneTree

## Reports how far the cached overworld script and text resources can be read.
## This tool only reads the derived user cache. It never writes cartridge data
## into the project.
##
##   Godot --headless --path . -s res://tools/validate_world_scripts.gd -- gold silver crystal

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]


func _initialize() -> void:
	var requested: Array[StringName] = []
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--"):
			continue
		requested.append(StringName(raw.to_lower()))
	if requested.is_empty():
		requested = GAME_IDS.duplicate()

	var failures: int = 0
	for game_id: StringName in requested:
		if not GAME_IDS.has(game_id):
			print("FAIL %s: unknown game id" % game_id)
			failures += 1
			continue
		if not _validate(game_id):
			failures += 1
	quit(1 if failures > 0 else 0)


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
	var terminal_count: int = 0
	var parse_failures: int = 0
	var failure_reasons: Dictionary = {}
	var failure_opcodes: Dictionary = {}
	var command_names: Dictionary = {}
	for raw_key: Variant in (scripts_value as Dictionary):
		var bytes: PackedByteArray = _bytes(scripts_value[raw_key])
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
			if Gen2WorldScript.is_terminal(int(command["opcode"]), crystal_commands):
				terminal_count += 1
				break

	var invalid_text: int = 0
	var invalid_text_reasons: Dictionary = {}
	var invalid_text_samples: Array = []
	for raw_value: Variant in (text_value as Dictionary).values():
		var raw_text: PackedByteArray = _bytes(raw_value)
		var decoded: Dictionary = Gen2WorldScript.decode_text(raw_text)
		if not bool(decoded.get("ok", false)):
			invalid_text += 1
			var reason: String = String(decoded.get("reason", "unknown"))
			invalid_text_reasons[reason] = int(invalid_text_reasons.get(reason, 0)) + 1
			if invalid_text_samples.size() < 3:
				invalid_text_samples.append({"length": raw_text.size(), "head": _head(raw_text)})
	print("%s: scripts=%d commands=%d terminal=%d parse_failures=%d texts=%d invalid_text=%d" % [
		game_id, script_count, command_count, terminal_count, parse_failures,
		(text_value as Dictionary).size(), invalid_text,
	])
	print("  movements=%d" % (movement_value as Dictionary).size() \
		if movement_value is Dictionary else "  movements=missing")
	print("  failures=%s" % failure_reasons)
	print("  failure_opcodes=%s" % failure_opcodes)
	print("  invalid_text_reasons=%s" % invalid_text_reasons)
	print("  invalid_text_samples=%s" % JSON.stringify(invalid_text_samples))
	print("  commands=%s" % command_names)
	_print_standard_table(game_id)
	return true


func _bytes(value: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	if not value is Array:
		return out
	for byte: Variant in value as Array:
		out.append(int(byte))
	return out


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
