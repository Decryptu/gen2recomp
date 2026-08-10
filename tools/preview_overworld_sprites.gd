extends SceneTree

## Draws every overworld sprite a cache holds as one contact sheet, so a human
## can see at a glance whether the strip was read at the right offset and the
## frames were composed the right way round.
##
## Each sprite is a four-by-four block: the four facings across, in
## `Gen2WorldSprite`'s down/up/left/right order, and the four `Facings` frames
## down. Frames 0 and 2 are the standing drawing and 1 and 3 the walking one, so
## a correct walking sprite reads as two poses alternating down the block, with
## the right column mirroring the left.
##
## A still sprite draws the same picture sixteen times, which is right. A big
## object (`SPRITE_BIG_SNORLAX`, `SPRITE_BIG_ONIX`, the dolls) draws as a
## scramble, which is a known gap: those use `FacingBigDollSymmetric` and
## `..._Asymmetric`, sixteen and fourteen tiles in a 32x32 square, and
## `Gen2WorldSprite.image_for()` only knows the four-tile layout.
##
##   Godot --headless --path . -s res://tools/preview_overworld_sprites.gd -- crystal /tmp/sprites.png

const CELL: int = 16
const COLUMNS: int = 8
const SCALE: int = 2
## Four facings across, four frames down, plus a one-pixel gutter.
const TILE_W: int = CELL * 4 + 2
const TILE_H: int = CELL * 4 + 2
const BACKGROUND: Color = Color(0.15, 0.15, 0.2, 1.0)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -s tools/preview_overworld_sprites.gd -- <game> <output.png>")
		quit(1)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var count: int = data.overworld_sprite_count()
	var rows: int = ceili(float(count) / float(COLUMNS))
	var sheet := Image.create(COLUMNS * TILE_W, rows * TILE_H, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKGROUND)
	for number: int in range(1, count + 1):
		var sprite: Gen2WorldSprite = data.overworld_sprite(number)
		if sprite == null:
			continue
		var indices: PackedByteArray = data.overworld_sprite_indices(number)
		var palette: PackedColorArray = data.overworld_sprite_palette(
			sprite.default_palette, Gen2WorldPalette.TIME_DAY
		)
		var at := Vector2i(
			((number - 1) % COLUMNS) * TILE_W + 1,
			((number - 1) / COLUMNS) * TILE_H + 1
		)
		for facing: int in 4:
			for frame: int in 4:
				sheet.blit_rect(
					Gen2WorldSprite.image_for(sprite, indices, palette, facing, frame),
					Rect2i(0, 0, CELL, CELL),
					at + Vector2i(facing * CELL, frame * CELL)
				)
	sheet.resize(sheet.get_width() * SCALE, sheet.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	if sheet.save_png(args[1]) != OK:
		push_error("Could not write %s" % args[1])
		quit(1)
		return
	print("%s: %d sprites, %d per row, facings across and frames down." % [
		args[0], count, COLUMNS,
	])
	quit(0)
