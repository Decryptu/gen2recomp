extends GutTest

## The offset tables cannot be checked for correctness without a cartridge;
## that is what [method RomImporter.verify_layout] does at import time. What can
## be checked here is that they are internally consistent and complete, and that
## the addressing arithmetic around them is right.


func test_every_registry_game_has_a_layout() -> void:
	for id: StringName in RomRegistry.ORDER:
		assert_true(RomLayout.is_characterised(id), "%s has no layout" % id)


func test_an_unknown_game_has_none() -> void:
	assert_true(RomLayout.for_id(&"emerald").is_empty())


func test_gold_and_silver_share_their_common_layout() -> void:
	# The bank map is shared, but the item tables and the compact icon run move
	# between the two dumps.
	var gold: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	var silver: Dictionary = RomLayout.for_id(RomRegistry.SILVER)
	for key: String in gold:
		if key in [
			"item_attributes", "item_status_actions", "item_healing_hp",
			"overworld_icons", "copyright", "game_freak_presents",
		]:
			continue
		assert_eq(gold[key], silver[key], "Gold/Silver layout differs at %s" % key)
	assert_ne(gold["item_attributes"], silver["item_attributes"])
	# The copyright screen is the same graphic in the same place; only the
	# string's own address moves, sixty bytes apart in bank 1.
	var gold_copyright: Dictionary = gold["copyright"]
	var silver_copyright: Dictionary = silver["copyright"]
	assert_eq(gold_copyright["gfx"], silver_copyright["gfx"])
	assert_eq(gold_copyright["tiles"], silver_copyright["tiles"])
	assert_ne(gold_copyright["string"], silver_copyright["string"])
	# The splash graphics are the same pictures 440 bytes apart in the same bank,
	# and the object palette they are drawn through does not move at all.
	var gold_presents: Dictionary = gold["game_freak_presents"]
	var silver_presents: Dictionary = silver["game_freak_presents"]
	assert_ne(gold_presents["gfx"], silver_presents["gfx"])
	assert_eq(
		int(gold_presents["stars"]) - int(gold_presents["gfx"]),
		int(silver_presents["stars"]) - int(silver_presents["gfx"])
	)
	assert_eq(gold_presents["object_palette"], silver_presents["object_palette"])


func test_crystal_has_its_own() -> void:
	assert_ne(RomLayout.for_id(RomRegistry.CRYSTAL), RomLayout.for_id(RomRegistry.GOLD))


func test_layouts_carry_the_same_keys() -> void:
	var gold: Array = RomLayout.for_id(RomRegistry.GOLD).keys()
	var crystal: Array = RomLayout.for_id(RomRegistry.CRYSTAL).keys()
	gold.sort()
	crystal.sort()
	assert_eq(gold, crystal)


func test_every_offset_lands_inside_a_cartridge() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		for key: String in layout:
			if layout[key] is int and key != "pic_bank_add":
				assert_between(int(layout[key]), 0, RomRegistry.EXPECTED_SIZE - 1, "%s.%s" % [id, key])


func test_tables_do_not_run_off_the_end() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		var last_name: int = RomLayout.species_name_offset(layout, RomLayout.SPECIES_COUNT)
		assert_lt(last_name + RomLayout.NAME_LENGTH, RomRegistry.EXPECTED_SIZE)
		var last_stats: int = RomLayout.base_stats_offset(layout, RomLayout.SPECIES_COUNT)
		assert_lt(last_stats + RomLayout.BASE_STATS_SIZE, RomRegistry.EXPECTED_SIZE)
		var last_pic: int = RomLayout.pic_pointer_offset(layout, RomLayout.SPECIES_COUNT, true)
		assert_lt(last_pic + RomLayout.PIC_POINTER_SIZE, RomRegistry.EXPECTED_SIZE)
		var last_move: int = RomLayout.move_data_offset(layout, RomLayout.MOVE_COUNT)
		assert_lt(last_move + RomLayout.MOVE_DATA_SIZE, RomRegistry.EXPECTED_SIZE)
		var last_type: int = RomLayout.type_name_pointer_offset(layout, RomLayout.TYPE_COUNT - 1)
		assert_lt(last_type + RomLayout.TYPE_POINTER_SIZE, RomRegistry.EXPECTED_SIZE)


func test_species_tables_are_one_based() -> void:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	assert_eq(RomLayout.species_name_offset(layout, 1), int(layout["species_names"]))
	assert_eq(RomLayout.base_stats_offset(layout, 1), int(layout["base_stats"]))


func test_move_data_is_one_based_and_fixed_stride() -> void:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	assert_eq(RomLayout.move_data_offset(layout, 1), int(layout["move_data"]))
	assert_eq(
		RomLayout.move_data_offset(layout, 3) - RomLayout.move_data_offset(layout, 2),
		RomLayout.MOVE_DATA_SIZE
	)


func test_the_type_table_is_indexed_by_type_number_from_zero() -> void:
	# Unlike the species tables: NORMAL is type $00.
	var layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	assert_eq(RomLayout.type_name_pointer_offset(layout, 0), int(layout["type_names"]))
	assert_eq(
		RomLayout.type_name_pointer_offset(layout, 1) - int(layout["type_names"]),
		RomLayout.TYPE_POINTER_SIZE
	)


func test_a_type_pointer_resolves_against_its_own_bank() -> void:
	# The table stores an address and no bank, so the bank comes from where the
	# table itself sits.
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		var table: int = RomLayout.type_name_pointer_offset(layout, 0)
		var bank: int = RomLayout.bank_of(table)
		assert_eq(RomFile.linear(bank, 0x4000 + (table & 0x3FFF)), table)


func test_the_palette_table_is_indexed_by_species_number() -> void:
	# Unlike the others: there is an entry before Bulbasaur's.
	var layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	assert_eq(
		RomLayout.palette_offset(layout, 1),
		int(layout["palettes"]) + Gen2Palette.ENTRY_BYTES
	)


func test_pic_pointers_come_in_front_back_pairs() -> void:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	var front: int = RomLayout.pic_pointer_offset(layout, 2, false)
	var back: int = RomLayout.pic_pointer_offset(layout, 2, true)
	assert_eq(back - front, RomLayout.PIC_POINTER_SIZE)
	assert_eq(front - RomLayout.pic_pointer_offset(layout, 1, false), RomLayout.PIC_POINTER_SIZE * 2)


func test_the_trainer_tables_are_one_entry_out_of_step() -> void:
	# The palette table opens with the player, who has no pic, so a class reaches
	# its palette by its own number and its pic by one less.
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		assert_eq(
			RomLayout.trainer_pic_pointer_offset(layout, 1),
			int(layout["trainer_pic_pointers"]), "%s pics start at the first class" % id
		)
		assert_eq(
			RomLayout.trainer_palette_offset(layout, 1),
			int(layout["trainer_palettes"]) + Gen2Palette.PAIR_BYTES,
			"%s palettes start at the player" % id
		)


func test_a_trainer_palette_is_one_pair_and_a_species_is_two() -> void:
	# Only a Pokémon can be shiny, so a class stores half of what a species does.
	assert_eq(Gen2Palette.ENTRY_BYTES, Gen2Palette.PAIR_BYTES * 2)


func test_crystal_has_one_trainer_class_more_than_gold() -> void:
	assert_eq(
		RomLayout.trainer_class_count(RomLayout.for_id(RomRegistry.CRYSTAL)),
		RomLayout.trainer_class_count(RomLayout.for_id(RomRegistry.GOLD)) + 1
	)


func test_the_trainer_tables_do_not_run_off_the_end() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		var count: int = RomLayout.trainer_class_count(layout)
		assert_gt(count, 0, "%s has no trainer classes" % id)
		assert_lt(
			RomLayout.trainer_pic_pointer_offset(layout, count) + RomLayout.PIC_POINTER_SIZE,
			RomRegistry.EXPECTED_SIZE
		)
		assert_lt(
			RomLayout.trainer_palette_offset(layout, count) + Gen2Palette.PAIR_BYTES,
			RomRegistry.EXPECTED_SIZE
		)


func test_the_trainer_party_table_is_a_flat_run_of_pointers() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		assert_eq(
			RomLayout.trainer_party_pointer_offset(layout, 1),
			int(layout["trainer_parties"]), "%s parties start at the first class" % id
		)
		assert_eq(
			RomLayout.trainer_party_pointer_offset(layout, 2),
			int(layout["trainer_parties"]) + RomLayout.TRAINER_PARTY_POINTER_SIZE
		)


func test_the_trainer_party_table_does_not_run_off_the_end() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		var count: int = RomLayout.trainer_class_count(layout)
		assert_lt(
			RomLayout.trainer_party_pointer_offset(layout, count)
				+ RomLayout.TRAINER_PARTY_POINTER_SIZE,
			RomRegistry.EXPECTED_SIZE
		)


func test_the_trainer_dvs_table_is_a_flat_run_indexed_from_the_first_class() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		assert_eq(
			RomLayout.trainer_dvs_offset(layout, 1),
			int(layout["trainer_dvs"]), "%s DVs start at the first class" % id
		)
		assert_eq(
			RomLayout.trainer_dvs_offset(layout, 2),
			int(layout["trainer_dvs"]) + RomLayout.TRAINER_DVS_SIZE
		)

		var count: int = RomLayout.trainer_class_count(layout)
		assert_lt(
			RomLayout.trainer_dvs_offset(layout, count) + RomLayout.TRAINER_DVS_SIZE,
			RomRegistry.EXPECTED_SIZE
		)


## A NORMAL Pokémon is level and species only; the other three types add an
## item, four moves, or both, on top of that, never fewer than either half asks
## for on its own.
func test_a_trainer_mons_extra_size_matches_what_its_type_byte_says_it_carries() -> void:
	assert_eq(RomLayout.trainer_mon_extra_size(RomLayout.TRAINER_MON_NORMAL), 0)
	assert_eq(RomLayout.trainer_mon_extra_size(RomLayout.TRAINER_MON_ITEM), 1)
	assert_eq(
		RomLayout.trainer_mon_extra_size(RomLayout.TRAINER_MON_MOVES),
		RomLayout.TRAINER_MON_MOVE_COUNT
	)
	assert_eq(
		RomLayout.trainer_mon_extra_size(RomLayout.TRAINER_MON_ITEM_MOVES),
		RomLayout.TRAINER_MON_MOVE_COUNT + 1
	)


func test_unown_forms_are_zero_based() -> void:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	assert_eq(
		RomLayout.unown_pic_pointer_offset(layout, 0, false),
		int(layout["unown_pic_pointers"])
	)


func test_crystal_shifts_every_pic_bank_by_a_constant() -> void:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	assert_eq(RomLayout.fix_pic_bank(layout, 0x12), 0x12 + 0x36)
	assert_eq(RomLayout.fix_pic_bank(layout, 0x23), 0x23 + 0x36)


func test_gold_patches_only_the_three_banks_that_moved() -> void:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	assert_eq(RomLayout.fix_pic_bank(layout, 0x13), 0x1F)
	assert_eq(RomLayout.fix_pic_bank(layout, 0x14), 0x20)
	assert_eq(RomLayout.fix_pic_bank(layout, 0x1F), 0x2E)
	assert_eq(RomLayout.fix_pic_bank(layout, 0x1A), 0x1A, "an unpatched bank passes through")


func test_the_font_covers_the_printable_half_of_the_charmap() -> void:
	# The font is indexed by character code, so its first tile is $80 and its
	# last is $FF. Anything else and a character byte stops being a tile number.
	assert_eq(RomLayout.FONT_FIRST_CODE, Gen2Text.FIRST_PRINTABLE)
	assert_eq(RomLayout.FONT_FIRST_CODE + RomLayout.FONT_TILES - 1, 0xFF)


func test_the_font_runs_where_the_charmap_agrees() -> void:
	for run: Array in RomLayout.FONT_INK_RUNS:
		for code: int in range(run[0], run[1] + 1):
			assert_ne(Gen2Text.character(code), "<%02X>" % code, "$%02X has no character" % code)
	for run: Array in RomLayout.FONT_BLANK_RUNS:
		for code: int in range(run[0], run[1] + 1):
			assert_eq(Gen2Text.character(code), "<%02X>" % code, "$%02X has one" % code)


func test_the_box_drawing_codes_address_a_border_directly() -> void:
	# ┌ ─ ┐ │ └ ┘ are consecutive in the charmap, and the frame is loaded so
	# that those codes name its six tiles.
	assert_eq(Gen2Text.character(RomLayout.FRAME_FIRST_CODE), "┌")
	assert_eq(
		Gen2Text.character(RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TILES - 1), "┘"
	)


func test_frames_are_a_fixed_stride_table() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		assert_eq(RomLayout.frame_offset(layout, 0), int(layout["frames"]))
		assert_eq(
			RomLayout.frame_offset(layout, 1) - RomLayout.frame_offset(layout, 0),
			RomLayout.FRAME_TILES * Gen2Tiles.TILE_1BPP_BYTES
		)


func test_the_font_and_the_frames_do_not_overlap_or_run_off_the_end() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		var font_end: int = RomLayout.font_offset(layout) \
			+ RomLayout.FONT_TILES * Gen2Tiles.TILE_1BPP_BYTES
		assert_lt(font_end, RomLayout.frame_offset(layout, 0), "%s font overlaps its frames" % id)
		var last: int = RomLayout.frame_offset(layout, RomLayout.FRAME_COUNT - 1) \
			+ RomLayout.FRAME_TILES * Gen2Tiles.TILE_1BPP_BYTES
		assert_lt(last, RomRegistry.EXPECTED_SIZE)


func test_the_battle_graphics_sit_back_to_back_in_the_order_they_are_stored() -> void:
	# They are one run in the cartridge: the enemy's HUD border, the player's,
	# then the exp bar. Each offset is a claim about where the one before it ends.
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		assert_eq(
			int(layout["enemy_hud"]) + RomLayout.ENEMY_HUD_TILES * Gen2Tiles.TILE_1BPP_BYTES,
			int(layout["player_hud"]), "%s: the player's HUD does not follow the enemy's" % id
		)
		assert_eq(
			int(layout["player_hud"]) + RomLayout.PLAYER_HUD_TILES * Gen2Tiles.TILE_1BPP_BYTES,
			int(layout["exp_bar"]), "%s: the exp bar does not follow the HUD borders" % id
		)


func test_the_battle_font_follows_the_font_itself() -> void:
	# Both are in the section the font opens, and the battle sheet is the next
	# thing in it after the 128 glyphs.
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		assert_eq(
			RomLayout.font_offset(layout) + RomLayout.FONT_TILES * Gen2Tiles.TILE_1BPP_BYTES,
			int(layout["battle_font"]), "%s battle font" % id
		)


func test_the_bars_have_a_level_for_every_step_of_their_tiles() -> void:
	assert_lt(
		RomLayout.HP_BAR_FIRST_TILE + RomLayout.HP_BAR_LEVELS, RomLayout.BATTLE_FONT_TILES
	)
	assert_lt(RomLayout.EXP_BAR_LEVELS, RomLayout.EXP_BAR_TILES)


func test_a_fixed_bank_still_addresses_inside_the_cartridge() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		for stored: int in range(0x10, 0x40):
			var bank: int = RomLayout.fix_pic_bank(layout, stored)
			assert_lt(RomFile.linear(bank, 0x7FFF), RomRegistry.EXPECTED_SIZE)


## GetDexEntryPointer picks the bank from the species number rather than the
## pointer: `(species - 1) >> 6`, so each of the four sections covers 64 species
## and the last covers the 59 that are left.
func test_dex_entry_banks_change_every_sixty_four_species() -> void:
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		var banks: Array = (layout["pokedex"] as Dictionary)["entry_banks"]
		assert_eq(banks.size(), RomLayout.DEX_ENTRY_BANK_COUNT, "%s bank count" % id)
		for boundary: Array in [[1, 0], [64, 0], [65, 1], [128, 1], [129, 2], [192, 2],
			[193, 3], [RomLayout.SPECIES_COUNT, 3]]:
			assert_eq(
				RomLayout.dex_entry_bank(layout, int(boundary[0])),
				int(banks[int(boundary[1])]),
				"%s species %d" % [id, int(boundary[0])]
			)


func test_dex_entry_pointers_are_one_based_and_two_bytes_wide() -> void:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	var table: int = int((layout["pokedex"] as Dictionary)["entry_pointers"])
	assert_eq(RomLayout.dex_entry_pointer_offset(layout, 1), table)
	assert_eq(
		RomLayout.dex_entry_pointer_offset(layout, 2),
		table + RomLayout.DEX_ENTRY_POINTER_SIZE
	)


## A dex entry address is bank-local, so the flat offset is its bank's base plus
## the address's position within the window.
func test_a_dex_entry_address_resolves_into_its_own_bank() -> void:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	var bank: int = RomLayout.dex_entry_bank(layout, 1)
	assert_eq(
		RomLayout.dex_entry_offset(layout, 1, 0x5695),
		bank * RomFile.BANK_SIZE + 0x1695
	)


## Every Pokedex table has to sit inside the dump like the flat offsets do; the
## nested Dictionary keeps them out of that check, so they are checked here.
func test_pokedex_tables_land_inside_a_cartridge() -> void:
	for id: StringName in RomRegistry.ORDER:
		var pokedex: Dictionary = RomLayout.for_id(id)["pokedex"]
		for key: String in ["entry_pointers", "order_new", "order_alpha"]:
			assert_between(
				int(pokedex[key]), 0, RomRegistry.EXPECTED_SIZE - 1, "%s.%s" % [id, key]
			)
		for bank: int in pokedex["entry_banks"]:
			assert_between(
				bank * RomFile.BANK_SIZE, 0, RomRegistry.EXPECTED_SIZE - 1,
				"%s bank %d" % [id, bank]
			)


## constants/cry_constants.asm runs CRY_NIDORAN_M through CRY_DONPHAN
## inclusive, so NUM_CRIES is 68. A count of 67 dropped CRY_DONPHAN, which is
## the cry species 232 asks for and the last entry before the SFX table.
func test_the_cry_table_carries_every_cry_constant() -> void:
	assert_eq(RomLayout.AUDIO_CRY_COUNT, 68)
	for id: StringName in RomRegistry.ORDER:
		var layout: Dictionary = RomLayout.for_id(id)
		var last: int = int(layout["cry_pointers"]) \
			+ (RomLayout.AUDIO_CRY_COUNT - 1) * RomLayout.AUDIO_POINTER_SIZE
		assert_lt(last + RomLayout.AUDIO_POINTER_SIZE, RomRegistry.EXPECTED_SIZE, "%s" % id)
