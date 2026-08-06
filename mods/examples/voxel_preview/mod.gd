extends RefCounted

## Everything this mod does. It registers a renderer and returns; it never
## touches a scene node, and the host decides when to build one.


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_world_renderer(
		manifest.id, load("%s/renderer.gd" % manifest.directory), "Voxel"
	)
