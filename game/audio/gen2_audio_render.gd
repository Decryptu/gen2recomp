class_name Gen2AudioRender
extends RefCounted

## Offline render of one audio record: run the driver for a fixed number of
## frames and keep the samples. Used by the parity tool and by tests; live
## playback drives [Gen2SoundEngine] and [Gen2Apu] directly.


## Returns `pcm` as interleaved 16-bit stereo, and `trace` as the driver's
## hardware-register writes when `trace` is asked for.
static func render(
	record: Dictionary,
	kind: StringName,
	assets: Dictionary,
	frames: int,
	stereo: bool = false,
	trace: bool = false,
) -> Dictionary:
	if record.is_empty():
		return {"ok": false, "reason": &"audio_data_unavailable"}
	var apu := Gen2Apu.new()
	var engine := Gen2SoundEngine.new(apu)
	engine.stereo = stereo
	engine.set_assets(assets)
	apu.tracing = trace
	engine.init_sound()
	var started: bool = false
	match kind:
		&"cry", &"cries", &"mon_cry":
			started = engine.play_cry(record)
		&"sfx", &"sound":
			started = engine.play_sfx(record)
		_:
			started = engine.play_music(record)
	if not started:
		return {"ok": false, "reason": &"audio_record_unplayable"}

	var pcm := PackedInt32Array()
	pcm.resize(maxi(frames, 1) * Gen2Apu.SAMPLES_PER_FRAME * 2)
	var cursor: int = 0
	for frame: int in maxi(frames, 1):
		apu.trace_frame = frame
		engine.update_sound()
		var block: PackedInt32Array = apu.render_frame_pcm()
		for index: int in block.size():
			pcm[cursor + index] = block[index]
		cursor += block.size()
	return {
		"ok": true,
		"pcm": pcm,
		"trace": "\n".join(apu.trace_lines) + "\n" if trace else "",
		"frames": maxi(frames, 1),
	}


## Writes interleaved 16-bit stereo as a RIFF/WAVE file.
static func write_wav(path: String, pcm: PackedInt32Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var data_bytes: int = pcm.size() * 2
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_bytes)
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(2)
	file.store_32(Gen2Apu.SAMPLE_RATE)
	file.store_32(Gen2Apu.SAMPLE_RATE * 4)
	file.store_16(4)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_bytes)
	var samples := PackedByteArray()
	samples.resize(data_bytes)
	for index: int in pcm.size():
		var value: int = clampi(pcm[index], -32768, 32767) & 0xFFFF
		samples[index * 2] = value & 0xFF
		samples[index * 2 + 1] = (value >> 8) & 0xFF
	file.store_buffer(samples)
	file.close()
	return true
