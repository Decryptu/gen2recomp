class_name Gen2WorldAudioHost
extends RefCounted

## Scene-free inspection boundary for imported audio records.
##
## Runtime playback belongs exclusively to [Gen2AudioPlayer]. This host proves a
## record resolves and that the driver can run it, by starting it on a private
## engine and stepping a second of frames. It renders no samples, so it can
## never become a second synthesiser that diverges from the shared lane.

const BACKEND_PROBE: StringName = &"driver_probe_shared_runtime"
## A second of `_UpdateSound`, enough to walk past a stream's opening commands.
const PROBE_FRAMES: int = 60


static func play(
	record: Dictionary, request_kind: StringName, assets: Dictionary = {}
) -> Dictionary:
	if record.is_empty():
		return {"ok": false, "reason": &"audio_data_unavailable"}
	var payload: Variant = record.get("bytes", [])
	var byte_count: int = int(record.get("byte_count", payload.size() if payload is Array else 0))
	var engine := Gen2SoundEngine.new()
	engine.set_assets(assets)
	engine.init_sound()
	var started: bool = false
	match request_kind:
		&"cry", &"cries", &"mon_cry":
			started = engine.play_cry(record)
		&"sound", &"sfx":
			started = engine.play_sfx(record)
		_:
			started = engine.play_music(record)
	if not started:
		return {
			"ok": false,
			"played": false,
			"backend": BACKEND_PROBE,
			"reason": &"audio_record_unplayable",
			"byte_count": byte_count,
		}
	var frames: int = 0
	while frames < PROBE_FRAMES and engine.any_channel_active():
		engine.update_sound()
		frames += 1
	return {
		"ok": true,
		"played": false,
		"ready": true,
		"backend": BACKEND_PROBE,
		"request_kind": request_kind,
		"index": int(record.get("index", -1)),
		"bank": int(record.get("bank", -1)),
		"address": int(record.get("address", -1)),
		"byte_count": byte_count,
		"frames": frames,
		"still_playing": engine.any_channel_active(),
		"sfx_priority": engine.sfx_priority != 0,
	}
