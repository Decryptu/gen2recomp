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


func test_text_decoder_skips_tx_start_and_requires_the_terminator() -> void:
	var decoded: Dictionary = Gen2WorldScript.decode_text(
		PackedByteArray([0x00, 0x80, 0x81, 0x50, 0x80])
	)
	assert_true(decoded["ok"])
	assert_eq(decoded["text"], "AB")
	assert_eq(decoded["bytes"], 4)

	var missing: Dictionary = Gen2WorldScript.decode_text(PackedByteArray([0x00, 0x80]))
	assert_false(missing["ok"])
	assert_eq(missing["reason"], &"missing_text_terminator")
