class_name ThiossaneDeployCore
extends RefCounted
## Export CLI, ZIP, checksum, état d’upload persistant, validation presets.
## Copyright (c) 2026 Teranga Game Studio. Tous droits réservés.

const UPLOAD_STATE_PATH := "user://thiossane_upload_state.json"
const MAX_BUILD_BYTES := 512 * 1024 * 1024
const MAX_BUILD_MB := 512
const UPLOAD_CHUNK_SIZE := 2 * 1024 * 1024
const MAX_UPLOAD_WARN_MB := 200.0


# ── Checksum SHA-256 ──────────────────────────────────────────────────────────

static func file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	const BUF := 1024 * 1024
	while not f.eof_reached():
		var chunk: PackedByteArray = f.get_buffer(BUF)
		if chunk.size() > 0:
			ctx.update(chunk)
	f.close()
	var digest := ctx.finish()
	return digest.hex_encode()


static func file_size_bytes(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


# ── État upload persistant (reprise après crash éditeur) ─────────────────────

static func save_upload_state(state: Dictionary) -> void:
	var f := FileAccess.open(UPLOAD_STATE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Thiossane Deploy] Impossible d’écrire l’état upload: %s" % UPLOAD_STATE_PATH)
		return
	f.store_string(JSON.stringify(state))
	f.close()


static func load_upload_state() -> Dictionary:
	if not FileAccess.file_exists(UPLOAD_STATE_PATH):
		return {}
	var f := FileAccess.open(UPLOAD_STATE_PATH, FileAccess.READ)
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


static func clear_upload_state() -> void:
	if FileAccess.file_exists(UPLOAD_STATE_PATH):
		DirAccess.remove_absolute(UPLOAD_STATE_PATH)


static func build_upload_state(
	file_path: String,
	platform: String,
	game_id: int,
	version: String,
	session_uuid: String,
	chunk_index: int,
	chunks_total: int,
	chunk_size: int,
	total_bytes: int,
	sha256: String
) -> Dictionary:
	return {
		"file_path": file_path,
		"platform": platform,
		"game_id": game_id,
		"version": version,
		"session_uuid": session_uuid,
		"chunk_index": chunk_index,
		"chunks_total": chunks_total,
		"chunk_size": chunk_size,
		"total_bytes": total_bytes,
		"sha256": sha256,
		"saved_at": Time.get_unix_time_from_system(),
	}


## Vérifie qu’un état disque est encore valide (fichier présent, taille, hash).
static func validate_resume_state(state: Dictionary) -> Dictionary:
	## Retourne {ok: bool, reason: String, state: Dictionary}
	if state.is_empty():
		return {"ok": false, "reason": "empty", "state": {}}
	var path := str(state.get("file_path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return {"ok": false, "reason": "file_missing", "state": state}
	var expected_size := int(state.get("total_bytes", 0))
	var actual_size := file_size_bytes(path)
	if expected_size > 0 and actual_size != expected_size:
		return {"ok": false, "reason": "size_mismatch", "state": state}
	var expected_hash := str(state.get("sha256", ""))
	if expected_hash != "":
		var actual_hash := file_sha256(path)
		if actual_hash != expected_hash:
			return {"ok": false, "reason": "hash_mismatch", "state": state}
	var uuid := str(state.get("session_uuid", ""))
	if uuid == "":
		return {"ok": false, "reason": "no_session", "state": state}
	return {"ok": true, "reason": "", "state": state}


# ── Export presets inspection ─────────────────────────────────────────────────

static func list_export_presets() -> Array:
	## [{index, name, platform, runnable, export_path}]
	var out: Array = []
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return out
	var i := 0
	while cfg.has_section("preset.%d" % i):
		var sec := "preset.%d" % i
		out.append({
			"index": i,
			"name": str(cfg.get_value(sec, "name", "Preset %d" % i)),
			"platform": str(cfg.get_value(sec, "platform", "")),
			"runnable": bool(cfg.get_value(sec, "runnable", true)),
			"export_path": str(cfg.get_value(sec, "export_path", "")),
		})
		i += 1
	return out


static func platform_matches_preset(plat_key: String, preset_platform: String) -> bool:
	var p := preset_platform.to_lower()
	match plat_key:
		"web":
			return "web" in p or "html" in p
		"windows":
			return "windows" in p or "pc" in p or "desktop" in p
		"android":
			return "android" in p
		_:
			return true


static func export_template_hint(plat_key: String) -> String:
	## Message d’aide si templates manquants (best-effort, hors API EditorExport officielle).
	match plat_key:
		"web":
			return "Éditeur → Gestionnaire d’export → Web (HTML5) : téléchargez le template."
		"windows":
			return "Éditeur → Gestionnaire d’export → Windows Desktop : téléchargez le template."
		"android":
			return "Éditeur → Gestionnaire d’export → Android + SDK/JDK configurés."
		_:
			return "Vérifiez Projet → Exporter… et les templates d’export."


# ── Export CLI + ZIP (logique pure, sans UI) ──────────────────────────────────

static func export_via_cli(preset_name: String, path: String) -> Dictionary:
	## {ok: bool, exit_code: int, output: String}
	var godot_exe := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray([
		"--headless",
		"--path", project_path,
		"--export-release", preset_name,
		path,
	])
	var output: Array = []
	var exit_code := OS.execute(godot_exe, args, output, true, false)
	var out_text := ""
	for line in output:
		out_text += str(line) + "\n"
	return {
		"ok": exit_code == 0,
		"exit_code": exit_code,
		"output": out_text.strip_edges(),
	}


static func zip_export(src_path: String, platform: String, version: String) -> String:
	var zip_path := OS.get_cache_dir().path_join(
		"thiossane_%s_%s.zip" % [platform, version.replace(".", "_")]
	)
	if platform == "android" and src_path.ends_with(".apk") and FileAccess.file_exists(src_path):
		return src_path

	var packer := ZIPPacker.new()
	var err := packer.open(zip_path, ZIPPacker.APPEND_CREATE)
	if err != OK:
		return ""

	# Web : zipper tout le dossier parent (index.html + .js + .wasm + .pck + …)
	if platform == "web":
		var folder := src_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(folder):
			packer.close()
			return ""
		_add_folder_to_zip(packer, folder, "")
	elif DirAccess.dir_exists_absolute(src_path):
		_add_folder_to_zip(packer, src_path, "")
	elif FileAccess.file_exists(src_path):
		var fname := src_path.get_file()
		packer.start_file(fname)
		var f := FileAccess.open(src_path, FileAccess.READ)
		if f:
			zip_write_stream(packer, f)
			f.close()
		packer.close_file()
		var pck := src_path.get_basename() + ".pck"
		if FileAccess.file_exists(pck):
			packer.start_file(pck.get_file())
			var f2 := FileAccess.open(pck, FileAccess.READ)
			if f2:
				zip_write_stream(packer, f2)
				f2.close()
			packer.close_file()
	else:
		packer.close()
		return ""

	packer.close()
	if not FileAccess.file_exists(zip_path):
		return ""
	return zip_path


static func zip_write_stream(packer: ZIPPacker, f: FileAccess) -> void:
	while f.get_position() < f.get_length():
		packer.write_file(f.get_buffer(4 * 1024 * 1024))


static func _add_folder_to_zip(packer: ZIPPacker, folder: String, prefix: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = dir.get_next()
			continue
		var full := folder.path_join(fname)
		var entry := (prefix + "/" + fname) if prefix != "" else fname
		if dir.current_is_dir():
			_add_folder_to_zip(packer, full, entry)
		else:
			packer.start_file(entry)
			var f := FileAccess.open(full, FileAccess.READ)
			if f:
				zip_write_stream(packer, f)
				f.close()
			packer.close_file()
		fname = dir.get_next()
	dir.list_dir_end()


static func export_output_path(platform: String) -> String:
	var tmp_dir := OS.get_cache_dir().path_join("thiossane_export_%s" % platform)
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	match platform:
		"web":
			# Godot attend un fichier .html (génère .js / .wasm / .pck à côté)
			return tmp_dir.path_join("index.html")
		"windows":
			return tmp_dir.path_join("game.exe")
		"android":
			return tmp_dir.path_join("game.apk")
		_:
			return tmp_dir.path_join("build")


static func export_exists(path: String, platform: String) -> bool:
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return true
	if platform == "windows":
		var pck_alt := path.get_basename() + ".pck"
		return FileAccess.file_exists(pck_alt)
	if platform == "web":
		# index.html + fichiers compagnons dans le même dossier
		var parent := path.get_base_dir()
		return FileAccess.file_exists(parent.path_join("index.html")) \
			or DirAccess.dir_exists_absolute(parent)
	return false
