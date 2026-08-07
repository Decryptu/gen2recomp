extends GutTest

## The script layer is tested as a byte protocol. These tests deliberately use
## the command widths from the cartridge macros, not a scene or a mock node.


func test_command_parser_reads_near_and_warp_operands() -> void:
	var near: Dictionary = Gen2WorldScript.command_at(PackedByteArray([0x4C, 0x34, 0x12]), 0)
	assert_true(near["ok"])
	assert_eq(near["name"], &"writetext")
	assert_eq(near["address"], 0x1234)

	var warp: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x3C, 2, 3, 9, 10]), 0
	)
	assert_true(warp["ok"])
	assert_eq(warp["map_group"], 2)
	assert_eq(warp["map_number"], 3)
	assert_eq(warp["x"], 9)
	assert_eq(warp["y"], 10)


func test_command_parser_reads_profile_specific_object_commands() -> void:
	var crystal: Dictionary = Gen2WorldScript.command_at(PackedByteArray([0x6E, 2]), 0, true)
	assert_true(crystal["ok"])
	assert_eq(crystal["name"], &"disappear")
	assert_eq(crystal["width"], 2)
	assert_eq(crystal["object_id"], 2)

	var gold: Dictionary = Gen2WorldScript.command_at(PackedByteArray([0x6D, 2]), 0, false)
	assert_true(gold["ok"])
	assert_eq(gold["name"], &"disappear")
	assert_eq(gold["object_id"], 2)

	var gold_coins: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x3E, 4]), 0, false
	)
	assert_true(gold_coins["ok"])
	assert_eq(gold_coins["width"], 2)
	assert_eq(gold_coins["string_buffer"], 4)

	var crystal_coins: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x3E, 4, 5]), 0, true
	)
	assert_true(crystal_coins["ok"])
	assert_eq(crystal_coins["width"], 3)
	assert_eq(crystal_coins["string_buffer_2"], 5)


func test_crystal_trainer_and_tutorial_commands_use_the_pinned_layout() -> void:
	var load_temp: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x5C]), 0, true
	)
	assert_true(load_temp["ok"])
	assert_eq(load_temp["name"], &"loadtemptrainer")
	assert_eq(load_temp["width"], 1)

	var load_wild: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x5D, 16, 5]), 0, true
	)
	assert_true(load_wild["ok"])
	assert_eq(load_wild["name"], &"loadwildmon")
	assert_eq(load_wild["pokemon"], 16)
	assert_eq(load_wild["level"], 5)

	var tutorial: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x61, 3]), 0, true
	)
	assert_true(tutorial["ok"])
	assert_eq(tutorial["name"], &"catchtutorial")
	assert_eq(tutorial["value"], 3)


func test_raw_opcode_shifts_only_at_and_above_the_farjumptext_insertion() -> void:
	# Below the shift boundary both profiles agree on the raw byte.
	assert_eq(Gen2WorldScript.raw_opcode(0x51, false), 0x51)
	assert_eq(Gen2WorldScript.raw_opcode(0x51, true), 0x51)
	# At and above $52, Crystal's raw byte is one higher than the Gold/Silver
	# source opcode because farjumptext was inserted at raw $52.
	assert_eq(Gen2WorldScript.raw_opcode(0x52, false), 0x52)
	assert_eq(Gen2WorldScript.raw_opcode(0x52, true), 0x53)
	assert_eq(Gen2WorldScript.raw_opcode(0x53, true), 0x54) # gold waitbutton
	assert_eq(Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_LOADTEMPTRAINER, false), 0x5B)
	assert_eq(Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_LOADTEMPTRAINER, true), 0x5C)
	assert_eq(Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_STARTBATTLE, true), 0x5F)
	assert_eq(Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_RELOADMAPAFTERBATTLE, true), 0x60)
	assert_eq(Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_TRAINERFLAGACTION, true), 0x63)
	assert_eq(Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_ENCOUNTERMUSIC, true), 0x80)
	assert_eq(Gen2WorldScript.raw_opcode(Gen2WorldScript.GOLD_END, true), 0x91)


func test_special_index_normalizes_gold_silver_onto_the_crystal_table() -> void:
	# SpecialsPointers agrees for 0-46, so Crystal is the identity everywhere and
	# Gold/Silver is the identity below the BattleTowerFade insertion at 47.
	for crystal_index: int in [27, 37, 62, 78, 106, 166, 168]:
		assert_eq(Gen2WorldScript.special_index(crystal_index, true), crystal_index)
	assert_eq(Gen2WorldScript.special_index(0, false), 0)
	assert_eq(Gen2WorldScript.special_index(46, false), 46)

	# 47-107 sit one lower on Gold/Silver: FadeOutToBlack, RestartMapMusic,
	# HealMachineAnim, ToggleDecorationsVisibility, CheckPokerus, FadeOutMusic.
	assert_eq(Gen2WorldScript.special_index(47, false), 48)
	assert_eq(Gen2WorldScript.special_index(60, false), 61)
	assert_eq(Gen2WorldScript.special_index(61, false), 62)
	assert_eq(Gen2WorldScript.special_index(73, false), 74)
	assert_eq(Gen2WorldScript.special_index(77, false), 78)
	assert_eq(Gen2WorldScript.special_index(105, false), 106)
	assert_eq(Gen2WorldScript.special_index(107, false), 108)

	# Crystal's mobile block at 109-165 pushes the last three entries past it.
	assert_eq(Gen2WorldScript.special_index(108, false), 166) # InitialSetDSTFlag
	assert_eq(Gen2WorldScript.special_index(109, false), 167) # InitialClearDSTFlag
	assert_eq(Gen2WorldScript.special_index(111, false), 168) # UnusedDummySpecial

	# Gold/Silver 110 is MrChrono, which Crystal has no entry for at all.
	assert_eq(Gen2WorldScript.special_index(110, false), -1)


func test_raw_opcode_round_trips_the_trainer_intro_commands_through_command_at() -> void:
	# Each trainer-intro command name should decode identically whether it is
	# reached through the Gold/Silver raw byte or the shifted Crystal raw byte.
	var intro_commands: Array = [
		[Gen2WorldScript.GOLD_LOADTEMPTRAINER, &"loadtemptrainer"],
		[Gen2WorldScript.GOLD_ENCOUNTERMUSIC, &"encountermusic"],
		[0x53, &"waitbutton"],
		[Gen2WorldScript.GOLD_STARTBATTLE, &"startbattle"],
		[Gen2WorldScript.GOLD_RELOADMAPAFTERBATTLE, &"reloadmapafterbattle"],
		[Gen2WorldScript.GOLD_TRAINERFLAGACTION, &"trainerflagaction"],
		[Gen2WorldScript.GOLD_END, &"end"],
	]
	for entry: Array in intro_commands:
		var source_opcode: int = entry[0]
		var expected_name: StringName = entry[1]
		for crystal_commands: bool in [false, true]:
			var raw: int = Gen2WorldScript.raw_opcode(source_opcode, crystal_commands)
			var operand_count: int = Gen2WorldScript.command_width(raw, crystal_commands) - 1
			var bytes: PackedByteArray = PackedByteArray([raw])
			bytes.resize(1 + maxi(operand_count, 0))
			var decoded: Dictionary = Gen2WorldScript.command_at(bytes, 0, crystal_commands)
			assert_true(
				decoded["ok"],
				"%s should decode under crystal_commands=%s" % [expected_name, crystal_commands]
			)
			assert_eq(decoded["name"], expected_name)


func test_unknown_and_truncated_commands_are_structured_failures() -> void:
	var unknown: Dictionary = Gen2WorldScript.command_at(PackedByteArray([0xFE]), 0)
	assert_false(unknown["ok"])
	assert_eq(unknown["reason"], &"unsupported_command")

	var truncated: Dictionary = Gen2WorldScript.command_at(PackedByteArray([0x4C, 0x00]), 0)
	assert_false(truncated["ok"])
	assert_eq(truncated["reason"], &"truncated_operands")

	var gold_jump: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x52, 0x34, 0x12]), 0, false
	)
	assert_true(gold_jump["ok"])
	assert_eq(gold_jump["name"], &"jumptext")
	assert_eq(gold_jump["address"], 0x1234)
	var gold_wait: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x53]), 0, false
	)
	assert_true(gold_wait["ok"])
	assert_eq(gold_wait["name"], &"waitbutton")


func test_reference_scan_finds_scripts_and_text_without_following_unknown_bytes() -> void:
	var data := PackedByteArray([
		0x00, 0x34, 0x12,
		0x4C, 0x78, 0x56,
		0xFE,
	])
	var references: Dictionary = Gen2WorldScript.scan_references(data, 48, 0x6000)
	assert_eq(references["scripts"][0]["address"], 0x1234)
	assert_eq(references["texts"][0]["address"], 0x5678)
	assert_eq(references["scripts"].size(), 1)
	assert_eq(references["texts"].size(), 1)


func test_phonecall_scans_its_caller_name_pointer_as_text() -> void:
	var references: Dictionary = Gen2WorldScript.scan_references(
		PackedByteArray([0x98, 0x34, 0x12, 0x91]), 48, 0x6000, true
	)
	assert_eq(references["scripts"].size(), 0)
	assert_eq(references["texts"], [{"bank": 48, "address": 0x1234}])


func test_memcall_operands_are_runtime_addresses_not_static_script_references() -> void:
	var memcall: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([Gen2WorldScript.MEMCALL, 0x00, 0xD0]), 0
	)
	assert_true(memcall["ok"])
	assert_eq(memcall["address"], 0xD000)
	var memcallasm: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([Gen2WorldScript.MEMCALLASM, 0x00, 0xD0]), 0
	)
	assert_true(memcallasm["ok"])
	assert_eq(memcallasm["address"], 0xD000)
	var references: Dictionary = Gen2WorldScript.scan_references(
		PackedByteArray([Gen2WorldScript.MEMCALL, 0x00, 0xD0, Gen2WorldScript.END]),
		48, 0x6000
	)
	assert_eq(references["scripts"].size(), 0)


func test_text_decoder_skips_text_start_and_stops_at_source_done() -> void:
	var decoded: Dictionary = Gen2WorldScript.decode_text(
		PackedByteArray([0x00, 0x80, Gen2WorldScript.TEXT_PAGE, 0x81, 0x57, 0x80])
	)
	assert_true(decoded["ok"])
	assert_eq(decoded["text"], "A\n\nB")
	assert_eq(decoded["bytes"], 5)

	var missing: Dictionary = Gen2WorldScript.decode_text(PackedByteArray([0x00, 0x80]))
	assert_false(missing["ok"])
	assert_eq(missing["reason"], &"missing_text_terminator")


func test_command_parser_keeps_side_effect_operands_in_their_source_widths() -> void:
	var money: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x22, 1, 0x00, 0x12, 0x34]), 0
	)
	assert_true(money["ok"])
	assert_eq(money["width"], 5)
	assert_eq(money["account"], 1)
	assert_eq(money["amount_bytes"], PackedByteArray([0x00, 0x12, 0x34]))

	var trainer_name: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x43, 2, 7, 4]), 0
	)
	assert_true(trainer_name["ok"])
	assert_eq(trainer_name["width"], 4)
	assert_eq(trainer_name["trainer_group"], 2)
	assert_eq(trainer_name["trainer_id"], 7)
	assert_eq(trainer_name["string_buffer"], 4)

	var givepoke: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x2D, 25, 5, 0, 0]), 0
	)
	assert_true(givepoke["ok"])
	assert_eq(givepoke["width"], 5)
	assert_eq(givepoke["pokemon"], 25)

	var trained_givepoke: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x2D, 25, 5, 0, 1, 0x34, 0x12, 0x78, 0x56]), 0
	)
	assert_true(trained_givepoke["ok"])
	assert_eq(trained_givepoke["width"], 9)
	assert_eq(trained_givepoke["nickname_address"], 0x1234)
	assert_eq(trained_givepoke["ot_name_address"], 0x5678)


func test_reference_scan_collects_movement_pointers() -> void:
	var references: Dictionary = Gen2WorldScript.scan_references(
		PackedByteArray([0x68, 2, 0x34, 0x12, 0x47]), 48, 0x6000, false
	)
	assert_eq(references["movements"].size(), 1)
	assert_eq(references["movements"][0]["address"], 0x1234)


func test_command_parser_reads_scripted_overworld_feature_operands() -> void:
	var emote: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x75, 2, 3, 4]), 0, true
	)
	assert_true(emote["ok"])
	assert_eq(emote["name"], &"showemote")
	assert_eq(emote["value"], 2)
	assert_eq(emote["object_id"], 3)
	assert_eq(emote["value_2"], 4)

	var block: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x7A, 1, 2, 3]), 0, true
	)
	assert_true(block["ok"])
	assert_eq(block["name"], &"changeblock")
	assert_eq(block["x"], 1)
	assert_eq(block["y"], 2)
	assert_eq(block["block"], 3)

	var reload: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x7B]), 0, true
	)
	assert_true(reload["ok"])
	assert_eq(reload["name"], &"reloadmap")
	assert_eq(reload["width"], 1)

	var write_queue: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x7D, 0x34, 0x12]), 0, true
	)
	assert_true(write_queue["ok"])
	assert_eq(write_queue["name"], &"writecmdqueue")
	assert_eq(write_queue["address"], 0x1234)

	var delete_queue: Dictionary = Gen2WorldScript.command_at(
		PackedByteArray([0x7E, 2]), 0, true
	)
	assert_true(delete_queue["ok"])
	assert_eq(delete_queue["name"], &"delcmdqueue")
	assert_eq(delete_queue["value"], 2)
