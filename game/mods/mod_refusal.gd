class_name Gen2ModRefusal
extends RefCounted

## Why a mod was refused, said to a player rather than to a log.
##
## One table for every reason the mod layer produces: the installer's, the index
## feed's, the manifest reader's and the host's registrations alike. The launcher
## and the index dialog each used to keep their own, covering different halves of
## the same set, so a mod refused through the wrong screen showed a raw
## StringName. A new reason is worded here, once, and both screens have it.
##
## Anything unworded falls back to the reason itself, which is a poor line but an
## honest one: it names something a search finds.

## Reasons that read the same wherever they come from. A [code]%s[/code] is
## filled with the result's own [code]detail[/code]; a reason wanting anything
## else is a branch in [method text].
const WORDING: Dictionary = {
	# Choosing and reading the archive.
	&"not_a_zip": "%s is not a .zip archive.",
	&"archive_not_found": "%s could not be read.",
	&"archive_unreadable": "That archive could not be opened.",
	&"archive_is_empty": "That archive is empty.",
	&"archive_holds_more_than_one_folder": "The archive must hold a single mod folder.",
	&"archive_too_large": "That archive is too large to be a mod.",
	&"archive_too_many_entries": "That archive is too large to be a mod.",
	&"unsafe_archive_entry": "The archive tries to write outside the mod folder (%s).",

	# What the manifest says.
	&"missing_manifest": "The mod has no %s.",
	&"unreadable_manifest": "The mod's %s could not be read.",
	&"invalid_manifest": "The mod's %s is not valid JSON.",
	&"invalid_id": "\"%s\" is not a usable mod id.",
	&"invalid_mod_version": "\"%s\" is not a semantic mod version.",
	&"invalid_dependencies": "%s's dependencies must be an id-to-range object.",
	&"invalid_dependency": "\"%s\" is not a usable dependency id.",
	&"invalid_dependency_range": "The dependency range is invalid (%s).",
	&"invalid_games": "%s's games must be a list of cartridge ids.",
	&"invalid_game": "\"%s\" is not a usable cartridge id.",
	&"missing_entry": "The mod names no entry script.",
	&"entry_not_gdscript": "A mod's entry script has to be GDScript (%s).",
	&"entry_escapes_mod": "The entry script points outside the mod folder (%s).",

	# Writing it into place.
	&"could_not_create_mod_directory": "The mod folder could not be created.",
	&"could_not_stage_archive": "The download could not be written to disk.",
	&"could_not_write_mod_file": "%s could not be written.",
	&"already_installed": "It is already installed.",

	# Running it.
	&"missing_entry_script": "The entry script %s is missing.",
	&"entry_not_a_script": "The entry %s is not a script.",
	&"entry_has_no_register": "The entry script %s has no register() function.",
	&"duplicate_mod_id": "More than one installed mod declares the id \"%s\".",
	&"missing_dependency": "A required mod is not installed (%s).",
	&"dependency_disabled": "A required mod is switched off (%s).",
	&"incompatible_dependency": "A required mod has an incompatible version (%s).",
	&"dependency_failed": "A required mod failed to load (%s).",
	&"dependency_cycle": "The mod is part of a dependency cycle (%s).",
	&"incompatible_game": "That mod is not for %s.",
	&"unknown_mod_save_owner": "That mod cannot write another mod's save data.",
	&"missing_mod_save": "There is no active save for the mod to write.",
	&"invalid_mod_save_id": "That mod id cannot own save data.",
	&"mod_save_too_large": "That mod's save data is larger than 64 KiB.",

	# What it registered.
	&"invalid_renderer": "A mod registered a renderer with no id or script.",
	&"renderer_not_instantiable": "%s's renderer could not be created.",
	&"renderer_not_a_node": "%s's renderer is not a Node.",
	&"renderer_missing_methods": "A renderer is missing methods it needs (%s).",
	&"duplicate_renderer": "Two mods both registered the renderer \"%s\".",
	&"unknown_renderer": "There is no renderer called \"%s\".",
	&"unknown_menu": "There is no menu called \"%s\".",
	&"invalid_menu_entry": "A mod registered a menu entry with no id.",
	&"menu_entry_missing_label": "%s's menu entry has no label.",
	&"duplicate_menu_entry": "Two mods both registered the menu entry \"%s\".",
	&"invalid_option": "%s registered a setting with no key.",
	&"option_missing_label": "The setting %s has no label.",
	&"option_missing_values": "The setting %s offers no values.",
	&"option_labels_mismatch": "The setting %s has a label for only some of its values.",
	&"duplicate_option": "The setting %s was registered twice.",
	&"unknown_option": "There is no setting called %s.",
	&"invalid_option_value": "That is not one of %s's values.",
	&"option_not_written": "Settings could not be written to %s.",
	&"unknown_option_kind": "There is no setting kind called \"%s\".",
	&"option_is_not_a_button": "The setting %s is a ladder, not a button.",
	&"invalid_action": "%s registered a control with no key.",
	&"action_missing_label": "The control %s has no label.",
	&"duplicate_action": "The control %s was registered twice.",
	&"action_default_taken": "A mod's control defaults to a key the game already uses (%s).",
	&"unknown_channel": "There is no event channel called \"%s\".",
	&"invalid_subscriber": "A mod subscribed with no id.",
	&"invalid_subscriber_handler": "%s subscribed with nothing to call.",
	&"duplicate_subscriber": "%s subscribed to the same channel twice.",
	&"unknown_content_kind": "There is no content kind called \"%s\".",
	&"duplicate_content": "Two mods both claimed the same content (%s).",
	&"empty_content_patch": "A %s patch changes nothing.",
	&"invalid_effect": "%s is not a move effect number.",
	&"reserved_effect": "Move effect %s is one the engine reads back and cannot be replaced.",
	&"empty_effect": "Move effect %s was registered with no commands.",
	&"unknown_effect_command": "A move effect names steps that do not exist (%s).",
	&"invalid_effect_command": "A mod registered an effect command with no name.",
	&"invalid_effect_handler": "The effect command \"%s\" was registered with nothing to call.",
	&"reserved_effect_command": "\"%s\" is one of the engine's own steps.",
	&"duplicate_move_effect": "Two mods both claimed the same move effect (%s).",

	# Index feeds.
	&"empty_index_url": "Enter an index address first.",
	&"index_url_not_https": "An index must be an https address.",
	&"index_not_json": "That address did not return an index.",
	&"index_has_no_mods": "That index lists no mods.",
	&"index_too_large": "That index is too large to read.",
	&"unexpected_mod_id": "The download is a different mod (%s).",
}


## What to show a player for [param result], which is any
## [code]{ok: false, reason, detail}[/code] the mod layer answers with.
static func text(result: Dictionary) -> String:
	var reason: StringName = StringName(result.get("reason", &""))
	var detail: String = String(result.get("detail", ""))
	match reason:
		# Two reasons need something other than the detail: a filename rather
		# than the whole path, and a version this build can name itself.
		&"not_a_zip", &"archive_not_found":
			detail = detail.get_file()
		&"archive_has_no_manifest", &"missing_manifest", &"unreadable_manifest", \
		&"invalid_manifest":
			# The detail is a path; the filename is what a player recognises.
			detail = Gen2ModManifest.FILENAME
		&"unsupported_api_version":
			# The detail already names both versions.
			return "That mod was built for a different host: %s." % detail
		&"unsupported_index_schema":
			return "That index uses format %s; this build reads %d." % [
				detail, Gen2ModIndex.SCHEMA_VERSION,
			]
	if not WORDING.has(reason):
		return "%s %s" % [reason if reason != &"" else &"refused", detail]
	var wording: String = WORDING[reason]
	return wording % detail if wording.contains("%s") else wording
