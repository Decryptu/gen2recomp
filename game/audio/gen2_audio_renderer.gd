class_name Gen2AudioRenderer
extends RefCounted

## Converts decoded cartridge events into a Godot AudioStreamWAV. The source
## engine updates one channel every frame, so the renderer evaluates event
## state at the same 60 Hz timeline and only uses the output sample rate for
## interpolation between those state changes.

const SAMPLE_RATE: int = 22050
const MAX_RENDER_FRAMES: int = 60 * 30
const TWO_PI: float = TAU


static func render(decoded: Dictionary, assets: Dictionary = {}) -> Dictionary:
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "reason": decoded.get("reason", &"audio_decode_failed")}
	var tracks: Array = decoded.get("tracks", [])
	if tracks.is_empty():
		return {"ok": false, "reason": &"audio_has_no_tracks"}
	var source_frames: int = maxi(1, int(decoded.get("duration_frames", 1)))
	var render_frames: int = mini(source_frames, MAX_RENDER_FRAMES)
	var render_samples: int = maxi(1, render_frames * SAMPLE_RATE / 60)
	var looped: bool = bool(decoded.get("looped", false))
	var data := PackedByteArray()
	data.resize(render_samples * 4)
	var cursors: Array[int] = []
	var phases: Array[float] = []
	var lfsr: Array[int] = []
	for _track: Dictionary in tracks:
		cursors.append(0)
		phases.append(0.0)
		lfsr.append(0x7FFF)

	for sample_index: int in render_samples:
		var frame: int = int(float(sample_index) * 60.0 / float(SAMPLE_RATE))
		if looped and source_frames > 0:
			frame = frame % source_frames
		var mixed: float = 0.0
		for track_index: int in tracks.size():
			var track: Dictionary = tracks[track_index]
			var events: Array = track.get("events", [])
			var cursor: int = cursors[track_index]
			while cursor < events.size():
				var candidate: Dictionary = events[cursor]
				var candidate_end: int = int(candidate.get("start_frame", 0)) + int(
					candidate.get("duration_frames", 0)
				)
				if candidate_end > frame:
					break
				cursor += 1
			cursors[track_index] = cursor
			if cursor >= events.size():
				continue
			var event: Dictionary = events[cursor]
			var start: int = int(event.get("start_frame", 0))
			var end: int = start + int(event.get("duration_frames", 0))
			if frame < start or frame >= end or int(event.get("pitch", 0)) == 0:
				continue
			var value: Dictionary = _sample_event(
				event, track, track_index, sample_index, phases, lfsr, assets
			)
			mixed += float(value.get("sample", 0.0)) * float(value.get("volume", 0.0))
		var output: int = clampi(int(mixed * 7000.0), -32768, 32767)
		var byte_at: int = sample_index * 4
		data[byte_at] = output & 0xFF
		data[byte_at + 1] = (output >> 8) & 0xFF
		data[byte_at + 2] = data[byte_at]
		data[byte_at + 3] = data[byte_at + 1]

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = data
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = render_samples
	return {
		"ok": true,
		"stream": stream,
		"frame_count": render_frames,
		"sample_rate": SAMPLE_RATE,
		"looped": looped,
		"decoded": decoded,
	}


static func _sample_event(
	event: Dictionary, track: Dictionary, track_index: int, sample_index: int,
	phases: Array[float], lfsr: Array[int], assets: Dictionary
) -> Dictionary:
	var hardware_channel: int = int(event.get("hardware_channel", 1))
	var volume: float = float(int(event.get("volume", 0))) / 15.0
	var register_frequency: int = int(event.get("frequency", 0))
	var phase: float = phases[track_index]
	var sample: float = 0.0
	if bool(event.get("noise", false)):
		var envelope: int = int(event.get("envelope", 0xF0))
		var noise_samples: Array = event.get("noise_samples", [])
		if not noise_samples.is_empty():
			var local_frame: int = maxi(
				0, int(float(sample_index) * 60.0 / float(SAMPLE_RATE))
				- int(event.get("start_frame", 0))
			)
			var elapsed: int = 0
			for drum: Dictionary in noise_samples:
				if local_frame < elapsed + int(drum.get("duration_frames", 1)):
					envelope = int(drum.get("envelope", envelope))
					register_frequency = int(drum.get("frequency", register_frequency))
					break
				elapsed += int(drum.get("duration_frames", 1))
			volume = float((envelope >> 4) & 0x0F) / 15.0
			var state: int = lfsr[track_index]
			var stride: int = maxi(1, 18 - (register_frequency & 0x0F))
			if sample_index % stride == 0:
				var bit: int = (state ^ (state >> 1)) & 1
				state = (state >> 1) | (bit << 14)
				lfsr[track_index] = state
			sample = 1.0 if (state & 1) != 0 else -1.0
	elif hardware_channel == 3:
		var wave_index: int = clampi(int(event.get("wave_index", 0)), 0, 9)
		var wave: PackedByteArray = _wave_bytes(assets)
		var wave_position: int = int(phase * 32.0) % 32
		var wave_at: int = wave_index * 16 + wave_position / 2
		if wave_at < wave.size():
			var packed: int = wave[wave_at]
			var nibble: int = packed >> 4 if wave_position % 2 == 0 else packed & 0x0F
			sample = float(nibble) / 7.5 - 1.0
		else:
			var duty: Array[float] = [0.125, 0.25, 0.5, 0.75]
			var threshold: float = duty[clampi(int(event.get("duty", 0)), 0, 3)]
			sample = 1.0 if phase < threshold else -1.0
	else:
		var duty: Array[float] = [0.125, 0.25, 0.5, 0.75]
		var threshold: float = duty[clampi(int(event.get("duty", 0)), 0, 3)]
		sample = 1.0 if phase < threshold else -1.0

	var hz: float = _register_to_hz(register_frequency)
	phases[track_index] = fmod(phase + hz / float(SAMPLE_RATE), 1.0)
	return {"sample": sample, "volume": volume * 0.25}


static func _register_to_hz(value: int) -> float:
	if value <= 0 or value >= 2048:
		return 0.0
	return 131072.0 / float(2048 - value)


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
