class_name Gen2BattleIntro
extends RefCounted

## `BattleIntroSlidingPics` (engine/battle/sliding_intro.asm), which is a
## background scroll rather than a moving object: the routine rewrites `SCX` part
## way down the frame so the top band comes in from one side and the middle from
## the other, while the bottom never moves. A band edge falls inside the player's
## status panel, which is why this is a per-scanline offset.
##
## `InitBattleDisplay.BlankBGMap` leaves everything past the drawn scene blank,
## so an offset wraps at [constant MAP_WIDTH] and blank is what scrolls in.
##
## The one part of the battle presentation the two games do not share: Crystal
## drives `wLYOverrides`, an HBlank table with a value per scanline, while
## pokegold busy-waits on `rLY` and writes `rSCX` twice a frame. Band edges,
## starting offsets and the walk all differ, so both are written out.
##
## Neither band lands on zero (Crystal's middle ends at 2, Gold's top at 4);
## `InitBattleDisplay`'s `xor a` / `ldh [hSCX], a` settles the screen, and
## [method finished] is that write.
##
## `.subfunction3` slides the overworld's own objects off before `HideSprites`
## clears them. This screen has no OAM, so there is nothing to walk: a boundary,
## not a gap.

## 32 tiles of 8, what an offset wraps at. Everything past the screen's 160 is
## blank.
const MAP_WIDTH: int = 256

const HEIGHT: int = Gen2Screen.HEIGHT

## Both games step twice per frame, in opposite directions: `dec d` twice
## against `inc e` twice.
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

## `ld a, c` / `ldh [hSCX], a` / `call DelayFrame` puts the whole screen at the
## starting offset with no band written yet. Crystal delays nowhere, so it has
## none.
const GOLD_LEAD_FRAMES: int = 1

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


## One hardware frame. Redraws on every frame of the walk and on the one that
## ends it, since the settle to zero is a change like any other.
func advance_frame() -> bool:
	if finished():
		return false
	_frame += 1
	return true


## The background offset per scanline, hardware draw order. An offset looks
## *right* into the map, so a larger one puts the scene further left.
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


func _is_gold_lead() -> bool:
	return not _crystal and _frame < GOLD_LEAD_FRAMES


## Crystal steps every frame, `ld d, $90` down by two. Gold and Silver write to
## `hSCX`, which VBlank copies to `rSCX` only after the frame it was written
## during, so their top band trails the middle by one: both the lead frame and
## the loop's first frame show the starting offset. Crystal's two bands come out
## of one table and lag together, so only Gold's separate writes show it.
func _top_offset() -> int:
	if _crystal:
		return posmod(CRYSTAL_TOP_START - STEP * _frame, MAP_WIDTH)
	var stepped: int = maxi(_frame - GOLD_LEAD_FRAMES, 0)
	return posmod(GOLD_TOP_START - STEP * maxi(stepped - 1, 0), MAP_WIDTH)


## `$72` and `$70` up by two each frame. Crystal's runs past the end of a byte
## and wraps, which is why it lands on 2.
func _middle_offset() -> int:
	if _crystal:
		return posmod(CRYSTAL_MIDDLE_START + STEP * _frame, MAP_WIDTH)
	if _is_gold_lead():
		return GOLD_TOP_START
	return posmod(GOLD_MIDDLE_START + STEP * (_frame - GOLD_LEAD_FRAMES), MAP_WIDTH)
