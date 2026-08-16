class_name Gen2LauncherShell
extends Control

## The frame every launcher screen sits in: a backdrop, a status bar carrying the
## clock and the charge, a page host, and the row of round buttons along the
## bottom.
##
## The dock is the same shape on a desktop and on a phone, so there is no
## breakpoint that moves the navigation from one edge to another. What changes
## with width is only how much room the page gets and how big the discs are.

signal page_selected(id: StringName)

## Width below which the launcher writes smaller and pads tighter.
const COMPACT_WIDTH: float = 820.0
## Room kept for a message and its detail line above the page.
const TOAST_HEIGHT: float = 84.0

var theme_palette: Gen2LauncherTheme = null
var compact: bool = false

var _backdrop: TextureRect = null
## The two layers a cartridge's artwork crossfades between, and the sheet of
## page colour over them that keeps the launcher readable on top of a picture.
var _art_holder: Control = null
var _art_back: TextureRect = null
var _art_front: TextureRect = null
var _art_veil: ColorRect = null
var _art_texture: Texture2D = null
var _art_tween: Tween = null
var _host: MarginContainer = null
var _clock: Label = null
var _battery: Gen2LauncherBattery = null
var _top_right: HBoxContainer = null
var _pages: MarginContainer = null
var _dock_host: CenterContainer = null
var _dock: HBoxContainer = null
var _toast: Gen2LauncherToast = null
var _flash: ColorRect = null
var _entries: Array[Dictionary] = []
var _buttons: Dictionary = {}
var _page_nodes: Dictionary = {}
var _current: StringName = &""
var _focus: Gen2FocusGuard = null


static func create(palette: Gen2LauncherTheme) -> Gen2LauncherShell:
	var shell := Gen2LauncherShell.new()
	shell.theme_palette = palette
	shell._build()
	return shell


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = theme_palette.control_theme()

	_backdrop = TextureRect.new()
	_backdrop.texture = _page_gradient()
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	# The artwork and the sheet of page colour over it fade together, so a page
	# with no cartridge behind it is the plain gradient rather than a veil over
	# nothing. Inside, the two texture layers crossfade one picture into the next.
	_art_holder = Control.new()
	_art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_holder.modulate.a = 0.0
	add_child(_art_holder)
	_art_back = _art_layer()
	_art_front = _art_layer()
	# One sheet of page colour over the artwork rather than a translucent image:
	# the picture is a backdrop, and the text above it has to stay readable
	# whatever the picture happens to be doing underneath.
	_art_veil = ColorRect.new()
	_art_veil.color = theme_palette.with_alpha(
		theme_palette.backdrop_bottom, 0.76 if theme_palette.is_dark() else 0.72
	)
	_art_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_holder.add_child(_art_veil)

	_host = MarginContainer.new()
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_host)
	var root: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	_host.add_child(root)

	var top: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	root.add_child(top)
	_clock = Gen2LauncherUI.title(theme_palette, _now(), Gen2LauncherTheme.FONT_TITLE)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_clock)
	top.add_child(Gen2LauncherUI.spacer())
	_top_right = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	_top_right.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(_top_right)
	_battery = Gen2LauncherBattery.create(theme_palette)
	_battery.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_top_right.add_child(_battery)

	# The clock is only ever read to the minute, but ticking every second keeps
	# it from sitting a whole minute behind the one on the wall.
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(func() -> void: _clock.text = _now())
	add_child(tick)

	_pages = MarginContainer.new()
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_pages)

	root.add_child(_build_dock())

	_toast = Gen2LauncherToast.create(theme_palette)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(_toast)
	_pages.resized.connect(_place_toast)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	resized.connect(_apply_layout)
	_apply_layout()
	_place_toast()
	_focus = Gen2FocusGuard.attach(self)


## The wall clock, on the twenty-four hour dial the rest of the project uses.
func _now() -> String:
	var clock: Dictionary = Time.get_time_dict_from_system()
	return "%02d:%02d" % [int(clock["hour"]), int(clock["minute"])]


## The charge indicator, so a caller with a real power reading can set it.
func battery() -> Gen2LauncherBattery:
	return _battery


## A row of plain discs on the page, with nothing behind them. A bar or a card
## under the dock would be one more surface to place at every width, and the
## discs already say where they are.
func _build_dock() -> CenterContainer:
	_dock_host = CenterContainer.new()
	_dock = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	_dock_host.add_child(_dock)
	return _dock_host


## Adds a top-bar action, right aligned, in the order added.
func add_action(button: Control) -> void:
	_top_right.add_child(button)


## Registers a page and its dock entry. The first page added is shown.
func add_page(id: StringName, label: String, glyph: StringName, page: Control) -> void:
	_entries.append({"id": id, "label": label, "glyph": glyph})
	page.visible = false
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_nodes[id] = page
	_pages.add_child(page)
	_rebuild_dock()
	if _current.is_empty():
		select(id)


func select(id: StringName) -> void:
	if not _page_nodes.has(id):
		return
	_current = id
	for key: StringName in _page_nodes:
		(_page_nodes[key] as Control).visible = key == id
	for key: StringName in _buttons:
		(_buttons[key] as Gen2LauncherButton).set_active(key == id)
	# A page that has just been hidden takes its focus with it, so the new one
	# needs somewhere for a pad to land. A page that names its own landing spot
	# gets it, rather than whatever happens to come first in the tree.
	if _focus != null:
		var page: Control = _page_nodes[id]
		_focus.preferred = page.call("focus_target") if page.has_method("focus_target") else null
		_focus.refresh.call_deferred()
	page_selected.emit(id)


func current_page() -> StringName:
	return _current


func toast() -> Gen2LauncherToast:
	return _toast


## Puts [param texture] behind the launcher, crossfading from whatever was there.
## Pass null for the plain gradient, which is what a page with no cartridge
## behind it wants.
func set_backdrop_art(texture: Texture2D, game_screen: bool = false) -> void:
	if texture == _art_texture:
		return
	_art_texture = texture
	if _art_tween != null and _art_tween.is_valid():
		_art_tween.kill()
	# The layer on show drops to the back so the new picture can come up over it
	# rather than under it.
	var outgoing: TextureRect = _art_front
	_art_front = _art_back
	_art_back = outgoing
	_art_front.texture = texture
	_art_front.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art_front.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if game_screen
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
	_art_front.modulate.a = 0.0
	_art_holder.move_child(_art_back, 0)
	_art_holder.move_child(_art_front, 1)
	if not is_inside_tree():
		_art_front.modulate.a = 1.0
		_art_back.modulate.a = 0.0
		_art_holder.modulate.a = 1.0 if texture != null else 0.0
		return
	_art_tween = create_tween()
	_art_tween.set_parallel(true)
	_art_tween.tween_property(_art_front, "modulate:a", 1.0, 0.45)
	_art_tween.tween_property(_art_back, "modulate:a", 0.0, 0.45)
	_art_tween.tween_property(_art_holder, "modulate:a", 1.0 if texture != null else 0.0, 0.45)


func _art_layer() -> TextureRect:
	var layer := TextureRect.new()
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Covers the window at any shape: a backdrop is allowed to lose its edges,
	# and letterboxing one would show the gradient in two stripes.
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.modulate.a = 0.0
	_art_holder.add_child(layer)
	return layer


## A wipe over everything, used when a game is about to open.
func flash(duration: float = 0.4) -> void:
	if not is_inside_tree():
		return
	_flash.color = Color(0, 0, 0, 0) if theme_palette.is_dark() else Color(1, 1, 1, 0)
	var tween: Tween = create_tween()
	tween.tween_property(_flash, "color:a", 1.0, duration).set_ease(Tween.EASE_IN)
	await tween.finished


func _rebuild_dock() -> void:
	Gen2LauncherUI.clear(_dock)
	_buttons.clear()
	# A screen with one page has nowhere to navigate to, so it gets no dock.
	_dock_host.visible = _entries.size() > 1
	for entry: Dictionary in _entries:
		var id: StringName = entry["id"]
		var button: Gen2LauncherButton = Gen2LauncherButton.dock(theme_palette, entry["glyph"])
		# The name is a tooltip rather than a caption under the disc: a row of
		# four labels is four more things to fit at every width, and the glyph
		# plus the filled disc already say which page is open.
		button.tooltip_text = String(entry["label"])
		button.pressed.connect(select.bind(id))
		_dock.add_child(button)
		_buttons[id] = button
	if not _current.is_empty():
		select(_current)


func _apply_layout() -> void:
	var wide: bool = size.x >= COMPACT_WIDTH
	var margin: int = 30 if wide else 16
	_host.add_theme_constant_override("margin_left", margin)
	_host.add_theme_constant_override("margin_right", margin)
	_host.add_theme_constant_override("margin_top", 20 if wide else 14)
	_host.add_theme_constant_override("margin_bottom", 24 if wide else 16)
	for key: StringName in _buttons:
		(_buttons[key] as Gen2LauncherButton).set_side(
			Gen2LauncherButton.DOCK_SIDE if wide else 46.0
		)
	if compact == not wide and not _entries.is_empty():
		return
	compact = not wide
	for key: StringName in _page_nodes:
		var page: Control = _page_nodes[key]
		if page.has_method("set_compact"):
			page.call("set_compact", compact)


## Just above the page, so the message clears the dock and whatever the page puts
## along its own bottom edge. Measured rather than fixed: a short window has far
## less room under the page than a tall one.
func _place_toast() -> void:
	if _toast == null or _pages == null:
		return
	var below: float = (
		(global_position.y + size.y) - (_pages.global_position.y + _pages.size.y)
	)
	_toast.offset_bottom = -maxf(below + 10.0, 0.0)
	_toast.offset_top = _toast.offset_bottom - TOAST_HEIGHT


func _page_gradient() -> GradientTexture2D:
	var ramp := Gradient.new()
	ramp.set_color(0, theme_palette.backdrop_top)
	ramp.set_color(1, theme_palette.backdrop_bottom)
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.fill_from = Vector2(0.15, 0.0)
	texture.fill_to = Vector2(0.85, 1.0)
	texture.width = 64
	texture.height = 64
	return texture
