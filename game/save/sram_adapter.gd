class_name Gen2SramAdapter
extends RefCounted

## Boundary between an original Generation 2 SRAM image and the project's
## party-focused save model.
##
## The adapter only writes an existing, checksummed cartridge image. This is
## deliberate: the current canonical save model does not own map, options,
## inventory, PC boxes or event flags, so creating those bytes from scratch
## would silently invent game state. Bytes outside the fields mapped here stay
## untouched.

const SRAM_SIZE: int = 0x8000
const SAVE_CHECK_VALUE_1: int = 99
const SAVE_CHECK_VALUE_2: int = 127
const PARTY_LENGTH: int = 6
const PARTYMON_SIZE: int = 48
const NAME_LENGTH: int = 11
const MON_NAME_LENGTH: int = 11
const PP_MASK: int = 0x3F
const PP_UP_MASK: int = 0xC0

const LAYOUTS: Dictionary = {
	"gold": {
		"primary_check_1": 0x2008,
		"primary_data_start": 0x2009,
		"primary_data_end": 0x2D69,
		"primary_checksum": 0x2D69,
		"primary_check_2": 0x2D6B,
		"backup_check_1": 0x7E38,
		"backup_checksum": 0x7E6D,
		"backup_check_2": 0x7E6F,
		"player_name": 0x200B,
		"party": 0x288A,
		"backup_segments": [
			[0x2009, 0x15C7, 0x226],
			[0x222F, 0x3D96, 0x1AA],
			[0x23D9, 0x0C6B, 0x47D],
			[0x2856, 0x7E39, 0x34],
			[0x288A, 0x10E8, 0x4DF],
		],
		"backup_checksum_segments": [
			[0x10E8, 0x4DF],
			[0x0C6B, 0x47D],
			[0x15C7, 0x226],
			[0x3D96, 0x1AA],
			[0x7E39, 0x34],
		],
	},
	"silver": {
		"primary_check_1": 0x2008,
		"primary_data_start": 0x2009,
		"primary_data_end": 0x2D69,
		"primary_checksum": 0x2D69,
		"primary_check_2": 0x2D6B,
		"backup_check_1": 0x7E38,
		"backup_checksum": 0x7E6D,
		"backup_check_2": 0x7E6F,
		"player_name": 0x200B,
		"party": 0x288A,
		"backup_segments": [
			[0x2009, 0x15C7, 0x226],
			[0x222F, 0x3D96, 0x1AA],
			[0x23D9, 0x0C6B, 0x47D],
			[0x2856, 0x7E39, 0x34],
			[0x288A, 0x10E8, 0x4DF],
		],
		"backup_checksum_segments": [
			[0x10E8, 0x4DF],
			[0x0C6B, 0x47D],
			[0x15C7, 0x226],
			[0x3D96, 0x1AA],
			[0x7E39, 0x34],
		],
	},
	"crystal": {
		"primary_check_1": 0x2008,
		"primary_data_start": 0x2009,
		"primary_data_end": 0x2B83,
		"primary_checksum": 0x2D0D,
		"primary_check_2": 0x2D0F,
		"backup_check_1": 0x1208,
		"backup_data_start": 0x1209,
		"backup_data_end": 0x1D83,
		"backup_checksum": 0x1F0D,
		"backup_check_2": 0x1F0F,
		"player_name": 0x200B,
		"party": 0x2865,
		"backup_segments": [
			[0x2009, 0x1209, 0xB7A],
		],
		"backup_checksum_segments": [
			[0x1209, 0xB7A],
		],
	},
}


## Imports one primary or backup save copy. A backup copy is normalized into the
## primary layout before the party fields are decoded.
static func import_bytes(
	game_id: StringName,
	rom_sha1: String,
	slot: int,
	raw: PackedByteArray,
	data: GameData = null
) -> Dictionary:
	var layout: Dictionary = _layout_for(game_id)
	var gate: Dictionary = _validate_request(game_id, rom_sha1, slot, raw, layout)
	if not gate["ok"]:
		return gate

	var selected: String = ""
	if _primary_is_valid(raw, layout):
		selected = "primary"
	elif _backup_is_valid(raw, layout):
		selected = "backup"
	else:
		return _failure("both cartridge save copies failed their markers or checksum")

	var canonical: PackedByteArray = raw.duplicate()
	if selected == "backup":
		canonical = _copy_backup_to_primary(canonical, layout)
		_write_markers_and_checksums(canonical, layout)

	var save: Gen2SaveData = _read_save(canonical, game_id, rom_sha1, slot, layout)
	if save == null:
		return _failure("the cartridge party data is malformed")
	if data != null:
		var validation: Dictionary = Gen2SaveValidator.validate(save, data)
		if not validation["ok"]:
			return _failure("cartridge party is invalid: %s" % validation["message"])

	return {
		"ok": true,
		"message": "",
		"save": save,
		"copy": selected,
		"raw": canonical,
	}


## Patches the mapped canonical fields into an existing valid cartridge image,
## then rewrites both cartridge copies and their checksums. The selected cache is
## required because party records include derived stats that must be regenerated.
static func export_bytes(
	save: Gen2SaveData,
	raw: PackedByteArray,
	data: GameData
) -> Dictionary:
	if save == null:
		return _failure("the save is missing")
	var layout: Dictionary = _layout_for(save.game_id)
	var gate: Dictionary = _validate_request(save.game_id, save.rom_sha1, save.slot, raw, layout)
	if not gate["ok"]:
		return gate
	if data == null:
		return _failure("the selected cartridge cache is required for export")
	var validation: Dictionary = Gen2SaveValidator.validate(save, data)
	if not validation["ok"]:
		return _failure("save cannot be exported: %s" % validation["message"])

	var selected: String = ""
	if _primary_is_valid(raw, layout):
		selected = "primary"
	elif _backup_is_valid(raw, layout):
		selected = "backup"
	else:
		return _failure("both cartridge save copies failed their markers or checksum")

	var output: PackedByteArray = raw.duplicate()
	if selected == "backup":
		output = _copy_backup_to_primary(output, layout)
	_write_save(output, save, data, layout)
	output = _copy_primary_to_backup(output, layout)
	_write_markers_and_checksums(output, layout)
	return {
		"ok": true,
		"message": "",
		"raw": output,
		"copy": selected,
	}


static func _layout_for(game_id: StringName) -> Dictionary:
	return LAYOUTS.get(String(game_id), {})


static func _validate_request(
	game_id: StringName,
	rom_sha1: String,
	slot: int,
	raw: PackedByteArray,
	layout: Dictionary
) -> Dictionary:
	if layout.is_empty():
		return _failure("unsupported cartridge game %s" % game_id)
	if RomRegistry.sha1_for(game_id) != rom_sha1:
		return _failure("the save belongs to an unsupported cartridge revision")
	if slot < 0 or slot >= Gen2SaveStore.SLOT_COUNT:
		return _failure("save slot %d is out of range" % slot)
	if raw.size() < SRAM_SIZE:
		return _failure("cartridge save is shorter than 32 KiB")
	return {"ok": true, "message": ""}


static func _primary_is_valid(raw: PackedByteArray, layout: Dictionary) -> bool:
	return raw[int(layout["primary_check_1"])] == SAVE_CHECK_VALUE_1 \
		and raw[int(layout["primary_check_2"])] == SAVE_CHECK_VALUE_2 \
		and _checksum_matches(raw, int(layout["primary_checksum"]), _primary_checksum_segments(layout))


static func _backup_is_valid(raw: PackedByteArray, layout: Dictionary) -> bool:
	return raw[int(layout["backup_check_1"])] == SAVE_CHECK_VALUE_1 \
		and raw[int(layout["backup_check_2"])] == SAVE_CHECK_VALUE_2 \
		and _checksum_matches(raw, int(layout["backup_checksum"]), layout["backup_checksum_segments"])


static func _primary_checksum_segments(layout: Dictionary) -> Array:
	return [[int(layout["primary_data_start"]), int(layout["primary_data_end"]) - int(layout["primary_data_start"])]]


static func _checksum_matches(raw: PackedByteArray, checksum_offset: int, segments: Array) -> bool:
	if checksum_offset < 0 or checksum_offset + 1 >= raw.size():
		return false
	var expected: int = _checksum(raw, segments)
	return _read_u16_le(raw, checksum_offset) == expected


static func _checksum(raw: PackedByteArray, segments: Array) -> int:
	var sum: int = 0
	for segment: Array in segments:
		var start: int = int(segment[0])
		var length: int = int(segment[1])
		for index: int in length:
			sum = (sum + int(raw[start + index])) & 0xFFFF
	return sum


static func _copy_backup_to_primary(raw: PackedByteArray, layout: Dictionary) -> PackedByteArray:
	for segment: Array in layout["backup_segments"]:
		var primary_start: int = int(segment[0])
		var backup_start: int = int(segment[1])
		var length: int = int(segment[2])
		for index: int in length:
			raw[primary_start + index] = raw[backup_start + index]
	return raw


static func _copy_primary_to_backup(raw: PackedByteArray, layout: Dictionary) -> PackedByteArray:
	for segment: Array in layout["backup_segments"]:
		var primary_start: int = int(segment[0])
		var backup_start: int = int(segment[1])
		var length: int = int(segment[2])
		for index: int in length:
			raw[backup_start + index] = raw[primary_start + index]
	return raw


static func _read_save(
	raw: PackedByteArray,
	game_id: StringName,
	rom_sha1: String,
	slot: int,
	layout: Dictionary
) -> Gen2SaveData:
	var party_start: int = int(layout["party"])
	if party_start + 8 + PARTY_LENGTH * PARTYMON_SIZE \
		+ PARTY_LENGTH * NAME_LENGTH + PARTY_LENGTH * MON_NAME_LENGTH > raw.size():
		return null
	var count: int = int(raw[party_start])
	if count < 1 or count > PARTY_LENGTH:
		return null
	var save := Gen2SaveData.new()
	save.game_id = game_id
	save.rom_sha1 = rom_sha1
	save.slot = slot
	save.player_name = Gen2Text.decode_fixed(raw, int(layout["player_name"]), NAME_LENGTH)

	var species_start: int = party_start + 1
	var terminator: int = int(raw[species_start + count])
	if terminator != 0xFF:
		return null
	var mons_start: int = party_start + 1 + PARTY_LENGTH + 1
	var ot_start: int = mons_start + PARTY_LENGTH * PARTYMON_SIZE
	var nickname_start: int = ot_start + PARTY_LENGTH * NAME_LENGTH
	for index: int in count:
		var species: int = int(raw[species_start + index])
		if species <= 0 or species == 0xFF:
			return null
		var mon: Gen2SaveMon = _read_mon(raw, mons_start + index * PARTYMON_SIZE)
		if mon == null or mon.species != species:
			return null
		mon.original_trainer = Gen2Text.decode_fixed(raw, ot_start + index * NAME_LENGTH, NAME_LENGTH)
		mon.nickname = Gen2Text.decode_fixed(
			raw, nickname_start + index * MON_NAME_LENGTH, MON_NAME_LENGTH
		)
		save.party.append(mon)
	return save


static func _read_mon(raw: PackedByteArray, start: int) -> Gen2SaveMon:
	if start < 0 or start + PARTYMON_SIZE > raw.size():
		return null
	var mon := Gen2SaveMon.new()
	mon.species = int(raw[start])
	mon.item = int(raw[start + 1])
	mon.moves = []
	mon.pp = []
	for index: int in Gen2SaveMon.MAX_MOVES:
		mon.moves.append(int(raw[start + 2 + index]))
	mon.ot_id = _read_u16_be(raw, start + 6)
	mon.exp = _read_u24_be(raw, start + 8)
	mon.stat_exp = {}
	for index: int in Gen2SaveMon.STAT_EXP_KEYS.size():
		mon.stat_exp[Gen2SaveMon.STAT_EXP_KEYS[index]] = _read_u16_be(raw, start + 11 + index * 2)
	mon.dvs = _read_u16_be(raw, start + 21)
	for index: int in Gen2SaveMon.MAX_MOVES:
		mon.pp.append(int(raw[start + 23 + index]) & PP_MASK)
	mon.happiness = int(raw[start + 27])
	mon.pokerus = int(raw[start + 28])
	var caught_time_level: int = int(raw[start + 29])
	var caught_gender_location: int = int(raw[start + 30])
	mon.caught_time = (caught_time_level >> 6) & 0x03
	mon.caught_level = caught_time_level & 0x3F
	mon.caught_gender = (caught_gender_location >> 7) & 0x01
	mon.caught_location = caught_gender_location & 0x7F
	mon.level = int(raw[start + 31])
	mon.status = int(raw[start + 32])
	mon.hp = _read_u16_be(raw, start + 34)
	return mon


static func _write_save(raw: PackedByteArray, save: Gen2SaveData, data: GameData, layout: Dictionary) -> void:
	_write_fixed_text(raw, int(layout["player_name"]), NAME_LENGTH, save.player_name)
	var party_start: int = int(layout["party"])
	raw[party_start] = save.party.size()
	var species_start: int = party_start + 1
	for index: int in PARTY_LENGTH:
		raw[species_start + index] = 0xFF if index >= save.party.size() else int((save.party[index] as Gen2SaveMon).species)
	var mons_start: int = party_start + 1 + PARTY_LENGTH + 1
	var ot_start: int = mons_start + PARTY_LENGTH * PARTYMON_SIZE
	var nickname_start: int = ot_start + PARTY_LENGTH * NAME_LENGTH
	for index: int in PARTY_LENGTH:
		if index >= save.party.size():
			_clear_range(raw, mons_start + index * PARTYMON_SIZE, PARTYMON_SIZE)
			_clear_range(raw, ot_start + index * NAME_LENGTH, NAME_LENGTH, Gen2Text.TERMINATOR)
			_clear_range(raw, nickname_start + index * MON_NAME_LENGTH, MON_NAME_LENGTH, Gen2Text.TERMINATOR)
			continue
		var mon: Gen2SaveMon = save.party[index]
		_write_mon(raw, mons_start + index * PARTYMON_SIZE, mon, data)
		_write_fixed_text(raw, ot_start + index * NAME_LENGTH, NAME_LENGTH, mon.original_trainer)
		_write_fixed_text(raw, nickname_start + index * MON_NAME_LENGTH, MON_NAME_LENGTH, mon.nickname)


static func _write_mon(raw: PackedByteArray, start: int, mon: Gen2SaveMon, data: GameData) -> void:
	var old_pp: Array = []
	for index: int in Gen2SaveMon.MAX_MOVES:
		old_pp.append(int(raw[start + 23 + index]) & PP_UP_MASK)
	raw[start] = mon.species
	raw[start + 1] = mon.item
	for index: int in Gen2SaveMon.MAX_MOVES:
		raw[start + 2 + index] = int(mon.moves[index])
	_write_u16_be(raw, start + 6, mon.ot_id)
	_write_u24_be(raw, start + 8, mon.exp)
	for index: int in Gen2SaveMon.STAT_EXP_KEYS.size():
		_write_u16_be(raw, start + 11 + index * 2, int(mon.stat_exp.get(Gen2SaveMon.STAT_EXP_KEYS[index], 0)))
	_write_u16_be(raw, start + 21, mon.dvs)
	for index: int in Gen2SaveMon.MAX_MOVES:
		raw[start + 23 + index] = old_pp[index] | (int(mon.pp[index]) & PP_MASK)
	raw[start + 27] = mon.happiness
	raw[start + 28] = mon.pokerus
	raw[start + 29] = (clampi(mon.caught_time, 0, 3) << 6) | clampi(mon.caught_level, 0, 63)
	raw[start + 30] = ((1 if mon.caught_gender > 0 else 0) << 7) | clampi(mon.caught_location, 0, 127)
	raw[start + 31] = mon.level
	raw[start + 32] = mon.status
	raw[start + 33] = 0
	_write_u16_be(raw, start + 34, mon.hp)
	var base: Dictionary = data.species(mon.species).get("stats", {})
	var hp: int = Gen2Stats.calculate(
		int(base.get("hp", 0)), Gen2Stats.hp_dv(mon.dvs), int(mon.stat_exp.get("hp", 0)), mon.level, true
	)
	_write_u16_be(raw, start + 36, hp)
	var stat_keys: Array = ["attack", "defense", "speed", "sp_attack", "sp_defense"]
	var dv_keys: Array = [
		Gen2Stats.attack_dv(mon.dvs), Gen2Stats.defense_dv(mon.dvs),
		Gen2Stats.speed_dv(mon.dvs), Gen2Stats.special_dv(mon.dvs), Gen2Stats.special_dv(mon.dvs),
	]
	var exp_keys: Array = ["attack", "defense", "speed", "special", "special"]
	for index: int in stat_keys.size():
		var value: int = Gen2Stats.calculate(
			int(base.get(stat_keys[index], 0)), dv_keys[index],
			int(mon.stat_exp.get(exp_keys[index], 0)), mon.level
		)
		_write_u16_be(raw, start + 38 + index * 2, value)


static func _write_fixed_text(
	raw: PackedByteArray, start: int, length: int, text: String
) -> void:
	var encoded: PackedByteArray = Gen2Text.encode(text)
	_clear_range(raw, start, length, Gen2Text.TERMINATOR)
	for index: int in mini(encoded.size(), length - 1):
		raw[start + index] = encoded[index]


static func _clear_range(
	raw: PackedByteArray, start: int, length: int, value: int = 0
) -> void:
	for index: int in length:
		raw[start + index] = value


static func _write_markers_and_checksums(raw: PackedByteArray, layout: Dictionary) -> void:
	raw[int(layout["primary_check_1"])] = SAVE_CHECK_VALUE_1
	raw[int(layout["primary_check_2"])] = SAVE_CHECK_VALUE_2
	raw[int(layout["backup_check_1"])] = SAVE_CHECK_VALUE_1
	raw[int(layout["backup_check_2"])] = SAVE_CHECK_VALUE_2
	_write_u16_le(raw, int(layout["primary_checksum"]), _checksum(raw, _primary_checksum_segments(layout)))
	_write_u16_le(raw, int(layout["backup_checksum"]), _checksum(raw, layout["backup_checksum_segments"]))


static func _read_u16_be(raw: PackedByteArray, offset: int) -> int:
	return (int(raw[offset]) << 8) | int(raw[offset + 1])


static func _read_u16_le(raw: PackedByteArray, offset: int) -> int:
	return int(raw[offset]) | (int(raw[offset + 1]) << 8)


static func _read_u24_be(raw: PackedByteArray, offset: int) -> int:
	return (int(raw[offset]) << 16) | (int(raw[offset + 1]) << 8) | int(raw[offset + 2])


static func _write_u16_be(raw: PackedByteArray, offset: int, value: int) -> void:
	raw[offset] = (value >> 8) & 0xFF
	raw[offset + 1] = value & 0xFF


static func _write_u16_le(raw: PackedByteArray, offset: int, value: int) -> void:
	raw[offset] = value & 0xFF
	raw[offset + 1] = (value >> 8) & 0xFF


static func _write_u24_be(raw: PackedByteArray, offset: int, value: int) -> void:
	raw[offset] = (value >> 16) & 0xFF
	raw[offset + 1] = (value >> 8) & 0xFF
	raw[offset + 2] = value & 0xFF


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
