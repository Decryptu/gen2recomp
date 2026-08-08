class_name Gen2Cartridge
extends Control

## One cartridge on the stage: an empty bay until its dump is imported, and the
## cartridge itself once it is.
##
## The cartridge owns only presentation. Importing, verification and launching
## all belong to the launcher that listens to these signals.

signal insert_requested
signal play_requested

const ART: Dictionary = {
	&"gold": preload("res://assets/cartridges/gold.webp"),
	&"silver": preload("res://assets/cartridges/silver.webp"),
	&"crystal": preload("res://assets/cartridges/crystal.webp"),
}

## The cartridge shells are 1058 by 1201.
const ASPECT: float = 1058.0 / 1201.0

var game_id: StringName = &""
var imported: bool = false
## How far the cartridge is from the selected one, which decides its size and
## how far back it stands. Set by [Gen2CartridgeStage].
var depth: int = 0

var _theme: Gen2LauncherTheme = null
var _art: TextureRect = null
var _bay: Control = null
var _bay_icon: Gen2LauncherIcon = null
var _bay_label: Label = null
var _hover: bool = false
## The resting height the stage assigns. Animations move the cartridge relative
## to it, so a hop and a layout pass never fight over [member Control.position].
var _rest: float = 0.0
## Vertical offset the animations drive, kept apart from the position the stage
## assigns so the two never fight.
var _hop: float = 0.0:
	set(value):
		_hop = value
		_place()
## Scale the animations drive, on top of the stage's own.
var _squash: Vector2 = Vector2.ONE:
	set(value):
		_squash = value
		_place()


static func create(theme: Gen2LauncherTheme, id: StringName) -> Gen2Cartridge:
	var cartridge := Gen2Cartridge.new()
	cartridge._theme = theme
	cartridge.game_id = id
	cartridge._build()
	return cartridge


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = RomRegistry.title_for(game_id)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	gui_input.connect(_on_input)
	resized.connect(_place)

	_bay = Control.new()
	_bay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bay.draw.connect(_draw_bay)
	add_child(_bay)

	var invitation: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_SM)
	invitation.alignment = BoxContainer.ALIGNMENT_CENTER
	invitation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	invitation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Centred on the label window rather than on the bay, so the prompt sits where
	# a cartridge would carry its sticker.
	invitation.anchor_top = 0.28
	invitation.anchor_bottom = 0.88
	invitation.offset_top = 0.0
	invitation.offset_bottom = 0.0
	_bay.add_child(invitation)
	_bay_icon = Gen2LauncherIcon.create(&"download", 26.0, _theme.faint)
	_bay_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	invitation.add_child(_bay_icon)
	_bay_label = Gen2LauncherUI.muted(_theme, "Drop a dump\nor click to browse")
	_bay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bay_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	invitation.add_child(_bay_label)

	_art = TextureRect.new()
	_art.texture = ART.get(game_id, null)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_art)

	set_imported(false)


func set_imported(state: bool) -> void:
	imported = state
	_art.visible = state
	_bay.visible = not state
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()


## Applied by the stage after it has sized and placed this cartridge.
func set_depth(distance: int) -> void:
	depth = distance
	_bay_label.visible = distance == 0
	_bay_icon.set_glyph(&"download", 26.0 if distance == 0 else 20.0, _theme.faint)
	queue_redraw()


func _place() -> void:
	pivot_offset = size * 0.5
	position.y = _rest + _hop
	scale = _squash
	queue_redraw()


func set_rest_y(y: float) -> void:
	_rest = y
	_place()


func rest_y() -> float:
	return _rest


## The contact shadow under the cartridge and, when the bay is empty, the outline
## that says something belongs here. Drawn rather than styled so both follow the
## cartridge's own silhouette instead of a box around it.
func _draw() -> void:
	# Only a cartridge that is actually standing there casts one. An empty bay is
	# a hole in the shelf, not an object on it.
	if size.x <= 0.0 or not imported:
		return
	var lift: float = 1.0 if depth == 0 else 0.62
	# The higher the cartridge, the wider and fainter the pool under it.
	var rise: float = clampf(absf(_hop) / (size.y * 0.7), 0.0, 1.0)
	var width: float = size.x * lerpf(0.94, 1.30, rise)
	var height: float = size.x * lerpf(0.17, 0.21, rise) * lift
	var alpha: float = 0.46 * lift * lerpf(1.0, 0.30, rise)
	# Sat low enough that most of the pool shows under the cartridge: this node
	# draws before its own art, so anything higher is simply covered up.
	var rect := Rect2(
		Vector2((size.x - width) * 0.5, size.y - height * 0.34 - _hop * 0.28),
		Vector2(width, height),
	)
	draw_texture_rect(_shadow_ramp(), rect, false, _theme.with_alpha(_theme.shadow, alpha))


## One white radial fade, stretched into whatever ellipse the contact shadow
## needs and tinted on the way. A drawn circle would be a hard edged polygon,
## because the vertex count follows the radius and the radius here is one.
static var _shadow: GradientTexture2D = null


static func _shadow_ramp() -> GradientTexture2D:
	if _shadow != null:
		return _shadow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.38, 0.70, 1.0])
	ramp.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.82), Color(1, 1, 1, 0.30), Color(1, 1, 1, 0),
	])
	_shadow = GradientTexture2D.new()
	_shadow.gradient = ramp
	_shadow.fill = GradientTexture2D.FILL_RADIAL
	_shadow.fill_from = Vector2(0.5, 0.5)
	_shadow.fill_to = Vector2(1.0, 0.5)
	_shadow.width = 128
	_shadow.height = 128
	return _shadow


## The empty bay is drawn in the cartridge's own silhouette rather than as a
## rounded box, so the shape itself says what is missing.
func _draw_bay() -> void:
	if _bay.size.x <= 0.0:
		return
	var edge: Color = _theme.accent if _hover else _theme.with_alpha(_theme.faint, 0.7)
	var fill: Color = (
		_theme.accent_wash(0.08) if _hover
		else _theme.with_alpha(_theme.surface, 0.30 if _theme.is_dark() else 0.55)
	)
	var shell: PackedVector2Array = _silhouette(_bay.size)
	_bay.draw_colored_polygon(shell, fill)
	var closed: PackedVector2Array = shell.duplicate()
	closed.append(shell[0])
	_bay.draw_polyline(closed, edge, 2.0, true)
	# The grip at the top and the label window under it: the two details that make
	# the outline read as a cartridge rather than as a card with a corner off.
	var hint: Color = _theme.with_alpha(edge, 0.45)
	_bay.draw_style_box(
		_theme.box(Color(0, 0, 0, 0), _bay.size.y * 0.09, hint),
		Rect2(_bay.size * Vector2(0.17, 0.05), _bay.size * Vector2(0.60, 0.17)),
	)
	_bay.draw_style_box(
		_theme.box(Color(0, 0, 0, 0), Gen2LauncherTheme.RADIUS_SM, hint),
		Rect2(_bay.size * Vector2(0.13, 0.28), _bay.size * Vector2(0.74, 0.60)),
	)


## A rounded rectangle with the notch out of its top right corner that keeps a
## cartridge from going into its slot the wrong way round.
func _silhouette(box: Vector2) -> PackedVector2Array:
	var radius: float = box.x * 0.07
	var notch := Vector2(box.x * 0.10, box.y * 0.06)
	var points := PackedVector2Array()
	points.append_array(_corner(Vector2(radius, radius), radius, PI, PI * 1.5))
	points.append(Vector2(box.x - notch.x, 0.0))
	points.append(Vector2(box.x - notch.x, notch.y))
	points.append(Vector2(box.x, notch.y))
	points.append_array(_corner(Vector2(box.x - radius, box.y - radius), radius, 0.0, PI * 0.5))
	points.append_array(_corner(Vector2(radius, box.y - radius), radius, PI * 0.5, PI))
	return points


func _corner(centre: Vector2, radius: float, from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps: int = 7
	for step: int in steps + 1:
		var angle: float = lerpf(from, to, float(step) / float(steps))
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _on_hover(entered: bool) -> void:
	_hover = entered
	_bay.queue_redraw()
	if not is_inside_tree():
		return
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_hop", -8.0 if entered else 0.0, 0.18)


func _on_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var click: InputEventMouseButton = event
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if imported:
		play_requested.emit()
	else:
		insert_requested.emit()


## The cartridge dropping into its bay, played once an import succeeds.
func play_insert() -> void:
	if not is_inside_tree():
		return
	Gen2LauncherAudio.play(&"insert")
	set_imported(true)
	_art.modulate.a = 0.0
	_hop = -size.y * 0.7
	_squash = Vector2(1.04, 1.04)
	var tween: Tween = create_tween()
	tween.tween_property(_art, "modulate:a", 1.0, 0.09)
	tween.parallel().tween_property(self, "_hop", 0.0, 0.24).set_ease(Tween.EASE_IN).set_trans(
		Tween.TRANS_QUAD
	)
	# The squash lands after the drop, which is what sells the weight.
	tween.tween_property(self, "_squash", Vector2(1.07, 0.93), 0.06)
	tween.tween_property(self, "_squash", Vector2.ONE, 0.34).set_ease(Tween.EASE_OUT).set_trans(
		Tween.TRANS_ELASTIC
	)


## The cartridge being pressed home before the game opens. Awaited by the
## launcher, so the scene change happens after the sound and the movement.
func play_start() -> void:
	if not is_inside_tree():
		return
	Gen2LauncherAudio.play(&"power")
	var tween: Tween = create_tween()
	tween.tween_property(self, "_hop", 14.0, 0.13).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "_squash", Vector2(1.03, 0.94), 0.13)
	tween.tween_property(self, "_hop", 0.0, 0.30).set_ease(Tween.EASE_OUT).set_trans(
		Tween.TRANS_BACK
	)
	tween.parallel().tween_property(self, "_squash", Vector2.ONE, 0.30)
	await tween.finished


func play_eject() -> void:
	if not is_inside_tree():
		set_imported(false)
		return
	Gen2LauncherAudio.play(&"eject")
	var tween: Tween = create_tween()
	tween.tween_property(self, "_hop", -size.y * 0.6, 0.24).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_art, "modulate:a", 0.0, 0.24)
	await tween.finished
	set_imported(false)
	_hop = 0.0
	_art.modulate.a = 1.0
