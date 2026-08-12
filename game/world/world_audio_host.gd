class_name Gen2WorldAudioHost
extends RefCounted

## Scene-free boundary between imported audio records and the Godot playback
## node. Decoding/rendering stays pure here, while an owning scene decides when
## to attach the returned stream to an AudioStreamPlayer.

const BACKEND_WAV: StringName = &"godot_audio_stream_wav"


static func play(
	record: Dictionary, request_kind: StringName, assets: Dictionary = {}
) -> Dictionary:
	if record.is_empty():
		return {"ok": false, "reason": &"audio_data_unavailable"}
	var payload: Variant = record.get("bytes", [])
	var byte_count: int = int(record.get("byte_count", payload.size() if payload is Array else 0))
	var decoded: Dictionary = Gen2AudioDecoder.decode(record, request_kind, assets)
	if not bool(decoded.get("ok", false)):
		return {
			"ok": false,
			"played": false,
			"backend": BACKEND_WAV,
			"reason": decoded.get("reason", &"audio_decode_failed"),
			"byte_count": byte_count,
		}
	var rendered: Dictionary = Gen2AudioRenderer.render(decoded, assets)
	if not bool(rendered.get("ok", false)):
		return {
			"ok": false,
			"played": false,
			"backend": BACKEND_WAV,
			"reason": rendered.get("reason", &"audio_render_failed"),
			"byte_count": byte_count,
		}
	return {
		"ok": true,
		"played": false,
		"ready": true,
		"backend": BACKEND_WAV,
		"request_kind": request_kind,
		"index": int(record.get("index", -1)),
		"bank": int(record.get("bank", -1)),
		"address": int(record.get("address", -1)),
		"byte_count": byte_count,
		"decoded": decoded,
		"sfx_priority": _has_sfx_priority(decoded),
		"stream": rendered["stream"],
		"frame_count": int(rendered.get("frame_count", 0)),
	}


static func _has_sfx_priority(decoded: Dictionary) -> bool:
	for track: Dictionary in decoded.get("tracks", []):
		for event: Dictionary in track.get("events", []):
			if bool(event.get("sfx_priority", false)):
				return true
	return false
