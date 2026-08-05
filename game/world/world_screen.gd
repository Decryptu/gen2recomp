class_name Gen2WorldScreen
extends Control

## Development overworld screen for the first runtime slice.
##
## It intentionally takes an explicit map and starting cell rather than
## inventing save-backed map state. Later save integration belongs after the
## canonical map, inventory and event models exist.

const BACKGROUND: Color = Color("#09111f")
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const BATTLE_SCENE: PackedScene = preload("res://game/battle/battle_screen.tscn")

@export var map_group: int = 24
@export var map_number: int = 3
@export var start_cell: Vector2i = Vector2i(4, 4)
@export_range(0, 23) var hour: int = 6
@export_range(0, 3) var time_of_day: int = Gen2WorldPalette.TIME_MORNING
@export var encounter_seed: int = 0

var _data: GameData = null
var _injected_data: GameData = null
var _injected_save: Gen2SaveData = null
var _world: Gen2WorldAPI = null
var _renderer: Gen2WorldRenderer = null
var _animation: Gen2WorldAnimation = null
var _text_box: Gen2TextBox = null
var _script_prompt: String = ""
var _battle_host: Gen2BattleScreen = null
var _encounter_random := RandomNumberGenerator.new()

@onready var _screen: Gen2Screen = %Screen
@onready var _caption: Label = %Caption
@onready var _hint: Label = %Hint


func _ready() -> void:
	_data = _injected_data if _injected_data != null else (
		GameRuntime.selected_data() if GameRuntime.has_selected_game() else GameData.open_any()
	)
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

	_world = Gen2WorldAPI.open(_data, map_group, map_number, start_cell)
	if _world == null:
		_caption.text = "Map %d/%d unavailable" % [map_group, map_number]
		_hint.text = "Choose an imported map and starting cell in the scene settings."
		return
	if encounter_seed != 0:
		_encounter_random.seed = encounter_seed
	else:
		_encounter_random.randomize()

	_animation = Gen2WorldAnimation.new()
	_world.set_object_time(hour, time_of_day)
	_animation.configure(_world, time_of_day)
	_renderer = Gen2WorldRenderer.new()
	_renderer.set_world(_world, _animation)
	_renderer.set_time_of_day(time_of_day)
	_screen.display(_renderer)
	_text_box = Gen2TextBox.new()
	_text_box.font = Gen2Font.from_data(_data)
	_text_box.reveal_speed = 0.0
	_text_box.place_at_bottom()
	_text_box.visible = false
	_screen.display(_text_box)
	_refresh_labels()


func _process(_delta: float) -> void:
	if _animation != null and _animation.tick() and _renderer != null:
		_renderer.refresh_animation()
	if _world != null and _world.tick() and _renderer != null:
		_renderer.refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if _world == null or _battle_host != null or not event.is_pressed():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	if _world.script_input_waiting() and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_Z]:
		if _text_box != null and _text_box.visible:
			_advance_script_input()
		else:
			_show_script_results(_world.run_event_queue(true))
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
		_:
			return
	move_player(direction)
	accept_event()


## Public driver for screenshot tooling and scene tests.
func move_player(direction: Vector2i) -> bool:
	if _world == null:
		return false
	var movement: Dictionary = _world.move_result(direction)
	if not bool(movement.get("ok", false)):
		return false

	var transition: Dictionary = movement
	if movement.get("kind", &"") == &"move":
		transition = _world.try_warp()
	if _renderer != null:
		if bool(transition.get("ok", false)) and transition.get("kind", &"") != &"move":
			_animation.configure(_world, time_of_day)
			_renderer.set_world(_world, _animation)
		else:
			_renderer.refresh()
	_refresh_labels()
	var sight_results: Array = _world.dispatch_sight_events()
	if sight_results.is_empty():
		sight_results = _world.dispatch_script_events()
	if not sight_results.is_empty():
		_show_script_results(sight_results)
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
		"battle_active": _battle_host != null,
		"script_prompt": _script_prompt,
	}


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


## Public screenshot driver for the battle-request host path. It starts the
## same request shape emitted by [Gen2WorldScriptRunner], without pretending a
## map event was present in the selected development map.
func preview_battle_request() -> void:
	_start_battle_request({
		"kind": &"battle_requested",
		"values": {"kind": &"wild", "pokemon": 16, "level": 5},
	})


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


func _start_battle_request(request: Dictionary) -> void:
	if _battle_host != null or _data == null:
		return
	var save: Gen2SaveData = _injected_save if _injected_save != null else GameRuntime.selected_save()
	var host: Gen2BattleScreen = BATTLE_SCENE.instantiate() as Gen2BattleScreen
	host.set_data(_data)
	host.set_meta("world_battle_request", {"request": request.duplicate(true), "save": save})
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.z_index = 10
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	host.battle_finished.connect(_on_battle_finished)
	_battle_host = host
	_script_prompt = "Battle in progress"
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
		_script_prompt = "Battle finished: %s" % String(
			result.get("outcome", result.get("reason", "unknown"))
		)
	else:
		_show_script_results(resumed)
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


func _show_script_results(results: Array) -> void:
	var waiting: bool = false
	var failed: bool = false
	var map_changed: bool = false
	var recovered: bool = false
	var recovery_prompt: String = ""
	for result: Dictionary in results:
		var status: StringName = StringName(result.get("status", &""))
		if status == &"waiting":
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
			elif event_type == &"menu":
				_script_prompt = "Menu request: %s, choose an entry or press Space" % String(
					event.get("menu_kind", "menu")
				)
			elif event_type == &"runtime_request":
				var request: Dictionary = event.get("request", {})
				if StringName(request.get("kind", &"")) == &"battle_requested":
					_start_battle_request(request)
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
			if result_event.get("type", &"") == &"warp":
				map_changed = true
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
	if _renderer != null:
		if map_changed:
			_world.reload_current_map()
			_animation.configure(_world, time_of_day)
			_renderer.set_world(_world, _animation)
			_renderer.set_time_of_day(time_of_day)
		else:
			_renderer.refresh()
	_refresh_labels()


func _refresh_labels() -> void:
	_caption.text = "%s   map %d/%d   cell %d,%d" % [
		_data.title(), _world.current_map.group, _world.current_map.number,
		_world.player_cell.x, _world.player_cell.y,
	]
	_hint.text = "arrows/WASD move one 16px cell    raw collision %02X" % [
		_world.collision_code_at(_world.player_cell),
	]
	if not _script_prompt.is_empty():
		_hint.text += "    " + _script_prompt
