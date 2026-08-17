class_name Gen2AudioPlayer
extends Node

## Runs the cartridge sound driver in real time.
##
## One [Gen2SoundEngine] and one [Gen2Apu] behind a single generator stream:
## music, effects and cries share the four hardware channels and steal them from
## each other exactly as they do on the cartridge, so nothing here mixes or
## prioritises. Each serviced step is one `_UpdateSound` plus the frame of
## samples the APU produced from it.

## The generator's depth, which Godot rounds up to 4,096 output frames: seven
## driver frames, 125 ms. This is latency, not headroom, because the buffer is
## kept as full as it will go, so a button's effect is heard that long after the
## press. Measured worst emptiness on a desktop run is a quarter of it; halving
## it again would leave nothing for a long frame.
const BUFFER_SECONDS: float = 0.1

## Whether `Music_StereoPanning` is honoured. Follows the SOUND option, which is
## what `wOptions`' STEREO bit means to the driver.
var stereo: bool = false:
	set(value):
		stereo = value
		if _engine != null:
			_engine.stereo = value

var _player: AudioStreamPlayer = null
var _generator: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null
## Driver frames rendered, which is what says the timeline is moving at all. See
## [method timeline_updates].
var _timeline_updates: int = 0
var _engine: Gen2SoundEngine = null
var _apu: Gen2Apu = null
var _music_key: String = ""
var _buffer: PackedVector2Array = PackedVector2Array()


## The driver exists before the node enters the tree: a host that plays its map
## music while it is still building itself has to reach a live engine.
func _init() -> void:
	_apu = Gen2Apu.new()
	_engine = Gen2SoundEngine.new(_apu)
	_engine.init_sound()
	_buffer.resize(Gen2Apu.SAMPLES_PER_FRAME)


func _ready() -> void:
	stereo = Gen2OptionsStore.current().stereo
	_start_stream()
	set_process(true)


func _process(_delta: float) -> void:
	_service_timeline()


## Plays one imported audio record. Music continues when the source asks for the
## same track again; everything else follows the driver's own channel rules.
func play_record(
	record: Dictionary,
	request_kind: StringName,
	assets: Dictionary = {},
	restart: bool = false,
	cry_tracks: int = 0,
) -> Dictionary:
	if request_kind == &"music_fadeout":
		return {"ok": true, "played": fade_out(int(record.get("fade_time", 0)))}
	if record.is_empty():
		return {"ok": false, "played": false, "reason": &"audio_data_unavailable"}
	_engine.set_assets(assets)
	_engine.stereo = stereo

	var music: bool = _is_music(request_kind)
	var key: String = "%d:%d" % [int(record.get("bank", -1)), int(record.get("address", -1))]
	if music:
		# `PlayMusic MUSIC_NONE` is `_InitSound`, not a stream: it is how the
		# source stops everything.
		if int(record.get("index", -1)) == 0:
			_engine.init_sound()
			_music_key = ""
			return {"ok": true, "played": true, "stopped": true}
		if not restart and key == _music_key:
			return {"ok": true, "played": false, "continued": true}

	_start_stream()
	var started: bool = false
	match request_kind:
		&"cry", &"cries", &"mon_cry":
			# `PlayStereoCry` writes wCryTracks and puts 1 in wStereoPanningMask;
			# `PlayMonCry2` zeroes both. Written per request rather than kept, so
			# one battler's side cannot leak into the next cry.
			_engine.cry_tracks = cry_tracks
			_engine.stereo_panning_mask = 1 if cry_tracks != 0 else 0
			started = _engine.play_cry(record)
		&"sound", &"sfx":
			started = _engine.play_sfx(record)
		_:
			started = _engine.play_music(record)
	if not started:
		return {"ok": false, "played": false, "reason": &"audio_record_unplayable"}
	if music:
		_music_key = key
	return {
		"ok": true,
		"played": true,
		"ready": true,
		"request_kind": request_kind,
		"index": int(record.get("index", -1)),
		"bank": int(record.get("bank", -1)),
		"address": int(record.get("address", -1)),
	}


## `FadeMusic`: a frame count per volume step. Zero stops at once, which is what
## the source's own zero-length fades do.
func fade_out(frames: int = 0) -> bool:
	if frames <= 0:
		if not _engine.any_channel_active():
			return false
		_engine.init_sound()
		_music_key = ""
		return true
	_engine.start_fade(frames)
	_music_key = ""
	return true


## `FadeToMapMusic`: the same `wMusicFade`, with `wMusicFadeID` behind it, so the
## new track starts when the fade reaches zero rather than over the old one.
## Answers false when there is nothing playing to fade, which is the source's own
## `cp e / jr z, .done` and the driver starting the piece at once.
func fade_to(record: Dictionary, frames: int, assets: Dictionary = {}) -> bool:
	if record.is_empty():
		return false
	_engine.set_assets(assets)
	_engine.stereo = stereo
	var key: String = "%d:%d" % [int(record.get("bank", -1)), int(record.get("address", -1))]
	if key == _music_key:
		return false
	if not _engine.any_channel_active():
		return bool(play_record(record, &"map_music", assets).get("played", false))
	_start_stream()
	_engine.start_fade(frames, record)
	_music_key = key
	return true


func stop_all() -> void:
	_engine.init_sound()
	_music_key = ""
	if _player != null:
		_player.stop()
	_playback = null


## `wLowHealthAlarm`'s DANGER_ON bit, which is what `PlayDanger` runs off.
## `HandleHPPals` sets it while the player's bar is HP_RED and clears it
## otherwise; `StopDangerSound` and `CleanUpBattleRAM` zero the byte whole,
## which is what clearing it here does, timer and all.
func set_low_health_alarm(on: bool) -> void:
	if on:
		_engine.low_health_alarm |= 1 << Gen2SoundEngine.DANGER_ON_BIT
		return
	_engine.low_health_alarm = 0


func low_health_alarm() -> bool:
	return (_engine.low_health_alarm & (1 << Gen2SoundEngine.DANGER_ON_BIT)) != 0


## `_CheckSFX`, which is what `waitsfx` and the battle screen wait on.
func effect_playing() -> bool:
	return _engine.sfx_active()


## How many driver frames this player has actually rendered.
##
## The engine only advances inside [method _service_timeline], which needs an
## output stream with room in it: a headless run, a check or a replay leaves the
## channels exactly as the last request set them, so [method effect_playing] would
## answer true for the rest of the run. Anything WAITING on a sound compares this
## count across two frames instead of trusting that answer, and stops waiting when
## it has not moved. `AudioStreamPlayer.playing` is not that test: the dummy audio
## driver reports true and consumes nothing. See `Gen2BattleScreen`'s
## `ANIM_WAIT_SFX` and `HANDOFF.md`'s `WaitSFX` row.
func timeline_updates() -> int:
	return _timeline_updates


func audio_status() -> Dictionary:
	var active: Array[int] = []
	for index: int in Gen2SoundEngine.NUM_CHANNELS:
		if _engine.channels[index].channel_on:
			active.append(index + 1)
	return {
		"active_channels": active,
		"sfx_active": _engine.sfx_active(),
		"music_active": _engine.music_channels_active(),
		"volume": _engine.volume,
		"sound_output": _engine.sound_output,
		"registered_banks": _engine.registered_bank_count(),
	}


func _exit_tree() -> void:
	stop_all()
	# Stopping the player is not enough to let go of its playback: the audio
	# server holds one per stream, and only taking the stream off the player
	# releases it. A headless tool that builds a world screen and exits reported
	# one leaked `AudioStreamGeneratorPlayback` per screen without this.
	if _player != null:
		_player.stream = null
	_generator = null


func _is_music(request_kind: StringName) -> bool:
	return request_kind in [&"music", &"map_music", &"encounter_music"]


func _ensure_output() -> void:
	if _player != null:
		return
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = Gen2Apu.SAMPLE_RATE
	_generator.buffer_length = BUFFER_SECONDS
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.stream = _generator
	add_child(_player)


## The generator runs from the moment the node is in the tree, the way the APU
## is always clocked. A host that starts its music while still building itself
## reaches the driver first and the output as soon as it is on screen.
func _start_stream() -> void:
	_ensure_output()
	if not is_inside_tree():
		return
	if not _player.playing:
		_player.play()
		_playback = null
	if _playback == null:
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## Fills the generator a source frame at a time. Audio time is the driver's
## clock, not the renderer's: a long game frame is caught up here rather than
## slowing the music down.
func _service_timeline() -> void:
	if _player == null or not _player.playing:
		return
	if _playback == null:
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _playback == null:
			return
	while _playback.get_frames_available() >= Gen2Apu.SAMPLES_PER_FRAME:
		_timeline_updates += 1
		_engine.update_sound()
		_apu.render_frame(_buffer)
		_playback.push_buffer(_buffer)
