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

@export var map_group: int = 10
@export var map_number: int = 17
@export var start_cell: Vector2i = Vector2i(4, 4)
@export_range(0, 23) var hour: int = 6
@export_range(0, 3) var time_of_day: int = Gen2WorldPalette.TIME_MORNING

var _data: GameData = null
var _world: Gen2WorldAPI = null
var _renderer: Gen2WorldRenderer = null
var _animation: Gen2WorldAnimation = null
var _text_box: Gen2TextBox = null
var _script_prompt: String = ""

@onready var _screen: Gen2Screen = %Screen
@onready var _caption: Label = %Caption
@onready var _hint: Label = %Hint


func _ready() -> void:
	_data = GameRuntime.selected_data() if GameRuntime.has_selected_game() else GameData.open_any()
	_build_world()


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


func _unhandled_key_input(event: InputEvent) -> void:
	if _world == null or not event.is_pressed():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	if _text_box != null and _text_box.visible and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_Z]:
		_advance_script_input()
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
	_show_script_results(_world.dispatch_script_events())
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
		"script_prompt": _script_prompt,
	}


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
	for result: Dictionary in results:
		if StringName(result.get("status", &"")) == &"waiting":
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
		elif not bool(result.get("ok", false)):
			failed = true
			_script_prompt = "Script stopped: %s" % String(result.get("reason", "unknown"))
		for result_event: Dictionary in result.get("events", []):
			if result_event.get("type", &"") == &"warp":
				map_changed = true
	if not waiting and not failed:
		_script_prompt = ""
	if _renderer != null:
		if map_changed:
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
