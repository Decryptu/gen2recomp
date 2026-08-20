@tool
extends EditorScript

## Editor > File > Run: writes the Debugger's error list to
## user://editor_errors.txt and prints a tally per warning code.
##
## The GDScript analyzer runs only inside the editor and reports to that panel
## alone: no CLI mode prints its warnings, `--check-only` suppresses them and
## file logging records the running game rather than the editor. Scraping the
## panel is the only way to read them outside it.
##
## The panel holds what this editor session has analysed, so a full sweep is
## Project > Reload Current Project first, then this.

const OUTPUT_PATH: String = "user://editor_errors.txt"


func _run() -> void:
	var lines := PackedStringArray()
	for tree: Node in _trees(EditorInterface.get_base_control()):
		var root: TreeItem = (tree as Tree).get_root()
		if root == null:
			continue
		var entries := PackedStringArray()
		_walk(root.get_first_child(), 0, entries)
		if not _is_error_list(entries):
			continue
		lines.append_array(entries)

	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()

	var codes: Dictionary = {}
	for line: String in lines:
		if not line.contains("<GDScript Error>"):
			continue
		var code: String = line.split("<GDScript Error>")[1].strip_edges()
		codes[code] = int(codes.get(code, 0)) + 1
	var total: int = 0
	for code: String in codes:
		total += int(codes[code])
		print("%5d  %s" % [codes[code], code])
	print("%d entries, %d of them GDScript, in %s"
		% [lines.size(), total, ProjectSettings.globalize_path(OUTPUT_PATH)])


## An error list is the one tree whose rows carry the debugger's own fields.
func _is_error_list(entries: PackedStringArray) -> bool:
	for line: String in entries:
		if line.contains("<GDScript Source>") or line.contains("<C++ Source>"):
			return true
	return false


func _walk(item: TreeItem, depth: int, lines: PackedStringArray) -> void:
	while item != null:
		var columns := PackedStringArray()
		for column: int in item.get_tree().columns:
			var text: String = item.get_text(column)
			if not text.is_empty():
				columns.append(text)
		lines.append("\t".repeat(depth) + " ".join(columns))
		if item.get_first_child() != null:
			_walk(item.get_first_child(), depth + 1, lines)
		item = item.get_next()


func _trees(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	if node.is_class("Tree"):
		out.append(node)
	for child: Node in node.get_children(true):
		out.append_array(_trees(child))
	return out
