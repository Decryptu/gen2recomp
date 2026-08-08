class_name Gen2SettingsDialog
extends AcceptDialog

## Edits [Gen2Options] in two sections: the cartridge's own OPTION menu and the
## things the hardware had no concept of.
##
## Stock controls, no styling. Every change writes immediately, because there is
## no state here worth an apply button and a half-applied options file is worse
## than none.

## Label, then the values in the order the source cycles them.
const TEXT_SPEEDS: Array[String] = ["Fast", "Mid", "Slow"]
const PRINTER_LABELS: Array[String] = ["Lightest", "Lighter", "Normal", "Darker", "Darkest"]

var _options: Gen2Options = null
var _saved: Label = null


func _init() -> void:
	title = "Settings"
	ok_button_text = "Close"
	_options = Gen2OptionsStore.current()
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(520, 0)
	add_child(root)

	root.add_child(_heading("Cartridge options"))
	root.add_child(_choice("Text speed", TEXT_SPEEDS, _options.text_speed,
		func(index: int) -> void: _options.text_speed = index
	))
	root.add_child(_toggle("Battle scene", _options.battle_scene,
		func(on: bool) -> void: _options.battle_scene = on
	))
	root.add_child(_choice("Battle style", ["Shift", "Set"], 1 if _options.battle_style_set else 0,
		func(index: int) -> void: _options.battle_style_set = index == 1
	))
	root.add_child(_choice("Sound", ["Mono", "Stereo"], 1 if _options.stereo else 0,
		func(index: int) -> void: _options.stereo = index == 1
	))
	root.add_child(_number("Textbox frame", _options.textbox_frame, 0, Gen2Options.FRAME_COUNT - 1,
		func(value: int) -> void: _options.textbox_frame = value
	))
	root.add_child(_toggle("Menu account", _options.menu_account,
		func(on: bool) -> void: _options.menu_account = on
	))
	root.add_child(_choice("Print", PRINTER_LABELS, _options.printer_brightness,
		func(index: int) -> void: _options.printer_brightness = index
	))

	root.add_child(_heading("Application"))
	root.add_child(_number("Music volume", _options.music_volume, 0, Gen2Options.MAX_VOLUME,
		func(value: int) -> void: _options.music_volume = value
	))
	root.add_child(_number("Sound volume", _options.sfx_volume, 0, Gen2Options.MAX_VOLUME,
		func(value: int) -> void: _options.sfx_volume = value
	))
	root.add_child(_choice("Video mode", _titles(Gen2Options.VIDEO_MODES),
		maxi(Gen2Options.VIDEO_MODES.find(_options.video_mode), 0),
		func(index: int) -> void: _options.video_mode = Gen2Options.VIDEO_MODES[index]
	))
	root.add_child(_choice("Game speed", _titles(Gen2Options.GAME_SPEEDS),
		maxi(Gen2Options.GAME_SPEEDS.find(_options.game_speed), 0),
		func(index: int) -> void: _options.game_speed = Gen2Options.GAME_SPEEDS[index]
	))
	var fps_labels: Array[String] = []
	for fps: int in Gen2Options.FPS_CHOICES:
		fps_labels.append("Unlimited" if fps == 0 else str(fps))
	root.add_child(_choice("Max FPS", fps_labels,
		maxi(Gen2Options.FPS_CHOICES.find(_options.max_fps), 0),
		func(index: int) -> void: _options.max_fps = Gen2Options.FPS_CHOICES[index]
	))

	_saved = Label.new()
	root.add_child(_saved)


func _titles(values: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for value: StringName in values:
		out.append(String(value).capitalize())
	return out


func _persist() -> void:
	var ok: bool = Gen2OptionsStore.save(_options)
	_saved.text = "Saved to %s" % Gen2OptionsStore.PATH if ok else "The options file could not be written."


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	return label


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(180, 0)
	row.add_child(label)
	return row


func _choice(text: String, values: Array, selected: int, handler: Callable) -> HBoxContainer:
	var row: HBoxContainer = _row(text)
	var picker := OptionButton.new()
	for index: int in values.size():
		picker.add_item(String(values[index]), index)
	picker.selected = clampi(selected, 0, values.size() - 1)
	picker.item_selected.connect(func(index: int) -> void:
		handler.call(index)
		_persist()
	)
	row.add_child(picker)
	return row


func _toggle(text: String, pressed: bool, handler: Callable) -> HBoxContainer:
	var row: HBoxContainer = _row(text)
	var box := CheckBox.new()
	box.button_pressed = pressed
	box.toggled.connect(func(on: bool) -> void:
		handler.call(on)
		_persist()
	)
	row.add_child(box)
	return row


func _number(text: String, value: int, minimum: int, maximum: int, handler: Callable) -> HBoxContainer:
	var row: HBoxContainer = _row(text)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.value_changed.connect(func(changed: float) -> void:
		handler.call(int(changed))
		_persist()
	)
	row.add_child(spin)
	return row
