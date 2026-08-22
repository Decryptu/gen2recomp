class_name Gen2AppVersion
extends RefCounted

## Host application version. Keep this numeric value aligned with export metadata.
const VERSION: String = "0.1.0"
const CHANNEL: String = "development"

## Where the project lives, stated once: the release check derives its pages
## from [constant REPOSITORY], and the about page points a bug report at the
## tracker or at the chat.
const REPOSITORY: String = "https://github.com/Decryptu/pokerecomp"
const ISSUES: String = "https://github.com/Decryptu/pokerecomp/issues/new"
const DISCORD: String = "https://discord.gg/twkrHkHprk"


static func display() -> String:
	return "%s (%s)" % [VERSION, CHANNEL]
