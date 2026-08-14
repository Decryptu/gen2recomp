extends GutTest

## The battle animation layout checks, against dumps this test builds.
##
## No cartridge is opened here, for the reason `test_rom_importer.gd` states:
## where the tables are is only settled by a real dump and
## `tools/checks/battle_anims.gd`, and what is worth testing is that the
## checks would notice if they were somewhere else.

## Everything is put in bank 1, so an in-bank address is the file offset plus
## nothing and the dump stays two banks long.
const BANK: int = 1
const DUMP_SIZE: int = 0x8000

const SCRIPTS: int = 0x4000
const POUND_BODY: int = 0x4300
const DUMMY_BODY: int = 0x4400
const OBJECTS: int = 0x5000
const FRAMESETS: int = 0x6000
const FRAMESET_STREAM: int = 0x6200
const OAM_SETS: int = 0x6400
const OAM_SPRITES: int = 0x6800
const OBJECT_GFX: int = 0x7000
const SINE: int = 0x7400
## Somewhere inside the dump for an `AnimObjGFX` row to point at. Nothing
## decompresses it: only `import_to_cache` reads the stream.
const GFX_DATA: int = 0x0100

var _dump: PackedByteArray = PackedByteArray()


func before_each() -> void:
	_dump = PackedByteArray()
	_dump.resize(DUMP_SIZE)
	_write_scripts()
	_write_objects()
	_write_framesets()
	_write_oam_sets()
	_write_object_gfx()
	_write_sine()


## A plausible `BattleAnimations`: POUND at entry 1 and a bare `anim_ret`
## everywhere else.
func _write_scripts() -> void:
	for index: int in RomLayout.BATTLE_ANIM_SCRIPT_COUNT:
		_word(SCRIPTS + index * 2, POUND_BODY if index == 1 else DUMMY_BODY)
	for index: int in Gen2BattleAnimImporter.POUND_BYTES.size():
		_dump[POUND_BODY + index] = Gen2BattleAnimImporter.POUND_BYTES[index]
	_dump[DUMMY_BODY] = 0xFF


## 188 rows whose four table indexes are all in range.
func _write_objects() -> void:
	for index: int in RomLayout.BATTLE_ANIM_OBJECT_COUNT:
		var row: int = OBJECTS + index * RomLayout.BATTLE_ANIM_OBJECT_SIZE
		_dump[row + Gen2BattleAnimImporter.OBJECT_FLAGS] = 0x01
		_dump[row + Gen2BattleAnimImporter.OBJECT_Y_FIX] = 0xFF
		_dump[row + Gen2BattleAnimImporter.OBJECT_FRAMESET] = 0
		_dump[row + Gen2BattleAnimImporter.OBJECT_FUNCTION] = 0
		_dump[row + Gen2BattleAnimImporter.OBJECT_PALETTE] = 2
		_dump[row + Gen2BattleAnimImporter.OBJECT_GFX] = 1


## Every frameset pointing at one `oamframe` and an `oamend`.
func _write_framesets() -> void:
	for index: int in RomLayout.BATTLE_ANIM_FRAMESET_COUNT:
		_word(FRAMESETS + index * 2, FRAMESET_STREAM)
	_dump[FRAMESET_STREAM] = 0x00
	_dump[FRAMESET_STREAM + 1] = 0x06
	_dump[FRAMESET_STREAM + 2] = Gen2BattleAnimImporter.OAM_END


## Every OAM set naming one sprite.
func _write_oam_sets() -> void:
	for index: int in RomLayout.BATTLE_ANIM_OAM_SET_COUNT:
		var row: int = OAM_SETS + index * RomLayout.BATTLE_ANIM_OAM_SET_SIZE
		_dump[row + Gen2BattleAnimImporter.OAM_SET_VTILE] = 0
		_dump[row + Gen2BattleAnimImporter.OAM_SET_LENGTH] = 1
		_word(row + Gen2BattleAnimImporter.OAM_SET_POINTER, OAM_SPRITES)


func _write_object_gfx() -> void:
	for index: int in RomLayout.BATTLE_ANIM_GFX_COUNT:
		var row: int = OBJECT_GFX + index * RomLayout.BATTLE_ANIM_GFX_SIZE
		_dump[row + Gen2BattleAnimImporter.GFX_TILES] = 1
		_dump[row + Gen2BattleAnimImporter.GFX_POINTER] = 0
		_word(row + Gen2BattleAnimImporter.GFX_POINTER + 1, GFX_DATA)


func _write_sine() -> void:
	for index: int in RomLayout.BATTLE_ANIM_SINE_BYTES:
		_dump[SINE + index] = RomLayout.BATTLE_ANIM_SINE_WAVE[index]


func _word(at: int, value: int) -> void:
	_dump[at] = value & 0xFF
	_dump[at + 1] = (value >> 8) & 0xFF


func _layout() -> Dictionary:
	return {
		"battle_anims": {
			"scripts": SCRIPTS,
			"objects": OBJECTS,
			"framesets": FRAMESETS,
			"oam_sets": OAM_SETS,
			"object_gfx": OBJECT_GFX,
			"sine": SINE,
		},
	}


func _read(layout: Dictionary = _layout()) -> Dictionary:
	return Gen2BattleAnimImporter.read_battle_anims(
		RomFile.from_bytes(_dump, RomRegistry.GOLD), layout
	)


func test_a_plausible_layer_verifies() -> void:
	var result: Dictionary = _read()
	assert_true(bool(result["ok"]), String(result.get("message", "")))
	assert_eq(int(result["counts"]["scripts"]), RomLayout.BATTLE_ANIM_SCRIPT_COUNT)
	assert_eq(int(result["counts"]["objects"]), RomLayout.BATTLE_ANIM_OBJECT_COUNT)
	assert_eq(int(result["counts"]["framesets"]), RomLayout.BATTLE_ANIM_FRAMESET_COUNT)
	assert_eq(int(result["counts"]["oam_sets"]), RomLayout.BATTLE_ANIM_OAM_SET_COUNT)


## The sine table is stored as the cartridge's own bytes, quarter turn included:
## $0100 is what says it was read rather than derived in eight bits.
func test_the_sine_table_keeps_its_sixteen_bit_quarter_turn() -> void:
	var bytes: Array = _read()["anims"]["sine"]["bytes"]
	assert_eq(bytes.size(), RomLayout.BATTLE_ANIM_SINE_BYTES)
	assert_eq(int(bytes[32]), 0x00)
	assert_eq(int(bytes[33]), 0x01)


## Sixty-four identical bytes appear several times in a dump, so the values are
## the whole check for this offset.
func test_a_sine_table_of_the_wrong_shape_fails() -> void:
	_dump[SINE + 33] = 0x00
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "sine table byte 33")


## The region runs from the table to the end of the last body it reaches, and
## the pointer table is its own first bytes.
func test_the_script_region_starts_at_the_table_and_ends_at_the_last_body() -> void:
	var region: Dictionary = _read()["anims"]["scripts"]
	assert_eq(int(region["bank"]), BANK)
	assert_eq(int(region["address"]), SCRIPTS)
	assert_eq(int((region["bytes"] as Array).size()), DUMMY_BODY + 1 - SCRIPTS)
	assert_eq(int((region["bytes"] as Array)[2]), POUND_BODY & 0xFF)
	assert_eq(int((region["bytes"] as Array)[3]), POUND_BODY >> 8)


## An animation is only trustworthy against content, because almost any byte run
## decodes as commands: a table of the right shape in the wrong place walks.
func test_an_entry_that_is_not_pounds_fails() -> void:
	_dump[POUND_BODY + 4] = 0x30
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "not POUND's")


func test_a_script_pointer_outside_the_bank_fails() -> void:
	_word(SCRIPTS + 8, 0x3FFF)
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "outside the bank")


## A body with no `anim_ret` in it walks to the guard rather than off the bank.
func test_a_body_that_never_returns_fails() -> void:
	for at: int in range(DUMMY_BODY, DUMMY_BODY + Gen2BattleAnimImporter.MAX_BODY_BYTES + 2):
		_dump[at] = 0xFA  # anim_incvar, which never ends anything
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "never ends")


## A branch is followed, so a body only some other body jumps into is measured
## too, and one that jumps out of the bank is refused.
func test_a_branch_out_of_the_bank_fails() -> void:
	_dump[DUMMY_BODY] = 0xFC  # anim_jump
	_word(DUMMY_BODY + 1, 0x8000)
	_dump[DUMMY_BODY + 3] = 0xFF
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "branches to")


func test_a_called_body_joins_the_region() -> void:
	var called: int = DUMMY_BODY + 0x40
	_dump[DUMMY_BODY] = 0xFE  # anim_call
	_word(DUMMY_BODY + 1, called)
	_dump[DUMMY_BODY + 3] = 0xFF
	_dump[called] = 0xFF
	var region: Dictionary = _read()["anims"]["scripts"]
	assert_eq(int((region["bytes"] as Array).size()), called + 1 - SCRIPTS)


func test_an_object_naming_a_frameset_past_the_table_fails() -> void:
	_dump[OBJECTS + Gen2BattleAnimImporter.OBJECT_FRAMESET] = \
		RomLayout.BATTLE_ANIM_FRAMESET_COUNT
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "names frameset")


func test_an_object_naming_a_ninth_palette_fails() -> void:
	_dump[OBJECTS + Gen2BattleAnimImporter.OBJECT_PALETTE] = \
		Gen2BattleAnimImporter.PALETTE_COUNT
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "names palette")


## `oamframe` and `oamwait` are both two bytes and the three terminators are
## one, so a stream with no terminator strides past the guard.
func test_a_frameset_stream_that_never_ends_fails() -> void:
	for at: int in range(
		FRAMESET_STREAM, FRAMESET_STREAM + Gen2BattleAnimImporter.MAX_FRAMESET_BYTES * 2 + 4
	):
		_dump[at] = 0x00
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "never ends")


func test_a_frameset_naming_an_oam_set_past_the_table_fails() -> void:
	_dump[FRAMESET_STREAM] = RomLayout.BATTLE_ANIM_OAM_SET_COUNT
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "names OAM set")


## An `oamwait` is not a terminator: the stream carries on past it.
func test_an_oam_wait_does_not_end_a_stream() -> void:
	_dump[FRAMESET_STREAM] = Gen2BattleAnimImporter.OAM_WAIT
	_dump[FRAMESET_STREAM + 1] = 0x04
	_dump[FRAMESET_STREAM + 2] = 0x00
	_dump[FRAMESET_STREAM + 3] = 0x06
	_dump[FRAMESET_STREAM + 4] = Gen2BattleAnimImporter.OAM_END
	var region: Dictionary = _read()["anims"]["framesets"]
	assert_eq(int((region["bytes"] as Array).size()), FRAMESET_STREAM + 5 - FRAMESETS)


func test_an_oam_set_whose_sprites_leave_the_bank_fails() -> void:
	_dump[OAM_SETS + Gen2BattleAnimImporter.OAM_SET_LENGTH] = 0xFF
	_word(OAM_SETS + Gen2BattleAnimImporter.OAM_SET_POINTER, 0x7FF0)
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "outside the bank")


func test_an_oam_set_with_no_sprites_fails() -> void:
	_dump[OAM_SETS + Gen2BattleAnimImporter.OAM_SET_LENGTH] = 0
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "holds no sprites")


## Only rows 1 to 39 carry a sheet. Index 0 is the slot no `anim_*gfx` reaches
## and the last two are the `NULL` rows the battler-graphics commands fill in.
func test_three_graphics_rows_carry_no_sheet() -> void:
	var rows: Array = _read()["anims"]["object_gfx"]
	assert_eq(rows.size(), RomLayout.BATTLE_ANIM_GFX_COUNT)
	assert_false(bool(rows[0]["sheet"]))
	assert_true(bool(rows[RomLayout.BATTLE_ANIM_GFX_FIRST_SHEET]["sheet"]))
	assert_true(bool(rows[RomLayout.BATTLE_ANIM_GFX_LAST_SHEET]["sheet"]))
	assert_false(bool(rows[RomLayout.BATTLE_ANIM_GFX_LAST_SHEET + 1]["sheet"]))
	assert_false(bool(rows[RomLayout.BATTLE_ANIM_GFX_COUNT - 1]["sheet"]))


func test_a_layout_without_the_section_fails_rather_than_reading_zero() -> void:
	var result: Dictionary = _read({})
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "No battle animation layout")

	var empty: Dictionary = _read({"trainer_classes": 66})
	assert_false(bool(empty["ok"]))
	assert_string_contains(String(empty["message"]), "offsets are missing")


func test_a_dump_too_short_to_hold_the_tables_fails_rather_than_reading_past_it() -> void:
	_dump.resize(SCRIPTS + 4)
	var result: Dictionary = _read()
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["message"]), "outside the cartridge")
