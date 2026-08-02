class_name RomHeader
extends RefCounted

## The Game Boy cartridge header at $0100-$014F.
##
## The import gate identifies a dump by SHA-1, which is stricter than anything
## in here — this exists so a *diagnostic* can say why a file looked wrong, and
## so an added registry entry can be sanity-checked against what the cartridge
## claims about itself. Nothing in the importer branches on these fields.

const TITLE_START: int = 0x134
const TITLE_END: int = 0x143
const CGB_FLAG: int = 0x143
const NEW_LICENSEE: int = 0x144
const SGB_FLAG: int = 0x146
const CART_TYPE: int = 0x147
const ROM_SIZE_CODE: int = 0x148
const RAM_SIZE_CODE: int = 0x149
const DESTINATION: int = 0x14A
const OLD_LICENSEE: int = 0x14B
const VERSION: int = 0x14C
const HEADER_CHECKSUM: int = 0x14D
const GLOBAL_CHECKSUM: int = 0x14E

## $80 runs on both Game Boy and Game Boy Color; $C0 is Color-only. Gold and
## Silver are $80, Crystal is $C0 — Crystal was the first mainline game that
## would not boot on a DMG.
const CGB_COMPATIBLE: int = 0x80
const CGB_ONLY: int = 0xC0

var title: String = ""
var cgb_flag: int = 0
var new_licensee: String = ""
var sgb_flag: int = 0
var cart_type: int = 0
var rom_size_code: int = 0
var ram_size_code: int = 0
var destination: int = 0
var old_licensee: int = 0
var version: int = 0
var header_checksum: int = 0
var global_checksum: int = 0


static func parse(rom: RomFile) -> RomHeader:
	var header := RomHeader.new()

	var raw_title: PackedByteArray = rom.slice(TITLE_START, TITLE_END - TITLE_START)
	var letters: PackedByteArray = PackedByteArray()
	for byte: int in raw_title:
		# The title field is ASCII padded with $00, and later cartridges stole
		# its last bytes for the manufacturer code and the CGB flag. Stopping at
		# the first non-printable byte gets the human-readable part.
		if byte < 0x20 or byte > 0x7E:
			break
		letters.append(byte)
	header.title = letters.get_string_from_ascii()

	header.cgb_flag = rom.u8(CGB_FLAG)
	header.new_licensee = rom.slice(NEW_LICENSEE, 2).get_string_from_ascii()
	header.sgb_flag = rom.u8(SGB_FLAG)
	header.cart_type = rom.u8(CART_TYPE)
	header.rom_size_code = rom.u8(ROM_SIZE_CODE)
	header.ram_size_code = rom.u8(RAM_SIZE_CODE)
	header.destination = rom.u8(DESTINATION)
	header.old_licensee = rom.u8(OLD_LICENSEE)
	header.version = rom.u8(VERSION)
	header.header_checksum = rom.u8(HEADER_CHECKSUM)
	# The only big-endian field in the header.
	header.global_checksum = (rom.u8(GLOBAL_CHECKSUM) << 8) | rom.u8(GLOBAL_CHECKSUM + 1)
	return header


## Bytes $0134-$014C folded with x = x - byte - 1. The boot ROM refuses to start
## a cartridge whose stored value disagrees.
static func compute_header_checksum(rom: RomFile) -> int:
	var sum: int = 0
	for offset: int in range(TITLE_START, HEADER_CHECKSUM):
		sum = (sum - rom.u8(offset) - 1) & 0xFF
	return sum


## Sum of every byte in the cartridge except the two that store it. Real
## hardware never checks this, so a patched ROM commonly fails it.
static func compute_global_checksum(rom: RomFile) -> int:
	var sum: int = 0
	var data: PackedByteArray = rom.bytes()
	for i: int in data.size():
		if i != GLOBAL_CHECKSUM and i != GLOBAL_CHECKSUM + 1:
			sum += data[i]
	return sum & 0xFFFF


## Cartridge size the header claims, in bytes: 32 KiB shifted by the code.
func declared_rom_size() -> int:
	return 0x8000 << rom_size_code


func is_color_game() -> bool:
	return cgb_flag == CGB_COMPATIBLE or cgb_flag == CGB_ONLY


func describe() -> String:
	return "%s  cgb=$%02X  cart=$%02X  rom=%d KiB  ver=%d" % [
		title, cgb_flag, cart_type, declared_rom_size() / 1024, version,
	]
