class_name Gen2AudioRenderer
extends RefCounted

## Stateful DMG/GBC channel renderer. A RenderState is a live hardware timeline:
## it owns phase, noise, envelope/event cursors and the per-output analog filter.

const SAMPLE_RATE: int = 22050
const MAX_RENDER_FRAMES: int = 60 * 60
const ENVELOPE_STEPS_PER_SECOND: float = 64.0
const MAX_NOISE_CLOCKS_PER_SAMPLE: int = 64
const GB_CLOCK: float = 4194304.0
# Four independent DMG channels can be simultaneously full-scale before the
# analog stage. Keep the reference filter response but leave 6 dB of mixer
# headroom so a valid multi-channel record never reaches the digital clamp.
const MIX_SCALE: float = 0.25
const HPF_CHARGE: float = pow(0.999958, GB_CLOCK / float(SAMPLE_RATE))
const LPF_ALPHA: float = 0.8

## DMG wave duty patterns, indexed by NR10/NR21 duty bits. The first bit is
## the phase-zero bit written by the hardware, not a duty threshold.
const DUTY_PATTERNS: Array = [
	[0, 0, 0, 0, 0, 0, 0, 1],
	[1, 0, 0, 0, 0, 0, 0, 1],
	[1, 0, 0, 0, 0, 1, 1, 1],
	[0, 1, 1, 1, 1, 1, 1, 0],
]
const WAVE_LEVELS: Array[float] = [0.0, 1.0, 0.5, 0.25]


static func duty_pattern(duty: int) -> Array:
	return DUTY_PATTERNS[clampi(duty, 0, 3)].duplicate()


static func register_frequency(register: int, hardware_channel: int) -> float:
	return _register_to_hz(register, hardware_channel)


static func render(decoded: Dictionary, assets: Dictionary = {}) -> Dictionary:
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "reason": decoded.get("reason", &"audio_decode_failed")}
	if (decoded.get("tracks", []) as Array).is_empty():
		return {"ok": false, "reason": &"audio_has_no_tracks"}
	var source_frames: int = maxi(1, int(decoded.get("duration_frames", 1)))
	var frame_count: int = mini(source_frames, MAX_RENDER_FRAMES)
	var state: Dictionary = create_state(decoded, assets)
	var chunk := _render_state(decoded, state, frame_count, assets)
	if not bool(chunk.get("ok", false)):
		return chunk
	var data := PackedByteArray()
	var samples: PackedVector2Array = chunk["buffer"]
	data.resize(samples.size() * 4)
	for index: int in samples.size():
		var left: int = clampi(int(roundf(samples[index].x * 32767.0)), -32768, 32767)
		var right: int = clampi(int(roundf(samples[index].y * 32767.0)), -32768, 32767)
		var at: int = index * 4
		data[at] = left & 0xFF
		data[at + 1] = (left >> 8) & 0xFF
		data[at + 2] = right & 0xFF
		data[at + 3] = (right >> 8) & 0xFF

	var looped: bool = bool(decoded.get("looped", false))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = data
	if looped:
		var loop_frame: int = int(decoded.get("loop_start_frame", -1))
		var loop_begin: int = clampi(_frame_sample(loop_frame), 0, samples.size() - 1)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = loop_begin
		stream.loop_end = samples.size()
	return {
		"ok": true,
		"stream": stream,
		"frame_count": frame_count,
		"sample_rate": SAMPLE_RATE,
		"looped": looped,
		"decoded": decoded,
	}


## Creates persistent channel and analog state. Call render_chunk_stateful for
## successive buffers; the state must not be recreated at an AudioStreamGenerator
## boundary.
static func create_state(_decoded: Dictionary, _assets: Dictionary = {}) -> Dictionary:
	var tracks: Array = []
	for _track: Dictionary in _decoded.get("tracks", []):
		tracks.append({
			"event_index": 0,
			"phase": 0.0,
			"lfsr": 0x7FFF,
			"noise_clock": 0.0,
			"noise_row": -1,
		})
	return {
		"sample_cursor": 0,
		"tracks": tracks,
		"hpf_left": 0.0,
		"hpf_right": 0.0,
		"lpf_left": 0.0,
		"lpf_right": 0.0,
	}


## Renders from the current state and advances it. The returned sample count is
## based on the exact source-frame boundaries, so 60 Hz chunks do not accumulate
## a fractional-sample drift.
static func render_chunk_stateful(
	decoded: Dictionary, state: Dictionary, frame_count: int, assets: Dictionary = {}
) -> Dictionary:
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "reason": decoded.get("reason", &"audio_decode_failed")}
	return _render_state(decoded, state, maxi(frame_count, 1), assets)


static func prime_state(
	decoded: Dictionary, state: Dictionary, start_frame: int, assets: Dictionary = {}
) -> void:
	var target: int = _frame_sample(maxi(start_frame, 0))
	if target > int(state.get("sample_cursor", 0)):
		_render_samples(decoded, state, target - int(state.get("sample_cursor", 0)), assets, false)


## Compatibility API. It uses the same state machine and primes it from sample 0,
## making isolated chunks mathematically identical to a full render, including
## noise, modulation and analog filter state.
static func render_chunk(
	decoded: Dictionary, start_frame: int, frame_count: int, assets: Dictionary = {}
) -> Dictionary:
	var state: Dictionary = create_state(decoded, assets)
	var start_sample: int = _frame_sample(maxi(start_frame, 0))
	if start_sample > 0:
		_render_samples(decoded, state, start_sample, assets, false)
	return _render_state(decoded, state, maxi(frame_count, 1), assets)


static func _render_state(
	decoded: Dictionary, state: Dictionary, frame_count: int, assets: Dictionary
) -> Dictionary:
	var start_frame_sample: int = int(state.get("sample_cursor", 0))
	var end_frame_sample: int = start_frame_sample + _frame_sample(frame_count)
	var sample_count: int = maxi(1, end_frame_sample - start_frame_sample)
	var samples := PackedVector2Array()
	samples.resize(sample_count)
	for index: int in sample_count:
		samples[index] = _sample(decoded, state, assets)
	return {
		"ok": true,
		"buffer": samples,
		"frame_count": frame_count,
		"sample_count": sample_count,
	}


static func _render_samples(
	decoded: Dictionary, state: Dictionary, sample_count: int, assets: Dictionary,
	keep_output: bool
) -> PackedVector2Array:
	var samples := PackedVector2Array()
	if keep_output:
		samples.resize(sample_count)
	for index: int in sample_count:
		var value := _sample(decoded, state, assets)
		if keep_output:
			samples[index] = value
	return samples


static func _sample(decoded: Dictionary, state: Dictionary, assets: Dictionary) -> Vector2:
	var left: float = 0.0
	var right: float = 0.0
	var source_sample: int = int(state.get("sample_cursor", 0))
	var track_states: Array = state["tracks"]
	var tracks: Array = decoded.get("tracks", [])
	var wave: PackedByteArray = _wave_bytes(assets)
	for track_index: int in tracks.size():
		var track: Dictionary = tracks[track_index]
		var channel_state: Dictionary = track_states[track_index]
		var event_index: int = _event_at(track, source_sample, int(channel_state["event_index"]))
		if event_index != int(channel_state["event_index"]):
			channel_state["event_index"] = event_index
			channel_state["phase"] = 0.0
			channel_state["noise_row"] = -1
		var events: Array = track.get("events", [])
		if event_index < 0 or event_index >= events.size():
			continue
		var event: Dictionary = events[event_index]
		var start_sample: int = _frame_sample(int(event.get("start_frame", 0)))
		var age: int = maxi(0, source_sample - start_sample)
		var duration_samples: int = _frame_sample(int(event.get("duration_frames", 0)))
		var tail_samples: int = _frame_sample(int(event.get("tail_frames", 0)))
		if age >= duration_samples + tail_samples or int(event.get("pitch", 0)) == 0:
			continue
		var gain_left: float = 0.0
		var gain_right: float = 0.0
		if int(event.get("pan_left", 1)) != 0:
			gain_left = (float(int(event.get("master_left", 7))) + 1.0) / 8.0
		if int(event.get("pan_right", 1)) != 0:
			gain_right = (float(int(event.get("master_right", 7))) + 1.0) / 8.0
		var value: float = 0.0
		var hardware: int = int(event.get("hardware_channel", 1))
		var step: float = 0.0
		if bool(event.get("noise", false)):
			value = _noise_sample(event, age, channel_state)
		else:
			var register: int = _modulated_register(event, age)
			step = _register_to_hz(register, hardware) / SAMPLE_RATE
			var phase: float = float(channel_state["phase"])
			if hardware == 3:
				value = _wave_sample(event, phase, wave)
			else:
				var duty: int = int(event.get("duty", 0))
				var duty_pattern: Array = DUTY_PATTERNS[clampi(duty, 0, 3)]
				value = 1.0 if duty_pattern[int(phase * 8.0) & 7] != 0 else 0.0
				value *= _envelope_gain(event, age)
		if not bool(event.get("noise", false)):
			if hardware == 3:
				value *= WAVE_LEVELS[clampi(int(event.get("wave_level", 0)), 0, 3)]
			channel_state["phase"] = fmod(float(channel_state["phase"]) + step, 1.0)
		left += value * gain_left
		right += value * gain_right
	var output_left: float = _analog_output(left, state, true)
	var output_right: float = _analog_output(right, state, false)
	state["sample_cursor"] = source_sample + 1
	return Vector2(output_left, output_right)


static func _event_at(track: Dictionary, sample: int, hint: int) -> int:
	var events: Array = track.get("events", [])
	var index: int = clampi(hint, 0, events.size())
	while index < events.size():
		var event: Dictionary = events[index]
		var start: int = _frame_sample(int(event.get("start_frame", 0)))
		var end: int = _frame_sample(
			int(event.get("start_frame", 0)) + int(event.get("duration_frames", 0))
			+ int(event.get("tail_frames", 0))
		)
		if sample < start:
			return index - 1
		if sample < end:
			return index
		index += 1
	return events.size()


static func _modulated_register(event: Dictionary, age_samples: int) -> int:
	var base: int = int(event.get("frequency", 0)) & 0x7FF
	var age_frame: int = int(floor(float(age_samples) * 60.0 / SAMPLE_RATE))
	var target: int = int(event.get("pitch_slide_target", -1))
	if target >= 0:
		var slide_frames: int = maxi(1, int(event.get(
			"pitch_slide_frames", event.get("pitch_slide_duration", 0))))
		var progress_frame: int = mini(age_frame, slide_frames)
		base = base + int(round(float(target - base) * float(progress_frame) / float(slide_frames)))
	var vibrato: Dictionary = event.get("vibrato", {})
	if not vibrato.is_empty():
		var delay: int = int(vibrato.get("delay_frames", 0))
		var rate: int = int(vibrato.get("rate", 0))
		if age_frame >= delay and rate >= 0:
			var toggles: int = int(floor(float(age_frame - delay + 1) / float(rate + 1)))
			var low: int = base & 0xFF
			var high: int = base & 0x700
			if (toggles & 1) != 0:
				low = mini(0xFF, low + int(vibrato.get("above", 0)))
			else:
				low = maxi(0, low - int(vibrato.get("below", 0)))
			base = high | low
	return clampi(base, 0, 0x7FF)


static func _envelope_gain(event: Dictionary, age_samples: int) -> float:
	var level: int = int(event.get("volume", 0))
	var fade: int = int(event.get("fade", 0))
	if fade != 0:
		var seconds: float = float(age_samples) / SAMPLE_RATE
		var steps: int = int(floor(seconds / (absf(float(fade)) / ENVELOPE_STEPS_PER_SECOND)))
		level = maxi(0, level - steps) if fade > 0 else mini(15, level + steps)
	return float(level) / 15.0


static func _noise_sample(event: Dictionary, age_samples: int, channel_state: Dictionary) -> float:
	var rows: Array = event.get("noise_samples", [])
	var row_index: int = 0
	var row_age: int = age_samples
	if not rows.is_empty():
		var remaining: int = 0
		row_index = rows.size() - 1
		for index: int in rows.size():
			var row_samples: int = maxi(1, _frame_sample(int(rows[index].get("duration_frames", 1))))
			if age_samples < remaining + row_samples:
				row_index = index
				row_age = age_samples - remaining
				break
			remaining += row_samples
		if int(channel_state["noise_row"]) != row_index:
			channel_state["noise_row"] = row_index
			channel_state["lfsr"] = 0x7FFF
			channel_state["noise_clock"] = 0.0
	var row: Dictionary = rows[row_index] if not rows.is_empty() else event
	var parameter: int = int(row.get("frequency", event.get("frequency", 0))) & 0xFF
	var divisor: int = 8 if (parameter & 7) == 0 else (parameter & 7) * 16
	var shift: int = (parameter >> 4) & 0x0F
	var clocks_per_sample: float = 0.0 if shift >= 14 else GB_CLOCK / float(divisor << shift) / SAMPLE_RATE
	var clock: float = float(channel_state["noise_clock"]) + clocks_per_sample
	var clocks: int = mini(int(floor(clock)), MAX_NOISE_CLOCKS_PER_SAMPLE)
	channel_state["noise_clock"] = clock - floor(clock)
	for _clock: int in clocks:
		var lfsr: int = int(channel_state["lfsr"])
		var feedback: int = (lfsr & 1) ^ ((lfsr >> 1) & 1)
		lfsr = (lfsr >> 1) | (feedback << 14)
		if (parameter & 8) != 0:
			lfsr = (lfsr & ~0x40) | (feedback << 6)
		channel_state["lfsr"] = lfsr
	var envelope_event := event
	if not rows.is_empty():
		envelope_event = row
	var value: float = 1.0 if (int(channel_state["lfsr"]) & 1) == 0 else 0.0
	return value * _envelope_gain(envelope_event, row_age)


static func _wave_sample(event: Dictionary, phase: float, wave: PackedByteArray) -> float:
	var base: int = clampi(int(event.get("wave_index", 0)), 0, 9) * 16
	if base + 16 > wave.size():
		return 0.0
	var position: int = int(phase * 32.0) & 31
	var packed: int = wave[base + position / 2]
	var nibble: int = packed >> 4 if (position & 1) == 0 else packed & 0x0F
	return float(nibble) / 15.0


static func _analog_output(input: float, state: Dictionary, left: bool) -> float:
	var cap_key: String = "hpf_left" if left else "hpf_right"
	var lpf_key: String = "lpf_left" if left else "lpf_right"
	var cap: float = float(state[cap_key])
	var high_pass: float = input - cap
	state[cap_key] = input - high_pass * HPF_CHARGE
	var low_pass: float = float(state[lpf_key]) + LPF_ALPHA * (high_pass - float(state[lpf_key]))
	state[lpf_key] = low_pass
	return clampf(low_pass * MIX_SCALE, -1.0, 1.0)


static func _register_to_hz(value: int, hardware_channel: int) -> float:
	if value <= 0 or value >= 2048:
		return 0.0
	return (65536.0 if hardware_channel == 3 else 131072.0) / float(2048 - value)


static func _frame_sample(frame: int) -> int:
	return int(floor(float(maxi(frame, 0)) * SAMPLE_RATE / 60.0))


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
