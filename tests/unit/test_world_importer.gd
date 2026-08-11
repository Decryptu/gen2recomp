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


func test_a_conditional_background_event_collects_the_script_behind_it() -> void:
	# BGEVENT_IFSET and BGEVENT_IFNOTSET point at a four-byte conditional_event
	# record, an event flag then a near script pointer, not at a script
	# (macros/scripts/maps.asm). Giovanni's office door and the Rocket hideout's
	# transmitter door are both reached this way.
	var bank: int = 48
	var record: int = 0x6100
	var script: int = 0x6200
	var bytes := PackedByteArray()
	bytes.resize(RomFile.linear(bank, script) + 8)
	var record_offset: int = RomFile.linear(bank, record)
	bytes[record_offset] = 0x22
	bytes[record_offset + 1] = 0x11
	bytes[record_offset + 2] = script & 0xFF
	bytes[record_offset + 3] = script >> 8
	bytes[RomFile.linear(bank, script)] = Gen2WorldScript.END

	var rom: RomFile = RomFile.from_bytes(bytes, RomRegistry.CRYSTAL)
	var script_data: Dictionary = {}
	Gen2WorldImporter._collect_conditional_bg_script(
		rom, bank, {"type": Gen2WorldImporter.BGEVENT_IFNOTSET, "script": record},
		script_data, {}, {}
	)
	assert_true(
		script_data.has(Gen2WorldScript.pointer_key(bank, script)), JSON.stringify(script_data)
	)

	var read_only: Dictionary = {}
	Gen2WorldImporter._collect_conditional_bg_script(
		rom, bank, {"type": 0, "script": record}, read_only, {}, {}
	)
	assert_true(read_only.is_empty(), "a plain BGEVENT_READ points straight at its script")


func test_the_tileset_strip_places_the_second_graphics_block_at_its_own_index() -> void:
	var block_bytes: int = RomLayout.TILESET_BLOCK_TILES * Gen2Tiles.TILE_BYTES
	var raw := PackedByteArray()
	raw.resize(block_bytes * 2)
	raw.fill(0)
	# Two solid tiles, colour 1 in the first block and colour 3 in the second.
	for byte: int in Gen2Tiles.TILE_BYTES:
		raw[byte] = 0xFF if byte % 2 == 0 else 0x00
		raw[block_bytes + byte] = 0xFF

	var strip: PackedByteArray = Gen2WorldImporter._tileset_strip(raw)
	var width: int = RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_WIDTH
	assert_eq(strip.size(), width * Gen2Tiles.TILE_HEIGHT)
	assert_eq(strip[0], 1)
	assert_eq(strip[RomLayout.TILESET_BLOCK_STRIDE * Gen2Tiles.TILE_WIDTH], 3)
	assert_eq(
		strip[RomLayout.TILESET_BLOCK_TILES * Gen2Tiles.TILE_WIDTH], 0,
		"the font tiles between the two blocks are never a tileset's own"
	)


func test_a_tileset_shipping_one_graphics_block_leaves_the_second_blank() -> void:
	var block_bytes: int = RomLayout.TILESET_BLOCK_TILES * Gen2Tiles.TILE_BYTES
	var raw := PackedByteArray()
	raw.resize(block_bytes)
	raw.fill(0xFF)

	var strip: PackedByteArray = Gen2WorldImporter._tileset_strip(raw)
	assert_eq(strip.size(), RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	assert_eq(strip[0], 3)
	assert_eq(strip[RomLayout.TILESET_BLOCK_STRIDE * Gen2Tiles.TILE_WIDTH], 0)
