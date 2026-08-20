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
	skin: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_MD,
	padding: int = 20,
	padding_y: int = -1,
) -> Gen2LauncherCard:
	return _made(skin, skin.padded(skin.box(skin.panel, radius, skin.line), padding, padding_y))


## A step back from the page: the track a segmented control sits in, or a strip
## of read-only detail.
static func well(
	skin: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_MD,
	padding: int = 16,
	padding_y: int = -1,
) -> Gen2LauncherCard:
	return _made(skin, skin.padded(skin.box(skin.surface_alt, radius), padding, padding_y))


## The current choice in a list of cards: an accent hairline and a wash of it,
## rather than a fill that would fight the text inside.
static func selected(
	skin: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_MD,
	padding: int = 20,
) -> Gen2LauncherCard:
	var style: StyleBoxFlat = skin.box(skin.accent_wash(0.10), radius, skin.accent, 2)
	return _made(skin, skin.padded(style, padding))


## A surface that genuinely floats: sheets, toasts and the bottom dock. Never put
## one inside a container that clips, because the shadow is drawn outside it.
## A solid object laid on the page: filled in [member Gen2LauncherTheme.surface],
## which is the opposite side of the page from everything under it. Whatever goes
## inside is written in [member Gen2LauncherTheme.on_surface].
static func chip(
	skin: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_MD,
	padding: int = 16,
	spread: int = 20,
) -> Gen2LauncherCard:
	return _made(skin, skin.padded(skin.floating(skin.surface, radius, spread), padding))


static func floating(
	skin: Gen2LauncherTheme,
	radius: float = Gen2LauncherTheme.RADIUS_LG,
	padding: int = 20,
	spread: int = 26,
) -> Gen2LauncherCard:
	return _made(skin, skin.padded(skin.floating(skin.panel, radius, spread), padding))


static func _made(skin: Gen2LauncherTheme, style: StyleBoxFlat) -> Gen2LauncherCard:
	var card := Gen2LauncherCard.new()
	card.palette = skin
	card.add_theme_stylebox_override("panel", style)
	return card
