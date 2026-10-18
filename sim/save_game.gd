class_name SaveGame
extends RefCounted
## user://save.json, version 2. A newer version is left untouched.
## Version 1 gains an empty garage. Any other older version is copied aside.

const VERSION := 2
const DEFAULT_PATH := "user://save.json"
const DEFAULT_BACKUP_PATH := "user://save.backup.json"

const STATUS_MISSING := "missing"
const STATUS_OK := "ok"
const STATUS_NEWER := "newer"
const STATUS_OLDER := "older"
const STATUS_INVALID := "invalid"


static func backup_path_for(path: String) -> String:
	if path == DEFAULT_PATH:
		return DEFAULT_BACKUP_PATH
	return "%s.bak" % path


static func load_from_file(path: String, backup_path: String = "") -> Dictionary:
	var outcome := {
		"status": STATUS_MISSING,
		"error": "",
		"migrated": false,
		"settings": {},
		"garage": {"reputation": 0, "unlocked_ids": []},
		"championship": null,
	}
	if not FileAccess.file_exists(path):
		return outcome
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		outcome["status"] = STATUS_INVALID
		outcome["error"] = "Save file could not be read."
		return outcome
	var data := parsed as Dictionary
	var version := int(data.get("version", 0))
	if version > VERSION:
		outcome["status"] = STATUS_NEWER
		outcome["error"] = "Save file is from a newer version (%s). It was left unchanged." % version
		return outcome
	if version < VERSION and version != 1:
		var backup := backup_path if backup_path != "" else backup_path_for(path)
		var copied := _copy_file(path, backup)
		if copied != OK:
			outcome["status"] = STATUS_INVALID
			outcome["error"] = "Could not back up an older save."
			return outcome
		outcome["status"] = STATUS_OLDER
		outcome["error"] = "Save file is from version %s and was moved aside." % version
		return outcome
	outcome["status"] = STATUS_OK
	outcome["migrated"] = version == 1
	outcome["garage"] = _garage_from(data)
	var settings: Variant = data.get("settings", {})
	if settings is Dictionary:
		outcome["settings"] = (settings as Dictionary).duplicate(true)
	var championship: Variant = data.get("championship", null)
	if championship is Dictionary:
		outcome["championship"] = (championship as Dictionary).duplicate(true)
	return outcome


static func write_file(
	path: String,
	settings: Dictionary,
	championship: Variant,
	garage: Dictionary = {}
) -> Error:
	_ensure_parent(path)
	var payload := {
		"version": VERSION,
		"settings": {
			"time_scale": float(settings.get("time_scale", 1.0)),
			"muted": bool(settings.get("muted", false)),
		},
		"garage": _garage_from({"garage": garage}),
		"championship": championship,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.store_string("\n")
	file.close()
	return OK


static func _garage_from(data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("garage", {})
	var source: Dictionary = raw if raw is Dictionary else {}
	var ids: Array = []
	var raw_ids: Variant = source.get("unlocked_ids", [])
	if raw_ids is Array:
		for raw_id in raw_ids:
			var id := str(raw_id)
			if id != "" and not ids.has(id):
				ids.append(id)
	return {
		"reputation": maxi(int(source.get("reputation", 0)), 0),
		"unlocked_ids": ids,
	}


static func _copy_file(source: String, destination: String) -> Error:
	if not FileAccess.file_exists(source):
		return ERR_FILE_NOT_FOUND
	var bytes := FileAccess.get_file_as_bytes(source)
	_ensure_parent(destination)
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.close()
	return OK


static func _ensure_parent(path: String) -> void:
	var parent := path.get_base_dir()
	if parent == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
