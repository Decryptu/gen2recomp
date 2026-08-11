class_name Gen2ModVersion
extends RefCounted

## Small SemVer range evaluator for manifest dependencies. Versions are strict
## numeric major.minor.patch values; ranges accept exact versions, wildcards,
## comparison chains, caret and tilde shorthand.

static func valid_version(version: String) -> bool:
	var parts: PackedStringArray = version.strip_edges().split(".", false)
	if parts.size() != 3:
		return false
	for part: String in parts:
		if not part.is_valid_int() or int(part) < 0 or str(int(part)) != part:
			return false
	return true


static func valid_range(range_text: String) -> bool:
	var text: String = range_text.strip_edges()
	if text in ["", "*"]:
		return true
	for token: String in _tokens(text):
		if not _valid_token(token):
			return false
	return true


static func matches(version: String, range_text: String) -> bool:
	if not valid_version(version) or not valid_range(range_text):
		return false
	var text: String = range_text.strip_edges()
	if text in ["", "*"]:
		return true
	for token: String in _tokens(text):
		if not _matches_token(version, token):
			return false
	return true


static func _tokens(text: String) -> PackedStringArray:
	return text.replace(",", " ").split(" ", false)


static func _valid_token(token: String) -> bool:
	var value: String = token
	var operator: String = ""
	for prefix: String in [">=", "<=", ">", "<", "=", "^", "~"]:
		if value.begins_with(prefix):
			operator = prefix
			value = value.substr(prefix.length())
			break
	if value.contains("x") or value.contains("X") or value.contains("*"):
		if not operator.is_empty():
			return false
		var parts: PackedStringArray = value.split(".", false)
		if parts.is_empty() or parts.size() > 3:
			return false
		var wildcard_seen: bool = false
		for part: String in parts:
			if part in ["x", "X", "*"]:
				wildcard_seen = true
			elif wildcard_seen or not part.is_valid_int() or int(part) < 0 \
				or str(int(part)) != part:
				return false
		return wildcard_seen
	return valid_version(value)


static func _matches_token(version: String, token: String) -> bool:
	if token.begins_with("^"):
		var floor: String = token.substr(1)
		var values: Array[int] = _parts(floor)
		var ceiling: Array[int] = values.duplicate()
		if values[0] > 0:
			ceiling = [values[0] + 1, 0, 0]
		elif values[1] > 0:
			ceiling = [0, values[1] + 1, 0]
		else:
			ceiling = [0, 0, values[2] + 1]
		return _compare(version, floor) >= 0 and _compare(version, _join(ceiling)) < 0
	if token.begins_with("~"):
		var floor: String = token.substr(1)
		var values: Array[int] = _parts(floor)
		return _compare(version, floor) >= 0 \
			and _compare(version, "%d.%d.0" % [values[0], values[1] + 1]) < 0
	if token.contains("x") or token.contains("X") or token.contains("*"):
		var wanted: PackedStringArray = token.split(".", false)
		var actual: Array[int] = _parts(version)
		for index: int in wanted.size():
			if wanted[index] in ["x", "X", "*"]:
				return true
			if int(wanted[index]) != actual[index]:
				return false
		return true
	var operator: String = "="
	var wanted: String = token
	for prefix: String in [">=", "<=", ">", "<", "="]:
		if token.begins_with(prefix):
			operator = prefix
			wanted = token.substr(prefix.length())
			break
	var compared: int = _compare(version, wanted)
	match operator:
		">=": return compared >= 0
		"<=": return compared <= 0
		">": return compared > 0
		"<": return compared < 0
		_: return compared == 0


static func _compare(left: String, right: String) -> int:
	var a: Array[int] = _parts(left)
	var b: Array[int] = _parts(right)
	for index: int in 3:
		if a[index] != b[index]:
			return -1 if a[index] < b[index] else 1
	return 0


static func _parts(version: String) -> Array[int]:
	var split: PackedStringArray = version.split(".", false)
	return [int(split[0]), int(split[1]), int(split[2])]


static func _join(parts: Array[int]) -> String:
	return "%d.%d.%d" % [parts[0], parts[1], parts[2]]
