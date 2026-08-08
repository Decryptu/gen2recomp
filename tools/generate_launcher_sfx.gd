extends SceneTree

## Renders the launcher's sound effects to `assets/launcher/sfx/*.wav`.
##
## The sounds are synthesised rather than sampled so the repository carries no
## third-party audio. Run after changing any recipe below:
##
##     Godot --headless -s res://tools/generate_launcher_sfx.gd

const OUTPUT_DIR: String = "res://assets/launcher/sfx"
const RATE: int = 44100

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var recipes: Dictionary = {
		"hover": _hover,
		"click": _click,
		"insert": _insert,
		"eject": _eject,
		"power": _power,
		"error": _error,
	}
	for name: String in recipes:
		_rng.seed = hash(name)
		var samples: PackedFloat32Array = (recipes[name] as Callable).call()
		var path: String = "%s/%s.wav" % [OUTPUT_DIR, name]
		if not _write_wav(path, samples):
			printerr("Could not write %s" % path)
			quit(1)
			return
		print("%s  %.3fs" % [path, float(samples.size()) / float(RATE)])
	quit()


# Recipes. Each returns mono samples in -1..1.


## A barely-there tick under a pointer. Loud enough to feel, quiet enough to
## survive being triggered on every hover.
func _hover() -> PackedFloat32Array:
	var buffer: PackedFloat32Array = _silence(0.03)
	_tone(buffer, 0.0, 0.018, 1650.0, 1650.0, 0.10, 0.001, 3.0, 0.0)
	return _normalise(buffer, 0.12)


## A dry switch: a noise transient for the contact, a short body for the plate.
func _click() -> PackedFloat32Array:
	var buffer: PackedFloat32Array = _silence(0.09)
	_noise(buffer, 0.0, 0.010, 5200.0, 900.0, 0.5, 0.0005, 5.0)
	_tone(buffer, 0.002, 0.055, 940.0, 780.0, 0.45, 0.001, 4.0, 0.35)
	return _normalise(buffer, 0.45)


## A cartridge going home: plastic sliding down the rails, then the seat.
func _insert() -> PackedFloat32Array:
	var buffer: PackedFloat32Array = _silence(0.46)
	_noise(buffer, 0.0, 0.115, 1400.0, 3400.0, 0.30, 0.030, 1.1)
	_noise(buffer, 0.118, 0.030, 6000.0, 1200.0, 0.55, 0.0008, 6.0)
	_tone(buffer, 0.118, 0.230, 96.0, 74.0, 0.90, 0.0015, 3.2, 0.0)
	_tone(buffer, 0.118, 0.150, 187.0, 150.0, 0.40, 0.0015, 4.5, 0.5)
	_tone(buffer, 0.120, 0.070, 430.0, 330.0, 0.16, 0.001, 6.0, 0.0)
	return _normalise(buffer, 0.85)


## The same seat in reverse: the release first, then the rails on the way out.
func _eject() -> PackedFloat32Array:
	var buffer: PackedFloat32Array = _silence(0.40)
	_noise(buffer, 0.0, 0.022, 5200.0, 1500.0, 0.40, 0.0008, 6.0)
	_tone(buffer, 0.0, 0.120, 150.0, 210.0, 0.45, 0.0015, 4.0, 0.4)
	_noise(buffer, 0.045, 0.140, 3000.0, 1100.0, 0.26, 0.020, 1.4)
	return _normalise(buffer, 0.7)


## Power on: a rising fifth and octave over a short sub swell.
func _power() -> PackedFloat32Array:
	var buffer: PackedFloat32Array = _silence(0.90)
	_tone(buffer, 0.00, 0.30, 587.33, 587.33, 0.32, 0.008, 2.4, 0.22)
	_tone(buffer, 0.10, 0.32, 880.00, 880.00, 0.30, 0.008, 2.2, 0.22)
	_tone(buffer, 0.20, 0.55, 1174.66, 1174.66, 0.34, 0.010, 1.8, 0.18)
	_tone(buffer, 0.20, 0.55, 1760.00, 1760.00, 0.10, 0.012, 2.0, 0.0)
	_tone(buffer, 0.00, 0.45, 110.0, 146.83, 0.35, 0.030, 1.6, 0.0)
	return _normalise(buffer, 0.72)


## A refusal, not an alarm: low, short and flat.
func _error() -> PackedFloat32Array:
	var buffer: PackedFloat32Array = _silence(0.28)
	_tone(buffer, 0.0, 0.115, 196.0, 186.0, 0.5, 0.004, 3.0, 0.6)
	_tone(buffer, 0.125, 0.130, 155.0, 146.0, 0.5, 0.004, 3.0, 0.6)
	return _normalise(buffer, 0.5)


# Synthesis primitives.


func _silence(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(seconds * RATE))
	return buffer


## A sine with an optional square-ish edge, swept between two frequencies and
## shaped by an attack and an exponential decay.
func _tone(
	buffer: PackedFloat32Array,
	start: float,
	length: float,
	from_hz: float,
	to_hz: float,
	gain: float,
	attack: float,
	decay: float,
	edge: float,
) -> void:
	var first: int = int(start * RATE)
	var count: int = int(length * RATE)
	var phase: float = 0.0
	for index: int in count:
		var at: int = first + index
		if at >= buffer.size():
			return
		var t: float = float(index) / float(RATE)
		var progress: float = float(index) / float(maxi(count - 1, 1))
		phase += TAU * lerpf(from_hz, to_hz, progress) / float(RATE)
		var wave: float = sin(phase)
		wave = lerpf(wave, signf(wave) * pow(absf(wave), 0.35), edge)
		buffer[at] += wave * gain * _envelope(t, length, attack, decay)


## Filtered noise: one-pole low pass swept between two cutoffs, with the same
## envelope shape as [method _tone].
func _noise(
	buffer: PackedFloat32Array,
	start: float,
	length: float,
	from_hz: float,
	to_hz: float,
	gain: float,
	attack: float,
	decay: float,
) -> void:
	var first: int = int(start * RATE)
	var count: int = int(length * RATE)
	var low: float = 0.0
	var previous: float = 0.0
	var high: float = 0.0
	for index: int in count:
		var at: int = first + index
		if at >= buffer.size():
			return
		var t: float = float(index) / float(RATE)
		var progress: float = float(index) / float(maxi(count - 1, 1))
		var cutoff: float = lerpf(from_hz, to_hz, progress)
		var alpha: float = clampf(TAU * cutoff / float(RATE), 0.0, 1.0)
		var raw: float = _rng.randf_range(-1.0, 1.0)
		low = low + alpha * (raw - low)
		# A gentle high pass keeps the rumble out, so the noise reads as friction
		# rather than as a second thud under the one the tone already plays.
		high = 0.92 * (high + low - previous)
		previous = low
		buffer[at] += high * gain * _envelope(t, length, attack, decay)


func _envelope(t: float, length: float, attack: float, decay: float) -> float:
	var rise: float = 1.0 if attack <= 0.0 else clampf(t / attack, 0.0, 1.0)
	var fall: float = exp(-decay * t / maxf(length, 0.0001))
	# The last 8 ms always fade, so no recipe can leave a click at the end.
	var tail: float = clampf((length - t) / 0.008, 0.0, 1.0)
	return rise * fall * tail


func _normalise(buffer: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest: float = 0.0
	for sample: float in buffer:
		loudest = maxf(loudest, absf(sample))
	if loudest <= 0.0:
		return buffer
	var scale: float = peak / loudest
	for index: int in buffer.size():
		buffer[index] = buffer[index] * scale
	return buffer


## 16-bit mono PCM. Written by hand because Godot exports no WAV encoder.
func _write_wav(path: String, samples: PackedFloat32Array) -> bool:
	var payload := PackedByteArray()
	payload.resize(samples.size() * 2)
	for index: int in samples.size():
		payload.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32767.0))

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + payload.size())
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(RATE)
	file.store_32(RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(payload.size())
	file.store_buffer(payload)
	file.close()
	return true
