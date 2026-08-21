extends GutTest

## Hand-built index buffers and palettes. No cache, no cartridge, no display:
## an Image is data, so the whole of this runs headless.

const RED: Color = Color(1, 0, 0)
const BLUE: Color = Color(0, 0, 1)


func _palette() -> PackedColorArray:
	return Gen2Palette.pic_palette(PackedColorArray([RED, BLUE]))


func test_each_index_becomes_its_palette_colour() -> void:
	var indices: PackedByteArray = PackedByteArray([0, 1, 2, 3])
	var image: Image = Gen2PicImage.from_indices(indices, 4, 1, _palette())

	assert_eq(image.get_pixel(0, 0), Color.WHITE)
	assert_eq(image.get_pixel(1, 0), RED)
	assert_eq(image.get_pixel(2, 0), BLUE)
	assert_eq(image.get_pixel(3, 0), Color.BLACK)


func test_the_buffer_is_read_row_major() -> void:
	var indices: PackedByteArray = PackedByteArray([0, 1, 2, 3])
	var image: Image = Gen2PicImage.from_indices(indices, 2, 2, _palette())

	assert_eq(image.get_size(), Vector2i(2, 2))
	assert_eq(image.get_pixel(1, 0), RED, "second byte is the top-right pixel")
	assert_eq(image.get_pixel(0, 1), BLUE, "third byte starts the second row")


func test_background_is_opaque_white_by_default() -> void:
	# What the hardware does: there is no alpha, and index 0 is drawn white.
	var image: Image = Gen2PicImage.from_indices(PackedByteArray([0]), 1, 1, _palette())
	assert_eq(image.get_pixel(0, 0).a, 1.0)


func test_background_can_be_made_transparent() -> void:
	var image: Image = Gen2PicImage.from_indices(PackedByteArray([0, 1]), 2, 1, _palette(), true)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(1, 0).a, 1.0, "only index 0 is affected")


func test_a_short_buffer_yields_a_blank_image_rather_than_faulting() -> void:
	var image: Image = Gen2PicImage.from_indices(PackedByteArray([1]), 8, 8, _palette())
	assert_eq(image.get_size(), Vector2i(8, 8))


func test_a_zero_sized_image_is_refused() -> void:
	var image: Image = Gen2PicImage.from_indices(PackedByteArray(), 0, 0, _palette())
	assert_gt(image.get_width(), 0, "an Image of no size cannot be created at all")


func test_a_missing_palette_entry_is_visible_rather_than_black() -> void:
	# Magenta, for the same reason an unknown text byte prints as its hex: a
	# palette that did not load should look wrong, not merely dark.
	var image: Image = Gen2PicImage.from_indices(
		PackedByteArray([3]), 1, 1, PackedColorArray([Color.WHITE])
	)
	assert_eq(image.get_pixel(0, 0), Color.MAGENTA)


func _atlas() -> Dictionary:
	# Four 2x2 cells in a 4x4 buffer, two per row.
	return {"width": 4, "height": 4, "cell": 2, "columns": 2}


func _atlas_indices() -> PackedByteArray:
	return PackedByteArray([
		0, 0, 1, 1,
		0, 0, 1, 1,
		2, 2, 3, 3,
		2, 2, 3, 3,
	])


func test_a_slot_is_cut_out_of_the_atlas_by_arithmetic() -> void:
	var image: Image = Gen2PicImage.from_atlas(
		_atlas_indices(), _atlas(), {"slot": 3, "width": 2, "height": 2}, _palette()
	)
	assert_eq(image.get_size(), Vector2i(2, 2))
	assert_eq(image.get_pixel(0, 0), Color.BLACK, "slot 3 is the bottom-right cell")


func test_slots_run_across_before_down() -> void:
	var image: Image = Gen2PicImage.from_atlas(
		_atlas_indices(), _atlas(), {"slot": 1, "width": 2, "height": 2}, _palette()
	)
	assert_eq(image.get_pixel(0, 0), RED, "slot 1 is the top-right cell, not the second row")


func test_a_pic_smaller_than_its_cell_is_cropped() -> void:
	# Cells are the size of the largest pic of their kind, so a small sprite
	# carries blank tiles that must not be positioned by.
	var image: Image = Gen2PicImage.from_atlas(
		_atlas_indices(), _atlas(), {"slot": 0, "width": 1, "height": 1}, _palette()
	)
	assert_eq(image.get_size(), Vector2i(1, 1))


func test_a_pic_cannot_claim_more_than_its_cell() -> void:
	var image: Image = Gen2PicImage.from_atlas(
		_atlas_indices(), _atlas(), {"slot": 0, "width": 99, "height": 99}, _palette()
	)
	assert_eq(image.get_size(), Vector2i(2, 2))


func test_an_unknown_slot_yields_an_image_rather_than_an_error() -> void:
	var image: Image = Gen2PicImage.from_atlas(
		_atlas_indices(), _atlas(), {"slot": -1}, _palette()
	)
	assert_gt(image.get_width(), 0)


## `wBoxAlignment` is both halves of the flip or it is neither. `LoadOrientedFrontpic`
## mirrors each tile's own pixels and `PlaceGraphic`'s `.right` reverses the tile
## column order; doing only the second scrambles the sprite.
func test_x_flipped_mirrors_pixels_within_a_tile_not_just_tile_columns() -> void:
	# One 8x1 strip: a single lit pixel hard against the left edge.
	var indices: PackedByteArray = PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0])
	var image: Image = Gen2PicImage.from_indices(indices, 8, 1, _palette())

	var flipped: Image = Gen2PicImage.x_flipped(image)

	assert_eq(flipped.get_pixel(7, 0), RED, "the lit pixel crosses to the right edge")
	assert_eq(
		flipped.get_pixel(0, 0), Color.WHITE,
		"a column-strip reversal alone would leave it where it started"
	)


func test_x_flipped_reverses_tile_columns_too() -> void:
	# Two 8x1 tiles, lit only in the first.
	var indices: PackedByteArray = PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0])
	var image: Image = Gen2PicImage.from_indices(indices, 16, 1, _palette())

	var flipped: Image = Gen2PicImage.x_flipped(image)

	assert_eq(flipped.get_pixel(15, 0), RED, "the first tile lands in the last column")
	assert_eq(flipped.get_pixel(0, 0), Color.WHITE)


func test_x_flipped_leaves_the_source_alone() -> void:
	var image: Image = Gen2PicImage.from_indices(PackedByteArray([1, 0]), 2, 1, _palette())

	var _flipped: Image = Gen2PicImage.x_flipped(image)

	assert_eq(image.get_pixel(0, 0), RED, "the caller's image is not flipped in place")


func test_x_flipped_tolerates_a_null_image() -> void:
	assert_null(Gen2PicImage.x_flipped(null))


## `PadFrontpic`'s three branches. A full-width pic is padded on neither side; a
## narrower one takes one blank column at the left, and `LoadOrientedFrontpic`'s
## column reversal moves the trailing blank there instead.
func test_frontpic_pad_columns_is_padfrontpics_own_alignment() -> void:
	assert_eq(Gen2PicImage.frontpic_pad_columns(7), 0)
	assert_eq(Gen2PicImage.frontpic_pad_columns(6), 1)
	assert_eq(Gen2PicImage.frontpic_pad_columns(5), 1)
	assert_eq(Gen2PicImage.frontpic_pad_columns(6, true), 0)
	assert_eq(Gen2PicImage.frontpic_pad_columns(5, true), 1)
	assert_eq(Gen2PicImage.frontpic_pad_columns(0), 0, "a pic the cache has no size for")


## `AnimateFrontpic`, which draws through the same box these pads describe. The
## records here are hand-built rather than read from a cache: what a real
## cartridge holds is swept over the whole corpus by `tools/checks/pic_anim.gd`,
## and what is asserted here is the interpreter's own arithmetic.
const ANIM_HEIGHT: int = 5
const ANIM_MASK_BYTES: int = 4


## A record whose [param script] is the pairs given, terminated, and which holds
## one frame per entry of [param frames]: a bitmask and its tile numbers.
func _anim_record(script: Array, frames: Array = []) -> Dictionary:
	var run := PackedByteArray()
	for pair: Array in script:
		run.append(int(pair[0]) & 0xFF)
		run.append(int(pair[1]) & 0xFF)
	run.append(0xFF)
	run.append(0x00)
	var built: Array = []
	for frame: Array in frames:
		built.append(PackedByteArray(frame))
	return {"height": ANIM_HEIGHT, "script": run, "idle": run, "frames": built}


## `PokeAnim_PlaceGraphic` fills the 7x7 block column by column, which is the
## same `column * 7 + row` the enemy's square is stamped with.
func test_pic_animation_places_the_base_pic_column_major() -> void:
	var animation := Gen2PicAnimation.new(_anim_record([]))
	assert_eq(animation.box.size(), 49)
	assert_eq(int(animation.box[0]), 0)
	assert_eq(int(animation.box[1]), 1, "the second cell down the first column")
	assert_eq(int(animation.box[7]), 7, "the top of the second column")
	assert_eq(int(animation.box[48]), 48)


## `.flipped`: `PlaceGraphic` runs its columns back from the block's other end,
## so the first column's tiles land in the last.
func test_pic_animation_mirrors_the_whole_block() -> void:
	var animation := Gen2PicAnimation.new(_anim_record([]), Gen2PicAnimation.ANIM_MON_NORMAL, true)
	assert_eq(int(animation.box[42]), 0, "the first column at the block's right")
	assert_eq(int(animation.box[0]), 42)


## The frame counts are the source's own arithmetic, not a measurement: a
## `frame n, d` spends d, `setrepeat`/`dorepeat` spend none of their own except
## the pass that ends the repeat, `endanim` spends one, and `Setup` and `Finish`
## each pay for the transfers they add to the loop's.
func test_pic_animation_spends_the_scripts_own_frames() -> void:
	# `ANIM_MON_NORMAL` is StereoCry, Setup, Play, Finish.
	var script: Array = [[0, 2], [0, 3], [0xFE, 2], [0, 4], [0xFD, 3]]
	var animation := Gen2PicAnimation.new(_anim_record(script))
	var spent: int = 0
	var cries: int = 0
	while not animation.finished() and spent < 200:
		if animation.advance() != &"":
			cries += 1
		spent += 1
	assert_true(animation.finished(), "the script ended")
	assert_eq(cries, 1, "`PokeAnim_StereoCry`, once and inside the animation")
	# 1 cry + 2 setup + (2 + 3 + 4 + 4 + 1 dorepeat + 1 endanim) + 3 finish.
	assert_eq(spent, 21)


## `PokeAnim_GetDuration` is `a * (1 + speed / 16)` through an 8.8 multiply, so
## `ANIM_MON_SLOW`'s speed of 4 is a quarter longer with the fraction dropped.
func test_pic_animation_slow_stretches_every_duration() -> void:
	var script: Array = [[0, 7]]
	var normal: int = _frames_of(script, Gen2PicAnimation.ANIM_MON_NORMAL)
	var slow: int = _frames_of(script, Gen2PicAnimation.ANIM_MON_SLOW)
	assert_eq(slow - normal, 1, "7 becomes 8, not 8.75")


func _frames_of(script: Array, kind: int) -> int:
	var animation := Gen2PicAnimation.new(_anim_record(script), kind)
	var spent: int = 0
	while not animation.finished() and spent < 200:
		animation.advance()
		spent += 1
	return spent


## `PokeAnim_ConvertAndApplyBitmask` walks the pic's own square column by column,
## one bit per cell, and `.GetCoord` offsets it by `PadFrontpic`'s own pads.
func test_pic_animation_applies_a_frames_bitmask_over_the_pad() -> void:
	# Bit 0 alone: the pic's own cell (0, 0), which is box column 1, row 2.
	var frame: Array = [1, 0, 0, 0, 30]
	var animation := Gen2PicAnimation.new(_anim_record([[1, 1]], [frame]))
	while not animation.finished() and int(animation.box[1 * 7 + 2]) == 1 * 7 + 2:
		animation.advance()
	# Tile 30 is past a 5x5's own 25, so `.GetTilemap` takes the block's 49 as
	# its offset rather than the `poke_anim_box` table.
	assert_eq(int(animation.box[1 * 7 + 2]), 30 + 49 - 25)


## A record the cache has none of animates nothing, which is Gold and Silver's
## every row and the `.cry_no_anim` branch here.
func test_pic_animation_without_a_record_is_finished_at_once() -> void:
	assert_true(Gen2PicAnimation.new({}).finished())
	assert_eq(Gen2PicAnimation.new({}).advance(), &"")


## Why `PokeAnim_SetVBank1` is not decoration. The animation's tiles start at the
## 7x7 block's own 49, and `$31` is 49: that is `AppearUser`'s first tile for the
## player's back pic. The two only ever coexist because the enemy's box is put in
## VRAM bank 1 for as long as the animation runs, so a renderer reading one flat
## sheet draws the player's picture inside the enemy's square.
func test_a_pic_animations_tiles_collide_with_the_players_own_run() -> void:
	assert_eq(
		Gen2PicImage.FRONTPIC_TILES * Gen2PicImage.FRONTPIC_TILES,
		Gen2BattleScreenMap.PLAYER_BASE_TILE
	)
	assert_eq(RomLayout.pic_anim_box_tile(25, 5), Gen2BattleScreenMap.PLAYER_BASE_TILE)


## `PokeAnim_SetVBank1`'s rule, which is what stops the enemy's animation tiles
## being drawn over the player and the player's back pic over the enemy. The
## enemy's box is 7x7 and its frames run behind it; the player's is 6x6 from
## `$31`, which is the enemy block's own 49.
func test_a_pic_layer_claims_only_its_own_sheets_cells() -> void:
	var square: int = Gen2PicImage.FRONTPIC_TILES * Gen2PicImage.FRONTPIC_TILES
	var banked: int = square + 28
	# Bank 0 is the sheet both pictures share, so neither reaches past its box.
	assert_true(Gen2BattleRenderer.claims_tile(48, false, true, square, banked))
	assert_false(
		Gen2BattleRenderer.claims_tile(49, false, true, square, banked),
		"the player's first tile is not the enemy's fiftieth"
	)
	# Bank 1 is the animated layer's alone, and there its frames are in reach.
	assert_true(Gen2BattleRenderer.claims_tile(49, true, true, square, banked))
	assert_false(
		Gen2BattleRenderer.claims_tile(0, true, false, square, banked),
		"a layer that owns no bank 1 sheet draws none of its cells"
	)
	assert_false(Gen2BattleRenderer.claims_tile(banked, true, true, square, banked))
	assert_false(Gen2BattleRenderer.claims_tile(-1, false, false, square, banked))


## `WipeAttrmap` then `FillBoxCGB`: a box is (x, y, width, height, palette) and
## anything it does not reach stays on palette 0. A box running off the screen is
## clipped rather than wrapping, which is what `FillBoxCGB`'s own row step does.
func test_an_attrmap_is_its_boxes_over_the_zeroes_wipeattrmap_leaves() -> void:
	var slots: PackedInt32Array = Gen2PicImage.attribute_boxes(
		[[1, 0, 2, 2, 3], [3, 1, 4, 1, 5]], 4, 3
	)
	assert_eq(Array(slots), [0, 3, 3, 0, 0, 3, 3, 5, 0, 0, 0, 0])


## One index buffer, one palette per tile: the hardware's own shape, and what
## keeps the stats screen's bars, front pic and page indicators out of layers of
## their own.
func test_a_tile_is_drawn_in_the_palette_its_attrmap_slot_names() -> void:
	var tile: int = Gen2Font.TILE
	var indices := PackedByteArray()
	indices.resize(tile * 2 * tile)
	for x: int in tile * 2:
		indices[x] = 1
	var image: Image = Gen2PicImage.from_attributes(
		indices, tile * 2, tile, Gen2PicImage.attribute_boxes([[1, 0, 1, 1, 1]], 2, 1), 2,
		[
			PackedColorArray([Color.WHITE, Color.RED, Color.BLACK, Color.BLACK]),
			PackedColorArray([Color.WHITE, Color.BLUE, Color.BLACK, Color.BLACK]),
		]
	)
	assert_eq(image.get_pixel(0, 0), Color.RED)
	assert_eq(image.get_pixel(tile, 0), Color.BLUE)
	# A slot naming a palette that is not there falls back on the first rather
	# than reading past the list.
	var clamped: Image = Gen2PicImage.from_attributes(
		indices, tile * 2, tile, Gen2PicImage.attribute_boxes([[1, 0, 1, 1, 9]], 2, 1), 2,
		[PackedColorArray([Color.WHITE, Color.RED, Color.BLACK, Color.BLACK])]
	)
	assert_eq(clamped.get_pixel(tile, 0), Color.RED)
