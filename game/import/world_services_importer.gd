class_name Gen2WorldServicesImporter
extends RefCounted

## Imports the global services used by overworld scripts. These records are
## cartridge data, not runtime policy: the importer keeps the source pointers,
## bounded raw payloads and the fields the script interpreter needs to resolve
## a request without opening a ROM later.

const MAX_MENU_DATA_BYTES: int = 256
const MAX_MENU_ITEMS: int = 32
const MAX_MENU_STRING_BYTES: int = 64
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
	if not RomCache.write_json(
		RomCache.world_fruit_trees_path(directory), result["fruit_trees"]
	):
		return _error("Could not write world fruit tree data.")
	if not RomCache.write_json(RomCache.world_spawns_path(directory), result["spawns"]):
		return _error("Could not write world spawn data.")
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
		"mon_cries": (result["audio"].get("mon_cries", []) as Array).size(),
		"fruit_trees": (result["fruit_trees"] as Array).size(),
		"spawns": ((result["spawns"] as Dictionary)["spawns"] as Array).size(),
		"flypoints": ((result["spawns"] as Dictionary)["flypoints"] as Array).size(),
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
	var fruit_trees: Dictionary = read_fruit_trees(rom, layout)
	if not bool(fruit_trees.get("ok", false)):
		return fruit_trees
	var spawns: Dictionary = read_spawns(rom, layout)
	if not bool(spawns.get("ok", false)):
		return spawns
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
		"fruit_trees": fruit_trees["items"],
		"spawns": spawns["data"],
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


## `FruitTreeItems` (`data/items/fruit_trees.asm`): thirty item bytes, one per
## `FRUITTREE_*` constant, read by `GetFruitTreeItem` at the tree id less one.
## No terminator and no pointer, so the count is the whole of its shape and the
## table has to identify itself by content instead.
static func read_fruit_trees(rom: RomFile, layout: Dictionary) -> Dictionary:
	var offset: int = int(layout.get("fruit_trees", 0))
	if offset <= 0 or not rom.in_bounds(offset, RomLayout.FRUIT_TREE_COUNT):
		return _error("Fruit tree item table is outside the cartridge.")
	var items: Array = []
	for index: int in RomLayout.FRUIT_TREE_COUNT:
		var item: int = rom.u8(offset + index)
		if item <= 0 or item == RomLayout.MART_TERMINATOR:
			return _error("Fruit tree %d holds invalid item %d." % [index + 1, item])
		items.append(item)
	## Rows 17 to 23 are the seven apricorns and are the only apricorns in the
	## table, and the four Johto berry trees ahead of them all bear the same
	## fruit. Either alone could match neighbouring data; together they do not.
	var apricorns: Array = items.slice(
		RomLayout.FRUIT_TREE_FIRST_APRICORN, RomLayout.FRUIT_TREE_FIRST_APRICORN + 7
	)
	apricorns.sort()
	if apricorns != RomLayout.FRUIT_TREE_APRICORNS:
		return _error("Fruit tree rows 17 to 23 are not the seven apricorns.")
	for index: int in RomLayout.FRUIT_TREE_COUNT:
		var is_apricorn: bool = RomLayout.FRUIT_TREE_APRICORNS.has(int(items[index]))
		var in_run: bool = index >= RomLayout.FRUIT_TREE_FIRST_APRICORN \
			and index < RomLayout.FRUIT_TREE_FIRST_APRICORN + 7
		if is_apricorn != in_run:
			return _error("Fruit tree %d breaks the apricorn run." % (index + 1))
	if items.slice(0, 4).any(func(item: Variant) -> bool: return int(item) != int(items[0])):
		return _error("The first four fruit trees do not share one berry.")
	return {"ok": true, "items": items}


## `SpawnPoints` and `Flypoints`, the two tables every escape from a map reads:
## a spawn is `db group, number, x, y` and a flypoint is `db landmark, spawn`.
##
## Each identifies itself by the column that is the same on all three dumps, the
## spawn coordinates and the flypoint spawn indexes, and each is checked to its
## own terminator, so a shifted table fails rather than decoding its neighbour.
static func read_spawns(rom: RomFile, layout: Dictionary) -> Dictionary:
	var spawn_offset: int = int(layout.get("spawn_points", 0))
	var span: int = (RomLayout.SPAWN_COUNT + 1) * RomLayout.SPAWN_RECORD_SIZE
	if spawn_offset <= 0 or not rom.in_bounds(spawn_offset, span):
		return _error("Spawn point table is outside the cartridge.")
	var spawns: Array = []
	for index: int in RomLayout.SPAWN_COUNT:
		var at: int = spawn_offset + index * RomLayout.SPAWN_RECORD_SIZE
		var x: int = rom.u8(at + 2)
		var y: int = rom.u8(at + 3)
		if x != int(RomLayout.SPAWN_COORDINATES[index * 2]) \
				or y != int(RomLayout.SPAWN_COORDINATES[index * 2 + 1]):
			return _error("Spawn %d is not at the coordinates the table pins." % index)
		spawns.append({
			"map_group": rom.u8(at), "map_number": rom.u8(at + 1), "x": x, "y": y,
		})
	for byte: int in RomLayout.SPAWN_RECORD_SIZE:
		if rom.u8(spawn_offset + RomLayout.SPAWN_COUNT * RomLayout.SPAWN_RECORD_SIZE + byte) \
				!= RomLayout.SPAWN_TERMINATOR:
			return _error("The spawn point table does not end where it should.")

	var fly_offset: int = int(layout.get("flypoints", 0))
	var fly_span: int = RomLayout.FLYPOINT_COUNT * RomLayout.FLYPOINT_RECORD_SIZE + 1
	if fly_offset <= 0 or not rom.in_bounds(fly_offset, fly_span):
		return _error("Flypoint table is outside the cartridge.")
	var flypoints: Array = []
	for index: int in RomLayout.FLYPOINT_COUNT:
		var at: int = fly_offset + index * RomLayout.FLYPOINT_RECORD_SIZE
		var spawn: int = rom.u8(at + 1)
		if spawn != int(RomLayout.FLYPOINT_SPAWNS[index]):
			return _error("Flypoint %d does not name the spawn the table pins." % index)
		flypoints.append({"landmark": rom.u8(at), "spawn": spawn})
	if rom.u8(fly_offset + RomLayout.FLYPOINT_COUNT * RomLayout.FLYPOINT_RECORD_SIZE) \
			!= RomLayout.FLYPOINT_TERMINATOR:
		return _error("The flypoint table does not end where it should.")
	return {"ok": true, "data": {"spawns": spawns, "flypoints": flypoints}}


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
	var names_result: Dictionary = _read_phone_non_trainer_names(rom, layout)
	if not bool(names_result.get("ok", false)):
		return names_result
	var non_trainer_names: Array = names_result.get("names", [])
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
		var trainer_class: int = rom.u8(at)
		var trainer_number: int = rom.u8(at + 1)
		var caller_label: String = ""
		if trainer_class == 0 and trainer_number >= 0 and trainer_number < non_trainer_names.size():
			caller_label = String((non_trainer_names[trainer_number] as Dictionary).get("name", ""))
		contacts.append({
			"index": index,
			"trainer_class": trainer_class,
			"trainer_number": trainer_number,
			"non_trainer_id": trainer_number if trainer_class == 0 else -1,
			"caller_label": caller_label,
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
			"non_trainer_names": non_trainer_names,
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
	var mon_cries: Dictionary = _read_mon_cries(rom, layout)
	if not bool(mon_cries.get("ok", false)):
		return mon_cries

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
			"mon_cries": mon_cries["rows"],
			"wave_samples": assets["wave_samples"],
			"drumkits": assets["drumkits"],
		},
	}


## `PokemonCries`: the cry a species asks for and the pitch offset and length it
## asks for it at. Pinned by value, since the shape alone does not locate it.
static func _read_mon_cries(rom: RomFile, layout: Dictionary) -> Dictionary:
	var table: int = int(layout.get("mon_cries", -1))
	var span: int = RomLayout.MON_CRY_COUNT * RomLayout.MON_CRY_ROW_SIZE
	if table < 0 or not rom.in_bounds(table, span):
		return _error("Pokemon cry table is outside the cartridge.")
	var rows: Array = []
	for species: int in RomLayout.MON_CRY_COUNT:
		var at: int = table + species * RomLayout.MON_CRY_ROW_SIZE
		var row: Dictionary = {
			"index": rom.u16le(at),
			"pitch": rom.u16le(at + 2),
			"length": rom.u16le(at + 4),
		}
		if int(row["index"]) >= RomLayout.AUDIO_CRY_COUNT:
			return _error("Pokemon cry row %d names cry %d." % [species + 1, int(row["index"])])
		rows.append(row)
	for number: Variant in RomLayout.MON_CRY_PINS:
		var pin: Array = RomLayout.MON_CRY_PINS[number]
		var found: Dictionary = rows[int(number) - 1]
		if int(found["index"]) != int(pin[0]) or int(found["pitch"]) != int(pin[1]) \
				or int(found["length"]) != int(pin[2]):
			return _error("Pokemon cry row %d does not match the pinned values." % int(number))
	return {"ok": true, "rows": rows}


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


static func _read_phone_non_trainer_names(rom: RomFile, layout: Dictionary) -> Dictionary:
	var table: int = int(layout.get("phone_non_trainer_names", -1))
	var bank: int = int(layout.get("phone_non_trainer_names_bank", -1))
	var count: int = int(layout.get("phone_non_trainer_name_count", -1))
	if table < 0 or bank < 0 or count <= 0:
		return _error("Phone non-trainer caller-name layout is incomplete.")
	if not rom.in_bounds(table, count * RomLayout.PHONE_NON_TRAINER_NAME_POINTER_SIZE):
		return _error("Phone non-trainer caller-name pointers are outside the cartridge.")
	var names: Array = []
	for index: int in count:
		var address: int = rom.u16le(
			table + index * RomLayout.PHONE_NON_TRAINER_NAME_POINTER_SIZE
		)
		if not _valid_cpu_address(address):
			return _error("Phone non-trainer caller name %d has an invalid pointer." % index)
		var offset: int = RomFile.linear(bank, address)
		if not rom.in_bounds(offset):
			return _error("Phone non-trainer caller name %d is outside the cartridge." % index)
		var end: int = offset
		while end < rom.size() and end - offset < RomLayout.MAX_NAME_LENGTH + 16:
			if rom.u8(end) == Gen2Text.TERMINATOR:
				break
			end += 1
		if end >= rom.size() or end - offset >= RomLayout.MAX_NAME_LENGTH + 16:
			return _error("Phone non-trainer caller name %d has no terminator." % index)
		var raw: PackedByteArray = rom.slice(offset, end - offset + 1)
		names.append({
			"index": index,
			"bank": bank,
			"address": address,
			"name": Gen2Text.decode(raw, 0, raw.size()),
		})
	return {"ok": true, "names": names}


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
		var decoded: Dictionary = _decode_menu_data(
			rom, bank, data_address, raw, menu_reference.get("uses", [])
		)
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


static func _decode_menu_data(
	rom: RomFile, data_bank: int, data_address: int, raw: PackedByteArray, uses: Variant
) -> Dictionary:
	if raw.size() < 2:
		return {}
	var menu_uses: Array = uses if uses is Array else []
	if menu_uses.has("2d"):
		return _decode_2d_menu_data(rom, data_bank, data_address, raw)
	return _decode_vertical_menu_data(raw)


static func _decode_vertical_menu_data(raw: PackedByteArray) -> Dictionary:
	var flags: int = raw[0]
	var count: int = raw[1]
	var out: Dictionary = {
		"data_flags": flags,
		"kind": "vertical",
		"items": count,
		"wrap": (flags & (1 << 5)) != 0,
		"cursor": (flags & (1 << 7)) != 0,
		"disable_b": (flags & 1) != 0,
		"enable_select": (flags & (1 << 1)) != 0,
	}
	if count > MAX_MENU_ITEMS:
		out["decode_error"] = "vertical menu has too many items"
		return out
	var strings: Dictionary = _read_inline_menu_strings(raw, 2, count)
	if not bool(strings.get("ok", false)):
		out["decode_error"] = strings.get("reason", "invalid vertical menu strings")
		return out
	out["options"] = strings["strings"]
	var at: int = int(strings["next_offset"])
	if (flags & (1 << 4)) != 0 and at < raw.size():
		var title_offset: int = raw[at]
		var title: Dictionary = _read_inline_menu_string(raw, at + 1, title_offset)
		if bool(title.get("ok", false)):
			out["title_offset"] = title_offset
			out["title"] = title["text"]
	return out


static func _decode_2d_menu_data(
	rom: RomFile, data_bank: int, data_address: int, raw: PackedByteArray
) -> Dictionary:
	var flags: int = raw[0]
	var dimensions: int = raw[1]
	var rows: int = (dimensions >> 4) & 0x0F
	var columns: int = dimensions & 0x0F
	var out: Dictionary = {
		"data_flags": flags,
		"kind": "2d",
		"dimensions": dimensions,
		"rows": rows,
		"columns": columns,
		"spacing": raw[2] if raw.size() > 2 else 0,
		"wrap": (flags & (1 << 5)) != 0,
		"cursor": (flags & (1 << 7)) != 0,
		"disable_b": (flags & 1) != 0,
		"enable_select": (flags & (1 << 1)) != 0,
	}
	if rows <= 0 or columns <= 0 or rows * columns > MAX_MENU_ITEMS:
		out["decode_error"] = "2D menu dimensions are invalid"
		return out
	var data_offset: int = RomFile.linear(data_bank, data_address)
	if not rom.in_bounds(data_offset, 9):
		out["decode_error"] = "2D menu data is truncated"
		return out
	var strings_pointer: Dictionary = rom.far_pointer(data_offset + 3)
	if not _valid_menu_pointer(strings_pointer):
		out["decode_error"] = "2D menu strings pointer is invalid"
		return out
	var strings: Dictionary = _read_menu_strings(
		rom, strings_pointer, rows * columns
	)
	if not bool(strings.get("ok", false)):
		out["decode_error"] = strings.get("reason", "2D menu strings are invalid")
		return out
	out["options"] = strings["strings"]
	out["strings_pointer"] = strings_pointer
	var function_pointer: Dictionary = rom.far_pointer(data_offset + 6)
	if function_pointer.get("address", 0) != 0:
		out["function_pointer"] = function_pointer
	return out


static func _read_inline_menu_strings(
	raw: PackedByteArray, offset: int, count: int
) -> Dictionary:
	var strings: Array = []
	var at: int = offset
	for _index: int in count:
		var string: Dictionary = _read_inline_menu_string(raw, at, MAX_MENU_STRING_BYTES)
		if not bool(string.get("ok", false)):
			return string
		strings.append(string["text"])
		at = int(string["next_offset"])
	return {"ok": true, "strings": strings, "next_offset": at}


static func _read_inline_menu_string(
	raw: PackedByteArray, offset: int, max_length: int
) -> Dictionary:
	if offset < 0 or offset >= raw.size():
		return {"ok": false, "reason": "menu string is outside the data"}
	var end: int = offset
	while end < raw.size() and end - offset < max_length:
		if raw[end] == Gen2Text.TERMINATOR:
			return {
				"ok": true,
				"text": Gen2Text.decode(raw, offset, end - offset),
				"next_offset": end + 1,
			}
		end += 1
	return {"ok": false, "reason": "menu string has no terminator"}


static func _read_menu_strings(
	rom: RomFile, pointer: Dictionary, count: int
) -> Dictionary:
	var strings: Array = []
	var address: int = int(pointer.get("address", -1))
	var bank: int = int(pointer.get("bank", -1))
	if not _valid_menu_pointer(pointer):
		return {"ok": false, "reason": "menu strings pointer is invalid"}
	var at: int = RomFile.linear(bank, address)
	for _index: int in count:
		if not rom.in_bounds(at):
			return {"ok": false, "reason": "menu strings run off the cartridge"}
		var end: int = at
		var terminated: bool = false
		while rom.in_bounds(end) and end - at < MAX_MENU_STRING_BYTES:
			if rom.u8(end) == Gen2Text.TERMINATOR:
				strings.append(Gen2Text.decode(rom.bytes(), at, end - at))
				at = end + 1
				terminated = true
				break
			end += 1
		if not terminated:
			return {"ok": false, "reason": "menu strings have an invalid terminator"}
	return {"ok": true, "strings": strings}


static func _valid_menu_pointer(pointer: Dictionary) -> bool:
	var bank: int = int(pointer.get("bank", -1))
	var address: int = int(pointer.get("address", -1))
	return bank >= 0 and address >= RomFile.BANK_SIZE and address < RomFile.BANK_SIZE * 2


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
