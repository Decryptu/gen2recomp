extends GutTest

## A background scrolled per scanline, over a map wider than the screen.

const WIDTH: int = Gen2Screen.WIDTH
const HEIGHT: int = Gen2Screen.HEIGHT
const MAP: int = Gen2BattleIntro.MAP_WIDTH


## Every column is its own colour, so where a pixel came from can be read back
## off the pixel.
func _numbered() -> Image:
	var image: Image = Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in HEIGHT:
		for x: int in WIDTH:
			image.set_pixel(x, y, Color8(x, 0, 0, 255))
	return image


func _flat(offset: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(HEIGHT)
	out.fill(offset)
	return out


## Which source column a screen column is showing, or -1 for the map's blank.
func _source_column(image: Image, x: int, y: int = 0) -> int:
	var pixel: Color = image.get_pixel(x, y)
	return -1 if pixel.a <= 0.0 else int(round(pixel.r8))


func test_no_offset_leaves_the_image_alone() -> void:
	var out: Image = Gen2Raster.scroll(_numbered(), _flat(0), MAP)
	assert_eq(_source_column(out, 0), 0)
	assert_eq(_source_column(out, WIDTH - 1), WIDTH - 1)


## An offset is a distance to look right into the map, so the drawn content
## moves left and the map's blank columns follow it in.
func test_an_offset_pushes_the_drawn_content_left_and_brings_blank_in() -> void:
	var out: Image = Gen2Raster.scroll(_numbered(), _flat(40), MAP)
	assert_eq(_source_column(out, 0), 40, "screen 0 shows map column 40")
	assert_eq(_source_column(out, WIDTH - 41), WIDTH - 1, "the last drawn column, moved left")
	assert_eq(_source_column(out, WIDTH - 40), -1, "and blank map behind it")
	assert_eq(_source_column(out, WIDTH - 1), -1)


## Past the map's own width the offset wraps, which is what brings the drawn
## content back in on the other side. `BattleIntroSlidingPics` starts at $90,
## which is already past the point where that happens.
func test_an_offset_past_the_map_wraps_the_content_back_in() -> void:
	var out: Image = Gen2Raster.scroll(_numbered(), _flat(0x90), MAP)
	assert_eq(_source_column(out, 0), 0x90, "the right end of the drawn content")
	assert_eq(_source_column(out, WIDTH - 0x90 - 1), WIDTH - 1, "up to its last column")
	assert_eq(_source_column(out, WIDTH - 0x90), -1, "then the map's blank")

	# 256 - 144 = 112: from there the map has come round to its own column 0.
	assert_eq(_source_column(out, MAP - 0x90 - 1), -1)
	assert_eq(_source_column(out, MAP - 0x90), 0, "and the content is back")
	assert_eq(_source_column(out, WIDTH - 1), WIDTH - 1 - (MAP - 0x90))


## An offset of the whole map is no offset at all.
func test_an_offset_of_a_whole_map_is_the_image_itself() -> void:
	var out: Image = Gen2Raster.scroll(_numbered(), _flat(MAP), MAP)
	assert_eq(_source_column(out, 0), 0)
	assert_eq(_source_column(out, WIDTH - 1), WIDTH - 1)


## The point of doing this per scanline rather than per layer: two rows of the
## same image can be in different places at once.
func test_each_scanline_takes_its_own_offset() -> void:
	var offsets: PackedInt32Array = _flat(0)
	for row: int in HEIGHT:
		offsets[row] = 8 if row < 10 else 24
	var out: Image = Gen2Raster.scroll(_numbered(), offsets, MAP)
	assert_eq(_source_column(out, 0, 0), 8)
	assert_eq(_source_column(out, 0, 9), 8)
	assert_eq(_source_column(out, 0, 10), 24)
	assert_eq(_source_column(out, 0, HEIGHT - 1), 24)


## A caller that has no offsets for every row gets its image back rather than a
## partly scrolled one.
func test_a_short_offset_list_scrolls_nothing() -> void:
	var out: Image = Gen2Raster.scroll(_numbered(), PackedInt32Array([4, 4]), MAP)
	assert_eq(_source_column(out, 0), 0)
