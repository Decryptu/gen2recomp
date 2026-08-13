extends GutTest

## Gen2WorldApricorn is SelectApricornForKurt's own state machine
## (engine/events/kurt.asm) and Gen2WorldQuantityPrompt is
## BuySellToss_InterpretJoypad's dial (engine/items/buy_sell_toss.asm). Both are
## scene-free, so every case here presses buttons and reads the model.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const RED: int = 0x55
const BLU: int = 0x59
const YLW: int = 0x5C
const GRN: int = 0x5D
const WHT: int = 0x61
const BLK: int = 0x63
const PNK: int = 0x65
const ALL_SEVEN: Array[int] = [RED, BLU, YLW, GRN, WHT, BLK, PNK]

var _data: GameData = null


func before_each() -> void:
	_data = Fixture.build()


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _state(items: Dictionary) -> Gen2WorldState:
	return Gen2WorldState.new({}, {}, items)


func _all_seven(quantity: int = 5) -> Gen2WorldState:
	var items: Dictionary = {}
	for item: int in ALL_SEVEN:
		items[item] = quantity
	return _state(items)


func test_the_bag_list_keeps_apricorn_balls_order_and_drops_what_is_not_held() -> void:
	var selection: Array = Gen2WorldApricorn.find_in_bag(
		_data, _state({PNK: 2, RED: 1, 7: 9, YLW: 4})
	)
	assert_eq(selection.size(), 3)
	assert_eq(selection[0]["item"], RED)
	assert_eq(selection[1]["item"], YLW)
	assert_eq(selection[2]["item"], PNK)
	assert_eq(selection[1]["quantity"], 4)
	## The second ApricornBalls column, which KurtsHouse.asm hands back a day on.
	assert_eq(selection[0]["ball"], 0x9F)
	assert_eq(selection[2]["ball"], 0xA6)


func test_the_quantity_of_an_apricorn_clamps_at_the_source_ceiling() -> void:
	var state: Gen2WorldState = _state({RED: 99, BLU: 40})
	assert_eq(Gen2WorldApricorn.quantity_of(state, RED), 99)
	assert_eq(Gen2WorldApricorn.quantity_of(state, BLU), 40)
	assert_eq(Gen2WorldApricorn.quantity_of(state, YLW), 0)


func test_an_empty_bag_finishes_the_selection_on_the_source_refusal() -> void:
	var selection: Gen2WorldApricorn = Gen2WorldApricorn.open(_data, _state({7: 4}))
	assert_true(selection.is_done())
	assert_eq(selection.result(), {"item": 0, "quantity": 0})


func test_a_short_list_shows_the_cancel_row_and_a_full_one_scrolls_to_it() -> void:
	var two: Gen2WorldApricorn = Gen2WorldApricorn.open(_data, _state({RED: 1, BLU: 1}))
	assert_eq(two.rows(), 3)
	two.press(Gen2Button.DOWN)
	two.press(Gen2Button.DOWN)
	assert_eq(two.cursor_y, 3)
	assert_eq(two.scroll, 0)
	assert_true(two.selected_entry().is_empty())

	var seven: Gen2WorldApricorn = Gen2WorldApricorn.open(_data, _all_seven())
	assert_eq(seven.rows(), Gen2WorldApricorn.MENU_HEIGHT)
	for press: int in 7:
		seven.press(Gen2Button.DOWN)
	assert_eq(seven.cursor_y, 4)
	assert_eq(seven.scroll, 4)
	assert_eq(seven.selected_index(), 7)
	assert_true(seven.selected_entry().is_empty())
	## `.d_down` stops once the window has reached the sentinel.
	seven.press(Gen2Button.DOWN)
	assert_eq(seven.scroll, 4)


func test_the_cursor_walks_the_window_before_the_list_scrolls() -> void:
	var selection: Gen2WorldApricorn = Gen2WorldApricorn.open(_data, _all_seven())
	selection.press(Gen2Button.DOWN)
	assert_eq(selection.scroll, 0)
	assert_eq(selection.selected_entry()["item"], BLU)
	selection.press(Gen2Button.UP)
	assert_eq(selection.cursor_y, 1)
	## Up at the top edge with nothing scrolled away does nothing at all.
	selection.press(Gen2Button.UP)
	assert_eq(selection.cursor_y, 1)
	assert_eq(selection.scroll, 0)


func test_choosing_an_apricorn_opens_the_quantity_box_on_one() -> void:
	var selection: Gen2WorldApricorn = Gen2WorldApricorn.open(_data, _state({GRN: 6}))
	selection.press(Gen2Button.A)
	assert_eq(selection.phase, Gen2WorldApricorn.SELECT_QUANTITY)
	assert_eq(selection.prompt.value, 1)
	assert_eq(selection.prompt.maximum, 6)
	selection.press(Gen2Button.A)
	assert_true(selection.is_done())
	assert_eq(selection.result(), {"item": GRN, "quantity": 1})


func test_backing_out_of_the_quantity_box_returns_to_the_same_row() -> void:
	var selection: Gen2WorldApricorn = Gen2WorldApricorn.open(_data, _all_seven())
	for press: int in 5:
		selection.press(Gen2Button.DOWN)
	var row: int = selection.cursor_y
	var scrolled: int = selection.scroll
	var chosen: int = int(selection.selected_entry()["item"])
	selection.press(Gen2Button.A)
	assert_eq(selection.phase, Gen2WorldApricorn.SELECT_QUANTITY)
	selection.press(Gen2Button.B)
	assert_eq(selection.phase, Gen2WorldApricorn.SELECT_APRICORN)
	assert_eq(selection.cursor_y, row)
	assert_eq(selection.scroll, scrolled)
	assert_eq(int(selection.selected_entry()["item"]), chosen)
	## wScriptVar is only what the last pass through the loop wrote.
	selection.press(Gen2Button.B)
	assert_true(selection.is_done())
	assert_eq(selection.result(), {"item": 0, "quantity": 0})


func test_the_cancel_row_answers_with_the_same_zero_a_b_press_does() -> void:
	var selection: Gen2WorldApricorn = Gen2WorldApricorn.open(_data, _state({WHT: 3}))
	selection.press(Gen2Button.DOWN)
	assert_true(selection.selected_entry().is_empty())
	selection.press(Gen2Button.A)
	assert_true(selection.is_done())
	assert_eq(selection.result(), {"item": 0, "quantity": 0})


func test_the_quantity_dial_wraps_at_both_ends() -> void:
	var prompt: Gen2WorldQuantityPrompt = Gen2WorldQuantityPrompt.open(4)
	assert_eq(prompt.value, 1)
	prompt.press(Gen2Button.DOWN)
	assert_eq(prompt.value, 4)
	prompt.press(Gen2Button.UP)
	assert_eq(prompt.value, 1)
	prompt.press(Gen2Button.UP)
	assert_eq(prompt.value, 2)


func test_the_quantity_dial_pages_by_ten_and_stops_at_the_ceiling() -> void:
	var prompt: Gen2WorldQuantityPrompt = Gen2WorldQuantityPrompt.open(25)
	prompt.press(Gen2Button.RIGHT)
	assert_eq(prompt.value, 11)
	prompt.press(Gen2Button.RIGHT)
	assert_eq(prompt.value, 21)
	prompt.press(Gen2Button.RIGHT)
	assert_eq(prompt.value, 25)
	prompt.press(Gen2Button.LEFT)
	assert_eq(prompt.value, 15)
	prompt.press(Gen2Button.LEFT)
	assert_eq(prompt.value, 5)
	## `.left` lands on one rather than wrapping, borrow or zero alike.
	prompt.press(Gen2Button.LEFT)
	assert_eq(prompt.value, 1)


func test_the_quantity_dial_reports_its_two_terminals() -> void:
	var prompt: Gen2WorldQuantityPrompt = Gen2WorldQuantityPrompt.open(9)
	assert_eq(prompt.press(Gen2Button.UP), Gen2WorldQuantityPrompt.PENDING)
	assert_eq(prompt.press(Gen2Button.A), Gen2WorldQuantityPrompt.CONFIRMED)
	assert_eq(prompt.press(Gen2Button.B), Gen2WorldQuantityPrompt.CANCELLED)
