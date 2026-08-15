class_name Gen2WorldEffects
extends RefCounted

## Scene-free presentation state for effects that the overworld engine paces in
## hardware frames. The renderer owns the pixels; this class owns the source
## duration, amplitude and deterministic offsets.
##
## Two shapes live here. `ShakeScreen` is one packed byte of duration and
## amplitude. The rest are the sprites the engine draws over the map rather than
## as map objects: `SpawnStrengthBoulderDust`, `ShakeGrass` and
## `ShakeHeadbuttTree`, each its own frameset over one of the sheets
## GameData.overworld_effect() holds.

var _frame: int = 0
var _duration: int = 0
var _amplitude: int = 0
var _kind: StringName = &"none"
var _source: Dictionary = {}
var _sprites: Array = []

## The three effect sprites, by the sheet each draws from.
const SPRITE_BOULDER_DUST: StringName = &"boulder_dust"
const SPRITE_GRASS_RUSTLE: StringName = &"grass_rustle"
const SPRITE_HEADBUTT_TREE: StringName = &"headbutt_tree"

## constants/sprite_data_constants.asm. Every emote-object spawn names its
## palette: PAL_OW_EMOTE for the dust and the emote bubbles, PAL_OW_TREE for the
## grass and for `.OAMData_Tree`.
const PAL_OW_EMOTE: int = 5
const PAL_OW_TREE: int = 6

## ShakeHeadbuttTree's `ld a, 32 / ld [wFrameCounter], a`.
const HEADBUTT_TREE_FRAMES: int = 32

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
static func _tiles_for(sprite: Dictionary) -> Array:
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
