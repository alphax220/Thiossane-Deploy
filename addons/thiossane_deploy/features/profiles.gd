class_name ThiossaneDeployProfiles
extends RefCounted
## Profils de déploiement nommés — plateformes + presets.
## Copyright (c) 2026 Teranga Game Studio. Tous droits réservés.

const PROFILES_PATH := "user://thiossane_deploy_profiles.json"


static func load_all() -> Dictionary:
	## { "Nom profil": {web, windows, android, preset_web, preset_windows, preset_android} }
	if not FileAccess.file_exists(PROFILES_PATH):
		return {}
	var f := FileAccess.open(PROFILES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


static func save_all(profiles: Dictionary) -> void:
	var f := FileAccess.open(PROFILES_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Thiossane Deploy] Impossible d’écrire les profils.")
		return
	f.store_string(JSON.stringify(profiles))
	f.close()


static func save_profile(name: String, data: Dictionary, existing: Dictionary = {}) -> Dictionary:
	var n := name.strip_edges()
	if n == "":
		return existing
	var profiles := existing if not existing.is_empty() else load_all()
	profiles[n] = {
		"web": bool(data.get("web", false)),
		"windows": bool(data.get("windows", false)),
		"android": bool(data.get("android", false)),
		"preset_web": str(data.get("preset_web", "")),
		"preset_windows": str(data.get("preset_windows", "")),
		"preset_android": str(data.get("preset_android", "")),
	}
	save_all(profiles)
	return profiles


static func delete_profile(name: String, existing: Dictionary = {}) -> Dictionary:
	var profiles := existing if not existing.is_empty() else load_all()
	profiles.erase(name)
	save_all(profiles)
	return profiles


static func capture_from_ui(
	web_on: bool, win_on: bool, and_on: bool,
	preset_web_name: String, preset_win_name: String, preset_and_name: String
) -> Dictionary:
	return {
		"web": web_on,
		"windows": win_on,
		"android": and_on,
		"preset_web": preset_web_name,
		"preset_windows": preset_win_name,
		"preset_android": preset_and_name,
	}
