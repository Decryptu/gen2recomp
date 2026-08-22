class_name Gen2UpdateCheck
extends RefCounted

## Compares this build against the project's published releases.
##
## Everything here is pure: no HTTP and no filesystem, so the version rules and
## the shape of a release feed are testable without a network. The launcher owns
## the request itself, the way [Gen2ModIndex] leaves fetching to its dialog.
##
## The check never runs on its own. It reaches a third party and reports that
## this build exists, so it happens when the player asks and not before.

const RELEASES_API: String = "https://api.github.com/repos/Decryptu/pokerecomp/releases/latest"
const RELEASES_PAGE: String = "%s/releases" % Gen2AppVersion.REPOSITORY
## A release document is metadata. Anything larger is not one.
const MAX_RESPONSE_BYTES: int = 1024 * 1024

enum Status {
	UP_TO_DATE,
	UPDATE_AVAILABLE,
	AHEAD,
	NO_RELEASES,
	UNREADABLE,
}


## The running build, kept in code so the launcher can identify development
## builds before a GitHub release exists.
static func current_version() -> String:
	return Gen2AppVersion.VERSION


## Splits a version into comparable integers. A leading "v" is accepted because
## tags usually carry one, and any trailing prerelease or build suffix is cut,
## since ordering those is a promise this does not need to make.
static func parse_version(raw: String) -> Array[int]:
	var text: String = raw.strip_edges().lstrip("vV")
	for separator: String in ["-", "+", " "]:
		var at: int = text.find(separator)
		if at >= 0:
			text = text.substr(0, at)
	var parts: PackedStringArray = text.split(".", false)
	var out: Array[int] = []
	for part: String in parts:
		if not part.is_valid_int():
			break
		out.append(int(part))
	return out


## Negative when [param left] is older, positive when newer, zero when equal.
## Missing components count as zero, so "1.2" and "1.2.0" are the same version.
static func compare_versions(left: String, right: String) -> int:
	var a: Array[int] = parse_version(left)
	var b: Array[int] = parse_version(right)
	for index: int in maxi(a.size(), b.size()):
		var one: int = a[index] if index < a.size() else 0
		var two: int = b[index] if index < b.size() else 0
		if one != two:
			return -1 if one < two else 1
	return 0


## Reads GitHub's latest-release document into the fields the launcher shows.
## Returns { ok, version, name, url, published } or { ok: false, reason }.
static func parse_release(text: String) -> Dictionary:
	if text.length() > MAX_RESPONSE_BYTES:
		return {"ok": false, "reason": &"release_too_large"}
	var json := JSON.new()
	if json.parse(text) != OK or json.data is not Dictionary:
		return {"ok": false, "reason": &"release_not_readable"}
	var row: Dictionary = json.data
	var tag: String = String(row.get("tag_name", "")).strip_edges()
	if tag.is_empty() or parse_version(tag).is_empty():
		return {"ok": false, "reason": &"release_has_no_version"}
	var url: String = String(row.get("html_url", "")).strip_edges()
	return {
		"ok": true,
		"version": tag,
		"name": String(row.get("name", tag)).strip_edges(),
		"url": url if url.begins_with("https://") else RELEASES_PAGE,
		"published": String(row.get("published_at", "")).strip_edges(),
	}


## What to tell the player, given this build and whatever the request returned.
## A 404 is the repository having published nothing yet, which is an answer
## rather than a failure: the check worked, there is simply no release.
static func status_for(http_code: int, body: String, current: String = "") -> Dictionary:
	var running: String = current if not current.is_empty() else current_version()
	if http_code == 404:
		return {"status": Status.NO_RELEASES, "current": running, "version": ""}
	if http_code != 200:
		return {"status": Status.UNREADABLE, "current": running, "version": ""}
	var release: Dictionary = parse_release(body)
	if not release["ok"]:
		return {"status": Status.UNREADABLE, "current": running, "version": ""}
	var difference: int = compare_versions(running, String(release["version"]))
	var status: Status = Status.UP_TO_DATE
	if difference < 0:
		status = Status.UPDATE_AVAILABLE
	elif difference > 0:
		status = Status.AHEAD
	return {
		"status": status,
		"current": running,
		"version": release["version"],
		"name": release["name"],
		"url": release["url"],
		"published": release["published"],
	}


## One line for the launcher's status area.
static func describe(result: Dictionary) -> String:
	var current: String = String(result.get("current", ""))
	match int(result.get("status", Status.UNREADABLE)):
		Status.UP_TO_DATE:
			return "pokerecomp %s is the latest release." % current
		Status.UPDATE_AVAILABLE:
			return "Version %s is available. This build is %s." % [
				result.get("version", "?"), current
			]
		Status.AHEAD:
			return "This build, %s, is newer than the latest release %s." % [
				current, result.get("version", "?")
			]
		Status.NO_RELEASES:
			return "No release has been published yet. This build is %s." % current
		_:
			return "The release list could not be read."
