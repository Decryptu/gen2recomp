class_name Gen2WorldServicesImporter
extends RefCounted

## Imports the global services used by overworld scripts. These records are
## cartridge data, not runtime policy: the importer keeps the source pointers,
## bounded raw payloads and the fields the script interpreter needs to resolve
## a request without opening a ROM later.

const MAX_MENU_DATA_BYTES: int = 256
const MAX_MENU_ITEMS: int = 32
const MAX_AUDIO_POINTERS: int = 512


static func verify_layout(rom: RomFile) -> Dictionary:
	var layout: Dictionary = RomLayout.for_id(rom.id)
	if layout.is_empty():
		return {"ok": false, "message": "No service layout for %s." % rom.id}
	var result: Dictionary = read_services(rom, layout)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("message", "Service data failed validation."))}
	return {"ok": true, "message": ""}


static func import_to_cache(
	rom: RomFile,
	layout: Dictionary,
	directory: String,
	scripts: Dictionary = {},
	standard_scripts: Dictionary = {},
) -> Dictionary:
	var result: Dictionary = read_services(rom, layout, scripts, standard_scripts)
	if not bool(result.get("ok", false)):
		return result
	if not RomCache.write_json(RomCache.world_menus_path(directory), result["menus"]):
		return _error("Could not write world menu data.")
	if not RomCache.write_json(RomCache.world_marts_path(directory), result["marts"]):
		return _error("Could not write world mart data.")
	if not RomCache.write_json(RomCache.world_phone_path(directory), result["phone"]):
		return _error("Could not write world phone data.")
	if not RomCache.write_json(RomCache.world_audio_path(directory), result["audio"]):
		return _error("Could not write world audio data.")

	return {
		"ok": true,
		"menus": result["menus"].size(),
		"marts": (result["marts"].get("marts", []) as Array).size(),
		"phone_contacts": (result["phone"].get("contacts", []) as Array).size(),
		"special_phone_calls": (result["phone"].get("special_calls", []) as Array).size(),
		"music": (result["audio"].get("music", []) as Array).size(),
		"sfx": (result["audio"].get("sfx", []) as Array).size(),
	}


static func read_services(
	rom: RomFile,
	layout: Dictionary,
	scripts: Dictionary = {},
	standard_scripts: Dictionary = {},
) -> Dictionary:
	var marts: Dictionary = _read_marts(rom, layout)
	if not bool(marts.get("ok", false)):
		return marts
	var phone: Dictionary = _read_phone(rom, layout)
	if not bool(phone.get("ok", false)):
		return phone
	var audio: Dictionary = _read_audio(rom, layout)
	if not bool(audio.get("ok", false)):
		return audio
	var menus: Dictionary = _read_menus(rom, scripts, standard_scripts)
	if not bool(menus.get("ok", false)):
		return menus
	return {
		"ok": true,
		"menus": menus["menus"],
		"marts": marts["data"],
		"phone": phone["data"],
		"audio": audio["data"],
	}


static func _read_marts(rom: RomFile, layout: Dictionary) -> Dictionary:
	var table: int = int(layout["mart_table"])
	var bank: int = RomLayout.bank_of(table)
	if not rom.in_bounds(table, RomLayout.MART_COUNT * RomLayout.MART_POINTER_SIZE):
		return _error("Mart pointer table is outside the cartridge.")

	var marts: Array = []
	for index: int in RomLayout.MART_COUNT:
		var address: int = rom.u16le(table + index * RomLayout.MART_POINTER_SIZE)
		var list: Dictionary = _read_mart_list(rom, bank, address, false)
		if not bool(list.get("ok", false)):
			return _error("Mart %d: %s" % [index, list.get("message", "invalid item list")])
		marts.append({
			"index": index,
			"bank": bank,
			"address": address,
			"items": list["items"],
		})

	var default_list: Dictionary = _read_mart_list_at(rom, int(layout["default_mart"]))
	if not bool(default_list.get("ok", false)):
		return _error("Default mart: %s" % default_list.get("message", "invalid item list"))

	var special: Dictionary = {}
	var bargain: Dictionary = _read_price_mart_at(
		rom, int(layout["bargain_mart"]), "bargain"
	)
	if not bool(bargain.get("ok", false)):
		return bargain
	if not bargain["items"].is_empty():
		special["bargain"] = bargain["items"]
	if int(layout.get("rooftop_mart_count", 0)) > 0:
		for key: String in ["rooftop_mart_1", "rooftop_mart_2"]:
			var rooftop: Dictionary = _read_price_mart_at(
				rom, int(layout[key]), key
			)
			if not bool(rooftop.get("ok", false)):
				return rooftop
			special[key] = rooftop["items"]

	return {
		"ok": true,
		"data": {
			"marts": marts,
			"default": {
				"bank": bank,
				"offset": int(layout["default_mart"]),
				"items": default_list["items"],
			},
			"special": special,
		},
	}


static func _read_mart_list(rom: RomFile, bank: int, address: int, _priced: bool) -> Dictionary:
	if not _valid_cpu_address(address):
		return {"ok": false, "message": "invalid CPU address $%04X" % address}
	var offset: int = RomFile.linear(bank, address)
	return _read_mart_list_at(rom, offset)


static func _read_mart_list_at(rom: RomFile, offset: int) -> Dictionary:
	if not rom.in_bounds(offset):
		return {"ok": false, "message": "record is outside the cartridge"}
	var count: int = rom.u8(offset)
	if count > RomLayout.MART_RECORD_MAX_ITEMS:
		return {"ok": false, "message": "item count %d is too large" % count}
	if not rom.in_bounds(offset + 1, count + 1):
		return {"ok": false, "message": "item list is truncated"}
	var items: Array = []
	for item_index: int in count:
		var item: int = rom.u8(offset + 1 + item_index)
		if item <= 0 or item == RomLayout.MART_TERMINATOR:
			return {"ok": false, "message": "item %d is invalid" % item}
		items.append(item)
	if rom.u8(offset + 1 + count) != RomLayout.MART_TERMINATOR:
		return {"ok": false, "message": "missing $FF terminator"}
	return {"ok": true, "items": items}


static func _read_price_mart(rom: RomFile, bank: int, address: int, name: String) -> Dictionary:
	if not _valid_cpu_address(address):
		return _error("%s mart has an invalid CPU address." % name)
	var offset: int = RomFile.linear(bank, address)
	return _read_price_mart_at(rom, offset, name)


static func _read_price_mart_at(rom: RomFile, offset: int, name: String) -> Dictionary:
	if not rom.in_bounds(offset):
		return _error("%s mart is outside the cartridge." % name)
	var count: int = rom.u8(offset)
	if count > RomLayout.MART_RECORD_MAX_ITEMS or not rom.in_bounds(offset + 1, count * 3 + 1):
		return _error("%s mart is truncated." % name)
	var items: Array = []
	for index: int in count:
		var at: int = offset + 1 + index * 3
		var item: int = rom.u8(at)
		if item <= 0 or item == RomLayout.MART_TERMINATOR:
			return _error("%s mart item %d is invalid." % [name, index])
		items.append({"item": item, "price": rom.u16le(at + 1)})
	if rom.u8(offset + 1 + count * 3) != RomLayout.MART_TERMINATOR:
		return _error("%s mart is missing its terminator." % name)
	return {"ok": true, "items": items}


static func _read_phone(rom: RomFile, layout: Dictionary) -> Dictionary:
	var table: int = int(layout["phone_contacts"])
	if not rom.in_bounds(table, RomLayout.PHONE_CONTACT_COUNT * RomLayout.PHONE_CONTACT_SIZE):
		return _error("Phone contact table is outside the cartridge.")
	var contacts: Array = []
	for index: int in RomLayout.PHONE_CONTACT_COUNT:
		var at: int = table + index * RomLayout.PHONE_CONTACT_SIZE
		var callee: Dictionary = _phone_pointer(rom, at + 5)
		var caller: Dictionary = _phone_pointer(rom, at + 9)
		if callee.is_empty() or caller.is_empty():
			return _error("Phone contact %d has an invalid script pointer." % index)
		contacts.append({
			"index": index,
			"trainer_class": rom.u8(at),
			"trainer_number": rom.u8(at + 1),
			"map_group": rom.u8(at + 2),
			"map_number": rom.u8(at + 3),
			"callee_time": rom.u8(at + 4),
			"callee_script": callee,
			"caller_time": rom.u8(at + 8),
			"caller_script": caller,
		})

	var special_table: int = int(layout["special_phone_calls"])
	if not rom.in_bounds(
		special_table, RomLayout.SPECIAL_PHONE_CALL_COUNT * RomLayout.SPECIAL_PHONE_CALL_SIZE
	):
		return _error("Special phone-call table is outside the cartridge.")
	var special_calls: Array = []
	for index: int in RomLayout.SPECIAL_PHONE_CALL_COUNT:
		var at: int = special_table + index * RomLayout.SPECIAL_PHONE_CALL_SIZE
		var script: Dictionary = _phone_pointer(rom, at + 3)
		if script.is_empty():
			return _error("Special phone call %d has an invalid script pointer." % index)
		special_calls.append({
			"index": index,
			"condition": rom.u16le(at),
			"contact": rom.u8(at + 2),
			"script": script,
		})

	return {
		"ok": true,
		"data": {"contacts": contacts, "special_calls": special_calls},
	}


static func _phone_pointer(rom: RomFile, at: int) -> Dictionary:
	var bank: int = rom.u8(at)
	var address: int = rom.u16le(at + 1)
	if not _valid_cpu_address(address) or not rom.in_bounds(RomFile.linear(bank, address)):
		return {}
	return {"bank": bank, "address": address}


static func _read_audio(rom: RomFile, layout: Dictionary) -> Dictionary:
	var music_result: Dictionary = _read_audio_table(
		rom, int(layout["music_pointers"]), int(layout["music_count"]), "music",
		int(layout["music_first_bank"]), int(layout["music_first_address"])
	)
	if not bool(music_result.get("ok", false)):
		return music_result
	var sfx_result: Dictionary = _read_audio_table(
		rom, int(layout["sfx_pointers"]), int(layout["sfx_count"]), "sfx",
		int(layout["sfx_first_bank"]), int(layout["sfx_first_address"])
	)
	if not bool(sfx_result.get("ok", false)):
		return sfx_result

	var rows: Array = music_result["rows"] + sfx_result["rows"]
	var targets: Array = []
	for row: Dictionary in rows:
		targets.append({"bank": int(row["bank"]), "offset": int(row["offset"])})
	for row: Dictionary in rows:
		var next_offset: int = rom.size()
		for target: Dictionary in targets:
			if int(target["bank"]) == int(row["bank"]) \
				and int(target["offset"]) > int(row["offset"]):
				next_offset = mini(next_offset, int(target["offset"]))
		var end: int = mini(
			next_offset, int(row["offset"]) + RomLayout.AUDIO_MAX_RECORD_BYTES
		)
		var raw: PackedByteArray = rom.slice(int(row["offset"]), end - int(row["offset"]))
		row["bytes"] = Array(raw)
		row["byte_count"] = raw.size()

	return {
		"ok": true,
		"data": {"music": music_result["rows"], "sfx": sfx_result["rows"]},
	}


static func _read_audio_table(
	rom: RomFile, table: int, count: int, kind: String, expected_bank: int, expected_address: int
) -> Dictionary:
	if count <= 0 or count > MAX_AUDIO_POINTERS \
		or not rom.in_bounds(table, count * RomLayout.AUDIO_POINTER_SIZE):
		return _error("%s pointer table is outside the cartridge." % kind)
	var first: Dictionary = rom.far_pointer(table)
	if int(first["bank"]) != expected_bank or int(first["address"]) != expected_address:
		return _error(
			"%s pointer table starts at $%02X:$%04X, expected $%02X:$%04X." % [
				kind, first["bank"], first["address"], expected_bank, expected_address,
			]
		)
	var rows: Array = []
	for index: int in count:
		var pointer: Dictionary = rom.far_pointer(table + index * RomLayout.AUDIO_POINTER_SIZE)
		var bank: int = int(pointer["bank"])
		var address: int = int(pointer["address"])
		if not _valid_cpu_address(address) or not rom.in_bounds(RomFile.linear(bank, address)):
			return _error("%s %d has an invalid far pointer." % [kind, index])
		rows.append({
			"index": index,
			"bank": bank,
			"address": address,
			"offset": RomFile.linear(bank, address),
		})
	return {"ok": true, "rows": rows}


static func _read_menus(rom: RomFile, scripts: Dictionary, standard_scripts: Dictionary) -> Dictionary:
	var references: Dictionary = {}
	for key: String in scripts:
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 2:
			continue
		_scan_menu_references(
			rom, _bytes_from_variant(scripts[key]), int(parts[0]), rom.id == &"crystal", references
		)
	for value: Dictionary in standard_scripts.values():
		_scan_menu_references(
			rom, _bytes_from_variant(value.get("bytes", [])), int(value.get("bank", 0)),
			rom.id == &"crystal", references
		)

	var menus: Dictionary = {}
	for key: String in references:
		var reference: Dictionary = references[key]
		var bank: int = int(reference["bank"])
		var address: int = int(reference["address"])
		if not _valid_cpu_address(address):
			continue
		var header_offset: int = RomFile.linear(bank, address)
		if not rom.in_bounds(header_offset, 8):
			continue
		var data_address: int = rom.u16le(header_offset + 5)
		var raw: PackedByteArray = PackedByteArray()
		if data_address != 0:
			if not _valid_cpu_address(data_address):
				continue
			raw = rom.slice(RomFile.linear(bank, data_address), MAX_MENU_DATA_BYTES)
			if raw.is_empty():
				continue
		var row: Dictionary = {
			"bank": bank,
			"address": address,
			"flags": rom.u8(header_offset),
			"top": rom.u8(header_offset + 1),
			"left": rom.u8(header_offset + 2),
			"bottom": rom.u8(header_offset + 3),
			"right": rom.u8(header_offset + 4),
			"data_bank": bank,
			"data_address": data_address,
			"default": rom.u8(header_offset + 7),
			"uses": reference.get("uses", []),
			"data": Array(raw),
		}
		var decoded: Dictionary = _decode_menu_data(raw)
		for decoded_key: String in decoded:
			row[decoded_key] = decoded[decoded_key]
		menus[key] = row
	return {"ok": true, "menus": menus}


static func _scan_menu_references(
	rom: RomFile,
	data: PackedByteArray,
	bank: int,
	crystal_commands: bool,
	references: Dictionary,
) -> void:
	var at: int = 0
	var last_key: String = ""
	for _command_index: int in Gen2WorldScript.MAX_COMMANDS:
		if at >= data.size():
			break
		var command: Dictionary = Gen2WorldScript.command_at(data, at, crystal_commands)
		if not bool(command.get("ok", false)):
			break
		var opcode: int = int(command["opcode"])
		if opcode == Gen2WorldScript.LOADMENU:
			var menu_address: int = int(command["address"])
			if _valid_cpu_address(menu_address):
				last_key = Gen2WorldScript.pointer_key(bank, menu_address)
				if not references.has(last_key):
					references[last_key] = {
						"bank": bank, "address": menu_address, "uses": [],
					}
			else:
				last_key = ""
		var source_opcode: int = opcode - 1 if crystal_commands and opcode >= 0x56 else opcode
		if source_opcode in [0x57, 0x58] and not last_key.is_empty() and references.has(last_key):
			var use: String = "2d" if source_opcode == 0x57 else "vertical"
			var uses: Array = references[last_key]["uses"]
			if not uses.has(use):
				uses.append(use)
		at += int(command["width"])
		if Gen2WorldScript.is_terminal(opcode, crystal_commands):
			break


static func _decode_menu_data(raw: PackedByteArray) -> Dictionary:
	if raw.size() < 2:
		return {}
	var out: Dictionary = {"data_flags": raw[0]}
	var count_or_dimensions: int = raw[1]
	if count_or_dimensions > 0 and count_or_dimensions <= MAX_MENU_ITEMS:
		var options: Array = []
		var at: int = 2
		for _index: int in count_or_dimensions:
			if at >= raw.size():
				return out
			var end: int = at
			while end < raw.size() and raw[end] != Gen2Text.TERMINATOR:
				end += 1
			if end >= raw.size():
				return out
			options.append(Gen2Text.decode(raw, at, end - at))
			at = end + 1
		out["options"] = options
		out["kind"] = "static"
		return out
	if raw.size() >= 9:
		out["kind"] = "2d_or_scrolling"
		out["dimensions"] = count_or_dimensions
		out["spacing_or_width"] = raw[2]
		out["pointer_bank_or_format"] = raw[3]
	return out


static func _bytes_from_variant(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	if not value is Array:
		return PackedByteArray()
	var raw: Array = value as Array
	var out := PackedByteArray()
	out.resize(raw.size())
	for index: int in out.size():
		out[index] = int(raw[index])
	return out


static func _valid_cpu_address(address: int) -> bool:
	return address >= RomFile.BANK_SIZE and address < RomFile.BANK_SIZE * 2


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
