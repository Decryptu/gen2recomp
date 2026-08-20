class_name Gen2BattleAnimObject
extends RefCounted

## One animation object: a `battle_anim_struct` and the two routines that read it
## (engine/battle_anims/core.asm, engine/battle_anims/helpers.asm).
##
## An object is spawned by `anim_obj`, which names a row of `BattleAnimObjects`
## and a place to put it. The row supplies the frameset, the motion callback, the
## palette and which graphics sheet its tiles come from; the command supplies the
## coordinates and a parameter the callback reads.
##
## Every field is a cartridge byte and is kept as one. The coordinates wrap at
## 256 because they are single bytes on hardware, and several animations rely on
## that: an object walking off one side is the wrap, not a clamp.
##
## `frame` starts at -1 rather than 0. `GetBattleAnimFrame` increments before it
## reads, so the first frame drawn is the frameset's first entry.

## Byte positions inside the struct, as `battleanimobj` orders them. Only the
## six a `BattleAnimObjects` row carries; the rest are runtime state.
const OAM_FLAGS_FIX_COORDS: int = 1 << 0

## `oam_anims.asm`. Anything below [constant Gen2BattleAnimImporter.OAM_DELETE]
## is an OAM set id.
const OAM_DELETE: int = Gen2BattleAnimImporter.OAM_DELETE
const OAM_WAIT: int = Gen2BattleAnimImporter.OAM_WAIT
const OAM_RESTART: int = Gen2BattleAnimImporter.OAM_RESTART
const OAM_END: int = Gen2BattleAnimImporter.OAM_END

## Hardware OAM attribute bits (constants/hardware.inc).
const OAM_PRIORITY: int = 1 << 7
const OAM_YFLIP: int = 1 << 6
const OAM_XFLIP: int = 1 << 5
const OAM_PAL1: int = 1 << 4
const OAM_BANK1: int = 1 << 3
const OAM_PALETTE: int = 0x07
## The three bits an object and its frame both have an opinion about, and which
## are therefore combined by XOR rather than replaced.
const OAM_SHARED_FLAGS: int = OAM_PRIORITY | OAM_YFLIP | OAM_XFLIP

## `BATTLEANIM_BASE_TILE`, `7 * 7`: every OAM tile id is counted from here,
## which is the first tile past the largest Pokemon picture.
const BASE_TILE: int = 49

## `InitBattleAnimBuffer`'s enemy-side coordinate fix. The x mirror is
## `ld a, (-10 * TILE_WIDTH) + 4` then `sub d`, which is `$b4 - x` in a byte.
const ENEMY_X_MIRROR: int = 0xB4
## `$ff` in the row's y-fix byte means "add five tiles" rather than "mirror".
const Y_FIX_ADD: int = 0xFF
const Y_FIX_ADD_PIXELS: int = 5 * 8

## The three moves whose enemy-side y fix is one tile higher, checked by move
## number with `wFXAnimID`'s high byte clear so only a move animation matches.
const Y_FIX_RAISED_MOVES: Array[int] = [0x86, 0x87, 0xD0]  # KINESIS, SOFTBOILED, MILK_DRINK
const Y_FIX_RAISED_PIXELS: int = 8

## Runaway guard for `GetBattleAnimFrame`'s own loop, which `oamrestart` and
## `oamend` can each send round again. The cartridge has no limit; a frameset
## whose first entry is `oamrestart` spins there forever.
const MAX_FRAME_STEPS: int = 64

var index: int = 0
var oam_flags: int = 0
var y_fix: int = 0
var frameset: int = 0
var function: int = 0
var palette: int = 0
var tile_id: int = 0
var x: int = 0
var y: int = 0
var x_offset: int = 0
var y_offset: int = 0
var param: int = 0
var duration: int = 0
var frame: int = 0xFF
var jumptable_index: int = 0
var var1: int = 0
var var2: int = 0

## Set by `GetBattleAnimFrame` for the frame about to be drawn, from the two flip
## bits in an `oamframe`'s second byte. Not part of the struct: the cartridge
## keeps it in `wBattleAnimTempFrameOAMFlags`, one frame at a time.
var _frame_flags: int = 0


## `InitBattleAnimation`. [param row] is a `BattleAnimObjects` row and
## [param tile_id] is what `GetBattleAnimTileOffset` answered for its graphics.
static func create(
	object_index: int, row: Dictionary, tile: int,
	at_x: int, at_y: int, parameter: int
) -> Gen2BattleAnimObject:
	var out := Gen2BattleAnimObject.new()
	out.index = object_index & 0xFF
	out.oam_flags = int(row.get(&"flags", 0))
	out.y_fix = int(row.get(&"y_fix", 0))
	out.frameset = int(row.get(&"frameset", 0))
	out.function = int(row.get(&"function", 0))
	out.palette = int(row.get(&"palette", 0))
	out.tile_id = tile & 0xFF
	out.x = at_x & 0xFF
	out.y = at_y & 0xFF
	out.param = parameter & 0xFF
	out.frame = 0xFF
	return out


## `DeinitBattleAnimation`: zeroing the index is what frees the slot.
func deinit() -> void:
	index = 0


func active() -> bool:
	return index != 0


## `BattleAnimOAMUpdate`, as the sprites it would write into `wShadowOAM`.
##
## Returns [code]{ deleted, sprites }[/code]. `sprites` is empty for an
## `oamwait`, which is a frame the object is simply not drawn on, and for the
## `oamdelete` that ends it; `deleted` says which of the two happened.
##
## [param enemy_turn] is `hBattleTurn`, the only thing that decides whether the
## coordinates are mirrored onto the other side of the field.
func oam_update(
	data: Gen2BattleAnimData, enemy_turn: bool, anim_index: int
) -> Dictionary:
	var buffer: Dictionary = _init_buffer(enemy_turn, anim_index)
	var command: int = _next_frame(data)
	if command == OAM_WAIT:
		return {"deleted": false, "sprites": []}
	if command == OAM_DELETE:
		deinit()
		return {"deleted": true, "sprites": []}

	# The object's own flags and the frame's own are combined rather than one
	# replacing the other, so a frameset can flip a sprite the row did not.
	var flags: int = (_frame_flags ^ int(buffer["flags"])) & OAM_SHARED_FLAGS

	var oam: Dictionary = data.oam_set(command)
	if oam.is_empty():
		return {"deleted": false, "sprites": []}
	var tile: int = (int(buffer["tile_id"]) + int(oam["vtile"])) & 0xFF

	var sprites: Array = []
	for slot: int in int(oam["length"]):
		var sprite: Dictionary = data.oam_sprite(int(oam["address"]), slot)
		sprites.append({
			"y": _place(
				int(sprite["y"]), int(buffer["y"]), int(buffer["y_offset"]),
				(flags & OAM_YFLIP) != 0
			),
			"x": _place(
				int(sprite["x"]), int(buffer["x"]), int(buffer["x_offset"]),
				(flags & OAM_XFLIP) != 0
			),
			"tile": (tile + BASE_TILE + int(sprite["tile"])) & 0xFF,
			"attributes": _attributes(int(sprite["attributes"]), flags, int(buffer["palette"])),
		})
	return {"deleted": false, "sprites": sprites}


## `InitBattleAnimBuffer`: the coordinates and flags this frame is drawn with,
## which are the struct's own on the player's turn and mirrored on the enemy's.
func _init_buffer(enemy_turn: bool, anim_index: int) -> Dictionary:
	var buffer: Dictionary = {
		"flags": oam_flags & OAM_PRIORITY,
		"palette": palette,
		"tile_id": tile_id,
		"x": x,
		"y": y,
		"x_offset": x_offset,
		"y_offset": y_offset,
	}
	if not enemy_turn:
		return buffer

	# On the enemy's turn the whole flags byte is taken, so the row's own y and x
	# flip bits come into play as well as its priority.
	buffer["flags"] = oam_flags
	if (oam_flags & OAM_FLAGS_FIX_COORDS) == 0:
		return buffer

	buffer["x"] = (ENEMY_X_MIRROR - x) & 0xFF
	if y_fix == Y_FIX_ADD:
		buffer["y"] = (Y_FIX_ADD_PIXELS + y) & 0xFF
	else:
		var fixed: int = (y_fix - y) & 0xFF
		# `wFXAnimID`'s high byte has to be clear, so only a move animation can
		# match: the non-move ids from $100 up share these low bytes.
		if anim_index < 0x100 and Y_FIX_RAISED_MOVES.has(anim_index):
			fixed = (fixed - Y_FIX_RAISED_PIXELS) & 0xFF
		buffer["y"] = fixed
	buffer["x_offset"] = (-x_offset) & 0xFF
	return buffer


## One sprite's place on screen: its own offset within the set, flipped about its
## own eight pixels if the frame is flipped, then moved to the object.
func _place(within: int, origin: int, offset: int, flipped: bool) -> int:
	var value: int = within
	if flipped:
		value = (-(value + 8)) & 0xFF
	return (value + origin + offset) & 0xFF


## The sprite's own attribute byte, its flips combined with the frame's, its DMG
## palette bit kept, and the object's own CGB palette and bank put in.
func _attributes(attributes: int, flags: int, object_palette: int) -> int:
	return ((attributes ^ flags) & OAM_SHARED_FLAGS) \
		| (attributes & OAM_PAL1) \
		| (object_palette & (OAM_PALETTE | OAM_BANK1))


## `GetBattleAnimFrame`. Answers the OAM set to draw, or one of the three
## commands, and leaves [member _frame_flags] set for the frame it chose.
##
## While a frame still has duration left it is redrawn without advancing.
## `oamend` steps back two and loops, which redraws the last real frame forever;
## `oamrestart` goes back to -1 and loops, which starts the frameset again.
func _next_frame(data: Gen2BattleAnimData) -> int:
	for _step: int in MAX_FRAME_STEPS:
		if duration != 0:
			duration = (duration - 1) & 0xFF
			var held: int = _frame_byte(data, 0)
			_frame_flags = _flags_of(_frame_byte(data, 1))
			return held

		frame = (frame + 1) & 0xFF
		var command: int = _frame_byte(data, 0)
		if command == OAM_RESTART:
			duration = 0
			frame = 0xFF
			continue
		if command == OAM_END:
			duration = 0
			frame = (frame - 2) & 0xFF
			continue

		var second: int = _frame_byte(data, 1)
		# The duration keeps only the bits the flips do not use, and the flips
		# live one bit higher than OAM's own, which is what leaves room for it.
		duration = second & ~((OAM_YFLIP | OAM_XFLIP) << 1) & 0xFF
		_frame_flags = _flags_of(second)
		return command
	return OAM_WAIT


## `.GetPointer` plus an offset: a frameset entry is two bytes and frames index
## it directly, terminators included.
func _frame_byte(data: Gen2BattleAnimData, at: int) -> int:
	var base: int = data.frameset_address(frameset)
	if base < 0:
		return OAM_END
	return data.byte_at(&"framesets", base + frame * 2 + at)


## An `oamframe`'s flip bits, which the macro stores one bit higher than OAM
## does so they cannot collide with the duration.
func _flags_of(second: int) -> int:
	return (second & ((OAM_YFLIP | OAM_XFLIP) << 1)) >> 1
