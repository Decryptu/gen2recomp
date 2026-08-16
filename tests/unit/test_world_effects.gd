extends GutTest


func test_source_packed_screen_shake_uses_duration_and_amplitude_bits() -> void:
	var effects := Gen2WorldEffects.new()
	var started: Dictionary = effects.start_screen_shake(0x54)
	assert_true(started["active"])
	assert_eq(started["duration"], 20)
	assert_eq(started["amplitude"], 2)
	assert_eq(started["offset"], Vector2(-2, 0))

	for _frame: int in 19:
		assert_true(effects.advance_frame())
	assert_true(effects.active())
	assert_true(effects.advance_frame())
	assert_false(effects.active())
	assert_false(effects.advance_frame(), "a spent effect costs no more frames")
	assert_eq(effects.offset(), Vector2.ZERO)


func test_the_headbutt_tree_runs_its_frameset_for_thirty_two_frames() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_headbutt_tree(Vector2i(4, 7))
	var sprite: Dictionary = effects.sprites()[0]
	assert_eq(sprite["kind"], Gen2WorldEffects.SPRITE_HEADBUTT_TREE)
	assert_eq(sprite["cell"], Vector2i(4, 7))
	assert_eq(effects.hidden_tree_cells(), [Vector2i(4, 7)])
	## Each oamframe lasts three frames: tiles 0-3, tiles 4-7, tiles 0-3, then
	## tiles 4-7 flipped, and then the frameset restarts.
	var bases: Array = []
	var flips: Array = []
	for frame: int in 12:
		var tiles: Array = (effects.sprites()[0] as Dictionary)["tiles"]
		bases.append(int((tiles[0] as Dictionary)["tile"]))
		flips.append(bool((tiles[0] as Dictionary)["flip_x"]))
		effects.advance_frame()
	assert_eq(bases, [0, 0, 0, 4, 4, 4, 0, 0, 0, 4, 4, 4])
	assert_eq(flips.slice(9), [true, true, true])
	assert_eq(int((effects.sprites()[0] as Dictionary)["tiles"][0]["tile"]), 0,
		"oamrestart takes the frameset back to its first entry")

	for _frame: int in 19:
		effects.advance_frame()
	assert_true(effects.sprites_active())
	effects.advance_frame()
	assert_false(effects.sprites_active(), "wFrameCounter is 32")
	assert_eq(effects.hidden_tree_cells(), [])


func test_a_grass_rustle_swaps_its_two_facings_every_four_frames() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_grass_rustle(-1, Vector2i(2, 2), 7)
	var first: Array = (effects.sprites()[0] as Dictionary)["tiles"]
	assert_eq(first.size(), 2)
	assert_eq((first[0] as Dictionary)["offset"], Vector2i(0, 8))
	assert_true(bool((first[1] as Dictionary)["flip_x"]), "FacingGrass1 mirrors its right tile")
	for _frame: int in 4:
		effects.advance_frame()
	assert_eq(
		((effects.sprites()[0] as Dictionary)["tiles"][0] as Dictionary)["offset"],
		Vector2i(-1, 9),
	)
	for _frame: int in 3:
		effects.advance_frame()
	assert_false(effects.sprites_active(), "a rustle is one frame shorter than its step")


func test_boulder_dust_takes_its_offset_from_the_push_direction() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_boulder_dust(2, Vector2i(5, 5), Vector2i.LEFT, 16)
	var sprite: Dictionary = effects.sprites()[0]
	assert_eq(sprite["object_index"], 2)
	assert_eq((sprite["tiles"][0] as Dictionary)["offset"], Vector2i(6, 2))
	assert_eq(sprite["tiles"].size(), 4, "one tile drawn four times in a 16x16 square")
	## `SetFacingBoulderDust` swaps the two tiles on bit 1 of the frame counter.
	effects.advance_frame()
	assert_eq(int((effects.sprites()[0] as Dictionary)["tiles"][0]["tile"]), 0)
	effects.advance_frame()
	assert_eq(int((effects.sprites()[0] as Dictionary)["tiles"][0]["tile"]), 1)
	## (step duration + 1) * 2 frames, so the dust outlives the push.
	for _frame: int in 31:
		effects.advance_frame()
	assert_true(effects.sprites_active())
	effects.advance_frame()
	assert_false(effects.sprites_active())


## `.Frameset_CutTree` splits the tree and slides the halves apart, and its
## `oamdelete` ends the sprite four frames before OWCutAnimation's own counter.
func test_the_cut_tree_splits_and_then_deletes_itself() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_cut(Vector2i(3, 3), 0, Vector2i.DOWN, Vector2i(2, 3))
	var sprite: Dictionary = effects.sprites()[0]
	assert_eq(sprite["kind"], Gen2WorldEffects.SPRITE_CUT_TREE)
	assert_eq((sprite["tiles"][0] as Dictionary)["offset"], Vector2i(0, 0),
		"the first three frames are the tree standing")
	for _frame: int in 3:
		effects.advance_frame()
	assert_eq(
		((effects.sprites()[0] as Dictionary)["tiles"][0] as Dictionary)["offset"],
		Vector2i(-2, 0),
	)
	for _frame: int in 17:
		effects.advance_frame()
	assert_true((effects.sprites()[0] as Dictionary)["tiles"].is_empty(),
		"oamwait draws nothing at all")
	for _frame: int in 8:
		effects.advance_frame()
	assert_true((effects.sprites()[0] as Dictionary)["tiles"].is_empty(),
		"and oamdelete is four frames before the counter runs out")
	for _frame: int in 4:
		effects.advance_frame()
	assert_false(effects.sprites_active())


## `Cut_SpawnAnimateLeaves` spawns four leaves an eighth of a turn apart over the
## quarter of the block the player stands in, and each spirals outwards.
func test_cut_leaves_spawn_four_deep_and_spiral() -> void:
	var effects := Gen2WorldEffects.new()
	effects.set_sine_table(Gen2BattleAnimData.create({}, [], _sine_bytes()))
	effects.start_cut(Vector2i(3, 3), 1, Vector2i.DOWN, Vector2i(2, 3))
	var sprites: Array = effects.sprites()
	assert_eq(sprites.size(), 4)
	var first: Dictionary = (sprites[0] as Dictionary)["tiles"][0]
	## Facing down, an even x and an odd y is the block's bottom left.
	assert_eq(first["offset"], Vector2i(16, 32) + Vector2i(-4, -4),
		"a leaf opens at its own corner with no radius yet")
	var offsets: Array = []
	for _frame: int in 8:
		effects.advance_frame()
		offsets.append(((effects.sprites()[0] as Dictionary)["tiles"][0] as Dictionary)["offset"])
	assert_true(offsets[7] != offsets[0], "the radius grows every second frame")
	assert_eq(effects.sprites().size(), 4, "all four last the whole animation")


## `SpawnShadow` from `JumpStep`: one tile drawn twice under whoever is jumping,
## for twice the half-hop it was spawned in.
func test_a_jump_shadow_is_two_mirrored_tiles_under_the_jumper() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_jump_shadow(-1, Vector2i(4, 4), Vector2i.DOWN, Gen2WorldAPI.STEP_FRAMES_HOP)
	var sprite: Dictionary = effects.sprites()[0]
	assert_eq(sprite["kind"], Gen2WorldEffects.SPRITE_SHADOW)
	assert_eq(sprite["tiles"].size(), 2)
	assert_eq((sprite["tiles"][0] as Dictionary)["offset"], Vector2i(0, 14))
	assert_true(bool((sprite["tiles"][1] as Dictionary)["flip_x"]))
	for _frame: int in 17:
		effects.advance_frame()
	assert_true(effects.sprites_active(), "(8 + 1) * 2 frames, so it outlasts the hop")
	effects.advance_frame()
	assert_false(effects.sprites_active())


## `BattleAnimSineWave` as the cartridge stores it, which is what a leaf's
## offsets are read out of rather than derived from.
func _sine_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	for value: int in RomLayout.BATTLE_ANIM_SINE_WAVE:
		out.append(value)
	return out


## The mod actor layer, which is the other half of this file's subject: sprites
## the screen drives a frame at a time and the renderer draws, with no world
## state behind them. Its own contract is Gen2WorldActors.
const ActorFixture := preload("res://tests/integration/world_trainer_fixture.gd")


class TestActor extends RefCounted:
	var world: Gen2WorldAPI = null
	var frames: int = 0
	var reads: int = 0
	var out: Array = []

	func set_world(value: Gen2WorldAPI) -> void:
		world = value

	func advance_frame() -> void:
		frames += 1

	func sprites() -> Array:
		reads += 1
		return out


func _actor_world() -> Gen2WorldAPI:
	ActorFixture.build()
	return Gen2WorldAPI.open(
		GameData.open_directory(ActorFixture.directory()), 1, 1, Vector2i(4, 4)
	)


func test_an_actors_entry_is_resolved_to_the_sprite_the_map_objects_use() -> void:
	var world: Gen2WorldAPI = _actor_world()
	var actor := TestActor.new()
	actor.out = [{
		"icon": 1, "facing": Gen2WorldSprite.FACING_LEFT,
		"position_cells": Vector2(4, 5.5),
	}]
	var actors := Gen2WorldActors.new()
	actors.set_actors([actor])
	actors.set_world(world)
	assert_eq(actor.world, world)
	var drawn: Array = actors.sprites()
	assert_eq(drawn.size(), 1)
	var sprite: Gen2WorldSprite = drawn[0]["sprite"]
	assert_eq(sprite.sprite_type, Gen2WorldSprite.TYPE_MON_ICON)
	assert_eq(sprite.icon_number, 1)
	assert_true(sprite.animate_icon_frames, "an actor's icon animates, a map object's does not")
	assert_eq(drawn[0]["facing"], Gen2WorldSprite.FACING_LEFT)
	assert_eq(drawn[0]["position_cells"], Vector2(4, 5.5))
	RomCache.clear(ActorFixture.directory())


## `.Frameset_PartyMon`: two sets of eight, nine passes each.
func test_an_icon_actor_steps_the_strips_two_frames_at_the_framesets_rate() -> void:
	var world: Gen2WorldAPI = _actor_world()
	var actor := TestActor.new()
	actor.out = [{"icon": 1, "position_cells": Vector2.ZERO}]
	var actors := Gen2WorldActors.new()
	actors.set_actors([actor])
	actors.set_world(world)
	assert_eq(int(actors.sprites()[0]["frame"]), 0)
	for _frame: int in Gen2WorldActors.ICON_FRAME_FRAMES:
		actors.advance_frame()
	assert_eq(int(actors.sprites()[0]["frame"]), 1)
	var sprite: Gen2WorldSprite = actors.sprites()[0]["sprite"]
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_DOWN, 1), 4)
	for _frame: int in Gen2WorldActors.ICON_FRAME_FRAMES:
		actors.advance_frame()
	assert_eq(int(actors.sprites()[0]["frame"]), 0)
	assert_eq(actor.frames, Gen2WorldActors.ICON_FRAME_FRAMES * 2)
	RomCache.clear(ActorFixture.directory())


## A map object's icon is copied into both VRAM halves, so it shows one frame
## forever; only an actor asks for the second.
func test_a_map_objects_icon_never_reaches_the_strips_second_frame() -> void:
	var sprite: Gen2WorldSprite = Gen2WorldSprite.from_mon_icon(1)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_DOWN, 1), 0)
	assert_eq(sprite.frame_tile_offset(Gen2WorldSprite.FACING_UP, 3), 0)


func test_actor_sprites_are_sorted_by_row_and_read_once_a_frame() -> void:
	var world: Gen2WorldAPI = _actor_world()
	var actor := TestActor.new()
	actor.out = [
		{"icon": 1, "position_cells": Vector2(0, 6)},
		{"icon": 2, "position_cells": Vector2(0, 2)},
	]
	var actors := Gen2WorldActors.new()
	actors.set_actors([actor])
	actors.set_world(world)
	var reads: int = actor.reads
	var drawn: Array = actors.sprites()
	assert_eq((drawn[0]["sprite"] as Gen2WorldSprite).icon_number, 2)
	assert_eq((drawn[1]["sprite"] as Gen2WorldSprite).icon_number, 1)
	actors.sprites()
	assert_eq(actor.reads, reads, "a second draw in one frame asks the mod nothing")
	RomCache.clear(ActorFixture.directory())


## Art the cache does not carry is dropped rather than drawn as a placeholder,
## and an entry naming neither an icon nor a sprite is not an entry.
func test_an_actor_naming_art_that_is_not_there_draws_nothing() -> void:
	var world: Gen2WorldAPI = _actor_world()
	var actor := TestActor.new()
	actor.out = [
		{"icon": 0, "position_cells": Vector2.ZERO},
		{"icon": RomLayout.MON_ICON_COUNT + 1, "position_cells": Vector2.ZERO},
		{"position_cells": Vector2.ZERO},
		"not a sprite",
	]
	var actors := Gen2WorldActors.new()
	actors.set_actors([actor])
	actors.set_world(world)
	assert_eq(actors.sprites().size(), 0)
	RomCache.clear(ActorFixture.directory())


## Whether the screen has to redraw: a still actor costs nothing beyond the
## icon's own animation.
func test_an_actor_that_has_not_moved_reports_no_redraw() -> void:
	var world: Gen2WorldAPI = _actor_world()
	var actor := TestActor.new()
	actor.out = [{"icon": 1, "position_cells": Vector2(3, 3)}]
	var actors := Gen2WorldActors.new()
	actors.set_actors([actor])
	actors.set_world(world)
	assert_false(actors.advance_frame())
	actor.out = [{"icon": 1, "position_cells": Vector2(3, 3.5)}]
	assert_true(actors.advance_frame())
	RomCache.clear(ActorFixture.directory())
