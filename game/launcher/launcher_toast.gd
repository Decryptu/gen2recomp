class_name Gen2LauncherToast
extends Control

## What the launcher has to say about the last thing that happened, shown only
## while it is worth saying.
##
## It replaces a permanent status strip: a screen with nothing to report should
## look like a screen with nothing to report. Success and information fade out on
## their own; a refusal and a running import stay until they are replaced.

## How long a message that reports no problem stays up.
const LINGER: float = 3.6
const ICON: float = 22.0

var _theme: Gen2LauncherTheme = null
var _card: Gen2LauncherCard = null
var _icon: Gen2LauncherIcon = null
var _heading: Label = null
var _detail: Label = null
var _progress: ProgressBar = null
var _timer: SceneTreeTimer = null
## The one fade in flight. Raising and hiding overlap often enough that two
## tweens would otherwise race for the same alpha and the later one would lose.
var _fade: Tween = null
var _shown: bool = false


static func create(palette: Gen2LauncherTheme) -> Gen2LauncherToast:
	var toast := Gen2LauncherToast.new()
	toast._theme = palette
	toast._build()
	return toast


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	modulate.a = 0.0
	# A toast that has faded out is gone, not merely transparent. Alpha alone
	# leaves the card in the hit test over whatever the page put at the bottom
	# of the screen, which on the shelf is Play and the cache button.
	visible = false

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	# A chip rather than a card: the toast lies over whatever the page is doing,
	# so it is drawn on the opposite side of the page from everything under it.
	_card = Gen2LauncherCard.chip(_theme, Gen2LauncherTheme.RADIUS_MD, 16, 20)
	_card.custom_minimum_size = Vector2(360, 0)
	# Nothing in here is clickable, so nothing in here takes a click. The card
	# is the width of the shelf's action row and sits exactly on top of it.
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_card)

	var column: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_SM)
	_card.add_child(column)
	var line: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	column.add_child(line)
	_icon = Gen2LauncherIcon.create(&"about", ICON, _theme.on_surface)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_icon)
	var text: VBoxContainer = Gen2LauncherUI.column(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	_heading = Gen2LauncherUI.body(_theme, "")
	text.add_child(_heading)
	_detail = Gen2LauncherUI.muted(_theme, "")
	_detail.add_theme_color_override("font_color", _theme.with_alpha(_theme.on_surface, 0.75))
	text.add_child(_detail)

	_progress = ProgressBar.new()
	_progress.max_value = 100.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 5)
	_progress.visible = false
	# A bar that reports progress is read, never dragged.
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The bar sits on the chip, so it is styled against that rather than against
	# the page the stock theme was written for.
	_progress.add_theme_stylebox_override(
		"background", _theme.box(_theme.with_alpha(_theme.on_surface, 0.20), 4.0)
	)
	_progress.add_theme_stylebox_override("fill", _theme.box(_theme.accent, 4.0))
	column.add_child(_progress)


## [param kind] is one of info, success, error or busy, which chooses the icon
## and the colour the heading is written in.
func show_message(kind: StringName, heading: String, detail: String) -> void:
	if heading.is_empty():
		hide_message()
		return
	var colour: Color = _theme.on_surface
	var glyph: StringName = &"about"
	match kind:
		&"success":
			colour = _theme.on_chip(_theme.success)
			glyph = &"check"
		&"error":
			colour = _theme.on_chip(_theme.error)
			glyph = &"warning"
		&"busy":
			colour = _theme.on_chip(_theme.accent)
			glyph = &"refresh"
	_icon.set_glyph(glyph, ICON, colour)
	_heading.text = heading
	_heading.add_theme_color_override("font_color", colour)
	_detail.text = detail
	_detail.visible = not detail.is_empty()
	_raise()
	if kind == &"error" or kind == &"busy":
		_cancel_timer()
		return
	_dismiss_after(LINGER)


func set_progress(shown: bool, value: float = 0.0) -> void:
	_progress.visible = shown
	_progress.value = value


func hide_message() -> void:
	_cancel_timer()
	if not _shown:
		return
	_shown = false
	set_progress(false)
	if not is_inside_tree():
		modulate.a = 0.0
		visible = false
		return
	_fade = _restart_fade()
	_fade.tween_property(self, "modulate:a", 0.0, 0.20)
	_fade.tween_property(_card, "position:y", _card.position.y + 12.0, 0.20)
	_fade.chain().tween_callback(func() -> void: visible = false)


func _raise() -> void:
	visible = true
	if _shown or not is_inside_tree():
		modulate.a = 1.0
		_shown = true
		return
	_shown = true
	modulate.a = 0.0
	_fade = _restart_fade()
	_fade.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_fade.tween_property(self, "modulate:a", 1.0, 0.22)
	_fade.tween_method(
		func(offset: float) -> void: _card.position.y = offset, 14.0, 0.0, 0.26
	)


func _restart_fade() -> Tween:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	return tween


func _dismiss_after(seconds: float) -> void:
	_cancel_timer()
	if not is_inside_tree():
		return
	_timer = get_tree().create_timer(seconds)
	_timer.timeout.connect(hide_message)


func _cancel_timer() -> void:
	if _timer != null and _timer.timeout.is_connected(hide_message):
		_timer.timeout.disconnect(hide_message)
	_timer = null
