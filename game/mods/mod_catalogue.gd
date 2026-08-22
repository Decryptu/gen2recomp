class_name Gen2ModCatalogue
extends RefCounted

## One list of every mod the player can see, grouped by where it came from.
##
## A source is a followed index; a mod that no index lists came from a file the
## player chose. That is the whole ownership rule, and it needs nothing written
## down: a mod belongs to the source that lists its id, so uninstalling one from
## a source leaves it listed and re-downloadable, while uninstalling one that
## came from a file removes the only copy there was.
##
## Pure. It takes what [Gen2ModHost], [Gen2ModIndex] and [Gen2ModState] already
## answer and decides nothing about the network or the screen.

## The group a mod nothing lists belongs to.
const SOURCE_FILE: String = ""
const SOURCE_FILE_LABEL: String = "Installed from a file"


## The groups to draw, in the order to draw them: each followed source that has
## anything in it, in the order the player added them, then the file group.
##
## [param sources] is [method Gen2ModIndex.followed]'s rows, [param listings] is
## feed to that feed's entries, and [param manifests] is
## [method Gen2ModHost.manifests]. A group is
## `{feed, label, rows}`; see [method _row] for a row.
static func groups(manifests: Array, sources: Array, listings: Dictionary) -> Array:
	var installed: Dictionary = {}
	for manifest: Gen2ModManifest in manifests:
		installed[manifest.id] = manifest

	var out: Array = []
	var claimed: Dictionary = {}
	for source: Dictionary in sources:
		var feed: String = String(source.get("feed", ""))
		var label: String = String(source.get("label", feed))
		var rows: Array = []
		for entry: Variant in listings.get(feed, []) as Array:
			if entry is not Dictionary:
				continue
			var id := StringName((entry as Dictionary).get("id", &""))
			if String(id).is_empty() or claimed.has(id):
				continue
			claimed[id] = true
			rows.append(_row(id, entry as Dictionary, installed.get(id, null), feed, label))
		if not rows.is_empty():
			out.append({"feed": feed, "label": label, "rows": _sorted(rows)})

	var loose: Array = []
	for id: StringName in installed:
		if not claimed.has(id):
			loose.append(_row(id, {}, installed[id], SOURCE_FILE, SOURCE_FILE_LABEL))
	if not loose.is_empty():
		out.append({"feed": SOURCE_FILE, "label": SOURCE_FILE_LABEL, "rows": _sorted(loose)})
	return out


## One row of the list. [param entry] is the source's listing for it, empty for a
## mod no source lists; [param manifest] is the installed copy, null for one that
## is only listed.
##
## `version` is what the row shows: the installed version when there is one,
## because that is the copy the player has, and the listed version otherwise.
static func _row(
	id: StringName, entry: Dictionary, manifest: Gen2ModManifest, feed: String, label: String
) -> Dictionary:
	var listed_version: String = String(entry.get("version", ""))
	var installed_version: String = manifest.version if manifest != null else ""
	return {
		"id": id,
		"name": manifest.name if manifest != null else String(entry.get("name", id)),
		"version": installed_version if manifest != null else listed_version,
		"installed_version": installed_version,
		"listed_version": listed_version,
		"description": String(entry.get("description", "")),
		"download": String(entry.get("download", "")),
		# The installed copy's own file when there is one, and the listing's URL
		# otherwise, so a mod has a face while it is still only being browsed.
		"icon": Gen2ModArt.icon_path(manifest),
		"icon_url": String(entry.get("icon", "")),
		# What the listing says it is for. The installed manifest is the truth
		# when there is one; this is what the card has before then.
		"listed_games": entry.get("games", [] as Array[StringName]),
		"feed": feed,
		"source_label": label,
		"installed": manifest != null,
		"listed": not entry.is_empty(),
		"enabled": manifest != null and Gen2ModState.is_enabled(id),
		"update": Gen2ModIndex.update_state(listed_version, installed_version),
		"manifest": manifest,
	}


## What the row's own action does, which is the one place the Cydia rule lives:
## a listed mod is downloaded, updated or reinstalled, and an installed one is
## removed. Removing a listed mod leaves it listed.
static func action_for(row: Dictionary) -> StringName:
	if not bool(row.get("installed", false)):
		return &"download"
	if StringName(row.get("update", Gen2ModIndex.UNKNOWN)) == Gen2ModIndex.UPDATE_AVAILABLE:
		return &"update"
	return &"remove"


## What removing this row costs, which is what a confirmation has to say: a
## listed mod can be downloaded again, and a mod from a file cannot.
static func removal_is_permanent(row: Dictionary) -> bool:
	return not bool(row.get("listed", false))


static func _sorted(rows: Array) -> Array:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
	)
	return rows
