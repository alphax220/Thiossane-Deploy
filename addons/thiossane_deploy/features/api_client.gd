class_name ThiossaneApiClient
extends RefCounted
## HTTP client partagé — Thiossane Deploy
## Copyright (c) 2026 Teranga Game Studio. Tous droits réservés.
##
## Encapsule construction d’URL, headers auth, messages d’erreur réseau/API.
## Le dock garde les HTTPRequest nodes (EditorPlugin tree) et les callbacks.

const DEFAULT_API := "https://api.thiossane.store/api"


static func normalize_base(raw: String) -> String:
	var b := raw.strip_edges()
	if b == "":
		b = DEFAULT_API
	while b.ends_with("/"):
		b = b.substr(0, b.length() - 1)
	return b


static func auth_headers(access_token: String, include_bearer: bool = true) -> PackedStringArray:
	var h := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Connection: close",
	])
	if include_bearer and access_token != "":
		h.append("Authorization: Bearer " + access_token)
		h.append("X-Access-Token: " + access_token)
	return h


static func upload_chunk_headers(access_token: String, chunk_index: int) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/octet-stream",
		"Accept: application/json",
		"Connection: close",
		"Upload-Chunk-Index: %d" % chunk_index,
		"Authorization: Bearer " + access_token,
		"X-Access-Token: " + access_token,
	])


static func http_result_name(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS:
			return "SUCCESS"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "CHUNKED_BODY_SIZE_MISMATCH"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "CANT_RESOLVE"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "CONNECTION_ERROR"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS_HANDSHAKE_ERROR"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "NO_RESPONSE"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "BODY_SIZE_LIMIT_EXCEEDED"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "BODY_DECOMPRESS_FAILED"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "REQUEST_FAILED"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "DOWNLOAD_FILE_CANT_OPEN"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "DOWNLOAD_FILE_WRITE_ERROR"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "REDIRECT_LIMIT_REACHED"
		HTTPRequest.RESULT_TIMEOUT:
			return "TIMEOUT"
		_:
			return "UNKNOWN(%d)" % result


static func human_network_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Impossible de joindre le serveur (connexion refusée). Vérifiez l’URL API et votre réseau."
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Nom d’hôte introuvable (DNS). Vérifiez l’URL API."
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connexion interrompue. Réessayez dans un instant."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Erreur TLS/SSL. Vérifiez le certificat HTTPS de l’API."
		HTTPRequest.RESULT_TIMEOUT:
			return "Délai dépassé. Le serveur ne répond pas assez vite — réessayez."
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Aucune réponse du serveur."
		_:
			return "Erreur réseau (%s). Réessayez ou vérifiez l’API." % http_result_name(result)


static func api_error_message(data: Variant, code: int) -> String:
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		for k in ["message", "error", "detail", "msg"]:
			if d.has(k) and str(d[k]).strip_edges() != "":
				return str(d[k])
		if d.has("errors"):
			var errs = d["errors"]
			if typeof(errs) == TYPE_ARRAY and errs.size() > 0:
				return str(errs[0])
			if typeof(errs) == TYPE_DICTIONARY:
				for ek in errs.keys():
					return "%s: %s" % [str(ek), str(errs[ek])]
	elif typeof(data) == TYPE_STRING and str(data).strip_edges() != "":
		return str(data)
	if code == 401:
		return "Non autorisé (401) — reconnectez-vous."
	if code == 403:
		return "Accès refusé (403) — rôle développeur requis ?"
	if code == 404:
		return "Ressource introuvable (404)."
	if code == 413:
		return "Fichier trop volumineux (413)."
	if code == 422:
		return "Données invalides (422)."
	if code >= 500:
		return "Erreur serveur (%d). Réessayez plus tard." % code
	return "Erreur HTTP %d" % code


static func parse_json_body(body: PackedByteArray) -> Variant:
	var text := body.get_string_from_utf8()
	if text.strip_edges() == "":
		return null
	var json := JSON.new()
	if json.parse(text) == OK:
		return json.get_data()
	return null
