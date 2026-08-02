extends Control

## Boot scene. Right now it is a scaffold that proves the toolchain end to end:
## it prints the ROM allowlist on start, so `--headless --quit-after` is a real
## smoke test, and it draws enough to be worth a screenshot.
##
## Replace this with the launcher (game tabs / ROM import / save slots / mods)
## once those screens exist.

@onready var _status: Label = %Status


func _ready() -> void:
	var lines: PackedStringArray = []
	for id: StringName in RomRegistry.ORDER:
		lines.append("  %-8s %s" % [RomRegistry.title_for(id), RomRegistry.sha1_for(id)])

	print("gen2recomp — supported cartridges:")
	print("\n".join(lines))

	_status.text = "No ROM imported\n\nSupported: %s" % ", ".join(_titles())


func _titles() -> PackedStringArray:
	var out: PackedStringArray = []
	for id: StringName in RomRegistry.ORDER:
		out.append(RomRegistry.title_for(id))
	return out
