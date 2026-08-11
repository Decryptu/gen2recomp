extends GutTest


func test_movement_decoder_keeps_directional_and_parameterized_commands() -> void:
	var decoded: Dictionary = Gen2WorldMovement.decode(
		PackedByteArray([0x00, 0x0D, 0x46, 5, 0x3D, 0x47])
	)
	assert_true(decoded["ok"])
	assert_eq(decoded["bytes"], 6)
	assert_eq(decoded["commands"].size(), 4)
	assert_eq(decoded["commands"][0]["kind"], &"turn_head")
	assert_eq(decoded["commands"][1]["kind"], &"step")
	assert_eq(decoded["commands"][1]["direction"], 1)
	assert_eq(decoded["commands"][2]["kind"], &"step_sleep")
	assert_eq(decoded["commands"][2]["length"], 5)
	assert_eq(decoded["commands"][3]["kind"], &"hide_object")


func test_movement_decoder_requires_a_terminator_and_parameter_bytes() -> void:
	var missing_end: Dictionary = Gen2WorldMovement.decode(PackedByteArray([0x00]))
	assert_false(missing_end["ok"])
	assert_eq(missing_end["reason"], &"movement_terminator_missing")

	var missing_parameter: Dictionary = Gen2WorldMovement.decode(PackedByteArray([0x48]))
	assert_false(missing_parameter["ok"])
	assert_eq(missing_parameter["reason"], &"truncated_movement_operands")


func test_movement_decoder_preserves_shake_and_rock_smash_parameters() -> void:
	var decoded: Dictionary = Gen2WorldMovement.decode(
		PackedByteArray([0x55, 16, 0x57, 0, 0x56, 0x47])
	)
	assert_true(decoded["ok"])
	assert_eq(decoded["commands"][0]["kind"], &"step_shake")
	assert_eq(decoded["commands"][0]["value"], 16)
	assert_eq(decoded["commands"][1]["kind"], &"rock_smash")
	assert_eq(decoded["commands"][2]["kind"], &"tree_shake")
