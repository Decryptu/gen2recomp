extends GutTest

## World state has a JSON-safe representation independent of the map cache.


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
