class_name Gen2AudioDecoder
extends RefCounted

## Bounded decoder for the Gen II music, SFX and cry streams.
##
## The importer keeps the original bank/address and a bounded byte window per
## record. This follows the cartridge's command table: little-endian stream
## pointers, note-duration accumulation, subroutine returns, counted and infinite
## loops. It returns events rather than touching an audio device, so the format
## stays testable headless and the playback layer picks its own output rate.

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
	# Every channel of a looping stream jumps back at the same musical point,
	# but a channel that rests through the intro reaches it first, so the
	# earliest is the one the whole stream repeats from.
	var loop_start: int = -1
	for track: Dictionary in tracks:
		duration = maxi(duration, int(track.get("end_frame", 0)))
		looped = looped or bool(track.get("looped", false))
		var track_loop: int = int(track.get("loop_start_frame", -1))
		if track_loop >= 0 and (loop_start < 0 or track_loop < loop_start):
			loop_start = track_loop
	return {
		"ok": true,
		"kind": request_kind,
		"format": &"music_stream",
		"tracks": tracks,
		"duration_frames": duration,
		"looped": looped,
		"loop_start_frame": loop_start,
		"warnings": warnings,
	}


## `_PlayCry`'s two parameters, which `PlayCry` reads out of `PokemonCries`
## before it. Without them a cry is the raw stream, and most species share a
## stream: Ivysaur and Venusaur are both CRY_BULBASAUR.
##
## `wCryPitch` is `CHANNEL_PITCH_OFFSET`, added to the note frequency once per
## note; `wCryLength` is `CHANNEL_TEMPO`, which `SetNoteDuration` multiplies by.
## Both are read off the record, so a caller that supplies neither still gets
## the stream at its own speed.
static func _decode_cry(record: Dictionary, bytes: PackedByteArray) -> Dictionary:
	var pitch: int = int(record.get("cry_pitch", 0))
	var length: int = int(record.get("cry_length", 0))
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
			bytes, stream_at, channel_id, &"cry", origin, {},
			{"cry_pitch": pitch, "cry_length": length}
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
	origin: int, assets: Dictionary, cry: Dictionary = {}
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
		# `_InitSound` writes MAX_VOLUME ($77) to wVolume, and `GetLRTracks`
		# leaves both outputs on until a `stereo_panning` narrows them.
		"master_left": 7,
		"master_right": 7,
		"pan_left": 1,
		"pan_right": 1,
		"frame_at_offset": {},
		"loop_states": {},
		"calls": [],
		"steps": 0,
		"origin": origin,
	}
	var events: Array = []
	var warnings: Array[StringName] = []
	var hardware_channel: int = ((channel_id - 1) % 4) + 1
	# `_PlayCry` writes `wCryLength` into `CHANNEL_TEMPO` for every channel below
	# CHAN4 and skips the noise channel outright, so its notes keep the neutral
	# tempo above.
	if hardware_channel != 4 and int(cry.get("cry_length", 0)) > 0:
		state["tempo"] = int(cry["cry_length"]) & 0xFFFF
	state["pitch_offset"] = int(cry.get("cry_pitch", 0)) & 0xFFFF
	var looped: bool = false
	# Reaching MAX_FRAMES means the render budget ran out, which is not the
	# same thing as the stream looping. Conflating the two marked every SFX
	# as looping, and a looping stream never lets `waitsfx` finish.
	var truncated: bool = false
	var loop_start_frame: int = -1
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
		# Where a backward jump lands is the stream's loop point, and the frame
		# it loops back to is the frame that offset was first executed at.
		var seen: Dictionary = state["frame_at_offset"]
		if not seen.has(at):
			seen[at] = int(state["time"])
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
					truncated = true
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
				# `Music_Volume` and the two panning commands are mixer state, not
				# note state, so each event carries what was in force when it began.
				"master_left": int(state["master_left"]),
				"master_right": int(state["master_right"]),
				"pan_left": int(state["pan_left"]),
				"pan_right": int(state["pan_right"]),
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
				truncated = true
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
			var landed: int = int(command_result.get("loop_offset", -1))
			var seen_frames: Dictionary = state["frame_at_offset"]
			if seen_frames.has(landed):
				loop_start_frame = int(seen_frames[landed])
			# One pass is the whole stream: going round again only replays what
			# the events already carry, and used to run until MAX_FRAMES.
			break
		for warning: StringName in command_result.get("warnings", []):
			if not warnings.has(warning):
				warnings.append(warning)
		if bool(command_result.get("end", false)):
			break
		if int(state["time"]) >= MAX_FRAMES:
			truncated = true
			break

	if int(state["steps"]) >= MAX_STEPS or events.size() >= MAX_EVENTS:
		warnings.append(&"audio_stream_step_limit")
	if truncated:
		warnings.append(&"audio_stream_frame_limit")
	return {
		"ok": true,
		"track": {
			"channel": channel_id,
			"hardware_channel": hardware_channel,
			"events": events,
			"end_frame": int(state["time"]),
			"looped": looped,
			"loop_start_frame": loop_start_frame,
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
		# `HandleTrackVibrato`'s `SOUND_PITCH_OFFSET` branch adds the offset to
		# `wCurTrackFrequency`, which is a per-update copy, so it lands on the
		# note once rather than compounding. `rAUDxHIGH` keeps three frequency
		# bits, so a sum past $7ff wraps rather than clipping: Bulbasaur's own
		# 128 takes its first two notes over and they come out low.
		if frequency != 0:
			frequency = (frequency + int(state.get("pitch_offset", 0))) & 0x7FF
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
		# `Music_Volume` and the two panning commands are mixer state, not
		# note state, so each event carries what was in force when it began.
		"master_left": int(state["master_left"]),
		"master_right": int(state["master_right"]),
		"pan_left": int(state["pan_left"]),
		"pan_right": int(state["pan_right"]),
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
			# `Music_Tempo` takes the high byte first (`ld d, a` then `ld e, a`),
			# which is what the `bigdw` in the macro means. Read little-endian,
			# `tempo 144` decodes as $9000 and every note lasts 256 times too
			# long, which is what drove whole streams past MAX_FRAMES.
			state["tempo"] = _u16_be(bytes, at)
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
			if not _has(bytes, at, 1):
				return _failure(&"audio_panning_truncated")
			# `Music_StereoPanning` and `Music_ForceStereoPanning` both AND the
			# byte into CHANNEL_TRACKS, whose two nibbles enable the left and
			# right output. Stereo is an option on the cartridge; this follows
			# the forced branch, which is what the option being on means.
			state["pan_left"] = 1 if (bytes[at] & 0xF0) != 0 else 0
			state["pan_right"] = 1 if (bytes[at] & 0x0F) != 0 else 0
			at += 1
		0xE5:
			if not _has(bytes, at, 1):
				return _failure(&"audio_volume_truncated")
			# `Music_Volume` writes wVolume, the master left/right level
			# behind NR50, and never touches CHANNEL_VOLUME_ENVELOPE. Writing
			# it into the envelope clobbered every channel's volume, since
			# nearly every song opens on `volume 7, 7`.
			state["master_left"] = (bytes[at] >> 4) & 0x07
			state["master_right"] = bytes[at] & 0x07
			at += 1
		0xE6:
			if not _has(bytes, at, 2):
				return _failure(&"audio_pitch_offset_truncated")
			# `Music_PitchOffset` stores the high byte first, so the macro is
			# `bigdw` the way `tempo` is.
			state["pitch_offset"] = _u16_be(bytes, at)
			at += 2
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
			var jump_from: int = at - 1
			at = _audio_address(_u16(bytes, at)) - int(state.get("origin", 0))
			# A jump landing at or before the command itself never comes back,
			# which is how a stream with no `sound_loop 0` still loops forever.
			if at <= jump_from:
				state["at"] = at
				return {
					"ok": true, "looped": true, "loop_offset": at, "warnings": warnings,
				}
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
					return {
						"ok": true, "looped": true, "loop_offset": at, "warnings": warnings,
					}
			else:
				var remaining: int = int(loops[key])
				if remaining < 0:
					at = loop_target - int(state.get("origin", 0))
					state["at"] = at
					return {
						"ok": true, "looped": true, "loop_offset": at, "warnings": warnings,
					}
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
	# `sra d` / `rr e`, not `srl`: every table entry has bit 15 set, so the
	# sign propagates into the eleven bits `and $7` keeps. A logical shift
	# put octave 7 and 8 out by more than an octave; C_ at octave 8 came out
	# at register $1f0 against the hardware's $7f0.
	while shift > 0:
		frequency = (frequency >> 1) | (frequency & 0x8000)
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


## The order `tempo` and `pitch_offset` are written in: high byte first, which
## is what `bigdw` means in the macros. Every other two-byte operand is a
## stream pointer and little-endian.
static func _u16_be(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 8) | bytes[at + 1]


static func _has(bytes: PackedByteArray, at: int, count: int) -> bool:
	return at >= 0 and count >= 0 and at + count <= bytes.size()


static func _failure(reason: StringName, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "reason": reason, "format": &"gen2_audio", "details": details}
