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


## home/map.asm's .MovementPermissionsData, recounted per code (constants/
## collision_constants.asm's COLL_*_WALL/BUOY names). $c0-$c7 share the table.
func test_side_wall_face_mask_matches_movement_permissions_data() -> void:
	var expected: Dictionary = {
		0xB0: Gen2WorldCollision.FACE_RIGHT,
		0xB1: Gen2WorldCollision.FACE_LEFT,
		0xB2: Gen2WorldCollision.FACE_UP,
		0xB3: Gen2WorldCollision.FACE_DOWN,
		0xB4: Gen2WorldCollision.FACE_DOWN | Gen2WorldCollision.FACE_RIGHT,
		0xB5: Gen2WorldCollision.FACE_DOWN | Gen2WorldCollision.FACE_LEFT,
		0xB6: Gen2WorldCollision.FACE_UP | Gen2WorldCollision.FACE_RIGHT,
		0xB7: Gen2WorldCollision.FACE_UP | Gen2WorldCollision.FACE_LEFT,
	}
	for wall_code: int in expected:
		var buoy_code: int = wall_code + 0x10
		assert_eq(
			Gen2WorldCollision.side_wall_face_mask(wall_code), expected[wall_code],
			"$%02X" % wall_code
		)
		assert_eq(
			Gen2WorldCollision.side_wall_face_mask(buoy_code), expected[wall_code],
			"$%02X" % buoy_code
		)


func test_side_wall_face_mask_refuses_non_wall_non_buoy_codes() -> void:
	assert_eq(Gen2WorldCollision.side_wall_face_mask(0x00), 0)
	assert_eq(Gen2WorldCollision.side_wall_face_mask(0xA0), 0)
	assert_eq(Gen2WorldCollision.side_wall_face_mask(-1), 0)
	assert_eq(Gen2WorldCollision.side_wall_face_mask(0x100), 0)


func test_side_wall_face_mask_aliases_b8_to_bf_and_c8_to_cf() -> void:
	# .CheckHiNybble ANDs against $f0 before comparing, so $b8 shares $b0's
	# hi nybble and aliases onto the same entry, mirroring the $a8-$af ledge
	# alias allows_hop() already preserves.
	assert_eq(Gen2WorldCollision.side_wall_face_mask(0xB8), Gen2WorldCollision.FACE_RIGHT)
	assert_eq(Gen2WorldCollision.side_wall_face_mask(0xBF), Gen2WorldCollision.FACE_UP | Gen2WorldCollision.FACE_LEFT)
	assert_eq(Gen2WorldCollision.side_wall_face_mask(0xC8), Gen2WorldCollision.FACE_RIGHT)


func test_side_wall_codes_keep_their_plain_permission() -> void:
	for code: int in range(0xB0, 0xB8):
		assert_eq(Gen2WorldCollision.permission_for(code), Gen2WorldCollision.LAND_TILE, "$%02X" % code)
	for code: int in range(0xC0, 0xC8):
		assert_eq(Gen2WorldCollision.permission_for(code), Gen2WorldCollision.WATER_TILE, "$%02X" % code)


## home/map.asm's GetMovementPermissions, crystal profile: .ok_down/.ok_up/
## .ok_right/.ok_left OR their own FACE_* constant on a match.
func test_tile_permissions_crystal_blocks_the_matching_face_per_neighbor() -> void:
	var open_code: int = 0x00
	# Standing tile itself walls off FACE_RIGHT (leave rule).
	assert_eq(
		Gen2WorldCollision.tile_permissions(0xB0, open_code, open_code, open_code, open_code, true),
		Gen2WorldCollision.FACE_RIGHT
	)
	# Neighbour below is COLL_UP_WALL ($b2): its own mask includes FACE_UP,
	# so entering it from above (moving DOWN) is blocked.
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, open_code, 0xB2, open_code, open_code, true),
		Gen2WorldCollision.FACE_DOWN
	)
	# Neighbour above is COLL_DOWN_WALL ($b3): blocks moving UP into it.
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, 0xB3, open_code, open_code, open_code, true),
		Gen2WorldCollision.FACE_UP
	)
	# Neighbour to the right is COLL_LEFT_WALL ($b1): blocks moving RIGHT.
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, open_code, open_code, open_code, 0xB1, true),
		Gen2WorldCollision.FACE_RIGHT
	)
	# Neighbour to the left is COLL_RIGHT_WALL ($b0): blocks moving LEFT.
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, open_code, open_code, 0xB0, open_code, true),
		Gen2WorldCollision.FACE_LEFT
	)
	# Standing on a diagonal code (leave rule) blocks both faces it names.
	assert_eq(
		Gen2WorldCollision.tile_permissions(0xB4, open_code, open_code, open_code, open_code, true),
		Gen2WorldCollision.FACE_DOWN | Gen2WorldCollision.FACE_RIGHT
	)
	# A DOWN_LEFT neighbour below the player (mask FACE_DOWN|FACE_LEFT) does
	# not contain FACE_UP, the opposite of DOWN, so entering it from above is
	# not blocked by the enter rule.
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, open_code, 0xB5, open_code, open_code, true),
		0
	)


## pokegold/home/map.asm's .ok_down/.ok_up/.ok_right/.ok_left all set bit
## RIGHT (numerically FACE_DOWN), so every enter-rule match blocks only DOWN.
## No shipped Gold/Silver map exercises this: every real $bx/$cx cell in those
## caches has low three bits 2 (COLL_UP_WALL), which only ever feeds the
## down-neighbor check anyway, so the crystal and gold results already agree
## there. This pins the source's own divergence for a mod-authored map.
func test_tile_permissions_gold_silver_enter_rule_always_sets_face_down() -> void:
	var open_code: int = 0x00
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, 0xB3, open_code, open_code, open_code, false),
		Gen2WorldCollision.FACE_DOWN
	)
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, open_code, open_code, open_code, 0xB1, false),
		Gen2WorldCollision.FACE_DOWN
	)
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, open_code, open_code, 0xB0, open_code, false),
		Gen2WorldCollision.FACE_DOWN
	)
	# The leave rule is unaffected: standing on a wall code still walls off
	# its own real face on both games.
	assert_eq(
		Gen2WorldCollision.tile_permissions(0xB1, open_code, open_code, open_code, open_code, false),
		Gen2WorldCollision.FACE_LEFT
	)
	# The down-neighbor case already matches FACE_DOWN on crystal too, so it
	# does not by itself distinguish the two profiles.
	assert_eq(
		Gen2WorldCollision.tile_permissions(open_code, open_code, 0xB2, open_code, open_code, false),
		Gen2WorldCollision.FACE_DOWN
	)


## engine/overworld/npc_movement.asm's CanObjectLeaveTile and
## WillObjectBumpIntoTile, byte-identical between both pinned repositories.
func test_side_wall_step_blocked_matches_the_leave_and_enter_rules() -> void:
	var open_code: int = 0x00
	# Leaving a RIGHT_WALL tile moving RIGHT is blocked (leave rule).
	assert_true(Gen2WorldCollision.side_wall_step_blocked(0xB0, open_code, Vector2i.RIGHT))
	# Leaving the same tile moving LEFT, UP or DOWN is not.
	assert_false(Gen2WorldCollision.side_wall_step_blocked(0xB0, open_code, Vector2i.LEFT))
	assert_false(Gen2WorldCollision.side_wall_step_blocked(0xB0, open_code, Vector2i.UP))
	# Entering a LEFT_WALL tile from the west (moving RIGHT) is blocked
	# (enter rule: the destination's own mask contains FACE_LEFT, the
	# opposite of RIGHT).
	assert_true(Gen2WorldCollision.side_wall_step_blocked(open_code, 0xB1, Vector2i.RIGHT))
	assert_false(Gen2WorldCollision.side_wall_step_blocked(open_code, 0xB1, Vector2i.LEFT))
	# A RIGHT_WALL/LEFT_WALL pair blocks crossing in both directions even
	# though both tiles are plain LAND_TILE permission.
	assert_true(Gen2WorldCollision.side_wall_step_blocked(0xB0, 0xB1, Vector2i.RIGHT))
	assert_true(Gen2WorldCollision.side_wall_step_blocked(0xB1, 0xB0, Vector2i.LEFT))
	# A zero or diagonal direction never blocks.
	assert_false(Gen2WorldCollision.side_wall_step_blocked(0xB0, 0xB1, Vector2i.ZERO))
	assert_false(Gen2WorldCollision.side_wall_step_blocked(0xB0, 0xB1, Vector2i(1, 1)))


## engine/overworld/tile_events.asm's CheckCutCollision list against the
## permission table those codes ride on: two of the six block, four are ordinary
## ground, and only two of the six are used by any pinned tileset.
func test_cuttable_codes_keep_the_permissions_cut_depends_on() -> void:
	for code: int in [0x12, 0x1A]:
		assert_eq(
			Gen2WorldCollision.permission_for(code), Gen2WorldCollision.WALL_TILE,
			"cut tree $%02x" % code
		)
		assert_true(Gen2WorldCollision.talks(code), "cut tree $%02x" % code)
	for code: int in [0x10, 0x14, 0x18, 0x1C]:
		assert_eq(
			Gen2WorldCollision.permission_for(code), Gen2WorldCollision.LAND_TILE,
			"grass $%02x" % code
		)


## engine/overworld/player_movement.asm's DoPlayerMovement.CheckTile, branch for
## branch. Its tables are indexed after a mask, not by an exact code, so most of
## these entries have no COLL_* name and none is reachable on a pinned cartridge
## except $24, $33 and the three warp codes.
func test_forced_action_answers_none_on_ordinary_ground() -> void:
	for code: int in [0x00, 0x07, 0x12, 0x18, 0x20, 0x29, 0x60, 0x91, 0xA3, 0xB0, 0xC0]:
		assert_eq(
			StringName(Gen2WorldCollision.forced_action(code)["kind"]), &"none",
			"code $%02x" % code
		)
	for code: int in [-1, 0x100]:
		assert_eq(StringName(Gen2WorldCollision.forced_action(code)["kind"]), &"none")


func test_forced_action_turns_the_player_on_both_whirlpool_codes() -> void:
	for code: int in [0x24, 0x2C]:
		var forced: Dictionary = Gen2WorldCollision.forced_action(code)
		assert_eq(StringName(forced["kind"]), &"force_turn", "code $%02x" % code)
		assert_false(forced.has("direction"))
	# Their neighbours are ordinary water.
	for code: int in [0x23, 0x25, 0x2B, 0x2D]:
		assert_eq(StringName(Gen2WorldCollision.forced_action(code)["kind"]), &"none")


func test_forced_action_walks_every_current_code() -> void:
	# .water masks NUM_DIRECTIONS, so all sixteen $3x codes index the four-entry
	# .water_table rather than only $30-$33.
	var expected: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN,
	]
	for code: int in range(0x30, 0x40):
		var forced: Dictionary = Gen2WorldCollision.forced_action(code)
		assert_eq(StringName(forced["kind"]), &"walk", "code $%02x" % code)
		assert_eq(forced["direction"], expected[code & 0x03], "code $%02x" % code)
	# COLL_WATERFALL, the only one of the sixteen any pinned map ships.
	assert_eq(Gen2WorldCollision.forced_action(0x33)["direction"], Vector2i.DOWN)


func test_forced_action_follows_both_forced_walk_tables() -> void:
	var land1: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP,
		Vector2i.DOWN, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO,
	]
	var land2: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN,
		Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO,
	]
	for index: int in 8:
		_assert_forced_walk(0x40 + index, land1[index])
		_assert_forced_walk(0x50 + index, land2[index])
	# The masks are three bits wide, so the upper half of each row aliases onto
	# the same eight entries, as the ledge and side-wall codes do.
	for index: int in 8:
		_assert_forced_walk(0x48 + index, land1[index])
		_assert_forced_walk(0x58 + index, land2[index])


## .warps accepts four codes and lets every other $7x fall through, so a warp
## panel or an unnamed $7x tile forces nothing.
func test_forced_action_steps_down_off_doors_stairs_and_caves() -> void:
	for code: int in [0x71, 0x79, 0x7A, 0x7B]:
		_assert_forced_walk(code, Vector2i.DOWN)
	for code: int in [0x70, 0x72, 0x73, 0x74, 0x75, 0x78, 0x7C, 0x7D, 0x7F]:
		assert_eq(
			StringName(Gen2WorldCollision.forced_action(code)["kind"]), &"none",
			"code $%02x" % code
		)


func _assert_forced_walk(code: int, direction: Vector2i) -> void:
	var forced: Dictionary = Gen2WorldCollision.forced_action(code)
	if direction == Vector2i.ZERO:
		assert_eq(StringName(forced["kind"]), &"none", "code $%02x" % code)
		return
	assert_eq(StringName(forced["kind"]), &"walk", "code $%02x" % code)
	assert_eq(forced["direction"], direction, "code $%02x" % code)
