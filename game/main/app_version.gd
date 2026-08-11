class_name Gen2AppVersion
extends RefCounted

## Host application version. Keep this numeric value aligned with export metadata.
const VERSION: String = "0.1.0"
const CHANNEL: String = "development"


static func display() -> String:
	return "%s (%s)" % [VERSION, CHANNEL]
