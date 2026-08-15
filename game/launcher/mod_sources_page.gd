class_name Gen2ModSourcesPage
extends VBoxContainer

## The sources the player follows, and what to add.
##
## A source is a published index: a JSON listing naming mods that live wherever
## their authors put them. Following one is trusting whoever publishes it, so
## none ships with the game and none is ever added on its own.
##
## The page decides nothing. Following, forgetting and what a URL resolves to
## are [Gen2ModIndex]'s, and fetching is the mods page's, which owns the one
## request this launcher makes.

signal closed
signal followed(feed: String)
signal unfollowed(feed: String)
signal refresh_requested(feed: String)

var _theme: Gen2LauncherTheme = null
var _entry: LineEdit = null
var _list: VBoxContainer = null
var _status: Label = null


static func create(palette: Gen2LauncherTheme) -> Gen2ModSourcesPage:
	var page := Gen2ModSourcesPage.new()
	page._theme = palette
	page._build()
	page.refresh()
	return page


func _build() -> void:
	add_theme_constant_override("separation", Gen2LauncherUI.GAP_LG)

	var head: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	add_child(head)
	var back: Gen2LauncherButton = Gen2LauncherButton.icon_only(
		_theme, &"back", Gen2LauncherButton.Variant.QUIET, 42.0
	)
	back.tooltip_text = "Back to the mod list"
	back.pressed.connect(func() -> void: closed.emit())
	head.add_child(back)
	var text: VBoxContainer = Gen2LauncherUI.column(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	text.add_child(Gen2LauncherUI.title(_theme, "Sources", Gen2LauncherTheme.FONT_TITLE))
	text.add_child(Gen2LauncherUI.muted(
		_theme,
		"A source lists mods hosted by their authors. Following one is trusting"
			+ " whoever publishes it.",
	))

	var add_row: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	add_child(add_row)
	_entry = LineEdit.new()
	_entry.placeholder_text = "owner/repo or https://..."
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.text_submitted.connect(func(_text: String) -> void: _follow())
	add_row.add_child(_entry)
	var follow: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Follow", Gen2LauncherButton.Variant.PRIMARY, &"plus"
	)
	follow.pressed.connect(_follow)
	add_row.add_child(follow)

	var scroll: Gen2LauncherScroll = Gen2LauncherScroll.create()
	add_child(scroll)
	_list = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_status = Gen2LauncherUI.muted(_theme, "")
	add_child(_status)


func refresh() -> void:
	Gen2LauncherUI.clear(_list)
	var sources: Array[Dictionary] = Gen2ModIndex.followed()
	if sources.is_empty():
		var empty: Gen2LauncherCard = Gen2LauncherCard.well(
			_theme, Gen2LauncherTheme.RADIUS_MD, 28
		)
		var line: Label = Gen2LauncherUI.muted(_theme, "No source followed yet.")
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(line)
		_list.add_child(empty)
		return
	for source: Dictionary in sources:
		_list.add_child(_card(source))


func _card(source: Dictionary) -> Control:
	var feed: String = String(source["feed"])
	var panel: Gen2LauncherCard = Gen2LauncherCard.create(_theme, Gen2LauncherTheme.RADIUS_MD, 18)
	var line: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	panel.add_child(line)
	var text: VBoxContainer = Gen2LauncherUI.column(1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	text.add_child(Gen2LauncherUI.body(_theme, String(source["label"])))
	text.add_child(Gen2LauncherUI.muted(_theme, _listing_line(feed)))

	var update: Gen2LauncherButton = Gen2LauncherButton.icon_only(
		_theme, &"refresh", Gen2LauncherButton.Variant.NEUTRAL, 40.0
	)
	update.tooltip_text = "Read this source again"
	update.pressed.connect(func() -> void: refresh_requested.emit(feed))
	line.add_child(update)

	var forget: Gen2LauncherButton = Gen2LauncherButton.icon_only(
		_theme, &"trash", Gen2LauncherButton.Variant.DANGER, 40.0
	)
	forget.tooltip_text = "Stop following this source"
	forget.pressed.connect(func() -> void: _unfollow(feed))
	line.add_child(forget)
	return panel


## How many mods the last good copy of a feed listed, and how old that copy is.
## A source never read says so rather than showing an empty count.
static func _listing_line(feed: String) -> String:
	var cached: Dictionary = Gen2ModIndex.cached_feed(feed)
	if not bool(cached.get("ok", false)):
		return "Not read yet"
	var entries: Array = cached["entries"]
	return "%d mod%s  read %s ago" % [
		entries.size(), "" if entries.size() == 1 else "s",
		Gen2ModIndex.age_text(int(cached.get("age", 0))),
	]


func _follow() -> void:
	var result: Dictionary = Gen2ModIndex.follow(_entry.text)
	if not bool(result.get("ok", false)):
		set_status(Gen2ModRefusal.text(result), _theme.error)
		return
	_entry.text = ""
	refresh()
	set_status("Following %s." % result["label"], _theme.muted)
	followed.emit(String(result["feed"]))


## Forgetting a source drops its cached listing with it, so the mods it named
## leave the list unless they are installed, in which case they are a mod from a
## file like any other.
func _unfollow(feed: String) -> void:
	Gen2ModIndex.unfollow(feed)
	refresh()
	set_status("Stopped following that source.", _theme.muted)
	unfollowed.emit(feed)


func set_status(message: String, colour: Color) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", colour)
