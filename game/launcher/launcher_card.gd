class_name Gen2LauncherCard
extends PanelContainer

## A padded surface: the launcher's cards, wells and bars.
##
## Padding is the stylebox's own content margin, so the panel measures and sorts
## its child the way any [PanelContainer] does and there is no custom layout to
## go wrong.

var palette: Gen2LauncherTheme = null


## A card printed on the page: filled, with a hairline, and no shadow to be cut
## off by whatever scrolls it.
static func create(
	theme: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_MD,
	padding: int = 20,
	padding_y: int = -1,
) -> Gen2LauncherCard:
	return _made(theme, theme.padded(theme.box(theme.surface, radius, theme.line), padding, padding_y))


## A step back from the page: the track a segmented control sits in, or a strip
## of read-only detail.
static func well(
	theme: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_MD,
	padding: int = 16,
	padding_y: int = -1,
) -> Gen2LauncherCard:
	return _made(theme, theme.padded(theme.box(theme.surface_alt, radius), padding, padding_y))


## The current choice in a list of cards: an accent hairline and a wash of it,
## rather than a fill that would fight the text inside.
static func selected(
	theme: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_MD,
	padding: int = 20,
) -> Gen2LauncherCard:
	var style: StyleBoxFlat = theme.box(theme.accent_wash(0.10), radius, theme.accent, 2)
	return _made(theme, theme.padded(style, padding))


## A surface that genuinely floats: sheets, toasts and the bottom dock. Never put
## one inside a container that clips, because the shadow is drawn outside it.
static func floating(
	theme: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_LG,
	padding: int = 20,
	spread: int = 26,
) -> Gen2LauncherCard:
	return _made(theme, theme.padded(theme.floating(theme.surface, radius, spread), padding))


static func _made(theme: Gen2LauncherTheme, style: StyleBoxFlat) -> Gen2LauncherCard:
	var card := Gen2LauncherCard.new()
	card.palette = theme
	card.add_theme_stylebox_override("panel", style)
	return card
