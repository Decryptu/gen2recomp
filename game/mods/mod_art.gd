class_name Gen2ModArt
extends RefCounted

## A mod's own pictures: the icon the launcher draws beside its name, and the
## thumbnail a listing site shows for it.
##
## Both are optional and neither is declared for the usual mod: dropping
## `icon.png` beside `mod.json` is the whole of it, because a convention an
## author has to read a document to obey is one most will not. A manifest may
## still name another path, which is what a mod keeping its art in a
## subdirectory or inside a pack needs.
##
## The game never draws a thumbnail. It is resolved here anyway so one rule
## covers both files and a packaging script has one place to ask.

## Tried in order, and the first that exists wins. PNG leads because an icon is
## 32x32 pixel art off the cartridge, where lossy compression only costs.
const ICON_NAMES: Array = ["icon.png", "icon.webp", "icon.jpg", "icon.jpeg"]
## The website's picture, 1280x720. `thumb` is here because half of everyone
## types it.
const THUMBNAIL_NAMES: Array = [
	"thumbnail.webp", "thumb.webp", "thumbnail.png", "thumb.png", "thumbnail.jpg",
]

## What an icon is drawn from: the party-icon grid the cartridge itself uses, so
## a mod's icon sits beside the game's own art without resampling.
const ICON_SIDE: int = 32
## An icon is a few hundred bytes of pixel art. Anything larger is a photograph
## someone renamed, and refusing it here is cheaper than decoding it.
const MAX_ICON_BYTES: int = 1024 * 1024
## Room for an author who drew at 8x and never scaled down, and a stop well
## before a decoded image costs real memory on a phone.
const MAX_ICON_SIDE: int = 512
## Icons fetched from a followed index, one file per URL. Kept beside the feed
## cache and for the same reason: a listing browsed offline still has faces.
const CACHE_DIRECTORY: String = "user://mod_icon_cache"

## Icon bytes to the texture decoded from them, because the launcher rebuilds
## its whole list on any change and would otherwise decode every icon again.
## Keyed by content rather than by path: an icon file is a kilobyte, so reading
## it back is nothing beside decoding it, and a reinstalled mod cannot be drawn
## with the picture the version before it had. Modification time is not enough
## for that, since a replace inside the same second keeps it.
static var _textures: Dictionary = {}


## The icon file for [param manifest], or an empty string for a mod without one.
static func icon_path(manifest: Gen2ModManifest) -> String:
	if manifest == null:
		return ""
	return locate(manifest.directory, ICON_NAMES, manifest.icon)


## The thumbnail file for [param manifest], or an empty string. See the class
## note: nothing in the game reads this, and a packaging script does.
static func thumbnail_path(manifest: Gen2ModManifest) -> String:
	if manifest == null:
		return ""
	return locate(manifest.directory, THUMBNAIL_NAMES, manifest.thumbnail)


## The first of [param names] that exists in [param folder], or [param declared]
## when the manifest named one. Pure enough to test with a temporary directory
## and no mod around it.
static func locate(folder: String, names: Array, declared: String = "") -> String:
	if folder.is_empty():
		return ""
	if not declared.is_empty():
		var named: String = "%s/%s" % [folder, declared]
		return named if FileAccess.file_exists(named) else ""
	for candidate: String in names:
		var path: String = "%s/%s" % [folder, candidate]
		if FileAccess.file_exists(path):
			return path
	return ""


## Reads [param path] as an icon, or null for a file that is missing, too big,
## or not an image. A mod's icon comes from a stranger's archive, so every
## failure here is an ordinary answer rather than an error worth printing.
static func icon_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var key: String = _digest(bytes)
	if _textures.has(key):
		return _textures[key]
	var texture: Texture2D = _decode(bytes)
	if texture != null:
		_textures[key] = texture
	return texture


## The same for bytes that never became a file, which is what a fetched icon is
## before it is cached.
static func icon_texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	return _decode(bytes)


## Where a fetched icon is kept. Named by hash of its URL, the way
## [method Gen2ModIndex.cache_path] names a feed, because a URL is not a
## filename.
static func cache_path(url: String, directory: String = CACHE_DIRECTORY) -> String:
	return "%s/%s" % [directory, url.sha256_text().substr(0, 32)]


## Keeps [param bytes] as the icon for [param url]. Only bytes that decoded are
## worth keeping, so the caller checks first and a broken server cannot fill the
## cache with rubbish that is retried from disk forever.
static func cache_icon(url: String, bytes: PackedByteArray, directory: String = CACHE_DIRECTORY) -> bool:
	if bytes.size() > MAX_ICON_BYTES:
		return false
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(cache_path(url, directory), FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


## The cached icon for [param url], or null when it was never fetched.
static func cached_icon(url: String, directory: String = CACHE_DIRECTORY) -> Texture2D:
	return icon_texture(cache_path(url, directory))


## True when [param url] is worth fetching an icon from: https, like every other
## address this project reads, and not already on disk.
static func wants_fetch(url: String, directory: String = CACHE_DIRECTORY) -> bool:
	if not Gen2ModIndex.is_downloadable(url):
		return false
	return not FileAccess.file_exists(cache_path(url, directory))


## Content hash, since [PackedByteArray] has no digest of its own and a path
## with a modification time is not one: a mod replaced inside the same second
## keeps both.
static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _decode(bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty() or bytes.size() > MAX_ICON_BYTES:
		return null
	var image := Image.new()
	# Format by magic rather than by extension, because a fetched icon has no
	# name and a file's name is the author's guess at its own contents.
	var loaded: int = FAILED
	if bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		loaded = image.load_png_from_buffer(bytes)
	elif bytes.slice(0, 4) == PackedByteArray([0x52, 0x49, 0x46, 0x46]):
		loaded = image.load_webp_from_buffer(bytes)
	elif bytes.slice(0, 3) == PackedByteArray([0xFF, 0xD8, 0xFF]):
		loaded = image.load_jpg_from_buffer(bytes)
	if loaded != OK or image.is_empty():
		return null
	if image.get_width() > MAX_ICON_SIDE or image.get_height() > MAX_ICON_SIDE:
		return null
	return ImageTexture.create_from_image(image)
