class_name Gen2BattleIntro
extends RefCounted

## `BattleIntroSlidingPics` (engine/battle/sliding_intro.asm) is a background
## scroll, not a moving object: `SCX` is rewritten part way down the frame so the
## top band comes in from one side and the middle from the other while the bottom
## holds. A band edge falls inside the player's status panel, hence per scanline.
## `InitBattleDisplay.BlankBGMap` leaves everything past the scene blank, so an
## offset wraps at [constant MAP_WIDTH] and blank scrolls in.
##
## The one part of the battle presentation the two games do not share: Crystal
## drives `wLYOverrides` while pokegold busy-waits on `rLY` and writes `rSCX`
## twice a frame, so band edges, starting offsets and the walk all differ.
## Neither band lands on zero (Crystal's middle ends at 2, Gold's top at 4);
## `InitBattleDisplay`'s `xor a` / `ldh [hSCX], a` settles it and [method
## finished] is that write.
##
## The player is in two pieces while it runs, and reading `.subfunction3` as the
## overworld's leftovers cost a session: the eighteen sprites it walks are
## `CopyBackpic.LoadTrainerBackpicAsOAM`'s own, which is the top three tile rows
## of the player's back pic drawn as OAM. The bottom of that pic is on the
## background and comes in with the middle band, and the two track each other to
## within the two pixels `InitBattleDisplay`'s `xor a` / `ldh [hSCX], a` settles.
## Without the sprites the player has no head and no shoulders for the whole
## slide. `HideSprites` is what takes them off, after which `PlaceGraphic` puts
## the whole pic on the background at its own square.

## 32 tiles of 8, what an offset wraps at; past the screen's 160 is blank.
const MAP_WIDTH: int = 256

const HEIGHT: int = Gen2Screen.HEIGHT

## Twice per frame in opposite directions: `dec d` twice against `inc e` twice.
const STEP: int = 2

## Crystal's `ld d, $90` and `ld e, $72` over `.subfunction5`'s 62, 34 and 48.
const CRYSTAL_FRAMES: int = 73
const CRYSTAL_TOP_START: int = 0x90
const CRYSTAL_MIDDLE_START: int = 0x72
const CRYSTAL_TOP_ROWS: int = 62
const CRYSTAL_MIDDLE_ROWS: int = 34

## Gold and Silver's `ld b, $70` and `ld c, $90`, with `rSCX` rewritten at `rLY`
## 64 and 96, for the 72 frames `dec c` twice takes to reach zero.
const GOLD_LOOP_FRAMES: int = 72
const GOLD_TOP_START: int = 0x90
const GOLD_MIDDLE_START: int = 0x70
const GOLD_TOP_ROWS: int = 64
const GOLD_MIDDLE_ROWS: int = 32

## `ld a, c` / `ldh [hSCX], a` / `call DelayFrame` puts the whole screen at the
## starting offset with no band written yet. Crystal delays nowhere.
const GOLD_LEAD_FRAMES: int = 1

## `.LoadTrainerBackpicAsOAM`: six columns of three, `ld e, (SCREEN_WIDTH + 1) *
## TILE_WIDTH` for the first x and `ld d, 8 * TILE_WIDTH` for the first y, both
## stepping one tile. The tile ids are the back pic's own, column major over its
## six rows, so a column contributes its top three.
const SPRITE_COLUMNS: int = 6
const SPRITE_ROWS: int = 3
const SPRITE_FIRST_X: int = (Gen2BattleAnimBackground.SCREEN_WIDTH + 1) * Gen2Tiles.TILE_WIDTH
const SPRITE_FIRST_Y: int = 8 * Gen2Tiles.TILE_HEIGHT
## `PLAYER_SIDE` rows to a column in `vTiles0`, which is where `CopyBackpic`
## decompressed the pic before copying it into `vTiles2 tile $31`.
const SPRITE_PIC_ROWS: int = Gen2BattleScreenMap.PLAYER_SIDE
## `dec [hl]` twice per sprite.
const SPRITE_STEP: int = 2

var _crystal: bool = true
var _frame: int = 0


static func for_data(data: GameData) -> Gen2BattleIntro:
	return create(Gen2WorldState.is_crystal_profile(data))


static func create(crystal: bool) -> Gen2BattleIntro:
	var intro := Gen2BattleIntro.new()
	intro._crystal = crystal
	return intro


## Both games take the same number, by different arithmetic.
func frames() -> int:
	return CRYSTAL_FRAMES if _crystal else GOLD_LEAD_FRAMES + GOLD_LOOP_FRAMES


func finished() -> bool:
	return _frame >= frames()


## One hardware frame. The settle to zero is a redraw like any other.
func advance_frame() -> bool:
	if finished():
		return false
	_frame += 1
	return true


## `.LoadTrainerBackpicAsOAM` and `.subfunction3` together: the player's own
## eighteen sprites where this frame leaves them, each { tile, x, y } with OAM's
## own biased coordinates, which is what a renderer of one already takes.
##
## Gold and Silver walk the same eighteen: `.LoadTrainerBackpicAsOAM` is
## byte-identical in both disassemblies and their own `.subfunction1` steps them
## by two beside its `rSCX` writes. Crystal's walk is measured against a real
## cartridge, sprite by sprite, from x 158 to 16, and Gold's ends on the same 16:
## its lead frame spends no step, but its loop skips none either.
func sprites() -> Array:
	var out: Array = []
	if finished():
		# `HideSprites` runs the moment the slide returns, and `PlaceGraphic`
		# puts the whole pic on the background instead.
		return out
	# Crystal's `.subfunction3` is skipped on the loop's last pass, `cp $1 /
	# jr z, .skip1`, so 72 of its 73 frames step. Gold and Silver spend their
	# lead frame before the loop and then step on all 72 of its passes, with no
	# such test. Both walks are 72 steps long and the frame index is the count.
	var walked: int = _frame
	for column: int in SPRITE_COLUMNS:
		for row: int in SPRITE_ROWS:
			out.append({
				"tile": column * SPRITE_PIC_ROWS + row,
				"x": SPRITE_FIRST_X + column * Gen2Tiles.TILE_WIDTH - walked * SPRITE_STEP,
				"y": SPRITE_FIRST_Y + row * Gen2Tiles.TILE_HEIGHT,
			})
	return out


## Per scanline in hardware draw order; an offset looks *right* into the map.
func offsets() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(HEIGHT)
	if finished():
		out.fill(0)
		return out

	var top: int = _top_offset()
	var middle: int = _middle_offset()
	var top_rows: int = CRYSTAL_TOP_ROWS if _crystal else GOLD_TOP_ROWS
	var middle_rows: int = CRYSTAL_MIDDLE_ROWS if _crystal else GOLD_MIDDLE_ROWS
	for row: int in HEIGHT:
		if row < top_rows:
			out[row] = top
		elif row < top_rows + middle_rows:
			out[row] = middle
		else:
			# The lead frame is the whole screen at the starting offset:
			# `rSCX` holds it and no band has been written yet.
			out[row] = GOLD_TOP_START if _is_gold_lead() else 0
	return out


## How far the picture standing in each band is from its resting square, along
## x and in pixels, for a renderer with no background plane to read a scroll off.
## Zero once the slide has returned.
##
## Taken from the band's own arithmetic rather than from the byte [method
## offsets] reports, because a scroll register cannot say which way a picture is
## travelling: the two bands come in from opposite sides, and Crystal's middle
## runs two pixels past its square and back, so the same `$02` reads as +254 or
## -2 depending only on when in the slide it was sampled. The unwrapped step
## count has no such ambiguity.
##
## The top band carries the opponent, which is in from the left, so its
## displacement is negative and climbs to zero. The middle carries the player,
## in from the right, so its own falls to zero and then to the -2 Crystal
## overshoots by before `InitBattleDisplay`'s `xor a` settles it.
func enemy_offset() -> float:
	return 0.0 if finished() else float(-_top_scx())


func player_offset() -> float:
	return 0.0 if finished() else float(MAP_WIDTH - _middle_scx())


func _is_gold_lead() -> bool:
	return not _crystal and _frame < GOLD_LEAD_FRAMES


## Crystal steps `ld d, $90` down by two every frame. Gold and Silver write
## `hSCX`, which VBlank copies to `rSCX` a frame late, so their top band trails
## the middle by one. Crystal's two bands share a table and lag together.
func _top_offset() -> int:
	return posmod(_top_scx(), MAP_WIDTH)


## `$72` and `$70` up by two each frame. Crystal's runs past the end of a byte
## and wraps, which is why it lands on 2.
func _middle_offset() -> int:
	return posmod(_middle_scx(), MAP_WIDTH)


## The two bands before the hardware's own wrap, which is what [method
## enemy_offset] and [method player_offset] need and what the byte above hides.
func _top_scx() -> int:
	if _crystal:
		return CRYSTAL_TOP_START - STEP * _frame
	var stepped: int = maxi(_frame - GOLD_LEAD_FRAMES, 0)
	return GOLD_TOP_START - STEP * maxi(stepped - 1, 0)


func _middle_scx() -> int:
	if _crystal:
		return CRYSTAL_MIDDLE_START + STEP * _frame
	if _is_gold_lead():
		return GOLD_TOP_START
	return GOLD_MIDDLE_START + STEP * (_frame - GOLD_LEAD_FRAMES)
