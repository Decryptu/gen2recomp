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

@export var map_group: int = 1
@export var map_number: int = 1
@export var start_cell: Vector2i = Vector2i(3, 1)

var _data: GameData = null
var _world: Gen2WorldAPI = null
var _renderer: Gen2WorldRenderer = null
var _animation: Gen2WorldAnimation = null

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
	_animation.configure(_world)
	_renderer = Gen2WorldRenderer.new()
	_renderer.set_world(_world, _animation)
	_screen.display(_renderer)
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
	var moved: bool = _world.move(direction)
	if moved:
		var transition: Dictionary = _world.try_warp()
		if _renderer != null:
			if bool(transition.get("ok", false)):
				_animation.configure(_world)
				_renderer.set_world(_world, _animation)
			else:
				_renderer.refresh()
		_refresh_labels()
	return moved


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
	}


func _refresh_labels() -> void:
	_caption.text = "%s   map %d/%d   cell %d,%d" % [
		_data.title(), _world.current_map.group, _world.current_map.number,
		_world.player_cell.x, _world.player_cell.y,
	]
	_hint.text = "arrows/WASD move one 16px cell    raw collision %02X" % [
		_world.collision_code_at(_world.player_cell),
	]
