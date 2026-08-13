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
const INTRO_TOTAL_FRAMES: int = 2335

const PHASE_COPYRIGHT: StringName = &"copyright"
const PHASE_PRESENTS: StringName = &"presents"
const PHASE_INTRO_MOVIE: StringName = &"intro_movie"
const PHASE_TITLE: StringName = &"title"
const PHASE_NEW_GAME: StringName = &"new_game"
const PHASE_FINISHED: StringName = &"finished"
## The cartridge's own order: SplashScreen's copyright and GameFreak logo, then
## IntroSequence, then the title screen.
const PHASE_ORDER: Array[StringName] = [
	PHASE_COPYRIGHT, PHASE_PRESENTS, PHASE_INTRO_MOVIE, PHASE_TITLE,
]

var _profile: StringName = &"gold"
var _phase: StringName = &""
var _frame: int = 0
var _phase_frame: int = 0
var _intro_scene: int = 0
var _intro_scene_frame: int = 0
var _intro_scene_lengths: Array[int] = []
## `GameFreakPresentsScene` and the sprite beside it, which own every frame of
## the presents phase. Null until that phase is entered.
var _presents: Gen2GameFreakPresents = null
## `TitleScreenScene`'s own state while the title phase is up, null outside it.
var _title: Gen2TitleScene = null
## The `BattleAnimSineWave` the presents phase reads its motion out of, handed
## in by the host that has a cache open.
var _sine: Gen2BattleAnimData = null
var _waiting_sound: StringName = &""
var _events: Array[Dictionary] = []
## The phases the host can draw, empty for all of them.
var _available: Array[StringName] = []


## [param available] names the phases the host has art for. One left out does
## not run: the source's order is kept and what is missing is skipped, rather
## than held on a blank screen for the frames it would have taken. Empty means
## every phase, which is a host with the whole opening imported.
func start(
	profile: StringName = &"gold",
	intro_scene_lengths: Array[int] = [],
	available: Array[StringName] = [],
	sine: Gen2BattleAnimData = null,
) -> void:
	_profile = profile
	_sine = sine
	_presents = null
	_title = null
	_intro_scene_lengths = _validated_intro_lengths(intro_scene_lengths)
	_available = available.duplicate()
	if not is_available(PHASE_COPYRIGHT):
		_phase = PHASE_COPYRIGHT
		_frame = 0
		_phase_frame = 0
		_waiting_sound = &""
		_events.clear()
		_enter_after(PHASE_COPYRIGHT)
		return
	_phase = PHASE_COPYRIGHT
	_frame = 0
	_phase_frame = 0
	_intro_scene = 0
	_intro_scene_frame = 0
	_waiting_sound = &""
	_events.clear()
	_emit(&"play_music", {"music": &"none", "restart": true})
	_emit(&"hide_image", {"id": &"boot"})


## Whether [param phase] is one this run draws. A phase the host named, or any
## phase when it named none.
func is_available(phase: StringName) -> bool:
	return _available.is_empty() or phase in _available


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
func advance_frame(held: Array = []) -> Array[Dictionary]:
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
			_advance_title(held)
		PHASE_NEW_GAME:
			pass
	return drain_events()


## `RunTitleScreen`'s own loop, one frame of it. The screen answers on its own
## through `wTitleScreenSelectedOption`, so the two chords and the timeout land
## here rather than waiting on the host; only the main-menu answer is left for
## [method select_title], since what it opens is the host's business.
func _advance_title(held: Array) -> void:
	if _title == null:
		_enter_after(PHASE_TITLE)
		return
	_title.advance_frame(held)
	if not _title.finished():
		return
	var option: int = _title.selected_option()
	match option:
		Gen2TitleScene.OPTION_RESTART:
			# `TitleScreenEnd` fades the music out and jumps back to
			# `IntroSequence`, which is the whole opening again.
			_emit(&"play_music", {"music": &"none", "restart": true})
			_emit(&"restart_opening", {"profile": _profile})
			start(_profile, _intro_scene_lengths, _available, _sine)
		Gen2TitleScene.OPTION_DELETE_SAVE_DATA, Gen2TitleScene.OPTION_RESET_CLOCK:
			_emit(&"title_chord", {
				"option": option,
				"kind": (
					&"delete_save_data"
					if option == Gen2TitleScene.OPTION_DELETE_SAVE_DATA
					else &"reset_clock"
				),
			})
			_title = Gen2TitleScene.create(_profile, _sine)
		_:
			_emit(&"title_menu", {"profile": _profile})


## The live title screen, so a host can read the sprites and scroll it is
## drawing. Null outside the title phase.
func title() -> Gen2TitleScene:
	return _title


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
		_enter_after(PHASE_COPYRIGHT)


## The presents phase spends whatever `GameFreakPresentsScene` spends: the
## sequence is asked for a frame and the phase ends when it runs out, rather than
## on a budget of this coordinator's own.
func _advance_presents() -> void:
	if _presents == null:
		_enter_after(PHASE_PRESENTS)
		return
	_presents.advance_frame()
	for event: Dictionary in _presents.drain_events():
		# The sequence counts its own frames; the coordinator's are the ones a
		# caller reads, so only the payload crosses over.
		var values: Dictionary = event.duplicate()
		for key: String in ["type", "frame", "scene"]:
			values.erase(key)
		_emit(StringName(event.get("type", &"")), values)
	if _presents.finished():
		_emit(&"hide_image", {"id": &"game_freak_presents"})
		_enter_after(PHASE_PRESENTS)


## The live sequence, so a host can read the sprites and words it is drawing.
## Null outside the presents phase.
func presents() -> Gen2GameFreakPresents:
	return _presents


## The button `.joy_loop` reads, which is the only skip in the whole splash:
## the copyright half spends `DelayFrames` and never looks at the joypad.
func skip_presents() -> bool:
	return _presents != null and _presents.cancel()


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
		_enter_after(PHASE_INTRO_MOVIE)
	else:
		_emit(&"show_image", {"id": &"intro_scene", "scene": _intro_scene})


## Enters the first phase after [param phase] the host can draw, with that
## phase's own opening events, or finishes when none is left. The events a phase
## leaves behind belong to the phase leaving, so a caller emits those first.
func _enter_after(phase: StringName) -> void:
	var at: int = PHASE_ORDER.find(phase)
	for index: int in range(at + 1, PHASE_ORDER.size()):
		var next: StringName = PHASE_ORDER[index]
		if not is_available(next):
			continue
		_phase = next
		_phase_frame = 0
		match next:
			PHASE_PRESENTS:
				# `GameFreakPresentsInit`, which loads the art and puts the
				# Ditto or the star up before the loop's first frame.
				_presents = Gen2GameFreakPresents.new()
				_presents.start(_profile, _sine)
				_emit(&"show_image", {"id": &"game_freak_presents"})
			PHASE_INTRO_MOVIE:
				_intro_scene = 0
				_intro_scene_frame = 0
				_emit(&"play_music", {"music": &"gold_silver_opening", "restart": false})
				_emit(&"show_image", {"id": &"intro_scene", "scene": _intro_scene})
			PHASE_TITLE:
				# `_TitleScreen` draws the whole screen and plays
				# `SFX_TITLE_SCREEN_ENTRANCE` before the loop's first frame;
				# Crystal's music waits for its entrance to finish, so the
				# request is the same either way and the host owns the delay.
				_title = Gen2TitleScene.create(_profile, _sine)
				_emit(&"open_title", {"profile": _profile})
				_emit(&"play_music", {"music": &"title", "restart": false})
		return
	_phase = PHASE_FINISHED
	_phase_frame = 0
	_emit(&"finish_intro", {})


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
