class_name Gen2WorldEffects
extends RefCounted

## Scene-free presentation state for effects that the overworld engine paces in
## hardware frames. The renderer owns the pixels; this class owns the source
## duration, amplitude and deterministic offsets.

var _frame: int = 0
var _duration: int = 0
var _amplitude: int = 0
var _kind: StringName = &"none"
var _source: Dictionary = {}


func start_screen_shake(packed_value: int, kind: StringName = &"screen_shake", source: Dictionary = {}) -> Dictionary:
	var value: int = clampi(packed_value, 0, 0xFF)
	_duration = value & 0x3F
	_amplitude = 1 << ((value >> 6) & 0x03) if _duration > 0 else 0
	_frame = 0
	_kind = kind if _duration > 0 else &"none"
	_source = source.duplicate(true)
	return snapshot()


func start_tree_shake(source: Dictionary = {}) -> Dictionary:
	## ShakeHeadbuttTree runs for eight tile steps at four frames each.
	return start_screen_shake(32, &"tree_shake", source)


func advance_frame() -> bool:
	if not active():
		return false
	_frame += 1
	if not active():
		_kind = &"none"
		_source = {}
	return true


func active() -> bool:
	return _frame < _duration and _duration > 0


func offset() -> Vector2:
	if not active():
		return Vector2.ZERO
	var magnitude: float = float(_amplitude)
	match _frame & 3:
		0: return Vector2(-magnitude, 0.0)
		1: return Vector2(magnitude, 0.0)
		2: return Vector2(0.0, -magnitude)
		_: return Vector2(0.0, magnitude)


func snapshot() -> Dictionary:
	return {
		"active": active(),
		"kind": _kind,
		"frame": _frame,
		"duration": _duration,
		"amplitude": _amplitude,
		"offset": offset(),
		"source": _source.duplicate(true),
	}
