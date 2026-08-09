class_name Gen2Raster
extends RefCounted

## A background scrolled by a different amount on each scanline, which is what
## the hardware's `SCX` is once a routine rewrites it part way down a frame.
##
## The background map is wider than the screen, [param map_width] against the
## image's own width, and everything past what was drawn is blank. So an offset
## does not slide an image sideways and leave a gap: it wraps, and blank is what
## comes in. An offset is a distance to look *right* into the map, so a larger
## one puts the drawn content further left.
##
## Node-free and pure: it takes an image and answers a new one, which is what
## lets a scroll be asserted headless rather than photographed.

## Rows sharing an offset are moved together, since a run of scanlines with one
## value is the shape every routine that does this produces: three bands for
## `BattleIntroSlidingPics`, one for a whole-screen scroll.
static func scroll(
	source: Image, offsets: PackedInt32Array, map_width: int
) -> Image:
	var width: int = source.get_width()
	var height: int = source.get_height()
	if width <= 0 or height <= 0 or map_width <= 0 or offsets.size() < height:
		return source

	var out: Image = Image.create_empty(width, height, false, source.get_format())
	var row: int = 0
	while row < height:
		var offset: int = posmod(offsets[row], map_width)
		var run: int = 1
		while row + run < height and posmod(offsets[row + run], map_width) == offset:
			run += 1
		_scroll_run(source, out, row, run, offset, map_width)
		row += run
	return out


## One run of scanlines at one offset. The visible row is at most two pieces of
## the drawn image with blank between them, since the map is the image followed
## by blank up to [param map_width] and then round again.
static func _scroll_run(
	source: Image, out: Image, row: int, run: int, offset: int, map_width: int
) -> void:
	if offset == 0:
		out.blit_rect(source, Rect2i(0, row, source.get_width(), run), Vector2i(0, row))
		return

	var width: int = source.get_width()
	# What is still on screen of the drawn image, pushed left by the offset.
	var kept: int = clampi(width - offset, 0, width)
	if kept > 0:
		out.blit_rect(source, Rect2i(offset, row, kept, run), Vector2i(0, row))

	# What has come round the far side of the map. The gap between the two is
	# the map's blank columns, which the empty image already is.
	var wrapped: int = clampi(offset + width - map_width, 0, width)
	if wrapped > 0:
		out.blit_rect(
			source, Rect2i(0, row, wrapped, run), Vector2i(map_width - offset, row)
		)


## The same thing vertically, which is what `hLYOverride*` pointed at `rSCY`
## produces: each scanline reads its own row of the map.
##
## The map is [param map_height] tall against the image's own height and
## everything past what was drawn is blank, exactly as [method scroll]'s columns
## are, so a row that wraps past the drawn image comes back blank.
static func scroll_rows(
	source: Image, offsets: PackedInt32Array, map_height: int
) -> Image:
	var width: int = source.get_width()
	var height: int = source.get_height()
	if width <= 0 or height <= 0 or map_height <= 0 or offsets.size() < height:
		return source

	var out: Image = Image.create_empty(width, height, false, source.get_format())
	for row: int in height:
		var from: int = posmod(row + offsets[row], map_height)
		if from >= height:
			continue
		out.blit_rect(source, Rect2i(0, from, width, 1), Vector2i(0, row))
	return out
