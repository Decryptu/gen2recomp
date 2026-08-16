extends GutTest

## The interface seam a native-layer renderer gets: how opaque the screen draws
## its own text box, and where that box is, plus the seam a mod's world actor
## gets, which is the same shape one layer down. Both screens are the production
## paths; only the renderer and the actor are synthetic.
##
## The contract is that the box stays the screen's. A renderer asks and is told;
## it never draws or moves the box, and the frame and the glyphs are opaque
## whatever it asks for, so nothing it can request makes text harder to read.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const NATIVE_SOURCE: String = """extends Node2D

var rects: Array = []

func set_world(_world, _animation = null) -> void:
	pass

func set_time_of_day(_time_of_day: int) -> void:
	pass

func set_battle_data(_data) -> bool:
	return true

func set_view(_view: Dictionary) -> void:
	pass

func refresh() -> void:
	pass

func refresh_animation() -> void:
	pass

func uses_hardware_viewport() -> bool:
	return false

func interface_opacity() -> float:
	return 0.75

func set_text_box_rect(rect: Rect2i) -> void:
	rects.append(rect)
"""

## The same request from a renderer drawing in hardware pixels, which cannot be
## honoured: it paints the field the box sits on, and a hole in the box would
## show the window behind the screen.
const HARDWARE_SOURCE: String = """extends Node2D

func set_world(_world, _animation = null) -> void:
	pass

func set_time_of_day(_time_of_day: int) -> void:
	pass

func refresh() -> void:
	pass

func refresh_animation() -> void:
	pass

func interface_opacity() -> float:
	return 0.25
"""

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null
var _battle_screen: Gen2BattleScreen = null


func before_each() -> void:
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	Gen2ModHost.reset()


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	if is_instance_valid(_battle_screen):
		_battle_screen.free()
		_battle_screen = null
	Gen2ModHost.reset()
	RomCache.clear(Fixture.directory())


func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script


func _open_world(source: String) -> Node:
	assert_true(Gen2ModHost.instance().register_world_renderer(&"native", _script(source))["ok"])
	assert_true(Gen2ModHost.instance().select_world_renderer(&"native")["ok"])
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	return _world_screen._renderer


func _open_battle() -> Node:
	assert_true(
		Gen2ModHost.instance().register_battle_renderer(&"native", _script(NATIVE_SOURCE))["ok"]
	)
	assert_true(Gen2ModHost.instance().select_battle_renderer(&"native")["ok"])
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_battle_screen = packed.instantiate() as Gen2BattleScreen
	_battle_screen.set_data(_data)
	add_child(_battle_screen)
	await get_tree().process_frame
	return _battle_screen._renderer


func test_a_native_layer_renderer_gets_the_field_it_asked_for() -> void:
	await _open_world(NATIVE_SOURCE)
	var box: Gen2TextBox = _world_screen._text_box
	assert_almost_eq(box.field_opacity, 0.75, 0.001)

	box.show_text("HI")
	box.finish()
	var image: Image = box.texture.get_image()
	# The field is drawn through and the ink is not: two alphas, and the opaque
	# one is the black the frame and the glyphs are drawn in.
	assert_almost_eq(image.get_pixel(80, 24).a, 0.75, 0.01)
	var opaque: Color = image.get_pixel(0, 0)
	assert_eq(opaque.a, 1.0)
	assert_eq(Color(opaque.r, opaque.g, opaque.b), Color.BLACK)


func test_a_hardware_viewport_renderer_cannot_ask_for_one() -> void:
	await _open_world(HARDWARE_SOURCE)
	assert_eq(_world_screen._text_box.field_opacity, 1.0)


func test_the_built_in_renderer_leaves_the_box_solid() -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	assert_eq(_world_screen._text_box.field_opacity, 1.0)
	var image: Image = _world_screen._text_box.texture.get_image()
	assert_eq(image.get_pixel(80, 24), Color.WHITE)


func test_the_world_renderer_is_told_where_the_box_is_and_when_it_is_gone() -> void:
	var renderer: Node = await _open_world(NATIVE_SOURCE)
	# Hidden until something is said, which is what the map shows.
	assert_eq((renderer.get("rects") as Array).back(), Rect2i())

	_world_screen._text_box.visible = true
	assert_eq(
		(renderer.get("rects") as Array).back(),
		Rect2i(0, Gen2TextBox.STANDARD_TOP * Gen2Font.TILE, 160, 48)
	)
	_world_screen._text_box.visible = false
	assert_eq((renderer.get("rects") as Array).back(), Rect2i())


func test_the_battle_screen_opens_the_same_seam() -> void:
	var renderer: Node = await _open_battle()
	assert_almost_eq(_battle_screen._box.field_opacity, 0.75, 0.001)
	# A battle's box is never hidden, the way the cartridge keeps it on the map.
	assert_eq(
		(renderer.get("rects") as Array).back(),
		Rect2i(0, Gen2TextBox.STANDARD_TOP * Gen2Font.TILE, 160, 48)
	)


## A mod's world actor, driven by the screen rather than by a view: the world it
## is handed, one advance per world frame, and the resolved sprites reaching the
## renderer that draws them.
const ACTOR_SOURCE: String = """extends RefCounted

var world = null
var frames: int = 0

func set_world(value) -> void:
	world = value

func advance_frame() -> void:
	frames += 1

func sprites() -> Array:
	return [{"icon": 1, "position_cells": Vector2(3, 4)}]
"""


func test_a_registered_world_actor_is_driven_by_the_screen_and_drawn_by_the_view() -> void:
	var actor: Object = _script(ACTOR_SOURCE).new()
	assert_true(Gen2ModHost.instance().register_world_actor(&"follower", actor)["ok"])
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	## The screen owns the frames it spends, so take its processing away before
	## counting them.
	_world_screen.set_process(false)
	assert_eq(actor.get("world"), _world_screen._world)
	var before: int = int(actor.get("frames"))
	_world_screen.advance_frames(3)
	assert_eq(int(actor.get("frames")), before + 3)
	var drawn: Array = _world_screen._actors.sprites()
	assert_eq(drawn.size(), 1)
	assert_eq((drawn[0]["sprite"] as Gen2WorldSprite).icon_number, 1)
	assert_eq(drawn[0]["position_cells"], Vector2(3, 4))
	assert_eq(_world_screen._renderer._actors, _world_screen._actors)
