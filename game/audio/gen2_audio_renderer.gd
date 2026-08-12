class_name Gen2AudioRenderer
extends RefCounted

## Stateful DMG/GBC channel renderer. A RenderState is a live hardware timeline:
## it owns phase, noise, envelope/event cursors and the per-output analog filter.

const SAMPLE_RATE: int = 22050
const MAX_RENDER_FRAMES: int = 60 * 60 * 30
const ENVELOPE_STEPS_PER_SECOND: float = 64.0
const MAX_NOISE_CLOCKS_PER_SAMPLE: int = 64
const GB_CLOCK: float = 4194304.0
const FRAME_CLOCKS: int = 70224
## _UpdateSound runs once per LCD VBlank, so a source frame is the DMG clock
## divided by 70,224 clocks rather than an idealized 60 Hz.
const SOURCE_FRAME_RATE: float = GB_CLOCK / float(FRAME_CLOCKS)
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


static func frame_sample(frame: int) -> int:
	return _frame_sample(frame)


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
	for source_track: Dictionary in _decoded.get("tracks", []):
		var source_events: Array = source_track.get("events", [])
		var first_start: int = 0
		var first_end: int = 0
		if not source_events.is_empty():
			var first_event: Dictionary = source_events[0]
			first_start = _frame_sample(int(first_event.get("start_frame", 0)))
			first_end = _frame_sample(
				int(first_event.get("start_frame", 0)) + int(first_event.get("duration_frames", 0))
				+ int(first_event.get("tail_frames", 0))
			)
		tracks.append({
			"events": source_events,
			"hardware_channel": int(source_track.get("hardware_channel", 1)),
			"event_index": 0,
			"event_start_sample": first_start,
			"event_end_sample": first_end,
			"phase": 0.0,
			"lfsr": 0x7FFF,
			"noise_clock": 0.0,
			"noise_row": -1,
		})
	return {
		"sample_cursor": 0,
		"source_frame_cursor": 0,
		"wave_bytes": _wave_bytes(_assets),
		"track_data": _decoded.get("tracks", []),
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
	state["source_frame_cursor"] = maxi(start_frame, 0)


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
	state["source_frame_cursor"] = maxi(start_frame, 0)
	return _render_state(decoded, state, maxi(frame_count, 1), assets)


static func _render_state(
	decoded: Dictionary, state: Dictionary, frame_count: int, assets: Dictionary
) -> Dictionary:
	var start_frame_sample: int = int(state.get("sample_cursor", 0))
	var start_frame: int = int(state.get("source_frame_cursor", 0))
	var end_frame_sample: int = start_frame_sample + _frame_sample(start_frame + frame_count) - _frame_sample(start_frame)
	var sample_count: int = maxi(1, end_frame_sample - start_frame_sample)
	var samples := PackedVector2Array()
	samples.resize(sample_count)
	for index: int in sample_count:
		samples[index] = _sample(decoded, state, assets)
	state["source_frame_cursor"] = start_frame + frame_count
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
	var tracks: Array = state["track_data"]
	var wave: PackedByteArray = state["wave_bytes"] if state.has("wave_bytes") else _wave_bytes(assets)
	for track_index: int in tracks.size():
		var channel_state: Dictionary = track_states[track_index]
		var events: Array = channel_state["events"]
		var event_index: int = int(channel_state["event_index"])
		while event_index < events.size() and source_sample >= int(channel_state["event_end_sample"]):
			event_index += 1
			if event_index < events.size():
				var next_event: Dictionary = events[event_index]
				channel_state["event_start_sample"] = _frame_sample(int(next_event.get("start_frame", 0)))
				channel_state["event_end_sample"] = _frame_sample(
					int(next_event.get("start_frame", 0)) + int(next_event.get("duration_frames", 0))
					+ int(next_event.get("tail_frames", 0))
				)
			else:
				channel_state["event_start_sample"] = source_sample
				channel_state["event_end_sample"] = source_sample
		if event_index != int(channel_state["event_index"]):
			channel_state["event_index"] = event_index
			channel_state["phase"] = 0.0
			channel_state["noise_row"] = -1
		if event_index < 0 or event_index >= events.size():
			continue
		var event: Dictionary = events[event_index]
		var start_sample: int = int(channel_state["event_start_sample"])
		var age: int = maxi(0, source_sample - start_sample)
		if source_sample < start_sample or age >= int(channel_state["event_end_sample"]) - start_sample or int(event.get("pitch", 0)) == 0:
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
				var duty_sequence: Variant = event.get("duty_pattern", [])
				if duty_sequence is Array and not (duty_sequence as Array).is_empty():
					var duty_frame: int = int(floor(float(age) * SOURCE_FRAME_RATE / SAMPLE_RATE))
					duty = int((duty_sequence as Array)[duty_frame % (duty_sequence as Array).size()])
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
	var age_frame: int = int(floor(float(age_samples) * SOURCE_FRAME_RATE / SAMPLE_RATE))
	var sweep: Dictionary = event.get("pitch_sweep", {})
	if not sweep.is_empty() and int(sweep.get("shift", 0)) > 0:
		var pace: int = int(sweep.get("pace", 0))
		if pace > 0:
			var iterations: int = int(floor(float(age_samples) * SOURCE_FRAME_RATE / SAMPLE_RATE * 128.0 / float(pace)))
			for _iteration: int in iterations:
				var delta: int = base >> int(sweep.get("shift", 0))
				base = base - delta if bool(sweep.get("subtract", false)) else base + delta
				if base < 0 or base > 0x7FF:
					return 0
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


static func _noise_sample(
	event: Dictionary, age_samples: int, channel_state: Dictionary, prefix: String = ""
) -> float:
	var lfsr_key: String = "lfsr" if prefix.is_empty() else prefix + "lfsr"
	var clock_key: String = "noise_clock" if prefix.is_empty() else prefix + "noise_clock"
	var row_key: String = "noise_row" if prefix.is_empty() else prefix + "noise_row"
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
		if int(channel_state.get(row_key, -1)) != row_index:
			channel_state[row_key] = row_index
			channel_state[lfsr_key] = 0x7FFF
			channel_state[clock_key] = 0.0
	var row: Dictionary = rows[row_index] if not rows.is_empty() else event
	var parameter: int = int(row.get("frequency", event.get("frequency", 0))) & 0xFF
	var divisor: int = 8 if (parameter & 7) == 0 else (parameter & 7) * 16
	var shift: int = (parameter >> 4) & 0x0F
	var clocks_per_sample: float = 0.0 if shift >= 14 else GB_CLOCK / float(divisor << shift) / SAMPLE_RATE
	var clock: float = float(channel_state.get(clock_key, 0.0)) + clocks_per_sample
	var clocks: int = mini(int(floor(clock)), MAX_NOISE_CLOCKS_PER_SAMPLE)
	channel_state[clock_key] = clock - floor(clock)
	for _clock: int in clocks:
		var lfsr: int = int(channel_state.get(lfsr_key, 0x7FFF))
		var feedback: int = (lfsr & 1) ^ ((lfsr >> 1) & 1)
		lfsr = (lfsr >> 1) | (feedback << 14)
		if (parameter & 8) != 0:
			lfsr = (lfsr & ~0x40) | (feedback << 6)
		channel_state[lfsr_key] = lfsr
	var envelope_event := event
	if not rows.is_empty():
		envelope_event = row
	var value: float = 1.0 if (int(channel_state.get(lfsr_key, 0x7FFF)) & 1) == 0 else 0.0
	return value * _envelope_gain(envelope_event, row_age)


static func _wave_sample(event: Dictionary, phase: float, wave: PackedByteArray) -> float:
	var base: int = clampi(int(event.get("wave_index", 0)), 0, 9) * 16
	if base + 16 > wave.size():
		return 0.0
	var position: int = int(phase * 32.0) & 31
	var packed: int = wave[base + position / 2]
	var nibble: int = packed >> 4 if (position & 1) == 0 else packed & 0x0F
	return (float(nibble) - 8.0) / 8.0


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
	return int(floor(float(maxi(frame, 0)) * SAMPLE_RATE / SOURCE_FRAME_RATE))


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


## Shared hardware timeline used by the runtime player. Music, effects and
## cries all feed the same four channel states and the same output filters.
static func create_shared_state(decoded: Dictionary, _assets: Dictionary = {}) -> Dictionary:
	var state := {
		"sample_cursor": 0,
		"frame_cursor": 0,
		"music_sample_cursor": 0,
		"music_frame_cursor": 0,
		"music_decoded": decoded,
		"music_tracks": decoded.get("tracks", []),
		"wave_bytes": _wave_bytes(_assets),
		"channels": [],
		"effects": [],
		"next_effect_id": 1,
		"stolen_channels": 0,
		"restored_channels": 0,
		"replaced_effects": 0,
		"hpf_left": 0.0,
		"hpf_right": 0.0,
		"lpf_left": 0.0,
		"lpf_right": 0.0,
	}
	for hardware: int in 4:
		var channel := {
			"hardware_channel": hardware + 1,
			"music_track_index": _track_index_for_hardware(decoded, hardware + 1),
			"music_event_index": -1,
			"music_phase": 0.0,
			"music_lfsr": 0x7FFF,
			"music_noise_clock": 0.0,
			"music_noise_row": -1,
			"effect_id": -1,
			"effect_track_index": -1,
			"effect_event_index": -1,
			"effect_phase": 0.0,
			"effect_lfsr": 0x7FFF,
			"effect_noise_clock": 0.0,
			"effect_noise_row": -1,
		}
		(state["channels"] as Array).append(channel)
	return state


static func start_effect(
	state: Dictionary, decoded: Dictionary, _assets: Dictionary = {}, priority: bool = false
) -> Dictionary:
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "reason": decoded.get("reason", &"audio_decode_failed")}
	var tracks: Array = decoded.get("tracks", [])
	if tracks.is_empty():
		return {"ok": false, "reason": &"audio_has_no_tracks"}
	var claimed: Array[int] = []
	var track_by_hardware: Dictionary = {}
	var track_states: Array = []
	for track_index: int in tracks.size():
		var track: Dictionary = tracks[track_index]
		var hardware: int = clampi(int(track.get("hardware_channel", 1)), 1, 4)
		if not claimed.has(hardware):
			claimed.append(hardware)
		track_by_hardware[str(hardware)] = track_index
		track_states.append({
			"event_index": -1,
			"phase": 0.0,
			"lfsr": 0x7FFF,
			"noise_clock": 0.0,
			"noise_row": -1,
		})
	var effects: Array = state["effects"]
	for old_index: int in effects.size():
		var old: Dictionary = effects[old_index]
		if not bool(old.get("active", false)):
			continue
		var overlaps: bool = false
		for hardware: int in claimed:
			if (old.get("claimed_channels", []) as Array).has(hardware):
				overlaps = true
				break
		if overlaps:
			effects[old_index]["active"] = false
			state["replaced_effects"] = int(state.get("replaced_effects", 0)) + 1
			_release_effect_channels(state, int(old.get("id", -1)))
	var effect_id: int = int(state.get("next_effect_id", 1))
	state["next_effect_id"] = effect_id + 1
	var effect := {
		"id": effect_id,
		"decoded": decoded,
		"start_sample": int(state.get("sample_cursor", 0)),
		"claimed_channels": claimed,
		"track_by_hardware": track_by_hardware,
		"track_states": track_states,
		"priority": priority,
		"active": true,
	}
	effects.append(effect)
	var channels: Array = state["channels"]
	for hardware: int in claimed:
		var channel: Dictionary = channels[hardware - 1]
		channel["effect_id"] = effect_id
		channel["effect_track_index"] = int(track_by_hardware.get(str(hardware), -1))
		channel["effect_event_index"] = -1
		channel["effect_phase"] = 0.0
		channel["effect_lfsr"] = 0x7FFF
		channel["effect_noise_clock"] = 0.0
		channel["effect_noise_row"] = -1
		if int(channel.get("music_track_index", -1)) >= 0:
			state["stolen_channels"] = int(state.get("stolen_channels", 0)) + 1
	return {
		"ok": true,
		"effect_id": effect_id,
		"claimed_channels": claimed,
		"priority": priority,
		"started": true,
	}


static func render_shared_chunk_stateful(
	state: Dictionary, frame_count: int, assets: Dictionary = {}
) -> Dictionary:
	var count: int = maxi(frame_count, 1)
	var start_frame: int = int(state.get("frame_cursor", 0))
	var sample_start: int = int(state.get("sample_cursor", 0))
	var sample_count: int = maxi(1, _frame_sample(start_frame + count) - _frame_sample(start_frame))
	var samples := PackedVector2Array()
	samples.resize(sample_count)
	for index: int in sample_count:
		samples[index] = _shared_sample(state, assets)
	state["frame_cursor"] = start_frame + count
	return {
		"ok": true,
		"buffer": samples,
		"frame_count": count,
		"sample_count": sample_count,
		"sample_start": sample_start,
		"effect_playing": shared_effect_playing(state),
	}


static func restart_shared_music(state: Dictionary, loop_start_frame: int) -> void:
	var start: int = maxi(loop_start_frame, 0)
	state["music_frame_cursor"] = start
	state["music_sample_cursor"] = _frame_sample(start)
	for channel: Dictionary in state.get("channels", []):
		channel["music_event_index"] = -1
		channel["music_noise_row"] = -1


static func shared_effect_playing(state: Dictionary) -> bool:
	for effect: Dictionary in state.get("effects", []):
		if bool(effect.get("active", false)):
			return true
	return false


static func shared_status(state: Dictionary) -> Dictionary:
	var active: Array = []
	for effect: Dictionary in state.get("effects", []):
		if bool(effect.get("active", false)):
			active.append(int(effect.get("id", -1)))
	return {
		"active_effect_ids": active,
		"stolen_channels": int(state.get("stolen_channels", 0)),
		"restored_channels": int(state.get("restored_channels", 0)),
		"replaced_effects": int(state.get("replaced_effects", 0)),
		"sample_cursor": int(state.get("sample_cursor", 0)),
	}


static func _track_index_for_hardware(decoded: Dictionary, hardware: int) -> int:
	var tracks: Array = decoded.get("tracks", [])
	for index: int in tracks.size():
		if int((tracks[index] as Dictionary).get("hardware_channel", 1)) == hardware:
			return index
	return -1


static func _shared_sample(state: Dictionary, assets: Dictionary) -> Vector2:
	var left: float = 0.0
	var right: float = 0.0
	var wave: PackedByteArray = state["wave_bytes"] if state.has("wave_bytes") else _wave_bytes(assets)
	var global_sample: int = int(state.get("sample_cursor", 0))
	var music_sample: int = int(state.get("music_sample_cursor", 0))
	var channels: Array = state["channels"]
	for hardware: int in 4:
		var channel: Dictionary = channels[hardware]
		var event: Dictionary = {}
		var age: int = 0
		var channel_state: Dictionary = channel
		var prefix: String = "music_"
		var effect_index: int = _active_effect_index_for_channel(state, hardware + 1)
		if effect_index >= 0:
			var effect: Dictionary = (state["effects"] as Array)[effect_index]
			var track_index: int = int((effect.get("track_by_hardware", {}) as Dictionary).get(str(hardware + 1), -1))
			if track_index >= 0:
				var effect_track: Dictionary = (effect["decoded"].get("tracks", []) as Array)[track_index]
				var track_state: Dictionary = (effect["track_states"] as Array)[track_index]
				var local_sample: int = global_sample - int(effect.get("start_sample", global_sample))
				var next_index: int = _event_at(effect_track, local_sample, int(track_state.get("event_index", -1)))
				if next_index != int(track_state.get("event_index", -1)):
					track_state["event_index"] = next_index
					track_state["phase"] = 0.0
					track_state["noise_row"] = -1
				var effect_events: Array = effect_track.get("events", [])
				if next_index >= 0 and next_index < effect_events.size():
					event = effect_events[next_index]
					age = maxi(0, local_sample - _frame_sample(int(event.get("start_frame", 0))))
					channel_state = track_state
					prefix = ""
		else:
			var music_track_index: int = int(channel.get("music_track_index", -1))
			var music_tracks: Array = state.get("music_tracks", [])
			if music_track_index >= 0 and music_track_index < music_tracks.size():
				var music_track: Dictionary = music_tracks[music_track_index]
				var next_music: int = _event_at(music_track, music_sample, int(channel.get("music_event_index", -1)))
				if next_music != int(channel.get("music_event_index", -1)):
					channel["music_event_index"] = next_music
					channel["music_phase"] = 0.0
					channel["music_noise_row"] = -1
				var music_events: Array = music_track.get("events", [])
				if next_music >= 0 and next_music < music_events.size():
					event = music_events[next_music]
					age = maxi(0, music_sample - _frame_sample(int(event.get("start_frame", 0))))
					channel_state = channel
					prefix = "music_"
		if not event.is_empty() and int(event.get("pitch", 0)) != 0:
			var value: float = _shared_event_sample(event, age, channel_state, wave, prefix)
			var gain_left: float = 0.0
			var gain_right: float = 0.0
			if int(event.get("pan_left", 1)) != 0:
				gain_left = (float(int(event.get("master_left", 7))) + 1.0) / 8.0
			if int(event.get("pan_right", 1)) != 0:
				gain_right = (float(int(event.get("master_right", 7))) + 1.0) / 8.0
			left += value * gain_left
			right += value * gain_right
	state["sample_cursor"] = global_sample + 1
	state["music_sample_cursor"] = music_sample + 1
	_retire_shared_effects(state)
	return Vector2(_analog_output(left, state, true), _analog_output(right, state, false))


static func _shared_event_sample(
	event: Dictionary, age: int, channel_state: Dictionary, wave: PackedByteArray, prefix: String
) -> float:
	if bool(event.get("noise", false)):
		return _noise_sample(event, age, channel_state, prefix)
	var phase_key: String = "phase" if prefix.is_empty() else prefix + "phase"
	var phase: float = float(channel_state.get(phase_key, 0.0))
	var register: int = _modulated_register(event, age)
	var hardware: int = int(event.get("hardware_channel", 1))
	var step: float = _register_to_hz(register, hardware) / SAMPLE_RATE
	var value: float = _wave_sample(event, phase, wave) if hardware == 3 else 0.0
	if hardware != 3:
		var duty: int = int(event.get("duty", 2))
		var sequence: Variant = event.get("duty_pattern", [])
		if sequence is Array and not (sequence as Array).is_empty():
			var duty_frame: int = int(floor(float(age) * SOURCE_FRAME_RATE / SAMPLE_RATE))
			duty = int((sequence as Array)[duty_frame % (sequence as Array).size()])
		var pattern: Array = DUTY_PATTERNS[clampi(duty, 0, 3)]
		value = 1.0 if pattern[int(phase * 8.0) & 7] != 0 else 0.0
		value *= _envelope_gain(event, age)
	if hardware == 3:
		value *= WAVE_LEVELS[clampi(int(event.get("wave_level", 0)), 0, 3)]
	channel_state[phase_key] = fmod(phase + step, 1.0)
	return value


static func _active_effect_index_for_channel(state: Dictionary, hardware: int) -> int:
	var effects: Array = state.get("effects", [])
	var latest: int = -1
	var latest_id: int = -1
	for index: int in effects.size():
		var effect: Dictionary = effects[index]
		if bool(effect.get("active", false)) and (effect.get("claimed_channels", []) as Array).has(hardware):
			if int(effect.get("id", -1)) > latest_id:
				latest = index
				latest_id = int(effect.get("id", -1))
	return latest


static func _retire_shared_effects(state: Dictionary) -> void:
	var effects: Array = state["effects"]
	var sample: int = int(state.get("sample_cursor", 0))
	for effect: Dictionary in effects:
		if not bool(effect.get("active", false)):
			continue
		var decoded: Dictionary = effect.get("decoded", {})
		if bool(decoded.get("looped", false)):
			continue
		if sample - int(effect.get("start_sample", sample)) >= _frame_sample(int(decoded.get("duration_frames", 0))):
			effect["active"] = false
			_release_effect_channels(state, int(effect.get("id", -1)))


static func _release_effect_channels(state: Dictionary, effect_id: int) -> void:
	var channels: Array = state["channels"]
	for channel: Dictionary in channels:
		if int(channel.get("effect_id", -1)) == effect_id:
			channel["effect_id"] = -1
			channel["effect_track_index"] = -1
			channel["effect_event_index"] = -1
			state["restored_channels"] = int(state.get("restored_channels", 0)) + 1
