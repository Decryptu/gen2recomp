class_name Gen2LauncherAudio
extends Node

## The launcher's own sound effects, separate from [Gen2AudioPlayer] because
## none of these come from a cartridge.
##
## Clips are synthesised by `tools/generate_launcher_sfx.gd`. Volume follows the
## app block's sound setting, and a muted setting silences the launcher without
## touching the game.

const CLIPS: Dictionary = {
	&"hover": preload("res://assets/launcher/sfx/hover.wav"),
	&"click": preload("res://assets/launcher/sfx/click.wav"),
	&"insert": preload("res://assets/launcher/sfx/insert.wav"),
	&"eject": preload("res://assets/launcher/sfx/eject.wav"),
	&"power": preload("res://assets/launcher/sfx/power.wav"),
	&"error": preload("res://assets/launcher/sfx/error.wav"),
}

## Several clips overlap: a hover tick lands while a cartridge is still seating.
const VOICES: int = 6

static var _instance: Gen2LauncherAudio = null

var muted: bool = false

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


static func play(clip: StringName) -> void:
	var audio: Gen2LauncherAudio = _shared()
	if audio != null:
		audio.play_clip(clip)


## Public so a screen can silence itself while it rebuilds, and so tests can
## drive the launcher without waking the audio server.
static func set_muted(on: bool) -> void:
	var audio: Gen2LauncherAudio = _shared()
	if audio != null:
		audio.muted = on


static func _shared() -> Gen2LauncherAudio:
	if is_instance_valid(_instance):
		return _instance
	var loop: MainLoop = Engine.get_main_loop()
	if loop is not SceneTree:
		return null
	var tree: SceneTree = loop
	if tree.root == null:
		return null
	_instance = Gen2LauncherAudio.new()
	_instance.name = "Gen2LauncherAudio"
	tree.root.add_child.call_deferred(_instance)
	return _instance


func _ready() -> void:
	for index: int in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func play_clip(clip: StringName) -> void:
	if muted or _players.is_empty() or not CLIPS.has(clip):
		return
	var volume: int = Gen2OptionsStore.current().sfx_volume
	if volume <= 0:
		return
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = CLIPS[clip]
	player.volume_db = linear_to_db(float(volume) / float(Gen2Options.MAX_VOLUME))
	player.play()
