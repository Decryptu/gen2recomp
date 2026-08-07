class_name RomFile
extends RefCounted

## A cartridge dump held in memory for the duration of an import.
##
## Node-free like the rest of the ROM layer. [method open_verified] refuses
## anything [RomVerifier] has not accepted, since every [RomLayout] offset is
## only meaningful for a characterised dump.
##
## Reads are bounds-checked and return zero rather than faulting: decoders walk
## data whose length is only known once decoded, and a corrupt stream should end
## as an honest "that did not decode" rather than an engine error.

## Cartridge banks are 16 KiB; the CPU sees one fixed and one switchable.
const BANK_SIZE: int = 0x4000

var path: String = ""
var sha1: String = ""
var id: StringName = &""

var _bytes: PackedByteArray = PackedByteArray()


## Loads a ROM only if it verifies against the registry. Returns null otherwise;
## call [method RomVerifier.identify] first if you want the reason.
static func open_verified(rom_path: String) -> RomFile:
	var info: Dictionary = RomVerifier.identify(rom_path)
	if info["status"] != RomVerifier.Status.OK:
		return null

	var file: FileAccess = FileAccess.open(rom_path, FileAccess.READ)
	if file == null:
		return null

	var rom := RomFile.new()
	rom.path = rom_path
	rom.sha1 = info["sha1"]
	rom.id = info["id"]
	rom._bytes = file.get_buffer(file.get_length())
	file.close()
	return rom


## Wraps bytes that have already been vouched for. For tests and tooling;
## production paths should go through [method open_verified].
static func from_bytes(data: PackedByteArray, game_id: StringName = &"") -> RomFile:
	var rom := RomFile.new()
	rom.id = game_id
	rom._bytes = data
	return rom


## A bank number and a CPU address as the cartridge sees them, flattened to an
## offset into the dump. Correct for both the fixed bank ($0000-$3FFF) and the
## switchable window ($4000-$7FFF): only the low 14 bits of an address carry a
## position within a bank.
static func linear(bank: int, address: int) -> int:
	return bank * BANK_SIZE + (address & 0x3FFF)


func size() -> int:
	return _bytes.size()


func bytes() -> PackedByteArray:
	return _bytes


func in_bounds(offset: int, length: int = 1) -> bool:
	return offset >= 0 and length >= 0 and offset + length <= _bytes.size()


func u8(offset: int) -> int:
	return _bytes[offset] if in_bounds(offset) else 0


func u16le(offset: int) -> int:
	if not in_bounds(offset, 2):
		return 0
	return _bytes[offset] | (_bytes[offset + 1] << 8)


func slice(offset: int, length: int) -> PackedByteArray:
	if not in_bounds(offset, length):
		return PackedByteArray()
	return _bytes.slice(offset, offset + length)


## Reads a three-byte "bank, little-endian address" pointer, the form every
## far-pointer table in these games uses. Returns { bank, address }.
func far_pointer(offset: int) -> Dictionary:
	return {"bank": u8(offset), "address": u16le(offset + 1)}
