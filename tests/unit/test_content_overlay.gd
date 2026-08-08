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
