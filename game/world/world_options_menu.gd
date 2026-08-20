class_name Gen2WorldOptionsMenu
extends RefCounted

## Scene-free model of the in-game OPTION menu (engine/menus/options_menu.asm).
##
## Seven value rows plus CANCEL, each row a left/right cycle over one field of
## [Gen2Options]. The model edits that object in place and never touches the
## file: [Gen2OptionsStore] owns persistence, the way [Gen2InputActions] leaves
## it alone.
##
## `data/default_options.asm` and the whole menu are byte identical between the
## pins except pokegold's `.ExitOptions` lacking the `SFX_TRANSACTION` play, so
## nothing here is profile split.

## GetOptionPointer.Pointers indexes.
const OPT_TEXT_SPEED: int = 0
const OPT_BATTLE_SCENE: int = 1
const OPT_BATTLE_STYLE: int = 2
const OPT_SOUND: int = 3
const OPT_PRINT: int = 4
const OPT_MENU_ACCOUNT: int = 5
const OPT_FRAME: int = 6
const OPT_CANCEL: int = 7
const NUM_OPTIONS: int = 8

## `StringOptions` and each handler's own value strings.
const TEXT_SPEED_VALUES: Array[String] = ["FAST", "MID", "SLOW"]
const PRINT_VALUES: Array[String] = ["LIGHTEST", "LIGHTER", "NORMAL", "DARKER", "DARKEST"]

const ROWS: Array[Dictionary] = [
	{"index": OPT_TEXT_SPEED, "label": "TEXT SPEED"},
	{"index": OPT_BATTLE_SCENE, "label": "BATTLE SCENE"},
	{"index": OPT_BATTLE_STYLE, "label": "BATTLE STYLE"},
	{"index": OPT_SOUND, "label": "SOUND"},
	{"index": OPT_PRINT, "label": "PRINT"},
	{"index": OPT_MENU_ACCOUNT, "label": "MENU ACCOUNT"},
	{"index": OPT_FRAME, "label": "FRAME"},
	{"index": OPT_CANCEL, "label": "CANCEL"},
]

var cursor: int = 0
var _options: Gen2Options = null


static func build(source_options: Gen2Options) -> Gen2WorldOptionsMenu:
	var menu := Gen2WorldOptionsMenu.new()
	menu._options = source_options if source_options != null else Gen2Options.new()
	return menu


func options() -> Gen2Options:
	return _options


func size() -> int:
	return ROWS.size()


## `OptionsControl`. Its two odd branches, `.CheckMenuAccount` writing
## OPT_MENU_ACCOUNT back before its own `inc` and `.UpPressed` special-casing
## OPT_FRAME, each land on exactly the value the plain step would, so this is a
## plain wrap in both directions. The source's own comments call them
## unexplained.
func move(delta: int) -> bool:
	if delta == 0:
		return false
	cursor = wrapi(cursor + signi(delta), 0, ROWS.size())
	return true


## CANCEL is the only row A answers: every other handler reads left and right
## alone, so A on them does nothing.
func is_cancel() -> bool:
	return cursor == OPT_CANCEL


## Left or right on the selected row. The four bit rows toggle on either
## direction, since each handler's `.LeftPressed` jumps to the opposite branch
## from `.NonePressed` rather than stepping the other way. Returns whether a
## value changed, so a caller knows when to write the file.
func adjust(delta: int) -> bool:
	if delta == 0:
		return false
	var step: int = signi(delta)
	match cursor:
		OPT_TEXT_SPEED:
			_options.text_speed = wrapi(
				_options.text_speed + step, 0, TEXT_SPEED_VALUES.size()
			)
		OPT_BATTLE_SCENE:
			_options.battle_scene = not _options.battle_scene
		OPT_BATTLE_STYLE:
			_options.battle_style_set = not _options.battle_style_set
		OPT_SOUND:
			_options.stereo = not _options.stereo
		OPT_PRINT:
			_options.printer_brightness = wrapi(
				_options.printer_brightness + step, 0, PRINT_VALUES.size()
			)
		OPT_MENU_ACCOUNT:
			_options.menu_account = not _options.menu_account
		## `maskbits NUM_FRAMES`, so it wraps rather than clamping.
		OPT_FRAME:
			_options.textbox_frame = wrapi(
				_options.textbox_frame + step, 0, Gen2Options.FRAME_COUNT
			)
		_:
			return false
	return true


## One `{index, label, value}` per row for a renderer. CANCEL carries an empty
## value, since the source prints no setting beside it.
func rows() -> Array:
	var built: Array = []
	for row: Dictionary in ROWS:
		built.append({
			"index": int(row["index"]),
			"label": String(row["label"]),
			"value": _value_label(int(row["index"])),
		})
	return built


func _value_label(index: int) -> String:
	match index:
		OPT_TEXT_SPEED:
			return TEXT_SPEED_VALUES[
				clampi(_options.text_speed, 0, TEXT_SPEED_VALUES.size() - 1)
			]
		OPT_BATTLE_SCENE:
			return "ON" if _options.battle_scene else "OFF"
		OPT_BATTLE_STYLE:
			return "SET" if _options.battle_style_set else "SHIFT"
		OPT_SOUND:
			return "STEREO" if _options.stereo else "MONO"
		OPT_PRINT:
			return PRINT_VALUES[
				clampi(_options.printer_brightness, 0, PRINT_VALUES.size() - 1)
			]
		OPT_MENU_ACCOUNT:
			return "ON" if _options.menu_account else "OFF"
		## `UpdateFrame` draws the stored 0-7 with `add '1'`.
		OPT_FRAME:
			return "TYPE %d" % (clampi(_options.textbox_frame, 0, Gen2Options.FRAME_COUNT - 1) + 1)
		_:
			return ""
