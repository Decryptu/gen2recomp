class_name Gen2WorldAudioHost
extends RefCounted

## The importer currently stores bounded raw music/SFX programs, not decoded
## channel notes. This host resolves and acknowledges those records while
## exposing the exact missing backend instead of inventing a waveform.

const BACKEND_PENDING: StringName = &"gb_audio_decoder_pending"


static func play(record: Dictionary, request_kind: StringName) -> Dictionary:
	if record.is_empty():
		return {"ok": false, "reason": &"audio_data_unavailable"}
	var payload: Variant = record.get("bytes", [])
	var byte_count: int = int(record.get("byte_count", payload.size() if payload is Array else 0))
	return {
		"ok": true,
		"played": false,
		"backend": BACKEND_PENDING,
		"request_kind": request_kind,
		"index": int(record.get("index", -1)),
		"bank": int(record.get("bank", -1)),
		"address": int(record.get("address", -1)),
		"byte_count": byte_count,
	}
