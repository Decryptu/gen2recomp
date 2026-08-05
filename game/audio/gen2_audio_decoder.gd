class_name Gen2AudioDecoder
extends RefCounted

## Bounded decoder for the Gen II music, SFX and cry streams.
##
## The importer keeps the original bank/address and a bounded byte window for
## every record. This decoder follows the command table used by the cartridge,
## including little-endian stream pointers, note-duration accumulation,
## subroutine returns and counted/infinite loops. It returns events rather than
## touching an audio device, which keeps the cartridge format testable in
## headless runs and lets the playback layer choose its output rate.

const FIRST_MUSIC_COMMAND: int = 0xD0
const SOUND_RETURN: int = 0xFF
const MAX_STEPS: int = 20000
const MAX_FRAMES: int = 60 * 60
const MAX_EVENTS: int = 4096
const NOTE_COUNT: int = 12

## The table is copied from pret's audio/notes.asm at import time conceptually,
## not from a generated waveform. These are register values used by the
## original GetFrequency routine, and are part of the format definition.
const FREQUENCY_TABLE: Array[int] = [
	0x0000,
	0xF82C, 0xF89D, 0xF907, 0xF96B, 0xF9CA, 0xFA23,
	0xFA77, 0xFAC7, 0xFB12, 0xFB58, 0xFB9B, 0xFBDA,
	0xFC16, 0xFC4E, 0xFC83, 0xFCB5, 0xFCE5, 0xFD11,
	0xFD3B, 0xFD63, 0xFD89, 0xFDAC, 0xFDCD, 0xFDED,
]


static func decode(
	record: Dictionary, request_kind: StringName = &"music", assets: Dictionary = {}
) -> Dictionary:
	if record.is_empty():
		return _failure(&"audio_data_unavailable")
	var bytes: PackedByteArray = _bytes(record.get("bytes", []))
	if bytes.size() < 3:
		return _failure(&"audio_record_truncated")
	var kind: StringName = request_kind
	if kind == &"cry":
		return _decode_cry(record, bytes)
	return _decode_music(record, bytes, kind, assets)


static func _decode_music(
	record: Dictionary, bytes: PackedByteArray, request_kind: StringName, assets: Dictionary
) -> Dictionary:
	var origin: int = int(record.get("data_address", record.get("address", 0)))
	var header_at: int = int(record.get("address", 0)) - origin
	if header_at < 0 or header_at >= bytes.size():
		return _failure(&"audio_header_outside_record")
	var header: int = bytes[header_at]
	var channel_count: int = ((header >> 6) & 0x03) + 1
	if channel_count > 4:
		return _failure(&"audio_invalid_channel_count")
	var tracks: Array = []
	var warnings: Array[StringName] = []
	for _channel: int in channel_count:
		if header_at + 2 >= bytes.size():
			return _failure(&"audio_channel_header_truncated")
		var packed: int = bytes[header_at]
		var channel_id: int = (packed & 0x0F) + 1
		var address: int = _audio_address(_u16(bytes, header_at + 1))
		var stream_at: int = address - origin
		if stream_at < 0 or stream_at >= bytes.size():
			return _failure(&"audio_channel_pointer_outside_record")
		var track_result: Dictionary = _decode_track(
			bytes, stream_at, channel_id, request_kind, origin, assets
		)
		if not bool(track_result.get("ok", false)):
			var details: Dictionary = track_result.get("details", {})
			details["channel"] = channel_id
			details["stream_at"] = stream_at
			track_result["details"] = details
			return track_result
		tracks.append(track_result["track"])
		for warning: StringName in track_result.get("warnings", []):
			if not warnings.has(warning):
				warnings.append(warning)
		header_at += 3

	var duration: int = 0
	var looped: bool = false
	for track: Dictionary in tracks:
		duration = maxi(duration, int(track.get("end_frame", 0)))
		looped = looped or bool(track.get("looped", false))
	return {
		"ok": true,
		"kind": request_kind,
		"format": &"music_stream",
		"tracks": tracks,
		"duration_frames": duration,
		"looped": looped,
		"warnings": warnings,
	}


static func _decode_cry(record: Dictionary, bytes: PackedByteArray) -> Dictionary:
	var origin: int = int(record.get("data_address", record.get("address", 0)))
	var header_at: int = int(record.get("address", 0)) - origin
	if header_at < 0 or header_at >= bytes.size():
		return _failure(&"audio_header_outside_record")
	var header: int = bytes[header_at]
	var channel_count: int = ((header >> 6) & 0x03) + 1
	if channel_count > 4:
		return _failure(&"audio_invalid_channel_count")
	var tracks: Array = []
	for _channel: int in channel_count:
		if header_at + 2 >= bytes.size():
			return _failure(&"audio_channel_header_truncated")
		var packed: int = bytes[header_at]
		var channel_id: int = (packed & 0x0F) + 1
		var address: int = _audio_address(_u16(bytes, header_at + 1))
		var stream_at: int = address - origin
		if stream_at < 0 or stream_at >= bytes.size():
			return _failure(&"audio_channel_pointer_outside_record")
		var track_result: Dictionary = _decode_track(
			bytes, stream_at, channel_id, &"cry", origin, {}
		)
		if not bool(track_result.get("ok", false)):
			return track_result
		tracks.append(track_result["track"])
		header_at += 3

	var duration: int = 0
	for track: Dictionary in tracks:
		duration = maxi(duration, int(track.get("end_frame", 0)))
	return {
		"ok": true,
		"kind": &"cry",
		"format": &"cry_stream",
		"tracks": tracks,
		"duration_frames": duration,
		"looped": false,
		"warnings": [],
	}


static func _decode_track(
	bytes: PackedByteArray, start: int, channel_id: int, request_kind: StringName,
	origin: int, assets: Dictionary
) -> Dictionary:
	var state: Dictionary = {
		"at": start,
		"time": 0,
		"duration_modifier": 0,
		"tempo": 0x100,
		"note_length": 1,
		"octave": 0,
		"transpose": 0,
		"volume_envelope": 0xF0,
		"duty": 0,
		"duty_pattern": [],
		"noise": false,
		"sfx": request_kind == &"sound",
		"drumkit": 0,
		"condition": 0,
		"loop_states": {},
		"calls": [],
		"steps": 0,
		"origin": origin,
	}
	var events: Array = []
	var warnings: Array[StringName] = []
	var hardware_channel: int = ((channel_id - 1) % 4) + 1
	var looped: bool = false
	while int(state["steps"]) < MAX_STEPS and events.size() < MAX_EVENTS:
		state["steps"] = int(state["steps"]) + 1
		var at: int = int(state["at"])
		if at < 0 or at >= bytes.size():
			return _failure(&"audio_stream_pointer_outside_record", {
				"offset": at, "address": int(state.get("origin", 0)) + at,
				"last_offset": int(state.get("last_at", -1)),
				"last_opcode": int(state.get("last_opcode", -1)),
			})
		var value: int = bytes[at]
		state["last_at"] = at
		state["last_opcode"] = value
		state["at"] = at + 1
		if value < FIRST_MUSIC_COMMAND:
			if request_kind == &"cry" or bool(state.get("sfx", false)):
				var fixed_result: Dictionary = _decode_fixed_note(
					bytes, state, value, channel_id, hardware_channel
				)
				if not bool(fixed_result.get("ok", false)):
					return fixed_result
				if fixed_result.has("event"):
					events.append(fixed_result["event"])
				state["at"] = int(fixed_result["at"])
				state["time"] = int(fixed_result["time"])
				if int(state["time"]) >= MAX_FRAMES:
					looped = true
					break
				continue
			var pitch: int = value >> 4
			var duration_code: int = value & 0x0F
			var duration: int = _set_note_duration(state, duration_code)
			var event: Dictionary = {
				"start_frame": int(state["time"]),
				"duration_frames": duration,
				"channel": channel_id,
				"hardware_channel": hardware_channel,
				"pitch": pitch,
				"volume": (int(state["volume_envelope"]) >> 4) & 0x0F,
				"envelope": int(state["volume_envelope"]),
				"duty": _duty_for_event(state),
				"wave_index": int(state["volume_envelope"]) & 0x0F,
				"frequency": 0,
				"noise": hardware_channel == 4,
			}
			if pitch > 0:
				state["last_pitch"] = pitch
				if hardware_channel == 4 and bool(state["noise"]):
					event["noise_samples"] = _drum_sample(
						assets, int(state["drumkit"]), pitch
					)
				else:
					event["frequency"] = _frequency(
						int(state["octave"]), pitch, int(state["transpose"])
					)
				events.append(event)
			elif duration > 0:
				events.append(event)
			state["time"] = mini(MAX_FRAMES, int(state["time"]) + duration)
			if int(state["time"]) >= MAX_FRAMES:
				looped = true
				break
			continue

		if value == SOUND_RETURN:
			var calls: Array = state["calls"]
			if not calls.is_empty():
				state["at"] = int(calls.pop_back())
				continue
			break

		var command_result: Dictionary = _command(
			bytes, state, value, channel_id, hardware_channel
		)
		if not bool(command_result.get("ok", false)):
			return command_result
		if bool(command_result.get("looped", false)):
			looped = true
		for warning: StringName in command_result.get("warnings", []):
			if not warnings.has(warning):
				warnings.append(warning)
		if bool(command_result.get("end", false)):
			break
		if int(state["time"]) >= MAX_FRAMES:
			looped = true
			break

	if int(state["steps"]) >= MAX_STEPS or events.size() >= MAX_EVENTS:
		warnings.append(&"audio_stream_step_limit")
	return {
		"ok": true,
		"track": {
			"channel": channel_id,
			"hardware_channel": hardware_channel,
			"events": events,
			"end_frame": int(state["time"]),
			"looped": looped,
		},
		"warnings": warnings,
	}


static func _decode_fixed_note(
	bytes: PackedByteArray, state: Dictionary, length: int, channel_id: int,
	hardware_channel: int
) -> Dictionary:
	var at: int = int(state["at"])
	var bytes_after_length: int = 2 if hardware_channel == 4 else 3
	if not _has(bytes, at, bytes_after_length):
		return _failure(&"audio_cry_note_truncated", {
			"offset": at,
			"channel": channel_id,
		})
	var envelope: int = bytes[at]
	var frequency: int = bytes[at + 1]
	if hardware_channel != 4:
		frequency |= bytes[at + 2] << 8
	at += bytes_after_length
	var duration: int = _set_note_duration(state, length)
	var event: Dictionary = {
		"start_frame": int(state["time"]),
		"duration_frames": duration,
		"channel": channel_id,
		"hardware_channel": hardware_channel,
		"pitch": 1 if frequency != 0 else 0,
		"volume": (envelope >> 4) & 0x0F,
		"envelope": envelope,
		"duty": _duty_for_event(state),
		"wave_index": envelope & 0x0F,
		"frequency": frequency,
		"noise": hardware_channel == 4,
	}
	return {
		"ok": true,
		"at": at,
		"time": mini(MAX_FRAMES, int(state["time"]) + duration),
		"event": event,
	}


static func _command(
	bytes: PackedByteArray, state: Dictionary, opcode: int, channel_id: int, hardware_channel: int
) -> Dictionary:
	var at: int = int(state["at"])
	var args: int = 0
	var warnings: Array[StringName] = []
	match opcode:
		0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7:
			state["octave"] = opcode & 0x07
		0xD8:
			if not _has(bytes, at, 1):
				return _failure(&"audio_note_type_truncated")
			state["note_length"] = bytes[at]
			at += 1
			if hardware_channel != 4:
				if not _has(bytes, at, 1):
					return _failure(&"audio_note_type_envelope_truncated")
				state["volume_envelope"] = bytes[at]
				at += 1
		0xD9:
			if not _has(bytes, at, 1):
				return _failure(&"audio_transpose_truncated")
			state["transpose"] = bytes[at]
			at += 1
		0xDA:
			if not _has(bytes, at, 2):
				return _failure(&"audio_tempo_truncated")
			state["tempo"] = _u16(bytes, at)
			at += 2
		0xDB:
			if not _has(bytes, at, 1):
				return _failure(&"audio_duty_truncated")
			state["duty"] = (bytes[at] & 0x03)
			at += 1
		0xDC:
			if not _has(bytes, at, 1):
				return _failure(&"audio_envelope_truncated")
			state["volume_envelope"] = bytes[at]
			at += 1
		0xDD:
			args = 1
		0xDE:
			if not _has(bytes, at, 1):
				return _failure(&"audio_duty_pattern_truncated")
			var pattern: int = bytes[at]
			state["duty_pattern"] = [
				(pattern >> 6) & 0x03, (pattern >> 4) & 0x03,
				(pattern >> 2) & 0x03, pattern & 0x03,
			]
			state["duty"] = (pattern >> 6) & 0x03
			at += 1
		0xDF:
			state["sfx"] = not bool(state.get("sfx", false))
		0xE0:
			args = 2
		0xE1:
			args = 2
		0xE2:
			args = 1
		0xE3, 0xF0:
			state["noise"] = not bool(state["noise"])
			if bool(state["noise"]):
				if not _has(bytes, at, 1):
					return _failure(&"audio_drumkit_truncated")
				state["drumkit"] = bytes[at]
				at += 1
		0xE4, 0xEF:
			args = 1
		0xE5:
			if not _has(bytes, at, 1):
				return _failure(&"audio_volume_truncated")
			state["volume_envelope"] = bytes[at]
			at += 1
		0xE6:
			args = 2
		0xE7, 0xE8, 0xE9:
			args = 1
		0xEA:
			if not _has(bytes, at, 2):
				return _failure(&"audio_restart_truncated")
			var restart_header: int = _audio_address(_u16(bytes, at))
			at += 2
			var restart_stream: int = _header_stream_offset(bytes, restart_header, int(state.get("origin", 0)))
			if restart_stream >= 0:
				at = restart_stream
			else:
				return _failure(&"audio_restart_outside_record", {
					"header": restart_header,
					"origin": int(state.get("origin", 0)),
				})
		0xEB:
			args = 2
		0xEC, 0xED:
			pass
		0xEE:
			args = 2
		0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9:
			pass
		0xFA:
			if not _has(bytes, at, 1):
				return _failure(&"audio_condition_truncated")
			state["condition"] = bytes[at]
			at += 1
		0xFB:
			if not _has(bytes, at, 3):
				return _failure(&"audio_conditional_jump_truncated")
			var condition: int = bytes[at]
			var conditional_target: int = _audio_address(_u16(bytes, at + 1))
			at += 3
			if int(state["condition"]) == condition:
				at = conditional_target - int(state.get("origin", 0))
		0xFC:
			if not _has(bytes, at, 2):
				return _failure(&"audio_jump_truncated")
			at = _audio_address(_u16(bytes, at)) - int(state.get("origin", 0))
		0xFD:
			if not _has(bytes, at, 3):
				return _failure(&"audio_loop_truncated")
			var loop_at: int = at - 1
			var loop_count: int = bytes[at]
			var loop_target: int = _audio_address(_u16(bytes, at + 1))
			at += 3
			var loops: Dictionary = state["loop_states"]
			var key: String = str(loop_at)
			if not loops.has(key):
				loops[key] = loop_count - 1 if loop_count > 0 else -1
				at = loop_target - int(state.get("origin", 0))
				if loop_count == 0:
					state["at"] = at
					return {"ok": true, "looped": true, "warnings": warnings}
			else:
				var remaining: int = int(loops[key])
				if remaining < 0:
					at = loop_target - int(state.get("origin", 0))
					state["at"] = at
					return {"ok": true, "looped": true, "warnings": warnings}
				if remaining > 0:
					loops[key] = remaining - 1
					at = loop_target - int(state.get("origin", 0))
				else:
					loops.erase(key)
		0xFE:
			if not _has(bytes, at, 2):
				return _failure(&"audio_call_truncated")
			var call_target: int = _audio_address(_u16(bytes, at))
			at += 2
			var calls: Array = state["calls"]
			calls.append(at)
			at = call_target - int(state.get("origin", 0))
		0xFF:
			return {"ok": true, "end": true, "warnings": warnings}
		_:
			return _failure(&"audio_unknown_command")
	if args > 0:
		if not _has(bytes, at, args):
				return _failure(&"audio_command_truncated")
		at += args
	state["at"] = at
	return {"ok": true, "warnings": warnings}


static func _set_note_duration(state: Dictionary, duration_code: int) -> int:
	var units: int = duration_code + 1
	var low_product: int = (int(state["note_length"]) * units) & 0xFF
	var total: int = int(state["tempo"]) * low_product + int(state["duration_modifier"])
	var duration: int = total >> 8
	state["duration_modifier"] = total & 0xFF
	return maxi(duration, 1)


static func _frequency(octave: int, pitch: int, transpose: int) -> int:
	var transposed_octave: int = octave + ((transpose >> 4) & 0x0F)
	var table_index: int = pitch + (transpose & 0x0F)
	if table_index < 0 or table_index >= FREQUENCY_TABLE.size():
		return 0
	var frequency: int = FREQUENCY_TABLE[table_index]
	var shift: int = 7 - transposed_octave
	while shift > 0:
		frequency = frequency >> 1
		shift -= 1
	return frequency & 0x07FF


static func _duty_for_event(state: Dictionary) -> int:
	var pattern: Array = state.get("duty_pattern", [])
	if pattern.is_empty():
		return int(state.get("duty", 0))
	var event_number: int = int(state.get("event_number", 0))
	state["event_number"] = event_number + 1
	return int(pattern[event_number % pattern.size()])


static func _drum_sample(assets: Dictionary, kit: int, instrument: int) -> Array:
	var asset: Dictionary = assets.get("drumkits", {})
	var bytes: PackedByteArray = _bytes(asset.get("bytes", []))
	if bytes.is_empty() or kit < 0 or kit >= 6 or instrument < 1 or instrument > 12:
		return []
	var base_address: int = int(asset.get("address", 0x4E52))
	var kit_address: int = _u16(bytes, kit * 2)
	var sample_pointer_at: int = kit_address - base_address + instrument * 2
	if sample_pointer_at < 0 or sample_pointer_at + 1 >= bytes.size():
		return []
	var sample_address: int = _u16(bytes, sample_pointer_at)
	var at: int = sample_address - base_address
	var samples: Array = []
	for _step: int in 64:
		if at < 0 or at >= bytes.size():
			return samples
		var length: int = bytes[at]
		at += 1
		if length == SOUND_RETURN:
			break
		if at + 2 >= bytes.size():
			return samples
		samples.append({
			"duration_frames": (length & 0x0F) + 1,
			"envelope": bytes[at],
			"frequency": bytes[at + 1],
		})
		at += 2
	return samples


static func _header_stream_offset(bytes: PackedByteArray, header_address: int, origin: int) -> int:
	header_address = _audio_address(header_address)
	var header_at: int = header_address - origin
	if header_at < 0 or header_at + 2 >= bytes.size():
		return -1
	return _audio_address(_u16(bytes, header_at + 1)) - origin


static func _audio_address(raw_address: int) -> int:
	return 0x4000 | (raw_address & 0x3FFF)


static func _bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	if not value is Array:
		return PackedByteArray()
	var raw: Array = value as Array
	var out := PackedByteArray()
	out.resize(raw.size())
	for index: int in out.size():
		out[index] = int(raw[index]) & 0xFF
	return out


static func _u16(bytes: PackedByteArray, at: int) -> int:
	return bytes[at] | (bytes[at + 1] << 8)


static func _has(bytes: PackedByteArray, at: int, count: int) -> bool:
	return at >= 0 and count >= 0 and at + count <= bytes.size()


static func _failure(reason: StringName, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "reason": reason, "format": &"gen2_audio", "details": details}
