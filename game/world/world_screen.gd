class_name Gen2WorldScreen
extends Control

## Cartridge-backed overworld screen.
##
## A validated world snapshot is authoritative. The explicit map and cell are
## retained as a development entry point for scene tests and cache inspection.

const BACKGROUND: Color = Color("#09111f")
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const BATTLE_SCENE: PackedScene = preload("res://game/battle/battle_screen.tscn")
const SERVICE_SCENE: PackedScene = preload("res://game/world/world_service_screen.tscn")
const START_MENU_SCENE: PackedScene = preload("res://game/world/start_menu_screen.tscn")
const PARTY_SCENE: PackedScene = preload("res://game/save/party_screen.tscn")
const AUDIO_PLAYER_SCRIPT := preload("res://game/audio/gen2_audio_player.gd")
## constants/sfx_constants.asm's SFX_JUMP_OVER_LEDGE (comments there are hex,
## confirmed against neighbouring $0a/$0f/$1a), played by .TryJump as the hop
## starts. Played directly rather than through _handle_audio_request(), which
## expects a runtime request to acknowledge; a hop is movement, not a script.
## _play_current_map_music() below is the precedent for this shape.
const SFX_JUMP_OVER_LEDGE: int = 0x16
## constants/sfx_constants.asm's SFX_PLACE_PUZZLE_PIECE_DOWN, played by
## OWCutAnimation before its sprite animation. The animation itself is not
## rendered here; the sound is.
const SFX_CUT: int = 0x1E
## constants/sfx_constants.asm's SFX_SURF, which is what PlayWhirlpoolSound plays
## (engine/events/field_moves.asm); there is no whirlpool-specific effect.
const SFX_WHIRLPOOL: int = 0x53
## constants/sfx_constants.asm's SFX_STRENGTH, played by MovementFunction_Strength
## as a pushed boulder starts moving, not by the menu that sets the flag.
const SFX_STRENGTH: int = 0x1B
## constants/sfx_constants.asm's SFX_BUBBLEBEAM, which Script_UsedWaterfall plays
## after its text and before the first climbing step.
const SFX_WATERFALL: int = 0x51
## constants/sfx_constants.asm's SFX_SANDSTORM, which is what ShakeHeadbuttTree
## plays (engine/events/field_moves.asm). SFX_HEADBUTT is a battle-move effect
## and is referenced by nothing in either pin's overworld code.
const SFX_HEADBUTT_TREE: int = 0x6D
## constants/music_constants.asm, which AnimateHallOfFame plays over the whole
## induction.
const MUSIC_HALL_OF_FAME: int = 20

@export var map_group: int = 24
@export var map_number: int = 3
@export var start_cell: Vector2i = Vector2i(4, 4)
@export_range(0, 23) var hour: int = 6
@export_range(0, 59) var minute: int = 0
@export_range(0, 6) var day: int = 0
@export_range(0, 3) var time_of_day: int = Gen2WorldPalette.TIME_MORNING
@export var encounter_seed: int = 0

var _data: GameData = null
var _injected_data: GameData = null
var _injected_save: Gen2SaveData = null
var _world: Gen2WorldAPI = null
## Whatever the mod host supplies. Typed as Node because a registered renderer
## only has to satisfy Gen2ModHost.WORLD_RENDERER_METHODS, not extend the 2D one.
var _renderer: Node = null
var _animation: Gen2WorldAnimation = null
var _effects: Gen2WorldEffects = null
var _text_box: Gen2TextBox = null
var _clock: Gen2WorldClock = null
var _audio_player: Gen2AudioPlayer = null
var _audio_waiting: bool = false
var _script_prompt: String = ""
var _story_picture_backdrop: ColorRect = null
var _story_picture: TextureRect = null
var _battle_host: Gen2BattleScreen = null
var _trainer_card_host: Gen2TrainerCardScreen = null
var _pokedex_host: Gen2PokedexScreen = null
## `wPrevDexEntry`, which is plain WRAM rather than saved data: it survives the
## dex closing and reopening for as long as the game runs, the way the start
## menu cursor below survives its own screen.
var _pokedex_prev_entry: int = 0
var _service_host: Gen2WorldServiceScreen = null
var _start_menu_host: Gen2StartMenuScreen = null
var _party_host: Gen2PartyScreen = null
var _hall_of_fame_host: Gen2HallOfFameScreen = null
var _credits_host: Gen2CreditsScreen = null
## Whether a field-move message is on screen waiting for its acknowledge. The
## world is idle while it is, the same way a script text pause holds it.
var _field_move_text: bool = false
## `ProfOaksPCBoot`'s three texts, one page at a time, and the sfx `Rate` leaves
## for it to play once the last of them is up.
var _oak_pc_pages: Array = []
var _oak_pc_sfx: int = -1
## Mirrors the source's wBattleMenuCursorPosition surviving a reopen.
var _start_menu_cursor: int = 0
## `.MenuReturns`' first entry, `.Reopen`: Pokedex, Pokemon, Pokegear and the
## trainer card all return 0 from their `StartMenu_*` handler, so the menu is
## drawn again rather than closed. Set when the menu opened the screen, so a
## Pokegear reached by a script or by the debug key still returns to the world.
var _reopen_start_menu: bool = false
var _trainer_approach: Dictionary = {}
var _active_battle_save: Gen2SaveData = null
var _active_battle_persist: bool = false
var _encounter_random := RandomNumberGenerator.new()
## NPC movement rolls from its own generator, so a seeded route keeps the same
## encounters and script results however long the player stands watching.
var _object_random := RandomNumberGenerator.new()
var _selected_rod: StringName = Gen2WorldEncounter.METHOD_OLD_ROD
## Real time banked toward the next hardware frame. The overworld's one clock:
## see [method _process].
var _frame_elapsed: float = 0.0
## `(frame, button)` input, recorded from a run and played back into another.
## Both are opt-in and off in play. A replay applies a log's entries on the frame
## that recorded them, from inside the pump, so a host that owes two frames
## delivers the input of both rather than only of the later one; that is what
## makes a replay independent of the frame rate it was recorded at.
var _input_recording: Array = []
var _recording_input: bool = false
var _input_replay: Dictionary = {}
var _replaying_input: bool = false
## What a replay is holding down, in place of the runtime's own poll.
var _replay_held_direction: int = Gen2Button.NONE
## Whether a frame is being spent right now, which is what tells a press
## delivered from inside the pump from one that arrived between two frames.
var _spending_frame: bool = false
var _screen_base_position: Vector2 = Vector2.ZERO

@onready var _screen: Gen2Screen = %Screen
@onready var _caption: Label = %Caption
@onready var _hint: Label = %Hint


func _ready() -> void:
	# The map and cell readout and the shortcut legend are scaffolding, and they
	# are also the two things standing between the player and a full screen on a
	# phone. Same flag as the shortcuts they describe.
	_caption.visible = Gen2DebugKeys.enabled()
	_hint.visible = Gen2DebugKeys.enabled()
	_data = _injected_data if _injected_data != null else _selected_runtime_data()
	_build_world()


## Supplies a cache-backed data source before the scene enters the tree. The
## launcher continues to use GameRuntime; this boundary lets scene tests and
## development tools exercise an explicitly selected cache without mutating
## global runtime selection.
func set_data(data: GameData) -> void:
	_injected_data = data


## Supplies an optional validated save for a scene test or development tool.
## Normal gameplay still reads the selected slot from GameRuntime.
func set_save(save: Gen2SaveData) -> void:
	_injected_save = save


## The run's seed, in the order a run can claim one: the slot that recorded it,
## the snapshot it was opened from, the scene's own development export, then a
## fresh roll. Whatever wins is written back to the slot, so a run is
## reproducible from the frame it started rather than from the next save.
func _resolve_run_seed(save: Gen2SaveData) -> int:
	var value: int = 0
	if save != null and save.run_seed != 0:
		value = save.run_seed
	elif _world.random_seed != 0:
		value = _world.random_seed
	elif encounter_seed != 0:
		value = encounter_seed
	else:
		var rolled := RandomNumberGenerator.new()
		rolled.randomize()
		while value == 0:
			value = rolled.randi()
	if save != null:
		save.run_seed = value
		if save.run_mods.is_empty():
			save.run_mods = Gen2ModHost.instance().loaded_mods()
	return value


func _build_world() -> void:
	if _data == null:
		_caption.text = "No imported cache"
		_hint.text = "Import a supported cartridge first."
		return

	var selected_save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	var initial_day: int = day
	var initial_hour: int = hour
	var initial_minute: int = minute
	if selected_save != null and selected_save.world != null:
		_world = Gen2WorldAPI.open_snapshot(_data, selected_save.world)
		if _world == null:
			_caption.text = "Saved overworld unavailable"
			_hint.text = "The saved map or player position is not valid for this cache."
			return
		var saved_clock: Dictionary = selected_save.world.world_clock()
		initial_day = int(saved_clock.get("day", initial_day))
		initial_hour = int(saved_clock.get("hour", initial_hour))
		initial_minute = int(saved_clock.get("minute", initial_minute))
	elif selected_save != null:
		_world = Gen2WorldAPI.open(_data, map_group, map_number, start_cell)
	else:
		var development_state := Gen2WorldState.new(
			{}, {}, {
				Gen2WorldInventory.ITEM_OLD_ROD: 1,
				Gen2WorldPartyHost.ITEM_POKE_BALL: 1,
			}
		)
		_world = Gen2WorldAPI.open(
			_data, map_group, map_number, start_cell, development_state
		)
	if _world == null:
		_caption.text = "Map %d/%d unavailable" % [map_group, map_number]
		_hint.text = "Choose an imported map and starting cell in the scene settings."
		return
	_refresh_party_summary()
	var run_seed: int = _resolve_run_seed(selected_save)
	_encounter_random.seed = run_seed
	## One seed, two streams: the second is offset so the object generator is not
	## a replay of the encounter one.
	_object_random.seed = run_seed + 1
	_world.random_seed = run_seed

	_world.schedule_random = _encounter_random
	_world.script_random = _encounter_random
	_world.object_random = _object_random
	_clock = Gen2WorldClock.new(initial_hour, initial_minute, initial_day)
	time_of_day = _clock.time_of_day()
	_animation = Gen2WorldAnimation.new()
	_effects = Gen2WorldEffects.new()
	_world.set_world_clock(initial_day, initial_hour, initial_minute)
	_world.set_object_time(initial_hour, time_of_day)
	var rods: Array[StringName] = _world.available_fishing_rods()
	if not rods.is_empty() and not rods.has(_selected_rod):
		_selected_rod = rods[0]
	_animation.configure(_world, time_of_day)
	_build_renderer()
	_screen_base_position = _screen.position
	_audio_player = AUDIO_PLAYER_SCRIPT.new()
	_audio_player.name = "AudioPlayer"
	add_child(_audio_player)
	_play_current_map_music()
	_text_box = Gen2TextBox.new()
	_text_box.font = Gen2Font.from_data(_data)
	_apply_text_box_options()
	_text_box.place_at_bottom()
	_text_box.visible = false
	_text_box.item_rect_changed.connect(_push_text_box_rect)
	_text_box.visibility_changed.connect(_push_text_box_rect)
	_screen.display(_text_box)
	_apply_renderer_interface_style()
	var entry_results: Array = _world.dispatch_map_entry()
	if not entry_results.is_empty():
		_show_script_results(entry_results)
	_refresh_labels()


## Builds the view for the selected renderer and attaches it to the layer that
## renderer asked for.
##
## Constructed through the mod host, so a registered renderer replaces this view
## without the screen knowing what it draws with. A renderer answering the
## surface question false gets the screen's rectangle at window resolution
## instead of the hardware viewport, which is what a 3D or HD view needs; text
## boxes and menus above it stay hardware pixels either way.
func _build_renderer() -> void:
	if _world == null:
		return
	if _renderer != null:
		if _screen.native_size_changed.is_connected(_on_native_size_changed):
			_screen.native_size_changed.disconnect(_on_native_size_changed)
		_renderer.get_parent().remove_child(_renderer)
		_renderer.queue_free()
	_renderer = Gen2ModHost.instance().create_world_renderer()
	if Gen2ModHost.renderer_uses_hardware_viewport(_renderer):
		_screen.display(_renderer)
	else:
		_screen.display_native(_renderer)
		_screen.native_size_changed.connect(_on_native_size_changed)
		_on_native_size_changed(_screen.native_size())
	_renderer.set_world(_world, _animation)
	_renderer.set_time_of_day(_render_time_of_day())
	_apply_renderer_interface_style()


## The text box is the screen's, not the renderer's, and over a native-layer view
## the cartridge's opaque white field is a slab across the map. A renderer may
## ask for it to be drawn through, and may be told where it is so it can compose
## around it. Both are pushed here and again whenever the box moves, resizes or
## is shown, since a renderer swapped in mid-scene has neither.
func _apply_renderer_interface_style() -> void:
	if _text_box == null:
		return
	_text_box.field_opacity = Gen2ModHost.renderer_interface_opacity(_renderer)
	_push_text_box_rect()


func _push_text_box_rect() -> void:
	if _text_box == null:
		return
	Gen2ModHost.renderer_set_text_box_rect(_renderer, _text_box.occupied_rect())


## What the renderer actually draws with, which is not always the clock: a dark
## cave stays dark until Flash is used and looks like night afterwards. See
## [method Gen2WorldPalette.map_time_of_day].
func _render_time_of_day() -> int:
	if _world == null:
		return time_of_day
	return _world.map_time_of_day()


func _on_native_size_changed(size_pixels: Vector2i) -> void:
	if _renderer != null \
		and _renderer.has_method(Gen2ModHost.RENDERER_RESIZE_METHOD):
		_renderer.call(Gen2ModHost.RENDERER_RESIZE_METHOD, size_pixels)


## Switches the live view to another registered renderer without disturbing the
## world behind it. This is the boundary a keybind uses to flip between the 2D
## view and a mod's: nothing about the map, the player or the running script
## changes, because a renderer only ever reads them.
func select_world_renderer(id: StringName) -> Dictionary:
	var result: Dictionary = Gen2ModHost.instance().select_world_renderer(id)
	if not bool(result.get("ok", false)):
		_script_prompt = "Renderer unavailable: %s" % String(result.get("reason", "unknown"))
		_refresh_labels()
		return result
	_build_renderer()
	_script_prompt = "Renderer: %s" % Gen2ModHost.instance().world_renderer_label(id)
	_refresh_labels()
	return result


## Selects the registered renderer after the current one, wrapping. One key can
## then cycle every installed view, which is how a mod's 3D world is reached.
func cycle_world_renderer() -> Dictionary:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var ids: Array = host.world_renderer_ids()
	if ids.size() < 2:
		_script_prompt = "No other renderer is registered"
		_refresh_labels()
		return {"ok": false, "reason": &"single_renderer"}
	var at: int = ids.find(host.selected_world_renderer())
	return select_world_renderer(ids[posmod(at + 1, ids.size())])


## Real time becomes hardware frames here and nowhere else in the overworld.
## Everything that counts frames is spent by [method advance_frame]; the day
## cycle underneath it is the one deliberate reader of `delta`, because Gen II
## keeps a real-time clock and a wall-clock reading is what the day cycle wants.
func _process(delta: float) -> void:
	_frame_elapsed = minf(
		_frame_elapsed + delta,
		Gen2WorldAnimation.FRAME_SECONDS * float(Gen2WorldAnimation.MAX_CATCHUP_FRAMES),
	)
	while _frame_elapsed >= Gen2WorldAnimation.FRAME_SECONDS:
		_frame_elapsed -= Gen2WorldAnimation.FRAME_SECONDS
		advance_frame()
	_advance_day_cycle(delta)


## Spends [param count] hardware frames. Public beside [method advance_frame] so
## a test, a preview tool or a replay settles the world on the frames it owes
## rather than on a clock.
func advance_frames(count: int) -> void:
	for _frame: int in maxi(0, count):
		advance_frame()


## One hardware frame of the overworld, in the order the frame is drawn in.
##
## Every countdown below is spent exactly once here, so each is a function of
## [member Gen2WorldAPI.frame_number] and not of banked real time.
func advance_frame() -> void:
	_spending_frame = true
	if _world != null:
		_world.advance_frame_counter()
		if _replaying_input:
			_apply_replayed_input(_world.frame_number)
	_advance_game_time_frame()
	if _effects != null:
		_effects.advance_frame()
		_apply_world_effect_offset()
	if _animation != null and _animation.advance_frame() and _renderer != null:
		_renderer.refresh_animation()
	if _world != null and _world.advance_player_step_frame() and _renderer != null:
		_renderer.refresh()
	if _world != null and _world.advance_emotes_frame() and _renderer != null:
		_renderer.refresh()
	_advance_forced_movement()
	_advance_held_direction()
	if _objects_may_move() and _world.advance_object_steps_frame(_object_random) \
		and _renderer != null:
		_renderer.refresh()
	# Not gated on _objects_may_move(): an applymovement is drawn while the
	# script that ran it is still going, which is when a script runs one.
	if _world != null and _world.advance_scripted_steps_frame() and _renderer != null:
		_renderer.refresh()
	# After the trail, because the frame it finishes drawing is the frame the
	# script waiting on it resumes.
	if _world != null and not _world.pending_script_wait().is_empty():
		var wait_results: Array = _world.advance_script_wait_frame()
		if not wait_results.is_empty():
			_show_script_results(wait_results)
	if not _trainer_approach.is_empty():
		_advance_trainer_approach()
	if _world != null and _world.phone_ring_active():
		var ring_results: Array = _world.advance_phone_ring_frame()
		if not ring_results.is_empty():
			_show_script_results(ring_results)
		_refresh_labels()
	# The condition is the audio device's, not a counter's, but the request it
	# completes is a script's, so it lands on a frame like every other resume.
	if _audio_waiting and _audio_player != null and not _audio_player.effect_playing():
		_audio_waiting = false
		var audio_result: Dictionary = Gen2WorldHost.complete_runtime_request(
			_world, {"ok": true, "sound_finished": true}
		)
		if bool(audio_result.get("ok", false)):
			_show_script_results(audio_result.get("results", []))
	_spending_frame = false


## Starts recording every button the world consumes, discarding any earlier log.
## What a run has to be replayable beside its seed: see [method replay_input] and
## `tools/replay_world.gd`.
func record_input() -> void:
	_input_recording = []
	_recording_input = true


## The recorded `(frame, kind, button)` entries, in the order they were consumed.
func input_recording() -> Array:
	return _input_recording.duplicate(true)


## Plays a recorded log back into this world instead of reading the input
## runtime. Every entry is applied on the frame it names, from inside the pump.
func replay_input(log: Array) -> void:
	_input_replay = {}
	for raw: Variant in log:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var frame: int = int(entry.get("frame", 0))
		var at: Dictionary = _input_replay.get(frame, {"hold": Gen2Button.NONE, "presses": []})
		if String(entry.get("kind", "")) == "hold":
			at["hold"] = int(entry.get("button", Gen2Button.NONE))
		else:
			(at["presses"] as Array).append(int(entry.get("button", Gen2Button.NONE)))
		_input_replay[frame] = at
	_replaying_input = true


func _apply_replayed_input(frame: int) -> void:
	var at: Dictionary = _input_replay.get(frame, {})
	_replay_held_direction = int(at.get("hold", Gen2Button.NONE))
	for button: int in at.get("presses", []) as Array:
		press_button(button)


## The Generation 2 day cycle, which is the one thing here that is not a frame
## count: the cartridge reads a real-time clock, so [Gen2WorldClock] takes real
## seconds and a replay holds it rather than converting it.
func _advance_day_cycle(delta: float) -> void:
	if _clock == null or _world == null:
		return
	var ticks: Array = _clock.advance(delta, _world)
	_world.set_world_clock(_clock.day, _clock.hour, _clock.minute)
	if ticks.is_empty():
		return
	_update_time_of_day()
	if not _overlay_open() and not _world.script_input_waiting():
		var phone_schedule: Dictionary = _world.advance_phone_schedule(
			ticks.size(), _encounter_random
		)
		var phone_results: Array = phone_schedule.get("results", [])
		if bool(phone_schedule.get("attempted", false)) and not phone_results.is_empty():
			_show_script_results(phone_results)
	_refresh_labels()


## .CheckTile's forced walk, which the source polls every frame with no input:
## a waterfall pushes the player back down and a door, staircase or cave tile
## steps them off it. The step already in progress paces it.
##
## PLAYERMOVEMENT_FORCE_TURN is deliberately not drained here. Its
## Script_ForcedMovement is a queued script whose two step_dig runs pace the spin,
## and this project renders none of that, so draining it per frame would flip the
## facing at the frame rate. Gen2WorldAPI.move_result() answers it on the movement
## attempt instead, which is where a player meets it.
func _advance_forced_movement() -> void:
	if not _objects_may_move() or _world.script_input_waiting() \
		or _world.player_step_in_progress():
		return
	if StringName(_world.forced_movement().get("kind", &"none")) != &"walk":
		return
	var forced: Dictionary = _world.advance_forced_movement()
	if bool(forced.get("ok", false)):
		_after_player_move(forced)


## Walking goes on while a direction is held, whatever is holding it: a key, a
## stick, a d-pad or a thumb on the on-screen controller.
##
## Polled rather than driven by repeated events, because the rate a held key
## repeats at belongs to the operating system and has nothing to do with the
## hardware. The poll runs once per hardware frame, which is what the source
## did, and [method move_player] refuses while a step is still in flight, which
## is what turns sixty polls a second into one step every sixteen frames.
func _advance_held_direction() -> void:
	## Polled before the pauses below rather than after, so a recording is what
	## was held rather than what the world did with it.
	var direction: int = _replay_held_direction if _replaying_input \
		else Gen2InputRuntime.instance().held_direction()
	if _recording_input and _world != null and direction != Gen2Button.NONE:
		_input_recording.append({
			"frame": _world.frame_number, "kind": "hold", "button": direction,
		})
	if not _objects_may_move() or _world.script_input_waiting() \
		or _world.player_step_in_progress():
		return
	if direction != Gen2Button.NONE:
		move_player(Gen2Button.vector(direction))


## Whether any embedded screen is up. Every overlay is named here and nowhere
## else: the six callers below each need a different set of the other pauses, but
## they all need this one, and adding an overlay to five of six lists by hand is
## what the Cut and Hall of Fame work each paid for once.
func _overlay_open() -> bool:
	return _battle_host != null or _service_host != null \
		or _start_menu_host != null or _party_host != null \
		or _hall_of_fame_host != null or _trainer_card_host != null \
		or _pokedex_host != null or _credits_host != null


## Wandering objects keep to themselves while anything else owns the world. A
## script may be moving those same objects, a trainer approach paces its own
## object by call count, and an overlay hides the map entirely.
func _objects_may_move() -> bool:
	return _world != null and not _overlay_open() \
		and not _field_move_text and _oak_pc_pages.is_empty() \
		and _trainer_approach.is_empty() \
		and not _world.script_busy() \
		and not _world.phone_ring_active() \
		and not _world.fishing_busy()


## Every control the cartridge had arrives here as a [Gen2Button], whichever
## device produced it. What is left over is a development shortcut or something
## only a renderer could want.
func _unhandled_input(event: InputEvent) -> void:
	if _world == null or _battle_host != null:
		return
	var button: int = Gen2Button.pressed_in(event)
	if button != Gen2Button.NONE:
		if press_button(button):
			accept_event()
		return
	## The dex area's SELECT and the credits' A and B are held states rather than
	## presses, and those two overlays are the only ones with anything to do with
	## a release.
	var released: int = Gen2Button.released_in(event)
	if released != Gen2Button.NONE and _pokedex_host != null:
		_pokedex_host.release_button(released)
		accept_event()
		return
	if released != Gen2Button.NONE and _credits_host != null:
		_credits_host.release_button(released)
		accept_event()
		return
	if event.is_pressed() and _handle_debug_key(event):
		accept_event()
		return
	# A mod's own declared control, before the raw leftovers: the mod hears its
	# own action id rather than an InputEvent, and the same pauses that hold a
	# renderer's events hold this one.
	if _renderer_input_free():
		var action: Dictionary = Gen2ModHost.instance().action_in(event)
		if not action.is_empty():
			Gen2ModHost.instance().emit_action(
				action["id"], action["key"], bool(action["pressed"])
			)
			accept_event()
			return
	# Everything the screen wants has been claimed above, so what reaches here is
	# what a renderer may have a use for: a free camera needs pointer and stick
	# motion, and the screen has no opinion about either.
	if _renderer_input_free() and Gen2ModHost.renderer_handles_input(_renderer, event):
		accept_event()


## One button, from whichever device produced it or from a replay, and the one
## place a press is recorded. A press between two frames is consumed by the world
## at the start of the next one, which is the frame the log names.
func press_button(button: int) -> bool:
	if _world == null or button == Gen2Button.NONE:
		return false
	if _recording_input:
		_input_recording.append({
			"frame": _world.frame_number if _spending_frame else _world.frame_number + 1,
			"kind": "press",
			"button": button,
		})
	return _handle_button(button)


## Routes one button to whatever owns the screen, and reports whether anything
## took it. A pause that owns the world swallows every button rather than
## refusing the ones it has no use for, which is what keeps a stray press from
## reaching the map behind it.
func _handle_button(button: int) -> bool:
	if not _trainer_approach.is_empty() or _world.phone_ring_active():
		return true
	## Before the PC and the party overlay because the Hall of Fame is the one
	## overlay a script opens with nothing behind it: there is no map to go back
	## to until it has finished, and it takes no cancel.
	if _hall_of_fame_host != null:
		_hall_of_fame_host.handle_button(button)
		return true
	if _credits_host != null:
		_credits_host.handle_button(button)
		return true
	if _party_host != null:
		_party_host.handle_button(button)
		return true
	if _field_move_text:
		if button == Gen2Button.A:
			_acknowledge_field_move_text()
		return true
	if not _oak_pc_pages.is_empty():
		## `JoyWaitAorB`, which is what waits between each of the three texts.
		if button in [Gen2Button.A, Gen2Button.B]:
			_advance_prof_oaks_pc()
		return true
	if _pokedex_host != null:
		return _pokedex_host.handle_button(button)
	if _trainer_card_host != null:
		return _trainer_card_host.handle_button(button)
	if _start_menu_host != null:
		return _start_menu_host.handle_button(button)
	if _service_host != null:
		return _service_host.handle_button(button)
	if _world.fishing_busy():
		if button == Gen2Button.A:
			_handle_fishing_result(_world.advance_fishing())
		return true
	if _world.script_input_waiting():
		if button == Gen2Button.A:
			_advance_script_pause()
		return true
	match button:
		Gen2Button.A:
			return interact()
		Gen2Button.START:
			_open_start_menu()
			return true
		Gen2Button.SELECT:
			open_select_menu()
			return true
	if Gen2Button.is_direction(button):
		move_player(Gen2Button.vector(button))
		return true
	return false


## The two OPTION rows a box reads, applied on every box rather than once:
## `Textbox` reads wTextboxFrame and `PrintLetterDelay` reads the text speed as
## each one is drawn, and the OPTION menu commits both on the press that changes
## them.
func _apply_text_box_options() -> void:
	if _text_box == null:
		return
	var options: Gen2Options = Gen2OptionsStore.current()
	_text_box.set_frame_style(options.textbox_frame)
	_text_box.reveal_speed = options.text_reveal_speed()


## The A press that clears whatever a running script is waiting on.
func _advance_script_pause() -> void:
	## Except a frame wait, which nothing but frames ends: the source is inside
	## WaitScriptMovement or a DelayFrames loop and reads no input there.
	if not _world.pending_script_wait().is_empty():
		return
	if _text_box != null and _text_box.visible:
		_advance_script_input()
		return
	if StringName(_world.pending_script_input().get("type", &"")) in [&"choice", &"menu"]:
		_script_prompt = "Host choice required: call choose_script_input(choice)"
		_refresh_labels()
		return
	if _world.pending_runtime_request().is_empty():
		_show_script_results(_world.run_event_queue(true))
		return
	var pending_request: Dictionary = _world.pending_runtime_request()
	if StringName(pending_request.get("kind", &"")) == &"audio_requested":
		var audio_results: Array = _handle_audio_request(pending_request)
		if not audio_results.is_empty():
			_show_script_results(audio_results)
		return
	var pending_save: Gen2SaveData = _injected_save if _injected_save != null \
		else _selected_runtime_save()
	var host_result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {"ok": true}, pending_save, _injected_save == null, _encounter_random
	)
	if bool(host_result.get("ok", false)):
		_show_script_results(host_result.get("results", []))
		return
	_script_prompt = "Host unavailable: %s" % String(host_result.get("reason", "unknown"))
	_refresh_labels()


## Scaffolding that reaches parts of the world no cartridge control does: the
## rods, the phone list, the renderer switch and a snapshot write. Debug builds
## only, so a shipped game offers exactly the eight buttons the hardware had.
## Every method behind them stays public, which is how the preview tools drive
## the same paths without a key press.
func _handle_debug_key(event: InputEvent) -> bool:
	if not Gen2DebugKeys.enabled():
		return false
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return false
	match key.keycode:
		KEY_1:
			select_fishing_rod(0)
		KEY_2:
			select_fishing_rod(1)
		KEY_3:
			select_fishing_rod(2)
		KEY_F:
			start_fishing()
		KEY_P:
			_open_phone_list()
		KEY_V:
			cycle_world_renderer()
		KEY_F5:
			var saved: Dictionary = persist_world_snapshot()
			_script_prompt = "World saved" if bool(saved.get("ok", false)) else "Save failed"
			_refresh_labels()
		_:
			return false
	return true


## Whether the overworld itself is idle. An event reaches the renderer only
## after the same overlays, pauses and hosts have each refused it.
func _renderer_input_free() -> bool:
	return _world != null and not _overlay_open() and not _field_move_text \
		and _oak_pc_pages.is_empty() and _trainer_approach.is_empty() \
		and not _world.phone_ring_active() and not _world.fishing_busy() \
		and not _world.script_input_waiting()


## Public driver for screenshot tooling and scene tests.
func move_player(direction: Vector2i) -> bool:
	if _world == null or _overlay_open() or _world.fishing_busy() \
		or _field_move_text or not _oak_pc_pages.is_empty() \
		or _world.phone_ring_active() \
		or not _trainer_approach.is_empty() or _world.script_busy() \
		or _world.player_step_in_progress():
		return false
	var movement: Dictionary = _world.player_input_move(direction)
	if not bool(movement.get("ok", false)):
		## A push bumps the player and starts the boulder, so the step reports
		## blocked while the map still changed. MovementFunction_Strength plays
		## SFX_STRENGTH here, not the menu that set the flag.
		if movement.has("boulder_pushed"):
			_play_sfx(SFX_STRENGTH)
			if _renderer != null:
				_renderer.refresh()
			_refresh_labels()
		return false
	## A whirlpool spins the player rather than moving them, so nothing a completed
	## step owes applies: no warp, no encounter, no repel step.
	## A turn on the spot costs a facing and four frames and nothing else, so it
	## owes none of what a completed step owes.
	if movement.get("kind", &"") == &"turn":
		if _renderer != null:
			_renderer.refresh()
		_refresh_labels()
		return true
	if movement.get("kind", &"") == &"forced_turn":
		if _renderer != null:
			_renderer.refresh()
		_refresh_labels()
		return true
	return _after_player_move(movement)


## Everything a completed step owes the rest of the screen: contextual audio, the
## warp it may have landed on, the redraw, then sight, phone and encounter checks
## in that order. Shared with the forced-tile path, which reaches it without a
## key press.
func _after_player_move(movement: Dictionary) -> bool:
	if movement.get("kind", &"") == &"ledge_hop":
		_play_ledge_hop_sfx()
	## .ExitWater calls PlayMapMusic before the step, which is what drops the
	## surfing track once the player is walking again.
	if movement.get("kind", &"") == &"exit_water":
		_play_current_map_music()

	var transition: Dictionary = movement
	## CheckTileEvent gates warps on nothing, so surfing onto a warp tile and the
	## step back onto land both reach one.
	if movement.get("kind", &"") in [
		&"move", &"ledge_hop", &"water_move", &"exit_water", &"forced_move",
	]:
		transition = _world.try_warp()
	if _renderer != null:
		if bool(transition.get("ok", false)) and transition.get("kind", &"") != &"move":
			_animation.configure(_world, time_of_day)
			_renderer.set_world(_world, _animation)
			_play_current_map_music()
		else:
			_renderer.refresh()
	_refresh_labels()
	var sight_results: Array = _world.dispatch_sight_events()
	if sight_results.is_empty():
		sight_results = _world.dispatch_script_events()
	if not sight_results.is_empty():
		_show_script_results(sight_results)
		return true
	var special_attempt: Dictionary = _world.try_special_phone_call()
	var special_results: Array = special_attempt.get("results", [])
	if bool(special_attempt.get("attempted", false)) and not special_results.is_empty():
		_show_script_results(special_results)
		return true
	var phone_attempt: Dictionary = _world.try_receive_phone_call(_encounter_random)
	var phone_results: Array = phone_attempt.get("results", [])
	if bool(phone_attempt.get("attempted", false)) and not phone_results.is_empty():
		_show_script_results(phone_results)
		return true
	_show_script_results([])
	var encounter: Dictionary = _world.encounter_request(_encounter_random)
	if not encounter.is_empty():
		_start_battle_request({
			"kind": &"battle_requested",
			"values": encounter["values"],
			"encounter": encounter.duplicate(true),
		})
	return true


## Public driver for the production NPC/object interaction path.
func interact() -> bool:
	if _world == null or _overlay_open() \
		or _field_move_text or not _oak_pc_pages.is_empty() \
		or _world.phone_ring_active() or _world.fishing_busy():
		return false
	var results: Array = _world.interact()
	if results.is_empty():
		return false
	_show_script_results(results)
	return true


func move_right() -> void:
	move_player(Vector2i.RIGHT)


func move_left() -> void:
	move_player(Vector2i.LEFT)


func move_up() -> void:
	move_player(Vector2i.UP)


func move_down() -> void:
	move_player(Vector2i.DOWN)


func world_snapshot() -> Dictionary:
	return {
		"map": _world.map_id() if _world != null else Vector2i(-1, -1),
		"player_cell": _world.player_cell if _world != null else Vector2i(-1, -1),
		"origin_cell": _world.visible_origin_cell() if _world != null else Vector2i(-1, -1),
		"collision": _world.collision_code_at(_world.player_cell) if _world != null else -1,
		"movement_mode": _world.movement_mode if _world != null else Gen2WorldAPI.MOVEMENT_WALK,
		"visible_objects": _world.visible_objects().size() if _world != null else 0,
		"just_battled": _world.state.just_battled() if _world != null else false,
		"fishing_state": _world.fishing_state() if _world != null else Gen2WorldFishing.STATE_IDLE,
		"swarm_map": _world.state.swarm_map() if _world != null else Vector2i(-1, -1),
		"roaming_count": _world.state.roaming_mons().size() if _world != null else 0,
		"owned_rods": _world.available_fishing_rods() if _world != null else [],
		"owned_balls": Gen2WorldPartyHost.owned_capture_balls(_world) if _world != null else [],
		"clock": _clock.snapshot() if _clock != null else {},
		"battle_active": _battle_host != null,
		"script_prompt": _script_prompt,
	}


func world_save_snapshot() -> Gen2WorldSnapshot:
	return _world.snapshot() if _world != null else null


## Writes the current map, player and mutable world state back to the selected
## project save. Injected test saves are updated in memory instead of touching
## the user's save directory.
func persist_world_snapshot() -> Dictionary:
	if _world == null or _data == null:
		return {"ok": false, "reason": &"missing_world"}
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	if save == null:
		return {"ok": false, "reason": &"missing_save"}
	save.world = _world.snapshot()
	if _injected_save != null:
		return {"ok": true, "kind": &"world_snapshot_saved", "save": save}
	return Gen2SaveStore.save(save, _data)


## `GameTimer`, one call per hardware frame. The play timer belongs to the save
## rather than to the world, since the cartridge keeps it in wPlayerData.
##
## Two source gates decide whether it counts, and neither is `_overlay_open()`:
## a battle, the pack and the start menu all keep counting. `wGameTimerPaused`
## is cleared for `Script_halloffame` alone (engine/overworld/scripting.asm:2318)
## and `wGameLogicPaused` is set by Bill's PC (engine/pokemon/bills_pc.asm:2000)
## and by saving, which costs no frames here.
func _advance_game_time_frame() -> void:
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	if save == null or save.game_time == null:
		return
	if _hall_of_fame_host != null:
		return
	save.game_time.advance_frames(1)


## Deterministic driver for tests and screenshot tooling. The live scene uses
## the same clock through _process(delta).
func advance_world_time(seconds: float) -> Array:
	if _clock == null or _world == null:
		return []
	var ticks: Array = _clock.advance(seconds, _world)
	_world.set_world_clock(_clock.day, _clock.hour, _clock.minute)
	if not ticks.is_empty():
		_update_time_of_day()
		_refresh_labels()
	return ticks


## Public host boundary for a time/radio tick. The imported roaming graph is
## advanced once, while swarm state remains the state transaction's result.
func advance_world_schedule() -> Dictionary:
	if _world == null:
		return {"ok": false, "reason": &"missing_map"}
	var result: Dictionary = _world.advance_schedule(_encounter_random)
	_refresh_labels()
	return result


func _update_time_of_day() -> void:
	if _clock == null or _world == null:
		return
	var next_time_of_day: int = _clock.time_of_day()
	if next_time_of_day == time_of_day:
		return
	time_of_day = next_time_of_day
	_world.set_object_time(_clock.hour, time_of_day)
	if _animation != null:
		_animation.configure(_world, time_of_day)
	if _renderer != null:
		_renderer.set_time_of_day(_render_time_of_day())


## Public screenshot driver for the scripted emote state and renderer path.
func preview_emote() -> void:
	if _world == null or _renderer == null:
		return
	var actors: Array = _world.visible_objects()
	if actors.is_empty():
		_script_prompt = "No visible object for emote preview"
		_refresh_labels()
		return
	var object: Gen2WorldObject = actors[0]
	object.set_emote(0, true)
	_renderer.refresh()
	_script_prompt = "Debug emote preview"
	_refresh_labels()


## Public screenshot driver. It executes the first active scripted event in
## source order, which keeps the debug image tied to imported map data.
func preview_script_event() -> void:
	if _world == null:
		return
	for source: String in ["coord_events", "bg_events", "objects"]:
		for event: Dictionary in _world.current_map.events.get(source, []):
			var cell := Vector2i(int(event.get("x", -1)), int(event.get("y", -1)))
			var results: Array = _world.dispatch_events(cell, true)
			if not results.is_empty():
				_show_script_results(results)
				return
	_script_prompt = "No active script at this map's event records"
	_refresh_labels()


## Public screenshot driver for the party submenu's field-move entry. Grants the
## move's badge and teaches it to the first party member, then injects that save
## so persistence stays off, the way preview_party_transaction() does.
func preview_field_move() -> void:
	_preview_field_move(Gen2WorldFieldMove.MOVE_CUT, Gen2WorldFieldMove.BADGE_HIVE)


## The rest of that sequence, one step per call: the first chooses the submenu's
## field-move entry and shows its message, the second acknowledges it and
## commits.
func preview_field_move_use() -> void:
	if _field_move_text:
		_acknowledge_field_move_text()
		return
	preview_field_move()
	if _party_host != null:
		_party_host.handle_button(Gen2Button.A)


## The same pair for Surf. The scene must be opened on a map where the player
## starts beside water and facing it; the Cut preview has the matching
## requirement of a cuttable tile.
func preview_surf() -> void:
	_preview_field_move(Gen2WorldFieldMove.MOVE_SURF, Gen2WorldFieldMove.BADGE_FOG)


func preview_surf_use() -> void:
	if _field_move_text:
		_acknowledge_field_move_text()
		return
	preview_surf()
	if _party_host != null:
		_party_host.handle_button(Gen2Button.A)


## And for Whirlpool, which needs the scene opened facing a COLL_WHIRLPOOL cell:
## Dragon's Den B1F, Route 41 or Route 27 are the only maps that carry one.
func preview_whirlpool() -> void:
	_preview_field_move(Gen2WorldFieldMove.MOVE_WHIRLPOOL, Gen2WorldFieldMove.BADGE_GLACIER)


func preview_whirlpool_use() -> void:
	if _field_move_text:
		_acknowledge_field_move_text()
		return
	preview_whirlpool()
	if _party_host != null:
		_party_host.handle_button(Gen2Button.A)


## And for Strength, which unlike the other three needs nothing in front of the
## player: .TryStrength checks the badge and stops. To watch a boulder actually
## move, open the scene on a map that has one and press a direction into it after
## the second call; Cianwood Gym (22/5) and Ice Path B1F are the reachable ones.
func preview_strength() -> void:
	_preview_field_move(Gen2WorldFieldMove.MOVE_STRENGTH, Gen2WorldFieldMove.BADGE_PLAIN)


func preview_strength_use() -> void:
	if _field_move_text:
		_acknowledge_field_move_text()
		return
	preview_strength()
	if _party_host != null:
		_party_host.handle_button(Gen2Button.A)


func _preview_field_move(move: int, badge: int) -> void:
	if _world == null or _data == null:
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Field move preview needs a party"
		_refresh_labels()
		return
	(save.party[0] as Gen2SaveMon).moves[0] = move
	_injected_save = save
	_world.state.set_engine_flag(Gen2WorldState.badge_flag(
		badge, Gen2WorldState.is_crystal_profile(_data)
	))
	_open_embedded_party()
	if _party_host == null:
		return
	_party_host.handle_button(Gen2Button.A)


## Public screenshot driver for the scene-free party item transaction. It uses a
## development save and keeps the result in memory, so the image demonstrates
## the real host boundary without changing a user's selected slot.
func preview_party_transaction() -> void:
	if _world == null or _data == null:
		return
	var preview_save: Gen2SaveData = Gen2SaveStore.create_development_save(_data, 0)
	if preview_save == null or preview_save.party.is_empty():
		_script_prompt = "Party transaction preview unavailable"
		_refresh_labels()
		return
	preview_save.world = _world.snapshot()
	var item_result: Dictionary = _world.state.apply_changes(
		{}, {}, {"items": {Gen2WorldPartyHost.ITEM_POTION: 1}}
	)
	if not bool(item_result.get("ok", false)):
		_script_prompt = "Party transaction preview unavailable"
		_refresh_labels()
		return
	preview_save.party[0].hp = 1
	var result: Dictionary = Gen2WorldPartyHost.use_item(
		_world, preview_save, Gen2WorldPartyHost.ITEM_POTION, 0, false
	)
	var preview_caption: String = ""
	if bool(result.get("ok", false)):
		var healed: int = int(result.get("healed", 0))
		_script_prompt = "POTION +%d HP" % healed
		preview_caption = "%s   PARTY TX: POTION +%d HP" % [_data.title(), healed]
	else:
		_script_prompt = "Party transaction failed: %s" % String(result.get("reason", "unknown"))
	_refresh_labels()
	if not preview_caption.is_empty():
		_caption.text = preview_caption


## Public screenshot driver for the pack's item use. It grants a Potion and hurts
## the first party member on an injected save, so nothing persists, then advances
## one menu step per call: Pack, the item, USE, the target, the result.
func preview_pack_use() -> void:
	if _world == null or _data == null:
		return
	if _start_menu_host != null:
		_start_menu_host.handle_button(Gen2Button.A)
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Pack preview needs a party"
		_refresh_labels()
		return
	(save.party[0] as Gen2SaveMon).hp = 1
	_injected_save = save
	_world.state.apply_changes({}, {}, {"items": {Gen2WorldPartyHost.ITEM_POTION: 1}})
	_open_start_menu()
	if _start_menu_host == null:
		return
	while _start_menu_host.get("_menu").selected_kind() != Gen2WorldStartMenu.ITEM_PACK:
		_start_menu_host.handle_button(Gen2Button.DOWN)
	_start_menu_host.handle_button(Gen2Button.A)


## Public screenshot driver for the start menu itself: opens it, and then walks
## the cursor one entry per call, which is what photographs MENU ACCOUNT's own
## description line under the list.
func preview_start_menu() -> void:
	if _world == null or _data == null:
		return
	if _start_menu_host == null:
		_injected_save = _embedded_party_save()
		_open_start_menu()
		return
	_start_menu_host.handle_button(Gen2Button.DOWN)


## Public screenshot driver for `TossMenu`. Grants a stack on an injected save
## so nothing persists, then advances one menu step per call: Pack, the item,
## TOSS, the quantity dial, the yes/no and the result.
func preview_pack_toss() -> void:
	if _world == null or _data == null:
		return
	if _start_menu_host != null:
		## The submenu opens on USE, so the cursor is walked onto TOSS before the
		## press that chooses it. Every other step is a plain A.
		if _start_menu_host.get("_mode") == Gen2StartMenuScreen.Mode.PACK_ITEM:
			var actions: Array = _start_menu_host.get("_item_actions")
			for index: int in actions.size():
				if StringName((actions[index] as Dictionary).get("action", &"")) \
					== Gen2WorldPack.ACTION_TOSS:
					_start_menu_host.set("_item_cursor", index)
					break
		_start_menu_host.handle_button(Gen2Button.A)
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null:
		_script_prompt = "Toss preview needs a save"
		_refresh_labels()
		return
	_injected_save = save
	_world.state.apply_changes({}, {}, {"items": {Gen2WorldPartyHost.ITEM_POTION: 5}})
	_open_start_menu()
	if _start_menu_host == null:
		return
	while _start_menu_host.get("_menu").selected_kind() != Gen2WorldStartMenu.ITEM_PACK:
		_start_menu_host.handle_button(Gen2Button.DOWN)
	_start_menu_host.handle_button(Gen2Button.A)


## Public screenshot driver for ForgetMove. It fills the first party member's
## four move slots and grants a TM or HM that member can learn, on an injected
## save so nothing persists, then advances one menu step per call: Pack, the
## TM/HM, USE, YES, the party member, ForgetMove's ask, and the move list.
##
## The granted item is whichever TM or HM this species can actually learn, since
## a development save's first member is whatever the cache holds; a species that
## can learn none reports that rather than opening a menu it cannot fill.
func preview_move_forget() -> void:
	if _world == null or _data == null:
		return
	if _start_menu_host != null:
		_start_menu_host.handle_button(Gen2Button.A)
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Forget preview needs a party"
		_refresh_labels()
		return
	var mon: Gen2SaveMon = save.party[0]
	var item: int = _teachable_tmhm_for(mon.species)
	if item <= 0:
		_script_prompt = "Forget preview: this species learns no TM or HM"
		_refresh_labels()
		return
	# Four moves the species need not know legitimately: ForgetMove is reached by
	# the slot count alone, and this is a screenshot rather than a save.
	mon.moves = [1, 2, 3, 4]
	mon.pp = [10, 10, 10, 10]
	_injected_save = save
	_world.state.apply_changes({}, {}, {"items": {item: 1}})
	_open_start_menu()
	if _start_menu_host == null:
		return
	while _start_menu_host.get("_menu").selected_kind() != Gen2WorldStartMenu.ITEM_PACK:
		_start_menu_host.handle_button(Gen2Button.DOWN)
	_start_menu_host.handle_button(Gen2Button.A)
	# The pack opens on the ITEM pocket, and the granted item is in the TM/HM
	# one. The guard bounds the walk in case no such pocket is built.
	var guard: int = Gen2WorldPack.POCKET_ORDER.size() + 1
	while guard > 0 and _previewed_pocket() != Gen2WorldPack.TYPE_TM_HM:
		_start_menu_host.handle_button(Gen2Button.RIGHT)
		guard -= 1


func _previewed_pocket() -> int:
	var pockets: Array = _start_menu_host.get("_pack_pockets")
	var index: int = int(_start_menu_host.get("_pack_pocket_index"))
	if index < 0 or index >= pockets.size():
		return -1
	return int((pockets[index] as Dictionary).get("pocket", -1))


## The first TM or HM item [param species] can learn, or 0. Walks the numbers
## rather than the items, since the run is not contiguous.
func _teachable_tmhm_for(species: int) -> int:
	var count: int = _data.tmhm_moves().size()
	for number: int in range(1, count + 1):
		var move: int = _data.tmhm_move(number)
		if move > 0 and Gen2WorldTMHM.can_learn(_data, species, move):
			return RomLayout.item_for_tmhm_number(number, count)
	return 0


## Public screenshot driver for the battle-request host path. It starts the
## same request shape emitted by [Gen2WorldScriptRunner], without pretending a
## map event was present in the selected development map.
func preview_battle_request() -> void:
	_start_battle_request({
		"kind": &"battle_requested",
		"values": {"kind": &"wild", "pokemon": 16, "level": 5},
	})


## Public screenshot driver for the real wild capture bridge. It adds one
## development Master Ball, starts an imported wild encounter, and leaves the
## production battle overlay on its throw message.
func preview_capture() -> void:
	if _world == null:
		return
	var added: Dictionary = _world.state.apply_changes(
		{}, {}, {"items": {Gen2WorldPartyHost.ITEM_MASTER_BALL: 1}}
	)
	if not bool(added.get("ok", false)):
		return
	var encounter: Dictionary = _world.encounter_request(_encounter_random, true)
	if encounter.is_empty():
		_script_prompt = "No wild encounter for capture preview"
		_refresh_labels()
		return
	_start_battle_request({
		"kind": &"battle_requested",
		"values": encounter["values"],
		"encounter": encounter.duplicate(true),
	})
	call_deferred("_preview_capture_throw")


func _preview_capture_throw() -> void:
	if _battle_host == null or _battle_host.capture_target() == null:
		call_deferred("_preview_capture_throw")
		return
	var balls: Array[int] = _battle_host.available_capture_balls()
	var master_index: int = balls.find(Gen2WorldPartyHost.ITEM_MASTER_BALL)
	if master_index < 0:
		return
	if not bool(_battle_host.begin_capture().get("ok", false)):
		return
	_battle_host.select_capture_ball(master_index)
	_battle_host.throw_capture_ball()
	_battle_host.finish()


## Public screenshot driver for a resolved imported wild encounter. It uses the
## current standing terrain and skips only the rate roll, leaving slot and surf
## level selection on the production resolver path.
func preview_wild_encounter() -> void:
	if _world == null:
		return
	var encounter: Dictionary = _world.encounter_request(_encounter_random, true)
	if encounter.is_empty():
		_script_prompt = "No normal encounter table for this map and terrain"
		_refresh_labels()
		return
	_start_battle_request({
		"kind": &"battle_requested",
		"values": encounter["values"],
		"encounter": encounter.duplicate(true),
	})


## Public screenshot and scene-test driver for the production fishing path.
## The caller can advance the cast and bite pauses with Space, Enter or Z.
func preview_fishing() -> void:
	_position_for_fishing_preview()
	start_fishing(true)


## Public screenshot driver for the complete fishing-to-battle host path.
func preview_fishing_battle() -> void:
	if _world == null:
		return
	_position_for_fishing_preview()
	var started: Dictionary = start_fishing(true)
	if not bool(started.get("ok", false)):
		return
	var bite: Dictionary = _world.advance_fishing()
	if StringName(bite.get("kind", &"")) != &"fishing_bite":
		_handle_fishing_result(bite)
		return
	_handle_fishing_result(_world.advance_fishing())


func _position_for_fishing_preview() -> void:
	if _world.current_map == null or _world.current_map.fish_group <= 0:
		return
	var size: Vector2i = _world.map_size_cells()
	var directions: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if _world.collision_permission_at(cell) != Gen2WorldCollision.LAND_TILE:
				continue
			for direction: Vector2i in directions:
				if _world.collision_permission_at(cell + direction) != Gen2WorldCollision.WATER_TILE:
					continue
				_world.player_cell = cell
				_world.player_facing = _facing_for_direction(direction)
				if _renderer != null:
					_renderer.refresh()
				return


func _facing_for_direction(direction: Vector2i) -> int:
	match direction:
		Vector2i.UP:
			return Gen2WorldSprite.FACING_UP
		Vector2i.LEFT:
			return Gen2WorldSprite.FACING_LEFT
		Vector2i.RIGHT:
			return Gen2WorldSprite.FACING_RIGHT
	return Gen2WorldSprite.FACING_DOWN


func select_fishing_rod(index: int) -> Dictionary:
	if _world == null:
		return {"ok": false, "reason": &"missing_map"}
	var rods: Array[StringName] = _world.available_fishing_rods()
	if index < 0 or index >= rods.size():
		return {"ok": false, "reason": &"invalid_rod"}
	_selected_rod = rods[index]
	_script_prompt = "Selected %s. F: cast" % Gen2WorldFishing.rod_label(_selected_rod)
	_refresh_labels()
	return {"ok": true, "rod": _selected_rod}


func start_fishing(force_encounter: bool = false) -> Dictionary:
	if _world == null:
		return {"ok": false, "reason": &"missing_map"}
	var result: Dictionary = _world.fishing_request(
		_selected_rod, _encounter_random, force_encounter
	)
	if not bool(result.get("ok", false)):
		_script_prompt = "Fishing failed: %s" % String(result.get("reason", "unknown"))
		_refresh_labels()
		return result
	_script_prompt = "Cast %s. A: wait" % String(result.get("rod_label", "ROD"))
	_refresh_labels()
	return result


func _handle_fishing_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_script_prompt = "Fishing stopped: %s" % String(result.get("reason", "unknown"))
		_refresh_labels()
		return
	match StringName(result.get("kind", &"")):
		&"fishing_no_bite":
			_script_prompt = "Nothing was hooked. F: cast again"
		&"fishing_bite":
			_script_prompt = "A bite! Press A to reel in"
		&"battle_requested":
			_start_battle_request(result)
			return
		_:
			_script_prompt = "Fishing: %s" % String(result.get("kind", "unknown"))
	_refresh_labels()


func _start_battle_request(request: Dictionary) -> void:
	if _battle_host != null or _data == null:
		return
	var values: Dictionary = request.get("values", {})
	var tutorial: bool = bool(values.get("tutorial", false))
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	_active_battle_save = save
	_active_battle_persist = save != null and _injected_save == null
	var host: Gen2BattleScreen = BATTLE_SCENE.instantiate() as Gen2BattleScreen
	host.set_data(_data)
	host.set_time_of_day(time_of_day)
	# The clock's row is what the battle's own heals read; the drawn row is what
	# a renderer staging the fight on this map has to match, so the context
	# carries that one.
	host.set_world_context(Gen2BattleWorldContext.capture(_world, _render_time_of_day()))
	if _world != null and not tutorial:
		host.set_capture_balls(
			Gen2WorldPartyHost.owned_capture_balls(_world), _world.state.items()
		)
	host.set_meta("world_battle_request", {
		"request": request.duplicate(true),
		"save": save,
		"player_badges": _world.state.badge_mask(Gen2WorldState.is_crystal_profile(_data)) \
			if _world != null and _world.state != null else 0,
	})
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 10
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	host.battle_finished.connect(_on_battle_finished)
	host.enemy_seen.connect(_on_enemy_seen)
	if not tutorial:
		host.capture_requested.connect(_on_capture_requested)
	_battle_host = host
	_script_prompt = "Battle in progress"
	_refresh_labels()


## `LoadEnemyMon`'s dex write. The flag lands on live world state, so the next
## snapshot carries it exactly as the cartridge's next save does.
func _on_enemy_seen(species: int) -> void:
	if _world != null and _world.state != null:
		_world.state.set_species_seen(species)


func _on_capture_requested(ball: int) -> void:
	if _battle_host == null or _world == null or _data == null:
		return
	var save: Gen2SaveData = _active_battle_save
	if save == null:
		save = Gen2SaveStore.create_development_save(_data, 0)
		if save != null:
			save.world = _world.snapshot()
		_active_battle_save = save
		_active_battle_persist = false
	var target: Gen2BattleMon = _battle_host.capture_target()
	var result: Dictionary = Gen2WorldPartyHost.capture_wild(
		_world, save, target, ball, _encounter_random, 0, _active_battle_persist
	)
	_battle_host.complete_capture(result)
	_refresh_labels()


func _on_battle_finished(result: Dictionary) -> void:
	var host: Gen2BattleScreen = _battle_host
	_battle_host = null
	if host != null:
		host.queue_free()
	if _world == null:
		return
	var pay_day_money: int = int(result.get("pay_day_money", 0))
	if pay_day_money > 0 and StringName(result.get("outcome", &"")) == Gen2WorldBattleAdapter.OUTCOME_WON:
		_world.state.apply_changes({}, {}, {"money": {
			0: mini(_world.state.money(0) + pay_day_money, Gen2WorldInventory.MAX_MONEY),
		}})
	var resumed: Array = _world.complete_runtime_request(result)
	if resumed.is_empty():
		if StringName(result.get("outcome", &"")) == Gen2WorldBattleAdapter.OUTCOME_CAUGHT:
			var capture: Dictionary = result.get("capture", {})
			var species: Dictionary = _data.species(int(capture.get("species", 0)))
			_script_prompt = "Caught %s" % String(species.get("name", "UNKNOWN"))
		else:
			_script_prompt = "Battle finished: %s" % String(
				result.get("outcome", result.get("reason", "unknown"))
			)
	else:
		_show_script_results(resumed)
	_active_battle_save = null
	_active_battle_persist = false
	_refresh_labels()


func _advance_script_input() -> void:
	if _text_box.is_revealing():
		_text_box.finish()
		return
	if _text_box.advance():
		return
	_text_box.visible = false
	_script_prompt = ""
	_show_script_results(_world.run_event_queue(true))
	_refresh_labels()


func _start_trainer_approach(request: Dictionary) -> void:
	if _world == null or not _trainer_approach.is_empty():
		return
	var values: Dictionary = request.get("values", {})
	var direction_value: Variant = values.get("direction", Vector2i.ZERO)
	var direction: Vector2i = direction_value if direction_value is Vector2i else Vector2i.ZERO
	var plan: Dictionary = _world.start_trainer_approach(
		int(values.get("object_index", -1)), direction, int(values.get("distance", 0))
	)
	if not bool(plan.get("ok", false)):
		var failed: Array = _world.complete_runtime_request({
			"ok": false,
			"reason": plan.get("reason", &"trainer_approach_failed"),
			"details": plan.duplicate(true),
		})
		_show_script_results(failed)
		return
	_trainer_approach = {
		"object_index": int(plan.get("object_index", -1)),
		"path": plan.get("path", []).duplicate(true),
		"path_index": 0,
		"emote_frames": int(plan.get("emote_frames", Gen2WorldAPI.TRAINER_SHOCK_FRAMES)),
		"movement_delay": 1,
	}
	_script_prompt = "Trainer spotted you"
	if _renderer != null:
		_renderer.refresh()
	_refresh_labels()


## One hardware frame of `SeenByTrainerScript`'s presentation: the shock emote's
## own count, the movement delay, then one planned cell at a time. The object's
## step_frames_remaining (set by
## [method Gen2WorldAPI.advance_trainer_approach_step]) is spent by the same
## frame, while step_offset() still gives the renderer 16-frame interpolation.
func _advance_trainer_approach() -> void:
	if _world == null:
		_trainer_approach = {}
		return
	var emote_frames: int = int(_trainer_approach.get("emote_frames", 0))
	if emote_frames > 0:
		_trainer_approach["emote_frames"] = emote_frames - 1
		if _renderer != null:
			_renderer.refresh()
		return
	var movement_delay: int = int(_trainer_approach.get("movement_delay", 0))
	if movement_delay > 0:
		_trainer_approach["movement_delay"] = movement_delay - 1
		return
	var object_index: int = int(_trainer_approach.get("object_index", -1))
	var stepping_object: Gen2WorldObject = _world.objects[object_index] \
		if _world != null and object_index >= 0 and object_index < _world.objects.size() else null
	if stepping_object != null and stepping_object.tick_step():
		if _renderer != null:
			_renderer.refresh()
		return
	var path: Array = _trainer_approach.get("path", [])
	var path_index: int = int(_trainer_approach.get("path_index", 0))
	if path_index < path.size():
		var direction_value: Variant = path[path_index]
		if not direction_value is Vector2i:
			_finish_trainer_approach(false, &"invalid_trainer_path", {})
			return
		var direction: Vector2i = direction_value
		var step: Dictionary = _world.advance_trainer_approach_step(
			object_index, direction
		)
		if not bool(step.get("ok", false)):
			_finish_trainer_approach(false, step.get("reason", &"trainer_approach_failed"), step)
			return
		_trainer_approach["path_index"] = path_index + 1
		if _renderer != null:
			_renderer.refresh()
		return
	var finished: Dictionary = _world.finish_trainer_approach(object_index)
	if not bool(finished.get("ok", false)):
		_finish_trainer_approach(false, finished.get("reason", &"trainer_approach_failed"), finished)
		return
	_finish_trainer_approach(true, &"", finished)


func _finish_trainer_approach(ok: bool, reason: StringName, details: Dictionary) -> void:
	var request: Dictionary = _trainer_approach.duplicate(true)
	_trainer_approach = {}
	if _world == null:
		return
	var result: Dictionary = {"ok": ok}
	if not ok:
		result["reason"] = reason
		result["details"] = details.duplicate(true)
	else:
		result["object_index"] = int(request.get("object_index", -1))
		result["path"] = request.get("path", []).duplicate(true)
	var resumed: Array = _world.complete_runtime_request(result)
	_show_script_results(resumed)


func _open_service_host() -> void:
	if _service_host != null or _world == null or _data == null:
		return
	var host: Gen2WorldServiceScreen = SERVICE_SCENE.instantiate() as Gen2WorldServiceScreen
	if host == null:
		_script_prompt = "Service scene unavailable"
		_refresh_labels()
		return
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	add_child(host)
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	var persist: bool = save != null and _injected_save == null
	if not host.open_pending(_world, _data, save, persist):
		host.queue_free()
		_script_prompt = "Service request unavailable"
		_refresh_labels()
		return
	host.completed.connect(_on_service_completed)
	_service_host = host
	_script_prompt = "Service host open"
	_refresh_labels()


## Opens the induction sequence `halloffame` asks for. Public so the screenshot
## tool and the scene tests can reach it without replaying the whole route.
##
## The party is the active save's, so an injected or development save inducts
## whatever it is carrying. A cache with no font answers nothing rather than
## drawing an empty screen.
func open_hall_of_fame() -> void:
	if _hall_of_fame_host != null or _world == null or _data == null:
		return
	var save: Gen2SaveData = _active_party_save()
	if save == null:
		_script_prompt = "Hall of Fame needs a save"
		_refresh_labels()
		return
	var pages: Array = Gen2HallOfFame.pages(_data, save, _world.state)
	## No anchor preset: this is a child of the 160x144 Gen2Screen and sizes
	## itself in native pixels, the way the story picture does.
	var host := Gen2HallOfFameScreen.new()
	host.set_context(_data, pages)
	host.closed.connect(_on_hall_of_fame_closed)
	host.rating_reached.connect(_on_hall_of_fame_rating)
	_hall_of_fame_host = host
	_screen.display(host)
	if _hall_of_fame_host == null:
		## set_context() with nothing to show closes on _ready(), which runs as
		## soon as the node enters the tree.
		return
	_play_hall_of_fame_music()
	_script_prompt = "Hall of Fame"
	_refresh_labels()


## HallOfFame calls SaveGameData before the animation, so the record is written
## whether or not the player watches it. This writes at the end instead: the
## screen owns no save state, and the snapshot it would write mid-sequence is
## the same one.
func _on_hall_of_fame_closed() -> void:
	var host: Gen2HallOfFameScreen = _hall_of_fame_host
	_hall_of_fame_host = null
	if host != null:
		host.queue_free()
	var written: Dictionary = persist_world_snapshot()
	_script_prompt = "Hall of Fame recorded" if bool(written.get("ok", false)) \
		else "Hall of Fame not saved: %s" % String(written.get("reason", "unknown"))
	_play_current_map_music()
	if _renderer != null:
		_renderer.refresh()
	_refresh_labels()
	## `AnimateHallOfFame` is followed by `farcall Credits` with the `wStatusFlags`
	## byte pushed before the Hall of Fame bit went into it, so this pair is never
	## skippable however many times it has been seen.
	open_credits(false)


## `ProfOaksPCRating`'s tail: `PlayMusic MUSIC_NONE` stops the induction music
## where it stands, without a fade, and the rating's own sound plays over the
## silence it leaves.
func _on_hall_of_fame_rating(sfx: int) -> void:
	if _audio_player != null:
		_audio_player.fade_out()
	_play_sfx(sfx)


## `Script_credits`, which farcalls `RedCredits` and then ends the script.
##
## [param skippable] is the `wStatusFlags` byte `Credits` is handed: `RedCredits`
## passes the live one, which by Red has the Hall of Fame bit in it, while
## `HallOfFame` pushes the byte before setting that bit, so the induction's own
## credits cannot be skipped even on a second run.
func open_credits(skippable: bool = true) -> void:
	if _credits_host != null or _world == null or _data == null:
		return
	var host := Gen2CreditsScreen.new()
	if not host.set_context(_data, skippable):
		host.free()
		_script_prompt = "The credits are not in this cache"
		_refresh_labels()
		return
	host.closed.connect(_on_credits_closed)
	host.music_requested.connect(_play_credits_music)
	host.music_fade_requested.connect(_fade_credits_music)
	_credits_host = host
	_screen.display(host)
	_script_prompt = "Credits"
	_refresh_labels()


func _on_credits_closed() -> void:
	var host: Gen2CreditsScreen = _credits_host
	_credits_host = null
	if host != null:
		host.queue_free()
	_play_current_map_music()
	if _renderer != null:
		_renderer.refresh()
	_script_prompt = ""
	_refresh_labels()


## `.music`, whose `PlayMusic MUSIC_NONE` and `DelayFrame` in front of the real
## call are what stop the induction's own track first.
func _play_credits_music(music: int) -> void:
	if _audio_player == null or _data == null:
		return
	_audio_player.fade_out()
	var record: Dictionary = _data.world_audio(&"music", music)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"map_music", _audio_assets())


## `.end`'s `wMusicFade`, which the overworld's own player owns the way it owns
## the Hall of Fame rating's sound.
func _fade_credits_music(_music: int, frames: int) -> void:
	if _audio_player != null:
		_audio_player.fade_out(frames)


func _play_hall_of_fame_music() -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.world_audio(&"music", MUSIC_HALL_OF_FAME)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"map_music", _audio_assets())


## Public driver for screenshot tooling and scene tests, mirroring
## _open_service_host()'s shape. The START branch in _handle_button() is the
## normal path.
func _open_start_menu() -> void:
	_open_start_menu_host(Callable())


## `SelectMenu` and `GiveTakePartyMonItem`'s GIVE both open the pack this screen
## already hosts, so they share its opener and hand it their own entry point.
## [param entry] is called with the host once it is on screen.
func _open_start_menu_host(entry: Callable) -> void:
	if _world == null or _data == null or _overlay_open() or _field_move_text \
		or not _oak_pc_pages.is_empty() \
		or not _trainer_approach.is_empty() or _world.script_busy() \
		or _world.phone_ring_active() or _world.fishing_busy():
		return
	var host: Gen2StartMenuScreen = START_MENU_SCENE.instantiate() as Gen2StartMenuScreen
	if host == null:
		_script_prompt = "Start menu scene unavailable"
		_refresh_labels()
		return
	# An injected save is a development or test one, so its item use stays in
	# memory the same way preview_party_transaction() does.
	host.set_party_context(
		_injected_save if _injected_save != null else _selected_runtime_save(),
		_injected_save == null
	)
	if not host.open(
		_world, _data, Callable(self, "persist_world_snapshot"), _start_menu_cursor
	):
		host.queue_free()
		_script_prompt = "Start menu unavailable"
		_refresh_labels()
		return
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	add_child(host)
	host.action_chosen.connect(_on_start_menu_action)
	host.closed.connect(_on_start_menu_closed)
	_start_menu_host = host
	_script_prompt = "Start menu open"
	if entry.is_valid():
		entry.call(host)
	_refresh_labels()


## `SelectMenu`, which is the whole of what the SELECT button does in the
## overworld: the registered item, or the text saying one may be registered.
func open_select_menu() -> void:
	_open_start_menu_host(func(host: Gen2StartMenuScreen) -> void:
		host.open_registered_item()
	)


func _on_start_menu_action(kind: StringName) -> void:
	var host: Gen2StartMenuScreen = _start_menu_host
	_start_menu_host = null
	if host != null:
		_start_menu_cursor = host.cursor()
		host.queue_free()
	_reopen_start_menu = kind in [
		Gen2WorldStartMenu.ITEM_POKEMON, Gen2WorldStartMenu.ITEM_POKEGEAR,
		Gen2WorldStartMenu.ITEM_PLAYER, Gen2WorldStartMenu.ITEM_POKEDEX,
	]
	match kind:
		Gen2WorldStartMenu.ITEM_POKEMON:
			_open_embedded_party()
		Gen2WorldStartMenu.ITEM_POKEGEAR:
			_open_pokegear()
		Gen2WorldStartMenu.ITEM_PLAYER:
			_open_trainer_card()
		Gen2WorldStartMenu.ITEM_POKEDEX:
			_open_pokedex()
	_refresh_labels()


## `.Reopen`, which every `StartMenu_*` handler that returns 0 lands on. The
## cursor is `wBattleMenuCursorPosition` and was kept when the menu closed.
func _reopen_start_menu_if_due() -> void:
	if not _reopen_start_menu:
		return
	_reopen_start_menu = false
	_open_start_menu()


## `StartMenu_Pokedex`'s `farcall Pokedex`. Its own B returns to the overworld,
## which is where DEXSTATE_EXIT lands too.
func _open_pokedex() -> void:
	if _pokedex_host != null or _data == null:
		return
	var host := Gen2PokedexScreen.new()
	if not host.open(_data, _world, _pokedex_prev_entry):
		host.free()
		_script_prompt = "The Pokedex needs a cache that carries its entries"
		_refresh_labels()
		return
	host.z_index = 10
	add_child(host)
	host.closed.connect(_on_pokedex_closed)
	host.cry_requested.connect(_on_pokedex_cry_requested)
	_pokedex_host = host
	_script_prompt = "Pokedex open"
	_refresh_labels()


## The entry screen's CRY button. `PlayCry` is an effect, not music, so it goes
## through the same player a script's `cry` command does.
func _on_pokedex_cry_requested(species: int) -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.species_cry(species)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"cry", _audio_assets())


func _on_pokedex_closed() -> void:
	var host: Gen2PokedexScreen = _pokedex_host
	_pokedex_host = null
	if host != null:
		_pokedex_prev_entry = host.previous_entry()
		host.queue_free()
	_script_prompt = "Pokedex closed"
	_reopen_start_menu_if_due()
	_refresh_labels()


## `ProfOaksPCBoot` (engine/events/prof_oaks_pc.asm): the level line, `Rate`'s
## seen and owned counts, and the rating those counts band into, each waiting for
## A or B. The special writes nothing, so the script has already run on to its
## own `end` and there is nothing to resume.
func open_prof_oaks_pc() -> void:
	if _world == null or _data == null or not _oak_pc_pages.is_empty():
		return
	var boot: Dictionary = Gen2ProfOaksPC.boot(_data, _world.state)
	if boot.is_empty():
		_script_prompt = "Prof Oak's PC needs a cache that carries its ratings"
		_refresh_labels()
		return
	_oak_pc_pages = boot["pages"]
	_oak_pc_sfx = int(boot["sfx"])
	_show_prof_oaks_pc_page()


func _show_prof_oaks_pc_page() -> void:
	if _text_box == null or _text_box.font == null:
		_close_prof_oaks_pc()
		return
	_apply_text_box_options()
	_text_box.show_text(String(_oak_pc_pages[0]))
	_text_box.visible = true
	## `ProfOaksPCBoot` plays the sound `Rate` chose after the rating is printed,
	## not before it.
	if _oak_pc_pages.size() == 1 and _oak_pc_sfx >= 0:
		_play_sfx(_oak_pc_sfx)
	_script_prompt = "A: continue"
	_refresh_labels()


func _advance_prof_oaks_pc() -> void:
	if _text_box == null:
		_close_prof_oaks_pc()
		return
	if _text_box.is_revealing():
		_text_box.finish()
		return
	if _text_box.advance():
		return
	_oak_pc_pages.remove_at(0)
	if _oak_pc_pages.is_empty():
		_close_prof_oaks_pc()
		return
	_show_prof_oaks_pc_page()


## `ProfOaksPCBoot` holds the script on the cartridge and nothing holds it here,
## so `OaksLab`'s own goodbye text was already queued behind these pages. It is
## put up now rather than dropped.
func _close_prof_oaks_pc() -> void:
	_oak_pc_pages = []
	_oak_pc_sfx = -1
	var pending: Dictionary = _world.pending_script_input() if _world != null else {}
	if StringName(pending.get("type", &"")) == &"text" \
		and _text_box != null and _text_box.font != null:
		_apply_text_box_options()
		_text_box.show_text(String(pending.get("text", "")))
		_text_box.visible = true
		_script_prompt = "A: advance text"
	else:
		if _text_box != null:
			_text_box.visible = false
		_script_prompt = ""
	_refresh_labels()


## `StartMenu_Status`'s `farcall TrainerCard`. Its own B returns to the
## overworld, which is where the source's own `ret` lands too.
func _open_trainer_card() -> void:
	if _trainer_card_host != null or _data == null:
		return
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	var host := Gen2TrainerCardScreen.new()
	if not host.open(_data, _world, save):
		host.free()
		_script_prompt = "The trainer card needs a save and a cache that carries it"
		_refresh_labels()
		return
	host.z_index = 10
	## Into the hardware screen, the way the Hall of Fame goes: the card sizes
	## itself in the 160x144 space, so adding it to this Control instead would
	## draw it at one window pixel per hardware pixel in the corner.
	_screen.display(host)
	host.closed.connect(_on_trainer_card_closed)
	_trainer_card_host = host
	_script_prompt = "Trainer card open"
	_refresh_labels()


func _on_trainer_card_closed() -> void:
	var host: Gen2TrainerCardScreen = _trainer_card_host
	_trainer_card_host = null
	if host != null:
		host.queue_free()
	_script_prompt = "Trainer card closed"
	_reopen_start_menu_if_due()
	_refresh_labels()


func _on_start_menu_closed() -> void:
	var host: Gen2StartMenuScreen = _start_menu_host
	_start_menu_host = null
	if host != null:
		_start_menu_cursor = host.cursor()
		host.queue_free()
	_script_prompt = "Start menu closed"
	_refresh_labels()


## The save the embedded party view shows: the injected or selected one, or a
## development party when neither exists.
func _embedded_party_save() -> Gen2SaveData:
	var save: Gen2SaveData = _injected_save if _injected_save != null \
		else _selected_runtime_save()
	return save if save != null else Gen2SaveStore.create_development_save(_data, 0)


func _open_embedded_party() -> void:
	if _party_host != null or _world == null or _data == null:
		return
	var host: Gen2PartyScreen = PARTY_SCENE.instantiate() as Gen2PartyScreen
	if host == null:
		_script_prompt = "Party scene unavailable"
		_refresh_labels()
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null:
		host.queue_free()
		_script_prompt = "Party requires a validated save"
		_refresh_labels()
		return
	host.set_context(_data, save, true)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	host.closed.connect(_on_party_closed)
	host.action_chosen.connect(_on_party_action)
	_party_host = host
	_script_prompt = "Party open"
	_refresh_labels()


func _on_party_closed(_result: Dictionary) -> void:
	var host: Gen2PartyScreen = _party_host
	_party_host = null
	if host != null:
		host.queue_free()
	_script_prompt = "Party closed"
	_reopen_start_menu_if_due()
	_refresh_labels()


## MonMenu_Cut and MonMenu_Surf share a shape: the party menu closes first, then
## the field-move function runs and either queues its script or pushes its own
## refusal text. Both refusals and the success message go through the hardware
## text box, and nothing changes until the acknowledge, matching Script_Cut
## reaching CutDownTreeOrGrass and UsedSurfScript reaching SurfStartStep only
## after their text.
func _on_party_action(action: Dictionary) -> void:
	var host: Gen2PartyScreen = _party_host
	_party_host = null
	if host != null:
		host.queue_free()
	# `PokemonActionSubmenu`'s `.quit` reaches `ExitAllMenus`, so a field move
	# leaves the overworld rather than reopening the menu behind it.
	_reopen_start_menu = false
	if _world == null:
		_refresh_labels()
		return
	if StringName(action.get("kind", &"")) == &"mon_item":
		_run_mon_item_action(action)
		return
	if StringName(action.get("kind", &"")) != &"field_move":
		_refresh_labels()
		return
	match int(action.get("move", 0)):
		Gen2WorldFieldMove.MOVE_CUT:
			var cut: Dictionary = _world.cut_request()
			if not bool(cut.get("ok", false)):
				_show_field_move_text(_cut_refusal(StringName(cut.get("reason", &""))))
				return
			_show_field_move_text("%s used CUT!" % String(action.get("name", "")))
		Gen2WorldFieldMove.MOVE_SURF:
			var surf: Dictionary = _world.surf_request(_party_species(int(action.get("slot", -1))))
			if not bool(surf.get("ok", false)):
				_show_field_move_text(_surf_refusal(StringName(surf.get("reason", &""))))
				return
			_show_field_move_text("%s used SURF!" % String(action.get("name", "")))
		Gen2WorldFieldMove.MOVE_STRENGTH:
			var strength: Dictionary = _world.strength_request(
				_party_species(int(action.get("slot", -1)))
			)
			if not bool(strength.get("ok", false)):
				_show_field_move_text(
					_strength_refusal(StringName(strength.get("reason", &"")))
				)
				return
			_show_field_move_text("%s used STRENGTH!" % String(action.get("name", "")))
		Gen2WorldFieldMove.MOVE_WHIRLPOOL:
			var whirlpool: Dictionary = _world.whirlpool_request()
			if not bool(whirlpool.get("ok", false)):
				_show_field_move_text(
					_whirlpool_refusal(StringName(whirlpool.get("reason", &"")))
				)
				return
			_show_field_move_text("%s used WHIRLPOOL!" % String(action.get("name", "")))
		Gen2WorldFieldMove.MOVE_WATERFALL:
			var waterfall: Dictionary = _world.waterfall_request()
			if not bool(waterfall.get("ok", false)):
				_show_field_move_text(
					_waterfall_refusal(StringName(waterfall.get("reason", &"")))
				)
				return
			_show_field_move_text("%s used WATERFALL!" % String(action.get("name", "")))
		Gen2WorldFieldMove.MOVE_FLASH:
			var flash: Dictionary = _world.flash_request()
			if not bool(flash.get("ok", false)):
				_show_field_move_text(_flash_refusal(StringName(flash.get("reason", &""))))
				return
			_show_field_move_text("%s used FLASH!" % String(action.get("name", "")))
		Gen2WorldFieldMove.MOVE_HEADBUTT:
			var headbutt: Dictionary = _world.headbutt_request()
			if not bool(headbutt.get("ok", false)):
				_show_field_move_text(
					_headbutt_refusal(StringName(headbutt.get("reason", &"")))
				)
				return
			## _UseHeadbuttText is "did a HEADBUTT!", not the "used" the other five share.
			_show_field_move_text("%s did a HEADBUTT!" % String(action.get("name", "")))
		Gen2WorldFieldMove.MOVE_ROCK_SMASH:
			var rock_smash: Dictionary = _world.rock_smash_request()
			if not bool(rock_smash.get("ok", false)):
				_show_field_move_text(
					_rock_smash_refusal(StringName(rock_smash.get("reason", &"")))
				)
				return
			_show_field_move_text("%s used ROCK SMASH!" % String(action.get("name", "")))
		_:
			_show_field_move_text("Can't use that here.")


## GetSurfType reads wPartySpecies at wCurPartyMon; the submenu action carries
## that slot. Zero when no save or slot answers, which is no species and so the
## ordinary surf sprite.
func _party_species(slot: int) -> int:
	var save: Gen2SaveData = _active_party_save()
	if save == null or slot < 0 or slot >= save.party.size():
		return 0
	var member: Variant = save.party[slot]
	return int((member as Gen2SaveMon).species) if member is Gen2SaveMon else 0


## engine/events/overworld.asm's refusal texts, verbatim from
## data/text/common_2.asm. A reason without a source text falls back to
## _CantUseItemText, which is the source's own generic field-move refusal.
func _cut_refusal(reason: StringName) -> String:
	match reason:
		&"badge_required":
			return "Sorry! A new BADGE is required."
		&"nothing_to_cut":
			return "There's nothing to CUT here."
	return "Can't use that here."


func _surf_refusal(reason: StringName) -> String:
	match reason:
		&"badge_required":
			return "Sorry! A new BADGE is required."
		&"already_surfing":
			return "You're already SURFING."
		&"cannot_surf":
			return "You can't SURF here."
	return "Can't use that here."


## .FailWhirlpool has no text of its own: it calls FieldMoveFailed, so every
## refusal but the badge falls back to _CantUseItemText. Cut is the exception,
## not the rule.
func _whirlpool_refusal(reason: StringName) -> String:
	if reason == &"badge_required":
		return "Sorry! A new BADGE is required."
	return "Can't use that here."


## .TryWaterfall refuses through FieldMoveFailed, whose text is the generic
## _CantUseItemText, so only the badge has a line of its own; CheckMapCanWaterfall
## has no message at all.
func _waterfall_refusal(reason: StringName) -> String:
	if reason == &"badge_required":
		return "Sorry! A new BADGE is required."
	return "Can't use that here."


## .CheckUseFlash has no refusal text of its own for a lit map: it reaches
## FieldMoveFailed, which is _CantUseItemText. Only the badge has a line.
func _flash_refusal(reason: StringName) -> String:
	if reason == &"badge_required":
		return "Sorry! A new BADGE is required."
	return "Can't use that here."


## TryRockSmashFromMenu refuses through FieldMoveFailed too, so its only text is
## the generic one. AskRockSmashScript's _MaySmashText belongs to the other
## path, where the runner owns it.
func _rock_smash_refusal(_reason: StringName) -> String:
	return "Can't use that here."


## TryHeadbuttFromMenu refuses through FieldMoveFailed, so every refusal is
## _CantUseItemText. There is no badge branch to add one: Headbutt is gated on
## CheckPartyMove and the faced tile alone.
func _headbutt_refusal(_reason: StringName) -> String:
	return "Can't use that here."


## .TryStrength's only refusal is CheckBadge's, since it checks nothing else;
## anything past it is this project's own guard, not a cartridge branch.
func _strength_refusal(reason: StringName) -> String:
	if reason == &"badge_required":
		return "Sorry! A new BADGE is required."
	return "Can't use that here."


## `GiveTakePartyMonItem`'s two answers. TAKE is a bag transaction and says so in
## the map's own text box; GIVE needs an item, which is `.GiveItem`'s pack over
## the Pokemon already chosen.
func _run_mon_item_action(action: Dictionary) -> void:
	var slot: int = int(action.get("slot", -1))
	if StringName(action.get("option", &"")) == Gen2PartyScreen.OPTION_GIVE:
		_open_start_menu_host(func(host: Gen2StartMenuScreen) -> void:
			host.open_give(slot)
		)
		return
	var save: Gen2SaveData = _embedded_party_save()
	var result: Dictionary = Gen2WorldBagHost.take_from_party(
		_world, save, slot, _injected_save == null
	)
	var name: String = String(action.get("name", ""))
	if bool(result.get("ok", false)):
		_show_field_move_text(Gen2WorldPack.took_text(name, String(result.get("name", ""))))
		return
	match StringName(result.get("reason", &"")):
		&"not_holding":
			_show_field_move_text(Gen2WorldPack.not_holding_text(name))
		&"bag_full":
			_show_field_move_text(Gen2WorldPack.storage_full_text())
		_:
			_show_field_move_text(
				"%s could not hand that over (%s)." % [
					name, String(result.get("reason", "")),
				]
			)


func _show_field_move_text(text: String) -> void:
	_field_move_text = true
	if _text_box != null and _text_box.font != null:
		_apply_text_box_options()
		_text_box.show_text(text)
		_text_box.visible = true
	_script_prompt = "A: continue"
	_refresh_labels()


## The acknowledge that closes a field-move message. A staged move commits here
## rather than when it was resolved, because Script_Cut only reaches
## CutDownTreeOrGrass after UseCutText and UsedSurfScript only reaches
## SurfStartStep after its waitbutton. A refusal has nothing staged and just
## closes.
func _acknowledge_field_move_text() -> void:
	_field_move_text = false
	if _text_box != null:
		_text_box.visible = false
	if _world == null:
		_script_prompt = ""
		_refresh_labels()
		return
	if not _world.pending_cut().is_empty():
		_commit_field_move(_world.complete_cut(), "Cut")
		return
	if not _world.pending_surf().is_empty():
		_commit_field_move(_world.complete_surf(), "Surf")
		return
	if not _world.pending_whirlpool().is_empty():
		_commit_field_move(_world.complete_whirlpool(), "Whirlpool")
		return
	if not _world.pending_strength().is_empty():
		_commit_field_move(_world.complete_strength(), "Strength")
		return
	if not _world.pending_waterfall().is_empty():
		_commit_field_move(_world.complete_waterfall(), "Waterfall")
		return
	if not _world.pending_flash().is_empty():
		_commit_field_move(_world.complete_flash(), "Flash")
		return
	if not _world.pending_headbutt().is_empty():
		_commit_field_move(_world.complete_headbutt(_encounter_random), "Headbutt")
		return
	if not _world.pending_rock_smash().is_empty():
		_commit_field_move(_world.complete_rock_smash(_encounter_random), "Rock Smash")
		return
	_script_prompt = ""
	_refresh_labels()


## Cut plays SFX_PLACE_PUZZLE_PIECE_DOWN, Whirlpool plays SFX_SURF, Waterfall
## plays SFX_BUBBLEBEAM and Surf changes the music, so each commit reports its
## own audio. Strength is the one that plays nothing: Script_UsedStrength has no
## PlaySFX, because SFX_STRENGTH belongs to the boulder that moves later, not to
## the flag being set, and neither does Flash. All six redraw anyway, since the
## party overlay closed over the map.
func _commit_field_move(applied: Dictionary, label: String) -> void:
	if bool(applied.get("ok", false)):
		match StringName(applied.get("kind", &"")):
			&"surf_applied":
				_play_current_map_music()
			&"whirlpool_applied":
				_play_sfx(SFX_WHIRLPOOL)
			&"strength_applied":
				pass
			&"waterfall_applied":
				_play_sfx(SFX_WATERFALL)
			&"flash_used":
				# BlindingFlash has no sound of its own: it fades to white,
				# swaps the palette set and fades back. The palette is the whole
				# of what changed, so the renderer is told the new row rather
				# than just asked to redraw.
				if _renderer != null:
					_renderer.set_time_of_day(_render_time_of_day())
				if _animation != null:
					_animation.configure(_world, _render_time_of_day())
			&"headbutt_applied":
				_play_sfx(SFX_HEADBUTT_TREE)
			&"rock_smash_applied":
				_play_sfx(SFX_STRENGTH)
			_:
				_play_sfx(SFX_CUT)
		if _renderer != null:
			_renderer.refresh()
		_script_prompt = label
		if StringName(applied.get("kind", &"")) == &"headbutt_applied":
			_finish_headbutt(applied)
			return
		if StringName(applied.get("kind", &"")) == &"rock_smash_applied":
			_finish_rock_smash(applied)
			return
	else:
		_script_prompt = "%s failed: %s" % [label, String(applied.get("reason", "unknown"))]
	_refresh_labels()


## HeadbuttScript after ShakeHeadbuttTree: TreeMonEncounter either sets
## wScriptVar and reaches startbattle, or falls to .no_battle, which is
## HeadbuttNothingText and a waitbutton. The tree is unchanged either way.
func _finish_headbutt(applied: Dictionary) -> void:
	var encounter: Variant = applied.get("encounter", {})
	if not encounter is Dictionary or (encounter as Dictionary).is_empty():
		_show_field_move_text("Nope. Nothing…")
		return
	_refresh_labels()
	_start_battle_request({
		"kind": &"battle_requested",
		"values": (encounter as Dictionary)["values"],
		"encounter": (encounter as Dictionary).duplicate(true),
	})


## RockSmashScript after the rock is gone: RockMonEncounter either reaches
## startbattle or the script ends. Unlike Headbutt there is no nothing-text,
## because `.done` is a bare `end`.
func _finish_rock_smash(applied: Dictionary) -> void:
	var encounter: Variant = applied.get("encounter", {})
	if not encounter is Dictionary or (encounter as Dictionary).is_empty():
		_refresh_labels()
		return
	_refresh_labels()
	_start_battle_request({
		"kind": &"battle_requested",
		"values": (encounter as Dictionary)["values"],
		"encounter": (encounter as Dictionary).duplicate(true),
	})


func _open_phone_list() -> void:
	_open_service_overlay(&"phone_list")


## The Pokegear's own card list, which is what the start menu's POKEGEAR entry
## reaches. The phone list is one card behind it, not the whole device.
func _open_pokegear() -> void:
	_open_service_overlay(&"pokegear")


func _open_service_overlay(kind: StringName) -> void:
	if _service_host != null or _world == null or _data == null:
		return
	var label: String = "Pokegear" if kind == &"pokegear" else "Phone list"
	var host: Gen2WorldServiceScreen = SERVICE_SCENE.instantiate() as Gen2WorldServiceScreen
	if host == null:
		_script_prompt = "%s scene unavailable" % label
		_refresh_labels()
		return
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	add_child(host)
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	var persist: bool = save != null and _injected_save == null
	var opened: bool = host.open_pokegear(_world, _data, save, persist) if kind == &"pokegear" \
		else host.open_phone_list(_world, _data, save, persist)
	if not opened:
		host.queue_free()
		_script_prompt = "%s unavailable" % label
		_refresh_labels()
		return
	host.completed.connect(_on_service_completed)
	_service_host = host
	_script_prompt = "%s open" % label
	_refresh_labels()


func _on_service_completed(results: Array) -> void:
	var host: Gen2WorldServiceScreen = _service_host
	_service_host = null
	if host != null:
		host.queue_free()
	# The radio card writes wMapMusic, so what plays after the Pokegear closes is
	# whichever station was left tuned, or the map's own track when none was.
	_play_current_map_music()
	_show_script_results(results)
	_reopen_start_menu_if_due()


func _show_script_results(results: Array) -> void:
	var waiting: bool = false
	var failed: bool = false
	var map_changed: bool = false
	var clock_changed: bool = false
	var recovered: bool = false
	var recovery_prompt: String = ""
	for result: Dictionary in results:
		Gen2ModHost.publish(Gen2ModHost.CHANNEL_WORLD, result)
		if result.has("clock"):
			clock_changed = true
		var status: StringName = StringName(result.get("status", &""))
		if status == &"phone_ring":
			waiting = true
			var ring: Dictionary = result.get("event", {})
			var contact: Dictionary = ring.get("contact", {})
			_script_prompt = "Phone ringing: %s" % _phone_contact_label(contact)
		elif status == &"waiting":
			waiting = true
			var event: Dictionary = result.get("event", {})
			var event_type: StringName = StringName(event.get("type", &""))
			if event_type == &"text" and _text_box != null and _text_box.font != null:
				## Prof Oak's PC is the one special that draws on its own and
				## whose script runs on past it, so its pages are shown first and
				## this text waits behind them.
				if _oak_pc_pages.is_empty():
					_apply_text_box_options()
					_text_box.show_text(String(event.get("text", "")))
					_text_box.visible = true
				_script_prompt = "A: advance text"
			elif event_type == &"button":
				if _text_box != null:
					_text_box.visible = true
				_script_prompt = "A: continue script"
			elif event_type == &"wait":
				_script_prompt = "Script waiting on %s" % String(event.get("wait", &"frames"))
			elif event_type in [&"choice", &"menu"]:
				_open_service_host()
				break
			elif event_type == &"runtime_request":
				var request: Dictionary = event.get("request", {})
				if StringName(request.get("kind", &"")) == &"trainer_approach_requested":
					_start_trainer_approach(request)
					break
				if StringName(request.get("kind", &"")) == &"battle_requested":
					_start_battle_request(request)
					break
				if StringName(request.get("kind", &"")) == &"catch_tutorial_requested":
					_start_battle_request(request)
					break
				if StringName(request.get("kind", &"")) == &"swarm_requested":
					var values: Dictionary = request.get("values", {})
					var swarm_results: Array = _world.complete_runtime_request({
						"ok": true,
						"active": true,
						"map_group": int(values.get("map_group", -1)),
						"map_number": int(values.get("map_number", -1)),
					})
					_show_script_results(swarm_results)
					return
				if StringName(request.get("kind", &"")) in [
					&"pokemon_requested", &"trade_requested",
				]:
					_script_prompt = "Party transaction: press A to confirm"
					continue
				if StringName(request.get("kind", &"")) in [
					&"mart_requested", &"phone_call_requested",
					&"special_phone_call_requested", &"town_map_requested",
					&"apricorn_selection_requested", &"pc_requested",
				]:
					_open_service_host()
					break
				if StringName(request.get("kind", &"")) == &"audio_requested":
					var audio_results: Array = _handle_audio_request(request)
					if not audio_results.is_empty():
						_show_script_results(audio_results)
					break
				_script_prompt = "Runtime request: %s, press A to acknowledge" % String(
					request.get("kind", "effect")
				)
		elif status == &"recovered":
			recovered = true
		elif not bool(result.get("ok", false)):
			failed = true
			_script_prompt = "Script stopped: %s" % String(result.get("reason", "unknown"))
		for result_event: Dictionary in result.get("events", []):
			if result_event.get("type", &"") == &"presentation_special_applied" \
				and StringName(result_event.get("kind", &"")) == &"prof_oaks_pc_boot":
				open_prof_oaks_pc()
			elif result_event.get("type", &"") == &"hall_of_fame_requested":
				## An event, not a runtime request: `halloffame` commits its flag
				## and runs on, and the source's own `end` is the next command,
				## so nothing is waiting to be resumed when this opens.
				open_hall_of_fame()
			elif result_event.get("type", &"") == &"credits_requested":
				open_credits()
			elif result_event.get("type", &"") == &"field_move_confirmed":
				## `iftrue Script_Cut` and its four counterparts. The move is the
				## host's, and it is the same staged request and acknowledge the
				## party submenu reaches, so the two ways in stay one path.
				_use_prompted_field_move(int(result_event.get("move", 0)),
					int(result_event.get("slot", -1)))
			elif result_event.get("type", &"") == &"pokemon_picture_requested":
				_show_story_picture(int(result_event.get("pokemon", 0)))
			elif result_event.get("type", &"") == &"pokemon_picture_closed":
				_hide_story_picture()
			elif result_event.get("type", &"") == &"screen_shake_requested":
				if _effects != null:
					_effects.start_screen_shake(
						int(result_event.get("strength", 0)),
						&"screen_shake",
						result_event,
					)
				_apply_world_effect_offset()
			elif result_event.get("type", &"") == &"tree_shake_requested":
				if _effects != null:
					_effects.start_tree_shake(result_event)
				_apply_world_effect_offset()
			elif result_event.get("type", &"") in [
				&"rock_smash_effect_requested",
				&"movement_command_requested",
			]:
				_script_prompt = "Applied: %s" % String(result_event.get("type", &"effect"))
			elif result_event.get("type", &"") == &"warp":
				map_changed = true
			elif result_event.get("type", &"") == &"world_clock_changed":
				clock_changed = true
			elif result_event.get("type", &"") == &"battle_map_reload_requested":
				map_changed = true
			elif result_event.get("type", &"") == &"blackout":
				recovered = true
				var recovery: Variant = result_event.get("recovery", {})
				var source: StringName = StringName(
					recovery.get("source", &"save") if recovery is Dictionary else &"save"
				)
				recovery_prompt = (
					"Blackout recovered from the development party"
					if source == &"development"
					else "Blackout recovered from the last saved party"
				)
			elif result_event.get("type", &"") in [
				&"item_changed", &"money_changed", &"coins_changed", &"movement_blocked",
				&"movement_failed",
			]:
				_script_prompt = "Applied: %s" % String(result_event.get("type", &"effect"))
	if recovered and not recovery_prompt.is_empty():
		_script_prompt = recovery_prompt
	elif not waiting and not failed:
		_script_prompt = ""
	if clock_changed:
		_sync_host_clock()
	if _renderer != null:
		if map_changed:
			_world.reload_current_map()
			_animation.configure(_world, time_of_day)
			_renderer.set_world(_world, _animation)
			_renderer.set_time_of_day(_render_time_of_day())
			_play_current_map_music()
		else:
			_renderer.refresh()
	_refresh_labels()


func _apply_world_effect_offset() -> void:
	if _screen == null:
		return
	var effect_offset: Vector2 = _effects.offset() if _effects != null else Vector2.ZERO
	_screen.position = _screen_base_position + effect_offset


## The yes half of an Ask*Script. Each move's own request is what decides
## whether anything happens, exactly as in the submenu path; the difference is
## that a refusal here is silent, because AskCutScript's `.CheckMap` failure
## falls straight to `closetext` with no text of its own.
func _use_prompted_field_move(move: int, slot: int) -> void:
	if _world == null:
		return
	var requested: Dictionary = {}
	var label: String = ""
	match move:
		Gen2WorldFieldMove.MOVE_CUT:
			requested = _world.cut_request()
			label = "used CUT!"
		Gen2WorldFieldMove.MOVE_SURF:
			requested = _world.surf_request(_party_species(slot))
			label = "used SURF!"
		Gen2WorldFieldMove.MOVE_WHIRLPOOL:
			requested = _world.whirlpool_request()
			label = "used WHIRLPOOL!"
		Gen2WorldFieldMove.MOVE_WATERFALL:
			requested = _world.waterfall_request()
			label = "used WATERFALL!"
		Gen2WorldFieldMove.MOVE_HEADBUTT:
			requested = _world.headbutt_request()
			label = "did a HEADBUTT!"
	if not bool(requested.get("ok", false)):
		return
	_show_field_move_text("%s %s" % [_prompted_field_move_name(slot), label])


## GetPartyNickname, which every one of these scripts calls before its own text.
func _prompted_field_move_name(slot: int) -> String:
	var save: Gen2SaveData = _active_party_save()
	if save == null or slot < 0 or slot >= save.party.size():
		return "#MON"
	var member: Variant = save.party[slot]
	return _mon_display_name(member as Gen2SaveMon) if member is Gen2SaveMon else "#MON"


func _show_story_picture(species: int) -> void:
	if _data == null:
		return
	var pic: Dictionary = _data.species_pic(species)
	if pic.is_empty():
		return
	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic,
		_data.palette(species)
	)
	_hide_story_picture()
	_story_picture_backdrop = ColorRect.new()
	_story_picture_backdrop.color = Color.WHITE
	_story_picture_backdrop.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_story_picture_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.display(_story_picture_backdrop)
	_story_picture = TextureRect.new()
	_story_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_story_picture.texture = ImageTexture.create_from_image(image)
	_story_picture.size = image.get_size()
	_story_picture.position = (
		Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT) - Vector2(image.get_size())
	) / 2.0
	_story_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.display(_story_picture)


func _hide_story_picture() -> void:
	if _story_picture != null:
		_story_picture.queue_free()
		_story_picture = null
	if _story_picture_backdrop != null:
		_story_picture_backdrop.queue_free()
		_story_picture_backdrop = null


func _sync_host_clock() -> void:
	if _clock == null or _world == null:
		return
	var clock: Dictionary = _world.world_clock()
	_clock.day = int(clock.get("day", _clock.day))
	_clock.hour = int(clock.get("hour", _clock.hour))
	_clock.minute = int(clock.get("minute", _clock.minute))


func _handle_audio_request(request: Dictionary) -> Array:
	if _audio_player == null:
		_script_prompt = "Audio unavailable: player is not ready"
		_refresh_labels()
		return []
	var kind: StringName = StringName(request.get("values", {}).get("kind", &""))
	if kind == &"sound_wait":
		if _audio_player.effect_playing():
			_audio_waiting = true
			_script_prompt = "Waiting for sound effect"
			_refresh_labels()
			return []
		var finished: Dictionary = Gen2WorldHost.complete_runtime_request(_world, {"ok": true})
		return finished.get("results", []) if bool(finished.get("ok", false)) else []
	var resolve_request: Dictionary = request.duplicate(true)
	if not resolve_request.has("source") and _world != null:
		resolve_request["source"] = _world.pending_runtime_request().get("source", {})
	var resolved: Dictionary = Gen2WorldHost.resolve_runtime_request(_world, resolve_request)
	if not bool(resolved.get("ok", false)):
		if kind == &"encounter_music":
			var skipped: Array = _world.complete_runtime_request({
				"ok": true, "audio_played": false,
				"audio_unavailable": resolved.get("reason", &"audio_data_unavailable"),
			})
			return skipped
		_script_prompt = "Audio unavailable: %s" % String(resolved.get("reason", "unknown"))
		_refresh_labels()
		return []
	var record: Dictionary = resolved.get("data", {}).get("audio", {})
	if kind == &"music_fadeout":
		record["fade_time"] = int(request.get("values", {}).get("fade_time", 0))
	var playback: Dictionary = _audio_player.play_record(
		record, kind, _audio_assets(),
		bool(request.get("values", {}).get("restart", false))
	)
	if not bool(playback.get("ok", false)):
		if kind == &"encounter_music":
			var skipped: Array = _world.complete_runtime_request({
				"ok": true, "audio_played": false,
				"audio_unavailable": playback.get("reason", &"audio_playback_failed"),
			})
			return skipped
		_script_prompt = "Audio unavailable: %s" % String(playback.get("reason", "unknown"))
		_refresh_labels()
		return []
	var completed: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {"ok": true, "audio_played": bool(playback.get("played", false))}
	)
	if not bool(completed.get("ok", false)):
		_script_prompt = "Audio completion failed: %s" % String(
			completed.get("reason", "unknown")
		)
		_refresh_labels()
		return []
	return completed.get("results", [])


func _audio_assets() -> Dictionary:
	return {
		"wave_samples": _data.world_audio_asset(&"wave_samples") if _data != null else {},
		"drumkits": _data.world_audio_asset(&"drumkits") if _data != null else {},
	}


## Plays whatever `wMapMusic` currently holds. `Gen2WorldAPI` owns the write,
## following PlayMapMusic and its SpecialMapMusic surf override on map entry, so
## the track a tuned radio station left there survives until the player leaves
## the map. Restarting a piece that is already playing is a presentation
## difference from the source, which compares before it restarts.
func _play_current_map_music() -> void:
	if _audio_player == null or _data == null or _world == null or _world.current_map == null:
		return
	var track: int = _world.state.map_music()
	var record: Dictionary = _data.world_audio(&"music", track)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"map_music", _audio_assets())


func _play_ledge_hop_sfx() -> void:
	_play_sfx(SFX_JUMP_OVER_LEDGE)


func _play_sfx(index: int) -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.world_audio(&"sfx", index)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"sound", _audio_assets())


## The save whose party a queued script's VAR_PARTYCOUNT read and CheckPokerus
## special should see. A battle in progress may hold its own save, including a
## synthesized development one from a fallback capture, so it takes priority
## over the screen's ordinary selected save.
func _active_party_save() -> Gen2SaveData:
	if _active_battle_save != null:
		return _active_battle_save
	return _injected_save if _injected_save != null else _selected_runtime_save()


## Mirrors the active save's party size and Pokerus state onto the world so a
## queued script can answer VAR_PARTYCOUNT and CheckPokerus without the
## scene-free world owning a save. Cleared, not zeroed, when no save is
## selected, so a missing wiring fails loudly instead of reading an invented
## empty party.
func _refresh_party_summary() -> void:
	if _world == null:
		return
	var save: Gen2SaveData = _active_party_save()
	if save == null:
		_world.clear_party_summary()
		_world.clear_player_id()
		_world.set_player_name("")
		return
	## wPlayerID rides the same refresh: it belongs to the save, and
	## GetTreeScore reads it the way VAR_PARTYCOUNT reads the party mirror.
	_world.set_player_id(save.player_id)
	_world.set_player_name(save.player_name)
	_world.set_player_gender(save.gender == Gen2SaveData.GENDER_FEMALE)
	var has_pokerus: bool = false
	var species: Array[int] = []
	var moves: Array = []
	var names: Array = []
	var eggs: Array = []
	for member: Variant in save.party:
		if member is Gen2SaveMon:
			var mon: Gen2SaveMon = member as Gen2SaveMon
			if (int(mon.pokerus) & 0x0F) != 0:
				has_pokerus = true
			species.append(int(mon.species))
			# CheckPartyMove walks every slot's four move slots; zeroes are empty
			# slots, not moves, so they are dropped rather than searched.
			var mon_moves: Array = []
			for move: int in mon.moves:
				if move != 0:
					mon_moves.append(move)
			moves.append(mon_moves)
			names.append(_mon_display_name(mon))
			eggs.append(mon.is_egg)
	_world.set_party_summary(save.party.size(), has_pokerus, species, moves, names, eggs)


## GetPartyNickname's answer for one slot, following the party screen's own rule:
## the stored nickname, or the species name when the save carries none.
func _mon_display_name(mon: Gen2SaveMon) -> String:
	if not mon.nickname.is_empty():
		return mon.nickname
	return String(_data.species(mon.species).get("name", "")) if _data != null else ""


func _refresh_labels() -> void:
	if _world == null or _data == null:
		return
	_refresh_party_summary()
	_caption.text = "%s   map %d/%d   cell %d,%d" % [
		_data.title(), _world.current_map.group, _world.current_map.number,
		_world.player_cell.x, _world.player_cell.y,
	]
	var ring: Dictionary = _world.pending_phone_ring()
	if _world.phone_ring_active() and not ring.is_empty():
		_caption.text += "   PHONE RING %d/%d: %s" % [
			int(ring.get("ring", 0)), int(ring.get("rings", 0)),
			_phone_contact_label(ring.get("contact", {})),
		]
	var rods: Array[StringName] = _world.available_fishing_rods()
	var rod_labels: Array[String] = []
	for rod: StringName in rods:
		rod_labels.append(Gen2WorldFishing.rod_label(rod))
	var owned: String = ", ".join(rod_labels) if not rod_labels.is_empty() else "none"
	var ball_labels: Array[String] = []
	if _world != null and _world.state != null:
		for ball: int in Gen2WorldPartyHost.owned_capture_balls(_world):
			ball_labels.append("%s x%d" % [_data.item_name(ball), _world.state.item_quantity(ball)])
	var balls: String = ", ".join(ball_labels) if not ball_labels.is_empty() else "none"
	var clock_text: String = "%02d:%02d" % [_clock.hour, _clock.minute] if _clock != null else "--:--"
	_hint.text = "the d-pad moves one 16px cell    raw collision %02X" % [
		_world.collision_code_at(_world.player_cell),
	]
	_hint.text += "    time %s    rods: %s    balls: %s    P: phone    F5: save" % [clock_text, owned, balls]
	var host: Gen2ModHost = Gen2ModHost.instance()
	if host.world_renderer_ids().size() > 1:
		_hint.text += "    V: view (%s)" % host.world_renderer_label(host.selected_world_renderer())
	var services: Dictionary = _data.world_service_counts()
	_hint.text += "    services menus %d marts %d phone %d music %d sfx %d cries %d" % [
		int(services.get("menus", 0)), int(services.get("marts", 0)),
		int(services.get("phone_contacts", 0)), int(services.get("music", 0)),
		int(services.get("sfx", 0)), int(services.get("cries", 0)),
	]
	if not rods.is_empty():
		_hint.text += "    1-%d: select    F: fish" % rods.size()
	if not _script_prompt.is_empty():
		_hint.text += "    " + _script_prompt


func _phone_contact_label(contact: Dictionary) -> String:
	if contact.is_empty():
		return "UNKNOWN CALLER"
	var caller_label: String = String(contact.get("caller_label", ""))
	if not caller_label.is_empty():
		return caller_label
	var trainer_class: int = int(contact.get("trainer_class", 0))
	if trainer_class > 0 and _data != null:
		var trainer_name: String = _data.trainer_name(trainer_class)
		if not trainer_name.is_empty():
			return "%s %d" % [trainer_name, int(contact.get("trainer_number", 0))]
	return "CONTACT %d" % int(contact.get("index", -1))


func _selected_runtime_data() -> GameData:
	return Gen2GameRuntime.data_or_any()


func _selected_runtime_save() -> Gen2SaveData:
	return Gen2GameRuntime.selected_save_or_null()
