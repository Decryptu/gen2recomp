class_name Gen2BattleAnimImporter
extends RefCounted

## Imports the battle animation data layer: `BattleAnimations`
## (data/moves/animations.asm) and the four tables in data/battle_anims that the
## objects it spawns are built from.
##
## Each of the five is a pointer table immediately followed by the data it points
## at, and every pointer inside one is bank-local, so each is cached as a whole
## region rather than entry by entry: the bytes stay the cartridge's own and a
## cached address resolves by subtraction. Nothing is rewritten on the way in.
##
## The three regions in bank $33 are contiguous and do not overlap: the frameset
## streams end where `BattleAnimOAMData` begins and its sprite data ends where
## `AnimObjGFX` begins. Each region is still measured from its own table's
## pointers rather than from its neighbour, so a profile that moved one would
## still import.
##
## Validation walks what it stores. Every script is run to a top-level
## `anim_ret`, every frameset stream to its terminator and every table index is
## range-checked before anything is written, which is what makes a wrong offset
## a refused import rather than a screen full of noise.
##
## The object graphics are the exception: they are LZ streams reached by far
## pointer, so they are decoded into tile strips the way the pics and the trainer
## card's sheets are.

## `BattleAnim_Pound` whole, the anchor the script table was located from. Held
## here rather than in [RomLayout] because it is a check, not an offset: the
## first entry of `BattleAnimations` is `BattleAnim_Dummy`, which is a bare
## `anim_ret` and proves nothing.
const POUND_BYTES: Array[int] = [
	0xD1, 0x01, 0xE0, 0x01, 0x31, 0xD0, 0x08, 0x88, 0x38, 0x00,
	0x06, 0xD0, 0x01, 0x88, 0x38, 0x00, 0x10, 0xFF,
]
## Which entry of `BattleAnimations` [constant POUND_BYTES] belongs to: POUND is
## move 1, and the table is indexed by move number.
const POUND_INDEX: int = 1

## Runaway guards. Neither is the cartridge's, which walks both of these without
## a limit; both sit well past the longest run in any of the three dumps, which
## are a 185-byte animation body and a 31-byte frameset stream.
const MAX_BODY_BYTES: int = 1024
const MAX_FRAMESET_BYTES: int = 256

## `oam_anims.asm`'s own commands. `FIRST_OAM_CMD` is $fc, so anything below it
## is an `oamframe`'s OAM set id.
const OAM_DELETE: int = 0xFC
const OAM_WAIT: int = 0xFD
const OAM_RESTART: int = 0xFE
const OAM_END: int = 0xFF
const FIRST_OAM_COMMAND: int = OAM_DELETE

## Byte positions inside one `battleanimobj` row.
const OBJECT_FLAGS: int = 0
const OBJECT_Y_FIX: int = 1
const OBJECT_FRAMESET: int = 2
const OBJECT_FUNCTION: int = 3
const OBJECT_PALETTE: int = 4
const OBJECT_GFX: int = 5

## Byte positions inside one `battleanimoam` row: vtile offset, sprite count,
## then a two-byte pointer to that many `dbsprite` records.
const OAM_SET_VTILE: int = 0
const OAM_SET_LENGTH: int = 1
const OAM_SET_POINTER: int = 2

## Byte positions inside one `anim_obj_gfx` row: a tile count, then a `dba`.
const GFX_TILES: int = 0
const GFX_POINTER: int = 1

## `NUM_BATTLE_ANIM_FUNCS` (constants/battle_anim_constants.asm), the callback
## jumptable an object row indexes. The only part of that constants file the two
## pins disagree on is `BATTLE_BG_EFFECT_*` from $25 on, which no table here
## indexes, so all five counts are shared.
const FUNCTION_COUNT: int = 80

## `PAL_BATTLE_OB_*`, the eight object palettes a row can name.
const PALETTE_COUNT: int = 8


static func verify_layout(rom: RomFile) -> Dictionary:
	var result: Dictionary = read_battle_anims(rom, RomLayout.for_id(rom.id))
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"message": String(result.get("message", "Battle animation data failed validation.")),
		}
	return {"ok": true, "message": ""}


static func import_to_cache(
	rom: RomFile, layout: Dictionary, directory: String
) -> Dictionary:
	var result: Dictionary = read_battle_anims(rom, layout)
	if not bool(result.get("ok", false)):
		return result

	var sheets: Dictionary = _decode_sheets(rom, result["anims"]["object_gfx"])
	if not bool(sheets.get("ok", false)):
		return sheets
	for number: int in sheets["strips"]:
		if not RomCache.write_indices(
			RomCache.battle_anim_gfx_path(directory, number), sheets["strips"][number]
		):
			return {"ok": false, "message": "Could not write battle animation graphics."}

	if not RomCache.write_section(
		RomCache.battle_anims_path(directory),
		RomCache.blob_path(RomCache.battle_anims_path(directory)),
		result["anims"]
	):
		return {"ok": false, "message": "Could not write battle animation data."}

	return {
		"ok": true,
		"scripts": int(result["counts"]["scripts"]),
		"objects": int(result["counts"]["objects"]),
		"framesets": int(result["counts"]["framesets"]),
		"oam_sets": int(result["counts"]["oam_sets"]),
		"gfx_sheets": int(sheets["sheets"]),
		"gfx_tiles": int(sheets["tiles"]),
	}


## Reads and validates the whole layer. Returns
## [code]{ ok, message, anims, counts }[/code].
static func read_battle_anims(rom: RomFile, layout: Dictionary) -> Dictionary:
	if layout.is_empty():
		return {"ok": false, "message": "No battle animation layout for %s." % rom.id}
	var configured: Variant = layout.get("battle_anims", null)
	if not configured is Dictionary:
		return {"ok": false, "message": "Battle animation offsets are missing for %s." % rom.id}
	var anim_layout: Dictionary = configured

	var scripts: Dictionary = _read_scripts(rom, int(anim_layout["scripts"]))
	if not bool(scripts.get("ok", false)):
		return scripts

	var framesets: Dictionary = _read_framesets(rom, int(anim_layout["framesets"]))
	if not bool(framesets.get("ok", false)):
		return framesets

	var oam_sets: Dictionary = _read_oam_sets(rom, int(anim_layout["oam_sets"]))
	if not bool(oam_sets.get("ok", false)):
		return oam_sets

	var object_gfx: Dictionary = _read_object_gfx(rom, int(anim_layout["object_gfx"]))
	if not bool(object_gfx.get("ok", false)):
		return object_gfx

	var objects: Dictionary = _read_objects(rom, int(anim_layout["objects"]))
	if not bool(objects.get("ok", false)):
		return objects

	return {
		"ok": true,
		"message": "",
		"anims": {
			"scripts": scripts["region"],
			"objects": objects["region"],
			"framesets": framesets["region"],
			"oam_sets": oam_sets["region"],
			"object_gfx": object_gfx["rows"],
		},
		"counts": {
			"scripts": RomLayout.BATTLE_ANIM_SCRIPT_COUNT,
			"objects": RomLayout.BATTLE_ANIM_OBJECT_COUNT,
			"framesets": RomLayout.BATTLE_ANIM_FRAMESET_COUNT,
			"oam_sets": RomLayout.BATTLE_ANIM_OAM_SET_COUNT,
		},
	}


## `BattleAnimations` and every body it reaches, as one region.
##
## The walk follows calls and branches the way [Gen2BattleAnimScript] does, so a
## body only some other body jumps into is still measured, and refuses anything
## that leaves the bank or never reaches a top-level `anim_ret`.
static func _read_scripts(rom: RomFile, table: int) -> Dictionary:
	var count: int = RomLayout.BATTLE_ANIM_SCRIPT_COUNT
	if not rom.in_bounds(table, count * 2):
		return {"ok": false, "message": "Battle animation script table is outside the cartridge."}

	var bank: int = table / RomFile.BANK_SIZE
	var base: int = 0x4000 + (table % RomFile.BANK_SIZE)
	var addresses: Array[int] = []
	for index: int in count:
		var address: int = rom.u16le(table + index * 2)
		if address < 0x4000 or address >= 0x8000:
			return {
				"ok": false,
				"message": "Battle animation %d points at $%04X, outside the bank." % [
					index, address,
				],
			}
		addresses.append(address)

	# The whole bank, so a walk can reach anything the table can and the extent
	# is measured rather than assumed. Only the reached span is kept.
	var bank_bytes: PackedByteArray = rom.slice(bank * RomFile.BANK_SIZE, RomFile.BANK_SIZE)
	if bank_bytes.size() != RomFile.BANK_SIZE:
		return {"ok": false, "message": "Battle animation bank is outside the cartridge."}

	# Content the offset is only trustworthy against: a table of the right shape
	# in the wrong place still walks, because almost any byte run decodes as
	# commands. POUND's animation is the same eighteen bytes in all three dumps.
	var pound: int = addresses[POUND_INDEX] - 0x4000
	if pound + POUND_BYTES.size() > bank_bytes.size():
		return {"ok": false, "message": "Battle animation %d runs past the bank." % POUND_INDEX}
	for index: int in POUND_BYTES.size():
		if bank_bytes[pound + index] != POUND_BYTES[index]:
			return {
				"ok": false,
				"message": "Battle animation %d is not POUND's: byte %d is $%02X, expected $%02X." % [
					POUND_INDEX, index, bank_bytes[pound + index], POUND_BYTES[index],
				],
			}

	var lowest: int = base
	var highest: int = base + count * 2
	var walked: Dictionary = {}
	var pending: Array[int] = addresses.duplicate()
	while not pending.is_empty():
		var address: int = pending.pop_back()
		if walked.has(address):
			continue
		walked[address] = true
		var body: Dictionary = _walk_body(bank_bytes, address)
		if not bool(body.get("ok", false)):
			return body
		lowest = mini(lowest, address)
		highest = maxi(highest, int(body["end"]))
		for target: int in body["targets"]:
			pending.append(target)

	return {
		"ok": true,
		"region": {
			"bank": bank,
			"address": lowest,
			"count": count,
			"bytes": _region_bytes(bank_bytes, lowest, highest),
		},
	}


## One animation body, from [param address] to its `anim_ret`. Returns
## [code]{ ok, end, targets }[/code], `end` being the address just past the ret.
static func _walk_body(bank_bytes: PackedByteArray, address: int) -> Dictionary:
	var targets: Array[int] = []
	var at: int = address
	var read: int = 0
	while true:
		read += 1
		if read > MAX_BODY_BYTES:
			return {
				"ok": false,
				"message": "Battle animation body at $%04X never ends." % address,
			}
		var command: Dictionary = Gen2BattleAnimScript.decode_command(bank_bytes, 0x4000, at)
		if not bool(command.get("ok", false)):
			return {
				"ok": false,
				"message": "Battle animation body at $%04X runs past the bank." % address,
			}
		at += int(command["size"])
		var target: int = int(command["target"])
		if target >= 0:
			if target < 0x4000 or target >= 0x8000:
				return {
					"ok": false,
					"message": "Battle animation body at $%04X branches to $%04X, outside the bank." % [
						address, target,
					],
				}
			targets.append(target)
		if command["name"] == Gen2BattleAnimScript.RET:
			break
	return {"ok": true, "end": at, "targets": targets}


## `BattleAnimObjects`, whose rows carry no pointers, so the region is the table
## and nothing else.
static func _read_objects(rom: RomFile, table: int) -> Dictionary:
	var count: int = RomLayout.BATTLE_ANIM_OBJECT_COUNT
	var size: int = count * RomLayout.BATTLE_ANIM_OBJECT_SIZE
	if not rom.in_bounds(table, size):
		return {"ok": false, "message": "Battle animation object table is outside the cartridge."}

	for index: int in count:
		var row: int = table + index * RomLayout.BATTLE_ANIM_OBJECT_SIZE
		var frameset: int = rom.u8(row + OBJECT_FRAMESET)
		if frameset >= RomLayout.BATTLE_ANIM_FRAMESET_COUNT:
			return {
				"ok": false,
				"message": "Battle animation object %d names frameset %d, past the table." % [
					index, frameset,
				],
			}
		var function: int = rom.u8(row + OBJECT_FUNCTION)
		if function >= FUNCTION_COUNT:
			return {
				"ok": false,
				"message": "Battle animation object %d names callback %d, past the table." % [
					index, function,
				],
			}
		var palette: int = rom.u8(row + OBJECT_PALETTE)
		if palette >= PALETTE_COUNT:
			return {
				"ok": false,
				"message": "Battle animation object %d names palette %d, past the eight." % [
					index, palette,
				],
			}
		var gfx: int = rom.u8(row + OBJECT_GFX)
		if gfx >= RomLayout.BATTLE_ANIM_GFX_COUNT:
			return {
				"ok": false,
				"message": "Battle animation object %d names graphics %d, past the table." % [
					index, gfx,
				],
			}

	return {
		"ok": true,
		"region": {
			"bank": table / RomFile.BANK_SIZE,
			"address": 0x4000 + (table % RomFile.BANK_SIZE),
			"count": count,
			"bytes": _bytes_of(rom.slice(table, size)),
		},
	}


## `BattleAnimFrameData` and the `oamframe` streams it points at, as one region.
static func _read_framesets(rom: RomFile, table: int) -> Dictionary:
	var count: int = RomLayout.BATTLE_ANIM_FRAMESET_COUNT
	if not rom.in_bounds(table, count * 2):
		return {"ok": false, "message": "Battle animation frameset table is outside the cartridge."}

	var bank: int = table / RomFile.BANK_SIZE
	var base: int = 0x4000 + (table % RomFile.BANK_SIZE)
	var bank_bytes: PackedByteArray = rom.slice(bank * RomFile.BANK_SIZE, RomFile.BANK_SIZE)
	if bank_bytes.size() != RomFile.BANK_SIZE:
		return {"ok": false, "message": "Battle animation frameset bank is outside the cartridge."}

	var lowest: int = base
	var highest: int = base + count * 2
	for index: int in count:
		var address: int = rom.u16le(table + index * 2)
		if address < 0x4000 or address >= 0x8000:
			return {
				"ok": false,
				"message": "Frameset %d points at $%04X, outside the bank." % [index, address],
			}
		var stream: Dictionary = _walk_frameset(bank_bytes, address)
		if not bool(stream.get("ok", false)):
			return stream
		lowest = mini(lowest, address)
		highest = maxi(highest, int(stream["end"]))

	return {
		"ok": true,
		"region": {
			"bank": bank,
			"address": lowest,
			"count": count,
			"bytes": _region_bytes(bank_bytes, lowest, highest),
		},
	}


## One `oamframe` stream, to whichever of the three terminators ends it.
##
## An `oamframe` and an `oamwait` are both two bytes, because `.GetPointer`
## indexes frames by `frame * 2`. The three terminators are one byte each in the
## macros and the byte after them belongs to the next frameset, which the
## cartridge reads and discards: `.next_frame` stores it as a duration for
## `oamdelete` and never for `oamend` or `oamrestart`, and the object is deleted
## before that duration can be counted.
static func _walk_frameset(bank_bytes: PackedByteArray, address: int) -> Dictionary:
	var at: int = address - 0x4000
	for _step: int in MAX_FRAMESET_BYTES:
		if at < 0 or at >= bank_bytes.size():
			return {"ok": false, "message": "Frameset stream at $%04X runs past the bank." % address}
		var byte: int = bank_bytes[at]
		if byte == OAM_END or byte == OAM_RESTART or byte == OAM_DELETE:
			return {"ok": true, "end": 0x4000 + at + 1}
		if byte < FIRST_OAM_COMMAND and byte >= RomLayout.BATTLE_ANIM_OAM_SET_COUNT:
			return {
				"ok": false,
				"message": "Frameset stream at $%04X names OAM set %d, past the table." % [
					address, byte,
				],
			}
		at += 2
	return {"ok": false, "message": "Frameset stream at $%04X never ends." % address}


## `BattleAnimOAMData` and the `dbsprite` records it points at, as one region.
static func _read_oam_sets(rom: RomFile, table: int) -> Dictionary:
	var count: int = RomLayout.BATTLE_ANIM_OAM_SET_COUNT
	var size: int = count * RomLayout.BATTLE_ANIM_OAM_SET_SIZE
	if not rom.in_bounds(table, size):
		return {"ok": false, "message": "Battle animation OAM table is outside the cartridge."}

	var bank: int = table / RomFile.BANK_SIZE
	var base: int = 0x4000 + (table % RomFile.BANK_SIZE)
	var bank_bytes: PackedByteArray = rom.slice(bank * RomFile.BANK_SIZE, RomFile.BANK_SIZE)
	if bank_bytes.size() != RomFile.BANK_SIZE:
		return {"ok": false, "message": "Battle animation OAM bank is outside the cartridge."}

	var lowest: int = base
	var highest: int = base + size
	for index: int in count:
		var row: int = table + index * RomLayout.BATTLE_ANIM_OAM_SET_SIZE
		var length: int = rom.u8(row + OAM_SET_LENGTH)
		if length <= 0:
			return {"ok": false, "message": "OAM set %d holds no sprites." % index}
		var address: int = rom.u16le(row + OAM_SET_POINTER)
		var span: int = length * RomLayout.BATTLE_ANIM_OAM_SPRITE_SIZE
		if address < 0x4000 or address + span > 0x8000:
			return {
				"ok": false,
				"message": "OAM set %d points at $%04X for %d sprites, outside the bank." % [
					index, address, length,
				],
			}
		lowest = mini(lowest, address)
		highest = maxi(highest, address + span)

	return {
		"ok": true,
		"region": {
			"bank": bank,
			"address": lowest,
			"count": count,
			"bytes": _region_bytes(bank_bytes, lowest, highest),
		},
	}


## `AnimObjGFX`, kept as rows rather than a region: its pointers are far ones
## into the compressed graphics banks, so nothing follows the table.
static func _read_object_gfx(rom: RomFile, table: int) -> Dictionary:
	var count: int = RomLayout.BATTLE_ANIM_GFX_COUNT
	var size: int = count * RomLayout.BATTLE_ANIM_GFX_SIZE
	if not rom.in_bounds(table, size):
		return {"ok": false, "message": "Battle animation graphics table is outside the cartridge."}

	var rows: Array = []
	for index: int in count:
		var row: int = table + index * RomLayout.BATTLE_ANIM_GFX_SIZE
		var pointer: Dictionary = rom.far_pointer(row + GFX_POINTER)
		var sheet: bool = index >= RomLayout.BATTLE_ANIM_GFX_FIRST_SHEET \
			and index <= RomLayout.BATTLE_ANIM_GFX_LAST_SHEET
		if sheet and not rom.in_bounds(
			RomFile.linear(int(pointer["bank"]), int(pointer["address"]))
		):
			return {
				"ok": false,
				"message": "Battle animation graphics %d point outside the cartridge." % index,
			}
		rows.append({
			"tiles": rom.u8(row + GFX_TILES),
			"bank": pointer["bank"],
			"address": pointer["address"],
			"sheet": sheet,
		})

	return {"ok": true, "rows": rows}


## Decompresses every row that has a sheet into a tile strip. Returns
## [code]{ ok, strips, sheets, tiles }[/code].
static func _decode_sheets(rom: RomFile, rows: Array) -> Dictionary:
	var lz := Gen2Lz.new()
	var strips: Dictionary = {}
	var tiles: int = 0
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		if not bool(row["sheet"]):
			continue
		var count: int = int(row["tiles"])
		var start: int = RomFile.linear(int(row["bank"]), int(row["address"]))
		var raw: PackedByteArray = lz.decompress(rom.bytes(), start)
		if lz.failed or raw.size() < count * Gen2Tiles.TILE_BYTES:
			return {
				"ok": false,
				"message": "Battle animation graphics %d decompressed to %d bytes, short of %d." % [
					index, raw.size(), count * Gen2Tiles.TILE_BYTES,
				],
			}
		strips[index] = Gen2Tiles.decode_2bpp_strip(raw, 0, count)
		tiles += count
	return {"ok": true, "strips": strips, "sheets": strips.size(), "tiles": tiles}


## The slice of a bank between two of its own addresses, as an Array the cache
## moves into the section blob.
static func _region_bytes(bank_bytes: PackedByteArray, from: int, to: int) -> Array:
	return _bytes_of(bank_bytes.slice(from - 0x4000, to - 0x4000))


static func _bytes_of(data: PackedByteArray) -> Array:
	var out: Array = []
	out.resize(data.size())
	for index: int in data.size():
		out[index] = data[index]
	return out
