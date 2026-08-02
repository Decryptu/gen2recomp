class_name Gen2Lz
extends RefCounted

## The LZ variant Generation 1 and 2 use for every compressed graphic.
##
## A stream is a run of commands, terminated by $FF. Each command byte packs a
## 3-bit opcode and a length; opcode 7 escapes to a long form that borrows two
## more length bits and a following byte, so a single command can span up to
## 1024 bytes.
##
##   000 literal    copy the next N bytes verbatim
##   001 iterate    repeat the next byte N times
##   010 alternate  repeat the next two bytes, alternating, N times
##   011 zero       N zero bytes
##   100 repeat     copy N bytes already written, forwards
##   101 flipped    same, with each byte's bits reversed
##   110 reversed   same, but reading backwards from the source
##
## The three back-references take an offset that is either a one-byte distance
## back from the write head (high bit set) or a two-byte absolute position from
## the start of the output (high bit clear). Sources may overlap the bytes being
## written, which is how the format expresses runs — so the copy has to be
## byte-at-a-time, not a slice.
##
## The bit-reversing opcode exists because these streams encode 2bpp tiles: a
## mirrored sprite half is the same bytes with their bits flipped.

enum Op {
	LITERAL,
	ITERATE,
	ALTERNATE,
	ZERO,
	REPEAT,
	FLIPPED,
	REVERSED,
	LONG,
}

const TERMINATOR: int = 0xFF
const MAX_SHORT_LENGTH: int = 32
const LONG_OFFSET_MASK: int = 0x80

## No Gen 2 graphic decompresses to anything near this. It only bounds the
## damage when a bad offset points at data that happens to decode forever.
const MAX_OUTPUT: int = 0x4000

## Set when the last decompression ran off the end of the data, hit an
## impossible back-reference, or overran [constant MAX_OUTPUT].
var failed: bool = false

## Bytes of compressed input the last successful decompression consumed,
## including the terminator.
var consumed: int = 0

static var _reversed_bits: PackedByteArray = PackedByteArray()


## Decompresses the stream starting at [param offset]. Returns the decompressed
## bytes, or an empty array on failure — check [member failed] to tell that
## apart from a legitimately empty stream.
func decompress(data: PackedByteArray, offset: int) -> PackedByteArray:
	failed = false
	consumed = 0

	var out: PackedByteArray = PackedByteArray()
	var pos: int = offset
	var size: int = data.size()

	while true:
		if pos < 0 or pos >= size:
			return _fail()

		var command: int = data[pos]
		pos += 1
		if command == TERMINATOR:
			consumed = pos - offset
			return out

		var op: int = command >> 5
		var length: int = (command & 0x1F) + 1
		if op == Op.LONG:
			if pos >= size:
				return _fail()
			op = (command >> 2) & 0x07
			length = (((command & 0x03) << 8) | data[pos]) + 1
			pos += 1

		match op:
			Op.LITERAL:
				if pos + length > size:
					return _fail()
				out.append_array(data.slice(pos, pos + length))
				pos += length

			Op.ITERATE:
				if pos >= size:
					return _fail()
				var value: int = data[pos]
				pos += 1
				for _i: int in length:
					out.append(value)

			Op.ALTERNATE:
				if pos + 2 > size:
					return _fail()
				var even: int = data[pos]
				var odd: int = data[pos + 1]
				pos += 2
				for i: int in length:
					out.append(odd if i & 1 else even)

			Op.ZERO:
				for _i: int in length:
					out.append(0)

			_:
				if pos >= size:
					return _fail()
				var source: int = 0
				var high: int = data[pos]
				pos += 1
				if high & LONG_OFFSET_MASK:
					source = out.size() - (high & 0x7F) - 1
				else:
					if pos >= size:
						return _fail()
					source = (high << 8) | data[pos]
					pos += 1

				if source < 0 or source >= out.size():
					return _fail()

				var table: PackedByteArray = _bit_reversal_table()
				for i: int in length:
					var from: int = source - i if op == Op.REVERSED else source + i
					if from < 0 or from >= out.size():
						return _fail()
					out.append(table[out[from]] if op == Op.FLIPPED else out[from])

		if out.size() > MAX_OUTPUT:
			return _fail()

	return out


## Convenience for callers that only care whether it worked.
static func unpack(data: PackedByteArray, offset: int) -> PackedByteArray:
	return Gen2Lz.new().decompress(data, offset)


func _fail() -> PackedByteArray:
	failed = true
	consumed = 0
	return PackedByteArray()


static func _bit_reversal_table() -> PackedByteArray:
	if not _reversed_bits.is_empty():
		return _reversed_bits

	var table: PackedByteArray = PackedByteArray()
	table.resize(256)
	for value: int in 256:
		var flipped: int = 0
		for bit: int in 8:
			if value & (1 << bit):
				flipped |= 1 << (7 - bit)
		table[value] = flipped
	_reversed_bits = table
	return _reversed_bits
