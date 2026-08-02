class_name RomRegistry
extends RefCounted

## The allowlist of ROMs this project can import from.
##
## gen2recomp ships no game data. A user supplies their own cartridge dump and
## it is matched against this table by SHA-1 before a single byte is read for
## content. An unknown hash is a hard refusal, never a "try anyway" — a ROM we
## have not characterised has unknown bank layout, and guessing produces
## corrupt assets rather than an honest error.
##
## Gen 2 is three games. Crystal's two common filenames (the "(UE) (V1.1)" and
## "(USA, Europe) (Rev 1)" dumps) are byte-identical, so they collapse to one
## entry here — matching is by hash, never by filename.

## Every Game Boy Color cartridge in this generation is 2 MiB. Used only as a
## cheap pre-filter so a wrong file is rejected before we hash it.
const EXPECTED_SIZE: int = 2097152

const GOLD: StringName = &"gold"
const SILVER: StringName = &"silver"
const CRYSTAL: StringName = &"crystal"

## sha1 (lowercase hex) -> { id, title, revision }
const BY_SHA1: Dictionary = {
	"d8b8a3600a465308c9953dfa04f0081c05bdcb94": {
		"id": GOLD,
		"title": "Gold",
		"revision": "USA/Europe",
	},
	"49b163f7e57702bc939d642a18f591de55d92dae": {
		"id": SILVER,
		"title": "Silver",
		"revision": "USA/Europe",
	},
	"f2f52230b536214ef7c9924f483392993e226cfb": {
		"id": CRYSTAL,
		"title": "Crystal",
		"revision": "USA/Europe Rev 1",
	},
}

## Display order for the launcher tabs.
const ORDER: Array[StringName] = [GOLD, SILVER, CRYSTAL]


static func is_known(sha1: String) -> bool:
	return BY_SHA1.has(sha1.to_lower())


## Returns the registry row for a hash, or an empty Dictionary if unknown.
static func lookup(sha1: String) -> Dictionary:
	return BY_SHA1.get(sha1.to_lower(), {})


## The hash that identifies a given game id, or "" if the id is not ours.
static func sha1_for(id: StringName) -> String:
	for sha1: String in BY_SHA1:
		if BY_SHA1[sha1]["id"] == id:
			return sha1
	return ""


static func title_for(id: StringName) -> String:
	for sha1: String in BY_SHA1:
		if BY_SHA1[sha1]["id"] == id:
			return BY_SHA1[sha1]["title"]
	return ""
