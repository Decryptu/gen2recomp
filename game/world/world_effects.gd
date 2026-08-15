class_name Gen2WorldEffects
extends RefCounted

## Scene-free presentation state for effects that the overworld engine paces in
## hardware frames. The renderer owns the pixels; this class owns the source
## duration, amplitude and deterministic offsets.
##
## Two shapes live here. `ShakeScreen` is one packed byte of duration and
## amplitude. The rest are the sprites the engine draws over the map rather than
## as map objects: `SpawnStrengthBoulderDust`, `ShakeGrass`, `ShakeHeadbuttTree`,
## `OWCutAnimation` and `SpawnShadow`, each its own frameset over one of the
## sheets GameData.overworld_effect() holds.

var _frame: int = 0
var _duration: int = 0
var _amplitude: int = 0
var _kind: StringName = &"none"
var _source: Dictionary = {}
var _sprites: Array = []

## The effect sprites, each named for the sheet it draws from.
const SPRITE_BOULDER_DUST: StringName = &"boulder_dust"
const SPRITE_GRASS_RUSTLE: StringName = &"grass_rustle"
const SPRITE_HEADBUTT_TREE: StringName = &"headbutt_tree"
const SPRITE_CUT_TREE: StringName = &"cut_tree"
const SPRITE_CUT_LEAF: StringName = &"cut_grass"
const SPRITE_SHADOW: StringName = &"shadow"

## constants/sprite_data_constants.asm. Every emote-object spawn names its
## palette: PAL_OW_EMOTE for the dust and the emote bubbles, PAL_OW_TREE for the
## grass and for `.OAMData_Tree`.
const PAL_OW_EMOTE: int = 5
const PAL_OW_TREE: int = 6

## ShakeHeadbuttTree's `ld a, 32 / ld [wFrameCounter], a`, and OWCutAnimation's
## own, which both branches of its jumptable write.
const HEADBUTT_TREE_FRAMES: int = 32
const CUT_FRAMES: int = 32

## `.Frameset_CutTree`, as [first frame, tile offsets] pairs. `oamframe X, n`
## lasts n + 1 frames and `oamwait n` draws nothing for n + 1, which is what puts
## the two gaps in: the tree stands for three frames, splits for seventeen, and
## then its halves slide apart in two steps of two. `oamdelete` ends it four
## frames before the counter does.
const CUT_TREE_STEPS: Array = [
	[0, [Vector2i(0, 0), Vector2i(8, 0), Vector2i(0, 8), Vector2i(8, 8)]],
	[3, [Vector2i(-2, 0), Vector2i(10, 0), Vector2i(-2, 8), Vector2i(10, 8)]],
	[20, []],
	[22, [Vector2i(-4, 0), Vector2i(12, 0), Vector2i(-4, 8), Vector2i(12, 8)]],
	[24, []],
	[26, [Vector2i(-8, 0), Vector2i(16, 0), Vector2i(-8, 8), Vector2i(16, 8)]],
	[28, []],
]

## `Cut_GetLeafSpawnCoords`, as pixel offsets from where the player is drawn.
## Its own table is screen coordinates, indexed by the facing and then by which
## quarter of the block the player stands in, because Cut clears the whole block
## and the leaves are spawned over it. Order is the source's: DOWN, UP, LEFT,
## RIGHT, each with top-left, top-right, bottom-left, bottom-right.
const CUT_LEAF_ORIGINS: Array[Vector2i] = [
	Vector2i(16, 16), Vector2i(0, 16), Vector2i(16, 32), Vector2i(0, 32),
	Vector2i(16, -16), Vector2i(0, -16), Vector2i(16, 0), Vector2i(0, 0),
	Vector2i(-16, 16), Vector2i(0, 16), Vector2i(-16, 0), Vector2i(0, 0),
	Vector2i(16, 16), Vector2i(32, 16), Vector2i(16, 0), Vector2i(32, 0),
]

## `Cut_SpawnAnimateLeaves` spawns four leaves an eighth of a turn apart, and
## `SpriteAnimFunc_CutLeaves` steps each angle by three a frame while the radius
## it is multiplied by grows by half a pixel.
const CUT_LEAF_ANGLES: Array[int] = [0x00, 0x10, 0x20, 0x30]
const CUT_LEAF_ANGLE_STEP: int = 3
const CUT_LEAF_RADIUS_STEP: int = 0x80
## `.OAMData_Leaf`'s single `dbsprite -1, -1, 4, 4`.
const CUT_LEAF_OFFSET := Vector2i(-4, -4)

## The rod tile `FacingFishDown` and its three siblings add to the player's own
## four, in Gen2WorldSprite's DOWN, UP, LEFT, RIGHT order: offset, which of the
## two rod tiles, and whether it is mirrored. The player picture itself is the
## standing one, so the rod is the whole difference.
const FISHING_ROD_TILES: Array = [
	{"offset": Vector2i(0, 16), "tile": 0, "flip_x": false},
	{"offset": Vector2i(0, -8), "tile": 0, "flip_x": false},
	{"offset": Vector2i(-8, 5), "tile": 1, "flip_x": true},
	{"offset": Vector2i(16, 5), "tile": 1, "flip_x": false},
]


## `MovementFunction_Shadow`: y offset 14 along the axis the jump is on and 12
## across it, x offset zero, in the source's DOWN, UP, LEFT, RIGHT order.
const SHADOW_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 14), Vector2i(0, 14), Vector2i(0, 12), Vector2i(0, 12),
]

## `MovementFunction_BoulderDust`'s `.dust_coords`, indexed by the boulder's own
## walking direction in the source's DOWN, UP, LEFT, RIGHT order.
const DUST_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -4), Vector2i(0, 8), Vector2i(6, 2), Vector2i(-6, 2),
]


func start_screen_shake(packed_value: int, kind: StringName = &"screen_shake", source: Dictionary = {}) -> Dictionary:
	var value: int = clampi(packed_value, 0, 0xFF)
	_duration = value & 0x3F
	_amplitude = 1 << ((value >> 6) & 0x03) if _duration > 0 else 0
	_frame = 0
	_kind = kind if _duration > 0 else &"none"
	_source = source.duplicate(true)
	return snapshot()


## `ShakeHeadbuttTree` over the cell the player is facing: the tree's four tiles
## are replaced with the tileset's own grass tile and an eight-tile sheet is
## animated in front of them for 32 frames.
func start_headbutt_tree(cell: Vector2i) -> void:
	_sprites.append({
		"kind": SPRITE_HEADBUTT_TREE,
		"cell": cell,
		"object_index": -2,
		"palette": PAL_OW_TREE,
		"frame": 0,
		"duration": HEADBUTT_TREE_FRAMES,
	})


## `OWCutAnimation`, over the cell the block being cut is faced from. Index 0 is
## the splitting tree and index 1 the four leaves (`Gen2WorldFieldMove`'s
## ANIMATION_TREE and ANIMATION_GRASS), which is the byte
## `CheckOverworldTileArrays` returns beside the replacement block.
##
## [param player_cell] is where the player stands, which is what picks the
## leaves' own corner of the block.
func start_cut(
	cell: Vector2i, animation: int, direction: Vector2i, player_cell: Vector2i
) -> void:
	if animation == 0:
		_sprites.append({
			"kind": SPRITE_CUT_TREE,
			"cell": cell,
			"object_index": -2,
			"palette": PAL_OW_TREE,
			"frame": 0,
			"duration": CUT_FRAMES,
		})
		return
	var origin: Vector2i = CUT_LEAF_ORIGINS[
		_direction_index(direction) * 4 + (player_cell.x & 1) + (player_cell.y & 1) * 2
	]
	for angle: int in CUT_LEAF_ANGLES:
		_sprites.append({
			"kind": SPRITE_CUT_LEAF,
			"cell": cell,
			"object_index": -1,
			"palette": PAL_OW_TREE,
			"frame": 0,
			"duration": CUT_FRAMES,
			"origin": origin,
			"angle": angle,
		})


## `SpawnShadow`, under a jumping object for twice the jump it was spawned in.
## Tracks whoever is jumping, and sits below them because the jump is an offset
## on the sprite alone.
func start_jump_shadow(object_index: int, cell: Vector2i, direction: Vector2i, step_frames: int) -> void:
	_sprites.append({
		"kind": SPRITE_SHADOW,
		"cell": cell,
		"object_index": object_index,
		"palette": PAL_OW_EMOTE,
		"frame": 0,
		"duration": (int(float(maxi(0, step_frames)) / 2.0) + 1) * 2,
		"direction": _direction_index(direction),
	})


## `ShakeGrass`, spawned where a step onto grass starts and tracking whoever
## took it. [param frames] is the step's own duration less one.
func start_grass_rustle(object_index: int, cell: Vector2i, frames: int) -> void:
	if frames <= 0:
		return
	_sprites.append({
		"kind": SPRITE_GRASS_RUSTLE,
		"cell": cell,
		"object_index": object_index,
		"palette": PAL_OW_TREE,
		"frame": 0,
		"duration": frames,
	})


## `SpawnStrengthBoulderDust`, spawned where the boulder starts sliding.
## `MovementFunction_BoulderDust` spends `(step duration + 1) * 2` frames, so the
## dust outlives the push.
func start_boulder_dust(object_index: int, cell: Vector2i, direction: Vector2i, step_frames: int) -> void:
	_sprites.append({
		"kind": SPRITE_BOULDER_DUST,
		"cell": cell,
		"object_index": object_index,
		"palette": PAL_OW_EMOTE,
		"frame": 0,
		"duration": (maxi(0, step_frames) + 1) * 2,
		"direction": _direction_index(direction),
	})


func advance_frame() -> bool:
	var moved: bool = false
	var running: Array = []
	for sprite: Dictionary in _sprites:
		sprite["frame"] = int(sprite["frame"]) + 1
		if int(sprite["frame"]) < int(sprite["duration"]):
			running.append(sprite)
		moved = true
	_sprites = running
	if not active():
		return moved
	_frame += 1
	if not active():
		_kind = &"none"
		_source = {}
	return true


func active() -> bool:
	return _frame < _duration and _duration > 0


## Whether any effect sprite is still on screen.
func sprites_active() -> bool:
	return not _sprites.is_empty()


func offset() -> Vector2:
	if not active():
		return Vector2.ZERO
	var magnitude: float = float(_amplitude)
	match _frame & 3:
		0: return Vector2(-magnitude, 0.0)
		1: return Vector2(magnitude, 0.0)
		2: return Vector2(0.0, -magnitude)
		_: return Vector2(0.0, magnitude)


## What a renderer draws this frame: one record per live sprite, each carrying
## the sheet it reads, the palette row it wears and the tiles `Facings` or the
## frameset places, as pixel offsets from the anchor.
##
## The anchor is the cell for the headbutt tree, whose sprite stands still, and
## the tracked object's own drawn position for the other two, which are
## STEP_TYPE_TRACKING_OBJECT and follow whatever spawned them.
func sprites() -> Array:
	var out: Array = []
	for sprite: Dictionary in _sprites:
		out.append({
			"kind": sprite["kind"],
			"cell": sprite["cell"],
			"object_index": int(sprite["object_index"]),
			"palette": int(sprite["palette"]),
			"frame": int(sprite["frame"]),
			"tiles": _tiles_for(sprite),
		})
	return out


## The cells a live effect takes the map's own tiles away from.
## `HideHeadbuttTree` writes the tileset's grass tile over the tree's four
## graphics tiles while the animation runs, which is what stops the tree drawing
## through it.
func hidden_tree_cells() -> Array:
	var out: Array = []
	for sprite: Dictionary in _sprites:
		if StringName(sprite["kind"]) == SPRITE_HEADBUTT_TREE:
			out.append(sprite["cell"])
	return out


## The tile the four hidden ones are replaced with, which the source's own
## comment pins: "Assumes any tileset with headbutt trees has grass at tile $05".
const HEADBUTT_TREE_HIDDEN_TILE: int = 0x05


func snapshot() -> Dictionary:
	return {
		"active": active(),
		"kind": _kind,
		"frame": _frame,
		"duration": _duration,
		"amplitude": _amplitude,
		"offset": offset(),
		"source": _source.duplicate(true),
		"sprites": sprites(),
	}


## One sprite's tiles this frame: [{ offset, tile, flip_x }], where `tile` is an
## index into the sheet the kind names.
func _tiles_for(sprite: Dictionary) -> Array:
	var frame: int = int(sprite["frame"])
	match StringName(sprite["kind"]):
		SPRITE_HEADBUTT_TREE:
			## `.Frameset_HeadbuttTree` is four `oamframe`s of two, which last
			## three frames each: tiles 0-3, tiles 4-7, tiles 0-3, then tiles 4-7
			## with each tile flipped where it stands.
			var step: int = int(float(frame % 12) / 3.0)
			var base: int = 0 if step == 0 or step == 2 else 4
			var flip: bool = step == 3
			var tiles: Array = []
			for index: int in 4:
				tiles.append({
					"offset": Vector2i((index & 1) * 8, (index >> 1) * 8),
					"tile": base + index,
					"flip_x": flip,
				})
			return tiles
		SPRITE_GRASS_RUSTLE:
			## `SetFacingGrassShake` swaps FACING_GRASS_1 and FACING_GRASS_2 on
			## bit 2 of the step frame, so each is up for four frames, and the
			## second sits one pixel down and one out on each side.
			if frame & 4 == 0:
				return [
					{"offset": Vector2i(0, 8), "tile": 0, "flip_x": false},
					{"offset": Vector2i(8, 8), "tile": 0, "flip_x": true},
				]
			return [
				{"offset": Vector2i(-1, 9), "tile": 0, "flip_x": false},
				{"offset": Vector2i(9, 9), "tile": 0, "flip_x": true},
			]
		SPRITE_CUT_TREE:
			## The frameset's own steps, held until the next one starts and gone
			## once `oamdelete` is reached.
			var tree: Array = []
			for step: Array in CUT_TREE_STEPS:
				if frame < int(step[0]):
					break
				tree = step[1]
			var cut: Array = []
			for index: int in tree.size():
				cut.append({"offset": tree[index], "tile": index, "flip_x": false})
			return cut
		SPRITE_CUT_LEAF:
			## `SpriteAnimFunc_CutLeaves`: the leaf sits on a circle whose angle
			## steps by three a frame and whose radius is the high byte of a
			## sixteen-bit accumulator growing by $80, so it widens every second
			## frame. `AnimSeqs_Sine` is the y offset and `AnimSeqs_Cosine` the x.
			var radius: int = int(float(frame * CUT_LEAF_RADIUS_STEP) / 256.0)
			var angle: int = (int(sprite["angle"]) + frame * CUT_LEAF_ANGLE_STEP) & 0xFF
			return [{
				"offset": (sprite["origin"] as Vector2i) + CUT_LEAF_OFFSET + Vector2i(
					_signed(_cosine(angle, radius)), _signed(_sine(angle, radius))
				),
				"tile": 0,
				"flip_x": false,
			}]
		SPRITE_SHADOW:
			## `FacingShadow`: one tile drawn twice, the second mirrored.
			var at: Vector2i = SHADOW_OFFSETS[int(sprite.get("direction", 0))]
			return [
				{"offset": at, "tile": 0, "flip_x": false},
				{"offset": at + Vector2i(8, 0), "tile": 0, "flip_x": true},
			]
		SPRITE_BOULDER_DUST:
			## `SetFacingBoulderDust` swaps FACING_BOULDER_DUST_1 and _2 on bit 1
			## of the step frame, and each draws its one tile four times in a
			## 16x16 square at the direction's own offset.
			var dust_tile: int = 0 if frame & 2 == 0 else 1
			var at: Vector2i = DUST_OFFSETS[int(sprite.get("direction", 0))]
			var dust: Array = []
			for index: int in 4:
				dust.append({
					"offset": at + Vector2i((index & 1) * 8, (index >> 1) * 8),
					"tile": dust_tile,
					"flip_x": false,
				})
			return dust
	return []


## `BattleAnim_Sine` and `..._Cosine` over `BattleAnimSineWave`, which is what
## `AnimSeqs_Sine` reaches. The table is cartridge data rather than a derivation
## (entry 16 is $0100), so a caller with no cache draws no leaves rather than
## drawing them on a table of its own.
var _sine_table: Gen2BattleAnimData = null


## Hands this the sine table the cut leaves ride on. Called once by the screen
## that owns the effects; nothing else here needs a cache.
func set_sine_table(sine: Gen2BattleAnimData) -> void:
	_sine_table = sine


func _sine(angle: int, amplitude: int) -> int:
	return Gen2BattleAnimFunctions.sine_of(_sine_table, angle, amplitude) \
		if _sine_table != null else 0


func _cosine(angle: int, amplitude: int) -> int:
	return Gen2BattleAnimFunctions.cosine_of(_sine_table, angle, amplitude) \
		if _sine_table != null else 0


## A sprite offset is a byte the cartridge adds; a renderer drawing at a signed
## pixel needs the same byte read as a two's complement offset.
static func _signed(value: int) -> int:
	return value - 0x100 if value >= 0x80 else value


## The source's DOWN, UP, LEFT, RIGHT order, which is what `.dust_coords` is
## indexed by.
static func _direction_index(direction: Vector2i) -> int:
	if direction == Vector2i.UP:
		return 1
	if direction == Vector2i.LEFT:
		return 2
	if direction == Vector2i.RIGHT:
		return 3
	return 0
