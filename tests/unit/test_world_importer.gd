extends GutTest

## The map importer reads trainer object pointers as source records, not as
## executable overworld scripts.


func test_trainer_record_decodes_the_source_fields_and_after_script_pointer() -> void:
	var bank: int = 48
	var address: int = 0x6000
	var offset: int = RomFile.linear(bank, address)
	var bytes := PackedByteArray()
	bytes.resize(offset + 12)
	bytes[offset] = 0x34
	bytes[offset + 1] = 0x12
	bytes[offset + 2] = 7
	bytes[offset + 3] = 9
	bytes[offset + 4] = 0x00
	bytes[offset + 5] = 0x70
	bytes[offset + 6] = 0x10
	bytes[offset + 7] = 0x70
	bytes[offset + 8] = 0x20
	bytes[offset + 9] = 0x70
	bytes[offset + 10] = 0x0C
	bytes[offset + 11] = 0x60

	var record: Dictionary = Gen2WorldImporter._read_trainer_record(
		RomFile.from_bytes(bytes, RomRegistry.CRYSTAL), bank, address
	)
	assert_eq(record["event_flag"], 0x1234)
	assert_eq(record["trainer_group"], 7)
	assert_eq(record["trainer_id"], 9)
	assert_eq(record["seen_text"], {"bank": bank, "address": 0x7000})
	assert_eq(record["win_text"], {"bank": bank, "address": 0x7010})
	assert_eq(record["loss_text"], {"bank": bank, "address": 0x7020})
	assert_eq(record["after_script"], 0x600C)
