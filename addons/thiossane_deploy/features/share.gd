class_name ThiossaneShareApi
extends RefCounted
## Share-links & Ambassadeurs — helpers API (chemins + corps JSON)
## Copyright (c) 2026 Teranga Game Studio. Tous droits réservés.
##
## Ne fait pas d'HTTP : le dock garde les HTTPRequest.
## Utilisation typique :
##   var path := ThiossaneShareApi.share_link_path(game_id)
##   var body := ThiossaneShareApi.share_link_body(label, campaign, channel, force_new)

# ── Share links (génériques / campagnes) ─────────────────────────────────────

static func share_link_path(game_id: int) -> String:
	return "/developer/games/%d/share-link" % game_id


static func share_stats_path() -> String:
	return "/developer/share-stats"


static func share_link_body(
		label: String = "",
		campaign_name: String = "",
		channel: String = "",
		force_new: bool = false,
		notes: String = ""
	) -> Dictionary:
	var body: Dictionary = {}
	if label.strip_edges() != "":
		body["label"] = label.strip_edges()
	if campaign_name.strip_edges() != "":
		body["campaign_name"] = campaign_name.strip_edges()
	if channel.strip_edges() != "":
		body["channel"] = channel.strip_edges().to_lower()
	if notes.strip_edges() != "":
		body["notes"] = notes.strip_edges()
	if force_new:
		body["force_new"] = true
	return body


# ── Ambassadeurs (liens ciblés par email / joueur) ────────────────────────────

static func ambassador_create_path(game_id: int) -> String:
	return "/developer/games/%d/ambassador-links" % game_id


static func ambassador_list_path(game_id: int = 0) -> String:
	if game_id > 0:
		return "/developer/ambassador-links?game_id=%d" % game_id
	return "/developer/ambassador-links"


static func ambassador_stats_path() -> String:
	return "/developer/ambassador-stats"


static func ambassador_revoke_path(link_id: int) -> String:
	return "/developer/ambassador-links/%d/revoke" % link_id


static func ambassador_click_path(token: String) -> String:
	## Public — pas d'auth
	return "/ambassador/%s/click" % token.strip_edges()


static func ambassador_create_body(
		email: String,
		label: String = "",
		notes: String = "",
		send_invite: bool = false
	) -> Dictionary:
	var body: Dictionary = {
		"email": email.strip_edges().to_lower(),
	}
	if label.strip_edges() != "":
		body["label"] = label.strip_edges()
	if notes.strip_edges() != "":
		body["notes"] = notes.strip_edges()
	if send_invite:
		body["send_invite"] = true
	return body


static func full_store_url(store_base: String, api_path: String) -> String:
	## api_path ex: "game.html?id=12&amb=TOKEN" ou "game.html?id=12&ref=TOKEN"
	var b := store_base.strip_edges()
	if b == "":
		b = "https://www.thiossane.store/"
	if not b.ends_with("/"):
		b += "/"
	var p := api_path.strip_edges()
	if p.begins_with("/"):
		p = p.substr(1)
	return b + p


static func summarize_ambassador_stats(data: Dictionary) -> String:
	var links := int(data.get("total_links", 0))
	var clicks := int(data.get("total_clicks", 0))
	var uniq := int(data.get("total_unique_clicks", 0))
	var conv := int(data.get("total_conversions", 0))
	return "Liens: %d · Clics: %d · Uniques: %d · Conversions: %d" % [links, clicks, uniq, conv]


static func is_valid_email(email: String) -> bool:
	var e := email.strip_edges()
	if e.length() < 5 or not e.contains("@"):
		return false
	var parts := e.split("@")
	if parts.size() != 2:
		return false
	if parts[0].is_empty() or parts[1].is_empty() or not parts[1].contains("."):
		return false
	return true
