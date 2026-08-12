class_name Gen2WorldAudioHost
extends RefCounted

## Scene-free inspection boundary for imported audio records.
##
## Runtime playback belongs exclusively to Gen2AudioPlayer. This host is used by
## the service overlay to prove that a record resolves and decodes; it must not
## create a second WAV renderer that can diverge from the shared hardware lane.

const BACKEND_DECODE_ONLY: StringName = &"decode_only_shared_runtime"


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
			"backend": BACKEND_DECODE_ONLY,
			"reason": decoded.get("reason", &"audio_decode_failed"),
			"byte_count": byte_count,
		}
	return {
		"ok": true,
		"played": false,
		"ready": true,
		"backend": BACKEND_DECODE_ONLY,
		"request_kind": request_kind,
		"index": int(record.get("index", -1)),
		"bank": int(record.get("bank", -1)),
		"address": int(record.get("address", -1)),
		"byte_count": byte_count,
		"decoded": decoded,
		"sfx_priority": _has_sfx_priority(decoded),
		"frame_count": int(decoded.get("duration_frames", 0)),
	}


static func _has_sfx_priority(decoded: Dictionary) -> bool:
	for track: Dictionary in decoded.get("tracks", []):
		for event: Dictionary in track.get("events", []):
			if bool(event.get("sfx_priority", false)):
				return true
	return false
