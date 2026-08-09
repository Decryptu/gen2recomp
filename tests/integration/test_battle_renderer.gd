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
