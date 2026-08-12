class_name Gen2AudioPlayer
extends Node

## Owns one generator and one four-channel hardware timeline. Music, SFX and
## cries are decoded into source events and rendered through the same channel
## phase, noise and analog filter state.

const AUDIO_DECODER := preload("res://game/audio/gen2_audio_decoder.gd")
const AUDIO_RENDERER := preload("res://game/audio/gen2_audio_renderer.gd")

const MUSIC_CACHE_LIMIT: int = 4
## Keep each refill below the generator's 0.25 second capacity. Sixteen source
## frames requested 5,880 output frames against a 5,512-frame buffer, so the
## refill loop never ran and live audio starved from startup.
const MUSIC_CHUNK_FRAMES: int = 4

var _music_player: AudioStreamPlayer = null
var _music_key: String = ""
var _music_cache: Dictionary = {}
var _fade_tween: Tween = null
var _music_generator: AudioStreamGenerator = null
var _music_playback: AudioStreamGeneratorPlayback = null
var _music_decoded: Dictionary = {}
var _music_assets: Dictionary = {}
var _music_source_frame: int = 0
var _music_render_state: Dictionary = {}
var _music_draining: bool = false


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)
	set_process(true)


func _process(_delta: float) -> void:
	_service_timeline()


## Plays one imported audio record. Music continues when the source asks for the
## same track again; effects claim only the hardware channels in their header.
func play_record(
	record: Dictionary,
	request_kind: StringName,
	assets: Dictionary = {},
	restart: bool = false,
) -> Dictionary:
	if request_kind == &"music_fadeout":
		return {"ok": true, "played": fade_out(int(record.get("fade_time", 0)))}
	var music: bool = _is_music(request_kind)
	var key: String = "%d:%d" % [int(record.get("bank", -1)), int(record.get("address", -1))]
	if music and not restart and key == _music_key:
		return {"ok": true, "played": false, "continued": true}
	if music:
		var prepared: Dictionary = _music_cache.get(key, {})
		if prepared.is_empty():
			var decoded: Dictionary = AUDIO_DECODER.decode(record, request_kind, assets)
			if not bool(decoded.get("ok", false)):
				return {"ok": false, "played": false, "reason": decoded.get("reason", &"audio_decode_failed")}
			prepared = {
				"ok": true,
				"ready": true,
				"decoded": decoded,
				"frame_count": int(decoded.get("duration_frames", 0)),
			}
			_cache_music(key, prepared)
		_stop_fade()
		_start_music_generator(prepared, assets)
		_music_key = key
		_touch_music(key)
		prepared["played"] = true
		return prepared

	var effect_decoded: Dictionary = AUDIO_DECODER.decode(record, request_kind, assets)
	if not bool(effect_decoded.get("ok", false)):
		return {"ok": false, "played": false, "reason": effect_decoded.get("reason", &"audio_decode_failed")}
	_ensure_generator(assets)
	var priority: bool = request_kind == &"cry" or _has_sfx_priority(effect_decoded)
	var started: Dictionary = AUDIO_RENDERER.start_effect(
		_music_render_state, effect_decoded, assets, priority
	)
	if not bool(started.get("ok", false)):
		return started
	return {
		"ok": true,
		"played": true,
		"ready": true,
		"backend": &"shared_hardware_generator",
		"request_kind": request_kind,
		"decoded": effect_decoded,
		"frame_count": int(effect_decoded.get("duration_frames", 0)),
		"sfx_priority": priority,
		"effect_id": int(started.get("effect_id", -1)),
		"claimed_channels": started.get("claimed_channels", []),
	}


func fade_out(frames: int = 0) -> bool:
	if _music_player == null or not _music_player.playing:
		return false
	_stop_fade()
	var seconds: float = maxf(0.01, float(frames) / AUDIO_RENDERER.SOURCE_FRAME_RATE)
	if frames <= 0:
		_music_player.stop()
		_music_player.volume_db = 0.0
		_music_key = ""
		_music_decoded = {}
		_music_render_state = {}
		_music_draining = false
		return true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_music_player, "volume_db", -80.0, seconds)
	_fade_tween.tween_callback(_finish_fade)
	return true


func stop_all() -> void:
	_stop_fade()
	if _music_player != null:
		_music_player.stop()
	_music_key = ""
	_music_decoded = {}
	_music_playback = null
	_music_generator = null
	_music_render_state = {}
	_music_draining = false


func effect_playing() -> bool:
	return not _music_render_state.is_empty() and AUDIO_RENDERER.shared_effect_playing(_music_render_state)


func audio_status() -> Dictionary:
	if _music_render_state.is_empty():
		return {"active_effect_ids": [], "stolen_channels": 0, "restored_channels": 0}
	return AUDIO_RENDERER.shared_status(_music_render_state)


func cached_music_count() -> int:
	return _music_cache.size()


func _exit_tree() -> void:
	stop_all()


func _is_music(request_kind: StringName) -> bool:
	return request_kind in [&"music", &"map_music", &"encounter_music"]


func _has_sfx_priority(decoded: Dictionary) -> bool:
	for track: Dictionary in decoded.get("tracks", []):
		for event: Dictionary in track.get("events", []):
			if bool(event.get("sfx_priority", false)):
				return true
	return false


func _cache_music(key: String, prepared: Dictionary) -> void:
	_music_cache[key] = prepared
	while _music_cache.size() > MUSIC_CACHE_LIMIT:
		var oldest: Variant = _music_cache.keys()[0]
		if String(oldest) == _music_key:
			if _music_cache.size() <= 1:
				break
			oldest = _music_cache.keys()[1]
		_music_cache.erase(oldest)


func _touch_music(key: String) -> void:
	if not _music_cache.has(key):
		return
	var prepared: Dictionary = _music_cache[key]
	_music_cache.erase(key)
	_music_cache[key] = prepared


func _stop_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _finish_fade() -> void:
	if _music_player != null:
		_music_player.stop()
		_music_player.volume_db = 0.0
	_music_key = ""
	_music_decoded = {}
	_music_playback = null
	_music_generator = null
	_music_render_state = {}
	_music_draining = false
	_fade_tween = null


func _start_music_generator(prepared: Dictionary, assets: Dictionary) -> void:
	if _music_player != null:
		_music_player.stop()
	_music_generator = AudioStreamGenerator.new()
	_music_generator.mix_rate = AUDIO_RENDERER.SAMPLE_RATE
	_music_generator.buffer_length = 0.25
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MusicPlayer"
		add_child(_music_player)
	_music_player.stream = _music_generator
	_music_player.volume_db = 0.0
	_music_decoded = prepared.get("decoded", {}).duplicate(true)
	_music_assets = assets.duplicate(true)
	_music_source_frame = 0
	_music_render_state = AUDIO_RENDERER.create_shared_state(_music_decoded, _music_assets)
	_music_draining = false
	_music_player.play()
	_music_playback = _music_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _ensure_generator(assets: Dictionary) -> void:
	if not _music_render_state.is_empty() and _music_playback != null:
		return
	_start_music_generator({
		"decoded": {"ok": true, "tracks": [], "duration_frames": 0, "looped": false},
	}, assets)


func _service_timeline() -> void:
	if _music_player == null or _music_render_state.is_empty() or not _music_player.playing:
		return
	if _music_playback == null:
		_music_playback = _music_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _music_playback == null:
			return
	var chunk_samples: int = ceili(
		float(MUSIC_CHUNK_FRAMES) * AUDIO_RENDERER.SAMPLE_RATE
		/ AUDIO_RENDERER.SOURCE_FRAME_RATE
	)
	var buffer_capacity: int = ceili(
		float(_music_generator.mix_rate) * _music_generator.buffer_length
	)
	if _music_draining and not AUDIO_RENDERER.shared_effect_playing(_music_render_state):
		if _music_playback.get_frames_available() >= maxi(0, buffer_capacity - 1):
			_music_player.stop()
			_music_key = ""
			_music_playback = null
			_music_render_state = {}
			_music_draining = false
		return
	while _music_playback.get_frames_available() >= chunk_samples:
		var frames: int = MUSIC_CHUNK_FRAMES
		if not _music_decoded.is_empty():
			var duration: int = maxi(1, int(_music_decoded.get("duration_frames", 1)))
			if _music_source_frame >= duration:
				if bool(_music_decoded.get("looped", false)):
					_music_source_frame = maxi(0, int(_music_decoded.get("loop_start_frame", 0)))
					AUDIO_RENDERER.restart_shared_music(_music_render_state, _music_source_frame)
				else:
					_music_decoded = {}
					_music_render_state["music_tracks"] = []
					_music_draining = true
					break
			frames = mini(MUSIC_CHUNK_FRAMES, duration - _music_source_frame)
		var chunk: Dictionary = AUDIO_RENDERER.render_shared_chunk_stateful(
			_music_render_state, frames, _music_assets
		)
		if not bool(chunk.get("ok", false)):
			push_error("Shared audio render failed: %s" % chunk.get("reason", "unknown"))
			_music_player.stop()
			_music_playback = null
			return
		_music_playback.push_buffer(chunk["buffer"])
		if not _music_decoded.is_empty():
			_music_source_frame += frames
		elif not AUDIO_RENDERER.shared_effect_playing(_music_render_state):
			_music_draining = true
