class_name Gen2WorldMapLayer
extends Node2D

## One map's blocks, drawn as a single quad.
##
## `LoadMetatiles` resolves a block byte to sixteen graphics tiles every time it
## refreshes the screen, and the renderer used to do the same on the CPU: one
## draw per 8x8 tile, 380 of them for a hardware screen. A view that fills the
## window at one pixel per world pixel wants tens of thousands, and a view that
## takes in a whole region wants hundreds of thousands, which no per-tile loop
## reaches at sixty frames a second.
##
## So the fold moves to the GPU. The block buffer, the tileset's metatile table
## and the coloured tile strip go across as three byte textures and the fragment
## shader does exactly what [method Gen2WorldAPI.drawn_block_at] does: block
## byte, `$00` to the map's border block, metatile slot, tile, pixel. Nothing is
## baked, so the strip the animation and the map fades already repaint is the
## one this samples and neither needs a second path.
##
## Drawn behind its parent, so the renderer's own sprites stay above the map.

## The three lookups a tile costs, in one pass. `map_blocks` of zero is the void
## fill: every block is the border block, which is what surrounds a map on the
## cartridge and what fills the window past the last connected map here.
const MAP_SHADER: String = """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform sampler2D blocks : filter_nearest, repeat_disable;
uniform sampler2D block_tiles : filter_nearest, repeat_disable;
uniform highp vec2 map_blocks = vec2(0.0, 0.0);
uniform highp vec2 view_origin = vec2(0.0, 0.0);
uniform highp float border_block = 0.0;
uniform highp float block_count = 1.0;
uniform highp float tile_count = 1.0;
uniform bool fill_border = false;

varying highp vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	highp vec2 world = floor(local_pos + view_origin);
	highp vec2 at = floor(world / 32.0);
	highp float block = border_block;
	if (at.x >= 0.0 && at.y >= 0.0 && at.x < map_blocks.x && at.y < map_blocks.y) {
		block = floor(texture(blocks, (at + 0.5) / max(map_blocks, vec2(1.0))).r * 255.0 + 0.5);
		if (block < 0.5) {
			block = border_block;
		}
	} else if (!fill_border) {
		discard;
	}
	highp vec2 inside = world - at * 32.0;
	highp vec2 cell = floor(inside / 8.0);
	highp float slot = cell.y * 4.0 + cell.x;
	highp float tile = floor(texture(block_tiles,
		vec2((slot + 0.5) / 16.0, (block + 0.5) / max(block_count, 1.0))).r * 255.0 + 0.5);
	highp vec2 pixel = inside - cell * 8.0;
	COLOR = texture(atlas, vec2((tile * 8.0 + pixel.x + 0.5) / max(tile_count * 8.0, 1.0),
		(pixel.y + 0.5) / 8.0));
}
"""

## One compiled program for every layer: the uniforms differ per map, the code
## never does.
static var _shader: Shader = null

var _material := ShaderMaterial.new()
var _quad := Rect2()


func _init() -> void:
	show_behind_parent = true
	if _shader == null:
		_shader = Shader.new()
		_shader.code = MAP_SHADER
	_material.shader = _shader
	material = _material


## [param blocks] is one byte per block in row-major order, [param block_tiles]
## the tileset's own sixteen-bytes-a-block metatile table, and [param atlas] the
## coloured tile strip the renderer already keeps.
func configure(
	atlas: Texture2D,
	blocks: Texture2D,
	block_tiles: Texture2D,
	map_blocks: Vector2i,
	border_block: int,
	block_count: int,
	tile_count: int,
	fill_border: bool,
) -> void:
	_material.set_shader_parameter(&"atlas", atlas)
	_material.set_shader_parameter(&"blocks", blocks)
	_material.set_shader_parameter(&"block_tiles", block_tiles)
	_material.set_shader_parameter(&"map_blocks", Vector2(map_blocks))
	_material.set_shader_parameter(&"border_block", float(border_block))
	_material.set_shader_parameter(&"block_count", float(maxi(block_count, 1)))
	_material.set_shader_parameter(&"tile_count", float(maxi(tile_count, 1)))
	_material.set_shader_parameter(&"fill_border", fill_border)


## Where the quad goes on screen and which world pixel its own origin is.
## [param origin] is zero for a map, whose quad starts at its own first block,
## and the camera's own 32-pixel phase for the void fill, which is one quad over
## the whole view rather than a map.
func place(at: Vector2, size: Vector2, origin: Vector2 = Vector2.ZERO) -> void:
	position = at
	_material.set_shader_parameter(&"view_origin", origin)
	if _quad.size != size:
		_quad = Rect2(Vector2.ZERO, size)
		queue_redraw()


func _draw() -> void:
	if _quad.size.x <= 0.0 or _quad.size.y <= 0.0:
		return
	draw_rect(_quad, Color.WHITE, true)


## The block buffer as a byte texture. [param bytes] is one block per byte in
## row-major order and is padded rather than refused: a short cache row draws as
## the map's border block, which is what the missing blocks would be.
static func block_texture(bytes: PackedByteArray, size: Vector2i) -> ImageTexture:
	if size.x <= 0 or size.y <= 0:
		return null
	var padded: PackedByteArray = bytes
	if padded.size() != size.x * size.y:
		padded = bytes.duplicate()
		padded.resize(size.x * size.y)
	return ImageTexture.create_from_image(
		Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, padded)
	)
