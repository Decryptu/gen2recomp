extends GutTest

## World state has a JSON-safe representation independent of the map cache.


func test_world_state_round_trips_persistent_overworld_fields() -> void:
	var state := Gen2WorldState.new(
		{7: true}, {"1:2": 4}, {3: 8}, {0: 120}, 17, {9: true},
		6, Vector2i(1, 2), 0xDF,
		[{"species": 0xF3, "level": 40, "map_group": 1, "map_number": 2}], true
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
	assert_eq(restored.roaming_mons().size(), 1)


func test_world_state_rejects_invalid_swarm_transaction_without_mutation() -> void:
	var state := Gen2WorldState.new()
	var failed: Dictionary = state.apply_changes({}, {}, {
		"swarm": {"active": true, "map_group": 1, "map_number": 1, "fishing_species": 99},
	})
	assert_false(failed["ok"])
	assert_eq(state.swarm_map(), Vector2i(-1, -1))
	assert_eq(state.fishing_swarm_species(), 0)
