extends GutTest

## Scene integration for the renderer input hook. The fixture is synthetic, but
## the world screen and mod host are the production paths.
##
## The contract under test is an order, not a keymap: the screen claims what it
## needs and offers the rest, so a renderer can own a camera and still never be
## in a position to move the player.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const RENDERER_SOURCE: String = """extends Node2D

var seen: Array = []

func set_world(_world, _animation = null) -> void:
	pass

func set_time_of_day(_time_of_day: int) -> void:
	pass

func refresh() -> void:
	pass

func refresh_animation() -> void:
	pass

func handle_world_input(event) -> bool:
	seen.append(event.keycode)
	return event.keycode == KEY_Q
"""

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	_data = Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	Gen2ModHost.reset()


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	Gen2ModHost.reset()
	RomCache.clear(Fixture.directory())


func _open_world_with_renderer() -> Node:
	var script := GDScript.new()
	script.source_code = RENDERER_SOURCE
	script.reload()
	assert_true(Gen2ModHost.instance().register_world_renderer(&"camera", script)["ok"])
	assert_true(Gen2ModHost.instance().select_world_renderer(&"camera")["ok"])
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	var world := Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6)
	)
	var save := Gen2SaveStore.create_development_save(_data, 0)
	save.world = world.snapshot()
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame
	return _world_screen._renderer


func _press(keycode: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	return key


func test_a_renderer_receives_the_keys_the_screen_does_not_use() -> void:
	var renderer: Node = await _open_world_with_renderer()
	assert_true(renderer.has_method(Gen2ModHost.RENDERER_INPUT_METHOD))
	_world_screen._unhandled_key_input(_press(KEY_Q))
	assert_eq(renderer.get("seen"), [KEY_Q])


func test_a_renderer_never_receives_a_movement_or_interaction_key() -> void:
	var renderer: Node = await _open_world_with_renderer()
	var before: Vector2i = _world_screen._world.player_cell
	_world_screen._unhandled_key_input(_press(KEY_RIGHT))
	_world_screen._unhandled_key_input(_press(KEY_SPACE))
	# The screen claimed both: the player moved, and neither key was offered on.
	assert_ne(_world_screen._world.player_cell, before)
	assert_eq(renderer.get("seen"), [])


func test_an_open_overlay_keeps_leftover_keys_from_the_renderer() -> void:
	var renderer: Node = await _open_world_with_renderer()
	_world_screen._open_start_menu()
	await get_tree().process_frame
	assert_not_null(_world_screen._start_menu_host)
	_world_screen._unhandled_key_input(_press(KEY_Q))
	assert_eq(renderer.get("seen"), [])


func test_a_renderer_without_the_hook_leaves_the_screen_unchanged() -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	# The built-in renderer takes no input, so an unused key stays unused.
	assert_false(_world_screen._renderer.has_method(Gen2ModHost.RENDERER_INPUT_METHOD))
	_world_screen._unhandled_key_input(_press(KEY_Q))
