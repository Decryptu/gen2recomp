class_name Gen2WorldPhoneRing
extends RefCounted

## Timing-only model of the cartridge's RingTwice_StartCall routine.
##
## The phone UI is owned by the world screen, but the timing stays scene-free
## so tests can advance it without a running window. The source spends twenty
## hardware frames in each of the three waits inside one ring, then repeats
## the ring once more.

const FRAME_SECONDS: float = 1.0 / 59.7275
const RING_COUNT: int = 2
const WAITS_PER_RING: int = 3
const WAIT_FRAMES: int = 20
const RING_FRAMES: int = WAITS_PER_RING * WAIT_FRAMES
const TOTAL_FRAMES: int = RING_COUNT * RING_FRAMES

var _elapsed_frames: int = 0
var _fractional_frames: float = 0.0
var _lead_frames: int = 0


func _init(lead_frames: int = 0) -> void:
	_lead_frames = maxi(0, lead_frames)


func advance(delta: float) -> Dictionary:
	if delta > 0.0:
		_fractional_frames += delta / FRAME_SECONDS
		var whole_frames: int = floori(_fractional_frames)
		if whole_frames > 0:
			_fractional_frames -= float(whole_frames)
			_elapsed_frames = mini(_elapsed_frames + whole_frames, total_frames())
	return snapshot()


func is_finished() -> bool:
	return _elapsed_frames >= total_frames()


func elapsed_frames() -> int:
	return _elapsed_frames


func total_frames() -> int:
	return _lead_frames + TOTAL_FRAMES


func snapshot() -> Dictionary:
	var ringing_frames: int = maxi(0, _elapsed_frames - _lead_frames)
	var ring_index: int = 0
	var phase: StringName = &"pre_ring"
	if ringing_frames > 0 or _elapsed_frames >= _lead_frames:
		ring_index = mini(ringing_frames / RING_FRAMES, RING_COUNT - 1)
		var phase_index: int = (ringing_frames % RING_FRAMES) / WAIT_FRAMES
		phase = [&"ringing", &"caller_name", &"caller_box"][phase_index % 3]
	if is_finished():
		ring_index = RING_COUNT - 1
		phase = &"caller_name"
	return {
		"ring": ring_index + 1 if phase != &"pre_ring" else 0,
		"rings": RING_COUNT,
		"phase": phase,
		"elapsed_frames": _elapsed_frames,
		"total_frames": total_frames(),
		"finished": is_finished(),
	}
