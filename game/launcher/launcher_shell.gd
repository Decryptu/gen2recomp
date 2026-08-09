class_name Gen2LauncherShell
extends Control

## The frame every launcher screen sits in: a tinted backdrop, a slim top bar, a
## page host, and the dock of round buttons along the bottom.
##
## The dock is the same shape on a desktop and on a phone, so there is no
## breakpoint that moves the navigation from one edge to another. What changes
## with width is only how much room the page gets.

signal page_selected(id: StringName)

## Width below which the launcher writes smaller and pads tighter.
const COMPACT_WIDTH: float = 820.0
const LOGO: Texture2D = preload("res://assets/launcher/logo.png")

var theme_palette: Gen2LauncherTheme = null
var compact: bool = false

var _backdrop: TextureRect = null
## The pool of colour behind the stage. It is one white radial texture tinted by
## [member Control.modulate], so a new selection costs no texture at all.
var _pool: TextureRect = null
var _tint: Color = Color(0, 0, 0, 0)
var _host: MarginContainer = null
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
	shell._tint = palette.accent
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

	_pool = TextureRect.new()
	_pool.texture = _tint_pool()
	_pool.stretch_mode = TextureRect.STRETCH_SCALE
	_pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pool.modulate = _tint
	add_child(_pool)

	_host = MarginContainer.new()
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_host)
	var root: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	_host.add_child(root)

	var top: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	root.add_child(top)
	top.add_child(_brand())
	top.add_child(Gen2LauncherUI.spacer())
	_top_right = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	_top_right.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(_top_right)

	_pages = MarginContainer.new()
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_pages)

	root.add_child(_build_dock())

	_toast = Gen2LauncherToast.create(theme_palette)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -190.0
	_toast.offset_bottom = -110.0
	add_child(_toast)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	resized.connect(_apply_layout)
	_apply_layout()
	_focus = Gen2FocusGuard.attach(self)


func _brand() -> HBoxContainer:
	var brand: HBoxContainer = Gen2LauncherUI.row(10)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mark := TextureRect.new()
	mark.texture = LOGO
	mark.custom_minimum_size = Vector2(30, 30)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(mark)
	var wordmark := RichTextLabel.new()
	wordmark.bbcode_enabled = true
	wordmark.fit_content = true
	wordmark.scroll_active = false
	wordmark.autowrap_mode = TextServer.AUTOWRAP_OFF
	wordmark.custom_minimum_size = Vector2(140, 0)
	wordmark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wordmark.add_theme_font_size_override("normal_font_size", Gen2LauncherTheme.FONT_TITLE)
	wordmark.text = "[b]gen[color=#%s]2[/color]recomp[/b]" % theme_palette.accent.to_html(false)
	wordmark.add_theme_color_override("default_color", theme_palette.text)
	brand.add_child(wordmark)
	return brand


## The dock floats over the page rather than sitting in a bar across it, so a
## narrow window loses nothing but the space either side of it.
func _build_dock() -> CenterContainer:
	_dock_host = CenterContainer.new()
	var centre: CenterContainer = _dock_host
	var card: Gen2LauncherCard = Gen2LauncherCard.floating(
		theme_palette, Gen2LauncherTheme.RADIUS_LG, 12, 22
	)
	centre.add_child(card)
	_dock = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	card.add_child(_dock)
	return centre


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
		var entry: Dictionary = _buttons[key]
		var button: Gen2LauncherButton = entry["button"]
		button.set_active(key == id)
		var label: Label = entry["label"]
		label.add_theme_color_override(
			"font_color", theme_palette.accent if key == id else theme_palette.faint
		)
	# A page that has just been hidden takes its focus with it, so the new one
	# needs somewhere for a pad to land.
	if _focus != null:
		_focus.refresh.call_deferred()
	page_selected.emit(id)


func current_page() -> StringName:
	return _current


func toast() -> Gen2LauncherToast:
	return _toast


## Lights the backdrop in [param colour], which is how the shell says which
## cartridge is selected without writing it anywhere. Pass a transparent colour
## to put the light out, which is what every page but the shelf wants: there the
## wash would only be a smudge behind a card.
func set_tint(colour: Color) -> void:
	_tint = colour
	if not is_inside_tree():
		_pool.modulate = colour
		return
	create_tween().tween_property(_pool, "modulate", colour, 0.35)


## A wipe over everything, used when a game is about to open.
func flash(duration: float = 0.4) -> void:
	if not is_inside_tree():
		return
	_flash.color = Color(0, 0, 0, 0) if theme_palette.is_dark() else Color(1, 1, 1, 0)
	var tween: Tween = create_tween()
	tween.tween_property(_flash, "color:a", 1.0, duration).set_ease(Tween.EASE_IN)
	await tween.finished


func _rebuild_dock() -> void:
	for child: Node in _dock.get_children():
		child.queue_free()
	_buttons.clear()
	# A screen with one page has nowhere to navigate to, so it gets no dock.
	_dock_host.visible = _entries.size() > 1
	for entry: Dictionary in _entries:
		var id: StringName = entry["id"]
		var column: VBoxContainer = Gen2LauncherUI.column(4)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		var button: Gen2LauncherButton = Gen2LauncherButton.dock(theme_palette, entry["glyph"])
		button.tooltip_text = String(entry["label"])
		button.pressed.connect(select.bind(id))
		column.add_child(button)
		var label: Label = Gen2LauncherUI.caption(theme_palette, String(entry["label"]))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		_dock.add_child(column)
		_buttons[id] = {"button": button, "label": label}
	if not _current.is_empty():
		select(_current)


func _apply_layout() -> void:
	var wide: bool = size.x >= COMPACT_WIDTH
	var margin: int = 30 if wide else 16
	_host.add_theme_constant_override("margin_left", margin)
	_host.add_theme_constant_override("margin_right", margin)
	_host.add_theme_constant_override("margin_top", 20 if wide else 14)
	# The dock floats, so the bottom margin has to clear its shadow as well as
	# the card itself.
	_host.add_theme_constant_override("margin_bottom", 30 if wide else 22)
	_place_pool()
	if compact == not wide and not _entries.is_empty():
		return
	compact = not wide
	for key: StringName in _page_nodes:
		var page: Control = _page_nodes[key]
		if page.has_method("set_compact"):
			page.call("set_compact", compact)


## A square of colour fading to nothing, centred on the stage. Sized to overhang
## the window so its edge is never on screen.
func _place_pool() -> void:
	var side: float = maxf(size.x, size.y) * 1.15
	_pool.size = Vector2(side, side)
	_pool.position = Vector2(size.x * 0.5, size.y * 0.42) - _pool.size * 0.5


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


func _tint_pool() -> GradientTexture2D:
	var ramp := Gradient.new()
	# Drawn white so one texture serves every cartridge: the colour arrives as
	# the node's modulate. The middle stop keeps the wash under the stage instead
	# of letting it creep across the whole page.
	var peak: float = 0.20 if theme_palette.is_dark() else 0.14
	ramp.offsets = PackedFloat32Array([0.0, 0.34, 1.0])
	ramp.colors = PackedColorArray([
		Color(1, 1, 1, peak), Color(1, 1, 1, peak * 0.28), Color(1, 1, 1, 0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture
