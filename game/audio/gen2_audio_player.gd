class_name Gen2AudioPlayer
extends Node

## Runtime owner for the generated streams. Music has its own player so an SFX
## or cry cannot cut it off; repeated requests replace the current music stream
## but short effects continue through the shared effect player.

const AUDIO_HOST := preload("res://game/world/world_audio_host.gd")

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


func play_record(record: Dictionary, request_kind: StringName, assets: Dictionary = {}) -> Dictionary:
	if request_kind == &"music_fadeout":
		return {"ok": true, "played": fade_out(int(record.get("fade_time", 0)))}
	var key: String = "%s:%d:%d" % [String(request_kind), int(record.get("bank", -1)), int(record.get("address", -1))]
	var prepared: Dictionary = _music_cache.get(key, {}) if _is_music(request_kind) else {}
	if prepared.is_empty():
		prepared = AUDIO_HOST.play(record, request_kind, assets)
		if bool(prepared.get("ok", false)) and _is_music(request_kind):
			_music_cache[key] = prepared
	if not bool(prepared.get("ok", false)):
		return prepared
	var stream: AudioStream = prepared.get("stream", null) as AudioStream
	if stream == null:
		return {"ok": false, "played": false, "reason": &"audio_stream_unavailable"}
	if _is_music(request_kind):
		_stop_fade()
		_music_player.stream = stream
		_music_player.volume_db = 0.0
		_music_player.play()
		_music_key = key
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


func _exit_tree() -> void:
	stop_all()


func _is_music(request_kind: StringName) -> bool:
	return request_kind in [&"music", &"map_music", &"encounter_music"]


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
