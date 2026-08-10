extends GutTest

## Scene integration for battle presentation through Gen2ModHost. The cache is
## synthetic, but the battle screen, the mod host and the built-in renderer are
## the production paths.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _battle_screen: Gen2BattleScreen = null


func before_each() -> void:
	Gen2ModHost.reset()
	_data = Fixture.build()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	if is_instance_valid(_battle_screen):
		_battle_screen.free()
		_battle_screen = null
	RomCache.clear(Fixture.directory())
	Gen2ModHost.reset()


func _open_battle() -> void:
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_battle_screen = packed.instantiate() as Gen2BattleScreen
	_battle_screen.set_data(_data)
	add_child(_battle_screen)
	await get_tree().process_frame


## `BattleIntroSlidingPics` runs before `BattleStartMessage`, so a battle says
## and does nothing until the pics are in place. In play the screen's own frames
## spend that; a test driving events without it would drive them into the slide.
func _settle_intro() -> void:
	var guard: int = 4000
	while _battle_screen.intro_running() and guard > 0:
		_battle_screen.advance_frame()
		guard -= 1


func _stub_script(body: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = body
	script.reload()
	return script


func test_the_built_in_renderer_draws_the_matchup_and_reports_ready() -> void:
	await _open_battle()
	assert_true(_battle_screen.is_ready())
	assert_true(_battle_screen._renderer is Gen2BattleRenderer)
	_battle_screen.show_matchup(16, 155, 5, 5)
	assert_true(_battle_screen.battle_snapshot()["ready"])


func test_a_registered_stub_renderer_receives_battle_data_and_a_matching_view() -> void:
	var script: GDScript = _stub_script("""extends Control

var received_data: bool = false
var last_view: Dictionary = {}

func set_battle_data(_data) -> bool:
	received_data = true
	return true

func set_view(view: Dictionary) -> void:
	last_view = view

func refresh() -> void:
	pass
""")
	assert_true(Gen2ModHost.instance().register_battle_renderer(&"stub", script)["ok"])
	assert_true(Gen2ModHost.instance().select_battle_renderer(&"stub")["ok"])

	await _open_battle()
	assert_true(_battle_screen.is_ready())
	var renderer: Node = _battle_screen._renderer
	assert_true(bool(renderer.get("received_data")))

	_battle_screen.show_matchup(16, 155, 7, 9)
	_battle_screen.set_hp(10, 20, 3, 4)
	var view: Dictionary = renderer.get("last_view")
	assert_eq(int(view.get("enemy_level", -1)), 7)
	assert_eq(int(view.get("player_level", -1)), 9)
	assert_eq(int(view.get("enemy_hp", -1)), 10)
	assert_eq(int(view.get("enemy_max_hp", -1)), 20)
	assert_eq(int(view.get("player_hp", -1)), 3)
	assert_eq(int(view.get("player_max_hp", -1)), 4)


## Where the fight is happening, for a renderer that stages it on the map. It is
## optional on both sides: the screen only calls a renderer that defines it, and
## a battle started outside the world supplies none.
func test_a_registered_renderer_is_handed_the_world_the_battle_was_entered_from() -> void:
	var script: GDScript = _stub_script("""extends Control

var context = null

func set_battle_data(_data) -> bool:
	return true

func set_world_context(value) -> void:
	context = value

func set_view(_view: Dictionary) -> void:
	pass

func refresh() -> void:
	pass
""")
	assert_true(Gen2ModHost.instance().register_battle_renderer(&"staged", script)["ok"])
	assert_true(Gen2ModHost.instance().select_battle_renderer(&"staged")["ok"])

	var world: Gen2WorldAPI = Gen2WorldAPI.open(_data, 1, 1, Vector2i(4, 4))
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_battle_screen = packed.instantiate() as Gen2BattleScreen
	_battle_screen.set_data(_data)
	_battle_screen.set_world_context(
		Gen2BattleWorldContext.capture(world, Gen2WorldPalette.TIME_NIGHT)
	)
	add_child(_battle_screen)
	await get_tree().process_frame

	assert_true(_battle_screen.is_ready())
	var context: Gen2BattleWorldContext = _battle_screen._renderer.get("context")
	assert_not_null(context, "the renderer defines the method, so it is called")
	assert_eq(context.map_id, Vector2i(1, 1))
	assert_eq(context.player_cell, Vector2i(4, 4))
	assert_eq(context.player_facing, Gen2WorldSprite.FACING_LEFT)
	assert_eq(context.time_of_day, Gen2WorldPalette.TIME_NIGHT)


## The built-in renderer defines no such method and must still come up: the
## cartridge's battle is a white field and has no place in it.
func test_the_built_in_renderer_ignores_a_world_context() -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(_data, 1, 1, Vector2i(4, 4))
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_battle_screen = packed.instantiate() as Gen2BattleScreen
	_battle_screen.set_data(_data)
	_battle_screen.set_world_context(Gen2BattleWorldContext.capture(world, 0))
	add_child(_battle_screen)
	await get_tree().process_frame

	assert_true(_battle_screen.is_ready())
	assert_false(_battle_screen._renderer.has_method("set_world_context"))
	assert_not_null(_battle_screen.world_context())


## The battle side of Gen2WorldScreen's own renderer-input seam. A Gen2Button is
## claimed by the screen before this and never arrives, so what a renderer is
## offered is the motion the screen has no opinion about.
func test_a_battle_renderer_is_offered_the_input_the_screen_did_not_claim() -> void:
	var script: GDScript = _stub_script("""extends Control

var seen: Array = []
var consume: bool = true

func set_battle_data(_data) -> bool:
	return true

func set_view(_view: Dictionary) -> void:
	pass

func refresh() -> void:
	pass

func handle_battle_input(event) -> bool:
	seen.append(event)
	return consume
""")
	assert_true(Gen2ModHost.instance().register_battle_renderer(&"steered", script)["ok"])
	assert_true(Gen2ModHost.instance().select_battle_renderer(&"steered")["ok"])
	await _open_battle()
	assert_true(_battle_screen.is_ready())
	var renderer: Node = _battle_screen._renderer

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(4.0, 0.0)
	_battle_screen._unhandled_input(motion)
	assert_eq((renderer.get("seen") as Array).size(), 1, "the renderer was not offered it")

	# A button belongs to whatever owns the screen, so it never reaches here.
	var press := InputEventAction.new()
	press.action = Gen2Button.ACTIONS[Gen2Button.A]
	press.pressed = true
	_battle_screen._unhandled_input(press)
	assert_eq((renderer.get("seen") as Array).size(), 1, "a button reached the renderer")

	# Ball selection is a modal state: it means something by itself, so the
	# renderer is not offered anything while it is up. Set directly rather than
	# through begin_capture(), which needs a whole hosted wild battle behind it
	# and would test that instead of this.
	_battle_screen._capture_selecting = true
	_battle_screen._unhandled_input(motion)
	assert_eq((renderer.get("seen") as Array).size(), 1, "a modal state let it through")
	_battle_screen._capture_selecting = false
	_battle_screen._unhandled_input(motion)
	assert_eq((renderer.get("seen") as Array).size(), 2, "and it stayed shut afterwards")


## A renderer that defines nothing keeps working, and one that answers false
## leaves the event where it was.
func test_a_battle_renderer_without_the_method_changes_nothing() -> void:
	await _open_battle()
	assert_false(_battle_screen._renderer.has_method("handle_battle_input"))
	var motion := InputEventMouseMotion.new()
	_battle_screen._unhandled_input(motion)
	assert_false(motion.is_echo(), "the built-in renderer must not crash on one")


## `view` says what is on the field; this says who it is against, which a
## renderer standing the opponent behind their Pokemon needs. A wild battle
## carries class 0, the way `wOtherTrainerClass` is zero there.
func test_the_view_names_the_trainer_the_battle_is_against() -> void:
	var script: GDScript = _stub_script("""extends Control

var last_view: Dictionary = {}

func set_battle_data(_data) -> bool:
	return true

func set_view(view: Dictionary) -> void:
	last_view = view

func refresh() -> void:
	pass
""")
	assert_true(Gen2ModHost.instance().register_battle_renderer(&"named", script)["ok"])
	assert_true(Gen2ModHost.instance().select_battle_renderer(&"named")["ok"])
	await _open_battle()
	var renderer: Node = _battle_screen._renderer

	_battle_screen.show_matchup(16, 155, 5, 5)
	var wild: Dictionary = renderer.get("last_view")
	assert_eq(StringName(wild.get("battle_kind", &"")), &"wild")
	assert_eq(int(wild.get("trainer_class", -1)), 0)
	assert_eq(String(wild.get("trainer_name", "x")), "")

	_battle_screen.show_trainer(Fixture.TRAINER_CLASS, 0)
	var trainer: Dictionary = renderer.get("last_view")
	assert_eq(StringName(trainer.get("battle_kind", &"")), &"trainer")
	assert_eq(int(trainer.get("trainer_class", -1)), Fixture.TRAINER_CLASS)
	assert_eq(int(trainer.get("trainer_index", -1)), 0)
	assert_eq(
		String(trainer.get("trainer_name", "")),
		String(_data.trainer_party(Fixture.TRAINER_CLASS, 0).get("name", "")),
	)


func test_a_renderer_reporting_missing_data_leaves_the_screen_not_ready() -> void:
	var script: GDScript = _stub_script("""extends Control

func set_battle_data(_data) -> bool:
	return false

func set_view(_view: Dictionary) -> void:
	pass

func refresh() -> void:
	pass
""")
	assert_true(Gen2ModHost.instance().register_battle_renderer(&"broken_data", script)["ok"])
	assert_true(Gen2ModHost.instance().select_battle_renderer(&"broken_data")["ok"])

	await _open_battle()
	assert_false(_battle_screen.is_ready())
	# Input must stay inert rather than crash on a renderer that never armed.
	_battle_screen._unhandled_input(InputEventKey.new())


func test_a_renderer_choosing_the_native_layer_lands_on_the_screens_native_layer() -> void:
	var script: GDScript = _stub_script("""extends Control

func set_battle_data(_data) -> bool:
	return true

func set_view(_view: Dictionary) -> void:
	pass

func refresh() -> void:
	pass

func uses_hardware_viewport() -> bool:
	return false
""")
	assert_true(Gen2ModHost.instance().register_battle_renderer(&"native", script)["ok"])
	assert_true(Gen2ModHost.instance().select_battle_renderer(&"native")["ok"])

	await _open_battle()
	assert_true(_battle_screen.is_ready())
	# Hardware pixels live inside the SubViewport; a renderer that opted out of
	# that must not end up there.
	assert_false(_battle_screen._renderer.get_parent() is SubViewport)


## `NormalHit` runs `applydamage` before `criticaltext` and `supereffectivetext`,
## and `DoEnemyDamage` ends with `predef AnimateHPBar`, so the bar drains first
## and the line describing the hit waits for it.
func test_a_hit_drains_the_bar_before_it_says_what_the_hit_was() -> void:
	await _open_battle()
	_battle_screen.show_matchup(16, 155, 7, 9)
	_settle_intro()
	_battle_screen.set_hp(48, 48, 40, 40)

	_battle_screen._pending = [{
		"type": Gen2Battle.HIT, "side": Gen2Battle.PLAYER, "target": Gen2Battle.ENEMY,
		"hp": 24, "max_hp": 48, "critical": false,
		"effectiveness": RomLayout.MATCHUP_SUPER_EFFECTIVE,
	}]
	_battle_screen._show_next_event()

	assert_true(_battle_screen.bars_animating(), "the bar is still on its way down")
	assert_ne(
		_battle_screen.battle_snapshot()["message"], "It's super effective!",
		"and the line has not been printed yet"
	)
	assert_eq(int(_battle_screen.get("_enemy_hp")), 24, "the committed HP is already there")

	## A press during the animation is swallowed, the way AnimateHPBar's own
	## blocking loop swallows one.
	_battle_screen.advance()
	assert_true(_battle_screen.bars_animating())

	var guard: int = 4000
	while _battle_screen.bars_animating() and guard > 0:
		_battle_screen.advance_bars()
		guard -= 1
	assert_eq(_battle_screen.battle_snapshot()["message"], "It's super effective!")


## A Pokemon coming out gets its bar drawn rather than drained: the maximum
## moved under it, so it is not the same bar.
func test_a_new_pokemon_does_not_animate_its_bar_up() -> void:
	await _open_battle()
	_battle_screen.show_matchup(16, 155, 7, 9)
	_battle_screen.set_hp(10, 48, 40, 40)
	_battle_screen._apply_event({
		"type": Gen2Battle.SENT_OUT, "side": Gen2Battle.ENEMY,
		"species": 155, "level": 7, "hp": 30, "max_hp": 30,
	})
	assert_false(_battle_screen.bars_animating())


## `Text_MonGainedExpPoint` is printed before `call AnimateExpBar`, so the EXP.
## Points line leads its bar; `BattleText_StringBuffer1GrewToLevel` is printed
## inside `.LoopLevels` once that level's segment has reached the end of the bar,
## so the level line waits for it.
func test_experience_says_its_line_first_and_the_level_line_after_the_bar() -> void:
	await _open_battle()
	_battle_screen.show_matchup(16, 155, 7, 9)
	_settle_intro()

	var mon: Gen2BattleMon = _battle_screen._battle.player
	var rate: int = mon.growth_rate()
	var index: int = _battle_screen._battle.party(Gen2Battle.PLAYER).active
	mon.exp = Gen2Experience.total_exp_at(rate, mon.level)
	_battle_screen._refresh_exp_bar()
	assert_eq(int(_battle_screen.get("_exp")), 0, "the bar starts at the level's own threshold")

	# What `_give_experience_to` does to the Pokemon before it describes it: an
	# award that carries it over the next level.
	var award: int = Gen2Experience.total_exp_at(rate, mon.level + 1) - mon.exp + 4
	var grown: int = mon.level + 1
	mon.gain_exp(award)
	mon.level_up()

	_battle_screen._pending = [
		{
			"type": Gen2Battle.EXP_GAINED, "side": Gen2Battle.PLAYER, "index": index,
			"species": mon.species, "amount": award, "exp": mon.exp, "exp_share": false,
		},
		{
			"type": Gen2Battle.GREW_LEVEL, "side": Gen2Battle.PLAYER, "index": index,
			"species": mon.species, "old_level": grown - 1, "new_level": grown,
			"old_stats": {}, "new_stats": {},
		},
	]

	_battle_screen._show_next_event()
	assert_true(_battle_screen.bars_animating(), "the bar is filling")
	assert_string_contains(
		String(_battle_screen.battle_snapshot()["message"]), "EXP. Points",
		"and its own line is already on screen"
	)

	# A press during the fill is swallowed, the way AnimateExpBar's own blocking
	# loop swallows one.
	_battle_screen.advance()
	assert_true(_battle_screen.bars_animating())

	# The first segment ends at the end of the bar, where the level line is
	# printed and the walk stops for the button that dismisses it.
	var guard: int = 4000
	while not _battle_screen._exp_bar.paused() and guard > 0:
		_battle_screen.advance_bars()
		guard -= 1
	assert_gt(guard, 0, "the bar reached the end of the level")
	assert_eq(
		_battle_screen._exp_bar.pixels(), Gen2ExpBarAnimation.LENGTH_PX,
		"and it is sitting there full"
	)
	assert_string_contains(
		String(_battle_screen.battle_snapshot()["message"]), "grew to level",
		"the level line waited for the bar to reach the end"
	)

	_battle_screen._box.advance()
	_battle_screen.advance()
	assert_false(_battle_screen._exp_bar.paused(), "the press let the next fill start")

	guard = 4000
	while _battle_screen.bars_animating() and guard > 0:
		_battle_screen.advance_bars()
		guard -= 1
	assert_gt(guard, 0, "the walk ended")
	assert_eq(
		int(_battle_screen.get("_exp")),
		Gen2ExpBarAnimation.pixels_for(rate, mon.level, mon.exp),
		"and the committed count caught up when it did"
	)


## `AnimateExpBar` returns before it touches the bar when the gainer is not the
## Pokemon on the field, which is every Exp. Share holder on the bench.
func test_a_benched_gainer_animates_no_bar() -> void:
	await _open_battle()
	_battle_screen.show_matchup(16, 155, 7, 9)
	var mon: Gen2BattleMon = _battle_screen._battle.player
	var benched: int = _battle_screen._battle.party(Gen2Battle.PLAYER).active + 1

	_battle_screen._apply_event({
		"type": Gen2Battle.EXP_GAINED, "side": Gen2Battle.PLAYER, "index": benched,
		"species": mon.species, "amount": 40, "exp": mon.exp, "exp_share": true,
	})
	assert_false(_battle_screen.bars_animating())


## `InitBattleDisplay` runs `BattleIntroSlidingPics` and only then does
## `BattleStartMessage` say anything, so a battle opens on an empty box with the
## background sliding, and the player's back pic is not on the map at all until
## `PlaceGraphic` puts it there after the slide.
func test_a_battle_opens_on_the_slide_and_says_nothing_until_it_is_done() -> void:
	await _open_battle()
	_battle_screen.show_matchup(16, 155, 7, 9)
	_battle_screen.show_message("Wild PIDGEY appeared!")

	assert_true(_battle_screen.intro_running())
	assert_eq(String(_battle_screen.battle_snapshot()["message"]), "", "the box is empty")

	var view: Dictionary = _battle_screen._renderer._view
	assert_false(bool(view["player_pic_visible"]), "the back pic is not placed yet")
	var offsets: PackedInt32Array = PackedInt32Array(view["raster_scx"])
	assert_eq(offsets.size(), Gen2Screen.HEIGHT)
	assert_ne(offsets[0], 0, "and the background is somewhere else entirely")

	# The slide is a run of unconditional `DelayFrame`s with nothing reading a
	# button, so a press does nothing at all.
	_battle_screen.advance()
	assert_true(_battle_screen.intro_running())

	_settle_intro()
	assert_eq(
		String(_battle_screen.battle_snapshot()["message"]), "Wild PIDGEY appeared!",
		"the start message waited for the slide"
	)
	var settled: Dictionary = _battle_screen._renderer._view
	assert_true(bool(settled["player_pic_visible"]))
	assert_true(PackedInt32Array(settled["raster_scx"]).is_empty(), "and nothing is scrolled")


## The text box is drawn into the background plane like everything else, so
## Gold and Silver's lead frame, which puts the whole screen at the starting
## offset, takes the box with it.
func test_the_text_box_is_scrolled_with_the_rest_of_the_background() -> void:
	await _open_battle()
	_battle_screen.show_matchup(16, 155, 7, 9)

	var box: Gen2TextBox = _battle_screen._box
	assert_eq(box.raster_scx.size(), box.rows * Gen2Font.TILE)
	var offsets: PackedInt32Array = PackedInt32Array(
		_battle_screen._renderer._view["raster_scx"]
	)
	var top: int = Gen2TextBox.STANDARD_TOP * Gen2Font.TILE
	assert_eq(box.raster_scx[0], offsets[top], "the box takes its own rows of the scroll")

	_settle_intro()
	assert_true(box.raster_scx.is_empty())
