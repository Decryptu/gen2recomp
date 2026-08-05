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
	text_data: Dictionary = {},
	movement_data: Dictionary = {},
) -> Dictionary:
	var result: Dictionary = read_services(
		rom, layout, scripts, standard_scripts, text_data, movement_data
	)
	if not bool(result.get("ok", false)):
		return result
	if not RomCache.write_json(RomCache.world_menus_path(directory), result["menus"]):
		return _error("Could not write world menu data.")
	if not RomCache.write_json(RomCache.world_marts_path(directory), result["marts"]):
		return _error("Could not write world mart data.")
	if not RomCache.write_json(RomCache.world_phone_path(directory), result["phone"]):
		return _error("Could not write world phone data.")
	if not RomCache.write_section(
		RomCache.world_audio_path(directory),
		RomCache.blob_path(RomCache.world_audio_path(directory)),
		result["audio"],
	):
		return _error("Could not write world audio data.")
	if not RomCache.write_payload_map(
		RomCache.world_scripts_path(directory),
		RomCache.blob_path(RomCache.world_scripts_path(directory)), scripts,
	):
		return _error("Could not update world scripts with phone scripts.")
	if not RomCache.write_payload_map(
		RomCache.world_text_path(directory),
		RomCache.blob_path(RomCache.world_text_path(directory)), text_data,
	):
		return _error("Could not update world text with phone text.")
	if not RomCache.write_payload_map(
		RomCache.world_movements_path(directory),
		RomCache.blob_path(RomCache.world_movements_path(directory)), movement_data,
	):
		return _error("Could not update world movements with phone movements.")

	return {
		"ok": true,
		"menus": result["menus"].size(),
		"marts": (result["marts"].get("marts", []) as Array).size(),
		"phone_contacts": (result["phone"].get("contacts", []) as Array).size(),
		"special_phone_calls": (result["phone"].get("special_calls", []) as Array).size(),
		"phone_scripts": int(result.get("phone_scripts", 0)),
		"music": (result["audio"].get("music", []) as Array).size(),
		"sfx": (result["audio"].get("sfx", []) as Array).size(),
		"cries": (result["audio"].get("cries", []) as Array).size(),
	}


static func read_services(
	rom: RomFile,
	layout: Dictionary,
	scripts: Dictionary = {},
	standard_scripts: Dictionary = {},
	text_data: Dictionary = {},
	movement_data: Dictionary = {},
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
	var phone_scripts: int = _collect_phone_scripts(
		rom, phone["data"], scripts, text_data, movement_data
	)
	return {
		"ok": true,
		"menus": menus["menus"],
		"marts": marts["data"],
		"phone": phone["data"],
		"audio": audio["data"],
		"phone_scripts": phone_scripts,
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
			"condition_kind": _phone_condition_kind(
				rom.u16le(at), layout
			),
			"contact": rom.u8(at + 2),
			"script": script,
		})
	var out_of_area: Dictionary = _layout_script_pointer(
		rom, layout, "phone_out_of_area_bank", "phone_out_of_area_address"
	)
	var just_talk: Dictionary = _layout_script_pointer(
		rom, layout, "phone_just_talk_bank", "phone_just_talk_address"
	)
	if out_of_area.is_empty() or just_talk.is_empty():
		return _error("Phone service script pointers are invalid.")

	return {
		"ok": true,
		"data": {
			"contacts": contacts,
			"special_calls": special_calls,
			"metadata": {
				"max_contacts": 10,
				"permanent_contacts": [1, 4],
				"receive_call_delays": [20, 10, 5, 3],
				"out_of_area_script": out_of_area,
				"just_talk_script": just_talk,
			},
		},
	}


static func _phone_pointer(rom: RomFile, at: int) -> Dictionary:
	var bank: int = rom.u8(at)
	var address: int = rom.u16le(at + 1)
	if not _valid_cpu_address(address) or not rom.in_bounds(RomFile.linear(bank, address)):
		return {}
	return {"bank": bank, "address": address}


static func _layout_script_pointer(
	rom: RomFile, layout: Dictionary, bank_key: String, address_key: String
) -> Dictionary:
	var bank: int = int(layout.get(bank_key, -1))
	var address: int = int(layout.get(address_key, -1))
	if bank < 0 or not _valid_cpu_address(address):
		return {}
	if not rom.in_bounds(RomFile.linear(bank, address)):
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
	var cry_result: Dictionary = _read_audio_table(
		rom, int(layout["cry_pointers"]), RomLayout.AUDIO_CRY_COUNT, "cry",
		int(layout["cry_first_bank"]), int(layout["cry_first_address"])
	)
	if not bool(cry_result.get("ok", false)):
		return cry_result
	var assets: Dictionary = _read_audio_assets(rom, layout)
	if not bool(assets.get("ok", false)):
		return assets

	var rows: Array = music_result["rows"] + sfx_result["rows"] + cry_result["rows"]
	for row: Dictionary in rows:
		var window: Dictionary = _audio_data_window(rom, row)
		if not bool(window.get("ok", false)):
			return window
		var start: int = int(window["start"])
		var end: int = int(window["end"])
		var raw: PackedByteArray = rom.slice(start, end - start)
		row["bytes"] = Array(raw)
		row["byte_count"] = raw.size()
		row["data_offset"] = start
		row["data_address"] = int(window["address"])

	return {
		"ok": true,
		"data": {
			"music": music_result["rows"],
			"sfx": sfx_result["rows"],
			"cries": cry_result["rows"],
			"wave_samples": assets["wave_samples"],
			"drumkits": assets["drumkits"],
		},
	}


static func _audio_data_window(rom: RomFile, row: Dictionary) -> Dictionary:
	var bank: int = int(row["bank"])
	var header_offset: int = int(row["offset"])
	if not rom.in_bounds(header_offset, 1):
		return _error("Audio record header is outside the cartridge.")
	var channel_count: int = ((rom.u8(header_offset) >> 6) & 0x03) + 1
	for channel: int in channel_count:
		var entry: int = header_offset + channel * 3
		if not rom.in_bounds(entry, 3):
			return _error("Audio record channel header is truncated.")
		var address: int = _audio_address(rom.u16le(entry + 1))
		var pointer_offset: int = RomFile.linear(bank, address)
		if not rom.in_bounds(pointer_offset, 1):
			return _error("Audio record channel pointer is outside the cartridge.")
	var bank_start: int = bank * RomFile.BANK_SIZE
	var bank_end: int = mini(rom.size(), bank_start + RomFile.BANK_SIZE)
	var start: int = bank_start
	var end: int = mini(bank_end, start + RomLayout.AUDIO_MAX_RECORD_BYTES)
	if end <= start:
		return _error("Audio record has no readable data window.")
	return {
		"ok": true,
		"start": start,
		"end": end,
		"address": 0x4000 + (start - bank_start),
}


static func _collect_phone_scripts(
	rom: RomFile,
	phone: Dictionary,
	scripts: Dictionary,
	text_data: Dictionary,
	movement_data: Dictionary,
) -> int:
	var before: int = scripts.size()
	for contact: Dictionary in phone.get("contacts", []):
		for field: String in ["callee_script", "caller_script"]:
			var pointer: Dictionary = contact.get(field, {})
			Gen2WorldImporter.collect_script(
				rom, int(pointer.get("bank", -1)), int(pointer.get("address", -1)),
				scripts, text_data, movement_data
			)
	for special_call: Dictionary in phone.get("special_calls", []):
		var pointer: Dictionary = special_call.get("script", {})
		Gen2WorldImporter.collect_script(
			rom, int(pointer.get("bank", -1)), int(pointer.get("address", -1)),
			scripts, text_data, movement_data
		)
	var metadata: Dictionary = phone.get("metadata", {})
	for field: String in ["out_of_area_script", "just_talk_script"]:
		var pointer: Dictionary = metadata.get(field, {})
		Gen2WorldImporter.collect_script(
			rom, int(pointer.get("bank", -1)), int(pointer.get("address", -1)),
			scripts, text_data, movement_data
		)
	return scripts.size() - before


static func _phone_condition_kind(condition: int, layout: Dictionary) -> StringName:
	if condition == int(layout.get("phone_condition_outside", -1)):
		return &"outside"
	if condition == int(layout.get("phone_condition_anywhere", -1)):
		return &"anywhere"
	return &"unknown"


static func _audio_address(raw_address: int) -> int:
	return 0x4000 | (raw_address & 0x3FFF)


static func _read_audio_assets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var wave_offset: int = int(layout["wave_samples"])
	var wave_bank: int = int(layout["wave_samples_bank"])
	var wave_address: int = int(layout["wave_samples_address"])
	if RomFile.linear(wave_bank, wave_address) != wave_offset \
		or not rom.in_bounds(wave_offset, RomLayout.AUDIO_WAVE_SAMPLE_COUNT * RomLayout.AUDIO_WAVE_SAMPLE_BYTES):
		return _error("Audio wave-sample table is outside the cartridge.")
	var wave: PackedByteArray = rom.slice(
		wave_offset, RomLayout.AUDIO_WAVE_SAMPLE_COUNT * RomLayout.AUDIO_WAVE_SAMPLE_BYTES
	)
	if wave[0] != 0x02 or wave[1] != 0x46 or wave[wave.size() - 2] != 0x43 \
		or wave[wave.size() - 1] != 0x21:
		return _error("Audio wave-sample table does not match the known cartridge data.")

	var drum_offset: int = int(layout["drumkits"])
	var drum_bank: int = int(layout["drumkits_bank"])
	var drum_address: int = int(layout["drumkits_address"])
	if RomFile.linear(drum_bank, drum_address) != drum_offset \
		or not rom.in_bounds(drum_offset, RomLayout.AUDIO_DRUMKIT_BYTES):
		return _error("Audio drum-kit data is outside the cartridge.")
	var drumkits: PackedByteArray = rom.slice(drum_offset, RomLayout.AUDIO_DRUMKIT_BYTES)
	if drumkits[0] != 0x5E or drumkits[1] != 0x4E or drumkits[drumkits.size() - 1] != 0xCB:
		return _error("Audio drum-kit data does not match the known cartridge data.")

	return {
		"ok": true,
		"wave_samples": {
			"bank": wave_bank,
			"address": wave_address,
			"offset": wave_offset,
			"sample_count": RomLayout.AUDIO_WAVE_SAMPLE_COUNT,
			"sample_bytes": RomLayout.AUDIO_WAVE_SAMPLE_BYTES,
			"bytes": Array(wave),
			"byte_count": wave.size(),
		},
		"drumkits": {
			"bank": drum_bank,
			"address": drum_address,
			"offset": drum_offset,
			"bytes": Array(drumkits),
			"byte_count": drumkits.size(),
		},
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
		var menu_reference: Dictionary = references[key]
		var bank: int = int(menu_reference["bank"])
		var address: int = int(menu_reference["address"])
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
			"uses": menu_reference.get("uses", []),
			"data": Array(raw),
		}
		var decoded: Dictionary = _decode_menu_data(raw)
		for decoded_key: String in decoded:
			row[decoded_key] = decoded[decoded_key]
		menus[key] = row
	return {"ok": true, "menus": menus}


static func _scan_menu_references(
	_rom: RomFile,
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
