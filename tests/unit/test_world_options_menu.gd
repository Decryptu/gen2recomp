extends GutTest

## The in-game OPTION menu model (engine/menus/options_menu.asm).

var _options: Gen2Options = null
var _menu: Gen2WorldOptionsMenu = null


func before_each() -> void:
	_options = Gen2Options.new()
	_menu = Gen2WorldOptionsMenu.build(_options)


func _select(index: int) -> void:
	_menu.cursor = index


func _value_at(index: int) -> String:
	return String(_menu.rows()[index].get("value", ""))


func test_the_rows_are_the_source_order_and_labels() -> void:
	var labels: Array = []
	for row: Dictionary in _menu.rows():
		labels.append(String(row.get("label", "")))
	assert_eq(labels, [
		"TEXT SPEED", "BATTLE SCENE", "BATTLE STYLE", "SOUND",
		"PRINT", "MENU ACCOUNT", "FRAME", "CANCEL",
	])
	assert_eq(_menu.size(), Gen2WorldOptionsMenu.NUM_OPTIONS)


func test_cancel_carries_no_value_and_is_the_only_row_a_answers() -> void:
	_select(Gen2WorldOptionsMenu.OPT_CANCEL)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_CANCEL), "")
	assert_true(_menu.is_cancel())
	_select(Gen2WorldOptionsMenu.OPT_FRAME)
	assert_false(_menu.is_cancel())


## OptionsControl wraps at both ends; its two odd branches land on the same
## value the plain step does.
func test_the_cursor_wraps_at_both_ends() -> void:
	_select(Gen2WorldOptionsMenu.OPT_CANCEL)
	_menu.move(1)
	assert_eq(_menu.cursor, Gen2WorldOptionsMenu.OPT_TEXT_SPEED)
	_menu.move(-1)
	assert_eq(_menu.cursor, Gen2WorldOptionsMenu.OPT_CANCEL)


func test_menu_account_and_frame_step_normally_despite_the_source_oddities() -> void:
	_select(Gen2WorldOptionsMenu.OPT_MENU_ACCOUNT)
	_menu.move(1)
	assert_eq(_menu.cursor, Gen2WorldOptionsMenu.OPT_FRAME)
	_menu.move(-1)
	assert_eq(_menu.cursor, Gen2WorldOptionsMenu.OPT_MENU_ACCOUNT)


func test_move_by_zero_changes_nothing() -> void:
	_select(Gen2WorldOptionsMenu.OPT_SOUND)
	assert_false(_menu.move(0))
	assert_eq(_menu.cursor, Gen2WorldOptionsMenu.OPT_SOUND)


func test_text_speed_cycles_and_wraps_both_ways() -> void:
	_select(Gen2WorldOptionsMenu.OPT_TEXT_SPEED)
	_options.text_speed = 0
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_TEXT_SPEED), "FAST")
	_menu.adjust(1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_TEXT_SPEED), "MID")
	_menu.adjust(1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_TEXT_SPEED), "SLOW")
	_menu.adjust(1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_TEXT_SPEED), "FAST")
	_menu.adjust(-1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_TEXT_SPEED), "SLOW")


func test_print_cycles_five_values_and_wraps_both_ways() -> void:
	_select(Gen2WorldOptionsMenu.OPT_PRINT)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_PRINT), "NORMAL")
	_menu.adjust(-1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_PRINT), "LIGHTER")
	_menu.adjust(-1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_PRINT), "LIGHTEST")
	_menu.adjust(-1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_PRINT), "DARKEST")
	_menu.adjust(1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_PRINT), "LIGHTEST")


## Each bit row's .LeftPressed jumps to the opposite branch from .NonePressed,
## so left and right both toggle rather than stepping opposite ways.
func test_the_four_bit_rows_toggle_on_either_direction() -> void:
	for index: int in [
		Gen2WorldOptionsMenu.OPT_BATTLE_SCENE,
		Gen2WorldOptionsMenu.OPT_BATTLE_STYLE,
		Gen2WorldOptionsMenu.OPT_SOUND,
		Gen2WorldOptionsMenu.OPT_MENU_ACCOUNT,
	]:
		_select(index)
		var start: String = _value_at(index)
		_menu.adjust(1)
		var toggled: String = _value_at(index)
		assert_ne(toggled, start)
		_menu.adjust(-1)
		assert_eq(_value_at(index), start)
		_menu.adjust(-1)
		assert_eq(_value_at(index), toggled)


func test_the_bit_rows_read_the_source_polarity() -> void:
	_options.battle_scene = true
	_options.battle_style_set = false
	_options.stereo = false
	_options.menu_account = true
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_BATTLE_SCENE), "ON")
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_BATTLE_STYLE), "SHIFT")
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_SOUND), "MONO")
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_MENU_ACCOUNT), "ON")
	_options.battle_style_set = true
	_options.stereo = true
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_BATTLE_STYLE), "SET")
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_SOUND), "STEREO")


## `maskbits NUM_FRAMES` over eight frames, drawn one-based by `add '1'`.
func test_frame_wraps_over_eight_types_and_is_drawn_one_based() -> void:
	_select(Gen2WorldOptionsMenu.OPT_FRAME)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_FRAME), "TYPE 1")
	_menu.adjust(-1)
	assert_eq(_options.textbox_frame, Gen2Options.FRAME_COUNT - 1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_FRAME), "TYPE 8")
	_menu.adjust(1)
	assert_eq(_value_at(Gen2WorldOptionsMenu.OPT_FRAME), "TYPE 1")


func test_cancel_has_nothing_to_adjust() -> void:
	_select(Gen2WorldOptionsMenu.OPT_CANCEL)
	assert_false(_menu.adjust(1))
	assert_false(_menu.adjust(-1))


func test_adjust_by_zero_changes_nothing() -> void:
	_select(Gen2WorldOptionsMenu.OPT_TEXT_SPEED)
	assert_false(_menu.adjust(0))
	assert_eq(_options.text_speed, 1)


## The model edits the object it was handed, which is what lets the launcher
## card and this menu share one Gen2OptionsStore instance.
func test_the_menu_edits_the_options_object_it_was_given() -> void:
	_select(Gen2WorldOptionsMenu.OPT_BATTLE_STYLE)
	_menu.adjust(1)
	assert_true(_options.battle_style_set)
	assert_same(_menu.options(), _options)


## A null Gen2Options is a caller mistake, not a crash: the menu builds its own
## defaults the way Gen2Options.parse clamps rather than refusing.
func test_a_null_options_object_builds_defaults() -> void:
	var menu: Gen2WorldOptionsMenu = Gen2WorldOptionsMenu.build(null)
	assert_not_null(menu.options())
	assert_eq(menu.rows().size(), Gen2WorldOptionsMenu.NUM_OPTIONS)
