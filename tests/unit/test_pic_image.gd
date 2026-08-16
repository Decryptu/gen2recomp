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
