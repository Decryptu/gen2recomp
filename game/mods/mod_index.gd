class_name Gen2ModIndex
extends RefCounted

## A published list of mods a player chose to follow.
##
## An index is metadata only: a JSON feed naming mods that live wherever their
## authors put them. Nothing here installs anything. A chosen entry hands its
## download to [Gen2ModInstaller] like any other archive, with the listed id
## required to match, so appearing in a feed buys a mod no trust that picking
## the same file by hand would not.
##
## No index ships with the game and none is ever added on its own. Following one
## is the player trusting whoever publishes it, so it is always their act.
##
## Everything above "fetching" is pure: no HTTP, no filesystem. The feed format
## is a contract with people we will never meet, so its rules are worth testing
## without a network.

## Feeds declare this. A later format may reuse a field name for something else,
## so an unknown version is refused rather than parsed hopefully.
const SCHEMA_VERSION: int = 1
## A feed is a listing, not a payload. Anything larger is not one.
const MAX_FEED_BYTES: int = 4 * 1024 * 1024
## Entries beyond this are ignored rather than refused, so one over-long feed
## does not make the whole index unusable.
const MAX_ENTRIES: int = 500
## The indexes this player follows. Small enough to keep beside the mods rather
## than wait for a general settings model.
const FOLLOWED_PATH: String = "user://mod_indexes.json"
## Where a fetched feed is kept, one file per feed. A cached listing is what a
## player sees while the request is in flight and what they still see when the
## server is down or the device is offline, so browsing what they follow does not
## depend on the network being up at that moment.
const CACHE_DIRECTORY: String = "user://mod_index_cache"

## What [method update_state] answers.
const UPDATE_AVAILABLE: StringName = &"update_available"
const UP_TO_DATE: StringName = &"up_to_date"
## The installed copy is newer than the listing, which a feed lagging behind its
## own releases produces. Not an update, and not an error either.
const INSTALLED_IS_NEWER: StringName = &"installed_is_newer"
## Either side is missing a version or carries one nothing can order.
const UNKNOWN: StringName = &"unknown"
## Not installed at all, so there is nothing to compare.
const NOT_INSTALLED: StringName = &"not_installed"


## Turns whatever the player pasted into the feed URL to read.
##
## People copy whichever URL they happen to be looking at, so a repository page,
## a Pages site, a bare `owner/repo` and the feed file itself all resolve to the
## same place. Returns { ok, feed, label } or { ok: false, reason }.
static func resolve_source(input: String) -> Dictionary:
	var url: String = input.strip_edges()
	if url.is_empty():
		return {"ok": false, "reason": &"empty_index_url"}

	var slug: Dictionary = _github_slug(url)
	if bool(slug.get("ok", false)):
		var owner: String = slug["owner"]
		var repository: String = slug["repository"]
		return {
			"ok": true,
			"feed": "https://%s.github.io/%s/index.json" % [owner, repository],
			"label": "%s/%s" % [owner, repository],
		}

	if not url.begins_with("https://"):
		# Plain http would let anyone on the path rewrite the download URLs the
		# feed hands out, which is the one thing a listing must get right.
		return {"ok": false, "reason": &"index_url_not_https"}
	if url.ends_with(".json"):
		return {"ok": true, "feed": url, "label": _label_for(url)}
	var base: String = url if url.ends_with("/") else "%s/" % url
	return {"ok": true, "feed": "%sindex.json" % base, "label": _label_for(base)}


## Reads a fetched feed into rows the launcher can list.
##
## Returns { ok, name, entries } where each entry has id, name, version,
## description, download, and the optional icon and thumbnail URLs. An entry
## missing an id or a usable download is dropped rather than failing the whole
## feed, because one bad row in someone else's file should not cost the player
## the rest of the list.
static func parse_feed(text: String) -> Dictionary:
	if text.length() > MAX_FEED_BYTES:
		return {"ok": false, "reason": &"index_too_large"}
	# The instance API reports malformed input as a return code. A feed comes
	# from a stranger's server, so bad JSON is an expected answer, not an
	# engine-level error worth printing.
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"ok": false, "reason": &"index_not_json"}
	var feed: Dictionary = json.data as Dictionary
	if int(feed.get("schema_version", 0)) != SCHEMA_VERSION:
		return {
			"ok": false,
			"reason": &"unsupported_index_schema",
			"detail": str(feed.get("schema_version", "missing")),
		}
	var raw_entries: Variant = feed.get("mods", [])
	if not raw_entries is Array:
		return {"ok": false, "reason": &"index_has_no_mods"}

	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw: Variant in raw_entries as Array:
		if entries.size() >= MAX_ENTRIES:
			break
		if not raw is Dictionary:
			continue
		var row: Dictionary = _entry_from(raw as Dictionary)
		if row.is_empty() or seen.has(row["id"]):
			continue
		seen[row["id"]] = true
		entries.append(row)
	return {
		"ok": true,
		"name": String(feed.get("name", "")),
		"entries": entries,
	}


## True when [param url] is a download this project will fetch. Only https, so a
## feed cannot downgrade a download to a channel anyone can rewrite.
static func is_downloadable(url: String) -> bool:
	return url.begins_with("https://") and url.length() > len("https://")


## What a listed entry is to the copy already installed: [constant NOT_INSTALLED],
## [constant UNKNOWN] when either side has no orderable version, or one of the
## three orderings. [Gen2UpdateCheck.compare_versions] is the same comparison the
## launcher makes against the project's own releases, so a feed and a release are
## ordered by one rule.
static func update_state(listed: String, installed: String) -> StringName:
	if installed.strip_edges().is_empty():
		return NOT_INSTALLED
	if not Gen2ModVersion.valid_version(listed) \
		or not Gen2ModVersion.valid_version(installed):
		return UNKNOWN
	var order: int = Gen2UpdateCheck.compare_versions(installed, listed)
	if order < 0:
		return UPDATE_AVAILABLE
	return UP_TO_DATE if order == 0 else INSTALLED_IS_NEWER


## How many of [param entries] a newer version is listed for. [param installed]
## is mod id to installed version, which [method Gen2ModHost.manifests] fills.
static func update_count(entries: Array, installed: Dictionary) -> int:
	var out: int = 0
	for entry: Variant in entries:
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry as Dictionary
		var have: String = String(installed.get(StringName(row.get("id", &"")), ""))
		if update_state(String(row.get("version", "")), have) == UPDATE_AVAILABLE:
			out += 1
	return out


## The file a feed's last good copy is kept in. Named by hash rather than by URL,
## because a URL is not a filename and a feed may live at any path a publisher
## likes.
static func cache_path(feed: String, directory: String = CACHE_DIRECTORY) -> String:
	return "%s/%s.json" % [directory, feed.sha256_text().substr(0, 32)]


## Keeps [param text] as the last good copy of [param feed]. Only a feed that
## parsed is worth keeping, so the caller stores after [method parse_feed] rather
## than on arrival.
static func cache_feed(feed: String, text: String, directory: String = CACHE_DIRECTORY) -> bool:
	if text.length() > MAX_FEED_BYTES:
		return false
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(cache_path(feed, directory), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"feed": feed, "fetched_at": int(Time.get_unix_time_from_system()), "text": text,
	}))
	file.close()
	return true


## The cached copy of [param feed], parsed, as
## { ok, name, entries, fetched_at, age }, or { ok: false, reason }. A cache file
## that no longer parses is refused like any other feed, so a corrupted one costs
## the listing and nothing else.
static func cached_feed(feed: String, directory: String = CACHE_DIRECTORY) -> Dictionary:
	var path: String = cache_path(feed, directory)
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": &"index_not_cached"}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or json.data is not Dictionary:
		return {"ok": false, "reason": &"index_not_cached"}
	var stored: Dictionary = json.data as Dictionary
	var parsed: Dictionary = parse_feed(String(stored.get("text", "")))
	if not bool(parsed.get("ok", false)):
		return parsed
	var fetched_at: int = int(stored.get("fetched_at", 0))
	parsed["fetched_at"] = fetched_at
	parsed["age"] = maxi(int(Time.get_unix_time_from_system()) - fetched_at, 0)
	return parsed


## What a fetch of [param feed] amounts to, whether or not it arrived.
##
## A feed that parsed is kept and answered; anything else falls back to the copy
## already on disk, so a server that is down costs the freshness of a listing
## rather than the listing. `stale` is true for the fallback, with `age` in
## seconds and `problem` the reason the fetch was not used. Separate from any
## request so both answers a server can give are testable without one.
static func receive_feed(
	feed: String, ok: bool, text: String = "", problem: String = ""
) -> Dictionary:
	if ok:
		var parsed: Dictionary = parse_feed(text)
		if bool(parsed.get("ok", false)):
			cache_feed(feed, text)
			parsed["stale"] = false
			return parsed
		problem = Gen2ModRefusal.text(parsed)
	var cached: Dictionary = cached_feed(feed)
	if not bool(cached.get("ok", false)):
		return {"ok": false, "reason": &"index_request_failed", "detail": problem}
	cached["stale"] = true
	cached["problem"] = problem
	return cached


## How old a cached listing is, rounded to the largest unit that still says
## something useful: a listing hours old and one days old are different answers,
## and minutes below an hour are not.
static func age_text(seconds: int) -> String:
	if seconds < 3600:
		return "%d minute%s" % [maxi(seconds / 60, 1), "" if seconds < 120 else "s"]
	if seconds < 86400:
		@warning_ignore("integer_division")
		var hours: int = seconds / 3600
		return "%d hour%s" % [hours, "" if hours == 1 else "s"]
	@warning_ignore("integer_division")
	var days: int = seconds / 86400
	return "%d day%s" % [days, "" if days == 1 else "s"]


## Drops a feed's cached copy, which [method unfollow] does so an index the
## player stopped following leaves nothing on disk.
static func forget_cache(feed: String, directory: String = CACHE_DIRECTORY) -> void:
	DirAccess.remove_absolute(cache_path(feed, directory))


static func _entry_from(raw: Dictionary) -> Dictionary:
	var id: String = String(raw.get("id", "")).strip_edges()
	var download: String = String(raw.get("download", "")).strip_edges()
	if id.is_empty() or not is_downloadable(download):
		return {}
	var regex := RegEx.new()
	regex.compile(Gen2ModManifest.ID_PATTERN)
	if regex.search(id) == null:
		return {}
	return {
		"id": StringName(id),
		"name": String(raw.get("name", id)),
		"version": String(raw.get("version", "")),
		"description": String(raw.get("description", "")),
		"download": download,
		# Optional art. Held to the same https rule as the download, and dropped
		# rather than refused: a listing without a picture is still a listing.
		"icon": _art_url(raw.get("icon", "")),
		"thumbnail": _art_url(raw.get("thumbnail", "")),
	}


static func _art_url(raw: Variant) -> String:
	var url: String = String(raw).strip_edges()
	return url if is_downloadable(url) else ""


static func _github_slug(url: String) -> Dictionary:
	var path: String = url
	for prefix: String in ["https://github.com/", "http://github.com/"]:
		if path.begins_with(prefix):
			path = path.substr(prefix.length())
			break
	if path.contains("://"):
		return {"ok": false}
	var parts: PackedStringArray = path.split("/", false)
	if parts.size() != 2:
		return {"ok": false}
	var repository: String = parts[1]
	if repository.ends_with(".git"):
		repository = repository.substr(0, repository.length() - 4)
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9._-]+$")
	if regex.search(parts[0]) == null or regex.search(repository) == null:
		return {"ok": false}
	return {"ok": true, "owner": parts[0], "repository": repository}


static func _label_for(url: String) -> String:
	var label: String = url
	for prefix: String in ["https://", "http://"]:
		if label.begins_with(prefix):
			label = label.substr(prefix.length())
	return label.trim_suffix("/")


## The indexes the player follows, oldest first. Empty until they add one: the
## game ships following nobody, because following an index is trusting whoever
## publishes it and that is not a choice to make on their behalf.
static func followed(path: String = FOLLOWED_PATH) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return rows
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Array:
		return rows
	for raw: Variant in json.data as Array:
		if not raw is Dictionary:
			continue
		var feed: String = String((raw as Dictionary).get("feed", ""))
		if feed.begins_with("https://"):
			rows.append({"feed": feed, "label": String((raw as Dictionary).get("label", feed))})
	return rows


## Adds [param input] to the followed list, resolving whatever shape it is in.
## Following the same feed twice is not an error and does not duplicate it.
static func follow(input: String, path: String = FOLLOWED_PATH) -> Dictionary:
	var resolved: Dictionary = resolve_source(input)
	if not bool(resolved.get("ok", false)):
		return resolved
	var rows: Array[Dictionary] = followed(path)
	for row: Dictionary in rows:
		if row["feed"] == resolved["feed"]:
			return {"ok": true, "feed": resolved["feed"], "label": row["label"], "added": false}
	rows.append({"feed": resolved["feed"], "label": resolved["label"]})
	_store(rows, path)
	return {"ok": true, "feed": resolved["feed"], "label": resolved["label"], "added": true}


static func unfollow(feed: String, path: String = FOLLOWED_PATH) -> void:
	var kept: Array[Dictionary] = []
	for row: Dictionary in followed(path):
		if row["feed"] != feed:
			kept.append(row)
	_store(kept, path)
	forget_cache(feed)


static func _store(rows: Array[Dictionary], path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(rows))
	file.close()
