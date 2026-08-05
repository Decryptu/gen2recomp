class_name Gen2SaveData
extends RefCounted

## One project save slot, independent of scenes and battle state.
##
## The game and ROM identifiers prevent a save from silently being opened with
## the wrong cartridge cache. The schema is versioned so a future save shape
## can be refused or migrated deliberately instead of being guessed at.

const FORMAT_VERSION: int = 1
const MAX_PARTY: int = Gen2Party.MAX_SIZE
const MAX_PLAYER_NAME: int = 10

var format_version: int = FORMAT_VERSION
var game_id: StringName = &""
var rom_sha1: String = ""
var slot: int = -1
var player_name: String = ""
var party: Array = []
var world: Gen2WorldSnapshot = null


func to_dict() -> Dictionary:
	var saved_party: Array = []
	for mon: Gen2SaveMon in party:
		saved_party.append(mon.to_dict() if mon != null else {})
	return {
		"format_version": format_version,
		"game_id": String(game_id),
		"rom_sha1": rom_sha1,
		"slot": slot,
		"player_name": player_name,
		"party": saved_party,
		"world": world.to_dict() if world != null else {},
	}


## Parses the serialized shape without claiming that the data is usable. The
## selected cartridge cache is needed for species, move, item and HP checks.
static func from_dict(raw: Variant) -> Gen2SaveData:
	if not raw is Dictionary:
		return null
	var source: Dictionary = raw
	var out := Gen2SaveData.new()
	out.format_version = int(source.get("format_version", -1))
	out.game_id = StringName(source.get("game_id", ""))
	out.rom_sha1 = String(source.get("rom_sha1", ""))
	out.slot = int(source.get("slot", -1))
	out.player_name = String(source.get("player_name", ""))
	var raw_party: Variant = source.get("party", [])
	if raw_party is Array:
		for raw_mon: Variant in raw_party as Array:
			out.party.append(Gen2SaveMon.from_dict(raw_mon))
	var raw_world: Variant = source.get("world", {})
	if raw_world is Dictionary and not (raw_world as Dictionary).is_empty():
		out.world = Gen2WorldSnapshot.from_dict(raw_world)
	return out
