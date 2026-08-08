extends GutTest

## ForgetMove's table and list against a synthetic cache built for this file.
##
## The load-bearing part is the HM list: it is seven moves, not the four
## [constant Gen2WorldFieldMove.FIELD_MOVES] this project acts on in the
## overworld, and getting that wrong would let a player forget Fly or Flash.

## home/hm_moves.asm's IsHMMove.HMMoves with the names
## constants/move_constants.asm gives them, in source order.
const HM_MOVES: Dictionary = {
	0x0F: "CUT",
	0x13: "FLY",
	0x39: "SURF",
	0x46: "STRENGTH",
	0x94: "FLASH",
	0x7F: "WATERFALL",
	0xFA: "WHIRLPOOL",
}

## Two moves no HM teaches, one either side of the HM range.
const MOVE_TACKLE: int = 0x21
const MOVE_SLASH: int = 0xA3

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testforget", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	var moves: Array = []
	for number: int in range(1, 0x100):
		moves.append({
			"number": number, "name": "MOVE%02X" % number, "effect": 0, "power": 40,
			"type": 0, "accuracy": 255, "pp": 10, "effect_chance": 0,
		})
	for move: int in HM_MOVES:
		moves[move - 1]["name"] = String(HM_MOVES[move])
	moves[MOVE_TACKLE - 1]["name"] = "TACKLE"
	moves[MOVE_SLASH - 1]["name"] = "SLASH"
	RomCache.write_json(RomCache.moves_path(_directory), moves)

	RomCache.write_json(RomCache.species_path(_directory), [])
	RomCache.write_json(RomCache.items_path(_directory), [])
	RomCache.write_json(RomCache.types_path(_directory), [])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [])
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testforget",
		"sha1": "0123456789abcdef",
		"complete": true,
	})


func _data() -> GameData:
	return GameData.open_directory(_directory)


## All seven, and nothing else. The count is asserted too, so an eighth entry
## slipping in from FIELD_MOVES or a TM list is a failure rather than a pass.
func test_is_hm_move_covers_every_hm_and_nothing_else() -> void:
	assert_eq(Gen2MoveForget.HM_MOVES.size(), 7)
	for move: int in HM_MOVES:
		assert_true(Gen2MoveForget.is_hm_move(move), String(HM_MOVES[move]))
	assert_false(Gen2MoveForget.is_hm_move(MOVE_TACKLE))
	assert_false(Gen2MoveForget.is_hm_move(MOVE_SLASH))
	assert_false(Gen2MoveForget.is_hm_move(0))


## The overworld's field-move list is a different, shorter question: Fly and
## Flash are HMs that this project does not act on, and forgetting is gated on
## all seven regardless.
func test_the_hm_list_is_wider_than_the_overworld_field_moves() -> void:
	for move: int in Gen2WorldFieldMove.FIELD_MOVES:
		assert_true(Gen2MoveForget.is_hm_move(move), "field move %d" % move)
	assert_eq(Gen2WorldFieldMove.FIELD_MOVES.size(), 5)
	assert_true(Gen2MoveForget.is_hm_move(0x13), "FLY is an HM with no field effect here")
	assert_false(Gen2WorldFieldMove.FIELD_MOVES.has(0x13))


## ListMoves walks the slots and stops at the first zero, so a padded slot is
## not offered. In practice ForgetMove only opens with all four taken.
func test_options_lists_known_moves_and_stops_at_the_first_empty_slot() -> void:
	var rows: Array = Gen2MoveForget.options(
		_data(), [MOVE_TACKLE, 0x39, 0, MOVE_SLASH]
	)
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["slot"], 0)
	assert_eq(rows[0]["name"], "TACKLE")
	assert_eq(rows[1]["slot"], 1)
	assert_eq(rows[1]["name"], "SURF")


## The IsHMMove test the menu makes on confirm, resolved per row.
func test_options_marks_hm_rows_as_not_forgettable() -> void:
	var rows: Array = Gen2MoveForget.options(
		_data(), [MOVE_TACKLE, 0x39, 0x94, MOVE_SLASH]
	)
	assert_eq(rows.size(), 4)
	assert_true(bool(rows[0]["forgettable"]), "TACKLE")
	assert_false(bool(rows[1]["forgettable"]), "SURF is HM03")
	assert_false(bool(rows[2]["forgettable"]), "FLASH is HM05")
	assert_true(bool(rows[3]["forgettable"]), "SLASH")


func test_options_answers_empty_without_data() -> void:
	assert_eq(Gen2MoveForget.options(null, [MOVE_TACKLE]), [])
	assert_eq(Gen2MoveForget.options(_data(), []), [])


## The wording is the source's, so a screen reads it rather than inventing one.
func test_prompts_name_the_pokemon_and_both_moves() -> void:
	assert_eq(
		Gen2MoveForget.ask_text("GEODUDE", "STRENGTH"),
		"GEODUDE is trying to learn STRENGTH. But GEODUDE can't learn more than four moves. Delete an older move to make room for STRENGTH?"
	)
	assert_eq(Gen2MoveForget.which_text(), "Which move should be forgotten?")
	assert_eq(Gen2MoveForget.stop_text("STRENGTH"), "Stop learning STRENGTH?")
	assert_eq(
		Gen2MoveForget.did_not_learn_text("GEODUDE", "STRENGTH"),
		"GEODUDE did not learn STRENGTH."
	)
	assert_eq(
		Gen2MoveForget.forgot_text("GEODUDE", "TACKLE"),
		"1, 2 and… Poof! GEODUDE forgot TACKLE. And…"
	)
	assert_eq(Gen2MoveForget.learned_text("GEODUDE", "STRENGTH"), "GEODUDE learned STRENGTH!")
	assert_eq(Gen2MoveForget.cant_forget_hm_text(), "HM moves can't be forgotten now.")
