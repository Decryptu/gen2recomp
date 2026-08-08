extends GutTest

## The editor's whole promise is that an edited save still loads, so most of
## these assert the invariant rather than the field: level and experience agree,
## HP stays under a recomputed maximum, move slots stay contiguous.
##
## Party and box editing use the synthetic battle cache. World editing asserts
## the state it changes directly, because that fixture has no maps and a world
## snapshot only validates against a cartridge that does.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _editor: Gen2SaveEditor = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"savetest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_editor = Gen2SaveEditor.open(_source_save(), _data)


func after_each() -> void:
	_editor = null
	RomCache.clear(_directory)


func _source_save() -> Gen2SaveData:
	var pikachu: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 20, [Fixture.TACKLE, Fixture.THUNDERBOLT],
		Gen2BattleMon.PERFECT_DVS
	)
	return Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, 0, Gen2Party.create([pikachu]), "RED"
	)


func _first() -> Gen2SaveMon:
	return _editor.save.party[0]


func _with_world() -> Gen2SaveEditor:
	_editor.save.world = Gen2WorldSnapshot.new()
	return _editor


func test_opening_takes_a_working_copy() -> void:
	var source: Gen2SaveData = _source_save()
	var editor: Gen2SaveEditor = Gen2SaveEditor.open(source, _data)

	assert_true(editor.set_player_name("ASH")["ok"])
	assert_eq(source.player_name, "RED", "the original is untouched until commit")


func test_opening_without_a_save_or_cache_answers_null() -> void:
	assert_null(Gen2SaveEditor.open(null, _data))
	assert_null(Gen2SaveEditor.open(_source_save(), null))


func test_a_fresh_editor_is_clean_and_valid() -> void:
	assert_false(_editor.is_dirty())
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_an_edit_marks_the_editor_dirty() -> void:
	assert_true(_editor.set_player_name("ASH")["ok"])
	assert_true(_editor.is_dirty())


func test_an_empty_or_overlong_player_name_is_refused() -> void:
	assert_false(_editor.set_player_name("   ")["ok"])
	assert_false(_editor.set_player_name("ABCDEFGHIJK")["ok"])
	assert_eq(_editor.save.player_name, "RED")


func test_setting_a_level_moves_experience_onto_the_curve() -> void:
	assert_true(_editor.set_level(_first(), 50)["ok"])

	var growth: int = int(_data.species(Fixture.PIKACHU)["growth_rate"])
	assert_eq(_first().level, 50)
	assert_eq(_first().exp, Gen2Experience.total_exp_at(growth, 50))
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_an_out_of_range_level_is_refused_rather_than_clamped() -> void:
	assert_false(_editor.set_level(_first(), 0)["ok"])
	assert_false(_editor.set_level(_first(), Gen2Experience.MAX_LEVEL + 1)["ok"])
	assert_eq(_first().level, 20)


func test_lowering_the_level_pulls_current_hp_under_the_new_maximum() -> void:
	assert_true(_editor.set_level(_first(), 100)["ok"])
	assert_true(_editor.set_hp(_first(), _editor.max_hp_for(_first()))["ok"])
	var high_hp: int = _first().hp

	assert_true(_editor.set_level(_first(), 5)["ok"])
	assert_lt(_first().hp, high_hp)
	assert_eq(_first().hp, _editor.max_hp_for(_first()))
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_changing_species_re_runs_experience_on_the_new_growth_curve() -> void:
	assert_true(_editor.set_species(_first(), Fixture.GEODUDE)["ok"])

	var growth: int = int(_data.species(Fixture.GEODUDE)["growth_rate"])
	assert_eq(_first().species, Fixture.GEODUDE)
	assert_eq(_first().exp, Gen2Experience.total_exp_at(growth, _first().level))
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_an_unknown_species_is_refused() -> void:
	assert_false(_editor.set_species(_first(), 9999)["ok"])
	assert_eq(_first().species, Fixture.PIKACHU)


func test_hp_is_clamped_to_the_computed_maximum() -> void:
	assert_true(_editor.set_hp(_first(), 99999)["ok"])
	assert_eq(_first().hp, _editor.max_hp_for(_first()))

	assert_true(_editor.set_hp(_first(), -5)["ok"])
	assert_eq(_first().hp, 0)


func test_a_learned_move_arrives_at_full_pp() -> void:
	assert_true(_editor.set_move(_first(), 2, Fixture.GROWL)["ok"])

	assert_eq(_first().moves[2], Fixture.GROWL)
	assert_eq(_first().pp[2], int(_data.move(Fixture.GROWL)["pp"]))
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_clearing_a_move_pulls_the_later_ones_forward() -> void:
	assert_true(_editor.set_move(_first(), 2, Fixture.GROWL)["ok"])
	assert_true(_editor.set_move(_first(), 0, Gen2SaveEditor.NO_MOVE)["ok"])

	assert_eq(_first().moves[0], Fixture.THUNDERBOLT)
	assert_eq(_first().moves[1], Fixture.GROWL)
	assert_eq(_first().moves[2], Gen2SaveEditor.NO_MOVE)
	assert_eq(_first().pp[2], 0, "a cleared slot keeps no PP")
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_a_move_cannot_be_written_after_a_gap() -> void:
	assert_false(_editor.set_move(_first(), 3, Fixture.GROWL)["ok"])
	assert_eq(_first().moves[3], Gen2SaveEditor.NO_MOVE)


func test_an_unknown_move_is_refused() -> void:
	assert_false(_editor.set_move(_first(), 0, 9999)["ok"])
	assert_eq(_first().moves[0], Fixture.TACKLE)


func test_pp_is_clamped_to_the_moves_own_maximum() -> void:
	assert_true(_editor.set_pp(_first(), 0, 999)["ok"])
	assert_eq(_first().pp[0], int(_data.move(Fixture.TACKLE)["pp"]))


func test_pp_on_an_empty_slot_is_refused() -> void:
	assert_false(_editor.set_pp(_first(), 3, 5)["ok"])


func test_dvs_are_clamped_per_component() -> void:
	assert_true(_editor.set_dvs(_first(), 99, -3, 7, 15)["ok"])

	assert_eq(Gen2Stats.attack_dv(_first().dvs), Gen2Stats.MAX_DV)
	assert_eq(Gen2Stats.defense_dv(_first().dvs), 0)
	assert_eq(Gen2Stats.speed_dv(_first().dvs), 7)
	assert_eq(Gen2Stats.special_dv(_first().dvs), 15)
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_lowering_dvs_pulls_hp_under_the_new_maximum() -> void:
	assert_true(_editor.set_hp(_first(), _editor.max_hp_for(_first()))["ok"])
	assert_true(_editor.set_dvs(_first(), 0, 0, 0, 0)["ok"])

	assert_eq(_first().hp, _editor.max_hp_for(_first()))
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_stat_experience_is_clamped_and_named() -> void:
	assert_true(_editor.set_stat_exp(_first(), "attack", 999999)["ok"])
	assert_eq(int(_first().stat_exp["attack"]), Gen2Stats.MAX_STAT_EXP)
	assert_false(_editor.set_stat_exp(_first(), "charisma", 1)["ok"])


func test_an_impossible_status_combination_is_refused() -> void:
	assert_true(_editor.set_status(_first(), Gen2Status.BURN)["ok"])
	assert_false(
		_editor.set_status(_first(), Gen2Status.BURN | Gen2Status.FREEZE)["ok"],
		"two major statuses at once cannot exist",
	)
	assert_eq(_first().status, Gen2Status.BURN)


func test_an_unknown_held_item_is_refused() -> void:
	assert_false(_editor.set_held_item(_first(), 9999)["ok"])
	assert_true(_editor.set_held_item(_first(), 0)["ok"], "no item is always allowed")


func test_adding_a_party_member_creates_a_legal_one() -> void:
	assert_true(_editor.add_party_member(Fixture.GEODUDE, 15)["ok"])

	assert_eq(_editor.save.party.size(), 2)
	var added: Gen2SaveMon = _editor.save.party[1]
	assert_eq(added.species, Fixture.GEODUDE)
	assert_eq(added.level, 15)
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_a_full_party_refuses_another_member() -> void:
	for _index: int in Gen2SaveData.MAX_PARTY - 1:
		assert_true(_editor.add_party_member(Fixture.GEODUDE, 5)["ok"])

	assert_eq(_editor.save.party.size(), Gen2SaveData.MAX_PARTY)
	assert_false(_editor.add_party_member(Fixture.GEODUDE, 5)["ok"])


func test_removing_the_last_member_leaves_a_legal_empty_party() -> void:
	assert_true(_editor.remove_party_member(0)["ok"])

	assert_eq(_editor.save.party.size(), 0)
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_removing_a_member_that_is_not_there_is_refused() -> void:
	assert_false(_editor.remove_party_member(4)["ok"])


func test_reordering_the_party_keeps_both_members() -> void:
	assert_true(_editor.add_party_member(Fixture.GEODUDE, 15)["ok"])
	assert_true(_editor.move_party_member(1, 0)["ok"])

	assert_eq((_editor.save.party[0] as Gen2SaveMon).species, Fixture.GEODUDE)
	assert_eq((_editor.save.party[1] as Gen2SaveMon).species, Fixture.PIKACHU)
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])


func test_a_box_member_is_added_and_removed() -> void:
	assert_true(_editor.add_box_member(0, Fixture.GEODUDE, 12)["ok"])
	assert_eq(_editor.box(0).occupied_count(), 1)
	assert_true(_editor.validate()["ok"], _editor.validate()["message"])

	assert_true(_editor.remove_box_member(0, 0)["ok"])
	assert_eq(_editor.box(0).occupied_count(), 0)


func test_a_box_that_does_not_exist_is_refused() -> void:
	assert_null(_editor.box(Gen2SaveData.BOX_COUNT))
	assert_false(_editor.add_box_member(Gen2SaveData.BOX_COUNT, Fixture.GEODUDE, 5)["ok"])


func test_removing_an_empty_box_slot_is_refused() -> void:
	assert_false(_editor.remove_box_member(0, 0)["ok"])


func test_committing_writes_the_slot_and_clears_dirty() -> void:
	assert_true(_editor.set_player_name("ASH")["ok"])
	var result: Dictionary = _editor.commit()
	assert_true(result["ok"], result["message"])
	assert_false(_editor.is_dirty())

	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(loaded["ok"], loaded["message"])
	assert_eq((loaded["save"] as Gen2SaveData).player_name, "ASH")

	Gen2SaveStore.delete_slot(_data.id, _data.sha1, 0)


# --- World ------------------------------------------------------------------


func test_a_save_with_no_world_refuses_every_world_edit() -> void:
	assert_false(_editor.has_world())
	assert_false(_editor.set_item_quantity(1, 5)["ok"])
	assert_false(_editor.set_money(0, 100)["ok"])
	assert_false(_editor.set_coins(10)["ok"])
	assert_false(_editor.set_event_flag(3, true)["ok"])
	assert_false(_editor.set_engine_flag(3, true)["ok"])
	assert_false(_editor.set_seen_species(Fixture.PIKACHU, true)["ok"])
	assert_false(_editor.set_clock(1, 2, 3)["ok"])
	assert_null(_editor.inventory())


func test_money_and_coins_are_clamped_to_source_ceilings() -> void:
	var editor: Gen2SaveEditor = _with_world()

	assert_true(editor.set_money(0, 999999999)["ok"])
	assert_eq(editor.save.world.world_state.money(0), Gen2WorldInventory.MAX_MONEY)

	assert_true(editor.set_coins(999999)["ok"])
	assert_eq(editor.save.world.world_state.coins(), Gen2WorldInventory.MAX_COINS)


func test_an_unknown_bag_item_is_refused() -> void:
	assert_false(_with_world().set_item_quantity(9999, 3)["ok"])


func test_event_and_engine_flags_are_set_and_cleared() -> void:
	var editor: Gen2SaveEditor = _with_world()
	var state: Gen2WorldState = editor.save.world.world_state

	assert_true(editor.set_event_flag(12, true)["ok"])
	assert_true(state.is_event_flag_active(12))
	assert_true(editor.set_event_flag(12, false)["ok"])
	assert_false(state.is_event_flag_active(12))

	assert_true(editor.set_engine_flag(Gen2WorldState.ENGINE_ZEPHYRBADGE, true)["ok"])
	assert_true(state.is_engine_flag_active(Gen2WorldState.ENGINE_ZEPHYRBADGE))


func test_a_negative_flag_number_is_refused() -> void:
	var editor: Gen2SaveEditor = _with_world()
	assert_false(editor.set_event_flag(-1, true)["ok"])
	assert_false(editor.set_engine_flag(-1, true)["ok"])


## The badge engine flags differ between the profiles, so the list follows the
## save's own game rather than a single hardcoded set.
func test_badge_flags_follow_the_saves_own_profile() -> void:
	var editor: Gen2SaveEditor = _with_world()
	editor.save.game_id = RomRegistry.CRYSTAL
	assert_eq(editor.badge_flags(), Gen2WorldState.BADGE_ENGINE_FLAGS)

	editor.save.game_id = RomRegistry.GOLD
	assert_eq(editor.badge_flags(), Gen2WorldState.BADGE_ENGINE_FLAGS_GOLD_SILVER)


func test_seen_species_is_recorded_and_cleared() -> void:
	var editor: Gen2SaveEditor = _with_world()
	var state: Gen2WorldState = editor.save.world.world_state

	assert_true(editor.set_seen_species(Fixture.PIKACHU, true)["ok"])
	assert_true(state.has_seen_species(Fixture.PIKACHU))

	assert_true(editor.set_seen_species(Fixture.PIKACHU, false)["ok"])
	assert_false(state.has_seen_species(Fixture.PIKACHU))
	assert_false(
		state.seen_species().has(Fixture.PIKACHU),
		"clearing drops the entry rather than storing false",
	)


func test_an_unknown_species_cannot_be_marked_seen() -> void:
	assert_false(_with_world().set_seen_species(9999, true)["ok"])


func test_the_clock_is_clamped_to_its_own_ranges() -> void:
	var editor: Gen2SaveEditor = _with_world()
	assert_true(editor.set_clock(99, 99, 99)["ok"])

	assert_eq(editor.save.world.world_day, Gen2WorldClock.DAYS_PER_WEEK - 1)
	assert_eq(editor.save.world.world_hour, Gen2WorldClock.HOURS_PER_DAY - 1)
	assert_eq(editor.save.world.world_minute, Gen2WorldClock.MINUTES_PER_HOUR - 1)


## The cache behind these tests has no maps at all, which is exactly the case
## that must be refused rather than written into a save that then will not load.
func test_moving_the_player_to_a_map_the_cache_lacks_is_refused() -> void:
	var editor: Gen2SaveEditor = _with_world()
	var before: Vector2i = editor.save.world.player_cell

	assert_false(editor.set_player_position(Vector2i(24, 4), Vector2i(3, 3))["ok"])
	assert_eq(editor.save.world.player_cell, before)
