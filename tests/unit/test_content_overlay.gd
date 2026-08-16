extends GutTest

## The overlay is reached the way a mod reaches it, through Gen2ModHost, and read
## the way the engine reads it, through a real GameData built over a real cache.
## Nothing here knows a mod exists once the content is registered, which is the
## whole point of putting it at GameData's own chokepoint.

const MOD: StringName = &"testmod"
const NEW_SPECIES: int = Gen2ContentOverlay.FIRST_MOD_NUMBER
const NEW_MOVE: int = Gen2ContentOverlay.FIRST_MOD_NUMBER + 1

var _directory: String = ""


func before_each() -> void:
	Gen2ModHost.reset()
	_directory = RomCache.directory_for(&"overlaygame", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)
	Gen2ModHost.reset()


func _write_cache() -> void:
	RomCache.write_json(RomCache.species_path(_directory), [{
		"number": 1, "name": "BULBASAUR",
		"stats": {"hp": 45, "attack": 49, "defense": 49, "speed": 45,
			"sp_attack": 65, "sp_defense": 65},
		"types": [0, 3], "front_tiles": [7, 7],
		"palette": {"normal": [0x1234, 0x1234], "shiny": [0x5678, 0x5678]},
		"evolutions": [], "learnset": [{"level": 1, "move": 33}],
	}])
	RomCache.write_json(RomCache.moves_path(_directory), [
		{"number": 1, "name": "POUND", "power": 40, "type": 0, "accuracy": 255, "pp": 35},
	])
	RomCache.write_json(RomCache.items_path(_directory), [
		{"number": 1, "name": "MASTER BALL", "price": 0},
	])
	RomCache.write_json(RomCache.types_path(_directory), [{"number": 0, "name": "NORMAL"}])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [
		{"number": 1, "name": "LEADER", "palette": [0x1234, 0x5678], "trainers": []},
	])
	RomCache.write_json(RomCache.world_trades_path(_directory), [])
	RomCache.write_json(RomCache.world_encounters_path(_directory), {
		"grass": {"3:2": {
			"map": "3:2", "region": "johto", "rate": 4, "rates": [4, 4, 4],
			"slots": [[{"level": 2, "species": 16}], [], []],
		}},
		"water": {},
		"fishing": {
			"groups": [{"rods": []}],
			"time_groups": [{
				"day": {"species": 0xDE, "level": 20},
				"night": {"species": 0x78, "level": 20},
			}],
		},
		"treemons": {
			"tree_maps": [{"map_group": 3, "map_number": 2, "set": 1}],
			"rock_maps": [],
			"sets": [
				{"common": [], "rare": []},
				{
					"common": [{"percent": 50, "species": 10, "level": 10}],
					"rare": [{"percent": 50, "species": 11, "level": 12}],
				},
			],
		},
		"bug_contest": {
			"mons": [{"percent": 20, "species": 10, "min_level": 7, "max_level": 18}],
			"contestants": [],
		},
		"roaming": {
			"maps": [],
			"mons": [{"species": 243, "level": 40, "map_group": 3, "map_number": 2}],
		},
	})
	RomCache.write_json(RomCache.tmhm_moves_path(_directory), [1])
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "overlaygame",
		"sha1": "0123456789abcdef",
		"atlases": {
			"front": {"width": 56, "height": 56, "cell": 56, "columns": 1, "decoded": 1},
			"back": {"width": 56, "height": 56, "cell": 56, "columns": 1, "decoded": 1},
		},
		"tiles": {},
		"complete": true,
	})


func _data() -> GameData:
	return GameData.open_directory(_directory)


func test_a_defined_species_reads_back_like_a_cartridge_one() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.register_content(
		Gen2ContentOverlay.KIND_SPECIES, MOD, NEW_SPECIES, {
			"name": "VOLTLING",
			"stats": {"speed": 200},
			"types": [0, 0],
			"learnset": [{"level": 1, "move": 1}, {"level": 7, "move": 2}],
			"evolutions": [{
				"method": RomLayout.EVOLVE_LEVEL, "parameter": 16, "condition": 0, "target": 1,
			}],
		}
	).get("ok", false)))

	var data: GameData = _data()
	var entry: Dictionary = data.species(NEW_SPECIES)
	assert_eq(String(entry["name"]), "VOLTLING")
	assert_eq(int(entry["number"]), NEW_SPECIES)
	# A partial stats block keeps the defaults it did not name, so nothing
	# downstream divides by a missing HP.
	assert_eq(int(entry["stats"]["speed"]), 200)
	assert_eq(int(entry["stats"]["hp"]), 1)
	# Everything a species carries rides on the same row, so the learnset and
	# evolution readers answer without knowing a mod defined this one.
	assert_eq(data.moves_at_level(NEW_SPECIES, 10).size(), 2)
	assert_eq(int(data.evolutions(NEW_SPECIES)[0]["target"]), 1)
	# And the fields a reader indexes directly are always there.
	assert_eq(data.palette(NEW_SPECIES).size(), 4)
	assert_false(data.species_pic(NEW_SPECIES).is_empty())


func test_a_patch_changes_named_fields_and_leaves_the_rest() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.patch_content(
		Gen2ContentOverlay.KIND_SPECIES, MOD, 1, {"stats": {"speed": 200}}
	).get("ok", false)))
	assert_true(bool(host.patch_content(
		Gen2ContentOverlay.KIND_MOVE, MOD, 1, {"power": 250}
	).get("ok", false)))

	var data: GameData = _data()
	assert_eq(int(data.species(1)["stats"]["speed"]), 200)
	assert_eq(int(data.species(1)["stats"]["hp"]), 45, "an unnamed stat is untouched")
	assert_eq(String(data.species(1)["name"]), "BULBASAUR")
	assert_eq(int(data.move(1)["power"]), 250)


func test_a_patch_does_not_invent_a_row_this_cartridge_lacks() -> void:
	# Crystal has a trainer class Gold does not. A mod patching it must change
	# nothing on the game that never had it, rather than conjure one.
	assert_true(bool(Gen2ModHost.instance().patch_content(
		Gen2ContentOverlay.KIND_TRAINER, MOD, 40, {"name": "GHOST"}
	).get("ok", false)))
	assert_true(_data().trainer(40).is_empty())


func test_cartridge_numbers_and_mod_numbers_keep_their_own_side() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_eq(
		StringName(host.register_content(
			Gen2ContentOverlay.KIND_SPECIES, MOD, 25, {"name": "NOTPIKACHU"}
		)["reason"]),
		&"reserved_content_number"
	)
	assert_eq(
		StringName(host.patch_content(
			Gen2ContentOverlay.KIND_SPECIES, MOD, NEW_SPECIES, {"name": "X"}
		)["reason"]),
		&"not_a_cartridge_number"
	)
	assert_eq(
		StringName(host.register_content(&"pokeblock", MOD, NEW_SPECIES, {})["reason"]),
		&"unknown_content_kind"
	)


func test_two_mods_claiming_one_number_is_refused_rather_than_decided_by_load_order() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.register_content(
		Gen2ContentOverlay.KIND_MOVE, MOD, NEW_MOVE, {"name": "FIRST"}
	).get("ok", false)))
	var second: Dictionary = host.register_content(
		Gen2ContentOverlay.KIND_MOVE, &"othermod", NEW_MOVE, {"name": "SECOND"}
	)
	assert_eq(StringName(second["reason"]), &"duplicate_content")
	assert_eq(String(_data().move(NEW_MOVE)["name"]), "FIRST")
	# The same mod refining its own registration is not a conflict.
	assert_true(bool(host.register_content(
		Gen2ContentOverlay.KIND_MOVE, MOD, NEW_MOVE, {"name": "AGAIN"}
	).get("ok", false)))


func test_a_cache_with_no_mods_reads_exactly_what_the_cartridge_held() -> void:
	var data: GameData = _data()
	assert_eq(String(data.species(1)["name"]), "BULBASAUR")
	assert_true(data.species(NEW_SPECIES).is_empty())
	assert_true(Gen2ContentOverlay.shared().is_empty())


func test_resetting_the_host_drops_what_the_last_load_registered() -> void:
	Gen2ModHost.instance().register_content(
		Gen2ContentOverlay.KIND_ITEM, MOD, Gen2ContentOverlay.FIRST_MOD_NUMBER, {"name": "THING"}
	)
	assert_eq(String(_data().item(Gen2ContentOverlay.FIRST_MOD_NUMBER)["name"]), "THING")
	Gen2ModHost.reset()
	assert_true(_data().item(Gen2ContentOverlay.FIRST_MOD_NUMBER).is_empty())


func test_the_overlay_names_who_claimed_what() -> void:
	Gen2ModHost.instance().register_content(
		Gen2ContentOverlay.KIND_SPECIES, MOD, NEW_SPECIES, {"name": "VOLTLING"}
	)
	var overlay: Gen2ContentOverlay = Gen2ModHost.instance().content_overlay()
	assert_eq(overlay.defined_numbers(Gen2ContentOverlay.KIND_SPECIES), [NEW_SPECIES] as Array[int])
	assert_eq(overlay.owner_of(Gen2ContentOverlay.KIND_SPECIES, NEW_SPECIES), MOD)


func test_an_encounter_row_is_patched_where_the_cartridge_table_is_read() -> void:
	# The single most wanted thing a randomizer does, and it has to arrive at
	# GameData's own chokepoint so nothing downstream learns a mod exists.
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.patch_encounter(MOD, &"grass", 3, 2, {
		"rate": 20, "slots": [[{"level": 50, "species": 1}], [], []],
	}).get("ok", false)))

	var data: GameData = _data()
	var row: Dictionary = data.world_encounter(&"grass", 3, 2)
	assert_eq(int(row["rate"]), 20)
	assert_eq(int(row["slots"][0][0]["species"]), 1, "an array field replaces whole")
	assert_eq(row["rates"], [4.0, 4.0, 4.0], "an unnamed field is untouched")
	# FindNest walks the region table rather than one map, and reads the same
	# patched row.
	var rows: Array = data.world_encounter_region_rows(&"grass", "johto")
	assert_eq(int(rows[0]["rate"]), 20)
	# A map this cartridge lacks, and a method that is not one, change nothing.
	assert_true(data.world_encounter(&"grass", 9, 9).is_empty())
	assert_eq(
		StringName(host.patch_encounter(MOD, &"headbutt", 3, 2, {"rate": 1})["reason"]),
		&"unknown_encounter_method"
	)


func test_a_fishing_group_is_patched_by_its_own_group_number() -> void:
	assert_true(bool(Gen2ModHost.instance().patch_fishing_group(
		MOD, 1, {"rods": [{"level": 10, "species": 129}]}
	).get("ok", false)))
	var groups: Array = _data().world_fishing_group(1)["rods"]
	assert_eq(int(groups[0]["species"]), 129)
	assert_true(_data().world_fishing_group(9).is_empty())


func test_a_table_kind_is_patched_and_never_defined() -> void:
	# There is no map or map header a mod can add, so there is no row for a
	# definition to sit at.
	assert_eq(
		StringName(Gen2ModHost.instance().register_content(
			Gen2ContentOverlay.KIND_ENCOUNTER, MOD, NEW_SPECIES, {}
		)["reason"]),
		&"content_kind_is_patch_only"
	)


## The four wild sources beside the map tables. Each is patched by its own index
## and each keeps the field a patch did not name, which is the whole point: a
## contest row's percent is its scoring weight and a roamer's map is live state.
func test_the_four_other_wild_sources_are_patched_by_index() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.patch_treemon_set(MOD, 1, {
		"common": [{"percent": 50, "species": 1, "level": 3}],
	}).get("ok", false)))
	assert_true(bool(host.patch_bug_contest_mon(MOD, 0, {"species": 2}).get("ok", false)))
	assert_true(bool(host.patch_roaming_mon(MOD, 0, {"species": 3}).get("ok", false)))
	assert_true(bool(host.patch_fishing_time_group(MOD, 0, {
		"night": {"species": 4, "level": 20},
	}).get("ok", false)))

	var data: GameData = _data()
	var set_one: Dictionary = data.treemon_set(1)
	assert_eq(int(set_one["common"][0]["species"]), 1)
	assert_eq(int(set_one["rare"][0]["species"]), 11, "the rare table is untouched")

	var contest: Array = data.bug_contest_mons()
	assert_eq(int(contest[0]["species"]), 2)
	assert_eq(int(contest[0]["percent"]), 20, "the contest's own weight survives")
	assert_eq(int(contest[0]["max_level"]), 18)

	var roaming: Array = data.world_roaming_mons()
	assert_eq(int(roaming[0]["species"]), 3)
	assert_eq(int(roaming[0]["map_group"]), 3, "where it is now is not a patch")
	assert_eq(int(roaming[0]["level"]), 40)

	var times: Array = data.world_fishing_time_groups()
	assert_eq(int(times[0]["night"]["species"]), 4)
	assert_eq(int(times[0]["day"]["species"]), 0xDE, "the day half is untouched")

	## Every one is a table row, so none of them can be DEFINED.
	for kind: StringName in [
		Gen2ContentOverlay.KIND_TREEMON, Gen2ContentOverlay.KIND_BUG_CONTEST,
		Gen2ContentOverlay.KIND_ROAMING, Gen2ContentOverlay.KIND_FISHING_TIME,
	]:
		assert_eq(
			StringName(host.register_content(kind, MOD, NEW_SPECIES, {})["reason"]),
			&"content_kind_is_patch_only", String(kind)
		)


## `clear_owner` is what a save switch spends: everything one mod claimed goes,
## and the numbers are free for the next run to claim again.
func test_clearing_one_owner_leaves_the_cartridge_row_and_frees_the_number() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.patch_bug_contest_mon(MOD, 0, {"species": 2}).get("ok", false)))
	assert_eq(int(_data().bug_contest_mons()[0]["species"]), 2)
	Gen2ContentOverlay.shared().clear_owner(MOD)
	assert_eq(int(_data().bug_contest_mons()[0]["species"]), 10)
	assert_eq(Gen2ContentOverlay.shared().owner_of(Gen2ContentOverlay.KIND_BUG_CONTEST, 0), &"")
	assert_true(bool(host.patch_bug_contest_mon(&"other", 0, {"species": 5}).get("ok", false)))
	assert_eq(int(_data().bug_contest_mons()[0]["species"]), 5)


## A catalog site is patched by the stable id the catalog gave it, and only the
## fields named move. The decode itself is checked on real cartridges by
## `tools/checks/catalog.gd`; what is here is the patch surface.
func test_a_catalog_site_is_patched_by_its_own_id() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var id: int = Gen2WorldCatalog.pack_id(Gen2WorldCatalog.KIND_STATIC, 48, 0x6E00)
	assert_true(bool(host.patch_check(MOD, id, {"species": 25}).get("ok", false)))
	assert_eq(
		Gen2ContentOverlay.shared().resolve(
			Gen2ContentOverlay.KIND_CHECK, id, {"species": 109, "level": 21}
		),
		{"species": 25, "level": 21},
		"the level a patch did not name is the cartridge's"
	)
	assert_eq(host.patch_check(MOD, -1, {"species": 1})["reason"], &"not_a_check_id")
	assert_eq(
		StringName(host.register_content(
			Gen2ContentOverlay.KIND_CHECK, MOD, NEW_SPECIES, {}
		)["reason"]),
		&"content_kind_is_patch_only"
	)


## Two mods cannot both move one site, and the refusal names both.
func test_two_mods_cannot_claim_one_catalog_site() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var id: int = Gen2WorldCatalog.pack_id(Gen2WorldCatalog.KIND_GIFT, 30, 0x4C62)
	assert_true(bool(host.patch_check(MOD, id, {"species": 1}).get("ok", false)))
	var second: Dictionary = host.patch_check(&"other", id, {"species": 2})
	assert_false(second["ok"])
	assert_eq(second["reason"], &"duplicate_content")
	assert_string_contains(String(second["detail"]), String(MOD))


## An id is the byte a site lives at, so the two spaces cannot collide and an
## event site is not a script site.
func test_a_catalog_id_names_a_kind_a_bank_and_an_address() -> void:
	var script_id: int = Gen2WorldCatalog.pack_id(Gen2WorldCatalog.KIND_ITEM, 48, 0x6E04)
	var event_id: int = Gen2WorldCatalog.pack_event_id(Gen2WorldCatalog.KIND_ITEM, 48, 0x6E, 4)
	assert_ne(script_id, event_id)
	assert_ne(
		script_id,
		Gen2WorldCatalog.pack_id(Gen2WorldCatalog.KIND_BADGE, 48, 0x6E04),
		"the kind is part of the id"
	)
	assert_eq(Gen2WorldCatalog.pack_id(&"not_a_kind", 1, 1), -1)
