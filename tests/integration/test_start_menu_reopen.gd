extends GutTest

## `StartMenu`'s `.MenuReturns`: every handler that returns 0 lands on `.Reopen`,
## which draws the menu again rather than closing it. Pokedex, Pokemon, Pokegear
## and the trainer card all do; a field move chosen in the party menu reaches
## `.quit`'s `ExitAllMenus` instead.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _screen: Gen2WorldScreen = null


func before_each() -> void:
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = Fixture.MAP_GROUP
	_screen.map_number = Fixture.MAP_NUMBER
	_screen.start_cell = Vector2i(7, 6)
	var world := Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6)
	)
	var save := Gen2SaveStore.create_development_save(_data, 0)
	save.world = world.snapshot()
	_screen.set_data(_data)
	_screen.set_save(save)
	add_child(_screen)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
		_screen = null
	RomCache.clear(Fixture.directory())


## Opens the start menu and picks [param kind], which is what
## `action_chosen` carries when the cursor is on that row.
func _choose(kind: StringName) -> void:
	_screen._open_start_menu()
	assert_not_null(_screen._start_menu_host, "the start menu opened")
	_screen._on_start_menu_action(kind)


func test_the_trainer_card_returns_to_the_menu() -> void:
	_choose(Gen2WorldStartMenu.ITEM_PLAYER)
	assert_null(_screen._start_menu_host, "the menu closed behind the card")
	assert_not_null(_screen._trainer_card_host)
	_screen._on_trainer_card_closed()
	assert_not_null(_screen._start_menu_host, ".Reopen drew it again")


func test_the_party_returns_to_the_menu() -> void:
	_choose(Gen2WorldStartMenu.ITEM_POKEMON)
	assert_null(_screen._start_menu_host)
	_screen._on_party_closed({})
	assert_not_null(_screen._start_menu_host)


func test_the_pokegear_returns_to_the_menu() -> void:
	_choose(Gen2WorldStartMenu.ITEM_POKEGEAR)
	assert_null(_screen._start_menu_host)
	_screen._on_service_completed([])
	assert_not_null(_screen._start_menu_host)


## A Pokegear reached by a script or by the debug key was never in the start
## menu, so closing it goes back to the world.
func test_a_pokegear_opened_on_its_own_does_not_open_the_menu() -> void:
	_screen._open_pokegear()
	_screen._on_service_completed([])
	assert_null(_screen._start_menu_host)


## `PokemonActionSubmenu`'s `.quit` reaches `ExitAllMenus`, so a field move
## leaves the overworld with no menu behind it.
func test_a_field_move_leaves_every_menu() -> void:
	_choose(Gen2WorldStartMenu.ITEM_POKEMON)
	_screen._on_party_action({"kind": &"field_move", "move": Gen2WorldFieldMove.MOVE_CUT})
	assert_null(_screen._start_menu_host)


## The cursor is `wBattleMenuCursorPosition`, which `.Reopen` reads back rather
## than resetting.
func test_the_reopened_menu_keeps_the_cursor() -> void:
	_screen._open_start_menu()
	var menu: Gen2WorldStartMenu = _screen._start_menu_host.get("_menu")
	menu.move(1)
	var moved: int = menu.cursor
	assert_gt(moved, 0, "the cursor moved off the first row")
	_screen._on_start_menu_action(Gen2WorldStartMenu.ITEM_PLAYER)
	_screen._on_trainer_card_closed()
	var reopened: Gen2WorldStartMenu = _screen._start_menu_host.get("_menu")
	assert_eq(reopened.cursor, moved)
