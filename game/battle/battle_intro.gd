class_name Gen2BattleIntro
extends RefCounted

## The two pics sliding into place at the start of a battle
## (`BattleIntroSlidingPics`, engine/battle/sliding_intro.asm), as the
## background scroll it really is.
##
## Nothing slides here as an object. The routine scrolls the background itself,
## in horizontal bands, by rewriting `SCX` part way down the frame: the top band
## comes in from one side and the middle band from the other, and the bottom of
## the screen never moves. A band edge falls inside the player's own status
## panel, which is why this is a per-scanline offset rather than a moving layer.
##
## The background map is 32 tiles wide against a 20-tile screen, and
## `InitBattleDisplay.BlankBGMap` leaves everything past the drawn scene blank,
## so an offset wraps at [constant MAP_WIDTH] and blank is what scrolls in.
##
## This is the one part of the battle presentation the two games do not share.
## Crystal drives it through `wLYOverrides`, an HBlank table carrying a value
## per scanline; pokegold busy-waits on `rLY` and writes `rSCX` twice a frame.
## The band edges, the starting offsets and the shape of the walk all differ, so
## both are written out rather than one standing in for the other.
##
## Neither band lands on zero. Crystal's middle ends at 2 and Gold's top at 4,
## and `InitBattleDisplay`'s own `xor a` / `ldh [hSCX], a` after the call is what
## settles the screen; [method finished] is that write.
##
## `.subfunction3`, the eighteen `wShadowOAMSprite00` entries walked two pixels
## left a frame, is the overworld's own objects being slid off before
## `HideSprites` clears them. This screen has no OAM and no overworld objects in
## it, so there is nothing to walk; it is a boundary, not a gap.
##
## Scene-free like the rest of the battle layer: the screen ticks this once per
## hardware frame and hands [method offsets] to whatever is drawing.

## The background map's width in pixels, which is what an offset wraps at: 32
## tiles of 8. Everything from the screen's own 160 up to it is blank.
const MAP_WIDTH: int = 256

## Screen height in pixels, and so the length of [method offsets].
const HEIGHT: int = Gen2Screen.HEIGHT

## How much a band moves per frame. Both games step twice, in opposite
## directions: `dec d` twice against `inc e` twice.
const STEP: int = 2

## Crystal's `ld d, $90` and `ld e, $72`, over `.subfunction5`'s three runs of
## 62, 34 and 48 scanlines, for `$48 + 1` frames.
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

## Gold and Silver spend one frame before the loop: `ld a, c` / `ldh [hSCX], a`
## / `call DelayFrame` puts the whole screen at the starting offset, with no
## band written yet. Crystal delays nowhere before its own loop, so it has none.
const GOLD_LEAD_FRAMES: int = 1

var _crystal: bool = true
var _frame: int = 0


## The intro for [param data]'s own game.
static func for_data(data: GameData) -> Gen2BattleIntro:
	return create(Gen2WorldState.is_crystal_profile(data))


static func create(crystal: bool) -> Gen2BattleIntro:
	var intro := Gen2BattleIntro.new()
	intro._crystal = crystal
	return intro


## How many frames the whole slide is on screen for. Both games take the same
## number, by different arithmetic.
func frames() -> int:
	return CRYSTAL_FRAMES if _crystal else GOLD_LEAD_FRAMES + GOLD_LOOP_FRAMES


func finished() -> bool:
	return _frame >= frames()


## One hardware frame. Answers whether the screen should be redrawn, which is
## every frame of the walk and the one that ends it, since the settle to zero is
## a change like any other.
func advance_frame() -> bool:
	if finished():
		return false
	_frame += 1
	return true


## The background offset for every scanline, in the order the hardware draws
## them. An offset is a distance to look *right* into the background map, so a
## larger one puts the drawn scene further left.
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
			# Gold and Silver's lead frame is the whole screen at the starting
			# offset: `rSCX` still holds it and nothing has written a band yet.
			out[row] = GOLD_TOP_START if _is_gold_lead() else 0
	return out


## Whether this is Gold and Silver's pre-loop frame, which has no bands at all.
func _is_gold_lead() -> bool:
	return not _crystal and _frame < GOLD_LEAD_FRAMES


## Crystal steps its top band every frame, `ld d, $90` down by two.
##
## Gold and Silver write theirs to `hSCX`, which the VBlank handler copies to
## `rSCX` only after the frame it was written during, so their top band trails
## the middle one by a frame: the lead frame and the loop's own first frame both
## show the starting offset. Crystal's two bands come out of one table and lag
## together, so only Gold's separate writes make a lag visible.
func _top_offset() -> int:
	if _crystal:
		return posmod(CRYSTAL_TOP_START - STEP * _frame, MAP_WIDTH)
	var stepped: int = maxi(_frame - GOLD_LEAD_FRAMES, 0)
	return posmod(GOLD_TOP_START - STEP * maxi(stepped - 1, 0), MAP_WIDTH)


## Both middle bands step every frame of their own loop, `$72` and `$70` up by
## two. Crystal's runs past the end of a byte and wraps, which is why it lands
## on 2 rather than on nothing.
func _middle_offset() -> int:
	if _crystal:
		return posmod(CRYSTAL_MIDDLE_START + STEP * _frame, MAP_WIDTH)
	if _is_gold_lead():
		return GOLD_TOP_START
	return posmod(GOLD_MIDDLE_START + STEP * (_frame - GOLD_LEAD_FRAMES), MAP_WIDTH)
