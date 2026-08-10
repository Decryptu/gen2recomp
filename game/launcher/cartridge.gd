class_name Gen2Cartridge
extends Control

## One cartridge on the stage: an empty bay until its dump is imported, and the
## cartridge itself once it is.
##
## The cartridge owns only presentation, and not even its own presses: importing,
## verification and launching belong to the launcher, and reading a press belongs
## to the stage, which is the only node that knows whether one became a drag.

const ART: Dictionary = {
	&"gold": preload("res://assets/cartridges/gold.webp"),
	&"silver": preload("res://assets/cartridges/silver.webp"),
	&"crystal": preload("res://assets/cartridges/crystal.webp"),
}

## What the launcher puts behind itself while a cartridge is selected. Only shown
## once that cartridge is imported: an empty bay has no game to dress the page in.
const BACKDROP: Dictionary = {
	&"gold": preload("res://assets/launcher/bg/gold.webp"),
	&"silver": preload("res://assets/launcher/bg/silver.webp"),
	&"crystal": preload("res://assets/launcher/bg/crystal.webp"),
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
## Whether the stage is being driven by a keyboard or a pad and this is the
## cartridge it is on. A pointer needs no ring; a pad has nothing else to go on.
var _highlighted: bool = false
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
	# The stage owns every press on the row, because a press here is the start of
	# a drag as often as it is a choice, and only the stage knows which it became.
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


func set_highlighted(state: bool) -> void:
	if _highlighted == state:
		return
	_highlighted = state
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


## The ring that says a keyboard or a pad is on this cartridge. Nothing else is
## drawn here: the cartridge casts no shadow, so the row reads as a carousel of
## flat art rather than as objects standing on a shelf.
func _draw() -> void:
	if size.x <= 0.0 or not _highlighted:
		return
	var pad: float = size.x * 0.05
	draw_style_box(
		_theme.box(Color(0, 0, 0, 0), size.x * 0.09, _theme.accent, 3),
		Rect2(Vector2(-pad, -pad), size + Vector2(pad, pad) * 2.0),
	)


## The empty bay is drawn in the cartridge's own silhouette rather than as a
## rounded box, so the shape itself says what is missing.
func _draw_bay() -> void:
	if _bay.size.x <= 0.0:
		return
	var edge: Color = _theme.accent if _hover else _theme.with_alpha(_theme.faint, 0.7)
	var fill: Color = (
		_theme.accent_wash(0.08) if _hover
		else _theme.with_alpha(_theme.panel, 0.30 if _theme.is_dark() else 0.55)
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
