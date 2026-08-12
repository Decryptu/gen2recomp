class_name Gen2IntroPresentation
extends RefCounted

## Small, scene-free pieces of `engine/menus/intro_menu.asm`: the intro moves
## pictures on VBlank counts, not rendered-frame interpolation.

const PLAYER_SLIDE_FRAMES: int = 8
const FRAME_RATE: float = 59.7275
const WIPE_START: int = 0x77
const WIPE_STEP: int = 8

var _start: int = 0
var _finish: int = 0
var _frame: int = 0
var _frames: int = 0


func start_slide(start: int, finish: int, frames: int = PLAYER_SLIDE_FRAMES) -> void:
	_start = start
	_finish = finish
	_frame = 0
	_frames = maxi(frames, 1)


func advance_frame() -> bool:
	if finished():
		return false
	_frame += 1
	return true


func finished() -> bool:
	return _frames <= 0 or _frame >= _frames


func position() -> int:
	if _frames <= 0:
		return _finish
	var progress: int = clampi(_frame, 0, _frames)
	return _start + ((_finish - _start) * progress) / _frames


func frame() -> int:
	return _frame


## `Intro_WipeInFrontpic` writes hWX from $77 down in eights.
static func wipe_window_x(frame: int) -> int:
	return maxi(0, WIPE_START - maxi(frame, 0) * WIPE_STEP)


## The source rotates the four-colour row itself, so the helper takes a row and
## returns the exact cyclic order rather than asking a renderer to approximate.
static func rotate_palette(row: PackedColorArray, right: bool) -> PackedColorArray:
	if row.is_empty():
		return PackedColorArray()
	var out := PackedColorArray()
	out.resize(row.size())
	for index: int in row.size():
		var source: int = (index - 1) if right else (index + 1)
		source = posmod(source, row.size())
		out[index] = row[source]
	return out
