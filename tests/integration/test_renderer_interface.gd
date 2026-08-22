extends GutTest

## The interface seam a native-layer renderer gets: how opaque the screen draws
## its own text box, where that box is, when a screen laid out in 160x144 takes
## the picture over it, and whether the surface it is handed fills the window.
## Plus the seam a mod's world actor gets, which is the same shape one layer
## down. Both screens are the production paths; only the renderer and the actor
## are synthetic.
##
## The contract is that the box stays the screen's. A renderer asks and is told;
## it never draws or moves the box, and the frame and the glyphs are opaque
## whatever it asks for, so nothing it can request makes text harder to read.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const NATIVE_SOURCE: String = """extends Node2D

var rects: Array = []
var masks: Array = []
var screens: Array = []

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

func set_interface_masked(masked: bool) -> void:
	masks.append(masked)

func set_screen_rect(rect: Rect2i) -> void:
	screens.append(rect)
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
	# SCREEN FILL is what half of this file measures, and the persisting a zoom
	# step does must not reach the developer's own options file.
	Gen2OptionsStore.use_test_path()
	Gen2OptionsStore.current().screen_fill = true
	_forget_view()
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
	_forget_view()
	RomCache.clear(Fixture.directory())


## Choosing a view writes the installation's own file, so a test that chooses one
## puts it back rather than leaving the player on a renderer a test registered.
func _forget_view() -> void:
	DirAccess.remove_absolute(Gen2ModState.PATH)
	Gen2ModState.reload()


func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script


func _open_world(source: String) -> Node:
	assert_true(Gen2ModHost.instance().register_world_renderer(&"native", _script(source))["ok"])
	assert_true(Gen2ModHost.instance().select_view(&"native")["ok"])
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
	assert_true(Gen2ModHost.instance().select_view(&"native")["ok"])
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


## The screen owns everything above the renderer, so a renderer built after the
## text box, which is what cycling back to the built-in one does, still goes
## below it. Before this the fresh view was appended after the live box and
## painted over the words being read.
func test_a_renderer_rebuilt_mid_scene_stays_below_the_live_text_box() -> void:
	await _open_world(HARDWARE_SOURCE)
	var box: Gen2TextBox = _world_screen._text_box
	box.show_text("HI")
	box.finish()
	box.visible = true
	var texture: Texture2D = box.texture

	assert_true(Gen2ModHost.instance().select_view(&"gen2")["ok"])
	_world_screen._build_renderer()
	var viewport: SubViewport = _world_screen._screen.viewport()
	var interface: Control = _world_screen._screen.interface_layer()
	assert_eq(_world_screen._renderer.get_parent(), viewport, "still in the viewport")
	assert_eq(box.get_parent(), interface, "the box is on the interface layer")
	assert_true(
		viewport.get_children().find(_world_screen._renderer)
			< viewport.get_children().find(interface),
		"and below the box rather than over it"
	)
	assert_eq(_world_screen._text_box, box, "the same live box node")
	assert_eq(box.texture, texture, "with the glyphs it was already showing")
	assert_true(box.visible)
	## And the view it replaced is off the screen on the frame it was replaced,
	## not at the end of it: `queue_free` alone would leave the old one drawn
	## under the new for one frame, which is a stale layer a screenshot catches.
	assert_eq(_dropped_on(viewport), 0, "the old view is off the screen, not under the new")


## The same rule in the battle screen, whose box is never hidden at all.
func test_a_battle_renderer_rebuilt_mid_scene_stays_below_the_interface() -> void:
	await _open_battle()
	assert_true(Gen2ModHost.instance().select_view(&"gen2")["ok"])
	_battle_screen._build_renderer()
	var viewport: SubViewport = _battle_screen._screen.viewport()
	var children: Array = viewport.get_children()
	var interface: Control = _battle_screen._screen.interface_layer()
	assert_eq(children.find(_battle_screen._renderer), 0, "the renderer is the floor")
	assert_eq(_battle_screen._box.get_parent(), interface)
	assert_true(children.find(interface) > 0)
	assert_eq(_dropped_on(viewport), 0, "the old view is off the screen, not under the new")


## How many of the viewport's children are already dead: `queue_free` alone
## leaves a replaced node in the tree, and drawn, until the frame ends.
func _dropped_on(viewport: SubViewport) -> int:
	var count: int = 0
	for child: Node in viewport.get_children():
		if child.is_queued_for_deletion():
			count += 1
	return count


## A page turn hides the box and the next event shows it again inside one call,
## so the rectangle a renderer composes around must not go empty between them: a
## 3D view told the box had closed pans back to the player and away again.
func test_one_conversation_never_publishes_an_empty_text_box_rect_between_pages() -> void:
	var raw: Callable = func(source_opcode: int) -> int:
		return Gen2WorldScript.raw_opcode(source_opcode, true)
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), {
		Gen2WorldScript.pointer_key(Fixture.BANK, Fixture.TRAINER_SCRIPT): [
			raw.call(0x90),
		],
		Gen2WorldScript.pointer_key(Fixture.BANK, Fixture.TUTORIAL_SCRIPT): [
			Gen2WorldScript.OPENTEXT,
			Gen2WorldScript.WRITETEXT,
			Fixture.SEEN_TEXT & 0xFF, Fixture.SEEN_TEXT >> 8,
			Gen2WorldScript.WAITBUTTON,
			Gen2WorldScript.WRITETEXT,
			Fixture.WIN_TEXT & 0xFF, Fixture.WIN_TEXT >> 8,
			Gen2WorldScript.WAITBUTTON,
			Gen2WorldScript.CLOSETEXT,
			raw.call(0x90),
		],
	})
	_data = GameData.open_directory(Fixture.directory())
	var renderer: Node = await _open_world(NATIVE_SOURCE)
	var box: Gen2TextBox = _world_screen._text_box

	_world_screen._show_script_results(
		_world_screen._world.dispatch_script_events(Vector2i(4, 5))
	)
	box.finish()
	assert_true(box.visible, "the first page is up")
	var occupied: Rect2i = (renderer.get("rects") as Array).back() as Rect2i
	assert_ne(occupied, Rect2i())

	## Every page and button of it, driven the way a press does. The box closes
	## and reopens inside those calls; the renderer must not hear about it.
	var pushed: int = (renderer.get("rects") as Array).size()
	for _press: int in 8:
		if not box.visible:
			break
		box.finish()
		_world_screen._advance_script_input()
	assert_false(box.visible, "the conversation is over")
	assert_eq(
		(renderer.get("rects") as Array).size(), pushed + 1,
		"one publication for the whole conversation, at the end of it"
	)
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


## A mod's visible-encounter provider: the context it is handed, one advance per
## world frame, the entries it answers, and the result of a battle it caused.
const PROVIDER_SOURCE: String = """extends RefCounted

var context: Dictionary = {}
var frames: int = 0
var results: Array = []
var entry: Dictionary = {}

func set_context(value: Dictionary) -> void:
	context = value

func advance_frame() -> void:
	frames += 1

func encounters() -> Array:
	return [] if entry.is_empty() else [entry]

func battle_finished(id, result) -> void:
	results.append([id, result])
"""


## The whole seam in one walk: the provider is contexted from the map's own
## tables, its entry is validated against them, drawn with the SPECIES' colours,
## and met by stepping onto it instead of by a roll.
func test_a_visible_encounter_provider_is_driven_validated_drawn_and_fought() -> void:
	var provider: Object = _script(PROVIDER_SOURCE).new()
	assert_true(
		Gen2ModHost.instance().register_visible_encounters(&"wilds", provider)["ok"]
	)
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	_world_screen.set_process(false)
	## The fixture map is plain land, which is not grass. A cave floor is
	## eligible everywhere, which is the branch that makes the sweep answerable
	## here at all.
	_world_screen._world.current_map.environment = Gen2WorldAPI.ENVIRONMENT_CAVE
	_world_screen._encounters.set_providers([provider])

	var context: Dictionary = provider.get("context")
	assert_eq(context["map"], Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER))
	assert_eq(int(context["generation"]), 1)
	var slots: Array = context["tables"][Gen2WorldEncounter.METHOD_GRASS]["slots"]
	assert_eq(int(slots[0]["species"]), Fixture.TRAINER_SPECIES)
	var cell := Vector2i(7, 7)
	assert_true(
		(context["eligible"][Gen2WorldEncounter.METHOD_GRASS] as PackedVector2Array).has(
			Vector2(cell)
		)
	)

	## `occupied` is who is standing where, and it is deliberately NOT folded
	## into `eligible`: the trainer's cell is in both, because which cells a wild
	## MAY stand on is a cartridge rule and `_validate` drops an entry outside it.
	var trainer: Gen2WorldObject = _world_screen._world.visible_objects()[0]
	assert_true(
		(context["occupied"] as PackedVector2Array).has(Vector2(trainer.cell)),
		"the map's own object holds its cell"
	)
	assert_true(
		(context["eligible"][Gen2WorldEncounter.METHOD_GRASS] as PackedVector2Array).has(
			Vector2(trainer.cell)
		),
		"and eligible still answers the cartridge's own rule for it"
	)
	assert_false(
		(context["occupied"] as PackedVector2Array).has(
			Vector2(_world_screen._world.player_cell)
		),
		"the player is in `player`, not in `occupied`"
	)

	## An object moves without the player moving, so the occupancy is refreshed
	## with the pose rather than only on a map change.
	trainer.cell = Vector2i(6, 3)
	_world_screen._encounters.advance_frame()
	var moved: PackedVector2Array = provider.get("context")["occupied"]
	assert_true(moved.has(Vector2(6, 3)), "the cell it walked onto")
	assert_false(moved.has(Vector2(5, 3)), "and not the one it left")

	## Mid-step it is DRAWN across two cells, and a wild standing in either of
	## them stands inside it, so `step_offset_cells()` puts both in the list.
	trainer.step_direction = Vector2i(1, 0)
	trainer.step_passes_total = 8
	trainer.step_passes_remaining = 4
	_world_screen._encounters.advance_frame()
	var walking: PackedVector2Array = provider.get("context")["occupied"]
	assert_true(walking.has(Vector2(6, 3)), "the cell it is committed to")
	assert_true(walking.has(Vector2(5, 3)), "and the one it is still drawn over")

	## Off the table, so nothing is drawn: the host will not stand a Pokemon the
	## map cannot produce.
	provider.set("entry", {
		"id": &"a", "cell": cell, "species": Fixture.TRAINER_SPECIES, "level": 99, "dvs": 0,
	})
	_world_screen.advance_frames(1)
	assert_eq(_world_screen._encounters.entries().size(), 0, "level off the table")

	## Shiny DVs: `CheckShininess`'s three tens and the attack mask.
	var shiny: int = Gen2Stats.pack_dvs(2, 10, 10, 10)
	provider.set("entry", {
		"id": &"a", "cell": cell, "species": Fixture.TRAINER_SPECIES, "level": 5,
		"dvs": shiny, "facing": Gen2WorldSprite.FACING_UP,
	})
	var stepped: int = int(provider.get("frames"))
	_world_screen.advance_frames(1)
	assert_eq(int(provider.get("frames")), stepped + 1)
	var entries: Array = _world_screen._encounters.entries()
	assert_eq(entries.size(), 1)
	assert_true(bool(entries[0]["shiny"]), "the host answers shininess, not the mod")
	var drawn: Array = _world_screen._actors.sprites()
	assert_eq(drawn.size(), 1)
	assert_eq(drawn[0]["position_cells"], Vector2(cell))
	assert_eq(
		drawn[0]["colors"], _data.palette(Fixture.TRAINER_SPECIES, true),
		"the shiny palette"
	)

	## A step onto an empty cell starts nothing, though the map's own grass rate
	## is 255: while a provider is active the post-step roll is off.
	_world_screen._world.player_cell = Vector2i(6, 7)
	_world_screen._after_player_move({"kind": &"step"})
	assert_null(_world_screen._battle_host, "no roll while a provider is active")

	## Walking onto it starts the battle with those exact DVs.
	_world_screen._world.player_cell = cell
	_world_screen._after_player_move({"kind": &"step"})
	## The adapter's own prepared request, which is the `values` block itself.
	_world_screen.settle_battle_transition()
	var request: Dictionary = _world_screen._battle_host.world_battle_request()
	assert_eq(int(request["dvs"]), shiny)
	assert_eq(int(request["level"]), 5)
	## Which entry it was is the world's own bookkeeping, since that is what gets
	## reported back to the provider when the fight ends.
	assert_eq(_world_screen._battle_encounter_id, &"a")

	_world_screen._on_battle_finished({"outcome": Gen2WorldBattleAdapter.OUTCOME_RAN})
	var reported: Array = provider.get("results")
	assert_eq(reported.size(), 1)
	assert_eq(StringName(reported[0][0]), &"a")
	assert_eq(StringName(reported[0][1]["outcome"]), Gen2WorldBattleAdapter.OUTCOME_RAN)

	## A map change discards the population and every sprite resolved from it
	## before the next map is drawn, and says so with a fresh generation.
	var generation: int = int((provider.get("context") as Dictionary)["generation"])
	_world_screen._world.current_map.number = Fixture.MAP_NUMBER + 1
	_world_screen._encounters.set_world(_world_screen._world)
	assert_eq(_world_screen._encounters.entries().size(), 0)
	assert_eq(
		int((provider.get("context") as Dictionary)["generation"]), generation + 1
	)


## `StartTrainerBattle_Flash` writes `wBGP` and calls `DmgToCgbBGPals` alone,
## so its three passes are a background order: the map, the Poke Ball's own tile
## and the wedges take it, and the sprites standing over them do not. Measured
## on a real Route 30 trainer, where the player's own 74 black, 35 red and 31
## skin pixels are the same on every frame of the flash while the background
## behind them walks the whole list.
func test_the_transition_flash_is_the_background_s_order_and_not_the_sprites() -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	_world_screen.set_process(false)
	var renderer: Gen2WorldRenderer = _world_screen._renderer

	var identity: PackedByteArray = _player_sprite_bytes(renderer)
	var orders: Dictionary = {}
	var floods: Dictionary = {}
	## Every frame of the first flash pass, which is where the whole list is
	## walked; `preview_battle_transition` drives the animation and nothing else.
	for frame: int in range(24, 49):
		_world_screen.preview_battle_transition(frame, true)
		var order: int = _world_screen._battle_transition.palette_order()
		orders[order] = true
		floods[order] = renderer.flood_palette()
		assert_eq(
			_player_sprite_bytes(renderer), identity,
			"the player keeps its own colours through order $%02X" % order
		)
	assert_gt(orders.size(), 4, "the flash walks more than one order")
	var flood: PackedColorArray = floods[Gen2BattleTransition.IDENTITY]
	assert_eq(flood.size(), 4, "`.copypals` fills one palette")
	for order: int in floods:
		if order == Gen2BattleTransition.IDENTITY:
			continue
		assert_ne(
			floods[order], flood,
			"$%02X reorders the background's own four colours" % order
		)


func _player_sprite_bytes(renderer: Gen2WorldRenderer) -> PackedByteArray:
	var texture: Texture2D = renderer._actor_texture(
		_world_screen._world.player_sprite(), _world_screen._world.player_palette(),
		_world_screen._world.player_facing, 0
	)
	return PackedByteArray() if texture == null else texture.get_image().get_data()


## A cell `DoBattleTransition` has written is the background under a sprite
## standing in grass, so the map's own priority tile is not drawn there:
## `.InitSprite`'s OAM_PRIO is a test against whatever the tilemap holds now.
func test_the_grass_over_a_sprite_leaves_the_transition_s_own_cells_to_it() -> void:
	var renderer := Gen2WorldRenderer.new()
	var whole := Rect2(Vector2(64, 68), Vector2(8, 8))
	assert_eq(
		renderer._priority_pieces(whole), [whole] as Array[Rect2],
		"with no transition up the map owns the lot"
	)
	var cells := PackedByteArray()
	cells.resize(Gen2BattleTransition.COLUMNS * Gen2BattleTransition.ROWS)
	## Screen cell (8, 8) alone, which is the left half of a rectangle spanning
	## cells 8 and 9 of row 8.
	cells[8 * Gen2BattleTransition.COLUMNS + 8] = Gen2BattleTransition.CELL_BLACK
	renderer.set_transition(cells, PackedByteArray(), PackedColorArray())
	assert_eq(
		renderer._priority_pieces(Rect2(Vector2(64, 64), Vector2(8, 8))), [] as Array[Rect2],
		"the cell it took is its own"
	)
	assert_eq(
		renderer._priority_pieces(Rect2(Vector2(64, 64), Vector2(16, 8))),
		[Rect2(Vector2(72, 64), Vector2(8, 8))] as Array[Rect2],
		"the cell beside it is still the map's"
	)
	assert_eq(
		renderer._priority_pieces(whole), [Rect2(Vector2(64, 72), Vector2(8, 4))] as Array[Rect2],
		"a rectangle straddling the grid is split on it, not dropped whole"
	)
	renderer.free()


## The optional half of the actor contract, through the production path: the
## press only the actors are offered, the emote a renderer reads off the same
## resolved list, and the cry the host plays because a mod may not.
const PET_ACTOR_SOURCE: String = """extends RefCounted

var world = null
var petted: bool = false
var pressed: Array = []
var cries: Array = []

func set_world(value) -> void:
	world = value

func advance_frame() -> void:
	pass

func sprites() -> Array:
	var entry: Dictionary = {"icon": 1, "position_cells": Vector2(7, 7)}
	if petted:
		entry["emote"] = 4
	return entry_list(entry)

func entry_list(entry: Dictionary) -> Array:
	return [entry]

func interact(cell: Vector2i, facing: int) -> bool:
	pressed.append(cell)
	if cell != Vector2i(7, 7):
		return false
	petted = true
	cries.append({"kind": &"cry", "species": 155})
	return true

func take_requests() -> Array:
	var out: Array = cries
	cries = []
	return out
"""


func test_an_actor_is_offered_the_press_and_the_host_spends_its_cry() -> void:
	var actor: Object = _script(PET_ACTOR_SOURCE).new()
	assert_true(Gen2ModHost.instance().register_world_actor(&"pet", actor)["ok"])
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	_world_screen.set_process(false)
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_DOWN

	assert_true(_world_screen.interact(), "The faced cell is the actor's own.")
	assert_eq(actor.get("pressed"), [Vector2i(7, 7)], "facing_cell(), not the player's")
	assert_eq(
		int(_world_screen._actors.sprites()[0]["emote"]), Gen2WorldActors.EMOTE_HEART,
		"The pose the press changed is drawn on the frame it was pressed."
	)
	## The outbox is drained by the world frame, not by the press.
	assert_eq((actor.get("cries") as Array).size(), 1)
	_world_screen.advance_frames(1)
	assert_eq((actor.get("cries") as Array).size(), 0, "One drain empties it.")


## An actor may never shadow a cartridge interaction: the press reaches it only
## when `Gen2WorldAPI.interact()` answered nothing at all.
func test_an_actor_is_not_offered_a_press_a_cartridge_object_answered() -> void:
	var actor: Object = _script(PET_ACTOR_SOURCE).new()
	assert_true(Gen2ModHost.instance().register_world_actor(&"pet", actor)["ok"])
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	_world_screen.set_process(false)
	var world: Gen2WorldAPI = _world_screen._world
	var object: Gen2WorldObject = world.objects[0]
	object.active = true
	object.cell = Vector2i(7, 7)
	world.player_facing = Gen2WorldSprite.FACING_DOWN

	assert_true(_world_screen.interact())
	assert_eq(actor.get("pressed"), [], "The object answered, so nothing was offered.")


## R27's bargain: the mod names a cell and the HOST runs the map's own script, so
## the bag, the event flag, the text box and the fanfare stay the world's.
func test_a_mods_hidden_item_request_runs_the_maps_own_script_when_the_world_is_idle() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts["48:6300"] = [40, 0, 3, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_data = GameData.open_directory(Fixture.directory())
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	_world_screen.set_data(_data)
	add_child(_world_screen)
	await get_tree().process_frame
	_world_screen.set_process(false)
	var world: Gen2WorldAPI = _world_screen._world
	world.current_map.events["bg_events"] = [
		{"x": 2, "y": 3, "type": Gen2WorldAPI.BGEVENT_ITEM, "script": 0x6300},
	]

	var listed: Array = world.hidden_items()
	assert_eq(listed.size(), 1, JSON.stringify(listed))
	assert_eq(listed[0]["cell"], Vector2i(2, 3))
	assert_false(bool(listed[0]["taken"]))

	## Nowhere near the player and never faced: naming the cell is the whole ask.
	Gen2ModHost.instance().request_hidden_item(Vector2i(2, 3))
	_world_screen.advance_frames(1)
	assert_true(world.script_busy(), "The map's own script is running, in the world's own box.")
	assert_true(_world_screen._text_box.visible)
	assert_true(
		("Found" in _world_screen._text_box.text_lines()[0]),
		"`verbosegiveitem`'s own FOUND text, in the world's own box."
	)
	## What the script does from there is the world's, and is covered where the
	## `hiddenitem` path is owned (`test_world_api.gd`). What is this layer's is
	## that the ask was spent exactly once: the queue is empty, and the following
	## frames do not run it again while its own box is still up.
	assert_eq(Gen2ModHost.instance().take_hidden_item_requests(), [])
	_world_screen.advance_frames(3)
	assert_eq(world.state.items().get(3, 0), 0, "The receipt has not been pressed past.")


## A renderer that counts what it was asked to redraw, which is the only way to
## say WHEN a change reached the picture rather than whether the pose is right.
const COUNTING_SOURCE: String = """extends Node2D

var refreshes: int = 0

func set_world(_world, _animation = null) -> void:
	pass

func set_time_of_day(_time_of_day: int) -> void:
	pass

func refresh() -> void:
	refreshes += 1

func refresh_animation() -> void:
	pass
"""


## A consumed press has to reach the picture ON THE FRAME OF THE PRESS. The actor
## layer re-collects where it consumes one, so nothing after it sees a change to
## redraw for: without this the emote waits for the next unrelated change, which
## for a mon icon is its own two-frame flip nine frames later.
func test_a_consumed_press_redraws_on_the_frame_it_was_pressed() -> void:
	var actor: Object = _script(PET_ACTOR_SOURCE).new()
	assert_true(Gen2ModHost.instance().register_world_actor(&"pet", actor)["ok"])
	var renderer: Node = await _open_world(COUNTING_SOURCE)
	_world_screen.set_process(false)
	_world_screen._world.player_facing = Gen2WorldSprite.FACING_DOWN

	var before: int = int(renderer.get("refreshes"))
	assert_true(_world_screen.interact())
	assert_gt(
		int(renderer.get("refreshes")), before,
		"the press drew nothing on its own frame"
	)
	## And the frames after it do not depend on an unrelated change to catch up:
	## the emote is already on screen, so the icon's flip is all that is left.
	assert_eq(
		int(_world_screen._actors.sprites()[0]["emote"]), Gen2WorldActors.EMOTE_HEART
	)


## SCREEN FILL's letterbox is drawn inside the hardware viewport, and the
## viewport is composited over the native layer, so raising it would crop a view
## that had already filled the whole surface.
func test_the_interface_mask_does_not_reach_the_native_layer() -> void:
	var renderer: Node = await _open_world(NATIVE_SOURCE)
	assert_true(_world_screen._screen.expanded, "the overworld fills the window")
	assert_eq((renderer.get("masks") as Array), [false], "told once, before anything opened")

	_world_screen.preview_battle_transition(0)
	assert_false(
		_world_screen._screen.interface_masked,
		"the screen leaves the layer behind it alone",
	)
	assert_eq(
		(renderer.get("masks") as Array).back(), true,
		"and tells the view to close its own surround",
	)


## A renderer drawing in the hardware buffer is masked by the screen, which is
## what the letterbox describes.
func test_a_hardware_viewport_renderer_keeps_the_screens_own_mask() -> void:
	await _open_world(HARDWARE_SOURCE)
	assert_false(_world_screen._screen.interface_masked)
	_world_screen.preview_battle_transition(0)
	assert_true(_world_screen._screen.interface_masked)


## Zoom counts screen pixels per HARDWARE pixel. A view that declined the
## hardware buffer has none, so the keys are left where its own camera can read
## them rather than spent stepping a buffer nothing draws into.
func test_zoom_is_left_alone_for_a_view_with_no_hardware_pixel() -> void:
	await _open_world(NATIVE_SOURCE)
	var before: int = _world_screen._screen.zoom_step
	assert_false(_world_screen._handle_zoom(_key(KEY_MINUS)))
	assert_eq(_world_screen._screen.zoom_step, before, "and nothing moved")


func test_zoom_steps_the_buffer_a_hardware_renderer_draws_into() -> void:
	await _open_world(HARDWARE_SOURCE)
	var before: int = _world_screen._screen.zoom_step
	assert_true(_world_screen._handle_zoom(_key(KEY_MINUS)))
	assert_eq(_world_screen._screen.zoom_step, before - 1)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


## A fight staged on the map in 3D has as much to fill a window with as the
## overworld it started from; the built-in arena is a 160x144 scene and has not.
func test_a_native_layer_battle_fills_the_window_and_the_built_in_one_does_not() -> void:
	await _open_battle()
	assert_true(_battle_screen._screen.expanded)

	_battle_screen.free()
	_battle_screen = null
	assert_true(Gen2ModHost.instance().select_view(Gen2ModHost.BUILT_IN_RENDERER)["ok"])
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_battle_screen = packed.instantiate() as Gen2BattleScreen
	_battle_screen.set_data(_data)
	add_child(_battle_screen)
	await get_tree().process_frame
	assert_false(_battle_screen._screen.expanded)


## A hardware-pixel number means nothing on the native layer without the
## rectangle the hardware screen occupies there. Framed it was the whole surface,
## and filled it is not, so the screen says where.
func test_the_native_layer_is_told_where_the_hardware_screen_is() -> void:
	var renderer: Node = await _open_world(NATIVE_SOURCE)
	var screen: Gen2Screen = _world_screen._screen
	assert_true(screen.expanded)
	var rect: Rect2i = (renderer.get("screens") as Array).back()
	assert_eq(rect, screen.screen_rect())
	assert_gt(rect.position.x, 0, "centred in a surface wider than the hardware's")
	assert_eq(
		float(rect.size.x) / float(rect.size.y),
		float(Gen2Screen.WIDTH) / float(Gen2Screen.HEIGHT),
		"and still ten by nine",
	)
	assert_lt(rect.size.x, screen.native_size().x, "with the view around it")


## Framed, the rectangle is the whole surface, which is the mapping every
## renderer written before this assumed.
func test_a_framed_screen_hands_back_its_whole_surface() -> void:
	Gen2OptionsStore.current().screen_fill = false
	var renderer: Node = await _open_world(NATIVE_SOURCE)
	var screen: Gen2Screen = _world_screen._screen
	assert_false(screen.expanded)
	assert_eq(
		(renderer.get("screens") as Array).back(),
		Rect2i(Vector2i.ZERO, screen.native_size()),
	)
