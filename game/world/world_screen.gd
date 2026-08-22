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
## rendered here; the sound is. Not SFX_CUT, which is $38 and is the battle
## move's own effect: the field animation shares the Unown puzzle's sound.
const SFX_CUT: int = Gen2UnownPuzzle.SFX_PLACE_PIECE
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

## `GetWarpSFX`: the door, the warp panel, and everything else, which is a step
## out of a building. Read off the tile the step landed on, the way
## `wPlayerTileCollision` is.
const SFX_ENTER_DOOR: int = 0x1F
const SFX_WARP_TO: int = 0x13
const SFX_EXIT_BUILDING: int = 0x23
const COLL_DOOR: int = 0x71
const COLL_WARP_PANEL: int = 0x7C
## `FadeToMapMusic`'s own `ld a, 8` into `wMusicFade`, which is what the new
## map's track arrives behind.
const WARP_MUSIC_FADE_FRAMES: int = 8

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
## The sprites registered mods put in the world, driven a frame at a time here
## and drawn by the renderer with the map's own objects.
var _actors: Gen2WorldActors = null
var _encounters: Gen2WorldEncounters = null
## The id of the visible encounter the running battle belongs to, so its provider
## is told how the fight ended and nothing else is.
var _battle_encounter_id: StringName = &""
## The headbutt result waiting for ShakeHeadbuttTree's 32 frames to be spent.
var _pending_headbutt_finish: Dictionary = {}
## The step in flight whose `PlayerEvents` are still owed, empty while none is.
## `CheckPlayerState` reads `PLAYERSTEP_STOP_F`, so the warp, the coord events
## and the wild roll all belong to the frame the step lands on.
var _pending_step_events: Dictionary = {}
## `MapSetupScript_Door` while it is running: `{ stage, step, frames, cell }`,
## empty on every other frame. The map swaps between the two stages, which is
## where the setup script's own list sits.
var _map_fade: Dictionary = {}
## The fade one of the five fade specials is inside, `{ orders, white_fill,
## step_frames, step, frames }`, and the row it left behind once it is done. A
## `FadeOutToWhite` holds the screen white until its own `FadeInFromWhite` runs,
## so the last row of a finished fade stays applied rather than snapping back.
var _script_fade: Dictionary = {}
var _script_fade_order: int = Gen2WorldPalette.FADE_IDENTITY
var _script_fade_white: bool = false
## `DoBattleTransition` and the battle it is in front of: the encounter is
## resolved when the transition starts, and the battle screen is not built until
## it has finished.
var _battle_transition: Gen2BattleTransition = null
var _battle_transition_request: Dictionary = {}
## `wLandmarkSignTimer` and the window the sign is drawn in. The map load decides
## whether there is a sign (`Gen2WorldAPI.map_name_sign_pending`); the sixty
## passes it stands for are spent here, like every other overworld countdown.
var _map_name_sign: TextureRect = null
var _map_name_sign_passes: int = 0
## `wOverworldDelay`, counted down a hardware frame at a time so `HandleMap`
## runs once per [member Gen2WorldAPI.FRAMES_PER_OVERWORLD_PASS] of them.
var _overworld_delay: int = 0
var _text_box: Gen2TextBox = null
var _text_box_rect: Rect2i = Rect2i()
var _text_box_rect_pushed: bool = false
var _text_box_rect_held: int = 0
var _clock: Gen2WorldClock = null
var _audio_player: Gen2AudioPlayer = null
var _audio_waiting: bool = false
var _script_prompt: String = ""
var _story_picture: TextureRect = null
## `engine/menus/menu_2.asm`'s balance window, up until `closetext` redraws the
## map behind it.
var _money_window: TextureRect = null
## `SelectMonFromParty` opened by a special rather than by the start menu: which
## request is waiting on the answer, empty when the list belongs to the menu.
var _party_selection: Dictionary = {}
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
## `EvolveAfterBattle`'s own screen, opened on the overworld after a battle that
## was won and by an evolution stone from the pack.
var _evolution_host: Gen2EvolutionScreen = null
## What the evolution pass has to run when its screen closes: the pack's own
## continuation, or nothing for the after-battle pass.
var _evolution_after: Callable = Callable()
## The party the open pass applies to, which is the fought save rather than
## whatever is selected while the screen is up.
var _evolution_save: Gen2SaveData = null
## `OverworldHatchEgg`'s screen and the save whose party it has already written.
var _hatch_host: Gen2EggHatchScreen = null
var _hatch_save: Gen2SaveData = null
## `special NameRater`'s screen and the save whose party row it may rename.
var _name_rater_host: Gen2NameRaterScreen = null
var _name_rater_save: Gen2SaveData = null
## `special MoveDeletion`'s screen. It needs no save of its own beside it: the
## moves and their PP belong to the save it was handed and it writes them itself.
var _move_deleter_host: Gen2MoveDeleterScreen = null
var _move_tutor_host: Gen2MoveTutorScreen = null
## `MoveTutor`'s answer, held between the screen's `finished` and its `closed`
## the way the Day-Care's is.
var _move_tutor_script_value: int = Gen2MoveTutor.SCRIPT_VALUE_CANCELLED
## The Day-Care's five routines, all one screen. It edits the save's party and
## the world state directly, which is what `DepositBreedmon` and `RetrieveBreedmon`
## do, so the save it was handed is kept beside it only to write nothing else.
var _day_care_host: Gen2DayCareScreen = null
var _unown_puzzle_host: Gen2UnownPuzzleScreen = null
var _slot_machine_host: Gen2SlotMachineScreen = null
var _card_flip_host: Gen2CardFlipScreen = null
## What `DayCareManOutside` left in wScriptVar, held between the screen finishing
## and the request completing. -1 while no routine has written one.
var _day_care_script_value: int = -1
## Whether a field-move message is on screen waiting for its acknowledge. The
## world is idle while it is, the same way a script text pause holds it.
var _field_move_text: bool = false
## Whether the text on screen owes a press of its own. A `writetext` whose last
## page ends in `<DONE>` does not: `MapTextbox` prints and returns, and the
## press is the `waitbutton` behind the command.
var _text_awaits_press: bool = true
## How many presses [method preview_text_scroll] will spend looking for one.
const PREVIEW_TEXT_PRESSES: int = 8
## `ProfOaksPCBoot`'s three texts, one page at a time, and the sfx `Rate` leaves
## for it to play once the last of them is up.
var _oak_pc_pages: Array = []
var _oak_pc_sfx: int = -1
## `DisplayUnownWords`' box, up until the `JoyWaitAorB` behind it is answered.
var _unown_wall_box: TextureRect = null
## Mirrors the source's wBattleMenuCursorPosition surviving a reopen.
var _start_menu_cursor: int = 0
## `.MenuReturns`' first entry, `.Reopen`: Pokedex, Pokemon, Pokegear and the
## trainer card all return 0 from their `StartMenu_*` handler, so the menu is
## drawn again rather than closed. Set when the menu opened the screen, so a
## Pokegear reached by a script or by the debug key still returns to the world.
var _reopen_start_menu: bool = false
var _trainer_approach: Dictionary = {}
var _active_battle_save: Gen2SaveData = null
## How many battles this run has started, which is what a replay compares beside
## the party: a route that fought and one that walked past the grass reach
## different states for the same reason.
var _battles_fought: int = 0
## What the last one resolved to (`Gen2WorldBattleAdapter.OUTCOME_*`), which is
## the fight's own result rather than the party's: a lost battle heals the party
## on the way out, so the outcome is what says the turn resolved at all.
var _last_battle_outcome: StringName = &""
## The audio driver's rendered-frame count as of the last frame, for the one
## script wait that reads it. See [method Gen2AudioPlayer.timeline_updates].
var _audio_rendered_seen: int = 0
var _active_battle_persist: bool = false
var _encounter_random := RandomNumberGenerator.new()
## NPC movement rolls from its own generator, so a seeded route keeps the same
## encounters and script results however long the player stands watching.
var _object_random := RandomNumberGenerator.new()
## The Day-Care's rolls, from a stream of their own for the same reason.
var _breed_random := RandomNumberGenerator.new()
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
## A run of sounds the world owes the driver, spent one entry at a time by
## [method advance_frame]: `HealMachineAnim`'s, whose entries are due on a frame
## count of their own, and the ITEMFINDER's, whose are `WaitPlaySFX` and due when
## the four effect channels are free. Nothing plays two at once, since the script
## that started one is waiting on it.
var _sound_schedule: Array = []
var _sound_schedule_frame: int = 0
var _screen_base_position: Vector2 = Vector2.ZERO
## Whether a screen laid out in 160x144 owns the picture, as last told to the
## renderer, and whether it has been told at all: [method _apply_interface_mask]
## runs every frame, and a renderer swapped in mid-scene has heard nothing.
var _interface_owned: bool = false
var _interface_owned_pushed: bool = false

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
	_breed_random.seed = run_seed + 2
	_world.random_seed = run_seed

	_world.schedule_random = _encounter_random
	_world.script_random = _encounter_random
	_world.object_random = _object_random
	_world.breed_random = _breed_random
	_clock = Gen2WorldClock.new(initial_hour, initial_minute, initial_day)
	time_of_day = _clock.time_of_day()
	_animation = Gen2WorldAnimation.new()
	_effects = Gen2WorldEffects.new()
	_actors = Gen2WorldActors.new()
	_actors.set_actors(Gen2ModHost.instance().world_actors())
	## The cut leaves ride BattleAnimSineWave, which is cartridge data rather
	## than a table this could derive.
	var anim_data: Gen2BattleAnimData = Gen2BattleAnimData.from_game_data(_data)
	_effects.set_sine_table(anim_data)
	_world.set_world_clock(initial_day, initial_hour, initial_minute)
	_world.set_object_time(initial_hour, time_of_day)
	## After the clock, since the tables a provider is handed are the ones this
	## time of day resolves to.
	_encounters = Gen2WorldEncounters.new()
	_encounters.set_providers(Gen2ModHost.instance().visible_encounter_providers())
	_encounters.set_world(_world, anim_data)
	_actors.set_encounters(_encounters)
	var rods: Array[StringName] = _world.available_fishing_rods()
	if not rods.is_empty() and not rods.has(_selected_rod):
		_selected_rod = rods[0]
	_animation.configure(_world, _render_time_of_day())
	_apply_screen_fill()
	_build_renderer()
	_screen.view_size_changed.connect(_on_view_size_changed)
	_screen_base_position = _screen.position
	_audio_player = AUDIO_PLAYER_SCRIPT.new()
	_audio_player.name = "AudioPlayer"
	add_child(_audio_player)
	_play_current_map_music()
	_text_box = Gen2TextBox.new()
	# The overworld owns the frame, so the reveal is spent in [method
	# advance_frame] with everything else the frame draws rather than on a second
	# clock only real time turns.
	_text_box.driven = true
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
		Gen2Screen.drop(_renderer)
	_renderer = Gen2ModHost.instance().create_world_renderer()
	if Gen2ModHost.renderer_uses_hardware_viewport(_renderer):
		_screen.display_content(_renderer)
	else:
		_screen.display_native(_renderer)
		_screen.native_size_changed.connect(_on_native_size_changed)
		_on_native_size_changed(_screen.native_size())
	if _renderer.has_method(Gen2ModHost.RENDERER_EFFECTS_METHOD):
		_renderer.call(Gen2ModHost.RENDERER_EFFECTS_METHOD, _effects)
	if _renderer.has_method(Gen2ModHost.RENDERER_ACTORS_METHOD):
		_renderer.call(Gen2ModHost.RENDERER_ACTORS_METHOD, _actors)
	if _renderer.has_method(Gen2ModHost.RENDERER_ENCOUNTERS_METHOD):
		_renderer.call(Gen2ModHost.RENDERER_ENCOUNTERS_METHOD, _encounters)
	_set_renderer_world()
	_renderer.set_time_of_day(_render_time_of_day())
	_apply_renderer_interface_style()


## The map under the player changed, or the view was created: the renderer and
## the mod actors are both told, since an actor is handed the same
## [Gen2WorldAPI] a renderer is and has to drop whatever it was following on the
## map it has just left.
func _set_renderer_world() -> void:
	if _world == null:
		return
	if _renderer != null:
		_renderer.set_world(_world, _animation)
	if _actors != null:
		_actors.set_world(_world)
	if _encounters != null:
		_encounters.set_world(_world)


## The text box is the screen's, not the renderer's, and over a native-layer view
## the cartridge's opaque white field is a slab across the map. A renderer may
## ask for it to be drawn through, and may be told where it is so it can compose
## around it. Both are pushed here and again whenever the box moves, resizes or
## is shown, since a renderer swapped in mid-scene has neither.
func _apply_renderer_interface_style() -> void:
	if _text_box == null:
		return
	_text_box.field_opacity = Gen2ModHost.renderer_interface_opacity(_renderer)
	# A renderer swapped in mid-scene has no rectangle, so this one is not deduped.
	_text_box_rect_pushed = false
	_push_text_box_rect()
	_interface_owned_pushed = false
	_apply_interface_mask()


## Pushed only when the rectangle actually changes, and never while a page turn
## is between the box it just closed and the box the next event opens: a renderer
## composing around the box would otherwise pan away and back inside one
## conversation. A conversation that really ends pushes the empty rectangle once,
## because the empty one differs from the occupied one it replaces.
func _push_text_box_rect() -> void:
	if _text_box == null or _text_box_rect_held > 0:
		return
	var rect: Rect2i = _text_box.occupied_rect()
	if _text_box_rect_pushed and rect == _text_box_rect:
		return
	_text_box_rect = rect
	_text_box_rect_pushed = true
	Gen2ModHost.renderer_set_text_box_rect(_renderer, rect)


## What the renderer actually draws with, which is not always the clock: a dark
## cave stays dark until Flash is used and looks like night afterwards. See
## [method Gen2WorldPalette.map_time_of_day].
func _render_time_of_day() -> int:
	if _world == null:
		return time_of_day
	return _world.map_time_of_day()


## SCREEN FILL: the overworld is the one screen with more to show than the
## hardware framed, so it is the one screen that grows into the window. Every
## menu, box and cursor over it stays inside the 160x144 rectangle
## [Gen2Screen] centres in the buffer.
func _apply_screen_fill() -> void:
	var options: Gen2Options = Gen2OptionsStore.current()
	## The bars a framed screen leaves are this scene's own background, so a mask
	## that stands in for them is painted in the same colour.
	var background := get_node_or_null(^"Background") as Panel
	var style := background.get_theme_stylebox(&"panel") as StyleBoxFlat \
		if background != null else null
	if style != null:
		_screen.letterbox_color = style.bg_color
	_screen.expanded = options.screen_fill
	if _screen.expanded:
		_screen.zoom_step = options.zoom_step
	_on_view_size_changed(_screen.view_size())
	_apply_interface_mask()


## A screen that hides the map takes the whole picture with it: it is laid out
## in 160x144 and has nothing to put in a wider buffer, so the surround becomes
## the letterbox rather than the map behind it. The start menu is not one of
## these -- it is a box the map is still visible around, as on the cartridge --
## and neither is a map fade, which fades the whole picture.
##
## `DoBattleTransition` is: it writes twenty by eighteen screen cells and
## nothing wider, so a wedge pattern in a filled window would stop where the
## cartridge's screen ended. It closes the surround for the battle that follows
## it, which is masked for the same reason.
##
## The mask is drawn inside the hardware viewport and the viewport is composited
## over the native layer, so raising it would crop a renderer that is not drawing
## in the buffer it describes: one of those has already filled the whole surface,
## and a letterbox around a rectangle it never used has nothing to say about it.
## Such a renderer is told instead
## ([constant Gen2ModHost.RENDERER_INTERFACE_MASK_METHOD]) and closes its own
## surround in its own units, which is the only way a transition's wedge reaches
## the edge of a filled window.
func _apply_interface_mask() -> void:
	var owned: bool = (
		_battle_transition != null
		or _battle_host != null or _service_host != null or _party_host != null
		or _hall_of_fame_host != null or _trainer_card_host != null
		or _pokedex_host != null or _credits_host != null
		or _evolution_host != null or _hatch_host != null
		or _name_rater_host != null or _move_deleter_host != null
		or _move_tutor_host != null or _day_care_host != null
		or _unown_puzzle_host != null or _slot_machine_host != null
		or _card_flip_host != null
	)
	_screen.interface_masked = _screen.expanded and owned \
		and Gen2ModHost.renderer_uses_hardware_viewport(_renderer)
	if _interface_owned_pushed and owned == _interface_owned:
		return
	_interface_owned = owned
	_interface_owned_pushed = true
	Gen2ModHost.renderer_set_interface_masked(_renderer, owned)


func _on_view_size_changed(size_pixels: Vector2i) -> void:
	if _world == null:
		return
	if _world.view_pixels == size_pixels:
		return
	_world.view_pixels = size_pixels
	if _renderer != null and _renderer.has_method(&"refresh"):
		_renderer.refresh()


func _on_native_size_changed(size_pixels: Vector2i) -> void:
	if _renderer != null \
		and _renderer.has_method(Gen2ModHost.RENDERER_RESIZE_METHOD):
		_renderer.call(Gen2ModHost.RENDERER_RESIZE_METHOD, size_pixels)
	Gen2ModHost.renderer_set_screen_rect(_renderer, _screen.screen_rect())


## Switches the live view without disturbing the world behind it. The choice is
## the whole view rather than the overworld's half of it, so a fight started
## after this is drawn by the same mod: nothing about the map, the player or the
## running script changes, because a renderer only ever reads them.
func select_view(id: StringName) -> Dictionary:
	var result: Dictionary = Gen2ModHost.instance().select_view(id)
	if not bool(result.get("ok", false)):
		_script_prompt = "Renderer unavailable: %s" % String(result.get("reason", "unknown"))
		_refresh_labels()
		return result
	_build_renderer()
	_script_prompt = "Renderer: %s" % Gen2ModHost.instance().view_label(id)
	_refresh_labels()
	return result


## Selects the view after the current one, wrapping. One key can then cycle every
## installed view, which is how a mod's 3D world is reached with no launcher.
func cycle_view() -> Dictionary:
	var host: Gen2ModHost = Gen2ModHost.instance()
	var ids: Array[StringName] = host.view_ids()
	if ids.size() < 2:
		_script_prompt = "No other renderer is registered"
		_refresh_labels()
		return {"ok": false, "reason": &"single_renderer"}
	var at: int = ids.find(host.selected_view())
	return select_view(ids[posmod(at + 1, ids.size())])


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
	## Every drawn frame rather than every hardware frame: above sixty a drawn
	## frame can carry no hardware one, and a screen opened by the press that
	## drawn frame served would show the map around it until the next.
	_apply_interface_mask()


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
##
## Half of what follows is `HandleMap`'s own pass and runs once per two frames:
## see [member Gen2WorldAPI.FRAMES_PER_OVERWORLD_PASS] and `map_pass` below. The
## other half is what the source spends its own `DelayFrames` on from inside a
## command, which the pass does not gate: a text box, either fade, the battle
## transition, `GameTimer` and `AnimateTileset` are all VBlank's or a routine's
## own and are spent on every frame.
func advance_frame() -> void:
	_spending_frame = true
	## `ResetOverworldDelay` and `NextOverworldFrame`: the pass reloads the delay
	## and then spends it, so the first frame of a world is a pass and every
	## FRAMES_PER_OVERWORLD_PASS-th frame after it is the next one.
	_overworld_delay -= 1
	var map_pass: bool = _overworld_delay <= 0
	if map_pass:
		_overworld_delay = Gen2WorldAPI.FRAMES_PER_OVERWORLD_PASS
	if _text_box != null:
		_text_box.accelerated = Gen2Button.text_accelerating()
		_text_box.advance_frame()
	if _world != null:
		_world.advance_frame_counter()
		if _replaying_input:
			_apply_replayed_input(_world.frame_number)
	_advance_game_time_frame()
	## Before everything the map draws: the fade owns the frame the map swaps on,
	## and nothing else runs while `RunMapSetupScript` is spending its own.
	_advance_map_fade()
	_advance_script_fade()
	## `DoBattleTransition`'s own `.loop`, which owns every frame between the
	## encounter and the battle screen.
	_advance_battle_transition()
	## Here as well as in [method _process]: a driver that spends frames without
	## a clock -- a test, a preview, a replay -- never reaches the other one.
	_apply_interface_mask()
	## `RefreshMapSprites` runs inside the setup script and `PlaceMapNameSign`
	## with the rest of the map's background, so a sign raised by the load this
	## frame carried is spent from the next one.
	if map_pass:
		_advance_map_name_sign_pass()
	_raise_map_name_sign()
	if _effects != null:
		var effects_moved: bool = _effects.advance_frame()
		if map_pass:
			effects_moved = _effects.advance_pass() or effects_moved
		if effects_moved and _renderer != null:
			_renderer.refresh()
		_apply_world_effect_offset()
	## `AnimateTileset` is VBlank's, not the pass's, so the water and the flowers
	## animate on every frame while the objects standing on them move on passes.
	if _animation != null and _animation.advance_frame() and _renderer != null:
		_renderer.refresh_animation()
	## `GetJoypad` and `PlayerEvents` are both inside the pass, so a held
	## direction starts a step on a pass and never between two. Before the step
	## below, which is `HandleMap`'s own order: `MapEvents` starts the step and
	## `HandleMapObjects` moves it in the same pass, so a walk begun from
	## standing covers its first two pixels on the pass the press landed on.
	if map_pass:
		_advance_forced_movement()
		_advance_held_direction()
	if map_pass and _world != null and _world.advance_player_step_pass() \
		and _renderer != null:
		_renderer.refresh()
	## `CheckPlayerState` reads the step flags at the end of `HandleMap`, after
	## `HandleMapObjects`, so the step that finishes on this frame is the one
	## whose events this frame runs.
	if map_pass and not _pending_step_events.is_empty() and _world != null \
		and not _world.player_step_in_progress():
		var landed: Dictionary = _pending_step_events
		_pending_step_events = {}
		_complete_player_step(landed)
	## Not the pass's: an emote's own countdown stands in for the `pause` between
	## `ShowEmoteScript`'s two movements, and a script's `DelayFrames` is spent
	## from inside the command rather than by `NextOverworldFrame`.
	if _world != null and _world.advance_emotes_frame() and _renderer != null:
		_renderer.refresh()
	## After the player's own step, so an actor reading
	## `player_step_offset_cells()` sees this frame rather than the last one's.
	## Before the actors, which draw its population: a wild that moved this frame
	## has to be in the sprite list the actor layer collects after it.
	if _encounters != null and _encounters.advance_frame():
		_play_encounter_sounds()
		if _renderer != null:
			_renderer.refresh()
	if _actors != null and _actors.advance_frame() and _renderer != null:
		_renderer.refresh()
	_spend_actor_requests()
	_spend_hidden_item_requests()
	if map_pass and _objects_may_move() \
		and _world.advance_object_steps_pass(_object_random) \
		and _renderer != null:
		_renderer.refresh()
	# Not gated on _objects_may_move(): an applymovement is drawn while the
	# script that ran it is still going, which is when a script runs one.
	if map_pass and _world != null and _world.advance_scripted_steps_pass() \
		and _renderer != null:
		_renderer.refresh()
	# After both trails: `ShakeGrass` is called where the step starts, so a
	# rustle taken now belongs to a step begun on this frame.
	if map_pass:
		_spawn_grass_rustles()
	if not _pending_headbutt_finish.is_empty() and (_effects == null or not _effects.sprites_active()):
		var headbutt: Dictionary = _pending_headbutt_finish
		_pending_headbutt_finish = {}
		_finish_headbutt(headbutt)
	# After the trail, because the frame it finishes drawing is the frame the
	# script waiting on it resumes.
	if _world != null and not _world.pending_script_wait().is_empty():
		var wait_results: Array = _world.advance_script_wait_frame()
		if not wait_results.is_empty():
			_show_script_results(wait_results)
	_advance_sound_schedule()
	## `_ContText`'s scroll ends on a frame rather than on a press, and the page
	## it lands on may be the text's last, which is where the script runs on.
	_continue_if_text_settled()
	if not _trainer_approach.is_empty():
		_advance_trainer_approach(map_pass)
	if _world != null and _world.phone_ring_active():
		var ring_results: Array = _world.advance_phone_ring_frame()
		if not ring_results.is_empty():
			_show_script_results(ring_results)
		_refresh_labels()
	# The condition is the audio device's, not a counter's, but the request it
	# completes is a script's, so it lands on a frame like every other resume.
	## The same rule the battle's `ANIM_WAIT_SFX` follows: a driver nobody is
	## servicing leaves `effect_playing()` true for the rest of the run, so the
	## rendered-frame count is what decides whether this is a wait at all.
	var audio_rendered: int = _audio_player.timeline_updates() if _audio_player != null else 0
	var audio_moved: bool = audio_rendered != _audio_rendered_seen
	_audio_rendered_seen = audio_rendered
	if _audio_waiting and _audio_player != null \
		and (not _audio_player.effect_playing() or not audio_moved):
		_audio_waiting = false
		var audio_result: Dictionary = Gen2WorldHost.complete_runtime_request(
			_world, {"ok": true, "sound_finished": true}
		)
		if bool(audio_result.get("ok", false)):
			_show_script_results(audio_result.get("results", []))
	# `PlayRadioShow` runs from the Pokegear's own loop, so an open radio card
	# spends this frame too rather than counting one of its own.
	if _service_host != null:
		_service_host.advance_frame()
	## A battle is `BattleIntro` onward running inside the map's own loop, so its
	## bars, its animations and its faints are spent from this pump rather than
	## from real time. That is what makes a fight inside a replay reach the same
	## place on the same frame.
	if _battle_host != null:
		_battle_host.advance_hardware_frame()
	## `EvolveAfterBattle` runs inside the map's own loop the same way, so its
	## `DelayFrames` counts are spent from this pump.
	if _evolution_host != null:
		_evolution_host.advance_frame()
	if _hatch_host != null:
		_hatch_host.advance_frame()
	if _name_rater_host != null:
		_name_rater_host.advance_frame()
	if _move_deleter_host != null:
		_move_deleter_host.advance_frame()
	if _move_tutor_host != null:
		_move_tutor_host.advance_frame()
	if _day_care_host != null:
		_day_care_host.advance_frame()
	if _unown_puzzle_host != null:
		_unown_puzzle_host.advance_frame()
	if _slot_machine_host != null:
		_slot_machine_host.advance_frame()
	if _card_flip_host != null:
		_card_flip_host.advance_frame()
	_spending_frame = false


## Whether a battle owns the screen right now. Public beside
## [method battles_fought] so a tool driving a run knows which of the two funnels
## its presses are going through, and so a replay can compare the count.
func battle_active() -> bool:
	return _battle_host != null


func battles_fought() -> int:
	return _battles_fought


func last_battle_outcome() -> StringName:
	return _last_battle_outcome


## The save this run is playing, which is what a fight writes its party back into.
## The injected one for a test or a tool, the runtime's selected slot otherwise.
func active_save() -> Gen2SaveData:
	if _active_battle_save != null:
		return _active_battle_save
	return _injected_save if _injected_save != null else _selected_runtime_save()


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
func replay_input(entries: Array) -> void:
	_input_replay = {}
	for raw: Variant in entries:
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
	_apply_pokerus_days(ticks)
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
	## `.CheckForced` sits in front of `.GetAction` in all three of
	## `.TranslateIntoMovement`'s branches, so a player standing on ice keeps
	## walking with nothing held at all and a held direction is only obeyed when
	## `.GetAction` tests it before the slide's own.
	var held: Vector2i = Vector2i.ZERO if direction == Gen2Button.NONE \
		else Gen2Button.vector(direction)
	var walking: Vector2i = _world.effective_input_direction(held)
	if walking != Vector2i.ZERO:
		move_player(walking)
		return
	## A poll that commits nothing reaches `.StandInPlace`, which is what stops a
	## slide from resuming after the player has stepped off the ice.
	_world.note_standing_still()


## Whether any embedded screen is up. Every overlay is named here and nowhere
## else: the six callers below each need a different set of the other pauses, but
## they all need this one, and adding an overlay to five of six lists by hand is
## what the Cut and Hall of Fame work each paid for once.
func _overlay_open() -> bool:
	## A map fade is not an overlay, but nothing may move or be pressed inside
	## one either: `RunMapSetupScript` runs with the joypad unread.
	return not _map_fade.is_empty() or _battle_transition != null \
		or _battle_host != null or _service_host != null \
		or _start_menu_host != null or _party_host != null \
		or _hall_of_fame_host != null or _trainer_card_host != null \
		or _pokedex_host != null or _credits_host != null \
		or _evolution_host != null or _hatch_host != null \
		or _name_rater_host != null or _move_deleter_host != null \
		or _move_tutor_host != null \
		or _day_care_host != null or _unown_puzzle_host != null \
		or _slot_machine_host != null or _card_flip_host != null


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
	if _world == null:
		return
	var button: int = Gen2Button.pressed_in(event)
	if button != Gen2Button.NONE:
		if press_button(button):
			accept_event()
		return
	## The dex area's SELECT, the credits' A and B and the Unown puzzle's
	## directions are held states rather than presses, and those three overlays
	## are the only ones with anything to do with a release.
	var released: int = Gen2Button.released_in(event)
	if released != Gen2Button.NONE and _unown_puzzle_host != null:
		_unown_puzzle_host.release_button(released)
		accept_event()
		return
	if released != Gen2Button.NONE and _pokedex_host != null:
		_pokedex_host.release_button(released)
		accept_event()
		return
	if released != Gen2Button.NONE and _credits_host != null:
		_credits_host.release_button(released)
		accept_event()
		return
	if _handle_zoom(event):
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
	## First, because a battle hides the map entirely and owns every button while
	## it does. The fight takes it through this funnel rather than reading events
	## of its own, so a press inside a battle is recorded once, by the world, and
	## a replayed log reaches the fight (`tools/replay_world.gd`).
	if _battle_host != null:
		_battle_host.press_button(button)
		return true
	if not _map_fade.is_empty() or not _trainer_approach.is_empty() \
		or _world.phone_ring_active():
		return true
	## In front of every other overlay: `EvolveAfterBattle` runs with the map
	## loop suspended, and the pack path reaches it with the pack still open
	## behind it, so its B is the animation's cancel rather than the pack's back.
	if _evolution_host != null:
		_evolution_host.handle_button(button)
		return true
	## The same rule for `OverworldHatchEgg`, which `PlayerEvents` runs with the
	## map loop suspended in exactly the same place.
	if _hatch_host != null:
		_hatch_host.handle_button(button)
		return true
	## `special NameRater` runs inside `opentext`, so the map loop is suspended
	## behind it the same way and its own two screens are reached through it.
	if _name_rater_host != null:
		_name_rater_host.handle_button(button)
		return true
	## `special MoveTutor` and `special MoveDeletion`, the same shape again.
	if _move_tutor_host != null:
		_move_tutor_host.handle_button(button)
		return true
	if _move_deleter_host != null:
		_move_deleter_host.handle_button(button)
		return true
	## The Day-Care's five, one screen with the same shape again.
	if _day_care_host != null:
		_day_care_host.handle_button(button)
		return true
	## `special UnownPuzzle`, which owns the whole screen until START or the
	## last piece.
	if _unown_puzzle_host != null:
		_unown_puzzle_host.handle_button(button)
		return true
	## `special SlotMachine`, which owns the whole screen until the player says
	## no to another game or runs out of coins.
	if _slot_machine_host != null:
		_slot_machine_host.handle_button(button)
		return true
	## `special CardFlip`, the Game Corner's other machine, which owns the screen
	## on the same terms.
	if _card_flip_host != null:
		_card_flip_host.handle_button(button)
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
	if _unown_wall_box != null:
		## `DisplayUnownWords`' own `JoyWaitAorB`, and the click it plays after.
		if button in [Gen2Button.A, Gen2Button.B]:
			_close_unown_wall()
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
	## The d-pad first, because `DoPlayerMovement` runs in front of
	## `CheckStandingOnIce` in `OWPlayerInput` and has already decided what a
	## direction means while a slide is running.
	if Gen2Button.is_direction(button):
		move_player(_world.effective_input_direction(Gen2Button.vector(button)))
		return true
	## `OWPlayerInput`'s own comment: "Can't perform button actions while sliding
	## on ice." `CheckStandingOnIce` stands in front of `CheckAPressOW` and
	## `CheckMenuOW`, so A, START and SELECT are all refused until the run ends.
	if _world.standing_on_ice():
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
	var host_result: Dictionary = _complete_pending_request()
	if bool(host_result.get("ok", false)):
		_show_script_results(host_result.get("results", []))
		return
	_script_prompt = "Host unavailable: %s" % String(host_result.get("reason", "unknown"))
	_refresh_labels()


## One pending runtime request answered by the host with the selected save,
## which is the same call whether a press asked for it or nothing did.
func _complete_pending_request(result: Dictionary = {"ok": true}) -> Dictionary:
	var pending_save: Gen2SaveData = _injected_save if _injected_save != null \
		else _selected_runtime_save()
	return Gen2WorldHost.complete_runtime_request(
		_world, result, pending_save, _injected_save == null, _encounter_random
	)


## A request that spends no press on the cartridge, settled where it is staged.
## Empty when the host refused it, which leaves the caller its own prompt: a
## save with no party heals nothing, and that is a reason, not a press.
func _complete_unattended_request() -> Array:
	var settled: Dictionary = _complete_pending_request()
	if not bool(settled.get("ok", false)):
		_script_prompt = "Host unavailable: %s" % String(settled.get("reason", "unknown"))
		return []
	return settled.get("results", [])


## Zoom, on the keys every map program uses for it and on the wheel.
##
## Only while the map itself has the screen: a text box, a menu or a script is
## laid out against the 160x144 rectangle and moving the surface under one is
## the player losing their place. A framed screen refuses the step, since there
## is no more world to show and it would only shrink the picture
## ([method Gen2Screen.step_zoom]), and so does a view on the native layer, which
## has no hardware pixel for the ladder to count.
func _handle_zoom(event: InputEvent) -> bool:
	if not _renderer_input_free() or not _screen.expanded:
		return false
	## A view that declined the hardware buffer has no hardware pixel to scale:
	## the ladder's unit is screen pixels per one of those, and what a step moves
	## is a buffer that renderer never draws into. Its zoom is its camera's own
	## registered action, and leaving the event alone is what reaches it.
	if not Gen2ModHost.renderer_uses_hardware_viewport(_renderer):
		return false
	var delta: int = 0
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				delta = 1
			KEY_MINUS, KEY_KP_SUBTRACT:
				delta = -1
			KEY_0, KEY_KP_0:
				_screen.reset_zoom()
				_persist_zoom()
				return true
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			delta = 1
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			delta = -1
	if delta == 0:
		return false
	_screen.step_zoom(delta)
	_persist_zoom()
	return true


func _persist_zoom() -> void:
	var options: Gen2Options = Gen2OptionsStore.current()
	if options.zoom_step == _screen.zoom_step:
		return
	options.zoom_step = _screen.zoom_step
	Gen2OptionsStore.save(options)


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
			cycle_view()
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
			var pushed: Dictionary = movement["boulder_pushed"]
			if _effects != null:
				## SpawnStrengthBoulderDust runs where MovementFunction_Strength
				## starts the slide, and the dust tracks the boulder from there.
				_effects.start_boulder_dust(
					int(pushed["index"]), pushed["to_cell"], pushed["direction"],
					Gen2WorldAPI.STEP_PASSES_BOULDER_PUSH,
				)
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


## What a step owes the rest of the screen on the frame it starts: the sounds
## that belong to the step itself and the redraw. Everything else waits for the
## step to land; see [method _complete_player_step]. Shared with the forced-tile
## path, which reaches it without a key press.
func _after_player_move(movement: Dictionary) -> bool:
	if movement.get("kind", &"") == &"ledge_hop":
		_play_ledge_hop_sfx()
		if _effects != null:
			## `JumpStep` spawns the shadow where the hop starts, and it tracks
			## the player over both cells of it.
			_effects.start_jump_shadow(
				-1, _world.player_cell, _world.facing_direction(),
				Gen2WorldAPI.STEP_PASSES_HOP,
			)
	## .ExitWater calls PlayMapMusic before the step, which is what drops the
	## surfing track once the player is walking again.
	if movement.get("kind", &"") == &"exit_water":
		_play_current_map_music()
	if _renderer != null:
		if movement.get("kind", &"") == &"connection":
			## `MapSetupScript_Connection`, which is the step itself rather than
			## a warp: the neighbour's blocks are loaded under a camera that
			## never stops, and its `FadeToMapMusic` is why crossing a route
			## boundary into the same track is one continuous piece. It carries
			## no `LoadMapGraphics` either, so the tile animation is re-pointed
			## at the new tileset where it stands rather than restarted.
			_animation.reload_tileset(_world, _render_time_of_day())
			_set_renderer_world()
			_fade_to_map_music()
		else:
			_renderer.refresh()
	## `CheckPlayerState` only turns `wMapEventStatus` on where the step function
	## set `PLAYERSTEP_STOP_F`, so `PlayerEvents` and everything under it run on
	## the frame the step lands rather than on the frame it was asked for. The
	## step's own frames are spent by `advance_frame`, which drains this.
	if _world != null and _world.player_step_in_progress():
		_pending_step_events = movement.duplicate(true)
		return true
	return _complete_player_step(movement)


## `PlayerEvents` for the step that has just landed: the warp it stands on, and
## then the map's own tail.
func _complete_player_step(movement: Dictionary) -> bool:
	## `CheckTileEvent` gates warps on nothing, so surfing onto a warp tile and
	## the step back onto land both reach one. `edge_warp` is
	## `DoPlayerMovement.CheckWarp`'s own answer, which has already made the
	## check `CheckWarpTile` refuses for a carpet.
	_spend_step_happiness()
	_spend_egg_steps()
	_spend_day_care_steps()
	var kind: StringName = StringName(movement.get("kind", &""))
	if kind == &"edge_warp" or (kind in [
		&"move", &"ledge_hop", &"water_move", &"exit_water", &"forced_move",
	] and _world.warp_pending()):
		## `WarpToNewMapScript`: the sound, and then `newloadmap MAPSETUP_DOOR`,
		## whose `FadeOutToWhite` runs before the map is loaded at all. The map
		## swaps when that fade lands, and everything a step still owes waits
		## for `FadeInFromWhite` behind it.
		_zero_map_name_sign_timer()
		_start_map_fade()
		return true
	return _after_map_settled()


## `StepHappiness`, which `CountStep` reaches every 256 steps and which acts on
## every second visit. [method Gen2WorldState.count_step] counts on the step
## itself, wherever it was taken; the party lives on the save, which is here.
## The cartridge raises happiness in WRAM and writes SRAM only when the player
## saves, so this touches the loaded save and persists nothing of its own.
func _spend_step_happiness() -> void:
	if _world == null or _world.state == null:
		return
	var owed: int = _world.state.take_pending_step_happiness()
	if owed <= 0:
		return
	var save: Gen2SaveData = active_save()
	if save == null:
		return
	if not Gen2WorldPartyHost.apply_step_happiness(save, owed).is_empty():
		_refresh_labels()


## `DoEggStep` and the `PLAYEREVENT_HATCH` it raises. The party lives on the
## save, so the walk counts the step and this spends it, the way
## [method _spend_step_happiness] does for `StepHappiness`.
##
## `HatchEggs` walks the whole party, so every egg the pass left on zero hatches
## in one screen rather than one per step.
func _spend_egg_steps() -> void:
	if _world == null or _world.state == null or _hatch_host != null:
		return
	var owed: int = _world.state.take_pending_egg_steps()
	if owed <= 0:
		return
	var save: Gen2SaveData = active_save()
	if save == null:
		return
	if Gen2WorldPartyHost.apply_egg_steps(save, owed) < 0:
		return
	var hatches: Array = []
	for index: int in save.party.size():
		var summary: Dictionary = Gen2WorldPartyHost.hatch_egg(_world, save, index)
		if not summary.is_empty():
			hatches.append(summary)
	if hatches.is_empty():
		return
	_open_hatch(hatches, save)


## `DayCareStep`, which `CountStep` reaches on every step that did not hatch an
## egg: `jr nz, .hatch` jumps over the `farcall`, and the hatch screen standing
## is what says this step was one of those.
##
## The two slots live in the world state rather than on the save, so nothing here
## is a save transaction; what it can produce is `DAYCAREMAN_HAS_EGG_F`, which
## the man outside the Day-Care reads.
func _spend_day_care_steps() -> void:
	if _world == null or _world.state == null or _data == null:
		return
	var owed: int = _world.state.take_pending_day_care_steps()
	if owed <= 0 or _hatch_host != null:
		return
	for _pass: int in owed:
		Gen2WorldDayCare.step(_world.state, _data, _breed_random)


## `OverworldHatchEgg`. The rows are already written; the screen owns the
## sequence and the nickname alone.
func _open_hatch(hatches: Array, save: Gen2SaveData) -> void:
	var host := Gen2EggHatchScreen.new()
	host.set_context(_data, hatches)
	_hatch_save = save
	host.named.connect(_on_hatch_named)
	host.closed.connect(_on_hatch_closed)
	host.cry_requested.connect(_play_species_cry)
	host.sfx_requested.connect(_play_sfx)
	host.music_requested.connect(_play_evolution_music)
	host.z_index = 30
	_hatch_host = host
	_screen.display(host)
	if _hatch_host == null:
		return
	_script_prompt = "Hatching"
	_refresh_labels()


## `InitName`, which writes whatever the naming screen left into the row's
## nickname. `.nonickname` reaches this too, with the species name.
func _on_hatch_named(party_index: int, nickname: String) -> void:
	if _hatch_save == null or party_index < 0 \
		or party_index >= _hatch_save.party.size():
		return
	var mon: Gen2SaveMon = _hatch_save.party[party_index] as Gen2SaveMon
	if mon == null:
		return
	mon.nickname = nickname
	_script_prompt = "%s hatched" % nickname


func _on_hatch_closed() -> void:
	var host: Gen2EggHatchScreen = _hatch_host
	_hatch_host = null
	_hatch_save = null
	if host != null:
		Gen2Screen.drop(host)
	if _renderer != null:
		_renderer.refresh()
	_refresh_labels()


## `special NameRater`. `_NameRater` owns its own boxes and both of the screens
## it opens, so the whole routine is one host and the script stays suspended
## behind it, which is what `opentext` left it doing.
func _open_name_rater() -> bool:
	if _name_rater_host != null or _world == null or _data == null:
		return false
	var texts: Dictionary = Gen2WorldHost.name_rater_texts(_data)
	if texts.is_empty():
		_script_prompt = "Name Rater unavailable: name_rater_text_unavailable"
		return false
	var save: Gen2SaveData = _embedded_party_save()
	if save == null:
		_script_prompt = "The Name Rater needs a validated save"
		return false
	var host := Gen2NameRaterScreen.new()
	host.set_context(_data, save, texts, _world.player_name(), _world.player_id())
	host.finished.connect(_on_name_rater_finished)
	host.closed.connect(_on_name_rater_closed)
	host.z_index = 30
	_name_rater_save = save
	_name_rater_host = host
	_screen.display(host)
	_script_prompt = "Name Rater"
	_refresh_labels()
	return true


## The `CopyBytes` and the text `.done` ends on. The text is put in the world's
## own speech box rather than pressed here: `special NameRater` returns as soon
## as `PrintText` has drawn it and the script's `waitbutton` is that press.
func _on_name_rater_finished(
	party_index: int, nickname: String, ending_text: String
) -> void:
	if party_index >= 0 and _name_rater_save != null:
		Gen2WorldPartyHost.rename_party_mon(_name_rater_save, party_index, nickname)
	if not ending_text.is_empty() and _text_box != null and _text_box.font != null:
		_apply_text_box_options()
		_text_awaits_press = false
		_text_box.show_text(ending_text, false)
		_text_box.visible = true


func _on_name_rater_closed() -> void:
	var host: Gen2NameRaterScreen = _name_rater_host
	_name_rater_host = null
	_name_rater_save = null
	if host != null:
		Gen2Screen.drop(host)
	if _renderer != null:
		_renderer.refresh()
	if _world != null:
		_show_script_results(_world.complete_runtime_request({"ok": true}))
	_refresh_labels()


## The Day-Care's five specials, hosted exactly as `special NameRater` is. The
## routine writes the party, the two slots and the money itself, so nothing is
## staged: the cartridge's own routines write WRAM straight and the save is only
## committed when the player saves.
## `special UnownPuzzle`. `FadeToMenu` in front of it and `ExitAllMenus` behind
## it are what the host's own overlay already is: the board covers the map and
## the map is redrawn when it closes.
func _open_unown_puzzle(request: Dictionary) -> bool:
	if _unown_puzzle_host != null or _world == null or _data == null:
		return false
	var host := Gen2UnownPuzzleScreen.new()
	## The board is scattered from the world's own generator, so the run's seed
	## reproduces it the way it reproduces an encounter.
	if not host.open(
		_data, int((request.get("values", {}) as Dictionary).get("puzzle", 0)),
		_encounter_random
	):
		host.free()
		_script_prompt = "Unown puzzle unavailable: unown_puzzle_art_unavailable"
		return false
	host.set_audio_player(_audio_player)
	host.closed.connect(_on_unown_puzzle_closed)
	host.sfx_requested.connect(_play_sfx)
	host.z_index = 30
	_unown_puzzle_host = host
	_screen.display(host)
	_script_prompt = "Unown puzzle"
	_refresh_labels()
	return true


## `ld a, [wSolvedUnownPuzzle] / ld [wScriptVar], a`, which the chamber's own
## `iftrue` after the `closetext` branches on.
func _on_unown_puzzle_closed(solved: bool) -> void:
	var host: Gen2UnownPuzzleScreen = _unown_puzzle_host
	_unown_puzzle_host = null
	if host != null:
		Gen2Screen.drop(host)
	_script_prompt = ""
	_show_script_results(_world.complete_runtime_request({
		"ok": true, "script_value": 1 if solved else 0,
	}))


## `special SlotMachine`. `reanchormap` in front of it is what redraws the map
## behind the machine when it closes, which the host's own overlay already does.
func _open_slot_machine(request: Dictionary) -> bool:
	if _slot_machine_host != null or _world == null or _data == null:
		return false
	var values: Dictionary = request.get("values", {})
	var host := Gen2SlotMachineScreen.new()
	## The bias, the reel manipulation and both streak rolls come off the
	## world's own generator, so the run's seed reproduces a spin the way it
	## reproduces an encounter.
	if not host.open(
		_data, int(values.get("coins", _world.state.coins() if _world.state != null else 0)),
		bool(values.get("lucky", false)), _encounter_random
	):
		host.free()
		_script_prompt = "Slot machine unavailable: slots_art_unavailable"
		return false
	host.set_audio_player(_audio_player)
	host.closed.connect(_on_slot_machine_closed)
	host.sfx_requested.connect(_play_sfx)
	host.music_requested.connect(_play_music)
	host.z_index = 30
	_slot_machine_host = host
	_screen.display(host)
	_script_prompt = "Slot machine"
	_refresh_labels()
	return true


## The machine's own `wCoins`, which it has been writing all game.
func _on_slot_machine_closed(coins: int) -> void:
	var host: Gen2SlotMachineScreen = _slot_machine_host
	_slot_machine_host = null
	if host != null:
		Gen2Screen.drop(host)
	_script_prompt = ""
	## `_SlotMachine` stops `MUSIC_GAME_CORNER` nowhere, so the map's own track
	## is started again where `reanchormap` would have.
	_play_current_map_music()
	_show_script_results(_world.complete_runtime_request({
		"ok": true, "coins": coins,
	}))


## `special CardFlip`. Its objects are drawn in `wOBPals1` palette 0, which
## `CardFlip_InitAttrPals` never writes, so the map's own `PAL_OW_RED` is handed
## over with the request.
func _open_card_flip(request: Dictionary) -> bool:
	if _card_flip_host != null or _world == null or _data == null:
		return false
	var values: Dictionary = request.get("values", {})
	var host := Gen2CardFlipScreen.new()
	if not host.open(
		_data, int(values.get("coins", _world.state.coins() if _world.state != null else 0)),
		_data.overworld_sprite_palette(0, _render_time_of_day()), _encounter_random
	):
		host.free()
		_script_prompt = "Card flip unavailable: card_flip_art_unavailable"
		return false
	host.set_audio_player(_audio_player)
	host.closed.connect(_on_card_flip_closed)
	host.sfx_requested.connect(_play_sfx)
	host.music_requested.connect(_play_music)
	host.z_index = 30
	_card_flip_host = host
	_screen.display(host)
	_script_prompt = "Card flip"
	_refresh_labels()
	return true


## The table's own `wCoins`, which it has been writing all game.
func _on_card_flip_closed(coins: int) -> void:
	var host: Gen2CardFlipScreen = _card_flip_host
	_card_flip_host = null
	if host != null:
		Gen2Screen.drop(host)
	_script_prompt = ""
	## `_CardFlip` starts `MUSIC_GAME_CORNER` and stops it nowhere, so the map's
	## own track is started again where `reanchormap` would have.
	_play_current_map_music()
	_show_script_results(_world.complete_runtime_request({
		"ok": true, "coins": coins,
	}))


func _open_day_care(request: Dictionary) -> bool:
	if _day_care_host != null or _world == null or _data == null:
		return false
	var texts: Dictionary = Gen2WorldHost.day_care_texts(_data)
	if texts.is_empty():
		_script_prompt = "Day-Care unavailable: day_care_text_unavailable"
		return false
	var save: Gen2SaveData = _embedded_party_save()
	if save == null:
		_script_prompt = "The Day-Care needs a validated save"
		return false
	var host := Gen2DayCareScreen.new()
	host.set_context(
		_data, save, _world.state,
		StringName((request.get("values", {}) as Dictionary).get("role", &"man")),
		texts, _world.player_name(), _world.player_id(), _breed_random
	)
	host.finished.connect(_on_day_care_finished)
	host.closed.connect(_on_day_care_closed)
	host.cry_requested.connect(_play_species_cry)
	host.sfx_requested.connect(_play_sfx)
	host.z_index = 30
	_day_care_host = host
	_screen.display(host)
	_script_prompt = "Day-Care"
	_refresh_labels()
	return true


## `DayCareManOutside`'s own wScriptVar, and the box the map script's
## `waitbutton` presses. -1 is the four routines that write no variable.
func _on_day_care_finished(script_value: int, ending_text: String) -> void:
	_day_care_script_value = script_value
	if not ending_text.is_empty() and _text_box != null and _text_box.font != null:
		_apply_text_box_options()
		_text_awaits_press = false
		_text_box.show_text(ending_text, false)
		_text_box.visible = true


func _on_day_care_closed() -> void:
	var host: Gen2DayCareScreen = _day_care_host
	_day_care_host = null
	if host != null:
		Gen2Screen.drop(host)
	if _renderer != null:
		_renderer.refresh()
	if _world != null:
		var completion: Dictionary = {"ok": true}
		if _day_care_script_value >= 0:
			completion["script_value"] = _day_care_script_value
		_day_care_script_value = -1
		_show_script_results(_world.complete_runtime_request(completion))
	_refresh_labels()


## `special MoveDeletion`, hosted exactly as `special NameRater` is.
func _open_move_deleter() -> bool:
	if _move_deleter_host != null or _world == null or _data == null:
		return false
	var texts: Dictionary = Gen2WorldHost.move_deleter_texts(_data)
	if texts.is_empty():
		_script_prompt = "Move deleter unavailable: move_deleter_text_unavailable"
		return false
	var save: Gen2SaveData = _embedded_party_save()
	if save == null:
		_script_prompt = "The move deleter needs a validated save"
		return false
	var host := Gen2MoveDeleterScreen.new()
	host.set_context(_data, save, texts)
	host.finished.connect(_on_move_deleter_finished)
	host.closed.connect(_on_move_deleter_closed)
	host.sfx_requested.connect(_play_sfx)
	host.z_index = 30
	_move_deleter_host = host
	_screen.display(host)
	_script_prompt = "Move deleter"
	_refresh_labels()
	return true


## The screen has already written the row, since the moves and their PP belong
## to the save it was handed. What is left is the text `.done` ends on, which
## the script's own `waitbutton` presses.
func _on_move_deleter_finished(
	_party_index: int, _move_index: int, ending_text: String
) -> void:
	if ending_text.is_empty() or _text_box == null or _text_box.font == null:
		return
	_apply_text_box_options()
	_text_awaits_press = false
	_text_box.show_text(ending_text, false)
	_text_box.visible = true


func _on_move_deleter_closed() -> void:
	var host: Gen2MoveDeleterScreen = _move_deleter_host
	_move_deleter_host = null
	if host != null:
		Gen2Screen.drop(host)
	if _renderer != null:
		_renderer.refresh()
	if _world != null:
		_show_script_results(_world.complete_runtime_request({"ok": true}))
	_refresh_labels()


## `special MoveTutor`, hosted exactly as `special MoveDeletion` is. The move
## comes from the request, since `.GetMoveTutorMove` has already read the map's
## own `setval`.
func _open_move_tutor(request: Dictionary) -> bool:
	if _move_tutor_host != null or _world == null or _data == null:
		return false
	var move: int = int((request.get("values", {}) as Dictionary).get("move", 0))
	if move <= 0:
		return false
	var save: Gen2SaveData = _embedded_party_save()
	if save == null:
		_script_prompt = "The move tutor needs a validated save"
		return false
	var host := Gen2MoveTutorScreen.new()
	host.set_context(_data, _world, save, move)
	host.finished.connect(_on_move_tutor_finished)
	host.closed.connect(_on_move_tutor_closed)
	host.sfx_requested.connect(_play_sfx)
	host.z_index = 30
	_move_tutor_host = host
	_move_tutor_script_value = Gen2MoveTutor.SCRIPT_VALUE_CANCELLED
	_screen.display(host)
	_script_prompt = "Move tutor"
	_refresh_labels()
	return true


## The screen has already written the move, its PP and the happiness row. What
## is left is `LearnedMoveText`, which the map script's own `promptbutton`
## presses on the branch that reached it.
func _on_move_tutor_finished(
	script_value: int, _party_index: int, ending_text: String
) -> void:
	_move_tutor_script_value = script_value
	if ending_text.is_empty() or _text_box == null or _text_box.font == null:
		return
	_apply_text_box_options()
	_text_awaits_press = false
	_text_box.show_text(ending_text, false)
	_text_box.visible = true


func _on_move_tutor_closed() -> void:
	var host: Gen2MoveTutorScreen = _move_tutor_host
	_move_tutor_host = null
	if host != null:
		Gen2Screen.drop(host)
	if _renderer != null:
		_renderer.refresh()
	if _world != null:
		_show_script_results(_world.complete_runtime_request({
			"ok": true, "script_value": _move_tutor_script_value,
		}))
	_refresh_labels()


## Public screenshot driver for `special MoveTutor`, the same way
## [method preview_move_deleter] is. The move is MT01, the first of the three
## rows `add_mt` appends past HM07, so a cartridge without them draws nothing.
func preview_move_tutor() -> void:
	if _world == null or _data == null or _move_tutor_host != null:
		return
	var move: int = Gen2MoveTutor.move_for_value(_data, Gen2MoveTutor.VALUE_FLAMETHROWER)
	if move <= 0:
		_script_prompt = "This cartridge has no move tutor moves"
		_refresh_labels()
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Move tutor preview needs a party"
		_refresh_labels()
		return
	save.party[0].is_egg = false
	_injected_save = save
	_open_move_tutor({"values": {"move": move}})


## Public screenshot driver for `special MoveDeletion`, the same way
## [method preview_name_rater] is: no fixture cell reaches it.
func preview_move_deleter() -> void:
	if _world == null or _data == null or _move_deleter_host != null:
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Move deleter preview needs a party"
		_refresh_labels()
		return
	save.party[0].is_egg = false
	_injected_save = save
	_open_move_deleter()


## `EnterMap`'s own tail, which a warp reaches once its setup script has run and
## an ordinary step reaches on the frame it finished: the sight lines, the map's
## scripts, the two phone paths, the contest timer, and the wild roll behind all
## of them.
func _after_map_settled() -> bool:
	_refresh_labels()
	var sight_results: Array = _world.dispatch_sight_events()
	if sight_results.is_empty():
		sight_results = _world.dispatch_script_events()
	if not sight_results.is_empty():
		_zero_map_name_sign_for(sight_results)
		_show_script_results(sight_results)
		return true
	var special_attempt: Dictionary = _world.try_special_phone_call()
	var special_results: Array = special_attempt.get("results", [])
	if bool(special_attempt.get("attempted", false)) and not special_results.is_empty():
		_zero_map_name_sign_timer()
		_show_script_results(special_results)
		return true
	var phone_attempt: Dictionary = _world.try_receive_phone_call(_encounter_random)
	var phone_results: Array = phone_attempt.get("results", [])
	if bool(phone_attempt.get("attempted", false)) and not phone_results.is_empty():
		_zero_map_name_sign_timer()
		_show_script_results(phone_results)
		return true
	## `CheckTimeEvents`' contest branch, which is read a step at a time and
	## takes the whole turn when it runs out: no encounter is rolled on the step
	## the contest ends.
	var contest_over: Array = _world.check_bug_contest_timer()
	if not contest_over.is_empty():
		_zero_map_name_sign_timer()
		_show_script_results(contest_over)
		return true
	_show_script_results([])
	## While a provider is active the step takes no roll of its own: a wild is
	## met by walking into one. Everything else that reaches a wild, a script, a
	## rod, Headbutt, Rock Smash, Sweet Scent and the contest, keeps its own path.
	if _encounters != null and _encounters.active():
		var request: Dictionary = _encounters.battle_request_at(_world.player_cell)
		if not request.is_empty():
			_battle_encounter_id = StringName(request["visible_encounter"])
			_zero_map_name_sign_timer()
			_start_battle_request(request)
		return true
	var encounter: Dictionary = _world.encounter_request(
		_encounter_random, false, &"auto", _repel_lead_level(), _party_holds_cleanse_tag()
	)
	if not encounter.is_empty():
		## `RandomEncounter` answers `CheckTileEvent` with carry, so a wild met
		## on a step is a player event like any other.
		_zero_map_name_sign_timer()
		_start_battle_request({
			"kind": &"battle_requested",
			"values": encounter["values"],
			"encounter": encounter.duplicate(true),
		})
	return true


## `MapSetupScript_Door` while it is running, for a test or a preview tool that
## has to land on one of its frames: `{ stage, step, frames }`, empty on every
## other frame of the game.
func map_fade() -> Dictionary:
	return _map_fade.duplicate()


## The same for one of the five fade specials, empty on every other frame.
func script_fade() -> Dictionary:
	return _script_fade.duplicate()


## `WarpToNewMapScript`. `GetWarpSFX` reads the tile the step landed on, and
## `MapSetupScript_Door`'s `FadeOutToWhite` is the first thing the setup script
## spends: four palette orders, two frames each, before anything is loaded.
func _start_map_fade() -> void:
	_play_sfx(_warp_sfx())
	_map_fade = {"stage": &"out", "step": 0, "frames": Gen2WorldPalette.FADE_STEP_FRAMES}
	_apply_map_fade_step()


## `GetWarpSFX`, off `wPlayerTileCollision`.
func _warp_sfx() -> int:
	match _world.collision_code_at(_world.player_cell):
		COLL_DOOR:
			return SFX_ENTER_DOOR
		COLL_WARP_PANEL:
			return SFX_WARP_TO
	return SFX_EXIT_BUILDING


## One frame of the fade the warp is inside, spent from [method advance_frame]
## like every other countdown here. The two stages are `FadeOutToWhite` and
## `FadeInFromWhite`; the map is loaded between them, which is where the rest of
## `MapSetupScript_Door`'s list sits.
func _advance_map_fade() -> void:
	if _map_fade.is_empty():
		return
	_map_fade["frames"] = int(_map_fade["frames"]) - 1
	if int(_map_fade["frames"]) > 0:
		return
	var step: int = int(_map_fade["step"]) + 1
	var out: bool = StringName(_map_fade["stage"]) == &"out"
	if step < Gen2WorldPalette.FADE_OUT_ORDERS.size():
		_map_fade["step"] = step
		_map_fade["frames"] = Gen2WorldPalette.FADE_STEP_FRAMES
		_apply_map_fade_step()
		return
	if out:
		_swap_warped_map()
		_map_fade = {"stage": &"in", "step": 0, "frames": Gen2WorldPalette.FADE_STEP_FRAMES}
		_apply_map_fade_step()
		return
	_map_fade = {}
	_apply_map_fade_step()
	## `EnterMap` runs the map's own scripts once the setup script has finished,
	## which is the frame the fade lands on.
	_after_map_settled()


## The palette order this step of the fade draws with. `FillWhiteBGColor` is the
## fade out's alone, so the way back in flattens onto whatever the new map's own
## palette 0 holds.
func _apply_map_fade_step() -> void:
	if _renderer == null or not _renderer.has_method(Gen2ModHost.RENDERER_FADE_METHOD):
		return
	if _map_fade.is_empty():
		## The warp's fade is over; whatever a script fade left standing is what
		## the screen is drawn with, which is the identity unless one is held.
		_renderer.call(
			Gen2ModHost.RENDERER_FADE_METHOD, _script_fade_order, _script_fade_white
		)
		return
	var out: bool = StringName(_map_fade["stage"]) == &"out"
	var orders: Array[int] = Gen2WorldPalette.FADE_OUT_ORDERS if out \
		else Gen2WorldPalette.FADE_IN_ORDERS
	_renderer.call(
		Gen2ModHost.RENDERER_FADE_METHOD, orders[int(_map_fade["step"])], out
	)


## `FadeOutToWhite` and its four siblings, opened by the special and stepped from
## here. The script is already holding for the frames the fade costs, since the
## runner staged that wait; this is the row the renderer draws with on each of
## them.
func _start_script_fade(event: Dictionary) -> void:
	var orders: Array = event.get("orders", [])
	if orders.is_empty():
		return
	_script_fade = {
		"orders": orders.duplicate(),
		"white_fill": bool(event.get("white_fill", false)),
		"step_frames": maxi(1, int(event.get("step_frames", 1))),
		"step": 0,
	}
	_script_fade["frames"] = int(_script_fade["step_frames"])
	_apply_script_fade_step()


## One frame of it, and the row the last step leaves behind.
func _advance_script_fade() -> void:
	if _script_fade.is_empty():
		return
	_script_fade["frames"] = int(_script_fade["frames"]) - 1
	if int(_script_fade["frames"]) > 0:
		return
	var step: int = int(_script_fade["step"]) + 1
	if step >= (_script_fade["orders"] as Array).size():
		_script_fade = {}
		return
	_script_fade["step"] = step
	_script_fade["frames"] = int(_script_fade["step_frames"])
	_apply_script_fade_step()


func _apply_script_fade_step() -> void:
	var orders: Array = _script_fade.get("orders", [])
	var step: int = int(_script_fade.get("step", 0))
	if step >= orders.size():
		return
	_script_fade_order = int(orders[step])
	_script_fade_white = bool(_script_fade.get("white_fill", false))
	## The warp's own fade owns the renderer while it runs, so a script fade
	## under one is held rather than drawn twice.
	if _map_fade.is_empty():
		_apply_map_fade_step()


## `MapSetupScript_Door`'s own fade in ends with the map's palettes restored, so
## a row a script fade was holding is dropped where the map is.
func _clear_script_fade() -> void:
	_script_fade = {}
	_script_fade_order = Gen2WorldPalette.FADE_IDENTITY
	_script_fade_white = false


## The middle of `MapSetupScript_Door`: the map the warp names is loaded with the
## screen at its whitest, and `FadeToMapMusic` is the eight-step fade the new
## map's track arrives behind rather than a restart.
func _swap_warped_map() -> void:
	var transition: Dictionary = _world.try_warp()
	if not bool(transition.get("ok", false)):
		return
	_clear_script_fade()
	_animation.configure(_world, _render_time_of_day())
	_set_renderer_world()
	_fade_to_map_music()


## The three placings as one line. `_BugContestJudging` prints them as three
## texts of its own, which no script points at and so nothing imports; the
## placings themselves are the source's.
func _bug_contest_placings_text(judged: Dictionary) -> String:
	var parts: PackedStringArray = []
	var places: Array[String] = ["1st", "2nd", "3rd"]
	var placings: Array = judged.get("placings", [])
	for index: int in placings.size():
		var entry: Dictionary = placings[index]
		var who: String = "You" if int(entry.get("id", 0)) == Gen2WorldBugContest.PLAYER_ID \
			else "Contestant %d" % int(entry.get("id", 0))
		parts.append("%s %s, %s (%d)" % [
			places[index], who,
			String(_data.species(int(entry.get("species", 0))).get("name", "-")),
			int(entry.get("score", 0)),
		])
	return "Bug Contest: %s" % ", ".join(parts)


## `CheckRepelEffect`'s own lead: the first party member that is not fainted, or
## -1 when there is no party to read, which is what a repel compares a wild
## level against. The party lives in the save rather than in the world API, so
## the screen is the one place that can answer it.
func _repel_lead_level() -> int:
	var save: Gen2SaveData = _selected_runtime_save()
	if save == null:
		return -1
	for mon: Gen2SaveMon in save.party:
		if mon.hp > 0:
			return mon.level
	return -1


## `ApplyCleanseTagEffectOnEncounterRate` walks the whole party, fainted members
## included, and halves the rate on the first Cleanse Tag it finds.
func _party_holds_cleanse_tag() -> bool:
	var save: Gen2SaveData = _selected_runtime_save()
	if save == null:
		return false
	for mon: Gen2SaveMon in save.party:
		if mon.item == Gen2HeldItem.CLEANSE_TAG:
			return true
	return false


## Public driver for the production NPC/object interaction path.
func interact() -> bool:
	if _world == null or _overlay_open() \
		or _field_move_text or not _oak_pc_pages.is_empty() \
		or _world.phone_ring_active() or _world.fishing_busy():
		return false
	var results: Array = _world.interact()
	if results.is_empty():
		## Only here, after every cartridge branch `PlayerEvents` tries answered
		## nothing: an actor can never shadow an object, a background event or a
		## tile branch. Its own pose is all it changes, so no player event is
		## spent and the sign timer stands.
		if _actors == null \
			or not _actors.interact(_world.facing_cell(), _world.player_facing):
			return false
		## On the frame of the press, which is what the offer promises. The
		## actor layer re-collects where the press is consumed, so nothing after
		## this sees a change to redraw for: `advance_frame` would compare a list
		## already carrying the new pose against itself and skip its own refresh,
		## and the picture would wait for the next unrelated change, which for a
		## mon icon is its two-frame flip nine frames later.
		if _renderer != null:
			_renderer.refresh()
		return true
	## `OWPlayerInput`, the last branch `PlayerEvents` tries, and a player event
	## like the rest of them.
	_zero_map_name_sign_timer()
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


## Whether the player is mid-slide, for `preview_world.gd`'s `ice_slide` kind,
## which drives until the run has started rather than spending a count.
func standing_on_ice() -> bool:
	return _world != null and _world.standing_on_ice()


## The hop's own arc, for `preview_world.gd`'s `ledge` kind, which drives to the
## top of it rather than spending a count.
func player_height_offset_pixels() -> float:
	return _world.player_height_offset_pixels() if _world != null else 0.0


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
		"yanma_swarm_map": _world.state.swarm_map(
			Gen2WorldState.SWARM_YANMA
		) if _world != null else Vector2i(-1, -1),
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
	_apply_pokerus_days(ticks)
	if not ticks.is_empty():
		_update_time_of_day()
		_refresh_labels()
	return ticks


## `CheckPokerusTick`, which `UpdateTime` reaches with the days elapsed since the
## timer's start day. The clock here runs a minute at a time rather than being
## read off a hardware RTC, so the count is the midnights the ticks crossed.
func _apply_pokerus_days(ticks: Array) -> void:
	var days: int = 0
	for tick: Dictionary in ticks:
		if int(tick.get("hour", -1)) == 0 and int(tick.get("minute", -1)) == 0:
			days += 1
	if days <= 0:
		return
	Gen2WorldPartyHost.apply_pokerus_tick(
		_injected_save if _injected_save != null else _selected_runtime_save(), days
	)


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
		_animation.configure(_world, _render_time_of_day())
	if _renderer != null:
		_renderer.set_time_of_day(_render_time_of_day())


## Public screenshot driver for the sprites the engine draws over an object
## rather than as one. `effects` is the scripted emote, `SpawnStrengthBoulderDust`,
## `ShakeGrass` and `ShakeHeadbuttTree`; `cut` is `OWCutAnimation`'s two halves
## and the jump shadow. Each is started through the call the game makes, so this
## photographs the renderer's own path.
func preview_effect_sprites(kind: StringName = &"effects") -> void:
	if _world == null or _renderer == null:
		return
	if kind == &"cut":
		if _effects != null:
			## Both halves of `OWCutAnimation` at once, over the cell Cut would
			## clear, plus the shadow `JumpStep` spawns under a ledge hop.
			_effects.start_cut(_world.facing_cell(), 0, _world.facing_direction(), _world.player_cell)
			_effects.start_cut(_world.facing_cell(), 1, _world.facing_direction(), _world.player_cell)
			_effects.start_jump_shadow(
				-1, _world.player_cell, _world.facing_direction(),
				Gen2WorldAPI.STEP_PASSES_HOP,
			)
		_script_prompt = "Debug cut animation preview"
		_renderer.refresh()
		_refresh_labels()
		return
	if kind == &"heal_machine":
		## `HealMachineAnim` over Elm's Lab, driven to the last frame before
		## `.FlashPalettes8Times` starts: a full party is on the machine and the
		## palette is still the one `.LoadPalettes` wrote, which is the picture
		## the colours can be read off.
		if _effects != null:
			var balls: int = Gen2WorldEffects.HEAL_MACHINE_BALLS.size()
			_effects.start_heal_machine(Gen2WorldEffects.HEAL_MACHINE_ELMS_LAB, balls)
			for _frame: int in balls * Gen2WorldEffects.HEAL_MACHINE_BALL_FRAMES - 1:
				_effects.advance_frame()
		_script_prompt = "Debug heal machine preview"
		_renderer.refresh()
		_refresh_labels()
		return
	if _effects != null:
		_effects.start_headbutt_tree(_world.player_cell + Vector2i(1, 0))
		_effects.start_boulder_dust(
			-1, _world.player_cell, Vector2i.DOWN, Gen2WorldAPI.STEP_PASSES_BOULDER_PUSH
		)
		_effects.start_grass_rustle(
			-1, _world.player_cell, Gen2WorldAPI.STEP_PASSES_WALK - 1
		)
	## The nearest object rather than the first, so the emote lands inside the
	## view a capture photographs.
	var nearest: Gen2WorldObject = null
	for object: Gen2WorldObject in _world.visible_objects():
		if nearest == null or object.cell.distance_squared_to(_world.player_cell) \
			< nearest.cell.distance_squared_to(_world.player_cell):
			nearest = object
	if nearest == null:
		_script_prompt = "No visible object for the emote"
	else:
		nearest.set_emote(0, true)
		_script_prompt = "Debug effect sprite preview"
	_renderer.refresh()
	_refresh_labels()


## Public screenshot driver for the visible-encounter seam, which otherwise needs
## a mod: a shiny Pokemon of the map's own table, on the eligible cell nearest
## the player, asking for its pulse. The provider is the synthetic one below;
## everything else is the host's own path.
func preview_visible_encounter() -> void:
	if _world == null or _encounters == null or _renderer == null:
		return
	_encounters.set_providers([PreviewEncounters.new(_world)])
	advance_frames(2)
	_script_prompt = "Debug visible encounter preview"
	_renderer.refresh()
	_refresh_labels()


## What a mod's provider is, in the fewest lines that exercise the contract.
class PreviewEncounters extends RefCounted:
	## `CheckShininess`: the attack mask and three tens.
	const SHINY_DVS: int = (2 << 12) | (10 << 8) | (10 << 4) | 10

	var _entries: Array = []

	func _init(world: Gen2WorldAPI) -> void:
		var cells: Dictionary = world.visible_encounter_cells()
		var tables: Dictionary = world.active_encounter_tables()
		for method: Variant in cells:
			var slots: Array = (tables.get(method, {}) as Dictionary).get("slots", [])
			var nearest := Vector2(-1, -1)
			for cell: Vector2 in cells[method] as PackedVector2Array:
				if nearest.x < 0 or cell.distance_squared_to(Vector2(world.player_cell)) \
					< nearest.distance_squared_to(Vector2(world.player_cell)):
					nearest = cell
			if nearest.x < 0 or slots.is_empty():
				continue
			_entries.append({
				"id": StringName("preview_%s" % method),
				"cell": Vector2i(nearest),
				"species": int(slots[0]["species"]),
				"level": int(slots[0]["min_level"]),
				"dvs": SHINY_DVS,
				"pulse": true,
			})

	func set_context(_context: Dictionary) -> void:
		pass

	func advance_frame() -> void:
		pass

	func encounters() -> Array:
		return _entries

	func battle_finished(_id: StringName, _result: Variant) -> void:
		pass


## Public screenshot driver for the actor seam's optional half, which otherwise
## needs a mod: a Pokemon one cell behind the player, pressed with A so it is
## drawn wearing the heart the press put up. The press and the cry go through
## the host's own path; only the actor is synthetic.
func preview_pet_actor() -> void:
	if _world == null or _actors == null or _renderer == null:
		return
	## Faced up so the bubble, which `MovementFunction_Emote` puts two rows above
	## the sprite, is clear of the player rather than behind them.
	_world.player_facing = Gen2WorldSprite.FACING_UP
	_actors.set_actors([PreviewPet.new(_world)])
	## Deliberately NOT followed by a refresh of its own, unlike the other
	## drivers here: the press is what has to reach the picture, and a driver
	## redrawing after it would photograph a heart that never arrived on the
	## frame it was pressed.
	interact()
	_script_prompt = "Debug pet actor preview"
	_refresh_labels()


## What a mod's actor is, in the fewest lines that exercise the optional half.
class PreviewPet extends RefCounted:
	const CYNDAQUIL: int = 155

	var _world: Gen2WorldAPI = null
	var _petted: bool = false
	var _cried: bool = false

	func _init(world: Gen2WorldAPI) -> void:
		_world = world

	func set_world(world: Gen2WorldAPI) -> void:
		_world = world

	func advance_frame() -> void:
		pass

	func sprites() -> Array:
		var entry: Dictionary = {
			"icon": _world.data.mon_menu_icon(CYNDAQUIL),
			"facing": _world.player_facing,
			"position_cells": Vector2(_cell()),
		}
		if _petted:
			entry["emote"] = Gen2WorldActors.EMOTE_HEART
		return [entry]

	func interact(cell: Vector2i, _facing: int) -> bool:
		if cell != _cell():
			return false
		_petted = true
		return true

	func take_requests() -> Array:
		if not _petted or _cried:
			return []
		_cried = true
		return [{"kind": Gen2WorldActors.REQUEST_CRY, "species": CYNDAQUIL}]

	## The faced cell, so a press with nothing in front of the player reaches it.
	func _cell() -> Vector2i:
		return _world.facing_cell()


## Public screenshot driver for `Script_pokepic`'s box. The scripts that run one
## are Elm's three balls and their neighbours, which no map reaches from a bare
## warp, so the species is named here; everything else is the branch's own call.
func preview_pokepic(species: int) -> void:
	_show_story_picture(species)
	_refresh_labels()


## Public screenshot driver for `_ContText`'s scroll: the object in front of the
## player is talked to and its text walked to the `<CONT>` that scrolls, and the
## box's own frames are then spent by hand so the picture is the same every run
## rather than whatever the wall clock reached.
func preview_text_scroll() -> void:
	if _text_box == null:
		return
	## A `BGEVENT_READ` is read from the cell below it, so the sign is faced
	## first; its own tile is a wall, so this turns rather than steps.
	move_up()
	interact()
	for _press: int in PREVIEW_TEXT_PRESSES:
		if _text_box.is_scrolling():
			break
		_advance_script_pause()
	_text_box.set_process(false)
	## One frame into the first of `TextScroll`'s two steps, where the two lines
	## sit on rows no finished page can put them on.
	_text_box.advance_scroll_frames(1.0)
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
	if not _walk_start_menu_to(Gen2WorldStartMenu.ITEM_PACK):
		return
	_start_menu_host.handle_button(Gen2Button.A)


## Public screenshot driver for a field evolution, which is the pack's USE on a
## stone. Driven twice, like the other `*_use` names: the first call opens the
## pack on the stone and the second uses it on the party's first member, so the
## picture is `EvolvingText` and `CongratulationsYourPokemonText` in the pack's
## own box rather than a staged string.
func preview_item_evolution_use() -> void:
	if _world == null or _data == null:
		return
	if _start_menu_host != null:
		# USE, then the party list, then the first member.
		for _press: int in 3:
			_start_menu_host.handle_button(Gen2Button.A)
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Evolution preview needs a party"
		_refresh_labels()
		return
	var stone: Dictionary = _first_stone_evolution()
	if stone.is_empty():
		_script_prompt = "Evolution preview: this cache has no stone evolution"
		_refresh_labels()
		return
	var mon: Gen2SaveMon = save.party[0]
	mon.species = int(stone["species"])
	mon.nickname = String(_data.species(mon.species).get("name", ""))
	_injected_save = save
	_world.state.apply_changes({}, {}, {"items": {int(stone["item"]): 1}})
	_open_start_menu()
	if _start_menu_host == null:
		return
	if not _walk_start_menu_to(Gen2WorldStartMenu.ITEM_PACK):
		return
	_start_menu_host.handle_button(Gen2Button.A)
	var rows: Array = _start_menu_host.call("_current_pocket_items")
	for index: int in rows.size():
		if int((rows[index] as Dictionary).get("item", 0)) == int(stone["item"]):
			_start_menu_host.set("_pack_cursor", index)
			break


## Public screenshot driver for `special NameRater`, which no cell of the
## fixture maps reaches: it stands a member the player caught in the first party
## slot and opens the routine on it, so every box, both questions and the party
## list can be photographed on any map.
func preview_name_rater() -> void:
	if _world == null or _data == null or _name_rater_host != null:
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Name Rater preview needs a party"
		_refresh_labels()
		return
	var mon: Gen2SaveMon = save.party[0]
	mon.is_egg = false
	mon.original_trainer = save.player_name
	mon.ot_id = save.player_id
	_injected_save = save
	_world.set_player_id(save.player_id)
	_open_name_rater()


## Public screenshot driver for the Day-Care's five specials, which no cell of
## the fixture maps reaches either. [param role] picks the routine; the two signs
## and the man outside need state behind them, so a slot is filled and the egg
## flag set before the screen opens.
func preview_day_care(role: StringName) -> void:
	if _world == null or _data == null or _day_care_host != null:
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.size() < 2:
		_script_prompt = "The Day-Care preview needs two party members"
		_refresh_labels()
		return
	_injected_save = save
	_world.set_player_id(save.player_id)
	var state: Gen2WorldState = _world.state
	if role in [&"mon1", &"mon2"]:
		for slot: int in [
			Gen2WorldDayCare.SLOT_MAN, Gen2WorldDayCare.SLOT_LADY
		]:
			state.set_day_care_mon(slot, save.party[slot] as Gen2SaveMon)
			state.set_day_care_has_mon(slot, true)
	elif role == &"outside":
		state.set_day_care_man_flags(
			state.day_care_man_flags() | Gen2WorldDayCare.MAN_HAS_EGG
		)
		state.set_day_care_egg(save.party[0] as Gen2SaveMon)
	_open_day_care({"values": {"role": role}})


## How long `preview_slot_machine` gives the loop to reach its bet menu.
const SLOT_MACHINE_MENU_FRAME_CAP: int = 16


## Public screenshot driver and scene-test entry for `special SlotMachine`,
## which only the two Game Corners reach and no fixture cell does.
##
## [param coins] is the balance the machine opens with, [param lucky] the
## `wScriptVar` the map's own `setval` leaves, and [param frames] how far into
## the game to drive: the machine is pressed past its bet menu and then handed
## A three times, which is how a spin is photographed at all.
func preview_slot_machine(
	coins: int = 100, lucky: bool = false, bet: int = 1, frames: int = 0
) -> void:
	if _world == null or _data == null or _slot_machine_host != null:
		return
	_open_slot_machine({"values": {"coins": coins, "lucky": lucky}})
	var host: Gen2SlotMachineScreen = _slot_machine_host
	if host == null:
		return
	## `SlotsAction_Init` runs on the first pass and `..._BetAndStart` on the
	## second, so the menu is two frames in rather than up at the open.
	for _frame: int in SLOT_MACHINE_MENU_FRAME_CAP:
		if host.prompt() == Gen2SlotMachine.Prompt.BET:
			break
		host.advance_frame()
	## `Slots_AskBet`'s menu opens on " 3", so a bet of one is two presses down.
	for _step: int in clampi(3 - bet, 0, 2):
		host.handle_button(Gen2Button.DOWN)
	host.handle_button(Gen2Button.A)
	## Every reel is stopped by an A press, which is the only way a spin ends at
	## all: the driver hands one over whenever the loop is waiting for it.
	for _frame: int in maxi(frames, 0):
		if _slot_machine_host == null:
			break
		## The `WaitSFX` steps are the driver's, and a screenshot spends no wall
		## clock for an effect to finish in, so each is cut rather than waited
		## out: `SFXChannelsOff` is what the cartridge does to a sound it will
		## not wait for.
		if _audio_player != null and host.machine() != null \
			and host.machine().waiting_for_sfx():
			_audio_player.stop_effects()
		host.advance_frame()
		if host.machine() != null and host.machine().jumptable_index() in [
			Gen2SlotMachine.SLOTS_WAIT_REEL1, Gen2SlotMachine.SLOTS_WAIT_REEL2,
			Gen2SlotMachine.SLOTS_WAIT_REEL3,
		]:
			host.handle_button(Gen2Button.A)


## How long `preview_card_flip` gives the loop to reach a prompt.
const CARD_FLIP_PROMPT_FRAME_CAP: int = 240


## Public screenshot driver and scene-test entry for `special CardFlip`, which
## only the two Game Corners reach and no fixture cell does.
##
## [param coins] is the balance the table opens with and [param frames] how far
## into the game to drive: every `YesNoBox` is answered YES and every
## `WaitPressAorB` pressed, so the table deals, toggles and pays without the
## driver knowing which state it is in.
func preview_card_flip(coins: int = 100, frames: int = 0) -> void:
	if _world == null or _data == null or _card_flip_host != null:
		return
	_open_card_flip({"values": {"coins": coins}})
	var host: Gen2CardFlipScreen = _card_flip_host
	if host == null:
		return
	for _frame: int in maxi(frames, 0):
		if _card_flip_host == null:
			break
		## The `WaitSFX` steps are the driver's, and a screenshot spends no wall
		## clock for an effect to finish in, so each is cut rather than waited
		## out, the way `preview_slot_machine` does it.
		if _audio_player != null and host.game() != null \
			and host.game().waiting_for_sfx():
			_audio_player.stop_effects()
		host.advance_frame()
		match host.prompt():
			Gen2CardFlip.Prompt.YES_NO, Gen2CardFlip.Prompt.PRESS, \
			Gen2CardFlip.Prompt.CHOOSE, Gen2CardFlip.Prompt.BET:
				host.handle_button(Gen2Button.A)
			_:
				pass


## Public screenshot driver and scene-test entry for `special UnownPuzzle`,
## which only the four Ruins of Alph chambers reach and no fixture cell does.
## [param puzzle] is the `UNOWNPUZZLE_*` index the chamber's own `setval` names.
## Long enough for any of the puzzle's own effects to finish under the driver.
const PUZZLE_WAIT_FRAME_CAP: int = 240


## [param solve] walks the board into `.SolvedPuzzleConfiguration` through the
## screen's own presses, which is the only way to photograph the assembled
## picture: nothing else puts a piece anywhere.
func preview_unown_puzzle(puzzle: int, solve: bool = false) -> void:
	if _world == null or _data == null or _unown_puzzle_host != null:
		return
	_open_unown_puzzle({"values": {"puzzle": puzzle}})
	if not solve or _unown_puzzle_host == null:
		return
	var board: Gen2UnownPuzzle = _unown_puzzle_host.board()
	for piece: int in range(1, Gen2UnownPuzzle.PIECES + 1):
		_walk_puzzle_cursor(_puzzle_cell_of(board, piece))
		_press_puzzle_a()
		_walk_puzzle_cursor(_puzzle_cell_of(board, piece, true))
		_press_puzzle_a()


## `UnownPuzzle_A` ends on `WaitSFX` and the loop reads nothing until it
## returns, so a driver spending no frames would have its next press swallowed.
func _press_puzzle_a() -> void:
	var host: Gen2UnownPuzzleScreen = _unown_puzzle_host
	if host == null:
		return
	host.handle_button(Gen2Button.A)
	host.release_button(Gen2Button.A)
	## The wait is the driver's, and a screenshot spends no wall clock for it to
	## finish in, so the effect is cut rather than waited out: `SFXChannelsOff`
	## is what the cartridge itself does to a sound it will not wait for.
	if _audio_player != null:
		_audio_player.stop_effects()
	var guard: int = PUZZLE_WAIT_FRAME_CAP
	while guard > 0 and host.waiting_for_sfx():
		host.advance_frame()
		guard -= 1


## Which cell holds [param piece], or where the solved board wants it.
func _puzzle_cell_of(
	board: Gen2UnownPuzzle, piece: int, solved: bool = false
) -> int:
	for cell: int in Gen2UnownPuzzle.CELLS:
		var holds: int = Gen2UnownPuzzle.solved_piece_at(cell) if solved \
			else board.piece_at(cell)
		if holds == piece:
			return cell
	return 0


## Up and left both refuse at the edge, so pressing each a row's worth parks the
## cursor on cell 0, and the board is walked from there.
func _walk_puzzle_cursor(cell: int) -> void:
	var host: Gen2UnownPuzzleScreen = _unown_puzzle_host
	if host == null:
		return
	## Each press is released before the next: `hJoyLast` carries every held
	## button and `.Function` takes the first direction it finds, so a driver
	## that never lets go would walk up for ever.
	for _step: int in Gen2UnownPuzzle.ROWS:
		_tap_puzzle(Gen2Button.LEFT)
		_tap_puzzle(Gen2Button.UP)
	for _step: int in cell / Gen2UnownPuzzle.COLUMNS:
		_tap_puzzle(Gen2Button.DOWN)
	for _step: int in cell % Gen2UnownPuzzle.COLUMNS:
		_tap_puzzle(Gen2Button.RIGHT)


func _tap_puzzle(button: int) -> void:
	var host: Gen2UnownPuzzleScreen = _unown_puzzle_host
	if host == null:
		return
	host.handle_button(button)
	host.release_button(button)


## Public screenshot driver and scene-test entry for `OverworldHatchEgg`: it
## stands an egg with one cycle left in the first party slot of an injected
## save, spends the egg step, and opens the sequence on whatever hatched.
##
## [param species] is what is inside the egg; 0 takes the first species the
## cache holds, so the driver works on all three without a table.
## One of the five fade specials on the map that is already open, for a
## screenshot. The frames it spends are the script's on the real path, so this
## opens the fade and the caller advances into it.
func preview_script_fade(special: int) -> void:
	if not Gen2WorldScriptRunner.FADE_ORDERS_OF.has(special):
		return
	_start_script_fade({
		"orders": Gen2WorldScriptRunner.FADE_ORDERS_OF[special],
		"white_fill": special in Gen2WorldScriptRunner.FADE_WHITE_FILL_SPECIALS,
		"step_frames": Gen2WorldPalette.BATTLE_TOWER_FADE_STEP_FRAMES \
			if special == Gen2WorldScriptRunner.SPECIAL_BATTLE_TOWER_FADE \
			else Gen2WorldPalette.FADE_STEP_FRAMES,
	})


func preview_egg_hatch(species: int = 0) -> void:
	if _world == null or _data == null or _hatch_host != null:
		return
	var save: Gen2SaveData = _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Hatch preview needs a party"
		_refresh_labels()
		return
	var mon: Gen2SaveMon = save.party[0]
	mon.species = species if species > 0 else 1
	mon.is_egg = true
	mon.hp = 0
	mon.nickname = "EGG"
	## One cycle left, so the pass this drains is the one that hatches it.
	mon.happiness = 1
	_injected_save = save
	if Gen2WorldPartyHost.apply_egg_steps(save, 1) < 0:
		return
	var summary: Dictionary = Gen2WorldPartyHost.hatch_egg(_world, save, 0)
	if summary.is_empty():
		return
	_open_hatch([summary], save)


## The first `EVOLVE_ITEM` row this cache carries, as `{species, item}`. Walked
## rather than named, so the driver works on all three without a table.
func _first_stone_evolution() -> Dictionary:
	for species: int in range(1, _data.species_count() + 1):
		for row: Dictionary in _data.evolutions(species):
			if int(row.get("method", 0)) == RomLayout.EVOLVE_ITEM:
				return {"species": species, "item": int(row.get("parameter", 0))}
	return {}


## Public screenshot driver and scene-test entry for `EvolveAfterBattle`'s own
## presentation: it stands the first party member on the first LEVEL evolution
## the cache holds and opens the screen on it, which is the one path a stone
## cannot reach, since `.pressed_b` lets B cancel this one and not that one.
##
## The party row is left alone. [method _on_evolution_resolved] applies it, the
## same way the after-battle pass does, so the preview is that pass rather than
## a picture of it.
func preview_level_evolution() -> void:
	if _world == null or _data == null:
		return
	if _evolution_host != null:
		return
	var save: Gen2SaveData = _injected_save if _injected_save != null \
		else _embedded_party_save()
	if save == null or save.party.is_empty():
		_script_prompt = "Evolution preview needs a party"
		_refresh_labels()
		return
	_injected_save = save
	var plans: Array = Gen2Evolution.after_battle(
		_data, save, [0], _world.object_time_of_day
	)
	if plans.is_empty():
		## Only when the party's own lead has nothing due: a caller that has
		## already staged one is photographing that one.
		var row: Dictionary = _first_level_evolution()
		if row.is_empty():
			_script_prompt = "Evolution preview: this cache has no level evolution"
			_refresh_labels()
			return
		var mon: Gen2SaveMon = save.party[0]
		mon.species = int(row["species"])
		mon.level = maxi(mon.level, int(row["row"].get("parameter", mon.level)))
		mon.nickname = String(_data.species(mon.species).get("name", ""))
		mon.hp = maxi(mon.hp, 1)
		mon.status = Gen2Status.NONE
		plans = Gen2Evolution.after_battle(
			_data, save, [0], _world.object_time_of_day
		)
	_open_evolution(plans, save, Callable())


func _first_level_evolution() -> Dictionary:
	for species: int in range(1, _data.species_count() + 1):
		for row: Dictionary in _data.evolutions(species):
			if int(row.get("method", 0)) == RomLayout.EVOLVE_LEVEL:
				return {"species": species, "row": row}
	return {}


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


## Public screenshot driver for `_Option`, which is what the start menu's own
## OPTION row opens. One call, since the picture wanted is the settings screen
## and not the row that reaches it.
func preview_options() -> void:
	if _world == null or _data == null:
		return
	if _start_menu_host == null:
		_injected_save = _embedded_party_save()
		_open_start_menu()
	if _start_menu_host == null:
		return
	if not _walk_start_menu_to(Gen2WorldStartMenu.ITEM_OPTION):
		return
	_start_menu_host.handle_button(Gen2Button.A)


## Walks the open start menu's cursor onto [param kind] and answers whether it
## got there. Bounded by the row count on purpose: a row the menu is not
## offering, because its gate is shut on this save, is a cursor that never
## reaches it, and an unbounded walk there spins a core without ever rendering a
## frame. Every `preview_*` driver below goes through this.
func _walk_start_menu_to(kind: StringName) -> bool:
	if _start_menu_host == null:
		return false
	var menu: Variant = _start_menu_host.get("_menu")
	for _row: int in Gen2WorldStartMenu.SOURCE_ENTRIES.size():
		if menu.selected_kind() == kind:
			return true
		_start_menu_host.handle_button(Gen2Button.DOWN)
	if menu.selected_kind() == kind:
		return true
	_script_prompt = "The start menu is not offering %s" % kind
	_refresh_labels()
	return false


## Public screenshot driver for the Pokegear, reached the way a player reaches
## it: START and the POKEGEAR row. The picture is `Pokegear_LoadGFX`'s own card
## list, which is the layer a debug panel used to stand behind; a card opened
## from it is a full screen of its own and has its own cases.
func preview_pokegear() -> void:
	if _world == null or _data == null:
		return
	if _service_host == null and _start_menu_host == null:
		_injected_save = _embedded_party_save()
		## The row is gated on ENGINE_POKEGEAR, which a world opened straight
		## onto a map has not been given yet.
		_world.state.apply_changes({}, {}, {
			"engine_flags": {Gen2WorldStartMenu.ENGINE_POKEGEAR: true},
		})
		_open_start_menu()
	if _start_menu_host != null:
		if not _walk_start_menu_to(Gen2WorldStartMenu.ITEM_POKEGEAR):
			return
		## The row opens the overlay through the same signal a press does, so
		## the card list is up by the time this returns.
		_start_menu_host.handle_button(Gen2Button.A)


## Public screenshot drivers for `SaveMenu`, one per box it puts up:
## `WouldYouLikeToSaveTheGameText` with its yes/no, `AlreadyASaveFileText` past
## `_ContText`'s own wait, and `SavingDontTurnOffThePowerText` with no question
## behind it. An injected save keeps the write in memory, the way
## [method preview_pack_toss] keeps its stack.
func preview_save_menu() -> void:
	_preview_save_menu(0)


func preview_save_overwrite() -> void:
	_preview_save_menu(2)


func preview_save_writing() -> void:
	_preview_save_menu(3)


## [param answers] is how many A presses to spend past the first question.
func _preview_save_menu(answers: int) -> void:
	if _world == null or _data == null or _start_menu_host != null:
		return
	_injected_save = _embedded_party_save()
	_open_start_menu()
	if _start_menu_host == null:
		return
	if not _walk_start_menu_to(Gen2WorldStartMenu.ITEM_SAVE):
		return
	for _press: int in answers + 1:
		_start_menu_host.handle_button(Gen2Button.A)


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
	if not _walk_start_menu_to(Gen2WorldStartMenu.ITEM_PACK):
		return
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
	if not _walk_start_menu_to(Gen2WorldStartMenu.ITEM_PACK):
		return
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


## Public screenshot driver for `.Field`: grants [param item] on an injected
## save, opens the pack on the key items and uses it, so what is photographed is
## the world's own answer with the pack already closed behind it.
func preview_field_item(item: int = Gen2WorldPack.ITEM_ITEMFINDER) -> void:
	if _world == null or _data == null or _start_menu_host != null:
		return
	_injected_save = _embedded_party_save()
	# The coins are for the Coin Case, which is the one row here whose own words
	# are a number; every other item ignores them.
	_world.state.apply_changes({}, {}, {"items": {item: 1}, "coins": 1234})
	_open_start_menu()
	if _start_menu_host == null:
		return
	if not _walk_start_menu_to(Gen2WorldStartMenu.ITEM_PACK):
		return
	_start_menu_host.handle_button(Gen2Button.A)
	# The row itself, rather than whichever one the pocket opens on: the save may
	# already own other key items, and a capture has to photograph the named one.
	if not bool(_start_menu_host.call("_select_pack_item", item)):
		return
	# The row's submenu, and then its first action, which for a key item is USE.
	_start_menu_host.handle_button(Gen2Button.A)
	_start_menu_host.handle_button(Gen2Button.A)
	if _text_box != null:
		# The box reveals a tile at a time off wall-clock delta, and a capture
		# owning its own frames spends none on that.
		_text_box.finish()


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
	var map_size: Vector2i = _world.map_size_cells()
	var directions: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]
	for y: int in map_size.y:
		for x: int in map_size.x:
			var cell := Vector2i(x, y)
			if _world.collision_permission_at(cell) != Gen2WorldCollision.LAND_TILE:
				continue
			for direction: Vector2i in directions:
				if _world.collision_permission_at(cell + direction) != Gen2WorldCollision.WATER_TILE:
					continue
				_world.player_cell = cell
				_world.player_facing = _world.facing_for_direction(direction)
				if _renderer != null:
					_renderer.refresh()
				return


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


## `StartBattle`: the transition first, and the battle screen only once it has
## finished. `PlayBattleMusic` runs in front of `DoBattleTransition`, so the
## map's track stops and the battle's own starts here, 170 frames before the
## fight is built, and the animation is played under it rather than in silence.
func _start_battle_request(request: Dictionary) -> void:
	if _battle_host != null or _battle_transition != null or _data == null:
		return
	_play_battle_music(request)
	_battle_transition_request = request.duplicate(true)
	_battle_transition = _build_battle_transition(request)
	if _battle_transition == null:
		_open_battle_host(_battle_transition_request)
		return
	_apply_battle_transition()
	_script_prompt = "Battle starting"
	_refresh_labels()


## `StartTrainerBattle_DetermineWhichAnimation`'s two bits, and the ball only a
## trainer's own transition draws.
func _build_battle_transition(request: Dictionary) -> Gen2BattleTransition:
	if _world == null or _data == null:
		return null
	var values: Dictionary = request.get("values", {})
	if bool(values.get("tutorial", false)):
		return null
	var environment: int = _world.current_map.environment if _world.current_map != null else 0
	## `cp CAVE / cp ENVIRONMENT_5 / cp DUNGEON`, the three the flash and the
	## wavy outro belong to.
	var cave: bool = environment in Gen2WorldAPI.CAVE_ENVIRONMENTS
	var lead: int = _battle_lead_level()
	var opponent: int = int(values.get("level", lead))
	return Gen2BattleTransition.create(
		lead + Gen2BattleTransition.STRONGER_MARGIN < opponent,
		cave,
		int(values.get("trainer_class", 0)) > 0,
		_render_time_of_day() == Gen2WorldPalette.TIME_DARK,
		_encounter_random,
		_data.battle_anim_sine()
	)


## `wBattleMonLevel`, which is the party's own lead rather than the battle's:
## the transition is picked before `InitBattleMon` has run.
func _battle_lead_level() -> int:
	var save: Gen2SaveData = _injected_save if _injected_save != null \
		else _selected_runtime_save()
	if save == null or save.party.is_empty():
		return 1
	return int((save.party[0] as Gen2SaveMon).level)


## `DoBattleTransition` alone, driven to [param frames] frames in, for a
## screenshot: the transition over the map it actually runs on, without the
## battle behind it. [param trainer] is the branch that draws the Poke Ball and
## floods every background tile with `PAL_BG_TEXT`.
func preview_battle_transition(frames: int, trainer: bool = false) -> void:
	_battle_transition = Gen2BattleTransition.create(
		false, false, trainer, false, _encounter_random,
		_data.battle_anim_sine() if _data != null else PackedByteArray()
	)
	_apply_interface_mask()
	_apply_battle_transition()
	for _frame: int in maxi(frames, 0):
		if _battle_transition == null:
			break
		_battle_transition.advance_frame()
		_apply_battle_transition()


## Spends `DoBattleTransition` where the caller wants the battle rather than the
## animation in front of it, which is every driver that opens one without a
## person watching.
func settle_battle_transition(limit: int = 600) -> void:
	var guard: int = limit
	while _battle_transition != null and guard > 0:
		advance_frame()
		guard -= 1


## Whether `DoBattleTransition` is still running, which is the several seconds
## between an encounter resolving and the battle screen existing.
func battle_transition_running() -> bool:
	return _battle_transition != null


## One frame of it, and the battle behind it when the last one has been spent.
func _advance_battle_transition() -> void:
	if _battle_transition == null:
		return
	_battle_transition.advance_frame()
	_apply_battle_transition()
	if not _battle_transition.finished():
		return
	var request: Dictionary = _battle_transition_request
	_battle_transition = null
	_battle_transition_request = {}
	if _renderer != null and _renderer.has_method("clear_transition"):
		_renderer.clear_transition()
	_open_battle_host(request)


## What the transition is showing right now, handed to whatever is drawing the
## map. A renderer of a mod's own that does not take it draws the map as it was,
## which is the same contract the map fade has.
func _apply_battle_transition() -> void:
	if _renderer == null or _battle_transition == null:
		return
	if not _renderer.has_method("set_transition"):
		return
	_renderer.set_transition(
		_battle_transition.cells(),
		_data.tile_indices("battle_transition") if _data != null else PackedByteArray(),
		_data.battle_transition_palette(
			_render_time_of_day() == Gen2WorldPalette.TIME_DARK
		) if _battle_transition.ball_drawn() and _data != null else PackedColorArray(),
		_battle_transition.sprites(),
		## `hLastTalked`, which `RespawnPlayerAndOpponent` keeps beside the
		## player. A wild encounter has none and leaves the player alone.
		int(_battle_transition_request.get("values", {}).get("object_index", -1)),
		## `StartTrainerBattle_Flash` writes `wBGP` and calls `DmgToCgbBGPals`
		## alone, so this is the background's order and not the map fade's:
		## the sprites standing over the wedges keep their own colours.
		_battle_transition.palette_order(),
	)


## `PlayBattleMusic`, resolved from the request rather than from a fight that
## does not exist yet. Asking twice for the same track is what the driver
## continues, so the transition and the battle screen behind it never restart the
## piece between them.
func _play_battle_music(request: Dictionary) -> void:
	if _audio_player == null or _data == null:
		return
	var landmark: int = _world.landmark() if _world != null \
		else Gen2WorldRadio.LANDMARK_SPECIAL
	var track: int = Gen2WorldBattleAdapter.music_for(
		request, landmark, time_of_day, Gen2WorldState.is_crystal_profile(_data)
	)
	var record: Dictionary = _data.world_audio(&"music", track)
	if record.is_empty():
		_audio_player.stop_all()
		return
	_audio_player.play_record(record, &"map_music", _audio_assets())


func _open_battle_host(request: Dictionary) -> void:
	if _battle_host != null or _data == null:
		return
	var values: Dictionary = request.get("values", {})
	var tutorial: bool = bool(values.get("tutorial", false))
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	_active_battle_save = save
	_active_battle_persist = save != null and _injected_save == null
	_battles_fought += 1
	var host: Gen2BattleScreen = BATTLE_SCENE.instantiate() as Gen2BattleScreen
	host.set_data(_data)
	host.set_audio_player(_audio_player)
	host.set_rules(_world.rules if _world != null else null)
	## Drawn from the world's own generator, so the fight's own decisions are part
	## of the run's seeded chain and a replay reproduces them without recording
	## anything about the battle. Its frames and its buttons both come through this
	## screen from here on.
	host.set_random_seed(_encounter_random.randi())
	host.set_external_input(true)
	host.set_time_of_day(time_of_day)
	# The clock's row is what the battle's own heals read; the drawn row is what
	# a renderer staging the fight on this map has to match, so the context
	# carries that one.
	host.set_world_context(Gen2BattleWorldContext.capture(_world, _render_time_of_day()))
	var badges: int = _world.state.badge_mask(Gen2WorldState.is_crystal_profile(_data)) \
		if _world != null and _world.state != null else 0
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 10
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	host.battle_finished.connect(_on_battle_finished)
	host.enemy_seen.connect(_on_enemy_seen)
	if not tutorial:
		host.capture_requested.connect(_on_capture_requested)
		host.item_used.connect(_on_battle_item_used)
	_battle_host = host
	## Started after the connections and here rather than left to the host's own
	## deferred call: `startbattle` is a script command, so the fight belongs to
	## the frame the encounter fired on, and a run driven frame by frame (a check,
	## a replay) never reaches a deferred call at all.
	## `PlayBattleMusic` has already run, either in front of the transition or
	## here for a request that had none, and the fight is handed this screen's own
	## driver, so its first cry takes the channels the track is holding.
	_play_battle_music(request)
	host.start_world_battle(request.duplicate(true), save, badges)
	## After the fight exists, because starting one clears whatever capture action
	## was staged: the bag belongs to this battle rather than to the last one.
	if _world != null and not tutorial:
		## `BattleMenu_Pack`'s contest branch loads PARK_BALL and nothing else,
		## and the count is `wParkBallsRemaining` rather than the bag.
		if _world.bug_contest_active():
			host.set_capture_balls(
				[Gen2WorldPartyHost.ITEM_PARK_BALL],
				{Gen2WorldPartyHost.ITEM_PARK_BALL: _world.state.park_balls()}
			)
		else:
			host.set_capture_balls(
				Gen2WorldPartyHost.owned_capture_balls(_world), _world.state.items()
			)
			host.set_battle_pack(
				Gen2WorldPack.battle_items(_data, _world.state), _world.state.items()
			)
	## Its frames come from this screen's own pump from here on, so it must not
	## also spend real-time ones of its own.
	host.set_process(false)
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
	## The ball is thrown from a party that has already fought: the catch's own
	## candidate is built from this save, so the fought HP and PP have to be on
	## it before the transaction opens.
	_battle_host.sync_live_party()
	var target: Gen2BattleMon = _battle_host.capture_target()
	## A contest throw is its own transaction: the ball is the contest's, the
	## catch goes to wContestMon and no save is touched.
	var result: Dictionary = (
		Gen2WorldPartyHost.capture_contest(_world, target, _encounter_random)
		if _world.bug_contest_active()
		else Gen2WorldPartyHost.capture_wild(
			_world, save, target, ball, _encounter_random, 0, _active_battle_persist
		)
	)
	_battle_host.complete_capture(result)
	_refresh_labels()


## `UseDisposableItem` inside a battle: the effect has already landed on the
## party the battle owns, so all the world does is take the row down by one.
func _on_battle_item_used(item: int, _target: int) -> void:
	if _world == null or _world.inventory == null:
		return
	_world.inventory.change_item_quantity(item, -1)
	if _battle_host != null:
		_battle_host.set_battle_pack(
			Gen2WorldPack.battle_items(_data, _world.state), _world.state.items()
		)
		_battle_host.set_capture_balls(
			Gen2WorldPartyHost.owned_capture_balls(_world), _world.state.items()
		)


func _on_battle_finished(result: Dictionary) -> void:
	var host: Gen2BattleScreen = _battle_host
	_battle_host = null
	if host != null:
		Gen2Screen.drop(host)
	if not String(_battle_encounter_id).is_empty():
		var fought: StringName = _battle_encounter_id
		_battle_encounter_id = &""
		if _encounters != null:
			_encounters.battle_finished(fought, result.duplicate(true))
	if _world == null:
		return
	_last_battle_outcome = StringName(result.get("outcome", &""))
	var pay_day_money: int = int(result.get("pay_day_money", 0))
	if pay_day_money > 0 and StringName(result.get("outcome", &"")) == Gen2WorldBattleAdapter.OUTCOME_WON:
		_world.state.apply_changes({}, {}, {"money": {
			0: mini(_world.state.money(0) + pay_day_money, Gen2WorldInventory.MAX_MONEY),
		}})
	## `ExitBattle`'s own tail, in its order: `CheckPayDay`, then
	## `EvolveAfterBattle`, then `GivePokerusAndConvertBerries`, and only then
	## does the map come back. The evolution owns frames, so the rest of the exit
	## is what its screen resumes into rather than something that runs behind it.
	var fought_save: Gen2SaveData = _active_battle_save
	var plans: Array = _after_battle_evolution_plans(result, fought_save)
	if not plans.is_empty():
		_open_evolution(plans, fought_save, func() -> void:
			_finish_battle_exit(result, fought_save)
		)
		return
	_finish_battle_exit(result, fought_save)


## `EvolveAfterBattle`'s `wEvolvableFlags`, read only on a battle that was won.
func _after_battle_evolution_plans(result: Dictionary, save: Gen2SaveData) -> Array:
	if _data == null or save == null or _world == null:
		return []
	if StringName(result.get("outcome", &"")) != Gen2WorldBattleAdapter.OUTCOME_WON:
		return []
	return Gen2Evolution.after_battle(
		_data, save, result.get("evolvable", []), _world.object_time_of_day
	)


## Everything `ExitBattle` does once `EvolveAfterBattle` has returned.
func _finish_battle_exit(result: Dictionary, fought_save: Gen2SaveData) -> void:
	if _world == null:
		return
	if StringName(result.get("outcome", &"")) == Gen2WorldBattleAdapter.OUTCOME_WON:
		Gen2WorldPartyHost.give_pokerus_and_convert_berries(
			_data, fought_save, _world, _encounter_random
		)
		_persist_after_battle(fought_save)
	var resumed: Array = _world.complete_runtime_request(result)
	if resumed.is_empty():
		## `WildBattleScript` is `randomwildmon`, `startbattle`,
		## `reloadmapafterbattle`, `end`: a wild encounter reloads the map on the
		## way out even though no script was suspended, and that reload is what
		## puts the five-step cooldown back so the next step cannot roll another.
		_world.reload_current_map()
		if _renderer != null:
			_renderer.refresh()
		if StringName(result.get("outcome", &"")) == Gen2WorldBattleAdapter.OUTCOME_CAUGHT:
			var capture: Dictionary = result.get("capture", {})
			if bool(capture.get("contest", false)):
				## The catch is only kept when the question the battle asked was
				## answered YES, or when there was nothing to replace, which the
				## host already stored.
				var caught_mon: Dictionary = capture.get("mon", {})
				if bool(capture.get("replace", false)) and not caught_mon.is_empty():
					_world.state.set_contest_mon(caught_mon)
				var held: Dictionary = _world.state.contest_mon()
				_script_prompt = "Contest: holding %s, %d PARK BALLs left" % [
					String(_data.species(int(held.get("species", 0))).get("name", "nothing")),
					_world.state.park_balls(),
				]
			else:
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
	## `MapSetupScript_ReloadMap`'s `ForceMapMusic`, which is `TryRestartMapMusic`:
	## a battle leaves through a map reload, and that reload is what puts the
	## map's own track back over the one `PlayBattleMusic` started.
	_play_current_map_music()
	_refresh_labels()


## `EvoStoneEffect`'s evolution, which the pack has already applied: only the
## animation is left, and it is the after-battle pass's own screen so both ways
## in draw the same thing.
func _on_pack_evolution(plan: Dictionary, after: Callable) -> void:
	## No [member _evolution_save]: the row is already written, so [method
	## _on_evolution_resolved] has nothing to apply and the dex write was the
	## pack transaction's.
	_open_evolution([plan], null, after)


## `EvolveAfterBattle`'s screen. [param plans] is
## [method Gen2Evolution.after_battle]'s list, [param save] the party they are
## applied to, and [param after] whatever the caller was doing when the pass
## interrupted it, run once the last plan has been answered.
func _open_evolution(plans: Array, save: Gen2SaveData, after: Callable) -> void:
	if _evolution_host != null or _data == null or plans.is_empty():
		if after.is_valid():
			after.call()
		return
	var host := Gen2EvolutionScreen.new()
	host.set_context(_data, plans)
	_evolution_save = save
	_evolution_after = after
	host.resolved.connect(_on_evolution_resolved)
	host.closed.connect(_on_evolution_closed)
	host.cry_requested.connect(_play_species_cry)
	host.sfx_requested.connect(_play_sfx)
	host.music_requested.connect(_play_evolution_music)
	## Into the 160x144 viewport rather than over the whole window: the first box
	## is printed over the map, so it has to be composited with it the way the
	## world's own text box is.
	host.z_index = 30
	## Held before the node enters the tree: `_ready()` runs inside
	## [method Gen2Screen.display], and a screen that closes there has to find
	## itself here to be taken off again.
	_evolution_host = host
	_screen.display(host)
	if _evolution_host == null:
		return
	_script_prompt = "Evolving"
	_refresh_labels()


## `.proceed`'s own write, or `CancelEvolution` doing nothing but printing.
## `SetSeenAndCaughtMon` and `UpdateUnownDex` are here rather than in the screen:
## the screen draws, the world owns the dex and the party.
func _on_evolution_resolved(plan: Dictionary, canceled: bool) -> void:
	if canceled or _evolution_save == null or _data == null:
		return
	var index: int = int(plan.get("index", -1))
	if index < 0 or index >= _evolution_save.party.size():
		return
	var applied: Dictionary = Gen2WorldPartyHost.apply_evolution(
		_data, _evolution_save.party[index], plan.get("row", {})
	)
	if applied.is_empty() or _world == null or _world.state == null:
		return
	_world.state.set_species_caught(int(applied["register_caught"]))
	var form: int = int(applied.get("register_unown", 0))
	if form > 0:
		_world.state.update_unown_dex(form)
	## `LearnLevelMoves` teaches whatever fits an empty slot, which
	## [method Gen2WorldPartyHost.apply_evolution] has already done. A move that
	## needs `ForgetMove` is declined here: that menu lives inside the start menu
	## screen's own mode machine and this pass has no way into it, and declining
	## is one of the two answers the cartridge takes.
	_script_prompt = "%s evolved" % String(plan.get("evolving_name", ""))


func _on_evolution_closed() -> void:
	var host: Gen2EvolutionScreen = _evolution_host
	_evolution_host = null
	_evolution_save = null
	if host != null:
		Gen2Screen.drop(host)
	if _renderer != null:
		_renderer.refresh()
	var after: Callable = _evolution_after
	_evolution_after = Callable()
	if after.is_valid():
		after.call()


## `PlayMusic` from inside the animation: MUSIC_NONE stops what the map or the
## battle left playing, and MUSIC_EVOLUTION is its own track.
func _play_evolution_music(music: int) -> void:
	if _audio_player == null or _data == null:
		return
	if music == Gen2EvolutionScreen.MUSIC_NONE:
		_audio_player.stop_all()
		return
	var record: Dictionary = _data.world_audio(&"music", music)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"map_music", _audio_assets())


## The save write `ExitBattle` owes once the evolution pass and Pokerus have
## both run over the party the battle already wrote.
func _persist_after_battle(save: Gen2SaveData) -> void:
	if save == null or not _active_battle_persist or _data == null:
		return
	var written: Dictionary = Gen2SaveStore.save(save, _data)
	if not bool(written.get("ok", false)):
		push_error("Could not save the battle exit: %s" % String(written.get("message", "")))


func _advance_script_input() -> void:
	if _text_box.advance():
		_continue_if_text_settled()
		return
	_text_box_rect_held += 1
	_text_box.visible = false
	_script_prompt = ""
	_show_script_results(_world.run_event_queue(true))
	_text_box_rect_held -= 1
	_push_text_box_rect()
	_refresh_labels()


## `Script_writetext` is `MapTextbox` and returns as soon as the string is
## placed, so a text ending in `<DONE>` owes no press of its own and the script
## runs on the moment its last page is up. The box reaches that page three ways:
## shown whole, turned to by the press that clears a `<PARA>`, or scrolled into
## by `_ContText`, and only the first two are a press. The scroll ends on a
## frame, which is why [method advance_frame] asks this as well; without it the
## last page sat there with the script still suspended and the press that closed
## the box paid for the `waitbutton` behind it, so every `<CONT>`-terminated
## text cost one press more than the cartridge spends.
func _continue_if_text_settled() -> bool:
	if _text_box == null or not _text_box.visible or _world == null:
		return false
	if _text_awaits_press or not _oak_pc_pages.is_empty():
		return false
	if _text_box.is_scrolling() or _text_box.has_pages_left():
		return false
	if StringName(_world.pending_script_input().get("type", &"")) != &"text":
		return false
	_continue_after_text()
	return true


## Runs a script on past a text that owes no press, leaving the box up: the
## cartridge closes it at `closetext`, not at the end of a `writetext`. So the
## box is taken down only where nothing is left to print into it.
func _continue_after_text() -> void:
	_text_awaits_press = true
	_text_box_rect_held += 1
	_script_prompt = ""
	_show_script_results(_world.run_event_queue(true))
	if _text_box != null and StringName(_world.pending_script_input().get("type", &"")) \
		not in [&"text", &"button"] and _world.pending_script_wait().is_empty():
		_text_box.visible = false
	_text_box_rect_held -= 1
	_push_text_box_rect()
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
## step_passes_remaining (set by
## [method Gen2WorldAPI.advance_trainer_approach_step]) is spent by the same
## frame, while step_offset() still gives the renderer 16-frame interpolation.
## [param map_pass] is whether this hardware frame runs `HandleMap`'s own pass.
## The two countdowns in front of the walk are the script's `DelayFrames` and are
## spent on every frame; the walk itself is `HandleObjectStep`'s and is not.
func _advance_trainer_approach(map_pass: bool) -> void:
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
	if not map_pass:
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
		Gen2Screen.drop(host)
		_script_prompt = "Service request unavailable"
		_refresh_labels()
		return
	host.completed.connect(_on_service_completed)
	host.sfx_requested.connect(_play_sfx)
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
		Gen2Screen.drop(host)
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
		Gen2Screen.drop(host)
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
		Gen2Screen.drop(host)
		_script_prompt = "Start menu unavailable"
		_refresh_labels()
		return
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	add_child(host)
	## `StartMenu`'s box stands over the map, so it is drawn into the screen the
	## map is already in rather than into one of the host's own.
	host.set_screen(_screen)
	host.action_chosen.connect(_on_start_menu_action)
	host.closed.connect(_on_start_menu_closed)
	host.field_item_used.connect(_on_field_item_used)
	host.evolution_animation_requested.connect(_on_pack_evolution)
	host.sfx_requested.connect(_play_sfx)
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
		Gen2Screen.drop(host)
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
	host.sfx_requested.connect(_play_sfx)
	_pokedex_host = host
	_script_prompt = "Pokedex open"
	_refresh_labels()


## The entry screen's CRY button, which is one caller of [method
## _play_species_cry] rather than a path of its own.
func _on_pokedex_cry_requested(species: int) -> void:
	_play_species_cry(species)


func _on_pokedex_closed() -> void:
	var host: Gen2PokedexScreen = _pokedex_host
	_pokedex_host = null
	if host != null:
		_pokedex_prev_entry = host.previous_entry()
		Gen2Screen.drop(host)
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
	## `ProfOaksPCBoot` waits with `JoyWaitAorB`, which loads no cursor, so no
	## page of the rating blinks an arrow however it ends. `_OakPCText2` ends in
	## `prompt` and still shows none.
	_text_box.show_text(String(_oak_pc_pages[0]), false)
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
		# `OakPCText4` and its own `JoyWaitAorB`, the same as the pages above.
		_text_box.show_text(String(pending.get("text", "")), false)
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
		Gen2Screen.drop(host)
	_script_prompt = "Trainer card closed"
	_reopen_start_menu_if_due()
	_refresh_labels()


func _on_start_menu_closed() -> void:
	var host: Gen2StartMenuScreen = _start_menu_host
	_start_menu_host = null
	if host != null:
		_start_menu_cursor = host.cursor()
		Gen2Screen.drop(host)
	_script_prompt = "Start menu closed"
	_refresh_labels()


## `PACKSTATE_QUITRUNSCRIPT`: the pack closes and the script the effect queued
## runs in the overworld. The words are the cartridge's own, read out of the
## cache by [method _field_item_text]; the host's wording behind it is only what
## a cache imported before those texts were carries.
func _on_field_item_used(request: Dictionary) -> void:
	var host: Gen2StartMenuScreen = _start_menu_host
	_start_menu_host = null
	if host != null:
		_start_menu_cursor = host.cursor()
		Gen2Screen.drop(host)
	## `.Field` reaches `ExitAllMenus`, so nothing reopens behind the effect.
	_reopen_start_menu = false
	if _world == null:
		_refresh_labels()
		return
	match StringName(request.get("effect", &"")):
		Gen2WorldPack.FIELD_EFFECT_BICYCLE:
			## `Script_GetOnBike` and `Script_GetOffBike`, both of which are a
			## line, a `waitbutton` and `special UpdatePlayerSprite`. The music is
			## the function's own rather than either script's.
			var on: bool = StringName(
				(request.get("bike", {}) as Dictionary).get("kind", &"")
			) == &"bike_on"
			var bike_name: String = _data.item_name(int(request.get("item", 0)))
			_show_field_move_text(
				"Got on the\n%s." % bike_name if on else "Got off\nthe %s." % bike_name
			)
			_play_current_map_music()
			if _renderer != null:
				_renderer.refresh()
		Gen2WorldPack.FIELD_EFFECT_ESCAPE_ROPE:
			_show_field_move_text(_field_item_text("escape_rope", "Used an\nESCAPE ROPE."))
			_refresh_after_escape()
		Gen2WorldPack.FIELD_EFFECT_ROD:
			var rods: Array[StringName] = _world.available_fishing_rods()
			select_fishing_rod(rods.find(StringName(request.get("rod", &""))))
			start_fishing()
		Gen2WorldPack.FIELD_EFFECT_ITEMFINDER:
			## `.Script_FoundSomething` runs `.ItemfinderSound` before its line;
			## `.Script_FoundNothing` plays nothing at all.
			if bool(request.get("found", false)):
				_start_sound_schedule(Gen2WorldScriptRunner.itemfinder_sounds())
				_advance_sound_schedule()
			_show_field_move_text(
				_field_item_text(
					"itemfinder_nearby",
					"Yes! ITEMFINDER\nindicates there's\nan item nearby."
				) if bool(request.get("found", false)) \
				else _field_item_text(
					"itemfinder_nope", "Nope! ITEMFINDER\nisn't responding."
				)
			)
		Gen2WorldPack.FIELD_EFFECT_SACRED_ASH:
			_show_field_move_text(
				_field_item_text("sacred_ash", "#MON were all\nhealed!")
			)
		## `farsjump CardKeySlotScript` and `farsjump BasementDoorScript`, each
		## `QueueScript`d by its own routine, so both run as any map script does.
		Gen2WorldPack.FIELD_EFFECT_CARD_KEY, Gen2WorldPack.FIELD_EFFECT_BASEMENT_KEY:
			_show_script_results(_world.queue_item_script(request))
		## `.SquirtbottleScript`, whose `callasm` picks between the tree's own
		## script and the line it says when nothing is in front of the player.
		Gen2WorldPack.FIELD_EFFECT_SQUIRTBOTTLE:
			if StringName(request.get("kind", &"")) == &"squirtbottle_watered":
				_show_script_results(_world.queue_item_script(request))
			else:
				_show_field_move_text(_field_item_text(
					"squirtbottle", "Sprinkled water.\nBut nothing\nhappened…"
				))
	_refresh_labels()


## One of `data/text/common_2.asm`'s field-item lines, with `<PLAYER>` filled
## from the world the way every other text's marker is. [param fallback] is what
## a cache imported before these texts were carries instead.
func _field_item_text(key: String, fallback: String) -> String:
	var text: String = _data.menu_text(key) if _data != null else ""
	if text.is_empty():
		return fallback
	return text.replace(
		Gen2WorldPC.PLAYER_MARKER, _world.player_name() if _world != null else ""
	)


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
		Gen2Screen.drop(host)
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
	host.sfx_requested.connect(_play_sfx)
	## `OpenPartyStats`' `PlayMonCry2` reaches the same player the Pokedex's own
	## CRY button does.
	host.cry_requested.connect(_on_pokedex_cry_requested)
	_party_host = host
	_script_prompt = "Party open"
	_refresh_labels()


func _on_party_closed(_result: Dictionary) -> void:
	var host: Gen2PartyScreen = _party_host
	_party_host = null
	if host != null:
		Gen2Screen.drop(host)
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
		Gen2Screen.drop(host)
	# `PokemonActionSubmenu`'s `.quit` reaches `ExitAllMenus`, so a field move
	# leaves the overworld rather than reopening the menu behind it.
	_reopen_start_menu = false
	if _world == null:
		_refresh_labels()
		return
	if StringName(action.get("kind", &"")) == &"mon_item":
		_run_mon_item_action(action)
		return
	if StringName(action.get("kind", &"")) == &"heal_transfer":
		_run_heal_transfer(action)
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
		Gen2WorldFieldMove.MOVE_FLY:
			var fly: Dictionary = _world.fly_request()
			if not bool(fly.get("ok", false)):
				## `.nostormbadge` says the badge line and `.indoors`
				## `FieldMoveFailed`; neither is a text this project imports, so
				## both get the refusal every field move shares.
				_show_field_move_text("Can't use that here.")
				return
			_open_fly_map(fly)
		Gen2WorldFieldMove.MOVE_SWEET_SCENT:
			var scent: Dictionary = _world.sweet_scent_request(_encounter_random)
			if not bool(scent.get("ok", false)):
				## `SweetScentNothing`, which is the one refusal the script has:
				## a tile no wild could be stepped into on says the same thing a
				## map with no table does.
				_show_field_move_text("Looks like there's\nnothing here…")
				return
			_show_field_move_text("%s used SWEET SCENT!" % String(action.get("name", "")))
			var found: Dictionary = scent["encounter"]
			_start_battle_request({
				"kind": &"battle_requested",
				"values": found["values"],
				"encounter": found.duplicate(true),
			})
		Gen2WorldFieldMove.MOVE_DIG:
			var dig: Dictionary = _world.dig_request()
			if not bool(dig.get("ok", false)):
				## `.CantUseDigText`, which every refusal of an escape shares.
				_show_field_move_text("Can't use that here.")
				return
			_show_field_move_text("%s used DIG!" % String(action.get("name", "")))
			_refresh_after_escape()
		Gen2WorldFieldMove.MOVE_TELEPORT:
			var teleport: Dictionary = _world.teleport_request()
			if not bool(teleport.get("ok", false)):
				_show_field_move_text("Can't use that here.")
				return
			## `_TeleportReturnText`, which names no Pokemon: the move says where
			## it is going rather than who used it.
			_show_field_move_text("Return to the last\n#MON CENTER.")
			_refresh_after_escape()
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
	var action_name: String = String(action.get("name", ""))
	if bool(result.get("ok", false)):
		_show_field_move_text(Gen2WorldPack.took_text(action_name, String(result.get("name", ""))))
		return
	match StringName(result.get("reason", &"")):
		&"not_holding":
			_show_field_move_text(Gen2WorldPack.not_holding_text(action_name))
		&"bag_full":
			_show_field_move_text(Gen2WorldPack.storage_full_text())
		_:
			_show_field_move_text(
				"%s could not hand that over (%s)." % [
					action_name, String(result.get("reason", "")),
				]
			)


## `Softboiled_MilkDrinkFunction`'s two halves, once the party menu has picked
## who is giving and who is receiving. The health moves through the world's own
## transaction, since the party it changes is a save the world owns.
func _run_heal_transfer(action: Dictionary) -> void:
	var result: Dictionary = Gen2WorldPartyHost.transfer_health(
		_world, _embedded_party_save(), int(action.get("slot", -1)),
		int(action.get("target_slot", -1)), _injected_save == null
	)
	if not bool(result.get("ok", false)):
		_show_field_move_text("It won't have any effect.")
		return
	## `PARTYMENUTEXT_HEAL_HP`, which is the line every healing item shares.
	## `ItemActionText` is followed by `JoyWaitAorB`, which loads no cursor, so
	## the line waits without an arrow the way `ProfOaksPCBoot`'s pages do.
	_show_field_move_text(
		"%s\nrecovered health!" % String(action.get("target_name", "")), false
	)


## [param blink_cursor] is whether the wait behind the line is one of the three
## routines that call `LoadBlinkingCursor`, not whether it waits at all.
func _show_field_move_text(text: String, blink_cursor: bool = true) -> void:
	_field_move_text = true
	if _text_box != null and _text_box.font != null:
		_apply_text_box_options()
		_text_box.show_text(text, blink_cursor)
		_text_box.visible = true
	_script_prompt = "A: continue"
	_refresh_labels()


## The acknowledge that closes a field-move message. A staged move commits here
## rather than when it was resolved, because Script_Cut only reaches
## CutDownTreeOrGrass after UseCutText and UsedSurfScript only reaches
## SurfStartStep after its waitbutton. A refusal has nothing staged and just
## closes.
func _acknowledge_field_move_text() -> void:
	## A text longer than the box is several `waitbutton`s, so a press with a page
	## still behind it spends itself on the box rather than on the move. A
	## one-page text closes on the first press, which is every other caller.
	if _text_box != null and _text_box.has_pages_left():
		_text_box.advance()
		return
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
				if _effects != null:
					_effects.start_headbutt_tree(applied.get("cell", Vector2i.ZERO))
			&"rock_smash_applied":
				_play_sfx(SFX_STRENGTH)
			_:
				## `OWCutAnimation` plays it, which is why the sound and the
				## animation start together.
				_play_sfx(SFX_CUT)
				if _effects != null and StringName(applied.get("kind", &"")) == &"cut_applied":
					_effects.start_cut(
						applied.get("cell", Vector2i.ZERO),
						int(applied.get("animation", 0)),
						_world.facing_direction(),
						_world.player_cell,
					)
		if _renderer != null:
			_renderer.refresh()
		_script_prompt = label
		if StringName(applied.get("kind", &"")) == &"headbutt_applied":
			## HeadbuttScript's `callasm ShakeHeadbuttTree` spends its 32 frames
			## before `callasm TreeMonEncounter`, so the roll's own result waits
			## for the animation rather than opening a battle over it.
			_pending_headbutt_finish = applied.duplicate(true)
			_refresh_labels()
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


## `PokeGear` itself, which is what the start menu's POKEGEAR entry reaches: the
## clock card, with the rest a `Pokegear_SwitchPage` away. The phone list opens
## on one card instead of the whole device.
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
		Gen2Screen.drop(host)
		_script_prompt = "%s unavailable" % label
		_refresh_labels()
		return
	host.completed.connect(_on_service_completed)
	host.sfx_requested.connect(_play_sfx)
	_service_host = host
	_script_prompt = "%s open" % label
	_refresh_labels()


## `_FlyMap` as its own overlay, and the warp its answer asks for. A cancel
## leaves the player where they were, which is what `.illegal` does with the
## `-1` a B press writes.
func _open_fly_map(request: Dictionary) -> void:
	if _service_host != null or _world == null or _data == null:
		return
	var host: Gen2WorldServiceScreen = SERVICE_SCENE.instantiate() as Gen2WorldServiceScreen
	if host == null:
		_script_prompt = "Region map scene unavailable"
		_refresh_labels()
		return
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	add_child(host)
	var save: Gen2SaveData = _injected_save if _injected_save != null \
		else _selected_runtime_save()
	if not host.open_fly_map(_world, _data, save, request):
		Gen2Screen.drop(host)
		_script_prompt = "Region map unavailable"
		_refresh_labels()
		return
	host.completed.connect(_on_service_completed)
	host.sfx_requested.connect(_play_sfx)
	_service_host = host
	_script_prompt = "Fly: choose a town"
	_refresh_labels()


## The fly map's own answer, which is not a script result: a spawn to warp to, or
## -1 for a cancel.
func _apply_fly_choice(results: Array) -> bool:
	for result: Dictionary in results:
		if StringName(result.get("kind", &"")) != &"fly_chosen":
			continue
		var spawn: int = int(result.get("spawn", -1))
		if spawn < 0:
			_refresh_labels()
			return true
		var warped: Dictionary = _world.warp_to_spawn(spawn)
		if bool(warped.get("ok", false)):
			_refresh_after_escape()
		return true
	return false


func _on_service_completed(results: Array) -> void:
	var host: Gen2WorldServiceScreen = _service_host
	_service_host = null
	if host != null:
		Gen2Screen.drop(host)
	if _apply_fly_choice(results):
		return
	# `ExitPokegearRadio_HandleMusic`: only the radio card takes the music off the
	# map, and the restart behind it is what plays whichever station was left
	# tuned, or the map's own track when none was. Every other service leaves the
	# music where it stands, which is what `_TownMap` does with the map poster.
	if host != null and host.radio_music_playing() != Gen2WorldServiceScreen.RADIO_MUSIC_SILENT:
		_play_current_map_music()
	_show_script_results(results)
	_reopen_start_menu_if_due()


func _show_script_results(results: Array) -> void:
	## Whether this result staged a text at all; whether it owes a press is
	## [method _continue_if_text_settled]'s question, asked once the loop is done.
	var continue_after_text: bool = false
	var waiting: bool = false
	var failed: bool = false
	var map_changed: bool = false
	var clock_changed: bool = false
	var recovered: bool = false
	var recovery_prompt: String = ""
	for source_result: Dictionary in results:
		var result: Dictionary = Gen2ModHost.publish(Gen2ModHost.CHANNEL_WORLD, source_result)
		## Applied before the status below, and before any branch of it that leaves
		## the loop: a command's presentation effect happened before the wait the
		## same result ends on, and a `break` that skipped this dropped it. That is
		## what left a `pokepic` undrawn, since `Script_pokepic` is followed by the
		## `cry` whose runtime request breaks out of the loop.
		for result_event: Dictionary in result.get("events", []):
			if result_event.get("type", &"") == &"presentation_special_applied" \
				and StringName(result_event.get("kind", &"")) == &"prof_oaks_pc_boot":
				open_prof_oaks_pc()
			elif result_event.get("type", &"") == &"presentation_special_applied" \
				and StringName(result_event.get("kind", &"")) == &"heal_machine_anim":
				_start_heal_machine_sounds(result_event)
			elif result_event.get("type", &"") == &"presentation_special_applied" \
				and StringName(result_event.get("kind", &"")) == &"palette_fade":
				_start_script_fade(result_event)
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
			elif result_event.get("type", &"") == &"money_window_opened":
				_show_money_window(result_event)
			elif result_event.get("type", &"") == &"money_window_closed":
				_hide_money_window()
			elif result_event.get("type", &"") == &"party_happiness_changed":
				_apply_party_happiness(result_event)
			elif result_event.get("type", &"") == &"screen_shake_requested":
				if _effects != null:
					_effects.start_screen_shake(
						int(result_event.get("strength", 0)),
						&"screen_shake",
						result_event,
					)
				_apply_world_effect_offset()
			elif result_event.get("type", &"") == &"tree_shake_requested":
				## The object animates itself for the frames the stream sleeps;
				## there is nothing for a host to start.
				pass
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
			if event_type == &"text" and event.has("unown_wall") \
				and _open_unown_wall(String(event.get("text", ""))):
				break
			if event_type == &"text" and _text_box != null and _text_box.font != null:
				## Prof Oak's PC is the one special that draws on its own and
				## whose script runs on past it, so its pages are shown first and
				## this text waits behind them.
				# `LoadBlinkingCursor` is `Paragraph`, `_ContText` and
				# `PromptText`; a `writetext` whose text ends in `done` reaches
				# none of them, so its last page carries no arrow and the script
				# runs straight on.
				_text_awaits_press = bool(event.get("prompt", true))
				if _oak_pc_pages.is_empty():
					_apply_text_box_options()
					_text_box.show_text(
						String(event.get("text", "")), _text_awaits_press
					)
					_text_box.visible = true
				_script_prompt = "A: advance text"
				continue_after_text = true
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
				if StringName(request.get("kind", &"")) == &"bug_contest_judging_requested":
					## `_BugContestJudging` scores the player, ranks them against
					## the contestants who turned up and leaves the placing in
					## wScriptVar, which the results script branches on.
					var judged: Dictionary = _world.judge_bug_contest(_encounter_random)
					var judged_results: Array = _world.complete_runtime_request({
						"ok": true,
						"script_value": int(judged.get("player_place", 0)),
						"judging": judged.duplicate(true),
					})
					_script_prompt = _bug_contest_placings_text(judged)
					_show_script_results(judged_results)
					return
				if StringName(request.get("kind", &"")) == &"party_selection_requested":
					if _open_party_selection():
						break
					continue
				if StringName(request.get("kind", &"")) == &"name_rater_requested":
					if _open_name_rater():
						break
					continue
				if StringName(request.get("kind", &"")) == &"move_deleter_requested":
					if _open_move_deleter():
						break
					continue
				if StringName(request.get("kind", &"")) == &"move_tutor_requested":
					if _open_move_tutor(request):
						break
					continue
				if StringName(request.get("kind", &"")) == &"day_care_requested":
					if _open_day_care(request):
						break
					continue
				if StringName(request.get("kind", &"")) == &"slot_machine_requested":
					if _open_slot_machine(request):
						break
					## A cartridge whose cache has no slots art gives the coins
					## back untouched rather than stopping the script.
					_show_script_results(_world.complete_runtime_request({
						"ok": true,
						"coins": int((request.get("values", {}) as Dictionary).get(
							"coins", 0
						)),
					}))
					return
				if StringName(request.get("kind", &"")) == &"card_flip_requested":
					if _open_card_flip(request):
						break
					## A cartridge whose cache has no card flip art gives the
					## coins back untouched rather than stopping the script.
					_show_script_results(_world.complete_runtime_request({
						"ok": true,
						"coins": int((request.get("values", {}) as Dictionary).get(
							"coins", 0
						)),
					}))
					return
				if StringName(request.get("kind", &"")) == &"unown_puzzle_requested":
					if _open_unown_puzzle(request):
						break
					## A cartridge whose cache has no puzzle art answers the
					## script an unsolved board rather than stopping it, which is
					## the `iftrue` the map takes either way.
					_show_script_results(_world.complete_runtime_request({
						"ok": true, "script_value": 0,
					}))
					return
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
				if StringName(request.get("kind", &"")) in \
					Gen2WorldHost.UNATTENDED_REQUESTS:
					var settled: Array = _complete_unattended_request()
					if not settled.is_empty():
						_show_script_results(settled)
						return
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
	if recovered and not recovery_prompt.is_empty():
		_script_prompt = recovery_prompt
	elif not waiting and not failed:
		_script_prompt = ""
	if clock_changed:
		_sync_host_clock()
	if _renderer != null:
		if map_changed:
			## A warp redraws the whole tilemap, so a balance window a script
			## left standing goes with it the way `closetext`'s redraw takes it.
			_hide_money_window()
			_world.reload_current_map()
			_animation.configure(_world, _render_time_of_day())
			_set_renderer_world()
			_renderer.set_time_of_day(_render_time_of_day())
			_play_current_map_music()
		else:
			_renderer.refresh()
	## Decided in the loop and spent here, because a special drawing its own
	## pages is an event on the same result as the text waiting behind them.
	if continue_after_text and _continue_if_text_settled():
		return
	_refresh_labels()


## What a map change owes the screen once the world has already applied it: the
## renderer, the animation and the music all belong to the map that is now under
## the player. A warp reached through a script goes through the script result
## instead; an escape move has no script here to carry it.
func _refresh_after_escape() -> void:
	if _world == null:
		return
	_animation.configure(_world, _render_time_of_day())
	_set_renderer_world()
	if _renderer != null:
		_renderer.set_time_of_day(_render_time_of_day())
	_play_current_map_music()
	_refresh_labels()


## One frame's worth of `ShakeGrass`, for the player and for every object that
## started a step onto grass on it.
func _spawn_grass_rustles() -> void:
	if _world == null or _effects == null:
		return
	for rustle: Dictionary in _world.take_grass_rustles():
		_effects.start_grass_rustle(
			int(rustle["object_index"]), rustle["cell"], int(rustle["frames"])
		)
	if _renderer != null and _effects.sprites_active():
		_renderer.refresh()


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


## `special DisplayCoinCaseBalance`, `..MoneyAndCoinBalance` and
## `PlaceMoneyTopRight`. Each writes the tilemap and returns, so the window
## stands over the map exactly as `Script_pokepic`'s box does and is taken away
## by the same thing: the redraw behind `closetext`.
func _show_money_window(event: Dictionary) -> void:
	if _data == null:
		return
	var drawn: Dictionary = Gen2MartPage.balance_window(
		_data, StringName(event.get("kind", &"money_top_right")),
		int(event.get("money", 0)), int(event.get("coins", 0))
	)
	if drawn.is_empty():
		return
	_hide_money_window()
	var image: Image = drawn["image"]
	_money_window = TextureRect.new()
	_money_window.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_money_window.texture = ImageTexture.create_from_image(image)
	_money_window.size = image.get_size()
	_money_window.position = Vector2(
		(drawn["at"] as Vector2i) * Gen2Font.TILE
	)
	_money_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.display(_money_window)


## Public screenshot drivers for the three, since no fixture cell reaches any of
## them: `crystal 26 2 <png> live money_top_right`, `... coin_balance` and
## `... money_and_coins`. Not `coin_case`, which is the pack's own field item.
func preview_money_top_right() -> void:
	_preview_balance_window(&"money_top_right")


func preview_coin_balance() -> void:
	_preview_balance_window(&"coin_case")


func preview_money_and_coins() -> void:
	_preview_balance_window(&"money_and_coins")


func _preview_balance_window(kind: StringName) -> void:
	if _world == null:
		return
	_show_money_window({
		"kind": kind,
		"money": _world.state.money() if _world.state != null else 0,
		"coins": _world.state.coins() if _world.state != null else 0,
	})
	_refresh_labels()


func _hide_money_window() -> void:
	if _money_window == null:
		return
	Gen2Screen.drop(_money_window)
	_money_window = null


## Whether a balance window is up, for a screenshot tool or a test that would
## otherwise have to read pixels back.
func money_window_open() -> bool:
	return _money_window != null


## `HaircutOrGrooming`'s own `call ChangeHappiness`. The row is the runner's,
## since the roll that picked it has to belong to the seeded generator; the byte
## it changes belongs to the save this screen holds.
func _apply_party_happiness(event: Dictionary) -> void:
	var save: Gen2SaveData = _embedded_party_save()
	var slot: int = int(event.get("slot", -1))
	if save == null or slot < 0 or slot >= save.party.size():
		return
	var mon: Gen2SaveMon = save.party[slot] as Gen2SaveMon
	if mon == null:
		return
	mon.happiness = Gen2WorldPartyHost.change_happiness(
		_data, mon.happiness, int(event.get("happiness_kind", 0))
	)


## `SelectMonFromParty` opened by one of `engine/events/haircut.asm`'s four
## routines. The same list the Name Rater and the move deleter open, and the
## same `_party_host` the start menu uses, so an overlay is named in one place
## and a press reaches it through one branch.
func _open_party_selection() -> bool:
	if _party_host != null or _world == null or _data == null:
		return false
	var save: Gen2SaveData = _embedded_party_save()
	if save == null:
		_script_prompt = "Party selection needs a validated save"
		return false
	var host: Gen2PartyScreen = PARTY_SCENE.instantiate() as Gen2PartyScreen
	if host == null:
		_script_prompt = "Party scene unavailable"
		return false
	host.set_context(_data, save, true)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.selection_made.connect(_on_party_selection_made)
	host.sfx_requested.connect(_play_sfx)
	host.cry_requested.connect(_on_pokedex_cry_requested)
	add_child(host)
	host.open_selection()
	_party_host = host
	_party_selection = {"save": save}
	_script_prompt = "Choose a #MON"
	_refresh_labels()
	return true


## `PartyMenuSelect`'s answer: the row for a member and the carry for CANCEL or
## B, which every one of the four routines turns into `xor a`.
func _on_party_selection_made(party_index: int) -> void:
	var host: Gen2PartyScreen = _party_host
	_party_host = null
	var save: Gen2SaveData = _party_selection.get("save", null) as Gen2SaveData
	_party_selection = {}
	if host != null:
		Gen2Screen.drop(host)
	if _world == null:
		_refresh_labels()
		return
	var result: Dictionary = {"ok": true, "party_index": -1}
	if save != null and party_index >= 0 and party_index < save.party.size():
		var mon: Gen2SaveMon = save.party[party_index] as Gen2SaveMon
		if mon != null:
			result = {
				"ok": true,
				"party_index": party_index,
				## `wPartySpecies` holds EGG for an egg slot, which is the byte
				## `HaircutOrGrooming` compares against.
				"species": Gen2WorldScriptRunner.SPECIES_EGG if mon.is_egg else mon.species,
				"nickname": _mon_display_name(mon),
				"species_name": String(_data.species(mon.species).get("name", "")),
			}
	_show_script_results(_world.complete_runtime_request(result))
	_refresh_labels()


## `Script_pokepic`'s box over the map, which is what a starter's ball and every
## other `pokepic` shows. The map stays up behind it: `MENU_BACKUP_TILES` is what
## `ClosePokepic` restores, and an overlay that is removed does that by existing.
func _show_story_picture(species: int) -> void:
	if _data == null or _world == null:
		return
	var image: Image = Gen2PokepicPage.render(
		_data, species, _world.current_map, _render_time_of_day()
	)
	if image == null:
		return
	_hide_story_picture()
	_story_picture = TextureRect.new()
	_story_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_story_picture.texture = ImageTexture.create_from_image(image)
	_story_picture.size = image.get_size()
	_story_picture.position = Vector2(
		Gen2PokepicPage.menu_box().border_position() * Gen2Font.TILE
	)
	_story_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.display(_story_picture)


## How many of `wLandmarkSignTimer`'s sixty frames the sign has left, and zero
## when there is none up. What a test or a screenshot tool waits on.
func map_name_sign_passes() -> int:
	return _map_name_sign_passes


## `InitMapNameSign`'s own decision, raised where the map load leaves it: the
## sign is a window over the bottom four rows and the map keeps moving behind it,
## which is why a connection crossing shows one without stopping the camera.
##
## Gold and Silver ship neither the routine nor `MapEntryFrameGFX`, so the world
## asks for no sign there and the page would answer none either.
func _raise_map_name_sign() -> void:
	if _world == null or _data == null:
		return
	var landmark: int = _world.map_name_sign_pending()
	_world.clear_map_name_sign()
	if landmark < 0:
		return
	_hide_map_name_sign()
	## The timer is the setup script's, not the sheet's: a cache with no
	## `MapEntryFrameGFX` spends the same sixty frames with nothing drawn in
	## them rather than skipping them.
	_map_name_sign_passes = Gen2WorldAPI.MAP_NAME_SIGN_PASSES
	var image: Image = Gen2MapNameSignPage.render(
		_data,
		_data.landmark_name(landmark),
		_world.current_map.environment if _world.current_map != null \
			else Gen2WorldAPI.ENVIRONMENT_TOWN,
		_render_time_of_day(),
	)
	if image == null:
		return
	_map_name_sign = TextureRect.new()
	_map_name_sign.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_name_sign.texture = ImageTexture.create_from_image(image)
	_map_name_sign.size = image.get_size()
	_map_name_sign.position = Vector2(0, Gen2MapNameSignPage.TOP)
	_map_name_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## `PlaceMapNameSign` returns on the frame the timer still reads 60, so the
	## window is only brought down on the frame after the one that raised it.
	_map_name_sign.visible = false
	_screen.display(_map_name_sign)


## `PlaceMapNameSign`, which counts `wLandmarkSignTimer` down a frame at a time
## and takes the window away on the frame it runs out.
func _advance_map_name_sign_pass() -> void:
	if _map_name_sign_passes <= 0:
		return
	_map_name_sign_passes -= 1
	if _map_name_sign_passes <= 0:
		_hide_map_name_sign()
		return
	if _map_name_sign != null:
		_map_name_sign.visible = true


## `PlayerEvents`' own `xor a / ld [wLandmarkSignTimer], a`, which sits behind
## `DoPlayerEvent` and is skipped for PLAYEREVENT_CONNECTION and
## PLAYEREVENT_JOYCHANGEFACING alone. Called where this screen dispatches one of
## the others, rather than keyed on a script being busy: the map's own callbacks
## are `RunMapCallback`'s work inside map setup and reach `PlayerEvents` never,
## so a queued one used to take down the very sign the map load had raised.
func _zero_map_name_sign_timer() -> void:
	_hide_map_name_sign()


## The same, for a batch of script results, since only some of them are a player
## event. `RunMapCallback`'s work is map setup and reaches `PlayerEvents` never;
## `RunSceneScript` runs its scene script and then answers carry only when that
## script set RUN_DEFERRED_SCRIPT, so a scene of bare `end`s (Route 29's two, and
## most of the map scenes in either pin) raises no event and takes no sign down.
func _zero_map_name_sign_for(results: Array) -> void:
	for result: Dictionary in results:
		match StringName((result.get("source", {}) as Dictionary).get("kind", &"")):
			&"callback":
				continue
			&"scene":
				if not bool(result.get("deferred", false)):
					continue
		_zero_map_name_sign_timer()
		return


func _hide_map_name_sign() -> void:
	_map_name_sign_passes = 0
	if _map_name_sign == null:
		return
	Gen2Screen.drop(_map_name_sign)
	_map_name_sign = null


## `DisplayUnownWords`: the chamber wall's word in a box of its own, held by
## `JoyWaitAorB`. The special stages the word as a text the runner is waiting on,
## so answering the box is what answers that wait; a cache or a map that cannot
## draw the letters falls back to the text box, which is what puts the word up
## on any host without the chamber's own tileset.
func _open_unown_wall(word: String) -> bool:
	if _world == null or _data == null or _unown_wall_box != null:
		return false
	var image: Image = Gen2UnownWallPage.render(
		_data, _world.current_tileset, _world.current_map, word, _render_time_of_day()
	)
	if image == null:
		return false
	var box: Gen2MenuBox = Gen2UnownWall.menu_box(word)
	_unown_wall_box = TextureRect.new()
	_unown_wall_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_unown_wall_box.texture = ImageTexture.create_from_image(image)
	_unown_wall_box.size = image.get_size()
	_unown_wall_box.position = Vector2(box.border_position() * Gen2Font.TILE)
	_unown_wall_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.display(_unown_wall_box)
	_script_prompt = "A or B: close the wall"
	return true


func _close_unown_wall() -> void:
	if _unown_wall_box == null:
		return
	Gen2Screen.drop(_unown_wall_box)
	_unown_wall_box = null
	_play_sfx(Gen2BattleSwitchMenu.SFX_READ_TEXT_2)
	## The wait behind the box is the staged text the special left, so the script
	## resumes on the same press the source's `CloseWindow` returns on.
	_show_script_results(_world.run_event_queue(true))


func _hide_story_picture() -> void:
	if _story_picture != null:
		Gen2Screen.drop(_story_picture)
		_story_picture = null


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


## `FadeToMapMusic`, which is what a map entered through a warp arrives behind:
## `wMusicFade` is eight and `wMusicFadeID` the map's own track, so the piece
## that was playing fades out and the new one starts where it lands. A map whose
## track is already playing keeps it, which is the routine's own `cp e`.
func _fade_to_map_music() -> void:
	if _audio_player == null or _data == null or _world == null \
		or _world.current_map == null:
		return
	_audio_player.fade_to(
		_data.world_audio(&"music", _world.state.map_music()),
		WARP_MUSIC_FADE_FRAMES, _audio_assets(),
	)


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


## An actor's one-shot outbox, drained once a world frame. A mod may not play a
## sound, so it asks for one and the host spends it: the same bargain the shiny
## pulse already has, with no dedup window needed since the mod asks once.
func _spend_actor_requests() -> void:
	if _actors == null:
		return
	for request: Dictionary in _actors.take_requests():
		if StringName(request["kind"]) == Gen2WorldActors.REQUEST_CRY:
			_play_species_cry(int(request["species"]))


## A mod's hidden-item asks, spent on the first world frame nothing else owns.
## The map's own script runs through the ordinary path, so the box, the fanfare
## and the pacing are the world screen's exactly as they are for a player walking
## onto the cell; the mod named a cell and nothing else.
##
## Only one is spent per frame, since the first one's script owns the world until
## its box is pressed past, and the rest wait in the host's queue.
func _spend_hidden_item_requests() -> void:
	if _world == null or not _world_idle_for_mod_request():
		return
	var requests: Array[Vector2i] = Gen2ModHost.instance().take_hidden_item_requests()
	for index: int in requests.size():
		var results: Array = _world.take_hidden_item(requests[index])
		if results.is_empty():
			continue
		_zero_map_name_sign_timer()
		_show_script_results(results)
		## What is left goes back, in order, rather than being dropped on the
		## floor by the drain that could only spend one of them.
		Gen2ModHost.instance().requeue_hidden_items(requests.slice(index + 1))
		return


## Nothing of the world's own is running, which is the gate [method interact]
## applies plus a box or a script still holding the screen: a request may not
## open a text box over one that is already up.
func _world_idle_for_mod_request() -> bool:
	return not _overlay_open() and not _field_move_text \
		and _oak_pc_pages.is_empty() and not _world.phone_ring_active() \
		and not _world.fishing_busy() and not _world.script_busy() \
		and (_text_box == null or not _text_box.visible)


## `Script_cry`'s own path and the Pokedex CRY button's: `PlayCry` is an effect
## and not music, so it goes through the player a script's `cry` command uses.
func _play_species_cry(species: int) -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.species_cry(species)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"cry", _audio_assets())


func _play_ledge_hop_sfx() -> void:
	_play_sfx(SFX_JUMP_OVER_LEDGE)


## `BattleAnimCmd_Sound` from a shiny pulse. The interpreter has no audio device,
## as it has none in a battle either, so the screen spends what its commands
## asked for. A cry is not one of them: the sparkle's script has no `anim_cry`.
func _play_encounter_sounds() -> void:
	for command: Dictionary in _encounters.frame_commands():
		if StringName(command["name"]) == Gen2BattleAnimScript.SOUND:
			_play_sfx(int((command["operands"] as Array)[1]))


## The machine's sounds, started where the special asked for them.
func _start_heal_machine_sounds(event: Dictionary) -> void:
	_start_sound_schedule((event.get("sounds", []) as Array).duplicate(true))
	if _effects != null:
		_effects.start_heal_machine(
			int(event.get("machine_type", 0)), int(event.get("balls", 0))
		)
	_advance_sound_schedule()


func _start_sound_schedule(schedule: Array) -> void:
	_sound_schedule = schedule
	_sound_schedule_frame = 0


## One frame of that schedule, spent from the same pump the script's own wait is.
##
## A `wait` entry is `WaitPlaySFX`, and it is a real wait only while the driver
## is being serviced: a run with no audio device leaves the channels as the last
## sound left them, so `effect_playing()` would answer true for the rest of the
## run and the schedule would never drain. The rendered-frame count is what tells
## the two apart, which is what the battle screen's own `ANIM_WAIT_SFX` does.
func _advance_sound_schedule() -> void:
	while not _sound_schedule.is_empty():
		var due: Dictionary = _sound_schedule[0]
		if bool(due.get("wait", false)):
			if _audio_player != null and _audio_player.effect_playing():
				var rendered: int = _audio_player.timeline_updates()
				if int(due.get("rendered", -1)) != rendered:
					due["rendered"] = rendered
					break
		elif int(due.get("frame", 0)) > _sound_schedule_frame:
			break
		_sound_schedule.pop_front()
		var index: int = int(due.get("index", 0))
		if StringName(due.get("kind", &"sound")) == &"music":
			_play_music(index)
		else:
			_play_sfx(index, bool(due.get("wait", false)))
	_sound_schedule_frame += 1


func _play_music(index: int) -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.world_audio(&"music", index)
	if record.is_empty():
		return
	_audio_player.play_record(record, &"map_music", _audio_assets())


## `PlaySFX`. [param waited] is the `WaitSFX` the source spends in front of a
## few of them; see [signal Gen2WorldServiceScreen.sfx_requested].
func _play_sfx(index: int, waited: bool = false) -> void:
	if _audio_player == null or _data == null:
		return
	var record: Dictionary = _data.world_audio(&"sfx", index)
	if record.is_empty():
		return
	_audio_player.play_record(
		record, &"waited_sfx" if waited else &"sound", _audio_assets()
	)


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
	var fainted: Array = []
	var happiness: Array = []
	var own_ot: Array = []
	for member: Variant in save.party:
		if member is Gen2SaveMon:
			var mon: Gen2SaveMon = member as Gen2SaveMon
			if (int(mon.pokerus) & 0x0F) != 0:
				has_pokerus = true
			happiness.append(int(mon.happiness))
			own_ot.append(_is_own_mon(save, mon))
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
			fainted.append(mon.hp <= 0)
	## The three party facts the Bug Contest's own scripts ask about, which are
	## not per-slot: whether the lead can be entered at all, the byte
	## `ContestDropOffMons` stashes, and whether what is caught can be taken home.
	var lead: Gen2SaveMon = save.party[0] if not save.party.is_empty() else null
	var second: Gen2SaveMon = save.party[1] if save.party.size() > 1 else null
	_world.set_party_summary(
		save.party.size(), has_pokerus, species, moves, names, eggs,
		{
			"lead_fainted": lead == null or lead.hp <= 0,
			"second_species": int(second.species) if second != null else 0,
			"storage_full": save.party.size() >= Gen2SaveData.MAX_PARTY \
				and not bool(save.first_empty_box_slot().get("ok", false)),
			## `VAR_BOXSPACE`, which Route 29's catching tutorial reads before it
			## offers to hand a POKé BALL over.
			"box_free_space": save.box_free_space(),
			## Per slot, for the two specials that read a happiness byte or an
			## OT: `GetFirstPokemonHappiness` and
			## `FindPartyMonThatSpeciesYourTrainerID`.
			"happiness": happiness,
			"own_ot": own_ot,
			## `CheckOwnMonAnywhere`'s answer for every species at once: a mon in
			## the party or in any box carrying the player's own ID and OT name.
			"owned_species": _owned_species(save),
		},
		fainted
	)


## `CheckOwnMon`'s three tests: the species is the caller's question, and what is
## left is the player's own ID and OT name.
func _is_own_mon(save: Gen2SaveData, mon: Gen2SaveMon) -> bool:
	return int(mon.ot_id) == int(save.player_id) \
		and mon.original_trainer == save.player_name


## `CheckOwnMonAnywhere` for every species in one walk. Its own `ret z` on an
## empty party is why an empty party owns nothing even when a box does not, and
## the Day-Care is deliberately not walked: `docs/bugs_and_glitches.md` records
## that omission as the cartridge's.
func _owned_species(save: Gen2SaveData) -> Array:
	var owned: Array = []
	if save.party.is_empty():
		return owned
	var seen: Dictionary = {}
	for member: Variant in save.party:
		if member is Gen2SaveMon and _is_own_mon(save, member as Gen2SaveMon):
			seen[int((member as Gen2SaveMon).species)] = true
	for box: Variant in save.boxes:
		if not box is Gen2SaveBox:
			continue
		for slot: Variant in (box as Gen2SaveBox).slots:
			if slot is Gen2SaveMon and _is_own_mon(save, slot as Gen2SaveMon):
				seen[int((slot as Gen2SaveMon).species)] = true
	for key: Variant in seen:
		owned.append(int(key))
	owned.sort()
	return owned


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
