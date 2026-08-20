class_name Gen2LauncherBattery
extends HBoxContainer

## The charge indicator in the top right: a cell that fills and empties, with the
## percentage written beside it.
##
## Godot 4 reports no power state on any platform, so the level is held here and
## set from outside. It sits at [constant FULL] until something knows better,
## which on a desktop or a console is the truth often enough to be worth drawing.

const FULL: int = 100
## The cell, without the terminal on its right end.
const BODY: Vector2 = Vector2(26.0, 13.0)
const TERMINAL: Vector2 = Vector2(2.5, 5.0)
## Below this the cell is drawn in the warning colour.
const LOW: int = 20

var level: int = FULL

var _theme: Gen2LauncherTheme = null
var _cell: Control = null
var _readout: Label = null


static func create(palette: Gen2LauncherTheme) -> Gen2LauncherBattery:
	var battery := Gen2LauncherBattery.new()
	battery._theme = palette
	battery._build()
	return battery


func _build() -> void:
	add_theme_constant_override("separation", Gen2LauncherUI.GAP_SM)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout = Gen2LauncherUI.title(_theme, "%d%%" % level, Gen2LauncherTheme.FONT_BODY)
	_readout.add_theme_color_override("font_color", _theme.surface)
	_readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_readout)
	_cell = Control.new()
	_cell.custom_minimum_size = Vector2(BODY.x + TERMINAL.x + 1.0, BODY.y)
	_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell.draw.connect(_draw_cell)
	add_child(_cell)


## Sets the charge, clamped to a percentage. The seam a real power reading will
## arrive through.
func set_level(percent: int) -> void:
	var wanted: int = clampi(percent, 0, FULL)
	if wanted == level:
		return
	level = wanted
	_readout.text = "%d%%" % level
	_cell.queue_redraw()


func _draw_cell() -> void:
	var ink: Color = _theme.warning if level <= LOW else _theme.surface
	var shell := Rect2(Vector2(0.0, (_cell.size.y - BODY.y) * 0.5), BODY)
	_cell.draw_style_box(
		_theme.box(Color(0, 0, 0, 0), 4.0, _theme.with_alpha(ink, 0.55), 2), shell
	)
	_cell.draw_style_box(
		_theme.box(_theme.with_alpha(ink, 0.55), 2.0),
		Rect2(
			Vector2(shell.end.x + 1.0, shell.get_center().y - TERMINAL.y * 0.5),
			TERMINAL,
		),
	)
	# Inset by the outline plus a hair, so a full cell still reads as a cell with
	# something in it rather than as a solid block.
	var inner: Rect2 = shell.grow(-3.5)
	if inner.size.x <= 0.0 or level <= 0:
		return
	inner.size.x *= float(level) / float(FULL)
	_cell.draw_style_box(_theme.box(ink, 2.0), inner)
