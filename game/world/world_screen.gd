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
const BOX_SCENE: PackedScene = preload("res://game/save/box_screen.tscn")
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
var _text_box: Gen2TextBox = null
var _clock: Gen2WorldClock = null
var _audio_player: Gen2AudioPlayer = null
var _audio_waiting: bool = false
var _script_prompt: String = ""
var _story_picture_backdrop: ColorRect = null
var _story_picture: TextureRect = null
var _battle_host: Gen2BattleScreen = null
var _service_host: Gen2WorldServiceScreen = null
var _pc_host: Gen2BoxScreen = null
var _start_menu_host: Gen2StartMenuScreen = null
var _party_host: Gen2PartyScreen = null
## Whether a field-move message is on screen waiting for its acknowledge. The
## world is idle while it is, the same way a script text pause holds it.
var _field_move_text: bool = false
## Mirrors the source's wBattleMenuCursorPosition surviving a reopen.
var _start_menu_cursor: int = 0
var _trainer_approach: Dictionary = {}
var _active_battle_save: Gen2SaveData = null
var _active_battle_persist: bool = false
var _encounter_random := RandomNumberGenerator.new()
## NPC movement rolls from its own generator, so a seeded route keeps the same
## encounters and script results however long the player stands watching.
var _object_random := RandomNumberGenerator.new()
var _selected_rod: StringName = Gen2WorldEncounter.METHOD_OLD_ROD

@onready var _screen: Gen2Screen = %Screen
@onready var _caption: Label = %Caption
@onready var _hint: Label = %Hint


func _ready() -> void:
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
	if encounter_seed != 0:
		_encounter_random.seed = encounter_seed
		_object_random.seed = encounter_seed + 1
	else:
		_encounter_random.randomize()
		_object_random.randomize()

	_world.schedule_random = _encounter_random
	_world.script_random = _encounter_random
	_world.object_random = _object_random
	_clock = Gen2WorldClock.new(initial_hour, initial_minute, initial_day)
	time_of_day = _clock.time_of_day()
	_animation = Gen2WorldAnimation.new()
	_world.set_world_clock(initial_day, initial_hour, initial_minute)
	_world.set_object_time(initial_hour, time_of_day)
	var rods: Array[StringName] = _world.available_fishing_rods()
	if not rods.is_empty() and not rods.has(_selected_rod):
		_selected_rod = rods[0]
	_animation.configure(_world, time_of_day)
	_build_renderer()
	_audio_player = AUDIO_PLAYER_SCRIPT.new()
	_audio_player.name = "AudioPlayer"
	add_child(_audio_player)
	_play_current_map_music()
	_text_box = Gen2TextBox.new()
	_text_box.font = Gen2Font.from_data(_data)
	_text_box.reveal_speed = 0.0
	_text_box.place_at_bottom()
	_text_box.visible = false
	_screen.display(_text_box)
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
	_renderer.set_time_of_day(time_of_day)


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


func _process(delta: float) -> void:
	if _animation != null and _animation.advance(delta) and _renderer != null:
		_renderer.refresh_animation()
	if _world != null and _world.advance_player_step(delta) and _renderer != null:
		_renderer.refresh()
	if _world != null and _world.tick() and _renderer != null:
		_renderer.refresh()
	_advance_forced_movement()
	if _objects_may_move() and _world.advance_object_steps(delta, _object_random) \
		and _renderer != null:
		_renderer.refresh()
	if not _trainer_approach.is_empty():
		_advance_trainer_approach()
	if _world != null and _world.phone_ring_active():
		var ring_results: Array = _world.advance_phone_ring(delta)
		if not ring_results.is_empty():
			_show_script_results(ring_results)
		_refresh_labels()
	if _clock != null and _world != null:
		var ticks: Array = _clock.advance(delta, _world)
		_world.set_world_clock(_clock.day, _clock.hour, _clock.minute)
		if not ticks.is_empty():
			_update_time_of_day()
			if _service_host == null and _battle_host == null and _pc_host == null \
				and _start_menu_host == null and _party_host == null \
				and not _world.script_input_waiting():
				var phone_schedule: Dictionary = _world.advance_phone_schedule(
					ticks.size(), _encounter_random
				)
				var phone_results: Array = phone_schedule.get("results", [])
				if bool(phone_schedule.get("attempted", false)) and not phone_results.is_empty():
					_show_script_results(phone_results)
			_refresh_labels()
	if _audio_waiting and _audio_player != null and not _audio_player.effect_playing():
		_audio_waiting = false
		var audio_result: Dictionary = Gen2WorldHost.complete_runtime_request(
			_world, {"ok": true, "sound_finished": true}
		)
		if bool(audio_result.get("ok", false)):
			_show_script_results(audio_result.get("results", []))


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


## Wandering objects keep to themselves while anything else owns the world. A
## script may be moving those same objects, a trainer approach paces its own
## object by call count, and an overlay hides the map entirely.
func _objects_may_move() -> bool:
	return _world != null \
		and _battle_host == null and _service_host == null and _pc_host == null \
		and _start_menu_host == null and _party_host == null \
		and not _field_move_text \
		and _trainer_approach.is_empty() \
		and not _world.script_busy() \
		and not _world.phone_ring_active() \
		and not _world.fishing_busy()


func _unhandled_key_input(event: InputEvent) -> void:
	if _world == null or _battle_host != null or not event.is_pressed():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	if not _trainer_approach.is_empty():
		accept_event()
		return
	if _world.phone_ring_active():
		accept_event()
		return
	if _pc_host != null:
		if key.keycode == KEY_ESCAPE:
			_pc_host.close_embedded()
		accept_event()
		return
	if _party_host != null:
		_party_host.handle_key(key.keycode)
		accept_event()
		return
	if _field_move_text:
		if key.keycode in [KEY_SPACE, KEY_ENTER, KEY_Z]:
			_acknowledge_field_move_text()
		accept_event()
		return
	if _start_menu_host != null:
		if _start_menu_host.handle_key(key.keycode):
			accept_event()
		return
	if _service_host != null:
		if _service_host.handle_key(key.keycode):
			accept_event()
		return
	if _world.fishing_busy() and key.keycode in [KEY_SPACE, KEY_Z]:
		_handle_fishing_result(_world.advance_fishing())
		accept_event()
		return
	if _world.script_input_waiting() and key.keycode in [KEY_SPACE, KEY_Z]:
		if _text_box != null and _text_box.visible:
			_advance_script_input()
		elif StringName(_world.pending_script_input().get("type", &"")) in [
			&"choice", &"menu",
		]:
			_script_prompt = "Host choice required: call choose_script_input(choice)"
			_refresh_labels()
		elif not _world.pending_runtime_request().is_empty():
			var pending_request: Dictionary = _world.pending_runtime_request()
			if StringName(pending_request.get("kind", &"")) == &"audio_requested":
				var audio_results: Array = _handle_audio_request(pending_request)
				if not audio_results.is_empty():
					_show_script_results(audio_results)
				accept_event()
				return
			var pending_save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
			var host_result: Dictionary = Gen2WorldHost.complete_runtime_request(
				_world, {"ok": true}, pending_save,
				_injected_save == null, _encounter_random
			)
			if bool(host_result.get("ok", false)):
				_show_script_results(host_result.get("results", []))
			else:
				_script_prompt = "Host unavailable: %s" % String(
					host_result.get("reason", "unknown")
				)
				_refresh_labels()
		else:
			_show_script_results(_world.run_event_queue(true))
		accept_event()
		return
	if key.keycode in [KEY_SPACE, KEY_Z]:
		if interact():
			accept_event()
		return
	var direction := Vector2i.ZERO
	match key.keycode:
		KEY_UP, KEY_W:
			direction = Vector2i.UP
		KEY_DOWN, KEY_S:
			direction = Vector2i.DOWN
		KEY_LEFT, KEY_A:
			direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D:
			direction = Vector2i.RIGHT
		KEY_1:
			select_fishing_rod(0)
			accept_event()
			return
		KEY_2:
			select_fishing_rod(1)
			accept_event()
			return
		KEY_3:
			select_fishing_rod(2)
			accept_event()
			return
		KEY_F:
			start_fishing()
			accept_event()
			return
		KEY_P:
			_open_phone_list()
			accept_event()
			return
		KEY_ENTER, KEY_TAB:
			_open_start_menu()
			accept_event()
			return
		KEY_V:
			cycle_world_renderer()
			accept_event()
			return
		KEY_F5:
			var saved: Dictionary = persist_world_snapshot()
			_script_prompt = "World saved" if bool(saved.get("ok", false)) else "Save failed"
			_refresh_labels()
			accept_event()
			return
		_:
			# Everything the screen wants has been claimed above, so what reaches
			# here is what a renderer may have a use for.
			if Gen2ModHost.renderer_handles_input(_renderer, key):
				accept_event()
			return
	move_player(direction)
	accept_event()


## Non-key input the screen never reads, offered to the renderer on the same
## terms as the leftover keys: a free camera needs pointer and stick motion, and
## the screen has no opinion about either.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or not _renderer_input_free():
		return
	if Gen2ModHost.renderer_handles_input(_renderer, event):
		accept_event()


## Whether the overworld itself is idle. The key path reaches the renderer only
## after the same overlays, pauses and hosts have each refused the event.
func _renderer_input_free() -> bool:
	return _world != null and _battle_host == null and _service_host == null \
		and _pc_host == null and _start_menu_host == null and _party_host == null \
		and not _field_move_text \
		and _trainer_approach.is_empty() and not _world.phone_ring_active() \
		and not _world.fishing_busy() and not _world.script_input_waiting()


## Public driver for screenshot tooling and scene tests.
func move_player(direction: Vector2i) -> bool:
	if _world == null or _world.fishing_busy() or _service_host != null \
		or _pc_host != null or _start_menu_host != null or _party_host != null \
		or _field_move_text or _world.phone_ring_active() \
		or not _trainer_approach.is_empty() or _world.player_step_in_progress():
		return false
	var movement: Dictionary = _world.move_result(direction)
	if not bool(movement.get("ok", false)):
		return false
	## A whirlpool spins the player rather than moving them, so nothing a completed
	## step owes applies: no warp, no encounter, no repel step.
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
	if _world == null or _battle_host != null or _service_host != null \
		or _pc_host != null or _start_menu_host != null or _party_host != null \
		or _field_move_text or _world.phone_ring_active() or _world.fishing_busy():
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
		_renderer.set_time_of_day(time_of_day)


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
			var results: Array = _world.dispatch_script_events(cell)
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
		_party_host.handle_key(KEY_SPACE)


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
		_party_host.handle_key(KEY_SPACE)


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
		_party_host.handle_key(KEY_SPACE)


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
	_party_host.handle_key(KEY_SPACE)


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
		_start_menu_host.handle_key(KEY_SPACE)
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
		_start_menu_host.handle_key(KEY_DOWN)
	_start_menu_host.handle_key(KEY_SPACE)


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
	_script_prompt = "Cast %s. Space: wait" % String(result.get("rod_label", "ROD"))
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
			_script_prompt = "A bite! Space: reel in"
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
	if _world != null and not tutorial:
		host.set_capture_balls(
			Gen2WorldPartyHost.owned_capture_balls(_world), _world.state.items()
		)
	host.set_meta("world_battle_request", {"request": request.duplicate(true), "save": save})
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 10
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	host.battle_finished.connect(_on_battle_finished)
	if not tutorial:
		host.capture_requested.connect(_on_capture_requested)
	_battle_host = host
	_script_prompt = "Battle in progress"
	_refresh_labels()


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


## Paced by call count rather than delta time, matching the emote and
## movement-delay counters beside it and staying independent of real frame
## timing. The object's step_frames_remaining (set by
## [method Gen2WorldAPI.advance_trainer_approach_step]) is consumed one per call
## like those counters, while step_offset() still gives the renderer 16-frame
## interpolation.
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


func _open_pc_host() -> void:
	if _pc_host != null or _world == null or _data == null:
		return
	var host: Gen2BoxScreen = BOX_SCENE.instantiate() as Gen2BoxScreen
	if host == null:
		_script_prompt = "PC storage scene unavailable"
		_refresh_labels()
		return
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	var persist: bool = save != null and _injected_save == null
	if save == null:
		save = Gen2SaveStore.create_development_save(_data, 0)
		if save != null:
			save.world = _world.snapshot()
		persist = false
	if save == null:
		host.queue_free()
		_script_prompt = "PC storage requires a validated save"
		_refresh_labels()
		return
	host.set_context(_data, save, persist, true)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	host.closed.connect(_on_pc_closed)
	_pc_host = host
	_script_prompt = "PC storage open"
	_refresh_labels()


func _on_pc_closed(result: Dictionary) -> void:
	var host: Gen2BoxScreen = _pc_host
	_pc_host = null
	if host != null:
		host.queue_free()
	if _world == null:
		return
	var resumed: Array = _world.complete_runtime_request(result)
	if resumed.is_empty():
		_script_prompt = "PC storage closed"
	else:
		_show_script_results(resumed)
	_refresh_labels()


## Public driver for screenshot tooling and scene tests, mirroring
## _open_pc_host()'s shape. The Enter/Tab key branch in
## _unhandled_key_input() is the normal path.
func _open_start_menu() -> void:
	if _start_menu_host != null or _party_host != null or _service_host != null \
		or _pc_host != null or _battle_host != null or _world == null or _data == null \
		or _field_move_text \
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
	_refresh_labels()


func _on_start_menu_action(kind: StringName) -> void:
	var host: Gen2StartMenuScreen = _start_menu_host
	_start_menu_host = null
	if host != null:
		_start_menu_cursor = host.cursor()
		host.queue_free()
	match kind:
		Gen2WorldStartMenu.ITEM_POKEMON:
			_open_embedded_party()
		Gen2WorldStartMenu.ITEM_POKEGEAR:
			_open_phone_list()
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
	if _world == null or StringName(action.get("kind", &"")) != &"field_move":
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
		Gen2WorldFieldMove.MOVE_WHIRLPOOL:
			var whirlpool: Dictionary = _world.whirlpool_request()
			if not bool(whirlpool.get("ok", false)):
				_show_field_move_text(
					_whirlpool_refusal(StringName(whirlpool.get("reason", &"")))
				)
				return
			_show_field_move_text("%s used WHIRLPOOL!" % String(action.get("name", "")))
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


func _show_field_move_text(text: String) -> void:
	_field_move_text = true
	if _text_box != null and _text_box.font != null:
		_text_box.show_text(text)
		_text_box.visible = true
	_script_prompt = "Space/Enter: continue"
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
	_script_prompt = ""
	_refresh_labels()


## Cut plays SFX_PLACE_PUZZLE_PIECE_DOWN, Whirlpool plays SFX_SURF and Surf
## changes the music, so each commit reports its own audio; all three redraw,
## because each changed what the map or the player looks like.
func _commit_field_move(applied: Dictionary, label: String) -> void:
	if bool(applied.get("ok", false)):
		match StringName(applied.get("kind", &"")):
			&"surf_applied":
				_play_current_map_music()
			&"whirlpool_applied":
				_play_sfx(SFX_WHIRLPOOL)
			_:
				_play_sfx(SFX_CUT)
		if _renderer != null:
			_renderer.refresh()
		_script_prompt = label
	else:
		_script_prompt = "%s failed: %s" % [label, String(applied.get("reason", "unknown"))]
	_refresh_labels()


func _open_phone_list() -> void:
	if _service_host != null or _world == null or _data == null:
		return
	var host: Gen2WorldServiceScreen = SERVICE_SCENE.instantiate() as Gen2WorldServiceScreen
	if host == null:
		_script_prompt = "Phone scene unavailable"
		_refresh_labels()
		return
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 20
	add_child(host)
	var save: Gen2SaveData = _injected_save if _injected_save != null else _selected_runtime_save()
	var persist: bool = save != null and _injected_save == null
	if not host.open_phone_list(_world, _data, save, persist):
		host.queue_free()
		_script_prompt = "Phone list unavailable"
		_refresh_labels()
		return
	host.completed.connect(_on_service_completed)
	_service_host = host
	_script_prompt = "Phone list open"
	_refresh_labels()


func _on_service_completed(results: Array) -> void:
	var host: Gen2WorldServiceScreen = _service_host
	_service_host = null
	if host != null:
		host.queue_free()
	_show_script_results(results)


func _show_script_results(results: Array) -> void:
	var waiting: bool = false
	var failed: bool = false
	var map_changed: bool = false
	var clock_changed: bool = false
	var recovered: bool = false
	var recovery_prompt: String = ""
	for result: Dictionary in results:
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
				_text_box.show_text(String(event.get("text", "")))
				_text_box.visible = true
				_script_prompt = "Space/Enter: advance text"
			elif event_type == &"button":
				if _text_box != null:
					_text_box.visible = true
				_script_prompt = "Space/Enter: continue script"
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
					_script_prompt = "Party transaction: Space to confirm"
					continue
				if StringName(request.get("kind", &"")) in [
					&"mart_requested", &"phone_call_requested",
					&"special_phone_call_requested",
				]:
					_open_service_host()
					break
				if StringName(request.get("kind", &"")) == &"pc_requested":
					_open_pc_host()
					break
				if StringName(request.get("kind", &"")) == &"audio_requested":
					var audio_results: Array = _handle_audio_request(request)
					if not audio_results.is_empty():
						_show_script_results(audio_results)
					break
				_script_prompt = "Runtime request: %s, press Space to acknowledge" % String(
					request.get("kind", "effect")
				)
		elif status == &"recovered":
			recovered = true
		elif not bool(result.get("ok", false)):
			failed = true
			_script_prompt = "Script stopped: %s" % String(result.get("reason", "unknown"))
		for result_event: Dictionary in result.get("events", []):
			if result_event.get("type", &"") == &"pokemon_picture_requested":
				_show_story_picture(int(result_event.get("pokemon", 0)))
			elif result_event.get("type", &"") == &"pokemon_picture_closed":
				_hide_story_picture()
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
			_renderer.set_time_of_day(time_of_day)
			_play_current_map_music()
		else:
			_renderer.refresh()
	_refresh_labels()


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


## PlayMapMusic: SpecialMapMusic answers first, so a surfing player carries
## MUSIC_SURF across map loads, warps and the step back onto land.
func _play_current_map_music() -> void:
	if _audio_player == null or _data == null or _world == null or _world.current_map == null:
		return
	var track: int = Gen2WorldFieldMove.MUSIC_SURF \
		if _world.movement_mode == Gen2WorldAPI.MOVEMENT_SURF \
		else _world.current_map.music
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
		return
	var has_pokerus: bool = false
	for member: Variant in save.party:
		if member is Gen2SaveMon and (int((member as Gen2SaveMon).pokerus) & 0x0F) != 0:
			has_pokerus = true
			break
	_world.set_party_summary(save.party.size(), has_pokerus)


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
	_hint.text = "arrows/WASD move one 16px cell    raw collision %02X" % [
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
	var runtime: Node = get_node_or_null("/root/GameRuntime")
	if runtime != null and bool(runtime.call("has_selected_game")):
		return runtime.call("selected_data") as GameData
	return GameData.open_any()


func _selected_runtime_save() -> Gen2SaveData:
	var runtime: Node = get_node_or_null("/root/GameRuntime")
	if runtime != null and bool(runtime.call("has_selected_save_slot")):
		return runtime.call("selected_save") as Gen2SaveData
	return null
