extends GutTest

## World state has a JSON-safe representation independent of the map cache.

## ENGINE_FLYPOINT_VERMILION's Crystal index (constants/engine_flags.asm). Named
## here rather than on Gen2WorldState because nothing in game/ reads a flypoint;
## the story walk does, and it holds Crystal indices.
const FLYPOINT_VERMILION: int = 58


func test_world_state_round_trips_persistent_overworld_fields() -> void:
	var state := Gen2WorldState.new(
		{7: true}, {"1:2": 4}, {3: 8}, {0: 120}, 17, {9: true},
		6, Vector2i(1, 2), 0xDF,
		[{"species": 0xF3, "level": 40, "map_group": 1, "map_number": 2}], true,
		0, Gen2WorldState.PHONE_RECEIVE_DELAYS[0], 0, {16: true}
	)
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_true(restored.is_event_flag_active(7))
	assert_eq(restored.map_scene(1, 2), 4)
	assert_eq(restored.item_quantity(3), 8)
	assert_eq(restored.money(), 120)
	assert_eq(restored.coins(), 17)
	assert_true(restored.has_phone_contact(9))
	assert_eq(restored.repel_steps(), 6)
	assert_eq(restored.swarm_map(), Vector2i(1, 2))
	assert_eq(restored.fishing_swarm_species(), 0xDF)
	assert_true(restored.just_battled())
	assert_true(restored.has_seen_species(16))
	assert_eq(restored.roaming_mons().size(), 1)


## `wPCItems` is its own array, so it round-trips beside the bag rather than
## inside it. A state written before the item PC existed has no key at all,
## which restores as an empty PC.
func test_pc_items_round_trip_beside_the_bag() -> void:
	var state := Gen2WorldState.new({}, {}, {3: 8})
	assert_true(bool(state.apply_changes({}, {}, {"pc_items": {3: 2, 9: 1}})["ok"]))
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.item_quantity(3), 8)
	assert_eq(restored.pc_item_quantity(3), 2)
	assert_eq(restored.pc_item_quantity(9), 1)
	var without: Dictionary = state.to_dict()
	without.erase("pc_items")
	assert_eq(Gen2WorldState.from_dict(without).pc_items().size(), 0)
	assert_eq(
		state.apply_changes({}, {}, {"pc_items": {0: 1}})["reason"],
		&"invalid_pc_item_quantity"
	)


func test_maptile_decorations_round_trip_and_validate_categories() -> void:
	var state := Gen2WorldState.new()
	assert_true(state.set_maptile_decoration(&"bed", 0x02))
	assert_true(state.set_maptile_decoration(&"poster", 0x10))
	assert_false(state.set_maptile_decoration(&"unknown", 1))
	assert_false(state.set_maptile_decoration(&"bed", 0x100))
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.maptile_decoration(&"bed"), 0x02)
	assert_eq(restored.maptile_decoration(&"poster"), 0x10)
	assert_eq(restored.maptile_decoration(&"plant"), 0)


func test_engine_flags_round_trip_and_daily_reset_preserves_hall_of_fame() -> void:
	var state := Gen2WorldState.new()
	state.set_hall_of_fame()
	var changed: Dictionary = state.apply_changes({}, {}, {
		"engine_flags": {
			Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED: true,
		},
	})
	assert_true(changed["ok"])
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_true(restored.hall_of_fame())
	assert_true(restored.bargain_merchant_closed())
	assert_true(restored.reset_daily_flags())
	assert_true(restored.hall_of_fame())
	assert_false(restored.bargain_merchant_closed())
	assert_false(restored.reset_daily_flags())


func test_badge_count_matches_active_flags_across_both_bytes() -> void:
	var state := Gen2WorldState.new()
	assert_eq(state.badge_count(), 0)
	state.set_engine_flag(Gen2WorldState.ENGINE_ZEPHYRBADGE)
	assert_eq(state.badge_count(), 1)
	for flag: int in Gen2WorldState.BADGE_ENGINE_FLAGS:
		state.set_engine_flag(flag)
	assert_eq(state.badge_count(), 16)
	## wBadges is one contiguous flag_array spanning both wJohtoBadges and
	## wKantoBadges, so a Kanto badge must count toward the same total.
	var kanto_only := Gen2WorldState.new()
	kanto_only.set_engine_flag(Gen2WorldState.ENGINE_EARTHBADGE)
	assert_eq(kanto_only.badge_count(), 1)


func test_badge_mask_follows_source_order_on_both_profiles() -> void:
	var crystal := Gen2WorldState.new()
	crystal.set_engine_flag(Gen2WorldState.ENGINE_ZEPHYRBADGE)
	crystal.set_engine_flag(Gen2WorldState.ENGINE_EARTHBADGE)
	assert_eq(crystal.badge_mask(), (1 << 0) | (1 << 15))

	var gold := Gen2WorldState.new()
	gold.set_engine_flag(Gen2WorldState.ENGINE_ZEPHYRBADGE - 1)
	gold.set_engine_flag(Gen2WorldState.ENGINE_EARTHBADGE - 1)
	assert_eq(gold.badge_mask(false), (1 << 0) | (1 << 15))


## BIKEFLAGS_STRENGTH_ACTIVE_F sits three flags ahead of ENGINE_ZEPHYRBADGE, so
## it carries the same one-index profile shift the badges do, and it must not be
## confused with a badge in either direction.
func test_strength_active_flag_is_profile_split_and_is_not_a_badge() -> void:
	assert_eq(Gen2WorldState.strength_active_flag(true), 24)
	assert_eq(Gen2WorldState.strength_active_flag(false), 23)
	assert_eq(
		Gen2WorldState.strength_active_flag(true),
		Gen2WorldState.badge_flag(0, true) - 3
	)
	assert_eq(
		Gen2WorldState.strength_active_flag(false),
		Gen2WorldState.badge_flag(0, false) - 3
	)

	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.strength_active_flag(true))
	assert_true(state.is_engine_flag_active(Gen2WorldState.strength_active_flag(true)))
	assert_false(state.is_engine_flag_active(Gen2WorldState.strength_active_flag(false)))
	assert_eq(state.badge_count(true), 0)
	assert_eq(state.badge_count(false), 0)


## Nothing in the pinned engine/ or home/ ever clears BIKEFLAGS_STRENGTH_ACTIVE_F,
## and engine flags serialize with the world snapshot, so the flag has to outlive
## a round trip and the map-reload reset that clears temporary event flags.
func test_strength_active_flag_survives_round_trip_and_map_reload() -> void:
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.strength_active_flag(true))
	state.set_event_flag(0, true)

	var restored: Gen2WorldState = Gen2WorldState.from_dict(state.to_dict())
	assert_true(restored.is_engine_flag_active(Gen2WorldState.strength_active_flag(true)))
	restored.reset_map_reload_flags()
	assert_true(restored.is_engine_flag_active(Gen2WorldState.strength_active_flag(true)))
	assert_false(restored.is_event_flag_active(0))


## pokegold's engine flag table has no ENGINE_MOBILE_SYSTEM entry ahead of the
## badge section, so every pokegold badge sits one index lower than the same
## symbol in pokecrystal's constants/engine_flags.asm. A Crystal-numbered
## ENGINE_ZEPHYRBADGE write must not count as a Gold/Silver badge, and a
## Gold/Silver-numbered write (one lower) must not count as a Crystal badge.
func test_badge_count_uses_the_gold_silver_table_when_requested() -> void:
	## Index 42 (ENGINE_EARTHBADGE) is the Crystal table's Kanto endpoint and
	## falls outside the Gold/Silver table (26-41), so it isolates the
	## Crystal-only end of the one-index shift.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_EARTHBADGE)
	assert_eq(state.badge_count(true), 1)
	assert_eq(state.badge_count(false), 0)

	## Index 26 (ENGINE_ZEPHYRBADGE - 1) is the Gold/Silver table's Johto
	## endpoint and falls outside the Crystal table (27-42), isolating the
	## Gold/Silver-only end.
	var gold_state := Gen2WorldState.new()
	gold_state.set_engine_flag(Gen2WorldState.ENGINE_ZEPHYRBADGE - 1)
	assert_eq(gold_state.badge_count(false), 1)
	assert_eq(gold_state.badge_count(true), 0)

	for flag: int in Gen2WorldState.BADGE_ENGINE_FLAGS_GOLD_SILVER:
		gold_state.set_engine_flag(flag)
	assert_eq(gold_state.badge_count(false), 16)


## Same one-index shift for the Goldenrod Underground merchant flag: pinned
## pokecrystal has it at 86, pinned pokegold at 85.
func test_bargain_merchant_closed_uses_the_gold_silver_flag_when_requested() -> void:
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED)
	assert_true(state.bargain_merchant_closed(true))
	assert_false(state.bargain_merchant_closed(false))

	var gold_state := Gen2WorldState.new()
	gold_state.set_engine_flag(
		Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED_GOLD_SILVER
	)
	assert_true(gold_state.bargain_merchant_closed(false))
	assert_false(gold_state.bargain_merchant_closed(true))


func test_reset_daily_flags_clears_the_matching_profiles_merchant_flag_only() -> void:
	var gold_state := Gen2WorldState.new()
	gold_state.set_engine_flag(
		Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED_GOLD_SILVER
	)
	assert_false(gold_state.reset_daily_flags(true))
	assert_true(gold_state.bargain_merchant_closed(false))
	assert_true(gold_state.reset_daily_flags(false))
	assert_false(gold_state.bargain_merchant_closed(false))


## CheckDailyResetTimer zeroes the whole wDailyFlags1 byte, so Kurt's flag goes
## with the merchant's. Without it he never finishes a ball.
func test_reset_daily_flags_clears_kurts_flag_on_both_profiles() -> void:
	for crystal: bool in [true, false]:
		var state := Gen2WorldState.new()
		var flag: int = Gen2WorldState.engine_flag(
			Gen2WorldState.ENGINE_KURT_MAKING_BALLS, crystal
		)
		state.set_engine_flag(flag)
		assert_false(state.reset_daily_flags(not crystal))
		assert_true(state.is_engine_flag_active(flag))
		assert_true(state.reset_daily_flags(crystal))
		assert_false(state.is_engine_flag_active(flag))


func test_the_saved_kurt_quantity_survives_a_snapshot_round_trip() -> void:
	var state := Gen2WorldState.new()
	state.set_kurt_apricorn_quantity(7)
	var restored: Gen2WorldState = Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.kurt_apricorn_quantity(), 7)
	## Absent in a state written before the errand existed, and zero is what a
	## fresh SelectApricornForKurt writes anyway.
	assert_eq(Gen2WorldState.from_dict({}).kurt_apricorn_quantity(), 0)


## Gen2WorldState.is_crystal_profile mirrors
## Gen2WorldScriptRunner._crystal_commands(): only a verified Gold or Silver
## cache is treated as the shorter engine flag table.
func test_is_crystal_profile_matches_the_game_id_and_defaults_true_for_no_data() -> void:
	assert_true(Gen2WorldState.is_crystal_profile(null))
	var crystal_data := GameData.new()
	crystal_data.id = &"crystal"
	assert_true(Gen2WorldState.is_crystal_profile(crystal_data))
	var gold_data := GameData.new()
	gold_data.id = &"gold"
	assert_false(Gen2WorldState.is_crystal_profile(gold_data))
	var silver_data := GameData.new()
	silver_data.id = &"silver"
	assert_false(Gen2WorldState.is_crystal_profile(silver_data))


## engine_flag() is the same one-index shift the named *_GOLD_SILVER constants
## spell out, for a caller holding a Crystal index and no pair. The three named
## pairs are what pin the shift's direction here: a derived answer that
## disagreed with any of them would be wrong in the same way twice.
func test_engine_flag_maps_a_crystal_index_onto_the_gold_silver_table() -> void:
	for index: int in [0, 3, 4, 15, Gen2WorldState.ENGINE_MOBILE_SYSTEM - 1]:
		assert_eq(Gen2WorldState.engine_flag(index, true), index)
		assert_eq(Gen2WorldState.engine_flag(index, false), index)

	## ENGINE_MOBILE_SYSTEM is the entry pokegold does not ship, so it maps onto
	## nothing there; -1 is what is_engine_flag_active() reads as inactive.
	assert_eq(
		Gen2WorldState.engine_flag(Gen2WorldState.ENGINE_MOBILE_SYSTEM, true),
		Gen2WorldState.ENGINE_MOBILE_SYSTEM
	)
	assert_eq(
		Gen2WorldState.engine_flag(Gen2WorldState.ENGINE_MOBILE_SYSTEM, false), -1
	)

	for pair: Array in [
		[Gen2WorldState.ENGINE_ROCKETS_IN_RADIO_TOWER,
			Gen2WorldState.ENGINE_ROCKETS_IN_RADIO_TOWER_GOLD_SILVER],
		[Gen2WorldState.ENGINE_STRENGTH_ACTIVE,
			Gen2WorldState.ENGINE_STRENGTH_ACTIVE_GOLD_SILVER],
		[Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED,
			Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED_GOLD_SILVER],
	]:
		assert_eq(Gen2WorldState.engine_flag(pair[0], true), pair[0])
		assert_eq(Gen2WorldState.engine_flag(pair[0], false), pair[1])

	for badge: int in Gen2WorldState.BADGE_ENGINE_FLAGS.size():
		assert_eq(
			Gen2WorldState.engine_flag(Gen2WorldState.badge_flag(badge, true), false),
			Gen2WorldState.badge_flag(badge, false)
		)

	## The read a caller actually makes: a Crystal index resolved on the Gold
	## table must find a Gold write and miss a Crystal one.
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.engine_flag(FLYPOINT_VERMILION, false))
	assert_true(state.is_engine_flag_active(
		Gen2WorldState.engine_flag(FLYPOINT_VERMILION, false)
	))
	assert_false(state.is_engine_flag_active(
		Gen2WorldState.engine_flag(FLYPOINT_VERMILION, true)
	))


func test_badge_flags_survive_round_trip_and_daily_or_map_reload_resets() -> void:
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_ZEPHYRBADGE)
	state.set_engine_flag(Gen2WorldState.ENGINE_HIVEBADGE)
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.badge_count(), 2)
	restored.reset_daily_flags()
	assert_eq(restored.badge_count(), 2)
	restored.reset_map_reload_flags()
	assert_eq(restored.badge_count(), 2)


func test_source_temporary_event_flags_include_zero_and_reset_on_map_reload() -> void:
	var state := Gen2WorldState.new()
	state.set_event_flag(0)
	state.set_event_flag(7)
	state.set_event_flag(8)
	assert_true(state.is_event_flag_active(0))
	assert_true(state.is_event_flag_active(7))
	assert_true(state.is_event_flag_active(8))
	assert_true(state.reset_map_reload_flags())
	assert_false(state.is_event_flag_active(0))
	assert_false(state.is_event_flag_active(7))
	assert_true(state.is_event_flag_active(8))
	assert_false(state.reset_map_reload_flags())


func test_invalid_engine_flag_transaction_does_not_mutate_state() -> void:
	var state := Gen2WorldState.new()
	var failed: Dictionary = state.apply_changes({}, {}, {
		"engine_flags": {-1: true},
	})
	assert_false(failed["ok"])
	assert_false(state.hall_of_fame())
	assert_false(state.bargain_merchant_closed())


func test_world_state_rejects_invalid_swarm_transaction_without_mutation() -> void:
	var state := Gen2WorldState.new()
	var failed: Dictionary = state.apply_changes({}, {}, {
		"swarm": {"active": true, "map_group": 1, "map_number": 1, "fishing_species": 99},
	})
	assert_false(failed["ok"])
	assert_eq(state.swarm_map(), Vector2i(-1, -1))
	assert_eq(state.fishing_swarm_species(), 0)


func test_phone_timer_and_pending_special_call_round_trip() -> void:
	var state := Gen2WorldState.new()
	assert_eq(state.phone_receive_cycle(), 0)
	assert_eq(state.phone_receive_minutes(), 20)
	assert_false(state.advance_phone_receive_timer(19))
	assert_eq(state.phone_receive_minutes(), 1)
	assert_true(state.advance_phone_receive_timer(1))
	assert_true(state.phone_receive_ready())
	assert_true(state.consume_phone_receive_timer())
	assert_eq(state.phone_receive_cycle(), 1)
	assert_eq(state.phone_receive_minutes(), 10)
	var changed: Dictionary = state.apply_changes({}, {}, {
		"pending_special_phone_call": 6,
	})
	assert_true(changed["ok"])
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.pending_special_phone_call(), 6)
	assert_eq(restored.phone_receive_cycle(), 1)
	assert_eq(restored.phone_receive_minutes(), 10)


func test_phone_contact_transaction_enforces_the_cartridge_capacity() -> void:
	var state := Gen2WorldState.new()
	var contacts: Dictionary = {}
	for contact: int in Gen2WorldState.PHONE_CONTACT_CAPACITY:
		contacts[contact] = true
	var accepted: Dictionary = state.apply_changes({}, {}, {"phone_contacts": contacts})
	assert_true(accepted["ok"])
	var rejected: Dictionary = state.apply_changes({}, {}, {"phone_contacts": {10: true}})
	assert_false(rejected["ok"])
	assert_eq(state.phone_contact_count(), Gen2WorldState.PHONE_CONTACT_CAPACITY)


func test_seen_species_changes_round_trip_and_commit_atomically() -> void:
	var state := Gen2WorldState.new()
	var changed: Dictionary = state.apply_changes({}, {}, {"seen_species": {25: true}})
	assert_true(changed["ok"])
	assert_true(state.has_seen_species(25))
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_true(restored.has_seen_species(25))


## readmem/writemem/loadmem address plain WRAM bytes; only a bounded handful
## carry script state, so the state keeps them as an address-keyed byte map.
func test_script_memory_round_trips_and_rejects_out_of_range_bytes() -> void:
	var state := Gen2WorldState.new()
	assert_eq(state.script_memory(0xD1D6), 0, "an address never written reads zero")
	var changed: Dictionary = state.apply_changes({}, {}, {"script_memory": {0xD1D6: 7}})
	assert_true(changed["ok"])
	assert_eq(state.script_memory(0xD1D6), 7)
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.script_memory(0xD1D6), 7)

	var cleared: Dictionary = state.apply_changes({}, {}, {"script_memory": {0xD1D6: 0}})
	assert_true(cleared["ok"])
	assert_eq(state.script_memory(0xD1D6), 0)
	assert_false(state.script_memory_values().has(0xD1D6))

	for rejected: Dictionary in [{0xD1D6: 256}, {0xD1D6: -1}, {0: 3}]:
		var result: Dictionary = state.apply_changes({}, {}, {"script_memory": rejected})
		assert_false(result["ok"], JSON.stringify(rejected))
		assert_eq(result["reason"], &"invalid_script_memory")
	assert_eq(state.script_memory(0xD1D6), 0, "a refused transaction mutates nothing")


## InitRoamMons seeds the roam structs, and Gen2WorldAPI.open() seeds the same
## imported records, so re-seeding must not teleport a beast already loose.
func test_seeding_roaming_mons_keeps_a_record_that_already_moved() -> void:
	var initial: Array = [{"species": 243, "level": 40, "map_group": 1, "map_number": 1}]
	var state := Gen2WorldState.new()
	state.ensure_roaming_mons(initial)
	assert_eq(state.roaming_mons(), initial)

	var moved: Array = [{"species": 243, "level": 40, "map_group": 5, "map_number": 9}]
	var loose: Gen2WorldState = Gen2WorldState.from_dict({"roaming_mons": moved})
	loose.ensure_roaming_mons(initial)
	assert_eq(loose.roaming_mons(), moved)


## A missing schedule stream must be a no-op, because creating and randomizing
## a generator here makes save-state movement depend on an invisible source.
func test_roaming_does_not_roll_without_an_injected_generator() -> void:
	var state := Gen2WorldState.new()
	var initial: Array = [{"species": 243, "level": 40, "map_group": 1, "map_number": 1}]
	state.ensure_roaming_mons(initial)
	var rows: Array = [{
		"map_group": 1,
		"map_number": 1,
		"connections": [{"map_group": 1, "map_number": 2}],
	}]

	assert_eq(state.advance_roaming(rows), [])
	assert_eq(state.roaming_mons(), initial)


## `wLastDexMode` sits in the saved player data, so it survives a snapshot the
## way the radio knob beside it does.
func test_the_last_dex_mode_round_trips() -> void:
	var state := Gen2WorldState.new()
	assert_eq(state.last_dex_mode(), RomLayout.DEXMODE_NEW, "a fresh state opens on NEW")
	state.set_last_dex_mode(RomLayout.DEXMODE_ABC)
	var restored := Gen2WorldState.from_dict(state.to_dict())
	assert_eq(restored.last_dex_mode(), RomLayout.DEXMODE_ABC)


## DEXMODE_UNOWN is the Unown dex rather than a listing order, and never becomes
## wCurDexMode, so it is refused rather than stored.
func test_the_unown_dex_is_not_a_listing_mode() -> void:
	var state := Gen2WorldState.new()
	state.set_last_dex_mode(RomLayout.DEXMODE_UNOWN)
	assert_eq(state.last_dex_mode(), RomLayout.DEXMODE_NEW)
