class_name Gen2LauncherSheet
extends Control

## A modal card over the launcher, used instead of an OS dialog.
##
## Godot's own dialogs open a second window with its own decorations, which no
## amount of theming makes belong here and which mobile has no place to put. A
## sheet is drawn inside the launcher, so it is one look on every platform.

signal closed

var _theme: Gen2LauncherTheme = null
var _body: VBoxContainer = null
var _actions: HBoxContainer = null
var _card: Gen2LauncherCard = null
## What had focus before the sheet opened, so closing puts it back rather than
## stranding a pad with nothing selected.
var _restore_focus: Control = null


static func create(palette: Gen2LauncherTheme, title: String) -> Gen2LauncherSheet:
	var sheet := Gen2LauncherSheet.new()
	sheet._theme = palette
	sheet._build(title)
	return sheet


func _build(title: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.34 if not _theme.is_dark() else 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close()
	)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	_card = Gen2LauncherCard.floating(_theme, Gen2LauncherTheme.RADIUS_LG, 26, 34)
	_card.custom_minimum_size = Vector2(420, 0)
	centre.add_child(_card)

	var column: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_LG)
	_card.add_child(column)

	var head: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	column.add_child(head)
	var heading: Label = Gen2LauncherUI.title(_theme, title)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var dismiss: Gen2LauncherButton = Gen2LauncherButton.icon_only(
		_theme, &"close", Gen2LauncherButton.Variant.QUIET, 36.0
	)
	dismiss.tooltip_text = "Close"
	dismiss.pressed.connect(close)
	head.add_child(dismiss)

	_body = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	column.add_child(_body)

	_actions = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	_actions.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_actions)


func body() -> VBoxContainer:
	return _body


func add_action(button: Control) -> void:
	_actions.add_child(button)


## Opens over [param host]. The card scales rather than moves, because the
## [CenterContainer] holding it owns its position and would undo a slide.
func open(host: Control) -> void:
	var viewport: Viewport = host.get_viewport()
	_restore_focus = viewport.gui_get_focus_owner() if viewport != null else null
	host.add_child(self)
	modulate.a = 0.0
	await get_tree().process_frame
	# The sheet is modal, so focus goes into it whatever the player is using: a
	# pad needs it to navigate and a keyboard needs it for the cancel below.
	var first: Control = Gen2FocusGuard.first_focusable(_card)
	if first != null:
		first.grab_focus()
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.96, 0.96)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.14)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.22).set_ease(
		Tween.EASE_OUT
	).set_trans(Tween.TRANS_BACK)


func close() -> void:
	if _restore_focus != null and is_instance_valid(_restore_focus):
		_restore_focus.grab_focus()
	closed.emit()
	Gen2Screen.drop(self)


## Unhandled rather than [method Control._gui_input], which only ever reaches the
## focused control: the sheet itself never holds focus, so a cancel pressed on a
## button inside it would have gone nowhere.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		close()
