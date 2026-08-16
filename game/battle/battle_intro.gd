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
## `.subfunction3` slides the overworld's objects off before `HideSprites`; this
## screen has no OAM, so there is nothing to walk.

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


func _is_gold_lead() -> bool:
	return not _crystal and _frame < GOLD_LEAD_FRAMES


## Crystal steps `ld d, $90` down by two every frame. Gold and Silver write
## `hSCX`, which VBlank copies to `rSCX` a frame late, so their top band trails
## the middle by one. Crystal's two bands share a table and lag together.
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
