class_name Gen2Options
extends RefCounted

## Player options, in two independent blocks.
##
## The cartridge block is the real `wOptions` .. `wOptionsEnd` bytes, so the
## in-game OPTION menu and this launcher screen can never disagree about what a
## setting means. The app block is everything the hardware had no concept of.
##
## `data/default_options.asm` is byte identical between the two pins, so nothing
## here is profile split.

const FORMAT_VERSION: int = 1

## `constants/ram_constants.asm`: bits 0-2 of `wOptions`.
const TEXT_DELAY_FAST: int = 1
const TEXT_DELAY_MED: int = 3
const TEXT_DELAY_SLOW: int = 5
const TEXT_DELAY_MASK: int = 0b111
## The delays above are frame counts, so a rate needs the frame.
const FRAME_SECONDS: float = 1.0 / 60.0
const TEXT_DELAYS: Array[int] = [TEXT_DELAY_FAST, TEXT_DELAY_MED, TEXT_DELAY_SLOW]

## Both of these read backwards: `options_menu.asm` `Options_BattleScene`
## clears BATTLE_SCENE to turn the scene ON, and `Options_BattleStyle` sets
## BATTLE_SHIFT to select SET rather than SHIFT.
const BIT_NO_TEXT_SCROLL: int = 4
const BIT_STEREO: int = 5
const BIT_BATTLE_SHIFT: int = 6
const BIT_BATTLE_SCENE: int = 7
## `wOptions2`. pokecrystal's wram comment says bit 1; its own MENU_ACCOUNT
## constant and every `bit`/`set`/`res` against it say bit 0, as does pokegold.
const BIT_MENU_ACCOUNT: int = 0

const FRAME_COUNT: int = 8
## `GetPrinterSetting` maps only these five values; anything else reads NORMAL.
const PRINTER_BRIGHTNESS: Array[int] = [0x00, 0x20, 0x40, 0x60, 0x7F]
const PRINTER_NORMAL_INDEX: int = 2

## `DefaultOptions` is 8 bytes ending at `wOptionsEnd`; byte 1 is
## `wSaveFileExists` and bytes 6-7 are padding, so neither is an option.
const SOURCE_BLOCK_SIZE: int = 8
const OFFSET_OPTIONS: int = 0
const OFFSET_TEXTBOX_FRAME: int = 2
const OFFSET_TEXTBOX_FLAGS: int = 3
const OFFSET_PRINTER: int = 4
const OFFSET_OPTIONS2: int = 5

## `wTextboxFlags` bit 0. Default on, meaning the text speed above is used.
const BIT_FAST_TEXT_DELAY: int = 0

const MAX_VOLUME: int = 10
const VIDEO_MODES: Array[StringName] = [&"windowed", &"fullscreen", &"borderless"]
const GAME_SPEEDS: Array[StringName] = [&"normal", &"double", &"half"]
const FPS_CHOICES: Array[int] = [30, 60, 120, 144, 0]
const UI_THEMES: Array[StringName] = [&"light", &"dark"]
## `auto` shows the on-screen controller while the player is using the
## touchscreen and hides it the moment they press a key or a pad. `never` is for
## a phone with a controller attached; [Gen2TapGesture] is the way back from it.
const TOUCH_AUTO: StringName = &"auto"
const TOUCH_ALWAYS: StringName = &"always"
const TOUCH_NEVER: StringName = &"never"
const TOUCH_MODES: Array[StringName] = [TOUCH_AUTO, TOUCH_ALWAYS, TOUCH_NEVER]

# Cartridge block.
var text_speed: int = 1
var battle_scene: bool = true
var battle_style_set: bool = false
var stereo: bool = false
var printer_brightness: int = PRINTER_NORMAL_INDEX
var menu_account: bool = true
var textbox_frame: int = 0
var fast_text_delay: bool = true

# App block.
var music_volume: int = 7
var sfx_volume: int = 7
var video_mode: StringName = &"windowed"
var max_fps: int = 60
var game_speed: StringName = &"normal"
var ui_theme: StringName = &"light"
## Button bindings, in the shape [Gen2InputActions] stores. Held as data rather
## than as an [InputMap] state so the file is the whole scheme and nothing has
## to read the engine back to know what the player chose.
## What the engine does where this project and the cartridge disagree, and the
## difficulty. Its own object because it belongs to a run rather than to this
## installation: see [Gen2Rules] and [member Gen2SaveData.run_rules].
var rules: Gen2Rules = Gen2Rules.new()

var controls: Dictionary = Gen2InputActions.defaults()
## What the player bound a mod's own actions to, keyed by the [InputMap] action
## name rather than by a button. Separate from [member controls] because a mod's
## action is not one of the cartridge's eight and an uninstalled mod's leftover
## row should be visibly not one of them.
var mod_controls: Dictionary = {}
var touch_mode: StringName = TOUCH_AUTO
var touch_layout: Gen2TouchLayout = Gen2TouchLayout.new()


## The cartridge block as the bytes the hardware kept, `DefaultOptions` order.
func to_source_bytes() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(SOURCE_BLOCK_SIZE)
	var options: int = TEXT_DELAYS[clampi(text_speed, 0, TEXT_DELAYS.size() - 1)]
	if not battle_scene:
		options |= 1 << BIT_BATTLE_SCENE
	if battle_style_set:
		options |= 1 << BIT_BATTLE_SHIFT
	if stereo:
		options |= 1 << BIT_STEREO
	bytes[OFFSET_OPTIONS] = options
	bytes[OFFSET_TEXTBOX_FRAME] = clampi(textbox_frame, 0, FRAME_COUNT - 1)
	bytes[OFFSET_TEXTBOX_FLAGS] = (1 << BIT_FAST_TEXT_DELAY) if fast_text_delay else 0
	bytes[OFFSET_PRINTER] = PRINTER_BRIGHTNESS[
		clampi(printer_brightness, 0, PRINTER_BRIGHTNESS.size() - 1)
	]
	bytes[OFFSET_OPTIONS2] = (1 << BIT_MENU_ACCOUNT) if menu_account else 0
	return bytes


## Frames `PrintLetterDelay` waits between two characters: the low three bits of
## `wOptions`, unless `wTextboxFlags`' FAST_TEXT_DELAY bit is clear, which is the
## routine's own `.fast` branch and overrides the row with one frame
## (`home/print_text.asm`).
func text_delay_frames() -> int:
	if not fast_text_delay:
		return TEXT_DELAY_FAST
	return TEXT_DELAYS[clampi(text_speed, 0, TEXT_DELAYS.size() - 1)]


## The same thing as a rate, which is what a text box driven by elapsed time
## needs: 60, 20 or 12 characters a second. See [member Gen2TextBox.reveal_speed].
func text_reveal_speed() -> float:
	return 1.0 / (FRAME_SECONDS * float(text_delay_frames()))


## Reads a cartridge block back. A short block is refused rather than padded,
## since a truncated one says nothing about what the missing bytes meant.
func apply_source_bytes(bytes: PackedByteArray) -> bool:
	if bytes.size() < SOURCE_BLOCK_SIZE:
		return false
	var options: int = bytes[OFFSET_OPTIONS]
	text_speed = _text_speed_index(options & TEXT_DELAY_MASK)
	battle_scene = (options & (1 << BIT_BATTLE_SCENE)) == 0
	battle_style_set = (options & (1 << BIT_BATTLE_SHIFT)) != 0
	stereo = (options & (1 << BIT_STEREO)) != 0
	textbox_frame = bytes[OFFSET_TEXTBOX_FRAME] & 0b111
	fast_text_delay = (bytes[OFFSET_TEXTBOX_FLAGS] & (1 << BIT_FAST_TEXT_DELAY)) != 0
	printer_brightness = _printer_index(bytes[OFFSET_PRINTER])
	menu_account = (bytes[OFFSET_OPTIONS2] & (1 << BIT_MENU_ACCOUNT)) != 0
	return true


## `GetTextSpeed` recognises only fast and slow; everything else is medium.
func _text_speed_index(delay: int) -> int:
	match delay:
		TEXT_DELAY_FAST:
			return 0
		TEXT_DELAY_SLOW:
			return 2
		_:
			return 1


## `GetPrinterSetting`, whose fallthrough is NORMAL for any unlisted value.
func _printer_index(brightness: int) -> int:
	var found: int = PRINTER_BRIGHTNESS.find(brightness & 0x7F)
	return found if found >= 0 else PRINTER_NORMAL_INDEX


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"text_speed": text_speed,
		"battle_scene": battle_scene,
		"battle_style_set": battle_style_set,
		"stereo": stereo,
		"printer_brightness": printer_brightness,
		"menu_account": menu_account,
		"textbox_frame": textbox_frame,
		"fast_text_delay": fast_text_delay,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"video_mode": String(video_mode),
		"max_fps": max_fps,
		"game_speed": String(game_speed),
		"ui_theme": String(ui_theme),
		"rules": rules.to_dict(),
		"controls": Gen2InputActions.to_dict(controls),
		"mod_controls": mod_controls.duplicate(true),
		"touch_mode": String(touch_mode),
		"touch_layout": touch_layout.to_dict(),
	}


## Every field is clamped rather than refused: an options file is not a save,
## and one unreadable value should not cost the player the rest of the file.
static func parse(raw: Variant) -> Gen2Options:
	var options := Gen2Options.new()
	if raw is not Dictionary:
		return options
	var row: Dictionary = raw
	options.text_speed = clampi(int(row.get("text_speed", 1)), 0, 2)
	options.battle_scene = bool(row.get("battle_scene", true))
	options.battle_style_set = bool(row.get("battle_style_set", false))
	options.stereo = bool(row.get("stereo", false))
	options.printer_brightness = clampi(
		int(row.get("printer_brightness", PRINTER_NORMAL_INDEX)),
		0,
		PRINTER_BRIGHTNESS.size() - 1,
	)
	options.menu_account = bool(row.get("menu_account", true))
	options.textbox_frame = clampi(int(row.get("textbox_frame", 0)), 0, FRAME_COUNT - 1)
	options.fast_text_delay = bool(row.get("fast_text_delay", true))
	options.music_volume = clampi(int(row.get("music_volume", 7)), 0, MAX_VOLUME)
	options.sfx_volume = clampi(int(row.get("sfx_volume", 7)), 0, MAX_VOLUME)
	options.video_mode = _one_of(row.get("video_mode", ""), VIDEO_MODES)
	options.game_speed = _one_of(row.get("game_speed", ""), GAME_SPEEDS)
	options.ui_theme = _one_of(row.get("ui_theme", ""), UI_THEMES)
	var fps: int = int(row.get("max_fps", 60))
	options.max_fps = fps if FPS_CHOICES.has(fps) else 60
	options.rules = Gen2Rules.parse(row.get("rules"))
	options.controls = Gen2InputActions.sanitize(row.get("controls"))
	options.mod_controls = Gen2InputActions.sanitize_mod_controls(row.get("mod_controls"))
	options.touch_mode = _one_of(row.get("touch_mode", ""), TOUCH_MODES)
	options.touch_layout = Gen2TouchLayout.parse(row.get("touch_layout"))
	return options


static func _one_of(value: Variant, allowed: Array[StringName]) -> StringName:
	var name := StringName(String(value))
	return name if allowed.has(name) else allowed[0]
