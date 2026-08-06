extends GutTest

## The service importer is a pure ROM-to-dictionary boundary. This fixture uses
## the real Gold layout and source record sizes, but writes only the bytes each
## table needs, so malformed pointers and terminators are still testable without
## depending on a commercial dump being present in a checkout.

var _layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)


func test_marts_phone_audio_and_referenced_menu_are_imported() -> void:
	var data := PackedByteArray()
	data.resize(0x200000)
	_write_marts(data)
	_write_phone(data)
	_write_audio(data)
	_write_menu(data)

	var scripts: Dictionary = {
		"5:7000": [
			Gen2WorldScript.LOADMENU, 0x00, 0x75, 0x58,
			Gen2WorldScript.LOADMENU, 0x00, 0x76, 0x57,
			Gen2WorldScript.END,
		],
	}
	var result: Dictionary = Gen2WorldServicesImporter.read_services(
		RomFile.from_bytes(data, RomRegistry.GOLD), _layout, scripts
	)

	assert_true(result["ok"], result.get("message", ""))
	var marts: Dictionary = result["marts"]
	assert_eq((marts["marts"] as Array).size(), RomLayout.MART_COUNT)
	assert_eq((marts["marts"][0]["items"] as Array), [0x12, 0x09])
	assert_eq((marts["default"]["items"] as Array), [0x05, 0x12])
	assert_eq((marts["special"]["bargain"] as Array)[0]["price"], 4500)

	var phone: Dictionary = result["phone"]
	assert_eq((phone["contacts"] as Array).size(), RomLayout.PHONE_CONTACT_COUNT)
	assert_eq(phone["contacts"][1]["map_group"], 1)
	assert_eq(phone["contacts"][1]["non_trainer_id"], 1)
	assert_eq(phone["contacts"][1]["caller_label"], "MOM")
	assert_eq(phone["non_trainer_names"][1]["name"], "MOM")
	assert_eq((phone["special_calls"] as Array).size(), RomLayout.SPECIAL_PHONE_CALL_COUNT)
	assert_eq(phone["special_calls"][0]["condition_kind"], &"outside")
	assert_eq(phone["special_calls"][1]["condition_kind"], &"anywhere")
	assert_eq(phone["metadata"]["max_contacts"], 10)
	assert_eq(phone["metadata"]["receive_call_delays"], [20, 10, 5, 3])
	assert_eq(phone["metadata"]["just_talk_script"], {
		"bank": int(_layout["phone_just_talk_bank"]),
		"address": int(_layout["phone_just_talk_address"]),
	})

	var audio: Dictionary = result["audio"]
	assert_eq((audio["music"] as Array).size(), int(_layout["music_count"]))
	assert_eq((audio["sfx"] as Array).size(), int(_layout["sfx_count"]))
	assert_eq(audio["music"][0]["bank"], int(_layout["music_first_bank"]))
	assert_eq(audio["sfx"][0]["address"], int(_layout["sfx_first_address"]))
	assert_eq((audio["cries"] as Array).size(), RomLayout.AUDIO_CRY_COUNT)
	assert_eq(audio["cries"][0]["address"], int(_layout["cry_first_address"]))
	assert_eq(audio["wave_samples"]["sample_count"], RomLayout.AUDIO_WAVE_SAMPLE_COUNT)
	assert_eq(audio["drumkits"]["byte_count"], RomLayout.AUDIO_DRUMKIT_BYTES)
	assert_gt(audio["music"][0]["byte_count"], 0)

	var menus: Dictionary = result["menus"]
	var menu: Dictionary = menus[Gen2WorldScript.pointer_key(5, 0x7500)]
	assert_eq(menu["uses"], ["vertical"])
	assert_eq(menu["options"], ["A", "B"])
	assert_eq(menu["kind"], "vertical")
	assert_eq(menu["wrap"], false)
	var menu_2d: Dictionary = menus[Gen2WorldScript.pointer_key(5, 0x7600)]
	assert_eq(menu_2d["uses"], ["2d"])
	assert_eq(menu_2d["kind"], "2d")
	assert_eq(menu_2d["rows"], 2)
	assert_eq(menu_2d["columns"], 2)
	assert_eq(menu_2d["spacing"], 6)
	assert_eq(menu_2d["options"], ["A", "B", "C", "D"])


func test_mart_terminator_is_required() -> void:
	var data := PackedByteArray()
	data.resize(0x200000)
	_write_marts(data)
	data[RomFile.linear(5, 0x7000) + 3] = 0x00
	var result: Dictionary = Gen2WorldServicesImporter.read_services(
		RomFile.from_bytes(data, RomRegistry.GOLD), _layout
	)
	assert_false(result["ok"])
	assert_true(String(result["message"]).contains("Mart 0"))


func _write_marts(data: PackedByteArray) -> void:
	var table: int = int(_layout["mart_table"])
	for index: int in RomLayout.MART_COUNT:
		var address: int = 0x7000 + index * 0x10
		_write_u16(data, table + index * 2, address)
		var offset: int = RomFile.linear(5, address)
		data[offset] = 2 if index == 0 else 1
		data[offset + 1] = 0x12 if index == 0 else index + 1
		if index == 0:
			data[offset + 2] = 0x09
			data[offset + 3] = 0xFF
		else:
			data[offset + 2] = 0xFF
	var default_offset: int = int(_layout["default_mart"])
	data[default_offset] = 2
	data[default_offset + 1] = 0x05
	data[default_offset + 2] = 0x12
	data[default_offset + 3] = 0xFF
	var bargain_offset: int = int(_layout["bargain_mart"])
	data[bargain_offset] = 1
	data[bargain_offset + 1] = 0x24
	_write_u16(data, bargain_offset + 2, 4500)
	data[bargain_offset + 4] = 0xFF


func _write_phone(data: PackedByteArray) -> void:
	var name_table: int = int(_layout["phone_non_trainer_names"])
	var name_bank: int = int(_layout["phone_non_trainer_names_bank"])
	var names: Array[String] = ["NONE", "MOM", "BIKE", "BILL", "ELM"]
	for index: int in names.size():
		var address: int = 0x7600 + index * 0x10
		_write_u16(
			data,
			name_table + index * RomLayout.PHONE_NON_TRAINER_NAME_POINTER_SIZE,
			address
		)
		var encoded: PackedByteArray = Gen2Text.encode(names[index])
		encoded.append(Gen2Text.TERMINATOR)
		var name_offset: int = RomFile.linear(name_bank, address)
		for byte_index: int in encoded.size():
			data[name_offset + byte_index] = encoded[byte_index]
	var table: int = int(_layout["phone_contacts"])
	for index: int in RomLayout.PHONE_CONTACT_COUNT:
		var at: int = table + index * RomLayout.PHONE_CONTACT_SIZE
		data[at] = 0
		data[at + 1] = index
		data[at + 2] = 1 if index == 1 else 0
		data[at + 3] = 1 if index == 1 else 0
		data[at + 4] = 0
		_write_far(data, at + 5, 5, 0x7400)
		data[at + 8] = 0
		_write_far(data, at + 9, 5, 0x7400)
	var special: int = int(_layout["special_phone_calls"])
	for index: int in RomLayout.SPECIAL_PHONE_CALL_COUNT:
		var at: int = special + index * RomLayout.SPECIAL_PHONE_CALL_SIZE
		var condition: int = 0x4000
		if index == 0:
			condition = int(_layout["phone_condition_outside"])
		elif index == 1:
			condition = int(_layout["phone_condition_anywhere"])
		_write_u16(data, at, condition)
		data[at + 2] = 4
		_write_far(data, at + 3, 5, 0x7400)


func _write_audio(data: PackedByteArray) -> void:
	var wave_offset: int = int(_layout["wave_samples"])
	data[wave_offset] = 0x02
	data[wave_offset + 1] = 0x46
	data[wave_offset + RomLayout.AUDIO_WAVE_SAMPLE_COUNT * RomLayout.AUDIO_WAVE_SAMPLE_BYTES - 2] = 0x43
	data[wave_offset + RomLayout.AUDIO_WAVE_SAMPLE_COUNT * RomLayout.AUDIO_WAVE_SAMPLE_BYTES - 1] = 0x21
	var drum_offset: int = int(_layout["drumkits"])
	data[drum_offset] = 0x5E
	data[drum_offset + 1] = 0x4E
	data[drum_offset + RomLayout.AUDIO_DRUMKIT_BYTES - 1] = 0xCB
	var music_table: int = int(_layout["music_pointers"])
	for index: int in int(_layout["music_count"]):
		var address: int = int(_layout["music_first_address"]) + index
		_write_far(data, music_table + index * 3, int(_layout["music_first_bank"]), address)
		data[RomFile.linear(int(_layout["music_first_bank"]), address)] = 0xFF
	var sfx_table: int = int(_layout["sfx_pointers"])
	for index: int in int(_layout["sfx_count"]):
		var address: int = int(_layout["sfx_first_address"]) + index
		_write_far(data, sfx_table + index * 3, int(_layout["sfx_first_bank"]), address)
		data[RomFile.linear(int(_layout["sfx_first_bank"]), address)] = 0xFF
	var cry_table: int = int(_layout["cry_pointers"])
	for index: int in RomLayout.AUDIO_CRY_COUNT:
		var address: int = int(_layout["cry_first_address"]) + index
		_write_far(data, cry_table + index * 3, int(_layout["cry_first_bank"]), address)
		data[RomFile.linear(int(_layout["cry_first_bank"]), address)] = 0xFF


func _write_menu(data: PackedByteArray) -> void:
	var header: int = RomFile.linear(5, 0x7500)
	data[header] = 0x40
	data[header + 1] = 0
	data[header + 2] = 0
	data[header + 3] = 8
	data[header + 4] = 7
	_write_u16(data, header + 5, 0x7510)
	data[header + 7] = 1
	var menu_data: int = RomFile.linear(5, 0x7510)
	data[menu_data] = 0x80
	data[menu_data + 1] = 2
	data[menu_data + 2] = 0x80
	data[menu_data + 3] = 0x50
	data[menu_data + 4] = 0x81
	data[menu_data + 5] = 0x50
	var header_2d: int = RomFile.linear(5, 0x7600)
	data[header_2d] = 0x40
	data[header_2d + 1] = 1
	data[header_2d + 2] = 2
	data[header_2d + 3] = 9
	data[header_2d + 4] = 10
	_write_u16(data, header_2d + 5, 0x7610)
	data[header_2d + 7] = 1
	var menu_2d: int = RomFile.linear(5, 0x7610)
	data[menu_2d] = 0x20
	data[menu_2d + 1] = 0x22
	data[menu_2d + 2] = 6
	data[menu_2d + 3] = 5
	data[menu_2d + 4] = 0x30
	data[menu_2d + 5] = 0x76
	data[menu_2d + 6] = 5
	data[menu_2d + 7] = 0
	data[menu_2d + 8] = 0
	var strings: int = RomFile.linear(5, 0x7630)
	var encoded: PackedByteArray = PackedByteArray()
	for value: String in ["A", "B", "C", "D"]:
		encoded.append_array(Gen2Text.encode(value))
		encoded.append(Gen2Text.TERMINATOR)
	for index: int in encoded.size():
		data[strings + index] = encoded[index]


func _write_far(data: PackedByteArray, offset: int, bank: int, address: int) -> void:
	data[offset] = bank
	_write_u16(data, offset + 1, address)


func _write_u16(data: PackedByteArray, offset: int, value: int) -> void:
	data[offset] = value & 0xFF
	data[offset + 1] = (value >> 8) & 0xFF
