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
