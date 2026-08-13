extends RefCounted

## Everything this mod does. It registers a renderer and returns; it never
## touches a scene node, and the host decides when to build one.


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_world_renderer(
		manifest.id, load("%s/renderer.gd" % manifest.directory), "Voxel"
	)
	## A setting is described, not drawn: the start menu's MODS entry and the
	## launcher's mods page are both built from this one registration, and the
	## renderer reads the value back through the host.
	host.register_option(manifest.id, {
		"key": "pitch", "label": "CAMERA",
		"values": [25.0, 50.19, 75.0], "labels": ["LOW", "MID", "HIGH"],
		"default": 50.19,
	})
	## A setting that is a press rather than a ladder: nothing is stored, and
	## the mod acts on option_changed.
	host.register_option(manifest.id, {
		"key": "recentre", "label": "RECENTRE", "kind": Gen2ModHost.OPTION_BUTTON,
		"press_label": "NOW",
	})
	## Controls of the mod's own, declared rather than read off raw keycodes: the
	## host binds them, the launcher's controls card rebinds them, and the
	## on-screen controller can carry them, so a phone player can reach the
	## camera. A default already on one of the cartridge's eight is dropped and
	## reported, which is what a default on W would be.
	host.register_action(manifest.id, {
		"key": "pitch_down", "label": "Camera down",
		"default": [{"kind": "key", "code": KEY_R}],
	})
	host.register_action(manifest.id, {
		"key": "pitch_up", "label": "Camera up",
		"default": [{"kind": "key", "code": KEY_F}],
	})
