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
## `CrystalIntro`'s own state while the movie phase is up, null outside it.
var _movie: Gen2IntroMovie = null
## The cache the movie reads its art out of, handed in by the host.
var _data: GameData = null
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
	data: GameData = null,
	available: Array[StringName] = [],
	sine: Gen2BattleAnimData = null,
) -> void:
	_profile = profile
	_sine = sine
	_data = data
	_presents = null
	_title = null
	_movie = null
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
	return _movie.scene() if _movie != null else 0


## The live movie, so a host can read the screen it is drawing. Null outside the
## intro phase.
func movie() -> Gen2IntroMovie:
	return _movie


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
			# `IntroSequence`, which is the whole opening again. The restart runs
			# first because [method start] empties the queue, and its own
			# `play_music none` is the fade landing.
			start(_profile, _data, _available, _sine)
			_emit(&"restart_opening", {"profile": _profile})
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


## The movie spends whatever `CrystalIntro` spends: the sequence is asked for a
## frame and the phase ends when its jumptable sets `JUMPTABLE_EXIT_F`.
func _advance_intro() -> void:
	if _movie == null:
		_enter_after(PHASE_INTRO_MOVIE)
		return
	var scene: int = _movie.scene()
	for event: Dictionary in _movie.advance_frame():
		var values: Dictionary = event.duplicate()
		for key: String in ["type", "frame", "scene"]:
			values.erase(key)
		_emit(StringName(event.get("type", &"")), values)
	if _movie.scene() != scene:
		_emit(&"show_image", {"id": &"intro_movie", "scene": _movie.scene()})
	if _movie.finished():
		_emit(&"hide_image", {"id": &"intro_movie"})
		_enter_after(PHASE_INTRO_MOVIE)


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
				# `CrystalIntro` starts on a cleared screen and plays no music
				# until `IntroScene13`, so the phase opens with the art alone.
				_movie = Gen2IntroMovie.create(_data, _sine)
				_emit(&"show_image", {"id": &"intro_movie", "scene": 0})
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
