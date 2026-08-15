extends GutTest

## Builds its own cache and reads it back. Nothing here opens a cartridge: the
## point of the cache is that the engine never needs one, so its reader has to
## be testable without one too.

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"testgame", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


## A cache with two species, one of each other table, and a 2x2-cell atlas.
func _write_cache(complete: bool = true) -> void:
	RomCache.write_json(RomCache.species_path(_directory), [
		_species(1, "BULBASAUR", 0x1234, 0x5678),
		_species(2, "IVYSAUR", 0x0C63, 0x1084),
	])
	RomCache.write_json(RomCache.moves_path(_directory), [
		{"number": 1, "name": "POUND", "power": 40, "type": 0, "accuracy": 255, "pp": 35},
	])
	RomCache.write_json(RomCache.items_path(_directory), [{"number": 1, "name": "MASTER BALL"}])
	RomCache.write_json(RomCache.types_path(_directory), [
		{"number": 0, "name": "NORMAL"}, {"number": 1, "name": "FIGHTING"},
	])
	RomCache.write_json(RomCache.matchups_path(_directory), [
		_matchup(0x14, 0x16, RomLayout.MATCHUP_SUPER_EFFECTIVE),
		_matchup(0x17, 0x04, RomLayout.MATCHUP_NO_EFFECT),
		_matchup(0x16, 0x16, RomLayout.MATCHUP_NOT_VERY_EFFECTIVE),
		_matchup(0x16, 0x14, RomLayout.MATCHUP_NOT_VERY_EFFECTIVE),
		_matchup(0x14, 0x09, RomLayout.MATCHUP_SUPER_EFFECTIVE),
		_matchup(RomLayout.TYPE_NORMAL, RomLayout.TYPE_GHOST, RomLayout.MATCHUP_NO_EFFECT, true),
	])
	RomCache.write_json(RomCache.trainers_path(_directory), [
		{
			"number": 1, "name": "LEADER", "palette": [0x1234, 0x5678],
			"attributes": {
				"item1": 0, "item2": 0, "base_reward": 25,
				"ai_move_weights": RomLayout.AI_BASIC | RomLayout.AI_STATUS,
				"ai_item_switch": RomLayout.CONTEXT_USE | RomLayout.SWITCH_SOMETIMES,
			},
				"dvs": 0x9A77,
			"trainers": [
				{
					"name": "FALKNER", "type": RomLayout.TRAINER_MON_NORMAL,
					"party": [
						{"level": 7, "species": 1, "item": 0, "moves": []},
						{"level": 9, "species": 2, "item": 0, "moves": []},
					],
				},
				{
					"name": "PICKY", "type": RomLayout.TRAINER_MON_ITEM_MOVES,
					"party": [{"level": 20, "species": 1, "item": 5, "moves": [1, 0, 0, 0]}],
				},
			],
		},
		{"number": 2, "name": "YOUNGSTER", "palette": [0x0C63, 0x1084], "trainers": []},
	])
	RomCache.write_indices(RomCache.pic_path(_directory, "front"), PackedByteArray([
		0, 0, 1, 1,
		0, 0, 1, 1,
		2, 2, 3, 3,
		2, 2, 3, 3,
	]))
	RomCache.write_indices(
		RomCache.tile_path(_directory, "font"), PackedByteArray([0, 3, 3, 0])
	)
	RomCache.write_json(RomCache.world_menus_path(_directory), {
		"5:7000": {"bank": 5, "address": 0x7000, "options": ["A", "B"]},
	})
	RomCache.write_json(RomCache.world_marts_path(_directory), {
		"marts": [{"index": 0, "items": [1, 2]}],
		"default": {"items": [3]}, "special": {},
	})
	RomCache.write_json(RomCache.world_phone_path(_directory), {
		"contacts": [{"index": 0, "trainer_class": 1}],
		"special_calls": [{"index": 0, "contact": 1}],
	})
	RomCache.write_json(RomCache.world_audio_path(_directory), {
		"music": [{"index": 0, "bank": 1, "address": 0x4000}],
		"sfx": [{"index": 0, "bank": 2, "address": 0x4000}],
	})
	RomCache.write_json(RomCache.dex_orders_path(_directory), {
		"new": _dex_order(true), "alpha": _dex_order(false),
	})
	_write_battle_anims()
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testgame",
		"sha1": "0123456789abcdef",
		"species_count": 2,
		"atlases": {
			"front": {"width": 4, "height": 4, "cell": 2, "columns": 2, "decoded": 2},
			"back": {"width": 4, "height": 4, "cell": 2, "columns": 2, "decoded": 2},
			"trainers": {"width": 4, "height": 2, "cell": 2, "columns": 2, "decoded": 2},
		},
		"tiles": {
			"font": {"width": 2, "height": 2, "tiles": 1, "first_code": 0x80},
		},
		"battle_object_palettes": _battle_object_palettes(),
		"complete": complete,
	})


## Two animation regions, the way the importer writes them: a pointer table with
## its bodies immediately after it, addressed by the region's own base.
##
## The script region holds two entries, one at $4004 and one at $4005, and the
## bodies are `anim_ret` and `anim_inc_var, anim_ret`. The object region is one
## `battleanimobj` row.
const _ANIM_BASE: int = 0x4000
const _ANIM_BANK: int = 0x32


func _write_battle_anims() -> void:
	RomCache.write_section(
		RomCache.battle_anims_path(_directory),
		RomCache.blob_path(RomCache.battle_anims_path(_directory)),
		{
			"scripts": {
				"bank": _ANIM_BANK, "address": _ANIM_BASE, "count": 2,
				"bytes": [0x04, 0x40, 0x05, 0x40, 0xFF, 0xFA, 0xFF],
			},
			"objects": {
				"bank": _ANIM_BANK, "address": _ANIM_BASE, "count": 1,
				"bytes": [0x01, 0xFF, 0x02, 0x03, 0x04, 0x05],
			},
			"object_gfx": [
				{"tiles": 0, "bank": 0x21, "address": 0x4A2E, "sheet": false},
				{"tiles": 1, "bank": 0x21, "address": 0x4A2E, "sheet": true},
			],
		}
	)
	RomCache.write_indices(
		RomCache.battle_anim_gfx_path(_directory, 1), _blank_tile()
	)


## `BattleObjectPals` verbatim, since the accessor's whole job is to hand the
## cartridge's own colours back unchanged.
func _battle_object_palettes() -> Dictionary:
	var out: Dictionary = {}
	for index: int in RomLayout.BATTLE_OBJECT_PALETTES_STORED:
		out[RomLayout.BATTLE_OBJECT_PALETTE_NAMES[index]] = \
			RomLayout.BATTLE_OBJECT_PALETTES[index]
	return out


func _blank_tile() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(Gen2Tiles.TILE_PIXELS)
	return out


## A full-length order table, since GameData drops one that is not: the two
## differ only in direction, which is enough to tell them apart.
func _dex_order(forward: bool) -> Array:
	var out: Array = []
	for number: int in range(1, RomLayout.SPECIES_COUNT + 1):
		out.append(number if forward else RomLayout.SPECIES_COUNT + 1 - number)
	return out


func _matchup(
	attacker: int, defender: int, multiplier: int, foresight: bool = false
) -> Dictionary:
	return {
		"attacker": attacker,
		"defender": defender,
		"multiplier": multiplier,
		"negated_by_foresight": foresight,
	}


func _species(number: int, name: String, normal: int, shiny: int) -> Dictionary:
	return {
		"number": number,
		"name": name,
		"stats": {"hp": 45, "attack": 49},
		"types": [0, 3],
		"front_tiles": [1, 1],
		"palette": {"normal": [normal, normal], "shiny": [shiny, shiny]},
		# Both halves of one cartridge table, cached on the species that owns them.
		"evolutions": [] if number != 1 else [{
			"method": RomLayout.EVOLVE_LEVEL, "parameter": 16, "condition": 0, "target": 2,
		}],
		"learnset": [{"level": 1, "move": 33}, {"level": 4, "move": 45}],
		"dex": {
			"category": "SEED",
			"height": 204,
			"weight": 150,
			"pages": ["page one", "page two"],
		},
	}


func test_a_complete_cache_opens() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_not_null(data)
	assert_eq(data.species_count(), 2)
	# Moves are counted like species and trainer classes, so a mod walking every
	# one does not have to scan 1 to 255 and keep what answers.
	assert_eq(data.move_count(), 1)


func test_an_incomplete_cache_does_not_open() -> void:
	# An interrupted import must not be read as if it were a finished one.
	_write_cache(false)
	assert_null(GameData.open_directory(_directory))


func test_a_missing_cache_does_not_open() -> void:
	assert_null(GameData.open_directory("user://nothing_here"))


## A cache written by an older importer is discarded rather than migrated, which
## is what a format bump is for. Written against the version rather than a
## number so the next bump does not have to edit this.
func test_a_cache_from_an_older_format_does_not_open() -> void:
	_write_cache()
	var manifest: Dictionary = RomCache.read_manifest(_directory)
	manifest["format_version"] = RomCache.FORMAT_VERSION - 1
	RomCache.write_json(RomCache.manifest_path(_directory), manifest)
	assert_null(GameData.open_directory(_directory))


func test_numbers_come_back_as_ints_not_floats() -> void:
	# JSON has one number type. Coercing here, once, is the whole reason this
	# class exists rather than callers reading the JSON themselves.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var move: Dictionary = data.move(1)
	assert_eq(int(move["power"]), 40)
	assert_true(data.atlas("front")["cell"] is int, "atlas metadata is coerced")


func test_lookups_are_by_number_not_position() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(String(data.species(2)["name"]), "IVYSAUR")
	assert_eq(data.item_name(1), "MASTER BALL")
	assert_eq(String(data.move(1)["name"]), "POUND")


func test_types_are_indexed_from_zero() -> void:
	# Unlike every other table: NORMAL is type $00.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.type_name(0), "NORMAL")
	assert_eq(data.type_name(1), "FIGHTING")


func test_world_service_records_are_read_from_the_cache() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.world_menu(5, 0x7000)["options"], ["A", "B"])
	assert_eq(data.world_mart(0)["items"], [1, 2])
	assert_eq(data.world_mart(99)["items"], [3])
	assert_eq(data.world_phone_contact(0)["trainer_class"], 1)
	assert_eq(data.world_special_phone_call(0)["contact"], 1)
	assert_eq(data.world_audio_pointer(&"music", 1, 0x4000)["index"], 0)
	assert_eq(data.world_service_counts(), {
		"menus": 1, "marts": 1, "phone_contacts": 1, "music": 1, "sfx": 1, "cries": 0,
	})


## A region comes back with its bank and address, so an in-bank pointer resolves
## by subtraction, and its bytes come out of the section blob rather than the
## JSON.
func test_a_battle_anim_region_carries_its_own_base_address() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var region: Dictionary = data.battle_anim_region(&"scripts")
	assert_eq(int(region["bank"]), _ANIM_BANK)
	assert_eq(int(region["address"]), _ANIM_BASE)
	assert_eq(int(region["count"]), 2)
	assert_eq((region["data"] as PackedByteArray).size(), 7)
	assert_true(data.battle_anim_region(&"nothing").is_empty())


## The pointer table is the first bytes of the scripts region rather than a copy
## beside it, which is what makes a cached address and the bytes it names one
## thing.
func test_a_battle_anim_address_is_read_out_of_the_region_itself() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.battle_anim_address(0), 0x4004)
	assert_eq(data.battle_anim_address(1), 0x4005)
	assert_eq(data.battle_anim_address(2), -1, "past the table")
	assert_eq(data.battle_anim_address(-1), -1)

	var region: Dictionary = data.battle_anim_region(&"scripts")
	var script := Gen2BattleAnimScript.create(
		region["data"], int(region["address"]), data.battle_anim_address(1)
	)
	var ran: Array = script.advance_frame()
	assert_eq(ran.size(), 2)
	assert_eq(ran[1]["name"], Gen2BattleAnimScript.RET)
	assert_eq(script.variable(), 1)
	assert_true(script.finished())


func test_a_battle_anim_object_row_reads_back_as_ints() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.battle_anim_object(0), {
		"flags": 1, "y_fix": 0xFF, "frameset": 2, "function": 3, "palette": 4, "gfx": 5,
	})
	assert_true(data.battle_anim_object(1).is_empty(), "past the table")


## Only the rows that name graphics have a sheet: index 0 is the slot no
## `anim_*gfx` reaches, and the two `NULL` rows belong to the battler-graphics
## commands.
func test_only_the_rows_with_graphics_carry_a_sheet() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.battle_anim_gfx_count(), 2)
	assert_false(bool(data.battle_anim_gfx(0)["sheet"]))
	assert_eq(data.battle_anim_gfx(1), {
		"tiles": 1, "bank": 0x21, "address": 0x4A2E, "sheet": true,
	})
	assert_eq(data.battle_anim_gfx_indices(1).size(), Gen2Tiles.TILE_PIXELS)
	assert_true(data.battle_anim_gfx(2).is_empty())


## Six of the eight object palettes are table rows; the first two are whoever is
## on the field, which is why they are passed in rather than looked up.
func test_the_first_two_object_palettes_come_from_the_battlers() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var enemy: Array = [0x1234, 0x5678]
	var player: Array = [0x0C63, 0x1084]
	assert_eq(data.battle_object_palette(0, enemy, player)[1], Gen2Palette.from_packed(0x1234))
	assert_eq(data.battle_object_palette(1, enemy, player)[1], Gen2Palette.from_packed(0x0C63))
	# Without a pair there is nothing to draw with, so it falls back rather than
	# reading the table's first row and colouring the mon wrong.
	assert_eq(data.battle_object_palette(0), Gen2Palette.pic_palette(
		PackedColorArray([Color.WHITE, Color.BLACK])
	))


func test_a_stored_object_palette_is_four_colours() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var gray: PackedColorArray = data.battle_object_palette(
		RomLayout.BATTLE_OBJECT_PALETTE_FIRST_STORED
	)
	assert_eq(gray.size(), RomLayout.BATTLE_OBJECT_PALETTE_COLORS)
	assert_eq(gray[0], Gen2Palette.from_packed(0x7FFF))
	assert_ne(gray, data.battle_object_palette(RomLayout.BATTLE_OBJECT_PALETTE_COUNT - 1))
	assert_eq(
		data.battle_object_palette(RomLayout.BATTLE_OBJECT_PALETTE_COUNT).size(),
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK])).size(),
		"a ninth palette falls back rather than reading past the table"
	)


func test_a_matchup_the_chart_does_not_list_is_neutral() -> void:
	# The chart holds only the exceptions, which is why the whole of Generation 2
	# fits in 332 bytes. Everything else is ten tenths.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.type_matchup(0x14, 0x16), RomLayout.MATCHUP_SUPER_EFFECTIVE)
	assert_eq(data.type_matchup(0x17, 0x04), RomLayout.MATCHUP_NO_EFFECT)
	assert_eq(data.type_matchup(0x14, 0x15), RomLayout.MATCHUP_EFFECTIVE, "not in the chart")
	assert_eq(data.type_matchup(0x13, 0x13), RomLayout.MATCHUP_EFFECTIVE, "nor is Curse's type")


func test_foresight_cancels_the_ghost_immunities_and_nothing_else() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(
		data.type_matchup(RomLayout.TYPE_NORMAL, RomLayout.TYPE_GHOST),
		RomLayout.MATCHUP_NO_EFFECT
	)
	assert_eq(
		data.type_matchup(RomLayout.TYPE_NORMAL, RomLayout.TYPE_GHOST, true),
		RomLayout.MATCHUP_EFFECTIVE
	)
	assert_eq(
		data.type_matchup(0x17, 0x04, true), RomLayout.MATCHUP_NO_EFFECT,
		"Foresight does not make a Ground type hittable by Electric"
	)


func test_two_types_truncate_between_them() -> void:
	# The quirk this returns tenths for. Grass is resisted by both halves of a
	# Grass/Fire defender, and the cartridge's accumulator reports 2, not 2.5:
	# ten to five to two, truncating on the way.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.type_effectiveness(0x16, [0x16, 0x14]), 2)


func test_a_single_type_defender_is_not_hit_twice() -> void:
	# A Pokémon with one type carries it in both slots. The cartridge applies a
	# row once whichever slot matched it.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.type_effectiveness(0x14, [0x16, 0x16]), RomLayout.MATCHUP_SUPER_EFFECTIVE)


func test_an_immunity_beats_a_weakness_whichever_way_round_they_are() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.type_effectiveness(RomLayout.TYPE_NORMAL, [RomLayout.TYPE_GHOST, 0x16]), 0)


func test_a_cache_with_no_chart_reads_everything_as_neutral() -> void:
	# A cache from before there was a chart, or an import that stopped short. The
	# engine gets a flat answer rather than a wrong one.
	_write_cache()
	DirAccess.remove_absolute(RomCache.matchups_path(_directory))
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.type_matchup(0x14, 0x16), RomLayout.MATCHUP_EFFECTIVE)


func test_an_unknown_number_answers_empty_rather_than_failing() -> void:
	# A mod may well ask for something that is not there.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_true(data.species(0).is_empty())
	assert_true(data.species(999).is_empty())
	assert_eq(data.item_name(999), "")
	assert_eq(data.type_name(-1), "")


func test_a_palette_is_four_colours_with_white_and_black_implied() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var palette: PackedColorArray = data.palette(1)
	assert_eq(palette.size(), Gen2Palette.COLORS_PER_PIC)
	assert_eq(palette[0], Color.WHITE)
	assert_eq(palette[3], Color.BLACK)


func test_shiny_is_a_different_palette_and_the_same_pixels() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_ne(data.palette(1, true), data.palette(1, false))


func test_a_species_pic_reports_its_own_size_not_the_cell_size() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var pic: Dictionary = data.species_pic(1)
	assert_eq(pic["slot"], 0, "slots are zero-based, species numbers are not")
	assert_eq(pic["width"], Gen2Tiles.TILE_WIDTH, "one tile, not the two-tile cell")


func test_back_pics_always_fill_their_cell() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.species_pic(1, true)["width"], 2)


func test_unown_forms_come_from_their_own_atlas() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	# There is no Unown in this two-species cache, so the answer is empty
	# rather than a lie about slot 0 of an atlas that was never written.
	assert_true(data.unown_pic(0).is_empty())


func test_trainer_classes_are_numbered_from_the_first_class_not_the_player() -> void:
	# The cartridge's palette table opens with the player, who has no pic. The
	# cache does not carry that entry, so class 1 is the first row here.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.trainer_count(), 2)
	assert_eq(data.trainer_name(1), "LEADER")
	assert_eq(data.trainer_pic(1)["slot"], 0)


func test_a_trainer_palette_has_no_shiny_half() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var palette: PackedColorArray = data.trainer_palette(1)
	assert_eq(palette.size(), Gen2Palette.COLORS_PER_PIC)
	assert_eq(palette[0], Color.WHITE)
	assert_ne(palette, data.trainer_palette(2))


func test_a_trainer_pic_always_fills_its_cell() -> void:
	# Every trainer is drawn at one size, unlike a species front pic.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var pic: Dictionary = data.trainer_pic(2)
	assert_eq(pic["width"], 2)
	assert_eq(pic["height"], 2)


func test_an_unknown_trainer_class_answers_empty() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_true(data.trainer(0).is_empty(), "class 0 is the player, who has no entry")


func test_a_trainer_classs_own_trainers_are_counted_and_read_back() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.trainer_party_count(1), 2)
	assert_eq(data.trainer_party_count(2), 0, "the one class this cache gives no party")

	var falkner: Dictionary = data.trainer_party(1, 0)
	assert_eq(falkner["name"], "FALKNER")
	assert_eq(falkner["type"], RomLayout.TRAINER_MON_NORMAL)
	assert_eq((falkner["party"] as Array).size(), 2)
	assert_eq(int(falkner["party"][1]["level"]), 9, "JSON's one number type, coerced back")
	assert_eq(int(falkner["party"][1]["species"]), 2)


func test_a_trainer_classs_own_attributes_read_back_as_ints() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var attributes: Dictionary = data.trainer_attributes(1)
	assert_eq(int(attributes["base_reward"]), 25, "JSON's one number type, coerced back")
	assert_eq(int(attributes["ai_move_weights"]), RomLayout.AI_BASIC | RomLayout.AI_STATUS)
	assert_eq(
		int(attributes["ai_item_switch"]), RomLayout.CONTEXT_USE | RomLayout.SWITCH_SOMETIMES
	)
	assert_true(data.trainer_attributes(0).is_empty(), "class 0 is the player, who has no entry")


func test_a_trainer_classs_own_dvs_read_back_as_an_int() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.trainer_dvs(1), 0x9A77, "JSON's one number type, coerced back")
	assert_eq(
		data.trainer_dvs(2), Gen2BattleMon.PERFECT_DVS,
		"class 2 has an entry but no dvs key, the same shape an unimported field takes"
	)
	assert_eq(data.trainer_dvs(0), Gen2BattleMon.PERFECT_DVS, "class 0 is the player, no entry at all")


func test_a_stored_moves_trainers_item_and_moves_read_back_as_ints() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var picky: Dictionary = data.trainer_party(1, 1)
	var mon: Dictionary = picky["party"][0]
	assert_eq(int(mon["item"]), 5)
	assert_eq(mon["moves"], [1, 0, 0, 0])


func test_an_out_of_range_trainer_party_index_answers_empty() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_true(data.trainer_party(1, 2).is_empty())
	assert_true(data.trainer_party(1, -1).is_empty())
	assert_true(data.trainer_pic(99).is_empty())
	assert_eq(data.trainer_name(99), "")


func test_index_buffers_are_read_once_and_kept() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var first: PackedByteArray = data.atlas_indices("front")
	assert_eq(first.size(), 16)
	assert_eq(data.atlas_indices("front"), first)


func test_a_tile_sheet_is_read_back_coerced_and_kept() -> void:
	# The font and the borders are not pics, so they have their own accessor and
	# their own directory in the cache; only the reading-once part is shared.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var sheet: Dictionary = data.tile_sheet("font")
	assert_eq(sheet["first_code"], 0x80)
	assert_true(sheet["tiles"] is int)
	assert_eq(data.tile_indices("font").size(), 4)
	assert_eq(data.tile_indices("font"), data.tile_indices("font"))


func test_a_tile_sheet_that_was_never_written_reads_as_empty() -> void:
	# An import that stopped before the font, or a cache from before there was
	# one. The renderer asks and gets nothing rather than a wrong answer.
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_true(data.tile_sheet("frames").is_empty())
	assert_eq(data.tile_indices("frames"), PackedByteArray())


func test_an_atlas_that_was_never_written_reads_as_empty() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_true(data.atlas("nothing").is_empty())
	assert_eq(data.atlas_indices("back"), PackedByteArray())


func test_a_learnset_comes_back_in_the_cartridges_order_as_ints() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var learnset: Array = data.learnset(1)
	assert_eq(learnset.size(), 2)
	assert_true(learnset[0]["level"] is int, "JSON gives a float back and the engine wants an int")
	assert_eq(learnset[0], {"level": 1, "move": 33})
	assert_eq(learnset[1], {"level": 4, "move": 45})


func test_a_species_with_no_learnset_answers_with_nothing() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.learnset(99), [])
	assert_eq(data.evolutions(99), [])
	assert_eq(data.moves_at_level(99, 50), [])


func test_evolutions_come_back_coerced_and_only_where_there_are_any() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var evolutions: Array = data.evolutions(1)
	assert_eq(evolutions.size(), 1)
	assert_true(evolutions[0]["method"] is int)
	assert_eq(int(evolutions[0]["method"]), RomLayout.EVOLVE_LEVEL)
	assert_eq(int(evolutions[0]["target"]), 2)
	assert_eq(data.evolutions(2), [], "the second species does not evolve")


func test_a_species_knows_what_its_level_says_it_knows() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.moves_at_level(1, 1), [33], "the move at level 4 is not learned yet")
	assert_eq(data.moves_at_level(1, 4), [33, 45])


## The dex entry travels on the species, so a number with no species has none.
func test_a_dex_entry_comes_back_with_its_numbers_coerced() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	var entry: Dictionary = data.dex_entry(1)
	assert_eq(String(entry["category"]), "SEED")
	assert_eq(int(entry["height"]), 204)
	assert_eq(int(entry["weight"]), 150)
	assert_eq(Array(entry["pages"] as PackedStringArray), ["page one", "page two"])
	assert_true(data.dex_entry(999).is_empty(), "no species, no entry")


func test_both_dex_order_tables_come_back_as_species_numbers() -> void:
	_write_cache()
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.dex_order_new().size(), RomLayout.SPECIES_COUNT)
	assert_eq(data.dex_order_new()[0], 1)
	assert_eq(data.dex_order_alpha()[0], RomLayout.SPECIES_COUNT)


## A table that is not the full species range would list a species number of
## zero, which the listing treats as its end, so it is dropped whole.
func test_a_short_dex_order_table_is_dropped() -> void:
	_write_cache()
	RomCache.write_json(RomCache.dex_orders_path(_directory), {"new": [1, 2, 3]})
	var data: GameData = GameData.open_directory(_directory)
	assert_true(data.dex_order_new().is_empty())
