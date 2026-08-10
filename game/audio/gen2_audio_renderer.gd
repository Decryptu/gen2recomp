class_name Gen2AudioRenderer
extends RefCounted

## Converts decoded cartridge events into a Godot AudioStreamWAV. The source
## engine updates one channel every frame, so the renderer evaluates event state
## at the same 60 Hz timeline and only uses the output sample rate for the
## waveform between those state changes.
##
## The four channels are the DMG's own, and each is generated the way the
## hardware register the engine writes says: rAUDxENV is a real envelope that
## steps while a note sounds, channel 3 reads a wave pattern at half the pitch
## the pulse channels get from the same register value, and channel 4 clocks an
## LFSR from rAUD4POLY rather than sounding a pitch.
##
## Walked per event rather than per sample. A stream is a few hundred events and
## a minute of output is over a million samples, so reading an event's fields
## once and filling its own span is the difference between a fraction of a second
## and the ten this used to spend building one track.

const SAMPLE_RATE: int = 22050
## Long enough for the longest stream [Gen2AudioDecoder] will hand over, so a
## looping track is rendered up to its own loop point rather than cut at an
## arbitrary length and looped from the top.
const MAX_RENDER_FRAMES: int = 60 * 60

## `rAUDxENV`: hi nibble the starting volume, bit 3 the direction, lo three bits
## the step period in 1/64ths of a second. Period 0 means the volume never moves.
const ENVELOPE_STEPS_PER_SECOND: float = 64.0

## `rAUD3LEVEL` bits 6-5, which `.load_wave_pattern` writes from the envelope's
## hi nibble: 0 mutes, 1 is full, and 2 and 3 shift the sample right.
const WAVE_LEVELS: Array[float] = [0.0, 1.0, 0.5, 0.25]

const DUTY_CYCLES: Array[float] = [0.125, 0.25, 0.5, 0.75]

## How many LFSR clocks one output sample will pay for. Channel 4 runs as fast as
## 524288 Hz, far above the output rate, and past a few dozen clocks per sample
## the result is indistinguishable noise; the cap keeps a drum from costing more
## than the rest of the mix put together.
const MAX_NOISE_CLOCKS_PER_SAMPLE: int = 32

## One channel against the four mixed, which is the headroom the mix is written
## for, times the sixteen-bit range.
const CHANNEL_SCALE: float = 7000.0


static func render(decoded: Dictionary, assets: Dictionary = {}) -> Dictionary:
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "reason": decoded.get("reason", &"audio_decode_failed")}
	var tracks: Array = decoded.get("tracks", [])
	if tracks.is_empty():
		return {"ok": false, "reason": &"audio_has_no_tracks"}
	var source_frames: int = maxi(1, int(decoded.get("duration_frames", 1)))
	var render_frames: int = mini(source_frames, MAX_RENDER_FRAMES)
	var render_samples: int = maxi(1, render_frames * SAMPLE_RATE / 60)

	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(render_samples)
	right.resize(render_samples)
	var wave: PackedByteArray = _wave_bytes(assets)
	for track: Dictionary in tracks:
		_render_track(track, left, right, render_samples, wave)

	var data := PackedByteArray()
	data.resize(render_samples * 4)
	for index: int in render_samples:
		var out_left: int = clampi(int(left[index] * CHANNEL_SCALE), -32768, 32767)
		var out_right: int = clampi(int(right[index] * CHANNEL_SCALE), -32768, 32767)
		var byte_at: int = index * 4
		data[byte_at] = out_left & 0xFF
		data[byte_at + 1] = (out_left >> 8) & 0xFF
		data[byte_at + 2] = out_right & 0xFF
		data[byte_at + 3] = (out_right >> 8) & 0xFF

	var looped: bool = bool(decoded.get("looped", false))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = data
	if looped:
		# Back to the stream's own loop point, not to the top: a track with an
		# intro plays it once, the way the sound engine does.
		var loop_frame: int = int(decoded.get("loop_start_frame", -1))
		var loop_begin: int = 0
		if loop_frame > 0:
			loop_begin = clampi(loop_frame * SAMPLE_RATE / 60, 0, render_samples - 1)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = loop_begin
		stream.loop_end = render_samples
	return {
		"ok": true,
		"stream": stream,
		"frame_count": render_frames,
		"sample_rate": SAMPLE_RATE,
		"looped": looped,
		"decoded": decoded,
	}


static func _render_track(
	track: Dictionary, left: PackedFloat32Array, right: PackedFloat32Array,
	render_samples: int, wave: PackedByteArray
) -> void:
	var phase: float = 0.0
	var lfsr: int = 0x7FFF
	var noise_phase: float = 0.0
	for event: Dictionary in track.get("events", []):
		if int(event.get("pitch", 0)) == 0:
			continue
		var start_frame: int = int(event.get("start_frame", 0))
		var first: int = start_frame * SAMPLE_RATE / 60
		var last: int = mini(
			render_samples,
			(start_frame + int(event.get("duration_frames", 0))) * SAMPLE_RATE / 60,
		)
		if first >= last or first >= render_samples:
			continue
		# NR51 routes a channel to one side, NR50 sets how loud that side is, and
		# volume 0 is an eighth rather than silence.
		var gain_left: float = 0.0
		var gain_right: float = 0.0
		if int(event.get("pan_left", 1)) != 0:
			gain_left = (float(int(event.get("master_left", 7))) + 1.0) / 8.0
		if int(event.get("pan_right", 1)) != 0:
			gain_right = (float(int(event.get("master_right", 7))) + 1.0) / 8.0

		if bool(event.get("noise", false)):
			var noise_state: Dictionary = _render_noise(
				event, left, right, first, last, gain_left, gain_right, lfsr, noise_phase
			)
			lfsr = int(noise_state["lfsr"])
			noise_phase = float(noise_state["phase"])
			continue

		var hardware_channel: int = int(event.get("hardware_channel", 1))
		var step: float = _register_to_hz(
			int(event.get("frequency", 0)), hardware_channel
		) / float(SAMPLE_RATE)
		if hardware_channel == 3:
			phase = _render_wave(
				event, left, right, first, last, gain_left, gain_right, phase, step, wave
			)
		else:
			phase = _render_pulse(
				event, left, right, first, last, gain_left, gain_right, phase, step
			)


static func _render_pulse(
	event: Dictionary, left: PackedFloat32Array, right: PackedFloat32Array,
	first: int, last: int, gain_left: float, gain_right: float, phase: float, step: float
) -> float:
	var threshold: float = DUTY_CYCLES[clampi(int(event.get("duty", 0)), 0, 3)]
	var envelope: int = int(event.get("envelope", 0xF0))
	var level: int = (envelope >> 4) & 0x0F
	var period: int = envelope & 0x07
	var rising: bool = ((envelope >> 3) & 0x01) != 0
	var step_samples: float = float(period) * float(SAMPLE_RATE) / ENVELOPE_STEPS_PER_SECOND
	for index: int in range(first, last):
		var volume: float = _envelope_level(
			level, period, rising, step_samples, float(index - first)
		) * 0.25
		var sample: float = 1.0 if phase < threshold else -1.0
		left[index] += sample * volume * gain_left
		right[index] += sample * volume * gain_right
		phase = fmod(phase + step, 1.0)
	return phase


static func _render_wave(
	event: Dictionary, left: PackedFloat32Array, right: PackedFloat32Array,
	first: int, last: int, gain_left: float, gain_right: float, phase: float,
	step: float, wave: PackedByteArray
) -> float:
	var volume: float = WAVE_LEVELS[(int(event.get("envelope", 0xF0)) >> 4) & 0x03] * 0.25
	var base: int = clampi(int(event.get("wave_index", 0)), 0, 9) * 16
	if volume <= 0.0 or base + 16 > wave.size():
		for _index: int in range(first, last):
			phase = fmod(phase + step, 1.0)
		return phase
	for index: int in range(first, last):
		var position: int = int(phase * 32.0) % 32
		var packed: int = wave[base + position / 2]
		var nibble: int = packed >> 4 if position % 2 == 0 else packed & 0x0F
		var sample: float = float(nibble) / 7.5 - 1.0
		left[index] += sample * volume * gain_left
		right[index] += sample * volume * gain_right
		phase = fmod(phase + step, 1.0)
	return phase


## `ReadNoiseSample` walks a drum's own list of `[duration, envelope, frequency]`
## rows, each row retriggering the channel, so the envelope restarts per row
## rather than per note.
static func _render_noise(
	event: Dictionary, left: PackedFloat32Array, right: PackedFloat32Array,
	first: int, last: int, gain_left: float, gain_right: float, lfsr: int, phase: float
) -> Dictionary:
	var rows: Array = event.get("noise_samples", [])
	if rows.is_empty():
		rows = [{
			"duration_frames": 0x7FFFFFFF,
			"envelope": int(event.get("envelope", 0xF0)),
			"frequency": int(event.get("frequency", 0)),
		}]
	var at: int = first
	for row: Dictionary in rows:
		if at >= last:
			break
		var row_samples: int = int(row.get("duration_frames", 1)) * SAMPLE_RATE / 60
		var row_end: int = mini(last, at + maxi(row_samples, 1))
		var envelope: int = int(row.get("envelope", 0xF0))
		var level: int = (envelope >> 4) & 0x0F
		var period: int = envelope & 0x07
		var rising: bool = ((envelope >> 3) & 0x01) != 0
		var step_samples: float = float(period) * float(SAMPLE_RATE) \
			/ ENVELOPE_STEPS_PER_SECOND
		var register: int = int(row.get("frequency", 0))
		var narrow: bool = (register & 0x08) != 0
		var step: float = _noise_hz(register) / float(SAMPLE_RATE)
		for index: int in range(at, row_end):
			var volume: float = _envelope_level(
				level, period, rising, step_samples, float(index - at)
			) * 0.25
			phase += step
			var clocks: int = mini(int(phase), MAX_NOISE_CLOCKS_PER_SAMPLE)
			phase -= floorf(phase)
			for _clock: int in clocks:
				var bit: int = (lfsr ^ (lfsr >> 1)) & 1
				lfsr = (lfsr >> 1) | (bit << 14)
				if narrow:
					lfsr = (lfsr & ~0x40) | (bit << 6)
			# The DMG inverts the low bit, so a fresh $7fff LFSR starts high.
			var sample: float = -1.0 if (lfsr & 1) != 0 else 1.0
			left[index] += sample * volume * gain_left
			right[index] += sample * volume * gain_right
		at = row_end
	return {"lfsr": lfsr, "phase": phase}


## The DMG volume envelope behind rAUDxENV, run forward from the note's own
## trigger: one level per period 64ths of a second, up or down by bit 3, stopping
## at the ends. Period 0 holds the starting volume.
static func _envelope_level(
	level: int, period: int, rising: bool, step_samples: float, elapsed: float
) -> float:
	if period <= 0:
		return float(level) / 15.0
	var steps: int = int(elapsed / step_samples)
	var value: int = mini(15, level + steps) if rising else maxi(0, level - steps)
	return float(value) / 15.0


## `f = 131072 / (2048 - x)` for the two pulse channels. Channel 3 walks its
## thirty-two samples over two periods of the same divider, so the same register
## value sounds an octave lower, which is what the music is written for.
static func _register_to_hz(value: int, hardware_channel: int) -> float:
	if value <= 0 or value >= 2048:
		return 0.0
	var numerator: float = 65536.0 if hardware_channel == 3 else 131072.0
	return numerator / float(2048 - value)


## rAUD4POLY: hi nibble the shift, bit 3 the LFSR width, lo three bits the
## divisor code, where code 0 means half.
static func _noise_hz(value: int) -> float:
	var shift: int = (value >> 4) & 0x0F
	if shift > 13:
		return 0.0
	var code: int = value & 0x07
	var divisor: int = 8 if code == 0 else code * 16
	return 4194304.0 / float(divisor << shift)


static func _wave_bytes(assets: Dictionary) -> PackedByteArray:
	var asset: Variant = assets.get("wave_samples", {})
	if not asset is Dictionary:
		return PackedByteArray()
	var raw: Variant = (asset as Dictionary).get("bytes", [])
	if raw is PackedByteArray:
		return raw
	if not raw is Array:
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize((raw as Array).size())
	for index: int in out.size():
		out[index] = int((raw as Array)[index]) & 0xFF
	return out
