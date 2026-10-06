class_name ThiossaneConfig
extends RefCounted
## Config + tokens sécurisés — format unifié (v1.9.2+)
## Compatible avec le stockage open_encrypted + store_var du dock historique.
## Migre aussi l’ancien format open_encrypted_with_pass + JSON.

const C = preload("res://addons/thiossane_deploy/core/constants.gd")

## Clé dérivée machine (identique au dock historique pour ne pas invalider les sessions).
static func derive_secure_key() -> PackedByteArray:
	var seed := str(OS.get_unique_id()) + "|" + OS.get_name() + "|" + OS.get_model_name() + "|thiossane-v1"
	return seed.sha256_buffer()


## Ancienne clé (v1.7 core non branché) — pour migration uniquement.
static func _legacy_passphrase() -> String:
	var machine := OS.get_unique_id()
	if machine.is_empty():
		machine = "thiossane-fallback-key"
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("thiossane-deploy-v1|" + machine).to_utf8_buffer())
	return ctx.finish().hex_encode()


static func load_secure_tokens() -> Dictionary:
	## Retourne {access_token, refresh_token} ou vide.
	var out := {"access_token": "", "refresh_token": ""}

	if not FileAccess.file_exists(C.SECURE_TOKEN_PATH):
		return _migrate_from_plain_cfg(out)

	# 1) Format actuel : open_encrypted + store_var (clé PackedByteArray 32)
	var f := FileAccess.open_encrypted(C.SECURE_TOKEN_PATH, FileAccess.READ, derive_secure_key())
	if f != null:
		var payload = f.get_var()
		f.close()
		if typeof(payload) == TYPE_DICTIONARY:
			out.access_token = str(payload.get("access_token", ""))
			out.refresh_token = str(payload.get("refresh_token", ""))
			return out

	# 2) Ancien format core : open_encrypted_with_pass + JSON
	var f2 := FileAccess.open_encrypted_with_pass(C.SECURE_TOKEN_PATH, FileAccess.READ, _legacy_passphrase())
	if f2 != null:
		var txt := f2.get_as_text()
		f2.close()
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			out.access_token = str(parsed.get("access_token", ""))
			out.refresh_token = str(parsed.get("refresh_token", ""))
			# Réécrit au format unifié
			if out.access_token != "" or out.refresh_token != "":
				save_secure_tokens(out.access_token, out.refresh_token)
			return out

	# 3) Dernier recours : tokens en clair dans le .cfg
	return _migrate_from_plain_cfg(out)


static func _migrate_from_plain_cfg(out: Dictionary) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(C.CONFIG_PATH) != OK:
		return out
	var at := str(cfg.get_value(C.CONFIG_SECTION, "access_token", ""))
	var rt := str(cfg.get_value(C.CONFIG_SECTION, "refresh_token", ""))
	if at == "" and rt == "":
		return out
	out.access_token = at
	out.refresh_token = rt
	save_secure_tokens(at, rt)
	cfg.set_value(C.CONFIG_SECTION, "access_token", "")
	cfg.set_value(C.CONFIG_SECTION, "refresh_token", "")
	cfg.save(C.CONFIG_PATH)
	return out


static func save_secure_tokens(access: String, refresh: String) -> bool:
	var f := FileAccess.open_encrypted(C.SECURE_TOKEN_PATH, FileAccess.WRITE, derive_secure_key())
	if f == null:
		return false
	f.store_var({"access_token": access, "refresh_token": refresh})
	f.close()
	return true


static func clear_secure_tokens() -> void:
	if FileAccess.file_exists(C.SECURE_TOKEN_PATH):
		DirAccess.remove_absolute(C.SECURE_TOKEN_PATH)


static func load_config() -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {
		"api_base": "https://api.thiossane.store/api",
		"email": "",
		"store_base": "https://www.thiossane.store/",
		"lang": "fr",
		"theme": "default",
		"music_path": "",
		"music_loop": true,
		"music_volume_db": -6.0,
	}
	if cfg.load(C.CONFIG_PATH) != OK:
		return out
	out.api_base = str(cfg.get_value(C.CONFIG_SECTION, "api_base", out.api_base))
	if out.api_base.strip_edges().trim_suffix("/") in ["http://127.0.0.1:8000/api", "http://localhost:8000/api"]:
		out.api_base = "https://api.thiossane.store/api"
	out.email = str(cfg.get_value(C.CONFIG_SECTION, "email", ""))
	out.store_base = str(cfg.get_value(C.CONFIG_SECTION, "store_base", ""))
	out.lang = str(cfg.get_value(C.CONFIG_SECTION, "lang", "fr"))
	out.theme = str(cfg.get_value(C.CONFIG_SECTION, "theme", "default"))
	out.music_path = str(cfg.get_value(C.CONFIG_SECTION, "music_path", ""))
	out.music_loop = bool(cfg.get_value(C.CONFIG_SECTION, "music_loop", true))
	out.music_volume_db = float(cfg.get_value(C.CONFIG_SECTION, "music_volume_db", -6.0))
	return out


static func save_config(values: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(C.CONFIG_PATH)
	for k in values:
		# Ne jamais écrire les tokens en clair
		if k == "access_token" or k == "refresh_token":
			continue
		cfg.set_value(C.CONFIG_SECTION, k, values[k])
	# Garantir l’absence de tokens en clair
	cfg.set_value(C.CONFIG_SECTION, "access_token", "")
	cfg.set_value(C.CONFIG_SECTION, "refresh_token", "")
	cfg.save(C.CONFIG_PATH)
