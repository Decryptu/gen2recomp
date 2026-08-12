class_name Gen2BootCinema
extends RefCounted

## Scene-free boot coordinator for SplashScreen, IntroSequence and the title
## handoff. Presentation hosts consume the requests; this object only advances
## source hardware frames and waits for explicit completion dependencies.
##
## Source: pokegold/engine/movie/splash.asm, engine/movie/intro.asm and
## engine/menus/intro_menu.asm (SplashScreen, IntroSceneJumper,
## TitleScreenScene, Copyright).

const FRAME_RATE: float = 59.7275
const COPYRIGHT_PRELUDE_FRAMES: int = 10
const COPYRIGHT_HOLD_FRAMES: int = 100
const PRESENTS_LOGO_FRAMES: int = 32
const PRESENTS_WORD_FRAMES: int = 64
const PRESENTS_HOLD_FRAMES: int = 128
const PRESENTS_CLEANUP_FRAMES: int = 16
const INTRO_TOTAL_FRAMES: int = 2335

const PHASE_COPYRIGHT: StringName = &"copyright"
const PHASE_PRESENTS: StringName = &"presents"
const PHASE_INTRO_MOVIE: StringName = &"intro_movie"
const PHASE_TITLE: StringName = &"title"
const PHASE_NEW_GAME: StringName = &"new_game"
const PHASE_FINISHED: StringName = &"finished"

var _profile: StringName = &"gold"
var _phase: StringName = &""
var _frame: int = 0
var _phase_frame: int = 0
var _intro_scene: int = 0
var _intro_scene_frame: int = 0
var _intro_scene_lengths: Array[int] = []
var _waiting_sound: StringName = &""
var _events: Array[Dictionary] = []


func start(profile: StringName = &"gold", intro_scene_lengths: Array[int] = []) -> void:
	_profile = profile
	_intro_scene_lengths = _validated_intro_lengths(intro_scene_lengths)
	_phase = PHASE_COPYRIGHT
	_frame = 0
	_phase_frame = 0
	_intro_scene = 0
	_intro_scene_frame = 0
	_waiting_sound = &""
	_events.clear()
	_emit(&"play_music", {"music": &"none", "restart": true})
	_emit(&"hide_image", {"id": &"boot"})


func phase() -> StringName:
	return _phase


func frame() -> int:
	return _frame


func phase_frame() -> int:
	return _phase_frame


func intro_scene() -> int:
	return _intro_scene


func waiting_sound() -> StringName:
	return _waiting_sound


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events.duplicate(true)
	_events.clear()
	return out


## Advances exactly one 59.7275 Hz source frame. A sound wait is released only
## through complete_sound(), so a slow or failed device cannot be mistaken for
## a fixed presentation delay.
func advance_frame() -> Array[Dictionary]:
	if _phase.is_empty() or _phase == PHASE_FINISHED or not _waiting_sound.is_empty():
		return drain_events()
	_frame += 1
	_phase_frame += 1
	match _phase:
		PHASE_COPYRIGHT:
			_advance_copyright()
		PHASE_PRESENTS:
			_advance_presents()
		PHASE_INTRO_MOVIE:
			_advance_intro()
		PHASE_TITLE:
			pass
		PHASE_NEW_GAME:
			pass
	return drain_events()


func wait_sound(token: StringName) -> void:
	_waiting_sound = token
	_emit(&"wait_sound", {"token": token})


func complete_sound(token: StringName) -> bool:
	if _waiting_sound != token:
		return false
	_waiting_sound = &""
	_emit(&"sound_completed", {"token": token})
	return true


func select_title(option: StringName) -> bool:
	if _phase != PHASE_TITLE or option not in [&"new_game", &"continue", &"option"]:
		return false
	_emit(&"title_selected", {"option": option})
	if option == &"new_game":
		_phase = PHASE_NEW_GAME
		_phase_frame = 0
		_emit(&"fade", {"frames": 8, "direction": &"out"})
		_emit(&"open_new_game", {"profile": _profile})
	return true


func finish_new_game() -> bool:
	if _phase != PHASE_NEW_GAME:
		return false
	_phase = PHASE_FINISHED
	_phase_frame = 0
	_emit(&"finish_intro", {})
	return true


func _advance_copyright() -> void:
	if _phase_frame == COPYRIGHT_PRELUDE_FRAMES:
		_emit(&"show_image", {"id": &"copyright"})
	if _phase_frame == COPYRIGHT_PRELUDE_FRAMES + COPYRIGHT_HOLD_FRAMES:
		_emit(&"hide_image", {"id": &"copyright"})
		_phase = PHASE_PRESENTS
		_phase_frame = 0
		_emit(&"show_image", {"id": &"game_freak_presents"})
		_emit(&"play_sfx", {"sfx": &"game_freak_logo"})


func _advance_presents() -> void:
	if _phase_frame == PRESENTS_LOGO_FRAMES:
		_emit(&"show_image", {"id": &"game_freak"})
		_emit(&"play_sfx", {"sfx": &"game_freak_presents"})
	if _phase_frame == PRESENTS_LOGO_FRAMES + PRESENTS_WORD_FRAMES:
		_emit(&"show_image", {"id": &"presents"})
	if _phase_frame == PRESENTS_LOGO_FRAMES + PRESENTS_WORD_FRAMES + PRESENTS_HOLD_FRAMES:
		_emit(&"hide_image", {"id": &"game_freak_presents"})
		_emit(&"wipe", {"direction": &"out", "frames": PRESENTS_CLEANUP_FRAMES})
		_phase = PHASE_INTRO_MOVIE
		_phase_frame = 0
		_intro_scene = 0
		_intro_scene_frame = 0
		_emit(&"play_music", {"music": &"gold_silver_opening", "restart": false})
		_emit(&"show_image", {"id": &"intro_scene", "scene": _intro_scene})


func _advance_intro() -> void:
	_intro_scene_frame += 1
	if _intro_scene >= _intro_scene_lengths.size():
		return
	if _intro_scene_frame < _intro_scene_lengths[_intro_scene]:
		_emit(&"intro_frame", {
			"scene": _intro_scene,
			"frame": _intro_scene_frame,
			"total_frame": _phase_frame,
		})
		return
	_intro_scene += 1
	_intro_scene_frame = 0
	if _intro_scene >= _intro_scene_lengths.size():
		_phase = PHASE_TITLE
		_phase_frame = 0
		_emit(&"open_title", {"profile": _profile})
		_emit(&"play_music", {"music": &"title", "restart": false})
	else:
		_emit(&"show_image", {"id": &"intro_scene", "scene": _intro_scene})


func _emit(type: StringName, values: Dictionary) -> void:
	var event: Dictionary = {
		"type": type,
		"phase": _phase,
		"frame": _frame,
		"phase_frame": _phase_frame,
	}
	event.merge(values, true)
	_events.append(event)


func _validated_intro_lengths(lengths: Array[int]) -> Array[int]:
	if lengths.is_empty():
		# The source movie is one frame-stepped 28-scene sequence. The fixed
		# scene budgets keep the coordinator deterministic; imported intro data
		# may replace them with the per-scene budgets used by its renderer.
		var defaults: Array[int] = []
		for _scene: int in 28:
			defaults.append(1)
		defaults[1] = 128
		defaults[2] = 800
		defaults[3] = 96
		defaults[4] = 80
		defaults[6] = 255
		defaults[7] = 255
		defaults[8] = 64
		defaults[10] = 128
		defaults[11] = 16
		defaults[12] = 128
		defaults[13] = 4
		defaults[14] = 64
		defaults[15] = 128
		defaults[16] = 64
		defaults[5] = 112
		var remainder: int = INTRO_TOTAL_FRAMES
		for value: int in defaults:
			remainder -= value
		defaults[5] += maxi(remainder, 0)
		return defaults
	var out: Array[int] = []
	var total: int = 0
	for value: int in lengths:
		if value <= 0:
			return _validated_intro_lengths([])
		out.append(value)
		total += value
	if out.size() != 28 or total != INTRO_TOTAL_FRAMES:
		return _validated_intro_lengths([])
	return out
