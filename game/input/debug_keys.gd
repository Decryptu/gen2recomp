class_name Gen2DebugKeys
extends RefCounted

## Whether the development shortcuts and readouts are live.
##
## The game screens carry scaffolding that reaches parts of the world no
## cartridge control does: fishing rods by number, the phone list, a renderer
## switch, a snapshot write, and battle drivers that stand in for a battle menu.
## They are how the world is inspected without a save file, and they are not
## controls a player should find.
##
## The editor, a headless run and a debug export all answer true here, which is
## every context those shortcuts exist for; a release export answers false and
## offers exactly the eight buttons the hardware had. Each shortcut's method
## stays public either way, so the preview tools drive the same paths in a
## release build without a key press.

static func enabled() -> bool:
	return OS.is_debug_build()
