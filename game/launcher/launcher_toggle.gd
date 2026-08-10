class_name Gen2LauncherToggle
extends BaseButton

## An on/off switch: a pill track with a knob that slides across it.
##
## Drawn rather than built from child controls, so the knob can be animated by a
## single number and the whole thing stays one node.

const TRACK: Vector2 = Vector2(50.0, 28.0)
const KNOB: float = 22.0

var _theme: Gen2LauncherTheme = null
## 0 at the off end of the track, 1 at the on end. Tweened, so it is a float
## rather than a copy of [member BaseButton.button_pressed].
var _slide: float = 0.0:
	set(value):
		_slide = value
		queue_redraw()


static func create(theme: Gen2LauncherTheme, on: bool) -> Gen2LauncherToggle:
	var toggle := Gen2LauncherToggle.new()
	toggle._theme = theme
	toggle.toggle_mode = true
	toggle.custom_minimum_size = TRACK
	toggle.set_pressed_no_signal(on)
	toggle._slide = 1.0 if on else 0.0
	toggle.toggled.connect(toggle._on_toggled)
	return toggle


func _draw() -> void:
	if _theme == null:
		return
	var track := Rect2(Vector2.ZERO, TRACK)
	var off: Color = _theme.surface_alt
	var on: Color = _theme.accent
	draw_style_box(_theme.box(off.lerp(on, _slide), TRACK.y * 0.5, _theme.line), track)
	var inset: float = (TRACK.y - KNOB) * 0.5
	var travel: float = TRACK.x - KNOB - inset * 2.0
	var centre := Vector2(inset + KNOB * 0.5 + travel * _slide, TRACK.y * 0.5)
	# The knob stays light in both appearances: it rides an accent track when the
	# switch is on, and the track is the same colour either way round the page.
	draw_circle(centre, KNOB * 0.5, _theme.on_accent)
	draw_circle(centre, KNOB * 0.5, _theme.with_alpha(_theme.line, 0.9), false, 1.0, true)
	if has_focus():
		draw_style_box(
			_theme.box(Color(0, 0, 0, 0), TRACK.y * 0.5 + 3.0, _theme.accent, 2),
			Rect2(Vector2(-3, -3), TRACK + Vector2(6, 6)),
		)


func _on_toggled(on: bool) -> void:
	Gen2LauncherAudio.play(&"click")
	if not is_inside_tree():
		_slide = 1.0 if on else 0.0
		return
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_slide", 1.0 if on else 0.0, 0.16)
