class_name Gen2TextLayout
extends RefCounted

## Breaking a string into the lines and pages a text box can show.
##
## Pure rules, no font and no screen: it counts tiles and returns strings, so a
## conversation's pagination can be checked without drawing anything.
##
## Widths count tiles, never characters: a ligature like "'s" is two characters
## in one glyph, so [method String.length] overstates a line and wraps it a
## column early. [method Gen2Text.encoded_length] is the measure that matches the
## screen.
##
## The cartridges do not wrap at runtime; their text is pre-broken at authoring
## time with control codes, which works when every string is known in advance and
## does not when a mod adds one or a name runs long.


## Breaks [param text] into lines of at most [param columns] tiles.
##
## Explicit newlines are kept: a caller that has already decided where a line
## ends is obeyed, and only the runs between them are wrapped.
static func wrap_lines(text: String, columns: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if columns <= 0:
		return out

	for paragraph: String in text.split("\n"):
		var line: String = ""
		for word: String in paragraph.split(" ", false):
			var candidate: String = word if line.is_empty() else "%s %s" % [line, word]
			if Gen2Text.encoded_length(candidate) <= columns:
				line = candidate
				continue

			if not line.is_empty():
				out.append(line)
				line = ""

			# A word too long for a line of its own is cut rather than allowed to
			# run off the edge. Nothing in these games is that long, but a mod's
			# text is not the cartridge's.
			while Gen2Text.encoded_length(word) > columns:
				var head: String = _take(word, columns)
				out.append(head)
				word = word.substr(head.length())
			line = word

		out.append(line)

	return out


## Groups lines into pages of at most [param rows], each page being what the box
## shows before it waits to be advanced.
static func paginate(lines: PackedStringArray, rows: int) -> Array:
	var out: Array = []
	if rows <= 0:
		return out

	var page: PackedStringArray = PackedStringArray()
	for line: String in lines:
		page.append(line)
		if page.size() == rows:
			out.append(page)
			page = PackedStringArray()

	if not page.is_empty():
		out.append(page)
	return out


## Both steps at once, honouring the two waits [Gen2TextStream] marks.
##
## `Paragraph` clears the box and starts again at the top line, so its page
## begins empty. `_ContText` scrolls by one line and writes at the bottom, so
## its page begins with the line that was underneath: with a two-line box that
## is the previous page's second line, and dropping it loses a line out of every
## paragraph that runs past two.
static func lay_out(text: String, columns: int, rows: int) -> Array:
	var out: Array = []
	if rows <= 0 or columns <= 0:
		return out
	var page: PackedStringArray = PackedStringArray()
	var at: int = 0
	while at <= text.length():
		var page_at: int = text.find(Gen2TextStream.PAGE_BREAK, at)
		var scroll_at: int = text.find(Gen2TextStream.SCROLL_BREAK, at)
		var stop: int = page_at
		if stop < 0 or (scroll_at >= 0 and scroll_at < stop):
			stop = scroll_at
		var segment: String = text.substr(at, -1) if stop < 0 else text.substr(at, stop - at)
		for line: String in wrap_lines(segment, columns):
			page.append(line)
			if page.size() == rows:
				out.append(page)
				page = PackedStringArray()
		if stop < 0:
			break
		var scrolled: bool = stop == scroll_at
		if not page.is_empty():
			out.append(page)
		page = PackedStringArray()
		if scrolled and not out.is_empty():
			var previous: PackedStringArray = out[out.size() - 1]
			if not previous.is_empty():
				page.append(previous[previous.size() - 1])
		at = stop + 1
	if not page.is_empty():
		out.append(page)
	return out


## The longest prefix of [param word] that fits in [param columns] tiles.
static func _take(word: String, columns: int) -> String:
	var length: int = 0
	while length < word.length():
		if Gen2Text.encoded_length(word.substr(0, length + 1)) > columns:
			break
		length += 1
	return word.substr(0, maxi(length, 1))
