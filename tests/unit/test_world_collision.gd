extends GutTest

## Gen2WorldCollision's ledge and tile-collision-std-script lookups against
## engine/overworld/player_movement.asm's .TryJump and
## engine/events/std_collision.asm's CheckFacingTileForStdScript, both from
## pokecrystal revision 5593381195342e481b69a2fd4ab25e202ddcf708.


func test_allows_hop_matches_the_ledge_table_for_every_hop_code() -> void:
	assert_true(Gen2WorldCollision.allows_hop(0xA0, Vector2i.RIGHT))
	assert_false(Gen2WorldCollision.allows_hop(0xA0, Vector2i.LEFT))
	assert_true(Gen2WorldCollision.allows_hop(0xA1, Vector2i.LEFT))
	assert_true(Gen2WorldCollision.allows_hop(0xA2, Vector2i.UP))
	assert_true(Gen2WorldCollision.allows_hop(0xA3, Vector2i.DOWN))
	assert_true(Gen2WorldCollision.allows_hop(0xA4, Vector2i.RIGHT))
	assert_true(Gen2WorldCollision.allows_hop(0xA4, Vector2i.DOWN))
	assert_false(Gen2WorldCollision.allows_hop(0xA4, Vector2i.UP))
	assert_true(Gen2WorldCollision.allows_hop(0xA5, Vector2i.DOWN))
	assert_true(Gen2WorldCollision.allows_hop(0xA5, Vector2i.LEFT))
	assert_true(Gen2WorldCollision.allows_hop(0xA6, Vector2i.UP))
	assert_true(Gen2WorldCollision.allows_hop(0xA6, Vector2i.RIGHT))
	assert_true(Gen2WorldCollision.allows_hop(0xA7, Vector2i.UP))
	assert_true(Gen2WorldCollision.allows_hop(0xA7, Vector2i.LEFT))


func test_allows_hop_refuses_non_ledge_codes() -> void:
	assert_false(Gen2WorldCollision.allows_hop(0x00, Vector2i.DOWN))
	assert_false(Gen2WorldCollision.allows_hop(0x07, Vector2i.DOWN))
	assert_false(Gen2WorldCollision.allows_hop(0xB0, Vector2i.RIGHT))
	assert_false(Gen2WorldCollision.allows_hop(-1, Vector2i.DOWN))
	assert_false(Gen2WorldCollision.allows_hop(0x100, Vector2i.DOWN))


func test_allows_hop_refuses_a_non_cardinal_or_zero_direction() -> void:
	assert_false(Gen2WorldCollision.allows_hop(0xA0, Vector2i.ZERO))
	assert_false(Gen2WorldCollision.allows_hop(0xA0, Vector2i(1, 1)))


func test_allows_hop_preserves_the_source_alias_for_unused_a8_to_af_codes() -> void:
	# .TryJump only checks the high nybble ($a0) before indexing .ledge_table
	# with the low three bits, so $a8 aliases to the same entry as $a0 rather
	# than being rejected. These codes are unused in every pinned tileset;
	# this only pins the source's own bit math, not real map behavior.
	assert_true(Gen2WorldCollision.allows_hop(0xA8, Vector2i.RIGHT))
	assert_false(Gen2WorldCollision.allows_hop(0xA8, Vector2i.LEFT))
	assert_true(Gen2WorldCollision.allows_hop(0xAF, Vector2i.UP))
	assert_true(Gen2WorldCollision.allows_hop(0xAF, Vector2i.LEFT))


func test_hop_codes_remain_land_permission() -> void:
	for code: int in range(0xA0, 0xA8):
		assert_eq(
			Gen2WorldCollision.permission_for(code), Gen2WorldCollision.LAND_TILE,
			"$%02X is land" % code
		)


func test_tile_collision_std_index_matches_both_pinned_repositories() -> void:
	# Recounted directly from engine/events/std_scripts.asm in both pinned
	# revisions (pokecrystal 5593381195342e481b69a2fd4ab25e202ddcf708,
	# pokegold add1dbe018170d7f25f7b7360e8046cec6354906): every entry but
	# PCScript lands on the same 0-based index in both games.
	var expected_both: Dictionary = {
		Gen2WorldCollision.COLL_BOOKSHELF: 3,
		Gen2WorldCollision.COLL_INCENSE_BURNER: 5,
		Gen2WorldCollision.COLL_MART_SHELF: 6,
		Gen2WorldCollision.COLL_TOWN_MAP: 7,
		Gen2WorldCollision.COLL_WINDOW: 8,
		Gen2WorldCollision.COLL_TV: 9,
		Gen2WorldCollision.COLL_RADIO: 11,
	}
	for code: int in expected_both:
		assert_eq(Gen2WorldCollision.tile_collision_std_index(code, true), expected_both[code])
		assert_eq(Gen2WorldCollision.tile_collision_std_index(code, false), expected_both[code])
	assert_eq(Gen2WorldCollision.tile_collision_std_index(Gen2WorldCollision.COLL_PC, true), 49)
	assert_eq(Gen2WorldCollision.tile_collision_std_index(Gen2WorldCollision.COLL_PC, false), 43)


func test_tile_collision_std_index_answers_missing_for_untabled_codes() -> void:
	assert_eq(Gen2WorldCollision.tile_collision_std_index(0x00, true), -1)
	assert_eq(Gen2WorldCollision.tile_collision_std_index(0x07, false), -1)
	assert_eq(Gen2WorldCollision.tile_collision_std_index(0xA0, true), -1)
