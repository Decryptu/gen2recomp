class_name Gen2AudioPlayer
extends Node

## Runtime owner for the generated streams. Music has its own player so an SFX
## or cry cannot cut it off; repeated requests replace the current music stream
## but short effects continue through the shared effect player.

const AUDIO_HOST := preload("res://game/world/world_audio_host.gd")

## How many rendered music streams are kept. A track is a whole decoded
## [AudioStreamWAV], which is a megabyte or so; Crystal has a hundred of them,
## and keeping every one a player walked past is a phone's worth of memory spent
## on songs nobody is going to hear again soon. Least recently played goes first.
const MUSIC_CACHE_LIMIT: int = 4

var _music_player: AudioStreamPlayer = null
var _effect_player: AudioStreamPlayer = null
var _music_key: String = ""
var _music_cache: Dictionary = {}
var _fade_tween: Tween = null


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_effect_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_effect_player.name = "EffectPlayer"
	add_child(_music_player)
	add_child(_effect_player)


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
	# The music that is already playing is not started again. Two connected maps
	# with the same header music are one continuous track on the cartridge, and
	# restarting it at every map edge is audible.
	#
	# The comparison is against the last track started rather than against
	# whether a channel is still sounding, which is what the cartridge compares:
	# it keeps the current music id and skips when the new map asks for the same
	# one. Stopping or fading clears the id, so those still start it again.
	var key: String = "%d:%d" % [int(record.get("bank", -1)), int(record.get("address", -1))]
	if music and not restart and key == _music_key:
		return {"ok": true, "played": false, "continued": true}
	var prepared: Dictionary = _music_cache.get(key, {}) if music else {}
	if prepared.is_empty():
		prepared = AUDIO_HOST.play(record, request_kind, assets)
		if bool(prepared.get("ok", false)) and music:
			_cache_music(key, prepared)
	if not bool(prepared.get("ok", false)):
		return prepared
	var stream: AudioStream = prepared.get("stream", null) as AudioStream
	if stream == null:
		return {"ok": false, "played": false, "reason": &"audio_stream_unavailable"}
	if music:
		_stop_fade()
		_music_player.stream = stream
		_music_player.volume_db = 0.0
		_music_player.play()
		_music_key = key
		_touch_music(key)
	else:
		_effect_player.stream = stream
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


func effect_playing() -> bool:
	return _effect_player != null and _effect_player.playing


## How many rendered music streams are being kept, for a test or a memory check.
func cached_music_count() -> int:
	return _music_cache.size()


func _exit_tree() -> void:
	stop_all()


func _is_music(request_kind: StringName) -> bool:
	return request_kind in [&"music", &"map_music", &"encounter_music"]


## Keeps a rendered track, dropping the least recently played once the cache is
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
