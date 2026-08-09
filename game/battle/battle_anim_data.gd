class_name Gen2BattleAnimData
extends RefCounted

## The five imported battle animation tables, read the way the cartridge reads
## them.
##
## [Gen2BattleAnimImporter] caches each table as a whole region, table and data
## together, because every pointer inside one is bank-local. This resolves those
## pointers: an address minus the region's base is an index into its bytes, which
## is the same arithmetic `add hl, de` does with the bank paged in.
##
## Scene-free and [GameData]-free once built, so a test can hand-build one the
## way a battle fixture hand-builds a party.

## `BattleAnimObjects` row fields, in the order `InitBattleAnimation` copies them.
const OBJECT_FIELDS: Array[StringName] = [
	&"flags", &"y_fix", &"frameset", &"function", &"palette", &"gfx",
]

var _regions: Dictionary = {}
var _gfx: Array = []


## Built from a cache. Returns null when the cache carries no animation layer,
## so a caller can tell "not imported" from "imported and empty".
static func from_game_data(data: GameData) -> Gen2BattleAnimData:
	if data == null:
		return null
	var regions: Dictionary = {}
	for name: StringName in [&"scripts", &"objects", &"framesets", &"oam_sets"]:
		var region: Dictionary = data.battle_anim_region(name)
		if region.is_empty():
			return null
		regions[name] = region
	var gfx: Array = []
	for index: int in data.battle_anim_gfx_count():
		gfx.append(data.battle_anim_gfx(index))
	return create(regions, gfx)


static func create(regions: Dictionary, gfx: Array) -> Gen2BattleAnimData:
	var out := Gen2BattleAnimData.new()
	out._regions = regions
	out._gfx = gfx
	return out


func region(name: StringName) -> Dictionary:
	var value: Variant = _regions.get(name, null)
	return value if value is Dictionary else {}


## One byte of a region, addressed the way the cartridge addresses it. Out of
## range answers zero, which is what [method RomFile.u8] does and for the same
## reason: a walk whose length is only known once decoded should end honestly
## rather than fault.
func byte_at(name: StringName, address: int) -> int:
	var entry: Dictionary = region(name)
	if entry.is_empty():
		return 0
	var at: int = address - int(entry["address"])
	var data: PackedByteArray = entry["data"]
	return data[at] if at >= 0 and at < data.size() else 0


func word_at(name: StringName, address: int) -> int:
	return byte_at(name, address) | (byte_at(name, address + 1) << 8)


## Entry [param index] of a region's own two-byte pointer table, which is the
## first bytes of the region.
func pointer(name: StringName, index: int) -> int:
	var entry: Dictionary = region(name)
	if entry.is_empty() or index < 0 or index >= int(entry["count"]):
		return -1
	return word_at(name, int(entry["address"]) + index * 2)


func count(name: StringName) -> int:
	var entry: Dictionary = region(name)
	return int(entry["count"]) if not entry.is_empty() else 0


## One `battleanimobj` row. Empty past the end of `BattleAnimObjects`.
func object_row(index: int) -> Dictionary:
	if index < 0 or index >= count(&"objects"):
		return {}
	var base: int = int(region(&"objects")["address"]) \
		+ index * RomLayout.BATTLE_ANIM_OBJECT_SIZE
	var out: Dictionary = {}
	for field: int in OBJECT_FIELDS.size():
		out[OBJECT_FIELDS[field]] = byte_at(&"objects", base + field)
	return out


## Where `BattleAnimFrameData`'s stream for [param frameset] starts.
func frameset_address(frameset: int) -> int:
	return pointer(&"framesets", frameset)


## One `battleanimoam` row: the tile offset it adds, how many `dbsprite`
## records follow and where they are.
func oam_set(index: int) -> Dictionary:
	if index < 0 or index >= count(&"oam_sets"):
		return {}
	var base: int = int(region(&"oam_sets")["address"]) \
		+ index * RomLayout.BATTLE_ANIM_OAM_SET_SIZE
	return {
		"vtile": byte_at(&"oam_sets", base + Gen2BattleAnimImporter.OAM_SET_VTILE),
		"length": byte_at(&"oam_sets", base + Gen2BattleAnimImporter.OAM_SET_LENGTH),
		"address": word_at(&"oam_sets", base + Gen2BattleAnimImporter.OAM_SET_POINTER),
	}


## One `dbsprite`: y, x, tile offset, attributes.
func oam_sprite(address: int, index: int) -> Dictionary:
	var at: int = address + index * RomLayout.BATTLE_ANIM_OAM_SPRITE_SIZE
	return {
		"y": byte_at(&"oam_sets", at),
		"x": byte_at(&"oam_sets", at + 1),
		"tile": byte_at(&"oam_sets", at + 2),
		"attributes": byte_at(&"oam_sets", at + 3),
	}


## One `AnimObjGFX` row, or empty past the table.
func gfx(index: int) -> Dictionary:
	if index < 0 or index >= _gfx.size():
		return {}
	var row: Variant = _gfx[index]
	return row if row is Dictionary else {}


func gfx_count() -> int:
	return _gfx.size()
