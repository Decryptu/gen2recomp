class_name Gen2AudioPlayer
extends Node

## Runtime owner for the generated streams. Music has its own player so an SFX
## or cry cannot cut it off; repeated requests replace the current music stream
## but short effects continue through the shared effect player.

const AUDIO_HOST := preload("res://game/world/world_audio_host.gd")
const AUDIO_DECODER := preload("res://game/audio/gen2_audio_decoder.gd")
const AUDIO_RENDERER := preload("res://game/audio/gen2_audio_renderer.gd")

## How many decoded music tracks are kept. Music is rendered into bounded
## generator chunks at playback time; effects and cries remain short WAV
## one-shots. Least recently played tracks are evicted first.
const MUSIC_CACHE_LIMIT: int = 4
const MUSIC_CHUNK_FRAMES: int = 16

var _music_player: AudioStreamPlayer = null
var _effect_player: AudioStreamPlayer = null
var _music_key: String = ""
var _music_cache: Dictionary = {}
var _fade_tween: Tween = null
var _music_generator: AudioStreamGenerator = null
var _music_playback: AudioStreamGeneratorPlayback = null
var _music_decoded: Dictionary = {}
var _music_assets: Dictionary = {}
var _music_source_frame: int = 0
var _music_render_state: Dictionary = {}
var _music_interrupted_by_sfx: bool = false


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_effect_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_effect_player.name = "EffectPlayer"
	add_child(_music_player)
	add_child(_effect_player)
	set_process(true)


func _process(_delta: float) -> void:
	_service_music()
	if _music_interrupted_by_sfx and not effect_playing():
		_music_interrupted_by_sfx = false
		if _music_player != null:
			_music_player.stream_paused = false


## Plays one imported audio record. [param restart] forces music that is already
## playing to start again, which only the source RestartMapMusic special wants.
func play_record(
	record: Dictionary,
	request_kind: StringName,
	assets: Dictionary = {},
	restart: bool = false,
) -> Dictionary:
	if request_kind == &"music_fadeout":
		return {"ok": true, "played": fade_out(int(record.get("fade_time", 0)))}
	var music: bool = _is_music(request_kind)
	# Music already playing is not restarted: two connected maps with the same
	# header music are one continuous track, and restarting at each map edge is
	# audible. The comparison is against the last track started, not against
	# whether a channel still sounds, which is what the cartridge compares.
	# Stopping or fading clears the id, so those do start it again.
	var key: String = "%d:%d" % [int(record.get("bank", -1)), int(record.get("address", -1))]
	if music and not restart and key == _music_key:
		return {"ok": true, "played": false, "continued": true}
	var prepared: Dictionary = _music_cache.get(key, {}) if music else {}
	if prepared.is_empty():
		if music:
			var decoded: Dictionary = AUDIO_DECODER.decode(record, request_kind, assets)
			if bool(decoded.get("ok", false)):
				prepared = {
					"ok": true,
					"ready": true,
					"decoded": decoded,
					"frame_count": int(decoded.get("duration_frames", 0)),
				}
			else:
				prepared = {"ok": false, "reason": decoded.get("reason", &"audio_decode_failed")}
		else:
			prepared = AUDIO_HOST.play(record, request_kind, assets)
		if bool(prepared.get("ok", false)) and music:
			_cache_music(key, prepared)
	if not bool(prepared.get("ok", false)):
		return prepared
	if music:
		_stop_fade()
		_start_music_generator(prepared, assets)
		_music_key = key
		_touch_music(key)
	else:
		var stream: AudioStream = prepared.get("stream", null) as AudioStream
		if stream == null:
			return {"ok": false, "played": false, "reason": &"audio_stream_unavailable"}
		_effect_player.stream = stream
		if bool(prepared.get("sfx_priority", false)) and _music_player.playing:
			_music_player.stream_paused = true
			_music_interrupted_by_sfx = true
		_effect_player.play()
	prepared["played"] = true
	return prepared


func fade_out(frames: int = 0) -> bool:
	if _music_player == null or not _music_player.playing:
		return false
	_stop_fade()
	var seconds: float = maxf(0.01, float(frames) / 60.0)
	if frames <= 0:
		_music_player.stop()
		_music_player.volume_db = 0.0
		_music_key = ""
		return true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_music_player, "volume_db", -80.0, seconds)
	_fade_tween.tween_callback(_finish_fade)
	return true


func stop_all() -> void:
	_stop_fade()
	if _music_player != null:
		_music_player.stop()
	if _effect_player != null:
		_effect_player.stop()
	_music_key = ""
	_music_decoded = {}
	_music_playback = null
	_music_generator = null
	_music_render_state = {}
	_music_interrupted_by_sfx = false


func effect_playing() -> bool:
	return _effect_player != null and _effect_player.playing


## How many decoded music tracks are being kept, for a test or memory check.
func cached_music_count() -> int:
	return _music_cache.size()


func _exit_tree() -> void:
	stop_all()


func _is_music(request_kind: StringName) -> bool:
	return request_kind in [&"music", &"map_music", &"encounter_music"]


## Keeps a decoded track, dropping the least recently played once the cache is
## over its limit. Dictionaries preserve insertion order, so the front key is the
## oldest and [method _touch_music] is what moves a track off it.
func _cache_music(key: String, prepared: Dictionary) -> void:
	_music_cache[key] = prepared
	while _music_cache.size() > MUSIC_CACHE_LIMIT:
		var oldest: Variant = _music_cache.keys()[0]
		if String(oldest) == _music_key:
			# Never evict what is playing: the stream would go on playing while
			# the next request re-rendered it.
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
	_fade_tween = null
	_music_decoded = {}
	_music_playback = null
	_music_generator = null
	_music_render_state = {}
	_music_interrupted_by_sfx = false


func _start_music_generator(prepared: Dictionary, assets: Dictionary) -> void:
	_music_player.stop()
	_music_generator = AudioStreamGenerator.new()
	_music_generator.mix_rate = AUDIO_RENDERER.SAMPLE_RATE
	_music_generator.buffer_length = 0.25
	_music_player.stream = _music_generator
	_music_player.volume_db = 0.0
	_music_decoded = prepared.get("decoded", {}).duplicate(true)
	_music_assets = assets.duplicate(true)
	_music_source_frame = 0
	_music_render_state = AUDIO_RENDERER.create_state(_music_decoded, _music_assets)
	_music_player.play()
	_music_playback = _music_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _service_music() -> void:
	if _music_playback == null or _music_decoded.is_empty() or not _music_player.playing:
		return
	var chunk_samples: int = MUSIC_CHUNK_FRAMES * AUDIO_RENDERER.SAMPLE_RATE / 60
	while _music_playback.get_frames_available() >= chunk_samples:
		var duration: int = maxi(1, int(_music_decoded.get("duration_frames", 1)))
		if _music_source_frame >= duration:
			if bool(_music_decoded.get("looped", false)):
				_music_source_frame = maxi(0, int(_music_decoded.get("loop_start_frame", 0)))
				_music_render_state = AUDIO_RENDERER.create_state(
					_music_decoded, _music_assets
				)
				AUDIO_RENDERER.prime_state(
					_music_decoded, _music_render_state, _music_source_frame, _music_assets
				)
			else:
				_music_player.stop()
				_music_key = ""
				_music_playback = null
				_music_decoded = {}
				return
		var frames: int = mini(MUSIC_CHUNK_FRAMES, duration - _music_source_frame)
		var chunk: Dictionary = AUDIO_RENDERER.render_chunk_stateful(
			_music_decoded, _music_render_state, frames, _music_assets
		)
		if not bool(chunk.get("ok", false)):
			push_error("Music chunk render failed: %s" % chunk.get("reason", "unknown"))
			_music_player.stop()
			_music_playback = null
			_music_decoded = {}
			return
		_music_playback.push_buffer(chunk["buffer"])
		_music_source_frame += frames
